package engine

import "core:mem"
import "core:strings"
import rl "vendor:raylib"

// ============================================================================
// Ldtk_Doc tileset definitions (LDtk's EditTilesetDefs / TilesetDef /
// Definitions): rename, remove (references cleared like Project.tidy),
// copy / paste / duplicate / reorder, the image (changed or resized: tile
// ids remapped by position, padding trimmed), the grid (tile ids remapped),
// spacing / padding, tags and the tag enum.
// ============================================================================

@(private = "file")
tilesets_arr :: proc(doc: ^Ldtk_Doc) -> ^LdtkJson {
	defs := LdtkJson_Get(doc.root, "defs")
	arr := LdtkJson_Get(defs, "tilesets")
	if arr == nil || arr.kind != .Array {
		arr = LdtkJson_New(.Array, doc.allocator)
		LdtkJson_Set(defs, "tilesets", arr, doc.allocator)
	}
	return arr
}

// Ldtk_Doc_TilesetCWid: TilesetDef.cWid for given sizes.
Ldtk_Doc_TilesetCWid :: proc(px, grid, spacing, padding: int) -> int {
	step := max(grid + spacing, 1)
	return max((px - padding * 2 + step - 1) / step, 0)
}

// ldtk_tileset_geometry: the cached sizes and pixel data after a size /
// grid / spacing / padding change (img: the image, when loaded).
@(private = "file")
ldtk_tileset_geometry :: proc(doc: ^Ldtk_Doc, o: ^LdtkJson, img: ^rl.Image) {
	a := doc.allocator
	grid := max(LdtkJson_Int(o, "tileGridSize", 16), 1)
	sp, pad := LdtkJson_Int(o, "spacing"), LdtkJson_Int(o, "padding")
	LdtkJson_SetInt(o, "__cWid", Ldtk_Doc_TilesetCWid(LdtkJson_Int(o, "pxWid"), grid, sp, pad), a)
	LdtkJson_SetInt(o, "__cHei", Ldtk_Doc_TilesetCWid(LdtkJson_Int(o, "pxHei"), grid, sp, pad), a)
	if img != nil && img.data != nil do LdtkJson_Set(o, "cachedPixelData", Ldtk_TilesetPixelData(img, grid, sp, pad, a), a)
}

// ldtk_remap_tile_ids: TilesetDef.remapAllTileIds - tiles keep their place in
// the image when the number of columns changes (Tiles layers, saved
// selections, auto-layer rules, enum tags, custom data). False: some tiles
// were lost.
@(private = "file")
ldtk_remap_tile_ids :: proc(doc: ^Ldtk_Doc, uid: int, oldCWid: int) -> bool {
	a := doc.allocator
	o := Ldtk_Doc_Tileset(doc, uid).obj
	cw, ch := LdtkJson_Int(o, "__cWid"), LdtkJson_Int(o, "__cHei")
	if oldCWid <= 0 || oldCWid == cw do return true
	remap :: proc(id, oldCWid, cw, ch: int) -> int {
		cy := id / oldCWid
		cx := id - cy * oldCWid
		if cx >= cw || cy >= ch do return -1
		return cx + cy * cw
	}
	Ldtk_Doc_RefreshDefs(doc)
	ts := Ldtk_Doc_Tileset(doc, uid)
	// Tiles layers
	for &lv in doc.levels {
		for &ly in lv.layers {
			d := Ldtk_Doc_LayerDef(doc, &ly)
			if d == nil || d.type != .Tiles || Ldtk_Doc_LayerTileset(doc, &ly) != ts do continue
			k := 0
			for t in ly.gridTiles {
				n := remap(int(t.t), oldCWid, cw, ch)
				if n < 0 do continue
				nt := t
				nt.t = i32(n)
				nt.src = Ldtk_Doc_TileSrc(ts, n)
				ly.gridTiles[k] = nt
				k += 1
			}
			resize(&ly.gridTiles, k)
			ly.cellsDirty = true
			lv.dirty = true
		}
	}
	// saved selections
	for sel in LdtkJson_Arr(o, "savedSelections") {
		ids := LdtkJson_Get(sel, "ids")
		if ids == nil do continue
		k := 0
		for v in ids.items {
			n := remap(int(v.num), oldCWid, cw, ch)
			if n < 0 do continue
			ids.items[k] = LdtkJson_NewInt(n, a)
			k += 1
		}
		resize(&ids.items, k)
	}
	// auto-layer rules
	for &d in doc.layerDefs {
		if d.tilesetUid != uid do continue
		for g in LdtkJson_Arr(d.obj, "autoRuleGroups") do for r in LdtkJson_Arr(g, "rules") do for rect in LdtkJson_Arr(r, "tileRectsIds") {
			for v, i in rect.items do rect.items[i] = LdtkJson_NewInt(remap(int(v.num), oldCWid, cw, ch), a)
		}
	}
	// enum tags, custom data
	for t in LdtkJson_Arr(o, "enumTags") {
		ids := LdtkJson_Get(t, "tileIds")
		if ids == nil do continue
		k := 0
		for v in ids.items {
			n := remap(int(v.num), oldCWid, cw, ch)
			if n < 0 do continue
			ids.items[k] = LdtkJson_NewInt(n, a)
			k += 1
		}
		resize(&ids.items, k)
	}
	if cd := LdtkJson_Get(o, "customData"); cd != nil {
		k := 0
		for item in cd.items {
			n := remap(LdtkJson_Int(item, "tileId"), oldCWid, cw, ch)
			if n < 0 do continue
			LdtkJson_SetInt(item, "tileId", n, a)
			cd.items[k] = item
			k += 1
		}
		resize(&cd.items, k)
	}
	return cw >= oldCWid
}

