package engine

import "core:slice"

// ============================================================================
// Ldtk_Doc selections: moving / copying / deleting a group of grid cells
// (IntGrid values, tile stacks) and entities of one level, possibly on
// several layers - LDtk's Selection tool (tool/SelectionTool.hx,
// GenericLevelElementGroup.hx) - plus duplicating entities and moving them
// to another Entities layer. Take a level undo step first.
// ============================================================================

Ldtk_SelCell :: struct {
	layer:  int,
	cx, cy: int,
}

Ldtk_SelEntity :: struct {
	layer: int,
	obj:   ^LdtkJson,
}

Ldtk_Selection :: struct {
	cells:    [dynamic]Ldtk_SelCell,
	entities: [dynamic]Ldtk_SelEntity,
}

Ldtk_Selection_Clear :: proc(s: ^Ldtk_Selection) {
	clear(&s.cells)
	clear(&s.entities)
}

Ldtk_Selection_Destroy :: proc(s: ^Ldtk_Selection) {
	delete(s.cells)
	delete(s.entities)
	s^ = {}
}

Ldtk_Selection_Empty :: proc(s: ^Ldtk_Selection) -> bool {
	return len(s.cells) == 0 && len(s.entities) == 0
}

Ldtk_Selection_HasCell :: proc(s: ^Ldtk_Selection, c: Ldtk_SelCell) -> bool {
	for x in s.cells do if x == c do return true
	return false
}

Ldtk_Selection_HasEntity :: proc(s: ^Ldtk_Selection, obj: ^LdtkJson) -> bool {
	for x in s.entities do if x.obj == obj do return true
	return false
}

// Ldtk_Selection_ToggleCell / ToggleEntity add or remove one element.
Ldtk_Selection_ToggleCell :: proc(s: ^Ldtk_Selection, c: Ldtk_SelCell) {
	for x, i in s.cells do if x == c {
		unordered_remove(&s.cells, i)
		return
	}
	append(&s.cells, c)
}

Ldtk_Selection_ToggleEntity :: proc(s: ^Ldtk_Selection, e: Ldtk_SelEntity) {
	for x, i in s.entities do if x.obj == e.obj {
		ordered_remove(&s.entities, i)
		return
	}
	append(&s.entities, e)
}

// ldtk_cell_has_value: IntGrid value or a tile there.
@(private = "file")
ldtk_cell_has_value :: proc(doc: ^Ldtk_Doc, ly: ^Ldtk_DocLayer, cx, cy: int) -> bool {
	d := Ldtk_Doc_LayerDef(doc, ly)
	if d == nil do return false
	#partial switch d.type {
	case .IntGrid: return Ldtk_Doc_GetIntGrid(ly, cx, cy) != 0
	case .Tiles: return len(Ldtk_Doc_TilesAt(ly, cx, cy)) > 0
	}
	return false
}

// Ldtk_Doc_SelectRect adds what lies in a level-pixel rectangle: cells with a
// value and entities whose cell is inside (only `onlyLayer` when >= 0;
// hidden layers are skipped; with `activeLayer`, other layers whose def
// says canSelectWhenInactive = false are skipped too).
// With `includeEmpty` (LDtk's "select empty spaces"), IntGrid and Tiles
// cells are selected even without a value: moving them clears the target.
Ldtk_Doc_SelectRect :: proc(doc: ^Ldtk_Doc, li: int, s: ^Ldtk_Selection, r: [4]int, onlyLayer := -1, activeLayer := -1, includeEmpty := false) {
	lv := &doc.levels[li]
	for &ly, j in lv.layers {
		if onlyLayer >= 0 && j != onlyLayer do continue
		if !LdtkJson_Bool(ly.obj, "visible", true) do continue
		d := Ldtk_Doc_LayerDef(doc, &ly)
		if d == nil do continue
		if activeLayer >= 0 && j != activeLayer && !LdtkJson_Bool(d.obj, "canSelectWhenInactive", true) do continue
		off := Ldtk_Doc_LayerOffset(&ly)
		g := d.gridSize
		x0 := ldtk_floor_div(r[0] - off.x, g)
		y0 := ldtk_floor_div(r[1] - off.y, g)
		x1 := ldtk_floor_div(r[0] + r[2] - 1 - off.x, g)
		y1 := ldtk_floor_div(r[1] + r[3] - 1 - off.y, g)
		if d.type == .Entities {
			for ent in LdtkJson_Arr(ly.obj, "entityInstances") {
				px := LdtkJson_Arr(ent, "px")
				if len(px) < 2 do continue
				cx := ldtk_floor_div(int(px[0].num), g)
				cy := ldtk_floor_div(int(px[1].num), g)
				if cx >= x0 && cx <= x1 && cy >= y0 && cy <= y1 && !Ldtk_Selection_HasEntity(s, ent) do append(&s.entities, Ldtk_SelEntity{j, ent})
			}
			continue
		}
		for cy in max(y0, 0) ..= min(y1, ly.cHei - 1) {
			for cx in max(x0, 0) ..= min(x1, ly.cWid - 1) {
				c := Ldtk_SelCell{j, cx, cy}
				fits := ldtk_cell_has_value(doc, &ly, cx, cy) || (includeEmpty && (d.type == .IntGrid || d.type == .Tiles))
				if fits && !Ldtk_Selection_HasCell(s, c) do append(&s.cells, c)
			}
		}
	}
}

