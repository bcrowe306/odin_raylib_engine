package engine

import "core:fmt"
import "core:math/rand"
import "core:mem"
import vmem "core:mem/virtual"
import os "osx"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import rl "vendor:raylib"

// ============================================================================
// Editable LDtk document (the level editor's model)
//
// Ldtk_Doc keeps the whole .ldtk (and its .ldtkl levels) as an ordered
// LdtkJson tree, so everything this engine does not know about is written
// back untouched. Per-layer cell data that the editor paints (IntGrid values,
// grid tiles) and the auto-layer tiles generated from rules are kept as typed
// arrays and written into the tree only while saving. Untouched layers are
// written from their original nodes, so a load followed by a save gives the
// same bytes LDtk wrote.
//
// Memory: the tree lives in the document's arena (doc.allocator); the typed
// definition caches in two arenas used in turn by Ldtk_Doc_RefreshDefs; cell
// arrays and undo entries on the heap (doc.heap). Ldtk_Doc_Destroy frees all.
//
// The auto-layer rule engine (ldtk_rules.odin) is a port of LDtk's own, so
// tiles generated here match the ones LDtk would generate.
// ============================================================================

LDTK_AUTO_LAYER_ANYTHING :: 1000001
LDTK_MAX_AUTO_PATTERN_SIZE :: 9
LDTK_UNDO_LIMIT :: 100

Ldtk_DocTile :: struct {
	px:    [2]i32,
	src:   [2]i32,
	t:     i32, // tile id
	coord: i32, // anchor cell (cx + cy * cWid)
	rule:  i32, // rule uid (auto tiles), -1 for grid tiles
	rank:  i32, // rule display rank (auto tiles sort key)
	seq:   i32, // order inside one (rank, coord)
	f:     u8,  // flip bits: 1 = X, 2 = Y
	a:     f64, // alpha
}

Ldtk_DocIntValue :: struct {
	value:      int,
	groupUid:   int,
	identifier: string,
	color:      rl.Color,
}

Ldtk_RuleChecker :: enum u8 {
	None,
	Horizontal,
	Vertical,
}

Ldtk_DocRule :: struct {
	obj:                 ^LdtkJson,
	uid:                 int,
	active:              bool,
	size:                int,
	pattern:             []i32,
	tileRects:           [][]i32,
	chance:              f64,
	breakOnMatch:        bool,
	alpha:               f64,
	alphaNode:           ^LdtkJson, // rule's "alpha" node (written into tiles as is)
	hasOutOfBounds:      bool,
	outOfBounds:         int,
	flipX, flipY:        bool,
	xModulo, yModulo:    int,
	xOffset, yOffset:    int,
	tileXOffset:         int,
	tileYOffset:         int,
	tileRandomXMin:      int,
	tileRandomXMax:      int,
	tileRandomYMin:      int,
	tileRandomYMax:      int,
	checker:             Ldtk_RuleChecker,
	stamp:               bool,
	pivot:               [2]f64,
	perlin:              bool,
	perlinSeed:          int,
	perlinScale:         f64,
	perlinOctaves:       int,
	required:            []i32, // explicitly required values (positive, not "anything")
}

Ldtk_DocRuleGroup :: struct {
	obj:          ^LdtkJson,
	uid:          int,
	name:         string,
	active:       bool,
	isOptional:   bool,
	biomeMode:    int,
	biomeValues:  []string,
	rules:        [dynamic]Ldtk_DocRule,
}

Ldtk_DocLayerDef :: struct {
	obj:                  ^LdtkJson,
	uid:                  int,
	identifier:           string,
	type:                 LdtkLayerType,
	gridSize:             int,
	opacity:              f32,
	pxOffset:             [2]int,
	tilesetUid:           int, // -1 = none
	autoSourceUid:        int,
	autoTilesKilledByUid: int,
	biomeFieldUid:        int,
	tilePivot:            [2]f64,
	values:               [dynamic]Ldtk_DocIntValue,
	groups:               [dynamic]Ldtk_DocRuleGroup,
}

Ldtk_DocTileset :: struct {
	obj:        ^LdtkJson,
	uid:        int,
	identifier: string,
	relPath:    string,
	pxSize:     [2]int,
	gridSize:   int,
	spacing:    int,
	padding:    int,
	cWid, cHei: int,
	opaque:     []bool,
	anims:      map[i32]Ldtk_TileAnim, // animated tiles (ldtk_tiles.odin)
}

Ldtk_DocEntityDef :: struct {
	obj:        ^LdtkJson,
	uid:        int,
	identifier: string,
	size:       [2]int,
	pivot:      [2]f64,
	color:      rl.Color,
	tilesetUid: int,
	tileRect:   [4]int, // x, y, w, h (w = 0: none)
}

Ldtk_DocLayer :: struct {
	obj:        ^LdtkJson,
	def:        int, // index in doc.layerDefs, -1 = unknown
	cWid, cHei: int,
	seed:       int,
	intGrid:    []i32,
	gridTiles:  [dynamic]Ldtk_DocTile, // sorted by coord
	autoTiles:  [dynamic]Ldtk_DocTile, // sorted by (rank, coord, seq)
	cellsDirty: bool, // intGrid / gridTiles differ from the tree
	autoDirty:  bool, // autoTiles differ from the tree
}

Ldtk_DocLevel :: struct {
	obj:     ^LdtkJson, // the level object in the project file
	data:    ^LdtkJson, // object holding layerInstances (the .ldtkl root for external levels)
	extRoot: ^LdtkJson, // .ldtkl tree, nil when internal
	world:   int,
	layers:  [dynamic]Ldtk_DocLayer,
	dirty:   bool, // external file needs writing
}

Ldtk_DocWorld :: struct {
	obj:       ^LdtkJson, // world object (the root for single-world projects)
	levelsArr: ^LdtkJson, // its "levels" array
}

Ldtk_UndoKind :: enum u8 {
	Cells,   // one layer's intGrid + gridTiles
	Level,   // one level's tree
	Project, // whole document
}

Ldtk_UndoEntry :: struct {
	kind:      Ldtk_UndoKind,
	label:     string,
	level:     int,
	layer:     int,
	intGrid:   []i32,
	gridTiles: []Ldtk_DocTile,
	texts:     []string, // Level: [level obj, ext root]; Project: [root, ext roots...]
}

