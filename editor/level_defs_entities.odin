package editor

import "core:fmt"
import "core:strconv"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Level editor: the Entities tab (EditEntityDefs) and field definitions
// (FieldDefsForm) - also used for level fields in the Project tab.
//
//   entity list | the entity's settings | its fields | the field's settings
//
// Entity: identifier, doc, tags, size and resizing (min / max, aspect),
// pivot, colour, render mode (rectangle, ellipse, tile, cross), tile and
// tile render mode (cover, fit, repeat, stretch, full size, 9-slice),
// opacities, hollow, name shown, count limit (scope, behaviour), table of
// contents, out of bounds.
// Field: identifier, type (conversions), doc, array (min / max length),
// nullable, default, min / max, regex, file types, language, tileset,
// reference rules, canvas display (mode, position, link style, colour,
// scale, always show, in world view, cut long values, prefix / suffix),
// smart colour, table of contents, searchable.
// ============================================================================

@(private = "file")
ent: struct {
	fieldUid:      int,  // the field shown in the form
	subtab:        int,  // narrow panels: 0 settings, 1 fields
	fieldsRequest: bool, // show the Fields sub-tab
}

// LevelDefs_ShowEntityFields: the Entities tab's Fields (narrow panels).
LevelDefs_ShowEntityFields :: proc() {ent.fieldsRequest = true}

LevelDefs_EntitiesPage :: proc(state: ^EditorState) {
	L := &GlobalLevel
	doc := L.doc
	avail := imgui.GetContentRegionAvail()
	selected := LevelDefs_SelectedEntity()
	if imgui.BeginChild("##entity_list", {180, avail.y}, {.Borders}, {}) {
		if UI_Button(fmt.tprintf("%s  Add entity", ICON_FA_PLUS), "defs.entity.add") {
			defs_checkpoint("Add Entity")
			LevelDefs_SelectEntity(e.Ldtk_Doc_AddEntityDef(doc, "Entity"))
			level_sync_palette()
		}
		level_tip("A new entity definition", "tab.entities")
		imgui.Separator()
		for &ed in doc.entityDefs {
			p := imgui.GetCursorScreenPos()
			imgui.DrawList_AddRectFilled(imgui.GetWindowDrawList(), {p.x + 2, p.y + 5}, {p.x + 12, p.y + 15}, col_u32({f32(ed.color.r) / 255, f32(ed.color.g) / 255, f32(ed.color.b) / 255, 1}), 2, {})
			imgui.SetCursorScreenPos({p.x + 18, p.y})
			if imgui.Selectable(fmt.ctprintf("%s##edl%d", ed.identifier, ed.uid), selected == ed.uid, {}, {0, 20}) do LevelDefs_SelectEntity(ed.uid)
			Drive_Item(fmt.tprintf("defs.entity:%s", ed.identifier))
			level_tip(fmt.tprintf("%s (%dx%d, %d fields). Right-click for more.", ed.identifier, ed.size.x, ed.size.y, len(e.LdtkJson_Arr(ed.obj, "fieldDefs"))), "tab.entities")
			if entity_list_menu(state, ed.uid) do break
		}
	}
	imgui.EndChild()
	ed := e.Ldtk_Doc_EntityDef(doc, LevelDefs_SelectedEntity())
	imgui.SameLine(0, 8)
	if ed == nil {
		UI_DimText("Pick an entity, or add one.")
		return
	}
	uid := ed.uid
	// the entity's settings and its fields side by side when there is room,
	// else as two tabs
	w := imgui.GetContentRegionAvail().x
	if w >= 1000 {
		if imgui.BeginChild("##entity_props", {400, avail.y}, {}, {}) do entity_form(state, uid)
		imgui.EndChild()
		imgui.SameLine(0, 8)
		if imgui.BeginChild("##entity_fields", {0, avail.y}, {}, {}) {
			if e.Ldtk_Doc_EntityDef(doc, uid) != nil do LevelDefs_FieldsPanel(state, uid)
		}
		imgui.EndChild()
		return
	}
	imgui.BeginGroup()
	if imgui.BeginTabBar("##entity_subtabs", {}) {
		if imgui.BeginTabItem(fmt.ctprintf("Settings###entsettings"), nil, {}) {
			ent.subtab = 0
			imgui.EndTabItem()
		}
		Drive_Item("defs.entity.tab:Settings")
		level_tip("The entity's settings", "tab.entities")
		if imgui.BeginTabItem(fmt.ctprintf("Fields (%d)###entfields", len(e.LdtkJson_Arr(ed.obj, "fieldDefs"))), nil, ent.fieldsRequest ? {.SetSelected} : {}) {
			ent.subtab = 1
			imgui.EndTabItem()
		}
		ent.fieldsRequest = false
		Drive_Item("defs.entity.tab:Fields")
		level_tip("Its fields", "fields")
		imgui.EndTabBar()
	}
	if imgui.BeginChild("##entity_page", {0, 0}, {}, {}) {
		if ent.subtab == 0 do entity_form(state, uid)
		else if e.Ldtk_Doc_EntityDef(doc, uid) != nil do LevelDefs_FieldsPanel(state, uid)
	}
	imgui.EndChild()
	imgui.EndGroup()
}

