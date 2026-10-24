package engine

import "core:math"
import "core:strings"

// ============================================================================
// Ldtk_Doc layer definitions (LDtk's EditLayerDefs / Definitions): grid
// changes that keep the content (LayerInstance.remapToGridSize), copy /
// paste / duplicate, baking an auto layer to a Tiles layer, IntGrid value
// groups / order / icons, moving entities between layers.
// ============================================================================

@(private = "file")
layer_def_obj :: proc(doc: ^Ldtk_Doc, uid: int) -> (^LdtkJson, int) {
	arr := LdtkJson_Get(LdtkJson_Get(doc.root, "defs"), "layers")
	if arr == nil do return nil, -1
	for d, i in arr.items do if LdtkJson_Int(d, "uid", -1) == uid do return d, i
	return nil, -1
}

// ----------------------------------------------------------------------------
// Grid size
// ----------------------------------------------------------------------------

// Ldtk_Doc_SetLayerGrid changes a layer's grid size, keeping its cells at the
// same cell coordinates (entities scaled), like LDtk; Auto layers reading it
// follow.
Ldtk_Doc_SetLayerGrid :: proc(doc: ^Ldtk_Doc, uid: int, grid: int) {
	a := doc.allocator
	grid := clamp(grid, 1, 1024)
	o, _ := layer_def_obj(doc, uid)
	if o == nil do return
	old := LdtkJson_Int(o, "gridSize", 16)
	if old == grid do return
	uids := make([dynamic]int, context.temp_allocator)
	append(&uids, uid)
	for d in LdtkJson_Arr(LdtkJson_Get(doc.root, "defs"), "layers") {
		if LdtkJson_Str(d, "type") == "AutoLayer" && LdtkJson_Int(d, "autoSourceLayerDefUid", -1) == uid do append(&uids, LdtkJson_Int(d, "uid"))
	}
	for u in uids {
		obj, _ := layer_def_obj(doc, u)
		LdtkJson_SetInt(obj, "gridSize", grid, a)
	}
	Ldtk_Doc_RefreshDefs(doc)
	ratio := f64(grid) / f64(max(old, 1))
	for &lv, li in doc.levels {
		size := Ldtk_Doc_LevelSize(doc, li)
		for &ly, layer in lv.layers {
			d := Ldtk_Doc_LayerDef(doc, &ly)
			if d == nil do continue
			mine := false
			for u in uids do if u == d.uid do mine = true
			if !mine do continue
			off := Ldtk_Doc_LayerOffset(&ly)
			cw := max(int(math.ceil(f64(size.x - off.x) / f64(grid))), 0)
			ch := max(int(math.ceil(f64(size.y - off.y) / f64(grid))), 0)
			#partial switch d.type {
			case .IntGrid, .AutoLayer, .Tiles:
				cells := make([]i32, cw * ch, doc.heap)
				if d.type == .IntGrid {
					for y in 0 ..< min(ly.cHei, ch) do for x in 0 ..< min(ly.cWid, cw) do cells[x + y * cw] = ly.intGrid[x + y * ly.cWid]
				}
				delete(ly.intGrid, doc.heap)
				ly.intGrid = cells
				k := 0
				for t in ly.gridTiles {
					x := int(t.coord) % max(ly.cWid, 1)
					y := int(t.coord) / max(ly.cWid, 1)
					if x >= cw || y >= ch do continue
					nt := t
					nt.coord = i32(x + y * cw)
					nt.px = {i32(x * grid), i32(y * grid)}
					ly.gridTiles[k] = nt
					k += 1
				}
				resize(&ly.gridTiles, k)
			case .Entities:
				for ent in Ldtk_Doc_Entities(doc, li, layer) {
					px := LdtkJson_Arr(ent, "px")
					if len(px) >= 2 do Ldtk_Doc_MoveEntity(doc, li, layer, ent, {int(math.floor(ratio * px[0].num)), int(math.floor(ratio * px[1].num))})
					ed := Ldtk_Doc_EntityDef(doc, LdtkJson_Int(ent, "defUid", -1))
					if ed == nil do continue
					w, h := LdtkJson_Int(ent, "width", ed.size.x), LdtkJson_Int(ent, "height", ed.size.y)
					if w != ed.size.x do LdtkJson_SetInt(ent, "width", int(math.floor(ratio * f64(w))), a)
					if h != ed.size.y do LdtkJson_SetInt(ent, "height", int(math.floor(ratio * f64(h))), a)
				}
			}
			ly.cWid, ly.cHei = cw, ch
			LdtkJson_SetInt(ly.obj, "__cWid", cw, a)
			LdtkJson_SetInt(ly.obj, "__cHei", ch, a)
			ly.cellsDirty = true
			lv.dirty = true
		}
	}
	for u in uids do Ldtk_Doc_LayerDefChanged(doc, u)
}