// Ldtk_Doc_SelectAll selects everything in a layer (or every layer: -1).
Ldtk_Doc_SelectAll :: proc(doc: ^Ldtk_Doc, li: int, s: ^Ldtk_Selection, layer := -1, activeLayer := -1) {
	Ldtk_Selection_Clear(s)
	sz := Ldtk_Doc_LevelSize(doc, li)
	Ldtk_Doc_SelectRect(doc, li, s, {-100000, -100000, sz.x + 200000, sz.y + 200000}, layer, activeLayer)
}

@(private)
ldtk_floor_div :: proc(a, b: int) -> int {
	if b == 0 do return 0
	q := a / b
	if (a % b != 0) && ((a < 0) != (b < 0)) do q -= 1
	return q
}

// Ldtk_Doc_SelectionCanMove: false when the selected cells' layers can't all
// move by whole cells of `deltaPx`.
Ldtk_Doc_SelectionCanMove :: proc(doc: ^Ldtk_Doc, li: int, s: ^Ldtk_Selection, deltaPx: [2]int) -> bool {
	for c in s.cells {
		d := Ldtk_Doc_LayerDef(doc, &doc.levels[li].layers[c.layer])
		if d == nil || deltaPx.x % d.gridSize != 0 || deltaPx.y % d.gridSize != 0 do return false
	}
	return true
}

// Ldtk_Doc_MoveSelection moves (or with `copy`, copies) the selection by
// `deltaPx` (whole cells for cell layers - see SelectionCanMove). Cells
// moved outside their layer are dropped; what the moved cells land on is
// replaced. The selection then holds the moved / copied elements. Auto
// tiles follow. Returns false when nothing could move.
Ldtk_Doc_MoveSelection :: proc(doc: ^Ldtk_Doc, li: int, s: ^Ldtk_Selection, deltaPx: [2]int, copy := false) -> bool {
	if Ldtk_Selection_Empty(s) || (deltaPx == {} && !copy) do return false
	if !Ldtk_Doc_SelectionCanMove(doc, li, s, deltaPx) do return false
	lv := &doc.levels[li]
	// read every source first (moves may overlap)
	Saved :: struct {
		c:     Ldtk_SelCell,
		value: i32,
		tiles: []Ldtk_DocTile,
	}
	saved := make([dynamic]Saved, context.temp_allocator)
	for c in s.cells {
		ly := &lv.layers[c.layer]
		sv := Saved{c = c, value = i32(Ldtk_Doc_GetIntGrid(ly, c.cx, c.cy))}
		sv.tiles = slice.clone(Ldtk_Doc_TilesAt(ly, c.cx, c.cy), context.temp_allocator)
		append(&saved, sv)
	}
	if !copy {
		for c in s.cells {
			ly := &lv.layers[c.layer]
			d := Ldtk_Doc_LayerDef(doc, ly)
			if d.type == .IntGrid do Ldtk_Doc_SetIntGrid(doc, li, c.layer, c.cx, c.cy, 0)
			else do Ldtk_Doc_SetTile(doc, li, c.layer, c.cx, c.cy, -1)
		}
	}
	// bounds of changes per layer (for the rules)
	Bounds :: struct {mn, mx: [2]int}
	bounds := make(map[int]Bounds, allocator = context.temp_allocator)
	grow :: proc(bounds: ^map[int]Bounds, layer: int, c: [2]int) {
		b, ok := bounds[layer]
		if !ok do b = {c, c}
		b.mn = {min(b.mn.x, c.x), min(b.mn.y, c.y)}
		b.mx = {max(b.mx.x, c.x), max(b.mx.y, c.y)}
		bounds[layer] = b
	}
	clear(&s.cells)
	for sv in saved {
		ly := &lv.layers[sv.c.layer]
		d := Ldtk_Doc_LayerDef(doc, ly)
		grow(&bounds, sv.c.layer, {sv.c.cx, sv.c.cy})
		nc := [2]int{sv.c.cx + deltaPx.x / d.gridSize, sv.c.cy + deltaPx.y / d.gridSize}
		if nc.x < 0 || nc.y < 0 || nc.x >= ly.cWid || nc.y >= ly.cHei do continue
		grow(&bounds, sv.c.layer, nc)
		if d.type == .IntGrid {
			Ldtk_Doc_SetIntGrid(doc, li, sv.c.layer, nc.x, nc.y, int(sv.value))
		} else {
			Ldtk_Doc_SetTile(doc, li, sv.c.layer, nc.x, nc.y, -1)
			for t, k in sv.tiles do Ldtk_Doc_SetTile(doc, li, sv.c.layer, nc.x, nc.y, int(t.t), t.f, k > 0)
		}
		append(&s.cells, Ldtk_SelCell{sv.c.layer, nc.x, nc.y})
	}
	for layer, b in bounds do Ldtk_Doc_ApplyRules(doc, li, layer, b.mn.x, b.mn.y, b.mx.x, b.mx.y)
	// entities
	for &se in s.entities {
		px := LdtkJson_Arr(se.obj, "px")
		if len(px) < 2 do continue
		np := [2]int{int(px[0].num) + deltaPx.x, int(px[1].num) + deltaPx.y}
		if copy {
			if dup := Ldtk_Doc_DuplicateEntity(doc, li, se.layer, se.obj, deltaPx); dup != nil do se.obj = dup
		} else {
			Ldtk_Doc_MoveEntity(doc, li, se.layer, se.obj, np)
		}
	}
	lv.dirty = true
	Ldtk_Doc_Touch(doc)
	return true
}

