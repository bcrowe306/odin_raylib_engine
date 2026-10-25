package engine

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import rl "vendor:raylib"

// Aseprite files (aseprite.odin / aseprite_render.odin) against what
// Aseprite itself makes of them: tests/aseprite/fixtures/*.aseprite (built
// by tests/aseprite/make_fixtures.lua), tests/aseprite/expected/<name>.json
// (Aseprite's own reading: tests/aseprite/dump.lua) and <name>_<frame>.png
// (Aseprite's renders). scripts/aseprite_fixtures.sh rebuilds them.

@(private = "file")
ASE_FIXTURES :: "tests/aseprite/fixtures"
@(private = "file")
ASE_EXPECTED :: "tests/aseprite/expected"

@(private = "file")
load_fixture :: proc(t: ^testing.T, name: string, dir := ASE_FIXTURES, expected := ASE_EXPECTED) -> (^Ase_Document, json.Object, bool) {
	path := fmt.tprintf("%s/%s.aseprite", dir, name)
	data, err := os.read_entire_file(path, context.temp_allocator)
	if !testing.expectf(t, err == nil, "%s: %v", path, err) do return nil, nil, false
	doc, why := Ase_Load(data)
	if !testing.expectf(t, doc != nil, "%s: %s", name, why) do return nil, nil, false
	jdata, jerr := os.read_entire_file(fmt.tprintf("%s/%s.json", expected, name), context.temp_allocator)
	if !testing.expect(t, jerr == nil, "expected json") do return doc, nil, false
	v, perr := json.parse(jdata, allocator = context.temp_allocator)
	if !testing.expect(t, perr == nil, "json parses") do return doc, nil, false
	return doc, v.(json.Object), true
}

@(private = "file")
num :: proc(v: json.Value) -> f64 {
	#partial switch x in v {
	case json.Float: return f64(x)
	case json.Integer: return f64(x)
	}
	return 0
}

// Every frame rendered = Aseprite's render (exact; reports the first
// difference).
@(private = "file")
check_frames :: proc(t: ^testing.T, name: string, doc: ^Ase_Document, dir := ASE_EXPECTED) {
	out := make([]u8, doc.width * doc.height * 4, context.temp_allocator)
	for f in 0 ..< len(doc.frames) {
		path := fmt.ctprintf("%s/%s_%d.png", dir, name, f)
		// (Aseprite names single-frame saves without the number.)
		if len(doc.frames) == 1 && !os.is_file(string(path)) do path = fmt.ctprintf("%s/%s.png", dir, name)
		img := rl.LoadImage(path)
		if !testing.expectf(t, img.data != nil, "%s missing", path) do continue
		defer rl.UnloadImage(img)
		rl.ImageFormat(&img, .UNCOMPRESSED_R8G8B8A8)
		testing.expectf(t, int(img.width) == doc.width && int(img.height) == doc.height, "%s frame %d: size", name, f)
		Ase_RenderFrame(doc, f, out)
		want := ([^]u8)(img.data)[:doc.width * doc.height * 4]
		diffs := 0
		first := -1
		for i := 0; i < len(out); i += 4 {
			// (Fully transparent pixels: the colour doesn't matter.)
			if out[i + 3] == 0 && want[i + 3] == 0 do continue
			if out[i] != want[i] || out[i + 1] != want[i + 1] || out[i + 2] != want[i + 2] || out[i + 3] != want[i + 3] {
				diffs += 1
				if first < 0 do first = i / 4
			}
		}
		if diffs > 0 {
			i := first * 4
			testing.expectf(t, false, "%s frame %d: %d pixels differ; first at (%d, %d): got %v, Aseprite %v", name, f, diffs,
				first % doc.width, first / doc.width, out[i:i + 4], want[i:i + 4])
		}
	}
}

@(test)
test_aseprite_renders_like_aseprite :: proc(t: ^testing.T) {
	infos, err := os.read_all_directory_by_path(ASE_FIXTURES, context.temp_allocator)
	if !testing.expect(t, err == nil && len(infos) > 0, "fixtures") do return
	for fi in infos {
		if !strings.has_suffix(fi.name, ".aseprite") do continue
		name := strings.trim_suffix(fi.name, ".aseprite")
		doc, _, ok := load_fixture(t, name)
		if !ok {
			Ase_Destroy(doc)
			continue
		}
		check_frames(t, name, doc)
		Ase_Destroy(doc)
	}
}

