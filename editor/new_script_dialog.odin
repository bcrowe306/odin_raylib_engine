package editor

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// New Script dialog: a file name and a template (engine/script_templates.odin
// - Empty, Platformer / Top-Down Character, Enemy Patrol, UI Menu, Pickup,
// Door / Trigger) with a preview. Opened from Assets (+, menus), the command
// palette, and a node's New Script (Inspector, scene tree), which attaches
// the new script to that node; the template that suits the node's type is
// picked first.
// ============================================================================

@(private = "file")
New_Script_Dialog :: struct {
	open:     bool,
	name:     [64]u8,
	template: int,
	node:     ^e.Node, // attach the new script to it (nil = none)
	focus:    bool,
}

@(private = "file")
dlg: New_Script_Dialog

// NewScriptDialog_Open opens the dialog; with a node, the script is attached
// to it and named after it.
NewScriptDialog_Open :: proc(state: ^EditorState, node: ^e.Node = nil, template := "", name := "") {
	dlg = {}
	dlg.open = true
	dlg.focus = true
	dlg.node = node
	base := "new_script"
	id := "empty"
	if node != nil {
		if s := strings.to_snake_case(node.name, context.temp_allocator); s != "" do base = s
		id = e.Script_TemplateFor(node.typeId)
	}
	if template != "" do id = template
	if name != "" do base = name
	copy(dlg.name[:len(dlg.name) - 1], base)
	for tp, i in e.Script_Templates() do if tp.id == id do dlg.template = i
}

