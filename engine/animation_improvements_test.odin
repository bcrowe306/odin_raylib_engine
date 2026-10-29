package engine

import "core:strings"
import "core:testing"
import "core:time"
import rl "vendor:raylib"

// ============================================================================
// Tests for Issue #100: Animations improvements
// ============================================================================

@(test)
test_ticker_dt_processing :: proc(t: ^testing.T) {
	tk: Ticker
	Ticker_Init(&tk, false)
	tk->setFPS(10) // 0.1s per tick
	ticks := 0
	tk->setCallback(proc(ticker: ^Ticker, currentTick: int, user_data: rawptr) {
		(cast(^int)user_data)^ += 1
	}, &ticks)
	tk->start(true)

	// Passing dt = 0.05s should not trigger a tick yet
	Ticker_ProcessDt(&tk, 0.05)
	testing.expect_value(t, ticks, 0)

	// Passing another dt = 0.05s (total 0.1s) should trigger 1 tick
	Ticker_ProcessDt(&tk, 0.05)
	testing.expect_value(t, ticks, 1)

	// Passing dt = 0.25s should trigger 2 ticks (0.2s) with 0.05s remaining
	Ticker_ProcessDt(&tk, 0.25)
	testing.expect_value(t, ticks, 3)

	// Passing 0.05s consumes the remainder and triggers 1 tick
	Ticker_ProcessDt(&tk, 0.05)
	testing.expect_value(t, ticks, 4)
}

@(test)
test_animation_player_dt_advancement :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("anim_dt", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running

	apn := cast(^AnimationPlayerNode)Node_CreateByTypeName(scene, "AnimationPlayerNode")
	apn.gameContext = &game.gameContext
	apn.fps = 10 // 0.1s per frame

	walk := AnimationPlayerNode_AddFrameAnimation(apn, nil, "walk", nil)
	walk.startFrame = 0
	walk.endFrame = 4
	walk.loop = true

	AnimationPlayerNode_Play(apn, "walk")
	testing.expect_value(t, apn.currentFrame, 0)

	// Advancing with dt = 0.05s: should remain on frame 0
	AnimationPlayerNode_Update(apn, &game.gameContext, 0.05)
	testing.expect_value(t, apn.currentFrame, 0)

	// Advancing with another dt = 0.05s (total 0.10s): should advance to frame 1
	AnimationPlayerNode_Update(apn, &game.gameContext, 0.05)
	testing.expect_value(t, apn.currentFrame, 1)

	// Advancing with dt = 0.20s: should advance two frames (1 -> 2 -> 3)
	AnimationPlayerNode_Update(apn, &game.gameContext, 0.20)
	testing.expect_value(t, apn.currentFrame, 3)
}

@(test)
test_animation_per_frame_durations :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("anim_dur", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running

	apn := cast(^AnimationPlayerNode)Node_CreateByTypeName(scene, "AnimationPlayerNode")
	apn.gameContext = &game.gameContext
	apn.fps = 10

	anim := AnimationPlayerNode_AddFrameAnimation(apn, nil, "custom_dur", nil)
	anim.startFrame = 0
	anim.endFrame = 2
	anim.loop = false

	// Frame 0: 0.2s, Frame 1: 0.5s, Frame 2: 0.1s
	Animation_SetFrameDuration(anim, 0, 0.2, apn.allocator)
	Animation_SetFrameDuration(anim, 1, 0.5, apn.allocator)
	Animation_SetFrameDuration(anim, 2, 0.1, apn.allocator)

	testing.expect_value(t, Animation_GetFrameDuration(anim, 0, apn.fps), f32(0.2))
	testing.expect_value(t, Animation_GetFrameDuration(anim, 1, apn.fps), f32(0.5))
	testing.expect_value(t, Animation_GetFrameDuration(anim, 2, apn.fps), f32(0.1))

	AnimationPlayerNode_Play(apn, "custom_dur")
	testing.expect_value(t, apn.currentFrame, 0)

	// 0.15s into frame 0 (duration 0.2s): still frame 0
	AnimationPlayerNode_Update(apn, &game.gameContext, 0.15)
	testing.expect_value(t, apn.currentFrame, 0)

	// Another 0.06s (total 0.21s): advances to frame 1
	AnimationPlayerNode_Update(apn, &game.gameContext, 0.06)
	testing.expect_value(t, apn.currentFrame, 1)

	// 0.40s into frame 1 (duration 0.5s): still frame 1
	AnimationPlayerNode_Update(apn, &game.gameContext, 0.40)
	testing.expect_value(t, apn.currentFrame, 1)

	// Another 0.15s: advances to frame 2
	AnimationPlayerNode_Update(apn, &game.gameContext, 0.15)
	testing.expect_value(t, apn.currentFrame, 2)
}

