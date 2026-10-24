package engine

import "core:encoding/json"
import "core:fmt"
import "core:mem"
import vmem "core:mem/virtual"
import os "osx"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
import rl "vendor:raylib"

// ============================================================================
// LDtk (Level Designer Toolkit) project data
//
// Ldtk_LoadProjectFromFile / Ldtk_ParseProject read a .ldtk project into an
// LdtkProject: worlds and their levels (external .ldtkl levels included),
// layer instances (IntGrid, Tiles, AutoLayer, Entities), entities with
// their fields and references, level fields, and the definitions - layer
// defs with IntGrid value names/colours, entity defs with field defs,
// enums (local and external) and tilesets with custom data and enum tags.
// Everything lives in one arena owned by the project (Ldtk_DestroyProject).
// The scene node that draws and builds levels is in ldtk_level_node.odin;
// the Lua API in ldtk_bindings.odin.
// ============================================================================

LdtkLayerType :: enum {
	IntGrid,
	Entities,
	Tiles,
	AutoLayer,
}

LdtkFieldType :: enum {
	String,
	Float,
	Int,
	Bool,
	Color,
	Point,
	EntityRef,
	Array,
	Unknown,
}

// LdtkTileRect is a tileset sub-rectangle (entity / field / enum tiles).
LdtkTileRect :: struct {
	tilesetUid: int,
	rect:       rl.Rectangle,
	has:        bool,
}

// LdtkEntityRef: an EntityRef field value - where the target entity lives.
LdtkEntityRef :: struct {
	entityIid: string,
	layerIid:  string,
	levelIid:  string,
	worldIid:  string,
}

LdtkFieldInstance :: struct {
	identifier:  string,
	typeName:    string,          // LDtk __type: "Int", "Array<Point>", "LocalEnum.Kind", ...
	enumName:    string,          // enum fields: the enum's identifier ("Kind")
	valueString: string,          // String / Enum / FilePath / Color hex / EntityRef iid
	valueFloat:  f32,
	valueInt:    int,
	valueBool:   bool,
	valueColor:  rl.Color,
	valuePoint:  [2]f32,          // Point: grid cell (cx, cy)
	entityRef:   string,          // EntityRef: referenced entity iid
	ref:         LdtkEntityRef,   // EntityRef: full reference
	tile:        LdtkTileRect,    // Tile fields
	values:      [dynamic]LdtkFieldInstance, // Array<...> elements
	isArray:     bool,
	isNull:      bool,
}

LdtkEntityInstance :: struct {
	identifier: string,
	iid:        string,
	defUid:     int,
	px:         [2]f32,          // position in the level (pivot point)
	grid:       [2]int,          // grid cell
	worldPos:   [2]f32,          // position in the world (multi-level layouts)
	size:       [2]f32,
	pivot:      [2]f32,
	smartColor: rl.Color,
	tile:       LdtkTileRect,    // the entity's editor visual, if any
	tags:       [dynamic]string,
	fields:     [dynamic]LdtkFieldInstance,
	layerIid:   string,
}

LdtkTileInstance :: struct {
	px:     [2]f32,
	src:    [2]f32,
	size:   [2]f32,
	flipX:  bool,
	flipY:  bool,
	tileId: int,
	alpha:  f32,
}

LdtkLayerInstance :: struct {
	identifier:      string,
	iid:             string,
	type:            LdtkLayerType,
	cWid:            int,
	cHei:            int,
	gridSize:        int,
	opacity:         f32,
	offset:          [2]f32,
	tilesetDefUid:   int,
	tilesetRelPath:  string,
	layerDefUid:     int,
	visible:         bool,     // hidden layers aren't drawn (scripts can toggle it)
	parallax:        [2]f32,   // parallax factors from the layer definition (0 = none)
	parallaxScaling: bool,
	intGrid:         [dynamic]int,
	gridTiles:       [dynamic]LdtkTileInstance,
	autoLayerTiles:  [dynamic]LdtkTileInstance,
	entities:        [dynamic]LdtkEntityInstance,
}

LdtkTilesetDef :: struct {
	uid:               int,
	identifier:        string,
	relPath:           string,
	pxWid:             int,
	pxHei:             int,
	tileGridSize:      int,
	spacing:           int,
	padding:           int,
	texture:           rl.Texture2D,
	textureLoaded:     bool,
	customData:        map[int]string,   // tile id -> custom data string
	tagsSourceEnumUid: int,              // enum whose values tag tiles (-1 = none)
	enumTags:          map[int][dynamic]string, // tile id -> enum value ids
	anims:             map[int]Ldtk_TileAnim,   // animated tiles (custom data "anim=" lines, ldtk_tiles.odin)
}

// Ldtk_TilesetTileSrc: a tile id's top-left pixel in the tileset image.
Ldtk_TilesetTileSrc :: proc(ts: ^LdtkTilesetDef, tid: int) -> [2]f32 {
	step := ts.tileGridSize + ts.spacing
	if step <= 0 do return {}
	cw := max((ts.pxWid - ts.padding * 2 + step - 1) / step, 1)
	return {f32(ts.padding + (tid % cw) * step), f32(ts.padding + (tid / cw) * step)}
}

// --- definitions ---------------------------------------------------------------------

LdtkIntGridValueDef :: struct {
	value:      int,
	identifier: string, // "" when unnamed
	color:      rl.Color,
	groupUid:   int,
	tile:       LdtkTileRect,
}

LdtkLayerDef :: struct {
	uid:             int,
	identifier:      string,
	type:            LdtkLayerType,
	gridSize:        int,
	opacity:         f32,
	parallax:        [2]f32,
	parallaxScaling: bool,
	tilesetUid:      int,
	intGridValues:   [dynamic]LdtkIntGridValueDef,
}

LdtkFieldDef :: struct {
	identifier: string,
	typeName:   string,
	isArray:    bool,
	enumName:   string,
}

LdtkEntityDef :: struct {
	uid:        int,
	identifier: string,
	color:      rl.Color,
	size:       [2]f32,
	tags:       [dynamic]string,
	tile:       LdtkTileRect,
	fields:     [dynamic]LdtkFieldDef,
}

LdtkEnumValue :: struct {
	id:    string,
	color: rl.Color,
	tile:  LdtkTileRect,
}

LdtkEnumDef :: struct {
	uid:          int,
	identifier:   string,
	values:       [dynamic]LdtkEnumValue,
	tags:         [dynamic]string,
	external:     bool,
	externalPath: string,
}

