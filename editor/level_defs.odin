package editor

import "core:fmt"
import "core:path/filepath"
import "core:strings"
import rl "vendor:raylib"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Level editor: the bottom panel's pages (LDtk's "Project" panels)
//
//   World        layout (Free / GridVania / linear), world grid, a map of
//                the levels (click to open one)
//   Level        (level_editor.odin) the level's / selected entity's values
//   Tilesets     from project images, grid / spacing / padding, per-tile
//                custom data, animations and enum tags
//   Entities     size, colour, pivot, resizing, tile, fields
//   Enums        values
//   Layers       grid, opacity, offset, tileset, auto-layer source, order,
//                IntGrid values (new layers: the Layers panel's + button)
//   Rules        auto-layer rule groups and rules (pattern grid, tiles,
//                chance, flips, modulo, break on match), terrains
//   Project      defaults, background, JSON options, level fields
//
// Every change is a project undo step (Ldtk_Doc_Checkpoint(doc, -1, ...)).
// ============================================================================

@(private = "file")
defs: struct {
	rulesLayerUid: int,
	layerUid:  int,
	entityUid: int,
	enumUid:   int,
	tilesetUid: int,
	ruleUid:   int,
	tileId:    int,
}

// text_edit: a text field bound to `key` of `obj`; returns the new text
// after Enter / leaving the field (ok = changed).
defs_text_edit :: proc(id: string, obj: ^e.LdtkJson, key: string) -> (string, bool) {
	// (ImGui edits its own copy while the field is active)
	cur := e.LdtkJson_Str(obj, key)
	buf: [256]u8
	copy(buf[:len(buf) - 1], cur)
	changed := imgui.InputText(fmt.ctprintf("##%s", id), cstring(raw_data(buf[:])), len(buf), {.EnterReturnsTrue})
	Drive_Item(id)
	text := strings.clone(string(cstring(raw_data(buf[:]))), context.temp_allocator)
	return text, changed && text != cur
}

defs_checkpoint :: proc(label: string) {
	e.Ldtk_Doc_Checkpoint(GlobalLevel.doc, -1, label)
}

