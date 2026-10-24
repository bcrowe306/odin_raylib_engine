package engine

import "core:fmt"
import "core:math/rand"
import vmem "core:mem/virtual"
import os "osx"
import "core:path/filepath"
import "core:strings"
import "core:testing"

// Samples saved by LDtk 1.5 (stamps, rule assistant, external levels) and
// the drive project (9 rule layers).
LDTK_DOC_FIXTURES := [?]string{
	"tests/drive/fixtures/ldtk_editor/stamps_zz.ldtk",
	"tests/drive/fixtures/ldtk_editor/assistant_zz.ldtk",
	"tests/drive/fixtures/ldtk_editor/SeparateLevelFiles.ldtk",
	"tests/drive/fixtures/ldtk/topdown.ldtk",
}

@(private = "file")
read_text :: proc(path: string) -> string {
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil do return ""
	return string(data)
}

@(test)
test_ldtk_json_round_trip_and_js_numbers :: proc(t: ^testing.T) {
	for path in LDTK_DOC_FIXTURES[:3] {
		text := read_text(path)
		testing.expectf(t, text != "", "fixture %s", path)
		arena: vmem.Arena
		_ = vmem.arena_init_growing(&arena)
		a := vmem.arena_allocator(&arena)
		root, ok := LdtkJson_Parse(text, a)
		testing.expect(t, ok)
		out := LdtkJson_ToString(root, .Compact, a)
		testing.expectf(t, out == text, "%s written back byte for byte", path)
		vmem.arena_destroy(&arena)
	}
	cases := [?]struct {v: f64, s: string}{
		{0.3, "0.3"}, {0.35000000000000003, "0.35000000000000003"}, {1, "1"}, {-2.5, "-2.5"},
		{1e21, "1e+21"}, {1e-7, "1e-7"}, {0.000001, "0.000001"}, {123456789012, "123456789012"}, {0.1 + 0.2, "0.30000000000000004"},
	}
	for c in cases {
		b := strings.builder_make(context.temp_allocator)
		ldtk_js_number(&b, c.v)
		testing.expectf(t, strings.to_string(b) == c.s, "%v -> %s (want %s)", c.v, strings.to_string(b), c.s)
	}
	// edits: new keys / strings are encoded, untouched numbers keep their text
	arena: vmem.Arena
	_ = vmem.arena_init_growing(&arena)
	defer vmem.arena_destroy(&arena)
	a := vmem.arena_allocator(&arena)
	root, _ := LdtkJson_Parse(`{"a": 1.50, "b": [1,2]}`, a)
	LdtkJson_SetStr(root, "c", "say \"hi\"\tnow", a)
	LdtkJson_SetInt(root, "a", 1, a)
	testing.expect_value(t, LdtkJson_ToString(root, .Compact, a), `{ "a": 1, "b": [1,2], "c": "say \"hi\" now" }`)
}

@(test)
test_ldtk_rules_match_ldtk_and_save_is_identical :: proc(t: ^testing.T) {
	for path in LDTK_DOC_FIXTURES {
		doc, ok := Ldtk_Doc_Load(path)
		testing.expectf(t, ok, "load %s", path)
		if !ok do continue
		defer Ldtk_Doc_Destroy(doc)
		layers := 0
		for &lv, li in doc.levels {
			stored := make([][dynamic]Ldtk_DocTile, len(lv.layers), context.temp_allocator)
			for &ly, i in lv.layers {
				stored[i] = make([dynamic]Ldtk_DocTile, context.temp_allocator)
				append(&stored[i], ..ly.autoTiles[:])
			}
			Ldtk_Doc_ApplyRulesFull(doc, li)
			for &ly, i in lv.layers {
				d := Ldtk_Doc_LayerDef(doc, &ly)
				if d == nil || len(d.groups) == 0 do continue
				layers += 1
				same := len(stored[i]) == len(ly.autoTiles)
				if same {
					for s, k in stored[i] {
						g := ly.autoTiles[k]
						if s.px != g.px || s.src != g.src || s.t != g.t || s.f != g.f || s.rule != g.rule || s.coord != g.coord {
							same = false
							break
						}
					}
				}
				testing.expectf(t, same, "%s level %d layer %s: regenerated auto tiles match LDtk's", path, li, d.identifier)
			}
		}
		// every layer re-written from the typed data gives LDtk's bytes
		// (topdown.ldtk was written by a script, not by LDtk)
		if strings.has_suffix(path, "topdown.ldtk") do continue
		for &lv in doc.levels do for &ly in lv.layers do ly.cellsDirty = true
		// the table of contents and the neighbours recomputed: LDtk's too
		Ldtk_Doc_UpdateToc(doc)
		Ldtk_Doc_UpdateNeighbours(doc)
		proj, paths, texts := Ldtk_Doc_Serialize(doc, context.temp_allocator)
		testing.expectf(t, proj == read_text(path), "%s serialized identically", path)
		for p, i in paths {
			full, _ := filepath.join({filepath.dir(path, context.temp_allocator), p}, context.temp_allocator)
			testing.expectf(t, texts[i] == read_text(full), "%s serialized identically", p)
		}
	}
}