// ----------------------------------------------------------------------------
// Copy / paste / duplicate
// ----------------------------------------------------------------------------

// Ldtk_Doc_LayerDefText: a layer definition as JSON text (the clipboard).
Ldtk_Doc_LayerDefText :: proc(doc: ^Ldtk_Doc, uid: int, allocator := context.allocator) -> string {
	o, _ := layer_def_obj(doc, uid)
	if o == nil do return ""
	return LdtkJson_ToString(o, .Minified, allocator)
}

// ldtk_insert_layer_def puts a layer def at `at` in the definitions and an
// empty instance of it at the same place in every level.
@(private = "file")
ldtk_insert_layer_def :: proc(doc: ^Ldtk_Doc, o: ^LdtkJson, at: int) -> int {
	a := doc.allocator
	arr := LdtkJson_Get(LdtkJson_Get(doc.root, "defs"), "layers")
	at := clamp(at, 0, len(arr.items))
	inject_at(&arr.items, at, o)
	Ldtk_Doc_RefreshDefs(doc)
	uid := LdtkJson_Int(o, "uid")
	di := Ldtk_Doc_LayerDefIndex(doc, uid)
	for &lv, li in doc.levels {
		inst := Ldtk_Doc_NewLayerInstance(doc, &doc.layerDefs[di], LdtkJson_Int(lv.obj, "uid"), Ldtk_Doc_LevelSize(doc, li), a)
		layers := LdtkJson_Get(lv.data, "layerInstances")
		if layers == nil || layers.kind != .Array {
			layers = LdtkJson_New(.Array, a)
			LdtkJson_Set(lv.data, "layerInstances", layers, a)
		}
		inject_at(&layers.items, clamp(at, 0, len(layers.items)), inst)
		ldtk_level_index_layers(doc, &lv)
		for &ly in lv.layers do ly.cellsDirty, ly.autoDirty = true, true
		lv.dirty = true
	}
	Ldtk_Doc_Touch(doc)
	return uid
}

// Ldtk_Doc_PasteLayerDef: Definitions.pasteLayerDef - a copied layer def
// with new uids (rules too) and a free identifier, after `afterUid` (or at
// the bottom). Returns its uid (-1: not a layer def).
Ldtk_Doc_PasteLayerDef :: proc(doc: ^Ldtk_Doc, text: string, afterUid := -1, baseName := "") -> int {
	a := doc.allocator
	o, ok := LdtkJson_Parse(text, a)
	if !ok || o.kind != .Object || LdtkJson_Get(o, "type") == nil || LdtkJson_Get(o, "gridSize") == nil do return -1
	LdtkJson_SetInt(o, "uid", Ldtk_Doc_NextUid(doc), a)
	for g in LdtkJson_Arr(o, "autoRuleGroups") {
		LdtkJson_SetInt(g, "uid", Ldtk_Doc_NextUid(doc), a)
		for r in LdtkJson_Arr(g, "rules") do LdtkJson_SetInt(r, "uid", Ldtk_Doc_NextUid(doc), a)
	}
	name := baseName != "" ? baseName : LdtkJson_Str(o, "identifier", "Layer")
	LdtkJson_SetStr(o, "identifier", Ldtk_Doc_UniqueIdentifier(doc, "layers", name), a)
	at := len(doc.layerDefs)
	if _, i := layer_def_obj(doc, afterUid); i >= 0 do at = i + 1
	return ldtk_insert_layer_def(doc, o, at)
}

// Ldtk_Doc_DuplicateLayerDef copies a layer def right after it (empty
// content, like LDtk).
Ldtk_Doc_DuplicateLayerDef :: proc(doc: ^Ldtk_Doc, uid: int, baseName := "") -> int {
	text := Ldtk_Doc_LayerDefText(doc, uid, context.temp_allocator)
	if text == "" do return -1
	return Ldtk_Doc_PasteLayerDef(doc, text, uid, baseName)
}