// Aseprite's own test sprites (the aseprite/ submodule), rendered by
// scripts/aseprite_fixtures.sh into build/aseprite_upstream/ (not committed:
// Aseprite's EULA): compared when they're there (a checkout with Aseprite).
@(test)
test_aseprite_upstream_sprites :: proc(t: ^testing.T) {
	UP :: "build/aseprite_upstream"
	infos, err := os.read_all_directory_by_path(UP, context.temp_allocator)
	if err != nil do return // (not generated here)
	for fi in infos {
		if !strings.has_suffix(fi.name, ".aseprite") do continue
		name := strings.trim_suffix(fi.name, ".aseprite")
		data, rerr := os.read_entire_file(fmt.tprintf("%s/%s", UP, fi.name), context.temp_allocator)
		if rerr != nil do continue
		doc, why := Ase_Load(data)
		if !testing.expectf(t, doc != nil, "upstream %s: %s", name, why) do continue
		check_frames(t, name, doc, UP)
		Ase_Destroy(doc)
	}
}

// Groups composited on their own (header flag 2; Aseprite 1.3.16 doesn't
// write it yet): the group's opacity and blend mode apply to the composite
// of its children, not to each child.
@(test)
test_aseprite_compose_groups :: proc(t: ^testing.T) {
	data, err := os.read_entire_file(ASE_FIXTURES + "/groups.aseprite", context.temp_allocator)
	if !testing.expect(t, err == nil, "fixture") do return
	plain, _ := Ase_Load(data)
	defer Ase_Destroy(plain)
	patched := make([]u8, len(data), context.temp_allocator)
	copy(patched, data)
	patched[14] |= 2 // Compose_Groups
	// The "Outer" group's opacity / blend mode (layer chunk: ... blend WORD,
	// opacity BYTE, 3 reserved, then the name): 200, Multiply.
	name := transmute([]u8)string("\x05\x00Outer")
	at := -1
	for i in 0 ..< len(patched) - len(name) do if string(patched[i:i + len(name)]) == string(name) {at = i; break}
	if !testing.expect(t, at > 6, "the group's layer chunk") do return
	patched[at - 4] = 200
	patched[at - 6], patched[at - 5] = 1, 0
	doc, _ := Ase_Load(patched)
	defer Ase_Destroy(doc)
	if !testing.expect(t, doc != nil && plain != nil, "loads") do return
	testing.expect(t, .Compose_Groups in doc.flags, "flag read")
	outer := Ase_FindLayer(doc, "Outer")
	testing.expect_value(t, doc.layers[outer].opacity, u8(200))
	testing.expect_value(t, doc.layers[outer].blend, Ase_Blend.Multiply)
	testing.expect_value(t, plain.layers[outer].opacity, u8(255))
	a := make([]u8, doc.width * doc.height * 4, context.temp_allocator)
	b := make([]u8, doc.width * doc.height * 4, context.temp_allocator)
	Ase_RenderFrame(doc, 0, a)
	Ase_RenderFrame(plain, 0, b)
	// Where only the base shows, the same; inside the group's area, not.
	same, differ := 0, 0
	for i := 0; i < len(a); i += 4 {
		if a[i] == b[i] && a[i + 1] == b[i + 1] && a[i + 2] == b[i + 2] && a[i + 3] == b[i + 3] do same += 1
		else do differ += 1
	}
	testing.expect(t, differ > 0 && same > 0, "the group's composite differs, the rest doesn't")
	// The group alone: its children composited, then the group's opacity.
	layerOnly := make([]u8, doc.width * doc.height * 4, context.temp_allocator)
	Ase_RenderLayer(doc, 0, outer, layerOnly)
	testing.expect(t, layerOnly[(2 * doc.width + 2) * 4 + 3] > 0, "the group renders")
}

@(test)
test_aseprite_reads_like_aseprite :: proc(t: ^testing.T) {
	check_reads(t, ASE_FIXTURES, ASE_EXPECTED)
	if os.is_dir("build/aseprite_upstream") do check_reads(t, "build/aseprite_upstream", "build/aseprite_upstream")
}

