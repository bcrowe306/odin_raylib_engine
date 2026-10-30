package editor

import "core:c"
import "core:fmt"
import "core:math"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Key inspector (#178): right of the timeline while keys are selected - their
// time (frame and seconds), value (the property's own widget), easing to the
// next key and bezier handles. Several selected keys edit together: a time
// change moves them all, a value or easing goes to each.
// ============================================================================

@(private = "file")
Sel_Key :: struct {
	track, index: int,
}

// key_components: the components a property's value uses (handles per each).
@(private = "file")
KEY_LABELS := [4]string{"x", "y", "z", "w"}
@(private = "file")
COLOR_LABELS := [4]string{"r", "g", "b", "a"}

@(private = "file")
key_components :: proc(kind: e.Property_Kind) -> (n: int, labels: []string) {
	#partial switch kind {
	case .Vec2:  return 2, KEY_LABELS[:2]
	case .Color: return 4, COLOR_LABELS[:]
	}
	return 1, {}
}

// AnimKeys_InspectorPanel draws the inspector for the selected keys.
AnimKeys_InspectorPanel :: proc(state: ^EditorState, apn: ^e.AnimationPlayerNode, anim: ^e.Animation, size: [2]f32) {
	imgui.SameLine(0, UI_SPACE)
	imgui.PushStyleColorImVec4(.ChildBg, UI_BG_APP)
	defer imgui.PopStyleColor()
	if !imgui.BeginChild("##anim_key_inspector", size, {}, {}) {
		imgui.EndChild()
		return
	}
	defer imgui.EndChild()

	keys := make([dynamic]Sel_Key, context.temp_allocator)
	earliest := max(f32)
	for r in animKeys.sel {
		if r.track < 0 || r.track >= len(anim.tracks) do continue
		if i := e.Track_KeyAt(&anim.tracks[r.track], r.time); i >= 0 {
			append(&keys, Sel_Key{r.track, i})
			earliest = min(earliest, r.time)
		}
	}
	imgui.TextUnformatted(fmt.ctprintf("%s  %s", ICON_FA_CIRCLE, "Key" if len(keys) == 1 else fmt.tprintf("%d Keys", len(keys))))
	imgui.SameLine(max(imgui.GetWindowWidth() - 28, 120))
	if UI_IconButton(ICON_FA_XMARK, "anim.keyinsp.close", "Deselect the keys", size = 20) {
		clear(&animKeys.sel)
		return
	}
	imgui.Separator()
	if len(keys) == 0 {
		UI_DimText("Select keys in the timeline to edit them here.")
		return
	}
	first := keys[0]
	tr0 := &anim.tracks[first.track]
	oneTrack := true
	for k in keys do if k.track != first.track do oneTrack = false
	mgr := state.activeScene.manager if state.activeScene != nil else nil
	resolve :: proc(mgr: ^e.NodeManager, apn: ^e.AnimationPlayerNode, tr: ^e.Property_Track) -> ^e.Node {
		if tr.target == "." || tr.target == "" do return apn
		return e.Node_ResolvePath(mgr, apn, tr.target) if mgr != nil else nil
	}
	if oneTrack {
		node := resolve(mgr, apn, tr0)
		UI_DimText(fmt.tprintf("%s.%s", node.name if node != nil else tr0.target, tr0.property))
	} else {
		UI_DimText("On several tracks")
	}
	imgui.Dummy({0, 4})

	// --- time: the first key's frame / seconds; the others keep their spacing ---
	labelW :: f32(70)
	row_label :: proc(text: string) {
		imgui.AlignTextToFramePadding()
		UI_DimText(text)
		imgui.SameLine(labelW)
	}
	moveTo := earliest
	row_label("Frame")
	frame := c.int(math.round(e.Animation_TimeFrame(apn, anim, earliest))) + 1
	imgui.SetNextItemWidth(-1)
	if imgui.DragInt("##keyinsp_frame", &frame, 0.1, 1, 100000) do moveTo = e.Animation_FrameTime(apn, anim, f32(max(frame, 1) - 1))
	undo_on_activate(state, "Move keys")
	Drive_Item("anim.keyinsp.frame")
	UI_Tooltip("The (first) key's frame: the selected keys move together")
	row_label("Time")
	t := earliest
	imgui.SetNextItemWidth(-1)
	if imgui.DragFloat("##keyinsp_time", &t, 0.005, 0, 3600, "%.3f s") do moveTo = max(t, 0)
	undo_on_activate(state, "Move keys")
	Drive_Item("anim.keyinsp.time")
	UI_Tooltip("The (first) key's time in seconds (free: not snapped to a frame)")
	if abs(moveTo - earliest) > e.TRACK_KEY_EPS {
		d := moveTo - earliest
		for ti in 0 ..< len(anim.tracks) {
			times := make([dynamic]f32, context.temp_allocator)
			for r in animKeys.sel do if r.track == ti do append(&times, r.time)
			if len(times) > 0 do e.Track_MoveKeys(&anim.tracks[ti], times[:], d)
		}
		for &r in animKeys.sel do r.time += d
		AnimationPanel_Rescrub(state, apn, anim)
		return // (the keys moved: next frame shows them)
	}

	// --- value: the property's own widget (keys of one kind of property) ---
	allProps := true
	for k in keys do if anim.tracks[k.track].kind != .Property do allProps = false
	if !allProps {
		imgui.Dummy({0, 4})
		#partial switch tr0.kind {
		case .EmitParticles, .InstantiateComponent, .SetEnabled:
			if len(keys) == 1 {
				row_label("Does")
				Anim_EventKeyEditor(state, apn, tr0, &tr0.keys[first.index], ":insp")
				return
			}
		}
		UI_DimText("Event keys: right-click one in the timeline (or its track's settings) for its action.")
		return
	}
	node := resolve(mgr, apn, tr0)
	prop: e.Node_Property
	sameKind := false
	if node != nil do prop, sameKind = e.Track_FindProperty(node, tr0.property)
	for k in keys {
		n := resolve(mgr, apn, &anim.tracks[k.track])
		if n == nil {
			sameKind = false
			continue
		}
		p, ok := e.Track_FindProperty(n, anim.tracks[k.track].property)
		if !ok || p.kind != prop.kind do sameKind = false
	}
	key0 := &tr0.keys[first.index]
	changed := false
	if !sameKind {
		UI_DimText("Values: select keys of one kind of property.")
	} else {
		row_label("Value")
		v := key0.value
		text := key0.text
		vchanged := false
		imgui.SetNextItemWidth(-1)
		#partial switch prop.kind {
		case .Float:
			vchanged = imgui.DragFloat("##keyinsp_value", &v[0], 0.1)
		case .Int:
			n := c.int(math.round(v[0]))
			if imgui.DragInt("##keyinsp_value", &n, 0.1) {
				v[0] = f32(n)
				vchanged = true
			}
		case .Vec2:
			xy := [2]f32{v[0], v[1]}
			if imgui.DragFloat2("##keyinsp_value", &xy, 0.5) {
				v[0], v[1] = xy.x, xy.y
				vchanged = true
			}
		case .Color:
			col := [4]f32{v[0], v[1], v[2], v[3]} / 255
			if imgui.ColorEdit4("##keyinsp_value", &col, {.AlphaBar}) {
				v = col * 255
				vchanged = true
			}
		case .Bool:
			on := v[0] >= 0.5
			if imgui.Checkbox("##keyinsp_value", &on) {
				v[0] = 1 if on else 0
				vchanged = true
			}
		case .Enum:
			if idx, ok := UI_Combo("anim.keyinsp.enum", int(math.round(v[0])), e.Property_EnumNames(prop)); ok {
				v[0] = f32(idx)
				vchanged = true
			}
		case .String:
			if tr0.property == "texture" {
				if path, ok := asset_picker("anim.keyinsp.texture", text, Editor_ListProjectFiles(state, "", TEXTURE_EXTS), allowNone = false); ok {
					text = path
					vchanged = true
				}
			} else {
				buf: [256]u8
				copy(buf[:len(buf) - 1], text)
				if imgui.InputText("##keyinsp_value", cstring(raw_data(buf[:])), len(buf)) {
					text = string(cstring(raw_data(buf[:])))
					vchanged = true
				}
			}
		}
		if prop.kind == .Enum || (prop.kind == .String && tr0.property == "texture") {
			if vchanged do Editor_RecordUndo(state, "Key value")
		} else {
			undo_on_activate(state, "Key value")
		}
		Drive_Item("anim.keyinsp.value")
		if vchanged {
			for k in keys {
				key := &anim.tracks[k.track].keys[k.index]
				if prop.kind == .String do key.text = strings.clone(text, apn.allocator)
				else do key.value = v
			}
			changed = true
		}
	}

	// --- easing to the next key (stepped properties hold) ---
	if sameKind && e.Track_IsStepped(prop) {
		imgui.Dummy({0, 4})
		UI_DimText("Holds its value until the next key (steps).")
	} else {
		names := make([dynamic]string, context.temp_allocator)
		for ease in e.Ease do append(&names, e.Ease_Name(ease))
		BEZIER :: "bezier" // (handles)
		append(&names, BEZIER)
		row_label("Easing")
		cur := len(names) - 1 if key0.bezier else int(key0.ease)
		imgui.SetNextItemWidth(-1)
		if idx, ok := UI_Combo("anim.keyinsp.ease", cur, names[:]); ok {
			Editor_RecordUndo(state, "Key easing")
			for k in keys {
				tr := &anim.tracks[k.track]
				key := &tr.keys[k.index]
				if idx < len(names) - 1 {
					key.ease = e.Ease(idx)
					key.bezier = false
				} else if !key.bezier {
					e.Track_SetSegmentCurve(tr, k.index, curve_from_ease(key.ease))
				}
			}
			changed = true
		}
		UI_Tooltip("The motion from this key to the next: an easing, or bezier handles (drag them here or in the graph)")

		// --- bezier handles (one key): out to the next key, in from the previous ---
		if len(keys) == 1 && sameKind {
			n, labels := key_components(prop.kind)
			hasNext := first.index + 1 < len(tr0.keys)
			hasPrev := first.index > 0 && tr0.keys[first.index - 1].bezier
			if key0.bezier && hasNext {
				imgui.Dummy({0, 4})
				UI_DimText("Out handle (time s, value)")
				for ci in 0 ..< n {
					row_label(labels[ci] if ci < len(labels) else "value")
					h := key0.outTan[ci]
					imgui.SetNextItemWidth(-1)
					if imgui.DragFloat2(fmt.ctprintf("##keyinsp_out%d", ci), &h, 0.005) {
						key0.outTan[ci] = {max(h.x, 0), h.y}
						changed = true
					}
					undo_on_activate(state, "Key handle")
					Drive_Item(fmt.tprintf("anim.keyinsp.out:%d", ci))
				}
			}
			if hasPrev {
				imgui.Dummy({0, 4})
				UI_DimText("In handle (time s, value)")
				for ci in 0 ..< n {
					row_label(labels[ci] if ci < len(labels) else "value")
					h := key0.inTan[ci]
					imgui.SetNextItemWidth(-1)
					if imgui.DragFloat2(fmt.ctprintf("##keyinsp_in%d", ci), &h, 0.005) {
						key0.inTan[ci] = {min(h.x, 0), h.y}
						changed = true
					}
					undo_on_activate(state, "Key handle")
					Drive_Item(fmt.tprintf("anim.keyinsp.in:%d", ci))
				}
			}
		}
	}
	if changed do AnimationPanel_Rescrub(state, apn, anim)
}
