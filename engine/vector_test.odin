package engine

import "core:log"
import "core:math"
import "core:testing"
import "core:time"

// Phase 14 M0: vector paths, flattening, earcut, tessellation (fills with
// holes, strokes, anti-aliasing fringes), the cache's scale buckets and the
// node. Leaks: the test runner's tracking allocator.

@(private = "file")
tri_area :: proc(a, b, c: [2]f32) -> f32 {
	return abs((b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)) * 0.5
}

@(private = "file")
indices_area :: proc(pts: [][2]f32, idx: []u32) -> f32 {
	sum: f32
	for i := 0; i < len(idx); i += 3 do sum += tri_area(pts[idx[i]], pts[idx[i + 1]], pts[idx[i + 2]])
	return sum
}

// covered: a point inside a fully opaque triangle of the mesh.
@(private = "file")
covered :: proc(m: ^Vector_Mesh, p: [2]f32) -> bool {
	for i := 0; i < len(m.idx); i += 3 {
		a, b, c := m.idx[i], m.idx[i + 1], m.idx[i + 2]
		if m.cols[a].a == 0 || m.cols[b].a == 0 || m.cols[c].a == 0 do continue
		pa, pb, pc := m.verts[a], m.verts[b], m.verts[c]
		d1 := (p.x - pb.x) * (pa.y - pb.y) - (pa.x - pb.x) * (p.y - pb.y)
		d2 := (p.x - pc.x) * (pb.y - pc.y) - (pb.x - pc.x) * (p.y - pc.y)
		d3 := (p.x - pa.x) * (pc.y - pa.y) - (pc.x - pa.x) * (p.y - pa.y)
		neg := d1 < 0 || d2 < 0 || d3 < 0
		pos := d1 > 0 || d2 > 0 || d3 > 0
		if !(neg && pos) do return true
	}
	return false
}

@(test)
test_vector_flatten :: proc(t: ^testing.T) {
	p: Vector_Path
	Vector_Path_Init(&p)
	defer Vector_Path_Destroy(&p)
	Vector_Ellipse(&p, {10, 20}, {100, 100})
	f: Vector_Flat
	defer Vector_Flat_Destroy(&f)
	for tol in ([]f32{2, 0.25, 0.01}) {
		Vector_Flatten(&p, tol, &f)
		testing.expect_value(t, len(f.contours), 1)
		testing.expect(t, f.contours[0].closed, "closed")
		pts := Vector_Contour_Points(&f, f.contours[0])
		// (The cubic circle itself is off a true circle by 0.027%.)
		for q in pts {
			d := math.sqrt((q.x - 10) * (q.x - 10) + (q.y - 20) * (q.y - 20))
			testing.expectf(t, abs(d - 100) <= tol + 0.03, "tol %v: point at %v from the centre", tol, d)
		}
		// The first point isn't repeated at the end.
		testing.expect(t, pts[0] != pts[len(pts) - 1], "no closing duplicate")
	}
	// Finer tolerance: more points.
	Vector_Flatten(&p, 1, &f)
	coarse := len(f.pts)
	Vector_Flatten(&p, 0.01, &f)
	testing.expect(t, len(f.pts) > coarse * 4, "finer tolerance, more segments")
	// An open polyline and a lone move.
	Vector_Path_Clear(&p)
	Vector_MoveTo(&p, {0, 0}); Vector_LineTo(&p, {10, 0}); Vector_LineTo(&p, {10, 0}); Vector_LineTo(&p, {10, 10})
	Vector_MoveTo(&p, {50, 50})
	Vector_Flatten(&p, 0.25, &f)
	testing.expect_value(t, len(f.contours), 1)
	testing.expect_value(t, f.contours[0].count, 3) // (the duplicate dropped)
	testing.expect(t, !f.contours[0].closed, "open")
}

