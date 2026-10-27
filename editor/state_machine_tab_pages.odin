package editor

import "core:fmt"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// State Machine tab pages besides the graph (state_machine_graph.odin):
//
//   Parameters & Triggers  typed parameters (bool / int / float) with their
//                          starting values, triggers with their buffer time;
//                          live values and pending triggers while running
//                          (Fire sets a trigger in Simulate)
//   Settings               the AnimationPlayer, initial state, autostart,
//                          states made from the player's animations
// ============================================================================

// SM_ParamText: a parameter's value as its type shows it.
SM_ParamText :: proc(sm: ^e.StateMachineNode, name: string, value: f32) -> string {
	i := e.StateMachine_FindParam(sm, name)
	type := sm.params[i].type if i >= 0 else e.SM_Param_Type.Float
	switch type {
	case .Bool:  return "true" if value != 0 else "false"
	case .Int:   return fmt.tprintf("%d", i64(value))
	case .Float:
	}
	return fmt.tprintf("%.3g", value)
}

// SM_TriggerLeft: how long a pending trigger still waits ("" = until the
// next update checks it).
SM_TriggerLeft :: proc(sm: ^e.StateMachineNode, t: SMG_LiveTrigger) -> string {
	i := e.StateMachine_FindTrigger(sm, t.name)
	if i < 0 || sm.triggers[i].buffer <= 0 do return "pending"
	return fmt.tprintf("pending, %.2fs left", max(sm.triggers[i].buffer - t.held, 0))
}

// sm_unique_name: base, else base_2, base_3 ... not taken by a parameter or a trigger.
@(private = "file")
sm_unique_name :: proc(sm: ^e.StateMachineNode, base: string) -> string {
	name := base
	for k := 2; e.StateMachine_FindParam(sm, name) >= 0 || e.StateMachine_FindTrigger(sm, name) >= 0; k += 1 do name = fmt.tprintf("%s_%d", base, k)
	return name
}

// sm_name_taken: a parameter / trigger rename that would clash (logged).
@(private = "file")
sm_name_taken :: proc(state: ^EditorState, sm: ^e.StateMachineNode, name: string) -> bool {
	if e.StateMachine_FindParam(sm, name) < 0 && e.StateMachine_FindTrigger(sm, name) < 0 do return false
	Editor_Log(state, .Warn, "%s already has a parameter or trigger named %s", sm.name, name)
	return true
}

