package engine

import "core:math"

// ============================================================================
// Path effects (Phase 14 V.9): trim paths and shape tweens.
//
// Both work on paths as cubic segments (lines and quads converted exactly),
// grouped into subpaths:
// - Trim keeps a fraction of a path's length (start / end / offset, like
//   After Effects' Trim Paths): draw-on lines, progress rings, effects.
// - Morph interpolates one path into another (Flash's shape tweens):
//   subpaths paired in order (missing ones grow from / shrink to a point),
//   segment counts evened by splitting the longest segments, closed
//   subpaths turned the same way and started at the closest points (the
//   automatic shape hint), then every point interpolated. Styles blend too:
//   colours, widths, opacity, gradients with matching stops.
// ============================================================================

@(private = "file")
Seg :: [4][2]f32 // p0, c1, c2, p3

@(private = "file")
Sub :: struct {
	segs:   [dynamic]Seg,
	closed: bool,
}

// to_subs: a path as cubic subpaths (temp memory).
@(private = "file")
to_subs :: proc(path: ^Vector_Path) -> [dynamic]Sub {
	subs := make([dynamic]Sub, context.temp_allocator)
	cur, start: [2]f32
	open := false
	begin :: proc(subs: ^[dynamic]Sub, at: [2]f32) {
		append(subs, Sub{segs = make([dynamic]Seg, context.temp_allocator)})
	}
	add :: proc(subs: ^[dynamic]Sub, open: ^bool, start: ^[2]f32, cur: [2]f32, s: Seg) {
		if !open^ {
			begin(subs, cur)
			start^ = cur
			open^ = true
		}
		append(&subs[len(subs) - 1].segs, s)
	}
	pi := 0
	for c in path.cmds {
		switch c {
		case .Move:
			cur = path.pts[pi]
			start = cur
			pi += 1
			open = false
		case .Line:
			a := path.pts[pi]
			pi += 1
			add(&subs, &open, &start, cur, {cur, cur + (a - cur) / 3, cur + (a - cur) * 2 / 3, a})
			cur = a
		case .Quad:
			q, a := path.pts[pi], path.pts[pi + 1]
			pi += 2
			add(&subs, &open, &start, cur, {cur, cur + (q - cur) * 2 / 3, a + (q - a) * 2 / 3, a})
			cur = a
		case .Cubic:
			c1, c2, a := path.pts[pi], path.pts[pi + 1], path.pts[pi + 2]
			pi += 3
			add(&subs, &open, &start, cur, {cur, c1, c2, a})
			cur = a
		case .Close:
			if open {
				if cur != start do append(&subs[len(subs) - 1].segs, Seg{cur, cur + (start - cur) / 3, cur + (start - cur) * 2 / 3, start})
				subs[len(subs) - 1].closed = true
			}
			cur = start
			open = false
		}
	}
	return subs
}

@(private = "file")
from_subs :: proc(subs: []Sub, out: ^Vector_Path) {
	for s in subs {
		if len(s.segs) == 0 do continue
		Vector_MoveTo(out, s.segs[0][0])
		for g in s.segs do Vector_CubicTo(out, g[1], g[2], g[3])
		if s.closed do Vector_Close(out)
	}
}

@(private = "file")
seg_at :: proc(s: Seg, t: f32) -> [2]f32 {
	u := 1 - t
	return u * u * u * s[0] + 3 * u * u * t * s[1] + 3 * u * t * t * s[2] + t * t * t * s[3]
}

LENGTH_STEPS :: 24

@(private = "file")
seg_length :: proc(s: Seg) -> f32 {
	l: f32
	prev := s[0]
	for i in 1 ..= LENGTH_STEPS {
		p := seg_at(s, f32(i) / LENGTH_STEPS)
		l += math.sqrt((p.x - prev.x) * (p.x - prev.x) + (p.y - prev.y) * (p.y - prev.y))
		prev = p
	}
	return l
}

// seg_param: the parameter at a length along a segment (by its sampled
// arc length).
@(private = "file")
seg_param :: proc(s: Seg, length: f32) -> f32 {
	if length <= 0 do return 0
	l: f32
	prev := s[0]
	for i in 1 ..= LENGTH_STEPS {
		p := seg_at(s, f32(i) / LENGTH_STEPS)
		d := math.sqrt((p.x - prev.x) * (p.x - prev.x) + (p.y - prev.y) * (p.y - prev.y))
		if l + d >= length {
			k := (length - l) / d if d > 1e-9 else 0
			return (f32(i - 1) + k) / LENGTH_STEPS
		}
		l += d
		prev = p
	}
	return 1
}