// --- levels & worlds ---------------------------------------------------------------

LdtkNeighbour :: struct {
	levelIid: string,
	dir:      string, // n s e w nw ne sw se < > o
}

LdtkBgPos :: struct {
	topLeft: [2]f32,
	scale:   [2]f32,
	crop:    rl.Rectangle,
	has:     bool,
}

LdtkLevel :: struct {
	identifier: string,
	iid:        string,
	uid:        int,
	worldX:     int,
	worldY:     int,
	worldDepth: int,
	world:      int, // index in project.worlds
	pxWid:      int,
	pxHei:      int,
	bgColor:    rl.Color,
	bgRelPath:  string,
	bgPos:      LdtkBgPos,
	bgTexture:  rl.Texture2D,
	bgLoaded:   bool,
	externalRelPath: string, // "Save levels separately": the level's .ldtkl file
	neighbours: [dynamic]LdtkNeighbour,
	layers:     [dynamic]LdtkLayerInstance,
	fields:     [dynamic]LdtkFieldInstance,
}

LdtkWorld :: struct {
	iid:        string,
	identifier: string,
	layout:     string,  // Free, GridVania, LinearHorizontal, LinearVertical
	gridSize:   [2]int,  // GridVania cell size
	levels:     [dynamic]int, // indices in project.levels
}

@(private = "file")
ldtkLoadCounter: u64

LdtkProject :: struct {
	loadId:              u64,    // unique per parse (render caches key on it)
	filePath:            string,
	basePath:            string,
	iid:                 string,
	jsonVersion:         string,
	worldLayout:         string,
	bgColor:             rl.Color,
	defaultLevelBgColor: rl.Color,
	tilesets:            [dynamic]LdtkTilesetDef,
	levels:              [dynamic]LdtkLevel,
	worlds:              [dynamic]LdtkWorld,
	layerDefs:           [dynamic]LdtkLayerDef,
	entityDefs:          [dynamic]LdtkEntityDef,
	enums:               [dynamic]LdtkEnumDef,
	levelFieldDefs:      [dynamic]LdtkFieldDef,
	externalLevels:      bool,
	multiWorlds:         bool, // the file has a "worlds" array
	allocator:           mem.Allocator, // the project's arena
	arena:               vmem.Arena,
	ownerAllocator:      mem.Allocator, // allocated the LdtkProject itself
	// Reads files relative to the project (external levels, textures); set
	// to read from a mounted .ore package. nil = disk.
	reader:              Ldtk_FileReader,
	readerData:          rawptr,
}

// Ldtk_FileReader reads a file (path already joined with the project dir).
Ldtk_FileReader :: proc(path: string, user: rawptr) -> ([]byte, bool)

// ----------------------------------------------------------------------------
// JSON helpers
// ----------------------------------------------------------------------------

Ldtk_ParseHexColor :: proc(hex: string, defaultColor: rl.Color = rl.BLACK) -> rl.Color {
	s := strings.trim_space(hex)
	if strings.has_prefix(s, "#") do s = s[1:]
	if len(s) == 6 || len(s) == 8 {
		v, ok := strconv.parse_u64(s, 16)
		if !ok do return defaultColor
		if len(s) == 6 do return rl.Color{u8(v >> 16), u8(v >> 8), u8(v), 255}
		return rl.Color{u8(v >> 24), u8(v >> 16), u8(v >> 8), u8(v)}
	}
	return defaultColor
}

@(private)
json_get_obj :: proc(v: json.Value, key: string) -> (json.Object, bool) {
	obj, ok := v.(json.Object)
	if !ok do return nil, false
	child, found := obj[key]
	if !found do return nil, false
	cobj, cok := child.(json.Object)
	return cobj, cok
}

@(private)
json_get_arr :: proc(v: json.Value, key: string) -> (json.Array, bool) {
	obj, ok := v.(json.Object)
	if !ok do return nil, false
	child, found := obj[key]
	if !found do return nil, false
	carr, cok := child.(json.Array)
	return carr, cok
}

@(private)
json_get_str :: proc(v: json.Value, key: string, defaultVal: string = "") -> string {
	obj, ok := v.(json.Object)
	if !ok do return defaultVal
	child, found := obj[key]
	if !found do return defaultVal
	s, sok := child.(json.String)
	return s if sok else defaultVal
}

@(private)
json_get_int :: proc(v: json.Value, key: string, defaultVal: int = 0) -> int {
	obj, ok := v.(json.Object)
	if !ok do return defaultVal
	child, found := obj[key]
	if !found do return defaultVal
	#partial switch n in child {
	case json.Integer: return int(n)
	case json.Float:   return int(n)
	}
	return defaultVal
}

@(private)
json_get_float :: proc(v: json.Value, key: string, defaultVal: f32 = 0.0) -> f32 {
	obj, ok := v.(json.Object)
	if !ok do return defaultVal
	child, found := obj[key]
	if !found do return defaultVal
	#partial switch n in child {
	case json.Float:   return f32(n)
	case json.Integer: return f32(n)
	}
	return defaultVal
}

@(private)
json_get_bool :: proc(v: json.Value, key: string, defaultVal: bool = false) -> bool {
	obj, ok := v.(json.Object)
	if !ok do return defaultVal
	child, found := obj[key]
	if !found do return defaultVal
	b, bok := child.(json.Boolean)
	return bool(b) if bok else defaultVal
}

@(private = "file")
ldtk_num :: proc(v: json.Value) -> f32 {
	#partial switch n in v {
	case json.Integer: return f32(n)
	case json.Float:   return f32(n)
	}
	return 0
}

@(private = "file")
ldtk_vec2 :: proc(v: json.Value, key: string) -> ([2]f32, bool) {
	arr, ok := json_get_arr(v, key)
	if !ok || len(arr) < 2 do return {}, false
	return {ldtk_num(arr[0]), ldtk_num(arr[1])}, true
}

@(private = "file")
ldtk_tile_rect :: proc(v: json.Value) -> LdtkTileRect {
	obj, ok := v.(json.Object)
	if !ok do return {}
	return LdtkTileRect{
		tilesetUid = json_get_int(obj, "tilesetUid", -1),
		rect = {f32(json_get_int(obj, "x")), f32(json_get_int(obj, "y")), f32(json_get_int(obj, "w")), f32(json_get_int(obj, "h"))},
		has = true,
	}
}