@(private = "file")
check_reads :: proc(t: ^testing.T, dir, expected: string) {
	infos, _ := os.read_all_directory_by_path(dir, context.temp_allocator)
	for fi in infos {
		if !strings.has_suffix(fi.name, ".aseprite") do continue
		name := strings.trim_suffix(fi.name, ".aseprite")
		if !os.is_file(fmt.tprintf("%s/%s.json", expected, name)) do continue
		doc, want, ok := load_fixture(t, name, dir, expected)
		defer Ase_Destroy(doc)
		if !ok do continue
		testing.expectf(t, doc.width == int(num(want["width"])) && doc.height == int(num(want["height"])), "%s: size", name)
		// Frames and their durations.
		durations := want["frames"].(json.Array)
		if testing.expectf(t, len(doc.frames) == len(durations), "%s: %d frames, Aseprite %d", name, len(doc.frames), len(durations)) {
			for d, i in durations do testing.expectf(t, doc.frames[i].duration == int(num(d)), "%s frame %d: %d ms, Aseprite %v", name, i, doc.frames[i].duration, d)
		}
		// Layers: names, nesting, visibility, kinds, blend modes, opacity.
		layers := want["layers"].(json.Array)
		if testing.expectf(t, len(doc.layers) == len(layers), "%s: %d layers, Aseprite %d", name, len(doc.layers), len(layers)) {
			// (Same order as the file's layer chunks: bottom up, groups before their layers.)
			for lv, i in layers {
				wl := lv.(json.Object)
				l := doc.layers[i]
				if !testing.expectf(t, l.name == wl["name"].(json.String), "%s: layer %d is %q, Aseprite %v", name, i, l.name, wl["name"]) do continue
				parent := "" if l.parent < 0 else doc.layers[l.parent].name
				wparent, _ := wl["parent"].(json.String)
				testing.expectf(t, parent == wparent, "%s layer %s: parent %q, Aseprite %q", name, l.name, parent, wparent)
				testing.expectf(t, (.Visible in l.flags) == wl["visible"].(json.Boolean), "%s layer %s: visible", name, l.name)
				testing.expectf(t, (l.kind == .Group) == wl["group"].(json.Boolean), "%s layer %s: group", name, l.name)
				testing.expectf(t, (l.kind == .Tilemap) == wl["tilemap"].(json.Boolean), "%s layer %s: tilemap", name, l.name)
				testing.expectf(t, (.Background in l.flags) == wl["background"].(json.Boolean), "%s layer %s: background", name, l.name)
				// (Groups not composited on their own have no opacity / blend mode in Aseprite.)
				if wl["opacity"] != nil {
					testing.expectf(t, int(l.opacity) == int(num(wl["opacity"])), "%s layer %s: opacity %d, Aseprite %v", name, l.name, l.opacity, wl["opacity"])
					// (Aseprite's Lua numbers blend modes from 3 = Normal, Multiply = 14...)
					lua := int(num(wl["blendMode"]))
					want_blend := 0 if lua == 3 else lua - 13
					testing.expectf(t, int(l.blend) == want_blend, "%s layer %s: blend %v, Aseprite %d", name, l.name, l.blend, want_blend)
				}
				check_user(t, fmt.tprintf("%s layer %s", name, l.name), l.user, wl["userdata"].(json.Object))
			}
		}
		// Cels: position, opacity, z-index, size, user data.
		for cv in want["cels"].(json.Array) {
			wc := cv.(json.Object)
			li := int(num(wc["layerIndex"]))
			f := int(num(wc["frame"])) - 1
			c: ^Ase_Cel
			if li >= 0 && f >= 0 && f < len(doc.frames) do for &x in doc.frames[f].cels do if x.layer == li do c = &x
			label := fmt.tprintf("%s cel %v/%d", name, wc["layer"], f)
			if !testing.expectf(t, c != nil, "%s: missing", label) do continue
			testing.expectf(t, c.x == int(num(wc["x"])) && c.y == int(num(wc["y"])), "%s: position (%d, %d), Aseprite (%v, %v)", label, c.x, c.y, wc["x"], wc["y"])
			testing.expectf(t, int(c.opacity) == int(num(wc["opacity"])), "%s: opacity", label)
			testing.expectf(t, c.z_index == int(num(wc["zIndex"])), "%s: z-index %d, Aseprite %v", label, c.z_index, wc["zIndex"])
			if doc.layers[li].kind == .Image {
				testing.expectf(t, c.w == int(num(wc["width"])) && c.h == int(num(wc["height"])), "%s: size %dx%d, Aseprite %vx%v", label, c.w, c.h, wc["width"], wc["height"])
			}
			check_user(t, label, c.user, wc["userdata"].(json.Object))
		}
		// Tags.
		tags := want["tags"].(json.Array)
		if testing.expectf(t, len(doc.tags) == len(tags), "%s: %d tags, Aseprite %d", name, len(doc.tags), len(tags)) {
			for tv in tags {
				wt := tv.(json.Object)
				tg := Ase_FindTag(doc, wt["name"].(json.String))
				if !testing.expectf(t, tg != nil, "%s: tag %v", name, wt["name"]) do continue
				label := fmt.tprintf("%s tag %s", name, tg.name)
				testing.expectf(t, tg.from == int(num(wt["from"])) - 1 && tg.to == int(num(wt["to"])) - 1, "%s: frames %d..%d", label, tg.from, tg.to)
				testing.expectf(t, int(tg.direction) == int(num(wt["aniDir"])), "%s: direction %v, Aseprite %v", label, tg.direction, wt["aniDir"])
				testing.expectf(t, tg.repeats == int(num(wt["repeats"])), "%s: repeats %d, Aseprite %v", label, tg.repeats, wt["repeats"])
				check_user(t, label, tg.user, wt["userdata"].(json.Object))
			}
		}
		// Slices.
		for sv in want["slices"].(json.Array) {
			ws := sv.(json.Object)
			s := Ase_FindSlice(doc, ws["name"].(json.String))
			label := fmt.tprintf("%s slice %v", name, ws["name"])
			if !testing.expectf(t, s != nil && len(s.keys) > 0, "%s: missing", label) do continue
			k := s.keys[0]
			b := ws["bounds"].(json.Array)
			testing.expectf(t, k.x == int(num(b[0])) && k.y == int(num(b[1])) && k.w == int(num(b[2])) && k.h == int(num(b[3])), "%s: bounds", label)
			if c, has := ws["center"].(json.Array); has {
				testing.expectf(t, s.nine_patch && k.center == {int(num(c[0])), int(num(c[1])), int(num(c[2])), int(num(c[3]))}, "%s: 9-patch centre %v", label, k.center)
			} else {
				testing.expectf(t, !s.nine_patch, "%s: no 9-patch", label)
			}
			if p, has := ws["pivot"].(json.Array); has {
				testing.expectf(t, s.has_pivot && k.pivot == {int(num(p[0])), int(num(p[1]))}, "%s: pivot %v", label, k.pivot)
			}
			check_user(t, label, s.user, ws["userdata"].(json.Object))
		}
		// The palette and tilesets.
		pal := want["palette"].(json.Array)
		if doc.depth == .Indexed && testing.expectf(t, len(doc.palette) >= len(pal), "%s: palette size %d, Aseprite %d", name, len(doc.palette), len(pal)) {
			for pc, i in pal {
				c := pc.(json.Array)
				testing.expectf(t, doc.palette[i].color == {u8(num(c[0])), u8(num(c[1])), u8(num(c[2])), u8(num(c[3]))}, "%s: palette %d %v", name, i, doc.palette[i].color)
			}
		}
		for tv, i in want["tilesets"].(json.Array) {
			wt := tv.(json.Object)
			if !testing.expectf(t, i < len(doc.tilesets), "%s: tileset %d", name, i) do continue
			ts := doc.tilesets[i]
			testing.expectf(t, ts.name == wt["name"].(json.String) && ts.count == int(num(wt["tiles"])), "%s: tileset %s (%d tiles)", name, ts.name, ts.count)
			for d, ti in wt["tileData"].(json.Array) {
				text := ts.tile_user[ti].text if ti < len(ts.tile_user) else ""
				testing.expectf(t, text == d.(json.String), "%s: tile %d user data %q, Aseprite %v", name, ti, text, d)
			}
		}
		check_user(t, fmt.tprintf("%s sprite", name), doc.user, want["userdata"].(json.Object))
	}
}

