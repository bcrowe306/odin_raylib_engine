package engine

import "core:math"
import "core:os"
import "core:testing"
import lua "lua54"

@(private = "file")
square :: proc(p: ^Vector_Polys, x, y, s: f32) {
	Vector_PolysAddRing(p, [][2]f32{{x, y}, {x + s, y}, {x + s, y + s}, {x, y + s}})
}

@(private = "file")
tmp_polys :: proc() -> Vector_Polys {
	return {pts = make([dynamic][2]f32, context.temp_allocator), rings = make([dynamic]Vector_Ring, context.temp_allocator)}
}

@(private = "file")
near_pct :: proc(a, b, pct: f32) -> bool {return abs(a - b) <= abs(b) * pct / 100}

// Path operations (V.15): booleans, offsets, stroke outlines, fill rules,
// clip paths, simplifying, flattening, cutting a drawing (paints kept),
// convex decomposition; measured polylines.
@(test)
test_vector_path_ops :: proc(t: ^testing.T) {
	a, b, r := tmp_polys(), tmp_polys(), tmp_polys()
	square(&a, 0, 0, 100)
	square(&b, 50, 50, 100)
	expect_op :: proc(t: ^testing.T, op: Vector_Bool_Op, a, b, r: ^Vector_Polys, want: f32) {
		ok := Vector_PolysBoolean(op, a, b, 0.1, r)
		testing.expectf(t, ok && near_pct(Vector_PolysArea(r), want, 0.1), "%v: area %v (want %v)", op, Vector_PolysArea(r), want)
	}
	expect_op(t, .Union, &a, &b, &r, 17500)
	expect_op(t, .Intersect, &a, &b, &r, 2500)
	expect_op(t, .Subtract, &a, &b, &r, 7500)
	expect_op(t, .Exclude, &a, &b, &r, 15000)
	// A square minus a square inside it: one outer ring with a hole.
	inner := tmp_polys()
	square(&inner, 25, 25, 50)
	Vector_PolysBoolean(.Subtract, &a, &inner, 0.1, &r)
	testing.expect(t, len(r.rings) == 2 && r.rings[1].parent == 0, "a hole belongs to its outer ring")
	testing.expect(t, Vector_PolysContains(&r, {10, 10}) && !Vector_PolysContains(&r, {50, 50}), "inside the ring, not in the hole")
	// Offsets.
	Vector_PolysOffset(&a, 10, .Miter, 0.1, &r)
	testing.expectf(t, near_pct(Vector_PolysArea(&r), 14400, 0.1), "grown, mitred: %v", Vector_PolysArea(&r))
	Vector_PolysOffset(&a, 10, .Round, 0.05, &r)
	testing.expectf(t, near_pct(Vector_PolysArea(&r), 10000 + 4000 + math.PI * 100, 0.5), "grown, rounded: %v", Vector_PolysArea(&r))
	Vector_PolysOffset(&a, -10, .Miter, 0.1, &r)
	testing.expectf(t, near_pct(Vector_PolysArea(&r), 6400, 0.1), "shrunk: %v", Vector_PolysArea(&r))

	// Stroke outlines: caps, a closed stroke, dashes.
	line := Vector_Shape{style = VECTOR_STYLE_DEFAULT}
	Vector_Path_Init(&line.path, context.temp_allocator)
	Vector_MoveTo(&line.path, {0, 0}); Vector_LineTo(&line.path, {100, 0})
	line.style.fill, line.style.stroke, line.style.strokeWidth = false, true, 10
	line.style.cap = .Butt
	Vector_StrokeOutline(&line, 0.05, &r)
	testing.expectf(t, near_pct(Vector_PolysArea(&r), 1000, 0.2), "butt caps: %v", Vector_PolysArea(&r))
	line.style.cap = .Round
	Vector_StrokeOutline(&line, 0.05, &r)
	testing.expectf(t, near_pct(Vector_PolysArea(&r), 1000 + math.PI * 25, 0.5), "round caps: %v", Vector_PolysArea(&r))
	line.style.cap = .Butt
	line.style.dash = {count = 2, values = {10, 10, 0, 0, 0, 0, 0, 0}}
	Vector_StrokeOutline(&line, 0.05, &r)
	testing.expectf(t, near_pct(Vector_PolysArea(&r), 500, 1), "dashed half way: %v", Vector_PolysArea(&r))
	box := Vector_Shape{style = VECTOR_STYLE_DEFAULT}
	Vector_Path_Init(&box.path, context.temp_allocator)
	Vector_Rect(&box.path, {0, 0}, {100, 100})
	box.style.stroke, box.style.strokeWidth, box.style.join = true, 10, .Miter
	Vector_StrokeOutline(&box, 0.05, &r)
	testing.expectf(t, near_pct(Vector_PolysArea(&r), 110 * 110 - 90 * 90, 0.2), "a closed stroke on both sides: %v", Vector_PolysArea(&r))
	// The whole shape: fill + stroke = the outer square.
	Vector_ShapesArea([]Vector_Shape{box}, 0.05, &r)
	testing.expectf(t, near_pct(Vector_PolysArea(&r), 12100, 0.2), "fill and stroke united: %v", Vector_PolysArea(&r))

	// Fill rules: two circles the same way - non-zero fills the middle,
	// even-odd makes a ring.
	ring := Vector_Shape{style = VECTOR_STYLE_DEFAULT}
	Vector_Path_Init(&ring.path, context.temp_allocator)
	Vector_Ellipse(&ring.path, {0, 0}, {100, 100})
	Vector_Ellipse(&ring.path, {0, 0}, {50, 50})
	Vector_FillArea(&ring, 0.05, &r)
	testing.expectf(t, near_pct(Vector_PolysArea(&r), math.PI * 10000, 0.5), "non-zero: the disc (%v)", Vector_PolysArea(&r))
	ring.style.fillRule = .EvenOdd
	Vector_FillArea(&ring, 0.05, &r)
	testing.expectf(t, near_pct(Vector_PolysArea(&r), math.PI * 7500, 0.5), "even-odd: the ring (%v)", Vector_PolysArea(&r))
	// A clip path cuts the area.
	k: Vector_Clip
	Vector_Path_Init(&k.path, context.temp_allocator)
	Vector_Rect(&k.path, {0, -200}, {200, 200})
	ring.clip = &k
	Vector_FillArea(&ring, 0.05, &r)
	testing.expectf(t, near_pct(Vector_PolysArea(&r), math.PI * 3750, 0.5), "clipped to the right half (%v)", Vector_PolysArea(&r))

	// Simplify: a fine circle loses most points, keeps its area.
	disc := tmp_polys()
	Vector_PolysCircle(&disc, {0, 0}, 100, 0.01)
	before := len(disc.pts)
	Vector_PolysSimplify(&disc, 1, &r)
	testing.expectf(t, len(r.pts) < before / 3 && near_pct(Vector_PolysArea(&r), math.PI * 10000, 2), "simplified %d -> %d points, area %v", before, len(r.pts), Vector_PolysArea(&r))

	// Flattening: lines only.
	curve: Vector_Path
	Vector_Path_Init(&curve, context.temp_allocator)
	Vector_Ellipse(&curve, {0, 0}, {50, 50})
	flat: Vector_Path
	Vector_Path_Init(&flat, context.temp_allocator)
	Vector_PathFlatten(&curve, 0.25, &flat)
	lines := true
	for c in flat.cmds do if c == .Cubic || c == .Quad do lines = false
	testing.expect(t, lines && len(flat.cmds) > 16, "flattened to lines")
	// Shapes boolean into a path.
	out: Vector_Path
	Vector_Path_Init(&out, context.temp_allocator)
	testing.expect(t, Vector_ShapesBoolean(.Subtract, []Vector_Shape{box}, []Vector_Shape{ring}, 0.1, &out) && len(out.cmds) > 0, "shapes boolean -> path")

	// Convex decomposition: a square with a hole, an L.
	pieces := make([dynamic][2]f32, context.temp_allocator)
	counts := make([dynamic]int, context.temp_allocator)
	holed := tmp_polys()
	Vector_PolysBoolean(.Subtract, &a, &inner, 0.1, &holed)
	Vector_ConvexDecompose(&holed, 8, &pieces, &counts)
	total: f32
	convex := true
	kk := 0
	for n in counts {
		poly := pieces[kk:kk + n]
		kk += n
		total += abs(Vector_SignedArea(poly)) * 0.5
		if n > 8 do convex = false
		s0: f32 = 0
		for i in 0 ..< n {
			cr := (poly[(i + 1) % n] - poly[i]).x * (poly[(i + 2) % n] - poly[(i + 1) % n]).y - (poly[(i + 1) % n] - poly[i]).y * (poly[(i + 2) % n] - poly[(i + 1) % n]).x
			if abs(cr) < 1e-3 do continue
			if s0 == 0 do s0 = math.sign(cr)
			else if math.sign(cr) != s0 do convex = false
		}
	}
	testing.expectf(t, convex && near_pct(total, 7500, 0.1), "convex pieces of at most 8 corners cover it: %v in %d pieces", total, len(counts))
	testing.expectf(t, len(counts) < 8, "triangles merged (%d pieces)", len(counts))

	// Cutting a drawing: the fill and the stroke keep their paints.
	shapes := make([dynamic]Vector_Shape, context.temp_allocator)
	sq := Vector_Shape{style = VECTOR_STYLE_DEFAULT}
	Vector_Path_Init(&sq.path, context.temp_allocator)
	Vector_Rect(&sq.path, {0, 0}, {100, 100})
	sq.style.fillColor = {200, 40, 40, 255}
	sq.style.stroke, sq.style.strokeColor, sq.style.strokeWidth = true, {10, 10, 90, 255}, 4
	append(&shapes, sq)
	hole := tmp_polys()
	Vector_PolysCircle(&hole, {50, 50}, 20, 0.05)
	Vector_ShapesCut(&shapes, &hole, 0.1, context.temp_allocator)
	testing.expect_value(t, len(shapes), 2)
	if len(shapes) == 2 {
		testing.expect(t, shapes[0].style.fillColor == {200, 40, 40, 255} && !shapes[0].style.stroke, "the fill: its colour")
		testing.expect(t, shapes[1].style.fill && shapes[1].style.fillColor == {10, 10, 90, 255}, "the stroke: filled with its colour")
		Vector_FillArea(&shapes[0], 0.05, &r)
		testing.expectf(t, near_pct(Vector_PolysArea(&r), 10000 - math.PI * 400, 0.5), "the hole is cut (%v)", Vector_PolysArea(&r))
	}

	// Polylines: pieces with a jump between them, sampled and matched.
	pl: Polyline
	defer Polyline_Destroy(&pl)
	Polyline_Add(&pl, {0, 0}); Polyline_Add(&pl, {100, 0})
	Polyline_Add(&pl, {0, 50}, true); Polyline_Add(&pl, {0, 150})
	testing.expect_value(t, Polyline_Length(pl.pts[:], pl.lens[:]), 200)
	pos, dir := Polyline_Sample(pl.pts[:], pl.lens[:], 150)
	testing.expectf(t, pos == {0, 100} && dir == {0, 1}, "in the second piece (%v %v)", pos, dir)
	pos, dir = Polyline_Sample(pl.pts[:], pl.lens[:], 100)
	testing.expectf(t, pos == {100, 0} || pos == {0, 50}, "at the jump: an end (%v)", pos)
	d, at := Polyline_Closest(pl.pts[:], pl.lens[:], {10, 90})
	testing.expectf(t, d == 140 && at == {0, 90}, "closest: on the second piece (%v %v)", d, at)
	d, at = Polyline_Closest(pl.pts[:], pl.lens[:], {50, 30})
	testing.expectf(t, d == 50 && at == {50, 0}, "not on the jump (%v %v)", d, at)
}