Ldtk_Doc :: struct {
	path:       string,
	dir:        string,
	root:       ^LdtkJson,
	levels:     [dynamic]Ldtk_DocLevel,
	worlds:     [dynamic]Ldtk_DocWorld,
	layerDefs:  [dynamic]Ldtk_DocLayerDef,
	tilesets:   [dynamic]Ldtk_DocTileset,
	entityDefs: [dynamic]Ldtk_DocEntityDef,
	multiWorlds: bool,
	external:   bool,
	minify:     bool,
	modified:   bool,
	revision:   u64, // bumped on every change (render caches)
	defsRevision: u64,
	undo:       [dynamic]Ldtk_UndoEntry,
	redo:       [dynamic]Ldtk_UndoEntry,
	pending:    Maybe(Ldtk_UndoEntry), // stroke in progress (Ldtk_Doc_BeginCells)
	removedFiles: [dynamic]string, // external level files to delete on save
	coalesceKey: rawptr, // Ldtk_Doc_CheckpointOnce: the edit the top undo step is for
	arena:      vmem.Arena,
	allocator:  mem.Allocator,
	// two arenas used in turn: pointers taken before a refresh (an editor
	// panel mid-frame) stay valid until the next one
	defsArenas: [2]vmem.Arena,
	defsCur:    int,
	heap:       mem.Allocator,
}

// ----------------------------------------------------------------------------
// Load / destroy
// ----------------------------------------------------------------------------

// Ldtk_Doc_Load reads a project file (and its external levels).
Ldtk_Doc_Load :: proc(path: string, heap := context.allocator) -> (^Ldtk_Doc, bool) {
	data, err := os.read_entire_file(path, heap)
	if err != nil do return nil, false
	defer delete(data, heap)
	return Ldtk_Doc_LoadFromMemory(string(data), path, heap)
}

// Ldtk_Doc_LoadFromMemory parses project text; `path` locates external
// levels and is where Ldtk_Doc_Save writes.
Ldtk_Doc_LoadFromMemory :: proc(text: string, path: string, heap := context.allocator) -> (^Ldtk_Doc, bool) {
	doc := new(Ldtk_Doc, heap)
	doc.heap = heap
	if vmem.arena_init_growing(&doc.arena) != nil {
		free(doc, heap)
		return nil, false
	}
	doc.allocator = vmem.arena_allocator(&doc.arena)
	if vmem.arena_init_growing(&doc.defsArenas[0]) != nil || vmem.arena_init_growing(&doc.defsArenas[1]) != nil {
		vmem.arena_destroy(&doc.defsArenas[0])
		vmem.arena_destroy(&doc.arena)
		free(doc, heap)
		return nil, false
	}
	doc.path = strings.clone(path, doc.allocator)
	doc.dir = strings.clone(filepath.dir(path, context.temp_allocator), doc.allocator)
	doc.levels = make([dynamic]Ldtk_DocLevel, heap)
	doc.worlds = make([dynamic]Ldtk_DocWorld, heap)
	doc.undo = make([dynamic]Ldtk_UndoEntry, heap)
	doc.redo = make([dynamic]Ldtk_UndoEntry, heap)
	doc.removedFiles = make([dynamic]string, heap)
	root, ok := LdtkJson_Parse(text, doc.allocator)
	if !ok || root.kind != .Object {
		Ldtk_Doc_Destroy(doc)
		return nil, false
	}
	doc.root = root
	if !ldtk_doc_build(doc, nil) {
		Ldtk_Doc_Destroy(doc)
		return nil, false
	}
	return doc, true
}

// ldtk_doc_build indexes worlds / levels / layers from doc.root. `extTexts`
// (undo) gives the external level trees instead of reading files.
@(private = "file")
ldtk_doc_build :: proc(doc: ^Ldtk_Doc, extTexts: []string) -> bool {
	a := doc.allocator
	doc.minify = LdtkJson_Bool(doc.root, "minifyJson")
	doc.external = LdtkJson_Bool(doc.root, "externalLevels")
	Ldtk_Doc_RefreshDefs(doc)
	for &l in doc.levels do ldtk_level_free(doc, &l)
	clear(&doc.levels)
	clear(&doc.worlds)
	worlds := LdtkJson_Get(doc.root, "worlds")
	doc.multiWorlds = worlds != nil && worlds.kind == .Array && len(worlds.items) > 0
	if doc.multiWorlds {
		for w in worlds.items {
			arr := LdtkJson_Get(w, "levels")
			if arr == nil || arr.kind != .Array {
				arr = LdtkJson_New(.Array, a)
				LdtkJson_Set(w, "levels", arr, a)
			}
			append(&doc.worlds, Ldtk_DocWorld{obj = w, levelsArr = arr})
		}
	} else {
		arr := LdtkJson_Get(doc.root, "levels")
		if arr == nil || arr.kind != .Array {
			arr = LdtkJson_New(.Array, a)
			LdtkJson_Set(doc.root, "levels", arr, a)
		}
		append(&doc.worlds, Ldtk_DocWorld{obj = doc.root, levelsArr = arr})
	}
	extIdx := 0
	for w, wi in doc.worlds {
		for lobj in w.levelsArr.items {
			lv := Ldtk_DocLevel{obj = lobj, data = lobj, world = wi}
			lv.layers = make([dynamic]Ldtk_DocLayer, doc.heap)
			rel := LdtkJson_Str(lobj, "externalRelPath")
			if rel != "" {
				text: string
				if extTexts != nil {
					if extIdx < len(extTexts) do text = extTexts[extIdx]
				} else {
					p, _ := filepath.join({doc.dir, rel}, context.temp_allocator)
					bytes, err := os.read_entire_file(p, context.temp_allocator)
					if err == nil do text = string(bytes)
				}
				if text != "" {
					if ext, ok := LdtkJson_Parse(text, a); ok && ext.kind == .Object {
						lv.extRoot = ext
						lv.data = ext
					}
				}
			}
			if rel != "" do extIdx += 1
			ldtk_level_index_layers(doc, &lv)
			append(&doc.levels, lv)
		}
	}
	doc.revision += 1
	return true
}

@(private = "file")
ldtk_level_free :: proc(doc: ^Ldtk_Doc, l: ^Ldtk_DocLevel) {
	for &ly in l.layers {
		delete(ly.intGrid, doc.heap)
		delete(ly.gridTiles)
		delete(ly.autoTiles)
	}
	delete(l.layers)
}

