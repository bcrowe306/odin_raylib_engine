package engine

import "core:encoding/json"
import "core:math"
import "core:strings"
import vmem "core:mem/virtual"
import rl "vendor:raylib"

// ============================================================================
// DragonBones import (docs/skeletal_animation.md): a _ske.json export
// (DragonBones 5.x) and its _tex.json texture atlas. DragonBones is y-down
// like the engine; transforms use Flash's skew convention (skX turns the y
// axis, skY the x axis - equal for a plain rotation). Times are in frames
// (the armature's frameRate).
//
// Supported: the first armature (or one by name), bones (inherit flags),
// slots (display index, colour, additive), the default skin's displays
// (images - trimmed sub-textures included - and meshes, weighted or not),
// IK (chain 0 / 1), animations: bone translate / rotate / scale frames
// (relative to the setup pose) with stepped, linear and curve tweens, slot
// display and colour frames, events. Not supported: zOrder frames,
// armature displays, FFD, inverse kinematics weights per frame.
// ============================================================================

@(private = "file")
dnum :: proc(o: json.Object, key: string, def: f32) -> f32 {
	#partial switch v in o[key] {
	case json.Float: return f32(v)
	case json.Integer: return f32(v)
	}
	return def
}

@(private = "file")
dstr :: proc(o: json.Object, key: string, def := "") -> string {
	if s, ok := o[key].(json.String); ok do return string(s)
	return def
}

@(private = "file")
dbool :: proc(o: json.Object, key: string, def: bool) -> bool {
	if b, ok := o[key].(json.Boolean); ok do return bool(b)
	return def
}

@(private = "file")
DB_Region :: struct {
	bounds:  rl.Rectangle,
	rotated: bool,
	frame:   [4]f32, // frameX, frameY, frameWidth, frameHeight (trimmed images; 0 = none)
}