@(private = "file")
ldtk_strings :: proc(v: json.Value, key: string, a: mem.Allocator) -> [dynamic]string {
	out := make([dynamic]string, a)
	if arr, ok := json_get_arr(v, key); ok {
		for s in arr do if str, isStr := s.(json.String); isStr do append(&out, strings.clone(str, a))
	}
	return out
}

// Ldtk_EnumNameOf: "LocalEnum.Item" / "Array<ExternEnum.Item>" -> "Item" ("" otherwise).
Ldtk_EnumNameOf :: proc(typeName: string) -> string {
	t := typeName
	if strings.has_prefix(t, "Array<") && strings.has_suffix(t, ">") do t = t[6:len(t) - 1]
	for prefix in ([]string{"LocalEnum.", "ExternEnum."}) {
		if strings.has_prefix(t, prefix) do return t[len(prefix):]
	}
	return ""
}

// parse_field_value fills a field from an LDtk __value of any type.
@(private = "file")
parse_field_value :: proc(fi: ^LdtkFieldInstance, raw: json.Value, a: mem.Allocator) {
	switch v in raw {
	case json.Null:
		fi.isNull = true
	case json.String:
		fi.valueString = strings.clone(v, a)
		if strings.has_prefix(v, "#") do fi.valueColor = Ldtk_ParseHexColor(v)
	case json.Integer:
		fi.valueInt = int(v)
		fi.valueFloat = f32(v)
	case json.Float:
		fi.valueFloat = f32(v)
		fi.valueInt = int(v)
	case json.Boolean:
		fi.valueBool = bool(v)
	case json.Object:
		if _, isPoint := v["cx"]; isPoint {
			fi.valuePoint = {ldtk_num(v["cx"]), ldtk_num(v["cy"])}
		} else if iid, isRef := v["entityIid"].(json.String); isRef {
			fi.ref = LdtkEntityRef{
				entityIid = strings.clone(iid, a),
				layerIid = strings.clone(json_get_str(v, "layerIid"), a),
				levelIid = strings.clone(json_get_str(v, "levelIid"), a),
				worldIid = strings.clone(json_get_str(v, "worldIid"), a),
			}
			fi.entityRef = fi.ref.entityIid
			fi.valueString = fi.ref.entityIid
		} else if _, isTile := v["tilesetUid"]; isTile {
			fi.tile = ldtk_tile_rect(v)
		}
	case json.Array:
		fi.isArray = true
		fi.values = make([dynamic]LdtkFieldInstance, a)
		for item in v {
			el := LdtkFieldInstance{identifier = fi.identifier, typeName = fi.typeName, enumName = fi.enumName}
			parse_field_value(&el, item, a)
			append(&fi.values, el)
		}
	}
}

@(private = "file")
parse_fields :: proc(arr: json.Array, a: mem.Allocator) -> [dynamic]LdtkFieldInstance {
	out := make([dynamic]LdtkFieldInstance, a)
	for fVal in arr {
		fObj, ok := fVal.(json.Object)
		if !ok do continue
		fi := LdtkFieldInstance{
			identifier = strings.clone(json_get_str(fObj, "__identifier"), a),
			typeName = strings.clone(json_get_str(fObj, "__type"), a),
		}
		fi.enumName = Ldtk_EnumNameOf(fi.typeName)
		raw, has := fObj["__value"]
		if !has do fi.isNull = true
		else do parse_field_value(&fi, raw, a)
		append(&out, fi)
	}
	return out
}

@(private = "file")
parse_field_defs :: proc(arr: json.Array, a: mem.Allocator) -> [dynamic]LdtkFieldDef {
	out := make([dynamic]LdtkFieldDef, a)
	for v in arr {
		t := strings.clone(json_get_str(v, "__type"), a)
		append(&out, LdtkFieldDef{
			identifier = strings.clone(json_get_str(v, "identifier"), a),
			typeName = t,
			isArray = json_get_bool(v, "isArray") || strings.has_prefix(t, "Array<"),
			enumName = Ldtk_EnumNameOf(t),
		})
	}
	return out
}

@(private = "file")
layer_type_of :: proc(s: string) -> LdtkLayerType {
	switch s {
	case "Entities":  return .Entities
	case "Tiles":     return .Tiles
	case "AutoLayer": return .AutoLayer
	}
	return .IntGrid
}

@(private = "file")
ldtk_read :: proc(project: ^LdtkProject, rel: string) -> ([]byte, bool) {
	path := rel
	if !filepath.is_abs(rel) && project.basePath != "" {
		joined, _ := filepath.join({project.basePath, rel}, context.temp_allocator)
		path, _ = filepath.clean(joined, context.temp_allocator)
	}
	if project.reader != nil do return project.reader(path, project.readerData)
	data, err := os.read_entire_file(path, context.temp_allocator)
	return data, err == nil
}

// ----------------------------------------------------------------------------
// Parsing
// ----------------------------------------------------------------------------

