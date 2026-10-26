package engine

import "core:math"
import "core:strings"
import "core:testing"

// SVG import (Phase 14 M2): the path grammar, arcs, colours, transforms,
// units, CSS, inheritance, gradients, clips, groups and warnings - on
// fixtures shaped like Inkscape / Illustrator / Affinity / Figma exports
// (tests/vector/svg).

@(private = "file")
SVG_INKSCAPE :: #load("../tests/vector/svg/inkscape_character.svg", string)
@(private = "file")
SVG_ILLUSTRATOR :: #load("../tests/vector/svg/illustrator_css.svg", string)
@(private = "file")
SVG_AFFINITY :: #load("../tests/vector/svg/affinity_presentation.svg", string)
@(private = "file")
SVG_FIGMA :: #load("../tests/vector/svg/figma_export.svg", string)

@(private = "file")
shape_box :: proc(s: ^Vector_Shape) -> [4]f32 {
	b := [4]f32{max(f32), max(f32), min(f32), min(f32)}
	for p in s.path.pts {
		b[0] = min(b[0], p.x); b[1] = min(b[1], p.y)
		b[2] = max(b[2], p.x); b[3] = max(b[3], p.y)
	}
	return b
}

@(private = "file")
near :: proc(a, b: f32, eps: f32 = 0.01) -> bool {return abs(a - b) <= eps}

@(test)
test_svg_path_grammar :: proc(t: ^testing.T) {
	p: Vector_Path
	Vector_Path_Init(&p)
	defer Vector_Path_Destroy(&p)
	// Absolute / relative, implicit lines after M, H / V, smooth curves, packed numbers.
	Vector_ParsePathData("M10 10 20 10 h10 v10 H10 z m5,5 l5-5 c1,2,3,4,5,6 s7,8,9,10 Q0 0 1 1 T 4 4 .5.5", &p)
	cmds := p.cmds[:]
	testing.expect_value(t, cmds[0], Vector_Cmd.Move)
	testing.expect_value(t, cmds[1], Vector_Cmd.Line) // (implicit)
	testing.expect_value(t, p.pts[1], [2]f32{20, 10})
	testing.expect_value(t, p.pts[2], [2]f32{30, 10}) // h10
	testing.expect_value(t, p.pts[3], [2]f32{30, 20}) // v10
	testing.expect_value(t, p.pts[4], [2]f32{10, 20}) // H10
	testing.expect_value(t, cmds[5], Vector_Cmd.Close)
	testing.expect_value(t, p.pts[5], [2]f32{15, 15}) // m5,5 from the subpath start (10, 10)
	testing.expect_value(t, p.pts[6], [2]f32{20, 10}) // l5-5
	// s reflects the previous control point: c ended at (25, 16) with c2 (23, 14).
	ci := 0
	for c, i in cmds do if c == .Cubic {ci = i; break}
	_ = ci
	last := p.pts[len(p.pts) - 1]
	testing.expect(t, near(last.x, 0.5) && near(last.y, 0.5), "T then an implicit absolute T with packed .5.5")
	// Exponents and arc flags packed together.
	Vector_Path_Clear(&p)
	Vector_ParsePathData("M0 0L1e2 0a50 50 0 0150 50", &p)
	testing.expect_value(t, p.pts[1], [2]f32{100, 0})
	end := p.pts[len(p.pts) - 1]
	testing.expect(t, near(end.x, 150) && near(end.y, 50), "packed arc flags")
	// Junk stops the parse without crashing.
	Vector_Path_Clear(&p)
	Vector_ParsePathData("M 0 0 L 10 x 20", &p)
	testing.expect_value(t, len(p.cmds), 1)
}

@(test)
test_svg_arcs :: proc(t: ^testing.T) {
	p: Vector_Path
	Vector_Path_Init(&p)
	defer Vector_Path_Destroy(&p)
	// A half circle of radius 50 from (0, 0) to (100, 0), sweeping through (50, -50) or (50, 50).
	Vector_ParsePathData("M0 0 A50 50 0 0 1 100 0", &p)
	f: Vector_Flat
	defer Vector_Flat_Destroy(&f)
	Vector_Flatten(&p, 0.05, &f)
	minY, maxY: f32 = 1e9, -1e9
	for q in f.pts {
		d := math.sqrt((q.x - 50) * (q.x - 50) + q.y * q.y)
		testing.expectf(t, abs(d - 50) < 0.2, "on the circle: %v", d)
		minY = min(minY, q.y); maxY = max(maxY, q.y)
	}
	testing.expect(t, near(minY, -50, 0.2) && maxY < 0.01, "sweep 1 goes up (screen: clockwise)")
	// Radii too small are scaled up; zero radii are a line.
	Vector_Path_Clear(&p)
	Vector_ParsePathData("M0 0 A1 1 0 0 0 100 0", &p)
	testing.expect(t, near(p.pts[len(p.pts) - 1].x, 100), "small radii scaled")
	Vector_Path_Clear(&p)
	Vector_ParsePathData("M0 0 A0 10 0 0 0 100 0", &p)
	testing.expect_value(t, p.cmds[1], Vector_Cmd.Line)
}