@(private)
ldtk_level_index_layers :: proc(doc: ^Ldtk_Doc, lv: ^Ldtk_DocLevel) {
	for &ly in lv.layers {
		delete(ly.intGrid, doc.heap)
		delete(ly.gridTiles)
		delete(ly.autoTiles)
	}
	clear(&lv.layers)
	for lobj in LdtkJson_Arr(lv.data, "layerInstances") {
		ly := Ldtk_DocLayer{obj = lobj}
		ly.def = Ldtk_Doc_LayerDefIndex(doc, LdtkJson_Int(lobj, "layerDefUid", -1))
		ly.cWid = LdtkJson_Int(lobj, "__cWid")
		ly.cHei = LdtkJson_Int(lobj, "__cHei")
		ly.seed = LdtkJson_Int(lobj, "seed")
		n := max(ly.cWid * ly.cHei, 0)
		ly.intGrid = make([]i32, n, doc.heap)
		for v, i in LdtkJson_Arr(lobj, "intGridCsv") {
			if i < n do ly.intGrid[i] = i32(v.num)
		}
		ly.gridTiles = make([dynamic]Ldtk_DocTile, doc.heap)
		ly.autoTiles = make([dynamic]Ldtk_DocTile, doc.heap)
		ldtk_read_tiles(&ly.gridTiles, LdtkJson_Arr(lobj, "gridTiles"), false)
		ldtk_read_tiles(&ly.autoTiles, LdtkJson_Arr(lobj, "autoLayerTiles"), true)
		append(&lv.layers, ly)
	}
}

@(private = "file")
ldtk_read_tiles :: proc(out: ^[dynamic]Ldtk_DocTile, arr: []^LdtkJson, auto: bool) {
	reserve(out, len(arr))
	for t, i in arr {
		tile := Ldtk_DocTile{rule = -1, a = 1, seq = i32(i)}
		if px := LdtkJson_Arr(t, "px"); len(px) >= 2 do tile.px = {i32(px[0].num), i32(px[1].num)}
		if src := LdtkJson_Arr(t, "src"); len(src) >= 2 do tile.src = {i32(src[0].num), i32(src[1].num)}
		tile.f = u8(LdtkJson_Int(t, "f"))
		tile.t = i32(LdtkJson_Int(t, "t"))
		tile.a = LdtkJson_Float(t, "a", 1)
		d := LdtkJson_Arr(t, "d")
		if auto && len(d) >= 2 {
			tile.rule = i32(d[0].num)
			tile.coord = i32(d[1].num)
		} else if len(d) >= 1 {
			tile.coord = i32(d[0].num)
		}
		append(out, tile)
	}
}

Ldtk_Doc_Destroy :: proc(doc: ^Ldtk_Doc) {
	if doc == nil do return
	heap := doc.heap
	for &l in doc.levels do ldtk_level_free(doc, &l)
	delete(doc.levels)
	delete(doc.worlds)
	ldtk_undo_clear(doc, &doc.undo)
	ldtk_undo_clear(doc, &doc.redo)
	delete(doc.undo)
	delete(doc.redo)
	for f in doc.removedFiles do delete(f, heap)
	delete(doc.removedFiles)
	if p, ok := doc.pending.?; ok do ldtk_undo_free(doc, &p)
	vmem.arena_destroy(&doc.defsArenas[0])
	vmem.arena_destroy(&doc.defsArenas[1])
	vmem.arena_destroy(&doc.arena)
	free(doc, heap)
}

// ----------------------------------------------------------------------------
// Definitions cache
// ----------------------------------------------------------------------------

// Ldtk_Doc_RefreshDefs rebuilds the typed definition caches from the tree;
// call after editing anything under "defs".
Ldtk_Doc_RefreshDefs :: proc(doc: ^Ldtk_Doc) {
	doc.defsCur = 1 - doc.defsCur
	vmem.arena_free_all(&doc.defsArenas[doc.defsCur])
	a := vmem.arena_allocator(&doc.defsArenas[doc.defsCur])
	doc.layerDefs = make([dynamic]Ldtk_DocLayerDef, a)
	doc.tilesets = make([dynamic]Ldtk_DocTileset, a)
	doc.entityDefs = make([dynamic]Ldtk_DocEntityDef, a)
	defs := LdtkJson_Get(doc.root, "defs")
	for t in LdtkJson_Arr(defs, "tilesets") {
		ts := Ldtk_DocTileset{
			obj = t,
			uid = LdtkJson_Int(t, "uid"),
			identifier = LdtkJson_Str(t, "identifier"),
			relPath = LdtkJson_Str(t, "relPath"),
			pxSize = {LdtkJson_Int(t, "pxWid"), LdtkJson_Int(t, "pxHei")},
			gridSize = max(LdtkJson_Int(t, "tileGridSize", 16), 1),
			spacing = LdtkJson_Int(t, "spacing"),
			padding = LdtkJson_Int(t, "padding"),
		}
		hasAtlas := ts.relPath != "" || !LdtkJson_IsNull(t, "embedAtlas")
		if hasAtlas {
			step := f64(ts.gridSize + ts.spacing)
			ts.cWid = int(ldtk_ceil(f64(ts.pxSize.x - ts.padding * 2) / step))
			ts.cHei = int(ldtk_ceil(f64(ts.pxSize.y - ts.padding * 2) / step))
		}
		if cache := LdtkJson_Get(t, "cachedPixelData"); cache != nil {
			op := LdtkJson_Str(cache, "opaqueTiles")
			if len(op) == ts.cWid * ts.cHei && len(op) > 0 {
				ts.opaque = make([]bool, len(op), a)
				for i in 0 ..< len(op) do ts.opaque[i] = op[i] == '1'
			}
		}
		ts.anims = make(map[i32]Ldtk_TileAnim, allocator = a)
		for cd in LdtkJson_Arr(t, "customData") {
			if anim, ok := Ldtk_ParseTileAnim(LdtkJson_Str(cd, "data"), a); ok do ts.anims[i32(LdtkJson_Int(cd, "tileId"))] = anim
		}
		append(&doc.tilesets, ts)
	}
	for e in LdtkJson_Arr(defs, "entities") {
		ed := Ldtk_DocEntityDef{
			obj = e,
			uid = LdtkJson_Int(e, "uid"),
			identifier = LdtkJson_Str(e, "identifier"),
			size = {LdtkJson_Int(e, "width", 16), LdtkJson_Int(e, "height", 16)},
			pivot = {LdtkJson_Float(e, "pivotX"), LdtkJson_Float(e, "pivotY")},
			color = Ldtk_ParseHexColor(LdtkJson_Str(e, "color", "#94D9B3")),
			tilesetUid = LdtkJson_Int(e, "tilesetId", -1),
		}
		if tr := LdtkJson_Get(e, "tileRect"); tr != nil && tr.kind == .Object {
			ed.tilesetUid = LdtkJson_Int(tr, "tilesetUid", ed.tilesetUid)
			ed.tileRect = {LdtkJson_Int(tr, "x"), LdtkJson_Int(tr, "y"), LdtkJson_Int(tr, "w"), LdtkJson_Int(tr, "h")}
		}
		append(&doc.entityDefs, ed)
	}
	for l in LdtkJson_Arr(defs, "layers") {
		ld := Ldtk_DocLayerDef{
			obj = l,
			uid = LdtkJson_Int(l, "uid"),
			identifier = LdtkJson_Str(l, "identifier"),
			type = ldtk_doc_layer_type(LdtkJson_Str(l, "type", LdtkJson_Str(l, "__type"))),
			gridSize = max(LdtkJson_Int(l, "gridSize", 16), 1),
			opacity = f32(LdtkJson_Float(l, "displayOpacity", 1)),
			pxOffset = {LdtkJson_Int(l, "pxOffsetX"), LdtkJson_Int(l, "pxOffsetY")},
			tilesetUid = ldtk_nullable_int(l, "tilesetDefUid"),
			autoSourceUid = ldtk_nullable_int(l, "autoSourceLayerDefUid"),
			autoTilesKilledByUid = ldtk_nullable_int(l, "autoTilesKilledByOtherLayerUid"),
			biomeFieldUid = ldtk_nullable_int(l, "biomeFieldUid"),
			tilePivot = {LdtkJson_Float(l, "tilePivotX"), LdtkJson_Float(l, "tilePivotY")},
		}
		ld.values = make([dynamic]Ldtk_DocIntValue, a)
		for v in LdtkJson_Arr(l, "intGridValues") {
			append(&ld.values, Ldtk_DocIntValue{
				value = LdtkJson_Int(v, "value"),
				groupUid = LdtkJson_Int(v, "groupUid"),
				identifier = LdtkJson_Str(v, "identifier"),
				color = Ldtk_ParseHexColor(LdtkJson_Str(v, "color", "#000000")),
			})
		}
		ld.groups = make([dynamic]Ldtk_DocRuleGroup, a)
		for g in LdtkJson_Arr(l, "autoRuleGroups") {
			rg := Ldtk_DocRuleGroup{
				obj = g,
				uid = LdtkJson_Int(g, "uid"),
				name = LdtkJson_Str(g, "name"),
				active = LdtkJson_Bool(g, "active", true),
				isOptional = LdtkJson_Bool(g, "isOptional"),
				biomeMode = LdtkJson_Int(g, "biomeRequirementMode"),
			}
			bv := LdtkJson_Arr(g, "requiredBiomeValues")
			rg.biomeValues = make([]string, len(bv), a)
			for b, i in bv do rg.biomeValues[i] = b.text
			rg.rules = make([dynamic]Ldtk_DocRule, a)
			for r in LdtkJson_Arr(g, "rules") do append(&rg.rules, ldtk_parse_rule(r, a))
			append(&ld.groups, rg)
		}
		append(&doc.layerDefs, ld)
	}
	for &l in doc.levels {
		for &ly in l.layers do ly.def = Ldtk_Doc_LayerDefIndex(doc, LdtkJson_Int(ly.obj, "layerDefUid", -1))
	}
	doc.defsRevision += 1
	doc.revision += 1
}

