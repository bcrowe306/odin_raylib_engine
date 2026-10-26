package engine

import "core:math"
import rl "vendor:raylib"

// ============================================================================
// VectorShapeNode: draws vector shapes - crisp at any zoom, tessellated once
// per scale bucket and cached (vector_mesh.odin). Phase 14 M0: built-in
// preset shapes (a star, a ring, a badge, a procedural character used by
// the benchmark); vector assets (SVG import, symbols) come in M2 / M3.
// ============================================================================

Vector_Preset :: enum u8 {
	Star,
	Ring,
	Badge,
	Character,
	Gradients,
}

VectorShapeNode :: struct {
	using node:  Node,
	preset:      Vector_Preset `gui:"true"`,
	fillColor:   rl.Color `gui:"true"`,
	strokeColor: rl.Color `gui:"true"`,
	strokeWidth: f32 `gui:"true" min:"0" max:"64"`,
	tint:        rl.Color `gui:"true"`,
	shapes:      [dynamic]Vector_Shape,
	cache:       Vector_Cache,
	built:       struct {preset: Vector_Preset, fill, stroke: rl.Color, width: f32, ok: bool},
}

// The main thread's tessellation scratch (worker threads get their own in M2).
@(private = "file")
vectorTess: Vector_Tess

VectorShapeNode_Create :: proc(scene: ^Scene, name: string = "VectorShape", parent: ^Node = nil) -> ^VectorShapeNode {
	v := CreateNode(scene.manager, VectorShapeNode)
	v.name = clone_name(name, v.allocator)
	v.preset = .Star
	v.fillColor = {255, 196, 64, 255}
	v.strokeColor = {40, 24, 8, 255}
	v.strokeWidth = 4
	v.tint = rl.WHITE
	// (Meshes are rebuilt on zoom: the heap, not the node's arena.)
	v.shapes = make([dynamic]Vector_Shape, Engine_HeapAllocator())
	v.render = VectorShapeNode_Render
	v.onDestroy = proc(n: ^Node, ctx: ^GameContext) {
		v := cast(^VectorShapeNode)n
		vector_shapes_free(&v.shapes)
		delete(v.shapes)
		Vector_Cache_Destroy(&v.cache)
	}
	scene->addNode(v, parent)
	return v
}

@(private = "file")
clone_name :: proc(name: string, allocator := context.allocator) -> string {
	b := make([]u8, len(name), allocator)
	copy(b, name)
	return string(b)
}

@(private = "file")
vector_shapes_free :: proc(shapes: ^[dynamic]Vector_Shape) {
	for &s in shapes do Vector_Path_Destroy(&s.path)
	clear(shapes)
}

// VectorShapeNode_Build (re)makes the shapes from the properties.
VectorShapeNode_Build :: proc(v: ^VectorShapeNode) {
	context.allocator = Engine_HeapAllocator()
	vector_shapes_free(&v.shapes)
	fill := [4]u8{v.fillColor.r, v.fillColor.g, v.fillColor.b, v.fillColor.a}
	line := [4]u8{v.strokeColor.r, v.strokeColor.g, v.strokeColor.b, v.strokeColor.a}
	Vector_PresetShapes(v.preset, fill, line, v.strokeWidth, &v.shapes)
	v.built = {v.preset, v.fillColor, v.strokeColor, v.strokeWidth, true}
	v.cache.dirty = true
}

VectorShapeNode_Render :: proc(node: ^Node, ctx: ^GameContext, dt: f32) {
	v := cast(^VectorShapeNode)node
	if !rl.IsWindowReady() do return
	if !v.built.ok || v.built.preset != v.preset || v.built.fill != v.fillColor || v.built.stroke != v.strokeColor || v.built.width != v.strokeWidth {
		VectorShapeNode_Build(v)
	}
	{
		context.allocator = Engine_HeapAllocator()
		Vector_Cache_Ensure(&v.cache, &vectorTess, v.shapes[:], Vector_ScreenPixel(v.globalScale))
	}
	Vector_Cache_Draw(&v.cache, v.globalPosition, v.globalRotation, v.globalScale, v.tint)
}

// Vector_ShutdownScratch frees the main thread's tessellation buffers
// (engine shutdown; leak checks).
Vector_ShutdownScratch :: proc() {
	Vector_Tess_Destroy(&vectorTess)
}

// --- presets ------------------------------------------------------------------------

