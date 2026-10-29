package editor

import "core:fmt"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Level editor: the Layers tab (LDtk's EditLayerDefs)
//
//   layer list (copy / cut / paste / duplicate / reorder / delete) | form
//
// Form: identifier, doc, UI colour, grid (cells keep their coordinates),
// guide grid, opacity / inactive opacity, offset, parallax, list / inactive
// options, filter tags; per type: IntGrid values with groups, order and icons
// and the auto-layer tileset / biome field / killing Tiles layer; Auto
// layers' source; Entities layers' required / excluded tags and moving
// entities to another layer; Tiles layers' tileset and tile pivot. Baking an
// auto layer into a Tiles layer.
// ============================================================================

@(private = "file")
ll: struct {
	clip:        string,
	bakeReq:     bool,
	bakeUid:     int,
	moveReq:     bool,
	moveUid:     int,
	moveFilter:  int,
	moveTarget:  int,
	deleteReq:   bool,
	deleteUid:   int,
	iconsTs:     map[int]int, // layer uid -> the tileset its value icons come from
	groupReq:    bool,
	groupLayer:  int,
	groupUid:    int,
	groupBuf:    [64]u8,
	valueRmReq:  bool,
	valueRm:     [2]int, // layer uid, value
}

LevelLayers_Shutdown :: proc() {
	delete(ll.clip)
	delete(ll.iconsTs)
	ll = {}
}

LAYER_TOPIC :: "tab.layers"

LevelLayers_Page :: proc(state: ^EditorState) {
	L := &GlobalLevel
	doc := L.doc
	avail := imgui.GetContentRegionAvail()
	if imgui.BeginChild("##layer_list", {210, avail.y}, {.Borders}, {}) {
		if UI_Button(fmt.tprintf("%s  New layer...", ICON_FA_PLUS), "defs.layer.new") do LevelDefs_OpenNewLayer()
		level_tip("A new layer: type, name, grid, tileset", "layer.new")
		filter := level_filter_box("layerdefs", "Filter layers")
		imgui.Separator()
		for &d in doc.layerDefs {
			if !level_filter_hit(filter, d.identifier) do continue
			uid := d.uid
			p := imgui.GetCursorScreenPos()
			if hex := e.LdtkJson_Str(d.obj, "uiColor"); hex != "" {
				c := e.Ldtk_ParseHexColor(hex)
				imgui.DrawList_AddRectFilled(imgui.GetWindowDrawList(), {p.x, p.y + 3}, {p.x + 3, p.y + 19}, col_u32({f32(c.r) / 255, f32(c.g) / 255, f32(c.b) / 255, 1}), 1, {})
			}
			hidden := e.LdtkJson_Bool(d.obj, "hideInList")
			if hidden do imgui.PushStyleColorImVec4(.Text, UI_TEXT_DIM)
			if imgui.Selectable(fmt.ctprintf("  %s  %s%s##ld%d", LAYER_TYPE_ICON[d.type], d.identifier, hidden ? " (hidden)" : "", uid), LevelDefs_SelectedLayer() == uid, {}, {0, 22}) do LevelDefs_SelectLayer(uid)
			if hidden do imgui.PopStyleColor()
			Drive_Item(fmt.tprintf("defs.layer:%s", d.identifier))
			tip := fmt.tprintf("%s layer, grid %d px. Right-click for more.", LAYER_TYPE_NAME[d.type], d.gridSize)
			if docText := e.LdtkJson_Str(d.obj, "doc"); docText != "" do tip = fmt.tprintf("%s\n\n%s", docText, tip)
			level_tip(tip, LAYER_TOPIC)
			if layer_def_menu(state, uid) {
				imgui.EndChild()
				layer_dialogs(state)
				return
			}
		}
		// the empty area: paste
		imgui.Dummy({imgui.GetContentRegionAvail().x, max(imgui.GetContentRegionAvail().y, 20)})
		if imgui.BeginPopupContextItem("##ldlistctx") {
			if ctx_item(ICON_FA_PASTE, "Paste layer", "Paste the copied layer at the bottom", ll.clip != "") do paste_layer(state, -1)
			imgui.EndPopup()
		}
	}
	imgui.EndChild()
	imgui.SameLine(0, 8)
	if imgui.BeginChild("##layer_props", {0, avail.y}, {}, {}) {
		di := e.Ldtk_Doc_LayerDefIndex(doc, LevelDefs_SelectedLayer())
		if di < 0 do UI_DimText("Pick a layer, or add one with the button on the left.")
		else do layer_form(state, di)
	}
	imgui.EndChild()
	layer_dialogs(state)
}

@(private = "file")
paste_layer :: proc(state: ^EditorState, afterUid: int) {
	doc := GlobalLevel.doc
	defs_checkpoint("Paste Layer")
	if nu := e.Ldtk_Doc_PasteLayerDef(doc, ll.clip, afterUid); nu > 0 {
		LevelDefs_SelectLayer(nu)
		level_after_defs()
	} else do Editor_Log(state, .Warn, "The clipboard doesn't hold a layer")
}

// layer_def_menu: a layer's right-click menu (true: the layers changed).
@(private = "file")
layer_def_menu :: proc(state: ^EditorState, uid: int) -> bool {
	doc := GlobalLevel.doc
	if !imgui.BeginPopupContextItem(fmt.ctprintf("##ldctx%d", uid)) do return false
	defer imgui.EndPopup()
	di := e.Ldtk_Doc_LayerDefIndex(doc, uid)
	if di < 0 do return false
	d := &doc.layerDefs[di]
	if ctx_item(ICON_FA_COPY, "Copy", "Copy the layer definition") {
		delete(ll.clip)
		ll.clip = e.Ldtk_Doc_LayerDefText(doc, uid)
	}
	if ctx_item(ICON_FA_SCISSORS, "Cut", "Copy it, then delete it") {
		delete(ll.clip)
		ll.clip = e.Ldtk_Doc_LayerDefText(doc, uid)
		delete_layer(state, uid)
		return true
	}
	if ctx_item(ICON_FA_PASTE, "Paste after", "Paste the copied layer after this one", ll.clip != "") {
		paste_layer(state, uid)
		return true
	}
	if ctx_item(ICON_FA_CLONE, "Duplicate", "A copy of the definition (and its rules) after it; its levels' content starts empty") {
		defs_checkpoint("Duplicate Layer")
		if nu := e.Ldtk_Doc_DuplicateLayerDef(doc, uid); nu > 0 do LevelDefs_SelectLayer(nu)
		level_after_defs()
		return true
	}
	imgui.Separator()
	if ctx_item(ICON_FA_ARROW_UP, "Move up", "Drawn above the layer above it", di > 0) {
		defs_checkpoint("Move Layer")
		e.Ldtk_Doc_MoveLayerDef(doc, uid, -1)
		level_after_defs()
		return true
	}
	if ctx_item(ICON_FA_ARROW_DOWN, "Move down", "Drawn below the layer below it", di + 1 < len(doc.layerDefs)) {
		defs_checkpoint("Move Layer")
		e.Ldtk_Doc_MoveLayerDef(doc, uid, 1)
		level_after_defs()
		return true
	}
	if d.type == .IntGrid || d.type == .AutoLayer {
		imgui.Separator()
		if ctx_item(ICON_FA_WAND_MAGIC_SPARKLES, "Edit rules", "Its auto-layer rules (Rules tab)") {
			LevelRules_SelectLayer(uid)
			LevelEditor_ShowTab(.Rules)
		}
		if ctx_item(ICON_FA_LAYER_GROUP, "Bake...", "Flatten its auto tiles into a new Tiles layer", len(d.groups) > 0) {
			ll.bakeReq = true
			ll.bakeUid = uid
		}
	}
	if d.type == .Entities {
		imgui.Separator()
		if ctx_item(ICON_FA_RIGHT_LEFT, "Move entities...", "Move this layer's entities to another Entities layer, in every level") {
			ll.moveReq = true
			ll.moveUid = uid
		}
	}
	imgui.Separator()
	if ctx_item(ICON_FA_TRASH, "Delete", "Delete the layer and its content in every level (undo brings it back)") {
		delete_layer(state, uid)
		return true
	}
	imgui.Separator()
	if ctx_item(ICON_FA_CIRCLE_QUESTION, "Help", "Layers in the reference") do LevelRef_Open(LAYER_TOPIC)
	return false
}

@(private = "file")
delete_layer :: proc(state: ^EditorState, uid: int) {
	doc := GlobalLevel.doc
	if e.Ldtk_Doc_LayerIsSource(doc, uid) {
		ll.deleteReq = true
		ll.deleteUid = uid
		return
	}
	defs_checkpoint("Delete Layer")
	e.Ldtk_Doc_RemoveLayerDef(doc, uid)
	LevelDefs_SelectLayer(-1)
	level_after_defs()
}

// ----------------------------------------------------------------------------
// The form
// ----------------------------------------------------------------------------

@(private = "file")
layer_form :: proc(state: ^EditorState, di: int) {
	L := &GlobalLevel
	doc := L.doc
	a := doc.allocator
	d := &doc.layerDefs[di]
	uid := d.uid
	obj := d.obj
	UI_PanelTitle(LAYER_TYPE_ICON[d.type], d.identifier, fmt.tprintf("%s layer", LAYER_TYPE_NAME[d.type]))
	UI_HeaderButtons(3)
	if UI_HeaderButton(ICON_FA_CLONE, "defs.layer.duplicate", "") {
		defs_checkpoint("Duplicate Layer")
		if nu := e.Ldtk_Doc_DuplicateLayerDef(doc, uid); nu > 0 do LevelDefs_SelectLayer(nu)
		level_after_defs()
		return
	}
	level_tip("Duplicate the layer definition (and its rules)", LAYER_TOPIC)
	if UI_HeaderButton(ICON_FA_TRASH, "defs.layer.remove", "") {
		delete_layer(state, uid)
		return
	}
	level_tip("Delete the layer and its content in every level", LAYER_TOPIC)
	if UI_HeaderButton(ICON_FA_CIRCLE_QUESTION, "defs.layer.help", "") do LevelRef_Open(LAYER_TOPIC)
	level_tip("Layers in the reference", LAYER_TOPIC)
	if !UI_BeginProps("##layer_form_t") do return
	changed := false // something the instances cache (LayerDefChanged)
	{
		UI_PropLabel("Identifier")
		if name, ok := defs_text_edit("defs.layer.name", obj, "identifier"); ok && name != "" {
			defs_checkpoint("Rename Layer")
			e.Ldtk_Doc_RenameLayerDef(doc, uid, e.Ldtk_Doc_UniqueIdentifier(doc, "layers", name))
			UI_EndProps()
			return
		}
		level_tip("Letters, digits and _ (unique among layers; Enter applies)", LAYER_TOPIC)
		prop_text("Documentation", "defs.layer.doc", obj, "doc", "A note shown in the layer's tooltip (and exported)", LAYER_TOPIC)
		UI_PropLabel("UI colour")
		hex := e.LdtkJson_Str(obj, "uiColor")
		c := e.Ldtk_ParseHexColor(hex != "" ? hex : "#000000")
		col := [3]f32{f32(c.r) / 255, f32(c.g) / 255, f32(c.b) / 255}
		if imgui.ColorEdit3("##uicol", &col, {.NoInputs}) {
			e.Ldtk_Doc_CheckpointOnce(doc, -1, "Layer UI Colour", obj)
			e.LdtkJson_SetStr(obj, "uiColor", e.Ldtk_ColorHex({u8(col[0] * 255 + 0.5), u8(col[1] * 255 + 0.5), u8(col[2] * 255 + 0.5), 255}), a)
			e.Ldtk_Doc_Touch(doc)
		}
		if imgui.IsItemDeactivated() do e.Ldtk_Doc_EndCoalesce(doc)
		level_tip("A colour marking the layer in lists", LAYER_TOPIC)
		if hex != "" {
			imgui.SameLine()
			if UI_Button("None", "defs.layer.uicolor.none") {
				defs_checkpoint("Layer UI Colour")
				e.LdtkJson_SetNull(obj, "uiColor", a)
				e.Ldtk_Doc_Touch(doc)
			}
			level_tip("No colour", LAYER_TOPIC)
		}
		UI_PropLabel("Grid size")
		if d.type == .AutoLayer {
			UI_DimText(fmt.tprintf("%d px (follows the layer it reads)", d.gridSize))
		} else {
			grid := i32(d.gridSize)
			if (imgui.InputInt("##grid", &grid, 1, 8) || imgui.IsItemDeactivatedAfterEdit()) && grid >= 1 && int(grid) != d.gridSize {
				defs_checkpoint("Layer Grid")
				e.Ldtk_Doc_SetLayerGrid(doc, uid, int(grid))
				level_after_defs()
				UI_EndProps()
				return
			}
			Drive_Item("defs.layer.grid")
			level_tip("Cell size in pixels. Cells keep their coordinates; entities are scaled; Auto layers reading it follow.", LAYER_TOPIC)
		}
		UI_PropLabel("Guide grid")
		gg := [2]i32{i32(e.LdtkJson_Int(obj, "guideGridWid")), i32(e.LdtkJson_Int(obj, "guideGridHei"))}
		if layer_pair("defs.layer.guide", &gg) {
			defs_checkpoint("Guide Grid")
			e.LdtkJson_SetInt(obj, "guideGridWid", gg.x <= 1 ? 0 : int(gg.x), a)
			e.LdtkJson_SetInt(obj, "guideGridHei", gg.y <= 1 ? 0 : int(gg.y), a)
			e.Ldtk_Doc_Touch(doc)
		}
		level_tip("Extra grid lines every W / H pixels while the layer is active (0: none)", "layers.display")
		UI_PropLabel("Opacity")
		op := d.opacity
		if imgui.SliderFloat("##opacity", &op, 0.1, 1, "%.2f") {
			e.Ldtk_Doc_CheckpointOnce(doc, -1, "Layer Opacity", obj)
			e.LdtkJson_SetFloat(obj, "displayOpacity", f64(op), a)
			e.Ldtk_Doc_RefreshDefs(doc)
		}
		Drive_Item("defs.layer.opacity")
		level_tip("The layer's opacity", "layers.display")
		if imgui.IsItemDeactivatedAfterEdit() do changed = true
		if imgui.IsItemDeactivated() do e.Ldtk_Doc_EndCoalesce(doc)
		prop_slider("Inactive opacity", "defs.layer.inactive", obj, "inactiveOpacity", "Its opacity while another layer is active (0: hidden)", "layers.display")
		UI_PropLabel("Offset (px)")
		off := [2]i32{i32(d.pxOffset.x), i32(d.pxOffset.y)}
		if layer_pair("defs.layer.offset", &off) {
			defs_checkpoint("Layer Offset")
			e.LdtkJson_SetInt(obj, "pxOffsetX", int(off.x), a)
			e.LdtkJson_SetInt(obj, "pxOffsetY", int(off.y), a)
			changed = true
		}
		level_tip("Moves the whole layer by these pixels", LAYER_TOPIC)
		// parallax
		UI_PropLabel("Parallax X")
		px := f32(e.LdtkJson_Float(obj, "parallaxFactorX"))
		scaling := e.LdtkJson_Bool(obj, "parallaxScaling", true)
		if imgui.SliderFloat("##parx", &px, -1, 1, "%.2f") {
			e.Ldtk_Doc_CheckpointOnce(doc, -1, "Parallax", rawptr(uintptr(1)))
			same := e.LdtkJson_Float(obj, "parallaxFactorX") == e.LdtkJson_Float(obj, "parallaxFactorY")
			e.LdtkJson_SetFloat(obj, "parallaxFactorX", f64(px), a)
			if same || scaling do e.LdtkJson_SetFloat(obj, "parallaxFactorY", f64(px), a)
			e.Ldtk_Doc_Touch(doc)
		}
		if imgui.IsItemDeactivated() do e.Ldtk_Doc_EndCoalesce(doc)
		Drive_Item("defs.layer.parallax")
		level_tip("How much it lags behind the camera: 0 none, 0.5 half as fast (far away), negative: closer than the level", "layers.parallax")
		UI_PropLabel("Parallax Y")
		py := f32(e.LdtkJson_Float(obj, "parallaxFactorY"))
		imgui.BeginDisabled(scaling)
		if imgui.SliderFloat("##pary", &py, -1, 1, "%.2f") {
			e.Ldtk_Doc_CheckpointOnce(doc, -1, "Parallax", rawptr(uintptr(2)))
			e.LdtkJson_SetFloat(obj, "parallaxFactorY", f64(py), a)
			e.Ldtk_Doc_Touch(doc)
		}
		if imgui.IsItemDeactivated() do e.Ldtk_Doc_EndCoalesce(doc)
		imgui.EndDisabled()
		level_tip(scaling ? "Same as X while parallax scaling is on" : "The vertical factor", "layers.parallax")
		if prop_bool("Parallax scaling", "defs.layer.parallaxscaling", obj, "parallaxScaling", "Far layers (positive factor) are also drawn smaller, so they fit the level", "layers.parallax", true) {
			if e.LdtkJson_Bool(obj, "parallaxScaling", true) do e.LdtkJson_SetFloat(obj, "parallaxFactorY", e.LdtkJson_Float(obj, "parallaxFactorX"), a)
		}
		prop_bool("Hide in list", "defs.layer.hideinlist", obj, "hideInList", "Not shown in the Layers panel (still drawn; for layers you never edit by hand)", "layers.display")
		prop_bool("Hide fields when inactive", "defs.layer.hidefields", obj, "hideFieldsWhenInactive", "Entity field labels only show while this layer is active", "layers.display")
		prop_bool("Selectable when inactive", "defs.layer.selectinactive", obj, "canSelectWhenInactive", "Its content can be selected (Alt / Select tool) while another layer is active", "layers.display", true)
		prop_bool("Render in world view", "defs.layer.worldview", obj, "renderInWorldView", "LDtk draws it in its world view (kept for LDtk)", "layers.display", true)
		prop_bool("Async render", "defs.layer.async", obj, "useAsyncRender", "LDtk renders it in the background (kept for LDtk; big auto layers)", "layers.display")
		prop_tags("Filter tags", "defs.layer.uitags", obj, "uiFilterTags", "Comma-separated tags to group layers (LDtk's layer filter)", LAYER_TOPIC)
	}
	d = &doc.layerDefs[e.Ldtk_Doc_LayerDefIndex(doc, uid)]
	switch d.type {
	case .IntGrid, .AutoLayer:
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
			if pick, ch := UI_Combo("defs.layer.source", cur, names[:]); ch {
				defs_checkpoint("Auto Layer Source")
				if uids[pick] < 0 do e.LdtkJson_SetNull(obj, "autoSourceLayerDefUid", a)
				else {
					e.LdtkJson_SetInt(obj, "autoSourceLayerDefUid", uids[pick], a)
					src := &doc.layerDefs[e.Ldtk_Doc_LayerDefIndex(doc, uids[pick])]
					e.LdtkJson_SetInt(obj, "gridSize", src.gridSize, a)
				}
				changed = true
			}
			level_tip("The IntGrid layer whose values its rules read (its grid follows)", LAYER_TOPIC)
		}
		changed |= tileset_combo(d, d.type == .AutoLayer ? "The tileset its rules place tiles from (required)" : "The tileset its auto-layer rules place tiles from (optional)")
		UI_PropLabel("Biome field")
		{
			names := make([dynamic]string, context.temp_allocator)
			uids := make([dynamic]int, context.temp_allocator)
			append(&names, "No biome enum")
			append(&uids, -1)
			cur := 0
			for fd in e.LdtkJson_Arr(e.LdtkJson_Get(doc.root, "defs"), "levelFields") {
				if e.Ldtk_FieldKindOf(fd) != .Enum do continue
				fuid := e.LdtkJson_Int(fd, "uid")
				if fuid == d.biomeFieldUid do cur = len(names)
				en := e.Ldtk_Doc_EnumDef(doc, e.Ldtk_FieldEnumUid(fd))
				append(&names, fmt.tprintf("%s (%s)", e.LdtkJson_Str(fd, "identifier"), en != nil ? e.LdtkJson_Str(en, "identifier") : "?"))
				append(&uids, fuid)
			}
			if pick, ch := UI_Combo("defs.layer.biome", cur, names[:]); ch {
				defs_checkpoint("Biome Field")
				if uids[pick] < 0 do e.LdtkJson_SetNull(obj, "biomeFieldUid", a)
				else do e.LdtkJson_SetInt(obj, "biomeFieldUid", uids[pick], a)
				changed = true
			}
			level_tip("A level Enum field: rule groups can require some of its values (group menu > Biome)", "rules.groups")
		}
		UI_PropLabel("Tiles removed by")
		{
			names := make([dynamic]string, context.temp_allocator)
			uids := make([dynamic]int, context.temp_allocator)
			append(&names, "(none)")
			append(&uids, -1)
			cur := 0
			for &o in doc.layerDefs do if o.type == .Tiles {
				if o.uid == d.autoTilesKilledByUid do cur = len(names)
				append(&names, o.identifier)
				append(&uids, o.uid)
			}
			if pick, ch := UI_Combo("defs.layer.killedby", cur, names[:]); ch {
				defs_checkpoint("Auto Tiles Removed By")
				if uids[pick] < 0 do e.LdtkJson_SetNull(obj, "autoTilesKilledByOtherLayerUid", a)
				else do e.LdtkJson_SetInt(obj, "autoTilesKilledByOtherLayerUid", uids[pick], a)
				changed = true
			}
			level_tip("Where this Tiles layer has a tile, the auto tiles are left out (paint over generated tiles)", LAYER_TOPIC)
		}
	case .Entities:
		prop_tags("Required tags", "defs.layer.reqtags", obj, "requiredTags", "Only entities with one of these tags can go in it (comma-separated)", LAYER_TOPIC)
		prop_tags("Excluded tags", "defs.layer.excltags", obj, "excludedTags", "Entities with one of these tags can't go in it", LAYER_TOPIC)
		UI_PropLabel("")
		if UI_Button(fmt.tprintf("%s  Move entities...", ICON_FA_RIGHT_LEFT), "defs.layer.moveentities") {
			ll.moveReq = true
			ll.moveUid = uid
		}
		level_tip("Move this layer's entities (all, one kind, or a tag) to another Entities layer, in every level", LAYER_TOPIC)
	case .Tiles:
		changed |= tileset_combo(d, "The tileset painted from (its grid becomes the layer's)")
		d = &doc.layerDefs[e.Ldtk_Doc_LayerDefIndex(doc, uid)]
		if ts := e.Ldtk_Doc_Tileset(doc, d.tilesetUid); ts != nil && ts.gridSize != d.gridSize && (ts.gridSize < d.gridSize || ts.gridSize % d.gridSize != 0) {
			UI_PropLabel("")
			imgui.PushTextWrapPos(0)
			imgui.TextColored(UI_WARNING, "The tileset grid (%d px) and the layer grid (%d px) aren't multiples: picking groups of tiles can misbehave.", i32(ts.gridSize), i32(d.gridSize))
			imgui.PopTextWrapPos()
		}
		UI_PropLabel("Tile pivot")
		if p, ch := level_pivot_picker("defs.layer.tilepivot", d.tilePivot, "Where tiles bigger than the grid are anchored in their cell", LAYER_TOPIC); ch {
			defs_checkpoint("Tile Pivot")
			e.LdtkJson_SetFloat(obj, "tilePivotX", p.x, a)
			e.LdtkJson_SetFloat(obj, "tilePivotY", p.y, a)
			changed = true
		}
	}
	UI_EndProps()
	if changed {
		e.Ldtk_Doc_LayerDefChanged(doc, uid)
		level_after_defs()
		return
	}
	d = &doc.layerDefs[e.Ldtk_Doc_LayerDefIndex(doc, uid)]
	if d.type == .IntGrid && values_section(state, uid) do return
	d = &doc.layerDefs[e.Ldtk_Doc_LayerDefIndex(doc, uid)]
	if d.type == .AutoLayer || d.type == .IntGrid {
		imgui.Dummy({0, 4})
		if UI_Button(fmt.tprintf("%s  Edit rules (%d groups)", ICON_FA_WAND_MAGIC_SPARKLES, len(d.groups)), "defs.layer.rules") {
			LevelRules_SelectLayer(uid)
			LevelEditor_ShowTab(.Rules)
		}
		level_tip("Its auto-layer rules (Rules tab)", "tab.rules")
		if len(d.groups) > 0 {
			imgui.SameLine()
			if UI_Button(fmt.tprintf("%s  Bake...", ICON_FA_LAYER_GROUP), "defs.layer.bake") {
				ll.bakeReq = true
				ll.bakeUid = uid
			}
			level_tip("Flatten the generated tiles into a new Tiles layer", "layers.bake")
		}
	}
}