@(private = "file")
tileset_changed :: proc(doc: ^Ldtk_Doc, uid: int) {
	Ldtk_Doc_RefreshDefs(doc)
	ts := Ldtk_Doc_Tileset(doc, uid)
	for &lv in doc.levels do for &ly in lv.layers {
		if Ldtk_Doc_LayerTileset(doc, &ly) != ts do continue
		for &t in ly.gridTiles do t.src = Ldtk_Doc_TileSrc(ts, int(t.t))
		ly.cellsDirty = true
		lv.dirty = true
	}
	for &d in doc.layerDefs do if d.tilesetUid == uid do Ldtk_Doc_LayerDefChanged(doc, d.uid)
	Ldtk_Doc_ApplyRulesFull(doc, -1)
	Ldtk_Doc_Touch(doc)
}

// Ldtk_Doc_SetTilesetGrid: the grid size (tile ids remapped, like LDtk);
// false: the bigger grid lost some tiles.
Ldtk_Doc_SetTilesetGrid :: proc(doc: ^Ldtk_Doc, uid: int, grid: int, img: ^rl.Image) -> bool {
	ts := Ldtk_Doc_Tileset(doc, uid)
	if ts == nil do return true
	o := ts.obj
	oldCWid := LdtkJson_Int(o, "__cWid")
	LdtkJson_SetInt(o, "tileGridSize", max(grid, 2), doc.allocator)
	ldtk_tileset_geometry(doc, o, img)
	ok := ldtk_remap_tile_ids(doc, uid, oldCWid)
	tileset_changed(doc, uid)
	return ok
}

// Ldtk_Doc_SetTilesetSpacing: spacing and padding (no remapping, like LDtk).
Ldtk_Doc_SetTilesetSpacing :: proc(doc: ^Ldtk_Doc, uid: int, spacing, padding: int, img: ^rl.Image) {
	ts := Ldtk_Doc_Tileset(doc, uid)
	if ts == nil do return
	LdtkJson_SetInt(ts.obj, "spacing", max(spacing, 0), doc.allocator)
	LdtkJson_SetInt(ts.obj, "padding", max(padding, 0), doc.allocator)
	ldtk_tileset_geometry(doc, ts.obj, img)
	tileset_changed(doc, uid)
}

Ldtk_TilesetImageResult :: enum u8 {
	Ok,
	Remapped,
	Remap_Loss,
	Trimmed_Padding,
}