// entity_list_menu: an entity def's right-click menu (true: the list changed).
@(private = "file")
entity_list_menu :: proc(state: ^EditorState, uid: int) -> bool {
	L := &GlobalLevel
	doc := L.doc
	if !imgui.BeginPopupContextItem(fmt.ctprintf("##edctx%d", uid)) do return false
	defer imgui.EndPopup()
	if ctx_item(ICON_FA_PAINTBRUSH, "Place in the level", "Pick it for the Brush") {
		L.entityDef = uid
		L.tool = .Brush
	}
	if ctx_item(ICON_FA_CLONE, "Duplicate", "A copy of the definition (with its fields)") {
		defs_checkpoint("Duplicate Entity")
		LevelDefs_SelectEntity(e.Ldtk_Doc_DuplicateEntityDef(doc, uid))
		return true
	}
	if ctx_item(ICON_FA_ARROW_UP, "Move up", "Earlier in the list") {
		defs_checkpoint("Reorder Entities")
		e.Ldtk_Doc_MoveEntityDef(doc, uid, -1)
		return true
	}
	if ctx_item(ICON_FA_ARROW_DOWN, "Move down", "Later in the list") {
		defs_checkpoint("Reorder Entities")
		e.Ldtk_Doc_MoveEntityDef(doc, uid, 1)
		return true
	}
	imgui.Separator()
	if ctx_item(ICON_FA_TRASH, "Delete", "Delete the definition and every instance (undo brings them back)") {
		defs_checkpoint("Delete Entity")
		e.Ldtk_Doc_RemoveEntityDef(doc, uid)
		level_after_defs()
		return true
	}
	imgui.Separator()
	if ctx_item(ICON_FA_CIRCLE_QUESTION, "Help", "Entities in the reference") do LevelRef_Open("tab.entities")
	return false
}

// ----------------------------------------------------------------------------
// small widgets
// ----------------------------------------------------------------------------

// prop_bool: a check box bound to a JSON bool; returns true when changed.
prop_bool :: proc(label, id: string, obj: ^e.LdtkJson, key: string, tip, topic: string, def := false) -> bool {
	L := &GlobalLevel
	UI_PropLabel(label)
	v := e.LdtkJson_Bool(obj, key, def)
	changed := imgui.Checkbox(fmt.ctprintf("##%s", id), &v)
	Drive_Item(id)
	level_tip(tip, topic)
	if changed {
		defs_checkpoint(label)
		e.LdtkJson_SetBool(obj, key, v, L.doc.allocator)
		e.Ldtk_Doc_Touch(L.doc)
	}
	return changed
}

// prop_opt_int: an optional integer ("" = none / null).
prop_opt_int :: proc(label, id: string, obj: ^e.LdtkJson, key: string, tip, topic: string) -> bool {
	L := &GlobalLevel
	UI_PropLabel(label)
	buf: [32]u8
	cur := e.LdtkJson_Get(obj, key)
	if cur != nil && cur.kind == .Number do copy(buf[:31], fmt.tprintf("%v", cur.num))
	entered := imgui.InputTextWithHint(fmt.ctprintf("##%s", id), "none", cstring(raw_data(buf[:])), len(buf), {.EnterReturnsTrue, .CharsScientific})
	Drive_Item(id)
	level_tip(tip, topic)
	if !entered do return false
	t := strings.trim_space(string(cstring(raw_data(buf[:]))))
	defs_checkpoint(label)
	if t == "" {
		e.LdtkJson_SetNull(obj, key, L.doc.allocator)
	} else {
		v, ok := strconv.parse_f64(t)
		if !ok do return false
		e.LdtkJson_SetFloat(obj, key, v, L.doc.allocator)
	}
	e.Ldtk_Doc_Touch(L.doc)
	return true
}

// prop_enum: a combo over string values bound to a JSON string.
prop_enum :: proc(label, id: string, obj: ^e.LdtkJson, key: string, values: []string, labels: []string, tip, topic: string) -> bool {
	L := &GlobalLevel
	UI_PropLabel(label)
	cur := e.LdtkJson_Str(obj, key, values[0])
	idx := 0
	for v, i in values do if v == cur do idx = i
	pick, changed := UI_Combo(id, idx, labels)
	level_tip(tip, topic)
	if changed {
		defs_checkpoint(label)
		e.LdtkJson_SetStr(obj, key, values[pick], L.doc.allocator)
		e.Ldtk_Doc_Touch(L.doc)
	}
	return changed
}

// prop_text: a text line bound to a JSON string (nullable: "" = null).
prop_text :: proc(label, id: string, obj: ^e.LdtkJson, key: string, tip, topic: string, nullable := true) -> bool {
	L := &GlobalLevel
	UI_PropLabel(label)
	text, ok := defs_text_edit(id, obj, key)
	level_tip(tip, topic)
	if !ok do return false
	defs_checkpoint(label)
	if text == "" && nullable do e.LdtkJson_SetNull(obj, key, L.doc.allocator)
	else do e.LdtkJson_SetStr(obj, key, text, L.doc.allocator)
	e.Ldtk_Doc_Touch(L.doc)
	return true
}

// prop_slider: a 0..1 opacity.
prop_slider :: proc(label, id: string, obj: ^e.LdtkJson, key: string, tip, topic: string, def: f64 = 1) -> bool {
	L := &GlobalLevel
	UI_PropLabel(label)
	v := f32(e.LdtkJson_Float(obj, key, def))
	changed := imgui.SliderFloat(fmt.ctprintf("##%s", id), &v, 0, 1, "%.2f")
	Drive_Item(id)
	level_tip(tip, topic)
	if changed {
		e.Ldtk_Doc_CheckpointOnce(L.doc, -1, label, rawptr(raw_data(key)))
		e.LdtkJson_SetFloat(obj, key, f64(v), L.doc.allocator)
		e.Ldtk_Doc_Touch(L.doc)
	}
	if imgui.IsItemDeactivated() do e.Ldtk_Doc_EndCoalesce(L.doc)
	return changed
}