@(private = "file")
ldtk_ceil :: proc(v: f64) -> f64 {
	i := f64(i64(v))
	return i < v ? i + 1 : i
}

@(private = "file")
ldtk_nullable_int :: proc(o: ^LdtkJson, key: string) -> int {
	v := LdtkJson_Get(o, key)
	if v == nil || v.kind != .Number do return -1
	return int(v.num)
}

@(private = "file")
ldtk_doc_layer_type :: proc(s: string) -> LdtkLayerType {
	switch s {
	case "Entities": return .Entities
	case "Tiles": return .Tiles
	case "AutoLayer": return .AutoLayer
	}
	return .IntGrid
}

@(private = "file")
ldtk_parse_rule :: proc(r: ^LdtkJson, a: mem.Allocator) -> Ldtk_DocRule {
	rule := Ldtk_DocRule{
		obj = r,
		uid = LdtkJson_Int(r, "uid"),
		active = LdtkJson_Bool(r, "active", true),
		size = max(LdtkJson_Int(r, "size", 3), 1),
		chance = LdtkJson_Float(r, "chance", 1),
		breakOnMatch = LdtkJson_Bool(r, "breakOnMatch"),
		alpha = LdtkJson_Float(r, "alpha", 1),
		alphaNode = LdtkJson_Get(r, "alpha"),
		flipX = LdtkJson_Bool(r, "flipX"),
		flipY = LdtkJson_Bool(r, "flipY"),
		xModulo = max(LdtkJson_Int(r, "xModulo", 1), 1),
		yModulo = max(LdtkJson_Int(r, "yModulo", 1), 1),
		xOffset = LdtkJson_Int(r, "xOffset"),
		yOffset = LdtkJson_Int(r, "yOffset"),
		tileXOffset = LdtkJson_Int(r, "tileXOffset"),
		tileYOffset = LdtkJson_Int(r, "tileYOffset"),
		tileRandomXMin = LdtkJson_Int(r, "tileRandomXMin"),
		tileRandomXMax = LdtkJson_Int(r, "tileRandomXMax"),
		tileRandomYMin = LdtkJson_Int(r, "tileRandomYMin"),
		tileRandomYMax = LdtkJson_Int(r, "tileRandomYMax"),
		stamp = LdtkJson_Str(r, "tileMode") == "Stamp",
		pivot = {LdtkJson_Float(r, "pivotX"), LdtkJson_Float(r, "pivotY")},
		perlin = LdtkJson_Bool(r, "perlinActive"),
		perlinSeed = LdtkJson_Int(r, "perlinSeed"),
		perlinScale = LdtkJson_Float(r, "perlinScale", 0.2),
		perlinOctaves = LdtkJson_Int(r, "perlinOctaves", 2),
	}
	if rule.alphaNode != nil && rule.alphaNode.kind != .Number do rule.alphaNode = nil
	switch LdtkJson_Str(r, "checker") {
	case "Horizontal": rule.checker = .Horizontal
	case "Vertical": rule.checker = .Vertical
	}
	if ob := LdtkJson_Get(r, "outOfBoundsValue"); ob != nil && ob.kind == .Number {
		rule.hasOutOfBounds = true
		rule.outOfBounds = int(ob.num)
	}
	pat := LdtkJson_Arr(r, "pattern")
	rule.pattern = make([]i32, rule.size * rule.size, a)
	for v, i in pat do if i < len(rule.pattern) do rule.pattern[i] = i32(v.num)
	// AutoLayerRuleDef.tidy (LDtk runs it on load): symmetric patterns don't
	// flip, checker modes need a modulo.
	sym :: proc(r: ^Ldtk_DocRule, x: bool) -> bool {
		n := r.size
		for i in 0 ..< n / 2 {
			for j in 0 ..< n {
				a := x ? r.pattern[i + j * n] : r.pattern[j + i * n]
				b := x ? r.pattern[(n - 1 - i) + j * n] : r.pattern[j + (n - 1 - i) * n]
				if a != b do return false
			}
		}
		return true
	}
	if rule.flipX && sym(&rule, true) do rule.flipX = false
	if rule.flipY && sym(&rule, false) do rule.flipY = false
	if rule.xModulo == 1 && rule.yModulo == 1 do rule.checker = .None
	if rule.xModulo == 1 && rule.checker == .Horizontal do rule.checker = rule.yModulo > 1 ? .Vertical : .None
	if rule.yModulo == 1 && rule.checker == .Vertical do rule.checker = rule.xModulo > 1 ? .Horizontal : .None
	req := make([dynamic]i32, a)
	for v in rule.pattern {
		if v > 0 && v != LDTK_AUTO_LAYER_ANYTHING && !slice.contains(req[:], v) do append(&req, v)
	}
	rule.required = req[:]
	if rects := LdtkJson_Arr(r, "tileRectsIds"); rects != nil {
		rule.tileRects = make([][]i32, len(rects), a)
		for rect, i in rects {
			ids := make([]i32, len(rect.items), a)
			for t, j in rect.items do ids[j] = i32(t.num)
			rule.tileRects[i] = ids
		}
	} else if ids := LdtkJson_Arr(r, "tileIds"); ids != nil {
		// pre-1.5 format
		if rule.stamp {
			one := make([]i32, len(ids), a)
			for t, j in ids do one[j] = i32(t.num)
			rule.tileRects = make([][]i32, 1, a)
			rule.tileRects[0] = one
		} else {
			rule.tileRects = make([][]i32, len(ids), a)
			for t, j in ids {
				one := make([]i32, 1, a)
				one[0] = i32(t.num)
				rule.tileRects[j] = one
			}
		}
	}
	return rule
}