// Ldtk_Doc_SetTilesetImage: TilesetDef.importAtlasImage - a new / resized
// image (relPath "" keeps the path). Tile ids are remapped by position when
// the size changed (or the padding is trimmed when that explains it).
Ldtk_Doc_SetTilesetImage :: proc(doc: ^Ldtk_Doc, uid: int, relPath: string, img: ^rl.Image) -> Ldtk_TilesetImageResult {
	a := doc.allocator
	ts := Ldtk_Doc_Tileset(doc, uid)
	if ts == nil || img == nil || img.data == nil do return .Ok
	o := ts.obj
	old := ts.pxSize
	oldGrid := ts.gridSize
	if relPath != "" {
		LdtkJson_SetStr(o, "relPath", relPath, a)
		LdtkJson_SetNull(o, "embedAtlas", a)
	}
	w, h := int(img.width), int(img.height)
	LdtkJson_SetInt(o, "pxWid", w, a)
	LdtkJson_SetInt(o, "pxHei", h, a)
	maxGrid := max(min(w, h), 2)
	LdtkJson_SetInt(o, "tileGridSize", min(oldGrid, maxGrid), a)
	LdtkJson_SetInt(o, "spacing", min(LdtkJson_Int(o, "spacing"), maxGrid), a)
	res := Ldtk_TilesetImageResult.Ok
	if old != {w, h} && old.x > 0 {
		pad := LdtkJson_Int(o, "padding")
		if pad > 0 && old.x > w && old.y > h && abs(old.x - w) <= pad * 2 && abs(old.y - h) <= pad * 2 && w % 2 == 0 && h % 2 == 0 {
			LdtkJson_SetInt(o, "padding", pad - min(old.x - w, old.y - h) / 2, a)
			res = .Trimmed_Padding
		} else {
			oldCWid := (old.x + oldGrid - 1) / max(oldGrid, 1)
			ldtk_tileset_geometry(doc, o, img)
			res = ldtk_remap_tile_ids(doc, uid, oldCWid) ? .Remapped : .Remap_Loss
		}
	}
	ldtk_tileset_geometry(doc, o, img)
	// layers' cached paths
	for &lv in doc.levels do for &ly in lv.layers {
		if LdtkJson_Int(ly.obj, "__tilesetDefUid", -1) == uid do LdtkJson_SetStr(ly.obj, "__tilesetRelPath", LdtkJson_Str(o, "relPath"), a)
	}
	tileset_changed(doc, uid)
	return res
}

// Ldtk_Doc_RenameTileset: a unique identifier.
Ldtk_Doc_RenameTileset :: proc(doc: ^Ldtk_Doc, uid: int, name: string) {
	ts := Ldtk_Doc_Tileset(doc, uid)
	if ts == nil || strings.trim_space(name) == "" do return
	if Ldtk_Doc_CleanIdentifier(doc, name) == ts.identifier do return
	LdtkJson_SetStr(ts.obj, "identifier", Ldtk_Doc_UniqueIdentifier(doc, "tilesets", name), doc.allocator)
	Ldtk_Doc_RefreshDefs(doc)
	Ldtk_Doc_Touch(doc)
}

