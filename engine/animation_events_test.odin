package engine

import "core:strings"
import "core:testing"
import lua "lua54"

@(test)
test_animation_method_tracks_and_crossfade :: proc(t: ^testing.T) {
	ScriptVFS_RegisterEmbedded("anim_events.lua", `
local A = {}
A.properties = {}
function A:ready() calls = "" end
function A:on_step(frame) calls = calls .. "step" .. frame .. ";" end
function A:on_land(frame) calls = calls .. "land" .. frame .. ";" end
return A
`)
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("events", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	apn := cast(^AnimationPlayerNode)Node_CreateByTypeName(scene, "AnimationPlayerNode")
	apn.name = "Player"
	apn.gameContext = &game.gameContext
	hero := Node_CreateByTypeName(scene, "Node", apn)
	hero.name = "Hero"
	hero.gameContext = &game.gameContext
	Script_AttachToNode(hero, "anim_events.lua", nil, &game.scriptManager)

	walk := AnimationPlayerNode_AddFrameAnimation(apn, nil, "walk", nil)
	walk.endFrame = 5
	walk.loop = false
	F :: proc(apn: ^AnimationPlayerNode, a: ^Animation, f: f32) -> f32 {return Animation_FrameTime(apn, a, f)}
	calls := Animation_AddEventTrack(apn, walk, "Hero", .Method)
	Track_SetEventKey(calls, F(apn, walk, 1), "on_step", apn.allocator)
	Track_SetEventKey(calls, F(apn, walk, 4), "on_land", apn.allocator)
	rot := Animation_AddTrack(apn, walk, ".", "rotation")
	Track_SetKey(rot, 0, {0, 0, 0, 0})
	Track_SetKey(rot, F(apn, walk, 5), {100, 0, 0, 0})
	game->run(0.016)

	// Playing through the frames fires the keys once each (with their frame).
	AnimationPlayerNode_Play(apn, "walk")
	for _ in 0 ..< 60 do game->run(1.0 / 60) // (6 frames at 12 fps: 0.5 s)
	L := game.scriptManager.L
	lua.getglobal(L, "calls")
	testing.expect_value(t, string(lua.tostring(L, -1)), "step1;land4;")
	lua.pop(L, 1)
	// Scrubbing (editor) doesn't fire them.
	AnimationPlayerNode_ApplyTracks(apn, F(apn, walk, 4))
	lua.getglobal(L, "calls")
	testing.expect_value(t, string(lua.tostring(L, -1)), "step1;land4;")
	lua.pop(L, 1)

	// Crossfade: "idle" holds rotation 0; blending from walk at frame 5
	// (rotation 100) over 1s goes through the middle.
	idle := AnimationPlayerNode_AddFrameAnimation(apn, nil, "idle", nil)
	idle.endFrame = 5
	irot := Animation_AddTrack(apn, idle, ".", "rotation")
	Track_SetKey(irot, 0, {0, 0, 0, 0})
	apn.currentFrame = 5
	AnimationPlayerNode_SetAnimationByName(apn, "walk")
	apn.time = F(apn, walk, 5) // (walk at its end)
	AnimationPlayerNode_Play(apn, "idle", 1.0)
	apn.blendElapsed = 0.5
	AnimationPlayerNode_ApplyTracks(apn, 0)
	testing.expectf(t, abs(apn.rotation - 50) < 0.01, "half-way through the crossfade: %v", apn.rotation)
	apn.blendElapsed = 1.0
	AnimationPlayerNode_ApplyTracks(apn, 0)
	testing.expectf(t, abs(apn.rotation) < 0.01, "crossfade done: %v", apn.rotation)

	// Saved and loaded.
	text := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expectf(t, strings.contains(text, `"property": "@call", "kind": "method", "units": "seconds", "keys": [{"t": `) && strings.contains(text, `"text": "on_step"}`) && strings.contains(text, `"text": "on_land"}`), "method track saved: %s", text)
	s2 := game->createScene("events2", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	Scene_InstantiateFromJSON(s2, transmute([]u8)text, &game.gameContext)
	ProcessNodeQueues(s2.manager, &game.gameContext)
	p2 := cast(^AnimationPlayerNode)Scene_FindNodeByName(s2, "Player")
	a2: ^Animation
	if p2 != nil do for a in p2.animations do if a.name == "walk" do a2 = a
	testing.expect(t, a2 != nil && a2.tracks[0].kind == .Method && a2.tracks[0].keys[1].text == "on_land", "method track loaded")

}

// Custom key curves (cubic Bezier: shape, overshoot, sampling), saved and
// loaded with the key; Method keys with an argument (a number or text) and
// the player's animation_event signal.
@(test)
test_animation_curves_and_event_args :: proc(t: ^testing.T) {
	// The curve itself.
	testing.expectf(t, abs(Curve_Eval({0.25, 0.25, 0.75, 0.75}, 0.3) - 0.3) < 0.01, "a straight curve is linear")
	io := [4]f32{0.42, 0, 0.58, 1}
	testing.expectf(t, abs(Curve_Eval(io, 0.5) - 0.5) < 0.01, "ease in out: half way at half time")
	testing.expect(t, Curve_Eval(io, 0.2) < 0.2 && Curve_Eval(io, 0.8) > 0.8, "slow at the ends")
	testing.expect(t, Curve_Eval({0.34, 1.56, 0.64, 1}, 0.7) > 1, "back out overshoots")
	testing.expect(t, Curve_Eval(io, 0) == 0 && abs(Curve_Eval(io, 1) - 1) < 0.001, "ends at 0 and 1")

	ScriptVFS_RegisterEmbedded("anim_args.lua", `
local A = {}
A.properties = {}
function A:ready() got = "" end
function A:hit(v) got = got .. type(v) .. ":" .. tostring(v) .. ";" end
return A
`)
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("curves", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	apn := cast(^AnimationPlayerNode)Node_CreateByTypeName(scene, "AnimationPlayerNode")
	apn.name = "Player"
	apn.gameContext = &game.gameContext
	Script_AttachToNode(apn, "anim_args.lua", nil, &game.scriptManager)
	jump := AnimationPlayerNode_AddFrameAnimation(apn, nil, "jump", nil)
	jump.endFrame = 4
	jump.loop = false
	y := Animation_AddTrack(apn, jump, ".", "rotation")
	Track_SetKey(y, 0, {0, 0, 0, 0})
	Track_SetKey(y, Animation_FrameTime(apn, jump, 4), {100, 0, 0, 0})
	Track_SetSegmentCurve(y, 0, io)
	v, _ := Track_Sample(y, Animation_FrameTime(apn, jump, 1))
	testing.expectf(t, v[0] < 25, "sampled through the curve (%v, linear would be 25)", v[0])
	calls := Animation_AddEventTrack(apn, jump, ".", .Method)
	Track_SetEventKey(calls, Animation_FrameTime(apn, jump, 1), "hit", apn.allocator)
	Track_SetEventKey(calls, Animation_FrameTime(apn, jump, 2), "hit", apn.allocator)
	calls.keys[0].arg = strings.clone("2.5", apn.allocator)
	calls.keys[1].arg = strings.clone("heavy", apn.allocator)
	events := 0
	apn.onEvent->subscribe(proc(src: rawptr, v: EventValue, ctx: ^GameContext, ud: rawptr) {
		if s, ok := v.(string); ok && s == "hit" do (cast(^int)ud)^ += 1
	}, &events)
	game->run(0.016)
	AnimationPlayerNode_Play(apn, "jump")
	for _ in 0 ..< 40 do game->run(1.0 / 60) // (5 frames at 12 fps: 0.42 s)
	L := game.scriptManager.L
	lua.getglobal(L, "got")
	testing.expect_value(t, string(lua.tostring(L, -1)), "number:2.5;string:heavy;")
	lua.pop(L, 1)
	testing.expect_value(t, events, 2)

	// Saved and loaded.
	text := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expect(t, strings.contains(text, `"bezier": true`), text)
	testing.expect(t, strings.contains(text, `"text": "hit", "arg": "2.5"`), "argument saved")
	s2 := game->createScene("curves2", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	Scene_InstantiateFromJSON(s2, transmute([]u8)text, &game.gameContext)
	ProcessNodeQueues(s2.manager, &game.gameContext)
	p2 := cast(^AnimationPlayerNode)Scene_FindNodeByName(s2, "Player")
	a2: ^Animation
	if p2 != nil do for a in p2.animations do if a.name == "jump" do a2 = a
	if a2 != nil {
		c, isCurve := Track_SegmentCurve(&a2.tracks[0], 0)
		testing.expectf(t, isCurve && abs(c[0] - io[0]) < 0.001 && abs(c[1] - io[1]) < 0.001 && abs(c[2] - io[2]) < 0.001 && abs(c[3] - io[3]) < 0.001, "curve loaded: %v", c)
	}
	testing.expect(t, a2 != nil && a2.tracks[1].keys[1].arg == "heavy", "argument loaded")
}


@(test)
test_animation_single_frame_event_plays_once :: proc(t: ^testing.T) {
	ScriptVFS_RegisterEmbedded("anim_single.lua", `
local A = {}
A.properties = {}
function A:ready() calls = "" end
function A:on_single(frame) calls = calls .. "hit" .. frame .. ";" end
return A
`)
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("single_frame_events", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	apn := cast(^AnimationPlayerNode)Node_CreateByTypeName(scene, "AnimationPlayerNode")
	apn.name = "Player"
	apn.gameContext = &game.gameContext
	hero := Node_CreateByTypeName(scene, "Node", apn)
	hero.name = "Hero"
	hero.gameContext = &game.gameContext
	Script_AttachToNode(hero, "anim_single.lua", nil, &game.scriptManager)

	single := AnimationPlayerNode_AddFrameAnimation(apn, nil, "single", nil)
	single.startFrame = 0
	single.endFrame = 0
	single.loop = false
	calls := Animation_AddEventTrack(apn, single, "Hero", .Method)
	Track_SetEventKey(calls, 0, "on_single", apn.allocator)
	game->run(0.016)

	// Play single frame animation
	AnimationPlayerNode_Play(apn, "single")
	AnimationPlayerNode_AdvanceFrame(apn)

	L := game.scriptManager.L
	lua.getglobal(L, "calls")
	val := string(lua.tostring(L, -1))
	lua.pop(L, 1)
	testing.expect_value(t, val, "hit0;")
}

@(test)
test_animation_multiple_audio_tracks_and_settings :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("multi_audio_tracks", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running

	apn := cast(^AnimationPlayerNode)Node_CreateByTypeName(scene, "AnimationPlayerNode")
	apn.name = "Player"
	apn.gameContext = &game.gameContext

	anim := AnimationPlayerNode_AddFrameAnimation(apn, nil, "action", nil)
	anim.endFrame = 4

	// Add first audio track
	tr1 := Animation_AddEventTrack(apn, anim, ".", .Audio)
	testing.expect(t, tr1 != nil, "first audio track added")
	testing.expect_value(t, tr1.property, "@audio")
	testing.expect_value(t, tr1.name, "sounds")
	tr1.name = strings.clone("Footsteps", apn.allocator)
	tr1.audioSettings.bus = strings.clone("SFX", apn.allocator)
	tr1.audioSettings.volumeMin = 0.6
	tr1.audioSettings.volumeMax = 0.9
	tr1.audioSettings.pitchMin = 0.8
	tr1.audioSettings.pitchMax = 1.2
	tr1.audioSettings.positional = true
	tr1.audioSettings.minDistance = 80
	tr1.audioSettings.maxDistance = 500
	tr1.audioSettings.voices = 3
	Track_SetEventKey(tr1, 0, "step.wav", apn.allocator)

	// Add second audio track (Issue #27)
	tr2 := Animation_AddEventTrack(apn, anim, ".", .Audio)
	testing.expect(t, tr2 != nil, "second audio track added")
	testing.expect(t, tr1 != tr2, "two distinct audio tracks on the same animation")
	testing.expect_value(t, tr2.property, "@audio_2")
	testing.expect_value(t, tr2.name, "sounds 2")
	tr2.name = strings.clone("Voices", apn.allocator)
	tr2.audioSettings.bus = strings.clone("SFX", apn.allocator)
	tr2.audioSettings.volumeMin = 1.0
	tr2.audioSettings.volumeMax = 1.0
	Track_SetEventKey(tr2, 2, "grunt.wav", apn.allocator)

	testing.expect_value(t, len(anim.tracks), 2)

	// Serialize to JSON
	text := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expect(t, strings.contains(text, `"@audio_2"`), "second audio track serialized")
	testing.expect(t, strings.contains(text, `"Footsteps"`), "first track name serialized")
	testing.expect(t, strings.contains(text, `"Voices"`), "second track name serialized")
	testing.expect(t, strings.contains(text, `"audio_settings"`), "audio settings serialized")
	testing.expect(t, strings.contains(text, `"positional": true`), "positional setting serialized")

	// Instantiate in a second scene
	s2 := game->createScene("multi_audio_tracks_2", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	Scene_InstantiateFromJSON(s2, transmute([]u8)text, &game.gameContext)
	ProcessNodeQueues(s2.manager, &game.gameContext)

	p2 := cast(^AnimationPlayerNode)Scene_FindNodeByName(s2, "Player")
	testing.expect(t, p2 != nil, "Player node found in instantiated scene")
	a2: ^Animation
	if p2 != nil do for a in p2.animations do if a.name == "action" do a2 = a
	if testing.expect(t, a2 != nil, "action animation loaded") {
		if testing.expect_value(t, len(a2.tracks), 2) {
			t1_loaded := &a2.tracks[0]
			t2_loaded := &a2.tracks[1]
			testing.expect_value(t, t1_loaded.name, "Footsteps")
			testing.expect_value(t, t1_loaded.property, "@audio")
			testing.expect_value(t, t1_loaded.audioSettings.positional, true)
			testing.expect_value(t, t1_loaded.audioSettings.voices, 3)
			testing.expect_value(t, t1_loaded.audioSettings.minDistance, 80)
			testing.expect_value(t, t1_loaded.audioSettings.maxDistance, 500)
			testing.expect_value(t, len(t1_loaded.keys), 1)
			testing.expect_value(t, t1_loaded.keys[0].text, "step.wav")

			testing.expect_value(t, t2_loaded.name, "Voices")
			testing.expect_value(t, t2_loaded.property, "@audio_2")
			testing.expect_value(t, len(t2_loaded.keys), 1)
			testing.expect_value(t, t2_loaded.keys[0].text, "grunt.wav")
		}
	}
}