@(test)
test_animation_adhoc_frames_and_empty_frames :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("anim_frames", true)

	apn := cast(^AnimationPlayerNode)Node_CreateByTypeName(scene, "AnimationPlayerNode")
	anim := AnimationPlayerNode_AddFrameAnimation(apn, nil, "test_empty", nil)
	testing.expect_value(t, len(anim.frames), 0)

	// Add empty frames
	Animation_AddEmptyFrame(apn, anim)
	testing.expect_value(t, len(anim.frames), 1)
	testing.expect(t, anim.frames[0] == nil, "first frame is empty")
	testing.expect_value(t, anim.endFrame, 0)

	// Insert empty frame at index 0
	Animation_InsertEmptyFrame(apn, anim, 0)
	testing.expect_value(t, len(anim.frames), 2)
	testing.expect(t, anim.frames[0] == nil && anim.frames[1] == nil, "both frames empty")
	testing.expect_value(t, anim.endFrame, 1)

	// Render empty frame should not crash
	FA_RenderFrame(anim, 0, apn)

	// Remove frame
	removed := Animation_RemoveFrames(apn, anim, []int{0}, nil)
	testing.expect_value(t, removed, 1)
	testing.expect_value(t, len(anim.frames), 1)
}

@(test)
test_animation_any_scene_node_properties :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("anim_scene_props", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running

	// Root node with two children: Player (with apn) and Enemy
	root := scene.rootNode
	player := Node_CreateByTypeName(scene, "Node", root)
	player.name = "Player"
	player.gameContext = &game.gameContext

	apn := cast(^AnimationPlayerNode)Node_CreateByTypeName(scene, "AnimationPlayerNode", player)
	apn.name = "AnimPlayer"
	apn.gameContext = &game.gameContext

	enemy := Node_CreateByTypeName(scene, "Node", root)
	enemy.name = "Enemy"
	enemy.gameContext = &game.gameContext
	enemy.rotation = 0
	enemy.zIndex = 0
	enemy.enabled = true

	// Path from AnimPlayer to Enemy is "../../Enemy"
	relPath := Node_RelativePath(scene.manager, apn, enemy)
	testing.expect_value(t, relPath, "../../Enemy")

	anim := AnimationPlayerNode_AddFrameAnimation(apn, nil, "action", nil)
	anim.startFrame = 0
	anim.endFrame = 10

	// Track on Enemy's rotation
	rotTrack := Animation_AddTrack(apn, anim, relPath, "rotation")
	Track_SetKey(rotTrack, 0, {0, 0, 0, 0})
	Track_SetKey(rotTrack, 10, {180, 0, 0, 0})

	// Track on Enemy's zIndex
	zTrack := Animation_AddTrack(apn, anim, relPath, "zIndex")
	Track_SetKey(zTrack, 0, {1, 0, 0, 0})
	Track_SetKey(zTrack, 10, {5, 0, 0, 0})

	// Track on Enemy's enabled property (Bool animatable)
	enTrack := Animation_AddTrack(apn, anim, relPath, "enabled")
	Track_SetKey(enTrack, 0, {1, 0, 0, 0})
	Track_SetKey(enTrack, 5, {0, 0, 0, 0}) // disabled at frame 5

	// Apply tracks at frame 5
	AnimationPlayerNode_ApplyTracks(apn, 5)
	testing.expect_value(t, enemy.rotation, f32(90))
	testing.expect_value(t, enemy.zIndex, i32(3))
	testing.expect_value(t, enemy.enabled, false)

	// Apply tracks at frame 0
	AnimationPlayerNode_ApplyTracks(apn, 0)
	testing.expect_value(t, enemy.rotation, f32(0))
	testing.expect_value(t, enemy.zIndex, i32(1))
	testing.expect_value(t, enemy.enabled, true)
}

