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
//   Enums        (level_defs_enums.odin) enums, values, external enums
//   Layers       (level_defs_layers.odin) every layer option, IntGrid values
//                and groups, copy / paste, bake (new layers: the Layers
//                panel's + button)
//   Rules        auto-layer rule groups and rules (pattern grid, tiles,
//                chance, flips, modulo, break on match), terrains
//   Project      (level_project.odin) file / save options, identifier
//                style, defaults, flags, level fields
//
// Every change is a project undo step (Ldtk_Doc_Checkpoint(doc, -1, ...)).
// ============================================================================

@(private = "file")
defs: struct {
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
	case .Enums: LevelEnums_Page(state)
	case .Layers: LevelLayers_Page(state)
	case .Rules: LevelRules_Page(state)
	case .Project: LevelProject_Page(state)
	}
}

// level_after_defs keeps the editor's indices valid after a defs change.
level_after_defs :: proc() {
	L := &GlobalLevel
	if L.doc == nil || len(L.doc.levels) == 0 do return
	level_follow_layer_uid()
	level_clear_selection()
	level_sync_palette()
}

// ----------------------------------------------------------------------------
// Rules page
// ----------------------------------------------------------------------------

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
LevelDefs_SelectedLayer :: proc() -> int {return defs.layerUid}
LevelDefs_SelectTileset :: proc(uid: int) {defs.tilesetUid = uid}
LevelDefs_SelectRulesLayer :: proc(uid: int) {LevelRules_SelectLayer(uid)}
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
world_ui: struct {
	renameReq: bool,
	renameIdx: int,
	renameBuf: [128]u8,
}

