package engine

import "core:testing"

// The editor's platformer template drives a Script-mode CharacterMover:
// it falls and lands, runs with move_right, jumps with jump and lands again.
@(test)
test_character_platformer_template :: proc(t: ^testing.T) {
	ScriptVFS_RegisterEmbedded("player_tpl.lua", CharacterTemplate_Fill(CHARACTER_PLATFORMER_TEMPLATE, "player_tpl", "PlayerTpl", context.temp_allocator))
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("tpl", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	game.physicsWorld.gravity = {0, 980}

	floor := StaticBodyNode_Create(scene, "Floor")
	floor.position = {400, 420}
	floor.globalPosition = floor.position
	floor.gameContext = &game.gameContext
	StaticBodyNode_AddShape(floor, MakeBoxPhysicsShape(2000, 40, {0, 0}, 0), &game.gameContext)

	mover := CharacterMoverNode_Create(scene, "Player")
	mover.position = {400, 300}
	mover.controlMode = .Script
	mover.enableKeyboardInput = false
	mover.gameContext = &game.gameContext
	inst := Script_AttachToNode(mover, "player_tpl.lua", nil, &game.scriptManager)
	testing.expect(t, inst != nil, "template compiles and attaches")
	if inst == nil do return
	testing.expect_value(t, inst.properties["jump_velocity"].valFloat, f32(420))
	testing.expect_value(t, inst.properties["wall_slide"].type, ScriptPropertyType.Boolean)

	for _ in 0 ..< 90 do game->run(1.0 / 60)
	testing.expectf(t, mover.isOnFloor, "landed on the floor (y=%v)", mover.position.y)
	rest := mover.position.y
	testing.expectf(t, rest > 340 && rest < 400, "resting on top of the floor (y=%v)", rest)

	// Run right.
	x0 := mover.position.x
	Input_SetSimulatedKey(&game.input, .D, true)
	for _ in 0 ..< 30 do game->run(1.0 / 60)
	Input_SetSimulatedKey(&game.input, .D, false)
	testing.expectf(t, mover.position.x > x0 + 40, "ran right (%v -> %v)", x0, mover.position.x)
	testing.expectf(t, abs(mover.position.y - rest) < 2, "stayed on the floor while running (y=%v)", mover.position.y)

	// Jump: up, then back down onto the floor.
	Input_SetSimulatedKey(&game.input, .SPACE, true)
	game->run(1.0 / 60)
	Input_SetSimulatedKey(&game.input, .SPACE, false)
	peak := mover.position.y
	for _ in 0 ..< 20 {
		game->run(1.0 / 60)
		peak = min(peak, mover.position.y)
	}
	testing.expectf(t, peak < rest - 20, "jumped (rest %v, peak %v)", rest, peak)
	for _ in 0 ..< 120 do game->run(1.0 / 60)
	testing.expectf(t, mover.isOnFloor && abs(mover.position.y - rest) < 2, "landed again (y=%v)", mover.position.y)
	testing.expect_value(t, mover.controlMode, CharacterMoverMode.Script)
}
