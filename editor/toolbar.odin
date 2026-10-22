package editor

import "core:c"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import rl "vendor:raylib"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Top Toolbar Subsystem: Pure Icon Buttons with Rich Hover Tooltips
// ============================================================================

Toolbar_Render :: proc(state: ^EditorState, width, height, posY: f32) {
	imgui.SetNextWindowPos(imgui.Vec2{0, posY})
	imgui.SetNextWindowSize(imgui.Vec2{width, height})
	flags: imgui.WindowFlags = {.NoTitleBar, .NoResize, .NoMove, .NoScrollbar, .NoSavedSettings, .NoDocking, .NoScrollWithMouse}

	imgui.PushStyleVarImVec2(.WindowPadding, {10, (height - 30) * 0.5})
	imgui.PushStyleVarImVec2(.ItemSpacing, {2, 0})
	imgui.PushStyleColorImVec4(.WindowBg, UI_BG_APP)
	defer {
		imgui.PopStyleColor()
		imgui.PopStyleVar(2)
	}
	defer imgui.End()
	if !imgui.Begin("Toolbar###FixedToolbarWindow", nil, flags) do return

	// 1. Breadcrumb: project › scene
	imgui.PushStyleColorImVec4(.Button, {0, 0, 0, 0})
	imgui.PushStyleColorImVec4(.ButtonHovered, UI_BG_HOVER)
	imgui.PushStyleVarImVec2(.FramePadding, {8, 6})
	projName := state.projectConfig.name if state.projectConfig.name != "" else filepath.base(state.projectPath)
	imgui.PushFont(GlobalFonts.semibold)
	if imgui.Button(fmt.ctprintf("%s  %s##crumb_project", ICON_FA_FOLDER, projName)) do ProjectSettingsDialog_Open(state)
	imgui.PopFont()
	Drive_Item("toolbar.project")
	UI_Tooltip(fmt.tprintf("%s - click for project settings", state.projectPath))
	imgui.SameLine(0, 0)
	imgui.AlignTextToFramePadding()
	UI_DimText("/")
	imgui.SameLine(0, 0)
	sceneLabel := filepath.base(state.activeScenePath) if state.activeScenePath != "" else "untitled"
	modified := Editor_ModifiedSceneCountCached(state) > 0
	imgui.Button(fmt.ctprintf("%s%s##crumb_scene", sceneLabel, "  " + ICON_FA_CIRCLE if modified else ""))
	Drive_Item("toolbar.scene")
	UI_Tooltip("Unsaved changes" if modified else "Active scene")
	imgui.PopStyleVar()
	imgui.PopStyleColor(2)

	UI_VerticalDivider()

	// 2. Tools
	tool :: proc(state: ^EditorState, mode: ToolMode, icon, id, tip: string) {
		if UI_IconButton(icon, id, tip, state.toolMode == mode) do state.toolMode = mode
		imgui.SameLine()
	}
	tool(state, .Select, ICON_FA_ARROW_POINTER, "toolbar.select", "Select (Q)")
	tool(state, .Translate, ICON_FA_ARROWS_UP_DOWN_LEFT_RIGHT, "toolbar.move", "Move (W)")
	tool(state, .Rotate, ICON_FA_ROTATE, "toolbar.rotate", "Rotate (E)")
	tool(state, .Scale, ICON_FA_EXPAND, "toolbar.scale", "Scale (R)")
	tool(state, .Pan, ICON_FA_HAND, "toolbar.pan", "Pan (T, or middle mouse)")

	UI_VerticalDivider()
	canUndo := len(state.undoStack) > 0
	canRedo := len(state.redoStack) > 0
	if !canUndo do imgui.BeginDisabled(true)
	if UI_IconButton(ICON_FA_ROTATE_LEFT, "toolbar.undo", "Undo (Ctrl+Z)") do Editor_Undo(state)
	if !canUndo do imgui.EndDisabled()
	imgui.SameLine()
	if !canRedo do imgui.BeginDisabled(true)
	if UI_IconButton(ICON_FA_ROTATE_RIGHT, "toolbar.redo", "Redo (Ctrl+Shift+Z)") do Editor_Redo(state)
	if !canRedo do imgui.EndDisabled()

	// 3. Play controls, centred (but never over the tools on the left).
	playW: f32 = 3 * 32 + 120
	imgui.SameLine()
	imgui.SetCursorPosX(max(imgui.GetCursorPosX() + UI_SPACE * 3, (width - playW) * 0.5))
	if state.gameProcessRunning || state.buildRunning {
		if UI_IconButton(ICON_FA_STOP, "toolbar.stop", "Stop (Shift+F5)", tint = UI_DANGER) {
			if state.buildRunning {
				_ = os.process_kill(state.buildProcess)
			} else {
				Editor_StopGameProcess(state)
			}
		}
	} else {
		if UI_IconButton(ICON_FA_PLAY, "toolbar.play", "Play project (F5) - saves changes, rebuilds if code changed", tint = UI_SUCCESS) {
			Editor_PlayGameProcess(state, .Project)
		}
		imgui.SameLine()
		if UI_IconButton(ICON_FA_CIRCLE_PLAY, "toolbar.play-scene", "Play this scene (F6)", tint = UI_SUCCESS) {
			Editor_PlayGameProcess(state, .CurrentScene)
		}
	}
	imgui.SameLine(0, UI_SPACE)
	imgui.AlignTextToFramePadding()
	switch {
	case state.buildRunning:
		imgui.PushStyleColorImVec4(.Text, UI_WARNING)
		imgui.TextUnformatted(fmt.ctprintf("%s  Building...", ICON_FA_HAMMER))
		imgui.PopStyleColor()
	case state.gameProcessRunning:
		imgui.PushStyleColorImVec4(.Text, UI_SUCCESS)
		imgui.TextUnformatted(fmt.ctprintf("%s  Running", ICON_FA_CIRCLE))
		imgui.PopStyleColor()
	}
	Drive_Item("toolbar.status")

	// 4. View toggles and file actions, right-aligned.
	rightW: f32 = 7 * 32 + 64 + 3 * 18 + 32 + 80
	imgui.SameLine()
	imgui.SetCursorPosX(max(imgui.GetCursorPosX() + UI_SPACE * 3, width - rightW - 10))
	toggle :: proc(v: ^bool, icon, id, tip: string) {
		if UI_IconButton(icon, id, tip, v^) do v^ = !v^
		imgui.SameLine()
	}
	toggle(&state.snapGrid, ICON_FA_MAGNET, "toolbar.snap", "Snap to grid")
	imgui.SetNextItemWidth(56)
	imgui.PushStyleVarImVec2(.FramePadding, {6, 6})
	imgui.DragFloat("##GridStep", &state.gridSize, 1.0, 4.0, 256.0, "%.0f px")
	imgui.PopStyleVar()
	Drive_Item("toolbar.grid-size")
	UI_Tooltip("Grid size")
	imgui.SameLine()
	toggle(&state.showGrid, ICON_FA_BORDER_ALL, "toolbar.grid", "Show grid")
	toggle(&state.showBounds, ICON_FA_EYE, "toolbar.bounds", "Show bounds & colliders")
	toggle(&state.showCameraBounds, ICON_FA_VIDEO, "toolbar.camera", "Show camera frames")
	toggle(&viewportLighting, ICON_FA_SUN, "toolbar.lighting", "Preview lighting (lights, the scene's ambient) and post effects")
	UI_VerticalDivider()
	if UI_IconButton(ICON_FA_EXPAND, "toolbar.fit", "Fit the scene to the view (Home)") do Viewport_FitScene(state)
	imgui.SameLine()
	imgui.SetNextItemWidth(76)
	imgui.PushStyleVarImVec2(.FramePadding, {6, 7})
	if imgui.BeginCombo("##zoom", fmt.ctprintf("%.0f%%", state.cameraZoom * 100)) {
		for z in ([]f32{0.25, 0.5, 1, 2, 4}) {
			if imgui.Selectable(fmt.ctprintf("%.0f%%", z * 100), abs(state.cameraZoom - z) < 0.001) do state.cameraZoom = z
			Drive_Item(fmt.tprintf("pick:%.0f%%", z * 100))
		}
		imgui.Separator()
		if imgui.Selectable("Fit Scene") do Viewport_FitScene(state)
		Drive_Item("pick:Fit Scene")
		if imgui.Selectable("Fit Game View") do Viewport_FitGameView(state)
		Drive_Item("pick:Fit Game View")
		if imgui.Selectable("Fit Selection") do Viewport_FitSelection(state)
		Drive_Item("pick:Fit Selection")
		imgui.EndCombo()
	}
	imgui.PopStyleVar()
	Drive_Item("toolbar.zoom")
	UI_Tooltip("Zoom")
	imgui.SameLine()
	UI_VerticalDivider()
	if UI_IconButton(ICON_FA_FLOPPY_DISK, "toolbar.save", "Save scene (Ctrl+S)", tint = UI_WARNING if modified else {}) do Toolbar_SaveScene(state)
	imgui.SameLine()
	if UI_IconButton(ICON_FA_BOX_ARCHIVE, "toolbar.export", "Export .ore package") do Toolbar_ExportOre(state)
	imgui.SameLine()
	if UI_IconButton(ICON_FA_GEAR, "toolbar.settings", "Project settings") do ProjectSettingsDialog_Open(state)
}

