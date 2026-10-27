package engine

import "core:strings"
import "core:testing"
import lua "lua54"

@(test)
test_state_machine :: proc(t: ^testing.T) {
	ScriptVFS_RegisterEmbedded("sm_hero.lua", `
local H = {}
H.properties = {}
function H:ready() log_sm = "" end
function H:on_enter_run(prev) log_sm = log_sm .. "enter_run<" .. prev .. ";" end
function H:on_exit_idle(next) log_sm = log_sm .. "exit_idle>" .. next .. ";" end
function H:on_enter_jump(prev) log_sm = log_sm .. "jump;" end
return H
`)
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("sm", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running

	hero := Node_CreateByTypeName(scene, "Node")
	hero.name = "Hero"
	hero.gameContext = &game.gameContext
	Script_AttachToNode(hero, "sm_hero.lua", nil, &game.scriptManager)
	apn := cast(^AnimationPlayerNode)Node_CreateByTypeName(scene, "AnimationPlayerNode", hero)
	apn.name = "Anim"
	apn.gameContext = &game.gameContext
	for name in ([]string{"idle", "run", "jump"}) {
		a := AnimationPlayerNode_AddFrameAnimation(apn, nil, name, nil)
		a.endFrame = 3
		a.loop = name != "jump"
	}
	sm := cast(^StateMachineNode)Node_CreateByTypeName(scene, "StateMachineNode", hero)
	sm.name = "Machine"
	sm.gameContext = &game.gameContext
	StateMachine_AddState(sm, "idle", "idle")
	StateMachine_AddState(sm, "run", "run")
	StateMachine_AddState(sm, "jump", "jump")
	tr := StateMachine_AddTransition(sm, "idle", "run", 0.1, .Automatic)
	StateMachine_AddCondition(sm, tr, .Greater, "speed", 10)
	tr = StateMachine_AddTransition(sm, "run", "idle", mode = .Automatic)
	StateMachine_AddCondition(sm, tr, .Less, "speed", 1)
	tr = StateMachine_AddTransition(sm, SM_ANY, "jump", mode = .Automatic)
	StateMachine_AddCondition(sm, tr, .Trigger, "jump")
	tr = StateMachine_AddTransition(sm, "jump", "idle", mode = .Automatic)
	StateMachine_AddCondition(sm, tr, .Finished)
	testing.expect_value(t, sm.initial, "idle")
	testing.expect_value(t, len(sm.params), 1) // speed
	testing.expect_value(t, len(sm.triggers), 1) // jump

	// Starts in the initial state on the first update, playing its animation.
	game->run(0.016)
	testing.expect_value(t, StateMachine_CurrentName(sm), "idle")
	testing.expect_value(t, AnimationPlayerNode_GetAnimationName(apn), "idle")

	// Parameters from Lua; the parent's script gets exit/enter callbacks.
	L := game.scriptManager.L
	ok := lua.L_dostring(L, `
local m = Scene.find_node("Machine")
m:sm_set("speed", 20)
`)
	testing.expect(t, ok == 0, "lua ran")
	game->run(0.016)
	testing.expect_value(t, StateMachine_CurrentName(sm), "run")
	testing.expect_value(t, AnimationPlayerNode_GetAnimationName(apn), "run")
	lua.getglobal(L, "log_sm")
	testing.expect_value(t, string(lua.tostring(L, -1)), "exit_idle>run;enter_run<idle;")
	lua.pop(L, 1)

	// A trigger from any state, consumed when it fires.
	_ = lua.L_dostring(L, `Scene.find_node("Machine"):sm_trigger("jump")`)
	game->run(0.016)
	testing.expect_value(t, StateMachine_CurrentName(sm), "jump")
	testing.expect(t, !StateMachine_TriggerPending(sm, "jump"), "the trigger is used up")
	_ = lua.L_dostring(L, `state_seen = Scene.find_node("Machine"):sm_state() .. "/" .. Scene.find_node("Machine"):sm_previous()`)
	lua.getglobal(L, "state_seen")
	testing.expect_value(t, string(lua.tostring(L, -1)), "jump/run")
	lua.pop(L, 1)

	// jump -> idle when its (non-looping) animation finishes.
	for _ in 0 ..< 4 do AnimationPlayerNode_AdvanceFrame(apn)
	game->run(0.016)
	testing.expect_value(t, StateMachine_CurrentName(sm), "idle")
	// speed is still 20: idle -> run next update.
	game->run(0.016)
	testing.expect_value(t, StateMachine_CurrentName(sm), "run")

	// A forced transition ignores conditions; "after" counts time in the state.
	testing.expect_value(t, StateMachine_Transition(sm, "idle", force = true), SM_Block.None)
	StateMachine_SetParam(sm, "speed", 0)
	tr = StateMachine_AddTransition(sm, "idle", "jump", mode = .Automatic)
	StateMachine_AddCondition(sm, tr, .After, "", 0.5)
	game->run(0.3)
	testing.expect_value(t, StateMachine_CurrentName(sm), "idle")
	game->run(0.3)
	testing.expect_value(t, StateMachine_CurrentName(sm), "jump")

	// Rename keeps transitions pointing at the state.
	StateMachine_RenameState(sm, 0, "stand")
	testing.expect_value(t, sm.initial, "stand")
	testing.expect_value(t, sm.transitions[0].from, "stand")

	// Saved and loaded.
	text := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expect(t, strings.contains(text, `"when": [[">", "speed", 10]]`), "condition saved")
	testing.expect(t, strings.contains(text, `{"from": "*", "to": "jump", "mode": "auto", "when": [["trigger", "jump"]]}`), "any-state trigger saved")
	s2 := game->createScene("sm2", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	Scene_InstantiateFromJSON(s2, transmute([]u8)text, &game.gameContext)
	ProcessNodeQueues(s2.manager, &game.gameContext)
	m2 := cast(^StateMachineNode)Scene_FindNodeByName(s2, "Machine")
	testing.expect(t, m2 != nil, "machine loaded")
	if m2 == nil do return
	testing.expect_value(t, len(m2.states), 3)
	testing.expect_value(t, len(m2.transitions), 5)
	testing.expect_value(t, m2.initial, "stand")
	testing.expect_value(t, m2.transitions[0].blend, 0.1)
	testing.expect_value(t, m2.transitions[3].conditions[0].op, SM_Op.Finished)
	testing.expect_value(t, m2.transitions[4].conditions[0].value, 0.5)
	testing.expect(t, StateMachine_Player(m2, s2.manager) != nil, "player found among siblings")
}

// Gameplay states: on_update_<state>(dt), a `call` condition asking the
// script, OR groups, a child machine run while its state is current, the
// history; children / positions / or / call saved.
@(test)
test_state_machine_gameplay :: proc(t: ^testing.T) {
	ScriptVFS_RegisterEmbedded("sm_guard.lua", `
local G = {}
G.properties = {}
function G:ready() ticks = 0; alert = false end
function G:on_update_patrol(dt) ticks = ticks + 1 end
function G:sees_player() return alert end
return G
`)
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("smg", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	guard := Node_CreateByTypeName(scene, "Node")
	guard.name = "Guard"
	guard.gameContext = &game.gameContext
	Script_AttachToNode(guard, "sm_guard.lua", nil, &game.scriptManager)
	sm := cast(^StateMachineNode)Node_CreateByTypeName(scene, "StateMachineNode", guard)
	sm.name = "Brain"
	sm.gameContext = &game.gameContext
	combat := cast(^StateMachineNode)Node_CreateByTypeName(scene, "StateMachineNode", sm)
	combat.name = "Combat"
	combat.gameContext = &game.gameContext
	StateMachine_AddState(combat, "aim")
	StateMachine_AddState(combat, "shoot")
	tr := StateMachine_AddTransition(combat, "aim", "shoot", mode = .Automatic)
	StateMachine_AddCondition(combat, tr, .After, "", 0.05)

	StateMachine_AddState(sm, "patrol")
	fight := StateMachine_AddState(sm, "fight")
	sm.states[fight].child = strings.clone("Combat", sm.allocator)
	// patrol -> fight when the script says so OR alarm is set.
	tr = StateMachine_AddTransition(sm, "patrol", "fight", mode = .Automatic)
	StateMachine_AddCondition(sm, tr, .Call, "sees_player")
	StateMachine_AddCondition(sm, tr, .Or)
	StateMachine_AddCondition(sm, tr, .Is_True, "alarm")
	tr = StateMachine_AddTransition(sm, "fight", "patrol", mode = .Automatic)
	StateMachine_AddCondition(sm, tr, .Is_False, "alarm")
	StateMachine_AddCondition(sm, tr, .Call, "calm") // missing method: false -> stays
	ProcessNodeQueues(scene.manager, &game.gameContext)

	L := game.scriptManager.L
	for _ in 0 ..< 3 do game->run(0.016)
	testing.expect_value(t, StateMachine_CurrentName(sm), "patrol")
	testing.expect(t, !combat.running, "a child machine waits for its state")
	lua.getglobal(L, "ticks")
	testing.expect(t, lua.tointeger(L, -1) >= 2, "on_update_patrol ran")
	lua.pop(L, 1)
	// The OR group: alarm alone takes it to fight (and starts Combat).
	StateMachine_SetParam(sm, "alarm", 1)
	game->run(0.016)
	testing.expect_value(t, StateMachine_CurrentName(sm), "fight")
	testing.expect(t, combat.running && StateMachine_CurrentName(combat) == "aim", "child started")
	for _ in 0 ..< 6 do game->run(0.016)
	testing.expect_value(t, StateMachine_CurrentName(combat), "shoot")
	// fight -> patrol needs calm() too (missing): stays; then travel back.
	StateMachine_SetParam(sm, "alarm", 0)
	game->run(0.016)
	testing.expect_value(t, StateMachine_CurrentName(sm), "fight")
	StateMachine_Transition(sm, "patrol", force = true)
	testing.expect(t, !combat.running, "child stopped with its state")
	// The script's condition: patrol -> fight.
	r := lua.L_dostring(L, "alert = true")
	testing.expect_value(t, r, i32(0))
	game->run(0.016)
	testing.expect_value(t, StateMachine_CurrentName(sm), "fight")
	hist := StateMachine_History(sm)
	testing.expect(t, len(hist) == 4 && hist[0].why == "start" && hist[2].why == "forced" && hist[3].to == "fight", "history")
	status := StateMachine_StatusJSON(sm, "Guard/Brain")
	testing.expect(t, strings.contains(status, `"current": "fight"`) && strings.contains(status, `["patrol", "fight", `) && strings.contains(status, `"why"`) == false, status)

	// Saved and read back.
	json := Scene_SerializeToJSON(scene)
	defer delete(json)
	testing.expect(t, strings.contains(json, `"child": "Combat"`) && strings.contains(json, `["call", "sees_player"], ["or"], ["true", "alarm"]`) && strings.contains(json, `"pos": [`), json)
}

@(test)
test_state_machine_guards :: proc(t: ^testing.T) {
	ScriptVFS_RegisterEmbedded("sm_guards.lua", `
local G = {}
G.properties = {}
function G:ready() locked = false; asked = "" end
function G:can_exit_attack(next) asked = next; return not locked end
function G:can_enter_dash(previous) return previous ~= "hurt" end
return G
`)
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("smguard", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	sm := cast(^StateMachineNode)Node_CreateByTypeName(scene, "StateMachineNode")
	sm.name = "Brain"
	sm.gameContext = &game.gameContext
	Script_AttachToNode(sm, "sm_guards.lua", nil, &game.scriptManager)
	StateMachine_AddState(sm, "idle")
	attack := StateMachine_AddState(sm, "attack")
	StateMachine_AddState(sm, "hurt")
	dash := StateMachine_AddState(sm, "dash")
	sm.states[attack].minTime = 0.1
	sm.states[attack].noInterrupt = true
	StateMachine_AddConditionTo(sm, &sm.states[dash].enterWhen, .Greater, "stamina", 20)
	tr := StateMachine_AddTransition(sm, "idle", "attack", mode = .Automatic)
	StateMachine_AddCondition(sm, tr, .Trigger, "attack")
	tr = StateMachine_AddTransition(sm, SM_ANY, "hurt", mode = .Automatic)
	StateMachine_AddCondition(sm, tr, .Trigger, "hit")
	StateMachine_AddTrigger(sm, "hit").buffer = 1 // (buffered: waits while attack refuses)
	StateMachine_AddTransition(sm, "attack", "idle", mode = .Automatic) // always (after the guards)
	StateMachine_AddTransition(sm, "idle", "dash", mode = .Automatic)   // only by request
	tr = StateMachine_AddTransition(sm, "hurt", "idle", mode = .Automatic)
	StateMachine_AddCondition(sm, tr, .After, "", 0.03)
	ProcessNodeQueues(scene.manager, &game.gameContext)
	sm.explain = true

	game->run(0.016)
	testing.expect_value(t, StateMachine_CurrentName(sm), "idle")
	// The dash arrow has no conditions but dash's enter guard says no; the
	// explain view says why.
	game->run(0.016)
	testing.expect_value(t, StateMachine_CurrentName(sm), "idle")
	found := false
	for w in sm.ways[:sm.wayCount] do if sm.transitions[w.transition].to == "dash" {
		found = true
		testing.expect(t, w.arrow && w.block == .Enter_When && w.enterMask == 0, "dash blocked by its enter guard")
	}
	testing.expect(t, found, "the dash way is listed")
	// attack: minTime, and Any-state "hit" can't interrupt it.
	StateMachine_FireTrigger(sm, "attack")
	game->run(0.016)
	testing.expect_value(t, StateMachine_CurrentName(sm), "attack")
	StateMachine_FireTrigger(sm, "hit")
	game->run(0.016)
	testing.expect_value(t, StateMachine_CurrentName(sm), "attack")
	testing.expect(t, StateMachine_TriggerPending(sm, "hit"), "a buffered trigger stays set while blocked")
	// The script's can_exit_attack holds it once the time is up.
	lua.L_dostring(game.scriptManager.L, "locked = true")
	for _ in 0 ..< 8 do game->run(0.016)
	testing.expect_value(t, StateMachine_CurrentName(sm), "attack")
	lua.getglobal(game.scriptManager.L, "asked")
	testing.expect_value(t, string(lua.tostring(game.scriptManager.L, -1)), "idle")
	lua.pop(game.scriptManager.L, 1)
	b := StateMachine_Transition(sm, "idle")
	testing.expect_value(t, b, SM_Block.Can_Exit)
	lua.L_dostring(game.scriptManager.L, "locked = false")
	game->run(0.016)
	testing.expect_value(t, StateMachine_CurrentName(sm), "idle")
	// In idle the pending hit takes it to hurt (Any is fine from idle).
	game->run(0.016)
	testing.expect_value(t, StateMachine_CurrentName(sm), "hurt")
	// Requests: no arrow hurt -> dash; then from idle the enter guard, then ok.
	testing.expect_value(t, StateMachine_Transition(sm, "dash"), SM_Block.No_Transition)
	for _ in 0 ..< 4 do game->run(0.016)
	testing.expect_value(t, StateMachine_CurrentName(sm), "idle")
	testing.expect_value(t, StateMachine_Transition(sm, "dash"), SM_Block.Enter_When)
	StateMachine_SetParam(sm, "stamina", 50)
	testing.expect_value(t, StateMachine_Transition(sm, "dash"), SM_Block.None)
	testing.expect_value(t, StateMachine_CurrentName(sm), "dash")
	hist := StateMachine_History(sm)
	testing.expect_value(t, hist[len(hist) - 1].why, "manual")
	testing.expect(t, strings.contains(StateMachine_BlockText(sm, .Min_Time, "attack", "idle", 0.05), "leave after 0.1s"), StateMachine_BlockText(sm, .Min_Time, "attack", "idle", 0.05))
	// Lua: sm_transition returns ok, reason.
	r := lua.L_dostring(game.scriptManager.L, `local m = Scene.find_node("Brain"); req_ok, req_why = m:sm_transition("attack")`)
	testing.expect_value(t, r, i32(0))
	lua.getglobal(game.scriptManager.L, "req_why")
	testing.expect_value(t, string(lua.tostring(game.scriptManager.L, -1)), "no arrow from dash to attack")
	lua.pop(game.scriptManager.L, 1)

	// Saved and read back.
	json := Scene_SerializeToJSON(scene)
	defer delete(json)
	testing.expect(t, strings.contains(json, `"min_time": 0.1, "interruptible": false`) && strings.contains(json, `"enter_when": [[">", "stamina", 20]]`), json)
	status := StateMachine_StatusJSON(sm, "Brain")
	testing.expect(t, strings.contains(status, `"ways": [`) && strings.contains(status, `"leave": `), status)
}
