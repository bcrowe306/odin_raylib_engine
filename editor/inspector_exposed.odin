package editor

import "core:c"
import "core:fmt"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Exposed properties (#85): a component's root lists properties of its nodes
// (componentExposed, component_exposed.odin). An instance's root shows them
// in an "Instance" section; editing one edits that node (an ordinary
// override). In the component document, right-click a property's label >
// Expose on Instances; the root's "Exposed on Instances" section names and
// removes them.
// ============================================================================

// Editor_ComponentDocRoot: the component's node in a component document
// (nil: not one).
Editor_ComponentDocRoot :: proc(state: ^EditorState, scene: ^e.Scene) -> ^e.Node {
	if !Editor_IsComponentDoc(state, scene) || Editor_IsCustomNodeDoc(state, scene) do return nil
	kids := e.GetChildrenView(scene.manager, scene.rootNode)
	return kids[0] if len(kids) > 0 else nil
}

// exposed_label: an entry's label (none set: the property's name, after
// the node's name for a child).
exposed_label :: proc(manager: ^e.NodeManager, root: ^e.Node, x: e.Component_Exposed) -> string {
	if x.label != "" do return x.label
	name := pretty_name(strings.trim_prefix(x.property, "script."))
	if x.uid == "." do return name
	if n := e.Node_FindByUidPath(manager, root, x.uid); n != nil do return fmt.tprintf("%s %s", n.name, name)
	return name
}

// Inspector_InstanceSection: an instance root's exposed properties.
Inspector_InstanceSection :: proc(state: ^EditorState, node: ^e.Node) {
	if node.componentPath == "" || node.componentMissing || len(node.componentExposed) == 0 do return
	if !UI_SectionHeader("Instance") do return
	if !UI_BeginProps("##instance") do return
	defer UI_EndProps()
	mgr := state.activeScene.manager
	for x, i in node.componentExposed {
		imgui.PushIDInt(c.int(i))
		defer imgui.PopID()
		label := exposed_label(mgr, node, x)
		target := e.Node_FindByUidPath(mgr, node, x.uid)
		if target == nil || !exposed_row(state, target, x.property, label) {
			UI_PropLabel(label)
			UI_DimText("(not in the component any more)")
			UI_Tooltip(fmt.tprintf("%s of node %s", x.property, x.uid))
		}
	}
}

// exposed_row draws a node's property as a row (false: it has no such
// property; nothing drawn).
@(private = "file")
exposed_row :: proc(state: ^EditorState, target: ^e.Node, prop, label: string) -> bool {
	id := fmt.tprintf("insp.exposed:%s", label)
	if strings.has_prefix(prop, "script.") {
		if target.scriptInstance == nil do return false
		inst := cast(^e.ScriptInstance)target.scriptInstance
		name := prop[len("script."):]
		if !(name in inst.properties) do return false
		t := Script_PropsTarget{
			mod         = state.game.scriptManager.modules[e.ScriptVFS_NormalizePath(inst.modulePath)] or_else nil,
			modulePath  = inst.modulePath,
			values      = &inst.properties,
			owner       = target,
			idPrefix    = "insp.exposed-script",
			data        = inst,
			set         = proc(state: ^EditorState, t: ^Script_PropsTarget, name: string, val: e.ScriptValue) {
				e.ScriptInstance_SetProperty((^e.ScriptInstance)(t.data), name, val, &state.game.scriptManager)
			},
			record_undo = proc(state: ^EditorState, t: ^Script_PropsTarget, label: string) {Editor_RecordUndo(state, label)},
		}
		script_prop_one(state, &t, name, label)
		return true
	}
	p, ok := e.Node_FindProperty(target, prop) // (the Transform rows too)
	if !ok || p.runtime do return false
	prop_label(label, target, prop_script_path(target, p), prop_lua_value(p))
	at := imgui.GetCursorScreenPos()
	property_widget(state, target, p, false)
	Drive_ItemRect(id, {at.x, at.y}, {at.x + field_width(), at.y + imgui.GetFrameHeight()}, true)
	return true
}

// Inspector_ExposedList: a component document root's exposed properties:
// their labels, and Stop Exposing.
Inspector_ExposedList :: proc(state: ^EditorState, node: ^e.Node) {
	root := Editor_ComponentDocRoot(state, state.activeScene)
	if root == nil || node != root || len(root.componentExposed) == 0 do return
	if !UI_SectionHeader("Exposed on Instances") do return
	if !UI_BeginProps("##exposedlist") do return
	defer UI_EndProps()
	mgr := state.activeScene.manager
	remove := -1
	for x, i in root.componentExposed {
		imgui.PushIDInt(c.int(i))
		defer imgui.PopID()
		target := e.Node_FindByUidPath(mgr, root, x.uid)
		UI_PropLabel(fmt.tprintf("%s · %s", target.name if target != nil else "(missing)", pretty_name(strings.trim_prefix(x.property, "script."))))
		UI_Tooltip(fmt.tprintf("%s of node %s", x.property, x.uid))
		buf: [128]u8
		copy(buf[:len(buf) - 1], x.label)
		imgui.SetNextItemWidth(imgui.GetContentRegionAvail().x - 30)
		if imgui.InputTextWithHint("##label", fmt.ctprintf("%s", exposed_label(mgr, root, {uid = x.uid, property = x.property})), cstring(raw_data(buf[:])), len(buf), {}) {
			root.componentExposed[i].label = strings.clone(string(cstring(raw_data(buf[:]))), root.allocator)
		}
		undo_on_activate(state, "Rename exposed property")
		Drive_Item(fmt.tprintf("insp.exposed-label:%d", i))
		UI_Tooltip("The label on instances (empty: the property's name)")
		imgui.SameLine(0, 4)
		if UI_IconButton(ICON_FA_XMARK, fmt.tprintf("insp.exposed-remove:%d", i), "Stop exposing this property", size = 24) do remove = i
	}
	if remove >= 0 {
		Editor_RecordUndo(state, "Stop exposing")
		e.Component_Unexpose(root, remove)
	}
}

// exposable: can the Instance section draw this row (exposed_row)?
@(private = "file")
exposable :: proc(node: ^e.Node, path: string) -> bool {
	if strings.has_prefix(path, "script.") do return node.scriptInstance != nil
	p, ok := e.Node_FindProperty(node, path) // (the Transform rows too)
	return ok && !p.runtime
}

// exposed_menu: Expose on Instances / Stop Exposing in a property label's
// menu, in a component document.
exposed_menu :: proc(state: ^EditorState, node: ^e.Node, path: string) {
	root := Editor_ComponentDocRoot(state, state.activeScene)
	if root == nil || !exposable(node, path) do return
	mgr := state.activeScene.manager
	inside := false
	for n := node; n != nil; n = e.GetParent(mgr, n) do if n == root {inside = true; break}
	if !inside do return
	uidPath := e.Node_UidPathBelow(mgr, node, root)
	i := e.Component_ExposedIndex(root, uidPath, path) if uidPath != "" else -1
	if i < 0 {
		if imgui.MenuItem(fmt.ctprintf("%s  Expose on Instances", ICON_FA_SLIDERS)) {
			Editor_RecordUndo(state, "Expose property")
			e.Component_Expose(root, e.Node_UidPathBelow(mgr, node, root, assign = true), path, "")
		}
		Drive_Item("ctx:expose-property")
		UI_Tooltip("Show this property on the root of every instance (edited as an override there)")
	} else {
		if imgui.MenuItem(fmt.ctprintf("%s  Stop Exposing", ICON_FA_XMARK)) {
			Editor_RecordUndo(state, "Stop exposing")
			e.Component_Unexpose(root, i)
		}
		Drive_Item("ctx:unexpose-property")
	}
	imgui.Separator()
}
