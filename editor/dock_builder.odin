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