// seg_split: de Casteljau at t.
@(private = "file")
seg_split :: proc(s: Seg, t: f32) -> (a, b: Seg) {
	p01 := math.lerp(s[0], s[1], t)
	p12 := math.lerp(s[1], s[2], t)
	p23 := math.lerp(s[2], s[3], t)
	p012 := math.lerp(p01, p12, t)
	p123 := math.lerp(p12, p23, t)
	m := math.lerp(p012, p123, t)
	return {s[0], p01, p012, m}, {m, p123, p23, s[3]}
}

@(private = "file")
seg_range :: proc(s: Seg, t0, t1: f32) -> Seg {
	if t0 <= 0 && t1 >= 1 do return s
	left, _ := seg_split(s, t1)
	if t0 <= 0 do return left
	_, r := seg_split(left, t0 / t1 if t1 > 1e-9 else 0)
	return r
}

// Vector_PathLength: a path's length (curves sampled).
Vector_PathLength :: proc(path: ^Vector_Path) -> f32 {
	total: f32
	for s in to_subs(path) do for g in s.segs do total += seg_length(g)
	return total
}

// Vector_PathTrim appends the part of a path between start and end (0..1 of
// its whole length, every subpath in turn), moved along by offset (wrapping
// round): out gets open subpaths, or the path itself when all of it is kept.
// each: every subpath trimmed on its own (a ring's two circles drawn on
// together) instead of one after the other.
Vector_PathTrim :: proc(path: ^Vector_Path, start, end, offset: f32, out: ^Vector_Path, each := false) {
	s0, e0 := clamp(min(start, end), 0, 1), clamp(max(start, end), 0, 1)
	if e0 - s0 >= 1 {
		vector_path_append(out, path)
		return
	}
	if e0 - s0 <= 1e-6 do return
	all := to_subs(path)
	if each {
		for i in 0 ..< len(all) do trim_subs(all[i:i + 1], s0, e0, offset, out)
	} else {
		trim_subs(all[:], s0, e0, offset, out)
	}
}

@(private = "file")
trim_subs :: proc(subs: []Sub, s0, e0, offset: f32, out: ^Vector_Path) {
	lens := make([dynamic]f32, context.temp_allocator)
	total: f32
	for s in subs do for g in s.segs {
		l := seg_length(g)
		append(&lens, l)
		total += l
	}
	if total <= 1e-6 do return
	s := s0 + offset
	s -= math.floor(s)
	e := s + (e0 - s0)
	trim_range(subs, lens[:], s * total, min(e, 1) * total, out)
	if e > 1 do trim_range(subs, lens[:], 0, (e - 1) * total, out)
}

@(private = "file")
trim_range :: proc(subs: []Sub, lens: []f32, a, b: f32, out: ^Vector_Path) {
	at: f32
	li := 0
	for s in subs {
		subStart := at
		started := false
		for g in s.segs {
			l := lens[li]
			li += 1
			g0, g1 := at, at + l
			at = g1
			if g1 <= a || g0 >= b || l <= 1e-9 do continue
			t0 := seg_param(g, a - g0) if a > g0 else 0
			t1 := seg_param(g, b - g0) if b < g1 else 1
			piece := seg_range(g, t0, t1)
			if !started {
				Vector_MoveTo(out, piece[0])
				started = true
			}
			Vector_CubicTo(out, piece[1], piece[2], piece[3])
		}
		// All of a closed subpath: still closed.
		if started && s.closed && a <= subStart && b >= at do Vector_Close(out)
	}
}

@(private = "file")
vector_path_append :: proc(out, src: ^Vector_Path) {
	append(&out.cmds, ..src.cmds[:])
	append(&out.pts, ..src.pts[:])
}

// --- morphing --------------------------------------------------------------------------

@(private = "file")
sub_area :: proc(s: Sub) -> f32 {
	a: f32
	for g in s.segs do a += g[0].x * g[3].y - g[3].x * g[0].y
	return a * 0.5
}

@(private = "file")
sub_center :: proc(s: Sub) -> [2]f32 {
	c: [2]f32
	if len(s.segs) == 0 do return c
	for g in s.segs do c += g[0]
	return c / f32(len(s.segs))
}

