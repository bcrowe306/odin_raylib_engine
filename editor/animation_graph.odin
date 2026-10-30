package editor

import "core:fmt"
import "core:math"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Graph editor (#180): the timeline's value view - each property track's
// curve (vectors and colours split into components) over the same frames
// and playhead; keys are points (drag: time snapped to frames, Shift: free;
// and value), bezier keys show their in / out handles (drag; Alt breaks the
// pair). Wheel: values up / down, Alt + wheel: value zoom, Frame All (F).
// ============================================================================

@(private = "file")
Graph_Drag_Kind :: enum {
	None,
	Key,
	Out,
	In,
}

@(private = "file")
Graph_Channel :: struct {
	track, comp: int,
	name:        string,
	col:         imgui.Vec4,
}

animGraph: struct {
	lo, hi:  f32, // the values shown (bottom, top)
	framed:  bool,
	hidden:  map[string]bool, // channels left out ("target|property|component")
	drag:    struct {
		kind:       Graph_Drag_Kind,
		track:      int,
		comp:       int,
		time:       f32, // the key's time now
		startMouse: [2]f32,
		startTime:  f32,
		startValue: f32,
	},
	menu:    struct {track: int, time: f32, comp: int},
}

AnimGraph_Shutdown :: proc() {
	for k in animGraph.hidden do delete(k)
	delete(animGraph.hidden)
}

// AnimGraph_FrameAll: fits the values next time the graph draws.
AnimGraph_FrameAll :: proc() {animGraph.framed = false}

@(private = "file")
channel_key :: proc(tr: ^e.Property_Track, comp: int) -> string {
	return fmt.tprintf("%s|%s|%d", tr.target, tr.property, comp)
}

@(private = "file")
XY_NAMES := [2]string{"x", "y"}
@(private = "file")
RGBA_NAMES := [4]string{"r", "g", "b", "a"}
@(private = "file")
COMP_COLS := [4]imgui.Vec4{{0.95, 0.42, 0.42, 1}, {0.45, 0.85, 0.45, 1}, {0.45, 0.62, 1, 1}, {0.75, 0.75, 0.75, 1}}

// graph_channels: the curves the graph can show (stepped tracks don't
// curve), hidden ones included (`shown` = false).
@(private = "file")
graph_channels :: proc(state: ^EditorState, apn: ^e.AnimationPlayerNode, anim: ^e.Animation) -> []Graph_Channel {
	out := make([dynamic]Graph_Channel, context.temp_allocator)
	mgr := state.activeScene.manager if state.activeScene != nil else nil
	for &tr, ti in anim.tracks {
		if tr.kind != .Property do continue
		target: ^e.Node = apn
		if tr.target != "." && tr.target != "" do target = e.Node_ResolvePath(mgr, apn, tr.target) if mgr != nil else nil
		kind := e.Property_Kind.Float
		if target != nil {
			p, ok := e.Track_FindProperty(target, tr.property)
			if !ok || e.Track_IsStepped(p) do continue
			kind = p.kind
		}
		node := "" if tr.target == "." || tr.target == "" else fmt.tprintf("%s.", target.name if target != nil else tr.target)
		#partial switch kind {
		case .Vec2:
			for c in 0 ..< 2 do append(&out, Graph_Channel{ti, c, fmt.tprintf("%s%s.%s", node, tr.property, XY_NAMES[c]), COMP_COLS[c]})
		case .Color:
			for c in 0 ..< 4 do append(&out, Graph_Channel{ti, c, fmt.tprintf("%s%s.%s", node, tr.property, RGBA_NAMES[c]), COMP_COLS[c]})
		case:
			append(&out, Graph_Channel{ti, 0, fmt.tprintf("%s%s", node, tr.property), {1, 0.8, 0.35, 1}})
		}
	}
	return out[:]
}

