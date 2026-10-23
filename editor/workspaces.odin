package editor

import "core:c"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import imgui "lib/imgui"

// ============================================================================
// Workspaces (View > Workspaces): layout presets built with the dock
// builder - Default, Level Design (big viewport), Scripting (the Code tab in
// the middle), Animation (a tall timeline) - and layouts the user saves
// (ImGui's layout text in ~/.config/ore_editor/workspaces/<name>.ini),
// loaded at the start of a frame. Reset Layout = the Default preset.
// ============================================================================

Layout_Preset :: enum {
	Default,
	LevelDesign,
	Scripting,
	Animation,
}

LAYOUT_PRESET_NAMES := [Layout_Preset]string {
	.Default     = "Default",
	.LevelDesign = "Level Design",
	.Scripting   = "Scripting",
	.Animation   = "Animation",
}

@(private = "file")
layoutRequest := -1 // a Layout_Preset to build next frame

@(private = "file")
pendingIni: string // a saved workspace to load before the next frame

// currentWorkspace: the last preset / workspace applied (shown in the menu).
currentWorkspace := "Default"

Workspace_RequestPreset :: proc(p: Layout_Preset) {
	layoutRequest = int(p)
	currentWorkspace = LAYOUT_PRESET_NAMES[p]
}

// Workspace_BuildIfNeeded (re)builds the dock layout: the first time, or
// when a preset was picked.
Workspace_BuildIfNeeded :: proc(state: ^EditorState, dockspaceID: imgui.ID, pos, size: imgui.Vec2) {
	if DockBuilderGetNode(dockspaceID) != nil && layoutRequest < 0 do return
	preset := Layout_Preset(layoutRequest) if layoutRequest >= 0 else .Default
	layoutRequest = -1
	r := preset_ratios(preset)
	if preset == .Default && size.y > 0 {
		// The bottom panel (Console, Animation, ...) starts DEFAULT_BOTTOM_PX tall.
		r.bottom = clamp(DEFAULT_BOTTOM_PX / size.y, 0.05, 0.5)
	}

	DockBuilderRemoveNode(dockspaceID)
	DockBuilderAddNode(dockspaceID, 0)
	DockBuilderSetNodePos(dockspaceID, pos)
	DockBuilderSetNodeSize(dockspaceID, size)
	dockMain := dockspaceID
	dockLeft, dockLeftPreview, dockRight, dockBottom, dockInspector, dockHierarchy: imgui.ID

	// Left column: Assets over Preview. Right column: Scene over Inspector.
	// Bottom (under the viewport): Console and the other tools.
	DockBuilderSplitNode(dockMain, .Left, r.left, &dockLeft, &dockMain)
	DockBuilderSplitNode(dockLeft, .Down, 0.36, &dockLeftPreview, &dockLeft)
	DockBuilderDockWindow("Assets###AssetBrowserWindow", dockLeft)
	DockBuilderDockWindow("Preview###PreviewPanelWindow", dockLeftPreview)
	DockBuilderSplitNode(dockMain, .Right, r.right, &dockRight, &dockMain)
	DockBuilderSplitNode(dockMain, .Down, r.bottom, &dockBottom, &dockMain)
	DockBuilderDockWindow("Console###BottomPanelWindow", dockBottom)
	DockBuilderSplitNode(dockRight, .Down, 0.50, &dockInspector, &dockHierarchy)
	DockBuilderDockWindow("Scene###SceneHierarchyWindow", dockHierarchy)
	DockBuilderDockWindow("Inspector###InspectorWindow", dockInspector)
	DockBuilderDockWindow("Viewport###ViewportWindow", dockMain)
	DockBuilderDockWindow(CODE_WINDOW, dockMain) // a tab next to the Viewport
	DockBuilderFinish(dockspaceID)

	#partial switch preset {
	case .Scripting:
		GlobalCode.focusRequest = true // the Code tab in front (when a script is open)
		if len(GlobalCode.docs) == 0 do Editor_Log(state, .Info, "Scripting layout: open a script to fill the Code tab")
	case .Animation:
		animTabRequest = true
	}
}

DEFAULT_BOTTOM_PX :: f32(100)

@(private = "file")
preset_ratios :: proc(p: Layout_Preset) -> (r: struct {left, right, bottom: f32}) {
	switch p {
	case .Default: r = {0.20, 0.25, 0.28}
	case .LevelDesign: r = {0.15, 0.21, 0.18}
	case .Scripting: r = {0.17, 0.22, 0.30}
	case .Animation: r = {0.16, 0.22, 0.46}
	}
	return
}

// Workspace_BeforeFrame loads a saved workspace (call before NewFrame).
Workspace_BeforeFrame :: proc() {
	if pendingIni == "" do return
	imgui.LoadIniSettingsFromMemory(strings.clone_to_cstring(pendingIni, context.temp_allocator), c.size_t(len(pendingIni)))
	delete(pendingIni)
	pendingIni = ""
}

workspaces_dir :: proc(state: ^EditorState) -> string {
	if GlobalDrive.enabled {
		p, _ := filepath.join({state.projectPath, ".editor_workspaces"}, context.temp_allocator)
		return p
	}
	home, err := os.user_home_dir(context.temp_allocator)
	if err != nil do return ".editor_workspaces"
	p, _ := filepath.join({home, ".config", "ore_editor", "workspaces"}, context.temp_allocator)
	return p
}

// Workspace_List: the saved workspaces' names.
Workspace_List :: proc(state: ^EditorState) -> []string {
	out := make([dynamic]string, context.temp_allocator)
	infos, err := os.read_all_directory_by_path(workspaces_dir(state), context.temp_allocator)
	if err != nil do return out[:]
	for fi in infos do if strings.has_suffix(fi.name, ".ini") do append(&out, strings.trim_suffix(fi.name, ".ini"))
	slice.sort(out[:])
	return out[:]
}

@(private = "file")
workspace_file :: proc(state: ^EditorState, name: string) -> string {
	clean, _ := strings.replace_all(strings.trim_space(name), "/", "_", context.temp_allocator)
	p, _ := filepath.join({workspaces_dir(state), strings.concatenate({clean, ".ini"}, context.temp_allocator)}, context.temp_allocator)
	return p
}

// Workspace_Save stores the current layout under a name.
Workspace_Save :: proc(state: ^EditorState, name: string) -> bool {
	if strings.trim_space(name) == "" do return false
	size: c.size_t
	data := imgui.SaveIniSettingsToMemory(&size)
	_ = os.make_directory_all(workspaces_dir(state))
	if os.write_entire_file(workspace_file(state, name), transmute([]u8)string(data)[:size]) != nil {
		Editor_Log(state, .Error, "Could not save the workspace %s", name)
		return false
	}
	currentWorkspace = strings.clone(strings.trim_space(name))
	Editor_Log(state, .Info, "Saved workspace %s", name)
	return true
}

// Workspace_Load applies a saved workspace at the start of the next frame.
Workspace_Load :: proc(state: ^EditorState, name: string) -> bool {
	data, err := os.read_entire_file(workspace_file(state, name), context.allocator)
	if err != nil {
		Editor_Log(state, .Error, "Workspace %s not found", name)
		return false
	}
	delete(pendingIni)
	pendingIni = string(data)
	currentWorkspace = strings.clone(name)
	Editor_Log(state, .Info, "Workspace %s", name)
	return true
}

Workspace_Delete :: proc(state: ^EditorState, name: string) {
	if os.remove(workspace_file(state, name)) == nil do Editor_Log(state, .Info, "Deleted workspace %s", name)
}