@(private = "file")
GROUND_SVG :: `<svg xmlns="http://www.w3.org/2000/svg" width="400" height="60" viewBox="0 0 400 60">
<path d="M0 20 Q200 -10 400 20 L400 60 L0 60 Z" fill="#6b8e23" stroke="#3b4e13" stroke-width="4"/></svg>`

@(private = "file")
drop_ball :: proc(t: ^testing.T, mode: Vector_Collider, cutUnder: bool) -> (y: f32, v: ^VectorShapeNode, built: int) {
	dir :: "test_vector_collider_zz"
	_ = os.make_directory_all(dir)
	_ = os.write_entire_file(dir + "/ground.svg", transmute([]u8)string(GROUND_SVG))
	defer os.remove_all(dir)
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	AssetManager_SetProjectDir(&game.assetManager, dir)
	game.resourceManager.projectDir = game.assetManager.projectDir
	scene := game->createScene("vcol", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	// Ground: a Vector Shape with a collider and no body (its own static body).
	g := cast(^VectorShapeNode)Node_CreateByTypeName(scene, "VectorShapeNode")
	g.name = "Ground"
	g.file = "ground.svg"
	g.position = {0, 400} // (centred: its top edge near y 375)
	g.collider = mode
	ball := DynamicBodyNode_Create(scene, "Ball")
	ball.position = {0, 300}
	circle: PhysicsShape
	PhysicsShape_InitDefault(&circle, .Circle)
	circle.radius = 10
	circle.restitution = 0
	DynamicBodyNode_AddShape(ball, circle)
	// A crate: a Dynamic Body whose shape comes from a Vector Shape child.
	crate := DynamicBodyNode_Create(scene, "Crate")
	crate.position = {120, 250}
	art := cast(^VectorShapeNode)Node_CreateByTypeName(scene, "VectorShapeNode", crate)
	art.preset = .Badge
	art.scale = {0.2, 0.2}
	art.collider = .Solid
	ProcessNodeQueues(scene.manager, &game.gameContext)
	for _ in 0 ..< 150 do game->run(1.0 / 60)
	testing.expectf(t, ball.globalPosition.y < 375 && ball.globalPosition.y > 340, "%v: the ball rests on the ground (y %v)", mode, ball.globalPosition.y)
	testing.expectf(t, crate.globalPosition.y < 375 && crate.globalPosition.y > 300, "%v: the crate (shaped by its art) lands on it (y %v)", mode, crate.globalPosition.y)
	testing.expect(t, len(art.collision.shapes) > 0 && art.collision.body == crate.bodyId, "the crate's art joins its body")
	built = g.collision.built
	if cutUnder {
		// Lua: a crater under the ball - it falls through.
		L := game.scriptManager.L
		if lua.L_dostring(L, `local g = Scene.find_node("Ground"); local b = Scene.find_node("Ball"); g:vector_cut(b.position.x, b.position.y + 10, 40)`) != 0 {
			testing.fail_now(t, string(lua.tostring(L, -1)))
		}
		for _ in 0 ..< 90 do game->run(1.0 / 60)
		testing.expect(t, g.carving && g.collision.built > built, "cut: the art and its collider re-made")
	}
	return ball.globalPosition.y, g, built
}

// Collision from vector shapes (V.16): Solid pieces and Outline loops on a
// body of its own, a Vector Shape giving its Dynamic Body a shape, cutting
// a crater the ball falls into; path queries.
@(test)
test_vector_collider :: proc(t: ^testing.T) {
	drop_ball(t, .Solid, false)
	drop_ball(t, .Outline, false)
	y, _, _ := drop_ball(t, .Solid, true)
	testing.expectf(t, y > 380, "the ball fell into the crater (y %v)", y)

	// Geometry without physics: a ring preset (a hole) in Solid pieces.
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("vgeo", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	v := cast(^VectorShapeNode)Node_CreateByTypeName(scene, "VectorShapeNode")
	v.preset = .Ring
	v.collider = .Solid
	c, ok := VectorShapeNode_ColliderGeometry(v)
	testing.expect(t, ok && len(c.counts) > 1 && len(c.area.rings) == 2, "a ring: pieces round a hole")
	n := c.built
	_, _ = VectorShapeNode_ColliderGeometry(v)
	testing.expect_value(t, c.built, n) // (unchanged: not re-made)
	v.colliderDetail = 4
	_, _ = VectorShapeNode_ColliderGeometry(v)
	testing.expect_value(t, c.built, n + 1)
	// Path queries on its outline.
	pl := VectorShapeNode_Polyline(v)
	l := Polyline_Length(pl.pts[:], pl.lens[:])
	testing.expectf(t, near_pct(l, math.TAU * (100 + 55), 1), "length: both circles (%v)", l)
	d, at := Polyline_Closest(pl.pts[:], pl.lens[:], {0, -130})
	testing.expectf(t, abs(at.y + 100) < 1 || abs(at.y + 55) < 1, "closest point on a circle (%v at %v)", at, d)
	// A Path Follow rides the outline (shared with PathNode).
	f := cast(^PathFollowNode)Node_CreateByTypeName(scene, "PathFollowNode", v)
	f.progress = 25
	f.rotate = false
	// Lua.
	v.name = "RingZ"
	v.position = {500, 300}
	ProcessNodeQueues(scene.manager, &game.gameContext)
	game.state = .Running
	game->run(1.0 / 60)
	wantPos, _ := Polyline_Sample(pl.pts[:], pl.lens[:], 25)
	testing.expectf(t, abs(f.position.x - wantPos.x) < 0.01 && abs(f.position.y - wantPos.y) < 0.01, "the follower on the outline (%v vs %v)", f.position, wantPos)
	L := game.scriptManager.L
	if lua.L_dostring(L, `
local r = Scene.find_node("RingZ")
len = r:vector_length()
local p = r:vector_point_at(0)
px = p.x
local d, q = r:vector_closest(Vec2(500, 150))
qy = q.y
inside = r:vector_contains(580, 300)
hole = r:vector_contains(500, 300)
`) != 0 {
		testing.fail_now(t, string(lua.tostring(L, -1)))
	}
	getn :: proc(L: ^lua.State, n: cstring) -> f64 {lua.getglobal(L, n); defer lua.pop(L, 1); return f64(lua.tonumber(L, -1))}
	getb :: proc(L: ^lua.State, n: cstring) -> bool {lua.getglobal(L, n); defer lua.pop(L, 1); return bool(lua.toboolean(L, -1))}
	testing.expectf(t, near_pct(f32(getn(L, "len")), l, 0.1), "vector_length (%v)", getn(L, "len"))
	testing.expectf(t, abs(getn(L, "qy") - 200) < 1, "vector_closest in the world (%v)", getn(L, "qy"))
	testing.expect(t, getb(L, "inside") && !getb(L, "hole"), "vector_contains: on the ring, not in its hole")
}
