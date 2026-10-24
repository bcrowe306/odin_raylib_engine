package engine

import "core:encoding/json"
import "core:math"
import "core:path/filepath"
import "core:slice"
import "core:strconv"
import "core:strings"
import vmem "core:mem/virtual"
import rl "vendor:raylib"

// ============================================================================
// Spine import (docs/skeletal_animation.md): a skeleton .json export (Spine
// 3.8 - 4.2) and its .atlas (libGDX text format: pages, then regions with
// bounds / xy + size, rotate). Spine is y-up with counter-clockwise angles;
// everything is flipped into the engine's y-down, clockwise space on load.
//
// Supported: bones (inherit modes), slots (colour, setup attachment,
// additive blend), skins (regions, meshes - weighted or not - and linked
// meshes), IK (1 and 2 bones), animations (rotate, translate, scale,
// shear; attachment and colour; draw order; events) with linear, stepped
// and Bezier curves (a key's curve is shared by its channels: the first
// channel's is used). Not supported: path / transform / physics
// constraints, clipping, deform (FFD) timelines, sequences.
// ============================================================================

Skel_AtlasRegion :: struct {
	page:    int,
	bounds:  rl.Rectangle,
	rotated: bool,
}

Skel_Atlas :: struct {
	pages:   [dynamic]string, // file names (relative to the atlas)
	regions: map[string]Skel_AtlasRegion,
}

// Skel_ParseAtlas reads a libGDX / Spine .atlas (3.x and 4.x syntax).
Skel_ParseAtlas :: proc(text: string, allocator := context.allocator) -> Skel_Atlas {
	atlas: Skel_Atlas
	atlas.pages = make([dynamic]string, allocator)
	atlas.regions = make(map[string]Skel_AtlasRegion, 32, allocator)
	page := -1
	region := ""
	expectPage := true
	nums :: proc(s: string) -> [4]f32 {
		out: [4]f32
		i := 0
		for part in strings.split(s, ",", context.temp_allocator) {
			if i >= 4 do break
			out[i], _ = strconv.parse_f32(strings.trim_space(part))
			i += 1
		}
		return out
	}
	for raw in strings.split_lines(text, context.temp_allocator) {
		line := strings.trim_space(raw)
		if line == "" {
			expectPage = true
			region = ""
			continue
		}
		colon := strings.index_byte(line, ':')
		if colon < 0 {
			if expectPage {
				append(&atlas.pages, strings.clone(line, allocator))
				page = len(atlas.pages) - 1
				expectPage = false
			} else {
				region = strings.clone(line, allocator)
				atlas.regions[region] = {page = page}
			}
			continue
		}
		expectPage = false
		if region == "" do continue // (page settings: size, filter, pma...)
		key := strings.trim_space(line[:colon])
		val := strings.trim_space(line[colon + 1:])
		r := atlas.regions[region]
		switch key {
		case "bounds":
			v := nums(val)
			r.bounds = {v[0], v[1], v[2], v[3]}
		case "xy":
			v := nums(val)
			r.bounds.x, r.bounds.y = v[0], v[1]
		case "size":
			v := nums(val)
			r.bounds.width, r.bounds.height = v[0], v[1]
		case "rotate":
			r.rotated = val == "true" || val == "90"
		}
		atlas.regions[region] = r
	}
	// Rotated regions: bounds / size give the unrotated size; the page holds it turned.
	for name, &r in atlas.regions {
		_ = name
		if r.rotated do r.bounds.width, r.bounds.height = r.bounds.height, r.bounds.width
	}
	return atlas
}

@(private = "file")
jnum :: proc(o: json.Object, key: string, def: f32) -> f32 {
	#partial switch v in o[key] {
	case json.Float: return f32(v)
	case json.Integer: return f32(v)
	}
	return def
}

@(private = "file")
jstr :: proc(o: json.Object, key: string, def := "") -> string {
	if s, ok := o[key].(json.String); ok do return string(s)
	return def
}

