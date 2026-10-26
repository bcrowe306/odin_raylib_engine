package engine

import "core:math"

// ============================================================================
// Polygon triangulation: a port of Mapbox's earcut (v2.2.4, ISC license -
// licenses/THIRD_PARTY_NOTICES.txt). Triangulates a polygon with holes by
// ear clipping, z-order hashed for large polygons (fast) and with fallbacks
// for bad input (self-touching outlines, degenerate holes).
//
//   Earcut_Triangulate(&ec, coords, holeStarts, &indices)
//
// coords are x, y pairs: the outer ring, then each hole (holeStarts: the
// vertex index each hole begins at). Indices into coords' vertices are
// appended to `indices` (u32 triples). Earcut keeps its node pool between
// calls (Earcut_Destroy frees it): no allocation per triangle.
// ============================================================================

EC_NIL :: i32(-1)

@(private = "file")
EC_Node :: struct {
	i:            u32, // vertex index
	x, y:         f64,
	prev, next:   i32,
	z:            i32,
	prevZ, nextZ: i32,
	steiner:      bool,
}

Earcut :: struct {
	nodes:   [dynamic]EC_Node,
	queue:   [dynamic]i32,
	out:     ^[dynamic]u32,
	minX:    f64,
	minY:    f64,
	invSize: f64,
}

Earcut_Destroy :: proc(ec: ^Earcut) {
	delete(ec.nodes)
	delete(ec.queue)
	ec^ = {}
}

// Earcut_Triangulate appends the triangles of the polygon (outer ring +
// holes) to `out`; returns false when the outer ring has fewer than 3 points.
Earcut_Triangulate :: proc(ec: ^Earcut, coords: [][2]f32, holeStarts: []int, out: ^[dynamic]u32) -> bool {
	clear(&ec.nodes)
	clear(&ec.queue)
	ec.out = out
	n := len(coords)
	outerLen := holeStarts[0] if len(holeStarts) > 0 else n
	outer := ec_linked_list(ec, coords, 0, outerLen, true)
	if outer == EC_NIL || N(ec, outer).next == N(ec, outer).prev do return false
	if len(holeStarts) > 0 do outer = ec_eliminate_holes(ec, coords, holeStarts, outer)
	ec.invSize = 0
	if n > 80 {
		minX, minY := f64(coords[0].x), f64(coords[0].y)
		maxX, maxY := minX, minY
		for p in coords[1:outerLen] {
			minX = min(minX, f64(p.x)); minY = min(minY, f64(p.y))
			maxX = max(maxX, f64(p.x)); maxY = max(maxY, f64(p.y))
		}
		ec.minX, ec.minY = minX, minY
		size := max(maxX - minX, maxY - minY)
		ec.invSize = 32767 / size if size != 0 else 0
	}
	ec_earcut_linked(ec, outer, 0)
	return true
}

@(private = "file")
N :: #force_inline proc(ec: ^Earcut, i: i32) -> ^EC_Node {return &ec.nodes[i]}

@(private = "file")
ec_signed_area :: proc(coords: [][2]f32, start, end: int) -> f64 {
	sum: f64
	j := end - 1
	for i in start ..< end {
		sum += (f64(coords[j].x) - f64(coords[i].x)) * (f64(coords[i].y) + f64(coords[j].y))
		j = i
	}
	return sum
}

@(private = "file")
ec_linked_list :: proc(ec: ^Earcut, coords: [][2]f32, start, end: int, clockwise: bool) -> i32 {
	last := EC_NIL
	if clockwise == (ec_signed_area(coords, start, end) > 0) {
		for i in start ..< end do last = ec_insert(ec, u32(i), coords[i], last)
	} else {
		for i := end - 1; i >= start; i -= 1 do last = ec_insert(ec, u32(i), coords[i], last)
	}
	if last != EC_NIL && ec_equals(ec, last, N(ec, last).next) {
		nx := N(ec, last).next
		ec_remove(ec, last)
		last = nx
	}
	return last
}

@(private = "file")
ec_filter_points :: proc(ec: ^Earcut, start: i32, end_: i32 = EC_NIL) -> i32 {
	if start == EC_NIL do return start
	end := end_ if end_ != EC_NIL else start
	p := start
	for {
		again := false
		pn := N(ec, p)
		if !pn.steiner && (ec_equals(ec, p, pn.next) || ec_area(ec, pn.prev, p, pn.next) == 0) {
			ec_remove(ec, p)
			p = pn.prev
			end = p
			if p == N(ec, p).next do break
			again = true
		} else {
			p = pn.next
		}
		if !again && p == end do break
	}
	return end
}

