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
	calls := Animation_AddEventTrack(apn, walk, "Hero", .Method)
	Track_SetEventKey(calls, 1, "on_step", apn.allocator)
	Track_SetEventKey(calls, 4, "on_land", apn.allocator)
	rot := Animation_AddTrack(apn, walk, ".", "rotation")
	Track_SetKey(rot, 0, {0, 0, 0, 0})
	Track_SetKey(rot, 5, {100, 0, 0, 0})
	game->run(0.016)

	// Playing through the frames fires the keys once each.
	AnimationPlayerNode_Play(apn, "walk")
	for _ in 0 ..< 6 do AnimationPlayerNode_AdvanceFrame(apn)
	L := game.scriptManager.L
	lua.getglobal(L, "calls")
	testing.expect_value(t, string(lua.tostring(L, -1)), "step1;land4;")
	lua.pop(L, 1)
	// Scrubbing (editor) doesn't fire them.
	AnimationPlayerNode_ApplyTracks(apn, 4)
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
	AnimationPlayerNode_Play(apn, "idle", 1.0)
	apn.blendElapsed = 0.5
	AnimationPlayerNode_ApplyTracks(apn, 0)
	testing.expectf(t, abs(apn.rotation - 50) < 0.01, "half-way through the crossfade: %v", apn.rotation)
	apn.blendElapsed = 1.0
	AnimationPlayerNode_ApplyTracks(apn, 0)
	testing.expectf(t, abs(apn.rotation) < 0.01, "crossfade done: %v", apn.rotation)

	// Saved and loaded.
	text := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expect(t, strings.contains(text, `"property": "@call", "kind": "method", "keys": [[1, "on_step"], [4, "on_land"]]`), "method track saved")
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
	Track_SetKey(y, 4, {100, 0, 0, 0})
	y.keys[0].curve, y.keys[0].hasCurve = io, true
	v, _ := Track_Sample(y, 1)
	testing.expectf(t, v[0] < 25, "sampled through the curve (%v, linear would be 25)", v[0])
	calls := Animation_AddEventTrack(apn, jump, ".", .Method)
	Track_SetEventKey(calls, 1, "hit", apn.allocator)
	Track_SetEventKey(calls, 2, "hit", apn.allocator)
	calls.keys[0].arg = strings.clone("2.5", apn.allocator)
	calls.keys[1].arg = strings.clone("heavy", apn.allocator)
	events := 0
	apn.onEvent->subscribe(proc(src: rawptr, v: EventValue, ctx: ^GameContext, ud: rawptr) {
		if s, ok := v.(string); ok && s == "hit" do (cast(^int)ud)^ += 1
	}, &events)
	game->run(0.016)
	AnimationPlayerNode_Play(apn, "jump")
	for _ in 0 ..< 5 do AnimationPlayerNode_AdvanceFrame(apn)
	L := game.scriptManager.L
	lua.getglobal(L, "got")
	testing.expect_value(t, string(lua.tostring(L, -1)), "number:2.5;string:heavy;")
	lua.pop(L, 1)
	testing.expect_value(t, events, 2)

	// Saved and loaded.
	text := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expect(t, strings.contains(text, `"linear", [0.42, 0, 0.58, 1]]`), text)
	testing.expect(t, strings.contains(text, `[1, "hit", "2.5"]`), "argument saved")
	s2 := game->createScene("curves2", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	Scene_InstantiateFromJSON(s2, transmute([]u8)text, &game.gameContext)
	ProcessNodeQueues(s2.manager, &game.gameContext)
	p2 := cast(^AnimationPlayerNode)Scene_FindNodeByName(s2, "Player")
	a2: ^Animation
	if p2 != nil do for a in p2.animations do if a.name == "jump" do a2 = a
	testing.expect(t, a2 != nil && a2.tracks[0].keys[0].hasCurve && a2.tracks[0].keys[0].curve == io, "curve loaded")
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