// Ldtk_Doc_RemoveTileset: Definitions.removeTilesetDef + Project.tidy -
// layers, level overrides, entities, Tile fields (values emptied), enum and
// IntGrid icons and rule group icons using it lose it.
Ldtk_Doc_RemoveTileset :: proc(doc: ^Ldtk_Doc, uid: int) {
	a := doc.allocator
	arr := tilesets_arr(doc)
	for t, i in arr.items do if LdtkJson_Int(t, "uid", -1) == uid {
		ordered_remove(&arr.items, i)
		break
	}
	defs := LdtkJson_Get(doc.root, "defs")
	rect_uses :: proc(r: ^LdtkJson, uid: int) -> bool {return r != nil && r.kind == .Object && LdtkJson_Int(r, "tilesetUid", -1) == uid}
	layers := make([dynamic]int, context.temp_allocator)
	for d in LdtkJson_Arr(defs, "layers") {
		if LdtkJson_Int(d, "tilesetDefUid", -1) == uid {
			LdtkJson_SetNull(d, "tilesetDefUid", a)
			append(&layers, LdtkJson_Int(d, "uid"))
		}
		for v in LdtkJson_Arr(d, "intGridValues") do if rect_uses(LdtkJson_Get(v, "tile"), uid) do LdtkJson_SetNull(v, "tile", a)
		for g in LdtkJson_Arr(d, "autoRuleGroups") do if rect_uses(LdtkJson_Get(g, "icon"), uid) do LdtkJson_SetNull(g, "icon", a)
	}
	fields := make([dynamic]int, context.temp_allocator)
	fix_fields :: proc(list: []^LdtkJson, uid: int, fields: ^[dynamic]int, a: mem.Allocator) {
		for fd in list do if LdtkJson_Int(fd, "tilesetUid", -1) == uid {
			LdtkJson_SetNull(fd, "tilesetUid", a)
			LdtkJson_SetNull(fd, "defaultOverride", a)
			append(fields, LdtkJson_Int(fd, "uid"))
		}
	}
	fix_fields(LdtkJson_Arr(defs, "levelFields"), uid, &fields, a)
	for ed in LdtkJson_Arr(defs, "entities") {
		if LdtkJson_Int(ed, "tilesetId", -1) == uid {
			LdtkJson_SetNull(ed, "tilesetId", a)
			LdtkJson_SetNull(ed, "tileRect", a)
		}
		if rect_uses(LdtkJson_Get(ed, "uiTileRect"), uid) do LdtkJson_SetNull(ed, "uiTileRect", a)
		fix_fields(LdtkJson_Arr(ed, "fieldDefs"), uid, &fields, a)
	}
	for key in ([]string{"enums", "externalEnums"}) do for en in LdtkJson_Arr(defs, key) {
		if LdtkJson_Int(en, "iconTilesetUid", -1) == uid do LdtkJson_SetNull(en, "iconTilesetUid", a)
		for v in LdtkJson_Arr(en, "values") do if rect_uses(LdtkJson_Get(v, "tileRect"), uid) do LdtkJson_SetNull(v, "tileRect", a)
	}
	// level overrides, Tile field values
	null_rev :: proc(fi: ^LdtkJson, a: mem.Allocator) {
		rev := LdtkJson_Get(fi, "realEditorValues")
		if rev == nil do return
		clear(&rev.items)
	}
	for &lv in doc.levels {
		for &ly in lv.layers do if LdtkJson_Int(ly.obj, "overrideTilesetUid", -1) == uid do LdtkJson_SetNull(ly.obj, "overrideTilesetUid", a)
		for f in fields {
			for fi in LdtkJson_Arr(lv.obj, "fieldInstances") do if LdtkJson_Int(fi, "defUid", -1) == f do null_rev(fi, a)
			if lv.extRoot != nil do for fi in LdtkJson_Arr(lv.extRoot, "fieldInstances") do if LdtkJson_Int(fi, "defUid", -1) == f do null_rev(fi, a)
			for &ly in lv.layers do for ent in LdtkJson_Arr(ly.obj, "entityInstances") {
				for fi in LdtkJson_Arr(ent, "fieldInstances") do if LdtkJson_Int(fi, "defUid", -1) == f do null_rev(fi, a)
			}
		}
		lv.dirty = true
	}
	Ldtk_Doc_RefreshDefs(doc)
	for f in fields do Ldtk_Doc_RefreshFieldInstances(doc, f)
	for &ed in doc.entityDefs do Ldtk_Doc_EntityDefChanged(doc, ed.uid)
	for d in layers do Ldtk_Doc_LayerDefChanged(doc, d)
	for &d in doc.layerDefs do Ldtk_Doc_LayerDefChanged(doc, d.uid) // level overrides
	Ldtk_Doc_Touch(doc)
}

// Ldtk_Doc_TilesetText / PasteTileset / DuplicateTileset: pasteTilesetDef - a
// copy with a new uid and a free identifier, after `afterUid`.
Ldtk_Doc_TilesetText :: proc(doc: ^Ldtk_Doc, uid: int, allocator := context.allocator) -> string {
	ts := Ldtk_Doc_Tileset(doc, uid)
	if ts == nil do return ""
	return LdtkJson_ToString(ts.obj, .Minified, allocator)
}