// sub_even splits the longest segments until there are n.
@(private = "file")
sub_even :: proc(s: ^Sub, n: int) {
	for len(s.segs) < n {
		best, bestLen := 0, f32(-1)
		for g, i in s.segs {
			if l := seg_length(g); l > bestLen {best, bestLen = i, l}
		}
		a, b := seg_split(s.segs[best], 0.5)
		s.segs[best] = a
		inject_at(&s.segs, best + 1, b)
	}
}

@(private = "file")
sub_reverse :: proc(s: ^Sub) {
	n := len(s.segs)
	for i in 0 ..< n / 2 do s.segs[i], s.segs[n - 1 - i] = s.segs[n - 1 - i], s.segs[i]
	for &g in s.segs do g = {g[3], g[2], g[1], g[0]}
}

// sub_align: a closed subpath turned the same way as `to` and started at
// the rotation closest to it (the automatic shape hint).
@(private = "file")
sub_align :: proc(s: ^Sub, to: Sub) {
	if (sub_area(s^) < 0) != (sub_area(to) < 0) do sub_reverse(s)
	n := len(s.segs)
	if n > 96 do return
	best, bestD := 0, f32(math.F32_MAX)
	for r in 0 ..< n {
		d: f32
		for i in 0 ..< n {
			q := s.segs[(i + r) % n][0] - to.segs[i][0]
			d += q.x * q.x + q.y * q.y
		}
		if d < bestD {best, bestD = r, d}
	}
	if best == 0 do return
	rot := make([]Seg, n, context.temp_allocator)
	for i in 0 ..< n do rot[i] = s.segs[(i + best) % n]
	copy(s.segs[:], rot)
}

// point_sub: a subpath of n segments collapsed onto a point.
@(private = "file")
point_sub :: proc(at: [2]f32, n: int, closed: bool) -> Sub {
	s := Sub{segs = make([dynamic]Seg, n, context.temp_allocator), closed = closed}
	for &g in s.segs do g = {at, at, at, at}
	return s
}

// Vector_PathMorph appends the path t of the way from a to b.
Vector_PathMorph :: proc(a, b: ^Vector_Path, t: f32, out: ^Vector_Path) {
	if t <= 0 {vector_path_append(out, a); return}
	if t >= 1 {vector_path_append(out, b); return}
	sa, sb := to_subs(a), to_subs(b)
	n := max(len(sa), len(sb))
	for i in 0 ..< n {
		x, y: Sub
		if i < len(sa) && i < len(sb) {
			x, y = sa[i], sb[i]
		} else if i < len(sa) {
			x = sa[i]
			y = point_sub(sub_center(x), len(x.segs), x.closed)
		} else {
			y = sb[i]
			x = point_sub(sub_center(y), len(y.segs), y.closed)
		}
		if len(x.segs) == 0 || len(y.segs) == 0 do continue
		m := max(len(x.segs), len(y.segs))
		sub_even(&x, m)
		sub_even(&y, m)
		if x.closed && y.closed do sub_align(&y, x)
		Vector_MoveTo(out, math.lerp(x.segs[0][0], y.segs[0][0], t))
		for k in 0 ..< m {
			g, h := x.segs[k], y.segs[k]
			Vector_CubicTo(out, math.lerp(g[1], h[1], t), math.lerp(g[2], h[2], t), math.lerp(g[3], h[3], t))
		}
		if (x.closed if t < 0.5 else y.closed) do Vector_Close(out)
	}
}

@(private = "file")
lerp_color :: proc(a, b: [4]u8, t: f32) -> [4]u8 {
	c: [4]u8
	for i in 0 ..< 4 do c[i] = u8(clamp(f32(a[i]) + (f32(b[i]) - f32(a[i])) * t + 0.5, 0, 255))
	return c
}

// as_gradient: a solid colour as a gradient shaped like `like` (so solid
// <-> gradient blends).
@(private = "file")
as_gradient :: proc(color: [4]u8, like: Vector_Paint) -> Vector_Paint {
	p := like
	for i in 0 ..< int(p.stopCount) do p.stops[i].color = color
	return p
}

