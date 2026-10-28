package editor

import "core:fmt"
import "core:slice"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Scene tree tools:
//   - Filter terms (all must match): plain text = the name, "#enemy" = a
//     tag, "t:sprite" / "type:TextureNode" = the node type (type name or
//     its Add Node name).
//   - Tags (groups) in the Inspector: chips (click to remove), add by typing
//     or from the tags used in the scene; applied to the whole selection.
//   - Reorder by drag: drop on the top / bottom edge of a row to place the
//     node before / after it (the middle re-parents, as before).
//   - Across scenes: pasting into another scene keeps the nodes' world
//     positions; Copy / Move to Scene on the context menu.
// ============================================================================

// node_matches: every filter term matches the node.
node_matches :: proc(node: ^e.Node, filter: string) -> bool {
	if filter == "" do return true
	for term in strings.fields(filter, context.temp_allocator) {
		switch {
		case strings.has_prefix(term, "#"):
			want := term[1:]
			hit := false
			for t in node.tags do if strings.contains(strings.to_lower(t, context.temp_allocator), want) do hit = true
			if !hit do return false
		case strings.has_prefix(term, "t:") || strings.has_prefix(term, "type:"):
			want := term[strings.index_byte(term, ':') + 1:]
			typeName := e.Node_TypeName(node)
			label, _ := node_type_description(typeName)
			if !strings.contains(strings.to_lower(typeName, context.temp_allocator), want) &&
			   !strings.contains(strings.to_lower(label, context.temp_allocator), want) {
				return false
			}
		case:
			if !strings.contains(strings.to_lower(node.name, context.temp_allocator), term) do return false
		}
	}
	return true
}

// Editor_InsertNodeAt moves `node` next to `target` (before or after it),
// under target's parent; keeps its world position. One undo step.
Editor_InsertNodeAt :: proc(state: ^EditorState, node, target: ^e.Node, after: bool) -> bool {
	if state.activeScene == nil || node == nil || target == nil || node == target do return false
	mgr := state.activeScene.manager
	parent := e.GetParent(mgr, target)
	if parent == nil do return false
	for p := target; p != nil; p = e.GetParent(mgr, p) do if p == node do return false // no cycles
	// Inside an instance, children can change order (an override, #78) but
	// not parent.
	reorder := e.GetParent(mgr, node) == parent
	if !reorder && (Editor_NodeLocked(state, node) || Editor_NodeLocked(state, target)) {
		Editor_Log(state, .Warn, "Nodes inside a component keep their parent: move them in the component")
		return false
	}
	Editor_RecordUndo(state, fmt.tprintf("Move %s", node.name))
	if old := e.GetParent(mgr, node); old != parent {
		snap := NodeRefs_Capture(state) // scripts / node properties pointing into it
		world := node.globalPosition
		if old != nil do e.RemoveChild(mgr, old, node)
		e.AddChild(mgr, parent, node)
		node.position = Editor_WorldToLocal(parent, world)
		node.name = strings.clone(Editor_UniqueChildName(state, parent, node.name, node), node.allocator)
		NodeRefs_AfterChange(state, snap)
	}
	index := 0
	for c in e.GetChildrenView(mgr, parent) {
		if c == node do continue
		if c == target do break
		index += 1
	}
	e.MoveChild(mgr, parent, node, index + (1 if after else 0))
	e.Node_SetGlobalPositions(mgr, state.activeScene.rootNode)
	return true
}

// scene_tags: every tag used in the active scene (sorted).
scene_tags :: proc(state: ^EditorState) -> []string {
	out := make([dynamic]string, context.temp_allocator)
	if state.activeScene == nil do return out[:]
	for n in state.activeScene.manager.nodes {
		if n == nil do continue
		for t in n.tags do if !slice.contains(out[:], t) do append(&out, t)
	}
	slice.sort(out[:])
	return out[:]
}

@(private = "file")
tagInput: [64]u8

