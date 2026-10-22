package editor

import "core:c"
import "core:fmt"
import "core:math"
import "core:os"
import "core:path/filepath"
import "core:strings"
import rl "vendor:raylib"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Right Sidebar: Clean Hierarchy (No bullets / trailing arrows) & Inspector
// ============================================================================

SceneInspector_Render :: proc(state: ^EditorState) {
	SceneHierarchy_RenderWindow(state)
	PropertyInspector_RenderWindow(state)
}

// ----------------------------------------------------------------------------
// 1. Scene tree: flat rows with type icons; drag a row onto another to
//    re-parent (onto empty space = root); right-click for actions; the eye
//    toggles visibility; double-click frames the node in the viewport.
// ----------------------------------------------------------------------------

hierarchyFilterBuf: [128]u8
hierarchyPendingFocus: ^e.Node

SceneHierarchy_RenderWindow :: proc(state: ^EditorState) {
	defer imgui.End()
	if !imgui.Begin("Scene###SceneHierarchyWindow") do return
	if state.activeScene == nil {
		UI_DimText("No scene open")
		return
	}

	// Header: scene name (+ modified dot) and actions on the right.
	modified := Editor_SceneIsModifiedCached(state, state.activeScene)
	title := filepath.base(state.activeScenePath) if state.activeScenePath != "" else state.activeScene.name
	UI_PanelTitle(ICON_FA_LAYER_GROUP, title)
	if modified {
		imgui.SameLine(0, 6)
		imgui.PushStyleColorImVec4(.Text, UI_WARNING)
		imgui.PushFont(GlobalFonts.small)
		imgui.TextUnformatted(ICON_FA_CIRCLE)
		imgui.PopFont()
		imgui.PopStyleColor()
		UI_Tooltip("Unsaved changes (Ctrl+S to save)")
	}
	canModify := state.selectedNode != nil && state.selectedNode != state.activeScene.rootNode
	imgui.SameLine(imgui.GetWindowWidth() - 3 * 30 - 18)
	if UI_IconButton(ICON_FA_PLUS, "hier.add", "Add node (Ctrl+A)", size = 28) do AddNodeDialog_Open()
	imgui.SameLine(0, 2)
	if !canModify do imgui.BeginDisabled(true)
	if UI_IconButton(ICON_FA_COPY, "hier.duplicate", "Duplicate (Ctrl+D)", size = 28) do SceneHierarchy_DuplicateSelected(state)
	imgui.SameLine(0, 2)
	if UI_IconButton(ICON_FA_TRASH, "hier.delete", "Delete (Del)", size = 28) do SceneHierarchy_DeleteSelected(state)
	if !canModify do imgui.EndDisabled()

	imgui.SetNextItemWidth(-1)
	imgui.InputTextWithHint("##hierfilter", fmt.ctprintf("%s  Filter nodes", ICON_FA_MAGNIFYING_GLASS), cstring(raw_data(hierarchyFilterBuf[:])), len(hierarchyFilterBuf), {})
	Drive_Item("hier.filter")
	imgui.Dummy({0, 2})

	filter := strings.to_lower(string(cstring(raw_data(hierarchyFilterBuf[:]))), context.temp_allocator)
	imgui.PushStyleVarImVec2(.ItemSpacing, {4, 2})
	imgui.PushStyleVarImVec2(.FramePadding, {6, 4})
	if imgui.BeginChild("##tree", {0, 0}, {}, {}) {
		root := state.activeScene.rootNode
		if root != nil {
			children := e.GetChildren(state.activeScene.manager, root)
			defer delete(children)
			for child in children do SceneHierarchy_RenderNodeTree(state, child, "", filter)
			// Drop on empty space: move to the root.
			imgui.Dummy({imgui.GetContentRegionAvail().x, max(imgui.GetContentRegionAvail().y, 40)})
			Drive_Item("hier.empty")
			if imgui.BeginDragDropTarget() {
				if payload := imgui.AcceptDragDropPayload("ORE_NODE"); payload != nil {
					dragged := (^^e.Node)(payload.Data)^
					Editor_ReparentNode(state, dragged, root)
				}
				imgui.EndDragDropTarget()
			}
			if imgui.IsItemClicked(.Left) do state.selectedNode = nil
			if imgui.BeginPopupContextItem("##hier_empty_ctx") {
				Editor_ClearSelection(state)
				if hier_menu(ICON_FA_PLUS, "Add Node...", "add-node", true, "Cmd+A") do AddNodeDialog_Open()
				if hier_menu(ICON_FA_PASTE, "Paste", "paste", Editor_HasClipboardNodes(), "Cmd+V") do Editor_PasteNodes(state)
				if hier_menu(ICON_FA_CHECK, "Select All", "select-all", true, "Cmd+Shift+A") do Editor_SelectAllNodes(state)
				imgui.EndPopup()
			}
		}
	}
	imgui.EndChild()
	imgui.PopStyleVar(2)
}

