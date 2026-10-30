package editor

import "core:fmt"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// The game's frame in the editor (#202): the project's virtual resolution
// (the design size the HUD is laid out on) - not a camera's runtime size
// cache - and, with the Expand fill mode, the frame grown to a preview
// screen shape picked in the toolbar (where right / bottom anchored HUD
// lands on that screen).
// ============================================================================

PREVIEW_SHAPES := [?]struct {
	name:   string,
	aspect: [2]f32, // width : height
}{
	{"16:9", {16, 9}},
	{"16:10", {16, 10}},
	{"4:3", {4, 3}},
	{"21:9", {21, 9}},
	{"Phone (portrait)", {9, 19.5}},
}

// Editor_DesignSize: the project's virtual resolution.
Editor_DesignSize :: proc(state: ^EditorState) -> [2]f32 {
	w := state.projectConfig.virtualWidth if state.projectConfig.virtualWidth > 0 else 1280
	h := state.projectConfig.virtualHeight if state.projectConfig.virtualHeight > 0 else 720
	return {w, h}
}

// Editor_PreviewShape: the screen shape the Expand frame is shown for.
Editor_PreviewShape :: proc() -> int {
	return clamp(GlobalSettings.previewShape, 0, len(PREVIEW_SHAPES) - 1)
}

// Editor_GameFrameSize: the frame the game draws at - the design size, or
// (Expand) grown to the preview screen's shape.
Editor_GameFrameSize :: proc(state: ^EditorState) -> [2]f32 {
	design := Editor_DesignSize(state)
	if state.projectConfig.fill != .Expand do return design
	a := PREVIEW_SHAPES[Editor_PreviewShape()].aspect
	return e.Screen_FillSize(design, {a.x * 1000, a.y * 1000}, .Expand, state.projectConfig.integerScaling)
}

// Editor_SyncGameFrame keeps the editor's game on the project's frame
// (Simulate's cameras, Screen Layers) - each frame, so settings follow.
Editor_SyncGameFrame :: proc(state: ^EditorState) {
	if state.game == nil do return
	state.game.designSize = Editor_DesignSize(state)
	state.game.virtualSize = Editor_GameFrameSize(state)
	state.game.fill = state.projectConfig.fill
}

// Toolbar_PreviewShape: the screen-shape picker (only with Expand).
Toolbar_PreviewShape :: proc(state: ^EditorState) {
	if state.projectConfig.fill != .Expand do return
	imgui.SameLine(0, 2)
	cur := Editor_PreviewShape()
	imgui.SetNextItemWidth(84)
	if imgui.BeginCombo("##preview_shape", fmt.ctprintf("%s", PREVIEW_SHAPES[cur].name)) {
		for s, i in PREVIEW_SHAPES {
			if imgui.Selectable(fmt.ctprintf("%s", s.name), i == cur) {
				GlobalSettings.previewShape = i
				_ = Editor_SaveSettings()
			}
			Drive_Item(fmt.tprintf("pick:%s", s.name))
		}
		imgui.EndCombo()
	}
	Drive_Item("toolbar.screen-shape")
	size := Editor_GameFrameSize(state)
	UI_Tooltip(fmt.tprintf("Expand fill: the camera frame on a %s screen (%.0f x %.0f; the design frame %.0f x %.0f inside) - dashed in the viewport", PREVIEW_SHAPES[cur].name, size.x, size.y, Editor_DesignSize(state).x, Editor_DesignSize(state).y))
}
