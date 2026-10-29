package engine

import "core:strings"
import "core:testing"
import lua "lua54"

// (Helpers: a game with one scene, a machine under a scripted parent.)
@(private = "file")
SM_Fixture :: struct {
	game: ^Game,
	scene: ^Scene,
	owner: ^Node,
	sm:   ^StateMachineNode,
	apn:  ^AnimationPlayerNode,
}

@(private = "file")
sm_fixture :: proc(script_name, script: string) -> SM_Fixture {
	ScriptVFS_RegisterEmbedded(script_name, script)
	f: SM_Fixture
	f.game = new(Game)
	InitializeGame(f.game)
	f.scene = f.game->createScene("smr", true)
	ProcessSceneChange(&f.game.sceneManager, &f.game.gameContext)
	f.game.state = .Running
	f.owner = Node_CreateByTypeName(f.scene, "Node")
	f.owner.name = "Owner"
	f.owner.gameContext = &f.game.gameContext
	Script_AttachToNode(f.owner, script_name, nil, &f.game.scriptManager)
	f.apn = cast(^AnimationPlayerNode)Node_CreateByTypeName(f.scene, "AnimationPlayerNode", f.owner)
	f.apn.name = "Anim"
	f.apn.gameContext = &f.game.gameContext
	f.sm = cast(^StateMachineNode)Node_CreateByTypeName(f.scene, "StateMachineNode", f.owner)
	f.sm.name = "Machine"
	f.sm.gameContext = &f.game.gameContext
	return f
}

@(private = "file")
lua_str :: proc(L: ^lua.State, name: cstring) -> string {
	lua.getglobal(L, name)
	defer lua.pop(L, 1)
	return strings.clone(string(lua.tostring(L, -1)), context.temp_allocator)
}

@(private = "file")
lua_run :: proc(t: ^testing.T, L: ^lua.State, code: string) {
	if lua.L_dostring(L, strings.clone_to_cstring(code, context.temp_allocator)) != 0 {
		testing.fail_now(t, string(lua.tostring(L, -1)))
	}
}

// Arrows default to Manual: the machine doesn't take them, sm_transition
// does - checking the arrow's conditions only when it has some; force skips
// conditions and guards; Automatic arrows can be taken by a script too;
// every refusal says why.
@(test)
test_sm_manual_transitions :: proc(t: ^testing.T) {
	f := sm_fixture("smr_manual.lua", `local S = {} S.properties = {} return S`)
	defer f.game->terminate()
	sm := f.sm
	StateMachine_AddState(sm, "idle")
	StateMachine_AddState(sm, "walk")
	StateMachine_AddState(sm, "jump")
	attack := StateMachine_AddState(sm, "attack")
	StateMachine_AddState(sm, "nowhere")
	plain := StateMachine_AddTransition(sm, "idle", "walk") // manual, no conditions
	testing.expect_value(t, plain.mode, SM_Mode.Manual)
	gated := StateMachine_AddTransition(sm, "walk", "jump") // manual, with a condition
	StateMachine_AddCondition(sm, gated, .Is_True, "on_floor")
	StateMachine_AddTransition(sm, "jump", "attack")
	sm.states[attack].minTime = 1
	StateMachine_AddTransition(sm, "attack", "idle")
	auto := StateMachine_AddTransition(sm, "idle", "nowhere", mode = .Automatic)
	StateMachine_AddCondition(sm, auto, .Is_True, "never")

	testing.expect_value(t, StateMachine_Transition(sm, "walk"), SM_Block.Not_Running)
	for _ in 0 ..< 5 do f.game->run(0.016)
	testing.expect_value(t, StateMachine_CurrentName(sm), "idle") // (a manual arrow waits)
	testing.expect_value(t, StateMachine_Transition(sm, "nope"), SM_Block.No_State)
	testing.expect_value(t, StateMachine_Transition(sm, "jump"), SM_Block.No_Transition)
	testing.expect_value(t, StateMachine_Transition(sm, "walk"), SM_Block.None)
	testing.expect_value(t, StateMachine_CurrentName(sm), "walk") // (at once)
	// The arrow's own condition counts for a script's transition.
	testing.expect_value(t, StateMachine_Transition(sm, "jump"), SM_Block.Conditions)
	StateMachine_SetParam(sm, "on_floor", 1)
	block, _ := StateMachine_CanTransition(sm, "jump")
	testing.expect_value(t, block, SM_Block.None)
	testing.expect_value(t, StateMachine_CurrentName(sm), "walk") // (asking changes nothing)
	testing.expect_value(t, StateMachine_Transition(sm, "jump"), SM_Block.None)
	testing.expect_value(t, StateMachine_Transition(sm, "attack"), SM_Block.None)
	// Guards hold a script's transition; force skips them.
	testing.expect_value(t, StateMachine_Transition(sm, "idle"), SM_Block.Min_Time)
	testing.expect_value(t, StateMachine_Transition(sm, "idle", force = true), SM_Block.None)
	// Force skips the arrow's conditions too - not the need for an arrow.
	testing.expect_value(t, StateMachine_Transition(sm, "nowhere"), SM_Block.Conditions)
	testing.expect_value(t, StateMachine_Transition(sm, "attack", force = true), SM_Block.No_Transition)
	testing.expect_value(t, StateMachine_Transition(sm, "nowhere", force = true), SM_Block.None) // (an automatic arrow, by script)
	hist := StateMachine_History(sm)
	testing.expect(t, hist[len(hist) - 1].why == "forced" && hist[len(hist) - 3].why == "manual", "history says how")

	// Lua: ok, reason.
	L := f.game.scriptManager.L
	StateMachine_Transition(sm, "nowhere") // (no-op)
	lua_run(t, L, `
local m = Scene.find_node("Machine")
ok1, why1 = m:sm_transition("idle")
can, canwhy = m:sm_can_transition("walk")
`)
	testing.expect_value(t, lua_str(L, "why1"), "no arrow from nowhere to idle")
	testing.expect_value(t, lua_str(L, "canwhy"), "no arrow from nowhere to walk")
}