Ldtk_ParseProject :: proc(jsonBytes: []u8, basePath: string = "", allocator := context.allocator, reader: Ldtk_FileReader = nil, readerData: rawptr = nil) -> (^LdtkProject, bool) {
	parsedVal, err := json.parse(jsonBytes, allocator = context.temp_allocator)
	if err != .None do return nil, false
	rootObj, isObj := parsedVal.(json.Object)
	if !isObj do return nil, false

	project := new(LdtkProject, allocator)
	project.ownerAllocator = allocator
	ldtkLoadCounter += 1
	project.loadId = ldtkLoadCounter
	if vmem.arena_init_growing(&project.arena) != nil {
		free(project, allocator)
		return nil, false
	}
	a := vmem.arena_allocator(&project.arena)
	project.allocator = a
	project.basePath = strings.clone(basePath, a)
	project.reader, project.readerData = reader, readerData
	project.iid = strings.clone(json_get_str(rootObj, "iid"), a)
	project.jsonVersion = strings.clone(json_get_str(rootObj, "jsonVersion"), a)
	project.worldLayout = strings.clone(json_get_str(rootObj, "worldLayout", "Free"), a)
	project.bgColor = Ldtk_ParseHexColor(json_get_str(rootObj, "bgColor", "#40465B"))
	project.defaultLevelBgColor = Ldtk_ParseHexColor(json_get_str(rootObj, "defaultLevelBgColor", "#696A79"))
	project.externalLevels = json_get_bool(rootObj, "externalLevels", false)
	project.tilesets = make([dynamic]LdtkTilesetDef, a)
	project.levels = make([dynamic]LdtkLevel, a)
	project.worlds = make([dynamic]LdtkWorld, a)
	project.layerDefs = make([dynamic]LdtkLayerDef, a)
	project.entityDefs = make([dynamic]LdtkEntityDef, a)
	project.enums = make([dynamic]LdtkEnumDef, a)
	project.levelFieldDefs = make([dynamic]LdtkFieldDef, a)

	if defs, hasDefs := json_get_obj(rootObj, "defs"); hasDefs {
		parse_defs(project, defs)
	}

	// Worlds: the "worlds" array (multi-worlds projects), else one world
	// holding the top-level "levels".
	if worldsArr, ok := json_get_arr(rootObj, "worlds"); ok && len(worldsArr) > 0 {
		project.multiWorlds = true
		for wv in worldsArr {
			wi := len(project.worlds)
			append(&project.worlds, LdtkWorld{
				iid = strings.clone(json_get_str(wv, "iid"), a),
				identifier = strings.clone(json_get_str(wv, "identifier", fmt.tprintf("World_%d", wi)), a),
				layout = strings.clone(json_get_str(wv, "worldLayout", project.worldLayout), a),
				gridSize = {json_get_int(wv, "worldGridWidth", 256), json_get_int(wv, "worldGridHeight", 256)},
				levels = make([dynamic]int, a),
			})
			if wLevels, has := json_get_arr(wv, "levels"); has {
				for lv in wLevels do parse_level(project, lv, wi)
			}
		}
	}
	if levelsArr, ok := json_get_arr(rootObj, "levels"); ok && len(levelsArr) > 0 {
		wi := len(project.worlds)
		append(&project.worlds, LdtkWorld{
			iid = strings.clone(json_get_str(rootObj, "dummyWorldIid"), a),
			identifier = strings.clone("World", a),
			layout = project.worldLayout,
			gridSize = {json_get_int(rootObj, "worldGridWidth", 256), json_get_int(rootObj, "worldGridHeight", 256)},
			levels = make([dynamic]int, a),
		})
		for lv in levelsArr do parse_level(project, lv, wi)
	}
	return project, true
}

@(private = "file")
parse_defs :: proc(project: ^LdtkProject, defs: json.Object) {
	a := project.allocator
	if tilesetsArr, ok := json_get_arr(defs, "tilesets"); ok {
		for tsObj in tilesetsArr {
			ts: LdtkTilesetDef
			ts.uid = json_get_int(tsObj, "uid")
			ts.identifier = strings.clone(json_get_str(tsObj, "identifier"), a)
			ts.relPath = strings.clone(json_get_str(tsObj, "relPath"), a)
			ts.pxWid = json_get_int(tsObj, "pxWid")
			ts.pxHei = json_get_int(tsObj, "pxHei")
			ts.tileGridSize = json_get_int(tsObj, "tileGridSize", 16)
			ts.spacing = json_get_int(tsObj, "spacing", 0)
			ts.padding = json_get_int(tsObj, "padding", 0)
			ts.tagsSourceEnumUid = json_get_int(tsObj, "tagsSourceEnumUid", -1)
			ts.customData = make(map[int]string, allocator = a)
			ts.enumTags = make(map[int][dynamic]string, allocator = a)
			ts.anims = make(map[int]Ldtk_TileAnim, allocator = a)
			if cd, has := json_get_arr(tsObj, "customData"); has {
				for item in cd {
					data := strings.clone(json_get_str(item, "data"), a)
					ts.customData[json_get_int(item, "tileId")] = data
					if anim, ok := Ldtk_ParseTileAnim(data, a); ok do ts.anims[json_get_int(item, "tileId")] = anim
				}
			}
			if tags, has := json_get_arr(tsObj, "enumTags"); has {
				for tag in tags {
					id := strings.clone(json_get_str(tag, "enumValueId"), a)
					if ids, hasIds := json_get_arr(tag, "tileIds"); hasIds {
						for tid in ids {
							key := int(ldtk_num(tid))
							if key not_in ts.enumTags do ts.enumTags[key] = make([dynamic]string, a)
							append(&ts.enumTags[key], id)
						}
					}
				}
			}
			append(&project.tilesets, ts)
		}
	}
	if layersArr, ok := json_get_arr(defs, "layers"); ok {
		for lv in layersArr {
			ld := LdtkLayerDef{
				uid = json_get_int(lv, "uid"),
				identifier = strings.clone(json_get_str(lv, "identifier"), a),
				type = layer_type_of(json_get_str(lv, "__type", json_get_str(lv, "type"))),
				gridSize = json_get_int(lv, "gridSize", 16),
				opacity = json_get_float(lv, "displayOpacity", 1),
				parallax = {json_get_float(lv, "parallaxFactorX", 0), json_get_float(lv, "parallaxFactorY", 0)},
				parallaxScaling = json_get_bool(lv, "parallaxScaling", true),
				tilesetUid = json_get_int(lv, "tilesetDefUid", -1),
				intGridValues = make([dynamic]LdtkIntGridValueDef, a),
			}
			if vals, has := json_get_arr(lv, "intGridValues"); has {
				for v in vals {
					iv := LdtkIntGridValueDef{
						value = json_get_int(v, "value"),
						identifier = strings.clone(json_get_str(v, "identifier"), a),
						color = Ldtk_ParseHexColor(json_get_str(v, "color", "#FFFFFF"), rl.WHITE),
						groupUid = json_get_int(v, "groupUid"),
					}
					if obj, isObj := v.(json.Object); isObj {
						if t, hasT := obj["tile"]; hasT do iv.tile = ldtk_tile_rect(t)
					}
					append(&ld.intGridValues, iv)
				}
			}
			append(&project.layerDefs, ld)
		}
	}
	if entArr, ok := json_get_arr(defs, "entities"); ok {
		for ev in entArr {
			ed := LdtkEntityDef{
				uid = json_get_int(ev, "uid"),
				identifier = strings.clone(json_get_str(ev, "identifier"), a),
				color = Ldtk_ParseHexColor(json_get_str(ev, "color", "#FFFFFF"), rl.WHITE),
				size = {json_get_float(ev, "width", 16), json_get_float(ev, "height", 16)},
				tags = ldtk_strings(ev, "tags", a),
			}
			if obj, isObj := ev.(json.Object); isObj {
				if t, hasT := obj["uiTileRect"]; hasT do ed.tile = ldtk_tile_rect(t)
				if !ed.tile.has {
					if t, hasT := obj["tileRect"]; hasT do ed.tile = ldtk_tile_rect(t)
				}
			}
			if fd, has := json_get_arr(ev, "fieldDefs"); has do ed.fields = parse_field_defs(fd, a)
			else do ed.fields = make([dynamic]LdtkFieldDef, a)
			append(&project.entityDefs, ed)
		}
	}
	parse_enums :: proc(project: ^LdtkProject, arr: json.Array, external: bool) {
		a := project.allocator
		for ev in arr {
			en := LdtkEnumDef{
				uid = json_get_int(ev, "uid"),
				identifier = strings.clone(json_get_str(ev, "identifier"), a),
				values = make([dynamic]LdtkEnumValue, a),
				tags = ldtk_strings(ev, "tags", a),
				external = external,
				externalPath = strings.clone(json_get_str(ev, "externalRelPath"), a),
			}
			if vals, has := json_get_arr(ev, "values"); has {
				for v in vals {
					c := json_get_int(v, "color", 0xFFFFFF)
					val := LdtkEnumValue{
						id = strings.clone(json_get_str(v, "id"), a),
						color = rl.Color{u8(c >> 16), u8(c >> 8), u8(c), 255},
					}
					if obj, isObj := v.(json.Object); isObj {
						if t, hasT := obj["tileRect"]; hasT do val.tile = ldtk_tile_rect(t)
					}
					append(&en.values, val)
				}
			}
			append(&project.enums, en)
		}
	}
	if arr, ok := json_get_arr(defs, "enums"); ok do parse_enums(project, arr, false)
	if arr, ok := json_get_arr(defs, "externalEnums"); ok do parse_enums(project, arr, true)
	if arr, ok := json_get_arr(defs, "levelFields"); ok {
		delete(project.levelFieldDefs)
		project.levelFieldDefs = parse_field_defs(arr, a)
	}
}

