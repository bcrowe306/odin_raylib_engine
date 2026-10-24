package engine

import "core:strings"
import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

// ============================================================================
// 2D lighting.
//
// LightNode: a point light or a spot cone (rotation = direction) with a
// colour, energy, radius and falloff, optionally casting shadows from the
// scene's physics shapes (StaticBody / DynamicBody / CharacterMover,
// sensors excluded - so LDtk and tile map colliders cast shadows too).
//
// When a scene has lights (or a non-white ambient), a light map is built
// each frame: cleared to the scene's ambient colour, each light added on
// top (its shadows cut out of its own contribution), then multiplied over
// the world layers. UI layers aren't lit.
//
// Order: Lighting_Prepare (before the frame's drawing target is set up:
// it renders into its own render texture), the scene's world layers, then
// Lighting_Composite in screen space.
// ============================================================================

Light_Kind :: enum {
	Point,
	Spot,
}

LightNode :: struct {
	using node: Node,
	kind:    Light_Kind `gui:"true"`,
	color:   rl.Color `gui:"true"`,
	energy:  f32 `gui:"true" min:"0" max:"8"`,
	radius:  f32 `gui:"true" min:"1" max:"4000"`,
	falloff: f32 `gui:"true" min:"0.1" max:"8"`,  // 1 linear, 2 smooth, higher = tighter
	spread:  f32 `gui:"true" min:"1" max:"180"`,  // spot: half-angle of the cone (degrees)
	shadows: bool `gui:"true"`,
}

LightNode_Create :: proc(scene: ^Scene, name: string = "Light", parent: ^Node = nil) -> ^LightNode {
	l := CreateNode(scene.manager, LightNode)
	l.name = strings.clone(name, l.allocator) // owned: callers pass temp strings too
	l.color = {255, 236, 200, 255}
	l.energy = 1
	l.radius = 256
	l.falloff = 2
	l.spread = 35
	l.shadows = true
	scene->addNode(l, parent)
	return l
}

@(private = "file")
LIGHT_SHADER :: `#version 330
in vec2 fragTexCoord;
in vec4 fragColor;
out vec4 finalColor;
uniform float falloff;
uniform float spread;   // cos of the cone half-angle (-1 = point light)
void main() {
    vec2 d = fragTexCoord * 2.0 - 1.0;   // -1..1 across the light's square
    float r = length(d);
    if (r > 1.0) discard;
    float a = pow(1.0 - r, falloff);
    if (spread > -1.0) {
        // The cone points along +x of the quad (rotated by the light).
        float c = r > 0.0001 ? d.x / r : 1.0;
        a *= smoothstep(spread, mix(spread, 1.0, 0.15), c);
    }
    finalColor = vec4(fragColor.rgb * a * fragColor.a, 1.0);
}
`

@(private = "file")
lighting: struct {
	shader:     rl.Shader,
	shaderOk:   bool,
	locFalloff: i32,
	locSpread:  i32,
	lightMap:   rl.RenderTexture2D,
	scratch:    rl.RenderTexture2D, // one light at a time (with its shadows)
	size:       [2]i32,
	ready:      bool, // a light map was prepared this frame
}

// Scene_HasLighting: lights, or an ambient that isn't white.
Scene_HasLighting :: proc(scene: ^Scene) -> bool {
	if scene == nil || scene.manager == nil do return false
	if scene.ambient != {} && scene.ambient != {255, 255, 255, 255} do return true
	for n in scene.manager.nodes do if n != nil && n.typeId == LightNode && n.enabled do return true
	return false
}

@(private = "file")
ensure_targets :: proc(w, h: i32) -> bool {
	if !rl.IsWindowReady() || w <= 0 || h <= 0 do return false
	if !lighting.shaderOk {
		lighting.shader = rl.LoadShaderFromMemory(nil, LIGHT_SHADER)
		if !rl.IsShaderValid(lighting.shader) do return false
		lighting.locFalloff = rl.GetShaderLocation(lighting.shader, "falloff")
		lighting.locSpread = rl.GetShaderLocation(lighting.shader, "spread")
		lighting.shaderOk = true
	}
	if lighting.size != {w, h} {
		if lighting.lightMap.id != 0 {
			rl.UnloadRenderTexture(lighting.lightMap)
			rl.UnloadRenderTexture(lighting.scratch)
		}
		lighting.lightMap = rl.LoadRenderTexture(w, h)
		lighting.scratch = rl.LoadRenderTexture(w, h)
		lighting.size = {w, h}
	}
	return true
}