@(private = "file")
lerp_paint :: proc(a, b: Vector_Paint, t: f32) -> Vector_Paint {
	if a.kind != b.kind || a.stopCount != b.stopCount do return a if t < 0.5 else b
	p := a if t < 0.5 else b
	for i in 0 ..< int(a.stopCount) {
		p.stops[i] = {math.lerp(a.stops[i].offset, b.stops[i].offset, t), lerp_color(a.stops[i].color, b.stops[i].color, t)}
	}
	p.p0, p.p1 = math.lerp(a.p0, b.p0, t), math.lerp(a.p1, b.p1, t)
	p.center, p.radius = math.lerp(a.center, b.center, t), math.lerp(a.radius, b.radius, t)
	ta := a.transform if a.transform != {} else [6]f32{1, 0, 0, 1, 0, 0}
	tb := b.transform if b.transform != {} else [6]f32{1, 0, 0, 1, 0, 0}
	for i in 0 ..< 6 do p.transform[i] = math.lerp(ta[i], tb[i], t)
	return p
}

@(private = "file")
paint_or :: proc(p: Vector_Paint, color: [4]u8, other: Vector_Paint) -> Vector_Paint {
	if p.kind == .Solid && other.kind != .Solid do return as_gradient(color, other)
	return p
}

// Vector_StyleMorph: a style t of the way from a to b - colours (a missing
// fill / stroke fades in or out), widths, opacity, gradients with the same
// kind and stop count; the rest switches halfway.
Vector_StyleMorph :: proc(a, b: Vector_Style, t: f32) -> Vector_Style {
	s := a if t < 0.5 else b
	fa, fb := a.fillColor, b.fillColor
	if !a.fill do fa = {fb[0], fb[1], fb[2], 0}
	if !b.fill do fb = {fa[0], fa[1], fa[2], 0}
	s.fill = a.fill || b.fill
	s.fillColor = lerp_color(fa, fb, t)
	if a.fill && b.fill do s.fillPaint = lerp_paint(paint_or(a.fillPaint, a.fillColor, b.fillPaint), paint_or(b.fillPaint, b.fillColor, a.fillPaint), t)
	sa, sb := a.strokeColor, b.strokeColor
	wa, wb := a.strokeWidth, b.strokeWidth
	if !a.stroke {sa = {sb[0], sb[1], sb[2], 0}; wa = wb}
	if !b.stroke {sb = {sa[0], sa[1], sa[2], 0}; wb = wa}
	s.stroke = a.stroke || b.stroke
	s.strokeColor = lerp_color(sa, sb, t)
	s.strokeWidth = math.lerp(wa, wb, t)
	if a.stroke && b.stroke do s.strokePaint = lerp_paint(paint_or(a.strokePaint, a.strokeColor, b.strokePaint), paint_or(b.strokePaint, b.strokeColor, a.strokePaint), t)
	oa := a.opacity if a.opacity > 0 else 1
	ob := b.opacity if b.opacity > 0 else 1
	s.opacity = math.lerp(oa, ob, t)
	return s
}

// Vector_ShapesMorph appends shapes t of the way from list a to list b
// (paired in order; extra shapes shrink to / grow from their centres and
// fade). Paths are allocated in context.allocator.
Vector_ShapesMorph :: proc(a, b: []Vector_Shape, t: f32, out: ^[dynamic]Vector_Shape) {
	n := max(len(a), len(b))
	for i in 0 ..< n {
		s := Vector_Shape{}
		Vector_Path_Init(&s.path)
		if i < len(a) && i < len(b) {
			s.style = Vector_StyleMorph(a[i].style, b[i].style, t)
			s.clip = a[i].clip if t < 0.5 else b[i].clip
			Vector_PathMorph(&a[i].path, &b[i].path, t, &s.path)
		} else {
			src := a[i] if i < len(a) else b[i]
			k := t if i < len(a) else 1 - t // (how far gone it is)
			s.style = src.style
			s.style.opacity = (src.style.opacity if src.style.opacity > 0 else 1) * (1 - k)
			s.clip = src.clip
			dot := Vector_Path{}
			Vector_Path_Init(&dot, context.temp_allocator)
			c: [2]f32
			if subs := to_subs(&src.path); len(subs) > 0 do c = sub_center(subs[0])
			Vector_MoveTo(&dot, c)
			Vector_LineTo(&dot, c)
			Vector_PathMorph(&src.path, &dot, k, &s.path)
		}
		if s.style.opacity < 0.001 do s.style.opacity = 0.001 // (0 means opaque)
		append(out, s)
	}
}
