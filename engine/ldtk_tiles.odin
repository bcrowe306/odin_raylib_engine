package engine

import "core:fmt"
import "core:strconv"
import "core:strings"

// ============================================================================
// Per-tile data: animated tiles, custom data, enum tags; terrain rules
//
// Animated tiles live in a tile's LDtk "custom data" text (so LDtk keeps
// them and you can also type them there), one key per line:
//
//     anim=12,13,14,15
//     fps=8
//
// Wherever the first tile (12) is placed - painted or by a rule - the game
// and the editors cycle through the frames. Other lines of the custom data
// are left alone (your own data for scripts: Ldtk_GetTileCustomData).
// ============================================================================

LDTK_TILE_ANIM_DEFAULT_FPS :: 8

Ldtk_TileAnim :: struct {
	frames: []i32,
	fps:    f32,
}

// Ldtk_ParseTileAnim reads "anim=" / "fps=" lines; frames are allocated with
// `allocator`. ok = false without at least two frames.
Ldtk_ParseTileAnim :: proc(text: string, allocator := context.allocator) -> (Ldtk_TileAnim, bool) {
	if !strings.contains(text, "anim") do return {}, false
	frames := make([dynamic]i32, context.temp_allocator)
	fps: f32 = LDTK_TILE_ANIM_DEFAULT_FPS
	for line in strings.split_lines(text, context.temp_allocator) {
		l := strings.trim_space(line)
		eq := strings.index_any(l, "=:")
		if eq < 0 do continue
		key := strings.trim_space(l[:eq])
		val := strings.trim_space(l[eq + 1:])
		switch key {
		case "anim":
			for part in strings.split_multi(val, {",", " "}, context.temp_allocator) {
				p := strings.trim_space(part)
				if p == "" do continue
				if v, ok := strconv.parse_int(p); ok do append(&frames, i32(v))
			}
		case "fps":
			if v, ok := strconv.parse_f32(val); ok && v > 0 do fps = v
		}
	}
	if len(frames) < 2 do return {}, false
	out := make([]i32, len(frames), allocator)
	copy(out, frames[:])
	return {frames = out, fps = fps}, true
}

// Ldtk_TileAnimFrame: the tile id an animation shows at `t` seconds.
Ldtk_TileAnimFrame :: proc(a: Ldtk_TileAnim, t: f64) -> i32 {
	if len(a.frames) == 0 do return 0
	i := int(t * f64(a.fps)) % len(a.frames)
	return a.frames[max(i, 0)]
}

// ldtk_custom_data_set_lines replaces (or appends / removes, with value
// "") the given "key=value" lines of a custom data text.
@(private = "file")
ldtk_custom_data_set_lines :: proc(text: string, keys: []string, values: []string) -> string {
	b := strings.builder_make(context.temp_allocator)
	done := make([]bool, len(keys), context.temp_allocator)
	first := true
	write :: proc(b: ^strings.Builder, first: ^bool, line: string) {
		if !first^ do strings.write_byte(b, '\n')
		strings.write_string(b, line)
		first^ = false
	}
	for line in strings.split_lines(text, context.temp_allocator) {
		l := strings.trim_space(line)
		eq := strings.index_any(l, "=:")
		matched := -1
		if eq >= 0 do for k, i in keys do if strings.trim_space(l[:eq]) == k do matched = i
		if matched < 0 {
			if l != "" do write(&b, &first, line)
			continue
		}
		if !done[matched] && values[matched] != "" do write(&b, &first, fmt.tprintf("%s=%s", keys[matched], values[matched]))
		done[matched] = true
	}
	for k, i in keys do if !done[i] && values[i] != "" do write(&b, &first, fmt.tprintf("%s=%s", k, values[i]))
	return strings.to_string(b)
}

// ----------------------------------------------------------------------------
// Editing (Ldtk_Doc)
// ----------------------------------------------------------------------------

// Ldtk_Doc_TileCustomData: a tile's custom data text ("" if none).
Ldtk_Doc_TileCustomData :: proc(doc: ^Ldtk_Doc, tilesetUid: int, tid: int) -> string {
	ts := Ldtk_Doc_Tileset(doc, tilesetUid)
	if ts == nil do return ""
	for cd in LdtkJson_Arr(ts.obj, "customData") do if LdtkJson_Int(cd, "tileId", -1) == tid do return LdtkJson_Str(cd, "data")
	return ""
}

// Ldtk_Doc_SetTileCustomData sets (or, with "", removes) a tile's custom data.
Ldtk_Doc_SetTileCustomData :: proc(doc: ^Ldtk_Doc, tilesetUid: int, tid: int, text: string) {
	a := doc.allocator
	ts := Ldtk_Doc_Tileset(doc, tilesetUid)
	if ts == nil do return
	list := LdtkJson_Get(ts.obj, "customData")
	if list == nil || list.kind != .Array {
		list = LdtkJson_New(.Array, a)
		LdtkJson_Set(ts.obj, "customData", list, a)
	}
	for cd, i in list.items {
		if LdtkJson_Int(cd, "tileId", -1) != tid do continue
		if text == "" do ordered_remove(&list.items, i)
		else do LdtkJson_SetStr(cd, "data", text, a)
		Ldtk_Doc_RefreshDefs(doc)
		Ldtk_Doc_Touch(doc)
		return
	}
	if text == "" do return
	o := LdtkJson_New(.Object, a)
	append(&o.keys, strings.clone("tileId", a), strings.clone("data", a))
	append(&o.items, LdtkJson_NewInt(tid, a), LdtkJson_NewString(text, a))
	// LDtk keeps the list sorted by tile id
	at := len(list.items)
	for cd, i in list.items do if LdtkJson_Int(cd, "tileId") > tid {
		at = i
		break
	}
	inject_at(&list.items, at, o)
	Ldtk_Doc_RefreshDefs(doc)
	Ldtk_Doc_Touch(doc)
}