@(private = "file")
ec_earcut_linked :: proc(ec: ^Earcut, ear_: i32, pass: int) {
	ear := ear_
	if ear == EC_NIL do return
	if pass == 0 && ec.invSize != 0 do ec_index_curve(ec, ear)
	stop := ear
	for N(ec, ear).prev != N(ec, ear).next {
		prev, next := N(ec, ear).prev, N(ec, ear).next
		if ec.invSize != 0 ? ec_is_ear_hashed(ec, ear) : ec_is_ear(ec, ear) {
			append(ec.out, N(ec, prev).i, N(ec, ear).i, N(ec, next).i)
			ec_remove(ec, ear)
			ear = N(ec, next).next
			stop = ear
			continue
		}
		ear = next
		if ear == stop {
			switch pass {
			case 0:
				ec_earcut_linked(ec, ec_filter_points(ec, ear), 1)
			case 1:
				ear = ec_cure_local_intersections(ec, ec_filter_points(ec, ear))
				ec_earcut_linked(ec, ear, 2)
			case 2:
				ec_split_earcut(ec, ear)
			}
			break
		}
	}
}

@(private = "file")
ec_is_ear :: proc(ec: ^Earcut, ear: i32) -> bool {
	b := N(ec, ear)
	a, c := N(ec, b.prev), N(ec, b.next)
	if ec_area_n(a, b, c) >= 0 do return false // reflex
	x0, x1 := min(a.x, b.x, c.x), max(a.x, b.x, c.x)
	y0, y1 := min(a.y, b.y, c.y), max(a.y, b.y, c.y)
	p := c.next
	for p != b.prev {
		pn := N(ec, p)
		if pn.x >= x0 && pn.x <= x1 && pn.y >= y0 && pn.y <= y1 &&
		   ec_point_in_triangle(a.x, a.y, b.x, b.y, c.x, c.y, pn.x, pn.y) &&
		   ec_area(ec, pn.prev, p, pn.next) >= 0 {
			return false
		}
		p = pn.next
	}
	return true
}

@(private = "file")
ec_is_ear_hashed :: proc(ec: ^Earcut, ear: i32) -> bool {
	b := N(ec, ear)
	ai, ci := b.prev, b.next
	a, c := N(ec, ai), N(ec, ci)
	if ec_area_n(a, b, c) >= 0 do return false
	x0, x1 := min(a.x, b.x, c.x), max(a.x, b.x, c.x)
	y0, y1 := min(a.y, b.y, c.y), max(a.y, b.y, c.y)
	minZ := ec_z_order(ec, x0, y0)
	maxZ := ec_z_order(ec, x1, y1)
	blocks :: proc(ec: ^Earcut, q: i32, ai, ci: i32, a, b, c: ^EC_Node, x0, x1, y0, y1: f64) -> bool {
		qn := N(ec, q)
		return qn.x >= x0 && qn.x <= x1 && qn.y >= y0 && qn.y <= y1 && q != ai && q != ci &&
			ec_point_in_triangle(a.x, a.y, b.x, b.y, c.x, c.y, qn.x, qn.y) && ec_area(ec, qn.prev, q, qn.next) >= 0
	}
	p, n := b.prevZ, b.nextZ
	for p != EC_NIL && N(ec, p).z >= minZ && n != EC_NIL && N(ec, n).z <= maxZ {
		if blocks(ec, p, ai, ci, a, b, c, x0, x1, y0, y1) do return false
		p = N(ec, p).prevZ
		if blocks(ec, n, ai, ci, a, b, c, x0, x1, y0, y1) do return false
		n = N(ec, n).nextZ
	}
	for p != EC_NIL && N(ec, p).z >= minZ {
		if blocks(ec, p, ai, ci, a, b, c, x0, x1, y0, y1) do return false
		p = N(ec, p).prevZ
	}
	for n != EC_NIL && N(ec, n).z <= maxZ {
		if blocks(ec, n, ai, ci, a, b, c, x0, x1, y0, y1) do return false
		n = N(ec, n).nextZ
	}
	return true
}

@(private = "file")
ec_cure_local_intersections :: proc(ec: ^Earcut, start_: i32) -> i32 {
	start := start_
	p := start
	for {
		a := N(ec, p).prev
		b := N(ec, N(ec, p).next).next
		if !ec_equals(ec, a, b) && ec_intersects(ec, a, p, N(ec, p).next, b) && ec_locally_inside(ec, a, b) && ec_locally_inside(ec, b, a) {
			append(ec.out, N(ec, a).i, N(ec, p).i, N(ec, b).i)
			pnext := N(ec, p).next
			ec_remove(ec, p)
			ec_remove(ec, pnext)
			p = b
			start = b
		}
		p = N(ec, p).next
		if p == start do break
	}
	return ec_filter_points(ec, p)
}