// check_user: text, colour and properties as Aseprite reads them.
@(private = "file")
check_user :: proc(t: ^testing.T, label: string, u: Ase_User_Data, want: json.Object) {
	wtext, _ := want["text"].(json.String)
	testing.expectf(t, u.text == wtext, "%s: user data text %q, Aseprite %q", label, u.text, wtext)
	if c, ok := want["color"].(json.Array); ok && len(c) == 4 {
		wc := [4]u8{u8(num(c[0])), u8(num(c[1])), u8(num(c[2])), u8(num(c[3]))}
		if wc != {0, 0, 0, 0} do testing.expectf(t, u.has_color && u.color == wc, "%s: user data colour %v, Aseprite %v", label, u.color, wc)
	}
	if props, ok := want["properties"].(json.Object); ok {
		testing.expectf(t, len(u.properties) == len(props), "%s: %d properties, Aseprite %d", label, len(u.properties), len(props))
		for k, wv in props {
			v, has := u.properties[k]
			if !testing.expectf(t, has, "%s: property %s", label, k) do continue
			testing.expectf(t, value_matches(v, wv), "%s: property %s = %v, Aseprite %v", label, k, v, wv)
		}
	}
}

@(private = "file")
value_matches :: proc(v: Ase_Value, w: json.Value) -> bool {
	switch x in v {
	case bool: b, ok := w.(json.Boolean); return ok && bool(b) == x
	case i64: return f64(x) == num(w)
	case u64: return f64(x) == num(w)
	case f64: return abs(x - num(w)) < 1e-6
	case string: s, ok := w.(json.String); return ok && s == x
	case Ase_Point: o, ok := w.(json.Object); return ok && i32(num(o["x"])) == x[0] && i32(num(o["y"])) == x[1]
	case Ase_Size: o, ok := w.(json.Object); return ok && i32(num(o["width"])) == x[0] && i32(num(o["height"])) == x[1]
	case Ase_Rect:
		o, ok := w.(json.Object)
		return ok && i32(num(o["x"])) == x.x && i32(num(o["y"])) == x.y && i32(num(o["width"])) == x.w && i32(num(o["height"])) == x.h
	case []Ase_Value:
		a, ok := w.(json.Array)
		if !ok || len(a) != len(x) do return false
		for e, i in x do if !value_matches(e, a[i]) do return false
		return true
	case map[string]Ase_Value:
		o, ok := w.(json.Object)
		if !ok || len(o) != len(x) do return false
		for k, e in x do if !value_matches(e, o[k]) do return false
		return true
	case Ase_UUID: return true
	}
	return w == nil
}

