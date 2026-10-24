package editor

import "core:fmt"
import "core:time"
import imgui "lib/imgui"

// ============================================================================
// Quitting with unsaved scenes or scripts asks first (Save All / Don't Save
// / Cancel). Triggered by Cmd+Q, File > Quit and the window's close button.
// ============================================================================

Editor_RequestQuit :: proc(state: ^EditorState) {
	if !GlobalSettings.confirmQuit || (Editor_ModifiedSceneCount(state) == 0 && Code_DirtyCount() == 0 && !LevelEditor_HasUnsaved()) {
		state.quitConfirmed = true
		return
	}
	state.quitRequested = true
}

QuitPrompt_Render :: proc(state: ^EditorState) {
	if !state.quitRequested do return
	imgui.OpenPopup("Unsaved Changes###QuitPrompt")
	center := imgui.GetMainViewport().WorkPos + imgui.GetMainViewport().WorkSize * 0.5
	imgui.SetNextWindowPos(center, {}, {0.5, 0.5})
	if !imgui.BeginPopupModal("Unsaved Changes###QuitPrompt", nil, {.NoResize, .AlwaysAutoResize, .NoTitleBar}) do return
	defer imgui.EndPopup()
	scenes := Editor_ModifiedSceneCount(state)
	scripts := Code_DirtyCount()
	UI_PanelTitle(ICON_FA_TRIANGLE_EXCLAMATION, "Quit with unsaved changes?")
	imgui.Dummy({0, 4})
	if scenes > 0 do imgui.TextUnformatted(fmt.ctprintf("%d scene(s) have unsaved changes.", scenes))
	if scripts > 0 do imgui.TextUnformatted(fmt.ctprintf("%d script(s) have unsaved changes.", scripts))
	if LevelEditor_HasUnsaved() do imgui.TextUnformatted(fmt.ctprintf("The level %s has unsaved changes.", GlobalLevel.rel))
	imgui.Dummy({0, 8})
	if UI_PrimaryButton("Save All and Quit", "quit.save") {
		Editor_SaveAllScenes(state)
		Code_SaveAll(state)
		if LevelEditor_HasUnsaved() do LevelEditor_Save(state)
		if Editor_ModifiedSceneCount(state) == 0 && Code_DirtyCount() == 0 && !LevelEditor_HasUnsaved() do state.quitConfirmed = true
		state.quitRequested = false
		imgui.CloseCurrentPopup()
	}
	imgui.SameLine()
	if UI_Button("Don't Save", "quit.discard") {
		state.quitConfirmed = true
		state.quitRequested = false
		imgui.CloseCurrentPopup()
	}
	imgui.SameLine()
	if UI_Button("Cancel", "quit.cancel") || imgui.IsKeyPressed(.Escape, false) {
		state.quitRequested = false
		imgui.CloseCurrentPopup()
	}
}

@(private = "file")
lastAutosave: time.Tick

// Editor_Autosave saves modified scenes and scripts every N minutes
// (Settings > General > Autosave; off by default and while simulating).
Editor_Autosave :: proc(state: ^EditorState) {
	mins := GlobalSettings.autosaveMinutes
	if mins <= 0 || state.isSimulating {
		lastAutosave = time.tick_now()
		return
	}
	if lastAutosave == {} do lastAutosave = time.tick_now()
	if time.tick_since(lastAutosave) < time.Duration(mins) * time.Minute do return
	lastAutosave = time.tick_now()
	scenes := Editor_ModifiedSceneCount(state) > 0
	scripts := Code_DirtyCount() > 0
	if !scenes && !scripts do return
	n := Editor_SaveAllScenes(state) if scenes else 0
	m := Code_SaveAll(state) if scripts else 0
	Editor_Log(state, .Info, "Autosaved %d scene(s) and %d script(s)", n, m)
}