// Painting with incremental rule updates gives the same tiles as a full
// regeneration; undo / redo restore cells and tiles.
@(test)
test_ldtk_doc_paint_incremental_rules_and_undo :: proc(t: ^testing.T) {
	doc, ok := Ldtk_Doc_Load("tests/drive/fixtures/ldtk/topdown.ldtk")
	testing.expect(t, ok)
	if !ok do return
	defer Ldtk_Doc_Destroy(doc)
	li, layer := -1, -1
	for &lv, i in doc.levels {
		for &ly, j in lv.layers {
			d := Ldtk_Doc_LayerDef(doc, &ly)
			if d != nil && d.type == .IntGrid && len(d.values) > 0 {
				// an IntGrid layer that feeds rules
				deps := 0
				for &other in lv.layers do if Ldtk_RuleSource(doc, &lv, &other) == &ly do deps += 1
				if deps > 0 && li < 0 do li, layer = i, j
			}
		}
	}
	testing.expect(t, li >= 0)
	if li < 0 do return
	Ldtk_Doc_ApplyRulesFull(doc, li)
	before := Ldtk_Doc_ToText(doc)
	ly := &doc.levels[li].layers[layer]
	d := Ldtk_Doc_LayerDef(doc, ly)
	r := rand.create(7)
	context.random_generator = rand.default_random_generator(&r)
	Ldtk_Doc_BeginCells(doc, li, layer, "Paint")
	for _ in 0 ..< 60 {
		cx := rand.int_max(ly.cWid)
		cy := rand.int_max(ly.cHei)
		v := rand.int_max(3) == 0 ? 0 : d.values[rand.int_max(len(d.values))].value
		if Ldtk_Doc_SetIntGrid(doc, li, layer, cx, cy, v) do Ldtk_Doc_ApplyRules(doc, li, layer, cx, cy, cx, cy)
	}
	Ldtk_Doc_EndCells(doc)
	testing.expect_value(t, len(doc.undo), 1)
	painted := Ldtk_Doc_ToText(doc)
	// incremental == full
	incr := make([][dynamic]Ldtk_DocTile, len(doc.levels[li].layers), context.temp_allocator)
	for &l, i in doc.levels[li].layers {
		incr[i] = make([dynamic]Ldtk_DocTile, context.temp_allocator)
		append(&incr[i], ..l.autoTiles[:])
	}
	Ldtk_Doc_ApplyRulesFull(doc, li)
	for &l, i in doc.levels[li].layers {
		same := len(l.autoTiles) == len(incr[i])
		if same do for tl, k in l.autoTiles do if tl.px != incr[i][k].px || tl.t != incr[i][k].t || tl.rule != incr[i][k].rule || tl.f != incr[i][k].f {
			same = false
			break
		}
		testing.expectf(t, same, "layer %d: incremental rules == full regeneration (%d vs %d tiles)", i, len(incr[i]), len(l.autoTiles))
	}
	testing.expect(t, painted != before)
	testing.expect(t, Ldtk_Doc_Undo(doc))
	testing.expect(t, Ldtk_Doc_ToText(doc) == before, "undo restores the cells and tiles")
	testing.expect(t, Ldtk_Doc_Redo(doc))
	testing.expect(t, Ldtk_Doc_ToText(doc) == painted, "redo paints again")
	// tiles: set, stack, clear
	for &l, j in doc.levels[li].layers {
		ld := Ldtk_Doc_LayerDef(doc, &l)
		if ld == nil || ld.type != .Tiles do continue
		Ldtk_Doc_BeginCells(doc, li, j, "Tiles")
		testing.expect(t, Ldtk_Doc_SetTile(doc, li, j, 1, 1, 5))
		testing.expect(t, Ldtk_Doc_SetTile(doc, li, j, 1, 1, 6, 1, true))
		testing.expect_value(t, len(Ldtk_Doc_TilesAt(&l, 1, 1)), 2)
		testing.expect(t, !Ldtk_Doc_SetTile(doc, li, j, 1, 1, 6, 1, true))
		testing.expect(t, Ldtk_Doc_SetTile(doc, li, j, 1, 1, -1))
		testing.expect_value(t, len(Ldtk_Doc_TilesAt(&l, 1, 1)), 0)
		Ldtk_Doc_EndCells(doc)
		break
	}
	// level / project checkpoints
	text0 := Ldtk_Doc_ToText(doc)
	Ldtk_Doc_Checkpoint(doc, li, "Rename")
	LdtkJson_SetStr(doc.levels[li].obj, "identifier", "Zz_Renamed", doc.allocator)
	Ldtk_Doc_Touch(doc)
	testing.expect_value(t, Ldtk_Doc_LevelName(doc, li), "Zz_Renamed")
	testing.expect(t, Ldtk_Doc_Undo(doc))
	testing.expect(t, Ldtk_Doc_ToText(doc) == text0)
	testing.expect(t, Ldtk_Doc_Redo(doc))
	testing.expect_value(t, Ldtk_Doc_LevelName(doc, li), "Zz_Renamed")
	Ldtk_Doc_Checkpoint(doc, -1, "Defs")
	LdtkJson_SetInt(doc.root, "defaultGridSize", 99, doc.allocator)
	testing.expect(t, Ldtk_Doc_Undo(doc))
	testing.expect_value(t, LdtkJson_Int(doc.root, "defaultGridSize"), 16)
	testing.expect_value(t, Ldtk_Doc_LevelName(doc, li), "Zz_Renamed")
}

@(test)
test_ldtk_doc_external_levels_save :: proc(t: ^testing.T) {
	doc, ok := Ldtk_Doc_Load("tests/drive/fixtures/ldtk_editor/SeparateLevelFiles.ldtk")
	testing.expect(t, ok)
	if !ok do return
	defer Ldtk_Doc_Destroy(doc)
	testing.expect_value(t, len(doc.levels), 3)
	testing.expect(t, doc.levels[1].extRoot != nil)
	testing.expect(t, len(doc.levels[1].layers) > 0)
	dir := fmt.tprintf("%s/ore_ldtk_doc_zz", os.get_env("TMPDIR", context.temp_allocator))
	_ = os.make_directory(dir)
	out := fmt.tprintf("%s/SeparateLevelFiles.ldtk", dir)
	testing.expect(t, Ldtk_Doc_Save(doc, out))
	again, ok2 := Ldtk_Doc_Load(out)
	testing.expect(t, ok2)
	if ok2 {
		testing.expect(t, Ldtk_Doc_ToText(again) == Ldtk_Doc_ToText(doc))
		// paint a level; only it is marked for writing
		for &ly, j in again.levels[1].layers {
			d := Ldtk_Doc_LayerDef(again, &ly)
			if d != nil && d.type == .IntGrid {
				Ldtk_Doc_SetIntGrid(again, 1, j, 0, 0, 1)
				break
			}
		}
		testing.expect(t, again.levels[1].dirty && !again.levels[0].dirty)
		testing.expect(t, Ldtk_Doc_Save(again))
		testing.expect(t, !again.levels[1].dirty && !again.modified)
		Ldtk_Doc_Destroy(again)
	}
	os.remove_all(dir)
}

