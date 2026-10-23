package engine

import "core:strings"
import lua "vendor:lua/5.4"

// ============================================================================
// StateMachineNode: named states, transitions between them guarded by
// conditions on parameters, and an AnimationPlayer it drives.
//
// - Each state can name an animation: entering the state plays it on the
//   player (crossfading for the transition's blend time).
// - A transition goes from a state (or "*": any state) to another when all
//   of its conditions hold: a parameter compared with a value, a trigger
//   (set from a script, consumed when the transition fires), the state's
//   animation finishing, or time spent in the state. No conditions = at
//   once. Transitions are checked in order; at most one fires per update.
// - On a change the scripts of the machine and of its parent get
//   `on_exit_<old>(next)` and `on_enter_<new>(previous)` (when defined), and
//   the machine emits "state_changed"(new state).
// - The player is a path from the machine; empty = the first
//   AnimationPlayer among its siblings, then its children.
// - Gameplay states: no animation needed. While a state is current, the
//   machine's and its parent's scripts get `on_update_<state>(dt)` every
//   frame. A condition can ask a script: `call` runs a method of the
//   machine's script (else its parent's) and holds when it returns truthy.
// - Conditions are ANDed; an `or` separator starts another group (the
//   transition fires when any group holds).
// - A state can run a child state machine (a path): started when the state
//   is entered, stopped when it is left (sub-states: Combat > Attack / Block).
// - The last SM_HISTORY_MAX changes are kept (from, to, time, why) for the
//   editor's history and Lua's sm_history().
// ============================================================================

SM_Op :: enum {
	Is_True,   // param != 0
	Is_False,  // param == 0
	Equal,
	Not_Equal,
	Greater,
	Less,
	Trigger,   // param set by sm_trigger; reset when the transition fires
	Finished,  // the state's animation reached its end (non-looping)
	After,     // value seconds spent in the state
	Call,      // param = a script method; holds when it returns truthy
	Or,        // separator: the conditions after it are another group
}

SM_OP_NAMES := [SM_Op]string {
	.Is_True   = "true",
	.Is_False  = "false",
	.Equal     = "==",
	.Not_Equal = "!=",
	.Greater   = ">",
	.Less      = "<",
	.Trigger   = "trigger",
	.Finished  = "finished",
	.After     = "after",
	.Call      = "call",
	.Or        = "or",
}

SM_Condition :: struct {
	op:    SM_Op,
	param: string,
	value: f32,
}

SM_State :: struct {
	name:      string,
	animation: string,  // "" = leave the player alone (a gameplay state)
	child:     string,  // a child state machine (path) run while in this state
	pos:       [2]f32,  // graph editor position
	breakOnEnter: bool, // editor only: pause when entered (not saved)
}

SM_HISTORY_MAX :: 32

// SM_Change: one state change (history).
SM_Change :: struct {
	from, to: string, // (owned by the states / static)
	time:     f32,    // seconds the machine had run
	why:      string, // "transition 3", "travel", "start" (static or allocator)
}

SM_ANY :: "*"

SM_Transition :: struct {
	from:       string, // a state name or SM_ANY
	to:         string,
	blend:      f32,    // crossfade seconds when the target state plays its animation
	conditions: [dynamic]SM_Condition,
}

SM_Param :: struct {
	name:  string,
	value: f32, // bools are 0 / 1
}

StateMachineNode :: struct {
	using node: Node,
	states:      [dynamic]SM_State,
	transitions: [dynamic]SM_Transition,
	params:      [dynamic]SM_Param,
	initial:     string,
	anyPos:      [2]f32, // graph editor position of the "Any state" box
	player:      string, // path to the AnimationPlayer ("" = find one)
	autostart:   bool,

	// Runtime.
	running:     bool,
	current:     int, // index into states, -1 = none
	previous:    int,
	timeInState: f32,
	timeRunning: f32,
	playerNode:  ^AnimationPlayerNode,
	history:     [SM_HISTORY_MAX]SM_Change, // ring
	historyLen:  int,
	historyNext: int,
	lastFired:   int, // index of the transition that fired last (-1 = none)
	onEnterHook: proc(sm: ^StateMachineNode, state: string), // editor: break on enter
	// "state_changed"(name): entered a state.
	onStateChanged: EventSubject,
}

