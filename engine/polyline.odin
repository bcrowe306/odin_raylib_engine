package engine

import "core:math"

// ============================================================================
// Measured polylines: points with the cumulative length at each, for
// queries by distance along a curve - the point and direction at a
// distance, the closest point - shared by PathNode (its baked curve) and
// VectorShapeNode (its drawing's subpaths, one after another: vector_
// collider.odin). Between subpaths the length doesn't grow (a jump, never
// sampled or matched).
// ============================================================================

Polyline :: struct {
	pts:  [dynamic][2]f32,
	lens: [dynamic]f32, // cumulative length at each point
}

Polyline_Destroy :: proc(p: ^Polyline) {
	delete(p.pts)
	delete(p.lens)
	p^ = {}
}

Polyline_Clear :: proc(p: ^Polyline) {
	clear(&p.pts)
	clear(&p.lens)
}

// Polyline_Add appends a point; jump = true starts a new piece (no length
// from the previous point).
Polyline_Add :: proc(p: ^Polyline, q: [2]f32, jump := false) {
	total: f32 = 0
	if n := len(p.pts); n > 0 {
		total = p.lens[n - 1]
		if !jump {
			d := q - p.pts[n - 1]
			total += math.sqrt(d.x * d.x + d.y * d.y)
		}
	}
	append(&p.pts, q)
	append(&p.lens, total)
}

Polyline_Length :: proc(pts: [][2]f32, lens: []f32) -> f32 {
	return lens[len(lens) - 1] if len(lens) > 0 else 0
}

// Polyline_Sample: the point at `dist` along (clamped) and the unit
// direction there.
Polyline_Sample :: proc(pts: [][2]f32, lens: []f32, dist: f32) -> (pos, dir: [2]f32) {
	n := len(pts)
	if n == 0 do return {}, {1, 0}
	if n == 1 do return pts[0], {1, 0}
	d := clamp(dist, 0, lens[n - 1])
	lo, hi := 0, n - 1
	for hi - lo > 1 {
		mid := (lo + hi) / 2
		if lens[mid] <= d do lo = mid
		else do hi = mid
	}
	// (A jump: step past it to the piece's first real segment.)
	for hi < n - 1 && lens[hi] == lens[lo] && lens[hi] <= d {lo += 1; hi += 1}
	seg := lens[hi] - lens[lo]
	t := (d - lens[lo]) / seg if seg > 0 else 0
	a, b := pts[lo], pts[hi]
	pos = a + (b - a) * t
	l := math.sqrt((b - a).x * (b - a).x + (b - a).y * (b - a).y)
	dir = (b - a) / l if l > 0 && seg > 0 else {1, 0}
	return
}

// Polyline_Closest: the distance along of the point nearest to q, and
// that point.
Polyline_Closest :: proc(pts: [][2]f32, lens: []f32, q: [2]f32) -> (dist: f32, at: [2]f32) {
	if len(pts) == 1 do return 0, pts[0]
	bestD := max(f32)
	for i in 0 ..< len(pts) - 1 {
		if lens[i + 1] == lens[i] do continue // (a jump between pieces)
		a, b := pts[i], pts[i + 1]
		ab := b - a
		ll := ab.x * ab.x + ab.y * ab.y
		t := clamp(((q.x - a.x) * ab.x + (q.y - a.y) * ab.y) / ll, 0, 1) if ll > 0 else 0
		c := a + ab * t
		d := (q.x - c.x) * (q.x - c.x) + (q.y - c.y) * (q.y - c.y)
		if d < bestD {
			bestD = d
			dist = lens[i] + (lens[i + 1] - lens[i]) * t
			at = c
		}
	}
	return
}