// Building a project from scratch with the editing API; the runtime reader
// (Ldtk_ParseProject) loads the result.
@(test)
test_ldtk_doc_new_project_defs_entities_levels :: proc(t: ^testing.T) {
	doc, ok := Ldtk_Doc_New("/tmp/ore_zz_new.ldtk")
	testing.expect(t, ok)
	if !ok do return
	defer Ldtk_Doc_Destroy(doc)
	testing.expect_value(t, len(doc.levels), 1)
	testing.expect_value(t, len(doc.layerDefs), 2) // Collisions (top), Entities
	testing.expect_value(t, doc.layerDefs[0].identifier, "Collisions")
	testing.expect_value(t, len(doc.levels[0].layers), 2)
	col := doc.layerDefs[0].uid
	// a tileset (no image: no opaque data), an auto layer reading Collisions
	ts := Ldtk_Doc_AddTileset(doc, "atlas/tiles_zz.png", {64, 64}, 16)
	auto := Ldtk_Doc_AddLayerDef(doc, .AutoLayer, "Walls", ts)
	d := &doc.layerDefs[Ldtk_Doc_LayerDefIndex(doc, auto)]
	LdtkJson_SetInt(d.obj, "autoSourceLayerDefUid", col, doc.allocator)
	Ldtk_Doc_LayerDefChanged(doc, auto)
	g := Ldtk_Doc_AddRuleGroup(doc, auto, "Walls")
	r := Ldtk_Doc_AddRule(doc, auto, g, 3, 1, 5)
	testing.expect(t, r > 0)
	// paint: one wall -> one auto tile (tile 5 at the cell)
	li := 0
	cl := -1
	for &ly, j in doc.levels[li].layers do if Ldtk_Doc_LayerDef(doc, &ly).uid == col do cl = j
	testing.expect(t, cl >= 0)
	testing.expect(t, Ldtk_Doc_SetIntGrid(doc, li, cl, 3, 4, 1))
	Ldtk_Doc_ApplyRules(doc, li, cl, 3, 4, 3, 4)
	wl := Ldtk_Doc_LevelLayer(doc, &doc.levels[li], auto)
	testing.expect_value(t, len(wl.autoTiles), 1)
	if len(wl.autoTiles) == 1 {
		testing.expect_value(t, wl.autoTiles[0].t, 5)
		testing.expect_value(t, wl.autoTiles[0].px, [2]i32{48, 64})
		testing.expect_value(t, wl.autoTiles[0].src, [2]i32{16, 16})
	}
	// the rule now forbids a wall above: (3,4) still matches, (3,5) doesn't
	Ldtk_Doc_SetRuleCell(doc, r, 1, 0, -1)
	Ldtk_Doc_SetIntGrid(doc, li, cl, 3, 5, 1)
	Ldtk_Doc_ApplyRules(doc, li, cl, 3, 5, 3, 5)
	wl = Ldtk_Doc_LevelLayer(doc, &doc.levels[li], auto)
	testing.expect_value(t, len(wl.autoTiles), 1)
	// entities with fields
	ent := Ldtk_Doc_AddEntityDef(doc, "chest")
	testing.expect_value(t, Ldtk_Doc_EntityDef(doc, ent).identifier, "Chest")
	gold := Ldtk_Doc_AddFieldDef(doc, ent, "F_Int", "gold")
	en := Ldtk_Doc_AddEnum(doc, "Rarity")
	testing.expect(t, Ldtk_Doc_AddEnumValue(doc, en, "common"))
	testing.expect(t, Ldtk_Doc_AddEnumValue(doc, en, "Rare"))
	testing.expect(t, !Ldtk_Doc_AddEnumValue(doc, en, "Rare"))
	Ldtk_Doc_AddFieldDef(doc, ent, fmt.tprintf("F_Enum(%d)", en), "rarity")
	el := -1
	for &ly, j in doc.levels[li].layers do if Ldtk_Doc_LayerDef(doc, &ly).type == .Entities do el = j
	e1 := Ldtk_Doc_AddEntity(doc, li, el, ent, {40, 56})
	testing.expect(t, e1 != nil)
	fis := LdtkJson_Arr(e1, "fieldInstances")
	testing.expect_value(t, len(fis), 2)
	testing.expect(t, Ldtk_Doc_SetFieldValue(doc, fis[0], "25"))
	testing.expect(t, !Ldtk_Doc_SetFieldValue(doc, fis[0], "lots"))
	testing.expect(t, Ldtk_Doc_SetFieldValue(doc, fis[1], "Rare"))
	testing.expect(t, !Ldtk_Doc_SetFieldValue(doc, fis[1], "Epic"))
	testing.expect_value(t, Ldtk_FieldText(fis[0]), "25")
	testing.expect_value(t, LdtkJson_ToString(LdtkJson_Get(fis[0], "realEditorValues"), .Minified, context.temp_allocator), `[{"id":"V_Int","params":[25]}]`)
	_ = gold
	Ldtk_Doc_MoveEntity(doc, li, el, e1, {72, 88})
	testing.expect_value(t, LdtkJson_ToString(LdtkJson_Get(e1, "__grid"), .Minified, context.temp_allocator), "[4,5]")
	testing.expect(t, Ldtk_Doc_EntityAt(doc, li, el, {75, 90}) == e1)
	// levels: a second one to the right is a neighbour; resize keeps cells
	l2 := Ldtk_Doc_AddLevel(doc, 0, {256, 0})
	testing.expect_value(t, l2, 1)
	testing.expect_value(t, Ldtk_Doc_FreeLevelSpot(doc, 0, {256, 0}, {256, 256}, 1), [2]int{512, 0})
	n0 := LdtkJson_Arr(doc.levels[0].obj, "__neighbours")
	testing.expect_value(t, len(n0), 1)
	if len(n0) == 1 do testing.expect_value(t, LdtkJson_Str(n0[0], "dir"), "e")
	testing.expect(t, Ldtk_Doc_RenameLevel(doc, 1, "Cave"))
	testing.expect(t, !Ldtk_Doc_RenameLevel(doc, 0, "Cave"))
	Ldtk_Doc_ResizeLevel(doc, 0, {128, 128})
	cly := &doc.levels[0].layers[cl]
	testing.expect_value(t, cly.cWid, 8)
	testing.expect_value(t, Ldtk_Doc_GetIntGrid(cly, 3, 4), 1)
	// layer order follows into every level
	testing.expect(t, Ldtk_Doc_MoveLayerDef(doc, auto, 1))
	testing.expect_value(t, LdtkJson_Int(doc.levels[1].layers[1].obj, "layerDefUid"), auto)
	// the runtime reader loads it
	text := Ldtk_Doc_ToText(doc)
	proj, pok := Ldtk_ParseProject(transmute([]u8)text)
	testing.expect(t, pok)
	if pok {
		testing.expect_value(t, len(proj.levels), 2)
		testing.expect_value(t, proj.levels[1].identifier, "Cave")
		Ldtk_DestroyProject(proj)
	}
	// remove things
	Ldtk_Doc_RemoveEntityDef(doc, ent)
	testing.expect_value(t, len(Ldtk_Doc_Entities(doc, li, el)), 0)
	testing.expect(t, Ldtk_Doc_RemoveLayerDef(doc, auto))
	testing.expect_value(t, len(doc.levels[0].layers), 2)
	testing.expect(t, Ldtk_Doc_RemoveLevel(doc, 1))
	testing.expect_value(t, len(doc.levels), 1)
}