@(private = "file")
jbool :: proc(o: json.Object, key: string, def: bool) -> bool {
	if b, ok := o[key].(json.Boolean); ok do return bool(b)
	return def
}

@(private = "file")
hex_color :: proc(s: string) -> [4]f32 {
	c := [4]f32{1, 1, 1, 1}
	for i in 0 ..< min(len(s) / 2, 4) {
		v, _ := strconv.parse_int(s[i * 2:i * 2 + 2], 16)
		c[i] = f32(v) / 255
	}
	return c
}

// Skeleton_LoadSpine builds skeleton data from a Spine JSON export and its
// atlas; `loadTexture` gets a page file name (relative to the atlas).
Skeleton_LoadSpine :: proc(jsonText, atlasText: string, loadTexture: proc(page: string, data: rawptr) -> ^Texture, texData: rawptr) -> (^Skeleton_Data, bool) {
	root, err := json.parse_string(jsonText, allocator = context.temp_allocator)
	if err != nil do return nil, false
	obj, isObj := root.(json.Object)
	if !isObj do return nil, false
	d := new(Skeleton_Data)
	if vmem.arena_init_growing(&d.arena, 64 * 1024) != nil {
		free(d)
		return nil, false
	}
	a := Skeleton_DataAllocator(d)
	d.textures = make([dynamic]^Texture)

	version := "4.0"
	if sk, ok := obj["skeleton"].(json.Object); ok do version = jstr(sk, "spine", "4.0")
	v4 := !strings.has_prefix(version, "3.")

	// Bones (parents come first in Spine exports).
	bonesJ, _ := obj["bones"].(json.Array)
	bones := make([]Skel_Bone, len(bonesJ), a)
	for bv, i in bonesJ {
		b, _ := bv.(json.Object)
		parent := -1
		if pn := jstr(b, "parent"); pn != "" {
			for j in 0 ..< i do if bones[j].name == pn {parent = j; break}
		}
		inherit := jstr(b, "inherit", jstr(b, "transform", "normal"))
		bones[i] = {
			name = strings.clone(jstr(b, "name"), a), parent = parent,
			x = jnum(b, "x", 0), y = -jnum(b, "y", 0), rotation = -jnum(b, "rotation", 0),
			scaleX = jnum(b, "scaleX", 1), scaleY = jnum(b, "scaleY", 1),
			shearX = -jnum(b, "shearX", 0), shearY = -jnum(b, "shearY", 0),
			length = jnum(b, "length", 0),
			inheritRotation = inherit != "onlyTranslation" && inherit != "noRotationOrReflection",
			inheritScale = inherit != "onlyTranslation" && inherit != "noScale" && inherit != "noScaleOrReflection",
		}
	}
	d.bones = bones
	boneIdx :: proc(d: ^Skeleton_Data, name: string) -> int {return Skeleton_BoneIndex(d, name)}

	// Slots.
	slotsJ, _ := obj["slots"].(json.Array)
	slots := make([]Skel_Slot, len(slotsJ), a)
	for sv, i in slotsJ {
		s, _ := sv.(json.Object)
		slots[i] = {
			name = strings.clone(jstr(s, "name"), a), bone = max(boneIdx(d, jstr(s, "bone")), 0),
			color = hex_color(jstr(s, "color", "ffffffff")),
			attachment = strings.clone(jstr(s, "attachment"), a),
			additive = jstr(s, "blend") == "additive",
		}
	}
	d.slots = slots

	// Atlas and its pages.
	atlas := Skel_ParseAtlas(atlasText, context.temp_allocator)
	pages := make([]^Texture, len(atlas.pages), context.temp_allocator)
	for p, i in atlas.pages {
		pages[i] = loadTexture(p, texData) if loadTexture != nil else nil
		if pages[i] != nil do append(&d.textures, pages[i])
	}
	region_of :: proc(atlas: ^Skel_Atlas, pages: []^Texture, name: string) -> (^Texture, rl.Rectangle, bool, bool) {
		r, ok := atlas.regions[name]
		if !ok || r.page < 0 || r.page >= len(pages) do return nil, {}, false, false
		return pages[r.page], r.bounds, r.rotated, true
	}

	// Skins (4.x: an array; 3.x: an object of skins).
	skins := make([dynamic]Skel_Skin, a)
	Pending_Linked :: struct {skin, slot: int, name, parent, path: string}
	linked := make([dynamic]Pending_Linked, context.temp_allocator)
	add_skin :: proc(d: ^Skeleton_Data, skins: ^[dynamic]Skel_Skin, name: string, atts: json.Object, atlas: ^Skel_Atlas, pages: []^Texture, linked: ^[dynamic]Pending_Linked) {
		a := Skeleton_DataAllocator(d)
		skin := Skel_Skin{name = strings.clone(name, a), attachments = make(map[string]Skel_Attachment, 16, a)}
		for slotName, sv in atts {
			si := Skeleton_SlotIndex(d, slotName)
			if si < 0 do continue
			so, _ := sv.(json.Object)
			for attName, av in so {
				ao, _ := av.(json.Object)
				kind := jstr(ao, "type", "region")
				path := jstr(ao, "path", jstr(ao, "name", attName))
				key := skel_attach_key(si, attName, a)
				switch kind {
				case "region":
					tex, uv, rot, ok := region_of(atlas, pages, path)
					if !ok do continue
					skin.attachments[key] = Skel_Region{
						texture = tex, uv = uv, rotated = rot,
						x = jnum(ao, "x", 0), y = -jnum(ao, "y", 0), rotation = -jnum(ao, "rotation", 0),
						scaleX = jnum(ao, "scaleX", 1), scaleY = jnum(ao, "scaleY", 1),
						width = jnum(ao, "width", uv.width), height = jnum(ao, "height", uv.height),
					}
				case "mesh":
					tex, uv, rot, ok := region_of(atlas, pages, path)
					if !ok do continue
					skin.attachments[key] = spine_mesh(d, ao, tex, uv, rot)
				case "linkedmesh":
					append(linked, Pending_Linked{len(skins), si, strings.clone(attName, context.temp_allocator), strings.clone(jstr(ao, "parent"), context.temp_allocator), strings.clone(path, context.temp_allocator)})
				}
			}
		}
		append(skins, skin)
	}
	switch sk in obj["skins"] {
	case json.Array:
		for skv in sk {
			so, _ := skv.(json.Object)
			atts, _ := so["attachments"].(json.Object)
			add_skin(d, &skins, jstr(so, "name", "default"), atts, &atlas, pages, &linked)
		}
	case json.Object:
		// 3.x: "default" first.
		if def, ok := sk["default"].(json.Object); ok do add_skin(d, &skins, "default", def, &atlas, pages, &linked)
		for name, sv in sk {
			if name == "default" do continue
			atts, _ := sv.(json.Object)
			add_skin(d, &skins, name, atts, &atlas, pages, &linked)
		}
	case json.Null, json.Integer, json.Float, json.Boolean, json.String:
	}
	// Linked meshes: the parent mesh's geometry with their own region.
	for l in linked {
		parent, found := Skeleton_Attachment_InSkins(skins[:], l.slot, l.parent)
		m, isMesh := parent.(Skel_Mesh)
		if !found || !isMesh do continue
		if tex, uv, rot, ok := region_of(&atlas, pages, l.path); ok {
			m.texture, m.uv, m.rotated = tex, uv, rot
		}
		skins[l.skin].attachments[skel_attach_key(l.slot, l.name, a)] = m
	}
	d.skins = skins[:]

	// IK.
	if iks, ok := obj["ik"].(json.Array); ok {
		ik := make([]Skel_IK, len(iks), a)
		for iv, i in iks {
			io, _ := iv.(json.Object)
			bl, _ := io["bones"].(json.Array)
			bones := make([]int, len(bl), a)
			for bn, j in bl do bones[j] = Skeleton_BoneIndex(d, string(bn.(json.String) or_else ""))
			ik[i] = {
				name = strings.clone(jstr(io, "name"), a), bones = bones, target = Skeleton_BoneIndex(d, jstr(io, "target")),
				mix = jnum(io, "mix", 1),
				// (y flipped: Spine's positive bend is the engine's negative one)
				bendPositive = !jbool(io, "bendPositive", true),
			}
		}
		d.ik = ik
	}

	// Events (defaults for the animations' event keys).
	eventDefs, _ := obj["events"].(json.Object)

	// Animations.
	if anims, ok := obj["animations"].(json.Object); ok {
		list := make([dynamic]Skel_Animation, a)
		for name, av in anims {
			ao, _ := av.(json.Object)
			append(&list, spine_animation(d, name, ao, eventDefs, v4))
		}
		slice.sort_by(list[:], proc(x, y: Skel_Animation) -> bool {return x.name < y.name})
		d.animations = list[:]
	}
	return d, true
}