StateMachineNode_Create :: proc(scene: ^Scene, name: string = "StateMachine", parent: ^Node = nil) -> ^StateMachineNode {
	sm := CreateNode(scene.manager, StateMachineNode)
	StateMachineNode_Init(sm)
	sm.name = strings.clone(name, sm.allocator) // owned: callers pass temp strings too
	return sm
}

StateMachineNode_Init :: proc(sm: ^StateMachineNode) {
	sm.states = make([dynamic]SM_State, sm.allocator)
	sm.transitions = make([dynamic]SM_Transition, sm.allocator)
	sm.params = make([dynamic]SM_Param, sm.allocator)
	sm.autostart = true
	sm.anyPos = {-160, 40}
	sm.current = -1
	sm.previous = -1
	sm.lastFired = -1
	sm.update = StateMachineNode_Update
	sm.onDestroy = StateMachineNode_Destroy
	InitializeSubject(&sm.onStateChanged, "state_changed", sm)
}

StateMachineNode_Destroy :: proc(node: ^Node, ctx: ^GameContext) {
	sm := cast(^StateMachineNode)node
	DestroySubject(&sm.onStateChanged)
}

// --- editing -------------------------------------------------------------------

StateMachine_FindState :: proc(sm: ^StateMachineNode, name: string) -> int {
	for s, i in sm.states do if s.name == name do return i
	return -1
}

StateMachine_AddState :: proc(sm: ^StateMachineNode, name: string, animation := "") -> int {
	if i := StateMachine_FindState(sm, name); i >= 0 do return i
	append(&sm.states, SM_State{name = strings.clone(name, sm.allocator), animation = strings.clone(animation, sm.allocator), pos = {f32(len(sm.states) % 4) * 200 + 160, f32(len(sm.states) / 4) * 120 + 40}})
	if sm.initial == "" do sm.initial = sm.states[len(sm.states) - 1].name
	return len(sm.states) - 1
}

// StateMachine_RemoveState drops a state and the transitions to and from it.
StateMachine_RemoveState :: proc(sm: ^StateMachineNode, index: int) {
	if index < 0 || index >= len(sm.states) do return
	name := sm.states[index].name
	for i := len(sm.transitions) - 1; i >= 0; i -= 1 {
		t := sm.transitions[i]
		if t.from == name || t.to == name do ordered_remove(&sm.transitions, i)
	}
	if sm.initial == name do sm.initial = ""
	ordered_remove(&sm.states, index)
	if sm.initial == "" && len(sm.states) > 0 do sm.initial = sm.states[0].name
	sm.current = -1
}

// StateMachine_RenameState renames a state and every reference to it.
StateMachine_RenameState :: proc(sm: ^StateMachineNode, index: int, name: string) {
	if index < 0 || index >= len(sm.states) || name == "" do return
	old := sm.states[index].name
	n := strings.clone(name, sm.allocator)
	for &t in sm.transitions {
		if t.from == old do t.from = n
		if t.to == old do t.to = n
	}
	if sm.initial == old do sm.initial = n
	sm.states[index].name = n
}

StateMachine_AddTransition :: proc(sm: ^StateMachineNode, from, to: string, blend: f32 = 0) -> ^SM_Transition {
	append(&sm.transitions, SM_Transition{
		from = strings.clone(from, sm.allocator),
		to = strings.clone(to, sm.allocator),
		blend = blend,
		conditions = make([dynamic]SM_Condition, sm.allocator),
	})
	return &sm.transitions[len(sm.transitions) - 1]
}

StateMachine_AddCondition :: proc(sm: ^StateMachineNode, t: ^SM_Transition, op: SM_Op, param := "", value: f32 = 0) {
	append(&t.conditions, SM_Condition{op, strings.clone(param, sm.allocator), value})
	if param != "" && SM_Op_UsesParam(op) && op != .Call do StateMachine_EnsureParam(sm, param)
}

StateMachine_EnsureParam :: proc(sm: ^StateMachineNode, name: string, value: f32 = 0) -> ^SM_Param {
	for &p in sm.params do if p.name == name do return &p
	append(&sm.params, SM_Param{strings.clone(name, sm.allocator), value})
	return &sm.params[len(sm.params) - 1]
}

// --- runtime -------------------------------------------------------------------

StateMachine_SetParam :: proc(sm: ^StateMachineNode, name: string, value: f32) {
	StateMachine_EnsureParam(sm, name).value = value
}

