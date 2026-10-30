package editor

import "core:c"
import "core:fmt"
import "core:path/filepath"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Event tracks (#181): what each key does, said on the timeline (labels);
// one editor for a particles / spawn / enable key (the key's menu, the key
// inspector, the track's side panel); the side panel: the target (particle
// tracks: the scene's emitters only) and every key.
// ============================================================================

// Anim_EventKeyLabel: a key's action in a few words.
Anim_EventKeyLabel :: proc(tr: ^e.Property_Track, k: e.Track_Key) -> string {
	#partial switch tr.kind {
	case .Method:
		return fmt.tprintf("%s(%s)", k.text, k.arg)
	case .Audio:
		return filepath.stem(k.text) if k.text != "" else "(no sound)"
	case .EmitParticles:
		action, count := e.Particle_KeyAction(k.text)
		switch action {
		case .Restart: return "restart"
		case .Emit:    return fmt.tprintf("emit %d", count)
		case .Start:   return "start"
		case .Stop:    return "stop"
		}
	case .InstantiateComponent:
		if k.text == "" do return "(no component)"
		name := filepath.base(k.text)
		return fmt.tprintf("spawn %s", strings.trim_suffix(name, ".component.json"))
	case .SetEnabled:
		return "enable" if anim_key_enabled(k) else "disable"
	}
	return ""
}

anim_key_enabled :: proc(k: e.Track_Key) -> bool {
	return k.text != "disable" && k.text != "false" && k.text != "off" && k.text != "0"
}

// Anim_EventKeyEditor edits a particles / spawn / enable key; true when it
// changed.
Anim_EventKeyEditor :: proc(state: ^EditorState, apn: ^e.AnimationPlayerNode, tr: ^e.Property_Track, key: ^e.Track_Key, id := "") -> bool {
	changed := false
	#partial switch tr.kind {
	case .EmitParticles:
		action, count := e.Particle_KeyAction(key.text)
		imgui.SetNextItemWidth(130)
		if idx, ok := UI_Combo(fmt.tprintf("anim.event-particles%s", id), int(action), []string{"Restart", "Emit a burst", "Start", "Stop"}); ok {
			Editor_RecordUndo(state, "Event key")
			key.text = strings.clone(e.Particle_KeyText(e.Particle_Key_Action(idx), count if count > 0 else 10), apn.allocator)
			changed = true
		}
		UI_Tooltip("Restart: start over; Emit: a burst of N (not emitting after); Start / Stop emitting")
		if action == .Emit {
			imgui.SameLine()
			n := c.int(count)
			imgui.SetNextItemWidth(56)
			if imgui.InputInt(fmt.ctprintf("##part_count%s", id), &n, 0, 0) { // (no step buttons: room for the number)
				key.text = strings.clone(e.Particle_KeyText(.Emit, max(int(n), 1)), apn.allocator)
				changed = true
			}
			if imgui.IsItemActivated() do Editor_RecordUndo(state, "Event key")
			Drive_Item(fmt.tprintf("anim.event-particles-count%s", id))
		}
	case .InstantiateComponent:
		imgui.SetNextItemWidth(-1)
		if path, ok := asset_picker(fmt.tprintf("anim.event-spawn%s", id), key.text, Editor_ListProjectFiles(state, "", {".component.json"}), allowNone = false); ok {
			Editor_RecordUndo(state, "Event key")
			key.text = strings.clone(path, apn.allocator)
			changed = true
		}
		Drive_Item(fmt.tprintf("anim.event-spawn%s", id))
	case .SetEnabled:
		on := anim_key_enabled(key^)
		if imgui.Checkbox(fmt.ctprintf("Enabled at this key##en%s", id), &on) {
			Editor_RecordUndo(state, "Event key")
			key.text = strings.clone("enable" if on else "disable", apn.allocator)
			changed = true
		}
		Drive_Item(fmt.tprintf("anim.event-enabled%s", id))
	}
	return changed
}

// Anim_SceneEmitters: the scene's particle emitters (what a particles track
// can target).
Anim_SceneEmitters :: proc(state: ^EditorState) -> []^e.Node {
	out := make([dynamic]^e.Node, context.temp_allocator)
	if state.activeScene == nil do return nil
	for n in state.activeScene.manager.nodes do if n != nil && n.typeId == e.ParticleEmitterNode do append(&out, n)
	return out[:]
}

