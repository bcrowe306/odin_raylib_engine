package editor

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Level editor: the Project tab (LDtk's EditProject) and the project's save
// / load hooks (backups; external enums synced on load).
//
//   file      extension (.ldtk / .json), backups, minify, external levels
//   names     identifier style (applied everywhere), level name pattern
//   defaults  grid, entity size and pivot, colours
//   advanced  LDtk's project flags
//   notes     the project's description
// ============================================================================

@(private = "file")
lp: struct {
	styleReq:  bool,
	styleTo:   e.Ldtk_IdentifierStyle,
	descBuf:   [2048]u8,
	descFor:   rawptr,
}

PROJECT_TOPIC :: "tab.project"

// LevelProject_BeforeSave: a backup of the files on disk, when enabled.
LevelProject_BeforeSave :: proc(state: ^EditorState) {
	doc := GlobalLevel.doc
	if doc == nil || !e.LdtkJson_Bool(doc.root, "backupOnSave") do return
	if dir := e.Ldtk_Doc_Backup(doc); dir != "" do Editor_Log(state, .Info, "Backup: %s", dir)
}

// LevelProject_AfterLoad: external enum files changed since the last sync are
// synced (asking first when used values would go).
LevelProject_AfterLoad :: proc(state: ^EditorState) {
	doc := GlobalLevel.doc
	if doc == nil do return
	for src in e.Ldtk_Doc_ExternalEnumSources(doc) {
		if src.missing {
			Editor_Log(state, .Warn, "External enum file not found: %s", src.relPath)
			continue
		}
		if src.modified do LevelEnums_Sync(state, src.relPath, true)
	}
}

LevelProject_Page :: proc(state: ^EditorState) {
	L := &GlobalLevel
	doc := L.doc
	root := doc.root
	a := doc.allocator
	avail := imgui.GetContentRegionAvail()
	if imgui.BeginChild("##project_props", {460, avail.y}, {}, {}) {
		UI_PanelTitle(ICON_FA_GEAR, "Project", filepath.base(L.rel))
		UI_HeaderButtons(1)
		if UI_HeaderButton(ICON_FA_CIRCLE_QUESTION, "defs.project.help", "") do LevelRef_Open(PROJECT_TOPIC)
		level_tip("The Project tab in the reference", PROJECT_TOPIC)
		if UI_SectionHeader("File") && UI_BeginProps("##proj_file") {
			UI_PropLabel("File extension")
			ext := filepath.ext(doc.path)
			if pick, ch := UI_Combo("defs.project.ext", ext == ".json" ? 1 : 0, []string{".ldtk (LDtk's)", ".json"}); ch {
				project_set_extension(state, pick == 1 ? ".json" : ".ldtk")
			}
			level_tip("Renames the project file (the same JSON either way)", "project.file")
			prop_bool("Backup on save", "defs.project.backup", root, "backupOnSave", "Before each save, a copy of the files as they were goes to the backup folder", "project.file")
			if e.LdtkJson_Bool(root, "backupOnSave") {
				UI_PropLabel("Backups kept")
				lim := i32(e.LdtkJson_Int(root, "backupLimit", 10))
				if imgui.InputInt("##blimit", &lim, 1, 5, {.EnterReturnsTrue}) {
					defs_checkpoint("Backup Limit")
					e.LdtkJson_SetInt(root, "backupLimit", int(clamp(lim, 3, 50)), a)
					e.Ldtk_Doc_Touch(doc)
				}
				Drive_Item("defs.project.backuplimit")
				level_tip("How many backups stay (3-50; the oldest go first)", "project.file")
				prop_text("Backup folder", "defs.project.backupdir", root, "backupRelPath", "Relative to the project file; empty: <project name>/backups", "project.file")
				UI_PropLabel("")
				if UI_Button(fmt.tprintf("%s  Open backups", ICON_FA_FOLDER_OPEN), "defs.project.openbackups") {
					dir := e.Ldtk_Doc_BackupDir(doc)
					_ = os.make_directory_all(dir)
					Editor_OpenExternally(state, dir)
				}
				level_tip("Show the backup folder", "project.file")
				imgui.SameLine()
				if UI_Button(fmt.tprintf("%s  Back up now", ICON_FA_COPY), "defs.project.backupnow") {
					if dir := e.Ldtk_Doc_Backup(doc); dir != "" do Editor_Log(state, .Info, "Backup: %s", dir)
					else do Editor_Log(state, .Warn, "Nothing to back up: save the project first")
				}
				level_tip("A backup of the saved files now", "project.file")
			}
			UI_PropLabel("Minify JSON")
			minify := e.LdtkJson_Bool(root, "minifyJson")
			if imgui.Checkbox("##minify", &minify) {
				defs_checkpoint("Minify JSON")
				e.LdtkJson_SetBool(root, "minifyJson", minify, a)
				doc.minify = minify
				for &lv in doc.levels do lv.dirty = true
				e.Ldtk_Doc_Touch(doc)
			}
			Drive_Item("defs.project.minify")
			level_tip("One line of JSON: smaller files, harder to read or merge", "project.file")
			UI_PropLabel("External level files")
			ext_on := doc.external
			if imgui.Checkbox("##external", &ext_on) {
				defs_checkpoint("External Levels")
				e.Ldtk_Doc_SetExternalLevels(doc, ext_on)
			}
			Drive_Item("defs.project.external")
			level_tip("Each level in its own .ldtkl file (in a folder named like the project): good for big projects and version control", "project.file")
			UI_EndProps()
		}
		if UI_SectionHeader("Names") && UI_BeginProps("##proj_names") {
			UI_PropLabel("Identifier style")
			style := e.Ldtk_Doc_IdentifierStyle(doc)
			labels := []string{"Capitalize: My_identifier_1", "Uppercase: MY_IDENTIFIER_1", "Lowercase: my_identifier_1", "Free: my_IdEnTiFiEr_1"}
			if pick, ch := UI_Combo("defs.project.style", int(style), labels); ch && e.Ldtk_IdentifierStyle(pick) != style {
				lp.styleReq = true
				lp.styleTo = e.Ldtk_IdentifierStyle(pick)
			}
			level_tip("How identifiers are written; changing it converts every identifier (asks first)", "project.names")
			UI_PropLabel("Level names")
			if name, ok := defs_text_edit("defs.project.levelnames", root, "levelNamePattern"); ok {
				defs_checkpoint("Level Names")
				e.LdtkJson_SetStr(root, "levelNamePattern", name != "" ? name : "Level_%idx", a)
				e.Ldtk_Doc_Touch(doc)
			}
			level_tip("New levels' names: %idx = a free number, %world = the world's name", "project.names")
			UI_EndProps()
		}
		if UI_SectionHeader("Defaults") && UI_BeginProps("##proj_defaults") {
			UI_PropLabel("Grid size")
			g := i32(e.LdtkJson_Int(root, "defaultGridSize", 16))
			if imgui.InputInt("##pgrid", &g, 1, 8, {.EnterReturnsTrue}) && g > 0 {
				defs_checkpoint("Default Grid")
				e.LdtkJson_SetInt(root, "defaultGridSize", int(clamp(g, 1, 1024)), a)
				e.Ldtk_Doc_Touch(doc)
			}
			Drive_Item("defs.project.grid")
			level_tip("The grid of new layers", "project.defaults")
			UI_PropLabel("Entity size")
			es := [2]i32{i32(e.LdtkJson_Int(root, "defaultEntityWidth", 16)), i32(e.LdtkJson_Int(root, "defaultEntityHeight", 16))}
			if project_pair("defs.project.entitysize", &es) && es.x > 0 && es.y > 0 {
				defs_checkpoint("Default Entity Size")
				e.LdtkJson_SetInt(root, "defaultEntityWidth", int(es.x), a)
				e.LdtkJson_SetInt(root, "defaultEntityHeight", int(es.y), a)
				e.Ldtk_Doc_Touch(doc)
			}
			level_tip("The size of new entities (width, height; Enter applies)", "project.defaults")
			UI_PropLabel("Entity pivot")
			pv := [2]f64{e.LdtkJson_Float(root, "defaultPivotX"), e.LdtkJson_Float(root, "defaultPivotY")}
			if p, ch := level_pivot_picker("defs.project.pivot", pv, "The pivot of new entities", "project.defaults"); ch {
				defs_checkpoint("Default Pivot")
				e.LdtkJson_SetFloat(root, "defaultPivotX", p.x, a)
				e.LdtkJson_SetFloat(root, "defaultPivotY", p.y, a)
				e.Ldtk_Doc_Touch(doc)
			}
			project_colour("Workspace", "bgColor", "#40465B", "The canvas background around the levels")
			project_colour("Level background", "defaultLevelBgColor", "#696A79", "The background of levels without their own colour")
			UI_EndProps()
		}
		if UI_SectionHeader("Advanced", false) {
			for f in e.LDTK_PROJECT_FLAGS {
				on := e.Ldtk_Doc_HasFlag(doc, f.name)
				if imgui.Checkbox(fmt.ctprintf("%s##%s", f.label, f.name), &on) {
					if f.name == "MultiWorlds" && !on && len(doc.worlds) > 1 {
						Editor_Log(state, .Warn, "Delete the other worlds first")
					} else {
						defs_checkpoint(f.label)
						e.Ldtk_Doc_SetProjectFlag(doc, f.name, on)
					}
				}
				Drive_Item(fmt.tprintf("defs.project.flag:%s", f.name))
				level_tip(f.desc, "project.flags")
				imgui.Indent(28)
				imgui.PushTextWrapPos(0)
				UI_DimText(f.desc)
				imgui.PopTextWrapPos()
				imgui.Unindent(28)
			}
		}
		if UI_SectionHeader("Description", false) {
			// the project's notes (LDtk's tutorialDesc)
			if lp.descFor != rawptr(doc) {
				lp.descFor = rawptr(doc)
				lp.descBuf = {}
				copy(lp.descBuf[:len(lp.descBuf) - 1], e.LdtkJson_Str(root, "tutorialDesc"))
			}
			imgui.InputTextMultiline("##desc", cstring(raw_data(lp.descBuf[:])), len(lp.descBuf), {-1, 90}, {})
			Drive_Item("defs.project.desc")
			level_tip("Notes about the project, saved in it", PROJECT_TOPIC)
			if imgui.IsItemDeactivatedAfterEdit() {
				text := string(cstring(raw_data(lp.descBuf[:])))
				defs_checkpoint("Project Description")
				if text == "" do e.LdtkJson_SetNull(root, "tutorialDesc", a)
				else do e.LdtkJson_SetStr(root, "tutorialDesc", text, a)
				e.Ldtk_Doc_Touch(doc)
			}
		}
	}
	imgui.EndChild()
	imgui.SameLine(0, 8)
	if imgui.BeginChild("##project_fields", {0, avail.y}, {}, {}) do LevelDefs_FieldsPanel(state, -1)
	imgui.EndChild()
	style_popup(state)
}

@(private = "file")
project_pair :: proc(id: string, v: ^[2]i32) -> bool {
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

@(private = "file")
project_colour :: proc(label, key, def, tip: string) {
	doc := GlobalLevel.doc
	UI_PropLabel(label)
	c := e.Ldtk_ParseHexColor(e.LdtkJson_Str(doc.root, key, def))
	col := [3]f32{f32(c.r) / 255, f32(c.g) / 255, f32(c.b) / 255}
	if imgui.ColorEdit3(fmt.ctprintf("##%s", key), &col, {.NoInputs}) {
		e.Ldtk_Doc_CheckpointOnce(doc, -1, label, rawptr(raw_data(key)))
		hex := e.Ldtk_ColorHex({u8(col[0] * 255 + 0.5), u8(col[1] * 255 + 0.5), u8(col[2] * 255 + 0.5), 255})
		e.LdtkJson_SetStr(doc.root, key, hex, doc.allocator)
		if key == "defaultLevelBgColor" {
			// levels using the default follow
			for &lv, li in doc.levels do if e.LdtkJson_IsNull(lv.obj, "bgColor") do e.Ldtk_Doc_SetLevelBgColor(doc, li, "")
		}
		e.Ldtk_Doc_Touch(doc)
	}
	if imgui.IsItemDeactivated() do e.Ldtk_Doc_EndCoalesce(doc)
	level_tip(tip, "project.defaults")
}

// project_set_extension renames the project file (.ldtk <-> .json).
@(private = "file")
project_set_extension :: proc(state: ^EditorState, ext: string) {
	L := &GlobalLevel
	doc := L.doc
	old := doc.path
	if filepath.ext(old) == ext do return
	next := fmt.tprintf("%s%s", strings.trim_suffix(old, filepath.ext(old)), ext)
	if os.exists(next) {
		Editor_Log(state, .Warn, "%s already exists", filepath.base(next))
		return
	}
	if !e.Ldtk_Doc_Save(doc, next) {
		Editor_Log(state, .Error, "Could not write %s", filepath.base(next))
		return
	}
	_ = os.remove(old)
	nrel := fmt.tprintf("%s%s", strings.trim_suffix(L.rel, filepath.ext(L.rel)), ext)
	delete(L.rel)
	L.rel = strings.clone(nrel)
	Editor_InvalidateProjectFiles()
	Editor_Log(state, .Info, "The project file is now %s", filepath.base(next))
}

@(private = "file")
style_popup :: proc(state: ^EditorState) {
	doc := GlobalLevel.doc
	if lp.styleReq {
		lp.styleReq = false
		imgui.OpenPopup("Identifier Style###LevelIdStyle")
	}
	center := imgui.GetMainViewport().WorkPos + imgui.GetMainViewport().WorkSize * 0.5
	imgui.SetNextWindowPos(center, .Appearing, {0.5, 0.5})
	if !imgui.BeginPopupModal("Identifier Style###LevelIdStyle", nil, {.AlwaysAutoResize}) do return
	defer imgui.EndPopup()
	UI_DimText("Make sure the game and importers you use support this style.")
	if lp.styleTo != .Free do UI_DimText("Every identifier of the project is converted to it (undo brings them back).")
	if UI_PrimaryButton("Convert", "style.ok") {
		defs_checkpoint("Identifier Style")
		e.Ldtk_Doc_SetIdentifierStyle(doc, lp.styleTo)
		level_after_defs()
		imgui.CloseCurrentPopup()
	}
	imgui.SameLine()
	if UI_Button("Cancel", "style.cancel") || imgui.IsKeyPressed(.Escape) do imgui.CloseCurrentPopup()
}
