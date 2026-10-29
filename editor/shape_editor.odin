package editor

import "core:fmt"
import "core:math"
import "core:strconv"
import "core:strings"
import b2 "vendor:box2d"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Collision shape editing in the viewport.
//
// With a physics body selected (StaticBody, DynamicBody, Area,
// CharacterMover), "Edit Shapes" (viewport overlay or Inspector) shows
// handles on its collision shapes instead of the transform gizmo:
//
//   centre        drag to move the shape (offset)
//   rotation knob drag to rotate it (not circles)
//   box           edges and corners resize (the opposite side stays put;
//                 hold Shift to resize around the centre)
//   circle        radius
//   capsule       radius (side) and length (ends)
//   polygon/chain drag points; click a "+" between two points to add one;
//                 right-click a point to remove it
//   segment       its two end points
//
// Shapes are edited in the node's local units (they scale with the node).
// Grid snapping applies. Every drag is one undo step. Esc leaves the mode.
// ============================================================================

@(private = "file")
Handle_Kind :: enum {
	None,
	Move,
	Rotate,
	Radius,
	Edge,     // index: 0 right, 1 bottom, 2 left, 3 top
	Corner,   // index: 0 TR, 1 BR, 2 BL, 3 TL
	CapEnd,   // index: 0 top, 1 bottom
	Point,    // polygon vertex / chain point / segment end (index)
	AddPoint, // insert after index
}

@(private = "file")
Handle :: struct {
	shape: int,
	kind:  Handle_Kind,
	index: int,
}

@(private = "file")
Shape_Edit :: struct {
	active:     bool,
	node:       ^e.Node,
	hover:      Handle,
	drag:       Handle,
	dragging:   bool,
	startShape: e.PhysicsShape,
	startMouse: [2]f32,
	startWorld: [2]f32, // the dragged handle's world position at the start
}

@(private = "file")
se: Shape_Edit

HANDLE_PX :: 5.0

ShapeEdit_IsActive :: proc(state: ^EditorState) -> bool {
	return se.active && state.selectedNode != nil && node_shapes_editor(state.selectedNode) != nil
}

ShapeEdit_SetActive :: proc(state: ^EditorState, on: bool) {
	se.active = on
	se.dragging = false
	se.hover = {}
	if on do Editor_Log(state, .Info, "Editing collision shapes: drag the handles (Esc to finish)")
}

// --- transforms ------------------------------------------------------------------------

@(private = "file")
rotate :: proc(v: [2]f32, deg: f32) -> [2]f32 {
	r := math.to_radians(deg)
	c, s := math.cos(r), math.sin(r)
	return {v.x * c - v.y * s, v.x * s + v.y * c}
}

@(private = "file")
node_scale :: proc(node: ^e.Node) -> [2]f32 {
	sc := node.globalScale
	if sc.x == 0 && sc.y == 0 do sc = {1, 1}
	if abs(sc.x) < 0.0001 do sc.x = 0.0001
	if abs(sc.y) < 0.0001 do sc.y = 0.0001
	return sc
}

// shape space (the shape's own frame) -> world
@(private = "file")
to_world :: proc(node: ^e.Node, shape: ^e.PhysicsShape, q: [2]f32) -> [2]f32 {
	local := shape.offset + rotate(q, shape.rotation)
	return node.globalPosition + rotate(local * node_scale(node), node.globalRotation)
}

// world -> node local (the space offsets are in)
@(private = "file")
to_node :: proc(node: ^e.Node, w: [2]f32) -> [2]f32 {
	return rotate(w - node.globalPosition, -node.globalRotation) / node_scale(node)
}

// world -> shape space of `shape`
@(private = "file")
to_shape :: proc(node: ^e.Node, shape: ^e.PhysicsShape, w: [2]f32) -> [2]f32 {
	return rotate(to_node(node, w) - shape.offset, -shape.rotation)
}

@(private = "file")
snap_world :: proc(state: ^EditorState, w: [2]f32) -> [2]f32 {
	if !state.snapGrid || state.gridSize <= 0 do return w
	g := state.gridSize
	return {math.round(w.x / g) * g, math.round(w.y / g) * g}
}