@(private = "file")
ec_split_earcut :: proc(ec: ^Earcut, start: i32) {
	a := start
	for {
		b := N(ec, N(ec, a).next).next
		for b != N(ec, a).prev {
			if N(ec, a).i != N(ec, b).i && ec_is_valid_diagonal(ec, a, b) {
				c := ec_split_polygon(ec, a, b)
				a = ec_filter_points(ec, a, N(ec, a).next)
				c = ec_filter_points(ec, c, N(ec, c).next)
				ec_earcut_linked(ec, a, 0)
				ec_earcut_linked(ec, c, 0)
				return
			}
			b = N(ec, b).next
		}
		a = N(ec, a).next
		if a == start do break
	}
}

@(private = "file")
ec_eliminate_holes :: proc(ec: ^Earcut, coords: [][2]f32, holeStarts: []int, outer_: i32) -> i32 {
	outer := outer_
	for h, i in holeStarts {
		start := h
		end := holeStarts[i + 1] if i < len(holeStarts) - 1 else len(coords)
		list := ec_linked_list(ec, coords, start, end, false)
		if list == EC_NIL do continue
		if list == N(ec, list).next do N(ec, list).steiner = true
		append(&ec.queue, ec_get_leftmost(ec, list))
	}
	ec_sort_queue_by_x(ec) // (by x; ties keep their order)
	for q in ec.queue do outer = ec_eliminate_hole(ec, q, outer)
	return outer
}

@(private = "file")
ec_sort_queue_by_x :: proc(ec: ^Earcut) {
	// Insertion sort (holes are few; stable).
	q := ec.queue[:]
	for i in 1 ..< len(q) {
		v := q[i]
		j := i - 1
		for j >= 0 && N(ec, q[j]).x > N(ec, v).x {
			q[j + 1] = q[j]
			j -= 1
		}
		q[j + 1] = v
	}
}

@(private = "file")
ec_eliminate_hole :: proc(ec: ^Earcut, hole, outer: i32) -> i32 {
	bridge := ec_find_hole_bridge(ec, hole, outer)
	if bridge == EC_NIL do return outer
	bridgeReverse := ec_split_polygon(ec, bridge, hole)
	ec_filter_points(ec, bridgeReverse, N(ec, bridgeReverse).next)
	return ec_filter_points(ec, bridge, N(ec, bridge).next)
}

@(private = "file")
ec_find_hole_bridge :: proc(ec: ^Earcut, hole, outer: i32) -> i32 {
	p := outer
	hx, hy := N(ec, hole).x, N(ec, hole).y
	qx := math.inf_f64(-1)
	m := EC_NIL
	for {
		pn := N(ec, p)
		nn := N(ec, pn.next)
		if hy <= pn.y && hy >= nn.y && nn.y != pn.y {
			x := pn.x + (hy - pn.y) * (nn.x - pn.x) / (nn.y - pn.y)
			if x <= hx && x > qx {
				qx = x
				m = p if pn.x < nn.x else pn.next
				if x == hx do return m
			}
		}
		p = pn.next
		if p == outer do break
	}
	if m == EC_NIL do return EC_NIL
	stop := m
	mx, my := N(ec, m).x, N(ec, m).y
	tanMin := math.inf_f64(1)
	p = m
	for {
		pn := N(ec, p)
		if hx >= pn.x && pn.x >= mx && hx != pn.x &&
		   ec_point_in_triangle(hx if hy < my else qx, hy, mx, my, qx if hy < my else hx, hy, pn.x, pn.y) {
			tan := abs(hy - pn.y) / (hx - pn.x)
			mn := N(ec, m)
			if ec_locally_inside(ec, p, hole) &&
			   (tan < tanMin || (tan == tanMin && (pn.x > mn.x || (pn.x == mn.x && ec_sector_contains_sector(ec, m, p))))) {
				m = p
				tanMin = tan
			}
		}
		p = pn.next
		if p == stop do break
	}
	return m
}

@(private = "file")
ec_sector_contains_sector :: proc(ec: ^Earcut, m, p: i32) -> bool {
	mn, pn := N(ec, m), N(ec, p)
	return ec_area(ec, mn.prev, m, pn.prev) < 0 && ec_area(ec, pn.next, m, mn.next) < 0
}

