// C entry points for Dear ImGui's internal DockBuilder API (imgui_internal.h),
// which dear_bindings doesn't expose: plain C names, the same on every
// compiler (C++ name mangling differs between Clang and MSVC).
// scripts/build_imgui.sh compiles this into imgui_<os>_<arch>.a / .lib;
// editor/dock_builder.odin binds it.
#include "imgui.h"
#include "imgui_internal.h"

extern "C" {
ImGuiDockNode* OreDock_GetNode(ImGuiID id) { return ImGui::DockBuilderGetNode(id); }
ImGuiID OreDock_AddNode(ImGuiID id, ImGuiDockNodeFlags flags) { return ImGui::DockBuilderAddNode(id, flags); }
void OreDock_RemoveNode(ImGuiID id) { ImGui::DockBuilderRemoveNode(id); }
void OreDock_SetNodePos(ImGuiID id, ImVec2 pos) { ImGui::DockBuilderSetNodePos(id, pos); }
void OreDock_SetNodeSize(ImGuiID id, ImVec2 size) { ImGui::DockBuilderSetNodeSize(id, size); }
ImGuiID OreDock_SplitNode(ImGuiID id, ImGuiDir dir, float ratio, ImGuiID* at_dir, ImGuiID* at_opposite) {
	return ImGui::DockBuilderSplitNode(id, dir, ratio, at_dir, at_opposite);
}
void OreDock_DockWindow(const char* window_name, ImGuiID id) { ImGui::DockBuilderDockWindow(window_name, id); }
void OreDock_Finish(ImGuiID id) { ImGui::DockBuilderFinish(id); }
}