// Ldtk_Doc_DeleteSelection removes the selected cells' values / tiles and
// the selected entities, and clears the selection.
Ldtk_Doc_DeleteSelection :: proc(doc: ^Ldtk_Doc, li: int, s: ^Ldtk_Selection) {
	lv := &doc.levels[li]
	Bounds :: struct {mn, mx: [2]int}
	bounds := make(map[int]Bounds, allocator = context.temp_allocator)
	for c in s.cells {
		d := Ldtk_Doc_LayerDef(doc, &lv.layers[c.layer])
		if d == nil do continue
		if d.type == .IntGrid do Ldtk_Doc_SetIntGrid(doc, li, c.layer, c.cx, c.cy, 0)
		else do Ldtk_Doc_SetTile(doc, li, c.layer, c.cx, c.cy, -1)
		b, ok := bounds[c.layer]
		if !ok do b = {{c.cx, c.cy}, {c.cx, c.cy}}
		b.mn = {min(b.mn.x, c.cx), min(b.mn.y, c.cy)}
		b.mx = {max(b.mx.x, c.cx), max(b.mx.y, c.cy)}
		bounds[c.layer] = b
	}
	for layer, b in bounds do Ldtk_Doc_ApplyRules(doc, li, layer, b.mn.x, b.mn.y, b.mx.x, b.mx.y)
	for se in s.entities do Ldtk_Doc_RemoveEntity(doc, li, se.layer, se.obj)
	Ldtk_Selection_Clear(s)
	Ldtk_Doc_Touch(doc)
}

// Ldtk_Doc_DuplicateEntity copies an entity (new iid) moved by `deltaPx`.
Ldtk_Doc_DuplicateEntity :: proc(doc: ^Ldtk_Doc, li, layer: int, ent: ^LdtkJson, deltaPx: [2]int) -> ^LdtkJson {
	a := doc.allocator
	list := LdtkJson_Get(doc.levels[li].layers[layer].obj, "entityInstances")
	if list == nil do return nil
	dup := LdtkJson_Clone(ent, a)
	LdtkJson_SetStr(dup, "iid", Ldtk_Doc_Iid(context.temp_allocator), a)
	append(&list.items, dup)
	px := LdtkJson_Arr(ent, "px")
	if len(px) >= 2 do Ldtk_Doc_MoveEntity(doc, li, layer, dup, {int(px[0].num) + deltaPx.x, int(px[1].num) + deltaPx.y})
	doc.levels[li].dirty = true
	Ldtk_Doc_Touch(doc)
	return dup
}