// Skeleton_LoadDragonBones builds skeleton data from a _ske.json and its
// _tex.json; `loadTexture` gets the atlas image (relative to the tex json).
Skeleton_LoadDragonBones :: proc(skeText, texText: string, armature: string, loadTexture: proc(page: string, data: rawptr) -> ^Texture, texData: rawptr) -> (^Skeleton_Data, bool) {
	root, err := json.parse_string(skeText, allocator = context.temp_allocator)
	if err != nil do return nil, false
	top, _ := root.(json.Object)
	arms, _ := top["armature"].(json.Array)
	arm: json.Object
	for av in arms {
		ao, _ := av.(json.Object)
		if armature == "" || dstr(ao, "name") == armature {arm = ao; break}
	}
	if arm == nil do return nil, false

	d := new(Skeleton_Data)
	if vmem.arena_init_growing(&d.arena, 64 * 1024) != nil {
		free(d)
		return nil, false
	}
	a := Skeleton_DataAllocator(d)
	d.textures = make([dynamic]^Texture)
	d.name = strings.clone(dstr(arm, "name"), a)
	fps := dnum(arm, "frameRate", dnum(top, "frameRate", 24))
	d.fps = fps

	// The texture atlas.
	tex: ^Texture
	regions := make(map[string]DB_Region, 32, context.temp_allocator)
	if texRoot, terr := json.parse_string(texText, allocator = context.temp_allocator); terr == nil {
		to, _ := texRoot.(json.Object)
		if loadTexture != nil do tex = loadTexture(dstr(to, "imagePath"), texData)
		if tex != nil do append(&d.textures, tex)
		subs, _ := to["SubTexture"].(json.Array)
		for sv in subs {
			s, _ := sv.(json.Object)
			r := DB_Region{bounds = {dnum(s, "x", 0), dnum(s, "y", 0), dnum(s, "width", 0), dnum(s, "height", 0)}, rotated = dbool(s, "rotated", false)}
			if _, has := s["frameWidth"]; has do r.frame = {dnum(s, "frameX", 0), dnum(s, "frameY", 0), dnum(s, "frameWidth", 0), dnum(s, "frameHeight", 0)}
			if r.rotated do r.bounds.width, r.bounds.height = r.bounds.height, r.bounds.width
			regions[strings.clone(dstr(s, "name"), context.temp_allocator)] = r
		}
	}

	transform :: proc(o: json.Object) -> (x, y, rot, sx, sy, shear: f32) {
		t, _ := o["transform"].(json.Object)
		skX, skY := dnum(t, "skX", 0), dnum(t, "skY", 0)
		return dnum(t, "x", 0), dnum(t, "y", 0), skY, dnum(t, "scX", 1), dnum(t, "scY", 1), skX - skY
	}

	// Bones (parents before children in exports).
	bonesJ, _ := arm["bone"].(json.Array)
	bones := make([]Skel_Bone, len(bonesJ), a)
	for bv, i in bonesJ {
		b, _ := bv.(json.Object)
		parent := -1
		if pn := dstr(b, "parent"); pn != "" {
			for j in 0 ..< i do if bones[j].name == pn {parent = j; break}
		}
		x, y, rot, sx, sy, shear := transform(b)
		bones[i] = {
			name = strings.clone(dstr(b, "name"), a), parent = parent, x = x, y = y, rotation = rot,
			scaleX = sx, scaleY = sy, shearY = shear, length = dnum(b, "length", 0),
			inheritRotation = dbool(b, "inheritRotation", true), inheritScale = dbool(b, "inheritScale", true),
		}
	}
	d.bones = bones

	// Slots; their display lists name the attachments (display index -> name).
	slotsJ, _ := arm["slot"].(json.Array)
	slots := make([]Skel_Slot, len(slotsJ), a)
	displayIndex := make([]int, len(slotsJ), context.temp_allocator)
	for sv, i in slotsJ {
		s, _ := sv.(json.Object)
		col := [4]f32{1, 1, 1, 1}
		if c, ok := s["color"].(json.Object); ok do col = {dnum(c, "rM", 100) / 100, dnum(c, "gM", 100) / 100, dnum(c, "bM", 100) / 100, dnum(c, "aM", 100) / 100}
		slots[i] = {
			name = strings.clone(dstr(s, "name"), a), bone = max(Skeleton_BoneIndex(d, dstr(s, "parent")), 0),
			color = col, additive = dstr(s, "blendMode") == "add",
		}
		displayIndex[i] = int(dnum(s, "displayIndex", 0))
	}
	d.slots = slots

	// The skin(s): each slot's displays.
	displays := make([][dynamic]string, len(slots), context.temp_allocator)
	for &dl in displays do dl = make([dynamic]string, context.temp_allocator)
	skinsJ, _ := arm["skin"].(json.Array)
	skins := make([dynamic]Skel_Skin, a)
	for skv in skinsJ {
		sk, _ := skv.(json.Object)
		skin := Skel_Skin{name = strings.clone(dstr(sk, "name", "default"), a), attachments = make(map[string]Skel_Attachment, 16, a)}
		first := len(skins) == 0
		sl, _ := sk["slot"].(json.Array)
		for ssv in sl {
			ss, _ := ssv.(json.Object)
			si := Skeleton_SlotIndex(d, dstr(ss, "name"))
			if si < 0 do continue
			dl, _ := ss["display"].(json.Array)
			for dv in dl {
				disp, _ := dv.(json.Object)
				name := dstr(disp, "name")
				path := dstr(disp, "path", name)
				if first do append(&displays[si], strings.clone(name, context.temp_allocator))
				r, found := regions[path]
				if !found do continue
				key := skel_attach_key(si, name, a)
				switch dstr(disp, "type", "image") {
				case "image":
					x, y, rot, sx, sy, _ := transform(disp)
					// Trimmed sub-textures: the trimmed part's centre within the full image.
					if r.frame[2] > 0 {
						x += (-r.frame[0] + r.bounds.width * 0.5 - r.frame[2] * 0.5) * sx
						y += (-r.frame[1] + r.bounds.height * 0.5 - r.frame[3] * 0.5) * sy
					}
					skin.attachments[key] = Skel_Region{
						texture = tex, uv = r.bounds, rotated = r.rotated, x = x, y = y, rotation = rot,
						scaleX = sx, scaleY = sy, width = r.bounds.width, height = r.bounds.height,
					}
				case "mesh":
					skin.attachments[key] = db_mesh(d, disp, tex, r)
				}
			}
		}
		append(&skins, skin)
	}
	d.skins = skins[:]
	for i in 0 ..< len(slots) {
		di := displayIndex[i]
		if di >= 0 && di < len(displays[i]) do slots[i].attachment = strings.clone(displays[i][di], a)
	}

	// IK: "bone" is the end of the chain; chain 1 adds its parent.
	if iks, ok := arm["ik"].(json.Array); ok {
		ik := make([]Skel_IK, len(iks), a)
		for iv, i in iks {
			io, _ := iv.(json.Object)
			end := Skeleton_BoneIndex(d, dstr(io, "bone"))
			list: []int
			if int(dnum(io, "chain", 0)) >= 1 && end >= 0 && bones[end].parent >= 0 {
				list = make([]int, 2, a)
				list[0], list[1] = bones[end].parent, end
			} else {
				list = make([]int, 1, a)
				list[0] = end
			}
			ik[i] = {name = strings.clone(dstr(io, "name"), a), bones = list, target = Skeleton_BoneIndex(d, dstr(io, "target")), mix = dnum(io, "weight", 1), bendPositive = dbool(io, "bendPositive", true)}
		}
		d.ik = ik
	}

	// Animations.
	if anims, ok := arm["animation"].(json.Array); ok {
		list := make([]Skel_Animation, len(anims), a)
		for av, i in anims {
			ao, _ := av.(json.Object)
			list[i] = db_animation(d, ao, fps, displays)
		}
		d.animations = list
	}
	return d, true
}

