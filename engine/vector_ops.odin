package engine

import "base:runtime"
import "core:math"
import clip "clipper"

// ============================================================================
// Path operations (Phase 14 V.15) on Clipper2 (engine/clipper): what shapes
// cover as polygons (fills by their own rule, strokes outlined, clip paths
// applied), boolean union / subtract / intersect / exclude, offsetting
// (grow / shrink), stroke outlines, simplifying and flattening - and cutting
// a drawing (destructible art, keeping each shape's paint). Collision from
// vector shapes (vector_collider.odin) starts from these polygons.
//
// Results are Vector_Polys: closed rings, each outer ring followed by its
// holes (parent = the outer's index). Curves are flattened to `tol` (the
// path's units) first; results are lines.
// ============================================================================

Vector_Ring :: struct {
	first, count: int, // into Vector_Polys.pts
	parent:       int, // a hole's outer ring (-1: an outer ring)
}

Vector_Polys :: struct {
	pts:   [dynamic][2]f32,
	rings: [dynamic]Vector_Ring,
}

Vector_Bool_Op :: enum u8 {
	Union,     // either
	Subtract,  // the first without the second
	Intersect, // both
	Exclude,   // one or the other, not both
}

Vector_Polys_Destroy :: proc(p: ^Vector_Polys) {
	delete(p.pts)
	delete(p.rings)
	p^ = {}
}

Vector_Polys_Clear :: proc(p: ^Vector_Polys) {
	clear(&p.pts)
	clear(&p.rings)
}

Vector_Polys_Ring :: proc(p: ^Vector_Polys, i: int) -> [][2]f32 {
	r := p.rings[i]
	return p.pts[r.first:r.first + r.count]
}

// Vector_PolysArea: the area covered (outer rings minus their holes).
Vector_PolysArea :: proc(p: ^Vector_Polys) -> f32 {
	a: f32
	for r, i in p.rings {
		ra := abs(Vector_SignedArea(Vector_Polys_Ring(p, i))) * 0.5
		a += ra if r.parent < 0 else -ra
	}
	return a
}

// Vector_PolysBounds: min x, min y, max x, max y ({} when empty).
Vector_PolysBounds :: proc(p: ^Vector_Polys) -> [4]f32 {
	if len(p.pts) == 0 do return {}
	b := [4]f32{max(f32), max(f32), -max(f32), -max(f32)}
	for q in p.pts do b = {min(b[0], q.x), min(b[1], q.y), max(b[2], q.x), max(b[3], q.y)}
	return b
}

// Vector_PolysContains: whether a point is in the covered area.
Vector_PolysContains :: proc(p: ^Vector_Polys, q: [2]f32) -> bool {
	inside := false
	for _, i in p.rings do if Vector_PointInPolygon(Vector_Polys_Ring(p, i), q) do inside = !inside
	return inside
}

// Vector_PolysAddRing appends a ring (an outer one unless parent >= 0).
Vector_PolysAddRing :: proc(p: ^Vector_Polys, pts: [][2]f32, parent := -1) {
	if len(pts) < 3 do return
	append(&p.rings, Vector_Ring{len(p.pts), len(pts), parent})
	append(&p.pts, ..pts)
}

// Vector_PolysCircle: a circle as a ring of segments within tol.
Vector_PolysCircle :: proc(p: ^Vector_Polys, center: [2]f32, radius: f32, tol: f32 = 0.25) {
	n := clamp(int(math.ceil(math.PI / math.acos(clamp(1 - tol / max(radius, 1e-3), -1, 1)))), 8, 256)
	pts := make([][2]f32, n, context.temp_allocator)
	for i in 0 ..< n {
		a := f32(i) / f32(n) * math.TAU
		pts[i] = center + [2]f32{math.cos(a), math.sin(a)} * radius
	}
	Vector_PolysAddRing(p, pts)
}

// vector_precision: Clipper's decimal places for a tolerance (a tenth of it).
vector_precision :: proc(tol: f32) -> i32 {
	return i32(clamp(math.ceil(-math.log10(f64(max(tol, 1e-6)) * 0.1)), 0, 8))
}

