package engine

import "core:strings"
import "core:testing"
import rl "vendor:raylib"

@(test)
test_sprite_sheet_cells :: proc(t: ^testing.T) {
	// 4x2 cells of 16x16 with a 2 px margin and 1 px spacing: 2+4*16+3+2 = 71 wide.
	size := [2]f32{71, 37}
	r := SpriteSheet_CellRect(size, {4, 2}, {2, 2}, {1, 1}, 0)
	testing.expect_value(t, r, rl.Rectangle{2, 2, 16, 16})
	r = SpriteSheet_CellRect(size, {4, 2}, {2, 2}, {1, 1}, 5) // column 1, row 1
	testing.expect_value(t, r, rl.Rectangle{19, 19, 16, 16})
	testing.expect_value(t, SpriteSheet_CellRect({64, 32}, {4, 2}, {}, {}, 7), rl.Rectangle{48, 16, 16, 16})

	// Saved and loaded with an AnimationPlayer: margin, spacing, chosen cells.
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("sheet", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	apn := cast(^AnimationPlayerNode)Node_CreateByTypeName(scene, "AnimationPlayerNode")
	apn.name = "Hero"
	ssa := AnimationPlayerNode_AddSheetAnimation(apn, nil, "run", "", {4, 2}, 0, 0)
	ssa.margin, ssa.spacing = {2, 2}, {1, 1}
	SpriteSheetAnimation_SetCells(ssa, {1, 2, 5, 6}, apn.allocator)
	testing.expect(t, ssa.startFrame == 0 && ssa.endFrame == 3 && ssa->frameCount() == 4, "four frames")
	text := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expect(t, strings.contains(text, `"margin": [2, 2], "spacing": [1, 1], "cells": [1, 2, 5, 6]`), "saved")
	s2 := game->createScene("sheet2", false)
	Scene_InstantiateFromJSON(s2, transmute([]u8)text, &game.gameContext)
	ProcessNodeQueues(s2.manager, &game.gameContext)
	h := cast(^AnimationPlayerNode)Scene_FindNodeByName(s2, "Hero")
	testing.expect(t, h != nil && len(h.animations) == 1, "loaded")
	s := cast(^SpriteSheetAnimation)h.animations[0]
	testing.expect(t, s.margin == {2, 2} && s.spacing == {1, 1} && len(s.cells) == 4 && s.cells[2] == 5 && s.endFrame == 3, "fields loaded")
}

// #233: slicing by cell size - exact whole-pixel cells, as many as fit (a
// sheet that isn't a whole number of cells, margin, spacing, a leftover
// strip); saved with the animation and the import preset; older files (no
// cell size) slice by the grid as before.
@(test)
test_sprite_sheet_cell_size :: proc(t: ^testing.T) {
	// 100 px wide, 32 px cells: 3 columns of exactly 32 (4 px unused), not 33.3.
	testing.expect_value(t, SpriteSheet_FitGrid({100, 70}, {}, {}, {32, 32}), [2]int{3, 2})
	testing.expect_value(t, SpriteSheet_CellRect({100, 70}, {3, 2}, {}, {}, 2, {32, 32}), rl.Rectangle{64, 0, 32, 32})
	testing.expect_value(t, SpriteSheet_CellRect({100, 70}, {3, 2}, {}, {}, 4, {32, 32}), rl.Rectangle{32, 32, 32, 32})
	// The grid way of the same sheet: fractional cells (unchanged).
	testing.expect(t, SpriteSheet_CellRect({100, 70}, {3, 2}, {}, {}, 1).width > 33, "by the grid: shared")
	// Margin and spacing: 2 px margin, 1 px spacing, 16 px cells in 80 px: (80-4+1)/17 = 4.
	testing.expect_value(t, SpriteSheet_FitGrid({80, 40}, {2, 2}, {1, 1}, {16, 16}), [2]int{4, 2})
	testing.expect_value(t, SpriteSheet_CellRect({80, 40}, {4, 2}, {2, 2}, {1, 1}, 5, {16, 16}), rl.Rectangle{19, 19, 16, 16})
	// Leftover strips stay unused: 52 px tall holds 3 rows of 16 (4 px left)
	// or 2 rows of 24 (4 px left).
	testing.expect_value(t, SpriteSheet_FitGrid({64, 52}, {}, {}, {16, 16}).y, 3)
	testing.expect_value(t, SpriteSheet_FitGrid({64, 52}, {}, {}, {16, 24}).y, 2)

	// Saved and loaded with the animation; an older scene has no cell size.
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("sheet_cells", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	apn := cast(^AnimationPlayerNode)Node_CreateByTypeName(scene, "AnimationPlayerNode")
	apn.name = "Hero"
	ssa := AnimationPlayerNode_AddSheetAnimation(apn, nil, "run", "", {3, 2}, 0, 0)
	SpriteSheetAnimation_SetCellSize(ssa, {32, 32})
	text := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expect(t, strings.contains(text, `"cell_size": [32, 32]`), "cell size saved")
	s2 := game->createScene("sheet_cells2", false)
	Scene_InstantiateFromJSON(s2, transmute([]u8)text, &game.gameContext)
	ProcessNodeQueues(s2.manager, &game.gameContext)
	h := cast(^AnimationPlayerNode)Scene_FindNodeByName(s2, "Hero")
	testing.expect(t, h != nil && (cast(^SpriteSheetAnimation)h.animations[0]).cellSize == {32, 32}, "cell size loaded")
	old, _ := strings.replace(text, `, "cell_size": [32, 32]`, "", 1, context.temp_allocator)
	s3 := game->createScene("sheet_cells3", false)
	Scene_InstantiateFromJSON(s3, transmute([]u8)old, &game.gameContext)
	ProcessNodeQueues(s3.manager, &game.gameContext)
	h3 := cast(^AnimationPlayerNode)Scene_FindNodeByName(s3, "Hero")
	testing.expect(t, h3 != nil && (cast(^SpriteSheetAnimation)h3.animations[0]).cellSize == {}, "an older scene slices by the grid")

	// The import preset keeps it too; an older preset has none.
	imp: Asset_Import
	imp.slice = {grid = {3, 2}, cellSize = {32, 32}}
	pre := Asset_ImportToJSON(imp, context.temp_allocator)
	testing.expect(t, strings.contains(pre, `"cell_size": [32, 32]`), "preset saved")
	back, older: Asset_Import
	Asset_ImportParse(pre, &back, context.temp_allocator)
	testing.expect_value(t, back.slice.cellSize, [2]int{32, 32})
	Asset_ImportParse(`{"slice": {"grid": [4, 1], "margin": [0, 0], "spacing": [0, 0]}}`, &older, context.temp_allocator)
	testing.expect_value(t, older.slice.cellSize, [2]int{})
}