Toolbar_StartSimulation :: proc(state: ^EditorState) {
	if state.activeScene == nil do return

	if state.snapshotJson != "" {
		delete(state.snapshotJson)
	}
	state.snapshotJson = e.Scene_SerializeToJSON(state.activeScene)
	// Scripts run in the editor's Lua state: remember its globals so Stop
	// can put them back (and reset module-level locals).
	e.ScriptManager_SnapshotGlobals(&state.game.scriptManager)
	// Edit-mode scenes never ran ready(); start them like the game would.
	state.game.scriptManager.suspended = false
	e.Scene_CallReady(state.activeScene, state.activeScene.rootNode, &state.game.gameContext)

	state.isSimulating = true
	state.isPaused = false
	Editor_Log(state, .Info, "Simulation started. Scene snapshot saved.")
}

Toolbar_StopSimulation :: proc(state: ^EditorState) {
	if !state.isSimulating do return

	state.isSimulating = false
	state.isPaused = false
	state.game.scriptManager.suspended = true

	// Rebuild the same scene object from the snapshot (it keeps its file and
	// registry entry, so saving still goes to the right place).
	if state.activeScene != nil && state.snapshotJson != "" {
		scene := state.activeScene
		e.Scene_Unload(scene, &state.game.gameContext)
		e.ScriptManager_RestoreGlobals(&state.game.scriptManager)
		e.Scene_InstantiateFromJSON(scene, transmute([]u8)state.snapshotJson, &state.game.gameContext)
		e.ProcessNodeQueues(scene.manager, &state.game.gameContext)
		scene.isLoaded = true
		state.selectedNode = nil
		Editor_Log(state, .Info, "Simulation stopped. Scene restored to pre-simulation snapshot.")
	}
}

Toolbar_NewScene :: proc(state: ^EditorState) {
	if state.game == nil do return
	Editor_NewScene(state)
}

Toolbar_SaveScene :: proc(state: ^EditorState) {
	Lua_MarkProjectTypesDirty() // generated Lua types follow the project
	if state.activeScene == nil do return
	Editor_SaveSceneDocument(state, state.activeScene)
}

// Editor_OrePath: exports go next to the project folder (<dir>.ore).
Editor_OrePath :: proc(state: ^EditorState) -> string {
	clean := strings.trim_suffix(state.projectPath, "/")
	return strings.concatenate({clean, ".ore"}, context.temp_allocator)
}

Toolbar_ExportOre :: proc(state: ^EditorState) {
	Editor_SaveAllScenes(state)
	defer Editor_InvalidateProjectFiles() // the package appears next to the project
	outPath := Editor_OrePath(state)
	ok := e.OrePackage_CreateFromDirectory(state.projectPath, outPath, true)
	if ok {
		Editor_Log(state, .Info, "Exported portable .ore archive: %s", outPath)
	} else {
		Editor_Log(state, .Error, "Failed to export .ore package: %s", outPath)
	}
}
