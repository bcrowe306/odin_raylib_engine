package engine

import "core:fmt"
import "core:strings"
import lua "lua54"

// ============================================================================
// StateMachineNode: named states, arrows between them, parameters and
// triggers, and an AnimationPlayer it drives. The user guide is
// engine/docs/state_machine.md; this is how it works.
//
// States
// - Entering a state runs, in order: `on_enter_<state>(previous)` on the
//   machine's script and its parent's (when defined), then the state's child
//   machine starts, then its animation plays on the player (crossfading for
//   the arrow's blend time). Leaving runs: the child machine stops, then
//   `on_exit_<state>(next)` - the last thing before the change. While a
//   state is current, `on_update_<state>(dt)` runs every update (also on the
//   update a change happened: then for the new state). Stopping the machine
//   runs the current state's on_exit("").
// - Guards: a state can refuse to be left (minTime seconds, Any-state arrows
//   when noInterrupt, its leaveWhen conditions, the script's
//   can_exit_<state>(next)) or entered (enterWhen, can_enter_<state>(prev)).
// - allowRetrigger: the state may go to itself (an arrow from it to it, or
//   from Any state): on_exit, on_enter and the animation run again.
//
// Arrows (transitions) say which states a state can go to, with a mode:
// - Manual (the default for new arrows): only a script takes it -
//   StateMachine_Transition / Lua sm_transition. It honours the guards, and
//   the arrow's conditions when it has any; `force` skips both. It happens
//   at once, inside the call.
// - Automatic: taken by the machine's update when its conditions hold (no
//   conditions = at once) and the guards allow it. Arrows are checked in
//   order; at most one automatic change per update.
// - Arrows from old scenes (saved before modes existed) load as Automatic.
//
// Conditions: a parameter is true / false / == / != / > / < a value, a
// trigger is set, the state's animation finished (a looping one: once it
// has looped), N seconds in the state, or `call`: a method of the machine's
// script (else its parent's) that returns truthy. ANDed; an `or` starts
// another group.
//
// Parameters are typed values scripts set (bool / int / float).
// Triggers are one-shot events: StateMachine_FireTrigger sets one; the first
// automatic arrow it opens takes it (and clears it); otherwise it's cleared
// after the first update that checked it - or, with a buffer time, once it
// has waited that long (input buffering: jump pressed just before landing).
//
// Safety for scripts changing state from callbacks: a chain of changes made
// inside callbacks stops at SM_CHAIN_MAX (a warning names the states);
// changing state from inside a guard, a `call` condition or an on_exit is
// refused (a warning) - the machine is deciding or leaving then.
//
// The last SM_HISTORY_MAX changes are kept (from, to, time, why). explain
// (set by the editor on the machine it shows): each update keeps every way
// out of the current state with each condition's result and what blocks it.
// ============================================================================

SM_Op :: enum {
	Is_True,   // param != 0
	Is_False,  // param == 0
	Equal,
	Not_Equal,
	Greater,
	Less,
	Trigger,   // the trigger `param` is set
	Finished,  // the state's animation reached its end (a looping one: has looped once)
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
	param: string, // a parameter, a trigger (Trigger) or a method (Call)
	value: f32,
}

SM_State :: struct {
	name:      string,
	animation: string,  // "" = leave the player alone (a gameplay state)
	child:     string,  // a child state machine (path) run while in this state
	pos:       [2]f32,  // graph editor position
	breakOnEnter:   bool, // editor only: pause when entered (not saved)
	allowRetrigger: bool, // may go to itself (re-entered)
	// Guards.
	minTime:     f32,                   // can't be left before this many seconds in it
	noInterrupt: bool,                  // Any-state arrows don't fire from it
	leaveWhen:   [dynamic]SM_Condition, // can be left only when these hold (empty: any time)
	enterWhen:   [dynamic]SM_Condition, // can be entered only when these hold
}

// SM_Block: what stops a change (StateMachine_Guard / StateMachine_Transition
// / the explain view).
SM_Block :: enum u8 {
	None,
	No_Transition,     // no arrow from the current state (or Any) to it
	Not_Interruptible, // an Any-state arrow, and the state says no
	Min_Time,          // not long enough in the state
	Leave_When,        // the state's leave conditions don't hold
	Enter_When,        // the target's enter conditions don't hold
	Can_Exit,          // can_exit_<state>(next) returned false
	Can_Enter,         // can_enter_<state>(previous) returned false
	Manual,            // (explain) a manual arrow: waits for a script's sm_transition
	Conditions,        // (a script's transition) the arrow's conditions don't hold
	No_Retrigger,      // to the current state, which doesn't allow retriggering
	Busy,              // asked from inside a guard, a condition or an on_exit
	Too_Deep,          // too many changes chained from callbacks
	Not_Running,       // the machine isn't running
	No_State,          // no state of that name
}

SM_WAYS_MAX :: 32
SM_CONDITIONS_MAX :: 32 // per list, for the explain masks
SM_CHAIN_MAX :: 8       // changes chained from callbacks (on_enter calling sm_transition ...)