@(test)
test_ldtk_doc_tile_data_animation_terrain :: proc(t: ^testing.T) {
	// the format
	anim, ok := Ldtk_ParseTileAnim("solid\nanim=12, 13,14\nfps=4", context.temp_allocator)
	testing.expect(t, ok)
	testing.expect_value(t, len(anim.frames), 3)
	testing.expect_value(t, anim.fps, 4)
	testing.expect_value(t, Ldtk_TileAnimFrame(anim, 0.3), 13)
	testing.expect_value(t, Ldtk_TileAnimFrame(anim, 0.8), 12)
	_, one := Ldtk_ParseTileAnim("anim=5", context.temp_allocator)
	testing.expect(t, !one)

	doc, dok := Ldtk_Doc_New("/tmp/ore_zz_tiles.ldtk")
	testing.expect(t, dok)
	if !dok do return
	defer Ldtk_Doc_Destroy(doc)
	ts := Ldtk_Doc_AddTileset(doc, "atlas/tiles_zz.png", {64, 64}, 16)
	// custom data keeps other lines; animation lines are replaced
	Ldtk_Doc_SetTileCustomData(doc, ts, 3, "solid")
	Ldtk_Doc_SetTileAnimation(doc, ts, 3, {3, 4, 5}, 6)
	testing.expect_value(t, Ldtk_Doc_TileCustomData(doc, ts, 3), "solid\nanim=3,4,5\nfps=6")
	Ldtk_Doc_SetTileAnimation(doc, ts, 3, {3, 7}, 8)
	testing.expect_value(t, Ldtk_Doc_TileCustomData(doc, ts, 3), "solid\nanim=3,7")
	testing.expect(t, 3 in Ldtk_Doc_Tileset(doc, ts).anims)
	Ldtk_Doc_SetTileAnimation(doc, ts, 3, nil, 0)
	testing.expect_value(t, Ldtk_Doc_TileCustomData(doc, ts, 3), "solid")
	Ldtk_Doc_SetTileCustomData(doc, ts, 1, "anim=1,2")
	testing.expect_value(t, len(LdtkJson_Arr(Ldtk_Doc_Tileset(doc, ts).obj, "customData")), 2)
	testing.expect_value(t, LdtkJson_Int(LdtkJson_Arr(Ldtk_Doc_Tileset(doc, ts).obj, "customData")[0], "tileId"), 1)
	// enum tags
	en := Ldtk_Doc_AddEnum(doc, "Ground")
	Ldtk_Doc_AddEnumValue(doc, en, "Ice")
	LdtkJson_SetInt(Ldtk_Doc_Tileset(doc, ts).obj, "tagsSourceEnumUid", en, doc.allocator)
	Ldtk_Doc_SetTileTag(doc, ts, 9, "Ice", true)
	Ldtk_Doc_SetTileTag(doc, ts, 2, "Ice", true)
	testing.expect(t, Ldtk_Doc_TileHasTag(doc, ts, 9, "Ice"))
	Ldtk_Doc_SetTileTag(doc, ts, 9, "Ice", false)
	testing.expect(t, !Ldtk_Doc_TileHasTag(doc, ts, 9, "Ice"))
	// the runtime reads the animation and the tags
	proj, pok := Ldtk_ParseProject(transmute([]u8)Ldtk_Doc_ToText(doc))
	testing.expect(t, pok)
	if pok {
		rts := &proj.tilesets[0]
		testing.expect(t, 1 in rts.anims)
		testing.expect_value(t, Ldtk_TilesetTileSrc(rts, 5), [2]f32{16, 16})
		testing.expect_value(t, len(rts.enumTags[2]), 1)
		Ldtk_DestroyProject(proj)
	}
	// terrain: a 3x3 block over Collisions value 1 through an auto layer
	col := doc.layerDefs[0].uid
	auto := Ldtk_Doc_AddLayerDef(doc, .AutoLayer, "Ground", ts)
	LdtkJson_SetInt(doc.layerDefs[Ldtk_Doc_LayerDefIndex(doc, auto)].obj, "autoSourceLayerDefUid", col, doc.allocator)
	Ldtk_Doc_LayerDefChanged(doc, auto)
	g := Ldtk_Doc_AddTerrainRules(doc, auto, 1, {0, 1, 2, 4, 5, 6, 8, 9, 10})
	testing.expect(t, g > 0)
	lv := &doc.levels[0]
	cl := -1
	for &ly, j in lv.layers do if Ldtk_Doc_LayerDef(doc, &ly).uid == col do cl = j
	for y in 2 ..= 4 do for x in 2 ..= 4 do Ldtk_Doc_SetIntGrid(doc, 0, cl, x, y, 1)
	Ldtk_Doc_ApplyRules(doc, 0, cl, 2, 2, 4, 4)
	gl := Ldtk_Doc_LevelLayer(doc, lv, auto)
	at :: proc(ly: ^Ldtk_DocLayer, cx, cy: int) -> i32 {
		for tl in ly.autoTiles do if int(tl.coord) == cx + cy * ly.cWid do return tl.t
		return -1
	}
	testing.expect_value(t, len(gl.autoTiles), 9)
	testing.expect_value(t, at(gl, 2, 2), 0)
	testing.expect_value(t, at(gl, 3, 2), 1)
	testing.expect_value(t, at(gl, 4, 2), 2)
	testing.expect_value(t, at(gl, 2, 3), 4)
	testing.expect_value(t, at(gl, 3, 3), 5)
	testing.expect_value(t, at(gl, 4, 4), 10)
}