// Vector_PresetShapes appends a preset's shapes (centred on 0, 0; about
// 200 px across). Character is deliberately busy (hundreds of curves): the
// benchmark's stand-in for a detailed Flash-style character.
Vector_PresetShapes :: proc(preset: Vector_Preset, fill, line: [4]u8, width: f32, out: ^[dynamic]Vector_Shape) {
	// (The returned path is only valid until the next shape is added.)
	shape :: proc(out: ^[dynamic]Vector_Shape, fill: [4]u8, line: [4]u8, width: f32, join := Vector_Join.Round) -> ^Vector_Path {
		s := Vector_Shape{style = VECTOR_STYLE_DEFAULT}
		Vector_Path_Init(&s.path)
		s.style.fillColor = fill
		s.style.fill = fill.a > 0
		s.style.strokeColor = line
		s.style.strokeWidth = width
		s.style.stroke = width > 0 && line.a > 0
		s.style.join = join
		s.style.cap = .Round
		append(out, s)
		return &out[len(out) - 1].path
	}
	switch preset {
	case .Star:
		p := shape(out, fill, line, width, .Miter)
		for i in 0 ..< 10 {
			a := f32(i) * math.PI / 5 - math.PI / 2
			r: f32 = 100 if i % 2 == 0 else 42
			pt := [2]f32{math.cos(a) * r, math.sin(a) * r}
			if i == 0 do Vector_MoveTo(p, pt)
			else do Vector_LineTo(p, pt)
		}
		Vector_Close(p)
	case .Ring:
		// A hole: the inner circle drawn the other way.
		p := shape(out, fill, line, width)
		Vector_Ellipse(p, {0, 0}, {100, 100})
		ring_inner(p, 55)
	case .Badge:
		p := shape(out, fill, line, width)
		Vector_MoveTo(p, {-90, -70})
		Vector_CubicTo(p, {-30, -110}, {30, -110}, {90, -70})
		Vector_LineTo(p, {80, 30})
		Vector_CubicTo(p, {60, 80}, {20, 100}, {0, 110})
		Vector_CubicTo(p, {-20, 100}, {-60, 80}, {-80, 30})
		Vector_Close(p)
		dot := shape(out, line, {}, 0)
		Vector_Ellipse(dot, {0, -10}, {28, 28})
	case .Character:
		character(out, fill, line, width)
	case .Gradients:
		gradients(out, fill, line, width)
	}
}

@(private = "file")
ring_inner :: proc(p: ^Vector_Path, r: f32) {
	K :: 0.5522847498
	k := r * K
	Vector_MoveTo(p, {r, 0})
	Vector_CubicTo(p, {r, -k}, {k, -r}, {0, -r})
	Vector_CubicTo(p, {-k, -r}, {-r, -k}, {-r, 0})
	Vector_CubicTo(p, {-r, k}, {-k, r}, {0, r})
	Vector_CubicTo(p, {k, r}, {r, k}, {r, 0})
	Vector_Close(p)
}

// character: a cartoon figure - body, limbs as thick strokes, a head with
// eyes, mouth and a mane of curved hair strands, and spots - ~300 curves.
@(private = "file")
character :: proc(out: ^[dynamic]Vector_Shape, fill, line: [4]u8, width: f32) {
	shape :: proc(out: ^[dynamic]Vector_Shape, fill, line: [4]u8, width: f32) -> ^Vector_Path {
		s := Vector_Shape{style = VECTOR_STYLE_DEFAULT}
		Vector_Path_Init(&s.path)
		s.style.fillColor = fill
		s.style.fill = fill.a > 0
		s.style.strokeColor = line
		s.style.strokeWidth = width
		s.style.stroke = width > 0 && line.a > 0
		s.style.join = .Round
		s.style.cap = .Round
		append(out, s)
		return &out[len(out) - 1].path
	}
	skin := [4]u8{255, 214, 170, 255}
	shirt := fill
	dark := line
	w := max(width, 2)
	// Legs and arms: open strokes.
	for side in ([]f32{-1, 1}) {
		leg := shape(out, {}, dark, 14)
		Vector_MoveTo(leg, {side * 18, 40})
		Vector_CubicTo(leg, {side * 24, 70}, {side * 14, 95}, {side * 26, 120})
		arm := shape(out, {}, skin, 10)
		Vector_MoveTo(arm, {side * 34, -20})
		Vector_CubicTo(arm, {side * 60, 0}, {side * 66, 30}, {side * 54, 55})
	}
	// Body.
	body := shape(out, shirt, dark, w)
	Vector_MoveTo(body, {-36, -30})
	Vector_CubicTo(body, {-50, 10}, {-44, 45}, {-30, 55})
	Vector_CubicTo(body, {-10, 62}, {10, 62}, {30, 55})
	Vector_CubicTo(body, {44, 45}, {50, 10}, {36, -30})
	Vector_CubicTo(body, {20, -40}, {-20, -40}, {-36, -30})
	Vector_Close(body)
	// Buttons.
	for i in 0 ..< 3 do Vector_Ellipse(shape(out, dark, {}, 0), {0, -10 + f32(i) * 18}, {4, 4})
	// Head, ears.
	for side in ([]f32{-1, 1}) do Vector_Ellipse(shape(out, skin, dark, w * 0.6), {side * 44, -78}, {9, 12})
	Vector_Ellipse(shape(out, skin, dark, w), {0, -80}, {42, 46})
	// Eyes with pupils and highlights.
	for side in ([]f32{-1, 1}) {
		Vector_Ellipse(shape(out, {255, 255, 255, 255}, dark, w * 0.5), {side * 15, -86}, {10, 12})
		Vector_Ellipse(shape(out, dark, {}, 0), {side * 14, -84}, {5, 6})
		Vector_Ellipse(shape(out, {255, 255, 255, 255}, {}, 0), {side * 12, -87}, {1.6, 1.6})
	}
	// Mouth.
	mouth := shape(out, {}, dark, w * 0.6)
	Vector_MoveTo(mouth, {-14, -58})
	Vector_CubicTo(mouth, {-6, -50}, {6, -50}, {14, -58})
	// Hair: 60 curved strands (filled leaf shapes).
	hair := [4]u8{90, 50, 30, 255}
	for i in 0 ..< 60 {
		a := math.PI + f32(i) / 59 * math.PI
		base := [2]f32{math.cos(a) * 40, -84 + math.sin(a) * 44}
		tip := base + [2]f32{math.cos(a) * 26, math.sin(a) * 26 - 6}
		nrm := [2]f32{-math.sin(a), math.cos(a)} * 5
		h := shape(out, hair, {}, 0)
		Vector_MoveTo(h, base - nrm)
		Vector_QuadTo(h, (base + tip) * 0.5 - nrm * 2, tip)
		Vector_QuadTo(h, (base + tip) * 0.5 + nrm * 2, base + nrm)
		Vector_Close(h)
	}
	// Spots on the shirt: 120 small blobs.
	for i in 0 ..< 120 {
		fi := f32(i)
		x := math.sin(fi * 12.9898) * 30
		y := 5 + math.cos(fi * 78.233) * 38
		Vector_Ellipse(shape(out, {255, 255, 255, 90}, {}, 0), {x, y}, {2.5 + math.abs(math.sin(fi)) * 2, 2.5})
	}
}