// Ldtk_Doc_EntityLayerAllowed: can this entity live in that Entities layer
// (the layer def's required / excluded tags, LDtk's rule)?
Ldtk_Doc_EntityLayerAllowed :: proc(doc: ^Ldtk_Doc, li, layer: int, ent: ^LdtkJson) -> bool {
	ly := &doc.levels[li].layers[layer]
	d := Ldtk_Doc_LayerDef(doc, ly)
	if d == nil || d.type != .Entities do return false
	tags := LdtkJson_Arr(ent, "__tags")
	has :: proc(tags: []^LdtkJson, t: string) -> bool {
		for x in tags do if x.kind == .String && x.text == t do return true
		return false
	}
	req := LdtkJson_Arr(d.obj, "requiredTags")
	if len(req) > 0 {
		any := false
		for r in req do if has(tags, r.text) do any = true
		if !any do return false
	}
	for x in LdtkJson_Arr(d.obj, "excludedTags") do if has(tags, x.text) do return false
	return true
}

// Ldtk_Doc_MoveEntityToLayer moves an entity to another Entities layer of
// the level (LDtk's "move entities between layers"); its position is kept.
Ldtk_Doc_MoveEntityToLayer :: proc(doc: ^Ldtk_Doc, li, from, to: int, ent: ^LdtkJson) -> bool {
	if from == to do return false
	lv := &doc.levels[li]
	td := Ldtk_Doc_LayerDef(doc, &lv.layers[to])
	if td == nil || td.type != .Entities do return false
	src := LdtkJson_Get(lv.layers[from].obj, "entityInstances")
	dst := LdtkJson_Get(lv.layers[to].obj, "entityInstances")
	if src == nil || dst == nil do return false
	for it, i in src.items {
		if it != ent do continue
		ordered_remove(&src.items, i)
		append(&dst.items, ent)
		px := LdtkJson_Arr(ent, "px")
		if len(px) >= 2 do Ldtk_Doc_MoveEntity(doc, li, to, ent, {int(px[0].num), int(px[1].num)})
		lv.dirty = true
		Ldtk_Doc_Touch(doc)
		return true
	}
	return false
}


// ----------------------------------------------------------------------------
// Clipboard
// ----------------------------------------------------------------------------

Ldtk_ClipCell :: struct {
	layerUid: int,
	cell:     [2]int, // relative to the clip's origin cell (in that layer's grid)
	value:    i32,
	tiles:    [dynamic]Ldtk_DocTile,
}

Ldtk_ClipEntity :: struct {
	layerUid: int,
	px:       [2]int, // relative to the clip's origin (pixels)
	json:     string, // the entity, minified
}

// Ldtk_Clipboard: copied cells and entities (heap), pasteable into any level
// of any open project with layers of the same uids.
Ldtk_Clipboard :: struct {
	cells:    [dynamic]Ldtk_ClipCell,
	entities: [dynamic]Ldtk_ClipEntity,
	origin:   [2]int, // top-left of what was copied, level pixels
	size:     [2]int, // its size in pixels
}

Ldtk_Clipboard_Clear :: proc(c: ^Ldtk_Clipboard) {
	for &x in c.cells do delete(x.tiles)
	for x in c.entities do delete(x.json)
	clear(&c.cells)
	clear(&c.entities)
}

Ldtk_Clipboard_Destroy :: proc(c: ^Ldtk_Clipboard) {
	Ldtk_Clipboard_Clear(c)
	delete(c.cells)
	delete(c.entities)
	c^ = {}
}

Ldtk_Clipboard_Empty :: proc(c: ^Ldtk_Clipboard) -> bool {return len(c.cells) == 0 && len(c.entities) == 0}