@(private = "file")
parse_level :: proc(project: ^LdtkProject, lvlVal: json.Value, worldIndex: int) {
	a := project.allocator
	lvlObj, lvlOk := lvlVal.(json.Object)
	if !lvlOk do return

	// "Save levels separately": the layers are in the level's own file.
	externalRel := json_get_str(lvlObj, "externalRelPath")
	layerSource := json.Value(lvlObj)
	if externalRel != "" {
		if data, ok := ldtk_read(project, externalRel); ok {
			if ext, perr := json.parse(data, allocator = context.temp_allocator); perr == .None do layerSource = ext
		} else {
			fmt.eprintfln("[LDtk] External level not found: %s", externalRel)
		}
	}

	level: LdtkLevel
	level.identifier = strings.clone(json_get_str(lvlObj, "identifier"), a)
	level.iid = strings.clone(json_get_str(lvlObj, "iid"), a)
	level.uid = json_get_int(lvlObj, "uid")
	level.worldX = json_get_int(lvlObj, "worldX", 0)
	level.worldY = json_get_int(lvlObj, "worldY", 0)
	level.worldDepth = json_get_int(lvlObj, "worldDepth", 0)
	level.world = worldIndex
	level.pxWid = json_get_int(lvlObj, "pxWid", 256)
	level.pxHei = json_get_int(lvlObj, "pxHei", 256)
	bgColStr := json_get_str(lvlObj, "__bgColor")
	if bgColStr == "" do bgColStr = json_get_str(lvlObj, "bgColor")
	level.bgColor = Ldtk_ParseHexColor(bgColStr, project.defaultLevelBgColor)
	level.bgRelPath = strings.clone(json_get_str(lvlObj, "bgRelPath"), a)
	level.externalRelPath = strings.clone(externalRel, a)
	if bp, has := json_get_obj(lvlObj, "__bgPos"); has {
		tl, _ := ldtk_vec2(bp, "topLeftPx")
		sc, _ := ldtk_vec2(bp, "scale")
		level.bgPos.topLeft = tl
		level.bgPos.scale = sc
		if crop, ok := json_get_arr(bp, "cropRect"); ok && len(crop) >= 4 {
			level.bgPos.crop = {ldtk_num(crop[0]), ldtk_num(crop[1]), ldtk_num(crop[2]), ldtk_num(crop[3])}
		}
		level.bgPos.has = true
	}
	level.layers = make([dynamic]LdtkLayerInstance, a)
	level.neighbours = make([dynamic]LdtkNeighbour, a)
	if nb, has := json_get_arr(lvlObj, "__neighbours"); has {
		for n in nb do append(&level.neighbours, LdtkNeighbour{strings.clone(json_get_str(n, "levelIid"), a), strings.clone(json_get_str(n, "dir"), a)})
	}
	if fieldsArr, has := json_get_arr(lvlObj, "fieldInstances"); has do level.fields = parse_fields(fieldsArr, a)
	else do level.fields = make([dynamic]LdtkFieldInstance, a)

	if layersArr, hasLayers := json_get_arr(layerSource, "layerInstances"); hasLayers {
		for lObj in layersArr {
			if _, ok := lObj.(json.Object); !ok do continue
			layer: LdtkLayerInstance
			layer.identifier = strings.clone(json_get_str(lObj, "__identifier"), a)
			layer.iid = strings.clone(json_get_str(lObj, "iid"), a)
			layer.type = layer_type_of(json_get_str(lObj, "__type"))
			layer.cWid = json_get_int(lObj, "__cWid")
			layer.cHei = json_get_int(lObj, "__cHei")
			layer.gridSize = json_get_int(lObj, "__gridSize", 16)
			layer.opacity = json_get_float(lObj, "__opacity", 1.0)
			layer.visible = json_get_bool(lObj, "visible", true)
			layer.offset = {json_get_float(lObj, "__pxTotalOffsetX", 0.0), json_get_float(lObj, "__pxTotalOffsetY", 0.0)}
			layer.tilesetDefUid = json_get_int(lObj, "__tilesetDefUid", -1)
			layer.tilesetRelPath = strings.clone(json_get_str(lObj, "__tilesetRelPath"), a)
			layer.layerDefUid = json_get_int(lObj, "layerDefUid", -1)
			if def := Ldtk_GetLayerDef(project, layer.layerDefUid); def != nil {
				layer.parallax = def.parallax
				layer.parallaxScaling = def.parallaxScaling
			}
			layer.intGrid = make([dynamic]int, a)
			layer.gridTiles = make([dynamic]LdtkTileInstance, a)
			layer.autoLayerTiles = make([dynamic]LdtkTileInstance, a)
			layer.entities = make([dynamic]LdtkEntityInstance, a)

			if csvArr, hasCsv := json_get_arr(lObj, "intGridCsv"); hasCsv {
				for c in csvArr do append(&layer.intGrid, int(ldtk_num(c)))
			}
			parse_tiles :: proc(arr: json.Array, target: ^[dynamic]LdtkTileInstance, gridSize: f32) {
				for item in arr {
					tile := LdtkTileInstance{alpha = 1.0, size = {gridSize, gridSize}}
					if px, ok := ldtk_vec2(item, "px"); ok do tile.px = px
					if src, ok := ldtk_vec2(item, "src"); ok do tile.src = src
					fBits := json_get_int(item, "f", 0)
					tile.flipX = (fBits & 1) != 0
					tile.flipY = (fBits & 2) != 0
					tile.tileId = json_get_int(item, "t", 0)
					tile.alpha = json_get_float(item, "a", 1.0)
					append(target, tile)
				}
			}
			if autoArr, has := json_get_arr(lObj, "autoLayerTiles"); has do parse_tiles(autoArr, &layer.autoLayerTiles, f32(layer.gridSize))
			if gridArr, has := json_get_arr(lObj, "gridTiles"); has do parse_tiles(gridArr, &layer.gridTiles, f32(layer.gridSize))

			if entArr, hasEnt := json_get_arr(lObj, "entityInstances"); hasEnt {
				for eObj in entArr {
					ent: LdtkEntityInstance
					ent.identifier = strings.clone(json_get_str(eObj, "__identifier"), a)
					ent.iid = strings.clone(json_get_str(eObj, "iid"), a)
					ent.layerIid = layer.iid
					ent.defUid = json_get_int(eObj, "defUid")
					ent.size = {json_get_float(eObj, "width", 16.0), json_get_float(eObj, "height", 16.0)}
					if px, ok := ldtk_vec2(eObj, "px"); ok do ent.px = px
					if piv, ok := ldtk_vec2(eObj, "__pivot"); ok do ent.pivot = piv
					if g, ok := ldtk_vec2(eObj, "__grid"); ok do ent.grid = {int(g.x), int(g.y)}
					ent.worldPos = {json_get_float(eObj, "__worldX", f32(level.worldX) + ent.px.x), json_get_float(eObj, "__worldY", f32(level.worldY) + ent.px.y)}
					ent.smartColor = Ldtk_ParseHexColor(json_get_str(eObj, "__smartColor", "#FFFFFF"), rl.WHITE)
					if obj, ok := eObj.(json.Object); ok {
						if t, has := obj["__tile"]; has do ent.tile = ldtk_tile_rect(t)
					}
					ent.tags = ldtk_strings(eObj, "__tags", a)
					if fieldsArr, has := json_get_arr(eObj, "fieldInstances"); has do ent.fields = parse_fields(fieldsArr, a)
					else do ent.fields = make([dynamic]LdtkFieldInstance, a)
					append(&layer.entities, ent)
				}
			}
			append(&level.layers, layer)
		}
	}
	append(&project.worlds[worldIndex].levels, len(project.levels))
	append(&project.levels, level)
}

