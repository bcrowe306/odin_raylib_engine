package editor

import "core:testing"
import e "../engine"

// #202: the editor's game frame is the project's virtual resolution (Expand:
// grown to the preview screen shape) - never a camera's runtime cache.
@(test)
test_game_frame_size :: proc(t: ^testing.T) {
	state: EditorState
	state.projectConfig.virtualWidth, state.projectConfig.virtualHeight = 640, 360
	testing.expect_value(t, Editor_GameFrameSize(&state), [2]f32{640, 360})
	state.projectConfig.fill = .Expand
	saved := GlobalSettings.previewShape
	defer GlobalSettings.previewShape = saved
	GlobalSettings.previewShape = 0 // 16:9: the design's own shape
	testing.expect_value(t, Editor_GameFrameSize(&state), [2]f32{640, 360})
	GlobalSettings.previewShape = 2 // 4:3: taller
	testing.expect_value(t, Editor_GameFrameSize(&state), [2]f32{640, 480})
	GlobalSettings.previewShape = 3 // 21:9: wider
	testing.expect_value(t, Editor_GameFrameSize(&state), [2]f32{840, 360})
	// No project size: 1280 x 720.
	empty: EditorState
	testing.expect_value(t, Editor_DesignSize(&empty), [2]f32{1280, 720})
	_ = e.Screen_Fill.Keep
}