// AnimGraph_Render draws the graph in [left, right] x [top, top + h]; the
// label column (channels) is [labelX, left). x0 / base / cellW: the
// timeline's frame columns.
AnimGraph_Render :: proc(state: ^EditorState, apn: ^e.AnimationPlayerNode, anim: ^e.Animation, dl: ^imgui.DrawList, labelX, left, right, top, h, x0: f32, base: int, cellW: f32, canInteract: bool) {
	g := &animGraph
	io := imgui.GetIO()
	mouse := [2]f32{io.MousePos.x, io.MousePos.y}
	bottom := top + h
	channels := graph_channels(state, apn, anim)
	m := Graph_Map{apn, anim, x0, cellW, base, g.lo, g.hi, top, h}

	// Frame All: every shown curve (keys, handles, the curve between) fits.
	if !g.framed {
		lo, hi := max(f32), -max(f32)
		for ch in channels {
			if channel_key(&anim.tracks[ch.track], ch.comp) in g.hidden do continue
			tr := &anim.tracks[ch.track]
			if len(tr.keys) == 0 do continue
			last := tr.keys[len(tr.keys) - 1].time
			for s in 0 ..= 64 {
				v, _ := e.Track_Sample(tr, last * f32(s) / 64)
				lo, hi = min(lo, v[ch.comp]), max(hi, v[ch.comp])
			}
			for k in tr.keys {
				lo, hi = min(lo, k.value[ch.comp]), max(hi, k.value[ch.comp])
			}
		}
		if lo > hi do lo, hi = 0, 1
		if hi - lo < 0.001 do lo, hi = lo - 1, hi + 1
		span := hi - lo
		g.lo, g.hi = lo - span * 0.1, hi + span * 0.1
		g.framed = true
		m.lo, m.hi = g.lo, g.hi
	}

	// The canvas and its value grid.
	imgui.DrawList_AddRectFilled(dl, {left, top}, {right, bottom}, col_u32(ui_line(0.03)), 3)
	span := g.hi - g.lo
	step := math.pow(10, math.floor(math.log10(max(span / 4, 0.0001))))
	// (Lines at least 18 px apart: labels don't overlap in a short panel.)
	maxLines := max((h - 2 * PAD) / 18, 1)
	for span / step > maxLines do step *= 2
	imgui.DrawList_PushClipRect(dl, {left, top}, {right, bottom}, true)
	for v := math.ceil(g.lo / step) * step; v <= g.hi; v += step {
		y := vy(m, v)
		imgui.DrawList_AddLine(dl, {left, y}, {right, y}, col_u32(ui_line(0.08 if abs(v) < step * 0.01 else 0.04)))
		imgui.DrawList_AddText(dl, {left + 4, y - 14}, col_u32(UI_TEXT_FAINT), fmt.ctprintf("%g", math.round(v / step) * step))
	}

	// Curves, then keys and handles (the hit one picked for a click).
	hitKind := Graph_Drag_Kind.None
	hitTrack, hitComp := -1, 0
	hitTime: f32
	for ch in channels {
		tr := &anim.tracks[ch.track]
		if channel_key(tr, ch.comp) in g.hidden || len(tr.keys) == 0 do continue
		prev: [2]f32
		for x := left; x <= right; x += 3 {
			v, _ := e.Track_Sample(tr, xt(m, x))
			p := [2]f32{x, vy(m, v[ch.comp])}
			if x > left do imgui.DrawList_AddLine(dl, prev, p, col_u32(ch.col), 1.5)
			prev = p
		}
		for k, i in tr.keys {
			kp := [2]f32{tx(m, k.time), vy(m, k.value[ch.comp])}
			frame := int(math.round(e.Animation_TimeFrame(apn, anim, k.time))) + 1
			// Handles: out (to the next key) on bezier keys, in (from the previous).
			if k.bezier && i + 1 < len(tr.keys) {
				hp := [2]f32{tx(m, k.time + k.outTan[ch.comp].x), vy(m, k.value[ch.comp] + k.outTan[ch.comp].y)}
				imgui.DrawList_AddLine(dl, kp, hp, col_u32(UI_TEXT_DIM), 1)
				imgui.DrawList_AddRectFilled(dl, hp - 3, hp + 3, col_u32(UI_TEXT))
				Drive_ItemRect(fmt.tprintf("anim.graph-out:%s:%d:%d", tr.property, ch.comp, frame), hp - 4, hp + 4)
				if hitKind == .None && dist_sq(mouse, hp) < 36 do hitKind, hitTrack, hitComp, hitTime = .Out, ch.track, ch.comp, k.time
			}
			if i > 0 && tr.keys[i - 1].bezier {
				hp := [2]f32{tx(m, k.time + k.inTan[ch.comp].x), vy(m, k.value[ch.comp] + k.inTan[ch.comp].y)}
				imgui.DrawList_AddLine(dl, kp, hp, col_u32(UI_TEXT_DIM), 1)
				imgui.DrawList_AddRectFilled(dl, hp - 3, hp + 3, col_u32(UI_TEXT))
				Drive_ItemRect(fmt.tprintf("anim.graph-in:%s:%d:%d", tr.property, ch.comp, frame), hp - 4, hp + 4)
				if hitKind == .None && dist_sq(mouse, hp) < 36 do hitKind, hitTrack, hitComp, hitTime = .In, ch.track, ch.comp, k.time
			}
			sel := AnimKeys_IsSelected(ch.track, k.time)
			imgui.DrawList_AddCircleFilled(dl, kp, 4.5, col_u32(UI_TEXT if sel else ch.col))
			if sel do imgui.DrawList_AddCircle(dl, kp, 7, col_u32(UI_TEXT), 0, 1.5)
			Drive_ItemRect(fmt.tprintf("anim.graph-key:%s:%d:%d", tr.property, ch.comp, frame), kp - 5, kp + 5)
			if hitKind == .None && dist_sq(mouse, kp) < 49 do hitKind, hitTrack, hitComp, hitTime = .Key, ch.track, ch.comp, k.time
		}
	}
	imgui.DrawList_PopClipRect(dl)

	// The channels (left, scrolling): click to show / hide one; Frame All.
	imgui.SetCursorScreenPos({labelX + 6, top})
	if imgui.BeginChild("##graph_channels", {left - labelX - 12, h}, {}, {}) {
		imgui.PushStyleVarImVec2(.FramePadding, {4, 1})
		if UI_Button(fmt.tprintf("%s  Frame All", ICON_FA_EXPAND), "anim.graph-frame") do g.framed = false
		imgui.PopStyleVar()
		UI_Tooltip("Fit the values of the shown curves (F)")
		for ch in channels {
			tr := &anim.tracks[ch.track]
			key := channel_key(tr, ch.comp)
			hidden := key in g.hidden
			p := imgui.GetCursorScreenPos()
			cdl := imgui.GetWindowDrawList()
			if imgui.Selectable(fmt.ctprintf("      %s##graph_ch_%s", ch.name, key), false, {}, {0, 16}) {
				if hidden {
					for k in g.hidden do if k == key {
						delete_key(&g.hidden, k)
						delete(k)
						break
					}
				} else {
					g.hidden[strings.clone(key)] = true
				}
				g.framed = false // (fit what's shown)
			}
			Drive_Item(fmt.tprintf("anim.graph-channel:%s:%d", tr.property, ch.comp))
			UI_Tooltip("Hide this curve" if !hidden else "Show this curve")
			imgui.DrawList_AddRectFilled(cdl, {p.x + 4, p.y + 3}, {p.x + 14, p.y + 13}, col_u32(ch.col if !hidden else ui_line(0.15)), 2)
			if hidden do imgui.DrawList_AddLine(cdl, {p.x + 20, p.y + 8}, {p.x + 20 + imgui.CalcTextSize(fmt.ctprintf("%s", ch.name)).x, p.y + 8}, col_u32(UI_TEXT_FAINT))
		}
	}
	imgui.EndChild()
	if len(channels) == 0 {
		imgui.DrawList_AddText(dl, {left + 12, top + 12}, col_u32(UI_TEXT_DIM), "No curves: key a number, vector or colour property (Add Track, or the Inspector's diamonds).")
	}

	// Mouse: the wheel moves / zooms the values; press picks a key or handle.
	inCanvas := canInteract && mouse.x >= left && mouse.x <= right && mouse.y >= top && mouse.y <= bottom
	if inCanvas && io.MouseWheel != 0 && !(io.KeySuper || io.KeyCtrl) {
		if io.KeyAlt {
			at := yv(m, mouse.y)
			f: f32 = 1 / 1.2 if io.MouseWheel > 0 else 1.2
			g.lo, g.hi = at + (g.lo - at) * f, at + (g.hi - at) * f
		} else {
			d := (g.hi - g.lo) * 0.1 * io.MouseWheel
			g.lo, g.hi = g.lo + d, g.hi + d
		}
	}
	if animTimelineFocused && !io.WantTextInput && imgui.IsKeyPressed(.F) do g.framed = false
	if inCanvas && hitKind != .None && imgui.IsMouseClicked(.Left) {
		tr := &anim.tracks[hitTrack]
		i := e.Track_KeyAt(tr, hitTime)
		Editor_RecordUndo(state, "Edit curve")
		if hitKind == .Key {
			AnimKeys_Click(hitTrack, hitTime, mouse.x)
			animKeys.pressed = false // (the graph drags it, in time and value)
			AnimationPanel_ScrubTo(state, apn, anim, hitTime)
		}
		g.drag = {hitKind, hitTrack, hitComp, hitTime, mouse, hitTime, tr.keys[i].value[hitComp] if i >= 0 else 0}
	} else if inCanvas && hitKind == .None && imgui.IsMouseClicked(.Left) && !(io.KeyShift || io.KeySuper || io.KeyCtrl) {
		clear(&animKeys.sel)
	}
	if inCanvas && hitKind == .Key && imgui.IsMouseClicked(.Right) {
		g.menu = {hitTrack, hitTime, hitComp}
		imgui.OpenPopup("##graph_key_ctx")
	}
	if g.drag.kind != .None {
		if !imgui.IsMouseDown(.Left) || g.drag.track >= len(anim.tracks) {
			g.drag.kind = .None
		} else {
			graph_drag(state, apn, anim, m, mouse)
			imgui.SetMouseCursor(.ResizeAll)
		}
	}
	graph_key_menu(state, apn, anim)
}