// ----------------------------------------------------------------------------
// Lookups
// ----------------------------------------------------------------------------

Ldtk_Doc_LayerDefIndex :: proc(doc: ^Ldtk_Doc, uid: int) -> int {
	for d, i in doc.layerDefs do if d.uid == uid do return i
	return -1
}

Ldtk_Doc_Tileset :: proc(doc: ^Ldtk_Doc, uid: int) -> ^Ldtk_DocTileset {
	if uid < 0 do return nil
	for &t in doc.tilesets do if t.uid == uid do return &t
	return nil
}

Ldtk_Doc_EntityDef :: proc(doc: ^Ldtk_Doc, uid: int) -> ^Ldtk_DocEntityDef {
	for &e in doc.entityDefs do if e.uid == uid do return &e
	return nil
}

Ldtk_Doc_LayerDef :: proc(doc: ^Ldtk_Doc, ly: ^Ldtk_DocLayer) -> ^Ldtk_DocLayerDef {
	if ly.def < 0 || ly.def >= len(doc.layerDefs) do return nil
	return &doc.layerDefs[ly.def]
}

// Ldtk_Doc_LayerTileset: the instance's override tileset, else the def's.
Ldtk_Doc_LayerTileset :: proc(doc: ^Ldtk_Doc, ly: ^Ldtk_DocLayer) -> ^Ldtk_DocTileset {
	if o := ldtk_nullable_int(ly.obj, "overrideTilesetUid"); o >= 0 do return Ldtk_Doc_Tileset(doc, o)
	d := Ldtk_Doc_LayerDef(doc, ly)
	if d == nil do return nil
	return Ldtk_Doc_Tileset(doc, d.tilesetUid)
}

Ldtk_Doc_IntValue :: proc(d: ^Ldtk_DocLayerDef, value: int) -> ^Ldtk_DocIntValue {
	if d == nil do return nil
	for &v in d.values do if v.value == value do return &v
	return nil
}

// Ldtk_Doc_LevelLayer finds a layer instance by its def uid.
Ldtk_Doc_LevelLayer :: proc(doc: ^Ldtk_Doc, lv: ^Ldtk_DocLevel, defUid: int) -> ^Ldtk_DocLayer {
	if defUid < 0 do return nil
	for &ly in lv.layers {
		if ly.def >= 0 && doc.layerDefs[ly.def].uid == defUid do return &ly
	}
	return nil
}

Ldtk_Doc_TileSrc :: proc(ts: ^Ldtk_DocTileset, tid: int) -> [2]i32 {
	if ts == nil || ts.cWid <= 0 do return {-1, -1}
	cx := tid - ts.cWid * (tid / ts.cWid)
	cy := tid / ts.cWid
	return {i32(ts.padding + cx * (ts.gridSize + ts.spacing)), i32(ts.padding + cy * (ts.gridSize + ts.spacing))}
}

Ldtk_Doc_LevelName :: proc(doc: ^Ldtk_Doc, li: int) -> string {
	if li < 0 || li >= len(doc.levels) do return ""
	return LdtkJson_Str(doc.levels[li].obj, "identifier")
}

// Ldtk_Doc_Iid makes a new random (version 4) identifier.
Ldtk_Doc_Iid :: proc(allocator := context.allocator) -> string {
	b: [16]u8
	for &x in b do x = u8(rand.uint32())
	b[6] = (b[6] & 0x0F) | 0x40
	b[8] = (b[8] & 0x3F) | 0x80
	return fmt.aprintf("%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
		b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15],
		allocator = allocator)
}

// Ldtk_Doc_NextUid takes the project's next unique id.
Ldtk_Doc_NextUid :: proc(doc: ^Ldtk_Doc) -> int {
	uid := LdtkJson_Int(doc.root, "nextUid", 1)
	LdtkJson_SetInt(doc.root, "nextUid", uid + 1, doc.allocator)
	return uid
}

// Ldtk_Doc_Touch marks the document changed.
Ldtk_Doc_Touch :: proc(doc: ^Ldtk_Doc) {
	doc.modified = true
	doc.revision += 1
}

// ----------------------------------------------------------------------------
// Cell editing
// ----------------------------------------------------------------------------

Ldtk_Doc_GetIntGrid :: proc(ly: ^Ldtk_DocLayer, cx, cy: int) -> int {
	if cx < 0 || cy < 0 || cx >= ly.cWid || cy >= ly.cHei do return 0
	return int(ly.intGrid[cx + cy * ly.cWid])
}

