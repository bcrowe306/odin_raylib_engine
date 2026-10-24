package editor

import "core:fmt"
import "core:math"
import e "../engine"
import imgui "lib/imgui"
import rl "vendor:raylib"

// ============================================================================
// Path editing in the viewport (PathNode, engine/path_node.odin).
//
//   every path        its curve, faint (bright when selected)
//   selected path     points (squares) and their Bézier handles (dots)
//   drag a point      move it;  drag a handle  bend the curve (the other
//                     handle mirrors it; Alt: only this one)
//   double-click      on the curve: a point there (the shape is kept)
//   Alt+click point   remove it (a path keeps two)
//   Ctrl+click        empty space: a point at the end
//
// Followers (PathFollowNode children) are shown at their progress while
// editing, so setting `progress` in the Inspector previews it.
// ============================================================================

Path_Handle_Kind :: enum u8 {None, Point, In, Out}

@(private = "file")
pe: struct {
	path:     ^e.PathNode,
	kind:     Path_Handle_Kind,
	index:    int,
	dragging: bool,
	undo:     bool,
	selected: int, // the last point clicked (-1)
}

PATH_HANDLE_PX :: 7

// PathEdit_Selected: the selected point of the selected path (-1 none).
PathEdit_Selected :: proc(path: ^e.PathNode) -> int {return pe.selected if pe.path == path else -1}

@(private = "file")
path_world_to_local :: proc(p: ^e.PathNode, w: [2]f32) -> [2]f32 {
	r := -p.globalRotation * math.PI / 180
	c, s := math.cos(r), math.sin(r)
	d := w - p.globalPosition
	l := [2]f32{d.x * c - d.y * s, d.x * s + d.y * c}
	sc := p.globalScale
	return {l.x / sc.x if sc.x != 0 else l.x, l.y / sc.y if sc.y != 0 else l.y}
}

// Viewport_DrawPaths (world space, raylib): every path's curve; followers
// placed at their progress while editing.
Viewport_DrawPaths :: proc(state: ^EditorState) {
	if state.activeScene == nil do return
	m := state.activeScene.manager
	for n in m.nodes {
		if n == nil || !n.enabled do continue
		switch n.typeId {
		case e.PathNode:
			if Editor_ViewHidden(state, n) do continue
			p := cast(^e.PathNode)n
			e.PathNode_Bake(p)
			sel := n == state.selectedNode
			col := p.color
			col.a = 255 if sel else 140
			th := (2.5 if sel else 1.5) / state.cameraZoom
			for i in 0 ..< len(p.baked) - 1 do rl.DrawLineEx(e.PathNode_ToWorld(p, p.baked[i]), e.PathNode_ToWorld(p, p.baked[i + 1]), th, col)
		case e.PathFollowNode:
			if !state.isSimulating {
				f := cast(^e.PathFollowNode)n
				if path := e.PathFollowNode_Path(f, m); path != nil do e.PathFollowNode_Place(f, path)
			}
		}
	}
}