// Lighting_Unload releases the light map and shader.
Lighting_Unload :: proc() {
	if !rl.IsWindowReady() do return
	if lighting.lightMap.id != 0 {
		rl.UnloadRenderTexture(lighting.lightMap)
		rl.UnloadRenderTexture(lighting.scratch)
	}
	if lighting.shaderOk do rl.UnloadShader(lighting.shader)
	lighting = {}
}

// occluder_polygons: world-space outlines of the shapes that cast shadows.
@(private = "file")
occluder_polygons :: proc(scene: ^Scene) -> [dynamic][dynamic][2]f32 {
	out := make([dynamic][dynamic][2]f32, context.temp_allocator)
	for n in scene.manager.nodes {
		if n == nil || !n.enabled do continue
		shapes: []PhysicsShape
		switch n.typeId {
		case StaticBodyNode:     shapes = (cast(^StaticBodyNode)n).shapes[:]
		case DynamicBodyNode:    shapes = (cast(^DynamicBodyNode)n).shapes[:]
		case CharacterMoverNode: shapes = (cast(^CharacterMoverNode)n).shapes[:]
		}
		for &s in shapes {
			if s.isSensor do continue
			g := PhysicsShape_Scaled(&s, n.globalScale)
			rot := n.globalRotation
			poly := make([dynamic][2]f32, context.temp_allocator)
			to_world :: proc(n: ^Node, g: ^PhysicsShape, rot: f32, q: [2]f32) -> [2]f32 {
				local := g.offset + rotate_vec(q, g.rotation)
				return n.globalPosition + rotate_vec(local, rot)
			}
			#partial switch g.type {
			case .Box, .RoundedBox:
				hw, hh := g.size.x * 0.5, g.size.y * 0.5
				for q in ([4][2]f32{{-hw, -hh}, {hw, -hh}, {hw, hh}, {-hw, hh}}) do append(&poly, to_world(n, &g, rot, q))
			case .Polygon:
				for v in g.vertices[:clamp(g.vertexCount, 3, len(g.vertices))] do append(&poly, to_world(n, &g, rot, v))
			case .Circle, .Capsule:
				half := g.size.y * 0.5 if g.type == .Capsule else 0
				for k in 0 ..< 12 {
					a := f32(k) / 12 * math.TAU
					c := [2]f32{math.cos(a), math.sin(a)} * g.radius
					c.y += half if c.y > 0 else -half
					append(&poly, to_world(n, &g, rot, c))
				}
			case .Segment:
				append(&poly, to_world(n, &g, rot, g.point1), to_world(n, &g, rot, g.point2))
			}
			if len(poly) >= 2 do append(&out, poly)
		}
	}
	return out
}