// Graph_Map: time <-> x (the timeline's columns), value <-> y.
@(private = "file")
Graph_Map :: struct {
	apn:          ^e.AnimationPlayerNode,
	anim:         ^e.Animation,
	x0, cellW:    f32,
	base:         int,
	lo, hi, top, h: f32,
}

@(private = "file")
PAD :: f32(14)

@(private = "file")
tx :: proc(m: Graph_Map, t: f32) -> f32 {return m.x0 + (f32(m.base) + e.Animation_TimeFrame(m.apn, m.anim, t)) * m.cellW + m.cellW * 0.5}
@(private = "file")
xt :: proc(m: Graph_Map, x: f32) -> f32 {return e.Animation_FrameTime(m.apn, m.anim, max((x - m.x0 - m.cellW * 0.5) / m.cellW - f32(m.base), 0))}
@(private = "file")
vy :: proc(m: Graph_Map, v: f32) -> f32 {return m.top + PAD + (m.hi - v) / max(m.hi - m.lo, 0.0001) * (m.h - 2 * PAD)}
@(private = "file")
yv :: proc(m: Graph_Map, y: f32) -> f32 {return m.hi - (y - m.top - PAD) / max(m.h - 2 * PAD, 1) * (m.hi - m.lo)}

@(private = "file")
dist_sq :: proc(a, b: [2]f32) -> f32 {d := a - b; return d.x * d.x + d.y * d.y}