NewScriptDialog_Render :: proc(state: ^EditorState) {
	if dlg.open && !imgui.IsPopupOpen("New Script###NewScriptDialog") do imgui.OpenPopup("New Script###NewScriptDialog")
	io := imgui.GetIO()
	imgui.SetNextWindowSize({820, 520}, .Appearing)
	imgui.SetNextWindowPos({io.DisplaySize.x * 0.5, io.DisplaySize.y * 0.5}, .Appearing, {0.5, 0.5})
	imgui.PushStyleVarImVec2(.WindowPadding, {16, 14})
	defer imgui.PopStyleVar()
	if !imgui.BeginPopupModal("New Script###NewScriptDialog", &dlg.open, {.NoResize, .NoTitleBar}) do return

	UI_PanelTitle(ICON_FA_FILE_CODE, "New Script")
	if dlg.node != nil {
		imgui.SameLine(0, UI_SPACE)
		UI_DimText(fmt.tprintf("attached to %s", dlg.node.name))
	}
	imgui.Dummy({0, 4})

	// File name: scripts/<name>.lua (a taken name gets _2, _3...).
	imgui.AlignTextToFramePadding()
	imgui.TextUnformatted("scripts/")
	imgui.SameLine(0, 2)
	if dlg.focus {
		imgui.SetKeyboardFocusHere()
		dlg.focus = false
	}
	imgui.SetNextItemWidth(260)
	imgui.InputText("##newscript_name", cstring(raw_data(dlg.name[:])), len(dlg.name), {.CharsNoBlank, .AutoSelectAll})
	Drive_Item("newscript.name")
	imgui.SameLine(0, 2)
	imgui.TextUnformatted(".lua")
	name := strings.trim_space(string(cstring(raw_data(dlg.name[:]))))
	name = strings.trim_suffix(name, ".lua")
	if name != "" {
		full, _ := filepath.join({state.projectPath, "scripts", fmt.tprintf("%s.lua", name)}, context.temp_allocator)
		if os.exists(full) {
			imgui.SameLine(0, UI_SPACE)
			UI_DimText(fmt.tprintf("exists - creates %s_2.lua", name))
		}
	}
	imgui.Dummy({0, 6})

	templates := e.Script_Templates()
	if imgui.IsKeyPressed(.DownArrow) do dlg.template = (dlg.template + 1) % len(templates)
	if imgui.IsKeyPressed(.UpArrow) do dlg.template = (dlg.template + len(templates) - 1) % len(templates)
	listH := imgui.GetContentRegionAvail().y - 44
	create := false
	imgui.PushStyleColorImVec4(.ChildBg, UI_BG_APP)
	if imgui.BeginChild("##templates", {250, listH}, {}, {}) {
		for tp, i in templates {
			suits := dlg.node != nil && template_suits(tp, dlg.node.typeId)
			label := fmt.ctprintf("   %s  %s%s###tpl_%s", ICON_FA_FILE_CODE, tp.label, "  " + ICON_FA_STAR if suits else "", tp.id)
			if imgui.Selectable(label, dlg.template == i, {}, {0, 28}) do dlg.template = i
			Drive_Item(fmt.tprintf("newscript.template:%s", tp.id))
			if suits do UI_Tooltip("Made for this node's type")
			if imgui.IsItemHovered() && imgui.IsMouseDoubleClicked(.Left) {
				dlg.template = i
				create = true
			}
		}
	}
	imgui.EndChild()
	imgui.PopStyleColor()

	imgui.SameLine(0, 16)
	if imgui.BeginChild("##template_detail", {0, listH}, {}, {}) {
		tp := templates[dlg.template]
		imgui.PushStyleColorImVec4(.Text, UI_ACCENT)
		imgui.PushFont(GlobalFonts.semibold)
		imgui.TextUnformatted(strings.clone_to_cstring(tp.label, context.temp_allocator))
		imgui.PopFont()
		imgui.PopStyleColor()
		imgui.TextWrapped("%s", strings.clone_to_cstring(tp.description, context.temp_allocator))
		imgui.Dummy({0, 4})
		// Preview with this file's names.
		cls := script_class_name(name if name != "" else "new_script")
		text, _ := strings.replace_all(tp.text, "$CLASS$", cls, context.temp_allocator)
		text, _ = strings.replace_all(text, "$NAME$", name, context.temp_allocator)
		imgui.PushStyleColorImVec4(.ChildBg, UI_BG_APP)
		if imgui.BeginChild("##template_preview", {0, 0}, {.Borders}, {.HorizontalScrollbar}) {
			if GlobalFonts.mono != nil do imgui.PushFont(GlobalFonts.mono)
			imgui.PushStyleColorImVec4(.Text, UI_TEXT_DIM)
			imgui.TextUnformatted(strings.clone_to_cstring(text, context.temp_allocator))
			imgui.PopStyleColor()
			if GlobalFonts.mono != nil do imgui.PopFont()
		}
		imgui.EndChild()
		imgui.PopStyleColor()
	}
	imgui.EndChild()

	imgui.Dummy({0, 6})
	if imgui.IsKeyPressed(.Enter) || imgui.IsKeyPressed(.KeypadEnter) do create = true
	imgui.SetCursorPosX(imgui.GetWindowWidth() - 16 - 120 - 90 - UI_SPACE)
	if UI_Button("Cancel", "newscript.cancel", {90, 30}) || imgui.IsKeyPressed(.Escape) {
		dlg.open = false
		imgui.CloseCurrentPopup()
	}
	imgui.SameLine(0, UI_SPACE)
	if UI_PrimaryButton("Create", "newscript.create", {120, 30}) do create = true
	if create && name != "" {
		tp := templates[dlg.template]
		node := dlg.node
		dlg.open = false
		imgui.CloseCurrentPopup()
		if node != nil {
			Editor_RecordUndo(state, "Attach script")
			if rel := Editor_NewScriptForNode(state, node, tp.id, name); rel != "" {
				node.gameContext = &state.game.gameContext
				if e.Script_AttachToNode(node, rel, nil, &state.game.scriptManager) != nil {
					Editor_Log(state, .Info, "Attached %s to %s", rel, node.name)
				} else {
					Editor_Log(state, .Error, "Could not attach %s", rel)
				}
			}
		} else {
			Editor_NewScript(state, name, tp.text)
		}
	}
	imgui.EndPopup()
}

@(private = "file")
template_suits :: proc(tp: e.Script_Template, t: typeid) -> bool {
	for s in tp.suits do if s == t do return true
	return false
}