@(test)
test_svg_colors_transforms :: proc(t: ^testing.T) {
	c, ok := Vector_ParseColor("#f80")
	testing.expect(t, ok && c == {255, 136, 0, 255}, "#rgb")
	c, _ = Vector_ParseColor("#11223344")
	testing.expect_value(t, c, [4]u8{0x11, 0x22, 0x33, 0x44})
	c, _ = Vector_ParseColor("rgb(255, 0, 128)")
	testing.expect_value(t, c, [4]u8{255, 0, 128, 255})
	c, _ = Vector_ParseColor("rgba(100%, 50%, 0%, 0.5)")
	testing.expect_value(t, c, [4]u8{255, 127, 0, 128})
	c, _ = Vector_ParseColor("hsl(120, 100%, 50%)")
	testing.expect_value(t, c, [4]u8{0, 255, 0, 255})
	c, _ = Vector_ParseColor("RebeccaPurple")
	testing.expect_value(t, c, [4]u8{0x66, 0x33, 0x99, 255})
	_, ok = Vector_ParseColor("notacolour")
	testing.expect(t, !ok, "unknown")
	m := Vector_ParseTransform("translate(10, 20) scale(2)")
	testing.expect_value(t, m, [6]f32{2, 0, 0, 2, 10, 20})
	m = Vector_ParseTransform("rotate(90 10 10)")
	// (10, 0) rotated 90 degrees about (10, 10) -> (20, 10).
	x := m[0] * 10 + m[2] * 0 + m[4]
	y := m[1] * 10 + m[3] * 0 + m[5]
	testing.expect(t, near(x, 20) && near(y, 10), "rotate about a point")
	m = Vector_ParseTransform("matrix(1,0,0,1,5,6)skewX(0)")
	testing.expect_value(t, m, [6]f32{1, 0, 0, 1, 5, 6})
}

@(test)
test_svg_inkscape :: proc(t: ^testing.T) {
	doc: Vector_Doc
	defer Vector_Doc_Destroy(&doc)
	testing.expect(t, Vector_LoadSVG(SVG_INKSCAPE, &doc), "loaded")
	// 200mm with a 200-unit viewBox: 1 unit = 3.78 px.
	testing.expect(t, near(doc.size.x, 755.9, 0.2), "mm size")
	// Body, its button, head, 2 eyes, mouth (the display:none path and the text are skipped).
	testing.expect_value(t, len(doc.shapes), 6)
	// Layers as groups, by their labels.
	names := make([dynamic]string, context.temp_allocator)
	for g in doc.groups do append(&names, g.name)
	testing.expect(t, len(names) == 2 && names[0] == "Body" && names[1] == "Head", "layer labels")
	testing.expect_value(t, doc.groups[1].count, 4)
	// The body: blue fill, dark stroke scaled with the document (2.5 units).
	body := &doc.shapes[0]
	testing.expect_value(t, body.style.fillColor, [4]u8{0x5b, 0x7f, 0xd6, 255})
	testing.expect(t, near(body.style.strokeWidth, 2.5 * 3.7795, 0.01), "stroke width in px")
	testing.expect_value(t, body.style.join, Vector_Join.Round)
	// The layer's translate(0,10) is baked: the body's top is at (110 + 10) units.
	testing.expect(t, near(shape_box(body)[1], 120 * 3.7795, 0.1), "group transform baked")
	// The head: a radial gradient through the xlink:href chain (2 stops), user space.
	head := &doc.shapes[2]
	testing.expect_value(t, head.style.fillPaint.kind, Vector_Paint_Kind.Radial)
	testing.expect_value(t, head.style.fillPaint.stopCount, 2)
	testing.expect_value(t, head.style.fillPaint.stops[0].color, [4]u8{0xff, 0xd5, 0xa8, 255})
	// The gradient's centre maps to the head's centre in document space.
	g := Vector_PaintCoord(&head.style.fillPaint, {100 * 3.7795, 70 * 3.7795})
	testing.expect(t, abs(g.x) < 0.01 && abs(g.y) < 0.01, "gradient centre at the head's")
	// The mouth: an arc, round caps, no fill.
	mouth := &doc.shapes[5]
	testing.expect(t, !mouth.style.fill && mouth.style.stroke && mouth.style.cap == .Round, "the mouth's stroke")
	// Warnings: the text, the focal point.
	all := strings.join(doc.warnings[:], "|", context.temp_allocator)
	testing.expect(t, strings.contains(all, "text isn't supported"), "text warning")
	testing.expect(t, strings.contains(all, "focal"), "focal warning")
}