// graph_drag: a key (time between its neighbours, snapped to frames unless
// Shift; value) or a handle (Alt: without its pair) follows the mouse.
@(private = "file")
graph_drag :: proc(state: ^EditorState, apn: ^e.AnimationPlayerNode, anim: ^e.Animation, m: Graph_Map, mouse: [2]f32) {
	d := &animGraph.drag
	tr := &anim.tracks[d.track]
	i := e.Track_KeyAt(tr, d.time)
	if i < 0 {
		d.kind = .None
		return
	}
	k := &tr.keys[i]
	c := d.comp
	io := imgui.GetIO()
	vscale := (m.hi - m.lo) / max(m.h - 2 * PAD, 1)
	switch d.kind {
	case .None:
	case .Key:
		col := e.Animation_TimeFrame(apn, anim, d.startTime) + (mouse.x - d.startMouse.x) / m.cellW
		if !io.KeyShift do col = math.round(col)
		t := e.Animation_FrameTime(apn, anim, max(col, 0))
		lo := tr.keys[i - 1].time + e.TRACK_KEY_EPS * 2 if i > 0 else 0
		hi := tr.keys[i + 1].time - e.TRACK_KEY_EPS * 2 if i + 1 < len(tr.keys) else max(f32)
		t = clamp(t, lo, hi)
		k.value[c] = d.startValue - (mouse.y - d.startMouse.y) * vscale
		if abs(t - k.time) > e.TRACK_KEY_EPS {
			for &r in animKeys.sel do if r.track == d.track && abs(r.time - k.time) < e.TRACK_KEY_EPS do r.time = t
			k.time = t
			d.time = t
		}
	case .Out, .In:
		ht, hv := xt(m, mouse.x), yv(m, mouse.y)
		dt, dv := ht - k.time, hv - k.value[c]
		if d.kind == .Out do dt = max(dt, 0.0001)
		else do dt = min(dt, -0.0001)
		if d.kind == .Out do k.outTan[c] = {dt, dv}
		else do k.inTan[c] = {dt, dv}
		// The pair stays in line (smooth) unless Alt breaks it.
		hasIn := i > 0 && tr.keys[i - 1].bezier
		hasOut := k.bezier && i + 1 < len(tr.keys)
		if !io.KeyAlt {
			if d.kind == .Out && hasIn {
				l := abs(k.inTan[c].x)
				k.inTan[c] = {-l, -dv * l / abs(dt)}
			} else if d.kind == .In && hasOut {
				l := abs(k.outTan[c].x)
				k.outTan[c] = {l, -dv * l / abs(dt)}
			}
		}
	}
	AnimationPanel_Rescrub(state, apn, anim)
}