// AsepriteNode plays tags as Aseprite does: per-frame durations, every
// direction, repeat counts, events (tests/aseprite/fixtures/animation:
// frames last 50, 100, ... 400 ms; idle 0-2 forward looping, walk 2-4
// reverse x2, jump 4-7 ping-pong x1, spin 1-6 ping-pong reverse x3).
@(test)
test_aseprite_node_playback :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	AssetManager_SetProjectDir(&game.assetManager, ASE_FIXTURES)
	scene := game->createScene("ase", true)
	an := AsepriteNode_Create(scene, "Hero")
	an.gameContext = &game.gameContext
	an.file = strings.clone("animation.aseprite", an.allocator)
	ProcessNodeQueues(scene.manager, &game.gameContext)

	Recorder :: struct {frames: [dynamic]int, finished: [dynamic]string, looped: int}
	rec: Recorder
	rec.frames = make([dynamic]int, context.temp_allocator)
	rec.finished = make([dynamic]string, context.temp_allocator)
	Subscribe(&an.onFrame, proc(src: rawptr, v: EventValue, ctx: ^GameContext, ud: rawptr) {
		r := cast(^Recorder)ud
		append(&r.frames, v.(int))
	}, &rec)
	Subscribe(&an.onFinished, proc(src: rawptr, v: EventValue, ctx: ^GameContext, ud: rawptr) {
		r := cast(^Recorder)ud
		append(&r.finished, v.(string))
	}, &rec)
	Subscribe(&an.onLooped, proc(src: rawptr, v: EventValue, ctx: ^GameContext, ud: rawptr) {
		(cast(^Recorder)ud).looped += 1
	}, &rec)

	play :: proc(an: ^AsepriteNode, rec: ^Recorder, tag: string, ms: int) -> []int {
		AsepriteNode_Play(an, tag)
		clear(&rec.frames)
		append(&rec.frames, an.frame)
		for _ in 0 ..< ms do AsepriteNode_Update(an, an.gameContext, 0.001)
		return rec.frames[:]
	}
	seq :: proc(t: ^testing.T, got: []int, want: []int, label: string) {
		ok := len(got) == len(want)
		if ok do for g, i in got do if g != want[i] do ok = false
		testing.expectf(t, ok, "%s: frames %v, want %v", label, got, want)
	}
	_ = AsepriteNode_Size(an) // (loads it)
	testing.expect(t, an.res != nil && len(an.res.doc.frames) == 8, "loaded")
	if an.res == nil do return

	// Reverse x2: 4 3 2, 4 3 2, then it stops (finished).
	seq(t, play(an, &rec, "walk", 4000), {4, 3, 2, 4, 3, 2}, "walk (reverse x2)")
	testing.expect(t, !an.playing && len(rec.finished) == 1 && rec.finished[0] == "walk", "walk finished")

	// Ping-pong x1: one direction only.
	seq(t, play(an, &rec, "jump", 4000), {4, 5, 6, 7}, "jump (ping-pong x1)")

	// Ping-pong reverse x3: down, up, down (the turning frame shown once).
	seq(t, play(an, &rec, "spin", 8000), {6, 5, 4, 3, 2, 1, 2, 3, 4, 5, 6, 5, 4, 3, 2, 1}, "spin (ping-pong reverse x3)")

	// No repeat count: loops (frame durations 50 / 100 / 150 ms: 300 ms a loop).
	rec.looped = 0
	got := play(an, &rec, "idle", 610)
	seq(t, got, {0, 1, 2, 0, 1, 2, 0}, "idle (loops)")
	testing.expect(t, an.playing && rec.looped == 2, "idle keeps looping")

	// loop = false: a tag without a repeat count plays once.
	an.loop = false
	seq(t, play(an, &rec, "idle", 2000), {0, 1, 2}, "idle once")
	testing.expect(t, !an.playing, "stopped")
	an.loop = true

	// Speed doubles the rate; "" plays every frame.
	an.speed = 2
	seq(t, play(an, &rec, "", 300), {0, 1, 2, 3, 4}, "every frame at 2x (300 ms = 600 ms of frames: 50+100+150+200 -> frame 4)")
	an.speed = 1
}