// --- handles -------------------------------------------------------------------------

@(private = "file")
Handle_Pos :: struct {
	h:   Handle,
	pos: [2]f32, // world
}

@(private = "file")
shape_handles :: proc(state: ^EditorState, node: ^e.Node, shapes: []e.PhysicsShape) -> [dynamic]Handle_Pos {
	out := make([dynamic]Handle_Pos, context.temp_allocator)
	z := state.cameraZoom
	for &s, i in shapes {
		add :: proc(out: ^[dynamic]Handle_Pos, node: ^e.Node, s: ^e.PhysicsShape, i: int, kind: Handle_Kind, idx: int, q: [2]f32) {
			append(out, Handle_Pos{{i, kind, idx}, to_world(node, s, q)})
		}
		switch s.type {
		case .Box, .RoundedBox:
			hw, hh := s.size.x * 0.5, s.size.y * 0.5
			add(&out, node, &s, i, .Edge, 0, {hw, 0})
			add(&out, node, &s, i, .Edge, 1, {0, hh})
			add(&out, node, &s, i, .Edge, 2, {-hw, 0})
			add(&out, node, &s, i, .Edge, 3, {0, -hh})
			add(&out, node, &s, i, .Corner, 0, {hw, -hh})
			add(&out, node, &s, i, .Corner, 1, {hw, hh})
			add(&out, node, &s, i, .Corner, 2, {-hw, hh})
			add(&out, node, &s, i, .Corner, 3, {-hw, -hh})
		case .Circle:
			add(&out, node, &s, i, .Radius, 0, {s.radius, 0})
		case .Capsule:
			half := s.size.y * 0.5
			add(&out, node, &s, i, .Radius, 0, {s.radius, 0})
			add(&out, node, &s, i, .CapEnd, 0, {0, -(half + s.radius)})
			add(&out, node, &s, i, .CapEnd, 1, {0, half + s.radius})
		case .Polygon:
			n := clamp(s.vertexCount, 3, int(b2.MAX_POLYGON_VERTICES))
			for v in 0 ..< n do add(&out, node, &s, i, .Point, v, s.vertices[v])
			if n < int(b2.MAX_POLYGON_VERTICES) {
				for v in 0 ..< n do add(&out, node, &s, i, .AddPoint, v, (s.vertices[v] + s.vertices[(v + 1) % n]) * 0.5)
			}
		case .Segment:
			add(&out, node, &s, i, .Point, 0, s.point1)
			add(&out, node, &s, i, .Point, 1, s.point2)
		case .Chain:
			n := len(s.chainPoints)
			for v in 0 ..< n do add(&out, node, &s, i, .Point, v, s.chainPoints[v])
			for v in 0 ..< n - 1 do add(&out, node, &s, i, .AddPoint, v, (s.chainPoints[v] + s.chainPoints[v + 1]) * 0.5)
			if s.isLoop && n > 2 do add(&out, node, &s, i, .AddPoint, n - 1, (s.chainPoints[n - 1] + s.chainPoints[0]) * 0.5)
		}
		// Centre and rotation knob (above the shape's top, in its frame).
		append(&out, Handle_Pos{{i, .Move, 0}, to_world(node, &s, {0, 0})})
		if s.type != .Circle {
			top := shape_extent(&s)
			c := to_world(node, &s, {0, 0})
			up := rotate({0, -1}, node.globalRotation + s.rotation)
			ext := top * abs(node_scale(node).y)
			append(&out, Handle_Pos{{i, .Rotate, 0}, c + up * (ext + 26 / z)})
		}
	}
	return out
}

// shape_extent: distance from the centre to the shape's top in shape space.
@(private = "file")
shape_extent :: proc(s: ^e.PhysicsShape) -> f32 {
	switch s.type {
	case .Box, .RoundedBox: return s.size.y * 0.5
	case .Circle: return s.radius
	case .Capsule: return s.size.y * 0.5 + s.radius
	case .Polygon:
		m: f32 = 0
		for v in s.vertices[:clamp(s.vertexCount, 0, len(s.vertices))] do m = max(m, -v.y)
		return m
	case .Segment: return max(-s.point1.y, -s.point2.y, 0)
	case .Chain:
		m: f32 = 0
		for p in s.chainPoints do m = max(m, -p.y)
		return m
	}
	return 0
}