// graph_key_menu: right-click a key - bezier handles, flat handles, linear,
// delete.
@(private = "file")
graph_key_menu :: proc(state: ^EditorState, apn: ^e.AnimationPlayerNode, anim: ^e.Animation) {
	if !imgui.BeginPopup("##graph_key_ctx") do return
	defer imgui.EndPopup()
	mn := animGraph.menu
	if mn.track < 0 || mn.track >= len(anim.tracks) do return
	tr := &anim.tracks[mn.track]
	i := e.Track_KeyAt(tr, mn.time)
	if i < 0 do return
	k := &tr.keys[i]
	changed := false
	defer if changed do AnimationPanel_Rescrub(state, apn, anim)
	UI_DimText(fmt.tprintf("Key at %.2fs", k.time))
	imgui.Separator()
	if imgui.MenuItem(fmt.ctprintf("%s  Bezier Handles", ICON_FA_BEZIER_CURVE), nil, k.bezier, i + 1 < len(tr.keys)) {
		Editor_RecordUndo(state, "Key easing")
		if !k.bezier do e.Track_SetSegmentCurve(tr, i, curve_from_ease(k.ease))
		changed = true
	}
	Drive_Item("anim.graph-bezier")
	if imgui.MenuItem("Flatten Handles (ease in and out here)") {
		Editor_RecordUndo(state, "Flatten handles")
		for c in 0 ..< 4 {
			k.outTan[c].y = 0
			k.inTan[c].y = 0
		}
		changed = true
	}
	Drive_Item("anim.graph-flat")
	if imgui.MenuItem("Linear") {
		Editor_RecordUndo(state, "Key easing")
		k.bezier = false
		k.ease = .Linear
		changed = true
	}
	Drive_Item("anim.graph-linear")
	if imgui.MenuItem(fmt.ctprintf("%s  Delete Key", ICON_FA_TRASH)) {
		Editor_RecordUndo(state, "Delete key")
		e.Track_RemoveKey(tr, mn.time)
		clear(&animKeys.sel)
		changed = true
	}
	Drive_Item("anim.graph-delete")
}