// Callback order: leaving runs the child machine's stop then on_exit(next)
// last; entering runs on_enter(previous) first, then the child machine
// starts and the animation plays; on_update runs on the update a change
// happened (for the new state); stopping runs on_exit("").
@(test)
test_sm_callback_order :: proc(t: ^testing.T) {
	f := sm_fixture("smr_order.lua", `
local S = {} S.properties = {}
function S:ready() log = "" end
local function anim() local a = Scene.find_node("Anim"):animation_get_current() return a end
function S:on_enter_a(prev) log = log .. "enter_a(" .. prev .. ") anim=" .. anim() .. " child=" .. Scene.find_node("Kid"):sm_state() .. ";" end
function S:on_exit_a(next) log = log .. "exit_a(" .. next .. ") child=" .. tostring(Scene.find_node("Kid"):sm_state() ~= "" and "running" or "") .. ";" end
function S:on_enter_b(prev) log = log .. "enter_b(" .. prev .. ");" end
function S:on_update_b(dt) log = log .. "update_b;" end
function S:on_exit_b(next) log = log .. "exit_b(" .. next .. ");" end
return S
`)
	defer f.game->terminate()
	sm := f.sm
	for name in ([]string{"run", "walk"}) {
		a := AnimationPlayerNode_AddFrameAnimation(f.apn, nil, name, nil)
		a.endFrame = 3
	}
	kid := cast(^StateMachineNode)Node_CreateByTypeName(f.scene, "StateMachineNode", sm)
	kid.name = "Kid"
	kid.gameContext = &f.game.gameContext
	StateMachine_AddState(kid, "inner")
	a := StateMachine_AddState(sm, "a", "run")
	sm.states[a].child = strings.clone("Kid", sm.allocator)
	StateMachine_AddState(sm, "b", "walk")
	tr := StateMachine_AddTransition(sm, "a", "b", mode = .Automatic)
	StateMachine_AddCondition(sm, tr, .Trigger, "go")
	StateMachine_AddTransition(sm, "b", "a")
	ProcessNodeQueues(f.scene.manager, &f.game.gameContext)
	L := f.game.scriptManager.L

	f.game->run(0.016) // starts in a
	// on_enter_a ran first: the player still showed its previous animation
	// (walk, the last added) - not run yet - and the child hadn't started.
	testing.expect_value(t, lua_str(L, "log"), "enter_a() anim=walk child=;")
	testing.expect(t, kid.running && AnimationPlayerNode_GetAnimationName(f.apn) == "run", "then the child started and the animation played")
	lua_run(t, L, `log = ""`)
	StateMachine_FireTrigger(sm, "go")
	f.game->run(0.016)
	// The child was stopped before on_exit_a; on_update_b ran on the same update.
	testing.expect_value(t, lua_str(L, "log"), "exit_a(b) child=running;enter_b(a);update_b;")
	testing.expect(t, !kid.running, "the child stopped with its state")
	lua_run(t, L, `log = ""`)
	StateMachine_Stop(sm)
	testing.expect_value(t, lua_str(L, "log"), "exit_b();")
	testing.expect_value(t, StateMachine_CurrentName(sm), "b") // (still the last state)
	StateMachine_Stop(sm) // (twice: nothing more)
	testing.expect_value(t, lua_str(L, "log"), "exit_b();")
}