// LevelDefs_Page draws a bottom-panel page (all but Level).
LevelDefs_Page :: proc(state: ^EditorState, page: Level_Panel_Tab) {
	if GlobalLevel.doc == nil do return
	#partial switch page {
	case .World: page_world(state)
	case .Tilesets: page_tilesets(state)
	case .Entities: LevelDefs_EntitiesPage(state)
	case .Enums: page_enums(state)
	case .Layers: page_layers(state)
	case .Rules: page_rules(state)
	case .Project: page_project(state)
	}
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
		if UI_Button(fmt.tprintf("%s  New layer...", ICON_FA_PLUS), "defs.layer.new") do LevelDefs_OpenNewLayer()
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
	level_clear_selection()
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
		defs_checkpoint("Move Layer")
		e.Ldtk_Doc_MoveLayerDef(doc, uid, -1)
		level_after_defs()
		return
	}
	if UI_HeaderButton(ICON_FA_ARROW_DOWN, "defs.layer.down", "Move down") {
		defs_checkpoint("Move Layer")
		e.Ldtk_Doc_MoveLayerDef(doc, uid, 1)
		level_after_defs()
		return
	}
	if UI_HeaderButton(ICON_FA_TRASH, "defs.layer.remove", "Delete the layer (and its content in every level)") {
		defs_checkpoint("Delete Layer")
		e.Ldtk_Doc_RemoveLayerDef(doc, uid)
		defs.layerUid = -1
		level_after_defs()
		return
	}
	if UI_BeginProps("##layer_props_t") {
		UI_PropLabel("Identifier")
		if name, ok := defs_text_edit("defs.layer.name", obj, "identifier"); ok {
			defs_checkpoint("Rename Layer")
			e.Ldtk_Doc_RenameLayerDef(doc, uid, name)
		}
		UI_PropLabel("Grid size")
		grid := i32(d.gridSize)
		if imgui.InputInt("##grid", &grid, 1, 8, {.EnterReturnsTrue}) && grid >= 1 {
			defs_checkpoint("Layer Grid")
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
			defs_checkpoint("Layer Offset")
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
				defs_checkpoint("Layer Tileset")
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
				defs_checkpoint("Auto Layer Source")
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
			if name, ok := defs_text_edit(fmt.tprintf("defs.value.name:%d", value), v, "identifier"); ok {
				defs_checkpoint("IntGrid Name")
				e.LdtkJson_SetStr(v, "identifier", name, doc.allocator)
				e.Ldtk_Doc_RefreshDefs(doc)
			}
			imgui.SameLine()
			if UI_IconButton(ICON_FA_TRASH, fmt.tprintf("defs.value.remove:%d", value), "Remove (clears its cells)", false, 22) {
				defs_checkpoint("Remove IntGrid Value")
				e.Ldtk_Doc_RemoveIntGridValue(doc, uid, value)
				imgui.PopID()
				break
			}
			imgui.PopID()
		}
		if UI_Button(fmt.tprintf("%s  Add value", ICON_FA_PLUS), "defs.value.add") {
			defs_checkpoint("Add IntGrid Value")
			e.Ldtk_Doc_AddIntGridValue(doc, uid)
			level_sync_palette()
		}
	}
	d = &doc.layerDefs[e.Ldtk_Doc_LayerDefIndex(doc, uid)]
	if d.type == .AutoLayer || d.type == .IntGrid {
		imgui.Dummy({0, 4})
		if UI_Button(fmt.tprintf("%s  Edit auto-layer rules (%d groups)", ICON_FA_WAND_MAGIC_SPARKLES, len(d.groups)), "defs.layer.rules") {
			defs.rulesLayerUid = uid
			LevelEditor_ShowTab(.Rules)
		}
	}
}

// ----------------------------------------------------------------------------
// Rules page
// ----------------------------------------------------------------------------

@(private = "file")
page_rules :: proc(state: ^EditorState) {
	L := &GlobalLevel
	doc := L.doc
	// the active layer's rules by default
	if e.Ldtk_Doc_LayerDefIndex(doc, defs.rulesLayerUid) < 0 {
		if _, d := level_active_layer(); d != nil && (d.type == .IntGrid || d.type == .AutoLayer) do defs.rulesLayerUid = d.uid
	}
	avail := imgui.GetContentRegionAvail()
	if imgui.BeginChild("##rules_layers", {200, avail.y}, {.Borders}, {}) {
		UI_DimText("Layers with rules:")
		for &d in doc.layerDefs {
			if d.type != .IntGrid && d.type != .AutoLayer do continue
			n := 0
			for g in d.groups do n += len(g.rules)
			if imgui.Selectable(fmt.ctprintf("%s  %s (%d)##rl%d", LAYER_TYPE_ICON[d.type], d.identifier, n, d.uid), defs.rulesLayerUid == d.uid, {}, {0, 22}) do defs.rulesLayerUid = d.uid
			Drive_Item(fmt.tprintf("defs.rules.layer:%s", d.identifier))
		}
	}
	imgui.EndChild()
	imgui.SameLine(0, 8)
	if imgui.BeginChild("##rules_page", {0, avail.y}, {}, {}) {
		di := e.Ldtk_Doc_LayerDefIndex(doc, defs.rulesLayerUid)
		if di < 0 {
			UI_DimText("Pick an IntGrid layer (with a tileset) or an Auto layer.")
		} else {
			d := &doc.layerDefs[di]
			UI_PanelTitle(LAYER_TYPE_ICON[d.type], d.identifier, "auto-layer rules")
			rules_editor(state, d.uid)
		}
	}
	imgui.EndChild()
}