// SM_Way: one way out of the current state as last evaluated (explain).
SM_Way :: struct {
	transition: i32,
	arrow:      bool,    // its conditions hold
	block:      SM_Block,
	mask:       u32,     // bit j: its condition j holds
	enterMask:  u32,     // bit j: the target's enter condition j holds
}

SM_HISTORY_MAX :: 32

// SM_Change: one state change (history).
SM_Change :: struct {
	from, to: string, // (owned by the states / static)
	time:     f32,    // seconds the machine had run
	why:      string, // "transition 3", "manual", "forced", "start" (static)
}

SM_ANY :: "*"

SM_Mode :: enum u8 {
	Manual,    // only a script's sm_transition takes it
	Automatic, // the machine takes it when its conditions hold
}

SM_MODE_NAMES := [SM_Mode]string {
	.Manual    = "manual",
	.Automatic = "auto",
}

SM_Transition :: struct {
	from:       string, // a state name or SM_ANY
	to:         string,
	mode:       SM_Mode,
	blend:      f32,    // crossfade seconds when the target state plays its animation
	conditions: [dynamic]SM_Condition,
}

SM_Param_Type :: enum u8 {
	Float,
	Int,
	Bool,
}

SM_PARAM_TYPE_NAMES := [SM_Param_Type]string {
	.Float = "float",
	.Int   = "int",
	.Bool  = "bool",
}

SM_Param :: struct {
	name:  string,
	value: f32, // ints are whole, bools are 0 / 1
	type:  SM_Param_Type,
}

SM_Trigger :: struct {
	name:   string,
	buffer: f32, // seconds it stays set after the first update that checks it (0: that update only)
	// Runtime.
	pending: bool,
	setAt:   u64, // the machine's update count when it was set
	held:    f32, // seconds it has waited since the first check
}