// Skeleton_Attachment_InSkins: an attachment of a slot in any skin.
Skeleton_Attachment_InSkins :: proc(skins: []Skel_Skin, slot: int, name: string) -> (Skel_Attachment, bool) {
	key := skel_attach_key(slot, name)
	for s in skins do if a, ok := s.attachments[key]; ok do return a, true
	return nil, false
}

@(private = "file")
spine_mesh :: proc(d: ^Skeleton_Data, ao: json.Object, tex: ^Texture, uv: rl.Rectangle, rot: bool) -> Skel_Mesh {
	a := Skeleton_DataAllocator(d)
	uvsJ, _ := ao["uvs"].(json.Array)
	trisJ, _ := ao["triangles"].(json.Array)
	vertsJ, _ := ao["vertices"].(json.Array)
	f :: proc(v: json.Value) -> f32 {
		#partial switch x in v {
		case json.Float: return f32(x)
		case json.Integer: return f32(x)
		}
		return 0
	}
	n := len(uvsJ) / 2
	m := Skel_Mesh{texture = tex, uv = uv, rotated = rot}
	m.uvs = make([][2]f32, n, a)
	for i in 0 ..< n do m.uvs[i] = {f(uvsJ[i * 2]), f(uvsJ[i * 2 + 1])}
	m.triangles = make([]u16, len(trisJ), a)
	for t, i in trisJ do m.triangles[i] = u16(f(t))
	if len(vertsJ) == n * 2 {
		m.vertices = make([][2]f32, n, a)
		for i in 0 ..< n do m.vertices[i] = {f(vertsJ[i * 2]), -f(vertsJ[i * 2 + 1])}
	} else {
		// Weighted: per vertex: count, then (bone, x, y, weight) * count.
		m.bonesOf = make([][]int, n, a)
		m.offsets = make([][][2]f32, n, a)
		m.weights = make([][]f32, n, a)
		k := 0
		for vi in 0 ..< n {
			if k >= len(vertsJ) do break
			count := int(f(vertsJ[k]))
			k += 1
			m.bonesOf[vi] = make([]int, count, a)
			m.offsets[vi] = make([][2]f32, count, a)
			m.weights[vi] = make([]f32, count, a)
			for j in 0 ..< count {
				if k + 3 >= len(vertsJ) + 1 do break
				m.bonesOf[vi][j] = clamp(int(f(vertsJ[k])), 0, len(d.bones) - 1)
				m.offsets[vi][j] = {f(vertsJ[k + 1]), -f(vertsJ[k + 2])}
				m.weights[vi][j] = f(vertsJ[k + 3])
				k += 4
			}
		}
	}
	return m
}