@(private = "file")
ec_index_curve :: proc(ec: ^Earcut, start: i32) {
	p := start
	for {
		pn := N(ec, p)
		if pn.z == 0 do pn.z = ec_z_order(ec, pn.x, pn.y)
		pn.prevZ = pn.prev
		pn.nextZ = pn.next
		p = pn.next
		if p == start do break
	}
	N(ec, N(ec, p).prevZ).nextZ = EC_NIL
	N(ec, p).prevZ = EC_NIL
	ec_sort_linked(ec, p)
}

// Simon Tatham's linked-list merge sort on z.
@(private = "file")
ec_sort_linked :: proc(ec: ^Earcut, list_: i32) -> i32 {
	list := list_
	inSize := 1
	for {
		p := list
		list = EC_NIL
		tail := EC_NIL
		numMerges := 0
		for p != EC_NIL {
			numMerges += 1
			q := p
			pSize := 0
			for _ in 0 ..< inSize {
				pSize += 1
				q = N(ec, q).nextZ
				if q == EC_NIL do break
			}
			qSize := inSize
			for pSize > 0 || (qSize > 0 && q != EC_NIL) {
				e: i32
				if pSize != 0 && (qSize == 0 || q == EC_NIL || N(ec, p).z <= N(ec, q).z) {
					e = p; p = N(ec, p).nextZ; pSize -= 1
				} else {
					e = q; q = N(ec, q).nextZ; qSize -= 1
				}
				if tail != EC_NIL do N(ec, tail).nextZ = e
				else do list = e
				N(ec, e).prevZ = tail
				tail = e
			}
			p = q
		}
		N(ec, tail).nextZ = EC_NIL
		inSize *= 2
		if numMerges <= 1 do break
	}
	return list
}

@(private = "file")
ec_z_order :: proc(ec: ^Earcut, fx, fy: f64) -> i32 {
	x := u32(i32((fx - ec.minX) * ec.invSize))
	y := u32(i32((fy - ec.minY) * ec.invSize))
	x = (x | (x << 8)) & 0x00FF00FF
	x = (x | (x << 4)) & 0x0F0F0F0F
	x = (x | (x << 2)) & 0x33333333
	x = (x | (x << 1)) & 0x55555555
	y = (y | (y << 8)) & 0x00FF00FF
	y = (y | (y << 4)) & 0x0F0F0F0F
	y = (y | (y << 2)) & 0x33333333
	y = (y | (y << 1)) & 0x55555555
	return i32(x | (y << 1))
}

@(private = "file")
ec_get_leftmost :: proc(ec: ^Earcut, start: i32) -> i32 {
	p := start
	leftmost := start
	for {
		pn, ln := N(ec, p), N(ec, leftmost)
		if pn.x < ln.x || (pn.x == ln.x && pn.y < ln.y) do leftmost = p
		p = pn.next
		if p == start do break
	}
	return leftmost
}

@(private = "file")
ec_point_in_triangle :: proc(ax, ay, bx, by, cx, cy, px, py: f64) -> bool {
	return (cx - px) * (ay - py) >= (ax - px) * (cy - py) &&
		(ax - px) * (by - py) >= (bx - px) * (ay - py) &&
		(bx - px) * (cy - py) >= (cx - px) * (by - py)
}

@(private = "file")
ec_is_valid_diagonal :: proc(ec: ^Earcut, a, b: i32) -> bool {
	an, bn := N(ec, a), N(ec, b)
	return N(ec, an.next).i != bn.i && N(ec, an.prev).i != bn.i && !ec_intersects_polygon(ec, a, b) &&
		((ec_locally_inside(ec, a, b) && ec_locally_inside(ec, b, a) && ec_middle_inside(ec, a, b) &&
				(ec_area(ec, an.prev, a, bn.prev) != 0 || ec_area(ec, a, bn.prev, b) != 0)) ||
			(ec_equals(ec, a, b) && ec_area(ec, an.prev, a, an.next) > 0 && ec_area(ec, bn.prev, b, bn.next) > 0))
}

@(private = "file")
ec_area_n :: #force_inline proc(p, q, r: ^EC_Node) -> f64 {
	return (q.y - p.y) * (r.x - q.x) - (q.x - p.x) * (r.y - q.y)
}

@(private = "file")
ec_area :: #force_inline proc(ec: ^Earcut, p, q, r: i32) -> f64 {
	return ec_area_n(N(ec, p), N(ec, q), N(ec, r))
}

@(private = "file")
ec_equals :: #force_inline proc(ec: ^Earcut, a, b: i32) -> bool {
	an, bn := N(ec, a), N(ec, b)
	return an.x == bn.x && an.y == bn.y
}

@(private = "file")
ec_sign :: #force_inline proc(v: f64) -> int {return 1 if v > 0 else (-1 if v < 0 else 0)}