// tileset_combo: the layer's tileset (Tiles layers take its grid).
@(private = "file")
tileset_combo :: proc(d: ^e.Ldtk_DocLayerDef, tip: string) -> bool {
	doc := GlobalLevel.doc
	a := doc.allocator
	UI_PropLabel("Tileset")
	names := make([]string, len(doc.tilesets) + 1, context.temp_allocator)
	names[0] = "(none)"
	cur := 0
	for ts, i in doc.tilesets {
		names[i + 1] = fmt.tprintf("%s (%d px)", ts.identifier, ts.gridSize)
		if ts.uid == d.tilesetUid do cur = i + 1
	}
	pick, ch := UI_Combo("defs.layer.tileset", cur, names)
	level_tip(tip, LAYER_TOPIC)
	if !ch do return false
	uid, obj := d.uid, d.obj
	defs_checkpoint("Layer Tileset")
	if pick == 0 {
		e.LdtkJson_SetNull(obj, "tilesetDefUid", a)
	} else {
		ts := &doc.tilesets[pick - 1]
		e.LdtkJson_SetInt(obj, "tilesetDefUid", ts.uid, a)
		if d.type == .Tiles && ts.gridSize != d.gridSize do e.Ldtk_Doc_SetLayerGrid(doc, uid, ts.gridSize)
	}
	return true
}