Ldtk_LoadProjectFromFile :: proc(filePath: string, allocator := context.allocator, reader: Ldtk_FileReader = nil, readerData: rawptr = nil) -> (^LdtkProject, bool) {
	data: []byte
	if reader != nil {
		d, ok := reader(filePath, readerData)
		if !ok do return nil, false
		data = d
	} else {
		d, readErr := os.read_entire_file(filePath, context.temp_allocator)
		if readErr != nil do return nil, false
		data = d
	}
	baseDir := filepath.dir(filePath, context.temp_allocator)
	proj, parseOk := Ldtk_ParseProject(data, baseDir, allocator, reader, readerData)
	if parseOk && proj != nil do proj.filePath = strings.clone(filePath, proj.allocator)
	return proj, parseOk
}

Ldtk_DestroyProject :: proc(project: ^LdtkProject) {
	if project == nil do return
	Ldtk_UnloadTextures(project)
	vmem.arena_destroy(&project.arena)
	free(project, project.ownerAllocator)
}

// ----------------------------------------------------------------------------
// Textures
// ----------------------------------------------------------------------------

@(private = "file")
ldtk_load_texture :: proc(project: ^LdtkProject, rel: string) -> rl.Texture2D {
	data, ok := ldtk_read(project, rel)
	if !ok do return {}
	img := rl.LoadImageFromMemory(fmt.ctprintf("%s", filepath.ext(rel)), raw_data(data), i32(len(data)))
	defer rl.UnloadImage(img)
	return rl.LoadTextureFromImage(img)
}

Ldtk_LoadTextures :: proc(project: ^LdtkProject) {
	if project == nil || !rl.IsWindowReady() do return
	for &ts in project.tilesets {
		if ts.textureLoaded || len(ts.relPath) == 0 do continue
		ts.texture = ldtk_load_texture(project, ts.relPath)
		ts.textureLoaded = ts.texture.id > 0
	}
	for &lvl in project.levels {
		if lvl.bgLoaded || len(lvl.bgRelPath) == 0 do continue
		lvl.bgTexture = ldtk_load_texture(project, lvl.bgRelPath)
		lvl.bgLoaded = lvl.bgTexture.id > 0
	}
}

Ldtk_UnloadTextures :: proc(project: ^LdtkProject) {
	if project == nil || !rl.IsWindowReady() do return
	for &ts in project.tilesets {
		if ts.textureLoaded {
			rl.UnloadTexture(ts.texture)
			ts.textureLoaded = false
			ts.texture = {}
		}
	}
	for &lvl in project.levels {
		if lvl.bgLoaded {
			rl.UnloadTexture(lvl.bgTexture)
			lvl.bgLoaded = false
			lvl.bgTexture = {}
		}
	}
}

// ----------------------------------------------------------------------------
// Queries
// ----------------------------------------------------------------------------

Ldtk_GetLevel :: proc(project: ^LdtkProject, identifier: string) -> ^LdtkLevel {
	if project == nil do return nil
	for &lvl in project.levels do if lvl.identifier == identifier do return &lvl
	return nil
}

Ldtk_GetLevelByIid :: proc(project: ^LdtkProject, iid: string) -> ^LdtkLevel {
	if project == nil || iid == "" do return nil
	for &lvl in project.levels do if lvl.iid == iid do return &lvl
	return nil
}

