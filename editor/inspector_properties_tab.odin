package editor

import "core:fmt"
import e "../engine"
import buf "../odin_editor/buffer"
import imgui "lib/imgui"

// ============================================================================
// The Inspector's tabs (#208): Node (the node's own settings) and Properties
// - its script's properties, added with + (a dialog writes the entry into
// the script), edited or removed from a property's right-click menu. Without
// a script, + makes one.
// ============================================================================

Inspector_Tab :: enum {
	Node,
	Properties,
}

inspectorTab: Inspector_Tab
inspectorTabRequest: Maybe(Inspector_Tab)

// Inspector_ScriptTarget: a node's script properties to edit (ok = false
// without a script).
Inspector_ScriptTarget :: proc(state: ^EditorState, node: ^e.Node) -> (Script_PropsTarget, bool) {
	if node == nil || node.scriptInstance == nil do return {}, false
	inst := cast(^e.ScriptInstance)node.scriptInstance
	sm := &state.game.scriptManager
	return Script_PropsTarget{
		mod         = sm.modules[e.ScriptVFS_NormalizePath(inst.modulePath)] or_else nil,
		modulePath  = inst.modulePath,
		values      = &inst.properties,
		owner       = node,
		idPrefix    = "insp.script",
		data        = inst,
		set         = proc(state: ^EditorState, t: ^Script_PropsTarget, name: string, val: e.ScriptValue) {
			e.ScriptInstance_SetProperty((^e.ScriptInstance)(t.data), name, val, &state.game.scriptManager)
		},
		record_undo = proc(state: ^EditorState, t: ^Script_PropsTarget, label: string) {Editor_RecordUndo(state, label)},
	}, true
}

// Inspector_Tabs draws the Node / Properties tabs; true when Node is shown.
Inspector_Tabs :: proc(state: ^EditorState, node: ^e.Node) -> bool {
	n := 0
	if inst := cast(^e.ScriptInstance)node.scriptInstance; inst != nil do n = len(inst.properties)
	req, has := inspectorTabRequest.?
	inspectorTabRequest = nil
	flags :: proc(t, req: Inspector_Tab, has: bool) -> imgui.TabItemFlags {return {.SetSelected} if has && req == t else {}}
	if imgui.BeginTabBar("##insp_tabs", {}) {
		if imgui.BeginTabItem(fmt.ctprintf("%s  Node###insp_node", ICON_FA_CIRCLE_DOT), nil, flags(.Node, req, has)) {
			inspectorTab = .Node
			imgui.EndTabItem()
		}
		Drive_Item("insp.tab:node")
		if imgui.BeginTabItem(fmt.ctprintf("%s  Properties%s###insp_props", ICON_FA_SLIDERS, fmt.tprintf(" (%d)", n) if n > 0 else ""), nil, flags(.Properties, req, has)) {
			inspectorTab = .Properties
			imgui.EndTabItem()
		}
		Drive_Item("insp.tab:properties")
		UI_Tooltip("Your properties for this node (its script's): add, edit, remove")
		imgui.EndTabBar()
	}
	return inspectorTab == .Node
}

// Inspector_PropertiesTab: the script's properties, + to add one.
Inspector_PropertiesTab :: proc(state: ^EditorState, node: ^e.Node) {
	imgui.Dummy({0, 2})
	if UI_PrimaryButton(fmt.tprintf("%s  Add Property", ICON_FA_PLUS), "insp.prop-add", {-1, 0}) do PropertyDialog_Open(state, node)
	UI_Tooltip("A property you set per node in the Inspector: a number, text, colour, asset, node, resource, list...")
	target, ok := Inspector_ScriptTarget(state, node)
	if !ok {
		imgui.Dummy({0, 4})
		imgui.PushTextWrapPos(0)
		imgui.PushStyleColorImVec4(.Text, UI_TEXT_FAINT)
		imgui.TextWrapped("No properties yet. Add one: a script is made for this node to hold it (its values are set here, per node; self.<name> in the script).")
		imgui.PopStyleColor()
		imgui.PopTextWrapPos()
		Drive_Item("insp.props-empty")
		return
	}
	rel := asset_rel_editor(state, target.modulePath)
	imgui.PushTextWrapPos(0)
	imgui.PushStyleColorImVec4(.Text, UI_TEXT_DIM)
	imgui.TextWrapped("%s", fmt.ctprintf("From %s - right-click a name: edit, remove", rel))
	imgui.PopStyleColor()
	imgui.PopTextWrapPos()
	if UI_BeginProps("##props_tab") {
		if script_props_editor(state, &target) == 0 {
			UI_PropLabel("")
			UI_DimText("None yet: Add Property.")
		}
		UI_EndProps()
	}
}

// Inspector_PropertyMenu: Edit / Remove in a script property's right-click
// menu (the ones its script declares; inherited ones are its base's).
Inspector_PropertyMenu :: proc(state: ^EditorState, node: ^e.Node, name: string) {
	inst := cast(^e.ScriptInstance)node.scriptInstance
	if inst == nil do return
	rel := asset_rel_editor(state, inst.modulePath)
	own := true
	if doc := code_doc_for_script(state, rel, false); doc != nil {
		text := buf.buffer_to_string(&doc.buffer, context.temp_allocator)
		own = Prop_Declared(text, Script_ClassName(text), name)
	}
	if imgui.MenuItem(fmt.ctprintf("%s  Edit Property...", ICON_FA_PEN), nil, false, own) do PropertyDialog_Open(state, node, name)
	Drive_Item("ctx:prop-edit")
	if !own do UI_Tooltip("Declared in the script it extends: edit it there")
	if imgui.MenuItem(fmt.ctprintf("%s  Remove Property...", ICON_FA_TRASH), nil, false, own) do PropertyDialog_Remove(state, node, name)
	Drive_Item("ctx:prop-remove")
	imgui.Separator()
}
