package engine

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

@(test)
test_animation_editing :: proc(t: ^testing.T) {
	dir, _ := filepath.join({os.get_env("TMPDIR", context.temp_allocator), "ore_anim_edit"}, context.temp_allocator)
	_ = os.remove_all(dir)
	_ = os.make_directory_all(dir)
	defer os.remove_all(dir)
	paths := make([dynamic]string, context.temp_allocator)
	for n in ([]string{"a", "b", "c", "d", "e"}) {
		p, _ := filepath.join({dir, strings.concatenate({n, ".png"}, context.temp_allocator)}, context.temp_allocator)
		_ = os.write_entire_file(p, transmute([]u8)string("x")) // headless: the file only has to exist
		append(&paths, p)
	}
	name :: proc(fa: ^FrameAnimation) -> string {
		sb := strings.builder_make(context.temp_allocator)
		for f in fa.frames do strings.write_string(&sb, filepath.stem(f.filePath))
		return strings.to_string(sb)
	}

	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("anim", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	rm := &game.resourceManager
	apn := cast(^AnimationPlayerNode)Node_CreateByTypeName(scene, "AnimationPlayerNode")
	apn.name = "Hero"
	walk := AnimationPlayerNode_AddFrameAnimation(apn, rm, "walk", paths[:])
	testing.expect_value(t, name(walk), "abcde")
	testing.expect(t, walk.startFrame == 0 && walk.endFrame == 4, "full range")

	// Range: frames 1..3 (b c d); adding a frame doesn't stretch a shorter range.
	Animation_SetRange(walk, 1, 3)
	FrameAnimation_AddFrame(walk, rm, paths[0])
	testing.expect(t, walk.startFrame == 1 && walk.endFrame == 3, "range kept")
	Animation_RemoveFrames(apn, walk, {5}, rm)

	// Remove before the range: it moves; remove inside: it shrinks.
	testing.expect_value(t, Animation_RemoveFrames(apn, walk, {0}, rm), 1)
	testing.expect(t, name(walk) == "bcde" && walk.startFrame == 0 && walk.endFrame == 2, "moved")
	Animation_RemoveFrames(apn, walk, {1}, rm)
	testing.expect(t, name(walk) == "bde" && walk.startFrame == 0 && walk.endFrame == 1, "shrunk")

	// Copy b d, paste right after the range (2): the range grows over them.
	clip: Frame_Clip
	defer {Frame_ClipClear(&clip); delete(clip.paths); delete(clip.cells)}
	testing.expect_value(t, Animation_CopyFrames(walk, {1, 0}, &clip), 2)
	testing.expect_value(t, Animation_PasteFrames(apn, walk, 2, &clip, rm), 2)
	testing.expect(t, name(walk) == "bdbde" && walk.startFrame == 0 && walk.endFrame == 3, "pasted into the range")

	// Sheet cells: removing from a plain 4x1 grid makes a cell list.
	sheet := AnimationPlayerNode_AddSheetAnimation(apn, nil, "spin", "", {4, 1}, 0, 3)
	Animation_RemoveFrames(apn, sheet, {1}, rm)
	testing.expect(t, len(sheet.cells) == 3 && sheet.cells[1] == 2 && sheet.endFrame == 2, "cells")
	Animation_CopyFrames(sheet, {0}, &clip)
	Animation_PasteFrames(apn, sheet, 0, &clip, rm)
	testing.expect(t, len(sheet.cells) == 4 && sheet.cells[0] == 0 && sheet.cells[1] == 0 && sheet.endFrame == 3, "cell pasted")

	// Per-animation reverse and FPS.
	walk.reverse = true
	walk.fps = 24
	AnimationPlayerNode_SetFPS(apn, 10)
	AnimationPlayerNode_SetAnimationByName(apn, "walk")
	testing.expect_value(t, apn.ticker.framesPerSecond, f32(24))
	AnimationPlayerNode_Start(apn)
	testing.expect_value(t, apn.currentFrame, walk.endFrame)
	AnimationPlayerNode_AdvanceFrame(apn)
	testing.expect_value(t, apn.currentFrame, walk.endFrame - 1)
	AnimationPlayerNode_SetAnimationByName(apn, "spin")
	testing.expect_value(t, apn.ticker.framesPerSecond, f32(10)) // the player's
	apn.reverse = true // the player's Reverse flips each animation's
	testing.expect(t, AnimationPlayerNode_IsReversed(apn, sheet) && !AnimationPlayerNode_IsReversed(apn, walk), "flipped")
	apn.reverse = false

	// Saved and loaded, with "walk" as the default animation.
	apn.defaultAnimation = "walk"
	text := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expect(t, strings.contains(text, `"default_animation": "walk"`), "default saved")
	testing.expect(t, strings.contains(text, `"reverse": true, "fps": 24`), "reverse / fps saved")
	testing.expect(t, strings.contains(text, `"start": 0, "end": 3`), "range saved")
	s2 := game->createScene("anim2", false)
	Scene_InstantiateFromJSON(s2, transmute([]u8)text, &game.gameContext)
	ProcessNodeQueues(s2.manager, &game.gameContext)
	h := cast(^AnimationPlayerNode)Scene_FindNodeByName(s2, "Hero")
	testing.expect(t, h != nil && h.defaultAnimation == "walk" && AnimationPlayerNode_GetAnimationName(h) == "walk", "default selected")
	w2 := h.animations[0]
	testing.expect(t, w2.reverse && w2.fps == 24 && w2.startFrame == 0 && w2.endFrame == 3 && Animation_SourceCount(w2) == 5, "loaded")
	testing.expect_value(t, h.fps, f32(10))
}
