package editor

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// New Component (#192): a component made from scratch - a name and its root
// node's type; writes components/<name>.component.json and opens it to build
// in. From the Assets + menu, Components' right-click menus and the palette.
// ============================================================================

@(private = "file")
ncd: struct {
	open:   bool,
	focus:  bool,
	name:   [64]u8,
	root:   string, // a node type name (NODE_CATALOG)
	filter: [64]u8,
}

NewComponentDialog_Open :: proc(state: ^EditorState) {
	ncd = {}
	ncd.open, ncd.focus = true, true
	ncd.root = "Node"
	copy(ncd.name[:], "NewComponent")
}

@(private = "file")
root_label :: proc(typeName: string) -> string {
	for entry in NODE_CATALOG do if entry.typeName == typeName do return fmt.tprintf("%s  %s (%s)", entry.icon, entry.name, typeName)
	return typeName
}

NewComponentDialog_Render :: proc(state: ^EditorState) {
	TITLE :: "New Component###NewComponentDialog"
	if ncd.open && !imgui.IsPopupOpen(TITLE) do imgui.OpenPopup(TITLE)
	io := imgui.GetIO()
	imgui.SetNextWindowSize({520, 0}, .Appearing)
	imgui.SetNextWindowPos({io.DisplaySize.x * 0.5, io.DisplaySize.y * 0.5}, .Appearing, {0.5, 0.5})
	imgui.PushStyleVarImVec2(.WindowPadding, {16, 14})
	defer imgui.PopStyleVar()
	if !imgui.BeginPopupModal(TITLE, &ncd.open, {.NoResize, .NoTitleBar, .AlwaysAutoResize}) do return
	defer imgui.EndPopup()

	UI_PanelTitle(ICON_FA_CUBES, "New Component")
	UI_DimText("A reusable piece of a scene: its root node here, then build it (children, script, settings) in its own tab.")
	imgui.Dummy({0, 6})

	field_label("Name", 90)
	if ncd.focus {
		imgui.SetKeyboardFocusHere()
		ncd.focus = false
	}
	imgui.SetNextItemWidth(-1)
	enter := imgui.InputTextWithHint("##nc_name", "Enemy", cstring(raw_data(ncd.name[:])), len(ncd.name), {.AutoSelectAll, .EnterReturnsTrue})
	Drive_Item("newcomp.name")
	name := strings.trim_space(string(cstring(raw_data(ncd.name[:]))))

	field_label("Root node", 90)
	imgui.SetNextItemWidth(-1)
	if imgui.BeginCombo("##nc_root", strings.clone_to_cstring(root_label(ncd.root), context.temp_allocator), {.HeightLarge}) {
		imgui.SetNextItemWidth(-1)
		imgui.InputTextWithHint("##nc_root_filter", "Search types", cstring(raw_data(ncd.filter[:])), len(ncd.filter), {})
		filter := strings.to_lower(strings.trim_space(string(cstring(raw_data(ncd.filter[:])))), context.temp_allocator)
		category := ""
		for entry in NODE_CATALOG {
			if filter != "" && !strings.contains(strings.to_lower(entry.name, context.temp_allocator), filter) && !strings.contains(strings.to_lower(entry.typeName, context.temp_allocator), filter) do continue
			if entry.category != category {
				category = entry.category
				UI_DimText(category)
			}
			if imgui.Selectable(fmt.ctprintf("%s  %s##ncr_%s", entry.icon, entry.name, entry.name), ncd.root == entry.typeName) do ncd.root = entry.typeName
			Drive_Item(fmt.tprintf("newcomp.root:%s", entry.typeName))
			if entry.description != "" do UI_Tooltip(entry.description)
		}
		imgui.EndCombo()
	}
	Drive_Item("newcomp.root")
	UI_Tooltip("The component's top node: e.g. a Kinematic Body for an enemy, an Area for a pickup, a plain Node to group")

	// Where it goes (never over an existing component: Enemy_2, ...).
	rel := Component_FreePath(state, name) if name != "" else ""
	imgui.Dummy({0, 4})
	if name == "" {
		imgui.PushStyleColorImVec4(.Text, UI_WARNING)
		imgui.TextUnformatted("Give it a name.")
		imgui.PopStyleColor()
	} else {
		UI_DimText(fmt.tprintf("Saved as %s", rel))
	}
	imgui.Dummy({0, 6})

	if UI_Button("Cancel", "newcomp.cancel", {100, 0}) || imgui.IsKeyPressed(.Escape) {
		ncd.open = false
		imgui.CloseCurrentPopup()
		return
	}
	imgui.SameLine()
	if name == "" do imgui.BeginDisabled(true)
	create := UI_PrimaryButton(fmt.tprintf("%s  Create", ICON_FA_PLUS), "newcomp.create", {120, 0}) || (enter && name != "")
	if name == "" do imgui.EndDisabled()
	if create && name != "" {
		if Editor_NewComponent(state, name, ncd.root) != "" {
			ncd.open = false
			imgui.CloseCurrentPopup()
		}
	}
}

// Editor_NewComponent writes a component of a root type (at a free name) and
// opens it; returns its path ("" on failure).
Editor_NewComponent :: proc(state: ^EditorState, name, rootType: string) -> string {
	json := e.Component_NewJSON(rootType, name, context.temp_allocator)
	if json == "" {
		Editor_Log(state, .Error, "%s is not a node type", rootType)
		return ""
	}
	_ = os.make_directory_all(Editor_ComponentsDir(state))
	rel := Component_FreePath(state, name)
	full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
	if os.write_entire_file(full, transmute([]u8)json) != nil {
		Editor_Log(state, .Error, "Could not write %s", rel)
		return ""
	}
	Editor_InvalidateProjectFiles() // the asset lists rescan
	Lua_MarkProjectTypesDirty()
	Editor_Log(state, .Info, "New component %s", rel)
	Editor_OpenComponent(state, rel)
	return rel
}
