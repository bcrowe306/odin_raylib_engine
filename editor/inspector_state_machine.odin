package editor

import "core:fmt"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Inspector: StateMachineNode - the AnimationPlayer it drives, its states
// (each optionally playing an animation), parameters, and transitions with
// their conditions. While simulating, the current state is highlighted.
// ============================================================================

@(private = "file")
OP_LABELS := [e.SM_Op]string {
	.Is_True   = "is true",
	.Is_False  = "is false",
	.Equal     = "==",
	.Not_Equal = "!=",
	.Greater   = ">",
	.Less      = "<",
	.Trigger   = "trigger",
	.Finished  = "animation finished",
	.After     = "after (s)",
}

// name_field: an InputText for a string held in the node's arena; returns
// the new text when an edit is committed (Enter or focus lost).
@(private = "file")
name_field :: proc(state: ^EditorState, id, value: string, width: f32, hint: cstring = "") -> (string, bool) {
	@(static) buf: [128]u8
	@(static) editing: string
	key := id
	if editing != key {
		buf = {}
		copy(buf[:len(buf) - 1], value)
	}
	imgui.SetNextItemWidth(width)
	imgui.InputTextWithHint(fmt.ctprintf("##%s", id), hint, cstring(raw_data(buf[:])), len(buf), {.AutoSelectAll})
	Drive_Item(id)
	if imgui.IsItemActivated() {
		delete(editing)
		editing = strings.clone(key)
	}
	if imgui.IsItemDeactivated() {
		delete(editing)
		editing = ""
		text := strings.trim_space(string(cstring(raw_data(buf[:]))))
		if text != value && text != "" do return strings.clone(text, context.temp_allocator), true
	}
	return "", false
}

@(private = "file")
state_combo :: proc(id: string, sm: ^e.StateMachineNode, cur: string, allowAny: bool) -> (string, bool) {
	preview := "Any state" if cur == e.SM_ANY else cur
	result, changed := cur, false
	if imgui.BeginCombo(fmt.ctprintf("##%s", id), strings.clone_to_cstring(preview, context.temp_allocator)) {
		if allowAny {
			if imgui.Selectable("Any state", cur == e.SM_ANY) do result, changed = e.SM_ANY, cur != e.SM_ANY
			Drive_Item("pick:Any state")
		}
		for s in sm.states {
			if imgui.Selectable(strings.clone_to_cstring(s.name, context.temp_allocator), s.name == cur) do result, changed = s.name, s.name != cur
			Drive_Item(fmt.tprintf("pick:%s", s.name))
		}
		imgui.EndCombo()
	}
	Drive_Item(id)
	return result, changed
}

