package editor

import "core:testing"
import "core:strings"

@test
test_asset_selection_single :: proc(t: ^testing.T) {
	state: EditorState
	defer Editor_ClearAssetSelection(&state)

	Editor_SelectAsset(&state, "/project/textures/a.png")
	testing.expect(t, Editor_AssetSelectedCount(&state) == 1, "Count should be 1")
	testing.expect(t, Editor_AssetIsSelected(&state, "/project/textures/a.png"), "a.png should be selected")
	testing.expect(t, !Editor_AssetIsSelected(&state, "/project/textures/b.png"), "b.png should not be selected")
	testing.expect_value(t, state.selectedAssetPath, "/project/textures/a.png")
	testing.expect_value(t, state.assetAnchorPath, "/project/textures/a.png")

	// Select a different single asset replaces selection
	Editor_SelectAsset(&state, "/project/textures/b.png")
	testing.expect(t, Editor_AssetSelectedCount(&state) == 1, "Count should be 1")
	testing.expect(t, !Editor_AssetIsSelected(&state, "/project/textures/a.png"), "a.png should no longer be selected")
	testing.expect(t, Editor_AssetIsSelected(&state, "/project/textures/b.png"), "b.png should be selected")
	testing.expect_value(t, state.selectedAssetPath, "/project/textures/b.png")
	testing.expect_value(t, state.assetAnchorPath, "/project/textures/b.png")
}

@test
test_asset_selection_toggle_ctrl :: proc(t: ^testing.T) {
	state: EditorState
	defer Editor_ClearAssetSelection(&state)

	// 1. Initial selection of file 1
	Editor_SelectAsset(&state, "/project/textures/1.png")
	testing.expect(t, Editor_AssetSelectedCount(&state) == 1)

	// 2. Ctrl-click file 2 -> both selected
	Editor_ToggleAssetSelection(&state, "/project/textures/2.png")
	testing.expect(t, Editor_AssetSelectedCount(&state) == 2, "Count should be 2")
	testing.expect(t, Editor_AssetIsSelected(&state, "/project/textures/1.png"))
	testing.expect(t, Editor_AssetIsSelected(&state, "/project/textures/2.png"))
	testing.expect_value(t, state.selectedAssetPath, "/project/textures/2.png")
	testing.expect_value(t, state.assetAnchorPath, "/project/textures/2.png")

	// 3. Ctrl-click file 3 -> 3 selected
	Editor_ToggleAssetSelection(&state, "/project/textures/3.png")
	testing.expect(t, Editor_AssetSelectedCount(&state) == 3, "Count should be 3")
	testing.expect(t, Editor_AssetIsSelected(&state, "/project/textures/3.png"))

	// 4. Ctrl-click file 2 -> unselects file 2, leaving 1 and 3
	Editor_ToggleAssetSelection(&state, "/project/textures/2.png")
	testing.expect(t, Editor_AssetSelectedCount(&state) == 2, "Count should be 2 after toggle off")
	testing.expect(t, Editor_AssetIsSelected(&state, "/project/textures/1.png"))
	testing.expect(t, !Editor_AssetIsSelected(&state, "/project/textures/2.png"))
	testing.expect(t, Editor_AssetIsSelected(&state, "/project/textures/3.png"))

	// 5. Ctrl-click file 3 (which was primary) -> unselects file 3, updates primary to file 1
	Editor_ToggleAssetSelection(&state, "/project/textures/3.png")
	testing.expect(t, Editor_AssetSelectedCount(&state) == 1)
	testing.expect(t, Editor_AssetIsSelected(&state, "/project/textures/1.png"))
	testing.expect_value(t, state.selectedAssetPath, "/project/textures/1.png")

	// 6. Ctrl-click file 1 -> unselects last file, count is 0, primary is ""
	Editor_ToggleAssetSelection(&state, "/project/textures/1.png")
	testing.expect(t, Editor_AssetSelectedCount(&state) == 0)
	testing.expect_value(t, state.selectedAssetPath, "")
}

@test
test_asset_selection_range_shift :: proc(t: ^testing.T) {
	state: EditorState
	state.projectPath = "/project"
	defer Editor_ClearAssetSelection(&state)

	files := []string{
		"textures/0.png",
		"textures/1.png",
		"textures/2.png",
		"textures/3.png",
		"textures/4.png",
	}

	// Click file 1 -> sets anchor to file 1
	Editor_SelectAsset(&state, "/project/textures/1.png")
	testing.expect_value(t, state.assetAnchorPath, "/project/textures/1.png")

	// Shift-click file 3 -> selects range 1..=3 (files 1, 2, 3)
	Editor_SelectAssetRange(&state, "/project/textures/3.png", files)
	testing.expect(t, Editor_AssetSelectedCount(&state) == 3, "Count should be 3")
	testing.expect(t, !Editor_AssetIsSelected(&state, "/project/textures/0.png"))
	testing.expect(t, Editor_AssetIsSelected(&state, "/project/textures/1.png"))
	testing.expect(t, Editor_AssetIsSelected(&state, "/project/textures/2.png"))
	testing.expect(t, Editor_AssetIsSelected(&state, "/project/textures/3.png"))
	testing.expect(t, !Editor_AssetIsSelected(&state, "/project/textures/4.png"))
	// Crucial: Anchor stays at file 1!
	testing.expect_value(t, state.assetAnchorPath, "/project/textures/1.png")
	testing.expect_value(t, state.selectedAssetPath, "/project/textures/3.png")

	// Shift-click backwards: Shift-click file 0 -> selects range 0..=1 (since anchor was 1)
	Editor_SelectAssetRange(&state, "/project/textures/0.png", files)
	testing.expect(t, Editor_AssetSelectedCount(&state) == 2, "Count should be 2")
	testing.expect(t, Editor_AssetIsSelected(&state, "/project/textures/0.png"))
	testing.expect(t, Editor_AssetIsSelected(&state, "/project/textures/1.png"))
	testing.expect(t, !Editor_AssetIsSelected(&state, "/project/textures/2.png"))
	testing.expect_value(t, state.assetAnchorPath, "/project/textures/1.png")
	testing.expect_value(t, state.selectedAssetPath, "/project/textures/0.png")

	// Shift-click with non-existent anchor falls back safely
	delete(state.assetAnchorPath)
	state.assetAnchorPath = ""
	Editor_SelectAssetRange(&state, "/project/textures/4.png", files)
	testing.expect(t, Editor_AssetSelectedCount(&state) == 1)
	testing.expect(t, Editor_AssetIsSelected(&state, "/project/textures/4.png"))
}

@test
test_asset_selection_clear :: proc(t: ^testing.T) {
	state: EditorState
	defer Editor_ClearAssetSelection(&state)

	Editor_SelectAsset(&state, "/project/textures/a.png")
	Editor_ToggleAssetSelection(&state, "/project/textures/b.png")
	testing.expect(t, Editor_AssetSelectedCount(&state) == 2)

	Editor_ClearAssetSelection(&state)
	testing.expect(t, Editor_AssetSelectedCount(&state) == 0)
	testing.expect_value(t, state.selectedAssetPath, "")
	testing.expect(t, !Editor_AssetIsSelected(&state, "/project/textures/a.png"))
	testing.expect(t, !Editor_AssetIsSelected(&state, "/project/textures/b.png"))
}
