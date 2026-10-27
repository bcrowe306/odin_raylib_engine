package engine

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"
import lua "lua54"
import rl "vendor:raylib"

// The State Machine guide's tutorials (engine/docs/state_machine.md), run
// for real: the scenes and scripts in tests/state_machine/project are the
// ones the guide shows. Each test loads a scene, drives it frame by frame
// with simulated keys and checks what the guide promises. (The runner plays
// the same scenes in CI: tests/state_machine/runtime_tests.json.)

@(private = "file")
SMG_PROJECT :: "tests/state_machine/project"
@(private = "file")
SMG_DT :: f32(1.0 / 60)

// smg_load: a game running tests/state_machine/project/scenes/<scene>.scene.json
// with the project's scripts (registered under their scene paths).
@(private = "file")
smg_load :: proc(t: ^testing.T, scene_name: string, scripts: []string) -> (^Game, ^Scene, bool) {
	for s in scripts {
		path := fmt.tprintf("%s/scripts/%s", SMG_PROJECT, s)
		code, err := os.read_entire_file(path, context.temp_allocator)
		if !testing.expectf(t, err == nil, "%s: %v", path, err) do return nil, nil, false
		ScriptVFS_RegisterEmbedded(fmt.tprintf("scripts/%s", s), string(code))
	}
	path := fmt.tprintf("%s/scenes/%s.scene.json", SMG_PROJECT, scene_name)
	text, err := os.read_entire_file(path, context.temp_allocator)
	if !testing.expectf(t, err == nil, "%s: %v", path, err) do return nil, nil, false
	game := new(Game)
	InitializeGame(game)
	scene := game->createScene(scene_name, true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	if !testing.expectf(t, Scene_InstantiateFromJSON(scene, text, &game.gameContext), "%s loads", path) {
		game->terminate()
		return nil, nil, false
	}
	ProcessNodeQueues(scene.manager, &game.gameContext)
	return game, scene, true
}

// smg_exec: runs Lua code; false (a failure) on an error.
@(private = "file")
smg_exec :: proc(t: ^testing.T, L: ^lua.State, code: string) -> bool {
	if lua.L_dostring(L, strings.clone_to_cstring(code, context.temp_allocator)) != 0 {
		testing.expectf(t, false, "Lua: %s", lua.tostring(L, -1))
		lua.pop(L, 1)
		return false
	}
	return true
}

// smg_lua: a Lua expression's value as text (tostring).
@(private = "file")
smg_lua :: proc(t: ^testing.T, L: ^lua.State, expr: string) -> string {
	if !smg_exec(t, L, fmt.tprintf("__smg = tostring(%s)", expr)) do return ""
	lua.getglobal(L, "__smg")
	defer lua.pop(L, 1)
	return strings.clone(string(lua.tostring(L, -1)), context.temp_allocator)
}

// smg_until: runs frames until the machine is in `state` (at most max);
// how many it took (-1: never).
@(private = "file")
smg_until :: proc(game: ^Game, sm: ^StateMachineNode, state: string, max: int) -> int {
	for i in 1 ..= max {
		game->run(SMG_DT)
		if StateMachine_CurrentName(sm) == state do return i
	}
	return -1
}

// smg_press: a key goes down for one frame.
@(private = "file")
smg_press :: proc(game: ^Game, key: rl.KeyboardKey) {
	Input_SetSimulatedKey(&game.input, key, true)
	game->run(SMG_DT)
	Input_SetSimulatedKey(&game.input, key, false)
}

@(private = "file")
smg_entered :: proc(sm: ^StateMachineNode, state: string) -> int {
	n := 0
	for c in StateMachine_History(sm) do if c.to == state do n += 1
	return n
}

// Tutorial 1: Idle / Run / Jump / Fall from parameters; the jump trigger's
// 0.15 s buffer makes a jump pressed ~0.1 s before landing happen on
// landing; without the buffer the same press is lost.
@(test)
test_sm_guide_platformer :: proc(t: ^testing.T) {
	game, scene, ok := smg_load(t, "platformer", {"platformer_player.lua", "probe.lua"})
	if !ok do return
	defer game->terminate()
	game.physicsWorld.gravity = {0, 980}
	player := cast(^CharacterMoverNode)Scene_FindNodeByName(scene, "Player")
	sm := cast(^StateMachineNode)Scene_FindNodeByName(scene, "StateMachine")
	if !testing.expect(t, player != nil && sm != nil, "the tutorial's nodes") do return

	// Spawned in the air: Idle -> Fall -> Idle once landed.
	for _ in 0 ..< 120 do game->run(SMG_DT)
	testing.expect(t, player.isOnFloor, "landed")
	testing.expect_value(t, StateMachine_CurrentName(sm), "idle")
	testing.expect(t, smg_entered(sm, "fall") == 1, "fell first")
	rest := player.position.y

	// Running: Idle <-> Run from the speed parameter.
	Input_SetSimulatedKey(&game.input, .D, true)
	testing.expect(t, smg_until(game, sm, "run", 10) > 0, "runs")
	Input_SetSimulatedKey(&game.input, .D, false)
	testing.expect(t, smg_until(game, sm, "idle", 10) > 0, "stops")

	// A jump on the floor: Idle -> Jump at once (on_enter_jump pushes off), Fall at the top.
	smg_press(game, .SPACE)
	testing.expect_value(t, StateMachine_CurrentName(sm), "jump")
	testing.expect(t, smg_until(game, sm, "fall", 60) > 0, "falls after the top")
	testing.expect(t, player.position.y < rest - 20, "went up")

	// press_before_landing: falls until landing is under 0.1 s away, presses
	// jump there; (frames from the press to landing, ok).
	press_before_landing :: proc(t: ^testing.T, game: ^Game, player: ^CharacterMoverNode, sm: ^StateMachineNode, rest: f32) -> (int, bool) {
		for _ in 0 ..< 120 {
			gap, vy := rest - player.position.y, player.velocity.y
			if vy > 0 && gap > 0 && gap / vy <= 0.1 {
				testing.expect(t, StateMachine_CurrentName(sm) == "fall" && !player.isOnFloor, "pressed in the air")
				smg_press(game, .SPACE)
				frames := 1
				for !player.isOnFloor && frames < 30 {
					game->run(SMG_DT)
					frames += 1
				}
				return frames, true
			}
			game->run(SMG_DT)
		}
		return 0, false
	}

	// Buffered: pressed before landing, the jump happens on landing.
	jumps := smg_entered(sm, "jump")
	frames, pressed := press_before_landing(t, game, player, sm, rest)
	testing.expect(t, pressed, "came down")
	testing.expectf(t, frames >= 2 && f32(frames) * SMG_DT <= 0.15, "pressed %d frames before landing", frames)
	testing.expect_value(t, StateMachine_CurrentName(sm), "jump") // (on the landing update)
	testing.expect_value(t, smg_entered(sm, "jump"), jumps + 1)
	testing.expect(t, StateMachine_History(sm)[sm.historyLen - 1].from == "fall", "straight from Fall")
	testing.expect(t, player.velocity.y < 0, "pushed off")

	// Without the buffer the same press is dropped after one update: lands in Idle.
	sm.triggers[StateMachine_FindTrigger(sm, "jump")].buffer = 0
	testing.expect(t, smg_until(game, sm, "fall", 60) > 0, "falls again")
	jumps = smg_entered(sm, "jump")
	frames, pressed = press_before_landing(t, game, player, sm, rest)
	testing.expect(t, pressed && frames >= 2, "pressed before landing")
	for _ in 0 ..< 5 do game->run(SMG_DT)
	testing.expect_value(t, StateMachine_CurrentName(sm), "idle")
	testing.expect_value(t, smg_entered(sm, "jump"), jumps)
}

// Tutorial 2: the enemy's script decides with sm_transition along Manual
// arrows; the machine never moves by itself (except stunned -> patrol,
// Automatic); the attack's Leave After refuses an early exit with a reason;
// force skips it.
@(test)
test_sm_guide_enemy :: proc(t: ^testing.T) {
	game, scene, ok := smg_load(t, "enemy", {"enemy_brain.lua", "probe.lua"})
	if !ok do return
	defer game->terminate()
	enemy := Scene_FindNodeByName(scene, "Enemy")
	player := Scene_FindNodeByName(scene, "Player")
	sm := cast(^StateMachineNode)Scene_FindNodeByName(scene, "Brain")
	if !testing.expect(t, enemy != nil && player != nil && sm != nil, "the tutorial's nodes") do return
	L := game.scriptManager.L

	// Far away: patrols its route.
	for _ in 0 ..< 120 do game->run(SMG_DT)
	testing.expect_value(t, StateMachine_CurrentName(sm), "patrol")
	testing.expectf(t, enemy.position.x >= 55 && enemy.position.x <= 145, "on its route (x=%v)", enemy.position.x)

	// Close enough: the script chases (a manual change).
	player.position = {enemy.position.x + 100, enemy.position.y}
	testing.expect(t, smg_until(game, sm, "chase", 3) > 0, "chases")
	h := StateMachine_History(sm)
	testing.expect_value(t, h[len(h) - 1].why, "manual")

	// Closes in and attacks.
	testing.expect(t, smg_until(game, sm, "attack", 120) > 0, "attacks")
	testing.expect_value(t, smg_lua(t, L, `Scene.find_node("Enemy"):get_script().attacks`), "1")
	testing.expect(t, abs(player.position.x - enemy.position.x) < 21, "in reach")

	// The player steps back: the attack's Leave After (0.5 s) refuses chase for now.
	player.position.x = enemy.position.x + 60
	for _ in 0 ..< 12 do game->run(SMG_DT) // 0.2 s
	testing.expect_value(t, StateMachine_CurrentName(sm), "attack")
	refusal := smg_lua(t, L, `Scene.find_node("Enemy"):get_script().last_refusal`)
	testing.expectf(t, strings.contains(refusal, "leave after"), "says why: %q", refusal)
	testing.expect(t, smg_until(game, sm, "chase", 30) > 0, "chases again once allowed")
	h = StateMachine_History(sm)
	testing.expectf(t, h[len(h) - 1].time - h[len(h) - 2].time >= 0.5 - 0.02, "attacked for 0.5 s (%v)", h[len(h) - 1].time - h[len(h) - 2].time)

	// Stunned mid-attack: force skips Leave After; back to patrol after 1 s by itself.
	testing.expect(t, smg_until(game, sm, "attack", 120) > 0, "attacks again")
	smg_exec(t, L, `Scene.find_node("Enemy"):get_script():stun()`)
	testing.expect_value(t, StateMachine_CurrentName(sm), "stunned")
	h = StateMachine_History(sm)
	testing.expect_value(t, h[len(h) - 1].why, "forced")
	player.position.x = enemy.position.x + 500 // (gone: it won't chase straight away)
	testing.expect(t, smg_until(game, sm, "patrol", 70) >= 55, "patrols again after 1 s")
	h = StateMachine_History(sm)
	testing.expect_value(t, h[len(h) - 1].why, "transition 6")
}

// Tutorial 3: attack1 -> attack2 -> attack3 only when attack was pressed and
// the animation finished; a press during an attack waits in the trigger's
// 0.3 s buffer; one too early (or with no buffer) is dropped: back to idle.
@(test)
test_sm_guide_combo :: proc(t: ^testing.T) {
	game, scene, ok := smg_load(t, "combo", {"combo_fighter.lua", "probe.lua"})
	if !ok do return
	defer game->terminate()
	Input_DefineAction(&game.input, "attack", {{deviceType = .KeyboardKey, key = .J}})
	apn := cast(^AnimationPlayerNode)Scene_FindNodeByName(scene, "Sprite")
	sm := cast(^StateMachineNode)Scene_FindNodeByName(scene, "Combo")
	if !testing.expect(t, apn != nil && sm != nil, "the tutorial's nodes") do return
	L := game.scriptManager.L
	// The test ends the animations (one frame each, no textures): the
	// player's clock is slowed so it never does.
	AnimationPlayerNode_SetFPS(apn, 0.1)
	for a in apn.animations do a.fps = 0.1
	finish :: proc(game: ^Game, apn: ^AnimationPlayerNode) {
		AnimationPlayerNode_AdvanceFrame(apn)
		game->run(SMG_DT)
	}
	wait :: proc(game: ^Game, frames: int) {for _ in 0 ..< frames do game->run(SMG_DT)}
	damage :: proc(t: ^testing.T, L: ^lua.State) -> string {return smg_lua(t, L, `Scene.find_node("Fighter"):get_script().damage_dealt`)}

	wait(game, 2)
	testing.expect_value(t, StateMachine_CurrentName(sm), "idle")
	smg_press(game, .J)
	testing.expect_value(t, StateMachine_CurrentName(sm), "attack1")
	testing.expect_value(t, damage(t, L), "10")

	// Pressed during attack1 (0.15 s before its end): waits, then attack2.
	wait(game, 3)
	smg_press(game, .J)
	wait(game, 8)
	testing.expect(t, StateMachine_CurrentName(sm) == "attack1" && StateMachine_TriggerPending(sm, "attack"), "buffered while attack1 plays")
	finish(game, apn)
	testing.expect_value(t, StateMachine_CurrentName(sm), "attack2")
	testing.expect_value(t, damage(t, L), "25")

	// Not pressed: attack2 ends in idle (no attack3).
	wait(game, 5)
	finish(game, apn)
	testing.expect_value(t, StateMachine_CurrentName(sm), "idle")
	testing.expect_value(t, smg_entered(sm, "attack3"), 0)

	// The whole chain.
	smg_press(game, .J)
	for want in ([]string{"attack2", "attack3"}) {
		wait(game, 4)
		smg_press(game, .J)
		wait(game, 4)
		finish(game, apn)
		testing.expect_value(t, StateMachine_CurrentName(sm), want)
	}
	wait(game, 4)
	finish(game, apn)
	testing.expect_value(t, StateMachine_CurrentName(sm), "idle")
	testing.expect_value(t, damage(t, L), "80")

	// Too early: pressed 0.5 s before attack1 ends - longer than the buffer.
	smg_press(game, .J)
	smg_press(game, .J)
	wait(game, 30)
	testing.expect(t, !StateMachine_TriggerPending(sm, "attack"), "the buffer ran out")
	finish(game, apn)
	testing.expect_value(t, StateMachine_CurrentName(sm), "idle")

	// No buffer: a press during the attack is dropped after one update.
	sm.triggers[StateMachine_FindTrigger(sm, "attack")].buffer = 0
	smg_press(game, .J)
	wait(game, 2)
	smg_press(game, .J)
	wait(game, 2)
	finish(game, apn)
	testing.expect_value(t, StateMachine_CurrentName(sm), "idle")
	testing.expect_value(t, smg_entered(sm, "attack2"), 2)
}