// The rings as Clipper input (temp memory).
@(private = "file")
polys_xy :: proc(p: ^Vector_Polys) -> (xy: [dynamic]f64, counts: [dynamic]i32) {
	xy = make([dynamic]f64, 0, len(p.pts) * 2, context.temp_allocator)
	counts = make([dynamic]i32, 0, len(p.rings), context.temp_allocator)
	for r, i in p.rings {
		if r.count < 3 do continue
		for q in Vector_Polys_Ring(p, i) do append(&xy, f64(q.x), f64(q.y))
		append(&counts, i32(r.count))
	}
	return
}

// A Clipper result into Polys (replacing what was there).
@(private = "file")
polys_from :: proc(res: ^clip.Paths, out: ^Vector_Polys) {
	Vector_Polys_Clear(out)
	k := 0
	for i in 0 ..< int(res.contours) {
		n := int(res.counts[i])
		append(&out.rings, Vector_Ring{len(out.pts), n, int(res.parents[i])})
		for j in 0 ..< n do append(&out.pts, [2]f32{f32(res.xy[(k + j) * 2]), f32(res.xy[(k + j) * 2 + 1])})
		k += n
	}
}

// Vector_PolysNormalize: the area under a fill rule as simple rings with
// their holes (self-intersections and overlaps resolved).
Vector_PolysNormalize :: proc(p: ^Vector_Polys, rule: Vector_Fill_Rule, tol: f32, out: ^Vector_Polys) -> bool {
	xy, counts := polys_xy(p)
	if len(counts) == 0 {Vector_Polys_Clear(out); return true}
	res: clip.Paths
	r: clip.Fill_Rule = .NonZero if rule == .NonZero else .EvenOdd
	if clip.normalize(raw_data(xy), raw_data(counts), i32(len(counts)), r, vector_precision(tol), &res) == 0 do return false
	defer clip.free_paths(&res)
	polys_from(&res, out)
	return true
}

// Vector_PolysBoolean: a op b (both covered areas: normalized polys).
Vector_PolysBoolean :: proc(op: Vector_Bool_Op, a, b: ^Vector_Polys, tol: f32, out: ^Vector_Polys) -> bool {
	axy, acounts := polys_xy(a)
	bxy, bcounts := polys_xy(b)
	res: clip.Paths
	cop: clip.Op
	switch op {
	case .Union: cop = .Union
	case .Subtract: cop = .Difference
	case .Intersect: cop = .Intersection
	case .Exclude: cop = .Xor
	}
	if len(acounts) == 0 {
		// (Nothing to cut from: union / exclude are the other one.)
		if op == .Union || op == .Exclude do return Vector_PolysNormalize(b, .NonZero, tol, out)
		Vector_Polys_Clear(out)
		return true
	}
	if clip.boolean(cop, raw_data(axy), raw_data(acounts), i32(len(acounts)), raw_data(bxy), raw_data(bcounts), i32(len(bcounts)), .NonZero, vector_precision(tol), &res) == 0 do return false
	defer clip.free_paths(&res)
	polys_from(&res, out)
	return true
}

// Vector_PolysOffset grows (delta > 0) or shrinks the area by delta.
Vector_PolysOffset :: proc(p: ^Vector_Polys, delta: f32, join: Vector_Join, tol: f32, out: ^Vector_Polys, miterLimit: f32 = 4) -> bool {
	xy, counts := polys_xy(p)
	if len(counts) == 0 {Vector_Polys_Clear(out); return true}
	res: clip.Paths
	if clip.offset(raw_data(xy), raw_data(counts), i32(len(counts)), 1, f64(delta), clip_join(join), .Butt, f64(miterLimit), f64(tol), vector_precision(tol), &res) == 0 do return false
	defer clip.free_paths(&res)
	polys_from(&res, out)
	return true
}

@(private = "file")
clip_join :: proc(j: Vector_Join) -> clip.Join {
	switch j {
	case .Round: return .Round
	case .Bevel: return .Bevel
	case .Miter: return .Miter
	}
	return .Miter
}