// subtree_matches: a node is shown when it or a descendant matches the filter.
@(private = "file")
subtree_matches :: proc(state: ^EditorState, node: ^e.Node, filter: string) -> bool {
	if filter == "" || strings.contains(strings.to_lower(node.name, context.temp_allocator), filter) do return true
	children := e.GetChildren(state.activeScene.manager, node)
	defer delete(children)
	for c in children do if subtree_matches(state, c, filter) do return true
	return false
}

// The row pressed (selected on release unless it was dragged).
@(private = "file")
hierPress: struct {
	node: ^e.Node,
	at:   [2]f32,
}

SceneHierarchy_RenderNodeTree :: proc(state: ^EditorState, node: ^e.Node, parentPath: string, filter: string) {
	if node == nil || !subtree_matches(state, node, filter) do return
	mgr := state.activeScene.manager
	path := node.name if parentPath == "" else fmt.tprintf("%s/%s", parentPath, node.name)
	children := e.GetChildren(mgr, node)
	defer delete(children)

	flags: imgui.TreeNodeFlags = {.SpanAvailWidth, .OpenOnArrow, .OpenOnDoubleClick, .FramePadding}
	if len(children) == 0 do flags += {.Leaf, .NoTreePushOnOpen}
	else do flags += {.DefaultOpen}
	if filter != "" do imgui.SetNextItemOpen(true)
	if Editor_IsSelected(state, node) || node == state.selectedNode do flags += {.Selected}

	dim := !node.enabled || !node.renderable
	rowColor := UI_TEXT_FAINT if dim else UI_TEXT
	if node.componentPath != "" do rowColor = {0.75, 0.62, 1.0, 1} // component instance
	else if Editor_NodeLocked(state, node) do rowColor = {0.75, 0.62, 1.0, 0.55}
	imgui.PushStyleColorImVec4(.Text, rowColor)
	imgui.SetNextItemAllowOverlap() // the visibility button sits on the row
	open := imgui.TreeNodeEx(fmt.ctprintf("%s   %s###n%p", Editor_NodeIcon(node), node.name, node), flags)
	imgui.PopStyleColor()
	Drive_Item(fmt.tprintf("hier:%s", path))

	// Select on release, not press: dragging a row (onto the Inspector, e.g.
	// a camera's Follow Target) mustn't select it and swap the Inspector.
	if imgui.IsItemClicked(.Left) && !imgui.IsItemToggledOpen() {
		hierPress = {node, {imgui.GetIO().MousePos.x, imgui.GetIO().MousePos.y}}
	}
	if hierPress.node == node && imgui.IsMouseReleased(.Left) {
		io := imgui.GetIO()
		d := [2]f32{io.MousePos.x, io.MousePos.y} - hierPress.at
		if d.x * d.x + d.y * d.y < 36 {
			Editor_SelectNode(state, node, io.KeyCtrl || io.KeySuper || io.KeyShift)
			PreviewPanel_OnNodeSelected(state, node)
		}
		hierPress = {}
	}
	if imgui.IsItemHovered() && imgui.IsMouseDoubleClicked(.Left) {
		state.cameraPos = node.globalPosition
	}
	if node == hierarchyPendingFocus {
		imgui.SetScrollHereY(0.5)
		hierarchyPendingFocus = nil
	}

	// Drag to re-parent.
	if imgui.BeginDragDropSource({}) {
		n := node
		imgui.SetDragDropPayload("ORE_NODE", &n, size_of(^e.Node))
		imgui.TextUnformatted(fmt.ctprintf("%s  %s", Editor_NodeIcon(node), node.name))
		imgui.EndDragDropSource()
	}
	if imgui.BeginDragDropTarget() {
		if payload := imgui.AcceptDragDropPayload("ORE_NODE"); payload != nil {
			dragged := (^^e.Node)(payload.Data)^
			if Editor_ReparentNode(state, dragged, node) {
				Editor_Log(state, .Info, "Moved %s under %s", dragged.name, node.name)
			}
		}
		imgui.EndDragDropTarget()
	}

	// Right-click actions.
	if imgui.BeginPopupContextItem(fmt.ctprintf("ctx%p", node)) {
		if !Editor_IsSelected(state, node) do Editor_SelectNode(state, node)
		Node_ContextMenu(state, node)
		imgui.EndPopup()
	}

	// Visibility toggle at the right edge of the row.
	rowMax := imgui.GetItemRectMax()
	imgui.SameLine(imgui.GetWindowContentRegionMax().x - 22)
	imgui.PushStyleColorImVec4(.Button, {0, 0, 0, 0})
	imgui.PushStyleColorImVec4(.ButtonHovered, UI_BG_HOVER)
	imgui.PushStyleColorImVec4(.Text, UI_TEXT_FAINT)
	imgui.PushStyleVarImVec2(.FramePadding, {3, 2})
	if imgui.SmallButton(fmt.ctprintf("%s##vis%p", ICON_FA_EYE if node.renderable else ICON_FA_EYE_SLASH, node)) {
		Editor_RecordUndo(state, "Toggle visibility")
		node.renderable = !node.renderable
	}
	imgui.PopStyleVar()
	imgui.PopStyleColor(3)
	Drive_Item(fmt.tprintf("hier.vis:%s", path))
	_ = rowMax

	if open && len(children) > 0 {
		for child in children do SceneHierarchy_RenderNodeTree(state, child, path, filter)
		imgui.TreePop()
	}
}