// gradients: paints and dashes - a radial orb, a linear sky, reflected
// stripes, a dashed ring.
@(private = "file")
gradients :: proc(out: ^[dynamic]Vector_Shape, fill, line: [4]u8, width: f32) {
	add :: proc(out: ^[dynamic]Vector_Shape) -> ^Vector_Shape {
		s := Vector_Shape{style = VECTOR_STYLE_DEFAULT}
		Vector_Path_Init(&s.path)
		append(out, s)
		return &out[len(out) - 1]
	}
	// A sky: a linear gradient top to bottom.
	sky := add(out)
	Vector_Rect(&sky.path, {-100, -100}, {100, 0})
	sky.style.fillPaint = Vector_LinearGradient({0, -100}, {0, 0}, {{0, {30, 60, 160, 255}}, {0.6, {240, 120, 80, 255}}, {1, {255, 210, 120, 255}}})
	// Stripes: a short linear gradient reflected across the band.
	band := add(out)
	Vector_Rect(&band.path, {-100, 0}, {100, 30})
	band.style.fillPaint = Vector_LinearGradient({-100, 0}, {-80, 0}, {{0, fill}, {1, line}}, .Reflect)
	// An orb: a radial gradient with an offset highlight (the gradient moved by its transform).
	orb := add(out)
	Vector_Ellipse(&orb.path, {0, -40}, {45, 45})
	orb.style.fillPaint = Vector_RadialGradient({0, 0}, 60, {{0, {255, 255, 255, 255}}, {0.35, {120, 200, 255, 255}}, {1, {10, 40, 120, 255}}})
	orb.style.fillPaint.transform = {1, 0, 0, 1, -15, -55}
	orb.style.stroke = true
	orb.style.strokeWidth = max(width, 1)
	orb.style.strokeColor = {10, 30, 80, 255}
	// A dashed ring (round caps) and a dotted line.
	ring := add(out)
	Vector_Ellipse(&ring.path, {0, 70}, {60, 25})
	ring.style.fill = false
	ring.style.stroke = true
	ring.style.strokeWidth = 6
	ring.style.strokeColor = line
	ring.style.cap = .Round
	ring.style.dash = {count = 2, values = {18, 10, 0, 0, 0, 0, 0, 0}}
	dots := add(out)
	Vector_MoveTo(&dots.path, {-90, 110}); Vector_LineTo(&dots.path, {90, 110})
	dots.style.fill = false
	dots.style.stroke = true
	dots.style.strokeWidth = 4
	dots.style.strokeColor = fill
	dots.style.dash = {count = 2, values = {8, 8, 0, 0, 0, 0, 0, 0}, offset = 4}
	// A half-transparent overlay (shape opacity).
	glass := add(out)
	Vector_Rect(&glass.path, {20, -90}, {90, -20})
	glass.style.fillColor = {255, 255, 255, 255}
	glass.style.opacity = 0.35
}
