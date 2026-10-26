package engine

import "core:math"

// ============================================================================
// Vector tessellation: shapes -> one triangle mesh (positions, colours,
// indices), anti-aliased without MSAA by a feathered fringe: every filled
// outline is inset by half a pixel and wrapped in a 1-pixel strip fading to
// transparent (NanoVG's approach); strokes are strips of four lanes (fade -
// solid - solid - fade).
//
// `pixel` is the size of a screen pixel in the shapes' units (1 / the scale
// they are drawn at): curves are flattened to a quarter pixel and fringes
// are one pixel wide. A cached mesh stays valid while the drawing scale
// stays near the one it was made for (vector_mesh.odin re-tessellates when
// it changes by more than ~2x).
//
// Fills: each closed contour's nesting depth decides outer / hole (even /
// odd); holes are cut from the smallest outer around them, then earcut
// triangulates (vector_earcut.odin). Self-intersecting outlines and the
// non-zero rule's overlapping same-direction contours are normalized by the
// polygon clipper in M1 (TODO Phase 14).
// ============================================================================

Vector_Mesh :: struct {
	verts:  [dynamic][2]f32,
	cols:   [dynamic][4]u8,
	idx:    [dynamic]u32,
	bounds: [4]f32, // min x, min y, max x, max y
}

Vector_Mesh_Clear :: proc(m: ^Vector_Mesh) {
	clear(&m.verts)
	clear(&m.cols)
	clear(&m.idx)
	m.bounds = {}
}

Vector_Mesh_Destroy :: proc(m: ^Vector_Mesh) {
	delete(m.verts)
	delete(m.cols)
	delete(m.idx)
	m^ = {}
}

// Vector_Tess: scratch buffers kept between tessellations (no allocation per
// shape once warm). One per thread.
Vector_Tess :: struct {
	flat:    Vector_Flat,
	ring:    [dynamic][2]f32,
	normals: [dynamic][2]f32,
	poly:    [dynamic][2]f32,
	holes:   [dynamic]int,
	depth:   [dynamic]int,
	parent:  [dynamic]int,
	area:    [dynamic]f32,
	tri:     [dynamic]u32,
	ec:      Earcut,
}

Vector_Tess_Destroy :: proc(t: ^Vector_Tess) {
	Vector_Flat_Destroy(&t.flat)
	delete(t.ring)
	delete(t.normals)
	delete(t.poly)
	delete(t.holes)
	delete(t.depth)
	delete(t.parent)
	delete(t.area)
	delete(t.tri)
	Earcut_Destroy(&t.ec)
	t^ = {}
}

// Vector_Tessellate appends the shapes' triangles to `mesh` (cleared first).
Vector_Tessellate :: proc(t: ^Vector_Tess, shapes: []Vector_Shape, pixel: f32, mesh: ^Vector_Mesh) {
	Vector_Mesh_Clear(mesh)
	px := max(pixel, 1e-4)
	for &s in shapes {
		Vector_Flatten(&s.path, px * 0.25, &t.flat)
		if len(t.flat.contours) == 0 do continue
		if s.style.fill && s.style.fillColor.a > 0 do tess_fill(t, s.style, px, mesh)
		if s.style.stroke && s.style.strokeColor.a > 0 && s.style.strokeWidth > 0 do tess_stroke(t, s.style, px, mesh)
	}
	if len(mesh.verts) > 0 {
		b := [4]f32{max(f32), max(f32), min(f32), min(f32)}
		for v in mesh.verts {
			b[0] = min(b[0], v.x); b[1] = min(b[1], v.y)
			b[2] = max(b[2], v.x); b[3] = max(b[3], v.y)
		}
		mesh.bounds = b
	}
}

@(private = "file")
add_vert :: #force_inline proc(m: ^Vector_Mesh, p: [2]f32, c: [4]u8) -> u32 {
	append(&m.verts, p)
	append(&m.cols, c)
	return u32(len(m.verts) - 1)
}

@(private = "file")
fade :: #force_inline proc(c: [4]u8) -> [4]u8 {return {c.r, c.g, c.b, 0}}

// ring_normals: per-vertex miter vectors pointing away from the polygon's
// interior (scaled so offsetting by d along them moves each edge by d).
@(private = "file")
ring_normals :: proc(pts: [][2]f32, outward_sign: f32, out: ^[dynamic][2]f32) {
	clear(out)
	n := len(pts)
	for i in 0 ..< n {
		p0, p1, p2 := pts[(i + n - 1) % n], pts[i], pts[(i + 1) % n]
		n0 := edge_normal(p0, p1) * outward_sign
		n1 := edge_normal(p1, p2) * outward_sign
		append(out, miter(n0, n1))
	}
}

@(private = "file")
edge_normal :: #force_inline proc(a, b: [2]f32) -> [2]f32 {
	d := b - a
	l := math.sqrt(d.x * d.x + d.y * d.y)
	if l < 1e-9 do return {}
	return {d.y / l, -d.x / l}
}