// ----------------------------------------------------------------------------
// Entity form
// ----------------------------------------------------------------------------

ENTITY_RENDER_MODES := [?]string{"Rectangle", "Ellipse", "Tile", "Cross"}
ENTITY_TILE_MODES := [?]string{"Cover", "FitInside", "Repeat", "Stretch", "FullSizeCropped", "FullSizeUncropped", "NineSlice"}
ENTITY_TILE_MODE_LABELS := [?]string{"Cover", "Fit inside", "Repeat", "Stretch", "Full size (cropped)", "Full size (uncropped)", "9-slice"}
ENTITY_LIMIT_SCOPES := [?]string{"PerLayer", "PerLevel", "PerWorld"}
ENTITY_LIMIT_SCOPE_LABELS := [?]string{"per layer", "per level", "per world"}
ENTITY_LIMIT_BEHAVIORS := [?]string{"MoveLastOne", "DiscardOldOnes", "PreventAdding"}
ENTITY_LIMIT_BEHAVIOR_LABELS := [?]string{"move the last one", "discard the oldest", "prevent adding"}

@(private = "file")
entity_form :: proc(state: ^EditorState, uid: int) {
	L := &GlobalLevel
	doc := L.doc
	a := doc.allocator
	ed := e.Ldtk_Doc_EntityDef(doc, uid)
	obj := ed.obj
	UI_PanelTitle(ICON_FA_CUBE, ed.identifier, "entity")
	UI_HeaderButtons(2)
	if UI_HeaderButton(ICON_FA_CIRCLE_QUESTION, "defs.entity.help", "") do LevelRef_Open("tab.entities")
	level_tip("Entities in the reference", "tab.entities")
	if UI_HeaderButton(ICON_FA_TRASH, "defs.entity.remove", "") {
		defs_checkpoint("Delete Entity")
		e.Ldtk_Doc_RemoveEntityDef(doc, uid)
		level_after_defs()
		return
	}
	level_tip("Delete the entity and its instances", "tab.entities")
	changed := false
	if UI_BeginProps("##entity_t") {
		defer UI_EndProps()
		UI_PropLabel("Identifier")
		if name, ok := defs_text_edit("defs.entity.name", obj, "identifier"); ok {
			defs_checkpoint("Rename Entity")
			e.LdtkJson_SetStr(obj, "identifier", e.Ldtk_Doc_UniqueIdentifier(doc, "entities", name), a)
			changed = true
		}
		level_tip("Its name (letters, digits, _). Game scripts / components find it by this name.", "tab.entities")
		changed |= prop_text("Doc", "defs.entity.doc", obj, "doc", "A description, shown as a tooltip", "tab.entities")
		UI_PropLabel("Tags")
		{
			b := strings.builder_make(context.temp_allocator)
			for t, i in e.LdtkJson_Arr(obj, "tags") {
				if i > 0 do strings.write_string(&b, ", ")
				strings.write_string(&b, t.text)
			}
			buf: [256]u8
			copy(buf[:255], strings.to_string(b))
			if imgui.InputText("##etags", cstring(raw_data(buf[:])), len(buf), {.EnterReturnsTrue}) {
				defs_checkpoint("Entity Tags")
				tags := e.LdtkJson_New(.Array, a)
				for t in strings.split(string(cstring(raw_data(buf[:]))), ",", context.temp_allocator) {
					if c := strings.trim_space(t); c != "" do append(&tags.items, e.LdtkJson_NewString(c, a))
				}
				e.LdtkJson_Set(obj, "tags", tags, a)
				changed = true
			}
			Drive_Item("defs.entity.tags")
			level_tip("Comma-separated tags: layers can require / exclude tags, references can allow tags, scripts can test them", "tab.entities")
		}
		UI_PropLabel("Size")
		size := [2]i32{i32(ed.size.x), i32(ed.size.y)}
		if imgui.InputInt2("##esize", &size, {.EnterReturnsTrue}) && size.x > 0 && size.y > 0 {
			defs_checkpoint("Entity Size")
			e.LdtkJson_SetInt(obj, "width", int(size.x), a)
			e.LdtkJson_SetInt(obj, "height", int(size.y), a)
			changed = true
		}
		Drive_Item("defs.entity.size")
		level_tip("Width, height in pixels (Enter applies)", "tab.entities")
		changed |= prop_bool("Resizable X", "defs.entity.resizex", obj, "resizableX", "Instances can be resized horizontally (the corner handle)", "tab.entities")
		changed |= prop_bool("Resizable Y", "defs.entity.resizey", obj, "resizableY", "Instances can be resized vertically", "tab.entities")
		if e.LdtkJson_Bool(obj, "resizableX") || e.LdtkJson_Bool(obj, "resizableY") {
			changed |= prop_bool("Keep aspect", "defs.entity.aspect", obj, "keepAspectRatio", "Resizing keeps the width / height ratio", "tab.entities")
			changed |= prop_opt_int("Min width", "defs.entity.minw", obj, "minWidth", "Smallest width when resizing (empty: none)", "tab.entities")
			changed |= prop_opt_int("Max width", "defs.entity.maxw", obj, "maxWidth", "Largest width (empty: none)", "tab.entities")
			changed |= prop_opt_int("Min height", "defs.entity.minh", obj, "minHeight", "Smallest height (empty: none)", "tab.entities")
			changed |= prop_opt_int("Max height", "defs.entity.maxh", obj, "maxHeight", "Largest height (empty: none)", "tab.entities")
		}
		UI_PropLabel("Pivot")
		for p, i in PIVOTS {
			if i % 3 != 0 do imgui.SameLine(0, 2)
			on := abs(p.x - ed.pivot.x) < 0.01 && abs(p.y - ed.pivot.y) < 0.01
			if UI_IconButton(on ? ICON_FA_CIRCLE : "·", fmt.tprintf("defs.entity.pivot:%d", i), "", on, 18) {
				defs_checkpoint("Entity Pivot")
				e.LdtkJson_SetFloat(obj, "pivotX", p.x, a)
				e.LdtkJson_SetFloat(obj, "pivotY", p.y, a)
				changed = true
			}
			level_tip(fmt.tprintf("Pivot %.1f, %.1f: the point placed on the grid (its position)", p.x, p.y), "tab.entities")
		}
		UI_PropLabel("Colour")
		col := [3]f32{f32(ed.color.r) / 255, f32(ed.color.g) / 255, f32(ed.color.b) / 255}
		if imgui.ColorEdit3("##ecol", &col, {.NoInputs}) {
			e.Ldtk_Doc_CheckpointOnce(doc, -1, "Entity Colour", obj)
			e.LdtkJson_SetStr(obj, "color", e.Ldtk_ColorHex({u8(col[0] * 255 + 0.5), u8(col[1] * 255 + 0.5), u8(col[2] * 255 + 0.5), 255}), a)
			changed = true
		}
		if imgui.IsItemDeactivated() do e.Ldtk_Doc_EndCoalesce(doc)
		level_tip("Its colour in the editor (fields can override it: smart colour)", "tab.entities")
		changed |= prop_enum("Render", "defs.entity.render", obj, "renderMode", ENTITY_RENDER_MODES[:], ENTITY_RENDER_MODES[:], "How the editor draws it: a rectangle, an ellipse, its tile, a cross", "tab.entities")
		UI_PropLabel("Tile")
		if ed.tileRect[2] > 0 {
			if ptr := level_texture_ptr(ed.tilesetUid); ptr != nil {
				tw, th := f32(ptr.width), f32(ptr.height)
				imgui.Image(transmute(imgui.TextureID)ptr, {24, 24}, {f32(ed.tileRect[0]) / tw, f32(ed.tileRect[1]) / th}, {f32(ed.tileRect[0] + ed.tileRect[2]) / tw, f32(ed.tileRect[1] + ed.tileRect[3]) / th})
				imgui.SameLine()
			}
		}
		if UI_Button("Use picked tile", "defs.entity.tile") {
			if ts, rect, ok := picked_tile_rect(); ok {
				defs_checkpoint("Entity Tile")
				e.Ldtk_Doc_SetEntityTile(doc, uid, ts, rect)
				changed = true
			} else do Editor_Log(state, .Info, "Pick tiles in a tileset palette first")
		}
		level_tip("Its picture: the tiles picked in a tileset palette", "tab.entities")
		if ed.tileRect[2] > 0 {
			imgui.SameLine()
			if UI_Button("Clear", "defs.entity.tile.clear") {
				defs_checkpoint("Entity Tile")
				e.Ldtk_Doc_SetEntityTile(doc, uid, -1, {})
				changed = true
			}
			level_tip("No tile", "tab.entities")
			changed |= prop_enum("Tile mode", "defs.entity.tilemode", obj, "tileRenderMode", ENTITY_TILE_MODES[:], ENTITY_TILE_MODE_LABELS[:], "How the tile fills the entity: cover, fit inside, repeat, stretch, full size, 9-slice", "tab.entities")
			if e.LdtkJson_Str(obj, "tileRenderMode") == "NineSlice" {
				UI_PropLabel("9-slice borders")
				nb := e.LdtkJson_Arr(obj, "nineSliceBorders")
				v := [4]i32{}
				for x, i in nb do if i < 4 do v[i] = i32(x.num)
				if imgui.InputInt4("##nine", &v, {.EnterReturnsTrue}) {
					defs_checkpoint("9-slice Borders")
					arr := e.LdtkJson_New(.Array, a)
					for x in v do append(&arr.items, e.LdtkJson_NewInt(int(max(x, 0)), a))
					e.LdtkJson_Set(obj, "nineSliceBorders", arr, a)
					changed = true
				}
				level_tip("Top, right, bottom, left borders in pixels (they don't stretch)", "tab.entities")
			}
			changed |= prop_slider("Tile opacity", "defs.entity.tileop", obj, "tileOpacity", "The tile's opacity in the editor", "tab.entities")
		}
		changed |= prop_slider("Fill opacity", "defs.entity.fillop", obj, "fillOpacity", "The shape's fill opacity in the editor", "tab.entities", 0.08)
		changed |= prop_slider("Line opacity", "defs.entity.lineop", obj, "lineOpacity", "The outline's opacity in the editor", "tab.entities")
		changed |= prop_bool("Hollow", "defs.entity.hollow", obj, "hollow", "Selected only by its outline (clicks inside go through)", "tab.entities")
		changed |= prop_bool("Show name", "defs.entity.showname", obj, "showName", "Its name above it in the canvas", "tab.entities", true)
		UI_PropLabel("Max count")
		mc := i32(e.LdtkJson_Int(obj, "maxCount"))
		if imgui.InputInt("##maxcount", &mc, 1, 1, {.EnterReturnsTrue}) && mc >= 0 {
			defs_checkpoint("Max Count")
			e.LdtkJson_SetInt(obj, "maxCount", int(mc), a)
			changed = true
		}
		Drive_Item("defs.entity.maxcount")
		level_tip("At most this many (0: no limit) - e.g. one Player", "tab.entities")
		if e.LdtkJson_Int(obj, "maxCount") > 0 {
			changed |= prop_enum("Limit", "defs.entity.limitscope", obj, "limitScope", ENTITY_LIMIT_SCOPES[:], ENTITY_LIMIT_SCOPE_LABELS[:], "Where the limit counts", "tab.entities")
			changed |= prop_enum("When reached", "defs.entity.limitbehavior", obj, "limitBehavior", ENTITY_LIMIT_BEHAVIORS[:], ENTITY_LIMIT_BEHAVIOR_LABELS[:], "Placing one more: the last one moves here, the oldest goes, or nothing happens", "tab.entities")
		}
		changed |= prop_bool("Table of contents", "defs.entity.toc", obj, "exportToToc", "List its instances in the project's table of contents (toc) for games", "tab.entities")
		changed |= prop_bool("Out of bounds", "defs.entity.oob", obj, "allowOutOfBounds", "Instances may stand outside their level", "tab.entities")
	}
	if changed do e.Ldtk_Doc_EntityDefChanged(doc, uid)
}