// Allow Retrigger: an arrow to the current state (its own, or from Any)
// re-enters it - on_exit, on_enter and the animation again - only when the
// state allows it.
@(test)
test_sm_retrigger :: proc(t: ^testing.T) {
	f := sm_fixture("smr_retrigger.lua", `
local S = {} S.properties = {}
function S:ready() enters = 0; exits = 0 end
function S:on_enter_hit(prev) enters = enters + 1; last_prev = prev end
function S:on_exit_hit(next) exits = exits + 1 end
return S
`)
	defer f.game->terminate()
	sm := f.sm
	a := AnimationPlayerNode_AddFrameAnimation(f.apn, nil, "flash", nil)
	a.endFrame = 5
	hit := StateMachine_AddState(sm, "hit", "flash")
	StateMachine_AddTransition(sm, "hit", "hit")
	any := StateMachine_AddTransition(sm, SM_ANY, "hit", mode = .Automatic)
	StateMachine_AddCondition(sm, any, .Trigger, "damage")
	ProcessNodeQueues(f.scene.manager, &f.game.gameContext)
	L := f.game.scriptManager.L
	f.game->run(0.016)
	testing.expect_value(t, StateMachine_Transition(sm, "hit"), SM_Block.No_Retrigger)
	StateMachine_FireTrigger(sm, "damage")
	f.game->run(0.016)
	testing.expect_value(t, lua_str(L, "enters"), "1") // (Any -> itself skipped)
	sm.states[hit].allowRetrigger = true
	AnimationPlayerNode_AdvanceFrame(f.apn)
	AnimationPlayerNode_AdvanceFrame(f.apn)
	testing.expect_value(t, StateMachine_Transition(sm, "hit"), SM_Block.None)
	testing.expect(t, lua_str(L, "enters") == "2" && lua_str(L, "exits") == "1" && lua_str(L, "last_prev") == "hit", "re-entered")
	testing.expect_value(t, f.apn.currentFrame, 0) // (the animation restarted)
	StateMachine_FireTrigger(sm, "damage")
	f.game->run(0.016)
	testing.expect_value(t, lua_str(L, "enters"), "3") // (Any -> itself now allowed)
}

// Issue #67: retriggering a state whose (non-looping) animation already
// finished plays it again from the start, frames advancing - through the
// machine's own updates (an Any-state trigger), as in a game.
@(test)
test_sm_retrigger_replays_finished_animation :: proc(t: ^testing.T) {
	f := sm_fixture("smr_retrigger_anim.lua", `local S = {} S.properties = {} return S`)
	defer f.game->terminate()
	sm := f.sm
	a := AnimationPlayerNode_AddFrameAnimation(f.apn, nil, "attack", nil, loop = false)
	a.endFrame = 3
	a.fps = 60
	hit := StateMachine_AddState(sm, "attack", "attack")
	sm.states[hit].allowRetrigger = true
	any := StateMachine_AddTransition(sm, SM_ANY, "attack", mode = .Automatic)
	StateMachine_AddCondition(sm, any, .Trigger, "swing")
	ProcessNodeQueues(f.scene.manager, &f.game.gameContext)
	f.game->run(1.0 / 60) // starts in attack
	// (the player's ticker runs on wall-clock time: frames are stepped here)
	for _ in 0 ..< 5 do AnimationPlayerNode_AdvanceFrame(f.apn)
	testing.expect(t, f.apn.finishedNotified && f.apn.currentFrame == 3 && !f.apn.ticker.running, "played to the end and finished")

	StateMachine_FireTrigger(sm, "swing")
	f.game->run(1.0 / 60)
	testing.expectf(t, f.apn.currentFrame == 0 && !f.apn.finishedNotified && f.apn.ticker.running, "restarted and playing (frame %d, running %v)", f.apn.currentFrame, f.apn.ticker.running)
	for _ in 0 ..< 5 do AnimationPlayerNode_AdvanceFrame(f.apn)
	testing.expectf(t, f.apn.currentFrame == 3 && f.apn.finishedNotified, "played through again (frame %d)", f.apn.currentFrame)
}