@(test)
test_ldtk_doc_world_layout :: proc(t: ^testing.T) {
	doc, ok := Ldtk_Doc_New("/tmp/ore_zz_layout.ldtk")
	testing.expect(t, ok)
	if !ok do return
	defer Ldtk_Doc_Destroy(doc)
	Ldtk_Doc_AddLevel(doc, 0, {600, 40}, {128, 64})
	// linear: computed from the order (48 px apart), -1 stored
	Ldtk_Doc_SetWorldLayout(doc, 0, "LinearHorizontal")
	testing.expect_value(t, LdtkJson_Int(doc.levels[1].obj, "worldX"), -1)
	testing.expect_value(t, Ldtk_Doc_LevelPos(doc, 1), [2]int{256 + 48, 0})
	testing.expect_value(t, len(LdtkJson_Arr(doc.levels[0].obj, "__neighbours")), 0)
	// back to free: the computed positions are written
	Ldtk_Doc_SetWorldLayout(doc, 0, "Free")
	testing.expect_value(t, LdtkJson_Int(doc.levels[1].obj, "worldX"), 304)
	// GridVania snaps to the world grid
	Ldtk_Doc_SetWorldLayout(doc, 0, "GridVania")
	testing.expect_value(t, Ldtk_Doc_LevelPos(doc, 1), [2]int{256, 0})
	testing.expect_value(t, LdtkJson_Str(doc.root, "worldLayout"), "GridVania")
}

@(test)
test_ldtk_doc_selection_move_copy_delete :: proc(t: ^testing.T) {
	doc, ok := Ldtk_Doc_New("/tmp/ore_zz_sel.ldtk")
	testing.expect(t, ok)
	if !ok do return
	defer Ldtk_Doc_Destroy(doc)
	col, ents := -1, -1
	for &ly, j in doc.levels[0].layers {
		d := Ldtk_Doc_LayerDef(doc, &ly)
		if d.type == .IntGrid do col = j
		if d.type == .Entities do ents = j
	}
	for x in 1 ..= 3 do Ldtk_Doc_SetIntGrid(doc, 0, col, x, 1, 1)
	chest := Ldtk_Doc_AddEntityDef(doc, "Chest")
	e1 := Ldtk_Doc_AddEntity(doc, 0, ents, chest, {40, 24})
	sel: Ldtk_Selection
	defer Ldtk_Selection_Destroy(&sel)
	// a rectangle over cells (1..3, 1) and the chest's cell (2, 1)
	Ldtk_Doc_SelectRect(doc, 0, &sel, {16, 16, 48, 16})
	testing.expectf(t, len(sel.cells) == 3, "cells %v", sel.cells)
	testing.expect_value(t, len(sel.entities), 1)
	// half a cell: cells can't move
	testing.expect(t, !Ldtk_Doc_SelectionCanMove(doc, 0, &sel, {8, 0}))
	// move two cells down
	testing.expect(t, Ldtk_Doc_MoveSelection(doc, 0, &sel, {0, 32}))
	cl := &doc.levels[0].layers[col]
	testing.expect_value(t, Ldtk_Doc_GetIntGrid(cl, 2, 1), 0)
	testing.expect_value(t, Ldtk_Doc_GetIntGrid(cl, 2, 3), 1)
	testing.expect_value(t, LdtkJson_ToString(LdtkJson_Get(e1, "px"), .Minified, context.temp_allocator), "[40,56]")
	// copy one cell right: both remain, the selection is the copy
	testing.expect(t, Ldtk_Doc_MoveSelection(doc, 0, &sel, {16, 0}, true))
	testing.expect_value(t, Ldtk_Doc_GetIntGrid(cl, 1, 3), 1)
	testing.expect_value(t, Ldtk_Doc_GetIntGrid(cl, 4, 3), 1)
	testing.expect_value(t, len(Ldtk_Doc_Entities(doc, 0, ents)), 2)
	testing.expect(t, sel.entities[0].obj != e1)
	testing.expect(t, LdtkJson_Str(sel.entities[0].obj, "iid") != LdtkJson_Str(e1, "iid"))
	// delete the copy
	Ldtk_Doc_DeleteSelection(doc, 0, &sel)
	testing.expect_value(t, Ldtk_Doc_GetIntGrid(cl, 4, 3), 0)
	testing.expect_value(t, Ldtk_Doc_GetIntGrid(cl, 1, 3), 1)
	testing.expect_value(t, len(Ldtk_Doc_Entities(doc, 0, ents)), 1)
	testing.expect(t, Ldtk_Selection_Empty(&sel))
	// select all in the IntGrid layer
	Ldtk_Doc_SelectAll(doc, 0, &sel, col) // the copy overlapped cells 2-3, so only cell 1 is left
	testing.expect_value(t, len(sel.cells), 1)
	testing.expect_value(t, len(sel.entities), 0)
	// another Entities layer requiring a tag: the chest (no tags) can't go
	l2 := Ldtk_Doc_AddLayerDef(doc, .Entities, "Items")
	tags := LdtkJson_New(.Array, doc.allocator)
	append(&tags.items, LdtkJson_NewString("item", doc.allocator))
	LdtkJson_Set(doc.layerDefs[Ldtk_Doc_LayerDefIndex(doc, l2)].obj, "requiredTags", tags, doc.allocator)
	Ldtk_Doc_RefreshDefs(doc)
	el2 := -1
	ents = -1
	for &ly, j in doc.levels[0].layers {
		d := Ldtk_Doc_LayerDef(doc, &ly)
		if d.uid == l2 do el2 = j
		else if d.type == .Entities do ents = j
	}
	testing.expect(t, !Ldtk_Doc_EntityLayerAllowed(doc, 0, el2, e1))
	testing.expect(t, Ldtk_Doc_MoveEntityToLayer(doc, 0, ents, el2, e1))
	testing.expect_value(t, len(Ldtk_Doc_Entities(doc, 0, el2)), 1)
	testing.expect_value(t, len(Ldtk_Doc_Entities(doc, 0, ents)), 0)
}