// ShapeEdit_LocalBounds: the bounding box of a body's shapes in the node's
// local space, scaled (for selection outlines and framing).
ShapeEdit_LocalBounds :: proc(node: ^e.Node, shapes: []e.PhysicsShape) -> (lo, hi: [2]f32, ok: bool) {
	sc := node_scale(node)
	for &s in shapes {
		pts := make([dynamic][2]f32, context.temp_allocator)
		switch s.type {
		case .Box, .RoundedBox:
			hw, hh := s.size.x * 0.5, s.size.y * 0.5
			append(&pts, [2]f32{-hw, -hh}, [2]f32{hw, -hh}, [2]f32{hw, hh}, [2]f32{-hw, hh})
		case .Circle:
			r := s.radius * max(abs(sc.x), abs(sc.y)) / max(abs(sc.x), 0.0001)
			r2 := s.radius * max(abs(sc.x), abs(sc.y)) / max(abs(sc.y), 0.0001)
			append(&pts, [2]f32{-r, 0}, [2]f32{r, 0}, [2]f32{0, -r2}, [2]f32{0, r2})
		case .Capsule:
			h := s.size.y * 0.5 + s.radius
			append(&pts, [2]f32{-s.radius, -h}, [2]f32{s.radius, -h}, [2]f32{s.radius, h}, [2]f32{-s.radius, h})
		case .Polygon:
			for v in s.vertices[:clamp(s.vertexCount, 3, len(s.vertices))] do append(&pts, v)
		case .Segment:
			append(&pts, s.point1, s.point2)
		case .Chain:
			for p in s.chainPoints do append(&pts, p)
		}
		for q in pts {
			p := (s.offset + rotate(q, s.rotation)) * sc
			if !ok do lo, hi, ok = p, p, true
			lo = {min(lo.x, p.x), min(lo.y, p.y)}
			hi = {max(hi.x, p.x), max(hi.y, p.y)}
		}
	}
	return
}

// ShapeEdit_ConvertShape keeps a shape's footprint when its type changes
// (a box becomes a polygon with the same corners, ...).
ShapeEdit_ConvertShape :: proc(s: ^e.PhysicsShape, from: e.PhysicsShapeType) {
	// The old footprint's half extents.
	half: [2]f32
	switch from {
	case .Box, .RoundedBox: half = s.size * 0.5
	case .Circle: half = {s.radius, s.radius}
	case .Capsule: half = {s.radius, s.size.y * 0.5 + s.radius}
	case .Polygon, .Segment, .Chain:
		lo, hi: [2]f32
		pts := make([dynamic][2]f32, context.temp_allocator)
		if from == .Polygon do for v in s.vertices[:clamp(s.vertexCount, 3, len(s.vertices))] do append(&pts, v)
		if from == .Segment do append(&pts, s.point1, s.point2)
		if from == .Chain do for p in s.chainPoints do append(&pts, p)
		for p, i in pts {
			if i == 0 do lo, hi = p, p
			lo = {min(lo.x, p.x), min(lo.y, p.y)}
			hi = {max(hi.x, p.x), max(hi.y, p.y)}
		}
		half = {max(abs(lo.x), abs(hi.x)), max(abs(lo.y), abs(hi.y))}
	}
	half = {max(half.x, 4), max(half.y, 4)}
	switch s.type {
	case .Box, .RoundedBox: s.size = half * 2
	case .Circle: s.radius = max(half.x, half.y)
	case .Capsule:
		s.radius = half.x
		s.size = {half.x * 2, max(half.y * 2 - half.x * 2, 1)}
	case .Polygon:
		s.vertexCount = 4
		s.vertices[0], s.vertices[1], s.vertices[2], s.vertices[3] = {-half.x, -half.y}, {half.x, -half.y}, {half.x, half.y}, {-half.x, half.y}
	case .Segment:
		s.point1, s.point2 = {-half.x, 0}, {half.x, 0}
	case .Chain:
		clear(&s.chainPoints)
		append(&s.chainPoints, [2]f32{-half.x, half.y}, [2]f32{-half.x / 3, -half.y}, [2]f32{half.x / 3, -half.y}, [2]f32{half.x, half.y})
	}
}

