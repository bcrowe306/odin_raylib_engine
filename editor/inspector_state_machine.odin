package editor

import "core:fmt"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Inspector: StateMachineNode - a summary (player, initial state, counts, the
// live state) and "Edit in State Machine Tab". Everything is edited in the
// State Machine bottom tab (state_machine_graph.odin); the editors it shares
// live here: SM_TransitionEditor (from / to, mode, blend, conditions),
// SM_ConditionList, SM_NameField, SM_StateCombo.
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
	.Call      = "script says",
	.Or        = "-- or --",
}

// SM_NameField: an InputText for a string held in the node's arena; returns
// the new text when an edit is committed (Enter or focus lost).
SM_NameField :: proc(state: ^EditorState, id, value: string, width: f32, hint: cstring = "") -> (string, bool) {
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

// SM_StateCombo: pick a state (or Any state); (the pick, changed).
SM_StateCombo :: proc(id: string, sm: ^e.StateMachineNode, cur: string, allowAny: bool) -> (string, bool) {
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
	player := e.StateMachine_Player(sm, state.activeScene.manager)
	if UI_BeginProps("##statemachine") {
		UI_PropLabel("Player")
		switch {
		case player != nil: imgui.TextUnformatted(fmt.ctprintf("%s%s", "Auto: " if sm.player == "" else "", player.name))
		case sm.player != "": imgui.TextColored(UI_WARNING, "%s", fmt.ctprintf("missing: %s", sm.player))
		case: UI_DimText("none (gameplay states only)")
		}
		UI_PropLabel("Initial State")
		imgui.TextUnformatted(fmt.ctprintf("%s", sm.initial if sm.initial != "" else "-"))
		UI_PropLabel("Contents")
		UI_DimText(fmt.tprintf("%d states, %d arrows, %d parameters, %d triggers", len(sm.states), len(sm.transitions), len(sm.params), len(sm.triggers)))
		if sm.running {
			UI_PropLabel("Current")
			imgui.TextColored(UI_ACCENT, "%s", fmt.ctprintf("%s  %s  (%.1fs)", ICON_FA_PLAY, e.StateMachine_CurrentName(sm), sm.timeInState))
		}
		UI_EndProps()
	}
	if UI_Button(fmt.tprintf("%s  Edit in State Machine Tab", ICON_FA_DIAGRAM_PROJECT), "insp.sm.edit", {-1, 0}) do bottomTabRequest = .StateGraph
	UI_Tooltip("States, arrows, parameters, triggers and settings are edited in the State Machine tab of the bottom panel")
}

// SM_TransitionEditor: from / to, mode, blend and the conditions of a
// transition (the graph's side panel); true = remove it.
SM_TransitionEditor :: proc(state: ^EditorState, sm: ^e.StateMachineNode, t: ^e.SM_Transition, i: int, avail: f32, live: u32 = 0, hasLive := false) -> (remove: bool) {
	w := avail * 0.36
	imgui.SetNextItemWidth(w)
	if v, ok := SM_StateCombo(fmt.tprintf("insp.sm.tr-from:%d", i), sm, t.from, true); ok {
		Editor_RecordUndo(state, "Transition from")
		t.from = v
	}
	imgui.SameLine()
	imgui.TextUnformatted(ICON_FA_ARROW_RIGHT)
	imgui.SameLine()
	imgui.SetNextItemWidth(w)
	if v, ok := SM_StateCombo(fmt.tprintf("insp.sm.tr-to:%d", i), sm, t.to, false); ok {
		Editor_RecordUndo(state, "Transition to")
		t.to = v
	}
	imgui.SameLine()
	if UI_IconButton(ICON_FA_TRASH, fmt.tprintf("insp.sm.tr-del:%d", i), "Remove transition", size = 24) do remove = true
	MODES :: [?]string{"Manual", "Automatic"}
	modes := MODES
	imgui.SetNextItemWidth(w)
	if k, changed := UI_Combo(fmt.tprintf("insp.sm.tr-mode:%d", i), int(t.mode), modes[:]); changed {
		Editor_RecordUndo(state, "Transition mode")
		t.mode = e.SM_Mode(k)
	}
	UI_Tooltip("Manual: only a script takes it - sm_transition(\"state\"); its conditions (if any) must hold then.\nAutomatic: the machine takes it by itself when its conditions hold (no conditions: at once).")
	imgui.SameLine()
	imgui.SetNextItemWidth(w)
	imgui.DragFloat("##blend", &t.blend, 0.01, 0, 5, "blend %.2fs")
	undo_on_activate(state, "Transition blend")
	Drive_Item(fmt.tprintf("insp.sm.tr-blend:%d", i))
	UI_Tooltip("Crossfade time into the target state's animation")
	SM_ConditionList(state, sm, &t.conditions, "insp.sm", i, avail, live = live, hasLive = hasLive)
	return
}

// SM_ConditionList edits a list of conditions (an arrow's, a state's leave /
// enter guards): rows "when <param> <op> <value>", "and ...", "-- or --",
// and the + Condition / Or buttons. A trigger condition picks a trigger, the
// others a parameter. Drive ids are "<ids>.cond-op:<key>.<j>",
// "<ids>.add-cond:<key>", ... With hasLive each row starts with a green or
// red mark (bit j of live = condition j holds now).
SM_ConditionList :: proc(state: ^EditorState, sm: ^e.StateMachineNode, conds: ^[dynamic]e.SM_Condition, ids: string, key: int, avail: f32, firstWord: cstring = "when", live: u32 = 0, hasLive := false) {
	clone :: proc(sm: ^e.StateMachineNode, s: string) -> string {return strings.clone(s, sm.allocator)}
	paramNames := make([dynamic]string, context.temp_allocator)
	for p in sm.params do append(&paramNames, p.name)
	triggerNames := make([dynamic]string, context.temp_allocator)
	for t in sm.triggers do append(&triggerNames, t.name)
	i := key
	removeCond := -1
	for &c, j in conds {
		imgui.PushIDInt(i32(j))
		if c.op == .Or {
			// A group separator: the conditions after it are an alternative.
			imgui.TextColored(UI_ACCENT, "or")
			imgui.SameLine()
			UI_DimText("(the next conditions are another way)")
			imgui.SameLine()
			if UI_IconButton(ICON_FA_XMARK, fmt.tprintf("%s.cond-del:%d.%d", ids, i, j), "Remove", size = 22) do removeCond = j
			imgui.PopID()
			continue
		}
		if hasLive {
			holds := j < e.SM_CONDITIONS_MAX && live & (1 << u32(j)) != 0
			imgui.TextColored(UI_SUCCESS if holds else UI_DANGER, ICON_FA_CIRCLE_CHECK if holds else ICON_FA_CIRCLE_XMARK)
			UI_Tooltip("Holds now" if holds else "Doesn't hold now")
			imgui.SameLine()
		}
		first := j == 0 || conds[j - 1].op == .Or
		imgui.TextDisabled(first ? firstWord : "and")
		imgui.SameLine()
		if c.op == .Call {
			// A script method that says yes / no.
			if v, ok := SM_NameField(state, fmt.tprintf("%s.cond-call:%d.%d", ids, i, j), c.param, avail * 0.34, "method_name"); ok {
				Editor_RecordUndo(state, "Condition method")
				c.param = clone(sm, v)
			}
			UI_Tooltip("A method of the machine's script (else its parent's), e.g. function Guard:sees_player() return ... end; holds when it returns true")
			imgui.SameLine()
		} else if e.SM_Op_UsesParam(c.op) {
			names := triggerNames[:] if c.op == .Trigger else paramNames[:]
			imgui.SetNextItemWidth(avail * 0.34)
			pi := -1
			for n, k in names do if n == c.param do pi = k
			if k, changed := UI_Combo(fmt.tprintf("%s.cond-param:%d.%d", ids, i, j), pi, names); changed {
				Editor_RecordUndo(state, "Condition parameter")
				c.param = clone(sm, names[k])
			}
			if c.op == .Trigger && len(names) == 0 do UI_Tooltip("No triggers yet: add one in Parameters & Triggers")
			imgui.SameLine()
		}
		opNames := make([]string, len(e.SM_Op), context.temp_allocator)
		for op in e.SM_Op do opNames[int(op)] = OP_LABELS[op]
		imgui.SetNextItemWidth(avail * 0.22)
		if k, changed := UI_Combo(fmt.tprintf("%s.cond-op:%d.%d", ids, i, j), int(c.op), opNames); changed {
			Editor_RecordUndo(state, "Condition")
			wasTrigger := c.op == .Trigger
			c.op = e.SM_Op(k)
			// Switching between a trigger and a parameter: pick one of the right kind.
			if c.op == .Trigger {
				if e.StateMachine_FindTrigger(sm, c.param) < 0 do c.param = clone(sm, triggerNames[0] if len(triggerNames) > 0 else "")
			} else if e.SM_Op_UsesParam(c.op) && c.op != .Call {
				if wasTrigger || e.StateMachine_FindParam(sm, c.param) < 0 do c.param = clone(sm, paramNames[0] if len(paramNames) > 0 else "")
			}
		}
		if e.SM_Op_UsesValue(c.op) {
			imgui.SameLine()
			imgui.SetNextItemWidth(avail * 0.14)
			imgui.DragFloat("##cv", &c.value, 0.1, 0, 0, "%.3g")
			undo_on_activate(state, "Condition value")
			Drive_Item(fmt.tprintf("%s.cond-value:%d.%d", ids, i, j))
		}
		imgui.SameLine()
		if UI_IconButton(ICON_FA_XMARK, fmt.tprintf("%s.cond-del:%d.%d", ids, i, j), "Remove condition", size = 22) do removeCond = j
		imgui.PopID()
	}
	if removeCond >= 0 {
		Editor_RecordUndo(state, "Remove condition")
		ordered_remove(conds, removeCond)
	}
	imgui.PushIDInt(i32(key))
	defer imgui.PopID()
	if UI_Button(fmt.tprintf("%s  Condition##%s", ICON_FA_PLUS, ids), fmt.tprintf("%s.add-cond:%d", ids, i)) {
		Editor_RecordUndo(state, "Add condition")
		if len(paramNames) > 0 do e.StateMachine_AddConditionTo(sm, conds, .Is_True, paramNames[0])
		else if len(triggerNames) > 0 do e.StateMachine_AddConditionTo(sm, conds, .Trigger, triggerNames[0])
		else do e.StateMachine_AddConditionTo(sm, conds, .Finished)
	}
	if len(conds) > 0 {
		imgui.SameLine()
		if UI_Button(fmt.tprintf("Or##%s", ids), fmt.tprintf("%s.add-or:%d", ids, i)) {
			Editor_RecordUndo(state, "Add or")
			e.StateMachine_AddConditionTo(sm, conds, .Or)
		}
		UI_Tooltip("Start another group of conditions: any group holding is enough")
	}
}
