package editor

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// New Resource dialog: a name (resources/<name>.resource.json) and its class -
// a script marked `Class.resource = { ... }` (engine/script_resources.odin).
// Opened from Assets (the Resources section's +, the + menu, the section's
// context menu). The new file sets no values (the class's defaults) and is
// selected. Without a class yet, it offers New Resource Class (the New
// Script dialog on the Resource Class template).
// ============================================================================

@(private = "file")
New_Resource_Dialog :: struct {
	open:    bool,
	focus:   bool,
	name:    [64]u8,
	class:   int,
	classes: [dynamic]string, // class scripts, found when opened (heap)
}

@(private = "file")
rdlg: New_Resource_Dialog

// NewResourceDialog_Open opens the dialog (class: the one to pick first).
NewResourceDialog_Open :: proc(state: ^EditorState, class := "") {
	for c in rdlg.classes do delete(c)
	clear(&rdlg.classes)
	rdlg.open = true
	rdlg.focus = true
	rdlg.name = {}
	rdlg.class = 0
	copy(rdlg.name[:len(rdlg.name) - 1], "new_resource")
	for rel, i in Resource_ClassScripts(state) {
		append(&rdlg.classes, strings.clone(rel))
		if rel == class do rdlg.class = i
	}
}

// Resource_ClassScripts: the project's resource classes - scripts with the
// marker line `<Name>.resource = {` (read, not run; temp allocated).
Resource_ClassScripts :: proc(state: ^EditorState) -> []string {
	out := make([dynamic]string, context.temp_allocator)
	for rel in Editor_ListProjectFiles(state, "", {".lua"}) {
		full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
		data, err := os.read_entire_file(full, context.temp_allocator)
		if err == nil && Resource_HasClassMarker(string(data)) do append(&out, rel)
	}
	return out[:]
}

