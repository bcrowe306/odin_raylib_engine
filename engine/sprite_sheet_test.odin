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