// world_props: worlds (multi-worlds), the world's layout, grid and new
// level size (true: the worlds changed - stop drawing this frame).
@(private = "file")
world_props :: proc(state: ^EditorState) -> bool {
	L := &GlobalLevel
	doc := L.doc
	w := doc.worlds[L.world].obj
	UI_PanelTitle(ICON_FA_GLOBE, e.Ldtk_Doc_WorldName(doc, L.world), doc.multiWorlds ? fmt.tprintf("%d worlds", len(doc.worlds)) : "")
	UI_HeaderButtons(1)
	if UI_HeaderButton(ICON_FA_CIRCLE_QUESTION, "defs.world.help", "") do LevelRef_Open("tab.world")
	level_tip("The World tab in the reference", "tab.world")
	if UI_BeginProps("##world_t") {
		defer UI_EndProps()
		UI_PropLabel("Multiple worlds")
		multi := doc.multiWorlds
		if imgui.Checkbox("##multi", &multi) {
			if !multi && len(doc.worlds) > 1 {
				Editor_Log(state, .Warn, "Delete the other worlds first")
			} else {
				defs_checkpoint("Multiple Worlds")
				e.Ldtk_Doc_SetMultiWorlds(doc, multi)
				return true
			}
		}
		Drive_Item("defs.world.multi")
		level_tip("Several worlds in one project (LDtk's MultiWorlds flag): the levels and world settings move to a worlds list", "worlds")
		if doc.multiWorlds {
			UI_PropLabel("Name")
			buf: [128]u8
			copy(buf[:127], e.LdtkJson_Str(w, "identifier"))
			if imgui.InputText("##wname", cstring(raw_data(buf[:])), len(buf), {.EnterReturnsTrue}) {
				defs_checkpoint("Rename World")
				e.Ldtk_Doc_RenameWorld(doc, L.world, string(cstring(raw_data(buf[:]))))
			}
			Drive_Item("defs.world.name")
			level_tip("The world's identifier (Enter applies)", "worlds")
		}
		UI_PropLabel("Layout")
		layout := e.Ldtk_Doc_WorldStr(doc, L.world, "worldLayout", "Free")
		cur := 0
		for n, i in e.LDTK_WORLD_LAYOUTS do if n == layout do cur = i
		if pick, changed := UI_Combo("defs.world.layout", cur, e.LDTK_WORLD_LAYOUTS[:]); changed {
			defs_checkpoint("World Layout")
			e.Ldtk_Doc_SetWorldLayout(doc, L.world, e.LDTK_WORLD_LAYOUTS[pick])
		}
		level_tip("Free: levels anywhere. GridVania: on a grid. Linear: in a row / column, in the level list's order.", "tab.world")
		if layout == "GridVania" {
			UI_PropLabel("World grid")
			g := [2]i32{i32(e.LdtkJson_Int(w, "worldGridWidth", 256)), i32(e.LdtkJson_Int(w, "worldGridHeight", 256))}
			if world_pair("defs.world.grid", &g) && g.x > 0 && g.y > 0 {
				defs_checkpoint("World Grid")
				e.Ldtk_Doc_SetWorldInt(doc, L.world, "worldGridWidth", int(g.x))
				e.Ldtk_Doc_SetWorldInt(doc, L.world, "worldGridHeight", int(g.y))
			}
			level_tip("The grid cell size levels snap to (width, height; Enter applies)", "tab.world")
		}
		UI_PropLabel("New level size")
		ls := [2]i32{i32(e.LdtkJson_Int(w, "defaultLevelWidth", 256)), i32(e.LdtkJson_Int(w, "defaultLevelHeight", 256))}
		if world_pair("defs.world.levelsize", &ls) && ls.x > 0 && ls.y > 0 {
			defs_checkpoint("New Level Size")
			e.Ldtk_Doc_SetWorldInt(doc, L.world, "defaultLevelWidth", int(ls.x))
			e.Ldtk_Doc_SetWorldInt(doc, L.world, "defaultLevelHeight", int(ls.y))
		}
		level_tip("The size of levels added to this world (pixels; Enter applies)", "tab.world")
		UI_PropLabel("Levels")
		UI_DimText(fmt.tprint(len(doc.worlds[L.world].levelsArr.items)))
	}
	if doc.multiWorlds {
		imgui.Spacing()
		UI_DimText("Worlds")
		for wd, i in doc.worlds {
			name := e.LdtkJson_Str(wd.obj, "identifier", "World")
			if imgui.Selectable(fmt.ctprintf("%s  %s (%d levels)##w%d", ICON_FA_GLOBE, name, len(wd.levelsArr.items), i), i == L.world, {}, {0, 22}) do world_open(i)
			Drive_Item(fmt.tprintf("defs.world:%s", name))
			level_tip(fmt.tprintf("%s: click to open it; right-click for more", name), "worlds")
			if imgui.BeginPopupContextItem(fmt.ctprintf("##wctx%d", i)) {
				defer imgui.EndPopup()
				if ctx_item(ICON_FA_FOLDER_OPEN, "Open", "Show this world's levels") do world_open(i)
				if ctx_item(ICON_FA_PEN_TO_SQUARE, "Rename...", "Change its identifier") {
					world_ui.renameReq = true
					world_ui.renameIdx = i
					world_ui.renameBuf = {}
					copy(world_ui.renameBuf[:127], name)
				}
				if ctx_item(ICON_FA_TRASH, "Delete", "Delete the world and its levels (undo brings it back; not the last world)", len(doc.worlds) > 1) {
					defs_checkpoint("Delete World")
					e.Ldtk_Doc_RemoveWorld(doc, i)
					L.world = clamp(L.world > i ? L.world - 1 : L.world, 0, len(doc.worlds) - 1)
					world_open(L.world)
					return true
				}
				imgui.Separator()
				if ctx_item(ICON_FA_CIRCLE_QUESTION, "Help", "Worlds in the reference") do LevelRef_Open("worlds")
			}
		}
	}
	if UI_Button(fmt.tprintf("%s  World", ICON_FA_PLUS), "defs.world.add") {
		defs_checkpoint("Add World")
		wi := e.Ldtk_Doc_AddWorld(doc)
		world_open(wi)
		return true
	}
	level_tip("Add a world with one level (turns multiple worlds on)", "worlds")
	world_rename_popup(state)
	UI_DimText("Move levels with the Move tool (M); resize them by")
	UI_DimText("dragging the handles around the active level.")
	return false
}

@(private = "file")
world_pair :: proc(id: string, v: ^[2]i32) -> bool {
	w := (imgui.GetContentRegionAvail().x - 4) * 0.5
	imgui.SetNextItemWidth(w)
	a := imgui.InputInt(fmt.ctprintf("##%s.x", id), &v.x, 0, 0, {.EnterReturnsTrue})
	Drive_Item(fmt.tprintf("%s.x", id))
	imgui.SameLine(0, 4)
	imgui.SetNextItemWidth(w)
	b := imgui.InputInt(fmt.ctprintf("##%s.y", id), &v.y, 0, 0, {.EnterReturnsTrue})
	Drive_Item(fmt.tprintf("%s.y", id))
	return a || b
}

