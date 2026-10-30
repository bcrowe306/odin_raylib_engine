package engine

import "core:testing"
import lua "lua54"

// #222: animation_play(name) of the animation already playing keeps it
// going (an unknown name changes nothing); bool tracks step at their keys;
// a Stop follower going backwards from 0 sets off from the far end.
@(test)
test_animation_play_same_bool_steps_path_backwards :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("anim222", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running

	apn := cast(^AnimationPlayerNode)Node_CreateByTypeName(scene, "AnimationPlayerNode")
	apn.name = "Player"
	apn.gameContext = &game.gameContext
	apn.fps = 10
	walk := AnimationPlayerNode_AddFrameAnimation(apn, nil, "walk", nil)
	walk.startFrame, walk.endFrame, walk.loop = 0, 7, true
	idle := AnimationPlayerNode_AddFrameAnimation(apn, nil, "idle", nil)
	idle.startFrame, idle.endFrame = 0, 3
	ProcessNodeQueues(scene.manager, &game.gameContext)
	AnimationPlayerNode_Play(apn, "walk")
	AnimationPlayerNode_Update(apn, &game.gameContext, 0.25)
	frame := apn.currentFrame
	testing.expect(t, frame >= 2, "walking")

	L := game.scriptManager.L
	testing.expect(t, lua.L_dostring(L, `Scene.find_node("Player"):animation_play("walk")`) == 0, "Lua ran")
	testing.expect_value(t, apn.currentFrame, frame)
	testing.expect(t, lua.L_dostring(L, `Scene.find_node("Player"):animation_play("nope")`) == 0, "Lua ran")
	testing.expect_value(t, apn.currentFrame, frame)
	testing.expect_value(t, apn.animations[apn.animationIndex].name, "walk")
	// Paused: naming it resumes it where it was.
	AnimationPlayerNode_Pause(apn)
	testing.expect(t, lua.L_dostring(L, `Scene.find_node("Player"):animation_play("walk")`) == 0, "Lua ran")
	testing.expect(t, apn.ticker.running && apn.currentFrame == frame, "resumed where it was")
	// Another animation (or no name) starts from its first frame.
	testing.expect(t, lua.L_dostring(L, `Scene.find_node("Player"):animation_play("idle")`) == 0, "Lua ran")
	testing.expect(t, apn.animations[apn.animationIndex].name == "idle" && apn.currentFrame == 0, "idle from the start")

	// Bools hold until the next key, whatever the easing.
	area := AreaNode_Create(scene, "Box")
	p, found := Track_FindProperty(area, "monitoring")
	testing.expect(t, found && Track_IsStepped(p), "a bool track steps")
	tr := Property_Track{keys = make([dynamic]Track_Key, context.temp_allocator)}
	Track_SetKey(&tr, 0, {1, 0, 0, 0})
	Track_SetKey(&tr, 1, {0, 0, 0, 0})
	k, _ := Track_SampleStep(&tr, 0.9)
	testing.expect_value(t, k.value[0], 1)
	k, _ = Track_SampleStep(&tr, 1)
	testing.expect_value(t, k.value[0], 0)

	// Backwards from 0 with Stop: from the far end, not finished at once.
	path := PathNode_Create(scene, "Path")
	f := PathFollowNode_Create(scene, "Follower", path)
	f.speed, f.loop, f.progress = -100, .Stop, 0
	finished := 0
	f.onFinished->subscribe(proc(src: rawptr, v: EventValue, ctx: ^GameContext, ud: rawptr) {(cast(^int)ud)^ += 1}, &finished)
	ProcessNodeQueues(scene.manager, &game.gameContext)
	game->run(0.1)
	length := Curve_Length(path)
	testing.expectf(t, !f.finished && finished == 0, "not finished on its first frame")
	testing.expectf(t, abs(f.progress - (length - 10)) < 0.5, "set off from the far end: %v of %v", f.progress, length)
	for _ in 0 ..< 200 do game->run(0.1)
	testing.expect(t, f.finished && finished == 1 && f.progress == 0, "finished at the start, once")
}