// Any image path can be an Aseprite file (its first frame), and layer
// overrides pick what's drawn.
@(test)
test_aseprite_layer_overrides :: proc(t: ^testing.T) {
	data, _ := os.read_entire_file(ASE_FIXTURES + "/groups.aseprite", context.temp_allocator)
	doc, _ := Ase_Load(data)
	defer Ase_Destroy(doc)
	if !testing.expect(t, doc != nil, "loads") do return
	vis := Ase_LayerOverrides(doc, "Base", "Hidden", context.temp_allocator)
	testing.expect(t, !vis[Ase_FindLayer(doc, "Base")] && vis[Ase_FindLayer(doc, "Hidden")], "hide / show")
	testing.expect(t, Ase_LayerOverrides(doc, "", " ", context.temp_allocator) == nil, "no overrides")
	out := make([]u8, doc.width * doc.height * 4, context.temp_allocator)
	Ase_RenderFrame(doc, 0, out, {visible = vis})
	// "Hidden" is solid magenta over everything: shown now.
	testing.expectf(t, out[0] == 255 && out[1] == 0 && out[2] == 255 && out[3] == 255, "the hidden layer shows: %v", out[:4])
}

// A tilemap layer rebuilt tile by tile (Ase_TileImage: what a TileMapNode's
// tileset is made of, flips baked in) equals the frame Aseprite renders.
@(test)
test_aseprite_tiles_match_the_render :: proc(t: ^testing.T) {
	data, _ := os.read_entire_file(ASE_FIXTURES + "/tilemap.aseprite", context.temp_allocator)
	doc, _ := Ase_Load(data)
	defer Ase_Destroy(doc)
	if !testing.expect(t, doc != nil, "loads") do return
	li := Ase_FindLayer(doc, "Tiles")
	if !testing.expect(t, li >= 0 && doc.layers[li].kind == .Tilemap, "the tilemap layer") do return
	ts := &doc.tilesets[doc.layers[li].tileset]
	cel: ^Ase_Cel
	for &c in doc.frames[0].cels do if c.layer == li do cel = &c
	if !testing.expect(t, cel != nil, "its cel") do return
	only := make([]bool, len(doc.layers), context.temp_allocator)
	only[li] = true
	want := make([]u8, doc.width * doc.height * 4, context.temp_allocator)
	Ase_RenderFrame(doc, 0, want, {visible = only})
	tile := make([]u8, ts.tile_w * ts.tile_h * 4, context.temp_allocator)
	flipped := 0
	for ty in 0 ..< cel.h do for tx in 0 ..< cel.w {
		tl := cel.tiles[ty * cel.w + tx]
		if tl.xflip || tl.yflip || tl.dflip do flipped += 1
		Ase_TileImage(doc, ts, int(tl.index), tl.xflip, tl.yflip, tl.dflip, tile)
		for y in 0 ..< ts.tile_h do for x in 0 ..< ts.tile_w {
			px, py := cel.x + tx * ts.tile_w + x, cel.y + ty * ts.tile_h + y
			if px >= doc.width || py >= doc.height do continue
			a := tile[(y * ts.tile_w + x) * 4:][:4]
			b := want[(py * doc.width + px) * 4:][:4]
			if a[3] == 0 && b[3] == 0 do continue
			if !testing.expectf(t, a[0] == b[0] && a[1] == b[1] && a[2] == b[2] && a[3] == b[3], "tile (%d, %d) pixel (%d, %d): %v, render %v", tx, ty, x, y, a, b) do return
		}
	}
	testing.expect(t, flipped > 0, "the fixture has flipped tiles")
}