// Ldtk_Doc_LayerIsSource: does an Auto layer read this IntGrid layer?
Ldtk_Doc_LayerIsSource :: proc(doc: ^Ldtk_Doc, uid: int) -> bool {
	for &d in doc.layerDefs do if d.type == .AutoLayer && d.autoSourceUid == uid do return true
	return false
}

// ----------------------------------------------------------------------------
// Baking
// ----------------------------------------------------------------------------

Ldtk_BakeMethod :: enum u8 {
	Delete_Original,
	Empty_Original, // IntGrid layers: their values are cleared
	Keep_Both,
}

// Ldtk_Doc_BakeLayer: EditLayerDefs.bakeLayer - a Tiles layer "<name>_baked"
// after it holding the auto tiles of every level (stacked like LDtk). Fails
// (-1) when an Auto layer reads this layer or it has no tileset.
Ldtk_Doc_BakeLayer :: proc(doc: ^Ldtk_Doc, uid: int, method: Ldtk_BakeMethod) -> int {
	a := doc.allocator
	di := Ldtk_Doc_LayerDefIndex(doc, uid)
	if di < 0 || Ldtk_Doc_LayerIsSource(doc, uid) do return -1
	src := doc.layerDefs[di]
	if src.type != .AutoLayer && src.type != .IntGrid do return -1
	if src.tilesetUid < 0 do return -1
	text := Ldtk_Doc_LayerDefText(doc, uid, context.temp_allocator)
	o, _ := LdtkJson_Parse(text, a)
	LdtkJson_SetInt(o, "uid", Ldtk_Doc_NextUid(doc), a)
	LdtkJson_SetStr(o, "identifier", Ldtk_Doc_UniqueIdentifier(doc, "layers", strings.concatenate({src.identifier, "_baked"}, context.temp_allocator)), a)
	LdtkJson_SetStr(o, "type", "Tiles", a)
	LdtkJson_SetStr(o, "__type", "Tiles", a)
	LdtkJson_Set(o, "autoRuleGroups", LdtkJson_New(.Array, a), a)
	LdtkJson_SetNull(o, "autoSourceLayerDefUid", a)
	LdtkJson_SetInt(o, "tilesetDefUid", src.tilesetUid, a)
	_, at := layer_def_obj(doc, uid)
	nu := ldtk_insert_layer_def(doc, o, at + 1)
	for &lv, li in doc.levels {
		si, ni := -1, -1
		for &ly, i in lv.layers {
			if d := Ldtk_Doc_LayerDef(doc, &ly); d != nil {
				if d.uid == uid do si = i
				if d.uid == nu do ni = i
			}
		}
		if si < 0 || ni < 0 do continue
		if ov := ldtk_nullable_int(lv.layers[si].obj, "overrideTilesetUid"); ov >= 0 && ov != src.tilesetUid {
			Ldtk_Doc_SetLayerTilesetOverride(doc, li, ni, ov)
		}
		g := max(src.gridSize, 1)
		tiles := make([dynamic]Ldtk_DocTile, context.temp_allocator)
		append(&tiles, ..lv.layers[si].autoTiles[:])
		for t in tiles do Ldtk_Doc_AddGridTile(doc, li, ni, int(t.px.x) / g, int(t.px.y) / g, int(t.t), t.f, true)
		if method == .Empty_Original && src.type == .IntGrid {
			ly := &lv.layers[si]
			for &c in ly.intGrid do c = 0
			clear(&ly.autoTiles)
			ly.cellsDirty, ly.autoDirty = true, true
		}
		lv.dirty = true
	}
	if method == .Delete_Original do Ldtk_Doc_RemoveLayerDef(doc, uid)
	else if method == .Empty_Original do Ldtk_Doc_ApplyRulesFull(doc, -1)
	Ldtk_Doc_Touch(doc)
	return nu
}

// ----------------------------------------------------------------------------
// IntGrid values: order, groups, icons
// ----------------------------------------------------------------------------

@(private = "file")
int_values :: proc(doc: ^Ldtk_Doc, layerUid: int) -> ^LdtkJson {
	o, _ := layer_def_obj(doc, layerUid)
	if o == nil do return nil
	return LdtkJson_Get(o, "intGridValues")
}