Ldtk_Doc_PasteTileset :: proc(doc: ^Ldtk_Doc, text: string, afterUid := -1) -> int {
	a := doc.allocator
	o, ok := LdtkJson_Parse(text, a)
	if !ok || o.kind != .Object || LdtkJson_Get(o, "tileGridSize") == nil || LdtkJson_Get(o, "pxWid") == nil do return -1
	nu := Ldtk_Doc_NextUid(doc)
	LdtkJson_SetInt(o, "uid", nu, a)
	LdtkJson_SetStr(o, "identifier", Ldtk_Doc_UniqueIdentifier(doc, "tilesets", LdtkJson_Str(o, "identifier", "Tileset")), a)
	arr := tilesets_arr(doc)
	at := len(arr.items)
	for t, i in arr.items do if LdtkJson_Int(t, "uid", -1) == afterUid do at = i + 1
	inject_at(&arr.items, at, o)
	Ldtk_Doc_RefreshDefs(doc)
	Ldtk_Doc_Touch(doc)
	return nu
}

Ldtk_Doc_DuplicateTileset :: proc(doc: ^Ldtk_Doc, uid: int) -> int {
	text := Ldtk_Doc_TilesetText(doc, uid, context.temp_allocator)
	if text == "" do return -1
	return Ldtk_Doc_PasteTileset(doc, text, uid)
}

Ldtk_Doc_MoveTileset :: proc(doc: ^Ldtk_Doc, uid: int, delta: int) -> bool {
	arr := tilesets_arr(doc)
	for t, i in arr.items do if LdtkJson_Int(t, "uid", -1) == uid {
		j := i + delta
		if j < 0 || j >= len(arr.items) do return false
		arr.items[i], arr.items[j] = arr.items[j], arr.items[i]
		Ldtk_Doc_RefreshDefs(doc)
		Ldtk_Doc_Touch(doc)
		return true
	}
	return false
}

// Ldtk_Doc_SetTilesetTags: the tileset's tags (group the list).
Ldtk_Doc_SetTilesetTags :: proc(doc: ^Ldtk_Doc, uid: int, tags: []string) {
	a := doc.allocator
	ts := Ldtk_Doc_Tileset(doc, uid)
	if ts == nil do return
	arr := LdtkJson_New(.Array, a)
	for t in tags do if c := strings.trim_space(t); c != "" do append(&arr.items, LdtkJson_NewString(c, a))
	LdtkJson_Set(ts.obj, "tags", arr, a)
	Ldtk_Doc_Touch(doc)
}

// Ldtk_Doc_SetTilesetTagEnum: the enum per-tile tags come from (< 0: none);
// changing it forgets the tags, like LDtk.
Ldtk_Doc_SetTilesetTagEnum :: proc(doc: ^Ldtk_Doc, uid: int, enumUid: int) {
	a := doc.allocator
	ts := Ldtk_Doc_Tileset(doc, uid)
	if ts == nil do return
	if LdtkJson_Int(ts.obj, "tagsSourceEnumUid", -1) == enumUid do return
	if enumUid < 0 do LdtkJson_SetNull(ts.obj, "tagsSourceEnumUid", a)
	else do LdtkJson_SetInt(ts.obj, "tagsSourceEnumUid", enumUid, a)
	LdtkJson_Set(ts.obj, "enumTags", LdtkJson_New(.Array, a), a)
	Ldtk_Doc_RefreshDefs(doc)
	Ldtk_Doc_Touch(doc)
}

// Ldtk_Doc_TilesetHasTags: some tile has an enum tag.
Ldtk_Doc_TilesetHasTags :: proc(doc: ^Ldtk_Doc, uid: int) -> bool {
	ts := Ldtk_Doc_Tileset(doc, uid)
	if ts == nil do return false
	for t in LdtkJson_Arr(ts.obj, "enumTags") do if len(LdtkJson_Arr(t, "tileIds")) > 0 do return true
	return false
}
