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
	ruleUid:   int,
}

// text_edit: a text field bound to `key` of `obj`; returns the new text
// after Enter / leaving the field (ok = changed).
defs_text_edit :: proc(id: string, obj: ^e.LdtkJson, key: string) -> (string, bool) {
	// (ImGui edits its own copy while the field is active)
	cur := e.LdtkJson_Str(obj, key)
	buf: [256]u8
	copy(buf[:len(buf) - 1], cur)
	changed := imgui.InputText(fmt.ctprintf("##%s", id), cstring(raw_data(buf[:])), len(buf), {.EnterReturnsTrue}) || imgui.IsItemDeactivatedAfterEdit()
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
	case .Tilesets: LevelTilesets_Page(state)
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
LevelDefs_SelectTileset :: proc(uid: int) {LevelTilesets_Select(uid)}
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
		level_tip("IntGrid: painted values (collisions, terrain) that rules can turn into tiles. Entities: objects. Tiles: painted tiles. Auto layer: tiles from another layer's values.", "layer.new")
		UI_PropLabel("Identifier")
		imgui.InputText("##nl_name", cstring(raw_data(newLayer.name[:])), len(newLayer.name), {})
		Drive_Item("defs.newlayer.name")
		level_tip("Its name (letters, digits, _)", "layer.new")
		UI_PropLabel("Grid size")
		imgui.InputInt("##nl_grid", &newLayer.grid, 1, 8)
		level_tip("Cell size in pixels", "layer.new")
		newLayer.grid = max(newLayer.grid, 1)
		if newLayer.type != .Entities {
			UI_PropLabel("Tileset")
			tn := make([]string, len(doc.tilesets) + 1, context.temp_allocator)
			tn[0] = "(none)"
			for ts, i in doc.tilesets do tn[i + 1] = ts.identifier
			newLayer.tileset, _ = UI_Combo("defs.newlayer.tileset", clamp(newLayer.tileset, 0, len(tn) - 1), tn)
			level_tip("The tileset it paints from (Tiles) or its rules place (IntGrid, Auto)", "layer.new")
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
			level_tip("The IntGrid layer whose values its rules read", "layer.new")
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
	level_tip("Add the layer (on top) to every level", "layer.new")
	imgui.SameLine()
	if UI_Button("Cancel", "defs.newlayer.cancel") || imgui.IsKeyPressed(.Escape) do imgui.CloseCurrentPopup()
	level_tip("Close without adding a layer", "layer.new")
}

// ----------------------------------------------------------------------------
// World and Project pages
// ----------------------------------------------------------------------------

@(private = "file")
world_ui: struct {
	mapCtx:    int, // the map's level under the right click
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
			if imgui.InputText("##wname", cstring(raw_data(buf[:])), len(buf), {.EnterReturnsTrue}) || imgui.IsItemDeactivatedAfterEdit() {
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
	a := imgui.InputInt(fmt.ctprintf("##%s.x", id), &v.x, 0, 0) || imgui.IsItemDeactivatedAfterEdit()
	Drive_Item(fmt.tprintf("%s.x", id))
	imgui.SameLine(0, 4)
	imgui.SetNextItemWidth(w)
	b := imgui.InputInt(fmt.ctprintf("##%s.y", id), &v.y, 0, 0) || imgui.IsItemDeactivatedAfterEdit()
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
	enter := imgui.InputText("##wrename", cstring(raw_data(world_ui.renameBuf[:])), len(world_ui.renameBuf), {.EnterReturnsTrue}) || imgui.IsItemDeactivatedAfterEdit()
	Drive_Item("defs.world.rename.name")
	level_tip("The world's new identifier", "worlds")
	if UI_PrimaryButton("Rename", "defs.world.rename.ok") || enter {
		defs_checkpoint("Rename World")
		e.Ldtk_Doc_RenameWorld(doc, world_ui.renameIdx, string(cstring(raw_data(world_ui.renameBuf[:]))))
		imgui.CloseCurrentPopup()
	}
	imgui.SameLine()
	if UI_Button("Cancel", "defs.world.rename.cancel") || imgui.IsKeyPressed(.Escape) do imgui.CloseCurrentPopup()
	level_tip("Keep the name", "worlds")
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
				if over {
					imgui.SetTooltip("%s", fmt.ctprintf("%s (%dx%d): click to open it; right-click for more", name, s.x, s.y))
					LevelRef_Hover("tab.world")
					if imgui.IsMouseClicked(.Right) {
						world_ui.mapCtx = i
						imgui.OpenPopup("##mapctx")
					}
				}
			}
		}
		if imgui.BeginPopup("##mapctx") {
			li := world_ui.mapCtx
			if li >= 0 && li < len(doc.levels) {
				UI_DimText(e.Ldtk_Doc_LevelName(doc, li))
				if ctx_item(ICON_FA_FOLDER_OPEN, "Open", "Make it the active level") do LevelEditor_SetLevel(li)
				if ctx_item(ICON_FA_EXPAND, "Frame", "Open it and fit it in the canvas") {
					LevelEditor_SetLevel(li)
					L.fitRequest = true
				}
				if ctx_item(ICON_FA_CLONE, "Duplicate", "Copy the level with its content, next to it") {
					e.Ldtk_Doc_Checkpoint(doc, -1, "Duplicate Level")
					if ni := e.Ldtk_Doc_DuplicateLevel(doc, li); ni >= 0 {
						L.level = -1
						LevelEditor_SetLevel(ni)
					}
				}
				if ctx_item(ICON_FA_TRASH, "Delete", "Delete the level (undo brings it back; not a world's last level)", level_world_count(doc.levels[li].world) > 1) {
					e.Ldtk_Doc_Checkpoint(doc, -1, "Delete Level")
					e.Ldtk_Doc_RemoveLevel(doc, li)
					level_keep_world_level()
					level_clear_selection()
				}
				imgui.Separator()
				if ctx_item(ICON_FA_CIRCLE_QUESTION, "Help", "The World tab in the reference") do LevelRef_Open("tab.world")
			}
			imgui.EndPopup()
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