@(private = "file")
layer_pair :: proc(id: string, v: ^[2]i32) -> bool {
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

// ----------------------------------------------------------------------------
// IntGrid values: groups, order, icons
// ----------------------------------------------------------------------------

@(private = "file")
value_used :: proc(doc: ^e.Ldtk_Doc, layerUid, value: int) -> bool {
	for &lv in doc.levels do for &ly in lv.layers {
		d := e.Ldtk_Doc_LayerDef(doc, &ly)
		if d == nil || d.uid != layerUid do continue
		for c in ly.intGrid do if int(c) == value do return true
	}
	return false
}

// values_section (true: the definitions changed - stop drawing).
@(private = "file")
values_section :: proc(state: ^EditorState, uid: int) -> bool {
	L := &GlobalLevel
	doc := L.doc
	a := doc.allocator
	if !UI_SectionHeader("IntGrid values") do return false
	d := &doc.layerDefs[e.Ldtk_Doc_LayerDefIndex(doc, uid)]
	vals := e.LdtkJson_Arr(d.obj, "intGridValues")
	groups := e.LdtkJson_Arr(d.obj, "intGridValuesGroups")
	// the icons' tileset
	if ll.iconsTs == nil do ll.iconsTs = make(map[int]int)
	if uid not_in ll.iconsTs {
		ll.iconsTs[uid] = d.tilesetUid
		for v in vals do if t := e.LdtkJson_Get(v, "tile"); t != nil && t.kind == .Object do ll.iconsTs[uid] = e.LdtkJson_Int(t, "tilesetUid", -1)
	}
	{
		imgui.TextUnformatted("Icons from")
		imgui.SameLine()
		names := make([]string, len(doc.tilesets) + 1, context.temp_allocator)
		names[0] = "No icons"
		cur := 0
		for ts, i in doc.tilesets {
			names[i + 1] = ts.identifier
			if ts.uid == ll.iconsTs[uid] do cur = i + 1
		}
		imgui.SetNextItemWidth(200)
		if pick, ch := UI_Combo("defs.value.iconts", cur, names); ch {
			ll.iconsTs[uid] = pick == 0 ? -1 : doc.tilesets[pick - 1].uid
			if pick == 0 {
				defs_checkpoint("Value Icons")
				for v in vals do e.Ldtk_Doc_SetIntGridValueTile(doc, uid, e.LdtkJson_Int(v, "value"), -1, {})
			}
		}
		level_tip("A tileset to pick an icon per value from (shown in the palette)", "layers.values")
	}
	group_list := make([dynamic]int, context.temp_allocator)
	append(&group_list, 0)
	for g in groups do append(&group_list, e.LdtkJson_Int(g, "uid"))
	for guid, gi in group_list {
		imgui.PushIDInt(i32(guid + 1000))
		defer imgui.PopID()
		if len(group_list) > 1 {
			// group header
			gname := "Ungrouped"
			gcol := imgui.Vec4{0, 0, 0, 0}
			if guid != 0 {
				g := groups[gi - 1]
				gname = e.LdtkJson_Str(g, "identifier", fmt.tprintf("Group %d", guid))
				if hex := e.LdtkJson_Str(g, "color"); hex != "" {
					c := e.Ldtk_ParseHexColor(hex)
					gcol = {f32(c.r) / 255, f32(c.g) / 255, f32(c.b) / 255, 1}
				}
			}
			imgui.Dummy({0, 2})
			p := imgui.GetCursorScreenPos()
			if gcol.w > 0 do imgui.DrawList_AddRectFilled(imgui.GetWindowDrawList(), {p.x, p.y + 2}, {p.x + 4, p.y + 18}, col_u32(gcol), 1, {})
			imgui.SetCursorScreenPos({p.x + 8, p.y})
			imgui.PushFont(GlobalFonts.semibold)
			imgui.Selectable(fmt.ctprintf("%s##grp", strings.to_upper(gname, context.temp_allocator)), false, {}, {260, 20})
			imgui.PopFont()
			Drive_Item(fmt.tprintf("defs.valuegroup:%s", gname))
			level_tip(guid == 0 ? "Values in no group" : fmt.tprintf("%s: right-click to rename, colour, reorder or delete it", gname), "layers.values")
			if guid != 0 && imgui.BeginPopupContextItem("##grpctx") {
				defer imgui.EndPopup()
				if ctx_item(ICON_FA_WAND_MAGIC_SPARKLES, "Create rules for group...", "Open Rules tab to create auto-layer rules for this group") {
					LevelRules_SelectLayer(uid)
					e.Ldtk_Doc_SyncRuleGroupsFromIntGrid(doc, uid)
					LevelEditor_ShowTab(.Rules)
					return true
				}
				if ctx_item(ICON_FA_PEN_TO_SQUARE, "Rename...", "Change the group's name") {
					ll.groupReq = true
					ll.groupLayer, ll.groupUid = uid, guid
					ll.groupBuf = {}
					copy(ll.groupBuf[:63], e.LdtkJson_Str(groups[gi - 1], "identifier"))
				}
				if imgui.BeginMenu(fmt.ctprintf("%s  Colour", ICON_FA_CIRCLE)) {
					for hex in e.LDTK_PALETTE {
						c := e.Ldtk_ParseHexColor(hex)
						imgui.PushStyleColorImVec4(.Text, {f32(c.r) / 255, f32(c.g) / 255, f32(c.b) / 255, 1})
						if imgui.MenuItem(fmt.ctprintf("%s  %s", ICON_FA_CIRCLE, hex)) {
							defs_checkpoint("Group Colour")
							e.Ldtk_Doc_SetIntGridGroup(doc, uid, guid, e.LdtkJson_Str(groups[gi - 1], "identifier"), hex)
						}
						imgui.PopStyleColor()
					}
					if imgui.MenuItem("None") {
						defs_checkpoint("Group Colour")
						e.Ldtk_Doc_SetIntGridGroup(doc, uid, guid, e.LdtkJson_Str(groups[gi - 1], "identifier"), "")
					}
					imgui.EndMenu()
				}
				Drive_Item("ctx:Colour")
				if ctx_item(ICON_FA_ARROW_UP, "Move up", "Earlier in the list", gi > 1) {
					defs_checkpoint("Move Group")
					e.Ldtk_Doc_MoveIntGridGroup(doc, uid, guid, -1)
					return true
				}
				if ctx_item(ICON_FA_ARROW_DOWN, "Move down", "Later in the list", gi < len(group_list) - 1) {
					defs_checkpoint("Move Group")
					e.Ldtk_Doc_MoveIntGridGroup(doc, uid, guid, 1)
					return true
				}
				if ctx_item(ICON_FA_TRASH, "Delete group", "Its values go back to Ungrouped") {
					defs_checkpoint("Delete Group")
					e.Ldtk_Doc_RemoveIntGridGroup(doc, uid, guid)
					return true
				}
			}
		}
		for v, vi in vals {
			if e.LdtkJson_Int(v, "groupUid") != guid do continue
			if value_row(state, uid, v, vi, len(vals), group_list[:], groups) do return true
		}
		if len(group_list) > 1 {
			imgui.Indent(8)
			if UI_Button(fmt.tprintf("%s  Value##g%d", ICON_FA_PLUS, guid), fmt.tprintf("defs.value.add:%d", guid)) {
				defs_checkpoint("Add IntGrid Value")
				nv := e.Ldtk_Doc_AddIntGridValue(doc, uid)
				e.Ldtk_Doc_SetIntGridValueGroup(doc, uid, nv, guid)
				level_sync_palette()
				imgui.Unindent(8)
				return true
			}
			level_tip("A new value in this group", "layers.values")
			imgui.Unindent(8)
		}
	}
	imgui.Dummy({0, 2})
	if UI_Button(fmt.tprintf("%s  Add value", ICON_FA_PLUS), "defs.value.add") {
		defs_checkpoint("Add IntGrid Value")
		e.Ldtk_Doc_AddIntGridValue(doc, uid)
		level_sync_palette()
		return true
	}
	level_tip("The next value (1, 2, 3...)", "layers.values")
	imgui.SameLine()
	if UI_Button(fmt.tprintf("%s  Add group", ICON_FA_LAYER_GROUP), "defs.valuegroup.add") {
		defs_checkpoint("Add IntGrid Group")
		e.Ldtk_Doc_AddIntGridGroup(doc, uid)
		return true
	}
	level_tip("A group to sort values in (rules can match a whole group in LDtk)", "layers.values")
	_ = a
	return false
}

@(private = "file")
value_row :: proc(state: ^EditorState, uid: int, v: ^e.LdtkJson, vi, count: int, group_list: []int, groups: []^e.LdtkJson) -> bool {
	L := &GlobalLevel
	doc := L.doc
	a := doc.allocator
	value := e.LdtkJson_Int(v, "value")
	imgui.PushIDInt(i32(value))
	defer imgui.PopID()
	c := e.Ldtk_ParseHexColor(e.LdtkJson_Str(v, "color", "#000000"))
	col := [3]f32{f32(c.r) / 255, f32(c.g) / 255, f32(c.b) / 255}
	if imgui.ColorEdit3("##c", &col, {.NoInputs}) {
		e.Ldtk_Doc_CheckpointOnce(doc, -1, "IntGrid Colour", v)
		e.LdtkJson_SetStr(v, "color", e.Ldtk_ColorHex({u8(col[0] * 255 + 0.5), u8(col[1] * 255 + 0.5), u8(col[2] * 255 + 0.5), 255}), a)
		e.Ldtk_Doc_RefreshDefs(doc)
	}
	if imgui.IsItemDeactivated() do e.Ldtk_Doc_EndCoalesce(doc)
	level_tip("The value's colour", "layers.values")
	imgui.SameLine()
	imgui.AlignTextToFramePadding()
	imgui.TextUnformatted(fmt.ctprintf("%d", value))
	imgui.SameLine()
	imgui.SetNextItemWidth(160)
	if name, ok := defs_text_edit(fmt.tprintf("defs.value.name:%d", value), v, "identifier"); ok {
		defs_checkpoint("IntGrid Name")
		clean := e.Ldtk_CleanIdentifier(name, keepCase = true)
		if strings.trim_space(name) == "" do e.LdtkJson_SetNull(v, "identifier", a)
		else do e.LdtkJson_SetStr(v, "identifier", clean, a)
		e.Ldtk_Doc_RefreshDefs(doc)
	}
	level_tip("Its identifier (rules and games can refer to it by name)", "layers.values")
	// icon
	its := ll.iconsTs[uid]
	if its >= 0 {
		imgui.SameLine()
		tile := e.LdtkJson_Get(v, "tile")
		ts := e.Ldtk_Doc_Tileset(doc, its)
		drawn := false
		if tile != nil && tile.kind == .Object && ts != nil {
			if ptr := level_texture_ptr(ts.uid); ptr != nil {
				tw, th := f32(ptr.width), f32(ptr.height)
				x, y, w, h := f32(e.LdtkJson_Int(tile, "x")), f32(e.LdtkJson_Int(tile, "y")), f32(e.LdtkJson_Int(tile, "w")), f32(e.LdtkJson_Int(tile, "h"))
				if imgui.ImageButton("##icon", transmute(imgui.TextureID)ptr, {20, 20}, {x / tw, y / th}, {(x + w) / tw, (y + h) / th}) do imgui.OpenPopup("##iconpick")
				drawn = true
			}
		}
		if !drawn && UI_IconButton(ICON_FA_IMAGE, fmt.tprintf("defs.value.icon:%d", value), "", false, 26) do imgui.OpenPopup("##iconpick")
		level_tip("Its icon: click to pick a tile", "layers.values")
		if tid, ok := tile_pick_popup("##iconpick", its); ok && ts != nil {
			src := e.Ldtk_Doc_TileSrc(ts, tid)
			defs_checkpoint("Value Icon")
			e.Ldtk_Doc_SetIntGridValueTile(doc, uid, value, its, {int(src.x), int(src.y), ts.gridSize, ts.gridSize})
		}
	}
	imgui.SameLine()
	if UI_IconButton(ICON_FA_TRASH, fmt.tprintf("defs.value.remove:%d", value), "", false, 24) {
		remove_value(state, uid, value)
		return true
	}
	level_tip("Remove the value (its cells are cleared; asks first when it is used)", "layers.values")
	// the row's menu (on the remove button and the name)
	if imgui.BeginPopupContextItem("##valrowctx") {
		defer imgui.EndPopup()
		if ctx_item(ICON_FA_ARROW_UP, "Move up", "Earlier in the list", vi > 0) {
			defs_checkpoint("Move IntGrid Value")
			e.Ldtk_Doc_MoveIntGridValue(doc, uid, value, -1)
			return true
		}
		if ctx_item(ICON_FA_ARROW_DOWN, "Move down", "Later in the list", vi + 1 < count) {
			defs_checkpoint("Move IntGrid Value")
			e.Ldtk_Doc_MoveIntGridValue(doc, uid, value, 1)
			return true
		}
		if len(group_list) > 1 && imgui.BeginMenu(fmt.ctprintf("%s  Move to group", ICON_FA_LAYER_GROUP)) {
			for g, k in group_list {
				gname := g == 0 ? "Ungrouped" : e.LdtkJson_Str(groups[k - 1], "identifier", fmt.tprintf("Group %d", g))
				if imgui.MenuItem(fmt.ctprintf("%s", gname), nil, e.LdtkJson_Int(v, "groupUid") == g) {
					defs_checkpoint("IntGrid Value Group")
					e.Ldtk_Doc_SetIntGridValueGroup(doc, uid, value, g)
				}
			}
			imgui.EndMenu()
		}
		if ll.iconsTs[uid] >= 0 && ctx_item(ICON_FA_ERASER, "Clear icon", "No icon", e.LdtkJson_Get(v, "tile") != nil && e.LdtkJson_Get(v, "tile").kind == .Object) {
			defs_checkpoint("Value Icon")
			e.Ldtk_Doc_SetIntGridValueTile(doc, uid, value, -1, {})
		}
		imgui.Separator()
		if ctx_item(ICON_FA_TRASH, "Remove", "Remove the value and clear its cells") {
			remove_value(state, uid, value)
			return true
		}
		imgui.Separator()
		if ctx_item(ICON_FA_CIRCLE_QUESTION, "Help", "IntGrid values in the reference") do LevelRef_Open("layers.values")
	}
	return false
}

@(private = "file")
remove_value :: proc(state: ^EditorState, uid, value: int) {
	doc := GlobalLevel.doc
	if value_used(doc, uid, value) {
		ll.valueRmReq = true
		ll.valueRm = {uid, value}
		return
	}
	defs_checkpoint("Remove IntGrid Value")
	e.Ldtk_Doc_RemoveIntGridValue(doc, uid, value)
	level_sync_palette()
}

@(private = "file")
danger_button :: proc(label, id: string) -> bool {
	imgui.PushStyleColorImVec4(.Button, UI_DANGER)
	imgui.PushStyleColorImVec4(.Text, {1, 1, 1, 1})
	pressed := imgui.Button(fmt.ctprintf("%s##%s", label, id))
	imgui.PopStyleColor(2)
	Drive_Item(id)
	return pressed
}

// tile_pick_popup: a popup showing a tileset; returns the clicked tile.
tile_pick_popup :: proc(id: cstring, tilesetUid: int) -> (tid: int, ok: bool) {
	doc := GlobalLevel.doc
	if !imgui.BeginPopup(id) do return
	defer imgui.EndPopup()
	ts := e.Ldtk_Doc_Tileset(doc, tilesetUid)
	ptr := ts != nil ? level_texture_ptr(ts.uid) : nil
	if ptr == nil {
		UI_DimText("The tileset's image isn't loaded.")
		return
	}
	scale := max(min(f32(320) / f32(ptr.width), f32(320) / f32(ptr.height)), 1)
	size := [2]f32{f32(ptr.width) * scale, f32(ptr.height) * scale}
	p := imgui.GetCursorScreenPos()
	imgui.Image(transmute(imgui.TextureID)ptr, size)
	Drive_ItemRect("tilepick.grid", p, p + 1, true)
	g := f32(ts.gridSize) * scale
	m := imgui.GetIO().MousePos
	if imgui.IsItemHovered() {
		cx, cy := int((m.x - p.x) / g), int((m.y - p.y) / g)
		dl := imgui.GetWindowDrawList()
		imgui.DrawList_AddRect(dl, {p.x + f32(cx) * g, p.y + f32(cy) * g}, {p.x + f32(cx + 1) * g, p.y + f32(cy + 1) * g}, col_u32(UI_ACCENT), 0, {}, 2)
		if imgui.IsItemClicked() && cx >= 0 && cy >= 0 && cx < ts.cWid && cy < ts.cHei {
			imgui.CloseCurrentPopup()
			return cx + cy * ts.cWid, true
		}
	}
	return
}

// ----------------------------------------------------------------------------
// Dialogs: bake, move entities, delete a source layer, remove a used value,
// rename a value group
// ----------------------------------------------------------------------------

@(private = "file")
layer_dialogs :: proc(state: ^EditorState) {
	L := &GlobalLevel
	doc := L.doc
	center := imgui.GetMainViewport().WorkPos + imgui.GetMainViewport().WorkSize * 0.5
	if ll.bakeReq {
		ll.bakeReq = false
		if e.Ldtk_Doc_LayerIsSource(doc, ll.bakeUid) do Editor_Log(state, .Warn, "This layer can't be baked: an Auto layer reads it")
		else if di := e.Ldtk_Doc_LayerDefIndex(doc, ll.bakeUid); di >= 0 && doc.layerDefs[di].tilesetUid < 0 do Editor_Log(state, .Warn, "This layer has no tileset: nothing to bake")
		else do imgui.OpenPopup("Bake Layer###LevelBake")
	}
	imgui.SetNextWindowPos(center, .Appearing, {0.5, 0.5})
	if imgui.BeginPopupModal("Bake Layer###LevelBake", nil, {.AlwaysAutoResize}) {
		di := e.Ldtk_Doc_LayerDefIndex(doc, ll.bakeUid)
		isInt := di >= 0 && doc.layerDefs[di].type == .IntGrid
		UI_DimText("Baking flattens the auto layer into a new Tiles layer holding")
		UI_DimText("every tile its rules generated. What happens to the original?")
		bake :: proc(state: ^EditorState, m: e.Ldtk_BakeMethod) {
			defs_checkpoint("Bake Layer")
			nu := e.Ldtk_Doc_BakeLayer(GlobalLevel.doc, ll.bakeUid, m)
			if nu > 0 {
				LevelDefs_SelectLayer(nu)
				Editor_Log(state, .Info, "Baked into %s", e.Ldtk_Doc_LayerDefIndex(GlobalLevel.doc, nu) >= 0 ? GlobalLevel.doc.layerDefs[e.Ldtk_Doc_LayerDefIndex(GlobalLevel.doc, nu)].identifier : "?")
			}
			level_after_defs()
			imgui.CloseCurrentPopup()
		}
		if UI_PrimaryButton("Bake, then delete the original", "bake.delete") do bake(state, .Delete_Original)
		if isInt && UI_Button("Bake, then empty the original", "bake.empty") do bake(state, .Empty_Original)
		if UI_Button("Keep both", "bake.keep") do bake(state, .Keep_Both)
		if UI_Button("Cancel", "bake.cancel") || imgui.IsKeyPressed(.Escape) do imgui.CloseCurrentPopup()
		level_tip("Close without changing anything", "tab.layers")
		imgui.EndPopup()
	}
	if ll.moveReq {
		ll.moveReq = false
		ll.moveFilter, ll.moveTarget = 0, 0
		imgui.OpenPopup("Move Entities###LevelMoveEntities")
	}
	imgui.SetNextWindowPos(center, .Appearing, {0.5, 0.5})
	if imgui.BeginPopupModal("Move Entities###LevelMoveEntities", nil, {.AlwaysAutoResize}) {
		filters := make([dynamic]string, context.temp_allocator)
		kinds := make([dynamic]e.Ldtk_EntityFilter, context.temp_allocator)
		names := make([dynamic]string, context.temp_allocator)
		append(&filters, "All entities")
		append(&kinds, e.Ldtk_EntityFilter.All)
		append(&names, "")
		for &ed in doc.entityDefs {
			append(&filters, fmt.tprintf("%s entities", ed.identifier))
			append(&kinds, e.Ldtk_EntityFilter.Def)
			append(&names, ed.identifier)
		}
		seen := make(map[string]bool, allocator = context.temp_allocator)
		for &ed in doc.entityDefs do for t in e.LdtkJson_Arr(ed.obj, "tags") {
			if t.kind != .String || seen[t.text] do continue
			seen[t.text] = true
			append(&filters, fmt.tprintf("entities tagged \"%s\"", t.text))
			append(&kinds, e.Ldtk_EntityFilter.Tag)
			append(&names, t.text)
		}
		targets := make([dynamic]string, context.temp_allocator)
		tuids := make([dynamic]int, context.temp_allocator)
		for &d in doc.layerDefs do if d.type == .Entities && d.uid != ll.moveUid {
			append(&targets, d.identifier)
			append(&tuids, d.uid)
		}
		UI_DimText("Move, in every level:")
		imgui.SetNextItemWidth(300)
		if pick, ch := UI_Combo("move.filter", ll.moveFilter, filters[:]); ch do ll.moveFilter = pick
		level_tip("Which entities move: all, one kind, or those with a tag", "tab.layers")
		UI_DimText("to the layer:")
		if len(targets) == 0 {
			UI_DimText("(no other Entities layer)")
		} else {
			imgui.SetNextItemWidth(300)
			if pick, ch := UI_Combo("move.target", ll.moveTarget, targets[:]); ch do ll.moveTarget = pick
			level_tip("The Entities layer they go to (its tags must accept them)", "tab.layers")
		}
		if UI_PrimaryButton("Move", "move.ok") && len(targets) > 0 {
			defs_checkpoint("Move Entities Between Layers")
			n := e.Ldtk_Doc_MoveEntitiesBetweenLayers(doc, ll.moveUid, tuids[clamp(ll.moveTarget, 0, len(tuids) - 1)], kinds[ll.moveFilter], names[ll.moveFilter])
			if n < 0 do Editor_Log(state, .Warn, "That layer's required / excluded tags don't accept these entities")
			else do Editor_Log(state, .Info, "Moved %d entit%s", n, n == 1 ? "y" : "ies")
			level_clear_selection()
			imgui.CloseCurrentPopup()
		}
		imgui.SameLine()
		if UI_Button("Cancel", "move.cancel") || imgui.IsKeyPressed(.Escape) do imgui.CloseCurrentPopup()
		level_tip("Close without changing anything", "tab.layers")
		imgui.EndPopup()
	}
	if ll.deleteReq {
		ll.deleteReq = false
		imgui.OpenPopup("Delete Layer###LevelDeleteSource")
	}
	imgui.SetNextWindowPos(center, .Appearing, {0.5, 0.5})
	if imgui.BeginPopupModal("Delete Layer###LevelDeleteSource", nil, {.AlwaysAutoResize}) {
		UI_DimText("An Auto layer reads this IntGrid layer: deleting it leaves")
		UI_DimText("that layer's rules without values. Delete it anyway?")
		if danger_button("Delete", "deletelayer.ok") {
			defs_checkpoint("Delete Layer")
			e.Ldtk_Doc_RemoveLayerDef(doc, ll.deleteUid)
			LevelDefs_SelectLayer(-1)
			level_after_defs()
			imgui.CloseCurrentPopup()
		}
		imgui.SameLine()
		if UI_Button("Cancel", "deletelayer.cancel") || imgui.IsKeyPressed(.Escape) do imgui.CloseCurrentPopup()
		level_tip("Close without changing anything", "tab.layers")
		imgui.EndPopup()
	}
	if ll.valueRmReq {
		ll.valueRmReq = false
		imgui.OpenPopup("Remove Value###LevelRemoveValue")
	}
	imgui.SetNextWindowPos(center, .Appearing, {0.5, 0.5})
	if imgui.BeginPopupModal("Remove Value###LevelRemoveValue", nil, {.AlwaysAutoResize}) {
		UI_DimText(fmt.tprintf("Value %d is painted in some levels: removing it clears", ll.valueRm[1]))
		UI_DimText("those cells too (undo brings them back). Remove it?")
		if danger_button("Remove", "removevalue.ok") {
			defs_checkpoint("Remove IntGrid Value")
			e.Ldtk_Doc_RemoveIntGridValue(doc, ll.valueRm[0], ll.valueRm[1])
			level_sync_palette()
			imgui.CloseCurrentPopup()
		}
		imgui.SameLine()
		if UI_Button("Cancel", "removevalue.cancel") || imgui.IsKeyPressed(.Escape) do imgui.CloseCurrentPopup()
		level_tip("Close without changing anything", "tab.layers")
		imgui.EndPopup()
	}
	if ll.groupReq {
		ll.groupReq = false
		imgui.OpenPopup("Rename Group###LevelValueGroup")
	}
	imgui.SetNextWindowPos(center, .Appearing, {0.5, 0.5})
	if imgui.BeginPopupModal("Rename Group###LevelValueGroup", nil, {.AlwaysAutoResize}) {
		imgui.SetNextItemWidth(260)
		if imgui.IsWindowAppearing() do imgui.SetKeyboardFocusHere()
		enter := imgui.InputText("##gname", cstring(raw_data(ll.groupBuf[:])), len(ll.groupBuf), {.EnterReturnsTrue}) || imgui.IsItemDeactivatedAfterEdit()
		Drive_Item("valuegroup.name")
		if UI_PrimaryButton("Rename", "valuegroup.ok") || enter {
			color := ""
			di := e.Ldtk_Doc_LayerDefIndex(doc, ll.groupLayer)
			if di >= 0 do for g in e.LdtkJson_Arr(doc.layerDefs[di].obj, "intGridValuesGroups") do if e.LdtkJson_Int(g, "uid") == ll.groupUid do color = e.LdtkJson_Str(g, "color")
			defs_checkpoint("Rename Group")
			e.Ldtk_Doc_SetIntGridGroup(doc, ll.groupLayer, ll.groupUid, string(cstring(raw_data(ll.groupBuf[:]))), color)
			imgui.CloseCurrentPopup()
		}
		imgui.SameLine()
		if UI_Button("Cancel", "valuegroup.cancel") || imgui.IsKeyPressed(.Escape) do imgui.CloseCurrentPopup()
		level_tip("Close without changing anything", "tab.layers")
		imgui.EndPopup()
	}
}