StateMachine_GetParam :: proc(sm: ^StateMachineNode, name: string) -> f32 {
	for p in sm.params do if p.name == name do return p.value
	return 0
}

StateMachine_CurrentName :: proc(sm: ^StateMachineNode) -> string {
	if sm.current < 0 || sm.current >= len(sm.states) do return ""
	return sm.states[sm.current].name
}

StateMachine_PreviousName :: proc(sm: ^StateMachineNode) -> string {
	if sm.previous < 0 || sm.previous >= len(sm.states) do return ""
	return sm.states[sm.previous].name
}

@(private = "file")
sm_manager :: proc(sm: ^StateMachineNode, ctx: ^GameContext = nil) -> ^NodeManager {
	gc := ctx if ctx != nil else sm.gameContext
	if gc == nil || gc.scene == nil do return nil
	return gc.scene.manager
}

// StateMachine_Player: the AnimationPlayer the machine drives (or nil);
// mgr defaults to the game's current scene.
StateMachine_Player :: proc(sm: ^StateMachineNode, mgr: ^NodeManager = nil) -> ^AnimationPlayerNode {
	if sm.playerNode != nil && Node_IsAlive(sm.playerNode) do return sm.playerNode
	sm.playerNode = nil
	mgr := mgr if mgr != nil else sm_manager(sm)
	if mgr == nil do return nil
	if sm.player != "" {
		if n := Node_ResolvePath(mgr, sm, sm.player); n != nil && n.typeId == AnimationPlayerNode do sm.playerNode = cast(^AnimationPlayerNode)n
		return sm.playerNode
	}
	if p := GetParent(mgr, sm); p != nil {
		for c in GetChildrenView(mgr, p) do if c != nil && c.typeId == AnimationPlayerNode {
			sm.playerNode = cast(^AnimationPlayerNode)c
			return sm.playerNode
		}
	}
	for c in GetChildrenView(mgr, sm) do if c != nil && c.typeId == AnimationPlayerNode {
		sm.playerNode = cast(^AnimationPlayerNode)c
		return sm.playerNode
	}
	return nil
}

// StateMachine_Start enters `state` (or the initial state).
StateMachine_Start :: proc(sm: ^StateMachineNode, state := "", ctx: ^GameContext = nil) {
	sm.running = true
	sm.current = -1
	sm.previous = -1
	sm.lastFired = -1
	target := state if state != "" else sm.initial
	if i := StateMachine_FindState(sm, target); i >= 0 {
		StateMachine_Enter(sm, i, 0, ctx, "start")
	} else if len(sm.states) > 0 {
		StateMachine_Enter(sm, 0, 0, ctx, "start")
	}
}

StateMachine_Stop :: proc(sm: ^StateMachineNode, ctx: ^GameContext = nil) {
	sm.running = false
	// Its current state's child machine stops with it.
	if sm.current >= 0 && sm.current < len(sm.states) do sm_child_run(sm, sm.states[sm.current].child, false, ctx)
}

// sm_child_run starts / stops a state's child state machine.
@(private = "file")
sm_child_run :: proc(sm: ^StateMachineNode, path: string, start: bool, ctx: ^GameContext) {
	if path == "" do return
	nodes := sm_manager(sm, ctx)
	if nodes == nil do return
	n := Node_ResolvePath(nodes, sm, path)
	if n == nil || n.typeId != StateMachineNode || n == sm do return
	child := cast(^StateMachineNode)n
	if start do StateMachine_Start(child, "", ctx)
	else do StateMachine_Stop(child, ctx)
}

// StateMachine_IsChild: another machine's state runs this one (it doesn't
// start by itself then).
StateMachine_IsChild :: proc(sm: ^StateMachineNode, nodes: ^NodeManager) -> bool {
	if nodes == nil do return false
	for n in nodes.nodes {
		if n == nil || n == sm || n.typeId != StateMachineNode || n.removing do continue
		other := cast(^StateMachineNode)n
		for s in other.states do if s.child != "" && Node_ResolvePath(nodes, other, s.child) == sm do return true
	}
	return false
}

// StateMachine_History: the last changes, oldest first (into a temp slice).
StateMachine_History :: proc(sm: ^StateMachineNode, allocator := context.temp_allocator) -> []SM_Change {
	out := make([]SM_Change, sm.historyLen, allocator)
	start := (sm.historyNext - sm.historyLen + SM_HISTORY_MAX) % SM_HISTORY_MAX
	for i in 0 ..< sm.historyLen do out[i] = sm.history[(start + i) % SM_HISTORY_MAX]
	return out
}