inspector_state_machine :: proc(state: ^EditorState, sm: ^e.StateMachineNode) {
	if !UI_SectionHeader("State Machine") do return
	mgr := state.activeScene.manager
	player := e.StateMachine_Player(sm, mgr)
	clone :: proc(sm: ^e.StateMachineNode, s: string) -> string {return strings.clone(s, sm.allocator)}

	if UI_BeginProps("##statemachine") {
		// The AnimationPlayer: automatic (sibling / child) or a picked node.
		UI_PropLabel("Player")
		preview := "None found"
		if sm.player == "" && player != nil do preview = fmt.tprintf("Auto (%s)", player.name)
		else if sm.player != "" do preview = player.name if player != nil else fmt.tprintf("missing: %s", sm.player)
		imgui.SetNextItemWidth(field_width())
		if imgui.BeginCombo("##smplayer", strings.clone_to_cstring(preview, context.temp_allocator)) {
			if imgui.Selectable("Auto", sm.player == "") {
				Editor_RecordUndo(state, "State machine player")
				sm.player = ""
				sm.playerNode = nil
			}
			Drive_Item("pick:Auto")
			for n in mgr.nodes {
				if n == nil || n.typeId != e.AnimationPlayerNode || n.transient do continue
				if imgui.Selectable(fmt.ctprintf("%s  %s##%p", ICON_FA_FILM, n.name, n), n == player && sm.player != "") {
					Editor_RecordUndo(state, "State machine player")
					sm.player = clone(sm, e.Node_RelativePath(mgr, sm, n))
					sm.playerNode = nil
				}
				Drive_Item(fmt.tprintf("pick:%s", n.name))
			}
			imgui.EndCombo()
		}
		Drive_Item("insp.sm.player")
		UI_Tooltip("The AnimationPlayer whose animations the states play (Auto: a sibling, else a child)")

		UI_PropLabel("Initial State")
		imgui.SetNextItemWidth(field_width())
		if v, ok := state_combo("insp.sm.initial", sm, sm.initial, false); ok {
			Editor_RecordUndo(state, "Initial state")
			sm.initial = v
		}
		UI_PropLabel("Autostart")
		imgui.Checkbox("##smautostart", &sm.autostart)
		undo_on_activate(state, "Toggle autostart")
		Drive_Item("insp.sm.autostart")
		UI_Tooltip("Enter the initial state when the game starts (else call machine:sm_start())")
		if sm.running {
			UI_PropLabel("Current")
			imgui.TextColored(UI_ACCENT, fmt.ctprintf("%s  (%.1fs)", e.StateMachine_CurrentName(sm), sm.timeInState))
		}
		UI_EndProps()
	}

	// --- States -------------------------------------------------------------
	imgui.SeparatorText("States")
	animNames := make([dynamic]string, context.temp_allocator)
	append(&animNames, "(none)")
	if player != nil do for a in player.animations do if a != nil do append(&animNames, a.name)
	avail := imgui.GetContentRegionAvail().x
	removeState := -1
	for &s, i in sm.states {
		imgui.PushIDInt(i32(i))
		isCurrent := sm.running && sm.current == i
		if isCurrent do imgui.TextColored(UI_ACCENT, ICON_FA_PLAY)
		else if s.name == sm.initial do imgui.TextDisabled(ICON_FA_FLAG)
		else do imgui.TextDisabled(" ")
		if s.name == sm.initial do UI_Tooltip("Initial state")
		imgui.SameLine()
		if v, ok := name_field(state, fmt.tprintf("insp.sm.state-name:%d", i), s.name, avail * 0.42); ok {
			if e.StateMachine_FindState(sm, v) >= 0 {
				Editor_Log(state, .Warn, "A state named %s already exists", v)
			} else {
				Editor_RecordUndo(state, "Rename state")
				e.StateMachine_RenameState(sm, i, v)
			}
		}
		imgui.SameLine()
		cur := 0
		for n, k in animNames do if k > 0 && n == s.animation do cur = k
		if s.animation != "" && cur == 0 {
			append(&animNames, s.animation) // not on the player (yet)
			cur = len(animNames) - 1
		}
		imgui.SetNextItemWidth(avail * 0.42)
		if k, changed := UI_Combo(fmt.tprintf("insp.sm.state-anim:%d", i), cur, animNames[:]); changed {
			Editor_RecordUndo(state, "State animation")
			s.animation = clone(sm, animNames[k]) if k > 0 else ""
		}
		UI_Tooltip("Animation played on entering the state")
		imgui.SameLine()
		if UI_IconButton(ICON_FA_TRASH, fmt.tprintf("insp.sm.state-del:%d", i), "Remove the state and its transitions", size = 24) do removeState = i
		imgui.PopID()
	}
	if removeState >= 0 {
		Editor_RecordUndo(state, "Remove state")
		e.StateMachine_RemoveState(sm, removeState)
	}
	if len(sm.states) == 0 do UI_DimText("No states yet")
	if UI_Button(fmt.tprintf("%s  Add State", ICON_FA_PLUS), "insp.sm.add-state") {
		Editor_RecordUndo(state, "Add state")
		name := "state"
		for k := 2; e.StateMachine_FindState(sm, name) >= 0; k += 1 do name = fmt.tprintf("state_%d", k)
		e.StateMachine_AddState(sm, name)
	}
	if player != nil && len(player.animations) > 0 {
		imgui.SameLine()
		if UI_Button(fmt.tprintf("%s  From Animations", ICON_FA_FILM), "insp.sm.from-anims") {
			Editor_RecordUndo(state, "States from animations")
			for a in player.animations do if a != nil && e.StateMachine_FindState(sm, a.name) < 0 do e.StateMachine_AddState(sm, a.name, a.name)
		}
		UI_Tooltip(fmt.tprintf("A state for each animation of %s", player.name))
	}

	// --- Parameters ---------------------------------------------------------
	imgui.SeparatorText("Parameters")
	removeParam := -1
	for &p, i in sm.params {
		imgui.PushIDInt(i32(i))
		if v, ok := name_field(state, fmt.tprintf("insp.sm.param-name:%d", i), p.name, avail * 0.5); ok {
			Editor_RecordUndo(state, "Rename parameter")
			old := p.name
			p.name = clone(sm, v)
			for &t in sm.transitions do for &c in t.conditions do if c.param == old do c.param = p.name
		}
		imgui.SameLine()
		imgui.SetNextItemWidth(avail * 0.34)
		imgui.DragFloat("##pv", &p.value, 0.1, 0, 0, "%.3g")
		undo_on_activate(state, "Edit parameter")
		Drive_Item(fmt.tprintf("insp.sm.param-value:%d", i))
		UI_Tooltip("Starting value (booleans: 0 / 1). Scripts: machine:sm_set(name, value)")
		imgui.SameLine()
		if UI_IconButton(ICON_FA_TRASH, fmt.tprintf("insp.sm.param-del:%d", i), "Remove parameter", size = 24) do removeParam = i
		imgui.PopID()
	}
	if removeParam >= 0 {
		Editor_RecordUndo(state, "Remove parameter")
		ordered_remove(&sm.params, removeParam)
	}
	if UI_Button(fmt.tprintf("%s  Add Parameter", ICON_FA_PLUS), "insp.sm.add-param") {
		Editor_RecordUndo(state, "Add parameter")
		name := "param"
		for k := 2; ; k += 1 {
			found := false
			for p in sm.params do if p.name == name do found = true
			if !found do break
			name = fmt.tprintf("param_%d", k)
		}
		e.StateMachine_EnsureParam(sm, name)
	}

	// --- Transitions --------------------------------------------------------
	imgui.SeparatorText("Transitions")
	paramNames := make([dynamic]string, context.temp_allocator)
	for p in sm.params do append(&paramNames, p.name)
	removeTr := -1
	for &t, i in sm.transitions {
		imgui.PushIDInt(i32(i))
		from := "Any state" if t.from == e.SM_ANY else t.from
		label := fmt.ctprintf("%s  %s  %s##tr", from, ICON_FA_ARROW_RIGHT, t.to)
		open := imgui.TreeNodeEx(label, {.DefaultOpen, .SpanAvailWidth})
		Drive_Item(fmt.tprintf("insp.sm.tr:%d", i))
		if len(t.conditions) == 0 do UI_Tooltip("No conditions: fires at once")
		if open {
			w := avail * 0.36
			imgui.SetNextItemWidth(w)
			if v, ok := state_combo(fmt.tprintf("insp.sm.tr-from:%d", i), sm, t.from, true); ok {
				Editor_RecordUndo(state, "Transition from")
				t.from = v
			}
			imgui.SameLine()
			imgui.TextUnformatted(ICON_FA_ARROW_RIGHT)
			imgui.SameLine()
			imgui.SetNextItemWidth(w)
			if v, ok := state_combo(fmt.tprintf("insp.sm.tr-to:%d", i), sm, t.to, false); ok {
				Editor_RecordUndo(state, "Transition to")
				t.to = v
			}
			imgui.SameLine()
			if UI_IconButton(ICON_FA_TRASH, fmt.tprintf("insp.sm.tr-del:%d", i), "Remove transition", size = 24) do removeTr = i
			imgui.SetNextItemWidth(w)
			imgui.DragFloat("##blend", &t.blend, 0.01, 0, 5, "blend %.2fs")
			undo_on_activate(state, "Transition blend")
			Drive_Item(fmt.tprintf("insp.sm.tr-blend:%d", i))
			UI_Tooltip("Crossfade time into the target state's animation")

			removeCond := -1
			for &c, j in t.conditions {
				imgui.PushIDInt(i32(j))
				imgui.TextDisabled(j == 0 ? "when" : "and")
				imgui.SameLine()
				if e.SM_Op_UsesParam(c.op) {
					imgui.SetNextItemWidth(avail * 0.34)
					pi := -1
					for n, k in paramNames do if n == c.param do pi = k
					if k, changed := UI_Combo(fmt.tprintf("insp.sm.cond-param:%d.%d", i, j), pi, paramNames[:]); changed {
						Editor_RecordUndo(state, "Condition parameter")
						c.param = clone(sm, paramNames[k])
					}
					imgui.SameLine()
				}
				opNames := make([]string, len(e.SM_Op), context.temp_allocator)
				for op in e.SM_Op do opNames[int(op)] = OP_LABELS[op]
				imgui.SetNextItemWidth(avail * 0.22)
				if k, changed := UI_Combo(fmt.tprintf("insp.sm.cond-op:%d.%d", i, j), int(c.op), opNames); changed {
					Editor_RecordUndo(state, "Condition")
					c.op = e.SM_Op(k)
					if e.SM_Op_UsesParam(c.op) && c.param == "" && len(paramNames) > 0 do c.param = clone(sm, paramNames[0])
				}
				if e.SM_Op_UsesValue(c.op) {
					imgui.SameLine()
					imgui.SetNextItemWidth(avail * 0.14)
					imgui.DragFloat("##cv", &c.value, 0.1, 0, 0, "%.3g")
					undo_on_activate(state, "Condition value")
					Drive_Item(fmt.tprintf("insp.sm.cond-value:%d.%d", i, j))
				}
				imgui.SameLine()
				if UI_IconButton(ICON_FA_XMARK, fmt.tprintf("insp.sm.cond-del:%d.%d", i, j), "Remove condition", size = 22) do removeCond = j
				imgui.PopID()
			}
			if removeCond >= 0 {
				Editor_RecordUndo(state, "Remove condition")
				ordered_remove(&t.conditions, removeCond)
			}
			if UI_Button(fmt.tprintf("%s  Condition", ICON_FA_PLUS), fmt.tprintf("insp.sm.add-cond:%d", i)) {
				Editor_RecordUndo(state, "Add condition")
				if len(paramNames) > 0 do e.StateMachine_AddCondition(sm, &t, .Is_True, paramNames[0])
				else do e.StateMachine_AddCondition(sm, &t, .Finished)
			}
			imgui.TreePop()
		}
		imgui.PopID()
	}
	if removeTr >= 0 {
		Editor_RecordUndo(state, "Remove transition")
		ordered_remove(&sm.transitions, removeTr)
	}
	if len(sm.transitions) == 0 do UI_DimText("No transitions yet")
	if UI_Button(fmt.tprintf("%s  Add Transition", ICON_FA_PLUS), "insp.sm.add-transition") {
		Editor_RecordUndo(state, "Add transition")
		from := sm.states[0].name if len(sm.states) > 0 else e.SM_ANY
		to := sm.states[1].name if len(sm.states) > 1 else from
		e.StateMachine_AddTransition(sm, from, to)
	}
	UI_DimText("Scripts: on_enter_<state>(previous) / on_exit_<state>(next) on the machine's or its parent's script")
}

