package engine

import "core:strings"
import "core:testing"
import lua "vendor:lua/5.4"

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