// miter: the join vector of two unit normals (length 1 / cos(half angle),
// capped so a hairpin doesn't shoot off).
@(private = "file")
miter :: #force_inline proc(n0, n1: [2]f32) -> [2]f32 {
	dm := (n0 + n1) * 0.5
	d2 := dm.x * dm.x + dm.y * dm.y
	if d2 < 1e-6 do return n1
	s := min(1 / d2, 64)
	return dm * s
}

@(private = "file")
tess_fill :: proc(t: ^Vector_Tess, style: Vector_Style, px: f32, mesh: ^Vector_Mesh) {
	f := &t.flat
	nc := len(f.contours)
	clear(&t.depth); clear(&t.parent); clear(&t.area)
	for c in f.contours {
		append(&t.area, Vector_SignedArea(Vector_Contour_Points(f, c)))
		append(&t.depth, 0)
		append(&t.parent, -1)
	}
	// Nesting: how many contours contain each one (its first point), and the
	// smallest of them.
	for i in 0 ..< nc {
		ci := f.contours[i]
		if ci.count < 3 do continue
		probe := f.pts[ci.first]
		best := f32(max(f32))
		for j in 0 ..< nc {
			if i == j || f.contours[j].count < 3 do continue
			cj := Vector_Contour_Points(f, f.contours[j])
			if abs(t.area[j]) <= abs(t.area[i]) do continue
			if Vector_PointInPolygon(cj, probe) {
				t.depth[i] += 1
				if abs(t.area[j]) < best {best = abs(t.area[j]); t.parent[i] = j}
			}
		}
	}
	col := style.fillColor
	half := px * 0.5
	for i in 0 ..< nc {
		ci := f.contours[i]
		if ci.count < 3 || t.depth[i] % 2 == 1 do continue // a hole: cut below
		// The outer ring inset by half a pixel, then its holes (each inset too:
		// moved away from the filled area).
		clear(&t.poly); clear(&t.holes)
		base := u32(len(mesh.verts))
		append_ring :: proc(t: ^Vector_Tess, pts: [][2]f32, outward: f32, half: f32, col: [4]u8, mesh: ^Vector_Mesh) {
			ring_normals(pts, outward, &t.normals)
			first := u32(len(mesh.verts))
			n := u32(len(pts))
			for p, k in pts {
				inner := p - t.normals[k] * half
				append(&t.poly, inner)
				add_vert(mesh, inner, col)
			}
			// The fringe: inner (solid) -> outer (transparent).
			outer0 := u32(len(mesh.verts))
			for p, k in pts do add_vert(mesh, p + t.normals[k] * half, fade(col))
			for k in 0 ..< n {
				k1 := (k + 1) % n
				a, b := first + k, first + k1
				c, d := outer0 + k, outer0 + k1
				append(&mesh.idx, a, b, d, a, d, c)
			}
		}
		pts := Vector_Contour_Points(f, ci)
		append_ring(t, pts, 1 if t.area[i] > 0 else -1, half, col, mesh)
		ring_len := len(pts)
		// Fill vertices: the inset outer is mesh[base ..< base+ring_len], each
		// hole's inset ring follows its fringe; map polygon indices to mesh.
		vmap := make([dynamic]u32, 0, ring_len, context.temp_allocator)
		for k in 0 ..< ring_len do append(&vmap, base + u32(k))
		for j in 0 ..< nc {
			if t.parent[j] != i || t.depth[j] % 2 == 0 do continue
			cj := f.contours[j]
			hpts := Vector_Contour_Points(f, cj)
			append(&t.holes, len(t.poly))
			hbase := u32(len(mesh.verts))
			// (A hole's fill edge moves into the hole: its outward is away from the fill.)
			append_ring(t, hpts, -1 if t.area[j] > 0 else 1, half, col, mesh)
			for k in 0 ..< len(hpts) do append(&vmap, hbase + u32(k))
		}
		clear(&t.tri)
		if Earcut_Triangulate(&t.ec, t.poly[:], t.holes[:], &t.tri) {
			for v in t.tri do append(&mesh.idx, vmap[v])
		}
	}
}