// ----------------------------------------------------------------------------
// Fields panel (an entity's, or the levels' with entityUid -1)
// ----------------------------------------------------------------------------

LevelDefs_FieldsPanel :: proc(state: ^EditorState, entityUid: int) {
	L := &GlobalLevel
	doc := L.doc
	topic := "fields"
	list: []^e.LdtkJson
	if entityUid >= 0 {
		ed := e.Ldtk_Doc_EntityDef(doc, entityUid)
		if ed == nil do return
		list = e.LdtkJson_Arr(ed.obj, "fieldDefs")
	} else {
		list = e.LdtkJson_Arr(e.LdtkJson_Get(doc.root, "defs"), "levelFields")
	}
	avail := imgui.GetContentRegionAvail()
	if imgui.BeginChild("##field_list", {190, avail.y}, {.Borders}, {}) {
		UI_DimText(entityUid >= 0 ? "Fields" : "Level fields")
		level_tip(entityUid >= 0 ? "Values each instance carries" : "Values every level carries", topic)
		found := false
		for fd in list {
			fuid := e.LdtkJson_Int(fd, "uid")
			if fuid == ent.fieldUid do found = true
			label := fmt.ctprintf("%s  %s##fl%d", e.LdtkJson_Str(fd, "identifier"), e.LdtkJson_Str(fd, "__type"), fuid)
			if imgui.Selectable(label, ent.fieldUid == fuid, {}, {0, 20}) do ent.fieldUid = fuid
			Drive_Item(fmt.tprintf("defs.field:%s", e.LdtkJson_Str(fd, "identifier")))
			level_tip(fmt.tprintf("%s (%s). Right-click for more.", e.LdtkJson_Str(fd, "identifier"), e.LdtkJson_Str(fd, "__type")), topic)
			if field_list_menu(state, fuid) do break
		}
		if !found && len(list) > 0 do ent.fieldUid = e.LdtkJson_Int(list[0], "uid")
		imgui.Separator()
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
		imgui.SetNextItemWidth(-1)
		typeIdx, _ = UI_Combo("defs.field.type", clamp(typeIdx, 0, len(names) - 1), names[:])
		level_tip("The new field's type", topic)
		if UI_Button(fmt.tprintf("%s  Add field", ICON_FA_PLUS), "defs.field.add") {
			defs_checkpoint("Add Field")
			ent.fieldUid = e.Ldtk_Doc_AddFieldDef(doc, entityUid, types[typeIdx], strings.to_lower(names[typeIdx], context.temp_allocator))
		}
		level_tip("Add a field of that type (instances get its default)", topic)
	}
	imgui.EndChild()
	imgui.SameLine(0, 8)
	if imgui.BeginChild("##field_form", {0, avail.y}, {}, {}) {
		if fd := e.Ldtk_Doc_FieldDef(doc, ent.fieldUid); fd != nil {
			field_form(state, fd)
		} else do UI_DimText("Add a field: pick a type on the left.")
	}
	imgui.EndChild()
}