// Scripts changing state from callbacks: a chain of changes stops at
// SM_CHAIN_MAX; changing state from inside a guard, a condition or an
// on_exit is refused; at most one automatic change per update.
@(test)
test_sm_chains_and_busy :: proc(t: ^testing.T) {
	f := sm_fixture("smr_chain.lua", `
local S = {} S.properties = {}
function S:ready() pings = 0; from_guard = "" ; from_exit = "" end
function S:on_enter_ping(prev) pings = pings + 1; Scene.find_node("Machine"):sm_transition("pong") end
function S:on_enter_pong(prev) Scene.find_node("Machine"):sm_transition("ping") end
function S:can_exit_guarded(next) local ok, why = Scene.find_node("Machine"):sm_transition("ping"); from_guard = why; return true end
function S:on_exit_quiet(next) local ok, why = Scene.find_node("Machine"):sm_transition("ping"); from_exit = why end
return S
`)
	defer f.game->terminate()
	sm := f.sm
	StateMachine_AddState(sm, "start")
	StateMachine_AddState(sm, "ping")
	StateMachine_AddState(sm, "pong")
	StateMachine_AddState(sm, "guarded")
	StateMachine_AddState(sm, "quiet")
	StateMachine_AddState(sm, "x")
	StateMachine_AddTransition(sm, "start", "ping")
	StateMachine_AddTransition(sm, "ping", "pong")
	StateMachine_AddTransition(sm, "pong", "ping")
	StateMachine_AddTransition(sm, "start", "guarded")
	StateMachine_AddTransition(sm, "guarded", "quiet")
	StateMachine_AddTransition(sm, "quiet", "x")
	StateMachine_AddTransition(sm, SM_ANY, "ping")
	ProcessNodeQueues(f.scene.manager, &f.game.gameContext)
	L := f.game.scriptManager.L
	f.game->run(0.016)
	// ping <-> pong from their on_enters: stopped after SM_CHAIN_MAX changes.
	testing.expect_value(t, StateMachine_Transition(sm, "ping"), SM_Block.None)
	testing.expect_value(t, sm.depth, 0)
	testing.expect_value(t, lua_str(L, "pings"), "4") // (8 changes: ping, pong, ... alternating)
	testing.expect(t, sm.historyLen == 9, "start + the 8 chained changes")
	// From inside a guard / an on_exit: refused.
	StateMachine_Start(sm, "start")
	testing.expect_value(t, StateMachine_Transition(sm, "guarded"), SM_Block.None)
	testing.expect_value(t, StateMachine_Transition(sm, "quiet"), SM_Block.None) // (can_exit_guarded tried)
	testing.expect(t, strings.contains(lua_str(L, "from_guard"), "inside a guard"), lua_str(L, "from_guard"))
	testing.expect_value(t, StateMachine_Transition(sm, "x"), SM_Block.None)
	testing.expect(t, strings.contains(lua_str(L, "from_exit"), "on_exit"), lua_str(L, "from_exit"))
	testing.expect_value(t, StateMachine_CurrentName(sm), "x")

	// At most one automatic change per update.
	s2 := cast(^StateMachineNode)Node_CreateByTypeName(f.scene, "StateMachineNode")
	s2.name = "Steps"
	s2.gameContext = &f.game.gameContext
	StateMachine_AddState(s2, "s1")
	StateMachine_AddState(s2, "s2")
	StateMachine_AddState(s2, "s3")
	StateMachine_AddTransition(s2, "s1", "s2", mode = .Automatic)
	StateMachine_AddTransition(s2, "s2", "s3", mode = .Automatic)
	ProcessNodeQueues(f.scene.manager, &f.game.gameContext)
	f.game->run(0.016) // starts in s1
	f.game->run(0.016)
	testing.expect_value(t, StateMachine_CurrentName(s2), "s2")
	f.game->run(0.016)
	testing.expect_value(t, StateMachine_CurrentName(s2), "s3")
}