@(test)
test_ldtk_doc_clipboard :: proc(t: ^testing.T) {
	doc, ok := Ldtk_Doc_New("/tmp/ore_zz_clip.ldtk")
	testing.expect(t, ok)
	if !ok do return
	defer Ldtk_Doc_Destroy(doc)
	col, ents := -1, -1
	for &ly, j in doc.levels[0].layers {
		d := Ldtk_Doc_LayerDef(doc, &ly)
		if d.type == .IntGrid do col = j
		if d.type == .Entities do ents = j
	}
	Ldtk_Doc_SetIntGrid(doc, 0, col, 2, 2, 1)
	Ldtk_Doc_SetIntGrid(doc, 0, col, 3, 2, 1)
	chest := Ldtk_Doc_AddEntityDef(doc, "Chest")
	Ldtk_Doc_AddEntity(doc, 0, ents, chest, {48, 48})
	sel: Ldtk_Selection
	defer Ldtk_Selection_Destroy(&sel)
	clip: Ldtk_Clipboard
	defer Ldtk_Clipboard_Destroy(&clip)
	Ldtk_Doc_SelectAll(doc, 0, &sel)
	testing.expect_value(t, len(sel.cells) + len(sel.entities), 3)
	Ldtk_Doc_CopySelection(doc, 0, &sel, &clip)
	testing.expect_value(t, clip.origin, [2]int{32, 32})
	// paste with the top-left at (128, 96): cells (8,6),(9,6), the chest at px (144,112)
	testing.expect(t, Ldtk_Doc_Paste(doc, 0, &clip, {128, 96}, &sel))
	cl := &doc.levels[0].layers[col]
	testing.expect_value(t, Ldtk_Doc_GetIntGrid(cl, 8, 6), 1)
	testing.expect_value(t, Ldtk_Doc_GetIntGrid(cl, 9, 6), 1)
	testing.expect_value(t, len(Ldtk_Doc_Entities(doc, 0, ents)), 2)
	testing.expect_value(t, LdtkJson_ToString(LdtkJson_Get(sel.entities[0].obj, "px"), .Minified, context.temp_allocator), "[144,112]")
	testing.expect_value(t, len(sel.cells), 2)
}

@(test)
test_ldtk_doc_duplicate_and_order_levels :: proc(t: ^testing.T) {
	doc, ok := Ldtk_Doc_Load("tests/drive/fixtures/ldtk_editor/SeparateLevelFiles.ldtk")
	testing.expect(t, ok)
	if !ok do return
	defer Ldtk_Doc_Destroy(doc)
	n := len(doc.levels)
	cells := 0
	for &ly in doc.levels[0].layers do for v in ly.intGrid do if v != 0 do cells += 1
	li := Ldtk_Doc_DuplicateLevel(doc, 0)
	testing.expect_value(t, li, 1)
	testing.expect_value(t, len(doc.levels), n + 1)
	dup := &doc.levels[1]
	testing.expect(t, dup.extRoot != nil)
	testing.expect(t, LdtkJson_Str(dup.obj, "iid") != LdtkJson_Str(doc.levels[0].obj, "iid"))
	testing.expect(t, LdtkJson_Str(dup.obj, "externalRelPath") != LdtkJson_Str(doc.levels[0].obj, "externalRelPath"))
	c2 := 0
	for &ly in dup.layers do for v in ly.intGrid do if v != 0 do c2 += 1
	testing.expect_value(t, c2, cells)
	// no overlap with the others
	p := Ldtk_Doc_LevelPos(doc, 1)
	s := Ldtk_Doc_LevelSize(doc, 1)
	testing.expect_value(t, Ldtk_Doc_FreeLevelSpot(doc, 0, p, s, 1) == p, false) // (the spot is taken now: by itself)
	// order
	name := Ldtk_Doc_LevelName(doc, 1)
	testing.expect_value(t, Ldtk_Doc_MoveLevelOrder(doc, 1, -1), 0)
	testing.expect_value(t, Ldtk_Doc_LevelName(doc, 0), name)
	testing.expect_value(t, LdtkJson_Str(doc.worlds[0].levelsArr.items[0], "identifier"), name)
	// it saves and loads back
	proj, paths, texts := Ldtk_Doc_Serialize(doc, context.temp_allocator)
	testing.expect_value(t, len(paths), n + 1)
	_ = proj
	_ = texts
}

