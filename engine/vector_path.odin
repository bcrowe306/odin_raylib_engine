package engine

import "core:math"

// ============================================================================
// 2D vector art (TODO Phase 14; engine/docs/vector.md): paths and shapes.
//
//   Vector_Path    move / line / quad / cubic / close commands; the points
//                  are packed: move and line take 1, quad 2 (control, end),
//                  cubic 3 (control 1, control 2, end)
//   Vector_Style   fill (colour, rule) and stroke (colour, width, joins,
//                  caps, miter limit)
//   Vector_Shape   a path drawn with a style
//
// Shapes are tessellated into triangle meshes (vector_tess.odin) once and
// cached; drawing them only sets a transform (vector_mesh.odin).
// ============================================================================

Vector_Cmd :: enum u8 {
	Move,
	Line,
	Quad,
	Cubic,
	Close,
}

Vector_Path :: struct {
	cmds: [dynamic]Vector_Cmd,
	pts:  [dynamic][2]f32,
}

Vector_Fill_Rule :: enum u8 {
	NonZero,
	EvenOdd,
}

Vector_Join :: enum u8 {
	Miter,
	Round,
	Bevel,
}

Vector_Cap :: enum u8 {
	Butt,
	Round,
	Square,
}

Vector_Style :: struct {
	fill:        bool,
	fillColor:   [4]u8,
	fillRule:    Vector_Fill_Rule,
	stroke:      bool,
	strokeColor: [4]u8,
	strokeWidth: f32,
	join:        Vector_Join,
	cap:         Vector_Cap,
	miterLimit:  f32,
}

VECTOR_STYLE_DEFAULT :: Vector_Style {
	fill        = true,
	fillColor   = {255, 255, 255, 255},
	strokeColor = {0, 0, 0, 255},
	strokeWidth = 1,
	miterLimit  = 4,
}

Vector_Shape :: struct {
	path:  Vector_Path,
	style: Vector_Style,
}

Vector_Path_Init :: proc(p: ^Vector_Path, allocator := context.allocator) {
	p.cmds = make([dynamic]Vector_Cmd, allocator)
	p.pts = make([dynamic][2]f32, allocator)
}

Vector_Path_Destroy :: proc(p: ^Vector_Path) {
	delete(p.cmds)
	delete(p.pts)
	p^ = {}
}

Vector_Path_Clear :: proc(p: ^Vector_Path) {
	clear(&p.cmds)
	clear(&p.pts)
}

Vector_MoveTo :: proc(p: ^Vector_Path, a: [2]f32) {
	append(&p.cmds, Vector_Cmd.Move)
	append(&p.pts, a)
}

Vector_LineTo :: proc(p: ^Vector_Path, a: [2]f32) {
	append(&p.cmds, Vector_Cmd.Line)
	append(&p.pts, a)
}

Vector_QuadTo :: proc(p: ^Vector_Path, c, a: [2]f32) {
	append(&p.cmds, Vector_Cmd.Quad)
	append(&p.pts, c, a)
}

Vector_CubicTo :: proc(p: ^Vector_Path, c1, c2, a: [2]f32) {
	append(&p.cmds, Vector_Cmd.Cubic)
	append(&p.pts, c1, c2, a)
}

Vector_Close :: proc(p: ^Vector_Path) {
	append(&p.cmds, Vector_Cmd.Close)
}

// Vector_Ellipse adds a closed ellipse (4 cubics, clockwise in screen space).
Vector_Ellipse :: proc(p: ^Vector_Path, c: [2]f32, r: [2]f32) {
	K :: 0.5522847498 // 4/3 * (sqrt(2) - 1): a circle's quarter as a cubic
	k := r * K
	Vector_MoveTo(p, {c.x + r.x, c.y})
	Vector_CubicTo(p, {c.x + r.x, c.y + k.y}, {c.x + k.x, c.y + r.y}, {c.x, c.y + r.y})
	Vector_CubicTo(p, {c.x - k.x, c.y + r.y}, {c.x - r.x, c.y + k.y}, {c.x - r.x, c.y})
	Vector_CubicTo(p, {c.x - r.x, c.y - k.y}, {c.x - k.x, c.y - r.y}, {c.x, c.y - r.y})
	Vector_CubicTo(p, {c.x + k.x, c.y - r.y}, {c.x + r.x, c.y - k.y}, {c.x + r.x, c.y})
	Vector_Close(p)
}

// Vector_Rect adds a closed rectangle (clockwise in screen space).
Vector_Rect :: proc(p: ^Vector_Path, min, max: [2]f32) {
	Vector_MoveTo(p, min)
	Vector_LineTo(p, {max.x, min.y})
	Vector_LineTo(p, max)
	Vector_LineTo(p, {min.x, max.y})
	Vector_Close(p)
}

// --- flattening ---------------------------------------------------------------------

// Vector_Contour: a flattened subpath (closed: the last point joins the first).
Vector_Contour :: struct {
	first, count: int, // into Vector_Flat.pts
	closed:       bool,
}