@(test)
test_svg_illustrator :: proc(t: ^testing.T) {
	doc: Vector_Doc
	defer Vector_Doc_Destroy(&doc)
	testing.expect(t, Vector_LoadSVG(SVG_ILLUSTRATOR, &doc), "loaded")
	testing.expect_value(t, doc.size, [2]f32{240, 160}) // (no width / height: the viewBox)
	// Sun circle, star polygon, polyline, clipped circle, gradient path, faded rect.
	testing.expect_value(t, len(doc.shapes), 6)
	testing.expect_value(t, doc.shapes[0].style.fillColor, [4]u8{0xe8, 0xb0, 0x4a, 255}) // .st0
	poly := &doc.shapes[1]
	testing.expect(t, !poly.style.fill && poly.style.stroke && near(poly.style.strokeWidth, 3), ".st1: stroke only")
	testing.expect_value(t, poly.style.miterLimit, 10)
	testing.expect_value(t, poly.path.cmds[len(poly.path.cmds) - 1], Vector_Cmd.Close) // polygon closes
	testing.expect(t, doc.shapes[2].path.cmds[len(doc.shapes[2].path.cmds) - 1] != .Close, "polyline stays open")
	// The clip (from <clipPath><use href=rect>) is the 60x60 square.
	clipped := &doc.shapes[3]
	testing.expect(t, clipped.clip != nil, "clipped")
	if clipped.clip != nil {
		b := [4]f32{max(f32), max(f32), min(f32), min(f32)}
		for q in clipped.clip.path.pts {
			b[0] = min(b[0], q.x); b[1] = min(b[1], q.y)
			b[2] = max(b[2], q.x); b[3] = max(b[3], q.y)
		}
		testing.expect_value(t, b, [4]f32{100, 20, 160, 80})
	}
	grad := &doc.shapes[4]
	testing.expect_value(t, grad.style.fillPaint.kind, Vector_Paint_Kind.Linear)
	testing.expect_value(t, grad.style.fillPaint.stopCount, 3)
	testing.expect(t, near(doc.shapes[5].style.opacity, 0.5), ".st4 opacity")
	testing.expect_value(t, doc.groups[0].name, "Sun")
}

@(test)
test_svg_affinity_figma :: proc(t: ^testing.T) {
	doc: Vector_Doc
	testing.expect(t, Vector_LoadSVG(SVG_AFFINITY, &doc), "affinity")
	// The artboard's empty rect (fill:none) is dropped: leaf and triangle.
	testing.expect_value(t, len(doc.shapes), 2)
	leaf := &doc.shapes[0]
	testing.expect_value(t, leaf.style.fillRule, Vector_Fill_Rule.EvenOdd) // inherited from the root's style
	testing.expect_value(t, leaf.style.fillColor, [4]u8{76, 175, 80, 255})
	testing.expect(t, near(leaf.style.strokeWidth, 4 * math.sqrt(f32(0.68)), 0.01), "stroke scaled by the matrix")
	testing.expect_value(t, doc.groups[1].name, "Leaf")
	testing.expect_value(t, doc.shapes[1].style.fillColor.a, 204) // fill-opacity 0.8
	Vector_Doc_Destroy(&doc)

	testing.expect(t, Vector_LoadSVG(SVG_FIGMA, &doc), "figma")
	defer Vector_Doc_Destroy(&doc)
	testing.expect_value(t, len(doc.shapes), 3)
	// The group's clip-path (a rounded rect) clips all three.
	for &sh in doc.shapes do testing.expect(t, sh.clip != nil, "the group's clip")
	// The rect: a gradient with rounded corners.
	rect := &doc.shapes[0]
	testing.expect_value(t, rect.style.fillPaint.kind, Vector_Paint_Kind.Linear)
	testing.expect(t, len(rect.path.cmds) > 5, "rounded corners")
	ring := &doc.shapes[1]
	testing.expect_value(t, ring.style.fillRule, Vector_Fill_Rule.EvenOdd)
	testing.expect_value(t, ring.style.fillColor.a, 230)
	line := &doc.shapes[2]
	testing.expect_value(t, line.style.dash.count, 2)
	testing.expect_value(t, line.style.cap, Vector_Cap.Round)
	// Tessellating the imported shapes works (the ring keeps its hole).
	tess: Vector_Tess
	defer Vector_Tess_Destroy(&tess)
	m: Vector_Mesh
	defer Vector_Mesh_Destroy(&m)
	Vector_Tessellate(&tess, doc.shapes[1:2], 1, &m)
	testing.expect(t, len(m.idx) > 0, "tessellated")
}

@(test)
test_svg_rejects :: proc(t: ^testing.T) {
	doc: Vector_Doc
	defer Vector_Doc_Destroy(&doc)
	testing.expect(t, !Vector_LoadSVG("not xml at all", &doc), "junk")
	Vector_Doc_Destroy(&doc)
	testing.expect(t, !Vector_LoadSVG("<html><body/></html>", &doc), "not svg")
	Vector_Doc_Destroy(&doc)
	// A <use> loop doesn't hang.
	testing.expect(t, Vector_LoadSVG(`<svg xmlns="http://www.w3.org/2000/svg"><g id="a"><use href="#a"/></g></svg>`, &doc), "loop")
}
