package editor

import "core:fmt"
import "core:math"
import "core:os"
import "core:path/filepath"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"
import rl "vendor:raylib"

// ============================================================================
// Animation editor depth (engine/docs/animation_editing.md):
//
//   onion skin     the selected AnimationPlayer's neighbouring frames drawn
//                  ghosted in the viewport (before: red, after: blue,
//                  fading with distance) where its own tracks put it
//   custom curves  a key's curve to the next key as a cubic Bezier (drag
//                  the two handles; presets), shown on the timeline row
//   method events  the target script's methods to pick from, and an
//                  argument passed to the method
// ============================================================================

Onion_Settings :: struct {
	on:      bool,
	before:  int,
	after:   int,
	opacity: f32,
}

onion := Onion_Settings{before = 2, after = 1, opacity = 0.25}

// Onion_ToolbarButton: the timeline toolbar's onion skin toggle and its
// settings (right-click / the arrow).
Onion_ToolbarButton :: proc(state: ^EditorState) {
	if UI_IconButton(ICON_FA_CLONE, "anim.onion", "Onion skin: show the frames before (red) and after (blue) in the viewport (right-click: how many)", onion.on, 26) do onion.on = !onion.on
	if imgui.IsItemClicked(.Right) do imgui.OpenPopup("##onion_settings")
	if imgui.BeginPopup("##onion_settings") {
		UI_DimText("Onion skin")
		b, a := i32(onion.before), i32(onion.after)
		imgui.SetNextItemWidth(140)
		if imgui.SliderInt("Before##onion", &b, 0, 5) do onion.before = int(b)
		Drive_Item("anim.onion-before")
		imgui.SetNextItemWidth(140)
		if imgui.SliderInt("After##onion", &a, 0, 5) do onion.after = int(a)
		Drive_Item("anim.onion-after")
		imgui.SetNextItemWidth(140)
		imgui.SliderFloat("Opacity##onion", &onion.opacity, 0.05, 1, "%.2f")
		imgui.EndPopup()
	}
}

// Viewport_DrawOnionSkin draws the selected AnimationPlayer's neighbouring
// frames, ghosted (world space, inside the viewport's camera).
Viewport_DrawOnionSkin :: proc(state: ^EditorState) {
	if !onion.on || state.selectedNode == nil || state.selectedNode.typeId != e.AnimationPlayerNode do return
	apn := cast(^e.AnimationPlayerNode)state.selectedNode
	anim := e.AnimationPlayerNode_GetAnimation(apn)
	if anim == nil do return
	first, last := anim.startFrame, anim.endFrame
	if last < first do return
	cur := apn.currentFrame
	for side in ([]int{-1, 1}) {
		count := onion.before if side < 0 else onion.after
		for d in 1 ..= count {
			f := cur + side * d
			if f < first || f > last {
				if !anim.loop do continue
				n := last - first + 1
				f = first + ((f - first) % n + n) % n
				if f == cur do continue
			}
			alpha := onion.opacity * (1 - f32(d - 1) / f32(count + 1))
			tint := rl.Color{255, 90, 90, u8(alpha * 255)} if side < 0 else rl.Color{90, 190, 255, u8(alpha * 255)}
			onion_draw_frame(apn, anim, f, tint)
		}
	}
}

// onion_draw_frame: one frame of the animation where the player's own
// tracks ("." position / rotation / scale) put it at that frame.
@(private = "file")
onion_draw_frame :: proc(apn: ^e.AnimationPlayerNode, anim: ^e.Animation, frame: int, tint: rl.Color) {
	tex: ^e.Texture
	src: rl.Rectangle
	if anim.renderFrame == e.FA_RenderFrame {
		fa := cast(^e.FrameAnimation)anim
		if frame < 0 || frame >= len(fa.frames) do return
		tex = fa.frames[frame]
		if tex == nil do return
		s := e.Texture_Size(tex)
		src = {0, 0, s.x, s.y}
	} else if anim.renderFrame == e.SSA_RenderFrame {
		ssa := cast(^e.SpriteSheetAnimation)anim
		tex = ssa.spriteSheet
		if tex == nil do return
		cell := frame
		if len(ssa.cells) > 0 do cell = ssa.cells[clamp(frame, 0, len(ssa.cells) - 1)]
		src = e.SpriteSheet_CellRect(e.Texture_Size(tex), ssa.grid, ssa.margin, ssa.spacing, cell, ssa.cellSize)
	} else {
		return
	}
	if tex.texture.id == 0 do return
	pos, rot, scl := apn.globalPosition, apn.globalRotation, apn.globalScale
	at := e.Animation_FrameTime(apn, anim, f32(frame - anim.startFrame))
	for &tr in anim.tracks {
		if tr.kind != .Property || (tr.target != "." && tr.target != "") do continue
		v, ok := e.Track_Sample(&tr, at)
		if !ok do continue
		switch tr.property {
		case "position": pos = apn.globalPosition - apn.position + {v[0], v[1]}
		case "rotation": rot = apn.globalRotation - apn.rotation + v[0]
		case "scale":    scl = {v[0], v[1]}
		}
	}
	size := [2]f32{src.width, src.height}
	e.Texture_DrawScaled(tex.texture, e.Texture_Src(tex, src), pos, size, scl, apn.pivot * size, rot, tint)
}