// Lighting_Prepare renders the light map for a camera on a w x h target.
// Call before the frame's own render target is bound (it renders into its
// own textures). Returns false when the scene has no lighting.
Lighting_Prepare :: proc(scene: ^Scene, cam: rl.Camera2D, w, h: i32) -> bool {
	lighting.ready = false
	if !Scene_HasLighting(scene) || !ensure_targets(w, h) do return false
	ambient := scene.ambient if scene.ambient != {} else rl.Color{255, 255, 255, 255}
	view := Camera2D_ViewRect(cam, f32(w), f32(h))
	occluders: [dynamic][dynamic][2]f32
	haveOccluders := false

	rl.BeginTextureMode(lighting.lightMap)
	rl.ClearBackground(ambient)
	rl.EndTextureMode()

	for n in scene.manager.nodes {
		if n == nil || n.typeId != LightNode || !n.enabled do continue
		l := cast(^LightNode)n
		r := l.radius * max(abs(l.globalScale.x), abs(l.globalScale.y))
		if r <= 0 || l.energy <= 0 do continue
		c := l.globalPosition
		if c.x + r < view.x || c.x - r > view.x + view.width || c.y + r < view.y || c.y - r > view.y + view.height do continue

		// The light on its own target, shadows cut out, then added to the map.
		rl.BeginTextureMode(lighting.scratch)
		rl.ClearBackground(rl.BLACK)
		rl.BeginMode2D(cam)
		rl.BeginShaderMode(lighting.shader)
		falloff := max(l.falloff, 0.1)
		spread: f32 = -1
		if l.kind == .Spot do spread = math.cos(math.to_radians(clamp(l.spread, 1, 180)))
		rl.SetShaderValue(lighting.shader, lighting.locFalloff, &falloff, .FLOAT)
		rl.SetShaderValue(lighting.shader, lighting.locSpread, &spread, .FLOAT)
		col := l.color
		e := clamp(l.energy, 0, 8)
		col = {u8(min(f32(col.r) * e, 255)), u8(min(f32(col.g) * e, 255)), u8(min(f32(col.b) * e, 255)), 255}
		// A textured quad (default white texture) so the shader gets UVs.
		tex := rl.Texture2D{id = rlgl.GetTextureIdDefault(), width = 1, height = 1, mipmaps = 1, format = .UNCOMPRESSED_R8G8B8A8}
		rl.DrawTexturePro(tex, {0, 0, 1, 1}, {c.x, c.y, r * 2, r * 2}, {r, r}, l.globalRotation, col)
		rl.EndShaderMode()
		if l.shadows {
			if !haveOccluders {
				occluders = occluder_polygons(scene)
				haveOccluders = true
			}
			far := r * 4
			for poly in occluders {
				n := len(poly)
				for i in 0 ..< n {
					if n == 2 && i == 1 do break
					a, b := poly[i], poly[(i + 1) % n]
					// Edges out of the light's reach cast nothing.
					if !segment_near(c, a, b, r) do continue
					da := a - c
					db := b - c
					la := math.sqrt(da.x * da.x + da.y * da.y)
					lb := math.sqrt(db.x * db.x + db.y * db.y)
					if la < 0.001 || lb < 0.001 do continue
					a2 := a + da / la * far
					b2 := b + db / lb * far
					rl.DrawTriangle(a, a2, b2, rl.BLACK)
					rl.DrawTriangle(a, b2, a2, rl.BLACK)
					rl.DrawTriangle(a, b2, b, rl.BLACK)
					rl.DrawTriangle(a, b, b2, rl.BLACK)
				}
			}
		}
		rl.EndMode2D()
		rl.EndTextureMode()

		rl.BeginTextureMode(lighting.lightMap)
		rl.BeginBlendMode(.ADDITIVE)
		st := lighting.scratch.texture
		rl.DrawTextureRec(st, {0, 0, f32(st.width), -f32(st.height)}, {0, 0}, rl.WHITE)
		rl.EndBlendMode()
		rl.EndTextureMode()
	}
	lighting.ready = true
	Render_RestoreFrameTarget() // post effects: back to the frame's target
	return true
}

@(private = "file")
segment_near :: proc(c, a, b: [2]f32, r: f32) -> bool {
	ab := b - a
	l2 := ab.x * ab.x + ab.y * ab.y
	t: f32 = 0
	if l2 > 0 do t = clamp(((c - a).x * ab.x + (c - a).y * ab.y) / l2, 0, 1)
	p := a + ab * t
	d := p - c
	return d.x * d.x + d.y * d.y <= r * r
}

// Lighting_Composite multiplies the light map over what has been drawn
// (screen space, the same w x h as Lighting_Prepare).
Lighting_Composite :: proc() {
	if !lighting.ready do return
	t := lighting.lightMap.texture
	rl.BeginBlendMode(.MULTIPLIED)
	m := renderPixel.margin // (inside the smooth camera's world texture)
	rl.DrawTextureRec(t, {0, 0, f32(t.width), -f32(t.height)}, {m, m}, rl.WHITE)
	rl.EndBlendMode()
	lighting.ready = false
}

// Lighting_LightMapTexture: the last light map (tests, debugging).
Lighting_LightMapTexture :: proc() -> rl.Texture2D {
	return lighting.lightMap.texture
}

LightNode_KindName :: proc(k: Light_Kind) -> string {
	return "spot" if k == .Spot else "point"
}