// Ldtk_Doc_SetIntGrid sets one IntGrid cell (0 clears). Returns true when it
// changed; call Ldtk_Doc_ApplyRules for the changed area afterwards.
Ldtk_Doc_SetIntGrid :: proc(doc: ^Ldtk_Doc, li, layer: int, cx, cy: int, v: int) -> bool {
	ly := &doc.levels[li].layers[layer]
	if cx < 0 || cy < 0 || cx >= ly.cWid || cy >= ly.cHei do return false
	i := cx + cy * ly.cWid
	if int(ly.intGrid[i]) == v do return false
	ly.intGrid[i] = i32(v)
	ly.cellsDirty = true
	doc.levels[li].dirty = true
	Ldtk_Doc_Touch(doc)
	return true
}

// ldtk_tiles_range: [lo, hi) of the tiles anchored at `coord` (gridTiles is
// sorted by coord).
@(private = "file")
ldtk_tiles_range :: proc(tiles: []Ldtk_DocTile, coord: i32) -> (int, int) {
	lo, hi := 0, len(tiles)
	for lo < hi {
		m := (lo + hi) / 2
		if tiles[m].coord < coord do lo = m + 1
		else do hi = m
	}
	end := lo
	for end < len(tiles) && tiles[end].coord == coord do end += 1
	return lo, end
}

// Ldtk_Doc_TilesAt returns the grid tiles stacked in a cell.
Ldtk_Doc_TilesAt :: proc(ly: ^Ldtk_DocLayer, cx, cy: int) -> []Ldtk_DocTile {
	if cx < 0 || cy < 0 || cx >= ly.cWid || cy >= ly.cHei do return nil
	lo, hi := ldtk_tiles_range(ly.gridTiles[:], i32(cx + cy * ly.cWid))
	return ly.gridTiles[lo:hi]
}

// Ldtk_Doc_SetTile puts a tile in a cell, replacing what was there (or on
// top of it with `stack`). tid < 0 clears the cell.
Ldtk_Doc_SetTile :: proc(doc: ^Ldtk_Doc, li, layer: int, cx, cy: int, tid: int, flips: u8 = 0, stack := false) -> bool {
	ly := &doc.levels[li].layers[layer]
	if cx < 0 || cy < 0 || cx >= ly.cWid || cy >= ly.cHei do return false
	d := Ldtk_Doc_LayerDef(doc, ly)
	if d == nil do return false
	coord := i32(cx + cy * ly.cWid)
	lo, hi := ldtk_tiles_range(ly.gridTiles[:], coord)
	if tid < 0 {
		if lo == hi do return false
		remove_range(&ly.gridTiles, lo, hi)
	} else {
		if !stack && hi - lo == 1 && ly.gridTiles[lo].t == i32(tid) && ly.gridTiles[lo].f == flips do return false
		if stack && hi > lo && ly.gridTiles[hi - 1].t == i32(tid) && ly.gridTiles[hi - 1].f == flips do return false
		ts := Ldtk_Doc_LayerTileset(doc, ly)
		tile := Ldtk_DocTile{
			px = {i32(cx * d.gridSize), i32(cy * d.gridSize)},
			src = Ldtk_Doc_TileSrc(ts, tid),
			t = i32(tid),
			coord = coord,
			rule = -1,
			f = flips,
			a = 1,
		}
		if !stack {
			remove_range(&ly.gridTiles, lo, hi)
			hi = lo
		}
		inject_at(&ly.gridTiles, hi, tile)
	}
	ly.cellsDirty = true
	doc.levels[li].dirty = true
	Ldtk_Doc_Touch(doc)
	return true
}

// ----------------------------------------------------------------------------
// Undo
// ----------------------------------------------------------------------------

@(private = "file")
ldtk_undo_free :: proc(doc: ^Ldtk_Doc, e: ^Ldtk_UndoEntry) {
	delete(e.intGrid, doc.heap)
	delete(e.gridTiles, doc.heap)
	for t in e.texts do delete(t, doc.heap)
	delete(e.texts, doc.heap)
	delete(e.label, doc.heap)
	e^ = {}
}

@(private = "file")
ldtk_undo_clear :: proc(doc: ^Ldtk_Doc, list: ^[dynamic]Ldtk_UndoEntry) {
	for &e in list do ldtk_undo_free(doc, &e)
	clear(list)
}

@(private = "file")
ldtk_undo_push :: proc(doc: ^Ldtk_Doc, e: Ldtk_UndoEntry) {
	doc.coalesceKey = nil
	if len(doc.undo) >= LDTK_UNDO_LIMIT {
		ldtk_undo_free(doc, &doc.undo[0])
		ordered_remove(&doc.undo, 0)
	}
	append(&doc.undo, e)
	ldtk_undo_clear(doc, &doc.redo)
}

@(private = "file")
ldtk_capture_cells :: proc(doc: ^Ldtk_Doc, li, layer: int, label: string) -> Ldtk_UndoEntry {
	ly := &doc.levels[li].layers[layer]
	return Ldtk_UndoEntry{
		kind = .Cells,
		label = strings.clone(label, doc.heap),
		level = li,
		layer = layer,
		intGrid = slice.clone(ly.intGrid, doc.heap),
		gridTiles = slice.clone(ly.gridTiles[:], doc.heap),
	}
}

// Ldtk_Doc_BeginCells starts a paint stroke on a layer: the cells are saved
// for undo; Ldtk_Doc_EndCells records the step if anything changed.
Ldtk_Doc_BeginCells :: proc(doc: ^Ldtk_Doc, li, layer: int, label: string) {
	if p, ok := doc.pending.?; ok {
		ldtk_undo_free(doc, &p)
		doc.pending = nil
	}
	doc.pending = ldtk_capture_cells(doc, li, layer, label)
}

Ldtk_Doc_EndCells :: proc(doc: ^Ldtk_Doc) {
	p, ok := doc.pending.?
	if !ok do return
	doc.pending = nil
	ly := &doc.levels[p.level].layers[p.layer]
	same := slice.equal(p.intGrid, ly.intGrid) && len(p.gridTiles) == len(ly.gridTiles)
	if same {
		for t, i in p.gridTiles {
			o := ly.gridTiles[i]
			if t.t != o.t || t.coord != o.coord || t.f != o.f {
				same = false
				break
			}
		}
	}
	if same {
		ldtk_undo_free(doc, &p)
		return
	}
	ldtk_undo_push(doc, p)
}