@(private = "file")
ec_on_segment :: proc(p, q, r: ^EC_Node) -> bool {
	return q.x <= max(p.x, r.x) && q.x >= min(p.x, r.x) && q.y <= max(p.y, r.y) && q.y >= min(p.y, r.y)
}

@(private = "file")
ec_intersects :: proc(ec: ^Earcut, p1i, q1i, p2i, q2i: i32) -> bool {
	p1, q1, p2, q2 := N(ec, p1i), N(ec, q1i), N(ec, p2i), N(ec, q2i)
	o1 := ec_sign(ec_area_n(p1, q1, p2))
	o2 := ec_sign(ec_area_n(p1, q1, q2))
	o3 := ec_sign(ec_area_n(p2, q2, p1))
	o4 := ec_sign(ec_area_n(p2, q2, q1))
	if o1 != o2 && o3 != o4 do return true
	if o1 == 0 && ec_on_segment(p1, p2, q1) do return true
	if o2 == 0 && ec_on_segment(p1, q2, q1) do return true
	if o3 == 0 && ec_on_segment(p2, p1, q2) do return true
	if o4 == 0 && ec_on_segment(p2, q1, q2) do return true
	return false
}

@(private = "file")
ec_intersects_polygon :: proc(ec: ^Earcut, a, b: i32) -> bool {
	p := a
	ai, bi := N(ec, a).i, N(ec, b).i
	for {
		pn := N(ec, p)
		ni := N(ec, pn.next).i
		if pn.i != ai && ni != ai && pn.i != bi && ni != bi && ec_intersects(ec, p, pn.next, a, b) do return true
		p = pn.next
		if p == a do break
	}
	return false
}

@(private = "file")
ec_locally_inside :: proc(ec: ^Earcut, a, b: i32) -> bool {
	an := N(ec, a)
	if ec_area(ec, an.prev, a, an.next) < 0 {
		return ec_area(ec, a, b, an.next) >= 0 && ec_area(ec, a, an.prev, b) >= 0
	}
	return ec_area(ec, a, b, an.prev) < 0 || ec_area(ec, a, an.next, b) < 0
}

@(private = "file")
ec_middle_inside :: proc(ec: ^Earcut, a, b: i32) -> bool {
	p := a
	inside := false
	px := (N(ec, a).x + N(ec, b).x) / 2
	py := (N(ec, a).y + N(ec, b).y) / 2
	for {
		pn := N(ec, p)
		nn := N(ec, pn.next)
		if (pn.y > py) != (nn.y > py) && nn.y != pn.y && px < (nn.x - pn.x) * (py - pn.y) / (nn.y - pn.y) + pn.x do inside = !inside
		p = pn.next
		if p == a do break
	}
	return inside
}

@(private = "file")
ec_split_polygon :: proc(ec: ^Earcut, a, b: i32) -> i32 {
	an, bn := N(ec, a)^, N(ec, b)^
	a2 := ec_new(ec, an.i, an.x, an.y)
	b2 := ec_new(ec, bn.i, bn.x, bn.y)
	anext := N(ec, a).next
	bprev := N(ec, b).prev
	N(ec, a).next = b; N(ec, b).prev = a
	N(ec, a2).next = anext; N(ec, anext).prev = a2
	N(ec, b2).next = a2; N(ec, a2).prev = b2
	N(ec, bprev).next = b2; N(ec, b2).prev = bprev
	return b2
}

@(private = "file")
ec_new :: proc(ec: ^Earcut, i: u32, x, y: f64) -> i32 {
	append(&ec.nodes, EC_Node{i = i, x = x, y = y, prev = EC_NIL, next = EC_NIL, prevZ = EC_NIL, nextZ = EC_NIL})
	return i32(len(ec.nodes) - 1)
}

@(private = "file")
ec_insert :: proc(ec: ^Earcut, i: u32, pt: [2]f32, last: i32) -> i32 {
	p := ec_new(ec, i, f64(pt.x), f64(pt.y))
	if last == EC_NIL {
		N(ec, p).prev = p
		N(ec, p).next = p
	} else {
		ln := N(ec, last)
		N(ec, p).next = ln.next
		N(ec, p).prev = last
		N(ec, ln.next).prev = p
		ln.next = p
	}
	return p
}

@(private = "file")
ec_remove :: proc(ec: ^Earcut, p: i32) {
	pn := N(ec, p)
	N(ec, pn.next).prev = pn.prev
	N(ec, pn.prev).next = pn.next
	if pn.prevZ != EC_NIL do N(ec, pn.prevZ).nextZ = pn.nextZ
	if pn.nextZ != EC_NIL do N(ec, pn.nextZ).prevZ = pn.prevZ
}