// field_list_menu: a field def's right-click menu (true: the list changed).
@(private = "file")
field_list_menu :: proc(state: ^EditorState, fuid: int) -> bool {
	L := &GlobalLevel
	doc := L.doc
	if !imgui.BeginPopupContextItem(fmt.ctprintf("##flctx%d", fuid)) do return false
	defer imgui.EndPopup()
	if ctx_item(ICON_FA_CLONE, "Duplicate", "A copy of the field") {
		defs_checkpoint("Duplicate Field")
		ent.fieldUid = e.Ldtk_Doc_DuplicateFieldDef(doc, fuid)
		return true
	}
	if ctx_item(ICON_FA_ARROW_UP, "Move up", "Earlier (the order in forms and the file)") {
		defs_checkpoint("Reorder Fields")
		e.Ldtk_Doc_MoveFieldDef(doc, fuid, -1)
		return true
	}
	if ctx_item(ICON_FA_ARROW_DOWN, "Move down", "Later") {
		defs_checkpoint("Reorder Fields")
		e.Ldtk_Doc_MoveFieldDef(doc, fuid, 1)
		return true
	}
	imgui.Separator()
	if ctx_item(ICON_FA_TRASH, "Delete", "Delete the field and its values (undo brings them back)") {
		defs_checkpoint("Delete Field")
		e.Ldtk_Doc_RemoveFieldDef(doc, fuid)
		return true
	}
	imgui.Separator()
	if ctx_item(ICON_FA_CIRCLE_QUESTION, "Help", "Fields in the reference") do LevelRef_Open("fields")
	return false
}