StateMachineNode :: struct {
	using node: Node,
	states:      [dynamic]SM_State,
	transitions: [dynamic]SM_Transition,
	params:      [dynamic]SM_Param,
	triggers:    [dynamic]SM_Trigger,
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
	updates:     u64, // updates run (triggers know whether an update has checked them)
	playerNode:  ^AnimationPlayerNode,
	history:     [SM_HISTORY_MAX]SM_Change, // ring
	historyLen:  int,
	historyNext: int,
	lastFired:   int, // index of the transition that fired last (-1 = none)
	onEnterHook: proc(sm: ^StateMachineNode, state: string), // editor: break on enter
	explain:     bool,    // keep ways / leaveMask each update (the editor's live view)
	ways:        [SM_WAYS_MAX]SM_Way,
	wayCount:    int,
	leaveMask:   u32,     // bit j: the current state's leave condition j holds
	// Callbacks changing state: the chain of changes in progress, and
	// whether the machine is deciding (guards / conditions) or leaving a state.
	chain:       [SM_CHAIN_MAX]string,
	depth:       int,
	evaluating:  int,
	exiting:     bool,
	warned:      [dynamic]string, // unknown trigger names already warned about
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
	sm.triggers = make([dynamic]SM_Trigger, sm.allocator)
	sm.warned = make([dynamic]string, sm.allocator)
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
	append(&sm.states, SM_State{
		name = strings.clone(name, sm.allocator),
		animation = strings.clone(animation, sm.allocator),
		pos = {f32(len(sm.states) % 4) * 200 + 160, f32(len(sm.states) / 4) * 120 + 40},
		leaveWhen = make([dynamic]SM_Condition, sm.allocator),
		enterWhen = make([dynamic]SM_Condition, sm.allocator),
	})
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

// StateMachine_AddTransition adds an arrow (Manual unless a mode is given).
StateMachine_AddTransition :: proc(sm: ^StateMachineNode, from, to: string, blend: f32 = 0, mode := SM_Mode.Manual) -> ^SM_Transition {
	append(&sm.transitions, SM_Transition{
		from = strings.clone(from, sm.allocator),
		to = strings.clone(to, sm.allocator),
		mode = mode,
		blend = blend,
		conditions = make([dynamic]SM_Condition, sm.allocator),
	})
	return &sm.transitions[len(sm.transitions) - 1]
}

StateMachine_AddCondition :: proc(sm: ^StateMachineNode, t: ^SM_Transition, op: SM_Op, param := "", value: f32 = 0) {
	StateMachine_AddConditionTo(sm, &t.conditions, op, param, value)
}

// StateMachine_AddConditionTo: a condition on any list (an arrow's, a
// state's leaveWhen / enterWhen); a parameter or trigger it names is added.
StateMachine_AddConditionTo :: proc(sm: ^StateMachineNode, list: ^[dynamic]SM_Condition, op: SM_Op, param := "", value: f32 = 0) {
	if list.allocator.procedure == nil do list.allocator = sm.allocator
	append(list, SM_Condition{op, strings.clone(param, sm.allocator), value})
	if param == "" do return
	if op == .Trigger do StateMachine_AddTrigger(sm, param)
	else if SM_Op_UsesParam(op) && op != .Call do StateMachine_EnsureParam(sm, param)
}

// StateMachine_HasGuards: the state refuses some changes.
StateMachine_HasGuards :: proc(s: SM_State) -> bool {
	return s.minTime > 0 || s.noInterrupt || len(s.leaveWhen) > 0 || len(s.enterWhen) > 0
}

// StateMachine_FindParam: a parameter's index (-1: none).
StateMachine_FindParam :: proc(sm: ^StateMachineNode, name: string) -> int {
	for p, i in sm.params do if p.name == name do return i
	return -1
}

// StateMachine_EnsureParam: the parameter of that name, added (with that
// type) when missing.
StateMachine_EnsureParam :: proc(sm: ^StateMachineNode, name: string, value: f32 = 0, type := SM_Param_Type.Float) -> ^SM_Param {
	if i := StateMachine_FindParam(sm, name); i >= 0 do return &sm.params[i]
	append(&sm.params, SM_Param{strings.clone(name, sm.allocator), sm_coerce(value, type), type})
	return &sm.params[len(sm.params) - 1]
}

// sm_coerce: a value as a parameter type stores it.
@(private = "file")
sm_coerce :: proc(v: f32, type: SM_Param_Type) -> f32 {
	switch type {
	case .Bool: return 1 if v != 0 else 0
	case .Int:  return f32(i64(v + (0.5 if v >= 0 else -0.5)))
	case .Float:
	}
	return v
}

// StateMachine_SetParamType changes a parameter's type (its value converted).
StateMachine_SetParamType :: proc(p: ^SM_Param, type: SM_Param_Type) {
	p.type = type
	p.value = sm_coerce(p.value, type)
}

// StateMachine_RenameParam renames a parameter and the conditions using it.
StateMachine_RenameParam :: proc(sm: ^StateMachineNode, index: int, name: string) {
	if index < 0 || index >= len(sm.params) || name == "" do return
	old := sm.params[index].name
	n := strings.clone(name, sm.allocator)
	sm.params[index].name = n
	sm_rename_refs(sm, old, n, false)
}

// StateMachine_FindTrigger: a trigger's index (-1: none).
StateMachine_FindTrigger :: proc(sm: ^StateMachineNode, name: string) -> int {
	for t, i in sm.triggers do if t.name == name do return i
	return -1
}

// StateMachine_AddTrigger: the trigger of that name, added when missing.
StateMachine_AddTrigger :: proc(sm: ^StateMachineNode, name: string, buffer: f32 = 0) -> ^SM_Trigger {
	if i := StateMachine_FindTrigger(sm, name); i >= 0 do return &sm.triggers[i]
	if sm.triggers.allocator.procedure == nil do sm.triggers = make([dynamic]SM_Trigger, sm.allocator)
	append(&sm.triggers, SM_Trigger{name = strings.clone(name, sm.allocator), buffer = max(buffer, 0)})
	return &sm.triggers[len(sm.triggers) - 1]
}

// StateMachine_RenameTrigger renames a trigger and the conditions testing it.
StateMachine_RenameTrigger :: proc(sm: ^StateMachineNode, index: int, name: string) {
	if index < 0 || index >= len(sm.triggers) || name == "" do return
	old := sm.triggers[index].name
	n := strings.clone(name, sm.allocator)
	sm.triggers[index].name = n
	sm_rename_refs(sm, old, n, true)
}

@(private = "file")
sm_rename_refs :: proc(sm: ^StateMachineNode, old, new: string, trigger: bool) {
	fix :: proc(list: []SM_Condition, old, new: string, trigger: bool) {
		for &c in list {
			if c.param != old do continue
			if trigger == (c.op == .Trigger) && (trigger || (SM_Op_UsesParam(c.op) && c.op != .Call)) do c.param = new
		}
	}
	for &t in sm.transitions do fix(t.conditions[:], old, new, trigger)
	for &s in sm.states {
		fix(s.leaveWhen[:], old, new, trigger)
		fix(s.enterWhen[:], old, new, trigger)
	}
}

// --- runtime -------------------------------------------------------------------

// StateMachine_SetParam sets a parameter (added as a float when missing),
// converted to its type (bools 0 / 1, ints whole).
StateMachine_SetParam :: proc(sm: ^StateMachineNode, name: string, value: f32) {
	p := StateMachine_EnsureParam(sm, name)
	p.value = sm_coerce(value, p.type)
}

StateMachine_GetParam :: proc(sm: ^StateMachineNode, name: string) -> f32 {
	for p in sm.params do if p.name == name do return p.value
	return 0
}

// StateMachine_FireTrigger sets a trigger. False (and a warning, once per
// name) when the machine has no trigger of that name.
StateMachine_FireTrigger :: proc(sm: ^StateMachineNode, name: string) -> bool {
	i := StateMachine_FindTrigger(sm, name)
	if i < 0 {
		for w in sm.warned do if w == name do return false
		append(&sm.warned, strings.clone(name, sm.allocator))
		Script_Problem(.Warning, "[StateMachine] %s has no trigger %q (add it in the State Machine tab > Parameters & Triggers)", sm.name, name)
		return false
	}
	t := &sm.triggers[i]
	t.pending = true
	t.setAt = sm.updates
	t.held = 0
	return true
}

// StateMachine_ClearTrigger un-sets a trigger.
StateMachine_ClearTrigger :: proc(sm: ^StateMachineNode, name: string) {
	if i := StateMachine_FindTrigger(sm, name); i >= 0 do sm.triggers[i].pending = false
}

// StateMachine_TriggerPending: the trigger is set (waiting for an arrow).
StateMachine_TriggerPending :: proc(sm: ^StateMachineNode, name: string) -> bool {
	i := StateMachine_FindTrigger(sm, name)
	return i >= 0 && sm.triggers[i].pending
}

// sm_age_triggers: after an update checked them, triggers without a buffer
// clear; buffered ones clear once they've waited longer than their buffer.
@(private = "file")
sm_age_triggers :: proc(sm: ^StateMachineNode, dt: f32) {
	for &t in sm.triggers {
		if !t.pending || t.setAt >= sm.updates do continue // (set during this update: checked by the next)
		t.held += dt
		if t.held > t.buffer do t.pending = false
	}
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

// StateMachine_Start enters `state` (or the initial state). A running
// machine leaves its current state first (on_exit).
StateMachine_Start :: proc(sm: ^StateMachineNode, state := "", ctx: ^GameContext = nil) {
	if sm.running do StateMachine_Stop(sm, ctx)
	sm.running = true
	sm.current = -1
	sm.previous = -1
	sm.lastFired = -1
	for &t in sm.triggers do t.pending = false
	// The state asked for, else the initial one, else the first.
	target := state if state != "" else sm.initial
	if i := StateMachine_FindState(sm, target); i >= 0 {
		StateMachine_Enter(sm, i, 0, ctx, "start")
	} else if i := StateMachine_FindState(sm, sm.initial); i >= 0 {
		StateMachine_Enter(sm, i, 0, ctx, "start")
	} else if len(sm.states) > 0 {
		StateMachine_Enter(sm, 0, 0, ctx, "start")
	}
}

// StateMachine_Stop stops the machine: its current state's child machine
// stops, then its on_exit("") runs. The state stays current (sm_state).
StateMachine_Stop :: proc(sm: ^StateMachineNode, ctx: ^GameContext = nil) {
	if !sm.running do return
	sm.running = false
	if sm.current < 0 || sm.current >= len(sm.states) do return
	sm_child_run(sm, sm.states[sm.current].child, false, ctx)
	sm_callback(sm, ctx, "on_exit_", sm.states[sm.current].name, "", exiting = true)
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

// sm_callback: <prefix><state>(arg) on the machine's script, then its
// parent's (when defined). exiting: state changes are refused meanwhile.
@(private = "file")
sm_callback :: proc(sm: ^StateMachineNode, ctx: ^GameContext, prefix, state: string, arg: EventValue, exiting := false) {
	gc := ctx if ctx != nil else sm.gameContext
	mgr := gc.scriptManager if gc != nil else nil
	if mgr == nil do return
	nodes := sm_manager(sm, ctx)
	parent := GetParent(nodes, sm) if nodes != nil else nil
	method := strings.concatenate({prefix, state}, context.temp_allocator)
	wasExiting := sm.exiting
	if exiting do sm.exiting = true
	Script_CallMethod(mgr, sm, method, arg, quiet = true)
	if parent != nil && Node_IsAlive(sm) && Node_IsAlive(parent) do Script_CallMethod(mgr, parent, method, arg, quiet = true)
	if Node_IsAlive(sm) do sm.exiting = wasExiting
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

// StateMachine_Enter changes to state `index` (no checks): the current
// state's child stops and its on_exit(next) runs, then on_enter(previous),
// the child machine starts and the animation plays. An on_enter that moved
// the machine on (a chain) skips the rest for this state.
StateMachine_Enter :: proc(sm: ^StateMachineNode, index: int, blend: f32, ctx: ^GameContext, why := "") {
	gc := ctx if ctx != nil else sm.gameContext
	nodes := sm_manager(sm, ctx)
	old := StateMachine_CurrentName(sm)
	next := sm.states[index].name
	if old != "" {
		sm_child_run(sm, sm.states[sm.current].child, false, ctx)
		sm_callback(sm, ctx, "on_exit_", old, next, exiting = true)
		if !Node_IsAlive(sm) do return
	}
	sm.previous = sm.current
	sm.current = index
	sm.timeInState = 0
	sm.wayCount = 0 // (they were the old state's)
	sm.leaveMask = 0
	// History (ring).
	sm.history[sm.historyNext] = SM_Change{old, next, sm.timeRunning, why}
	sm.historyNext = (sm.historyNext + 1) % SM_HISTORY_MAX
	sm.historyLen = min(sm.historyLen + 1, SM_HISTORY_MAX)
	sm_callback(sm, ctx, "on_enter_", next, old)
	if !Node_IsAlive(sm) || sm.current != index || !sm.running do return // (on_enter moved on, or stopped it)
	sm_child_run(sm, sm.states[index].child, true, ctx)
	if anim := sm.states[index].animation; anim != "" {
		if apn := StateMachine_Player(sm, nodes); apn != nil do AnimationPlayerNode_Play(apn, anim, blend)
	}
	if Node_IsAlive(sm) do sm.onStateChanged->notify(sm, next, gc)
	if Node_IsAlive(sm) && sm.onEnterHook != nil do sm.onEnterHook(sm, next)
	if Node_IsAlive(sm) && StateMachine_EnterHook != nil do StateMachine_EnterHook(sm, next)
}

// StateMachine_EnterHook: every machine's state change (the editor link's
// break on enter in a running game).
StateMachine_EnterHook: proc(sm: ^StateMachineNode, state: string)

// StateMachine_StatusJSON: a machine's live status for the editor link:
// {"path", "running", "current", "time", "fired", "leave", "ways",
// "history": [[from, to, time, why], ...], "params": [[name, value], ...],
// "triggers": [[name, pending 0|1, seconds waited], ...]}.
StateMachine_StatusJSON :: proc(sm: ^StateMachineNode, path: string) -> string {
	sb := strings.builder_make(context.temp_allocator)
	q :: proc(sb: ^strings.Builder, s: string) {
		strings.write_byte(sb, '"')
		for r in s {
			switch r {
			case '"': strings.write_string(sb, `\"`)
			case '\\': strings.write_string(sb, `\\`)
			case: strings.write_rune(sb, r)
			}
		}
		strings.write_byte(sb, '"')
	}
	strings.write_string(&sb, "{\"path\": ")
	q(&sb, path)
	fmt.sbprintf(&sb, ", \"running\": %t, \"current\": ", sm.running)
	q(&sb, StateMachine_CurrentName(sm))
	fmt.sbprintf(&sb, ", \"time\": %.3f, \"fired\": %d", sm.timeInState, sm.lastFired)
	// The ways out (explain): [transition, arrow 0|1, block, mask, enterMask].
	fmt.sbprintf(&sb, ", \"leave\": %d, \"ways\": [", sm.leaveMask)
	for w, i in sm.ways[:sm.wayCount] {
		if i > 0 do strings.write_string(&sb, ", ")
		fmt.sbprintf(&sb, "[%d, %d, %d, %d, %d]", w.transition, 1 if w.arrow else 0, int(w.block), w.mask, w.enterMask)
	}
	strings.write_string(&sb, "], \"history\": [")
	for h, i in StateMachine_History(sm) {
		if i > 0 do strings.write_string(&sb, ", ")
		strings.write_byte(&sb, '[')
		q(&sb, h.from)
		strings.write_string(&sb, ", ")
		q(&sb, h.to)
		fmt.sbprintf(&sb, ", %.3f, ", h.time)
		q(&sb, h.why)
		strings.write_byte(&sb, ']')
	}
	strings.write_string(&sb, "], \"params\": [")
	for p, i in sm.params {
		if i > 0 do strings.write_string(&sb, ", ")
		strings.write_byte(&sb, '[')
		q(&sb, p.name)
		fmt.sbprintf(&sb, ", %g]", p.value)
	}
	strings.write_string(&sb, "], \"triggers\": [")
	for t, i in sm.triggers {
		if i > 0 do strings.write_string(&sb, ", ")
		strings.write_byte(&sb, '[')
		q(&sb, t.name)
		fmt.sbprintf(&sb, ", %d, %.3f]", 1 if t.pending else 0, t.held)
	}
	strings.write_string(&sb, "]}")
	return strings.to_string(sb)
}

// sm_call_bool: Target:method([arg]) on the machine's script, else its
// parent's (the first that defines it answers); (result, found). The
// machine is "evaluating" meanwhile: the script can't change its state.
@(private = "file")
sm_call_bool :: proc(sm: ^StateMachineNode, method: string, arg := "", hasArg := false) -> (bool, bool) {
	gc := sm.gameContext
	if gc == nil || gc.scriptManager == nil || method == "" do return false, false
	mgr := gc.scriptManager
	targets := [2]^Node{sm, nil}
	if nodes := sm_manager(sm); nodes != nil do targets[1] = GetParent(nodes, sm)
	sm.evaluating += 1
	defer if Node_IsAlive(sm) do sm.evaluating -= 1
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
		nargs: i32 = 1
		if hasArg {
			lua.pushstring(L, strings.clone_to_cstring(arg, context.temp_allocator))
			nargs = 2
		}
		prev := mgr.currentInstance
		mgr.currentInstance = inst
		ok := false
		if lua.pcall(L, nargs, 1, errHandler) != 0 {
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

// SM_EQUAL_EPSILON: == and != on float parameters allow this much
// difference (0.1 + 0.2 == 0.3); ints and bools compare exactly.
SM_EQUAL_EPSILON :: 1e-4

@(private = "file")
condition_holds :: proc(sm: ^StateMachineNode, c: SM_Condition) -> bool {
	switch c.op {
	case .Is_True, .Is_False, .Equal, .Not_Equal, .Greater, .Less:
		v: f32
		isFloat := true
		if i := StateMachine_FindParam(sm, c.param); i >= 0 {
			v = sm.params[i].value
			isFloat = sm.params[i].type == .Float
		}
		eq := abs(v - c.value) <= SM_EQUAL_EPSILON if isFloat else v == c.value
		#partial switch c.op {
		case .Is_True:   return v != 0
		case .Is_False:  return v == 0
		case .Equal:     return eq
		case .Not_Equal: return !eq
		case .Greater:   return v > c.value
		case .Less:      return v < c.value
		}
	case .Trigger:
		return StateMachine_TriggerPending(sm, c.param)
	case .After:
		return sm.timeInState >= c.value
	case .Finished:
		apn := StateMachine_Player(sm)
		if apn == nil || sm.current < 0 do return false
		anim := sm.states[sm.current].animation
		if anim != "" && AnimationPlayerNode_GetAnimationName(apn) != anim do return false
		return apn.finishedNotified || apn.loopsDone > 0 // (a looping animation: it has looped once)
	case .Call:
		ok, _ := sm_call_bool(sm, c.param)
		return ok
	case .Or:
		return true // a separator (conditions_hold handles groups)
	}
	return false
}

// conditions_hold: any group of conditions (split by `or`) all hold; an
// empty list holds.
@(private = "file")
conditions_hold :: proc(sm: ^StateMachineNode, conds: []SM_Condition) -> bool {
	groupOk := true
	for c in conds {
		if c.op == .Or {
			if groupOk do return true
			groupOk = true
			continue
		}
		if groupOk && !condition_holds(sm, c) do groupOk = false
	}
	return groupOk
}

// StateMachine_ConditionsHold: (tests / tools) a condition list holds now.
StateMachine_ConditionsHold :: proc(sm: ^StateMachineNode, conds: []SM_Condition) -> bool {
	return conditions_hold(sm, conds)
}

// conditions_mask: like conditions_hold, but every condition is evaluated
// (bit j = condition j holds; the live view).
@(private = "file")
conditions_mask :: proc(sm: ^StateMachineNode, conds: []SM_Condition) -> (holds: bool, mask: u32) {
	groupOk, anyGroup := true, false
	for c, j in conds {
		if c.op == .Or {
			anyGroup ||= groupOk
			groupOk = true
			continue
		}
		ok := condition_holds(sm, c)
		if ok && j < SM_CONDITIONS_MAX do mask |= 1 << u32(j)
		if !ok do groupOk = false
	}
	return anyGroup || groupOk, mask
}

@(private = "file")
consume_triggers :: proc(sm: ^StateMachineNode, conds: []SM_Condition) {
	for c in conds do if c.op == .Trigger do StateMachine_ClearTrigger(sm, c.param)
}

// StateMachine_Guard: what stops the machine going from state `from` to
// `to` (.None: nothing); viaAny = by an Any-state arrow. The cheap checks
// come first, the scripts last.
StateMachine_Guard :: proc(sm: ^StateMachineNode, from, to: int, viaAny: bool) -> SM_Block {
	if from >= 0 && from < len(sm.states) {
		s := &sm.states[from]
		if viaAny && s.noInterrupt do return .Not_Interruptible
		if s.minTime > 0 && sm.timeInState < s.minTime do return .Min_Time
		if !conditions_hold(sm, s.leaveWhen[:]) do return .Leave_When
	}
	if to < 0 || to >= len(sm.states) do return .No_Transition
	if !conditions_hold(sm, sm.states[to].enterWhen[:]) do return .Enter_When
	return sm_script_guards(sm, from, to)
}

// sm_script_guards: can_exit_<from>(next) / can_enter_<to>(previous).
@(private = "file")
sm_script_guards :: proc(sm: ^StateMachineNode, from, to: int) -> SM_Block {
	fromName := sm.states[from].name if from >= 0 && from < len(sm.states) else ""
	toName := sm.states[to].name
	if fromName != "" {
		if ok, found := sm_call_bool(sm, strings.concatenate({"can_exit_", fromName}, context.temp_allocator), toName, true); found && !ok do return .Can_Exit
	}
	if ok, found := sm_call_bool(sm, strings.concatenate({"can_enter_", toName}, context.temp_allocator), fromName, true); found && !ok do return .Can_Enter
	return .None
}

// StateMachine_BlockText: a line saying why a change is blocked.
StateMachine_BlockText :: proc(sm: ^StateMachineNode, block: SM_Block, from, to: string, timeInState: f32) -> string {
	fi := StateMachine_FindState(sm, from)
	switch block {
	case .None:              return ""
	case .No_Transition:     return fmt.tprintf("no arrow from %s to %s", from if from != "" else "(none)", to)
	case .Not_Interruptible: return fmt.tprintf("%s can't be interrupted by Any state", from)
	case .Min_Time:
		need := sm.states[fi].minTime if fi >= 0 else 0
		return fmt.tprintf("%s: leave after %.2gs (%.2fs so far)", from, need, timeInState)
	case .Leave_When:        return fmt.tprintf("%s: its leave conditions don't hold", from)
	case .Enter_When:        return fmt.tprintf("%s: its enter conditions don't hold", to)
	case .Can_Exit:          return fmt.tprintf("can_exit_%s(\"%s\") said no", from, to)
	case .Can_Enter:         return fmt.tprintf("can_enter_%s(\"%s\") said no", to, from)
	case .Manual:            return fmt.tprintf("manual: a script calls sm_transition(\"%s\")", to)
	case .Conditions:        return fmt.tprintf("the arrow %s -> %s: its conditions don't hold", from, to)
	case .No_Retrigger:      return fmt.tprintf("%s doesn't allow retriggering (Allow Retrigger is off)", to)
	case .Busy:              return "can't change state from inside a guard, a condition or an on_exit"
	case .Too_Deep:          return fmt.tprintf("more than %d changes chained from callbacks", SM_CHAIN_MAX)
	case .Not_Running:       return "the state machine isn't running"
	case .No_State:          return fmt.tprintf("no state %q", to)
	}
	return ""
}

// sm_way_to: the arrow from the current state (else from Any) to `to`
// (-1: none), and whether it's from Any.
@(private = "file")
sm_way_to :: proc(sm: ^StateMachineNode, to: string) -> (index: int, viaAny: bool) {
	cur := StateMachine_CurrentName(sm)
	for t, k in sm.transitions do if t.from == cur && t.to == to do return k, false
	for t, k in sm.transitions do if t.from == SM_ANY && t.to == to do return k, true
	return -1, false
}

// sm_retrigger_ok: an arrow to the current state is allowed only when it
// allows retriggering.
@(private = "file")
sm_retrigger_ok :: proc(sm: ^StateMachineNode, to: int) -> bool {
	return to != sm.current || sm.states[to].allowRetrigger
}

// StateMachine_Step checks the automatic arrows once; returns true when one
// fired. Manual arrows wait for a script.
StateMachine_Step :: proc(sm: ^StateMachineNode, ctx: ^GameContext) -> bool {
	if !sm.running do return false
	if sm.current < 0 || sm.current >= len(sm.states) {
		StateMachine_Start(sm, "", ctx)
		return sm.current >= 0
	}
	if sm.explain do return sm_step_explained(sm, ctx)
	cur := sm.states[sm.current].name
	for &t, ti in sm.transitions {
		if t.mode != .Automatic do continue
		if t.from != cur && t.from != SM_ANY do continue
		to := StateMachine_FindState(sm, t.to)
		if to < 0 || !sm_retrigger_ok(sm, to) do continue
		if !conditions_hold(sm, t.conditions[:]) do continue
		if StateMachine_Guard(sm, sm.current, to, t.from == SM_ANY) != .None do continue
		sm_fire(sm, ti, to, -1, ctx)
		return true
	}
	return false
}

// sm_fire takes transition ti (its triggers and the guards' are used up);
// counts the change in the chain made from callbacks.
@(private = "file")
sm_fire :: proc(sm: ^StateMachineNode, ti, to: int, blend: f32, ctx: ^GameContext, why := "") {
	t := &sm.transitions[ti]
	consume_triggers(sm, t.conditions[:])
	consume_triggers(sm, sm.states[sm.current].leaveWhen[:])
	consume_triggers(sm, sm.states[to].enterWhen[:])
	sm.lastFired = ti
	if sm.depth < SM_CHAIN_MAX do sm.chain[sm.depth] = sm.states[to].name
	sm.depth += 1
	StateMachine_Enter(sm, to, blend if blend >= 0 else t.blend, ctx, why if why != "" else sm_why(ti))
	if Node_IsAlive(sm) do sm.depth -= 1
}

// sm_step_explained: Step, keeping every way out with each condition's
// result (all evaluated) and what blocks it; the first open automatic way
// fires. Manual arrows are listed as waiting for a script.
@(private = "file")
sm_step_explained :: proc(sm: ^StateMachineNode, ctx: ^GameContext) -> bool {
	cur := sm.states[sm.current].name
	s := &sm.states[sm.current]
	leaveOk: bool
	leaveOk, sm.leaveMask = conditions_mask(sm, s.leaveWhen[:])
	sm.wayCount = 0
	fire, fireTo := -1, -1
	for &t, ti in sm.transitions {
		if t.from != cur && t.from != SM_ANY do continue
		to := StateMachine_FindState(sm, t.to)
		if to < 0 do continue
		if t.from == SM_ANY && to == sm.current && !s.allowRetrigger do continue // (not a way out)
		w := SM_Way{transition = i32(ti)}
		w.arrow, w.mask = conditions_mask(sm, t.conditions[:])
		enterOk: bool
		enterOk, w.enterMask = conditions_mask(sm, sm.states[to].enterWhen[:])
		viaAny := t.from == SM_ANY
		switch {
		case !sm_retrigger_ok(sm, to):
			w.block = .No_Retrigger
		case t.mode == .Manual:
			w.block = .Manual
		case w.arrow:
			// The scripts' guards only for arrows that would fire.
			w.block = StateMachine_Guard(sm, sm.current, to, viaAny)
		case viaAny && s.noInterrupt:                      w.block = .Not_Interruptible
		case s.minTime > 0 && sm.timeInState < s.minTime: w.block = .Min_Time
		case !leaveOk:                                     w.block = .Leave_When
		case !enterOk:                                     w.block = .Enter_When
		}
		if sm.wayCount < SM_WAYS_MAX {
			sm.ways[sm.wayCount] = w
			sm.wayCount += 1
		}
		if fire < 0 && t.mode == .Automatic && w.arrow && w.block == .None do fire, fireTo = ti, to
	}
	if fire < 0 do return false
	sm_fire(sm, fire, fireTo, -1, ctx)
	return true
}

// StateMachine_CanTransition: what would stop StateMachine_Transition to
// `state` now (.None: it would go), without changing anything. The arrow's
// conditions are checked only when it has some; force skips them and the
// guards. Returns the arrow's index too.
StateMachine_CanTransition :: proc(sm: ^StateMachineNode, state: string, force := false) -> (SM_Block, int) {
	if !sm.running || sm.current < 0 || sm.current >= len(sm.states) do return .Not_Running, -1
	to := StateMachine_FindState(sm, state)
	if to < 0 do return .No_State, -1
	if sm.evaluating > 0 || sm.exiting do return .Busy, -1
	if sm.depth >= SM_CHAIN_MAX do return .Too_Deep, -1
	ti, viaAny := sm_way_to(sm, state)
	if ti < 0 do return .No_Transition, -1
	if !sm_retrigger_ok(sm, to) do return .No_Retrigger, ti
	if force do return .None, ti
	if conds := sm.transitions[ti].conditions[:]; len(conds) > 0 && !conditions_hold(sm, conds) do return .Conditions, ti
	return StateMachine_Guard(sm, sm.current, to, viaAny), ti
}

// StateMachine_Transition goes to `state` now, along an arrow (Manual or
// Automatic) from the current state or Any state - the script's way to
// change state. Without force: the guards, and the arrow's conditions when
// it has any; force skips both. blend < 0 = the arrow's. Returns what
// stopped it (.None = done); a refused call from inside a guard / condition
// / on_exit, or a chain too long, also warns.
StateMachine_Transition :: proc(sm: ^StateMachineNode, state: string, force := false, blend: f32 = -1, ctx: ^GameContext = nil) -> SM_Block {
	block, ti := StateMachine_CanTransition(sm, state, force)
	switch block {
	case .Busy:
		Script_Problem(.Warning, "[StateMachine] %s: sm_transition(%q) from inside a guard, a condition or an on_exit is ignored (change state in on_enter / on_update or your own update)", sm.name, state)
	case .Too_Deep:
		chain := strings.join(sm.chain[:sm.depth], " -> ", context.temp_allocator)
		Script_Problem(.Warning, "[StateMachine] %s: sm_transition(%q) stopped - %d changes chained from callbacks (%s): two states may be sending each other back", sm.name, state, SM_CHAIN_MAX, chain)
	case .None, .No_Transition, .Not_Interruptible, .Min_Time, .Leave_When, .Enter_When, .Can_Exit, .Can_Enter, .Manual, .Conditions, .No_Retrigger, .Not_Running, .No_State:
	}
	if block != .None do return block
	sm_fire(sm, ti, StateMachine_FindState(sm, state), blend, ctx, "forced" if force else "manual")
	return .None
}

@(private = "file")
sm_why :: proc(i: int) -> string {
	WHY :: [?]string{"transition 1", "transition 2", "transition 3", "transition 4", "transition 5", "transition 6", "transition 7", "transition 8", "transition 9", "transition 10", "transition 11", "transition 12", "transition 13", "transition 14", "transition 15", "transition 16"}
	w := WHY
	return w[i] if i < len(w) else "transition"
}

// StateMachineNode_Update: the automatic arrows (at most one change), then
// the current state's on_update(dt), then the triggers age.
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
	sm.updates += 1
	sm.timeInState += dt
	sm.timeRunning += dt
	StateMachine_Step(sm, ctx)
	if !Node_IsAlive(sm) do return
	// Gameplay: the current state's update on the scripts.
	if sm.running && sm.current >= 0 && sm.current < len(sm.states) {
		sm_callback(sm, ctx, "on_update_", sm.states[sm.current].name, dt)
	}
	if Node_IsAlive(sm) do sm_age_triggers(sm, dt)
}

SM_Op_Parse :: proc(s: string) -> (SM_Op, bool) {
	for name, op in SM_OP_NAMES do if name == s do return op, true
	return .Is_True, false
}

SM_Mode_Parse :: proc(s: string) -> (SM_Mode, bool) {
	for name, m in SM_MODE_NAMES do if name == s do return m, true
	return .Automatic, false
}

SM_Param_Type_Parse :: proc(s: string) -> (SM_Param_Type, bool) {
	for name, t in SM_PARAM_TYPE_NAMES do if name == s do return t, true
	return .Float, false
}

// SM_Op_UsesParam / SM_Op_UsesValue: which fields a condition needs.
SM_Op_UsesParam :: proc(op: SM_Op) -> bool {return op != .Finished && op != .After && op != .Or}
SM_Op_UsesValue :: proc(op: SM_Op) -> bool {
	#partial switch op {
	case .Equal, .Not_Equal, .Greater, .Less, .After: return true
	}
	return false
}