@(test)
test_animation_shortcut_track_types :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("anim_shortcuts", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running

	apn := cast(^AnimationPlayerNode)Node_CreateByTypeName(scene, "AnimationPlayerNode")
	apn.name = "Player"
	apn.gameContext = &game.gameContext

	emitter := ParticleEmitterNode_Create(scene, "SparkEmitter")
	emitter.gameContext = &game.gameContext
	AddChild(scene.manager, apn, emitter)
	emitter.emitter.emitting = false

	area := AreaNode_Create(scene, "Hitbox")
	area.gameContext = &game.gameContext
	AddChild(scene.manager, apn, area)
	area.enabled = true

	anim := AnimationPlayerNode_AddFrameAnimation(apn, nil, "attack", nil)
	anim.startFrame = 0
	anim.endFrame = 5

	// 1. Particle Track
	pTrack := Animation_AddEventTrack(apn, anim, "SparkEmitter", .EmitParticles)
	testing.expect(t, pTrack != nil && pTrack.kind == .EmitParticles, "particle track created")
	Track_SetEventKey(pTrack, 2, "burst", apn.allocator)

	// 2. Enable/Disable Track (toggle hitbox)
	enTrack := Animation_AddEventTrack(apn, anim, "Hitbox", .SetEnabled)
	testing.expect(t, enTrack != nil && enTrack.kind == .SetEnabled, "enabled track created")
	Track_SetEventKey(enTrack, 1, "disable", apn.allocator)
	Track_SetEventKey(enTrack, 3, "enable", apn.allocator)

	// Fire events at frame 1: should disable AreaNode
	AnimationPlayerNode_FireEvents(apn, 1)
	testing.expect_value(t, area.enabled, false)

	// Fire events at frame 2: should start particle emitter
	AnimationPlayerNode_FireEvents(apn, 2)
	testing.expect(t, emitter.emitter.emitting, "emitter started")

	// Fire events at frame 3: should re-enable AreaNode
	AnimationPlayerNode_FireEvents(apn, 3)
	testing.expect_value(t, area.enabled, true)
}

@(test)
test_animation_serialization_improvements :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("anim_ser_test", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running

	apn := cast(^AnimationPlayerNode)Node_CreateByTypeName(scene, "AnimationPlayerNode")
	apn.name = "Player"
	apn.gameContext = &game.gameContext

	anim := AnimationPlayerNode_AddFrameAnimation(apn, nil, "combo", nil)
	Animation_AddEmptyFrame(apn, anim)
	Animation_AddEmptyFrame(apn, anim)
	Animation_SetFrameDuration(anim, 0, 0.25, apn.allocator)
	Animation_SetFrameDuration(anim, 1, 0.75, apn.allocator)

	pTrack := Animation_AddEventTrack(apn, anim, ".", .EmitParticles)
	Track_SetEventKey(pTrack, 0, "burst", apn.allocator)

	sTrack := Animation_AddEventTrack(apn, anim, ".", .InstantiateComponent)
	Track_SetEventKey(sTrack, 1, "prefabs/bullet.component.json", apn.allocator)

	eTrack := Animation_AddEventTrack(apn, anim, ".", .SetEnabled)
	Track_SetEventKey(eTrack, 0, "disable", apn.allocator)

	text := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expect(t, strings.contains(text, `"frame_durations": [0.25, 0.75]`), "frame durations serialized")
	testing.expect(t, strings.contains(text, `"kind": "particles"`), "particles track serialized")
	testing.expect(t, strings.contains(text, `"kind": "spawn"`), "spawn track serialized")
	testing.expect(t, strings.contains(text, `"kind": "enable"`), "enable track serialized")

	s2 := game->createScene("anim_ser_reload", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	Scene_InstantiateFromJSON(s2, transmute([]u8)text, &game.gameContext)
	ProcessNodeQueues(s2.manager, &game.gameContext)

	apn2 := cast(^AnimationPlayerNode)Scene_FindNodeByName(s2, "Player")
	testing.expect(t, apn2 != nil, "player reloaded")
	anim2 := AnimationPlayerNode_GetAnimation(apn2)
	testing.expect(t, anim2 != nil, "animation reloaded")
	testing.expect_value(t, len(anim2.frameDurations), 2)
	testing.expect_value(t, anim2.frameDurations[0], f32(0.25))
	testing.expect_value(t, anim2.frameDurations[1], f32(0.75))

	fa2 := cast(^FrameAnimation)anim2
	testing.expect_value(t, len(fa2.frames), 2)
	testing.expect(t, fa2.frames[0] == nil && fa2.frames[1] == nil, "empty frames restored as nil")

	testing.expect_value(t, len(anim2.tracks), 3)
	testing.expect(t, anim2.tracks[0].kind == .EmitParticles, "particles track restored")
	testing.expect(t, anim2.tracks[1].kind == .InstantiateComponent, "spawn track restored")
	testing.expect(t, anim2.tracks[2].kind == .SetEnabled, "enable track restored")
}