// ----------------------------------------------------------------------------
// New layer dialog (the Layers panel's + button)
// ----------------------------------------------------------------------------

@(private = "file")
newLayer: struct {
	open:      bool,
	request:   bool,
	type:      e.LdtkLayerType,
	name:      [64]u8,
	grid:      i32,
	tileset:   int, // index + 1 in doc.tilesets, 0 = none
	source:    int, // auto layers: IntGrid def uid
}

// LevelDefs_SelectLayer / SelectRulesLayer / SelectEntity: what the Layers,
// Rules and Entities tabs show.
LevelDefs_SelectLayer :: proc(uid: int) {defs.layerUid = uid}
LevelDefs_SelectRulesLayer :: proc(uid: int) {defs.rulesLayerUid = uid}
LevelDefs_SelectEntity :: proc(uid: int) {defs.entityUid = uid}
LevelDefs_SelectedEntity :: proc() -> int {return defs.entityUid}

LevelDefs_OpenNewLayer :: proc() {
	newLayer.request = true
	newLayer.type = .IntGrid
	newLayer.name = {}
	copy(newLayer.name[:], "IntGrid")
	newLayer.grid = i32(e.LdtkJson_Int(GlobalLevel.doc.root, "defaultGridSize", 16))
	newLayer.tileset = 0
	newLayer.source = -1
}

LevelDefs_NewLayerDialog :: proc(state: ^EditorState) {
	L := &GlobalLevel
	doc := L.doc
	if doc == nil do return
	if newLayer.request {
		imgui.OpenPopup("New Layer###LevelNewLayer")
		newLayer.request = false
	}
	center := imgui.GetMainViewport().WorkPos + imgui.GetMainViewport().WorkSize * 0.5
	imgui.SetNextWindowPos(center, .Appearing, {0.5, 0.5})
	imgui.SetNextWindowSize({420, 0}, .Appearing)
	if !imgui.BeginPopupModal("New Layer###LevelNewLayer", nil, {.AlwaysAutoResize}) do return
	defer imgui.EndPopup()
	if UI_BeginProps("##newlayer") {
		defer UI_EndProps()
		UI_PropLabel("Type")
		names := []string{"IntGrid", "Entities", "Tiles", "AutoLayer"}
		if t, changed := UI_Combo("defs.newlayer.type", int(newLayer.type), names); changed {
			// the name follows the type while it is still a type name
			cur := string(cstring(raw_data(newLayer.name[:])))
			for n in names do if cur == n {
				newLayer.name = {}
				copy(newLayer.name[:len(newLayer.name) - 1], names[t])
			}
			newLayer.type = e.LdtkLayerType(t)
		}
		UI_PropLabel("Identifier")
		imgui.InputText("##nl_name", cstring(raw_data(newLayer.name[:])), len(newLayer.name), {})
		Drive_Item("defs.newlayer.name")
		UI_PropLabel("Grid size")
		imgui.InputInt("##nl_grid", &newLayer.grid, 1, 8)
		newLayer.grid = max(newLayer.grid, 1)
		if newLayer.type != .Entities {
			UI_PropLabel("Tileset")
			tn := make([]string, len(doc.tilesets) + 1, context.temp_allocator)
			tn[0] = "(none)"
			for ts, i in doc.tilesets do tn[i + 1] = ts.identifier
			newLayer.tileset, _ = UI_Combo("defs.newlayer.tileset", clamp(newLayer.tileset, 0, len(tn) - 1), tn)
		}
		if newLayer.type == .AutoLayer {
			UI_PropLabel("Rules read")
			sn := make([dynamic]string, context.temp_allocator)
			su := make([dynamic]int, context.temp_allocator)
			append(&sn, "(none)")
			append(&su, -1)
			cur := 0
			for &d in doc.layerDefs do if d.type == .IntGrid {
				if d.uid == newLayer.source do cur = len(sn)
				append(&sn, d.identifier)
				append(&su, d.uid)
			}
			if pick, changed := UI_Combo("defs.newlayer.source", cur, sn[:]); changed do newLayer.source = su[pick]
		}
	}
	if newLayer.type == .AutoLayer && (newLayer.tileset == 0 || newLayer.source < 0) do UI_DimText("Auto layers need a tileset and an IntGrid layer to read.")
	if newLayer.type == .Tiles && newLayer.tileset == 0 do UI_DimText("Tiles layers paint a tileset's tiles: pick one (or add one in Tilesets).")
	imgui.Dummy({0, 4})
	if UI_PrimaryButton("Create", "defs.newlayer.create") {
		defs_checkpoint("Add Layer")
		ts := newLayer.tileset > 0 && newLayer.tileset <= len(doc.tilesets) ? doc.tilesets[newLayer.tileset - 1].uid : -1
		uid := e.Ldtk_Doc_AddLayerDef(doc, newLayer.type, string(cstring(raw_data(newLayer.name[:]))), ts)
		d := &doc.layerDefs[e.Ldtk_Doc_LayerDefIndex(doc, uid)]
		changed := false
		if int(newLayer.grid) != d.gridSize {
			e.LdtkJson_SetInt(d.obj, "gridSize", int(newLayer.grid), doc.allocator)
			changed = true
		}
		if newLayer.type == .AutoLayer && newLayer.source >= 0 {
			e.LdtkJson_SetInt(d.obj, "autoSourceLayerDefUid", newLayer.source, doc.allocator)
			changed = true
		}
		if changed do e.Ldtk_Doc_LayerDefChanged(doc, uid)
		defs.layerUid = uid
		// the new layer becomes the active one
		for &ly, i in doc.levels[L.level].layers {
			if ld := e.Ldtk_Doc_LayerDef(doc, &ly); ld != nil && ld.uid == uid {
				L.layer = i
				L.layerUid = uid
			}
		}
		level_after_defs()
		imgui.CloseCurrentPopup()
	}
	imgui.SameLine()
	if UI_Button("Cancel", "defs.newlayer.cancel") || imgui.IsKeyPressed(.Escape) do imgui.CloseCurrentPopup()
}