// --- custom curves -------------------------------------------------------------------

Curve_Edit :: struct {
	open:  bool,
	track: int,
	time:  f32, // the key's time (seconds)
}

curveEdit: Curve_Edit

CURVE_PRESETS := [?]struct {
	name:  string,
	curve: [4]f32,
}{
	{"Ease In", {0.42, 0, 1, 1}},
	{"Ease Out", {0, 0, 0.58, 1}},
	{"Ease In Out", {0.42, 0, 0.58, 1}},
	{"Back Out", {0.34, 1.56, 0.64, 1}},
	{"Anticipate", {0.36, -0.4, 0.66, 1}},
	{"Snap", {0.9, 0, 0.1, 1}},
}

// CurveEditor_Render: the popup editing the curve from a key to the next
// (opened from the key's menu) - a bezier shape set on the keys' handles.
CurveEditor_Render :: proc(state: ^EditorState, apn: ^e.AnimationPlayerNode, anim: ^e.Animation) {
	if curveEdit.open {
		imgui.OpenPopup("##curve_editor")
		curveEdit.open = false
	}
	if !imgui.BeginPopup("##curve_editor") do return
	defer imgui.EndPopup()
	if curveEdit.track < 0 || curveEdit.track >= len(anim.tracks) {
		imgui.CloseCurrentPopup()
		return
	}
	tr := &anim.tracks[curveEdit.track]
	ki := e.Track_KeyAt(tr, curveEdit.time)
	if ki < 0 {
		imgui.CloseCurrentPopup()
		return
	}
	key := &tr.keys[ki]
	frame := int(math.round(e.Animation_TimeFrame(apn, anim, key.time)))
	UI_PanelTitle(ICON_FA_BEZIER_CURVE, fmt.tprintf("Curve from frame %d to the next key", frame + 1))
	if ki + 1 >= len(tr.keys) {
		UI_DimText("The last key: add a key after it to shape the motion between them.")
		return
	}
	custom, hasCurve := e.Track_SegmentCurve(tr, ki)
	if !hasCurve {
		UI_DimText(fmt.tprintf("Easing: %s - drag a handle or pick a preset for a custom curve.", e.Ease_Name(key.ease)))
	}
	// The canvas: x = time 0..1, y = progress (room above / below for overshoot).
	S :: f32(220)
	PAD :: f32(50)
	p0 := imgui.GetCursorScreenPos()
	imgui.InvisibleButton("##curve_canvas", {S, S + PAD * 2})
	Drive_Item("anim.curve-canvas")
	dl := imgui.GetWindowDrawList()
	o := [2]f32{p0.x, p0.y + PAD + S} // (0,0)
	to_px :: proc(o: [2]f32, x, y: f32) -> [2]f32 {return {o.x + x * S, o.y - y * S}}
	imgui.DrawList_AddRectFilled(dl, {p0.x, p0.y}, {p0.x + S, p0.y + S + PAD * 2}, col_u32(ui_line(0.03)), 4)
	imgui.DrawList_AddRect(dl, to_px(o, 0, 1), to_px(o, 1, 0), col_u32(ui_line(0.12)))
	for g in 1 ..< 4 {
		gx := f32(g) / 4
		imgui.DrawList_AddLine(dl, to_px(o, gx, 0), to_px(o, gx, 1), col_u32(ui_line(0.05)))
		imgui.DrawList_AddLine(dl, to_px(o, 0, gx), to_px(o, 1, gx), col_u32(ui_line(0.05)))
	}
	c := custom if hasCurve else curve_from_ease(key.ease)
	h1 := to_px(o, c[0], c[1])
	h2 := to_px(o, c[2], c[3])
	if hasCurve {
		imgui.DrawList_AddLine(dl, to_px(o, 0, 0), h1, col_u32(UI_TEXT_DIM), 1)
		imgui.DrawList_AddLine(dl, to_px(o, 1, 1), h2, col_u32(UI_TEXT_DIM), 1)
	}
	prev := to_px(o, 0, 0)
	for i in 1 ..= 48 {
		u := f32(i) / 48
		y := e.Track_SegmentFactor(tr, ki, u)
		pt := to_px(o, u, y)
		imgui.DrawList_AddLine(dl, prev, pt, col_u32(UI_ACCENT), 2)
		prev = pt
	}
	// Handles: drag either (x stays in 0..1).
	@(static) dragging: int
	mouse := imgui.GetIO().MousePos
	hot := 0
	if dist2(mouse, h1) < 64 do hot = 1
	else if dist2(mouse, h2) < 64 do hot = 2
	if imgui.IsItemActivated() && hot != 0 {
		dragging = hot
		Editor_RecordUndo(state, "Key curve")
		if !hasCurve do e.Track_SetSegmentCurve(tr, ki, c)
	}
	if dragging != 0 && imgui.IsItemActive() {
		x := clamp((mouse.x - o.x) / S, 0, 1)
		y := clamp((o.y - mouse.y) / S, -PAD / S, 1 + PAD / S)
		if dragging == 1 do c[0], c[1] = x, y
		else do c[2], c[3] = x, y
		e.Track_SetSegmentCurve(tr, ki, c)
	}
	if !imgui.IsItemActive() do dragging = 0
	for i in 1 ..= 2 {
		h := h1 if i == 1 else h2
		imgui.DrawList_AddCircleFilled(dl, h, 5, col_u32(UI_WARNING if hot == i || dragging == i else UI_TEXT))
		Drive_ItemRect(fmt.tprintf("anim.curve-handle:%d", i), {h.x - 5, h.y - 5}, {h.x + 5, h.y + 5})
	}
	// Presets.
	for p, i in CURVE_PRESETS {
		if i % 3 != 0 do imgui.SameLine()
		if UI_Button(p.name, fmt.tprintf("anim.curve-preset:%s", p.name)) {
			Editor_RecordUndo(state, "Key curve")
			e.Track_SetSegmentCurve(tr, ki, p.curve)
		}
	}
	if hasCurve {
		UI_DimText(fmt.tprintf("cubic-bezier(%.2f, %.2f, %.2f, %.2f)", custom[0], custom[1], custom[2], custom[3]))
		if UI_Button(fmt.tprintf("Use Easing (%s)", e.Ease_Name(key.ease)), "anim.curve-clear") {
			Editor_RecordUndo(state, "Key curve")
			key.bezier = false
		}
	}
}