@(test)
test_vector_earcut :: proc(t: ^testing.T) {
	ec: Earcut
	defer Earcut_Destroy(&ec)
	out := make([dynamic]u32)
	defer delete(out)
	// Square: 2 triangles, both windings.
	sq := [][2]f32{{0, 0}, {10, 0}, {10, 10}, {0, 10}}
	testing.expect(t, Earcut_Triangulate(&ec, sq, nil, &out), "square")
	testing.expect_value(t, len(out), 6)
	testing.expect(t, abs(indices_area(sq, out[:]) - 100) < 1e-3, "square area")
	clear(&out)
	sqr := [][2]f32{{0, 0}, {0, 10}, {10, 10}, {10, 0}}
	Earcut_Triangulate(&ec, sqr, nil, &out)
	testing.expect(t, abs(indices_area(sqr, out[:]) - 100) < 1e-3, "reversed square area")
	// Concave (a star): the triangles cover exactly its area.
	star := make([dynamic][2]f32, context.temp_allocator)
	for i in 0 ..< 10 {
		a := f32(i) * math.PI / 5
		r: f32 = 100 if i % 2 == 0 else 40
		append(&star, [2]f32{math.cos(a) * r, math.sin(a) * r})
	}
	clear(&out)
	Earcut_Triangulate(&ec, star[:], nil, &out)
	testing.expect_value(t, len(out), 8 * 3)
	testing.expect(t, abs(indices_area(star[:], out[:]) - abs(Vector_SignedArea(star[:])) * 0.5) < 0.05, "star area")
	// A square with a square hole.
	holed := [][2]f32{{0, 0}, {10, 0}, {10, 10}, {0, 10}, {3, 3}, {3, 7}, {7, 7}, {7, 3}}
	clear(&out)
	Earcut_Triangulate(&ec, holed, []int{4}, &out)
	testing.expect(t, abs(indices_area(holed, out[:]) - (100 - 16)) < 1e-3, "holed area")
	// Big (z-order hashed: > 80 points): a 500-gon.
	big := make([dynamic][2]f32, context.temp_allocator)
	for i in 0 ..< 500 {
		a := f32(i) / 500 * 2 * math.PI
		append(&big, [2]f32{math.cos(a) * 300, math.sin(a) * 300})
	}
	clear(&out)
	Earcut_Triangulate(&ec, big[:], nil, &out)
	testing.expect_value(t, len(out), 498 * 3)
	testing.expect(t, abs(indices_area(big[:], out[:]) - abs(Vector_SignedArea(big[:])) * 0.5) < 1, "500-gon area")
	// Junk: too few points, all collinear, duplicates.
	clear(&out)
	testing.expect(t, !Earcut_Triangulate(&ec, [][2]f32{{0, 0}, {1, 1}}, nil, &out), "2 points")
	Earcut_Triangulate(&ec, [][2]f32{{0, 0}, {1, 1}, {2, 2}, {3, 3}}, nil, &out)
	Earcut_Triangulate(&ec, [][2]f32{{0, 0}, {0, 0}, {5, 0}, {5, 0}, {5, 5}}, nil, &out)
	// (A self-touching figure eight: no crash, some triangles.)
	Earcut_Triangulate(&ec, [][2]f32{{0, 0}, {10, 10}, {10, 0}, {0, 10}}, nil, &out)
}