// spine_curve: a key's curve to the next (4.x: Bezier control points in
// time / value units, normalized here; 3.x: already normalized).
@(private = "file")
spine_curve :: proc(k: json.Object, t0, t1, v0, v1: f32, v4: bool) -> Skel_Curve {
	switch c in k["curve"] {
	case json.String:
		if c == "stepped" do return {kind = .Stepped}
	case json.Array:
		if len(c) < 4 do return {}
		f :: proc(v: json.Value) -> f32 {
			#partial switch x in v {
			case json.Float: return f32(x)
			case json.Integer: return f32(x)
			}
			return 0
		}
		cx1, cy1, cx2, cy2 := f(c[0]), f(c[1]), f(c[2]), f(c[3])
		if !v4 do return {kind = .Bezier, c = {cx1, cy1, cx2, cy2}}
		dt := t1 - t0
		dv := v1 - v0
		if dt <= 0 do return {}
		if math.abs(dv) < 1e-6 do return {kind = .Bezier, c = {(cx1 - t0) / dt, 0, (cx2 - t0) / dt, 1}} // (flat: the timing still shapes nothing)
		return {kind = .Bezier, c = {(cx1 - t0) / dt, (cy1 - v0) / dv, (cx2 - t0) / dt, (cy2 - v0) / dv}}
	case json.Float:
		// 3.x: a single number means a Bezier's first control x (rare).
	case json.Null, json.Integer, json.Boolean, json.Object:
	}
	return {}
}

