package editor

import "core:fmt"
import "core:path/filepath"
import "core:strings"
import rl "vendor:raylib"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Level editor: project definitions (LDtk's "Project" panels)
//
//   Layers       add / remove / reorder, grid, opacity, offset, tileset,
//                auto-layer source, IntGrid values; auto-layer rule groups
//                and rules (pattern grid, tiles, chance, flips, modulo,
//                break on match)
//   Entities     size, colour, pivot, resizing, tile, fields
//   Enums        values
//   Tilesets     from project images, grid / spacing / padding
//   Level fields
//
// Every change is a project undo step (Ldtk_Doc_Checkpoint(doc, -1, ...)).
// ============================================================================

@(private = "file")
Defs_Page :: enum u8 {
	Layers,
	Entities,
	Enums,
	Tilesets,
	Level_Fields,
}

@(private = "file")
defs: struct {
	page:      Defs_Page,
	layerUid:  int,
	entityUid: int,
	enumUid:   int,
	tilesetUid: int,
	ruleUid:   int,
	tileId:    int,
}

// text_edit: a text field bound to `key` of `obj`; returns the new text
// after Enter / leaving the field (ok = changed).
@(private = "file")
text_edit :: proc(id: string, obj: ^e.LdtkJson, key: string) -> (string, bool) {
	// (ImGui edits its own copy while the field is active)
	cur := e.LdtkJson_Str(obj, key)
	buf: [256]u8
	copy(buf[:len(buf) - 1], cur)
	changed := imgui.InputText(fmt.ctprintf("##%s", id), cstring(raw_data(buf[:])), len(buf), {.EnterReturnsTrue})
	Drive_Item(id)
	text := strings.clone(string(cstring(raw_data(buf[:]))), context.temp_allocator)
	return text, changed && text != cur
}

@(private = "file")
checkpoint :: proc(label: string) {
	e.Ldtk_Doc_Checkpoint(GlobalLevel.doc, -1, label)
}

LevelDefs_Render :: proc(state: ^EditorState) {
	L := &GlobalLevel
	if !L.showDefs || L.doc == nil do return
	imgui.SetNextWindowSize({760, 560}, .FirstUseEver)
	center := imgui.GetMainViewport().WorkPos + imgui.GetMainViewport().WorkSize * 0.5
	imgui.SetNextWindowPos(center, .FirstUseEver, {0.5, 0.5})
	defer imgui.End()
	if !imgui.Begin("Definitions###LevelDefsWindow", &L.showDefs, {.NoCollapse}) do return
	avail := imgui.GetContentRegionAvail()
	if imgui.BeginChild("##defs_nav", {130, avail.y}, {}, {}) {
		for p in Defs_Page {
			name := fmt.tprintf("%v", p)
			name, _ = strings.replace_all(name, "_", " ", context.temp_allocator)
			if imgui.Selectable(fmt.ctprintf("%s##defsnav", name), defs.page == p, {}, {0, 24}) do defs.page = p
			Drive_Item(fmt.tprintf("defs.page:%s", name))
		}
	}
	imgui.EndChild()
	imgui.SameLine(0, 8)
	if imgui.BeginChild("##defs_page", {0, avail.y}, {}, {}) {
		switch defs.page {
		case .Layers: page_layers(state)
		case .Entities: page_entities(state)
		case .Enums: page_enums(state)
		case .Tilesets: page_tilesets(state)
		case .Level_Fields: page_level_fields(state)
		}
	}
	imgui.EndChild()
}

// ----------------------------------------------------------------------------
// Layers
// ----------------------------------------------------------------------------

@(private = "file")
page_layers :: proc(state: ^EditorState) {
	L := &GlobalLevel
	doc := L.doc
	avail := imgui.GetContentRegionAvail()
	if imgui.BeginChild("##layer_list", {200, avail.y}, {.Borders}, {}) {
		for t in e.LdtkLayerType {
			if UI_IconButton(LAYER_TYPE_ICON[t], fmt.tprintf("defs.addlayer:%v", t), fmt.tprintf("Add a %v layer", t), false, 26) {
				checkpoint("Add Layer")
				ts := len(doc.tilesets) > 0 && t != .Entities && t != .IntGrid ? doc.tilesets[0].uid : -1
				defs.layerUid = e.Ldtk_Doc_AddLayerDef(doc, t, fmt.tprintf("%v", t), ts)
				level_after_defs()
			}
			imgui.SameLine()
		}
		imgui.NewLine()
		imgui.Separator()
		for &d in doc.layerDefs {
			if imgui.Selectable(fmt.ctprintf("%s  %s##ld%d", LAYER_TYPE_ICON[d.type], d.identifier, d.uid), defs.layerUid == d.uid, {}, {0, 22}) do defs.layerUid = d.uid
			Drive_Item(fmt.tprintf("defs.layer:%s", d.identifier))
		}
	}
	imgui.EndChild()
	imgui.SameLine(0, 8)
	if imgui.BeginChild("##layer_props", {0, avail.y}, {}, {}) {
		di := e.Ldtk_Doc_LayerDefIndex(doc, defs.layerUid)
		if di < 0 {
			UI_DimText("Pick a layer, or add one with the buttons on the left.")
		} else {
			layer_props(state, di)
		}
	}
	imgui.EndChild()
}

// level_after_defs keeps the editor's indices valid after a defs change.
level_after_defs :: proc() {
	L := &GlobalLevel
	if L.doc == nil || len(L.doc.levels) == 0 do return
	level_follow_layer_uid()
	L.selEntity = nil
	level_sync_palette()
}

@(private = "file")
layer_props :: proc(state: ^EditorState, di: int) {
	L := &GlobalLevel
	doc := L.doc
	d := &doc.layerDefs[di]
	uid := d.uid
	obj := d.obj
	UI_PanelTitle(LAYER_TYPE_ICON[d.type], d.identifier, fmt.tprintf("%v layer", d.type))
	UI_HeaderButtons(3)
	if UI_HeaderButton(ICON_FA_ARROW_UP, "defs.layer.up", "Move up (drawn above)") {
		checkpoint("Move Layer")
		e.Ldtk_Doc_MoveLayerDef(doc, uid, -1)
		level_after_defs()
		return
	}
	if UI_HeaderButton(ICON_FA_ARROW_DOWN, "defs.layer.down", "Move down") {
		checkpoint("Move Layer")
		e.Ldtk_Doc_MoveLayerDef(doc, uid, 1)
		level_after_defs()
		return
	}
	if UI_HeaderButton(ICON_FA_TRASH, "defs.layer.remove", "Delete the layer (and its content in every level)") {
		checkpoint("Delete Layer")
		e.Ldtk_Doc_RemoveLayerDef(doc, uid)
		defs.layerUid = -1
		level_after_defs()
		return
	}
	if UI_BeginProps("##layer_props_t") {
		UI_PropLabel("Identifier")
		if name, ok := text_edit("defs.layer.name", obj, "identifier"); ok {
			checkpoint("Rename Layer")
			e.Ldtk_Doc_RenameLayerDef(doc, uid, name)
		}
		UI_PropLabel("Grid size")
		grid := i32(d.gridSize)
		if imgui.InputInt("##grid", &grid, 1, 8, {.EnterReturnsTrue}) && grid >= 1 {
			checkpoint("Layer Grid")
			e.LdtkJson_SetInt(obj, "gridSize", int(grid), doc.allocator)
			e.Ldtk_Doc_LayerDefChanged(doc, uid)
		}
		Drive_Item("defs.layer.grid")
		UI_PropLabel("Opacity")
		op := d.opacity
		if imgui.SliderFloat("##opacity", &op, 0, 1, "%.2f") {
			e.Ldtk_Doc_CheckpointOnce(doc, -1, "Layer Opacity", obj)
			e.LdtkJson_SetFloat(obj, "displayOpacity", f64(op), doc.allocator)
			e.Ldtk_Doc_RefreshDefs(doc)
		}
		if imgui.IsItemDeactivatedAfterEdit() do e.Ldtk_Doc_LayerDefChanged(doc, uid) // the instances' cached opacity
		if imgui.IsItemDeactivated() do e.Ldtk_Doc_EndCoalesce(doc)
		UI_PropLabel("Offset (px)")
		off := [2]i32{i32(d.pxOffset.x), i32(d.pxOffset.y)}
		if imgui.InputInt2("##off", &off, {.EnterReturnsTrue}) {
			checkpoint("Layer Offset")
			e.LdtkJson_SetInt(obj, "pxOffsetX", int(off.x), doc.allocator)
			e.LdtkJson_SetInt(obj, "pxOffsetY", int(off.y), doc.allocator)
			e.Ldtk_Doc_LayerDefChanged(doc, uid)
		}
		if d.type != .Entities {
			UI_PropLabel("Tileset")
			names := make([]string, len(doc.tilesets) + 1, context.temp_allocator)
			names[0] = "(none)"
			cur := 0
			for ts, i in doc.tilesets {
				names[i + 1] = ts.identifier
				if ts.uid == d.tilesetUid do cur = i + 1
			}
			if pick, changed := UI_Combo("defs.layer.tileset", cur, names); changed {
				checkpoint("Layer Tileset")
				if pick == 0 do e.LdtkJson_SetNull(obj, "tilesetDefUid", doc.allocator)
				else do e.LdtkJson_SetInt(obj, "tilesetDefUid", doc.tilesets[pick - 1].uid, doc.allocator)
				e.Ldtk_Doc_LayerDefChanged(doc, uid)
			}
		}
		if d.type == .AutoLayer {
			UI_PropLabel("Rules read")
			names := make([dynamic]string, context.temp_allocator)
			uids := make([dynamic]int, context.temp_allocator)
			append(&names, "(none)")
			append(&uids, -1)
			cur := 0
			for &o in doc.layerDefs do if o.type == .IntGrid {
				if o.uid == d.autoSourceUid do cur = len(names)
				append(&names, o.identifier)
				append(&uids, o.uid)
			}
			if pick, changed := UI_Combo("defs.layer.source", cur, names[:]); changed {
				checkpoint("Auto Layer Source")
				if uids[pick] < 0 do e.LdtkJson_SetNull(obj, "autoSourceLayerDefUid", doc.allocator)
				else do e.LdtkJson_SetInt(obj, "autoSourceLayerDefUid", uids[pick], doc.allocator)
				e.Ldtk_Doc_LayerDefChanged(doc, uid)
			}
		}
		UI_EndProps()
	}
	d = &doc.layerDefs[e.Ldtk_Doc_LayerDefIndex(doc, uid)]
	if d.type == .IntGrid && UI_SectionHeader("IntGrid values") {
		vals := e.LdtkJson_Arr(d.obj, "intGridValues")
		for v, i in vals {
			imgui.PushIDInt(i32(i))
			value := e.LdtkJson_Int(v, "value")
			c := e.Ldtk_ParseHexColor(e.LdtkJson_Str(v, "color", "#000000"))
			col := [3]f32{f32(c.r) / 255, f32(c.g) / 255, f32(c.b) / 255}
			if imgui.ColorEdit3("##c", &col, {.NoInputs}) {
				e.Ldtk_Doc_CheckpointOnce(doc, -1, "IntGrid Colour", v)
				e.LdtkJson_SetStr(v, "color", e.Ldtk_ColorHex({u8(col[0] * 255 + 0.5), u8(col[1] * 255 + 0.5), u8(col[2] * 255 + 0.5), 255}), doc.allocator)
				e.Ldtk_Doc_RefreshDefs(doc)
			}
			imgui.SameLine()
			imgui.TextUnformatted(fmt.ctprintf("%d", value))
			imgui.SameLine()
			imgui.SetNextItemWidth(160)
			if name, ok := text_edit(fmt.tprintf("defs.value.name:%d", value), v, "identifier"); ok {
				checkpoint("IntGrid Name")
				e.LdtkJson_SetStr(v, "identifier", name, doc.allocator)
				e.Ldtk_Doc_RefreshDefs(doc)
			}
			imgui.SameLine()
			if UI_IconButton(ICON_FA_TRASH, fmt.tprintf("defs.value.remove:%d", value), "Remove (clears its cells)", false, 22) {
				checkpoint("Remove IntGrid Value")
				e.Ldtk_Doc_RemoveIntGridValue(doc, uid, value)
				imgui.PopID()
				break
			}
			imgui.PopID()
		}
		if UI_Button(fmt.tprintf("%s  Add value", ICON_FA_PLUS), "defs.value.add") {
			checkpoint("Add IntGrid Value")
			e.Ldtk_Doc_AddIntGridValue(doc, uid)
			level_sync_palette()
		}
	}
	d = &doc.layerDefs[e.Ldtk_Doc_LayerDefIndex(doc, uid)]
	if (d.type == .AutoLayer || d.type == .IntGrid) && UI_SectionHeader("Auto-layer rules") {
		rules_editor(state, uid)
	}
}

// ----------------------------------------------------------------------------
// Rules
// ----------------------------------------------------------------------------

@(private = "file")
rules_editor :: proc(state: ^EditorState, layerUid: int) {
	L := &GlobalLevel
	doc := L.doc
	d := &doc.layerDefs[e.Ldtk_Doc_LayerDefIndex(doc, layerUid)]
	if d.tilesetUid < 0 {
		UI_DimText("Pick a tileset first: rules place its tiles.")
		return
	}
	srcDef := d
	if d.type == .AutoLayer {
		si := e.Ldtk_Doc_LayerDefIndex(doc, d.autoSourceUid)
		if si < 0 {
			UI_DimText("Pick the IntGrid layer the rules read.")
			return
		}
		srcDef = &doc.layerDefs[si]
	}
	for gi in 0 ..< len(d.groups) {
		g := &doc.layerDefs[e.Ldtk_Doc_LayerDefIndex(doc, layerUid)].groups[gi]
		imgui.PushIDInt(i32(g.uid))
		active := g.active
		if imgui.Checkbox("##gactive", &active) {
			checkpoint("Rule Group")
			e.LdtkJson_SetBool(g.obj, "active", active, doc.allocator)
			e.Ldtk_Doc_RulesChanged(doc, layerUid)
			imgui.PopID()
			return
		}
		UI_Tooltip("Group on / off")
		imgui.SameLine()
		imgui.PushFont(GlobalFonts.semibold)
		imgui.TextUnformatted(fmt.ctprintf("%s", g.name))
		imgui.PopFont()
		imgui.SameLine()
		optional := g.isOptional
		if imgui.Checkbox("optional##gopt", &optional) {
			checkpoint("Rule Group")
			e.LdtkJson_SetBool(g.obj, "isOptional", optional, doc.allocator)
			e.Ldtk_Doc_RulesChanged(doc, layerUid)
			imgui.PopID()
			return
		}
		UI_Tooltip("Optional groups are enabled per level (Layers panel)")
		imgui.SameLine()
		if UI_Button(fmt.tprintf("%s Rule", ICON_FA_PLUS), fmt.tprintf("defs.rule.add:%s", g.name)) {
			checkpoint("Add Rule")
			v := len(srcDef.values) > 0 ? srcDef.values[0].value : 1
			tile := 0
			if len(L.tileSel) > 0 do tile = int(L.tileSel[0])
			defs.ruleUid = e.Ldtk_Doc_AddRule(doc, layerUid, g.uid, 3, v, tile)
			imgui.PopID()
			return
		}
		g = &doc.layerDefs[e.Ldtk_Doc_LayerDefIndex(doc, layerUid)].groups[gi]
		for &r, ri in g.rules {
			imgui.PushIDInt(i32(r.uid))
			if rule_row(state, layerUid, srcDef, &r, ri) {
				imgui.PopID()
				imgui.PopID()
				return
			}
			imgui.PopID()
		}
		imgui.PopID()
		imgui.Separator()
	}
	if UI_Button(fmt.tprintf("%s  Terrain from picked 3x3 tiles", ICON_FA_WAND_MAGIC_SPARKLES), "defs.terrain") {
		if len(L.tileSel) == 9 && L.tileSelW == 3 {
			v := L.intValue
			if e.Ldtk_Doc_IntValue(srcDef, v) == nil do v = len(srcDef.values) > 0 ? srcDef.values[0].value : 1
			block: [9]int
			for t, i in L.tileSel do block[i] = int(t)
			checkpoint("Terrain Rules")
			e.Ldtk_Doc_AddTerrainRules(doc, layerUid, v, block)
			return // (definitions rebuilt many times: this frame's pointers are stale)
		} else do Editor_Log(state, .Info, "Pick a 3x3 block of tiles (corners, edges, centre) in the Layers panel's tileset first")
	}
	UI_Tooltip("Rules drawing a 3x3 terrain block over the picked IntGrid value: corners, edges and the centre")
	imgui.SameLine()
	if UI_Button(fmt.tprintf("%s  Add rule group", ICON_FA_PLUS), "defs.group.add") {
		checkpoint("Add Rule Group")
		e.Ldtk_Doc_AddRuleGroup(doc, layerUid, fmt.tprintf("Group %d", len(d.groups) + 1))
	}
	UI_DimText("Pattern: left click requires the picked value, right click forbids it,")
	UI_DimText("Shift+click means any value, middle click clears.")
}

// rule_row draws one rule; returns true when the defs changed (stop).
@(private = "file")
rule_row :: proc(state: ^EditorState, layerUid: int, srcDef: ^e.Ldtk_DocLayerDef, r: ^e.Ldtk_DocRule, index: int) -> bool {
	L := &GlobalLevel
	doc := L.doc
	ts := e.Ldtk_Doc_Tileset(doc, doc.layerDefs[e.Ldtk_Doc_LayerDefIndex(doc, layerUid)].tilesetUid)
	cell :: 14
	size := r.size
	start := imgui.GetCursorScreenPos()
	dl := imgui.GetWindowDrawList()
	// pattern grid
	imgui.InvisibleButton("##pattern", {f32(size * cell), f32(size * cell)}, {.MouseButtonLeft, .MouseButtonRight, .MouseButtonMiddle})
	Drive_Item(fmt.tprintf("defs.rule.pattern:%d", index))
	hovered := imgui.IsItemHovered()
	for cy in 0 ..< size {
		for cx in 0 ..< size {
			v := int(r.pattern[cx + cy * size])
			mn := [2]f32{start.x + f32(cx * cell), start.y + f32(cy * cell)}
			mx := mn + {cell - 1, cell - 1}
			fill := imgui.Vec4{0.15, 0.16, 0.19, 1}
			if v == e.LDTK_AUTO_LAYER_ANYTHING do fill = {0.8, 0.8, 0.8, 1}
			else if v == -e.LDTK_AUTO_LAYER_ANYTHING do fill = {0.05, 0.05, 0.05, 1}
			else if v != 0 {
				iv := e.Ldtk_Doc_IntValue(srcDef, abs(v))
				c := iv != nil ? iv.color : rl.MAGENTA
				fill = {f32(c.r) / 255, f32(c.g) / 255, f32(c.b) / 255, 1}
			}
			imgui.DrawList_AddRectFilled(dl, mn, mx, col_u32(fill), 0, {})
			if v < 0 && v != -e.LDTK_AUTO_LAYER_ANYTHING do imgui.DrawList_AddLine(dl, mn, mx, col_u32(UI_DANGER), 2)
			if cx == size / 2 && cy == size / 2 do imgui.DrawList_AddRect(dl, mn, mx, col_u32(UI_WARNING), 0, {}, 1)
		}
	}
	if hovered {
		m := imgui.GetIO().MousePos
		cx := int((m.x - start.x) / cell)
		cy := int((m.y - start.y) / cell)
		if cx >= 0 && cy >= 0 && cx < size && cy < size {
			val := L.intValue
			if e.Ldtk_Doc_IntValue(srcDef, val) == nil do val = len(srcDef.values) > 0 ? srcDef.values[0].value : 1
			nv, set := 0, false
			shift := imgui.GetIO().KeyShift
			switch {
			case imgui.IsMouseClicked(.Left): nv, set = shift ? e.LDTK_AUTO_LAYER_ANYTHING : val, true
			case imgui.IsMouseClicked(.Right): nv, set = shift ? -e.LDTK_AUTO_LAYER_ANYTHING : -val, true
			case imgui.IsMouseClicked(.Middle): nv, set = 0, true
			}
			if set {
				checkpoint("Rule Pattern")
				e.Ldtk_Doc_SetRuleCell(doc, r.uid, cx, cy, nv)
				return true
			}
		}
	}
	imgui.SameLine(0, 8)
	// tiles
	if ts != nil {
		if tex, ok := level_texture(ts.uid); ok {
			for rect, i in r.tileRects {
				if i >= 6 do break
				if len(rect) == 0 do continue
				src := e.Ldtk_Doc_TileSrc(ts, int(rect[0]))
				uv0 := imgui.Vec2{f32(src.x) / f32(tex.width), f32(src.y) / f32(tex.height)}
				uv1 := imgui.Vec2{f32(int(src.x) + ts.gridSize) / f32(tex.width), f32(int(src.y) + ts.gridSize) / f32(tex.height)}
				imgui.Image(transmute(imgui.TextureID)level_texture_ptr(ts.uid), {28, 28}, uv0, uv1)
				imgui.SameLine(0, 2)
			}
		}
	}
	if UI_Button(fmt.tprintf("%s", ICON_FA_TABLE_CELLS), fmt.tprintf("defs.rule.tiles:%d", index)) && len(L.tileSel) > 0 {
		// the palette's selection: each tile a random choice (or one stamp)
		checkpoint("Rule Tiles")
		a := doc.allocator
		rects := e.LdtkJson_New(.Array, a)
		if r.stamp {
			one := e.LdtkJson_New(.Array, a)
			for t in L.tileSel do append(&one.items, e.LdtkJson_NewInt(int(t), a))
			append(&rects.items, one)
		} else {
			for t in L.tileSel {
				one := e.LdtkJson_New(.Array, a)
				append(&one.items, e.LdtkJson_NewInt(int(t), a))
				append(&rects.items, one)
			}
		}
		e.LdtkJson_Set(r.obj, "tileRectsIds", rects, a)
		e.Ldtk_Doc_RulesChanged(doc, layerUid)
		return true
	}
	UI_Tooltip("Use the tiles picked in the Layers panel's tileset (pick a Tiles layer, or this layer's tileset)")
	imgui.SameLine()
	if row_bool(r.obj, "flipX", "X", "Also match mirrored horizontally") || row_bool(r.obj, "flipY", "Y", "Also match mirrored vertically") || row_bool(r.obj, "breakOnMatch", ICON_FA_CIRCLE, "Break on match: later rules don't paint this cell") || row_bool(r.obj, "active", ICON_FA_EYE, "Rule on / off") {
		e.Ldtk_Doc_RulesChanged(doc, layerUid)
		return true
	}
	imgui.SameLine()
	if row_bool(r.obj, "tileMode", "S", "Stamp: place all the tiles as one block (else one at random)", true) {
		e.Ldtk_Doc_RulesChanged(doc, layerUid)
		return true
	}
	// numbers, on a second line next to the pattern
	imgui.NewLine()
	imgui.SetCursorScreenPos({start.x + f32(size * cell) + 8, imgui.GetCursorScreenPos().y})
	imgui.SetNextItemWidth(70)
	chance := f32(r.chance * 100)
	entered := imgui.InputFloat("##chance", &chance, 0, 0, "%.0f%%", {.EnterReturnsTrue})
	UI_Tooltip("Chance (Enter applies)")
	if entered {
		checkpoint("Rule Chance")
		e.LdtkJson_SetFloat(r.obj, "chance", f64(clamp(chance, 0, 100)) / 100, doc.allocator)
		e.Ldtk_Doc_RulesChanged(doc, layerUid)
		return true
	}
	imgui.SameLine()
	imgui.SetNextItemWidth(80)
	mod := [2]i32{i32(r.xModulo), i32(r.yModulo)}
	modEntered := imgui.InputInt2("##mod", &mod, {.EnterReturnsTrue})
	UI_Tooltip("Modulo X / Y: only every Nth cell (Enter applies)")
	if modEntered {
		checkpoint("Rule Modulo")
		e.LdtkJson_SetInt(r.obj, "xModulo", max(int(mod.x), 1), doc.allocator)
		e.LdtkJson_SetInt(r.obj, "yModulo", max(int(mod.y), 1), doc.allocator)
		e.Ldtk_Doc_RulesChanged(doc, layerUid)
		return true
	}
	imgui.SameLine()
	imgui.SetNextItemWidth(60)
	sz := i32(size)
	if imgui.InputInt("##size", &sz, 2, 2) {
		ns := clamp(int(sz) | 1, 1, e.LDTK_MAX_AUTO_PATTERN_SIZE)
		if ns != size {
			checkpoint("Rule Size")
			resize_rule(r, ns)
			e.Ldtk_Doc_RulesChanged(doc, layerUid)
			return true
		}
	}
	UI_Tooltip("Pattern size")
	imgui.SameLine()
	if UI_IconButton(ICON_FA_TRASH, fmt.tprintf("defs.rule.remove:%d", index), "Delete the rule", false, 22) {
		checkpoint("Delete Rule")
		e.Ldtk_Doc_RemoveRule(doc, r.uid)
		return true
	}
	imgui.SetCursorScreenPos({start.x, max(imgui.GetCursorScreenPos().y, start.y + f32(size * cell) + 4)})
	return false
}

// row_bool: a small toggle for a rule's boolean (or "tileMode" Stamp).
@(private = "file")
row_bool :: proc(obj: ^e.LdtkJson, key, label, tip: string, isMode := false) -> bool {
	doc := GlobalLevel.doc
	on := isMode ? e.LdtkJson_Str(obj, key) == "Stamp" : e.LdtkJson_Bool(obj, key, key == "active")
	pressed := UI_IconButton(label, fmt.tprintf("defs.rule.%s:%p", key, obj), tip, on, 22)
	imgui.SameLine(0, 2)
	if !pressed do return false
	checkpoint("Rule Option")
	if isMode do e.LdtkJson_SetStr(obj, key, on ? "Single" : "Stamp", doc.allocator)
	else do e.LdtkJson_SetBool(obj, key, !on, doc.allocator)
	return true
}

@(private = "file")
resize_rule :: proc(r: ^e.Ldtk_DocRule, ns: int) {
	doc := GlobalLevel.doc
	a := doc.allocator
	old := r.size
	pat := e.LdtkJson_New(.Array, a)
	pad := (ns - old) / 2
	for y in 0 ..< ns {
		for x in 0 ..< ns {
			ox, oy := x - pad, y - pad
			v := 0
			if ox >= 0 && oy >= 0 && ox < old && oy < old do v = int(r.pattern[ox + oy * old])
			append(&pat.items, e.LdtkJson_NewInt(v, a))
		}
	}
	e.LdtkJson_Set(r.obj, "pattern", pat, a)
	e.LdtkJson_SetInt(r.obj, "size", ns, a)
}

// ----------------------------------------------------------------------------
// Entities
// ----------------------------------------------------------------------------

@(private = "file")
page_entities :: proc(state: ^EditorState) {
	L := &GlobalLevel
	doc := L.doc
	avail := imgui.GetContentRegionAvail()
	if imgui.BeginChild("##entity_list", {200, avail.y}, {.Borders}, {}) {
		if UI_Button(fmt.tprintf("%s  Add entity", ICON_FA_PLUS), "defs.entity.add") {
			checkpoint("Add Entity")
			defs.entityUid = e.Ldtk_Doc_AddEntityDef(doc, "Entity")
			level_sync_palette()
		}
		imgui.Separator()
		for &ed in doc.entityDefs {
			if imgui.Selectable(fmt.ctprintf("%s##edl%d", ed.identifier, ed.uid), defs.entityUid == ed.uid, {}, {0, 22}) do defs.entityUid = ed.uid
			Drive_Item(fmt.tprintf("defs.entity:%s", ed.identifier))
		}
	}
	imgui.EndChild()
	imgui.SameLine(0, 8)
	if imgui.BeginChild("##entity_props", {0, avail.y}, {}, {}) {
		ed := e.Ldtk_Doc_EntityDef(doc, defs.entityUid)
		if ed == nil do UI_DimText("Pick an entity, or add one.")
		else do entity_props(state, ed.uid)
	}
	imgui.EndChild()
}

PIVOTS := [9][2]f64{{0, 0}, {0.5, 0}, {1, 0}, {0, 0.5}, {0.5, 0.5}, {1, 0.5}, {0, 1}, {0.5, 1}, {1, 1}}

@(private = "file")
entity_props :: proc(state: ^EditorState, uid: int) {
	L := &GlobalLevel
	doc := L.doc
	ed := e.Ldtk_Doc_EntityDef(doc, uid)
	obj := ed.obj
	a := doc.allocator
	UI_PanelTitle(ICON_FA_CUBE, ed.identifier, "entity")
	UI_HeaderButtons(1)
	if UI_HeaderButton(ICON_FA_TRASH, "defs.entity.remove", "Delete the entity and its instances") {
		checkpoint("Delete Entity")
		e.Ldtk_Doc_RemoveEntityDef(doc, uid)
		defs.entityUid = -1
		level_after_defs()
		return
	}
	if UI_BeginProps("##entity_props_t") {
		UI_PropLabel("Identifier")
		if name, ok := text_edit("defs.entity.name", obj, "identifier"); ok {
			checkpoint("Rename Entity")
			e.LdtkJson_SetStr(obj, "identifier", e.Ldtk_CleanIdentifier(name), a)
			e.Ldtk_Doc_EntityDefChanged(doc, uid)
		}
		UI_PropLabel("Size")
		size := [2]i32{i32(ed.size.x), i32(ed.size.y)}
		if imgui.InputInt2("##esize", &size, {.EnterReturnsTrue}) {
			checkpoint("Entity Size")
			e.LdtkJson_SetInt(obj, "width", max(int(size.x), 1), a)
			e.LdtkJson_SetInt(obj, "height", max(int(size.y), 1), a)
			e.Ldtk_Doc_EntityDefChanged(doc, uid)
		}
		UI_PropLabel("Colour")
		col := [3]f32{f32(ed.color.r) / 255, f32(ed.color.g) / 255, f32(ed.color.b) / 255}
		if imgui.ColorEdit3("##ecol", &col, {.NoInputs}) {
			e.Ldtk_Doc_CheckpointOnce(doc, -1, "Entity Colour", obj)
			e.LdtkJson_SetStr(obj, "color", e.Ldtk_ColorHex({u8(col[0] * 255 + 0.5), u8(col[1] * 255 + 0.5), u8(col[2] * 255 + 0.5), 255}), a)
			e.Ldtk_Doc_EntityDefChanged(doc, uid)
		}
		UI_PropLabel("Pivot")
		for p, i in PIVOTS {
			if i % 3 != 0 do imgui.SameLine(0, 2)
			on := abs(p.x - ed.pivot.x) < 0.01 && abs(p.y - ed.pivot.y) < 0.01
			if UI_IconButton(on ? ICON_FA_CIRCLE : "·", fmt.tprintf("defs.entity.pivot:%d", i), fmt.tprintf("Pivot %.1f, %.1f", p.x, p.y), on, 18) {
				checkpoint("Entity Pivot")
				e.LdtkJson_SetFloat(obj, "pivotX", p.x, a)
				e.LdtkJson_SetFloat(obj, "pivotY", p.y, a)
				e.Ldtk_Doc_EntityDefChanged(doc, uid)
			}
		}
		UI_PropLabel("Resizable")
		rx := e.LdtkJson_Bool(obj, "resizableX")
		ry := e.LdtkJson_Bool(obj, "resizableY")
		if imgui.Checkbox("X##rx", &rx) {
			checkpoint("Entity Resizable")
			e.LdtkJson_SetBool(obj, "resizableX", rx, a)
		}
		imgui.SameLine()
		if imgui.Checkbox("Y##ry", &ry) {
			checkpoint("Entity Resizable")
			e.LdtkJson_SetBool(obj, "resizableY", ry, a)
		}
		UI_PropLabel("Tile")
		if ed.tileRect[2] > 0 {
			if tex, ok := level_texture(ed.tilesetUid); ok {
				uv0 := imgui.Vec2{f32(ed.tileRect[0]) / f32(tex.width), f32(ed.tileRect[1]) / f32(tex.height)}
				uv1 := imgui.Vec2{f32(ed.tileRect[0] + ed.tileRect[2]) / f32(tex.width), f32(ed.tileRect[1] + ed.tileRect[3]) / f32(tex.height)}
				imgui.Image(transmute(imgui.TextureID)level_texture_ptr(ed.tilesetUid), {24, 24}, uv0, uv1)
				imgui.SameLine()
			}
		}
		if UI_Button("Use picked tile", "defs.entity.tile") {
			// the Layers panel's tileset selection
			if ts, rect, ok := picked_tile_rect(); ok {
				checkpoint("Entity Tile")
				e.Ldtk_Doc_SetEntityTile(doc, uid, ts, rect)
			} else do Editor_Log(state, .Info, "Pick tiles in a Tiles layer's palette first")
		}
		imgui.SameLine()
		if ed.tileRect[2] > 0 && UI_Button("Clear", "defs.entity.tile.clear") {
			checkpoint("Entity Tile")
			e.Ldtk_Doc_SetEntityTile(doc, uid, -1, {})
		}
		UI_EndProps()
	}
	if UI_SectionHeader("Fields") do fields_editor(state, uid, e.LdtkJson_Arr(obj, "fieldDefs"))
}

// picked_tile_rect: the palette selection as a pixel rectangle.
@(private = "file")
picked_tile_rect :: proc() -> (int, [4]int, bool) {
	L := &GlobalLevel
	if len(L.tileSel) == 0 do return -1, {}, false
	ly, _ := level_active_layer()
	if ly == nil do return -1, {}, false
	ts := e.Ldtk_Doc_LayerTileset(L.doc, ly)
	if ts == nil do return -1, {}, false
	src := e.Ldtk_Doc_TileSrc(ts, int(L.tileSel[0]))
	return ts.uid, {int(src.x), int(src.y), ts.gridSize * L.tileSelW, ts.gridSize * L.tileSelH}, true
}

@(private = "file")
fields_editor :: proc(state: ^EditorState, entityUid: int, fieldDefs: []^e.LdtkJson) {
	L := &GlobalLevel
	doc := L.doc
	for fd, i in fieldDefs {
		imgui.PushIDInt(i32(i))
		imgui.TextUnformatted(fmt.ctprintf("%s", e.LdtkJson_Str(fd, "identifier")))
		imgui.SameLine(180)
		UI_DimText(e.LdtkJson_Str(fd, "__type"))
		imgui.SameLine(320)
		nullable := e.LdtkJson_Bool(fd, "canBeNull")
		if imgui.Checkbox("nullable", &nullable) {
			checkpoint("Field")
			e.LdtkJson_SetBool(fd, "canBeNull", nullable, doc.allocator)
		}
		imgui.SameLine()
		if UI_IconButton(ICON_FA_TRASH, fmt.tprintf("defs.field.remove:%s", e.LdtkJson_Str(fd, "identifier")), "Delete the field", false, 22) {
			checkpoint("Delete Field")
			e.Ldtk_Doc_RemoveFieldDef(doc, e.LdtkJson_Int(fd, "uid"))
			imgui.PopID()
			return
		}
		imgui.PopID()
	}
	// add: a type, then a name
	@(static) typeIdx: int
	names := make([dynamic]string, context.temp_allocator)
	types := make([dynamic]string, context.temp_allocator)
	for t in e.LDTK_FIELD_TYPES {
		append(&names, t.label)
		append(&types, t.type)
	}
	for en in e.LdtkJson_Arr(e.LdtkJson_Get(doc.root, "defs"), "enums") {
		append(&names, fmt.tprintf("Enum %s", e.LdtkJson_Str(en, "identifier")))
		append(&types, fmt.tprintf("F_Enum(%d)", e.LdtkJson_Int(en, "uid")))
	}
	imgui.SetNextItemWidth(140)
	typeIdx, _ = UI_Combo(fmt.tprintf("defs.field.type:%d", entityUid), clamp(typeIdx, 0, len(names) - 1), names[:])
	imgui.SameLine()
	if UI_Button(fmt.tprintf("%s  Add field", ICON_FA_PLUS), fmt.tprintf("defs.field.add:%d", entityUid)) {
		checkpoint("Add Field")
		e.Ldtk_Doc_AddFieldDef(doc, entityUid, types[typeIdx], strings.to_lower(names[typeIdx], context.temp_allocator))
	}
}

// ----------------------------------------------------------------------------
// Enums / tilesets / level fields
// ----------------------------------------------------------------------------

@(private = "file")
page_enums :: proc(state: ^EditorState) {
	L := &GlobalLevel
	doc := L.doc
	enums := e.LdtkJson_Arr(e.LdtkJson_Get(doc.root, "defs"), "enums")
	avail := imgui.GetContentRegionAvail()
	if imgui.BeginChild("##enum_list", {200, avail.y}, {.Borders}, {}) {
		if UI_Button(fmt.tprintf("%s  Add enum", ICON_FA_PLUS), "defs.enum.add") {
			checkpoint("Add Enum")
			defs.enumUid = e.Ldtk_Doc_AddEnum(doc, "Enum")
		}
		imgui.Separator()
		for en in enums {
			uid := e.LdtkJson_Int(en, "uid")
			name := e.LdtkJson_Str(en, "identifier")
			if imgui.Selectable(fmt.ctprintf("%s##enl%d", name, uid), defs.enumUid == uid, {}, {0, 22}) do defs.enumUid = uid
			Drive_Item(fmt.tprintf("defs.enum:%s", name))
		}
	}
	imgui.EndChild()
	imgui.SameLine(0, 8)
	if imgui.BeginChild("##enum_props", {0, avail.y}, {}, {}) {
		en := e.Ldtk_Doc_EnumDef(doc, defs.enumUid)
		if en == nil {
			UI_DimText("Pick an enum, or add one.")
		} else {
			UI_PanelTitle(ICON_FA_LIST, e.LdtkJson_Str(en, "identifier"), "enum")
			if UI_BeginProps("##enum_t") {
				UI_PropLabel("Identifier")
				if name, ok := text_edit("defs.enum.name", en, "identifier"); ok {
					checkpoint("Rename Enum")
					e.LdtkJson_SetStr(en, "identifier", e.Ldtk_CleanIdentifier(name), doc.allocator)
				}
				UI_EndProps()
			}
			UI_SectionHeader("Values")
			vals := e.LdtkJson_Get(en, "values")
			for v, i in vals.items {
				imgui.PushIDInt(i32(i))
				imgui.TextUnformatted(fmt.ctprintf("%s", e.LdtkJson_Str(v, "id")))
				imgui.SameLine(200)
				if UI_IconButton(ICON_FA_TRASH, fmt.tprintf("defs.enum.value.remove:%s", e.LdtkJson_Str(v, "id")), "Remove", false, 22) {
					checkpoint("Remove Enum Value")
					ordered_remove(&vals.items, i)
					e.Ldtk_Doc_Touch(doc)
					imgui.PopID()
					break
				}
				imgui.PopID()
			}
			@(static) valBuf: [64]u8
			imgui.SetNextItemWidth(160)
			enter := imgui.InputTextWithHint("##newval", "New value", cstring(raw_data(valBuf[:])), len(valBuf), {.EnterReturnsTrue})
			Drive_Item("defs.enum.value.name")
			imgui.SameLine()
			if (UI_Button(fmt.tprintf("%s  Add", ICON_FA_PLUS), "defs.enum.value.add") || enter) && valBuf[0] != 0 {
				checkpoint("Add Enum Value")
				e.Ldtk_Doc_AddEnumValue(doc, defs.enumUid, string(cstring(raw_data(valBuf[:]))))
				valBuf = {}
			}
		}
	}
	imgui.EndChild()
}

@(private = "file")
page_tilesets :: proc(state: ^EditorState) {
	L := &GlobalLevel
	doc := L.doc
	avail := imgui.GetContentRegionAvail()
	if imgui.BeginChild("##tileset_list", {220, avail.y}, {.Borders}, {}) {
		UI_DimText("Add from a project image:")
		images := Editor_ListProjectFiles(state, "", {".png"})
		imgui.SetNextItemWidth(-1)
		if imgui.BeginCombo("##add_tileset", "Pick an image...") {
			for rel in images {
				if imgui.Selectable(fmt.ctprintf("%s", rel)) do add_tileset(state, rel)
				Drive_Item(fmt.tprintf("pick:%s", rel))
			}
			imgui.EndCombo()
		}
		Drive_Item("defs.tileset.add")
		imgui.Separator()
		for &ts in doc.tilesets {
			if imgui.Selectable(fmt.ctprintf("%s##tsl%d", ts.identifier, ts.uid), defs.tilesetUid == ts.uid, {}, {0, 22}) do defs.tilesetUid = ts.uid
			Drive_Item(fmt.tprintf("defs.tileset:%s", ts.identifier))
		}
	}
	imgui.EndChild()
	imgui.SameLine(0, 8)
	if imgui.BeginChild("##tileset_props", {0, avail.y}, {}, {}) {
		ts := e.Ldtk_Doc_Tileset(doc, defs.tilesetUid)
		if ts == nil {
			UI_DimText("Pick a tileset, or add one from an image.")
		} else {
			uid := ts.uid
			obj := ts.obj
			UI_PanelTitle(ICON_FA_TABLE_CELLS, ts.identifier, ts.relPath)
			if UI_BeginProps("##ts_t") {
				changed := false
				num :: proc(label, key: string, obj: ^e.LdtkJson, minv: int) -> bool {
					UI_PropLabel(label)
					v := i32(e.LdtkJson_Int(obj, key))
					if imgui.InputInt(fmt.ctprintf("##%s", key), &v, 1, 8, {.EnterReturnsTrue}) && int(v) >= minv {
						checkpoint("Tileset")
						e.LdtkJson_SetInt(obj, key, int(v), GlobalLevel.doc.allocator)
						return true
					}
					Drive_Item(fmt.tprintf("defs.tileset.%s", key))
					return false
				}
				changed |= num("Tile size", "tileGridSize", obj, 1)
				changed |= num("Spacing", "spacing", obj, 0)
				changed |= num("Padding", "padding", obj, 0)
				if changed {
					UI_EndProps()
					tileset_changed(state, uid)
					imgui.EndChild()
					return // (definitions rebuilt per layer: this frame's pointers are stale)
				}
				UI_EndProps()
			}
			UI_DimText(fmt.tprintf("%dx%d px, %dx%d tiles", ts.pxSize.x, ts.pxSize.y, ts.cWid, ts.cHei))
			tile_data_editor(state, uid)
		}
	}
	imgui.EndChild()
}

// add_tileset adds a project image (path made relative to the .ldtk).
@(private = "file")
add_tileset :: proc(state: ^EditorState, rel: string) {
	L := &GlobalLevel
	doc := L.doc
	abs := level_abs(state, rel)
	img := rl.LoadImage(strings.clone_to_cstring(abs, context.temp_allocator))
	if img.data == nil {
		Editor_Log(state, .Error, "Could not read %s", rel)
		return
	}
	defer rl.UnloadImage(img)
	relToDoc, err := filepath.rel(doc.dir, abs, context.temp_allocator)
	if err != nil do relToDoc = rel
	relToDoc, _ = strings.replace_all(relToDoc, "\\", "/", context.temp_allocator)
	grid := e.LdtkJson_Int(doc.root, "defaultGridSize", 16)
	checkpoint("Add Tileset")
	defs.tilesetUid = e.Ldtk_Doc_AddTileset(doc, relToDoc, {int(img.width), int(img.height)}, grid, &img)
}

// tileset_changed: grid / spacing / padding changed - the cached sizes,
// opaque tiles and every tile's source follow.
@(private = "file")
tileset_changed :: proc(state: ^EditorState, uid: int) {
	L := &GlobalLevel
	doc := L.doc
	ts := e.Ldtk_Doc_Tileset(doc, uid)
	if ts == nil do return
	a := doc.allocator
	obj := ts.obj
	grid := max(e.LdtkJson_Int(obj, "tileGridSize", 16), 1)
	sp := e.LdtkJson_Int(obj, "spacing")
	pad := e.LdtkJson_Int(obj, "padding")
	step := grid + sp
	e.LdtkJson_SetInt(obj, "__cWid", (ts.pxSize.x - pad * 2 + step - 1) / step, a)
	e.LdtkJson_SetInt(obj, "__cHei", (ts.pxSize.y - pad * 2 + step - 1) / step, a)
	abs, _ := filepath.join({doc.dir, ts.relPath}, context.temp_allocator)
	img := rl.LoadImage(strings.clone_to_cstring(abs, context.temp_allocator))
	if img.data != nil {
		e.LdtkJson_Set(obj, "cachedPixelData", e.Ldtk_TilesetPixelData(&img, grid, sp, pad, a), a)
		rl.UnloadImage(img)
	}
	e.Ldtk_Doc_RefreshDefs(doc)
	for &d in doc.layerDefs do if d.tilesetUid == uid do e.Ldtk_Doc_LayerDefChanged(doc, d.uid)
}

@(private = "file")
page_level_fields :: proc(state: ^EditorState) {
	UI_PanelTitle(ICON_FA_MAP, "Level fields")
	UI_DimText("Values every level has (edited in the Level Inspector).")
	fields_editor(state, -1, e.LdtkJson_Arr(e.LdtkJson_Get(GlobalLevel.doc.root, "defs"), "levelFields"))
}

// tile_data_editor: the tileset's tiles; the picked tile's custom data,
// animation and enum tags.
@(private = "file")
tile_data_editor :: proc(state: ^EditorState, uid: int) {
	L := &GlobalLevel
	doc := L.doc
	ts := e.Ldtk_Doc_Tileset(doc, uid)
	a := doc.allocator
	// tag enum
	if UI_BeginProps("##ts_tags") {
		UI_PropLabel("Tag enum")
		enums := e.LdtkJson_Arr(e.LdtkJson_Get(doc.root, "defs"), "enums")
		names := make([]string, len(enums) + 1, context.temp_allocator)
		names[0] = "(none)"
		cur := 0
		src := e.LdtkJson_Int(ts.obj, "tagsSourceEnumUid", -1)
		for en, i in enums {
			names[i + 1] = e.LdtkJson_Str(en, "identifier")
			if e.LdtkJson_Int(en, "uid") == src do cur = i + 1
		}
		if pick, changed := UI_Combo("defs.tileset.tagenum", cur, names); changed {
			checkpoint("Tag Enum")
			if pick == 0 do e.LdtkJson_SetNull(ts.obj, "tagsSourceEnumUid", a)
			else do e.LdtkJson_SetInt(ts.obj, "tagsSourceEnumUid", e.LdtkJson_Int(enums[pick - 1], "uid"), a)
			e.Ldtk_Doc_Touch(doc)
		}
		UI_EndProps()
	}
	UI_SectionHeader("Tiles")
	ptr := level_texture_ptr(uid)
	if ptr == nil {
		UI_DimText("Image not found.")
		return
	}
	tex := ptr^
	avail := imgui.GetContentRegionAvail()
	z := clamp(min(avail.x / f32(max(tex.width, 1)), 320 / f32(max(tex.height, 1))), 0.25, 3)
	w, h := f32(tex.width) * z, f32(tex.height) * z
	{ // (drawn inline: a scrolling child here would take the page's wheel)
		p := imgui.GetCursorScreenPos()
		dl := imgui.GetWindowDrawList()
		imgui.InvisibleButton("##tiles", {w, h})
		Drive_ItemRect("defs.tiles", {p.x, p.y}, {p.x + 1, p.y + 1}, true)
		imgui.DrawList_AddImage(dl, transmute(imgui.TextureID)ptr, p, {p.x + w, p.y + h})
		step := f32(ts.gridSize + ts.spacing) * z
		pad := f32(ts.padding) * z
		gs := f32(ts.gridSize) * z
		for cd in e.LdtkJson_Arr(ts.obj, "customData") {
			tid := e.LdtkJson_Int(cd, "tileId")
			x, y := tid % max(ts.cWid, 1), tid / max(ts.cWid, 1)
			c := imgui.Vec2{p.x + pad + f32(x) * step + gs - 5, p.y + pad + f32(y) * step + 5}
			isAnim := i32(tid) in ts.anims
			imgui.DrawList_AddCircleFilled(dl, c, 3, col_u32(isAnim ? UI_SUCCESS : UI_WARNING))
		}
		if imgui.IsItemActivated() {
			m := imgui.GetIO().MousePos
			cx := int((m.x - p.x - pad) / step)
			cy := int((m.y - p.y - pad) / step)
			if cx >= 0 && cy >= 0 && cx < ts.cWid && cy < ts.cHei do defs.tileId = cx + cy * ts.cWid
		}
		x, y := defs.tileId % max(ts.cWid, 1), defs.tileId / max(ts.cWid, 1)
		imgui.DrawList_AddRect(dl, {p.x + pad + f32(x) * step, p.y + pad + f32(y) * step}, {p.x + pad + f32(x) * step + gs, p.y + pad + f32(y) * step + gs}, col_u32(UI_ACCENT), 0, {}, 2)
	}
	UI_DimText("Dots: tiles with custom data (green: animated).")
	tid := defs.tileId
	UI_SectionHeader(fmt.tprintf("Tile %d", tid))
	// custom data (live; one undo step per edit)
	cur := e.Ldtk_Doc_TileCustomData(doc, uid, tid)
	buf: [1024]u8
	copy(buf[:len(buf) - 1], cur)
	if imgui.InputTextMultiline("##tile_custom", cstring(raw_data(buf[:])), len(buf), {-1, 70}, {}) {
		e.Ldtk_Doc_CheckpointOnce(doc, -1, "Tile Data", rawptr(uintptr(uid * 100003 + tid + 1)))
		e.Ldtk_Doc_SetTileCustomData(doc, uid, tid, string(cstring(raw_data(buf[:]))))
	}
	if imgui.IsItemDeactivated() do e.Ldtk_Doc_EndCoalesce(doc)
	Drive_Item("defs.tile.custom")
	UI_Tooltip("Free text for your scripts (node:ldtk_get_tile(layer, x, y).custom_data); \"anim=\" / \"fps=\" lines animate the tile")
	// animation
	anim, animated := e.Ldtk_Doc_TileAnimation(doc, uid, tid)
	if animated {
		b := strings.builder_make(context.temp_allocator)
		for f, i in anim.frames {
			if i > 0 do strings.write_string(&b, ", ")
			fmt.sbprintf(&b, "%d", f)
		}
		UI_DimText(fmt.tprintf("Animated: %s at %v fps", strings.to_string(b), anim.fps))
	}
	if UI_Button(fmt.tprintf("%s  Animate with picked tiles", ICON_FA_PLAY), "defs.tile.animate") {
		if len(L.tileSel) >= 2 {
			checkpoint("Tile Animation")
			e.Ldtk_Doc_SetTileAnimation(doc, uid, tid, L.tileSel[:], animated ? anim.fps : e.LDTK_TILE_ANIM_DEFAULT_FPS)
		} else do Editor_Log(state, .Info, "Pick two or more tiles (the frames, in order) in the Layers panel's tileset first")
	}
	UI_Tooltip("The frames: tiles picked in the Layers panel's tileset, left to right, top to bottom")
	if animated {
		imgui.SameLine()
		imgui.SetNextItemWidth(80)
		fps := anim.fps
		if imgui.InputFloat("fps##tile_fps", &fps, 0, 0, "%.1f", {.EnterReturnsTrue}) && fps > 0 {
			checkpoint("Tile Animation")
			e.Ldtk_Doc_SetTileAnimation(doc, uid, tid, anim.frames, fps)
		}
		imgui.SameLine()
		if UI_Button("Stop", "defs.tile.animate.stop") {
			checkpoint("Tile Animation")
			e.Ldtk_Doc_SetTileAnimation(doc, uid, tid, nil, 0)
		}
	}
	// enum tags
	src := e.LdtkJson_Int(ts.obj, "tagsSourceEnumUid", -1)
	if en := e.Ldtk_Doc_EnumDef(doc, src); en != nil {
		UI_DimText("Tags:")
		for v in e.LdtkJson_Arr(en, "values") {
			id := e.LdtkJson_Str(v, "id")
			on := e.Ldtk_Doc_TileHasTag(doc, uid, tid, id)
			imgui.SameLine()
			if imgui.Checkbox(fmt.ctprintf("%s##tag", id), &on) {
				checkpoint("Tile Tag")
				e.Ldtk_Doc_SetTileTag(doc, uid, tid, id, on)
			}
			Drive_Item(fmt.tprintf("defs.tile.tag:%s", id))
		}
	}
}