// --- outline -------------------------------------------------------------------------

@(private = "file")
draw_outline :: proc(state: ^EditorState, dl: ^imgui.DrawList, node: ^e.Node, s: ^e.PhysicsShape, col: u32, thick: f32) {
	pts := make([dynamic]imgui.Vec2, context.temp_allocator)
	add :: proc(state: ^EditorState, pts: ^[dynamic]imgui.Vec2, node: ^e.Node, s: ^e.PhysicsShape, q: [2]f32) {
		p := Viewport_WorldToScreen(state, to_world(node, s, q))
		append(pts, imgui.Vec2{p.x, p.y})
	}
	closed := true
	switch s.type {
	case .Box, .RoundedBox:
		hw, hh := s.size.x * 0.5, s.size.y * 0.5
		for q in ([4][2]f32{{-hw, -hh}, {hw, -hh}, {hw, hh}, {-hw, hh}}) do add(state, &pts, node, s, q)
	case .Circle:
		// Box2D circles take the node's larger scale axis.
		c := Viewport_WorldToScreen(state, to_world(node, s, {0, 0}))
		sc := node_scale(node)
		imgui.DrawList_AddCircle(dl, c, s.radius * max(abs(sc.x), abs(sc.y)) * state.cameraZoom, col, 48, thick)
		return
	case .Capsule:
		half, r := s.size.y * 0.5, s.radius
		for k in 0 ..= 16 {
			a := math.PI + f32(k) / 16 * math.PI
			add(state, &pts, node, s, {math.cos(a) * r, -half + math.sin(a) * r})
		}
		for k in 0 ..= 16 {
			a := f32(k) / 16 * math.PI
			add(state, &pts, node, s, {math.cos(a) * r, half + math.sin(a) * r})
		}
	case .Polygon:
		for v in s.vertices[:clamp(s.vertexCount, 3, len(s.vertices))] do add(state, &pts, node, s, v)
	case .Segment:
		add(state, &pts, node, s, s.point1)
		add(state, &pts, node, s, s.point2)
		closed = false
	case .Chain:
		for p in s.chainPoints do add(state, &pts, node, s, p)
		closed = s.isLoop
	}
	if len(pts) >= 2 do imgui.DrawList_AddPolyline(dl, raw_data(pts), i32(len(pts)), col, imgui.DrawFlags_Closed if closed else {}, thick)
}

// polygon_convex: Box2D uses the convex hull of a polygon's points.
@(private = "file")
polygon_convex :: proc(s: ^e.PhysicsShape) -> bool {
	n := clamp(s.vertexCount, 3, int(b2.MAX_POLYGON_VERTICES))
	hull := b2.ComputeHull(s.vertices[:n])
	return int(hull.count) == n
}

// --- interaction ---------------------------------------------------------------------