@(private = "file")
tess_stroke :: proc(t: ^Vector_Tess, style: Vector_Style, px: f32, mesh: ^Vector_Mesh) {
	f := &t.flat
	col := style.strokeColor
	w := style.strokeWidth
	// Thinner than a pixel: a pixel-wide line, fainter.
	if w < px {
		col.a = u8(f32(col.a) * w / px)
		w = px
	}
	hw := w * 0.5
	solid := max(hw - px * 0.5, 0)
	edge := hw + px * 0.5
	for c in f.contours {
		pts := Vector_Contour_Points(f, c)
		n := len(pts)
		if n < 2 do continue
		closed := c.closed && n > 2
		// Spine samples: a position and its offset direction (unit-ish); joins
		// add samples (bevel: 2, round: an arc).
		clear(&t.ring); clear(&t.normals)
		sample :: proc(t: ^Vector_Tess, p, off: [2]f32) {
			append(&t.ring, p)
			append(&t.normals, off)
		}
		for i in 0 ..< n {
			p := pts[i]
			has_prev := closed || i > 0
			has_next := closed || i < n - 1
			p_prev := pts[(i + n - 1) % n]
			p_next := pts[(i + 1) % n]
			if !has_prev {
				nn := edge_normal(p, p_next)
				d := [2]f32{-nn.y, nn.x} // along the line
				if style.cap == .Square do p -= d * hw
				sample(t, p, nn)
				continue
			}
			if !has_next {
				nn := edge_normal(p_prev, p)
				d := [2]f32{-nn.y, nn.x}
				if style.cap == .Square do p += d * hw
				sample(t, p, nn)
				continue
			}
			n0, n1 := edge_normal(p_prev, p), edge_normal(p, p_next)
			dm := miter(n0, n1)
			mlen2 := dm.x * dm.x + dm.y * dm.y
			cross := n0.x * n1.y - n0.y * n1.x
			// (A miter longer than miterLimit half-widths becomes a bevel.)
			sharp := style.join == .Miter && mlen2 > style.miterLimit * style.miterLimit
			switch {
			case style.join == .Round && abs(cross) > 1e-3:
				a0 := math.atan2(n0.y, n0.x)
				a1 := math.atan2(n1.y, n1.x)
				da := a1 - a0
				for da > math.PI do da -= 2 * math.PI
				for da < -math.PI do da += 2 * math.PI
				steps := clamp(int(math.ceil(abs(da) / math.acos(1 - px * 0.25 / max(hw, px)) )), 1, 32)
				for k in 0 ..= steps {
					a := a0 + da * f32(k) / f32(steps)
					sample(t, p, {math.cos(a), math.sin(a)})
				}
			case style.join == .Bevel && abs(cross) > 1e-3, sharp:
				sample(t, p, n0)
				sample(t, p, n1)
			case:
				sample(t, p, dm)
			}
		}
		// Four lanes per sample: fade, solid, solid, fade.
		count := len(t.ring)
		first := u32(len(mesh.verts))
		for k in 0 ..< count {
			p, o := t.ring[k], t.normals[k]
			add_vert(mesh, p + o * edge, fade(col))
			add_vert(mesh, p + o * solid, col)
			add_vert(mesh, p - o * solid, col)
			add_vert(mesh, p - o * edge, fade(col))
		}
		segs := count if closed else count - 1
		for k in 0 ..< segs {
			a := first + u32(k) * 4
			b := first + u32((k + 1) % count) * 4
			for l in u32(0) ..< 3 {
				append(&mesh.idx, a + l, b + l, b + l + 1, a + l, b + l + 1, a + l + 1)
			}
		}
		if !closed && style.cap == .Round {
			stroke_round_cap(mesh, pts[0], pts[0] - pts[1], hw, solid, edge, col, px)
			stroke_round_cap(mesh, pts[n - 1], pts[n - 1] - pts[n - 2], hw, solid, edge, col, px)
		}
	}
}

// stroke_round_cap: a half disc past the line's end (fan + fringe).
@(private = "file")
stroke_round_cap :: proc(mesh: ^Vector_Mesh, p, dir: [2]f32, hw, solid, edge: f32, col: [4]u8, px: f32) {
	l := math.sqrt(dir.x * dir.x + dir.y * dir.y)
	if l < 1e-9 do return
	d := dir / l
	nrm := [2]f32{d.y, -d.x}
	a0 := math.atan2(nrm.y, nrm.x)
	// From +normal through the direction to -normal (the side d points to).
	sweep: f32 = math.PI if (math.cos(a0 + math.PI / 2) * d.x + math.sin(a0 + math.PI / 2) * d.y) > 0 else -math.PI
	steps := clamp(int(math.ceil(math.PI / math.acos(1 - px * 0.25 / max(hw, px)))), 2, 32)
	center := add_vert(mesh, p, col)
	first := u32(len(mesh.verts))
	for k in 0 ..= steps {
		a := a0 + sweep * f32(k) / f32(steps)
		o := [2]f32{math.cos(a), math.sin(a)}
		add_vert(mesh, p + o * solid, col)
		add_vert(mesh, p + o * edge, fade(col))
	}
	for k in u32(0) ..< u32(steps) {
		i0, o0 := first + k * 2, first + k * 2 + 1
		i1, o1 := first + (k + 1) * 2, first + (k + 1) * 2 + 1
		append(&mesh.idx, center, i0, i1, i0, o0, o1, i0, o1, i1)
	}
}