@(test)
test_vector_tessellate_fill :: proc(t: ^testing.T) {
	shapes := make([dynamic]Vector_Shape)
	defer {
		for &s in shapes do Vector_Path_Destroy(&s.path)
		delete(shapes)
	}
	Vector_PresetShapes(.Ring, {255, 0, 0, 255}, {}, 0, &shapes)
	tess: Vector_Tess
	defer Vector_Tess_Destroy(&tess)
	m: Vector_Mesh
	defer Vector_Mesh_Destroy(&m)
	Vector_Tessellate(&tess, shapes[:], 1, &m)
	testing.expect(t, len(m.idx) > 0 && len(m.idx) % 3 == 0, "triangles")
	// Ring: outer radius 100, hole 55.
	testing.expect(t, covered(&m, {77, 0}), "the ring is filled")
	testing.expect(t, covered(&m, {0, -77}), "all around")
	testing.expect(t, !covered(&m, {0, 0}), "the hole is empty")
	testing.expect(t, !covered(&m, {30, 30}), "inside the hole")
	testing.expect(t, !covered(&m, {101, 0}), "outside")
	// The fringe fades out by the outline: transparent vertices exist, just past it.
	transparent := 0
	for c, i in m.cols do if c.a == 0 {
		transparent += 1
		r := math.sqrt(m.verts[i].x * m.verts[i].x + m.verts[i].y * m.verts[i].y)
		testing.expectf(t, abs(r - 100.5) < 0.6 || abs(r - 54.5) < 0.6, "fringe vertex at r=%v", r)
	}
	testing.expect(t, transparent > 0, "a fringe")
	testing.expect(t, m.bounds[0] < -100 && m.bounds[2] > 100, "bounds include the fringe")
	// Zoomed out (a pixel = 8 units): far fewer triangles, still a ring.
	fine := len(m.idx)
	Vector_Tessellate(&tess, shapes[:], 8, &m)
	testing.expect(t, len(m.idx) < fine / 2, "coarser when zoomed out")
	testing.expect(t, !covered(&m, {0, 0}), "the hole stays")
}

@(test)
test_vector_tessellate_stroke :: proc(t: ^testing.T) {
	shapes := make([dynamic]Vector_Shape)
	defer {
		for &s in shapes do Vector_Path_Destroy(&s.path)
		delete(shapes)
	}
	s := Vector_Shape{style = VECTOR_STYLE_DEFAULT}
	Vector_Path_Init(&s.path)
	s.style.fill = false
	s.style.stroke = true
	s.style.strokeWidth = 10
	s.style.join = .Miter
	s.style.cap = .Butt
	Vector_MoveTo(&s.path, {0, 0})
	Vector_LineTo(&s.path, {100, 0})
	Vector_LineTo(&s.path, {100, 100})
	append(&shapes, s)
	tess: Vector_Tess
	defer Vector_Tess_Destroy(&tess)
	m: Vector_Mesh
	defer Vector_Mesh_Destroy(&m)
	Vector_Tessellate(&tess, shapes[:], 1, &m)
	testing.expect(t, covered(&m, {50, 0}), "on the line")
	testing.expect(t, covered(&m, {50, 4}), "within half the width")
	testing.expect(t, !covered(&m, {50, 6}), "beyond it")
	testing.expect(t, covered(&m, {100, 50}), "the second segment")
	testing.expect(t, covered(&m, {104, -4}), "the miter corner")
	testing.expect(t, !covered(&m, {-3, 0}), "butt cap: nothing before the start")
	// Round caps reach half the width past the ends.
	shapes[0].style.cap = .Round
	Vector_Tessellate(&tess, shapes[:], 1, &m)
	testing.expect(t, covered(&m, {-3, 0}), "round cap")
	// Bevel: the corner's tip is cut.
	shapes[0].style.cap = .Butt
	shapes[0].style.join = .Bevel
	Vector_Tessellate(&tess, shapes[:], 1, &m)
	testing.expect(t, !covered(&m, {104.5, -4.5}), "bevel cuts the corner")
	// Hairline (0.25 px): drawn a pixel wide, fainter.
	shapes[0].style.strokeWidth = 0.25
	Vector_Tessellate(&tess, shapes[:], 1, &m)
	maxA: u8
	for c in m.cols do maxA = max(maxA, c.a)
	testing.expect(t, maxA > 0 && maxA < 100, "a faint hairline")
}