// Viewport_ShapeEdit draws the handles and handles the mouse; returns true
// while it owns the mouse (hovering or dragging a handle).
Viewport_ShapeEdit :: proc(state: ^EditorState, dl: ^imgui.DrawList, mouseScreen, mouseWorld: [2]f32) -> bool {
	if !se.active do return false
	node := state.selectedNode
	shapes := node_shapes_editor(node) if node != nil else nil
	if shapes == nil {
		se.dragging = false
		return false
	}
	if se.node != node {
		se.node = node
		se.dragging = false
	}
	// Seed points for a chain that has none yet.
	for &s in shapes {
		if s.type == .Chain && len(s.chainPoints) < 2 {
			for p in ([4][2]f32{{-48, 0}, {-16, -16}, {16, -16}, {48, 0}}) do append(&s.chainPoints, p)
		}
	}

	handles := shape_handles(state, node, shapes[:])
	accent := col_u32(UI_ACCENT)
	white := col_u32({1, 1, 1, 1})

	// Outlines (red: a polygon that isn't convex).
	for &s in shapes {
		col := accent
		if s.type == .Polygon && !polygon_convex(&s) do col = col_u32(UI_DANGER)
		draw_outline(state, dl, node, &s, col, 2)
	}

	// Hover: the nearest handle under the mouse (points over add-points).
	se.hover = {}
	if !se.dragging && state.viewportHovered {
		best := f32(HANDLE_PX + 4)
		for hp in handles {
			p := Viewport_WorldToScreen(state, hp.pos)
			d := math.sqrt((p.x - mouseScreen.x) * (p.x - mouseScreen.x) + (p.y - mouseScreen.y) * (p.y - mouseScreen.y))
			if hp.h.kind == .AddPoint do d += 2
			if d <= best {
				best = d
				se.hover = hp.h
			}
		}
	}

	// Draw handles.
	for hp in handles {
		p := Viewport_WorldToScreen(state, hp.pos)
		hot := (se.dragging && se.drag == hp.h) || (!se.dragging && se.hover == hp.h)
		id := fmt.tprintf("shape%d.%v%d", hp.h.shape, hp.h.kind, hp.h.index)
		Drive_ItemRect(id, p - HANDLE_PX, p + HANDLE_PX)
		switch hp.h.kind {
		case .Move:
			imgui.DrawList_AddCircleFilled(dl, p, HANDLE_PX + 1, accent if hot else col_u32({0.1, 0.12, 0.16, 0.9}))
			imgui.DrawList_AddCircle(dl, p, HANDLE_PX + 1, white, 16, 1.5)
			imgui.DrawList_AddLine(dl, p - {HANDLE_PX + 5, 0}, p + {HANDLE_PX + 5, 0}, white, 1)
			imgui.DrawList_AddLine(dl, p - {0, HANDLE_PX + 5}, p + {0, HANDLE_PX + 5}, white, 1)
		case .Rotate:
			c := Viewport_WorldToScreen(state, to_world(node, &shapes[hp.h.shape], {0, 0}))
			imgui.DrawList_AddLine(dl, c, p, col_u32({1, 1, 1, 0.35}), 1)
			imgui.DrawList_AddCircleFilled(dl, p, HANDLE_PX, col_u32(UI_WARNING) if hot else col_u32({0.95, 0.68, 0.35, 0.75}))
			imgui.DrawList_AddCircle(dl, p, HANDLE_PX, white, 16, 1.2)
		case .AddPoint:
			col := accent if hot else col_u32({1, 1, 1, 0.45})
			imgui.DrawList_AddCircle(dl, p, HANDLE_PX - 1, col, 12, 1.2)
			imgui.DrawList_AddLine(dl, p - {3, 0}, p + {3, 0}, col, 1.2)
			imgui.DrawList_AddLine(dl, p - {0, 3}, p + {0, 3}, col, 1.2)
		case .None:
		case .Radius, .Edge, .Corner, .CapEnd, .Point:
			imgui.DrawList_AddRectFilled(dl, p - HANDLE_PX, p + HANDLE_PX, accent if hot else white)
			imgui.DrawList_AddRect(dl, p - HANDLE_PX, p + HANDLE_PX, col_u32({0.1, 0.12, 0.16, 1}), 0, {}, 1.2)
		}
	}
	if se.hover.kind != .None || se.dragging {
		tip := ""
		h := se.drag if se.dragging else se.hover
		switch h.kind {
		case .Move: tip = "Move the shape"
		case .Rotate: tip = "Rotate the shape"
		case .Radius: tip = "Radius"
		case .Edge, .Corner: tip = "Resize (Shift: around the centre)"
		case .CapEnd: tip = "Length"
		case .Point: tip = "Drag the point · right-click to remove it"
		case .AddPoint: tip = "Click to add a point here"
		case .None:
		}
		if tip != "" do UI_Tooltip(tip)
	}

	// Remove a point (right-click).
	if se.hover.kind == .Point && imgui.IsMouseClicked(.Right) && !se.dragging {
		s := &shapes[se.hover.shape]
		#partial switch s.type {
		case .Polygon:
			if s.vertexCount > 3 {
				Editor_RecordUndo(state, "Remove shape point")
				for v in se.hover.index ..< s.vertexCount - 1 do s.vertices[v] = s.vertices[v + 1]
				s.vertexCount -= 1
			}
		case .Chain:
			if len(s.chainPoints) > 2 {
				Editor_RecordUndo(state, "Remove shape point")
				ordered_remove(&s.chainPoints, se.hover.index)
			}
		}
		return true
	}

	// Start a drag.
	if !se.dragging && se.hover.kind != .None && imgui.IsMouseClicked(.Left) {
		h := se.hover
		s := &shapes[h.shape]
		Editor_RecordUndo(state, "Edit collision shape")
		if h.kind == .AddPoint {
			// Insert the point, then drag it.
			#partial switch s.type {
			case .Polygon:
				n := s.vertexCount
				mid := (s.vertices[h.index] + s.vertices[(h.index + 1) % n]) * 0.5
				for v := n; v > h.index + 1; v -= 1 do s.vertices[v] = s.vertices[v - 1]
				s.vertices[h.index + 1] = mid
				s.vertexCount = n + 1
			case .Chain:
				n := len(s.chainPoints)
				mid := (s.chainPoints[h.index] + s.chainPoints[(h.index + 1) % n]) * 0.5
				inject_at(&s.chainPoints, h.index + 1, mid)
			}
			h = {h.shape, .Point, h.index + 1}
		}
		se.drag = h
		se.dragging = true
		se.startShape = s^
		se.startShape.chainPoints = nil // not needed (points are edited in place)
		se.startMouse = mouseWorld
		for hp in shape_handles(state, node, shapes[:]) do if hp.h == h do se.startWorld = hp.pos
		if h.kind == .Move do se.startWorld = to_world(node, s, {0, 0})
	}

	if se.dragging {
		if !imgui.IsMouseDown(.Left) {
			se.dragging = false
			return true
		}
		s := &shapes[se.drag.shape]
		st := &se.startShape
		target := snap_world(state, se.startWorld + (mouseWorld - se.startMouse))
		q := to_shape(node, st, target) // in the shape's frame at drag start
		symmetric := imgui.GetIO().KeyShift
		switch se.drag.kind {
		case .None, .AddPoint:
		case .Move:
			s.offset = to_node(node, target)
		case .Rotate:
			c := to_world(node, st, {0, 0})
			d := mouseWorld - c
			ang := math.to_degrees(math.atan2(d.y, d.x)) + 90 - node.globalRotation
			if state.snapGrid do ang = math.round(ang / 15) * 15
			for ang < 0 do ang += 360
			for ang >= 360 do ang -= 360
			s.rotation = ang
		case .Radius:
			if s.type == .Circle do s.radius = max(1, math.sqrt(q.x * q.x + q.y * q.y))
			else do s.radius = max(1, abs(q.x))
			if s.type == .Capsule do s.size.x = s.radius * 2
		case .CapEnd:
			s.size.y = max(1, (abs(q.y) - st.radius) * 2)
		case .Edge, .Corner:
			hw, hh := st.size.x * 0.5, st.size.y * 0.5
			left, right, top, bottom := -hw, hw, -hh, hh
			moveX, moveY := 0, 0 // -1 left/top, +1 right/bottom
			if se.drag.kind == .Edge {
				switch se.drag.index {
				case 0: moveX = 1
				case 1: moveY = 1
				case 2: moveX = -1
				case 3: moveY = -1
				}
			} else {
				switch se.drag.index {
				case 0: moveX, moveY = 1, -1
				case 1: moveX, moveY = 1, 1
				case 2: moveX, moveY = -1, 1
				case 3: moveX, moveY = -1, -1
				}
			}
			if moveX == 1 do right = max(q.x, left + 1)
			if moveX == -1 do left = min(q.x, right - 1)
			if moveY == 1 do bottom = max(q.y, top + 1)
			if moveY == -1 do top = min(q.y, bottom - 1)
			if symmetric {
				if moveX != 0 {
					ext := max(abs(q.x), 0.5)
					left, right = -ext, ext
				}
				if moveY != 0 {
					ext := max(abs(q.y), 0.5)
					top, bottom = -ext, ext
				}
			}
			s.size = {right - left, bottom - top}
			s.offset = st.offset + rotate({(left + right) * 0.5, (top + bottom) * 0.5}, st.rotation)
		case .Point:
			#partial switch s.type {
			case .Polygon: s.vertices[se.drag.index] = q
			case .Segment:
				if se.drag.index == 0 do s.point1 = q
				else do s.point2 = q
			case .Chain:
				if se.drag.index < len(s.chainPoints) do s.chainPoints[se.drag.index] = q
			}
		}
		return true
	}
	return se.hover.kind != .None
}