// ----------------------------------------------------------------------------
// World and Project pages
// ----------------------------------------------------------------------------

@(private = "file")
page_world :: proc(state: ^EditorState) {
	L := &GlobalLevel
	doc := L.doc
	a := doc.allocator
	if len(doc.worlds) == 0 do return
	w := doc.worlds[L.world].obj
	avail := imgui.GetContentRegionAvail()
	if imgui.BeginChild("##world_props", {320, avail.y}, {}, {}) {
		UI_PanelTitle(ICON_FA_GLOBE, doc.multiWorlds ? e.LdtkJson_Str(w, "identifier", "World") : "World")
		if UI_BeginProps("##world_t") {
			defer UI_EndProps()
			UI_PropLabel("Layout")
			layout := e.LdtkJson_Str(w, "worldLayout", e.LdtkJson_Str(doc.root, "worldLayout", "Free"))
			cur := 0
			for n, i in e.LDTK_WORLD_LAYOUTS do if n == layout do cur = i
			if pick, changed := UI_Combo("defs.world.layout", cur, e.LDTK_WORLD_LAYOUTS[:]); changed {
				defs_checkpoint("World Layout")
				e.Ldtk_Doc_SetWorldLayout(doc, L.world, e.LDTK_WORLD_LAYOUTS[pick])
			}
			UI_Tooltip("Free: levels anywhere. GridVania: on a grid. Linear: in a row / column, in the level list's order.")
			if layout == "GridVania" {
				UI_PropLabel("World grid")
				g := [2]i32{i32(e.LdtkJson_Int(w, "worldGridWidth", 256)), i32(e.LdtkJson_Int(w, "worldGridHeight", 256))}
				if imgui.InputInt2("##wgrid", &g, {.EnterReturnsTrue}) && g.x > 0 && g.y > 0 {
					defs_checkpoint("World Grid")
					e.LdtkJson_SetInt(w, "worldGridWidth", int(g.x), a)
					e.LdtkJson_SetInt(w, "worldGridHeight", int(g.y), a)
					e.Ldtk_Doc_Touch(doc)
				}
			}
			UI_PropLabel("Levels")
			UI_DimText(fmt.tprint(len(doc.worlds[L.world].levelsArr.items)))
		}
		UI_DimText("Move levels with the Move tool (M) or in the Level tab.")
	}
	imgui.EndChild()
	imgui.SameLine(0, 8)
	// the map: every level of the world; click one to open it
	if imgui.BeginChild("##world_map", {0, avail.y}, {.Borders}, {}) {
		dl := imgui.GetWindowDrawList()
		mp := imgui.GetCursorScreenPos()
		ms := imgui.GetContentRegionAvail()
		mn := [2]f32{1e9, 1e9}
		mx := [2]f32{-1e9, -1e9}
		for &lv, i in doc.levels {
			if lv.world != L.world do continue
			p := e.Ldtk_Doc_LevelPos(doc, i)
			s := e.Ldtk_Doc_LevelSize(doc, i)
			mn = {min(mn.x, f32(p.x)), min(mn.y, f32(p.y))}
			mx = {max(mx.x, f32(p.x + s.x)), max(mx.y, f32(p.y + s.y))}
		}
		if mx.x > mn.x {
			sc := min((ms.x - 16) / (mx.x - mn.x), (ms.y - 16) / (mx.y - mn.y))
			imgui.InvisibleButton("##map", {max(ms.x, 1), max(ms.y, 1)})
			Drive_Item("defs.world.map")
			hovered := imgui.IsItemHovered()
			clicked := imgui.IsItemClicked()
			m := imgui.GetIO().MousePos
			for &lv, i in doc.levels {
				if lv.world != L.world do continue
				p := e.Ldtk_Doc_LevelPos(doc, i)
				s := e.Ldtk_Doc_LevelSize(doc, i)
				a0 := imgui.Vec2{mp.x + 8 + (f32(p.x) - mn.x) * sc, mp.y + 8 + (f32(p.y) - mn.y) * sc}
				a1 := imgui.Vec2{a0.x + f32(s.x) * sc, a0.y + f32(s.y) * sc}
				c := e.Ldtk_ParseHexColor(e.LdtkJson_Str(lv.obj, "__bgColor", "#696A79"))
				over := hovered && m.x >= a0.x && m.y >= a0.y && m.x < a1.x && m.y < a1.y
				imgui.DrawList_AddRectFilled(dl, a0, a1, col_u32({f32(c.r) / 255, f32(c.g) / 255, f32(c.b) / 255, over ? 1 : 0.8}), 2, {})
				imgui.DrawList_AddRect(dl, a0, a1, col_u32(i == L.level ? UI_ACCENT : ui_line(0.25)), 2, {}, i == L.level ? 2 : 1)
				name := e.LdtkJson_Str(lv.obj, "identifier")
				if a1.x - a0.x > 40 do imgui.DrawList_AddText(dl, {a0.x + 4, a0.y + 2}, col_u32(UI_TEXT), fmt.ctprintf("%s", name))
				if over && clicked {
					LevelEditor_SetLevel(i)
					L.fitRequest = true
				}
			}
		}
	}
	imgui.EndChild()
}

