package engine

import "core:strings"

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
}

SM_Condition :: struct {
	op:    SM_Op,
	param: string,
	value: f32,
}

SM_State :: struct {
	name:      string,
	animation: string, // "" = leave the player alone
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
	player:      string, // path to the AnimationPlayer ("" = find one)
	autostart:   bool,

	// Runtime.
	running:     bool,
	current:     int, // index into states, -1 = none
	previous:    int,
	timeInState: f32,
	playerNode:  ^AnimationPlayerNode,
	// "state_changed"(name): entered a state.
	onStateChanged: EventSubject,
}

StateMachineNode_Create :: proc(scene: ^Scene, name: string = "StateMachine", parent: ^Node = nil) -> ^StateMachineNode {
	sm := CreateNode(scene.manager, StateMachineNode)
	StateMachineNode_Init(sm)
	sm.name = name
	return sm
}

StateMachineNode_Init :: proc(sm: ^StateMachineNode) {
	sm.states = make([dynamic]SM_State, sm.allocator)
	sm.transitions = make([dynamic]SM_Transition, sm.allocator)
	sm.params = make([dynamic]SM_Param, sm.allocator)
	sm.autostart = true
	sm.current = -1
	sm.previous = -1
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
	append(&sm.states, SM_State{strings.clone(name, sm.allocator), strings.clone(animation, sm.allocator)})
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
	if param != "" && op != .After && op != .Finished do StateMachine_EnsureParam(sm, param)
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
	target := state if state != "" else sm.initial
	if i := StateMachine_FindState(sm, target); i >= 0 {
		StateMachine_Enter(sm, i, 0, ctx)
	} else if len(sm.states) > 0 {
		StateMachine_Enter(sm, 0, 0, ctx)
	}
}

StateMachine_Stop :: proc(sm: ^StateMachineNode) {
	sm.running = false
}

// StateMachine_Travel switches to a state now (no conditions checked).
StateMachine_Travel :: proc(sm: ^StateMachineNode, state: string, blend: f32 = 0, ctx: ^GameContext = nil) -> bool {
	i := StateMachine_FindState(sm, state)
	if i < 0 do return false
	sm.running = true
	StateMachine_Enter(sm, i, blend, ctx)
	return true
}

StateMachine_Enter :: proc(sm: ^StateMachineNode, index: int, blend: f32, ctx: ^GameContext) {
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
	}
	sm.previous = sm.current
	sm.current = index
	sm.timeInState = 0
	if anim := sm.states[index].animation; anim != "" {
		if apn := StateMachine_Player(sm, nodes); apn != nil do AnimationPlayerNode_Play(apn, anim, blend)
	}
	method := strings.concatenate({"on_enter_", next}, context.temp_allocator)
	Script_CallMethod(mgr, sm, method, old, quiet = true)
	if parent != nil && Node_IsAlive(parent) do Script_CallMethod(mgr, parent, method, old, quiet = true)
	if Node_IsAlive(sm) do sm.onStateChanged->notify(sm, next, gc)
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
	}
	return false
}

// StateMachine_Step checks the transitions once; returns true when one fired.
StateMachine_Step :: proc(sm: ^StateMachineNode, ctx: ^GameContext) -> bool {
	if !sm.running do return false
	if sm.current < 0 || sm.current >= len(sm.states) {
		StateMachine_Start(sm, "", ctx)
		return sm.current >= 0
	}
	cur := sm.states[sm.current].name
	for &t in sm.transitions {
		if t.from != cur && t.from != SM_ANY do continue
		if t.to == cur do continue // "any" -> the current state would restart it every update
		to := StateMachine_FindState(sm, t.to)
		if to < 0 do continue
		ok := true
		for c in t.conditions do if !condition_holds(sm, c) {ok = false; break}
		if !ok do continue
		for c in t.conditions do if c.op == .Trigger do StateMachine_SetParam(sm, c.param, 0)
		StateMachine_Enter(sm, to, t.blend, ctx)
		return true
	}
	return false
}

StateMachineNode_Update :: proc(node: ^Node, ctx: ^GameContext, dt: f32) {
	sm := cast(^StateMachineNode)node
	if !sm.running {
		// Started on the first update (scripts are ready by then).
		if !sm.autostart || sm.current != -1 do return
		StateMachine_Start(sm, "", ctx)
		return
	}
	sm.timeInState += dt
	StateMachine_Step(sm, ctx)
}

SM_Op_Parse :: proc(s: string) -> (SM_Op, bool) {
	for name, op in SM_OP_NAMES do if name == s do return op, true
	return .Is_True, false
}

// SM_Op_UsesParam / SM_Op_UsesValue: which fields a condition needs.
SM_Op_UsesParam :: proc(op: SM_Op) -> bool {return op != .Finished && op != .After}
SM_Op_UsesValue :: proc(op: SM_Op) -> bool {
	#partial switch op {
	case .Equal, .Not_Equal, .Greater, .Less, .After: return true
	}
	return false
}