@(test)
test_vector_cache_buckets :: proc(t: ^testing.T) {
	shapes := make([dynamic]Vector_Shape)
	defer {
		for &s in shapes do Vector_Path_Destroy(&s.path)
		delete(shapes)
	}
	Vector_PresetShapes(.Character, {200, 60, 60, 255}, {30, 20, 10, 255}, 3, &shapes)
	testing.expect(t, len(shapes) > 190, "a busy character")
	tess: Vector_Tess
	defer Vector_Tess_Destroy(&tess)
	c: Vector_Cache
	defer Vector_Cache_Destroy(&c)
	testing.expect_value(t, Vector_PixelBucket(1), 1)
	testing.expect_value(t, Vector_PixelBucket(0.8), 1)
	testing.expect_value(t, Vector_PixelBucket(1.6), 2)
	testing.expect_value(t, Vector_PixelBucket(0.3), 0.25)
	Vector_Cache_Ensure(&c, &tess, shapes[:], 1)
	Vector_Cache_Ensure(&c, &tess, shapes[:], 0.9) // (same bucket)
	Vector_Cache_Ensure(&c, &tess, shapes[:], 1.2)
	testing.expect_value(t, c.stats.tessellations, 1)
	Vector_Cache_Ensure(&c, &tess, shapes[:], 0.4) // zoomed in 2.5x
	testing.expect_value(t, c.stats.tessellations, 2)
	c.dirty = true
	Vector_Cache_Ensure(&c, &tess, shapes[:], 0.4)
	testing.expect_value(t, c.stats.tessellations, 3)
	testing.expect(t, len(c.mesh.idx) > 3000, "thousands of triangles")
}

@(test)
test_vector_shape_node :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("vector", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	v := cast(^VectorShapeNode)Node_CreateByTypeName(scene, "VectorShapeNode")
	testing.expect(t, v != nil && v.typeId == VectorShapeNode, "created from the registry")
	VectorShapeNode_Build(v)
	testing.expect(t, len(v.shapes) == 1, "the star")
	v.preset = .Character
	VectorShapeNode_Build(v)
	testing.expect(t, len(v.shapes) > 190, "the character")
	// Properties round-trip through the scene file.
	v.preset = .Badge
	v.strokeWidth = 7
	json := Node_SerializeToJSON(v, scene.manager, context.temp_allocator)
	testing.expect(t, contains(json, `"preset": "Badge"`) && contains(json, `"strokeWidth": 7`), "saved")
}

@(private = "file")
contains :: proc(s, sub: string) -> bool {
	for i := 0; i + len(sub) <= len(s); i += 1 do if s[i:i + len(sub)] == sub do return true
	return false
}

// Cost of (re)tessellating the benchmark character (logged: the M0 numbers
// in engine/docs/vector.md); asserts only a generous ceiling.
@(test)
test_vector_tessellation_cost :: proc(t: ^testing.T) {
	shapes := make([dynamic]Vector_Shape)
	defer {
		for &s in shapes do Vector_Path_Destroy(&s.path)
		delete(shapes)
	}
	Vector_PresetShapes(.Character, {200, 60, 60, 255}, {30, 20, 10, 255}, 3, &shapes)
	tess: Vector_Tess
	defer Vector_Tess_Destroy(&tess)
	m: Vector_Mesh
	defer Vector_Mesh_Destroy(&m)
	for px in ([]f32{2, 1, 0.25}) {
		Vector_Tessellate(&tess, shapes[:], px, &m) // (warm the scratch buffers)
		start := time.tick_now()
		RUNS :: 20
		for _ in 0 ..< RUNS do Vector_Tessellate(&tess, shapes[:], px, &m)
		ms := time.duration_milliseconds(time.tick_since(start)) / RUNS
		log.infof("[vector] character at pixel %v: %v triangles, %v vertices, %.3f ms", px, len(m.idx) / 3, len(m.verts), ms)
		testing.expectf(t, ms < 50, "tessellation took %v ms", ms)
	}
}