@(private = "file")
page_project :: proc(state: ^EditorState) {
	L := &GlobalLevel
	doc := L.doc
	a := doc.allocator
	root := doc.root
	avail := imgui.GetContentRegionAvail()
	if imgui.BeginChild("##project_props", {380, avail.y}, {}, {}) {
		UI_PanelTitle(ICON_FA_GEAR, "Project", L.rel)
		if UI_BeginProps("##project_t") {
			defer UI_EndProps()
			ints :: proc(label, id, kx, ky: string, root: ^e.LdtkJson) {
				doc := GlobalLevel.doc
				UI_PropLabel(label)
				v := [2]i32{i32(e.LdtkJson_Int(root, kx)), i32(e.LdtkJson_Int(root, ky))}
				if imgui.InputInt2(fmt.ctprintf("##%s", id), &v, {.EnterReturnsTrue}) && v.x > 0 && v.y > 0 {
					defs_checkpoint(label)
					e.LdtkJson_SetInt(root, kx, int(v.x), doc.allocator)
					e.LdtkJson_SetInt(root, ky, int(v.y), doc.allocator)
					e.Ldtk_Doc_Touch(doc)
				}
				Drive_Item(id)
			}
			UI_PropLabel("Default grid")
			g := i32(e.LdtkJson_Int(root, "defaultGridSize", 16))
			if imgui.InputInt("##pgrid", &g, 1, 8, {.EnterReturnsTrue}) && g > 0 {
				defs_checkpoint("Default Grid")
				e.LdtkJson_SetInt(root, "defaultGridSize", int(g), a)
				e.Ldtk_Doc_Touch(doc)
			}
			ints("New level size", "defs.project.levelsize", "defaultLevelWidth", "defaultLevelHeight", root)
			ints("New entity size", "defs.project.entitysize", "defaultEntityWidth", "defaultEntityHeight", root)
			colour :: proc(label, key: string, root: ^e.LdtkJson) {
				doc := GlobalLevel.doc
				UI_PropLabel(label)
				c := e.Ldtk_ParseHexColor(e.LdtkJson_Str(root, key, "#40465B"))
				col := [3]f32{f32(c.r) / 255, f32(c.g) / 255, f32(c.b) / 255}
				if imgui.ColorEdit3(fmt.ctprintf("##%s", key), &col, {.NoInputs}) {
					e.Ldtk_Doc_CheckpointOnce(doc, -1, label, rawptr(raw_data(key)))
					e.LdtkJson_SetStr(root, key, e.Ldtk_ColorHex({u8(col[0] * 255 + 0.5), u8(col[1] * 255 + 0.5), u8(col[2] * 255 + 0.5), 255}), doc.allocator)
					e.Ldtk_Doc_Touch(doc)
				}
			}
			colour("Background", "bgColor", root)
			colour("Level background", "defaultLevelBgColor", root)
			UI_PropLabel("Level names")
			if name, ok := defs_text_edit("defs.project.levelnames", root, "levelNamePattern"); ok {
				defs_checkpoint("Level Names")
				e.LdtkJson_SetStr(root, "levelNamePattern", name, a)
				e.Ldtk_Doc_Touch(doc)
			}
			UI_Tooltip("New levels' names: %idx = a free number, %world = the world's name")
			UI_PropLabel("Minify JSON")
			minify := e.LdtkJson_Bool(root, "minifyJson")
			if imgui.Checkbox("##minify", &minify) {
				defs_checkpoint("Minify JSON")
				e.LdtkJson_SetBool(root, "minifyJson", minify, a)
				doc.minify = minify
				for &lv in doc.levels do lv.dirty = true
				e.Ldtk_Doc_Touch(doc)
			}
			UI_PropLabel("Level files")
			UI_DimText(doc.external ? "one .ldtkl per level" : "in the .ldtk")
		}
	}
	imgui.EndChild()
	imgui.SameLine(0, 8)
	if imgui.BeginChild("##project_fields", {0, avail.y}, {}, {}) do LevelDefs_FieldsPanel(state, -1)
	imgui.EndChild()
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
			defs_checkpoint("Rule Group")
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
			defs_checkpoint("Rule Group")
			e.LdtkJson_SetBool(g.obj, "isOptional", optional, doc.allocator)
			e.Ldtk_Doc_RulesChanged(doc, layerUid)
			imgui.PopID()
			return
		}
		UI_Tooltip("Optional groups are enabled per level (Layers panel)")
		imgui.SameLine()
		if UI_Button(fmt.tprintf("%s Rule", ICON_FA_PLUS), fmt.tprintf("defs.rule.add:%s", g.name)) {
			defs_checkpoint("Add Rule")
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
			defs_checkpoint("Terrain Rules")
			e.Ldtk_Doc_AddTerrainRules(doc, layerUid, v, block)
			return // (definitions rebuilt many times: this frame's pointers are stale)
		} else do Editor_Log(state, .Info, "Pick a 3x3 block of tiles (corners, edges, centre) in the Layers panel's tileset first")
	}
	UI_Tooltip("Rules drawing a 3x3 terrain block over the picked IntGrid value: corners, edges and the centre")
	imgui.SameLine()
	if UI_Button(fmt.tprintf("%s  Add rule group", ICON_FA_PLUS), "defs.group.add") {
		defs_checkpoint("Add Rule Group")
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
				defs_checkpoint("Rule Pattern")
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
		defs_checkpoint("Rule Tiles")
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
		defs_checkpoint("Rule Chance")
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
		defs_checkpoint("Rule Modulo")
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
			defs_checkpoint("Rule Size")
			resize_rule(r, ns)
			e.Ldtk_Doc_RulesChanged(doc, layerUid)
			return true
		}
	}
	UI_Tooltip("Pattern size")
	imgui.SameLine()
	if UI_IconButton(ICON_FA_TRASH, fmt.tprintf("defs.rule.remove:%d", index), "Delete the rule", false, 22) {
		defs_checkpoint("Delete Rule")
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
	defs_checkpoint("Rule Option")
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

PIVOTS := [9][2]f64{{0, 0}, {0.5, 0}, {1, 0}, {0, 0.5}, {0.5, 0.5}, {1, 0.5}, {0, 1}, {0.5, 1}, {1, 1}}

// picked_tile_rect: the palette selection as a pixel rectangle.
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
			defs_checkpoint("Add Enum")
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
				if name, ok := defs_text_edit("defs.enum.name", en, "identifier"); ok {
					defs_checkpoint("Rename Enum")
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
					defs_checkpoint("Remove Enum Value")
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
				defs_checkpoint("Add Enum Value")
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
						defs_checkpoint("Tileset")
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
	defs_checkpoint("Add Tileset")
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
			defs_checkpoint("Tag Enum")
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
			defs_checkpoint("Tile Animation")
			e.Ldtk_Doc_SetTileAnimation(doc, uid, tid, L.tileSel[:], animated ? anim.fps : e.LDTK_TILE_ANIM_DEFAULT_FPS)
		} else do Editor_Log(state, .Info, "Pick two or more tiles (the frames, in order) in the Layers panel's tileset first")
	}
	UI_Tooltip("The frames: tiles picked in the Layers panel's tileset, left to right, top to bottom")
	if animated {
		imgui.SameLine()
		imgui.SetNextItemWidth(80)
		fps := anim.fps
		if imgui.InputFloat("fps##tile_fps", &fps, 0, 0, "%.1f", {.EnterReturnsTrue}) && fps > 0 {
			defs_checkpoint("Tile Animation")
			e.Ldtk_Doc_SetTileAnimation(doc, uid, tid, anim.frames, fps)
		}
		imgui.SameLine()
		if UI_Button("Stop", "defs.tile.animate.stop") {
			defs_checkpoint("Tile Animation")
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
				defs_checkpoint("Tile Tag")
				e.Ldtk_Doc_SetTileTag(doc, uid, tid, id, on)
			}
			Drive_Item(fmt.tprintf("defs.tile.tag:%s", id))
		}
	}
}