// world_open: a world's first level becomes the active one.
@(private = "file")
world_open :: proc(wi: int) {
	L := &GlobalLevel
	for lv, i in L.doc.levels do if lv.world == wi {
		L.level = -1
		LevelEditor_SetLevel(i)
		L.fitRequest = true
		return
	}
	L.world = wi
}

@(private = "file")
world_rename_popup :: proc(state: ^EditorState) {
	doc := GlobalLevel.doc
	if world_ui.renameReq {
		imgui.OpenPopup("Rename World###LevelRenameWorld")
		world_ui.renameReq = false
	}
	center := imgui.GetMainViewport().WorkPos + imgui.GetMainViewport().WorkSize * 0.5
	imgui.SetNextWindowPos(center, .Appearing, {0.5, 0.5})
	if !imgui.BeginPopupModal("Rename World###LevelRenameWorld", nil, {.AlwaysAutoResize}) do return
	defer imgui.EndPopup()
	imgui.SetNextItemWidth(300)
	if imgui.IsWindowAppearing() do imgui.SetKeyboardFocusHere()
	enter := imgui.InputText("##wrename", cstring(raw_data(world_ui.renameBuf[:])), len(world_ui.renameBuf), {.EnterReturnsTrue})
	Drive_Item("defs.world.rename.name")
	if UI_PrimaryButton("Rename", "defs.world.rename.ok") || enter {
		defs_checkpoint("Rename World")
		e.Ldtk_Doc_RenameWorld(doc, world_ui.renameIdx, string(cstring(raw_data(world_ui.renameBuf[:]))))
		imgui.CloseCurrentPopup()
	}
	imgui.SameLine()
	if UI_Button("Cancel", "defs.world.rename.cancel") || imgui.IsKeyPressed(.Escape) do imgui.CloseCurrentPopup()
}

@(private = "file")
page_world :: proc(state: ^EditorState) {
	L := &GlobalLevel
	doc := L.doc
	a := doc.allocator
	if len(doc.worlds) == 0 do return
	w := doc.worlds[L.world].obj
	avail := imgui.GetContentRegionAvail()
	if imgui.BeginChild("##world_props", {340, avail.y}, {}, {}) {
		if world_props(state) {
			imgui.EndChild()
			return
		}
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

// ----------------------------------------------------------------------------
// Entities
// ----------------------------------------------------------------------------

PIVOTS := [9][2]f64{{0, 0}, {0.5, 0}, {1, 0}, {0, 0.5}, {0.5, 0.5}, {1, 0.5}, {0, 1}, {0.5, 1}, {1, 1}}

// level_pivot_picker: a 3x3 box of pivot points (drive ids <id>:0..8).
level_pivot_picker :: proc(id: string, cur: [2]f64, tip: string, topic: string) -> (pick: [2]f64, changed: bool) {
	CELL :: 18
	dl := imgui.GetWindowDrawList()
	start := imgui.GetCursorScreenPos()
	imgui.DrawList_AddRectFilled(dl, start, start + {3 * CELL + 4, 3 * CELL + 4}, col_u32(UI_BG_RAISED), 3, {})
	imgui.DrawList_AddRect(dl, start + 2 + CELL * 0.5, start + 2 + CELL * 2.5, col_u32(ui_line(0.25)), 0, {}, 1)
	for p, i in PIVOTS {
		at := start + {2 + f32(i % 3) * CELL, 2 + f32(i / 3) * CELL}
		imgui.SetCursorScreenPos(at)
		if imgui.InvisibleButton(fmt.ctprintf("##%s%d", id, i), {CELL, CELL}) do pick, changed = p, true
		Drive_Item(fmt.tprintf("%s:%d", id, i))
		level_tip(fmt.tprintf("%s (%.1f, %.1f)", tip, p.x, p.y), topic)
		on := abs(p.x - cur.x) < 0.01 && abs(p.y - cur.y) < 0.01
		c := at + CELL * 0.5
		if on do imgui.DrawList_AddCircleFilled(dl, c, 5, col_u32(UI_ACCENT), 0)
		else do imgui.DrawList_AddCircleFilled(dl, c, imgui.IsItemHovered() ? 4 : 3, col_u32(imgui.IsItemHovered() ? UI_TEXT : UI_TEXT_FAINT), 0)
	}
	imgui.SetCursorScreenPos(start)
	imgui.Dummy({3 * CELL + 4, 3 * CELL + 4})
	return
}

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
		filter := level_filter_box("tilesets", "Filter tilesets")
		imgui.Separator()
		for &ts in doc.tilesets {
			if !level_filter_hit(filter, ts.identifier) do continue
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