// Inspector_Tags: the selected node's tags (the whole selection's edits).
Inspector_Tags :: proc(state: ^EditorState, node: ^e.Node) {
	if !UI_SectionHeader("Tags") do return
	targets := multi_selection(state)
	if len(targets) == 0 do targets = {node}
	remove := ""
	for t, i in node.tags {
		if i > 0 do imgui.SameLine(0, 4)
		if imgui.GetContentRegionAvail().x < 60 do imgui.NewLine()
		imgui.PushStyleColorImVec4(.Button, UI_ACCENT_SOFT)
		imgui.PushStyleColorImVec4(.Text, UI_ACCENT)
		if imgui.SmallButton(fmt.ctprintf("#%s  %s##tag%d", t, ICON_FA_XMARK, i)) do remove = t
		imgui.PopStyleColor(2)
		UI_Tooltip("Remove the tag")
		Drive_Item(fmt.tprintf("insp.tag:%s", t))
	}
	if remove != "" {
		Editor_RecordUndo(state, "Remove tag")
		r := strings.clone(remove, context.temp_allocator)
		for n in targets do e.Node_RemoveTag(n, r)
		Lua_MarkProjectTypesDirty()
	}
	add := ""
	imgui.SetNextItemWidth(imgui.GetContentRegionAvail().x - 34)
	if imgui.InputTextWithHint("##taginput", "Add a tag (Enter)", cstring(raw_data(tagInput[:])), len(tagInput), {.EnterReturnsTrue}) {
		add = strings.clone(strings.trim_space(string(cstring(raw_data(tagInput[:])))), context.temp_allocator)
		tagInput = {}
	}
	Drive_Item("insp.tag.input")
	imgui.SameLine(0, 4)
	known := scene_tags(state)
	if imgui.BeginCombo("##tagpick", nil, {.NoPreview, .PopupAlignLeft}) {
		if len(known) == 0 do UI_DimText("No tags in this scene yet")
		for t in known {
			if imgui.Selectable(fmt.ctprintf("#%s", t), e.Node_HasTag(node, t)) do add = t
			Drive_Item(fmt.tprintf("pick:#%s", t))
		}
		imgui.EndCombo()
	}
	UI_Tooltip("Tags used in this scene")
	Drive_Item("insp.tag.pick")
	if add != "" {
		Editor_RecordUndo(state, "Add tag")
		for n in targets do e.Node_AddTag(n, add)
		Lua_MarkProjectTypesDirty()
	}
}

// --- across scenes -----------------------------------------------------------------------

// Where the clipboard's nodes came from: pasting into another scene keeps
// their world positions.
nodeClipboardScene: string
nodeClipboardWorld: [dynamic][2]f32

Clipboard_NoteSource :: proc(state: ^EditorState, roots: []^e.Node) {
	delete(nodeClipboardScene)
	nodeClipboardScene = strings.clone(state.activeScenePath)
	clear(&nodeClipboardWorld)
	for n in roots do append(&nodeClipboardWorld, n.globalPosition)
}

// Clipboard_FromOtherScene: the copied nodes came from another scene.
Clipboard_FromOtherScene :: proc(state: ^EditorState) -> bool {
	return nodeClipboardScene != "" && nodeClipboardScene != state.activeScenePath
}

// Editor_SendSelectionToScene copies (or moves) the selection into another
// project scene, at the same world positions, and opens that scene.
Editor_SendSelectionToScene :: proc(state: ^EditorState, relPath: string, move: bool) {
	if len(Editor_SelectionRoots(state)) == 0 || relPath == state.activeScenePath do return
	if move do Editor_CutSelection(state)
	else do Editor_CopySelection(state)
	if !Editor_OpenScene(state, relPath) do return
	Editor_PasteNodes(state)
}

// SendToScene_Menu: the context menu's Copy / Move to Scene submenus.
SendToScene_Menu :: proc(state: ^EditorState, move: bool) {
	label := "Move to Scene" if move else "Copy to Scene"
	open := imgui.BeginMenu(fmt.ctprintf("%s  %s", ICON_FA_ARROW_RIGHT if move else ICON_FA_CLONE, label))
	Drive_Item(fmt.tprintf("ctx:%s", "move-to-scene" if move else "copy-to-scene"))
	if !open do return
	defer imgui.EndMenu()
	any := false
	for rel in Editor_ListProjectFiles(state, "", {".scene.json"}) {
		if rel == state.activeScenePath do continue
		any = true
		if imgui.MenuItem(strings.clone_to_cstring(rel, context.temp_allocator)) {
			Editor_SendSelectionToScene(state, strings.clone(rel, context.temp_allocator), move)
		}
		Drive_Item(fmt.tprintf("ctx:%s:%s", "move-to" if move else "copy-to", rel))
	}
	if !any do UI_DimText("No other scenes")
}