// StateMachine_Travel switches to a state now (no conditions checked).
StateMachine_Travel :: proc(sm: ^StateMachineNode, state: string, blend: f32 = 0, ctx: ^GameContext = nil) -> bool {
	i := StateMachine_FindState(sm, state)
	if i < 0 do return false
	sm.running = true
	sm.lastFired = -1
	StateMachine_Enter(sm, i, blend, ctx, "travel")
	return true
}

StateMachine_Enter :: proc(sm: ^StateMachineNode, index: int, blend: f32, ctx: ^GameContext, why := "") {
	gc := ctx if ctx != nil else sm.gameContext
	mgr := gc.scriptManager if gc != nil else nil
	nodes := sm_manager(sm, ctx)
	parent := GetParent(nodes, sm) if nodes != nil else nil
	old := StateMachine_CurrentName(sm)
	next := sm.states[index].name
	if old != "" {
		method := strings.concatenate({"on_exit_", old}, context.temp_allocator)
		Script_CallMethod(mgr, sm, method, next, quiet = true)
		if parent != nil do Script_CallMethod(mgr, parent, method, next, quiet = true)
		if !Node_IsAlive(sm) do return
		if sm.current >= 0 && sm.current < len(sm.states) do sm_child_run(sm, sm.states[sm.current].child, false, ctx)
	}
	sm.previous = sm.current
	sm.current = index
	sm.timeInState = 0
	// History (ring).
	sm.history[sm.historyNext] = SM_Change{old, next, sm.timeRunning, why}
	sm.historyNext = (sm.historyNext + 1) % SM_HISTORY_MAX
	sm.historyLen = min(sm.historyLen + 1, SM_HISTORY_MAX)
	sm_child_run(sm, sm.states[index].child, true, ctx)
	if anim := sm.states[index].animation; anim != "" {
		if apn := StateMachine_Player(sm, nodes); apn != nil do AnimationPlayerNode_Play(apn, anim, blend)
	}
	method := strings.concatenate({"on_enter_", next}, context.temp_allocator)
	Script_CallMethod(mgr, sm, method, old, quiet = true)
	if parent != nil && Node_IsAlive(parent) do Script_CallMethod(mgr, parent, method, old, quiet = true)
	if Node_IsAlive(sm) do sm.onStateChanged->notify(sm, next, gc)
	if Node_IsAlive(sm) && sm.onEnterHook != nil do sm.onEnterHook(sm, next)
}

// sm_call_bool: Target:method() on the machine's script, else its
// parent's; (result, found).
@(private = "file")
sm_call_bool :: proc(sm: ^StateMachineNode, method: string) -> (bool, bool) {
	gc := sm.gameContext
	if gc == nil || gc.scriptManager == nil || method == "" do return false, false
	mgr := gc.scriptManager
	targets := [2]^Node{sm, nil}
	if nodes := sm_manager(sm); nodes != nil do targets[1] = GetParent(nodes, sm)
	for target in targets {
		if target == nil || target.scriptInstance == nil do continue
		inst := cast(^ScriptInstance)target.scriptInstance
		if !inst.isReady do continue
		L := mgr.L
		lua.pushcfunction(L, lua_traceback_error_handler)
		errHandler := lua.gettop(L)
		lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(inst.registryRef))
		lua.getfield(L, -1, strings.clone_to_cstring(method, context.temp_allocator))
		if lua.type(L, -1) != .FUNCTION {
			lua.settop(L, errHandler - 1)
			continue
		}
		lua.pushvalue(L, -2) // self
		prev := mgr.currentInstance
		mgr.currentInstance = inst
		ok := false
		if lua.pcall(L, 1, 1, errHandler) != 0 {
			Script_Problem(.Error, "[StateMachine] %s: error in %s(): %s", sm.name, method, lua.tostring(L, -1))
		} else {
			ok = bool(lua.toboolean(L, -1))
		}
		mgr.currentInstance = prev
		lua.settop(L, errHandler - 1)
		return ok, true
	}
	return false, false
}