// field_display_modes: the display modes a field def can use.
@(private = "file")
field_display_modes :: proc(fd: ^e.LdtkJson, forLevel: bool) -> ([]string, []string) {
	modes := make([dynamic]string, context.temp_allocator)
	labels := make([dynamic]string, context.temp_allocator)
	add :: proc(m, l: ^[dynamic]string, mode, label: string) {
		append(m, mode)
		append(l, label)
	}
	add(&modes, &labels, "Hidden", "Hidden")
	add(&modes, &labels, "ValueOnly", "Value only")
	add(&modes, &labels, "NameAndValue", "Name and value")
	isArray := e.LdtkJson_Bool(fd, "isArray")
	if isArray {
		add(&modes, &labels, "ArrayCountWithLabel", "Array count (with label)")
		add(&modes, &labels, "ArrayCountNoLabel", "Array count")
	}
	#partial switch e.Ldtk_FieldKindOf(fd) {
	case .Int, .Float:
		add(&modes, &labels, "RadiusPx", "Radius (pixels)")
		add(&modes, &labels, "RadiusGrid", "Radius (grid cells)")
	case .Point:
		add(&modes, &labels, "Points", "Points")
		if isArray {
			add(&modes, &labels, "PointPath", "Path")
			add(&modes, &labels, "PointPathLoop", "Loop")
			add(&modes, &labels, "PointStar", "Star")
		}
	case .EntityRef:
		add(&modes, &labels, "RefLinkBetweenPivots", "Link (pivots)")
		add(&modes, &labels, "RefLinkBetweenCenters", "Link (centres)")
	case .Enum, .Tile:
		if forLevel do add(&modes, &labels, "LevelTile", "Level tile")
		else do add(&modes, &labels, "EntityTile", "Entity tile")
	}
	return modes[:], labels[:]
}

FIELD_DISPLAY_POS := [?]string{"Above", "Center", "Beneath"}
FIELD_LINK_STYLES := [?]string{"StraightArrow", "CurvedArrow", "ArrowsLine", "DashedLine", "ZigZag"}
FIELD_LINK_LABELS := [?]string{"Straight arrow", "Curved arrow", "Arrows line", "Dashed line", "Zig zag"}
FIELD_REF_TARGETS := [?]string{"Any", "OnlySame", "OnlyTags", "OnlySpecificEntity"}
FIELD_REF_LABELS := [?]string{"any entity", "the same entity", "entities with tags", "one entity"}
FIELD_LANGS := [?]string{"", "LangPython", "LangRuby", "LangJS", "LangLua", "LangC", "LangHaxe", "LangMarkdown", "LangJson", "LangXml", "LangLog"}
FIELD_LANG_LABELS := [?]string{"plain text", "Python", "Ruby", "JavaScript", "Lua", "C", "Haxe", "Markdown", "JSON", "XML", "log"}