// ShapeEdit_Overlay: the "Edit Shapes" toggle over the viewport (top left)
// while a physics body is selected; call inside the viewport window.
ShapeEdit_Overlay :: proc(state: ^EditorState) -> (hovered: bool) {
	node := state.selectedNode
	if node == nil || node_shapes_editor(node) == nil || len(state.selection) > 1 do return
	pos := state.viewportPos + {10, 10}
	imgui.SetCursorScreenPos(pos)
	on := se.active
	if UI_IconButton(ICON_FA_DRAW_POLYGON, "viewport.edit-shapes", "Edit collision shapes in the viewport (Esc to finish)" if !on else "Stop editing shapes", on, 28) {
		ShapeEdit_SetActive(state, !on)
	}
	hovered = imgui.IsItemHovered()
	if on {
		imgui.SameLine(0, 6)
		imgui.AlignTextToFramePadding()
		imgui.PushStyleColorImVec4(.Text, UI_TEXT)
		imgui.TextUnformatted("Drag handles · + adds a point · right-click removes one · Shift: resize around the centre")
		imgui.PopStyleColor()
		for &sh in node_shapes_editor(node) {
			if sh.type == .Polygon && !polygon_convex(&sh) {
				imgui.SetCursorScreenPos(pos + {0, 34})
				imgui.PushStyleColorImVec4(.Text, UI_DANGER)
				imgui.TextUnformatted(fmt.ctprintf("%s  Polygons must be convex: the red one collides as its outline (convex hull).", ICON_FA_TRIANGLE_EXCLAMATION))
				imgui.PopStyleColor()
				break
			}
		}
	}
	return
}

