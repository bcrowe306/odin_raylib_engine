package editor

import "core:fmt"
import "core:path/filepath"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Level editor: the Enums tab (LDtk's EditEnumDefs, ExternalEnum, EnumSync)
//
//   enums (by tag) and external sources | the picked enum
//
// Enums: copy / cut / paste / duplicate / reorder / delete; identifier,
// tags, icon tileset; values renamed (instances follow), coloured, given
// icons, reordered, deleted (asks when used). External enums come from Haxe,
// CastleDB, JSON or text files: import, sync (renaming used values that
// disappeared, or removing them), remove a source.
// ============================================================================

@(private = "file")
le: struct {
	uid:         int,
	clip:        string,
	valBuf:      [64]u8,
	deleteReq:   bool,
	deleteUid:   int,
	valueReq:    bool,
	valueId:     [64]u8,
	syncReq:     bool,
	syncOpen:    bool,
	syncPath:    string,
	syncChoice:  map[string]string, // "Enum.Value" -> "" (remove) or the value it becomes
	importExt:   string,
	importReq:   bool,
}

ENUM_TOPIC :: "tab.enums"

LevelEnums_Select :: proc(uid: int) {le.uid = uid}

LevelEnums_Shutdown :: proc() {
	delete(le.clip)
	delete(le.syncPath)
	for k, v in le.syncChoice {
		delete(k)
		delete(v)
	}
	delete(le.syncChoice)
	le = {}
}

LevelEnums_Page :: proc(state: ^EditorState) {
	L := &GlobalLevel
	doc := L.doc
	defs := e.LdtkJson_Get(doc.root, "defs")
	avail := imgui.GetContentRegionAvail()
	if imgui.BeginChild("##enum_list", {230, avail.y}, {.Borders}, {}) {
		if UI_Button(fmt.tprintf("%s  Add enum", ICON_FA_PLUS), "defs.enum.add") {
			defs_checkpoint("Add Enum")
			le.uid = e.Ldtk_Doc_AddEnum(doc, "Enum")
		}
		level_tip("A new enum (a list of named values for Enum fields)", ENUM_TOPIC)
		imgui.SameLine()
		if UI_Button(fmt.tprintf("%s  Import", ICON_FA_FILE_IMPORT), "defs.enum.import") do imgui.OpenPopup("##enumimport")
		level_tip("Enums from a file of your project (kept in sync with it)", "enums.external")
		if imgui.BeginPopup("##enumimport") {
			kinds := [?][3]string{{"Text file", ".txt", "One enum per line: Name: A, B, C"}, {"JSON", ".json", "{\"Name\": [\"A\", \"B\"]} or {\"Name\": \"A, B\"}"}, {"Haxe source", ".hx", "Simple enums (no parameters) of a .hx file"}, {"CastleDB", ".cdb", "Sheets with a unique identifier column (colours too)"}}
			for k in kinds {
				if imgui.BeginMenu(fmt.ctprintf("%s (%s)", k[0], k[1])) {
					files := Editor_ListProjectFiles(state, "", {k[1]})
					if len(files) == 0 do UI_DimText(fmt.tprintf("No %s file in the project", k[1]))
					for f in files {
						if imgui.MenuItem(fmt.ctprintf("%s", f)) do LevelEnums_Sync(state, level_doc_rel(state, f), false)
						Drive_Item(fmt.tprintf("import:%s", f))
					}
					imgui.EndMenu()
				}
				Drive_Item(fmt.tprintf("ctx:%s", k[0]))
				if imgui.IsItemHovered() do imgui.SetTooltip("%s", fmt.ctprintf("%s", k[2]))
			}
			imgui.EndPopup()
		}
		filter := level_filter_box("enums", "Filter enums")
		imgui.Separator()
		enums := e.LdtkJson_Arr(defs, "enums")
		// tag groups (untagged first), like LDtk
		tags := make([dynamic]string, context.temp_allocator)
		append(&tags, "")
		for en in enums do for t in e.LdtkJson_Arr(en, "tags") {
			known := false
			for x in tags do if x == t.text do known = true
			if !known do append(&tags, t.text)
		}
		for tag in tags {
			if len(tags) > 1 do UI_DimText(tag == "" ? "UNTAGGED" : strings.to_upper(tag, context.temp_allocator))
			for en in enums {
				et := e.LdtkJson_Arr(en, "tags")
				first := len(et) > 0 ? et[0].text : ""
				if first != tag || !level_filter_hit(filter, e.LdtkJson_Str(en, "identifier")) do continue
				if enum_row(state, en, false) {
					imgui.EndChild()
					enum_dialogs(state)
					return
				}
			}
		}
		// external sources
		for src in e.Ldtk_Doc_ExternalEnumSources(doc) {
			imgui.Spacing()
			name := filepath.base(src.relPath)
			// buttons first: the name's badge changes width
			if UI_IconButton(ICON_FA_ROTATE, fmt.tprintf("defs.enum.sync:%s", name), "", src.modified, 22) do LevelEnums_Sync(state, src.relPath, false)
			level_tip("Reload and sync its enums", "enums.external")
			imgui.SameLine(0, 2)
			if UI_IconButton(ICON_FA_TRASH, fmt.tprintf("defs.enum.removesource:%s", name), "", false, 22) {
				defs_checkpoint("Remove External Enums")
				e.Ldtk_Doc_RemoveExternalEnumSource(doc, src.relPath)
				imgui.EndChild()
				enum_dialogs(state)
				return
			}
			level_tip("Remove this file's enums (and the fields using them)", "enums.external")
			imgui.SameLine(0, 6)
			col := src.missing ? UI_DANGER : src.modified ? UI_WARNING : UI_TEXT_DIM
			imgui.AlignTextToFramePadding()
			imgui.TextColored(col, "%s%s", fmt.ctprintf("%s  %s", ICON_FA_FILE, name), fmt.ctprintf("%s", src.missing ? " (missing)" : src.modified ? " (changed)" : ""))
			level_tip(fmt.tprintf("%s%s", src.relPath, src.missing ? ": the file isn't there" : src.modified ? ": changed since the last sync - sync it" : ""), "enums.external")
			for en in e.LdtkJson_Arr(defs, "externalEnums") {
				if e.LdtkJson_Str(en, "externalRelPath") != src.relPath || !level_filter_hit(filter, e.LdtkJson_Str(en, "identifier")) do continue
				if enum_row(state, en, true) {
					imgui.EndChild()
					enum_dialogs(state)
					return
				}
			}
		}
		imgui.Dummy({imgui.GetContentRegionAvail().x, max(imgui.GetContentRegionAvail().y, 20)})
		if imgui.BeginPopupContextItem("##enumlistctx") {
			if ctx_item(ICON_FA_PASTE, "Paste enum", "Paste the copied enum at the end", le.clip != "") {
				defs_checkpoint("Paste Enum")
				if nu := e.Ldtk_Doc_PasteEnum(doc, le.clip); nu > 0 do le.uid = nu
			}
			imgui.EndPopup()
		}
	}
	imgui.EndChild()
	imgui.SameLine(0, 8)
	if imgui.BeginChild("##enum_props", {0, avail.y}, {}, {}) {
		en := e.Ldtk_Doc_EnumDef(doc, le.uid)
		if en == nil do UI_DimText("Pick an enum, add one, or import some from a file.")
		else do enum_form(state, en)
	}
	imgui.EndChild()
	enum_dialogs(state)
}

// enum_row: one enum in the list (true: the enums changed).
@(private = "file")
enum_row :: proc(state: ^EditorState, en: ^e.LdtkJson, external: bool) -> bool {
	doc := GlobalLevel.doc
	uid := e.LdtkJson_Int(en, "uid")
	name := e.LdtkJson_Str(en, "identifier")
	if imgui.Selectable(fmt.ctprintf("%s%s (%d)##en%d", external ? "   " : "", name, len(e.LdtkJson_Arr(en, "values")), uid), le.uid == uid, {}, {0, 22}) do le.uid = uid
	Drive_Item(fmt.tprintf("defs.enum:%s", name))
	level_tip(fmt.tprintf("%s: %d values. Right-click for more.", name, len(e.LdtkJson_Arr(en, "values"))), ENUM_TOPIC)
	if !imgui.BeginPopupContextItem(fmt.ctprintf("##enctx%d", uid)) do return false
	defer imgui.EndPopup()
	if external {
		if ctx_item(ICON_FA_ROTATE, "Sync file", "Reload its file and sync") do LevelEnums_Sync(state, e.LdtkJson_Str(en, "externalRelPath"), false)
		if ctx_item(ICON_FA_TRASH, "Remove source", "Remove every enum of its file (and the fields using them)") {
			defs_checkpoint("Remove External Enums")
			e.Ldtk_Doc_RemoveExternalEnumSource(doc, e.LdtkJson_Str(en, "externalRelPath"))
			return true
		}
	} else {
		if ctx_item(ICON_FA_COPY, "Copy", "Copy the enum") {
			delete(le.clip)
			le.clip = e.Ldtk_Doc_EnumText(doc, uid)
		}
		if ctx_item(ICON_FA_SCISSORS, "Cut", "Copy it, then delete it") {
			delete(le.clip)
			le.clip = e.Ldtk_Doc_EnumText(doc, uid)
			delete_enum(uid)
			return true
		}
		if ctx_item(ICON_FA_PASTE, "Paste after", "Paste the copied enum after this one", le.clip != "") {
			defs_checkpoint("Paste Enum")
			if nu := e.Ldtk_Doc_PasteEnum(doc, le.clip, uid); nu > 0 do le.uid = nu
			return true
		}
		if ctx_item(ICON_FA_CLONE, "Duplicate", "A copy after it") {
			defs_checkpoint("Duplicate Enum")
			if nu := e.Ldtk_Doc_DuplicateEnum(doc, uid); nu > 0 do le.uid = nu
			return true
		}
		imgui.Separator()
		if ctx_item(ICON_FA_ARROW_UP, "Move up", "Earlier in the list") {
			defs_checkpoint("Move Enum")
			e.Ldtk_Doc_MoveEnum(doc, uid, -1)
			return true
		}
		if ctx_item(ICON_FA_ARROW_DOWN, "Move down", "Later in the list") {
			defs_checkpoint("Move Enum")
			e.Ldtk_Doc_MoveEnum(doc, uid, 1)
			return true
		}
		imgui.Separator()
		if ctx_item(ICON_FA_TRASH, "Delete", "Delete the enum and the fields using it (asks when used)") {
			delete_enum(uid)
			return true
		}
	}
	imgui.Separator()
	if ctx_item(ICON_FA_CIRCLE_QUESTION, "Help", "Enums in the reference") do LevelRef_Open(external ? "enums.external" : ENUM_TOPIC)
	return false
}

@(private = "file")
delete_enum :: proc(uid: int) {
	doc := GlobalLevel.doc
	if e.Ldtk_Doc_EnumUsed(doc, uid) || enum_has_fields(uid) {
		le.deleteReq = true
		le.deleteUid = uid
		return
	}
	defs_checkpoint("Delete Enum")
	e.Ldtk_Doc_RemoveEnum(doc, uid)
}

@(private = "file")
enum_has_fields :: proc(uid: int) -> bool {
	defs := e.LdtkJson_Get(GlobalLevel.doc.root, "defs")
	for f in e.LdtkJson_Arr(defs, "levelFields") do if e.Ldtk_FieldEnumUid(f) == uid do return true
	for en in e.LdtkJson_Arr(defs, "entities") do for f in e.LdtkJson_Arr(en, "fieldDefs") do if e.Ldtk_FieldEnumUid(f) == uid do return true
	return false
}

@(private = "file")
enum_form :: proc(state: ^EditorState, en: ^e.LdtkJson) {
	L := &GlobalLevel
	doc := L.doc
	a := doc.allocator
	uid := e.LdtkJson_Int(en, "uid")
	external := e.Ldtk_Doc_EnumIsExternal(en)
	UI_PanelTitle(ICON_FA_LIST, e.LdtkJson_Str(en, "identifier"), external ? "external enum" : "enum")
	UI_HeaderButtons(external ? 1 : 3)
	if !external {
		if UI_HeaderButton(ICON_FA_CLONE, "defs.enum.duplicate", "") {
			defs_checkpoint("Duplicate Enum")
			if nu := e.Ldtk_Doc_DuplicateEnum(doc, uid); nu > 0 do le.uid = nu
			return
		}
		level_tip("Duplicate the enum", ENUM_TOPIC)
		if UI_HeaderButton(ICON_FA_TRASH, "defs.enum.remove", "") {
			delete_enum(uid)
			return
		}
		level_tip("Delete the enum (and the fields using it)", ENUM_TOPIC)
	}
	if UI_HeaderButton(ICON_FA_CIRCLE_QUESTION, "defs.enum.help", "") do LevelRef_Open(external ? "enums.external" : ENUM_TOPIC)
	level_tip("Enums in the reference", ENUM_TOPIC)
	if UI_BeginProps("##enum_t") {
		UI_PropLabel("Identifier")
		if external {
			UI_DimText(e.LdtkJson_Str(en, "identifier"))
		} else if name, ok := defs_text_edit("defs.enum.name", en, "identifier"); ok && name != "" {
			defs_checkpoint("Rename Enum")
			e.Ldtk_Doc_RenameEnum(doc, uid, name)
		}
		level_tip(external ? "Comes from its file" : "Its name (Enum fields show it; Enter applies)", ENUM_TOPIC)
		if external {
			UI_PropLabel("Source")
			UI_DimText(e.LdtkJson_Str(en, "externalRelPath"))
			level_tip("The file it comes from (relative to the project)", "enums.external")
		}
		UI_PropLabel("Tags")
		{
			cur := strings.builder_make(context.temp_allocator)
			for t, i in e.LdtkJson_Arr(en, "tags") {
				if i > 0 do strings.write_string(&cur, ", ")
				strings.write_string(&cur, t.text)
			}
			buf: [256]u8
			copy(buf[:255], strings.to_string(cur))
			if imgui.InputTextWithHint("##entags", "none", cstring(raw_data(buf[:])), len(buf), {.EnterReturnsTrue}) {
				defs_checkpoint("Enum Tags")
				e.Ldtk_Doc_SetEnumTags(doc, uid, strings.split(string(cstring(raw_data(buf[:]))), ",", context.temp_allocator))
			}
			Drive_Item("defs.enum.tags")
			level_tip("Comma-separated: the list groups enums by their first tag", ENUM_TOPIC)
		}
		UI_PropLabel("Icons from")
		{
			names := make([]string, len(doc.tilesets) + 1, context.temp_allocator)
			names[0] = "No icons"
			cur := 0
			its := e.LdtkJson_Int(en, "iconTilesetUid", -1)
			for ts, i in doc.tilesets {
				names[i + 1] = ts.identifier
				if ts.uid == its do cur = i + 1
			}
			if pick, ch := UI_Combo("defs.enum.icons", cur, names); ch {
				defs_checkpoint("Enum Icons")
				e.Ldtk_Doc_SetEnumIconTileset(doc, uid, pick == 0 ? -1 : doc.tilesets[pick - 1].uid)
			}
			level_tip("A tileset to pick each value's icon from (the icons are cleared when it changes)", ENUM_TOPIC)
		}
		UI_EndProps()
	}
	UI_SectionHeader("Values")
	vals := e.LdtkJson_Arr(en, "values")
	its := e.LdtkJson_Int(en, "iconTilesetUid", -1)
	for v, i in vals {
		id := e.LdtkJson_Str(v, "id")
		imgui.PushIDInt(i32(i))
		rgb := e.LdtkJson_Int(v, "color")
		col := [3]f32{f32((rgb >> 16) & 255) / 255, f32((rgb >> 8) & 255) / 255, f32(rgb & 255) / 255}
		if imgui.ColorEdit3("##vc", &col, {.NoInputs}) {
			e.Ldtk_Doc_CheckpointOnce(doc, -1, "Enum Value Colour", v)
			e.Ldtk_Doc_SetEnumValueColor(doc, uid, id, int(col[0] * 255 + 0.5) << 16 | int(col[1] * 255 + 0.5) << 8 | int(col[2] * 255 + 0.5))
		}
		if imgui.IsItemDeactivated() do e.Ldtk_Doc_EndCoalesce(doc)
		level_tip("The value's colour (the canvas uses it for smart colours)", ENUM_TOPIC)
		imgui.SameLine()
		if its >= 0 {
			ts := e.Ldtk_Doc_Tileset(doc, its)
			drawn := false
			if t := e.LdtkJson_Get(v, "tileRect"); t != nil && t.kind == .Object && ts != nil {
				if ptr := level_texture_ptr(ts.uid); ptr != nil {
					tw, th := f32(ptr.width), f32(ptr.height)
					x, y, w, h := f32(e.LdtkJson_Int(t, "x")), f32(e.LdtkJson_Int(t, "y")), f32(e.LdtkJson_Int(t, "w")), f32(e.LdtkJson_Int(t, "h"))
					if imgui.ImageButton("##vicon", transmute(imgui.TextureID)ptr, {20, 20}, {x / tw, y / th}, {(x + w) / tw, (y + h) / th}) do imgui.OpenPopup("##vtile")
					drawn = true
				}
			}
			if !drawn && UI_IconButton(ICON_FA_IMAGE, fmt.tprintf("defs.enum.icon:%s", id), "", false, 26) do imgui.OpenPopup("##vtile")
			level_tip("Its icon: click to pick a tile", ENUM_TOPIC)
			if tid, ok := tile_pick_popup("##vtile", its); ok && ts != nil {
				src := e.Ldtk_Doc_TileSrc(ts, tid)
				defs_checkpoint("Enum Value Icon")
				e.Ldtk_Doc_SetEnumValueTile(doc, uid, id, its, {int(src.x), int(src.y), ts.gridSize, ts.gridSize})
			}
			imgui.SameLine()
		}
		imgui.SetNextItemWidth(200)
		if external {
			imgui.AlignTextToFramePadding()
			imgui.TextUnformatted(fmt.ctprintf("%s", id))
		} else if name, ok := defs_text_edit(fmt.tprintf("defs.enum.value.name:%s", id), v, "id"); ok && name != "" {
			defs_checkpoint("Rename Enum Value")
			e.Ldtk_Doc_RenameEnumValue(doc, uid, id, name)
			imgui.PopID()
			return
		}
		level_tip(external ? "Comes from the file" : "Rename it (field values using it follow; Enter applies). Right-click for more.", ENUM_TOPIC)
		if value_menu(state, uid, id, i, len(vals), external) {
			imgui.PopID()
			return
		}
		if !external {
			imgui.SameLine()
			if UI_IconButton(ICON_FA_TRASH, fmt.tprintf("defs.enum.value.remove:%s", id), "", false, 24) {
				delete_value(uid, id)
				imgui.PopID()
				return
			}
			level_tip("Remove the value (asks when fields use it)", ENUM_TOPIC)
		}
		imgui.PopID()
	}
	if !external {
		imgui.SetNextItemWidth(200)
		enter := imgui.InputTextWithHint("##newval", "New value", cstring(raw_data(le.valBuf[:])), len(le.valBuf), {.EnterReturnsTrue})
		Drive_Item("defs.enum.value.name")
		level_tip("The new value's name", ENUM_TOPIC)
		imgui.SameLine()
		if (UI_Button(fmt.tprintf("%s  Add", ICON_FA_PLUS), "defs.enum.value.add") || enter) && le.valBuf[0] != 0 {
			defs_checkpoint("Add Enum Value")
			if !e.Ldtk_Doc_AddEnumValue(doc, uid, string(cstring(raw_data(le.valBuf[:])))) do Editor_Log(state, .Warn, "This enum already has that value")
			le.valBuf = {}
		}
		level_tip("Add the value", ENUM_TOPIC)
	}
	_ = a
}

// value_menu: a value's right-click menu (true: the values changed).
@(private = "file")
value_menu :: proc(state: ^EditorState, uid: int, id: string, i, count: int, external: bool) -> bool {
	doc := GlobalLevel.doc
	if !imgui.BeginPopupContextItem("##valctx") do return false
	defer imgui.EndPopup()
	if ctx_item(ICON_FA_ARROW_UP, "Move up", "Earlier in the list", i > 0) {
		defs_checkpoint("Move Enum Value")
		e.Ldtk_Doc_MoveEnumValue(doc, uid, id, -1)
		return true
	}
	if ctx_item(ICON_FA_ARROW_DOWN, "Move down", "Later in the list", i + 1 < count) {
		defs_checkpoint("Move Enum Value")
		e.Ldtk_Doc_MoveEnumValue(doc, uid, id, 1)
		return true
	}
	if ctx_item(ICON_FA_ERASER, "Clear icon", "No icon") {
		defs_checkpoint("Enum Value Icon")
		e.Ldtk_Doc_SetEnumValueTile(doc, uid, id, -1, {})
	}
	if !external {
		imgui.Separator()
		if ctx_item(ICON_FA_TRASH, "Remove", "Remove the value") {
			delete_value(uid, id)
			return true
		}
	}
	imgui.Separator()
	if ctx_item(ICON_FA_CIRCLE_QUESTION, "Help", "Enums in the reference") do LevelRef_Open(ENUM_TOPIC)
	return false
}

@(private = "file")
delete_value :: proc(uid: int, id: string) {
	doc := GlobalLevel.doc
	if e.Ldtk_Doc_EnumValueUsed(doc, uid, id) {
		le.valueReq = true
		le.deleteUid = uid
		le.valueId = {}
		copy(le.valueId[:63], id)
		return
	}
	defs_checkpoint("Remove Enum Value")
	e.Ldtk_Doc_RemoveEnumValue(doc, uid, id)
}

// LevelEnums_Sync imports / syncs an external enum file: applied directly
// unless used values would go (then a dialog asks what they become).
LevelEnums_Sync :: proc(state: ^EditorState, relPath: string, onLoad: bool) {
	doc := GlobalLevel.doc
	s, ok := e.Ldtk_Doc_ExternalEnumDiff(doc, relPath)
	if !ok {
		Editor_Log(state, .Error, "Could not read %s (missing or empty)", relPath)
		return
	}
	if s.conflict != "" {
		Editor_Log(state, .Error, "Import failed: %s has the enum %s, which this project already has", relPath, s.conflict)
		return
	}
	if len(s.parsed) == 0 {
		Editor_Log(state, .Warn, "No enum found in %s", relPath)
		return
	}
	if e.Ldtk_EnumSync_NeedsConfirm(&s) {
		delete(le.syncPath)
		le.syncPath = strings.clone(relPath)
		for k, v in le.syncChoice {
			delete(k)
			delete(v)
		}
		clear(&le.syncChoice)
		le.syncReq = true
		return
	}
	if len(s.items) == 0 {
		// nothing to change (the colours / checksum may still update)
		e.Ldtk_Doc_ApplyEnumSync(doc, &s)
		if !onLoad do Editor_Log(state, .Info, "%s: enums already up to date", filepath.base(relPath))
		return
	}
	defs_checkpoint(s.isNew ? "Import Enums" : "Sync Enums")
	e.Ldtk_Doc_ApplyEnumSync(doc, &s)
	Editor_Log(state, .Info, "%s: enums %s", filepath.base(relPath), s.isNew ? "imported" : "updated")
	if s.isNew {
		for en in e.LdtkJson_Arr(e.LdtkJson_Get(doc.root, "defs"), "externalEnums") do if e.LdtkJson_Str(en, "externalRelPath") == relPath {
			le.uid = e.LdtkJson_Int(en, "uid")
			break
		}
	}
}

@(private = "file")
enum_dialogs :: proc(state: ^EditorState) {
	L := &GlobalLevel
	doc := L.doc
	center := imgui.GetMainViewport().WorkPos + imgui.GetMainViewport().WorkSize * 0.5
	if le.deleteReq {
		le.deleteReq = false
		imgui.OpenPopup("Delete Enum###LevelDeleteEnum")
	}
	imgui.SetNextWindowPos(center, .Appearing, {0.5, 0.5})
	if imgui.BeginPopupModal("Delete Enum###LevelDeleteEnum", nil, {.AlwaysAutoResize}) {
		UI_DimText("Fields use this enum: they are deleted with it, with")
		UI_DimText("their values in every level (undo brings them back).")
		if UI_PrimaryButton("Delete", "deleteenum.ok") {
			defs_checkpoint("Delete Enum")
			e.Ldtk_Doc_RemoveEnum(doc, le.deleteUid)
			imgui.CloseCurrentPopup()
		}
		imgui.SameLine()
		if UI_Button("Cancel", "deleteenum.cancel") || imgui.IsKeyPressed(.Escape) do imgui.CloseCurrentPopup()
		level_tip("Close without changing anything", "tab.enums")
		imgui.EndPopup()
	}
	if le.valueReq {
		le.valueReq = false
		imgui.OpenPopup("Remove Value###LevelRemoveEnumValue")
	}
	imgui.SetNextWindowPos(center, .Appearing, {0.5, 0.5})
	if imgui.BeginPopupModal("Remove Value###LevelRemoveEnumValue", nil, {.AlwaysAutoResize}) {
		id := string(cstring(raw_data(le.valueId[:])))
		UI_DimText(fmt.tprintf("Fields use %s: they become empty there.", id))
		if UI_PrimaryButton("Remove", "removeenumvalue.ok") {
			defs_checkpoint("Remove Enum Value")
			e.Ldtk_Doc_RemoveEnumValue(doc, le.deleteUid, id)
			imgui.CloseCurrentPopup()
		}
		imgui.SameLine()
		if UI_Button("Cancel", "removeenumvalue.cancel") || imgui.IsKeyPressed(.Escape) do imgui.CloseCurrentPopup()
		level_tip("Close without changing anything", "tab.enums")
		imgui.EndPopup()
	}
	if le.syncReq {
		le.syncReq = false
		imgui.OpenPopup("Sync Enums###LevelEnumSync")
	}
	imgui.SetNextWindowPos(center, .Appearing, {0.5, 0.5})
	if imgui.BeginPopupModal("Sync Enums###LevelEnumSync", nil, {.AlwaysAutoResize}) {
		defer imgui.EndPopup()
		s, ok := e.Ldtk_Doc_ExternalEnumDiff(doc, le.syncPath)
		if !ok {
			imgui.CloseCurrentPopup()
			return
		}
		UI_DimText(fmt.tprintf("%s changed. These values are used but", filepath.base(le.syncPath)))
		UI_DimText("aren't in the file any more: remove them, or rename them")
		UI_DimText("to a new value (the fields keep their choice).")
		if UI_BeginProps("##sync_t") {
			for it in s.items {
				if it.change != .Removed || !it.used do continue
				key := fmt.tprintf("%s.%s", it.enumId, it.valueId)
				UI_PropLabel(it.valueId == "" ? fmt.tprintf("enum %s", it.enumId) : key)
				if it.valueId == "" {
					UI_DimText("removed (with its fields)")
					continue
				}
				options := make([dynamic]string, context.temp_allocator)
				append(&options, "Remove")
				for x in s.items do if x.change == .Added && x.enumId == it.enumId && x.valueId != "" do append(&options, x.valueId)
				cur := 0
				if to, has := le.syncChoice[key]; has do for o, k in options do if k > 0 && o == to do cur = k
				labels := make([dynamic]string, context.temp_allocator)
				for o, k in options do append(&labels, k == 0 ? "Remove it" : fmt.tprintf("Rename to %s", o))
				if pick, ch := UI_Combo(fmt.tprintf("sync.choice:%s", key), cur, labels[:]); ch {
					if old, has := le.syncChoice[key]; has {
						delete(old)
						le.syncChoice[key] = strings.clone(pick == 0 ? "" : options[pick])
					} else do le.syncChoice[strings.clone(key)] = strings.clone(pick == 0 ? "" : options[pick])
				}
				level_tip("What the fields using it get", "enums.external")
			}
			UI_EndProps()
		}
		if UI_PrimaryButton("Sync", "sync.ok") {
			for &it in s.items {
				if it.change != .Removed || it.valueId == "" do continue
				if to, has := le.syncChoice[fmt.tprintf("%s.%s", it.enumId, it.valueId)]; has && to != "" {
					it.change = .Renamed
					it.to = to
				}
			}
			defs_checkpoint("Sync Enums")
			e.Ldtk_Doc_ApplyEnumSync(doc, &s)
			Editor_Log(state, .Info, "%s: enums updated", filepath.base(le.syncPath))
			imgui.CloseCurrentPopup()
		}
		level_tip("Apply the file's enums with these choices", "enums.external")
		imgui.SameLine()
		if UI_Button("Cancel", "sync.cancel") || imgui.IsKeyPressed(.Escape) do imgui.CloseCurrentPopup()
		level_tip("Close without changing anything", "tab.enums")
	}
}