SceneHierarchy_DuplicateSelected :: proc(state: ^EditorState) {
	if len(state.selection) > 1 {
		if n := Editor_DuplicateSelection(state); n > 0 do Editor_Log(state, .Info, "Duplicated %d nodes", n)
		return
	}
	if copy := Editor_DuplicateNode(state, state.selectedNode); copy != nil {
		Editor_Log(state, .Info, "Duplicated node as '%s'", copy.name)
	}
}

SceneHierarchy_DeleteSelected :: proc(state: ^EditorState) {
	if state.selectedNode == nil do return
	if len(state.selection) > 1 {
		if n := Editor_DeleteSelection(state); n > 0 do Editor_Log(state, .Info, "Deleted %d nodes", n)
		return
	}
	name := strings.clone(state.selectedNode.name, context.temp_allocator)
	if Editor_DeleteNode(state, state.selectedNode) {
		Editor_Log(state, .Info, "Deleted node '%s'", name)
	}
}


@(private = "file")
hier_menu :: proc(icon, label, id: string, enabled := true, shortcut: cstring = nil) -> bool {
	clicked := imgui.MenuItem(fmt.ctprintf("%s  %s", icon, label), shortcut, false, enabled)
	Drive_Item(fmt.tprintf("ctx:%s", id))
	return clicked
}

// Node_ContextMenu: every action for a node (or the selection it is in).
// Editor_SceneCamera: the active scene's current camera (else its first).
Editor_SceneCamera :: proc(state: ^EditorState) -> ^e.CameraNode {
	if state.activeScene == nil || state.activeScene.manager == nil do return nil
	first: ^e.CameraNode
	for n in state.activeScene.manager.nodes {
		if n == nil || n.typeId != e.CameraNode do continue
		c := cast(^e.CameraNode)n
		if c.isCurrent do return c
		if first == nil do first = c
	}
	return first
}