// db_curve: a frame's tween to the next ("tweenEasing" absent = stepped,
// 0 = linear, a "curve" = Bezier control points).
@(private = "file")
db_curve :: proc(f: json.Object) -> Skel_Curve {
	if c, ok := f["curve"].(json.Array); ok && len(c) >= 4 {
		g :: proc(v: json.Value) -> f32 {
			#partial switch x in v {
			case json.Float: return f32(x)
			case json.Integer: return f32(x)
			}
			return 0
		}
		return {kind = .Bezier, c = {g(c[0]), g(c[1]), g(c[len(c) - 2]), g(c[len(c) - 1])}}
	}
	#partial switch e in f["tweenEasing"] {
	case json.Null: return {kind = .Stepped}
	case json.Float:
		if e > 0 do return {kind = .Bezier, c = {0, 0, 0.58, 1}} // ease out
		if e < 0 do return {kind = .Bezier, c = {0.42, 0, 1, 1}} // ease in
		return {}
	case json.Integer:
		if e > 0 do return {kind = .Bezier, c = {0, 0, 0.58, 1}}
		if e < 0 do return {kind = .Bezier, c = {0.42, 0, 1, 1}}
		return {}
	}
	if _, has := f["tweenEasing"]; !has do return {kind = .Stepped}
	return {}
}

@(private = "file")
db_frames :: proc(d: ^Skeleton_Data, arr: json.Array, fps: f32, kind: Skel_Timeline_Kind, displays: []string = nil) -> []Skel_Key {
	a := Skeleton_DataAllocator(d)
	keys := make([]Skel_Key, len(arr), a)
	t: f32
	for fv, i in arr {
		f, _ := fv.(json.Object)
		keys[i].time = t / fps
		t += dnum(f, "duration", 1)
		keys[i].curve = db_curve(f)
		switch kind {
		case .Translate: keys[i].v = {dnum(f, "x", 0), dnum(f, "y", 0), 0, 0}
		case .Rotate: keys[i].v[0] = dnum(f, "rotate", 0)
		case .Scale: keys[i].v = {dnum(f, "x", 1), dnum(f, "y", 1), 0, 0}
		case .Shear:
		case .Attachment:
			idx := int(dnum(f, "value", 0))
			keys[i].name = strings.clone(displays[idx], a) if idx >= 0 && idx < len(displays) else ""
			keys[i].curve = {kind = .Stepped}
		case .Color:
			c, _ := f["value"].(json.Object)
			keys[i].v = {dnum(c, "rM", 100) / 100, dnum(c, "gM", 100) / 100, dnum(c, "bM", 100) / 100, dnum(c, "aM", 100) / 100}
		}
	}
	return keys
}

@(private = "file")
db_animation :: proc(d: ^Skeleton_Data, ao: json.Object, fps: f32, displays: [][dynamic]string) -> Skel_Animation {
	a := Skeleton_DataAllocator(d)
	anim := Skel_Animation{name = strings.clone(dstr(ao, "name"), a), duration = dnum(ao, "duration", 0) / fps}
	tls := make([dynamic]Skel_Timeline, a)
	if bones, ok := ao["bone"].(json.Array); ok {
		for bv in bones {
			bo, _ := bv.(json.Object)
			bi := Skeleton_BoneIndex(d, dstr(bo, "name"))
			if bi < 0 do continue
			if f, has := bo["translateFrame"].(json.Array); has do append(&tls, Skel_Timeline{.Translate, bi, db_frames(d, f, fps, .Translate)})
			if f, has := bo["rotateFrame"].(json.Array); has do append(&tls, Skel_Timeline{.Rotate, bi, db_frames(d, f, fps, .Rotate)})
			if f, has := bo["scaleFrame"].(json.Array); has do append(&tls, Skel_Timeline{.Scale, bi, db_frames(d, f, fps, .Scale)})
		}
	}
	if slots, ok := ao["slot"].(json.Array); ok {
		for sv in slots {
			so, _ := sv.(json.Object)
			si := Skeleton_SlotIndex(d, dstr(so, "name"))
			if si < 0 do continue
			if f, has := so["displayFrame"].(json.Array); has do append(&tls, Skel_Timeline{.Attachment, si, db_frames(d, f, fps, .Attachment, displays[si][:])})
			if f, has := so["colorFrame"].(json.Array); has do append(&tls, Skel_Timeline{.Color, si, db_frames(d, f, fps, .Color)})
		}
	}
	anim.timelines = tls[:]
	// Events: "frame": [{duration, events: [{name}] | event: name}].
	if frames, ok := ao["frame"].(json.Array); ok {
		evs := make([dynamic]Skel_Key, a)
		t: f32
		for fv in frames {
			f, _ := fv.(json.Object)
			if list, has := f["events"].(json.Array); has {
				for ev in list {
					eo, _ := ev.(json.Object)
					append(&evs, Skel_Key{time = t / fps, name = strings.clone(dstr(eo, "name"), a)})
				}
			} else if n := dstr(f, "event"); n != "" {
				append(&evs, Skel_Key{time = t / fps, name = strings.clone(n, a)})
			}
			t += dnum(f, "duration", 1)
		}
		anim.events = evs[:]
	}
	if anim.duration <= 0 do for tl in anim.timelines do for k in tl.keys do anim.duration = max(anim.duration, k.time)
	return anim
}