@(private = "file")
int_groups :: proc(doc: ^Ldtk_Doc, layerUid: int) -> ^LdtkJson {
	o, _ := layer_def_obj(doc, layerUid)
	if o == nil do return nil
	g := LdtkJson_Get(o, "intGridValuesGroups")
	if g == nil || g.kind != .Array {
		g = LdtkJson_New(.Array, doc.allocator)
		LdtkJson_Set(o, "intGridValuesGroups", g, doc.allocator)
	}
	return g
}

// Ldtk_Doc_MoveIntGridValue moves a value up / down in the list (its group
// is kept).
Ldtk_Doc_MoveIntGridValue :: proc(doc: ^Ldtk_Doc, layerUid: int, value: int, delta: int) -> bool {
	vals := int_values(doc, layerUid)
	if vals == nil do return false
	for v, i in vals.items do if LdtkJson_Int(v, "value") == value {
		j := i + delta
		if j < 0 || j >= len(vals.items) do return false
		vals.items[i], vals.items[j] = vals.items[j], vals.items[i]
		Ldtk_Doc_RefreshDefs(doc)
		Ldtk_Doc_Touch(doc)
		return true
	}
	return false
}

// Ldtk_Doc_AddIntGridGroup: LayerDef.addIntGridGroup; returns its uid.
Ldtk_Doc_AddIntGridGroup :: proc(doc: ^Ldtk_Doc, layerUid: int) -> int {
	a := doc.allocator
	groups := int_groups(doc, layerUid)
	if groups == nil do return -1
	uid := 1
	for g in groups.items do uid = max(uid, LdtkJson_Int(g, "uid") + 1)
	o := LdtkJson_New(.Object, a)
	LdtkJson_Set(o, "uid", LdtkJson_NewInt(uid, a), a)
	LdtkJson_Set(o, "identifier", LdtkJson_New(.Null, a), a)
	LdtkJson_Set(o, "color", LdtkJson_New(.Null, a), a)
	append(&groups.items, o)
	Ldtk_Doc_RefreshDefs(doc)
	Ldtk_Doc_Touch(doc)
	return uid
}

// Ldtk_Doc_RemoveIntGridGroup deletes a group; its values go back to "no
// group".
Ldtk_Doc_RemoveIntGridGroup :: proc(doc: ^Ldtk_Doc, layerUid: int, groupUid: int) {
	a := doc.allocator
	groups := int_groups(doc, layerUid)
	if groups == nil do return
	for g, i in groups.items do if LdtkJson_Int(g, "uid") == groupUid {
		ordered_remove(&groups.items, i)
		break
	}
	for v in int_values(doc, layerUid).items do if LdtkJson_Int(v, "groupUid") == groupUid do LdtkJson_SetInt(v, "groupUid", 0, a)
	Ldtk_Doc_RefreshDefs(doc)
	Ldtk_Doc_Touch(doc)
}

// Ldtk_Doc_SetIntGridGroup: a group's name ("" = none) and colour ("" =
// none).
Ldtk_Doc_SetIntGridGroup :: proc(doc: ^Ldtk_Doc, layerUid: int, groupUid: int, name: string, color: string) {
	a := doc.allocator
	groups := int_groups(doc, layerUid)
	if groups == nil do return
	for g in groups.items do if LdtkJson_Int(g, "uid") == groupUid {
		clean := Ldtk_CleanIdentifier(name, keepCase = true)
		if name == "" do LdtkJson_SetNull(g, "identifier", a)
		else do LdtkJson_SetStr(g, "identifier", clean, a)
		if color == "" do LdtkJson_SetNull(g, "color", a)
		else do LdtkJson_SetStr(g, "color", color, a)
	}
	Ldtk_Doc_Touch(doc)
}

// Ldtk_Doc_MoveIntGridGroup reorders groups.
Ldtk_Doc_MoveIntGridGroup :: proc(doc: ^Ldtk_Doc, layerUid: int, groupUid: int, delta: int) -> bool {
	groups := int_groups(doc, layerUid)
	if groups == nil do return false
	for g, i in groups.items do if LdtkJson_Int(g, "uid") == groupUid {
		j := i + delta
		if j < 0 || j >= len(groups.items) do return false
		groups.items[i], groups.items[j] = groups.items[j], groups.items[i]
		Ldtk_Doc_Touch(doc)
		return true
	}
	return false
}