// Vector_StrokeOutline: the area a shape's stroke covers (width, joins,
// caps, dashes) - "outline stroke" in vector apps.
Vector_StrokeOutline :: proc(sh: ^Vector_Shape, tol: f32, out: ^Vector_Polys) -> bool {
	Vector_Polys_Clear(out)
	st := sh.style
	if !st.stroke || st.strokeWidth <= 0 do return true
	flat: Vector_Flat
	flat.pts = make([dynamic][2]f32, context.temp_allocator)
	flat.contours = make([dynamic]Vector_Contour, context.temp_allocator)
	Vector_Flatten(&sh.path, tol, &flat)
	f := &flat
	dashed: Vector_Flat
	if st.dash.count > 0 {
		dashed.pts = make([dynamic][2]f32, context.temp_allocator)
		dashed.contours = make([dynamic]Vector_Contour, context.temp_allocator)
		vector_dash(&flat, &dashed, st.dash)
		f = &dashed
	}
	end: clip.End = .Round if st.cap == .Round else (.Square if st.cap == .Square else .Butt)
	acc: Vector_Polys
	acc.pts = make([dynamic][2]f32, context.temp_allocator)
	acc.rings = make([dynamic]Vector_Ring, context.temp_allocator)
	// Open contours with their ends, closed ones on both sides (two offsets).
	for kind in ([]i32{0, 2}) {
		xy := make([dynamic]f64, context.temp_allocator)
		counts := make([dynamic]i32, context.temp_allocator)
		for c in f.contours {
			if c.count < 2 || (kind == 2) != (c.closed && c.count > 2) do continue
			for q in Vector_Contour_Points(f, c) do append(&xy, f64(q.x), f64(q.y))
			append(&counts, i32(c.count))
		}
		if len(counts) == 0 do continue
		res: clip.Paths
		if clip.offset(raw_data(xy), raw_data(counts), i32(len(counts)), kind, f64(st.strokeWidth * 0.5), clip_join(st.join), end, f64(max(st.miterLimit, 1)), f64(tol), vector_precision(tol), &res) == 0 do continue
		part: Vector_Polys
		part.pts = make([dynamic][2]f32, context.temp_allocator)
		part.rings = make([dynamic]Vector_Ring, context.temp_allocator)
		polys_from(&res, &part)
		clip.free_paths(&res)
		base := len(acc.rings)
		for r, i in part.rings do Vector_PolysAddRing(&acc, Vector_Polys_Ring(&part, i), r.parent + base if r.parent >= 0 else -1)
	}
	return Vector_PolysNormalize(&acc, .NonZero, tol, out)
}

// Vector_FillArea: the area a shape's fill covers (its rule, its clip).
Vector_FillArea :: proc(sh: ^Vector_Shape, tol: f32, out: ^Vector_Polys) -> bool {
	Vector_Polys_Clear(out)
	if !sh.style.fill do return true
	flat: Vector_Flat
	flat.pts = make([dynamic][2]f32, context.temp_allocator)
	flat.contours = make([dynamic]Vector_Contour, context.temp_allocator)
	Vector_Flatten(&sh.path, tol, &flat)
	raw: Vector_Polys
	raw.pts = make([dynamic][2]f32, context.temp_allocator)
	raw.rings = make([dynamic]Vector_Ring, context.temp_allocator)
	for c in flat.contours do if c.count >= 3 do Vector_PolysAddRing(&raw, Vector_Contour_Points(&flat, c)) // (open ones fill as closed, like SVG)
	if !Vector_PolysNormalize(&raw, sh.style.fillRule, tol, out) do return false
	return vector_apply_clip(sh, tol, out)
}

// vector_apply_clip: a shape's area cut to its clip path.
@(private = "file")
vector_apply_clip :: proc(sh: ^Vector_Shape, tol: f32, area: ^Vector_Polys) -> bool {
	if sh.clip == nil do return true
	tmp := Vector_Shape{path = sh.clip.path, style = VECTOR_STYLE_DEFAULT}
	tmp.style.fillRule = sh.clip.rule
	region: Vector_Polys
	region.pts = make([dynamic][2]f32, context.temp_allocator)
	region.rings = make([dynamic]Vector_Ring, context.temp_allocator)
	if !Vector_FillArea(&tmp, tol, &region) do return false
	cut: Vector_Polys
	cut.pts = make([dynamic][2]f32, context.temp_allocator)
	cut.rings = make([dynamic]Vector_Ring, context.temp_allocator)
	if !Vector_PolysBoolean(.Intersect, area, &region, tol, &cut) do return false
	Vector_Polys_Clear(area)
	for r, i in cut.rings do Vector_PolysAddRing(area, Vector_Polys_Ring(&cut, i), r.parent)
	return true
}