@(private = "file")
field_form :: proc(state: ^EditorState, fd: ^e.LdtkJson) {
	L := &GlobalLevel
	doc := L.doc
	a := doc.allocator
	fuid := e.LdtkJson_Int(fd, "uid")
	kind := e.Ldtk_FieldKindOf(fd)
	forLevel := false
	for f in e.LdtkJson_Arr(e.LdtkJson_Get(doc.root, "defs"), "levelFields") do if f == fd do forLevel = true
	topic := "fields"
	UI_PanelTitle(ICON_FA_PEN_TO_SQUARE, e.LdtkJson_Str(fd, "identifier"), e.LdtkJson_Str(fd, "__type"))
	changed := false
	if !UI_BeginProps("##field_t") do return
	defer {
		UI_EndProps()
		if changed do e.Ldtk_Doc_RefreshFieldInstances(doc, fuid)
	}
	UI_PropLabel("Identifier")
	if name, ok := defs_text_edit("defs.field.name", fd, "identifier"); ok {
		defs_checkpoint("Rename Field")
		if !e.Ldtk_Doc_RenameFieldDef(doc, fuid, name) do Editor_Log(state, .Warn, "A field is already called %s", name)
	}
	level_tip("Its name: in the game, a script property with this name gets the value", topic)
	// type conversions
	UI_PropLabel("Type")
	convs := e.Ldtk_Doc_FieldConversions(fd)
	if imgui.BeginCombo("##ftype", fmt.ctprintf("%s", e.LdtkJson_Str(fd, "__type"))) {
		if len(convs) == 0 do UI_DimText("No conversion for this type")
		for c in convs {
			conv := e.LDTK_FIELD_CONVERSIONS[c]
			if imgui.Selectable(fmt.ctprintf("%s%s", conv.label, conv.lossless ? "" : "  (may lose data)")) {
				defs_checkpoint("Convert Field")
				e.Ldtk_Doc_ConvertFieldDef(doc, fuid, c)
				imgui.EndCombo()
				return
			}
			Drive_Item(fmt.tprintf("pick:%s", conv.label))
		}
		imgui.EndCombo()
	}
	Drive_Item("defs.field.convert")
	level_tip("Convert the field (and its values) to a compatible type, or turn it into an array", topic)
	changed |= prop_text("Doc", "defs.field.doc", fd, "doc", "A description, shown as the value's tooltip", topic)
	isArray := e.LdtkJson_Bool(fd, "isArray")
	if isArray {
		changed |= prop_opt_int("Min values", "defs.field.amin", fd, "arrayMinLength", "Fewest values (empty: none)", topic)
		changed |= prop_opt_int("Max values", "defs.field.amax", fd, "arrayMaxLength", "Most values (empty: no limit)", topic)
	}
	if kind != .Point && kind != .EntityRef && kind != .Tile && kind != .Path {
		changed |= prop_bool("Nullable", "defs.field.null", fd, "canBeNull", "Can be empty (otherwise it always has a value)", topic)
	}
	// default
	if kind != .Point && kind != .EntityRef && kind != .Path {
		UI_PropLabel("Default")
		text, isNull := e.Ldtk_Doc_FieldDefault(doc, fd)
		buf: [256]u8
		if !isNull do copy(buf[:255], text)
		if imgui.InputTextWithHint("##fdefault", isNull ? "(none)" : "", cstring(raw_data(buf[:])), len(buf), {.EnterReturnsTrue}) {
			defs_checkpoint("Field Default")
			if !e.Ldtk_Doc_FieldDefDefaultSet(doc, fd, string(cstring(raw_data(buf[:])))) do Editor_Log(state, .Warn, "That default doesn't fit the field")
		}
		Drive_Item("defs.field.default")
		level_tip("The value new instances (and unset values) use; empty: the type's own default", topic)
	}
	#partial switch kind {
	case .Int, .Float:
		changed |= prop_opt_int("Min", "defs.field.min", fd, "min", "Smallest value (empty: none)", topic)
		changed |= prop_opt_int("Max", "defs.field.max", fd, "max", "Largest value (empty: none)", topic)
	case .String:
		changed |= prop_text("Regex", "defs.field.regex", fd, "regex", "Values must match it, as /pattern/flags (i: ignore case) - e.g. /^[A-Z]{3}$/", topic)
	case .Text:
		changed |= prop_enum("Language", "defs.field.lang", fd, "textLanguageMode", FIELD_LANGS[:], FIELD_LANG_LABELS[:], "Syntax of the text (for highlighting in LDtk)", topic)
	case .Path:
		UI_PropLabel("File types")
		b := strings.builder_make(context.temp_allocator)
		for x, i in e.LdtkJson_Arr(fd, "acceptFileTypes") {
			if i > 0 do strings.write_string(&b, ", ")
			strings.write_string(&b, x.text)
		}
		buf: [256]u8
		copy(buf[:255], strings.to_string(b))
		if imgui.InputTextWithHint("##ftypes", "any file", cstring(raw_data(buf[:])), len(buf), {.EnterReturnsTrue}) {
			defs_checkpoint("File Types")
			arr := e.LdtkJson_New(.Array, a)
			for t in strings.split(string(cstring(raw_data(buf[:]))), ",", context.temp_allocator) do if c := strings.trim_space(t); c != "" do append(&arr.items, e.LdtkJson_NewString(c, a))
			if len(arr.items) == 0 do e.LdtkJson_SetNull(fd, "acceptFileTypes", a)
			else do e.LdtkJson_Set(fd, "acceptFileTypes", arr, a)
			changed = true
		}
		Drive_Item("defs.field.filetypes")
		level_tip("Comma-separated extensions (png, .ogg); empty: any file", topic)
	case .Tile:
		UI_PropLabel("Tileset")
		names := make([]string, len(doc.tilesets) + 1, context.temp_allocator)
		names[0] = "(none)"
		cur := 0
		for ts, i in doc.tilesets {
			names[i + 1] = ts.identifier
			if ts.uid == e.LdtkJson_Int(fd, "tilesetUid", -1) do cur = i + 1
		}
		if pick, ch := UI_Combo("defs.field.tileset", cur, names); ch {
			defs_checkpoint("Field Tileset")
			if pick == 0 do e.LdtkJson_SetNull(fd, "tilesetUid", a)
			else do e.LdtkJson_SetInt(fd, "tilesetUid", doc.tilesets[pick - 1].uid, a)
			changed = true
		}
		level_tip("The tileset its tiles come from", topic)
	case .EntityRef:
		changed |= prop_enum("Can point at", "defs.field.allowedrefs", fd, "allowedRefs", FIELD_REF_TARGETS[:], FIELD_REF_LABELS[:], "Which entities a reference may point at", topic)
		switch e.LdtkJson_Str(fd, "allowedRefs") {
		case "OnlySpecificEntity":
			UI_PropLabel("Entity")
			names := make([]string, len(doc.entityDefs), context.temp_allocator)
			cur := 0
			for &ed, i in doc.entityDefs {
				names[i] = ed.identifier
				if ed.uid == e.LdtkJson_Int(fd, "allowedRefsEntityUid", -1) do cur = i
			}
			if len(names) > 0 {
				if pick, ch := UI_Combo("defs.field.refentity", cur, names); ch {
					defs_checkpoint("Reference Target")
					e.LdtkJson_SetInt(fd, "allowedRefsEntityUid", doc.entityDefs[pick].uid, a)
					changed = true
				}
			}
			level_tip("The only entity it may point at", topic)
		case "OnlyTags":
			UI_PropLabel("Tags")
			b := strings.builder_make(context.temp_allocator)
			for t, i in e.LdtkJson_Arr(fd, "allowedRefTags") {
				if i > 0 do strings.write_string(&b, ", ")
				strings.write_string(&b, t.text)
			}
			buf: [256]u8
			copy(buf[:255], strings.to_string(b))
			if imgui.InputText("##reftags", cstring(raw_data(buf[:])), len(buf), {.EnterReturnsTrue}) {
				defs_checkpoint("Reference Tags")
				arr := e.LdtkJson_New(.Array, a)
				for t in strings.split(string(cstring(raw_data(buf[:]))), ",", context.temp_allocator) do if c := strings.trim_space(t); c != "" do append(&arr.items, e.LdtkJson_NewString(c, a))
				e.LdtkJson_Set(fd, "allowedRefTags", arr, a)
				changed = true
			}
			level_tip("Comma-separated: it may point at entities with one of these tags", topic)
		}
		changed |= prop_bool("Other levels", "defs.field.outoflevel", fd, "allowOutOfLevelRef", "May point at entities in other levels", topic, true)
		changed |= prop_bool("Symmetrical", "defs.field.symmetrical", fd, "symmetricalRef", "Pointing A at B makes B point at A (B needs the same field)", topic)
		changed |= prop_bool("Auto chain", "defs.field.autochain", fd, "autoChainRef", "After placing an entity, keep picking references (LDtk's chaining)", topic, true)
	}
	if (kind == .Color || kind == .Enum) {
		changed |= prop_bool("Smart colour", "defs.field.smartcolor", fd, "useForSmartColor", "Its colour (an enum value's colour) becomes the entity's / level's colour in the editor", topic)
	}
	// canvas display
	modes, labels := field_display_modes(fd, forLevel)
	changed |= prop_enum("Display", "defs.field.display", fd, "editorDisplayMode", modes, labels, "How the canvas shows it", "fields.display")
	mode := e.LdtkJson_Str(fd, "editorDisplayMode", "Hidden")
	if mode == "ValueOnly" || mode == "NameAndValue" || mode == "ArrayCountWithLabel" || mode == "ArrayCountNoLabel" {
		changed |= prop_enum("Position", "defs.field.pos", fd, "editorDisplayPos", FIELD_DISPLAY_POS[:], FIELD_DISPLAY_POS[:], "Above, at the centre of, or beneath the entity", "fields.display")
		changed |= prop_text("Prefix", "defs.field.prefix", fd, "editorTextPrefix", "Text before the value (e.g. \"x\")", "fields.display")
		changed |= prop_text("Suffix", "defs.field.suffix", fd, "editorTextSuffix", "Text after the value (e.g. \" hp\")", "fields.display")
		changed |= prop_bool("Cut long values", "defs.field.cut", fd, "editorCutLongValues", "Shorten long values with ...", "fields.display", true)
	}
	if mode == "RefLinkBetweenPivots" || mode == "RefLinkBetweenCenters" {
		changed |= prop_enum("Link style", "defs.field.link", fd, "editorLinkStyle", FIELD_LINK_STYLES[:], FIELD_LINK_LABELS[:], "How the arrow to the referenced entity looks", "fields.display")
	}
	if mode != "Hidden" {
		UI_PropLabel("Display colour")
		dc := e.LdtkJson_Str(fd, "editorDisplayColor")
		c := e.Ldtk_ParseHexColor(dc, {255, 255, 255, 255})
		col := [3]f32{f32(c.r) / 255, f32(c.g) / 255, f32(c.b) / 255}
		if imgui.ColorEdit3("##fdcol", &col, {.NoInputs}) {
			e.Ldtk_Doc_CheckpointOnce(doc, -1, "Display Colour", fd)
			e.LdtkJson_SetStr(fd, "editorDisplayColor", e.Ldtk_ColorHex({u8(col[0] * 255 + 0.5), u8(col[1] * 255 + 0.5), u8(col[2] * 255 + 0.5), 255}), a)
			e.Ldtk_Doc_Touch(doc)
		}
		if imgui.IsItemDeactivated() do e.Ldtk_Doc_EndCoalesce(doc)
		if dc != "" {
			imgui.SameLine()
			if UI_Button("Entity's", "defs.field.dcol.clear") {
				defs_checkpoint("Display Colour")
				e.LdtkJson_SetNull(fd, "editorDisplayColor", a)
				e.Ldtk_Doc_Touch(doc)
			}
			level_tip("Use the entity's colour", "fields.display")
		}
		level_tip("The colour it is shown in (default: the entity's)", "fields.display")
		UI_PropLabel("Display scale")
		sc := f32(e.LdtkJson_Float(fd, "editorDisplayScale", 1))
		if imgui.SliderFloat("##fdscale", &sc, 0.25, 4, "%.2f") {
			e.Ldtk_Doc_CheckpointOnce(doc, -1, "Display Scale", &fd.items)
			e.LdtkJson_SetFloat(fd, "editorDisplayScale", f64(sc), a)
			e.Ldtk_Doc_Touch(doc)
		}
		if imgui.IsItemDeactivated() do e.Ldtk_Doc_EndCoalesce(doc)
		level_tip("Text size in the canvas", "fields.display")
		changed |= prop_bool("Always show", "defs.field.always", fd, "editorAlwaysShow", "Also show it while it is still the default / empty", "fields.display")
		changed |= prop_bool("In world view", "defs.field.world", fd, "editorShowInWorld", "Also show it when zoomed out on the world", "fields.display", true)
	}
	changed |= prop_bool("Table of contents", "defs.field.toc", fd, "exportToToc", "Include its value in the table of contents (toc) entries", topic)
	changed |= prop_bool("Searchable", "defs.field.search", fd, "searchable", "Its values can be searched (the Find box)", topic)
}

// LevelDefs_SelectedField: the field shown in the form (drives).
LevelDefs_SelectedField :: proc() -> int {return ent.fieldUid}