// Triggers: set by sm_trigger; the first automatic arrow it opens takes it;
// otherwise cleared after the update that checked it (one set after the
// machine's update survives to the next); a buffer keeps it waiting; unknown
// names warn; triggers don't take manual arrows; cleared on start.
@(test)
test_sm_triggers :: proc(t: ^testing.T) {
	f := sm_fixture("smr_triggers.lua", `local S = {} S.properties = {} return S`)
	defer f.game->terminate()
	sm := f.sm
	StateMachine_AddState(sm, "idle")
	StateMachine_AddState(sm, "jump")
	fall := StateMachine_AddState(sm, "fall")
	StateMachine_AddState(sm, "wave")
	tr := StateMachine_AddTransition(sm, "idle", "jump", mode = .Automatic)
	StateMachine_AddCondition(sm, tr, .Trigger, "jump")
	tr = StateMachine_AddTransition(sm, "fall", "jump", mode = .Automatic) // (only once landed)
	StateMachine_AddCondition(sm, tr, .Trigger, "jump")
	StateMachine_AddCondition(sm, tr, .Is_True, "on_floor")
	tr = StateMachine_AddTransition(sm, "idle", "wave") // manual
	StateMachine_AddCondition(sm, tr, .Trigger, "hello")
	StateMachine_AddTransition(sm, "jump", "fall", mode = .Automatic)
	ProcessNodeQueues(f.scene.manager, &f.game.gameContext)
	f.game->run(0.016)

	// Taken by the arrow it opens, and used up.
	testing.expect(t, StateMachine_FireTrigger(sm, "jump"), "set")
	f.game->run(0.016)
	testing.expect(t, StateMachine_CurrentName(sm) == "jump" && !StateMachine_TriggerPending(sm, "jump"), "fired and used up")
	f.game->run(0.016)
	testing.expect_value(t, StateMachine_CurrentName(sm), "fall")
	// In fall, not on the floor: no arrow can use it - cleared after one update.
	StateMachine_FireTrigger(sm, "jump")
	f.game->run(0.016)
	testing.expect(t, !StateMachine_TriggerPending(sm, "jump"), "no buffer: dropped after the update that checked it")
	StateMachine_SetParam(sm, "on_floor", 1)
	f.game->run(0.016)
	testing.expect_value(t, StateMachine_CurrentName(sm), "fall") // (the press was lost)
	// With a buffer: pressed 80 ms before landing, the jump still happens.
	StateMachine_SetParam(sm, "on_floor", 0)
	StateMachine_AddTrigger(sm, "jump").buffer = 0.12
	StateMachine_FireTrigger(sm, "jump")
	for _ in 0 ..< 5 do f.game->run(0.016) // 80 ms in the air
	testing.expect(t, StateMachine_TriggerPending(sm, "jump"), "buffered: still waiting")
	StateMachine_SetParam(sm, "on_floor", 1)
	f.game->run(0.016)
	testing.expect_value(t, StateMachine_CurrentName(sm), "jump")
	// ... and a buffer runs out.
	f.game->run(0.016) // (jump -> fall)
	StateMachine_SetParam(sm, "on_floor", 0)
	StateMachine_FireTrigger(sm, "jump")
	for _ in 0 ..< 10 do f.game->run(0.016) // 160 ms
	testing.expect(t, !StateMachine_TriggerPending(sm, "jump"), "the buffer ran out")
	// Set after the machine's update (a later node's script): checked next update.
	sm.states[fall].minTime = 0
	sm.updates += 0
	StateMachine_Start(sm, "idle")
	StateMachine_FireTrigger(sm, "jump")
	sm_age := sm.updates
	testing.expect_value(t, sm.triggers[0].setAt, sm_age)
	f.game->run(0.016)
	testing.expect_value(t, StateMachine_CurrentName(sm), "jump")
	// Triggers don't take manual arrows.
	StateMachine_Start(sm, "idle")
	StateMachine_FireTrigger(sm, "hello")
	f.game->run(0.016)
	testing.expect_value(t, StateMachine_CurrentName(sm), "idle")
	// A start clears pending triggers.
	StateMachine_FireTrigger(sm, "hello")
	StateMachine_Start(sm, "idle")
	testing.expect(t, !StateMachine_TriggerPending(sm, "hello"), "cleared on start")
	// Unknown names: false (a warning, once).
	testing.expect(t, !StateMachine_FireTrigger(sm, "jmup"), "unknown")
	testing.expect(t, !StateMachine_FireTrigger(sm, "jmup") && len(sm.warned) == 1, "warned once")
	// Lua.
	L := f.game.scriptManager.L
	lua_run(t, L, `
local m = Scene.find_node("Machine")
t_ok = tostring(m:sm_trigger("hello"))
t_pending = tostring(m:sm_trigger_pending("hello"))
m:sm_clear_trigger("hello")
t_after = tostring(m:sm_trigger_pending("hello"))
t_bad = tostring(m:sm_trigger("nope"))
`)
	testing.expect(t, lua_str(L, "t_ok") == "true" && lua_str(L, "t_pending") == "true" && lua_str(L, "t_after") == "false" && lua_str(L, "t_bad") == "false", "Lua triggers")
}