Vector_Flat :: struct {
	pts:      [dynamic][2]f32,
	contours: [dynamic]Vector_Contour,
}

Vector_Flat_Destroy :: proc(f: ^Vector_Flat) {
	delete(f.pts)
	delete(f.contours)
	f^ = {}
}

Vector_Contour_Points :: proc(f: ^Vector_Flat, c: Vector_Contour) -> [][2]f32 {
	return f.pts[c.first:c.first + c.count]
}

// Vector_CurveSegments: how many lines approximate a curve within `tol`
// (Wang's formula: the curve stays within tol of its chords).
Vector_QuadSegments :: proc(p0, p1, p2: [2]f32, tol: f32) -> int {
	dd := linalg_len(p0 - 2 * p1 + p2)
	n := math.sqrt(0.25 * dd / max(tol, 1e-4))
	return clamp(int(math.ceil(n)), 1, 512)
}

Vector_CubicSegments :: proc(p0, p1, p2, p3: [2]f32, tol: f32) -> int {
	dd := max(linalg_len(p0 - 2 * p1 + p2), linalg_len(p1 - 2 * p2 + p3))
	n := math.sqrt(0.75 * dd / max(tol, 1e-4))
	return clamp(int(math.ceil(n)), 1, 512)
}

@(private = "file")
linalg_len :: proc(v: [2]f32) -> f32 {return math.sqrt(v.x * v.x + v.y * v.y)}

// Vector_Flatten turns a path into polylines whose distance to the curves is
// at most `tol` (in the path's units: tessellating for a zoom divides the
// screen tolerance by the scale). Consecutive duplicate points are dropped.
Vector_Flatten :: proc(path: ^Vector_Path, tol: f32, out: ^Vector_Flat) {
	clear(&out.pts)
	clear(&out.contours)
	cur := Vector_Contour{first = 0}
	last: [2]f32
	start: [2]f32
	add :: proc(out: ^Vector_Flat, cur: ^Vector_Contour, p: [2]f32) {
		if cur.count > 0 {
			q := out.pts[len(out.pts) - 1]
			if abs(q.x - p.x) < 1e-5 && abs(q.y - p.y) < 1e-5 do return
		}
		append(&out.pts, p)
		cur.count += 1
	}
	finish :: proc(out: ^Vector_Flat, cur: ^Vector_Contour, closed: bool) {
		if cur.count >= 2 {
			// A closing point equal to the first is implied.
			if closed && cur.count > 2 {
				a, b := out.pts[cur.first], out.pts[cur.first + cur.count - 1]
				if abs(a.x - b.x) < 1e-5 && abs(a.y - b.y) < 1e-5 {
					pop(&out.pts)
					cur.count -= 1
				}
			}
			cur.closed = closed
			append(&out.contours, cur^)
		} else {
			resize(&out.pts, cur.first)
		}
		cur^ = {first = len(out.pts)}
	}
	pi := 0
	for cmd in path.cmds {
		switch cmd {
		case .Move:
			if cur.count > 0 do finish(out, &cur, false)
			last = path.pts[pi]; start = last; pi += 1
			add(out, &cur, last)
		case .Line:
			if cur.count == 0 do add(out, &cur, last)
			last = path.pts[pi]; pi += 1
			add(out, &cur, last)
		case .Quad:
			if cur.count == 0 do add(out, &cur, last)
			c, e := path.pts[pi], path.pts[pi + 1]; pi += 2
			n := Vector_QuadSegments(last, c, e, tol)
			for i in 1 ..= n {
				t := f32(i) / f32(n)
				u := 1 - t
				add(out, &cur, u * u * last + 2 * u * t * c + t * t * e)
			}
			last = e
		case .Cubic:
			if cur.count == 0 do add(out, &cur, last)
			c1, c2, e := path.pts[pi], path.pts[pi + 1], path.pts[pi + 2]; pi += 3
			n := Vector_CubicSegments(last, c1, c2, e, tol)
			for i in 1 ..= n {
				t := f32(i) / f32(n)
				u := 1 - t
				add(out, &cur, u * u * u * last + 3 * u * u * t * c1 + 3 * u * t * t * c2 + t * t * t * e)
			}
			last = e
		case .Close:
			finish(out, &cur, true)
			last = start
		}
	}
	if cur.count > 0 do finish(out, &cur, false)
}

// Vector_SignedArea: twice the signed area of a polygon (positive = clockwise
// in screen space, y down).
Vector_SignedArea :: proc(pts: [][2]f32) -> f32 {
	a: f32
	n := len(pts)
	for i in 0 ..< n {
		p, q := pts[i], pts[(i + 1) % n]
		a += p.x * q.y - q.x * p.y
	}
	return a
}

// Vector_PointInPolygon: even-odd test.
Vector_PointInPolygon :: proc(pts: [][2]f32, p: [2]f32) -> bool {
	inside := false
	n := len(pts)
	j := n - 1
	for i in 0 ..< n {
		a, b := pts[i], pts[j]
		if (a.y > p.y) != (b.y > p.y) && p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x do inside = !inside
		j = i
	}
	return inside
}