@(private = "file")
dist2 :: proc(a, b: [2]f32) -> f32 {d := a - b; return d.x * d.x + d.y * d.y}

// curve_from_ease: a Bezier close to an easing (where a custom curve starts).
curve_from_ease :: proc(ease: e.Ease) -> [4]f32 {
	name := e.Ease_Name(ease)
	switch {
	case strings.has_prefix(name, "in_out"): return {0.42, 0, 0.58, 1}
	case strings.has_prefix(name, "in_"): return {0.42, 0, 1, 1}
	case strings.has_prefix(name, "out_"): return {0, 0, 0.58, 1}
	}
	return {0.25, 0.25, 0.75, 0.75} // linear
}

// Track_DrawCurves draws each key's curve to the next on a property track's
// row (the shape of the motion between keys).
Track_DrawCurves :: proc(dl: ^imgui.DrawList, tr: ^e.Property_Track, x_of: proc(time: f32, data: rawptr) -> f32, data: rawptr, top, bottom: f32) {
	if tr.kind != .Property do return
	for i in 0 ..< len(tr.keys) - 1 {
		a, b := tr.keys[i], tr.keys[i + 1]
		if !a.bezier && a.ease == .Linear do continue
		x0, x1 := x_of(a.time, data), x_of(b.time, data)
		if x1 - x0 < 6 do continue
		h := bottom - top
		prev := [2]f32{x0, bottom}
		for s in 1 ..= 16 {
			u := f32(s) / 16
			pt := [2]f32{x0 + (x1 - x0) * u, bottom - clamp(e.Track_SegmentFactor(tr, i, u), -0.2, 1.2) * h}
			imgui.DrawList_AddLine(dl, prev, pt, col_u32({0.45, 0.65, 1, 0.55}), 1.5)
			prev = pt
		}
	}
}

// --- method events -------------------------------------------------------------------

// Script_ListMethods: the methods a node's script defines
// (`function Cls:name(` / `function Cls.name(`), in file order.
Script_ListMethods :: proc(state: ^EditorState, n: ^e.Node) -> []string {
	out := make([dynamic]string, context.temp_allocator)
	rel := node_script_rel(state, n)
	if rel == "" do return out[:]
	full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
	data, err := os.read_entire_file(full, context.temp_allocator)
	if err != nil do return out[:]
	for line in strings.split_lines(string(data), context.temp_allocator) {
		t := strings.trim_space(line)
		if !strings.has_prefix(t, "function ") do continue
		rest := t[9:]
		i := strings.index_any(rest, ":.")
		j := strings.index_byte(rest, '(')
		if i < 0 || j < i do continue
		name := strings.trim_space(rest[i + 1:j])
		if name != "" do append(&out, name)
	}
	return out[:]
}