// db_mesh: a mesh display. Unweighted vertices are in the display's
// space; weighted ones in the armature's bind pose (bonePose / slotPose),
// turned into offsets from each weighting bone.
@(private = "file")
db_mesh :: proc(d: ^Skeleton_Data, disp: json.Object, tex: ^Texture, r: DB_Region) -> Skel_Mesh {
	a := Skeleton_DataAllocator(d)
	g :: proc(arr: json.Array, i: int) -> f32 {
		if i >= len(arr) do return 0
		#partial switch x in arr[i] {
		case json.Float: return f32(x)
		case json.Integer: return f32(x)
		}
		return 0
	}
	verts, _ := disp["vertices"].(json.Array)
	uvs, _ := disp["uvs"].(json.Array)
	tris, _ := disp["triangles"].(json.Array)
	n := len(uvs) / 2
	m := Skel_Mesh{texture = tex, uv = r.bounds, rotated = r.rotated}
	m.uvs = make([][2]f32, n, a)
	for i in 0 ..< n do m.uvs[i] = {g(uvs, i * 2), g(uvs, i * 2 + 1)}
	m.triangles = make([]u16, len(tris), a)
	for i in 0 ..< len(tris) do m.triangles[i] = u16(g(tris, i))
	weights, weighted := disp["weights"].(json.Array)
	if !weighted || len(weights) == 0 {
		m.vertices = make([][2]f32, n, a)
		for i in 0 ..< n do m.vertices[i] = {g(verts, i * 2), g(verts, i * 2 + 1)}
		return m
	}
	// Bind matrices: bonePose [bone, a, b, c, d, tx, ty]*, slotPose [a, b, c, d, tx, ty].
	slotPose, _ := disp["slotPose"].(json.Array)
	sp := [6]f32{1, 0, 0, 1, 0, 0}
	for i in 0 ..< min(6, len(slotPose)) do sp[i] = g(slotPose, i)
	bonePose, _ := disp["bonePose"].(json.Array)
	bind := make(map[int][6]f32, 16, context.temp_allocator)
	for i := 0; i + 6 < len(bonePose); i += 7 {
		bind[int(g(bonePose, i))] = {g(bonePose, i + 1), g(bonePose, i + 2), g(bonePose, i + 3), g(bonePose, i + 4), g(bonePose, i + 5), g(bonePose, i + 6)}
	}
	m.bonesOf = make([][]int, n, a)
	m.offsets = make([][][2]f32, n, a)
	m.weights = make([][]f32, n, a)
	k := 0
	for vi in 0 ..< n {
		vx, vy := g(verts, vi * 2), g(verts, vi * 2 + 1)
		// Armature space (Flash matrices: x' = a x + c y + tx, y' = b x + d y + ty).
		ax := sp[0] * vx + sp[2] * vy + sp[4]
		ay := sp[1] * vx + sp[3] * vy + sp[5]
		count := int(g(weights, k))
		k += 1
		m.bonesOf[vi] = make([]int, count, a)
		m.offsets[vi] = make([][2]f32, count, a)
		m.weights[vi] = make([]f32, count, a)
		for j in 0 ..< count {
			bi := int(g(weights, k))
			w := g(weights, k + 1)
			k += 2
			m.bonesOf[vi][j] = clamp(bi, 0, len(d.bones) - 1)
			m.weights[vi][j] = w
			mat, has := bind[bi]
			if !has do mat = {1, 0, 0, 1, 0, 0}
			// The inverse bind matrix applied to the armature-space vertex.
			det := mat[0] * mat[3] - mat[2] * mat[1]
			if math.abs(det) < 1e-8 do det = 1e-8
			px, py := ax - mat[4], ay - mat[5]
			m.offsets[vi][j] = {(mat[3] * px - mat[2] * py) / det, (-mat[1] * px + mat[0] * py) / det}
		}
	}
	return m
}