// Vector_ShapesArea: everything some shapes cover - fills and stroke
// outlines (each clipped by its clip path), united.
Vector_ShapesArea :: proc(shapes: []Vector_Shape, tol: f32, out: ^Vector_Polys, fills := true, strokes := true) -> bool {
	acc: Vector_Polys
	acc.pts = make([dynamic][2]f32, context.temp_allocator)
	acc.rings = make([dynamic]Vector_Ring, context.temp_allocator)
	part: Vector_Polys
	part.pts = make([dynamic][2]f32, context.temp_allocator)
	part.rings = make([dynamic]Vector_Ring, context.temp_allocator)
	add :: proc(acc, part: ^Vector_Polys) {
		base := len(acc.rings)
		for r, i in part.rings do Vector_PolysAddRing(acc, Vector_Polys_Ring(part, i), r.parent + base if r.parent >= 0 else -1)
	}
	for &sh in shapes {
		if fills && sh.style.fill && Vector_FillArea(&sh, tol, &part) do add(&acc, &part)
		if strokes && sh.style.stroke && Vector_StrokeOutline(&sh, tol, &part) && vector_apply_clip(&sh, tol, &part) do add(&acc, &part)
	}
	// (Normalized rings: outers one way, holes the other - non-zero unites them.)
	return Vector_PolysNormalize(&acc, .NonZero, tol, out)
}

// Vector_PolysSimplify drops points closer than tol to the line through
// their neighbours (Ramer-Douglas-Peucker per ring), then re-normalizes;
// rings that shrink to nothing go.
Vector_PolysSimplify :: proc(p: ^Vector_Polys, tol: f32, out: ^Vector_Polys) -> bool {
	tmp: Vector_Polys
	tmp.pts = make([dynamic][2]f32, context.temp_allocator)
	tmp.rings = make([dynamic]Vector_Ring, context.temp_allocator)
	for r, i in p.rings {
		ring := Vector_Polys_Ring(p, i)
		keep := make([]bool, len(ring), context.temp_allocator)
		// Split the ring at its first point and the point farthest from it.
		far, farD := 0, f32(-1)
		for q, k in ring {
			d := (q - ring[0]).x * (q - ring[0]).x + (q - ring[0]).y * (q - ring[0]).y
			if d > farD {far, farD = k, d}
		}
		keep[0], keep[far] = true, true
		rdp(ring, 0, far, tol, keep)
		rdp(ring, far, len(ring), tol, keep) // (wraps to 0)
		kept := make([dynamic][2]f32, context.temp_allocator)
		for q, k in ring do if keep[k] do append(&kept, q)
		if len(kept) < 3 || abs(Vector_SignedArea(kept[:])) * 0.5 < tol * tol do continue
		Vector_PolysAddRing(&tmp, kept[:], r.parent)
	}
	return Vector_PolysNormalize(&tmp, .NonZero, tol, out)
}

// rdp marks the points of ring[a..b] (b may equal len: the first point)
// that stay further than tol from the chord.
@(private = "file")
rdp :: proc(ring: [][2]f32, a, b: int, tol: f32, keep: []bool) {
	if b - a < 2 do return
	pa, pb := ring[a], ring[b % len(ring)]
	ab := pb - pa
	l := math.sqrt(ab.x * ab.x + ab.y * ab.y)
	best, bestD := -1, tol
	for k in a + 1 ..< b {
		q := ring[k]
		d: f32
		if l < 1e-9 do d = math.sqrt((q - pa).x * (q - pa).x + (q - pa).y * (q - pa).y)
		else do d = abs(ab.x * (pa.y - q.y) - ab.y * (pa.x - q.x)) / l
		if d > bestD {best, bestD = k, d}
	}
	if best < 0 do return
	keep[best] = true
	rdp(ring, a, best, tol, keep)
	rdp(ring, best, b, tol, keep)
}