@(test)
test_ldtk_doc_tile_stacking_saved_selections_override :: proc(t: ^testing.T) {
	doc, ok := Ldtk_Doc_New("/tmp/ore_zz_tiles2.ldtk")
	testing.expect(t, ok)
	if !ok do return
	defer Ldtk_Doc_Destroy(doc)
	ts := Ldtk_Doc_AddTileset(doc, "atlas/a_zz.png", {64, 64}, 16)
	ts2 := Ldtk_Doc_AddTileset(doc, "atlas/b_zz.png", {32, 32}, 16)
	// tile 3 is opaque
	tsd := Ldtk_Doc_Tileset(doc, ts)
	cache := LdtkJson_New(.Object, doc.allocator)
	LdtkJson_SetStr(cache, "opaqueTiles", "0001000000000000", doc.allocator)
	LdtkJson_SetStr(cache, "averageColors", "", doc.allocator)
	LdtkJson_Set(tsd.obj, "cachedPixelData", cache, doc.allocator)
	Ldtk_Doc_RefreshDefs(doc)
	tl := Ldtk_Doc_AddLayerDef(doc, .Tiles, "Deco", ts)
	j := -1
	for &ly, k in doc.levels[0].layers do if Ldtk_Doc_LayerDef(doc, &ly).uid == tl do j = k
	ly := &doc.levels[0].layers[j]
	Ldtk_Doc_AddGridTile(doc, 0, j, 1, 1, 0, 0, true)
	Ldtk_Doc_AddGridTile(doc, 0, j, 1, 1, 1, 0, true)
	testing.expect_value(t, len(Ldtk_Doc_TilesAt(ly, 1, 1)), 2)
	// the same tile again moves to the top
	Ldtk_Doc_AddGridTile(doc, 0, j, 1, 1, 0, 0, true)
	st := Ldtk_Doc_TilesAt(ly, 1, 1)
	testing.expect_value(t, len(st), 2)
	testing.expect_value(t, st[1].t, 0)
	// an opaque tile replaces the stack
	Ldtk_Doc_AddGridTile(doc, 0, j, 1, 1, 3, 0, true)
	testing.expect_value(t, len(Ldtk_Doc_TilesAt(ly, 1, 1)), 1)
	Ldtk_Doc_AddGridTile(doc, 0, j, 1, 1, 2, 0, true)
	testing.expect(t, Ldtk_Doc_RemoveTopTile(doc, 0, j, 1, 1))
	testing.expect_value(t, Ldtk_Doc_TilesAt(ly, 1, 1)[0].t, 3)
	// saved selections
	testing.expect(t, Ldtk_Doc_SaveTileSelection(doc, ts, {4, 5, 8, 9}, false))
	ids, random, found := Ldtk_Doc_SavedSelectionFor(doc, ts, 8)
	testing.expect(t, found && !random && len(ids) == 4)
	testing.expect(t, Ldtk_Doc_SaveTileSelection(doc, ts, {9, 10}, true)) // shares 9: replaces
	_, _, found = Ldtk_Doc_SavedSelectionFor(doc, ts, 4)
	testing.expect(t, !found)
	ids, random, found = Ldtk_Doc_SavedSelectionFor(doc, ts, 10)
	testing.expect(t, found && random)
	testing.expect(t, !Ldtk_Doc_SaveTileSelection(doc, ts, {7}, false)) // one tile: not saved
	// override: tile 3's source follows the other tileset (2 tiles per row)
	Ldtk_Doc_SetLayerTilesetOverride(doc, 0, j, ts2)
	testing.expect_value(t, LdtkJson_Int(ly.obj, "overrideTilesetUid"), ts2)
	testing.expect_value(t, Ldtk_Doc_TilesAt(ly, 1, 1)[0].src, [2]i32{16, 16})
	Ldtk_Doc_SetLayerTilesetOverride(doc, 0, j, -1)
	testing.expect(t, LdtkJson_IsNull(ly.obj, "overrideTilesetUid"))
	testing.expect_value(t, Ldtk_Doc_TilesAt(ly, 1, 1)[0].src, [2]i32{48, 0})
}