// anim_event_settings_panel: a particles / spawn / enable track - its target
// and each key (frame, what it does; click a frame to go there).
anim_event_settings_panel :: proc(state: ^EditorState, apn: ^e.AnimationPlayerNode, anim: ^e.Animation, tr: ^e.Property_Track, size: [2]f32) {
	imgui.SameLine(0, UI_SPACE)
	imgui.PushStyleColorImVec4(.ChildBg, UI_BG_APP)
	defer imgui.PopStyleColor()
	if !imgui.BeginChild("##anim_event_settings", size, {}, {}) {
		imgui.EndChild()
		return
	}
	defer imgui.EndChild()
	icon, title := ICON_FA_WAND_MAGIC_SPARKLES, "Particles Track"
	#partial switch tr.kind {
	case .InstantiateComponent: icon, title = ICON_FA_CUBES, "Spawn Track"
	case .SetEnabled:           icon, title = ICON_FA_TOGGLE_ON, "Enable / Disable Track"
	}
	imgui.TextUnformatted(fmt.ctprintf("%s  %s", icon, title))
	imgui.SameLine(max(imgui.GetWindowWidth() - 28, 120))
	if UI_IconButton(ICON_FA_XMARK, "anim.event-close", "Close the track settings", size = 20) {
		AnimationPanel_SelectTrack(-1)
		return
	}
	imgui.Separator()

	// The target: a particles track picks among the scene's emitters.
	mgr := state.activeScene.manager
	target: ^e.Node = apn
	if tr.target != "." && tr.target != "" do target = e.Node_ResolvePath(mgr, apn, tr.target)
	UI_DimText("EMITTER" if tr.kind == .EmitParticles else "TARGET NODE")
	choices := Anim_SceneEmitters(state) if tr.kind == .EmitParticles else mgr.nodes[:]
	imgui.SetNextItemWidth(-1)
	preview := target.name if target != nil else "(not found)"
	if tr.kind == .EmitParticles && target != nil && target.typeId != e.ParticleEmitterNode do preview = fmt.tprintf("%s (not an emitter)", target.name)
	if imgui.BeginCombo("##event_target", strings.clone_to_cstring(preview, context.temp_allocator)) {
		for n in choices {
			if n == nil do continue
			if imgui.Selectable(fmt.ctprintf("%s##%p", n.name, n), n == target) {
				Editor_RecordUndo(state, "Change track target")
				tr.target = strings.clone(e.Node_RelativePath(mgr, apn, n), apn.allocator)
			}
			Drive_Item(fmt.tprintf("pick:%s", n.name))
		}
		if len(choices) == 0 do UI_DimText("No particle emitters in the scene: add one (Animation & Effects).")
		imgui.EndCombo()
	}
	Drive_Item("anim.event-target")

	// The keys.
	imgui.Dummy({0, 4})
	UI_DimText("KEYS")
	removeAt := f32(-1)
	for &k, i in tr.keys {
		imgui.PushIDInt(c.int(i))
		frame := int(e.Animation_TimeFrame(apn, anim, k.time) + 0.5) + 1
		if UI_Button(fmt.tprintf("F%d", frame), fmt.tprintf("anim.event-key-frame:%d", frame), {44, 0}) do AnimationPanel_ScrubTo(state, apn, anim, k.time)
		UI_Tooltip(fmt.tprintf("%.2fs: go there", k.time))
		imgui.SameLine()
		Anim_EventKeyEditor(state, apn, tr, &k, fmt.tprintf(":%d", frame))
		imgui.SameLine()
		if UI_IconButton(ICON_FA_TRASH, fmt.tprintf("anim.event-key-delete:%d", frame), "Delete this key", size = 20) do removeAt = k.time
		imgui.PopID()
	}
	if removeAt >= 0 {
		Editor_RecordUndo(state, "Delete key")
		e.Track_RemoveKey(tr, removeAt)
		clear(&animKeys.sel)
	}
	if len(tr.keys) == 0 do UI_DimText("No keys yet: the dot on the track's row adds one at the playhead.")
}