@(private = "file")
spine_keys :: proc(d: ^Skeleton_Data, arr: json.Array, kind: Skel_Timeline_Kind, v4: bool) -> []Skel_Key {
	a := Skeleton_DataAllocator(d)
	keys := make([]Skel_Key, len(arr), a)
	def: f32 = 1 if kind == .Scale else 0
	for kv, i in arr {
		k, _ := kv.(json.Object)
		keys[i].time = jnum(k, "time", 0)
		switch kind {
		case .Rotate:
			keys[i].v[0] = -jnum(k, "value", jnum(k, "angle", 0))
		case .Translate:
			keys[i].v = {jnum(k, "x", 0), -jnum(k, "y", 0), 0, 0}
		case .Scale:
			keys[i].v = {jnum(k, "x", def), jnum(k, "y", def), 0, 0}
		case .Shear:
			keys[i].v = {-jnum(k, "x", 0), -jnum(k, "y", 0), 0, 0}
		case .Attachment:
			keys[i].name = strings.clone(jstr(k, "name"), a)
		case .Color:
			keys[i].v = hex_color(jstr(k, "color", jstr(k, "rgba", "ffffffff")))
		}
	}
	// Curves (need the next key).
	for kv, i in arr {
		if i + 1 >= len(arr) do break
		k, _ := kv.(json.Object)
		// (4.x Bezier values: the first channel, in Spine's units - not flipped)
		raw0, raw1: f32
		next, _ := arr[i + 1].(json.Object)
		switch kind {
		case .Rotate: raw0, raw1 = jnum(k, "value", jnum(k, "angle", 0)), jnum(next, "value", jnum(next, "angle", 0))
		case .Translate, .Shear: raw0, raw1 = jnum(k, "x", 0), jnum(next, "x", 0)
		case .Scale: raw0, raw1 = jnum(k, "x", 1), jnum(next, "x", 1)
		case .Attachment, .Color: raw0, raw1 = 0, 1
		}
		keys[i].curve = spine_curve(k, keys[i].time, keys[i + 1].time, raw0, raw1, v4)
	}
	return keys
}