// Parameters are typed (bool / int / float); every condition kind holds
// when it should: true, false, ==, !=, >, <, trigger, finished (and for a
// looping animation), after, call, or-groups.
@(test)
test_sm_params_and_conditions :: proc(t: ^testing.T) {
	f := sm_fixture("smr_conds.lua", `
local S = {} S.properties = {}
function S:ready() answer = false end
function S:says() return answer end
return S
`)
	defer f.game->terminate()
	sm := f.sm
	b := StateMachine_EnsureParam(sm, "grounded", 0, .Bool)
	n := StateMachine_EnsureParam(sm, "lives", 3, .Int)
	StateMachine_EnsureParam(sm, "speed", 0, .Float)
	StateMachine_AddTrigger(sm, "hit")
	StateMachine_SetParam(sm, "grounded", 5)
	testing.expect_value(t, b.value, 1) // (a bool: 0 / 1)
	StateMachine_SetParam(sm, "lives", 2.7)
	testing.expect_value(t, n.value, 3) // (an int: rounded)
	StateMachine_SetParam(sm, "lives", -1.6)
	testing.expect_value(t, StateMachine_GetParam(sm, "lives"), -2)
	StateMachine_SetParamType(&sm.params[2], .Int) // speed
	StateMachine_SetParam(sm, "speed", 0.1 + 0.2)
	testing.expect_value(t, StateMachine_GetParam(sm, "speed"), 0)
	StateMachine_SetParamType(&sm.params[2], .Float)

	holds :: proc(sm: ^StateMachineNode, conds: ..SM_Condition) -> bool {return StateMachine_ConditionsHold(sm, conds)}
	c :: proc(op: SM_Op, param := "", value: f32 = 0) -> SM_Condition {return {op, param, value}}
	StateMachine_SetParam(sm, "grounded", 1)
	StateMachine_SetParam(sm, "lives", 3)
	StateMachine_SetParam(sm, "speed", 0.1 + 0.2)
	testing.expect(t, holds(sm, c(.Is_True, "grounded")) && !holds(sm, c(.Is_False, "grounded")), "true / false")
	testing.expect(t, holds(sm, c(.Equal, "lives", 3)) && !holds(sm, c(.Not_Equal, "lives", 3)), "int ==")
	testing.expect(t, !holds(sm, c(.Equal, "lives", 3.00001)), "int == is exact")
	testing.expect(t, holds(sm, c(.Equal, "speed", 0.3)) && !holds(sm, c(.Not_Equal, "speed", 0.3)), "float == allows rounding (0.1 + 0.2 == 0.3)")
	testing.expect(t, holds(sm, c(.Greater, "speed", 0.2)) && holds(sm, c(.Less, "speed", 0.4)) && !holds(sm, c(.Greater, "speed", 0.4)), "> / <")
	testing.expect(t, !holds(sm, c(.Is_True, "missing")) && holds(sm, c(.Is_False, "missing")), "a missing parameter is 0")
	testing.expect(t, !holds(sm, c(.Trigger, "hit")), "trigger not set")
	StateMachine_FireTrigger(sm, "hit")
	testing.expect(t, holds(sm, c(.Trigger, "hit")), "trigger set")
	testing.expect(t, holds(sm), "no conditions: holds")
	testing.expect(t, !holds(sm, c(.Is_True, "grounded"), c(.Equal, "lives", 0)), "AND")
	testing.expect(t, holds(sm, c(.Equal, "lives", 0), c(.Or), c(.Is_True, "grounded")), "OR group")
	testing.expect(t, !holds(sm, c(.Equal, "lives", 0), c(.Or), c(.Is_False, "grounded")), "no group holds")
	// call / after / finished need a running machine and its state.
	once := AnimationPlayerNode_AddFrameAnimation(f.apn, nil, "attack", nil)
	once.endFrame = 2
	once.loop = false
	once.fps = 1
	looping := AnimationPlayerNode_AddFrameAnimation(f.apn, nil, "run", nil)
	looping.endFrame = 2
	looping.loop = true
	looping.fps = 1
	StateMachine_AddState(sm, "attack", "attack")
	StateMachine_AddState(sm, "run", "run")
	ProcessNodeQueues(f.scene.manager, &f.game.gameContext)
	f.game->run(0.016)
	L := f.game.scriptManager.L
	testing.expect(t, !holds(sm, c(.Call, "says")), "call: false")
	lua_run(t, L, "answer = true")
	testing.expect(t, holds(sm, c(.Call, "says")) && !holds(sm, c(.Call, "no_such_method")), "call: true; a missing method is false")
	testing.expect(t, !holds(sm, c(.After, "", 0.5)), "after: not yet")
	f.game->run(0.6)
	testing.expect(t, holds(sm, c(.After, "", 0.5)), "after")
	testing.expect(t, !holds(sm, c(.Finished)), "finished: not yet")
	for _ in 0 ..< 3 do AnimationPlayerNode_AdvanceFrame(f.apn)
	testing.expect(t, holds(sm, c(.Finished)), "finished (a one-shot animation)")
	StateMachine_Transition(sm, "run", force = true)
	testing.expect_value(t, StateMachine_Transition(sm, "run", force = true), SM_Block.No_Transition) // (no arrow: nothing forced)
	StateMachine_AddTransition(sm, "attack", "run")
	StateMachine_Start(sm, "attack")
	StateMachine_Transition(sm, "run")
	testing.expect(t, !holds(sm, c(.Finished)), "a looping animation: not until it loops")
	for _ in 0 ..< 3 do AnimationPlayerNode_AdvanceFrame(f.apn)
	testing.expect(t, holds(sm, c(.Finished)), "a looping animation: after one loop")
	// Lua: typed values.
	lua_run(t, L, `
local m = Scene.find_node("Machine")
m:sm_set("grounded", false)
m:sm_set("lives", 4)
g_type = type(m:sm_get("grounded")) .. "/" .. tostring(m:sm_get("grounded"))
l_type = math.type(m:sm_get("lives")) .. "/" .. tostring(m:sm_get("lives"))
s_type = math.type(m:sm_get("speed"))
missing = tostring(m:sm_get("nope"))
`)
	testing.expect_value(t, lua_str(L, "g_type"), "boolean/false")
	testing.expect_value(t, lua_str(L, "l_type"), "integer/4")
	testing.expect_value(t, lua_str(L, "s_type"), "float")
	testing.expect_value(t, lua_str(L, "missing"), "nil")
}

