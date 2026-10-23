package editor

import "core:c"
import imgui "lib/imgui"

// ============================================================================
// Dear ImGui Internal DockBuilder API Bindings
// ============================================================================

foreign import imgui_lib "lib/imgui/imgui_darwin_arm64.a"

@(default_calling_convention="c")
foreign imgui_lib {
	@(link_name="_ZN5ImGui18DockBuilderGetNodeEj")
	DockBuilderGetNode :: proc(node_id: imgui.ID) -> rawptr ---

	@(link_name="_ZN5ImGui18DockBuilderAddNodeEji")
	DockBuilderAddNode :: proc(node_id: imgui.ID, flags: c.int = 0) -> imgui.ID ---

	@(link_name="_ZN5ImGui21DockBuilderRemoveNodeEj")
	DockBuilderRemoveNode :: proc(node_id: imgui.ID) ---

	@(link_name="_ZN5ImGui21DockBuilderSetNodePosEj6ImVec2")
	DockBuilderSetNodePos :: proc(node_id: imgui.ID, pos: imgui.Vec2) ---

	@(link_name="_ZN5ImGui22DockBuilderSetNodeSizeEj6ImVec2")
	DockBuilderSetNodeSize :: proc(node_id: imgui.ID, size: imgui.Vec2) ---

	@(link_name="_ZN5ImGui20DockBuilderSplitNodeEj8ImGuiDirfPjS1_")
	DockBuilderSplitNode :: proc(node_id: imgui.ID, split_dir: imgui.Dir, size_ratio: f32, out_id_at_dir: ^imgui.ID, out_id_at_opposite_dir: ^imgui.ID) -> imgui.ID ---

	@(link_name="_ZN5ImGui21DockBuilderDockWindowEPKcj")
	DockBuilderDockWindow :: proc(window_name: cstring, node_id: imgui.ID) ---

	@(link_name="_ZN5ImGui17DockBuilderFinishEj")
	DockBuilderFinish :: proc(node_id: imgui.ID) ---
}

// ============================================================================
// Tab bars (View > Show Tab Bars). By default a dock node holding a single
// window hides its tab bar (AutoHideTabBar; the panels draw their own
// headers) - so after closing a window docked next to another, the one left
// loses its tab. With Show Tab Bars on, every docked window keeps its tab
// (to see, drag and re-dock windows); off, single windows hide theirs again.
// Reads ImGuiDockNode's leading fields (imgui_internal.h, 1.91):
//   ID u32, SharedFlags, LocalFlags, LocalFlagsInWindows, MergedFlags,
//   State (i32 each), ParentNode, ChildNodes[2], Windows (ImVector).
// ============================================================================

@(private = "file")
Dock_Node_Head :: struct {
	id:                  imgui.ID,
	sharedFlags:         c.int,
	localFlags:          c.int,
	localFlagsInWindows: c.int,
	mergedFlags:         c.int,
	state:               c.int,
	parent:              rawptr,
	children:            [2]rawptr,
	windowCount:         c.int, // ImVector<ImGuiWindow*>.Size
}

editorDockspaceID: imgui.ID // the main dockspace (main.odin)

DOCK_NODE_NO_TAB_BAR :: c.int(1 << 12)
DOCK_NODE_HIDDEN_TAB_BAR :: c.int(1 << 13)

// Dock_ApplyTabBars shows the tab bar of every docked window's node, or
// hides those of single-window nodes (ImGui keeps the tabs of nodes with
// more than one window). Returns how many nodes changed.
Dock_ApplyTabBars :: proc(dockspace: imgui.ID, show: bool) -> int {
	walk :: proc(p: rawptr, show: bool, depth: int) -> int {
		if p == nil || depth > 32 do return 0
		n := cast(^Dock_Node_Head)p
		changed := 0
		if n.children[0] == nil && n.children[1] == nil && n.windowCount > 0 {
			flags := n.localFlags
			if show do flags &~= DOCK_NODE_HIDDEN_TAB_BAR | DOCK_NODE_NO_TAB_BAR
			else if n.windowCount == 1 do flags |= DOCK_NODE_HIDDEN_TAB_BAR
			if flags != n.localFlags {
				n.localFlags = flags
				n.mergedFlags = n.sharedFlags | n.localFlags | n.localFlagsInWindows
				changed += 1
			}
		}
		return changed + walk(n.children[0], show, depth + 1) + walk(n.children[1], show, depth + 1)
	}
	return walk(DockBuilderGetNode(dockspace), show, 0)
}

// Dock_HiddenTabBars: how many nodes with windows hide their tab bar (drives).
Dock_HiddenTabBars :: proc(dockspace: imgui.ID) -> int {
	walk :: proc(p: rawptr, depth: int) -> int {
		if p == nil || depth > 32 do return 0
		n := cast(^Dock_Node_Head)p
		own := 1 if n.windowCount > 0 && n.localFlags & (DOCK_NODE_HIDDEN_TAB_BAR | DOCK_NODE_NO_TAB_BAR) != 0 else 0
		return own + walk(n.children[0], depth + 1) + walk(n.children[1], depth + 1)
	}
	return walk(DockBuilderGetNode(dockspace), 0)
}