@(private = "file")
condition_holds :: proc(sm: ^StateMachineNode, c: SM_Condition) -> bool {
	v := StateMachine_GetParam(sm, c.param)
	switch c.op {
	case .Is_True:   return v != 0
	case .Is_False:  return v == 0
	case .Equal:     return v == c.value
	case .Not_Equal: return v != c.value
	case .Greater:   return v > c.value
	case .Less:      return v < c.value
	case .Trigger:   return v != 0
	case .After:     return sm.timeInState >= c.value
	case .Finished:
		apn := StateMachine_Player(sm)
		if apn == nil || sm.current < 0 do return false
		anim := sm.states[sm.current].animation
		return apn.finishedNotified && (anim == "" || AnimationPlayerNode_GetAnimationName(apn) == anim)
	case .Call:
		ok, _ := sm_call_bool(sm, c.param)
		return ok
	case .Or:
		return true // a separator (transition_holds handles groups)
	}
	return false
}

// transition_holds: any group of conditions (split by `or`) all hold.
@(private = "file")
transition_holds :: proc(sm: ^StateMachineNode, t: ^SM_Transition) -> bool {
	groupOk := true
	for c in t.conditions {
		if c.op == .Or {
			if groupOk do return true
			groupOk = true
			continue
		}
		if groupOk && !condition_holds(sm, c) do groupOk = false
	}
	return groupOk
}

// StateMachine_Step checks the transitions once; returns true when one fired.
StateMachine_Step :: proc(sm: ^StateMachineNode, ctx: ^GameContext) -> bool {
	if !sm.running do return false
	if sm.current < 0 || sm.current >= len(sm.states) {
		StateMachine_Start(sm, "", ctx)
		return sm.current >= 0
	}
	cur := sm.states[sm.current].name
	for &t, ti in sm.transitions {
		if t.from != cur && t.from != SM_ANY do continue
		if t.to == cur do continue // "any" -> the current state would restart it every update
		to := StateMachine_FindState(sm, t.to)
		if to < 0 do continue
		if !transition_holds(sm, &t) do continue
		for c in t.conditions do if c.op == .Trigger do StateMachine_SetParam(sm, c.param, 0)
		sm.lastFired = ti
		StateMachine_Enter(sm, to, t.blend, ctx, sm_why(ti))
		return true
	}
	return false
}

@(private = "file")
sm_why :: proc(i: int) -> string {
	WHY :: [?]string{"transition 1", "transition 2", "transition 3", "transition 4", "transition 5", "transition 6", "transition 7", "transition 8", "transition 9", "transition 10", "transition 11", "transition 12", "transition 13", "transition 14", "transition 15", "transition 16"}
	w := WHY
	return w[i] if i < len(w) else "transition"
}

StateMachineNode_Update :: proc(node: ^Node, ctx: ^GameContext, dt: f32) {
	sm := cast(^StateMachineNode)node
	if !sm.running {
		// Started on the first update (scripts are ready by then); a child
		// machine waits for its parent's state.
		if !sm.autostart || sm.current != -1 do return
		if StateMachine_IsChild(sm, sm_manager(sm, ctx)) {
			sm.current = -2 // checked once
			return
		}
		StateMachine_Start(sm, "", ctx)
		return
	}
	sm.timeInState += dt
	sm.timeRunning += dt
	if StateMachine_Step(sm, ctx) do return
	// Gameplay: the current state's update on the scripts.
	if sm.current >= 0 && sm.current < len(sm.states) {
		gc := ctx if ctx != nil else sm.gameContext
		mgr := gc.scriptManager if gc != nil else nil
		method := strings.concatenate({"on_update_", sm.states[sm.current].name}, context.temp_allocator)
		Script_CallMethod(mgr, sm, method, dt, quiet = true)
		if nodes := sm_manager(sm, ctx); nodes != nil {
			if parent := GetParent(nodes, sm); parent != nil && Node_IsAlive(sm) do Script_CallMethod(mgr, parent, method, dt, quiet = true)
		}
	}
}

SM_Op_Parse :: proc(s: string) -> (SM_Op, bool) {
	for name, op in SM_OP_NAMES do if name == s do return op, true
	return .Is_True, false
}

// SM_Op_UsesParam / SM_Op_UsesValue: which fields a condition needs.
SM_Op_UsesParam :: proc(op: SM_Op) -> bool {return op != .Finished && op != .After && op != .Or}
SM_Op_UsesValue :: proc(op: SM_Op) -> bool {
	#partial switch op {
	case .Equal, .Not_Equal, .Greater, .Less, .After: return true
	}
	return false
}