// Viewport_PathEdit: the selected path's handles; true while it owns the mouse.
Viewport_PathEdit :: proc(state: ^EditorState, dl: ^imgui.DrawList, mouseScreen, mouseWorld: [2]f32) -> bool {
	sel := state.selectedNode
	if sel == nil || sel.typeId != e.PathNode || Editor_ViewLocked(state, sel) {
		pe.dragging = false
		return false
	}
	p := cast(^e.PathNode)sel
	if pe.path != p {
		pe.path, pe.dragging, pe.selected = p, false, -1
	}
	io := imgui.GetIO()
	scr :: proc(state: ^EditorState, p: ^e.PathNode, local: [2]f32) -> [2]f32 {return Viewport_WorldToScreen(state, e.PathNode_ToWorld(p, local))}

	// Draw: handle lines, handles, points; find what's under the mouse.
	hoverKind, hoverIndex := Path_Handle_Kind.None, -1
	best := f32(PATH_HANDLE_PX + 2)
	consider :: proc(kind: Path_Handle_Kind, i: int, at, mouse: [2]f32, best: ^f32, hk: ^Path_Handle_Kind, hi: ^int) {
		d := math.sqrt((at.x - mouse.x) * (at.x - mouse.x) + (at.y - mouse.y) * (at.y - mouse.y))
		if d < best^ {best^, hk^, hi^ = d, kind, i}
	}
	accent := col_u32(UI_ACCENT)
	for pt, i in p.points {
		a := scr(state, p, pt.pos)
		for k in ([2]Path_Handle_Kind{.In, .Out}) {
			off := pt.in_ if k == .In else pt.out
			if off == {} && pe.selected != i do continue
			h := scr(state, p, pt.pos + off)
			imgui.DrawList_AddLine(dl, a, h, col_u32(ui_line(0.5)), 1)
			imgui.DrawList_AddCircleFilled(dl, h, 4.5, col_u32({1, 1, 1, 1}))
			imgui.DrawList_AddCircle(dl, h, 4.5, accent)
			if state.viewportHovered do consider(k, i, h, mouseScreen, &best, &hoverKind, &hoverIndex)
			Drive_ItemRect(fmt.tprintf("path.%s:%d", "in" if k == .In else "out", i), h - {5, 5}, h + {5, 5}, inWindow = true)
		}
	}
	for pt, i in p.points {
		a := scr(state, p, pt.pos)
		r := f32(5)
		fill := accent if i == pe.selected else col_u32({1, 1, 1, 1})
		imgui.DrawList_AddRectFilled(dl, a - r, a + r, fill)
		imgui.DrawList_AddRect(dl, a - r, a + r, accent)
		if state.viewportHovered do consider(.Point, i, a, mouseScreen, &best, &hoverKind, &hoverIndex)
		Drive_ItemRect(fmt.tprintf("path.point:%d", i), a - {6, 6}, a + {6, 6}, inWindow = true)
	}
	// Each segment's middle (drives double-click there).
	n := len(p.points)
	segs := n if p.closed && n > 1 else n - 1
	for i in 0 ..< max(segs, 0) {
		a, b := p.points[i], p.points[(i + 1) % n]
		mid := path_bezier(a.pos, a.pos + a.out, b.pos + b.in_, b.pos, 0.5)
		s := scr(state, p, mid)
		Drive_ItemRect(fmt.tprintf("path.seg:%d", i), s - {4, 4}, s + {4, 4}, inWindow = true)
	}
	if hoverKind != .None do imgui.SetMouseCursor(.Hand)
	// On the curve (not a handle): clicks belong to the path (a double-click
	// adds a point there), not to picking what's under it.
	nearCurve := false
	if hoverKind == .None && state.viewportHovered {
		for i in 0 ..< len(p.baked) - 1 {
			a, b := scr(state, p, p.baked[i]), scr(state, p, p.baked[i + 1])
			ab := b - a
			ll := ab.x * ab.x + ab.y * ab.y
			t := clamp(((mouseScreen.x - a.x) * ab.x + (mouseScreen.y - a.y) * ab.y) / ll, 0, 1) if ll > 0 else 0
			q := a + ab * t
			if (mouseScreen.x - q.x) * (mouseScreen.x - q.x) + (mouseScreen.y - q.y) * (mouseScreen.y - q.y) < 64 {nearCurve = true; break}
		}
		if nearCurve do imgui.SetTooltip("Double-click: add a point here")
	}

	// Mouse.
	if state.viewportHovered && imgui.IsMouseClicked(.Left) && state.toolMode != .Pan {
		switch {
		case hoverKind == .Point && io.KeyAlt:
			if len(p.points) > 2 {
				Editor_RecordUndo(state, "Remove path point")
				ordered_remove(&p.points, hoverIndex)
				pe.selected = -1
			}
			return true
		case hoverKind != .None:
			pe.kind, pe.index, pe.dragging, pe.undo = hoverKind, hoverIndex, true, false
			pe.selected = hoverIndex
			return true
		case imgui.IsMouseDoubleClicked(.Left):
			if path_insert_at(state, p, path_world_to_local(p, mouseWorld)) do return true
		case nearCurve:
			return true // (the first click of a double-click)
		case io.KeyCtrl || io.KeySuper:
			Editor_RecordUndo(state, "Add path point")
			append(&p.points, e.Path_Point{pos = path_world_to_local(p, mouseWorld)})
			pe.selected = len(p.points) - 1
			return true
		}
	}
	if pe.dragging {
		if !imgui.IsMouseDown(.Left) {
			pe.dragging = false
			return true
		}
		if pe.index >= len(p.points) {
			pe.dragging = false
			return false
		}
		if imgui.IsMouseDragging(.Left, 1) {
			if !pe.undo {
				Editor_RecordUndo(state, "Edit path")
				pe.undo = true
			}
			pt := &p.points[pe.index]
			l := path_world_to_local(p, mouseWorld)
			switch pe.kind {
			case .Point: pt.pos = l
			case .Out:
				pt.out = l - pt.pos
				if !io.KeyAlt do pt.in_ = -pt.out
			case .In:
				pt.in_ = l - pt.pos
				if !io.KeyAlt do pt.out = -pt.in_
			case .None:
			}
		}
		return true
	}
	return hoverKind != .None && imgui.IsMouseDown(.Left)
}

@(private = "file")
path_bezier :: proc(p0, c0, c1, p1: [2]f32, t: f32) -> [2]f32 {
	u := 1 - t
	return u * u * u * p0 + 3 * u * u * t * c0 + 3 * u * t * t * c1 + t * t * t * p1
}

// path_insert_at splits the segment nearest to a local point there (de
// Casteljau: the curve keeps its shape). False when it's not near the curve.
@(private = "file")
path_insert_at :: proc(state: ^EditorState, p: ^e.PathNode, local: [2]f32) -> bool {
	n := len(p.points)
	segs := n if p.closed && n > 1 else n - 1
	bestSeg, bestT, bestD := -1, f32(0), max(f32)
	for i in 0 ..< max(segs, 0) {
		a, b := p.points[i], p.points[(i + 1) % n]
		for k in 0 ..= 64 {
			t := f32(k) / 64
			q := path_bezier(a.pos, a.pos + a.out, b.pos + b.in_, b.pos, t)
			d := (q.x - local.x) * (q.x - local.x) + (q.y - local.y) * (q.y - local.y)
			if d < bestD do bestSeg, bestT, bestD = i, t, d
		}
	}
	tol := 10 / max(state.cameraZoom, 0.01)
	if bestSeg < 0 || bestD > tol * tol || bestT <= 0 || bestT >= 1 do return false
	Editor_RecordUndo(state, "Insert path point")
	i, j := bestSeg, (bestSeg + 1) % n
	a, b := p.points[i], p.points[j]
	p0, c0, c1, p1 := a.pos, a.pos + a.out, b.pos + b.in_, b.pos
	t := bestT
	lerp :: proc(x, y: [2]f32, t: f32) -> [2]f32 {return x + (y - x) * t}
	q0, q1, q2 := lerp(p0, c0, t), lerp(c0, c1, t), lerp(c1, p1, t)
	r0, r1 := lerp(q0, q1, t), lerp(q1, q2, t)
	m := lerp(r0, r1, t)
	p.points[i].out = q0 - p0
	p.points[j].in_ = q2 - p1
	inject_at(&p.points, i + 1, e.Path_Point{pos = m, in_ = r0 - m, out = r1 - m})
	pe.selected = i + 1
	return true
}