StateGraph_ParamsPage :: proc(state: ^EditorState, sm: ^e.StateMachineNode) {
	view := StateGraph_View(state, sm)
	live := view.running
	avail := imgui.GetContentRegionAvail().x
	half := max((avail - 16) * 0.5, 260)
	TABLE :: imgui.TableFlags_SizingStretchProp | imgui.TableFlags_RowBg | imgui.TableFlags_BordersInnerH

	// --- Parameters (left) ---------------------------------------------------
	if imgui.BeginChild("##smg_params_col", {half, 0}, {}, {}) {
		imgui.SeparatorText("Parameters")
		UI_DimTextWrapped("Values the game feeds the machine every frame - sm_set(\"speed\", 4.2) - that arrows compare (speed > 3, on_floor is true).")
		removeParam := -1
		if len(sm.params) > 0 && imgui.BeginTable("##smg_params", 5 if live else 4, TABLE) {
			imgui.TableSetupColumn("Name", {.WidthStretch}, 0.38)
			imgui.TableSetupColumn("Type", {.WidthStretch}, 0.2)
			imgui.TableSetupColumn("Starting value" if !live || view.remote else "Value", {.WidthStretch}, 0.3)
			if live do imgui.TableSetupColumn("Live", {.WidthStretch}, 0.2)
			imgui.TableSetupColumn("", {.WidthFixed}, 26)
			imgui.TableHeadersRow()
			TYPES :: [?]string{"float", "int", "bool"}
			types := TYPES
			for &p, i in sm.params {
				imgui.PushIDInt(i32(i))
				imgui.TableNextRow()
				imgui.TableNextColumn()
				if v, ok := SM_NameField(state, fmt.tprintf("smg.param-name:%d", i), p.name, -1); ok && !sm_name_taken(state, sm, v) {
					Editor_RecordUndo(state, "Rename parameter")
					e.StateMachine_RenameParam(sm, i, v)
				}
				imgui.TableNextColumn()
				imgui.SetNextItemWidth(-1)
				if k, changed := UI_Combo(fmt.tprintf("smg.param-type:%d", i), int(p.type), types[:]); changed {
					Editor_RecordUndo(state, "Parameter type")
					e.StateMachine_SetParamType(&p, e.SM_Param_Type(k))
				}
				imgui.TableNextColumn()
				imgui.SetNextItemWidth(-1)
				switch p.type {
				case .Bool:
					b := p.value != 0
					if imgui.Checkbox("##pv", &b) {
						Editor_RecordUndo(state, "Edit parameter")
						p.value = 1 if b else 0
					}
				case .Int:
					v := i32(p.value)
					if imgui.DragInt("##pv", &v, 0.2) do p.value = f32(v)
					undo_on_activate(state, "Edit parameter")
				case .Float:
					imgui.DragFloat("##pv", &p.value, 0.1, 0, 0, "%.3g")
					undo_on_activate(state, "Edit parameter")
				}
				Drive_Item(fmt.tprintf("smg.param-value:%d", i))
				if live {
					imgui.TableNextColumn()
					for lp in view.params do if lp.name == p.name do imgui.TextColored(UI_ACCENT, "%s", strings.clone_to_cstring(SM_ParamText(sm, p.name, lp.value), context.temp_allocator))
				}
				imgui.TableNextColumn()
				if UI_IconButton(ICON_FA_TRASH, fmt.tprintf("smg.param-del:%d", i), "Remove the parameter (conditions using it stay, unmatched)", size = 22) do removeParam = i
				imgui.PopID()
			}
			imgui.EndTable()
		}
		if removeParam >= 0 {
			Editor_RecordUndo(state, "Remove parameter")
			ordered_remove(&sm.params, removeParam)
		}
		if len(sm.params) == 0 do UI_DimText("No parameters yet.")
		if UI_Button(fmt.tprintf("%s  Add Parameter", ICON_FA_PLUS), "smg.add-param") {
			Editor_RecordUndo(state, "Add parameter")
			e.StateMachine_EnsureParam(sm, sm_unique_name(sm, "param"), 0, .Bool)
		}
		UI_Tooltip("A new parameter is a bool; change its type in the Type column")
		if live && !view.remote do UI_DimTextWrapped("Simulating: edits change the running machine; the scene's values come back when Simulate stops.")
	}
	imgui.EndChild()
	imgui.SameLine()

	// --- Triggers (right) ----------------------------------------------------
	if imgui.BeginChild("##smg_triggers_col", {0, 0}, {}, {}) {
		imgui.SeparatorText("Triggers")
		UI_DimTextWrapped("One-shot events - sm_trigger(\"jump\") - for Automatic arrows. Used up by the arrow they open; else cleared after one update, or after the buffer time (input buffering).")
		removeTrigger := -1
		if len(sm.triggers) > 0 && imgui.BeginTable("##smg_triggers", 4 if live else 3, TABLE) {
			imgui.TableSetupColumn("Name", {.WidthStretch}, 0.42)
			imgui.TableSetupColumn("Buffer", {.WidthStretch}, 0.28)
			if live do imgui.TableSetupColumn("Live", {.WidthStretch}, 0.3)
			imgui.TableSetupColumn("", {.WidthFixed}, 26)
			imgui.TableHeadersRow()
			for &t, i in sm.triggers {
				imgui.PushIDInt(i32(i))
				imgui.TableNextRow()
				imgui.TableNextColumn()
				if v, ok := SM_NameField(state, fmt.tprintf("smg.trigger-name:%d", i), t.name, -1); ok && !sm_name_taken(state, sm, v) {
					Editor_RecordUndo(state, "Rename trigger")
					e.StateMachine_RenameTrigger(sm, i, v)
				}
				imgui.TableNextColumn()
				imgui.SetNextItemWidth(-1)
				imgui.DragFloat("##tb", &t.buffer, 0.01, 0, 5, "%.2f s" if t.buffer > 0 else "none")
				undo_on_activate(state, "Trigger buffer")
				if t.buffer < 0 do t.buffer = 0
				Drive_Item(fmt.tprintf("smg.trigger-buffer:%d", i))
				UI_Tooltip("How long it stays set waiting for an arrow it can open (none: only the next update). E.g. 0.15 s: a jump pressed just before landing still jumps.")
				if live {
					imgui.TableNextColumn()
					pending := false
					for lt in view.triggers do if lt.name == t.name && lt.pending {
						pending = true
						imgui.TextColored(UI_WARNING, "%s", fmt.ctprintf("%s %s", ICON_FA_BOLT, SM_TriggerLeft(sm, lt)))
					}
					if !pending {
						if view.remote {
							UI_DimText("-")
						} else if UI_Button("Fire", fmt.tprintf("smg.trigger-fire:%d", i)) {
							e.StateMachine_FireTrigger(sm, t.name)
						}
					}
				}
				imgui.TableNextColumn()
				if UI_IconButton(ICON_FA_TRASH, fmt.tprintf("smg.trigger-del:%d", i), "Remove the trigger (conditions testing it stay, unmatched)", size = 22) do removeTrigger = i
				imgui.PopID()
			}
			imgui.EndTable()
		}
		if removeTrigger >= 0 {
			Editor_RecordUndo(state, "Remove trigger")
			ordered_remove(&sm.triggers, removeTrigger)
		}
		if len(sm.triggers) == 0 do UI_DimText("No triggers yet.")
		if UI_Button(fmt.tprintf("%s  Add Trigger", ICON_FA_PLUS), "smg.add-trigger") {
			Editor_RecordUndo(state, "Add trigger")
			e.StateMachine_AddTrigger(sm, sm_unique_name(sm, "trigger"))
		}
	}
	imgui.EndChild()
}

