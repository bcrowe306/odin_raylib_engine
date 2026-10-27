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

@(test)
test_multiple_character_movers_input_isolation :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("multi_mover_test", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	game.physicsWorld.gravity = {0, 0}

	// 1. Player mover (Player 1)
	player := CharacterMoverNode_Create(scene, "Player")
	player.position = {100, 200}
	player.gameContext = &game.gameContext

	// 2. Enemy mover (created second - must default to no input / player 0)
	enemy := CharacterMoverNode_Create(scene, "Enemy")
	enemy.position = {300, 200}
	enemy.gameContext = &game.gameContext

	// 3. Foe mover with script attached (must not receive player keyboard input)
	foe := CharacterMoverNode_Create(scene, "Foe")
	foe.position = {500, 200}
	foe.gameContext = &game.gameContext

	testing.expect(t, player.enableKeyboardInput, "first character mover defaults to enableKeyboardInput = true")
	testing.expect_value(t, player.playerIndex, 1)
	testing.expect(t, !enemy.enableKeyboardInput, "subsequent character mover defaults to enableKeyboardInput = false")
	testing.expect_value(t, enemy.playerIndex, 0)
	testing.expect(t, !foe.enableKeyboardInput, "third character mover defaults to enableKeyboardInput = false")
	testing.expect_value(t, foe.playerIndex, 0)

	// Simulate pressing 'D' (MoveRight) for Player 1
	Input_SetSimulatedKey(&game.input, .D, true)
	for _ in 0 ..< 10 do game->run(1.0 / 60)
	Input_SetSimulatedKey(&game.input, .D, false)

	testing.expect(t, player.position.x > 100.0, "Player moved right on Player 1 input")
	testing.expect_value(t, enemy.position.x, f32(300.0))
	testing.expect_value(t, foe.position.x, f32(500.0))
}

@(test)
test_scene_serialization_multiple_character_movers_input_isolation :: proc(t: ^testing.T) {
	ScriptVFS_RegisterEmbedded("test_enemy.lua", `
local Enemy = {}
function Enemy:ready() end
function Enemy:update(dt) end
return Enemy
`)
	ScriptVFS_RegisterEmbedded("test_player.lua", `
local Player = {}
function Player:ready() end
function Player:update(dt)
    local dir = Input.get_axis("move_left", "move_right")
    if dir ~= 0 then
        local vx, vy = self.node:character_get_velocity()
        self.node:character_set_velocity(dir * 200, vy)
        self.node:character_move_and_slide()
    end
end
return Player
`)

	scene_json := `{"name": "test_scene", "root": {"type": "Node", "name": "root", "children": [
		{"type": "CharacterMoverNode", "name": "PlayerMover", "position": [100, 200], "properties": {"controlMode": "Script", "enableKeyboardInput": true}, "script": {"path": "test_player.lua"}},
		{"type": "CharacterMoverNode", "name": "EnemyMover", "position": [300, 200], "properties": {"controlMode": "BuiltIn", "enableKeyboardInput": true}, "script": {"path": "test_enemy.lua"}},
		{"type": "CharacterMoverNode", "name": "Foe1", "position": [500, 200], "properties": {"controlMode": "BuiltIn", "enableKeyboardInput": true}}
	]}}`

	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	game.state = .Running
	game.physicsWorld.gravity = {0, 0}

	scene := game->createScene("test_scene", true)
	Scene_InstantiateFromJSON(scene, transmute([]u8)scene_json, &game.gameContext)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)

	player := cast(^CharacterMoverNode)Scene_FindNodeByName(scene, "PlayerMover")
	enemy := cast(^CharacterMoverNode)Scene_FindNodeByName(scene, "EnemyMover")
	foe := cast(^CharacterMoverNode)Scene_FindNodeByName(scene, "Foe1")

	testing.expect(t, player != nil, "player exists")
	testing.expect(t, enemy != nil, "enemy exists")
	testing.expect(t, foe != nil, "foe exists")
	if player == nil || enemy == nil || foe == nil do return

	testing.expect_value(t, enemy.controlMode, CharacterMoverMode.Script)

	// Simulate pressing 'D' (MoveRight) for Player 1
	Input_SetSimulatedKey(&game.input, .D, true)
	for _ in 0 ..< 10 do game->run(1.0 / 60)
	Input_SetSimulatedKey(&game.input, .D, false)

	testing.expect(t, player.position.x > 100.0, "Player moved right on script input")
	testing.expect_value(t, enemy.position.x, f32(300.0)) // Enemy must not move
	testing.expect_value(t, foe.position.x, f32(500.0))   // Foe must not move
}
