package engine

import "core:math"
import "core:testing"

// Trim paths and shape tweens (Phase 14 V.9).

@(private = "file")
square :: proc(p: ^Vector_Path, size: f32) {
	Vector_MoveTo(p, {0, 0})
	Vector_LineTo(p, {size, 0})
	Vector_LineTo(p, {size, size})
	Vector_LineTo(p, {0, size})
	Vector_Close(p)
}

@(private = "file")
near :: proc(a, b: f32, eps: f32 = 0.5) -> bool {return abs(a - b) <= eps}

@(test)
test_vector_trim :: proc(t: ^testing.T) {
	sq: Vector_Path
	Vector_Path_Init(&sq, context.temp_allocator)
	square(&sq, 100)
	testing.expect(t, near(Vector_PathLength(&sq), 400), "a 100 px square is 400 long")
	out: Vector_Path
	Vector_Path_Init(&out, context.temp_allocator)
	// All of it: unchanged (still closed).
	Vector_PathTrim(&sq, 0, 1, 0, &out)
	testing.expect_value(t, len(out.cmds), len(sq.cmds))
	testing.expect_value(t, out.cmds[len(out.cmds) - 1], Vector_Cmd.Close)
	// Half: an open path half as long, from the start along the top and down.
	clear(&out.cmds); clear(&out.pts)
	Vector_PathTrim(&sq, 0, 0.5, 0, &out)
	testing.expect(t, near(Vector_PathLength(&out), 200), "half")
	testing.expect(t, out.cmds[len(out.cmds) - 1] != .Close, "open")
	last := out.pts[len(out.pts) - 1]
	testing.expect(t, near(last.x, 100) && near(last.y, 100), "ends at the second corner")
	// The middle quarter, mid-segment cuts.
	clear(&out.cmds); clear(&out.pts)
	Vector_PathTrim(&sq, 0.125, 0.375, 0, &out)
	testing.expect(t, near(Vector_PathLength(&out), 100), "a quarter")
	testing.expect(t, near(out.pts[0].x, 50) && near(out.pts[0].y, 0), "starts mid-top")
	// Offset wraps round the end: two pieces, the same length.
	clear(&out.cmds); clear(&out.pts)
	Vector_PathTrim(&sq, 0, 0.25, 0.875, &out)
	testing.expect(t, near(Vector_PathLength(&out), 100), "wrapped quarter")
	moves := 0
	for c in out.cmds do if c == .Move do moves += 1
	testing.expect_value(t, moves, 2)
	// Nothing; start > end swaps.
	clear(&out.cmds); clear(&out.pts)
	Vector_PathTrim(&sq, 0.5, 0.5, 0, &out)
	testing.expect_value(t, len(out.cmds), 0)
	Vector_PathTrim(&sq, 0.5, 0, 0, &out)
	testing.expect(t, near(Vector_PathLength(&out), 200), "swapped")
	// A circle's length (curves sampled): 2 pi r.
	c: Vector_Path
	Vector_Path_Init(&c, context.temp_allocator)
	Vector_Ellipse(&c, {0, 0}, {50, 50})
	testing.expect(t, near(Vector_PathLength(&c), 2 * math.PI * 50, 1), "circle")
	// Two subpaths: in turn (the first one first) or each on its own.
	Vector_Ellipse(&c, {0, 0}, {25, 25})
	clear(&out.cmds); clear(&out.pts)
	Vector_PathTrim(&c, 0, 0.5, 0, &out)
	moves = 0
	for k in out.cmds do if k == .Move do moves += 1
	testing.expect_value(t, moves, 1)
	clear(&out.cmds); clear(&out.pts)
	Vector_PathTrim(&c, 0, 0.5, 0, &out, each = true)
	moves = 0
	for k in out.cmds do if k == .Move do moves += 1
	testing.expect_value(t, moves, 2)
	testing.expect(t, near(Vector_PathLength(&out), math.PI * 75, 1), "half of each circle")
}