// Ldtk_Doc_SetTileAnimation makes `tid` animate through `frames` (fewer
// than two frames removes the animation), keeping other custom data lines.
Ldtk_Doc_SetTileAnimation :: proc(doc: ^Ldtk_Doc, tilesetUid: int, tid: int, frames: []i32, fps: f32) {
	cur := Ldtk_Doc_TileCustomData(doc, tilesetUid, tid)
	anim, fpsText := "", ""
	if len(frames) >= 2 {
		b := strings.builder_make(context.temp_allocator)
		for f, i in frames {
			if i > 0 do strings.write_byte(&b, ',')
			fmt.sbprintf(&b, "%d", f)
		}
		anim = strings.to_string(b)
		if fps > 0 && fps != LDTK_TILE_ANIM_DEFAULT_FPS do fpsText = fmt.tprintf("%v", fps)
	}
	Ldtk_Doc_SetTileCustomData(doc, tilesetUid, tid, ldtk_custom_data_set_lines(cur, {"anim", "fps"}, {anim, fpsText}))
}

// Ldtk_Doc_TileAnimation: the tile's animation (frames in the temp allocator).
Ldtk_Doc_TileAnimation :: proc(doc: ^Ldtk_Doc, tilesetUid: int, tid: int) -> (Ldtk_TileAnim, bool) {
	return Ldtk_ParseTileAnim(Ldtk_Doc_TileCustomData(doc, tilesetUid, tid), context.temp_allocator)
}

// Ldtk_Doc_TileHasTag: is the tile tagged with an enum value?
Ldtk_Doc_TileHasTag :: proc(doc: ^Ldtk_Doc, tilesetUid: int, tid: int, valueId: string) -> bool {
	ts := Ldtk_Doc_Tileset(doc, tilesetUid)
	if ts == nil do return false
	for tag in LdtkJson_Arr(ts.obj, "enumTags") {
		if LdtkJson_Str(tag, "enumValueId") != valueId do continue
		for t in LdtkJson_Arr(tag, "tileIds") do if int(t.num) == tid do return true
	}
	return false
}

// Ldtk_Doc_SetTileTag tags / untags a tile with a value of the tileset's
// tag enum ("tagsSourceEnumUid").
Ldtk_Doc_SetTileTag :: proc(doc: ^Ldtk_Doc, tilesetUid: int, tid: int, valueId: string, on: bool) {
	a := doc.allocator
	ts := Ldtk_Doc_Tileset(doc, tilesetUid)
	if ts == nil do return
	list := LdtkJson_Get(ts.obj, "enumTags")
	if list == nil || list.kind != .Array {
		list = LdtkJson_New(.Array, a)
		LdtkJson_Set(ts.obj, "enumTags", list, a)
	}
	tag: ^LdtkJson
	for t in list.items do if LdtkJson_Str(t, "enumValueId") == valueId do tag = t
	if tag == nil {
		tag = LdtkJson_New(.Object, a)
		append(&tag.keys, strings.clone("enumValueId", a), strings.clone("tileIds", a))
		append(&tag.items, LdtkJson_NewString(valueId, a), LdtkJson_New(.Array, a))
		append(&list.items, tag)
	}
	ids := LdtkJson_Get(tag, "tileIds")
	for t, i in ids.items {
		if int(t.num) != tid do continue
		if !on {
			ordered_remove(&ids.items, i)
			Ldtk_Doc_Touch(doc)
		}
		return
	}
	if on {
		at := len(ids.items)
		for t, i in ids.items do if int(t.num) > tid {
			at = i
			break
		}
		inject_at(&ids.items, at, LdtkJson_NewInt(tid, a))
		Ldtk_Doc_Touch(doc)
	}
}

// Ldtk_Doc_AddTerrainRules adds a rule group drawing a 3x3 terrain block
// (tile ids row by row: top-left, top, top-right, left, centre, right,
// bottom-left, bottom, bottom-right) over cells of `value`: corners and
// edges where the neighbours aren't `value`, the centre elsewhere.
// Returns the group uid.
Ldtk_Doc_AddTerrainRules :: proc(doc: ^Ldtk_Doc, layerUid: int, value: int, block: [9]int) -> int {
	g := Ldtk_Doc_AddRuleGroup(doc, layerUid, fmt.tprintf("Terrain %d", value))
	if g < 0 do return -1
	// pattern cells (3x3): 1 = up, 3 = left, 5 = right, 7 = down
	Rule :: struct {tile: int, not: []int}
	rules := [?]Rule{
		{block[0], {1, 3}}, {block[2], {1, 5}}, {block[6], {7, 3}}, {block[8], {7, 5}},
		{block[1], {1}}, {block[7], {7}}, {block[3], {3}}, {block[5], {5}},
		{block[4], {}},
	}
	for r in rules {
		uid := Ldtk_Doc_AddRule(doc, layerUid, g, 3, value, r.tile)
		for c in r.not do Ldtk_Doc_SetRuleCell(doc, uid, c % 3, c / 3, -value)
	}
	return g
}