// ShapeEdit_DriveQuery: shape.edit (mode on), shape:<Node>:<index>:<field>
// with field = type offset size radius rotation vertices points.
ShapeEdit_DriveQuery :: proc(state: ^EditorState, q: string) -> (string, bool) {
	if q == "shape.edit" do return "true" if ShapeEdit_IsActive(state) else "false", true
	if !strings.has_prefix(q, "shape:") do return "", false
	parts := strings.split(q[6:], ":", context.temp_allocator)
	if len(parts) != 3 do return "<shape:Node:index:field>", true
	node: ^e.Node
	if state.activeScene != nil {
		for n in state.activeScene.manager.nodes do if n != nil && n.name == parts[0] {node = n; break}
	}
	if node == nil do return "<no node>", true
	shapes := node_shapes_editor(node)
	idx, _ := strconv.parse_int(parts[1])
	if shapes == nil || idx < 0 || idx >= len(shapes) do return "<no shape>", true
	s := &shapes[idx]
	f2 :: proc(v: [2]f32) -> string {return fmt.tprintf("%.1f,%.1f", v.x, v.y)}
	switch parts[2] {
	case "type": return fmt.tprint(s.type), true
	case "offset": return f2(s.offset), true
	case "size": return f2(s.size), true
	case "radius": return fmt.tprintf("%.1f", s.radius), true
	case "rotation": return fmt.tprintf("%.1f", s.rotation), true
	case "vertices": return fmt.tprint(s.vertexCount), true
	case "points": return fmt.tprint(len(s.chainPoints)), true
	case "count": return fmt.tprint(len(shapes)), true
	}
	return "<field>", true
}