// Ldtk_Doc_SetIntGridValueGroup puts a value in a group (0: none).
Ldtk_Doc_SetIntGridValueGroup :: proc(doc: ^Ldtk_Doc, layerUid: int, value: int, groupUid: int) {
	vals := int_values(doc, layerUid)
	if vals == nil do return
	for v in vals.items do if LdtkJson_Int(v, "value") == value do LdtkJson_SetInt(v, "groupUid", groupUid, doc.allocator)
	Ldtk_Doc_RefreshDefs(doc)
	Ldtk_Doc_Touch(doc)
}

// Ldtk_Doc_SetIntGridValueTile: a value's icon (a tile rectangle of a
// tileset; tilesetUid < 0 clears it).
Ldtk_Doc_SetIntGridValueTile :: proc(doc: ^Ldtk_Doc, layerUid: int, value: int, tilesetUid: int, rect: [4]int) {
	a := doc.allocator
	vals := int_values(doc, layerUid)
	if vals == nil do return
	for v in vals.items do if LdtkJson_Int(v, "value") == value {
		if tilesetUid < 0 {
			LdtkJson_SetNull(v, "tile", a)
			continue
		}
		t := LdtkJson_New(.Object, a)
		LdtkJson_Set(t, "tilesetUid", LdtkJson_NewInt(tilesetUid, a), a)
		LdtkJson_Set(t, "x", LdtkJson_NewInt(rect[0], a), a)
		LdtkJson_Set(t, "y", LdtkJson_NewInt(rect[1], a), a)
		LdtkJson_Set(t, "w", LdtkJson_NewInt(rect[2], a), a)
		LdtkJson_Set(t, "h", LdtkJson_NewInt(rect[3], a), a)
		LdtkJson_Set(v, "tile", t, a)
	}
	Ldtk_Doc_Touch(doc)
}

// ----------------------------------------------------------------------------
// Moving entities between layers
// ----------------------------------------------------------------------------

Ldtk_EntityFilter :: enum u8 {
	All,
	Def, // entities of one definition (identifier)
	Tag, // entities with a tag
}

// Ldtk_Doc_MoveEntitiesBetweenLayers: MoveEntitiesBetweenLayers - every
// matching entity of one Entities layer goes to another, in every level.
// Returns how many moved (-1: the target layer doesn't accept that
// definition's tags).
Ldtk_Doc_MoveEntitiesBetweenLayers :: proc(doc: ^Ldtk_Doc, fromUid, toUid: int, filter: Ldtk_EntityFilter, name: string) -> int {
	if fromUid == toUid do return 0
	ti := Ldtk_Doc_LayerDefIndex(doc, toUid)
	if ti < 0 || doc.layerDefs[ti].type != .Entities do return 0
	has :: proc(arr: []^LdtkJson, t: string) -> bool {
		for x in arr do if x.kind == .String && x.text == t do return true
		return false
	}
	if filter == .Def {
		for &ed in doc.entityDefs do if ed.identifier == name {
			tags := LdtkJson_Arr(ed.obj, "tags")
			td := doc.layerDefs[ti].obj
			for x in LdtkJson_Arr(td, "excludedTags") do if has(tags, x.text) do return -1
			req := LdtkJson_Arr(td, "requiredTags")
			if len(req) > 0 {
				ok := false
				for r in req do if has(tags, r.text) do ok = true
				if !ok do return -1
			}
		}
	}
	n := 0
	for &lv, li in doc.levels {
		from, to := -1, -1
		for &ly, i in lv.layers {
			if d := Ldtk_Doc_LayerDef(doc, &ly); d != nil {
				if d.uid == fromUid do from = i
				if d.uid == toUid do to = i
			}
		}
		if from < 0 || to < 0 do continue
		moving := make([dynamic]^LdtkJson, context.temp_allocator)
		for ent in Ldtk_Doc_Entities(doc, li, from) {
			switch filter {
			case .All: append(&moving, ent)
			case .Def: if LdtkJson_Str(ent, "__identifier") == name do append(&moving, ent)
			case .Tag: if has(LdtkJson_Arr(ent, "__tags"), name) do append(&moving, ent)
			}
		}
		for ent in moving do if Ldtk_Doc_MoveEntityToLayer(doc, li, from, to, ent) do n += 1
	}
	if n > 0 do Ldtk_Doc_UpdateToc(doc)
	return n
}