StateGraph_SettingsPage :: proc(state: ^EditorState, sm: ^e.StateMachineNode) {
	mgr := state.activeScene.manager
	player := e.StateMachine_Player(sm, mgr)
	clone :: proc(sm: ^e.StateMachineNode, s: string) -> string {return strings.clone(s, sm.allocator)}
	imgui.PushItemWidth(-1)
	defer imgui.PopItemWidth()
	if imgui.BeginChild("##smg_settings_col", {min(imgui.GetContentRegionAvail().x, 520), 0}, {}, {}) {
		if UI_BeginProps("##smg_settings") {
			// The AnimationPlayer: automatic (sibling / child) or a picked node.
			UI_PropLabel("Animation Player")
			preview := "None found"
			if sm.player == "" && player != nil do preview = fmt.tprintf("Auto (%s)", player.name)
			else if sm.player != "" do preview = player.name if player != nil else fmt.tprintf("missing: %s", sm.player)
			imgui.SetNextItemWidth(-1)
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
			Drive_Item("smg.player")
			UI_Tooltip("The AnimationPlayer whose animations the states play (Auto: a sibling, else a child). Not needed for gameplay-only machines.")
			UI_PropLabel("Initial State")
			imgui.SetNextItemWidth(-1)
			if v, ok := SM_StateCombo("smg.initial", sm, sm.initial, false); ok {
				Editor_RecordUndo(state, "Initial state")
				sm.initial = v
			}
			UI_Tooltip("The state it starts in (also: right-click a state > Set as Initial State)")
			UI_PropLabel("Autostart")
			imgui.Checkbox("##smautostart", &sm.autostart)
			undo_on_activate(state, "Toggle autostart")
			Drive_Item("smg.autostart")
			UI_Tooltip("Enter the initial state when the game starts (else call machine:sm_start()). A child machine always waits for its parent's state.")
			UI_EndProps()
		}
		if player != nil && len(player.animations) > 0 {
			imgui.Dummy({0, 4})
			if UI_Button(fmt.tprintf("%s  Add a State per Animation", ICON_FA_FILM), "smg.from-anims") {
				Editor_RecordUndo(state, "States from animations")
				for a in player.animations do if a != nil && e.StateMachine_FindState(sm, a.name) < 0 do e.StateMachine_AddState(sm, a.name, a.name)
			}
			UI_Tooltip(fmt.tprintf("A state playing each animation of %s (those not there yet)", player.name))
		}
	}
	imgui.EndChild()
}