@(private = "file")
spine_animation :: proc(d: ^Skeleton_Data, name: string, ao: json.Object, eventDefs: json.Object, v4: bool) -> Skel_Animation {
	a := Skeleton_DataAllocator(d)
	anim := Skel_Animation{name = strings.clone(name, a)}
	tls := make([dynamic]Skel_Timeline, a)
	if bones, ok := ao["bones"].(json.Object); ok {
		for boneName, bv in bones {
			bi := Skeleton_BoneIndex(d, boneName)
			if bi < 0 do continue
			bo, _ := bv.(json.Object)
			for tname, tv in bo {
				arr, _ := tv.(json.Array)
				kind: Skel_Timeline_Kind
				switch tname {
				case "rotate": kind = .Rotate
				case "translate": kind = .Translate
				case "scale": kind = .Scale
				case "shear": kind = .Shear
				case: continue
				}
				append(&tls, Skel_Timeline{kind = kind, target = bi, keys = spine_keys(d, arr, kind, v4)})
			}
		}
	}
	if slots, ok := ao["slots"].(json.Object); ok {
		for slotName, sv in slots {
			si := Skeleton_SlotIndex(d, slotName)
			if si < 0 do continue
			so, _ := sv.(json.Object)
			for tname, tv in so {
				arr, _ := tv.(json.Array)
				switch tname {
				case "attachment": append(&tls, Skel_Timeline{kind = .Attachment, target = si, keys = spine_keys(d, arr, .Attachment, v4)})
				case "rgba", "color": append(&tls, Skel_Timeline{kind = .Color, target = si, keys = spine_keys(d, arr, .Color, v4)})
				}
			}
		}
	}
	anim.timelines = tls[:]
	if dor, ok := ao["drawOrder"].(json.Array); ok {
		keys := make([]Skel_Key, len(dor), a)
		n := len(d.slots)
		for kv, i in dor {
			k, _ := kv.(json.Object)
			keys[i].time = jnum(k, "time", 0)
			offs, has := k["offsets"].(json.Array)
			if !has do continue
			// Spine's draw order: slots moved by offsets, the rest keep their order.
			order := make([]int, n, a)
			for &o in order do o = -1
			unchanged := make([dynamic]int, context.temp_allocator)
			orig := 0
			for ov in offs {
				oo, _ := ov.(json.Object)
				si := Skeleton_SlotIndex(d, jstr(oo, "slot"))
				if si < 0 do continue
				for orig != si {append(&unchanged, orig); orig += 1}
				pos := orig + int(jnum(oo, "offset", 0))
				if pos >= 0 && pos < n do order[pos] = orig
				orig += 1
			}
			for orig < n {append(&unchanged, orig); orig += 1}
			ui := len(unchanged) - 1
			for j := n - 1; j >= 0; j -= 1 {
				if order[j] == -1 && ui >= 0 {
					order[j] = unchanged[ui]
					ui -= 1
				}
			}
			keys[i].order = order
		}
		anim.drawOrder = keys
	}
	if evs, ok := ao["events"].(json.Array); ok {
		keys := make([]Skel_Key, len(evs), a)
		for ev, i in evs {
			e, _ := ev.(json.Object)
			name := jstr(e, "name")
			def, _ := eventDefs[name].(json.Object)
			keys[i] = {
				time = jnum(e, "time", 0), name = strings.clone(name, a),
				ivalue = i32(jnum(e, "int", jnum(def, "int", 0))), fvalue = jnum(e, "float", jnum(def, "float", 0)),
				svalue = strings.clone(jstr(e, "string", jstr(def, "string")), a),
			}
		}
		anim.events = keys
	}
	// Duration: the last key of any timeline.
	for tl in anim.timelines do for k in tl.keys do anim.duration = max(anim.duration, k.time)
	for k in anim.drawOrder do anim.duration = max(anim.duration, k.time)
	for k in anim.events do anim.duration = max(anim.duration, k.time)
	return anim
}

// Skeleton_AtlasPathFor: the atlas next to a Spine JSON ("hero.json" ->
// "hero.atlas", also "hero.atlas.txt").
Skeleton_AtlasPathFor :: proc(jsonPath: string, allocator := context.temp_allocator) -> []string {
	base := strings.trim_suffix(jsonPath, filepath.ext(jsonPath))
	out := make([]string, 2, allocator)
	out[0] = strings.concatenate({base, ".atlas"}, allocator)
	out[1] = strings.concatenate({base, ".atlas.txt"}, allocator)
	return out
}