// Saving the file again reloads it (ResourceManager_CheckForChanges ->
// Ase_CheckForChanges): the resource's document and version change; the
// last release frees it.
@(test)
test_aseprite_resource_reload :: proc(t: ^testing.T) {
	path, _ := filepath.join({ase_tmp_dir(), "ore_ase_reload.aseprite"}, context.temp_allocator)
	defer os.remove(path)
	a, _ := os.read_entire_file(ASE_FIXTURES + "/animation.aseprite", context.temp_allocator)
	b, _ := os.read_entire_file(ASE_FIXTURES + "/slices.aseprite", context.temp_allocator)
	_ = os.write_entire_file(path, a)
	rm: ResourceManager
	r := ResourceManager_LoadAseprite(&rm, path)
	if !testing.expect(t, r != nil, "loads") do return
	testing.expect_value(t, len(r.doc.frames), 8)
	again := ResourceManager_LoadAseprite(&rm, path)
	testing.expect(t, again == r && r.refs == 2, "shared")
	ResourceManager_ReleaseAseprite(again)
	// "Saved in Aseprite": another sprite, newer than when it was loaded.
	_ = os.write_entire_file(path, b)
	r.modTime = {} // (as if loaded long ago)
	r.modTime._nsec = 1
	testing.expect_value(t, Ase_CheckForChanges(&rm), 1)
	testing.expect_value(t, r.version, 1)
	testing.expect_value(t, r.doc.width, 32)
	testing.expect_value(t, len(r.doc.slices), 3)
	testing.expect_value(t, Ase_CheckForChanges(&rm), 0)
	ResourceManager_ReleaseAseprite(r)
	testing.expect_value(t, Ase_ResourceCount(&rm), 0)
	delete(rm.aseprite)
}

// An exported game: the .aseprite file read from inside game.ore (no file on
// disk), its tags playing (the TileMap path needs a window: runtime_tests.json).
@(test)
test_aseprite_from_a_package :: proc(t: ^testing.T) {
	ore, _ := filepath.join({ase_tmp_dir(), "ore_ase_test.ore"}, context.temp_allocator)
	defer os.remove(ore)
	if !testing.expect(t, OrePackage_CreateFromDirectory("tests/aseprite/project", ore, true), "packaged") do return
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	if !testing.expect(t, game->loadProject(ore), "loads from the package") do return
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	scene := game.sceneManager.currentScene
	if !testing.expect(t, scene != nil, "a scene") do return
	walker := Scene_FindNodeByName(scene, "Walker")
	if !testing.expect(t, walker != nil && walker.typeId == AsepriteNode, "the Aseprite node") do return
	an := cast(^AsepriteNode)walker
	size := AsepriteNode_Size(an)
	testing.expect(t, an.res != nil && size == {8, 8}, "read from game.ore")
	AsepriteNode_Play(an, "walk")
	for _ in 0 ..< 300 do AsepriteNode_Update(an, &game.gameContext, 0.001) // 300 ms: frame 4 (250 ms), then 3
	testing.expect_value(t, an.frame, 3)
}

// ase_tmp_dir: a writable temporary folder (TMPDIR, TEMP / TMP on Windows).
@(private = "file")
ase_tmp_dir :: proc() -> string {
	for v in ([]string{"TMPDIR", "TEMP", "TMP"}) do if d := os.get_env(v, context.temp_allocator); d != "" do return d
	_ = os.make_directory_all("build/tmp")
	return "build/tmp"
}