@(test)
test_vector_morph :: proc(t: ^testing.T) {
	sq, circle, out: Vector_Path
	Vector_Path_Init(&sq, context.temp_allocator)
	Vector_Path_Init(&circle, context.temp_allocator)
	Vector_Path_Init(&out, context.temp_allocator)
	square(&sq, 100)
	Vector_Ellipse(&circle, {50, 50}, {50, 50})
	// The ends are the paths themselves.
	Vector_PathMorph(&sq, &circle, 0, &out)
	testing.expect_value(t, len(out.pts), len(sq.pts))
	clear(&out.cmds); clear(&out.pts)
	Vector_PathMorph(&sq, &circle, 1, &out)
	testing.expect_value(t, len(out.pts), len(circle.pts))
	// Between: one closed path, its length between the two.
	clear(&out.cmds); clear(&out.pts)
	Vector_PathMorph(&sq, &circle, 0.5, &out)
	testing.expect_value(t, out.cmds[0], Vector_Cmd.Move)
	testing.expect_value(t, out.cmds[len(out.cmds) - 1], Vector_Cmd.Close)
	l := Vector_PathLength(&out)
	testing.expect(t, l < 400 && l > 2 * math.PI * 50, "between a square and a circle")
	// Turned the other way round, it still morphs without collapsing (aligned).
	rev: Vector_Path
	Vector_Path_Init(&rev, context.temp_allocator)
	Vector_MoveTo(&rev, {0, 0}); Vector_LineTo(&rev, {0, 100}); Vector_LineTo(&rev, {100, 100}); Vector_LineTo(&rev, {100, 0}); Vector_Close(&rev)
	clear(&out.cmds); clear(&out.pts)
	Vector_PathMorph(&sq, &rev, 0.5, &out)
	testing.expect(t, near(Vector_PathLength(&out), 400, 1), "the same square drawn backwards: no twist")
	// A missing subpath grows from a point.
	two: Vector_Path
	Vector_Path_Init(&two, context.temp_allocator)
	square(&two, 100)
	Vector_Ellipse(&two, {300, 50}, {20, 20})
	clear(&out.cmds); clear(&out.pts)
	Vector_PathMorph(&sq, &two, 0.5, &out)
	moves := 0
	for c in out.cmds do if c == .Move do moves += 1
	testing.expect_value(t, moves, 2)

	// Styles: colours and widths blend, a missing stroke fades in.
	a := VECTOR_STYLE_DEFAULT
	a.fill, a.fillColor = true, {255, 0, 0, 255}
	b := VECTOR_STYLE_DEFAULT
	b.fill, b.fillColor = true, {0, 0, 255, 255}
	b.stroke, b.strokeColor, b.strokeWidth = true, {0, 0, 0, 255}, 4
	m := Vector_StyleMorph(a, b, 0.5)
	testing.expect_value(t, m.fillColor, [4]u8{128, 0, 128, 255})
	testing.expect(t, m.stroke && m.strokeWidth == 4 && m.strokeColor[3] == 128, "the stroke fades in")
	// Gradients with the same stops blend.
	a.fillPaint = Vector_LinearGradient({0, 0}, {100, 0}, {{0, {0, 0, 0, 255}}, {1, {255, 255, 255, 255}}})
	b.fillPaint = Vector_LinearGradient({0, 0}, {0, 100}, {{0, {255, 0, 0, 255}}, {1, {255, 255, 255, 255}}})
	m = Vector_StyleMorph(a, b, 0.5)
	testing.expect(t, m.fillPaint.kind == .Linear && m.fillPaint.stops[0].color == {128, 0, 0, 255} && m.fillPaint.p1 == {50, 50}, "gradient blend")
	// A solid colour and a gradient blend too (the colour as a flat gradient).
	b.fillPaint = {}
	m = Vector_StyleMorph(a, b, 0.5)
	testing.expect(t, m.fillPaint.kind == .Linear && m.fillPaint.stops[1].color == {128, 128, 255, 255}, "solid -> gradient")

	// Shape lists: an extra shape fades out.
	sa := make([dynamic]Vector_Shape, context.temp_allocator)
	sb := make([dynamic]Vector_Shape, context.temp_allocator)
	append(&sa, Vector_Shape{path = sq, style = a}, Vector_Shape{path = circle, style = a})
	append(&sb, Vector_Shape{path = circle, style = b})
	res := make([dynamic]Vector_Shape, context.temp_allocator)
	{
		context.allocator = context.temp_allocator
		Vector_ShapesMorph(sa[:], sb[:], 0.75, &res)
	}
	testing.expect_value(t, len(res), 2)
	testing.expect(t, near(res[1].style.opacity, 0.25, 0.01), "the extra shape at a quarter")
}

// The node: trimming / morphing makes its own mesh, only when they change.
@(test)
test_vector_node_fx :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("vfx", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	v := cast(^VectorShapeNode)Node_CreateByTypeName(scene, "VectorShapeNode")
	v.gameContext = &game.gameContext
	testing.expect(t, !VectorShapeNode_FxActive(v), "off by default (trimEnd 1)")
	v.preset = .Ring
	VectorShapeNode_Build(v)
	v.trimEnd = 0.5
	testing.expect(t, VectorShapeNode_FxActive(v), "trim on")
	_ = VectorShapeNode_FxShapes(v)
	n := len(v.fx)
	testing.expect_value(t, n, len(v.shapes))
	key := v.fxKey
	_ = VectorShapeNode_FxShapes(v)
	testing.expect(t, v.fxKey == key, "unchanged: not rebuilt")
	v.trimEnd = 0.75
	_ = VectorShapeNode_FxShapes(v)
	testing.expect(t, v.fxKey != key, "changed: rebuilt")
	// A morph target that isn't in the (preset's) file: ignored, not a crash.
	v.morphTo = "nothing"
	v.morph = 0.5
	_ = VectorShapeNode_FxShapes(v)
}