// Resource_HasClassMarker: Lua text that marks its table a resource class.
Resource_HasClassMarker :: proc(text: string) -> bool {
	text := text
	for line in strings.split_lines_iterator(&text) {
		l := strings.trim_space(line)
		i := strings.index(l, ".resource")
		if i <= 0 do continue
		owner := l[:i]
		ident := true
		for r in owner do if !(r == '_' || (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9')) do ident = false
		if !ident do continue
		rest := strings.trim_left_space(l[i + len(".resource"):])
		if !strings.has_prefix(rest, "=") do continue
		if strings.has_prefix(strings.trim_left_space(rest[1:]), "{") do return true
	}
	return false
}

// Editor_NewResource writes resources/<name>.resource.json of a class (a
// taken name gets _2, _3...) and selects it. Returns its path ("" = failed).
Editor_NewResource :: proc(state: ^EditorState, baseName, class: string) -> string {
	dir, _ := filepath.join({state.projectPath, "resources"}, context.temp_allocator)
	_ = os.make_directory_all(dir)
	name := baseName
	rel := ""
	for i := 1; ; i += 1 {
		if i > 1 do name = fmt.tprintf("%s_%d", baseName, i)
		rel = fmt.tprintf("resources/%s%s", name, e.RESOURCE_EXT)
		full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
		if !os.exists(full) do break
	}
	full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
	text := e.Resource_FileText(class, nil, nil, nil, context.temp_allocator)
	if os.write_entire_file(full, transmute([]u8)text) != nil {
		Editor_Log(state, .Error, "Could not create %s", rel)
		return ""
	}
	Lua_MarkProjectTypesDirty()
	Editor_Log(state, .Info, "Created %s (%s)", rel, class)
	Editor_SelectAsset(state, full)
	return rel
}

NewResourceDialog_Render :: proc(state: ^EditorState) {
	if rdlg.open && !imgui.IsPopupOpen("New Resource###NewResourceDialog") do imgui.OpenPopup("New Resource###NewResourceDialog")
	io := imgui.GetIO()
	imgui.SetNextWindowSize({560, 400}, .Appearing)
	imgui.SetNextWindowPos({io.DisplaySize.x * 0.5, io.DisplaySize.y * 0.5}, .Appearing, {0.5, 0.5})
	imgui.PushStyleVarImVec2(.WindowPadding, {16, 14})
	defer imgui.PopStyleVar()
	if !imgui.BeginPopupModal("New Resource###NewResourceDialog", &rdlg.open, {.NoResize, .NoTitleBar}) do return
	defer imgui.EndPopup()

	UI_PanelTitle(ICON_FA_GEM, "New Resource")
	imgui.Dummy({0, 4})

	// File name: resources/<name>.resource.json.
	imgui.AlignTextToFramePadding()
	imgui.TextUnformatted("resources/")
	imgui.SameLine(0, 2)
	if rdlg.focus {
		imgui.SetKeyboardFocusHere()
		rdlg.focus = false
	}
	imgui.SetNextItemWidth(220)
	imgui.InputText("##newresource_name", cstring(raw_data(rdlg.name[:])), len(rdlg.name), {.CharsNoBlank, .AutoSelectAll})
	Drive_Item("newresource.name")
	imgui.SameLine(0, 2)
	imgui.TextUnformatted(e.RESOURCE_EXT)
	name := strings.trim_space(string(cstring(raw_data(rdlg.name[:]))))
	name = strings.trim_suffix(name, e.RESOURCE_EXT)
	if name != "" {
		full, _ := filepath.join({state.projectPath, "resources", fmt.tprintf("%s%s", name, e.RESOURCE_EXT)}, context.temp_allocator)
		if os.exists(full) {
			imgui.SameLine(0, UI_SPACE)
			UI_DimText(fmt.tprintf("exists - creates %s_2", name))
		}
	}
	imgui.Dummy({0, 6})

	// Class.
	UI_DimText("Class")
	create := false
	listH := imgui.GetContentRegionAvail().y - 44
	imgui.PushStyleColorImVec4(.ChildBg, UI_BG_APP)
	if imgui.BeginChild("##resource_classes", {0, listH}, {}, {}) {
		if len(rdlg.classes) == 0 {
			imgui.Dummy({0, 4})
			UI_DimText("No resource classes yet. A class is a script whose table has a")
			UI_DimText("`resource` marker: MyClass.resource = { local_copy = false }")
			imgui.Dummy({0, 4})
			if UI_Button(fmt.tprintf("%s  New Resource Class...", ICON_FA_FILE_CODE), "newresource.new-class") {
				rdlg.open = false
				imgui.CloseCurrentPopup()
				NewScriptDialog_Open(state, nil, "resource", "new_resource_class")
			}
		}
		for rel, i in rdlg.classes {
			if imgui.Selectable(fmt.ctprintf("   %s  %s###cls_%s", ICON_FA_FILE_CODE, rel, rel), rdlg.class == i, {}, {0, 26}) do rdlg.class = i
			Drive_Item(fmt.tprintf("newresource.class:%s", rel))
			if imgui.IsItemHovered() && imgui.IsMouseDoubleClicked(.Left) {
				rdlg.class = i
				create = true
			}
		}
	}
	imgui.EndChild()
	imgui.PopStyleColor()

	imgui.Dummy({0, 6})
	if imgui.IsKeyPressed(.Enter) || imgui.IsKeyPressed(.KeypadEnter) do create = true
	imgui.SetCursorPosX(imgui.GetWindowWidth() - 16 - 120 - 90 - UI_SPACE)
	if UI_Button("Cancel", "newresource.cancel", {90, 30}) || imgui.IsKeyPressed(.Escape) {
		rdlg.open = false
		imgui.CloseCurrentPopup()
	}
	imgui.SameLine(0, UI_SPACE)
	canCreate := name != "" && rdlg.class < len(rdlg.classes)
	if UI_PrimaryButton("Create", "newresource.create", {120, 30}) do create = true
	if create && canCreate {
		class := rdlg.classes[rdlg.class]
		rdlg.open = false
		imgui.CloseCurrentPopup()
		Editor_NewResource(state, name, class)
	}
}