// Ldtk_GetLevelInWorld: a level by identifier within one world (identifiers
// may repeat across worlds).
Ldtk_GetLevelInWorld :: proc(project: ^LdtkProject, world: ^LdtkWorld, identifier: string) -> ^LdtkLevel {
	if project == nil do return nil
	if world == nil do return Ldtk_GetLevel(project, identifier)
	for i in world.levels do if project.levels[i].identifier == identifier do return &project.levels[i]
	return nil
}

Ldtk_GetLevelByIndex :: proc(project: ^LdtkProject, index: int) -> ^LdtkLevel {
	if project == nil || index < 0 || index >= len(project.levels) do return nil
	return &project.levels[index]
}

Ldtk_GetWorld :: proc(project: ^LdtkProject, identifier: string) -> ^LdtkWorld {
	if project == nil do return nil
	for &w in project.worlds do if w.identifier == identifier || (identifier != "" && w.iid == identifier) do return &w
	return nil
}

// Ldtk_WorldOf: the world a level belongs to.
Ldtk_WorldOf :: proc(project: ^LdtkProject, level: ^LdtkLevel) -> ^LdtkWorld {
	if project == nil || level == nil || level.world < 0 || level.world >= len(project.worlds) do return nil
	return &project.worlds[level.world]
}

// Ldtk_LevelAt: the level of `world` containing a world-space pixel at
// `depth` (nil if none).
Ldtk_LevelAt :: proc(project: ^LdtkProject, world: ^LdtkWorld, p: [2]f32, depth := 0) -> ^LdtkLevel {
	if project == nil || world == nil do return nil
	for i in world.levels {
		l := &project.levels[i]
		if l.worldDepth != depth do continue
		if p.x >= f32(l.worldX) && p.y >= f32(l.worldY) && p.x < f32(l.worldX + l.pxWid) && p.y < f32(l.worldY + l.pxHei) do return l
	}
	return nil
}

Ldtk_GetTilesetByUid :: proc(project: ^LdtkProject, uid: int) -> ^LdtkTilesetDef {
	if project == nil do return nil
	for &ts in project.tilesets do if ts.uid == uid do return &ts
	return nil
}

Ldtk_GetTilesetByRelPath :: proc(project: ^LdtkProject, relPath: string) -> ^LdtkTilesetDef {
	if project == nil do return nil
	for &ts in project.tilesets do if ts.relPath == relPath do return &ts
	return nil
}

Ldtk_GetLayerDef :: proc(project: ^LdtkProject, uid: int) -> ^LdtkLayerDef {
	if project == nil do return nil
	for &d in project.layerDefs do if d.uid == uid do return &d
	return nil
}

Ldtk_GetLayerDefByName :: proc(project: ^LdtkProject, identifier: string) -> ^LdtkLayerDef {
	if project == nil do return nil
	for &d in project.layerDefs do if d.identifier == identifier do return &d
	return nil
}

// Ldtk_GetIntGridValueDef: name and colour of an IntGrid value of a layer.
Ldtk_GetIntGridValueDef :: proc(project: ^LdtkProject, layer: ^LdtkLayerInstance, value: int) -> ^LdtkIntGridValueDef {
	if layer == nil do return nil
	def := Ldtk_GetLayerDef(project, layer.layerDefUid)
	if def == nil do def = Ldtk_GetLayerDefByName(project, layer.identifier)
	if def == nil do return nil
	for &v in def.intGridValues do if v.value == value do return &v
	return nil
}

Ldtk_GetEntityDef :: proc(project: ^LdtkProject, identifier: string) -> ^LdtkEntityDef {
	if project == nil do return nil
	for &d in project.entityDefs do if d.identifier == identifier do return &d
	return nil
}

Ldtk_GetEnum :: proc(project: ^LdtkProject, identifier: string) -> ^LdtkEnumDef {
	if project == nil do return nil
	for &en in project.enums do if en.identifier == identifier do return &en
	return nil
}

Ldtk_GetEnumByUid :: proc(project: ^LdtkProject, uid: int) -> ^LdtkEnumDef {
	if project == nil do return nil
	for &en in project.enums do if en.uid == uid do return &en
	return nil
}

// Ldtk_GetEnumValue: an enum value's colour and tile (and its index).
Ldtk_GetEnumValue :: proc(project: ^LdtkProject, enumName, id: string) -> (^LdtkEnumValue, int) {
	en := Ldtk_GetEnum(project, enumName)
	if en == nil do return nil, -1
	for &v, i in en.values do if v.id == id do return &v, i
	return nil, -1
}

Ldtk_GetLayer :: proc(level: ^LdtkLevel, identifier: string) -> ^LdtkLayerInstance {
	if level == nil do return nil
	for &layer in level.layers do if layer.identifier == identifier do return &layer
	return nil
}

Ldtk_GetIntGridValue :: proc(layer: ^LdtkLayerInstance, gx, gy: int) -> int {
	if layer == nil do return 0
	if gx < 0 || gx >= layer.cWid || gy < 0 || gy >= layer.cHei do return 0
	idx := gy * layer.cWid + gx
	if idx >= 0 && idx < len(layer.intGrid) do return layer.intGrid[idx]
	return 0
}

// Ldtk_PixelToCell: level pixel -> layer cell (may be outside the layer).
Ldtk_PixelToCell :: proc(layer: ^LdtkLayerInstance, px, py: f32) -> (int, int) {
	if layer == nil || layer.gridSize <= 0 do return -1, -1
	g := f32(layer.gridSize)
	return int(floor_f32((px - layer.offset.x) / g)), int(floor_f32((py - layer.offset.y) / g))
}

@(private = "file")
floor_f32 :: proc(v: f32) -> f32 {
	i := f32(int(v))
	return i - 1 if v < 0 && i != v else i
}

Ldtk_GetIntGridValueAtPixel :: proc(layer: ^LdtkLayerInstance, px, py: f32) -> int {
	gx, gy := Ldtk_PixelToCell(layer, px, py)
	return Ldtk_GetIntGridValue(layer, gx, gy)
}

// Ldtk_GetTileAt: the topmost tile of a Tiles/AutoLayer layer covering a
// level pixel.
Ldtk_GetTileAt :: proc(layer: ^LdtkLayerInstance, px, py: f32) -> (LdtkTileInstance, bool) {
	if layer == nil do return {}, false
	p := [2]f32{px, py} - layer.offset
	lists := [2][]LdtkTileInstance{layer.gridTiles[:], layer.autoLayerTiles[:]}
	for list in lists {
		#reverse for t in list {
			if p.x >= t.px.x && p.y >= t.px.y && p.x < t.px.x + t.size.x && p.y < t.px.y + t.size.y do return t, true
		}
	}
	return {}, false
}