// ldtk_level_texts serializes a level for undo: [project-file level object,
// external tree or ""].
@(private = "file")
ldtk_level_texts :: proc(doc: ^Ldtk_Doc, li: int) -> []string {
	scratch: vmem.Arena
	_ = vmem.arena_init_growing(&scratch)
	defer vmem.arena_destroy(&scratch)
	sa := vmem.arena_allocator(&scratch)
	lv := &doc.levels[li]
	restore := ldtk_flush_level(doc, lv, sa)
	out := make([]string, 2, doc.heap)
	out[0] = LdtkJson_ToString(lv.obj, .Minified, doc.heap)
	out[1] = lv.extRoot != nil ? LdtkJson_ToString(lv.extRoot, .Minified, doc.heap) : strings.clone("", doc.heap)
	ldtk_unflush(restore[:])
	return out
}

@(private = "file")
ldtk_project_texts :: proc(doc: ^Ldtk_Doc) -> []string {
	scratch: vmem.Arena
	_ = vmem.arena_init_growing(&scratch)
	defer vmem.arena_destroy(&scratch)
	sa := vmem.arena_allocator(&scratch)
	restore := make([dynamic]Ldtk_FlushSwap, sa)
	for &lv in doc.levels {
		r := ldtk_flush_level(doc, &lv, sa)
		append(&restore, ..r[:])
	}
	out := make([dynamic]string, doc.heap)
	append(&out, LdtkJson_ToString(doc.root, .Minified, doc.heap))
	for &lv in doc.levels {
		if lv.extRoot != nil do append(&out, LdtkJson_ToString(lv.extRoot, .Minified, doc.heap))
	}
	ldtk_unflush(restore[:])
	return out[:]
}

// Ldtk_Doc_Checkpoint saves an undo step before an edit of the level's tree
// (entities, fields, size, position) or, with li < 0, of the whole project
// (definitions, adding / removing levels).
Ldtk_Doc_Checkpoint :: proc(doc: ^Ldtk_Doc, li: int, label: string) {
	e := Ldtk_UndoEntry{label = strings.clone(label, doc.heap), level = li}
	if li >= 0 && li < len(doc.levels) {
		e.kind = .Level
		e.texts = ldtk_level_texts(doc, li)
	} else {
		e.kind = .Project
		e.texts = ldtk_project_texts(doc)
	}
	ldtk_undo_push(doc, e)
}

// Ldtk_Doc_CheckpointOnce: Ldtk_Doc_Checkpoint for live edits (dragging a
// value, picking a colour): one undo step per edit of `key`, until
// Ldtk_Doc_EndCoalesce (the widget released) or another step.
Ldtk_Doc_CheckpointOnce :: proc(doc: ^Ldtk_Doc, li: int, label: string, key: rawptr) {
	if doc.coalesceKey == key && key != nil && len(doc.redo) == 0 do return
	Ldtk_Doc_Checkpoint(doc, li, label)
	doc.coalesceKey = key
}

Ldtk_Doc_EndCoalesce :: proc(doc: ^Ldtk_Doc) {
	doc.coalesceKey = nil
}

// ldtk_apply_entry restores `e` and returns the entry that undoes that.
@(private = "file")
ldtk_apply_entry :: proc(doc: ^Ldtk_Doc, e: ^Ldtk_UndoEntry) -> Ldtk_UndoEntry {
	switch e.kind {
	case .Cells:
		back := ldtk_capture_cells(doc, e.level, e.layer, e.label)
		ly := &doc.levels[e.level].layers[e.layer]
		copy(ly.intGrid, e.intGrid)
		clear(&ly.gridTiles)
		append(&ly.gridTiles, ..e.gridTiles)
		ly.cellsDirty = true
		doc.levels[e.level].dirty = true
		Ldtk_Doc_ApplyRulesFull(doc, e.level)
		return back
	case .Level:
		back := Ldtk_UndoEntry{kind = .Level, label = strings.clone(e.label, doc.heap), level = e.level}
		back.texts = ldtk_level_texts(doc, e.level)
		lv := &doc.levels[e.level]
		a := doc.allocator
		if obj, ok := LdtkJson_Parse(e.texts[0], a); ok {
			arr := doc.worlds[lv.world].levelsArr
			for it, i in arr.items do if it == lv.obj do arr.items[i] = obj
			lv.obj = obj
			lv.data = obj
		}
		if e.texts[1] != "" {
			if ext, ok := LdtkJson_Parse(e.texts[1], a); ok {
				lv.extRoot = ext
				lv.data = ext
			}
		}
		ldtk_level_index_layers(doc, lv)
		for &ly in lv.layers do ly.cellsDirty, ly.autoDirty = true, true
		lv.dirty = true
		return back
	case .Project:
		back := Ldtk_UndoEntry{kind = .Project, label = strings.clone(e.label, doc.heap), level = -1}
		back.texts = ldtk_project_texts(doc)
		if root, ok := LdtkJson_Parse(e.texts[0], doc.allocator); ok {
			doc.root = root
			ldtk_doc_build(doc, e.texts[1:])
			for &lv in doc.levels {
				lv.dirty = true
				for &ly in lv.layers do ly.cellsDirty, ly.autoDirty = true, true
			}
		}
		return back
	}
	return {}
}

Ldtk_Doc_CanUndo :: proc(doc: ^Ldtk_Doc) -> bool {return len(doc.undo) > 0}
Ldtk_Doc_CanRedo :: proc(doc: ^Ldtk_Doc) -> bool {return len(doc.redo) > 0}

Ldtk_Doc_Undo :: proc(doc: ^Ldtk_Doc) -> bool {
	if len(doc.undo) == 0 do return false
	doc.coalesceKey = nil
	e := pop(&doc.undo)
	back := ldtk_apply_entry(doc, &e)
	ldtk_undo_free(doc, &e)
	append(&doc.redo, back)
	Ldtk_Doc_Touch(doc)
	return true
}

Ldtk_Doc_Redo :: proc(doc: ^Ldtk_Doc) -> bool {
	if len(doc.redo) == 0 do return false
	doc.coalesceKey = nil
	e := pop(&doc.redo)
	back := ldtk_apply_entry(doc, &e)
	ldtk_undo_free(doc, &e)
	append(&doc.undo, back)
	Ldtk_Doc_Touch(doc)
	return true
}

// ----------------------------------------------------------------------------
// Saving
// ----------------------------------------------------------------------------

Ldtk_FlushSwap :: struct {
	obj:  ^LdtkJson,
	idx:  int,
	prev: ^LdtkJson,
}