// Saved and loaded: modes, Allow Retrigger, triggers with buffers, typed
// parameters. Older scenes: arrows without a mode load as Automatic, and
// parameters tested by "trigger" conditions become triggers.
@(test)
test_sm_save_and_migrate :: proc(t: ^testing.T) {
	f := sm_fixture("smr_save.lua", `local S = {} S.properties = {} return S`)
	defer f.game->terminate()
	sm := f.sm
	StateMachine_EnsureParam(sm, "grounded", 1, .Bool)
	StateMachine_EnsureParam(sm, "lives", 3, .Int)
	StateMachine_AddTrigger(sm, "jump", 0.15)
	hit := StateMachine_AddState(sm, "hit")
	sm.states[hit].allowRetrigger = true
	StateMachine_AddState(sm, "idle")
	StateMachine_AddTransition(sm, "idle", "hit")
	tr := StateMachine_AddTransition(sm, "hit", "idle", mode = .Automatic)
	StateMachine_AddCondition(sm, tr, .Trigger, "jump")
	text := Scene_SerializeToJSON(f.scene, context.temp_allocator)
	testing.expect(t, strings.contains(text, `"params": [["grounded", 1, "bool"], ["lives", 3, "int"]]`), "typed parameters saved")
	testing.expect(t, strings.contains(text, `"triggers": [["jump", 0.15]]`), "triggers saved")
	testing.expect(t, strings.contains(text, `"retrigger": true`), "retrigger saved")
	testing.expect(t, strings.contains(text, `{"from": "idle", "to": "hit", "mode": "manual", "when": []}`) && strings.contains(text, `"mode": "auto"`), "modes saved")
	s2 := f.game->createScene("smr2", true)
	ProcessSceneChange(&f.game.sceneManager, &f.game.gameContext)
	Scene_InstantiateFromJSON(s2, transmute([]u8)text, &f.game.gameContext)
	ProcessNodeQueues(s2.manager, &f.game.gameContext)
	m2 := cast(^StateMachineNode)Scene_FindNodeByName(s2, "Machine")
	if m2 == nil do testing.fail_now(t, "no machine")
	testing.expect(t, len(m2.params) == 2 && m2.params[0].type == .Bool && m2.params[1].type == .Int && m2.params[1].value == 3, "parameters loaded")
	testing.expect(t, len(m2.triggers) == 1 && m2.triggers[0].buffer == 0.15, "trigger loaded")
	testing.expect(t, m2.states[0].allowRetrigger && m2.transitions[0].mode == .Manual && m2.transitions[1].mode == .Automatic, "flags loaded")

	// An older scene: no modes, a trigger kept as a parameter.
	old := `{"name": "old", "root": {"type": "Node", "name": "root", "children": [{"type": "StateMachineNode", "name": "Old", "state_machine": {
"initial": "Idle", "player": "", "autostart": true, "params": [["Punch", 0], ["speed", 0]],
"states": [{"name": "Idle", "pos": [0, 0]}, {"name": "Punch", "pos": [100, 0], "leave_when": [["finished"]]}],
"transitions": [{"from": "Idle", "to": "Punch", "when": [["trigger", "Punch"]]}, {"from": "Punch", "to": "Idle", "when": [[">", "speed", 1]]}]}}]}}`
	s3 := f.game->createScene("smr3", true)
	ProcessSceneChange(&f.game.sceneManager, &f.game.gameContext)
	Scene_InstantiateFromJSON(s3, transmute([]u8)string(old), &f.game.gameContext)
	ProcessNodeQueues(s3.manager, &f.game.gameContext)
	m3 := cast(^StateMachineNode)Scene_FindNodeByName(s3, "Old")
	if m3 == nil do testing.fail_now(t, "no old machine")
	testing.expect(t, m3.transitions[0].mode == .Automatic && m3.transitions[1].mode == .Automatic, "old arrows: automatic")
	testing.expect(t, len(m3.triggers) == 1 && m3.triggers[0].name == "Punch", "the trigger parameter became a trigger")
	testing.expect(t, len(m3.params) == 1 && m3.params[0].name == "speed", "and left the parameters")
	// It behaves as before: the trigger takes Idle -> Punch by itself.
	m3.gameContext = &f.game.gameContext
	f.game->run(0.016)
	StateMachine_FireTrigger(m3, "Punch")
	f.game->run(0.016)
	testing.expect_value(t, StateMachine_CurrentName(m3), "Punch")
	// Renaming a parameter / trigger renames its conditions.
	StateMachine_RenameTrigger(m3, 0, "Strike")
	StateMachine_RenameParam(m3, 0, "velocity")
	testing.expect(t, m3.transitions[0].conditions[0].param == "Strike" && m3.transitions[1].conditions[0].param == "velocity", "references renamed")
}