// Ldtk_GetTileEnumTags: enum values tagging a tileset tile.
Ldtk_GetTileEnumTags :: proc(project: ^LdtkProject, tilesetUid, tileId: int) -> []string {
	ts := Ldtk_GetTilesetByUid(project, tilesetUid)
	if ts == nil do return nil
	if tags, ok := ts.enumTags[tileId]; ok do return tags[:]
	return nil
}

// Ldtk_GetTileCustomData returns the custom data string of a tileset tile.
Ldtk_GetTileCustomData :: proc(project: ^LdtkProject, tilesetUid, tileId: int) -> string {
	ts := Ldtk_GetTilesetByUid(project, tilesetUid)
	if ts == nil do return ""
	return ts.customData[tileId]
}

Ldtk_GetEntity :: proc(level: ^LdtkLevel, identifier: string) -> ^LdtkEntityInstance {
	if level == nil do return nil
	for &layer in level.layers do for &ent in layer.entities do if ent.identifier == identifier do return &ent
	return nil
}

Ldtk_GetEntities :: proc(level: ^LdtkLevel, identifier: string = "", allocator := context.temp_allocator) -> [dynamic]^LdtkEntityInstance {
	res := make([dynamic]^LdtkEntityInstance, allocator)
	if level == nil do return res
	for &layer in level.layers {
		for &ent in layer.entities do if identifier == "" || ent.identifier == identifier do append(&res, &ent)
	}
	return res
}

Ldtk_GetEntityByIid :: proc(level: ^LdtkLevel, iid: string) -> ^LdtkEntityInstance {
	if level == nil do return nil
	for &layer in level.layers do for &ent in layer.entities do if ent.iid == iid do return &ent
	return nil
}

// Ldtk_FindEntity finds an entity anywhere in the project (references may
// cross levels and worlds).
Ldtk_FindEntity :: proc(project: ^LdtkProject, iid: string) -> (^LdtkEntityInstance, ^LdtkLevel) {
	if project == nil || iid == "" do return nil, nil
	for &lvl in project.levels {
		if ent := Ldtk_GetEntityByIid(&lvl, iid); ent != nil do return ent, &lvl
	}
	return nil, nil
}

// Ldtk_EntityRefs lists the EntityRef values of an entity's fields (arrays
// included) as (field, reference) pairs.
Ldtk_EntityRef_Entry :: struct {
	field: string,
	ref:   LdtkEntityRef,
	index: int, // element of an array field (-1 = single)
}

Ldtk_EntityRefs :: proc(entity: ^LdtkEntityInstance, allocator := context.temp_allocator) -> [dynamic]Ldtk_EntityRef_Entry {
	out := make([dynamic]Ldtk_EntityRef_Entry, allocator)
	if entity == nil do return out
	for &f in entity.fields {
		if f.isArray {
			for &el, i in f.values do if el.ref.entityIid != "" do append(&out, Ldtk_EntityRef_Entry{f.identifier, el.ref, i})
		} else if f.ref.entityIid != "" {
			append(&out, Ldtk_EntityRef_Entry{f.identifier, f.ref, -1})
		}
	}
	return out
}

Ldtk_GetField :: proc(entity: ^LdtkEntityInstance, identifier: string) -> ^LdtkFieldInstance {
	if entity == nil do return nil
	for &f in entity.fields do if f.identifier == identifier do return &f
	return nil
}

Ldtk_GetFieldString :: proc(entity: ^LdtkEntityInstance, identifier: string, defaultVal: string = "") -> string {
	f := Ldtk_GetField(entity, identifier)
	if f != nil && !f.isNull && len(f.valueString) > 0 do return f.valueString
	return defaultVal
}

Ldtk_GetFieldFloat :: proc(entity: ^LdtkEntityInstance, identifier: string, defaultVal: f32 = 0.0) -> f32 {
	f := Ldtk_GetField(entity, identifier)
	if f != nil && !f.isNull do return f.valueFloat
	return defaultVal
}

Ldtk_GetFieldInt :: proc(entity: ^LdtkEntityInstance, identifier: string, defaultVal: int = 0) -> int {
	f := Ldtk_GetField(entity, identifier)
	if f != nil && !f.isNull do return f.valueInt
	return defaultVal
}

Ldtk_GetFieldBool :: proc(entity: ^LdtkEntityInstance, identifier: string, defaultVal: bool = false) -> bool {
	f := Ldtk_GetField(entity, identifier)
	if f != nil && !f.isNull do return f.valueBool
	return defaultVal
}

Ldtk_GetFieldColor :: proc(entity: ^LdtkEntityInstance, identifier: string, defaultVal: rl.Color = rl.WHITE) -> rl.Color {
	f := Ldtk_GetField(entity, identifier)
	if f != nil && !f.isNull do return f.valueColor
	return defaultVal
}

Ldtk_GetLevelField :: proc(level: ^LdtkLevel, identifier: string) -> ^LdtkFieldInstance {
	if level == nil do return nil
	for &f in level.fields do if f.identifier == identifier do return &f
	return nil
}

// Ldtk_FieldValueText: a field's value as display text ("null", "[a, b]").
Ldtk_FieldValueText :: proc(f: ^LdtkFieldInstance, allocator := context.temp_allocator) -> string {
	if f.isNull do return "null"
	if f.isArray {
		sb := strings.builder_make(allocator)
		strings.write_byte(&sb, '[')
		for &el, i in f.values {
			if i > 0 do strings.write_string(&sb, ", ")
			strings.write_string(&sb, Ldtk_FieldValueText(&el, allocator))
		}
		strings.write_byte(&sb, ']')
		return strings.to_string(sb)
	}
	t := f.typeName
	switch {
	case t == "Int": return fmt.aprint(f.valueInt, allocator = allocator)
	case t == "Float": return fmt.aprintf("%g", f.valueFloat, allocator = allocator)
	case t == "Bool": return "true" if f.valueBool else "false"
	case strings.contains(t, "Point"): return fmt.aprintf("(%d, %d)", int(f.valuePoint.x), int(f.valuePoint.y), allocator = allocator)
	case f.ref.entityIid != "": return fmt.aprintf("-> %s", f.ref.entityIid, allocator = allocator)
	case f.tile.has: return fmt.aprintf("tile %d,%d", int(f.tile.rect.x), int(f.tile.rect.y), allocator = allocator)
	}
	return f.valueString
}