// ldtk_flush_level temporarily puts the typed cell data of dirty layers into
// the tree (nodes from `sa`); ldtk_unflush puts the originals back.
@(private = "file")
ldtk_flush_level :: proc(doc: ^Ldtk_Doc, lv: ^Ldtk_DocLevel, sa: mem.Allocator) -> [dynamic]Ldtk_FlushSwap {
	swaps := make([dynamic]Ldtk_FlushSwap, sa)
	swap :: proc(swaps: ^[dynamic]Ldtk_FlushSwap, obj: ^LdtkJson, key: string, v: ^LdtkJson, sa: mem.Allocator) {
		i := LdtkJson_Index(obj, key)
		if i < 0 {
			append(&obj.keys, key)
			append(&obj.items, v)
			append(swaps, Ldtk_FlushSwap{obj, len(obj.items) - 1, nil})
			return
		}
		append(swaps, Ldtk_FlushSwap{obj, i, obj.items[i]})
		obj.items[i] = v
	}
	for &ly in lv.layers {
		d := Ldtk_Doc_LayerDef(doc, &ly)
		if ly.cellsDirty {
			csv := LdtkJson_New(.Array, sa)
			if d != nil && d.type == .IntGrid {
				reserve(&csv.items, len(ly.intGrid))
				for v in ly.intGrid do append(&csv.items, LdtkJson_NewInt(int(v), sa))
			}
			swap(&swaps, ly.obj, "intGridCsv", csv, sa)
			swap(&swaps, ly.obj, "gridTiles", ldtk_tiles_json(ly.gridTiles[:], false, sa), sa)
		}
		if ly.autoDirty {
			swap(&swaps, ly.obj, "autoLayerTiles", ldtk_tiles_json(ly.autoTiles[:], true, sa), sa)
		}
	}
	return swaps
}

@(private = "file")
ldtk_unflush :: proc(swaps: []Ldtk_FlushSwap) {
	#reverse for s in swaps {
		if s.prev == nil {
			pop(&s.obj.keys)
			pop(&s.obj.items)
		} else do s.obj.items[s.idx] = s.prev
	}
}

@(private = "file")
ldtk_tiles_json :: proc(tiles: []Ldtk_DocTile, auto: bool, sa: mem.Allocator) -> ^LdtkJson {
	arr := LdtkJson_New(.Array, sa)
	reserve(&arr.items, len(tiles))
	pair :: proc(x, y: i32, sa: mem.Allocator) -> ^LdtkJson {
		p := LdtkJson_New(.Array, sa)
		append(&p.items, LdtkJson_NewInt(int(x), sa), LdtkJson_NewInt(int(y), sa))
		return p
	}
	for t in tiles {
		o := LdtkJson_New(.Object, sa)
		reserve(&o.keys, 6)
		reserve(&o.items, 6)
		append(&o.keys, "px", "src", "f", "t", "d", "a")
		d: ^LdtkJson
		if auto do d = pair(t.rule, t.coord, sa)
		else {
			d = LdtkJson_New(.Array, sa)
			append(&d.items, LdtkJson_NewInt(int(t.coord), sa))
		}
		append(&o.items, pair(t.px.x, t.px.y, sa), pair(t.src.x, t.src.y, sa), LdtkJson_NewInt(int(t.f), sa), LdtkJson_NewInt(int(t.t), sa), d, LdtkJson_NewFloat(t.a, sa))
		append(&arr.items, o)
	}
	return arr
}

// Ldtk_Doc_Serialize returns the project file text and, for external
// levels, each level's file text (relative path -> text). Strings are
// allocated with `allocator`.
Ldtk_Doc_Serialize :: proc(doc: ^Ldtk_Doc, allocator := context.allocator) -> (project: string, levelPaths: []string, levelTexts: []string) {
	scratch: vmem.Arena
	_ = vmem.arena_init_growing(&scratch)
	defer vmem.arena_destroy(&scratch)
	sa := vmem.arena_allocator(&scratch)
	style: LdtkJson_Style = doc.minify ? .Minified : .Compact
	restore := make([dynamic]Ldtk_FlushSwap, sa)
	for &lv in doc.levels {
		r := ldtk_flush_level(doc, &lv, sa)
		append(&restore, ..r[:])
	}
	project = LdtkJson_ToString(doc.root, style, allocator)
	paths := make([dynamic]string, allocator)
	texts := make([dynamic]string, allocator)
	for &lv in doc.levels {
		if lv.extRoot == nil do continue
		append(&paths, strings.clone(LdtkJson_Str(lv.obj, "externalRelPath"), allocator))
		append(&texts, LdtkJson_ToString(lv.extRoot, style, allocator))
	}
	ldtk_unflush(restore[:])
	return project, paths[:], texts[:]
}

// Ldtk_Doc_ToText: the project and its external levels as one string
// (temp allocator; tests and change detection).
Ldtk_Doc_ToText :: proc(doc: ^Ldtk_Doc) -> string {
	proj, _, texts := Ldtk_Doc_Serialize(doc, context.temp_allocator)
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, proj)
	for t in texts do strings.write_string(&b, t)
	return strings.to_string(b)
}

// Ldtk_Doc_Save writes the project (to `path`, default the loaded path) and
// the external levels that changed. Returns false when a write failed.
Ldtk_Doc_Save :: proc(doc: ^Ldtk_Doc, path := "") -> bool {
	target := path != "" ? path : doc.path
	if doc.modified do Ldtk_Doc_UpdateToc(doc)
	project, paths, texts := Ldtk_Doc_Serialize(doc, context.temp_allocator)
	dir := filepath.dir(target, context.temp_allocator)
	ok := os.write_entire_file(target, transmute([]byte)project) == nil
	li := 0
	for &lv in doc.levels {
		if lv.extRoot == nil do continue
		if lv.dirty || path != "" {
			p, _ := filepath.join({dir, paths[li]}, context.temp_allocator)
			_ = os.make_directory_all(filepath.dir(p, context.temp_allocator))
			if os.write_entire_file(p, transmute([]byte)texts[li]) != nil do ok = false
		}
		li += 1
	}
	// external files of removed / renamed levels (unless a level uses it again)
	for f in doc.removedFiles {
		used := false
		for &lv in doc.levels do if LdtkJson_Str(lv.obj, "externalRelPath") == f do used = true
		if !used {
			p, _ := filepath.join({dir, f}, context.temp_allocator)
			if os.is_file(p) do _ = os.remove(p)
		}
		delete(f, doc.heap)
	}
	clear(&doc.removedFiles)
	if ok {
		doc.modified = false
		for &lv in doc.levels do lv.dirty = false
		if path != "" && path != doc.path {
			doc.path = strings.clone(path, doc.allocator)
			doc.dir = strings.clone(dir, doc.allocator)
		}
	}
	return ok
}