// Ldtk_Doc_CopySelection fills the clipboard with the selection.
Ldtk_Doc_CopySelection :: proc(doc: ^Ldtk_Doc, li: int, s: ^Ldtk_Selection, c: ^Ldtk_Clipboard) {
	Ldtk_Clipboard_Clear(c)
	if Ldtk_Selection_Empty(s) do return
	lv := &doc.levels[li]
	mn := [2]int{max(int), max(int)}
	mx := [2]int{min(int), min(int)}
	for x in s.cells {
		ly := &lv.layers[x.layer]
		d := Ldtk_Doc_LayerDef(doc, ly)
		off := Ldtk_Doc_LayerOffset(ly)
		p := [2]int{x.cx * d.gridSize + off.x, x.cy * d.gridSize + off.y}
		mn = {min(mn.x, p.x), min(mn.y, p.y)}
		mx = {max(mx.x, p.x + d.gridSize), max(mx.y, p.y + d.gridSize)}
	}
	for x in s.entities {
		r := Ldtk_Doc_EntityRect(x.obj)
		mn = {min(mn.x, r[0]), min(mn.y, r[1])}
		mx = {max(mx.x, r[0] + r[2]), max(mx.y, r[1] + r[3])}
	}
	c.origin, c.size = mn, mx - mn
	for x in s.cells {
		ly := &lv.layers[x.layer]
		d := Ldtk_Doc_LayerDef(doc, ly)
		off := Ldtk_Doc_LayerOffset(ly)
		cc := Ldtk_ClipCell{layerUid = d.uid, value = i32(Ldtk_Doc_GetIntGrid(ly, x.cx, x.cy))}
		cc.cell = {x.cx - ldtk_floor_div(mn.x - off.x, d.gridSize), x.cy - ldtk_floor_div(mn.y - off.y, d.gridSize)}
		cc.tiles = make([dynamic]Ldtk_DocTile)
		append(&cc.tiles, ..Ldtk_Doc_TilesAt(ly, x.cx, x.cy))
		append(&c.cells, cc)
	}
	for x in s.entities {
		d := Ldtk_Doc_LayerDef(doc, &lv.layers[x.layer])
		px := LdtkJson_Arr(x.obj, "px")
		p := [2]int{}
		if len(px) >= 2 do p = {int(px[0].num), int(px[1].num)}
		append(&c.entities, Ldtk_ClipEntity{layerUid = d.uid, px = p - mn, json = LdtkJson_ToString(x.obj, .Minified)})
	}
}

// Ldtk_Doc_Paste puts the clipboard with its top-left at `at` (level pixels,
// snapped per layer grid) into the level's layers with the same uids; the
// selection becomes what was pasted. Returns false when nothing fitted.
Ldtk_Doc_Paste :: proc(doc: ^Ldtk_Doc, li: int, c: ^Ldtk_Clipboard, at: [2]int, s: ^Ldtk_Selection) -> bool {
	Ldtk_Selection_Clear(s)
	lv := &doc.levels[li]
	layerOf :: proc(doc: ^Ldtk_Doc, lv: ^Ldtk_DocLevel, uid: int) -> int {
		for &ly, j in lv.layers do if d := Ldtk_Doc_LayerDef(doc, &ly); d != nil && d.uid == uid do return j
		return -1
	}
	Bounds :: struct {mn, mx: [2]int}
	bounds := make(map[int]Bounds, allocator = context.temp_allocator)
	for cc in c.cells {
		j := layerOf(doc, lv, cc.layerUid)
		if j < 0 do continue
		ly := &lv.layers[j]
		d := Ldtk_Doc_LayerDef(doc, ly)
		off := Ldtk_Doc_LayerOffset(ly)
		base := [2]int{ldtk_floor_div(at.x - off.x, d.gridSize), ldtk_floor_div(at.y - off.y, d.gridSize)}
		p := base + cc.cell
		if p.x < 0 || p.y < 0 || p.x >= ly.cWid || p.y >= ly.cHei do continue
		if d.type == .IntGrid {
			Ldtk_Doc_SetIntGrid(doc, li, j, p.x, p.y, int(cc.value))
		} else {
			Ldtk_Doc_SetTile(doc, li, j, p.x, p.y, -1)
			for t, k in cc.tiles do Ldtk_Doc_SetTile(doc, li, j, p.x, p.y, int(t.t), t.f, k > 0)
		}
		b, ok := bounds[j]
		if !ok do b = {p, p}
		b.mn = {min(b.mn.x, p.x), min(b.mn.y, p.y)}
		b.mx = {max(b.mx.x, p.x), max(b.mx.y, p.y)}
		bounds[j] = b
		append(&s.cells, Ldtk_SelCell{j, p.x, p.y})
	}
	for j, b in bounds do Ldtk_Doc_ApplyRules(doc, li, j, b.mn.x, b.mn.y, b.mx.x, b.mx.y)
	for ce in c.entities {
		j := layerOf(doc, lv, ce.layerUid)
		if j < 0 do continue
		list := LdtkJson_Get(lv.layers[j].obj, "entityInstances")
		if list == nil do continue
		obj, ok := LdtkJson_Parse(ce.json, doc.allocator)
		if !ok do continue
		LdtkJson_SetStr(obj, "iid", Ldtk_Doc_Iid(context.temp_allocator), doc.allocator)
		append(&list.items, obj)
		Ldtk_Doc_MoveEntity(doc, li, j, obj, at + ce.px)
		append(&s.entities, Ldtk_SelEntity{j, obj})
	}
	lv.dirty = true
	Ldtk_Doc_Touch(doc)
	return !Ldtk_Selection_Empty(s)
}