// Vector_PolysToPath: the rings as a path of lines (closed subpaths).
Vector_PolysToPath :: proc(p: ^Vector_Polys, out: ^Vector_Path) {
	for _, i in p.rings {
		ring := Vector_Polys_Ring(p, i)
		Vector_MoveTo(out, ring[0])
		for q in ring[1:] do Vector_LineTo(out, q)
		Vector_Close(out)
	}
}

// Vector_PathFlatten: a path with its curves turned into lines within tol.
Vector_PathFlatten :: proc(path: ^Vector_Path, tol: f32, out: ^Vector_Path) {
	flat: Vector_Flat
	flat.pts = make([dynamic][2]f32, context.temp_allocator)
	flat.contours = make([dynamic]Vector_Contour, context.temp_allocator)
	Vector_Flatten(path, tol, &flat)
	for c in flat.contours {
		pts := Vector_Contour_Points(&flat, c)
		Vector_MoveTo(out, pts[0])
		for q in pts[1:] do Vector_LineTo(out, q)
		if c.closed do Vector_Close(out)
	}
}

// Vector_ShapesBoolean: the area of a op the area of b as one path
// (fills and strokes both count).
Vector_ShapesBoolean :: proc(op: Vector_Bool_Op, a, b: []Vector_Shape, tol: f32, out: ^Vector_Path) -> bool {
	pa, pb, r: Vector_Polys
	for p in ([]^Vector_Polys{&pa, &pb, &r}) {
		p.pts = make([dynamic][2]f32, context.temp_allocator)
		p.rings = make([dynamic]Vector_Ring, context.temp_allocator)
	}
	if !Vector_ShapesArea(a, tol, &pa) || !Vector_ShapesArea(b, tol, &pb) do return false
	if !Vector_PolysBoolean(op, &pa, &pb, tol, &r) do return false
	Vector_PolysToPath(&r, out)
	return true
}

// Vector_ShapesCut removes an area from a drawing, shape by shape, keeping
// each one's paint: a fill becomes its area minus the cut, a stroke its
// outline minus the cut (filled with the stroke's paint). Shapes left empty
// go. Paths are made with `allocator` (old ones freed).
Vector_ShapesCut :: proc(shapes: ^[dynamic]Vector_Shape, cut: ^Vector_Polys, tol: f32, allocator := context.allocator) {
	out := make([dynamic]Vector_Shape, context.temp_allocator)
	part, left: Vector_Polys
	for p in ([]^Vector_Polys{&part, &left}) {
		p.pts = make([dynamic][2]f32, context.temp_allocator)
		p.rings = make([dynamic]Vector_Ring, context.temp_allocator)
	}
	emit :: proc(out: ^[dynamic]Vector_Shape, left: ^Vector_Polys, style: Vector_Style, allocator: runtime.Allocator) {
		if len(left.rings) == 0 do return
		s := Vector_Shape{style = style}
		Vector_Path_Init(&s.path, allocator)
		Vector_PolysToPath(left, &s.path)
		append(out, s)
	}
	for &sh in shapes {
		if sh.style.fill && Vector_FillArea(&sh, tol, &part) && Vector_PolysBoolean(.Subtract, &part, cut, tol, &left) {
			st := sh.style
			st.stroke = false
			st.fillRule = .NonZero
			emit(&out, &left, st, allocator)
		}
		if sh.style.stroke && Vector_StrokeOutline(&sh, tol, &part) && vector_apply_clip(&sh, tol, &part) && Vector_PolysBoolean(.Subtract, &part, cut, tol, &left) {
			st := sh.style
			st.fill, st.stroke = true, false
			st.fillColor, st.fillPaint, st.fillRule = st.strokeColor, st.strokePaint, .NonZero
			emit(&out, &left, st, allocator)
		}
		Vector_Path_Destroy(&sh.path)
	}
	clear(shapes)
	append(shapes, ..out[:])
}

