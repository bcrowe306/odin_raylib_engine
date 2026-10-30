package engine

import "core:strings"
import "core:testing"
import lua "lua54"

// #176: keys in seconds - continuous sampling, older frame keys converted,
// tracks longer than the frames (loops, the end), bezier handles, stepped
// enum / string tracks, particle key actions.

@(private = "file")
time_game :: proc(name: string) -> (^Game, ^Scene, ^AnimationPlayerNode) {
	game := new(Game)
	InitializeGame(game)
	scene := game->createScene(name, true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	apn := cast(^AnimationPlayerNode)Node_CreateByTypeName(scene, "AnimationPlayerNode")
	apn.name = "Player"
	apn.gameContext = &game.gameContext
	return game, scene, apn
}

@(test)
test_animation_keys_in_seconds :: proc(t: ^testing.T) {
	game, _, apn := time_game("seconds")
	defer game->terminate()
	// 4 frames at 2 fps (2 s); rotation keyed 0 -> 200 over 2 s.
	anim := AnimationPlayerNode_AddFrameAnimation(apn, nil, "slow", nil)
	anim.endFrame = 3
	anim.fps = 2
	tr := Animation_AddTrack(apn, anim, ".", "rotation")
	Track_SetKey(tr, 0, {0, 0, 0, 0})
	Track_SetKey(tr, 2, {200, 0, 0, 0})
	testing.expect_value(t, Animation_Duration(apn, anim), 2)
	AnimationPlayerNode_Play(apn, "slow")
	for _ in 0 ..< 15 do game->run(1.0 / 60) // a quarter second: still frame 0
	testing.expect_value(t, apn.currentFrame, 0)
	testing.expectf(t, apn.rotation > 20 && apn.rotation < 30, "between frames, the value moves on (not stepping with the 2 fps frames): %v", apn.rotation)

	// Frame / time conversions, with a longer frame.
	Animation_SetFrameDuration(anim, 1, 1.5)
	testing.expect_value(t, Animation_FrameTime(apn, anim, 2), 2.0) // 0.5 + 1.5
	testing.expect_value(t, Animation_TimeFrame(apn, anim, 1.25), 1.5)
}

@(test)
test_animation_legacy_frame_keys :: proc(t: ^testing.T) {
	game, scene, _ := time_game("legacy")
	defer game->terminate()
	// A scene saved before keys in seconds: frames at the player's 10 fps.
	text := `{"name": "legacy", "root": {"type": "Node", "name": "root", "children": [
		{"type": "AnimationPlayerNode", "name": "Old", "fps": 10, "animations": [{"name": "a", "type": "frames", "frames": [], "loop": true,
		 "tracks": [{"target": ".", "property": "rotation", "keys": [[0, 0, 0, 0, 0, "linear", [0.42, 0, 0.58, 1]], [5, 100, 0, 0, 0]]},
		            {"target": ".", "property": "@call", "kind": "method", "keys": [[2, "hit", "x"]]}]}]}]}}`
	testing.expect(t, Scene_InstantiateFromJSON(scene, transmute([]u8)string(text), &game.gameContext), "loads")
	ProcessNodeQueues(scene.manager, &game.gameContext)
	old := cast(^AnimationPlayerNode)Scene_FindNodeByName(scene, "Old")
	if !testing.expect(t, old != nil, "found") do return
	a := AnimationPlayerNode_GetAnimation(old)
	if !testing.expect(t, a != nil && len(a.tracks) == 2, "tracks") do return
	rot := &a.tracks[0]
	testing.expect_value(t, rot.keys[1].time, 0.5) // frame 5 at 10 fps
	testing.expect(t, rot.keys[0].bezier, "the custom curve: bezier handles")
	c, _ := Track_SegmentCurve(rot, 0)
	testing.expectf(t, abs(c[0] - 0.42) < 0.001 && abs(c[2] - 0.58) < 0.001, "the same shape: %v", c)
	v, _ := Track_Sample(rot, 0.25)
	testing.expectf(t, abs(v[0] - 50) < 0.5, "symmetric curve: halfway at half time (%v)", v[0])
	testing.expect_value(t, a.tracks[1].keys[0].time, 0.2)
	testing.expect_value(t, a.tracks[1].keys[0].arg, "x")
	// Saved again: in seconds.
	saved := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expectf(t, strings.contains(saved, `"units": "seconds"`) && strings.contains(saved, `{"t": 0.2, "text": "hit", "arg": "x"}`), "saved in seconds: %s", saved)
}

@(test)
test_animation_tracks_longer_than_frames :: proc(t: ^testing.T) {
	ScriptVFS_RegisterEmbedded("anim_longer.lua", `
local P = {}
function P:ping() pings = (pings or 0) + 1 end
function P:on_animation_finished() finished = (finished or 0) + 1 end
return P
`)
	game, scene, apn := time_game("longer")
	defer game->terminate()
	Script_AttachToNode(apn, "anim_longer.lua", nil, &game.scriptManager)
	ProcessNodeQueues(scene.manager, &game.gameContext)
	// One frame (1/12 s) but keys up to 1 s: the tracks decide the length.
	once := AnimationPlayerNode_AddFrameAnimation(apn, nil, "once", nil)
	once.loop = false
	tr := Animation_AddTrack(apn, once, ".", "rotation")
	Track_SetKey(tr, 0, {0, 0, 0, 0})
	Track_SetKey(tr, 1, {90, 0, 0, 0})
	calls := Animation_AddEventTrack(apn, once, ".", .Method)
	Track_SetEventKey(calls, 0.5, "ping", apn.allocator)
	testing.expect(t, Animation_TracksLonger(apn, once), "the tracks run longer")
	AnimationPlayerNode_Play(apn, "once")
	for _ in 0 ..< 90 do game->run(1.0 / 60)
	testing.expectf(t, abs(apn.rotation - 90) < 0.01, "ran to the last key: %v", apn.rotation)
	get :: proc(game: ^Game, name: cstring) -> int {
		L := game.scriptManager.L
		lua.getglobal(L, name)
		defer lua.pop(L, 1)
		return int(lua.tointeger(L, -1))
	}
	testing.expect_value(t, get(game, "pings"), 1)
	testing.expect_value(t, get(game, "finished"), 1)

	// Looping: the event once per loop, loops counted by the tracks.
	once.loop = true
	AnimationPlayerNode_Play(apn, "once")
	for _ in 0 ..< 130 do game->run(1.0 / 60) // ~2.17 s: two loops done
	testing.expect_value(t, apn.loopsDone, 2)
	testing.expect_value(t, get(game, "pings"), 1 + 2) // (2.17 s: at 0.5 and 1.5) + the first run
}

@(test)
test_animation_bezier_handles :: proc(t: ^testing.T) {
	tr := Property_Track{keys = make([dynamic]Track_Key, context.temp_allocator)}
	Track_SetKey(&tr, 0, {0, 0, 0, 0})
	Track_SetKey(&tr, 1, {100, 0, 0, 0})
	tr.keys[0].bezier = true
	// Leaving fast and overshooting up, arriving flat.
	tr.keys[0].outTan[0] = {0.3, 150}
	tr.keys[1].inTan[0] = {-0.3, 0}
	v, _ := Track_Sample(&tr, 0.5)
	testing.expectf(t, v[0] > 100, "overshoots: %v", v[0])
	end, _ := Track_Sample(&tr, 1)
	testing.expect_value(t, end[0], 100)
	// Linear-looking handles: about linear.
	tr.keys[0].outTan[0] = {1.0 / 3, 100.0 / 3}
	tr.keys[1].inTan[0] = {-1.0 / 3, -100.0 / 3}
	v, _ = Track_Sample(&tr, 0.5)
	testing.expectf(t, abs(v[0] - 50) < 0.01, "a straight line: %v", v[0])
}

@(test)
test_animation_stepped_tracks_and_particle_actions :: proc(t: ^testing.T) {
	game, scene, apn := time_game("stepped")
	defer game->terminate()
	pen := ParticleEmitterNode_Create(scene, "Sparks")
	pen.gameContext = &game.gameContext
	AddChild(scene.manager, apn, pen)
	ParticleEmitterNode_Stop(pen)
	label := Node_CreateByTypeName(scene, "TextNode", apn)
	label.name = "Label"
	ProcessNodeQueues(scene.manager, &game.gameContext)
	anim := AnimationPlayerNode_AddFrameAnimation(apn, nil, "show", nil)
	// An enum (the particles' shape) and a string (the label's text): step.
	shape := Animation_AddTrack(apn, anim, "Sparks", "emitter.shape")
	Track_SetKey(shape, 0, {f32(int(ParticleShape.Circle)), 0, 0, 0})
	Track_SetKey(shape, 1, {f32(int(ParticleShape.Rectangle)), 0, 0, 0})
	text := Animation_AddTrack(apn, anim, "Label", "text")
	Track_SetEventKey(text, 0, "Ready", apn.allocator)
	Track_SetEventKey(text, 1, "Go!", apn.allocator)
	AnimationPlayerNode_ApplyTracks(apn, 0.9)
	testing.expect_value(t, pen.emitter.shape, ParticleShape.Circle) // (held: no in-between)
	testing.expect_value(t, (cast(^TextNode)label).text, "Ready")
	AnimationPlayerNode_ApplyTracks(apn, 1.0)
	testing.expect_value(t, pen.emitter.shape, ParticleShape.Rectangle)
	testing.expect_value(t, (cast(^TextNode)label).text, "Go!")
	p, _ := Track_FindProperty(pen, "emitter.shape")
	testing.expect(t, Track_IsAnimatable(p) && Track_IsStepped(p), "enums: animatable, stepped")

	// Particle keys: emit N, stop, start, restart (older text: restart).
	a, n := Particle_KeyAction("emit 7")
	testing.expect(t, a == .Emit && n == 7, "emit 7")
	a, _ = Particle_KeyAction("burst")
	testing.expect_value(t, a, Particle_Key_Action.Restart)
	burst := Animation_AddEventTrack(apn, anim, "Sparks", .EmitParticles)
	Track_SetEventKey(burst, 0.5, Particle_KeyText(.Emit, 7), apn.allocator)
	AnimationPlayerNode_FireEvents(apn, 0, 0.6)
	game->run(1.0 / 60)
	testing.expect_value(t, pen.emitter.aliveCount, 7)
	testing.expect(t, !pen.emitter.emitting, "a burst doesn't start emitting")
}