Node_ContextMenu :: proc(state: ^EditorState, node: ^e.Node) {
	mgr := state.activeScene.manager
	isRoot := node == state.activeScene.rootNode
	locked := Editor_NodeLocked(state, node)
	inst := e.Node_ComponentRoot(mgr, node)
	multi := len(state.selection) > 1
	UI_DimText(fmt.tprintf("%d nodes", len(state.selection)) if multi else node.name)
	imgui.Separator()
	if hier_menu(ICON_FA_PLUS, "Add Child...", "add-child", true, "Cmd+A") {
		state.selectedNode = node
		AddNodeDialog_Open()
	}
	compOpen := imgui.BeginMenu(fmt.ctprintf("%s  Add Component as Child", ICON_FA_CUBES))
	Drive_Item("ctx:add-component-child")
	if compOpen {
		for rel in Editor_ListProjectFiles(state, "components", {".component.json"}) {
			if imgui.MenuItem(strings.clone_to_cstring(rel, context.temp_allocator)) {
				state.selectedNode = node
				Editor_InstantiateComponentFile(state, rel, node.globalPosition)
			}
			Drive_Item(fmt.tprintf("ctx:component:%s", rel))
		}
		imgui.EndMenu()
	}
	imgui.Separator()
	if hier_menu(ICON_FA_SCISSORS, "Cut", "cut", !isRoot, "Cmd+X") do Editor_CutSelection(state)
	if hier_menu(ICON_FA_COPY, "Copy", "copy", !isRoot, "Cmd+C") do Editor_CopySelection(state)
	if hier_menu(ICON_FA_PASTE, "Paste", "paste", Editor_HasClipboardNodes(), "Cmd+V") do Editor_PasteNodes(state)
	if hier_menu(ICON_FA_PASTE, "Paste as Child", "paste-child", Editor_HasClipboardNodes()) do Editor_PasteNodesInto(state, node)
	if hier_menu(ICON_FA_CLONE, "Duplicate", "duplicate", !isRoot, "Cmd+D") do SceneHierarchy_DuplicateSelected(state)
	if hier_menu(ICON_FA_PEN, "Rename", "rename", !isRoot && !locked && !multi, "F2") {
		state.selectedNode = node
		Editor_BeginRename(state)
	}
	if hier_menu(ICON_FA_TRASH, "Delete", "delete", !isRoot, "Del") do SceneHierarchy_DeleteSelected(state)
	imgui.Separator()
	parent := e.GetParent(mgr, node)
	index, count := 0, 0
	if parent != nil {
		kids := e.GetChildrenView(mgr, parent)
		count = len(kids)
		for k, i in kids do if k == node do index = i
	}
	if hier_menu(ICON_FA_ARROW_UP, "Move Up", "move-up", parent != nil && index > 0 && !locked) {
		Editor_RecordUndo(state, "Move up")
		e.MoveChild(mgr, parent, node, index - 1)
	}
	if hier_menu(ICON_FA_ARROW_DOWN, "Move Down", "move-down", parent != nil && index < count - 1 && !locked) {
		Editor_RecordUndo(state, "Move down")
		e.MoveChild(mgr, parent, node, index + 1)
	}
	if hier_menu(ICON_FA_ARROW_TURN_UP, "Move to Root", "move-root", parent != nil && parent != state.activeScene.rootNode && !locked) {
		Editor_ReparentNode(state, node, state.activeScene.rootNode)
	}
	if hier_menu(ICON_FA_CHECK, "Select Children", "select-children", len(e.GetChildrenView(mgr, node)) > 0) {
		Editor_ClearSelection(state)
		for c in e.GetChildrenView(mgr, node) do if c != nil && !c.transient do Editor_SelectNode(state, c, true)
	}
	imgui.Separator()
	if hier_menu(ICON_FA_POWER_OFF, "Disable" if node.enabled else "Enable", "toggle-enabled", !isRoot) {
		Editor_RecordUndo(state, "Toggle enabled")
		on := !node.enabled
		for n in Editor_SelectionRoots(state) do n.enabled = on
	}
	if hier_menu(ICON_FA_EYE, "Hide" if node.renderable else "Show", "toggle-visible", !isRoot) {
		Editor_RecordUndo(state, "Toggle visible")
		on := !node.renderable
		for n in Editor_SelectionRoots(state) do n.renderable = on
	}
	if hier_menu(ICON_FA_CROSSHAIRS, "Frame in Viewport", "frame", true, "F") do state.cameraPos = node.globalPosition
	imgui.Separator()
	// Script.
	if node.scriptInstance != nil {
		if hier_menu(ICON_FA_CODE, "Open Script", "open-script") do Editor_OpenScript(state, (cast(^e.ScriptInstance)node.scriptInstance).modulePath)
		if hier_menu(ICON_FA_XMARK, "Detach Script", "detach-script") {
			Editor_RecordUndo(state, "Detach script")
			e.ScriptInstance_Destroy(cast(^e.ScriptInstance)node.scriptInstance, &state.game.scriptManager)
			node.scriptInstance = nil
		}
	} else if !isRoot {
		attachOpen := imgui.BeginMenu(fmt.ctprintf("%s  Attach Script", ICON_FA_CODE))
		Drive_Item("ctx:attach-script")
		if attachOpen {
			if hier_menu(ICON_FA_PLUS, "New Script", "attach-new-script") {
				Editor_RecordUndo(state, "Attach script")
				if rel := Editor_NewScriptForNode(state, node); rel != "" {
					node.gameContext = &state.game.gameContext
					e.Script_AttachToNode(node, rel, nil, &state.game.scriptManager)
				}
			}
			imgui.Separator()
			for rel in Editor_ListProjectFiles(state, "scripts", {".lua"}) {
				if imgui.MenuItem(strings.clone_to_cstring(rel, context.temp_allocator)) {
					Editor_RecordUndo(state, "Attach script")
					node.gameContext = &state.game.gameContext
					e.Script_AttachToNode(node, rel, nil, &state.game.scriptManager)
				}
			}
			imgui.EndMenu()
		}
	}
	// Components.
	imgui.Separator()
	if inst != nil {
		if hier_menu(ICON_FA_CUBES, "Edit Component", "edit-component") do Editor_OpenComponent(state, inst.componentPath)
		if hier_menu(ICON_FA_FLOPPY_DISK, "Apply Changes to Component", "apply-component") do Editor_ApplyInstanceToComponent(state, inst)
		if hier_menu(ICON_FA_CLONE, "Save as New Component...", "save-new-component") do Prompt_Open(.SaveComponentAs, fmt.tprintf("%s_variant", inst.name), inst)
		if hier_menu(ICON_FA_ROTATE_LEFT, "Revert Overrides" if node == inst else "Revert This Node", "revert-overrides") {
			Editor_RecordUndo(state, "Revert overrides")
			if fresh := e.Scene_RevertComponentOverrides(state.activeScene, node, &state.game.gameContext); fresh != nil do state.selectedNode = fresh
		}
		if hier_menu(ICON_FA_LINK_SLASH, "Unlink", "unlink-component", node == inst) {
			Editor_RecordUndo(state, "Unlink component")
			e.Node_UnlinkComponent(node)
		}
	} else if !isRoot {
		if hier_menu(ICON_FA_CUBES, "Save as Component", "save-component") do Component_SaveNodeToFile(state, node)
		if hier_menu(ICON_FA_CLONE, "Save as Component Named...", "save-component-named") do Prompt_Open(.SaveComponentAs, node.name, node)
	}
	imgui.Separator()
	if cam := Editor_SceneCamera(state); cam != nil && node.typeId != e.CameraNode && !node.transient {
		following := cam.followTarget != "" && e.Node_ResolvePath(state.activeScene.manager, cam, cam.followTarget) == node
		if hier_menu(ICON_FA_VIDEO, "Camera Stops Following" if following else "Camera Follows This", "camera-follow") {
			Editor_RecordUndo(state, "Camera follow target")
			e.CameraNode_SetFollowTarget(cam, state.activeScene.manager, nil if following else node)
		}
	}
	if hier_menu(ICON_FA_LINK, "Copy Node Path", "copy-node-path") {
		imgui.SetClipboardText(strings.clone_to_cstring(e.Node_RelativePath(mgr, state.activeScene.rootNode, node), context.temp_allocator))
	}
}