@(test)
test_ldtk_doc_field_values_arrays_refs :: proc(t: ^testing.T) {
	doc, ok := Ldtk_Doc_New("/tmp/ore_zz_fields.ldtk")
	testing.expect(t, ok)
	if !ok do return
	defer Ldtk_Doc_Destroy(doc)
	a := doc.allocator
	ents := -1
	for &ly, j in doc.levels[0].layers do if Ldtk_Doc_LayerDef(doc, &ly).type == .Entities do ents = j
	door := Ldtk_Doc_AddEntityDef(doc, "Door")
	hp := Ldtk_Doc_AddFieldDef(doc, door, "F_Int", "hp")
	name := Ldtk_Doc_AddFieldDef(doc, door, "F_String", "code")
	links := Ldtk_Doc_AddFieldDef(doc, door, "F_EntityRef", "links")
	path := Ldtk_Doc_AddFieldDef(doc, door, "F_Point", "path")
	col := Ldtk_Doc_AddFieldDef(doc, door, "F_Color", "tint")
	file := Ldtk_Doc_AddFieldDef(doc, door, "F_Path", "sound")
	icon := Ldtk_Doc_AddFieldDef(doc, door, "F_Tile", "icon")
	fdOf :: proc(doc: ^Ldtk_Doc, uid: int) -> ^LdtkJson {return Ldtk_Doc_FieldDef(doc, uid)}
	// hp: default 10, min 0 max 50
	testing.expect(t, Ldtk_Doc_FieldDefDefaultSet(doc, fdOf(doc, hp), "10"))
	LdtkJson_SetInt(fdOf(doc, hp), "max", 50, a)
	// code: regex /^[A-Z]{3}$/
	LdtkJson_SetStr(fdOf(doc, name), "regex", "/^[A-Z]{3}$/", a)
	// links: an array, symmetrical, any entity
	LdtkJson_SetBool(fdOf(doc, links), "isArray", true, a)
	LdtkJson_SetBool(fdOf(doc, links), "symmetricalRef", true, a)
	LdtkJson_SetStr(fdOf(doc, links), "allowedRefs", "Any", a)
	// path: array of points
	LdtkJson_SetBool(fdOf(doc, path), "isArray", true, a)
	// tint: the smart colour
	LdtkJson_SetBool(fdOf(doc, col), "useForSmartColor", true, a)
	// sound: .ogg / .wav only
	exts := LdtkJson_New(.Array, a)
	append(&exts.items, LdtkJson_NewString("ogg", a), LdtkJson_NewString(".wav", a))
	LdtkJson_Set(fdOf(doc, file), "acceptFileTypes", exts, a)
	LdtkJson_SetInt(fdOf(doc, icon), "tilesetUid", 7, a)
	LdtkJson_SetStr(fdOf(doc, icon), "editorDisplayMode", "EntityTile", a)
	Ldtk_Doc_RefreshDefs(doc)
	d1 := Ldtk_Doc_AddEntity(doc, 0, ents, door, {16, 16})
	d2 := Ldtk_Doc_AddEntity(doc, 0, ents, door, {64, 16})
	fi :: proc(ent: ^LdtkJson, uid: int) -> ^LdtkJson {
		for f in LdtkJson_Arr(ent, "fieldInstances") do if LdtkJson_Int(f, "defUid", -1) == uid do return f
		return nil
	}
	v, null := Ldtk_Doc_FieldText(doc, fi(d1, hp), 0)
	testing.expect(t, !null && v == "10")
	testing.expect(t, Ldtk_Doc_SetFieldRaw(doc, fi(d1, hp), 0, "99"))
	v, _ = Ldtk_Doc_FieldText(doc, fi(d1, hp), 0)
	testing.expect_value(t, v, "50")
	testing.expect(t, Ldtk_Doc_SetFieldRaw(doc, fi(d1, hp), 0, "", true)) // back to the default
	v, _ = Ldtk_Doc_FieldText(doc, fi(d1, hp), 0)
	testing.expect_value(t, v, "10")
	testing.expect(t, !Ldtk_Doc_SetFieldRaw(doc, fi(d1, name), 0, "ab1"))
	testing.expect(t, Ldtk_Doc_SetFieldRaw(doc, fi(d1, name), 0, "ABC"))
	testing.expect(t, !Ldtk_Doc_SetFieldRaw(doc, fi(d1, file), 0, "sfx/door.mp3"))
	testing.expect(t, Ldtk_Doc_SetFieldRaw(doc, fi(d1, file), 0, "sfx/door.WAV"))
	// points: a path of two
	p0 := Ldtk_Doc_FieldArrayAdd(doc, fi(d1, path))
	p1 := Ldtk_Doc_FieldArrayAdd(doc, fi(d1, path))
	Ldtk_Doc_SetFieldRaw(doc, fi(d1, path), p0, "3,4")
	Ldtk_Doc_SetFieldRaw(doc, fi(d1, path), p1, "5,4")
	testing.expect_value(t, LdtkJson_ToString(LdtkJson_Get(fi(d1, path), "__value"), .Minified, context.temp_allocator), `[{"cx":3,"cy":4},{"cx":5,"cy":4}]`)
	testing.expect(t, Ldtk_Doc_FieldArrayMove(doc, fi(d1, path), 1, -1))
	testing.expect_value(t, LdtkJson_ToString(LdtkJson_Get(fi(d1, path), "__value"), .Minified, context.temp_allocator), `[{"cx":5,"cy":4},{"cx":3,"cy":4}]`)
	// a symmetrical reference: d1 -> d2 makes d2 -> d1
	r0 := Ldtk_Doc_FieldArrayAdd(doc, fi(d1, links))
	testing.expect(t, Ldtk_Doc_SetFieldRef(doc, fi(d1, links), r0, d1, LdtkJson_Str(d2, "iid")))
	back, _ := Ldtk_Doc_FieldText(doc, fi(d2, links), 0)
	testing.expect_value(t, back, LdtkJson_Str(d1, "iid"))
	rv := LdtkJson_Arr(fi(d1, links), "__value")
	testing.expect_value(t, len(rv), 1)
	testing.expect_value(t, LdtkJson_Str(rv[0], "levelIid"), LdtkJson_Str(doc.levels[0].obj, "iid"))
	// clearing it removes the way back
	testing.expect(t, Ldtk_Doc_SetFieldRef(doc, fi(d1, links), r0, d1, ""))
	testing.expect_value(t, Ldtk_Doc_FieldArrayLen(doc, fi(d2, links)), 0)
	ok1, _ := Ldtk_Doc_RefAllowed(doc, fdOf(doc, links), d1, 0, d1, 0)
	testing.expect(t, !ok1)
	// tile and smart colour
	testing.expect(t, Ldtk_Doc_SetFieldRaw(doc, fi(d1, icon), 0, "16,0,16,16"))
	testing.expect_value(t, LdtkJson_ToString(LdtkJson_Get(fi(d1, icon), "__value"), .Minified, context.temp_allocator), `{"tilesetUid":7,"x":16,"y":0,"w":16,"h":16}`)
	testing.expect_value(t, LdtkJson_ToString(LdtkJson_Get(fi(d1, icon), "__tile"), .Minified, context.temp_allocator), `{"tilesetUid":7,"x":16,"y":0,"w":16,"h":16}`)
	testing.expect(t, Ldtk_Doc_SetFieldRaw(doc, fi(d1, col), 0, "#FF8000"))
	Ldtk_Doc_EntitySmart(doc, d1)
	testing.expect_value(t, LdtkJson_Int(LdtkJson_Get(d1, "__tile"), "x"), 16) // the field's tile is the entity's
	testing.expect_value(t, LdtkJson_Str(d1, "__smartColor"), "#FF8000")
	testing.expect_value(t, LdtkJson_ToString(LdtkJson_Get(fi(d1, col), "realEditorValues"), .Minified, context.temp_allocator), `[{"id":"V_Int","params":[16744448]}]`)
}
