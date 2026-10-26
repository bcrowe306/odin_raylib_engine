# Vector art

Rayzr draws vector shapes - fills, outlines, curves - crisp at any zoom and
anti-aliased, for Flash-style characters, UI and procedural art. This is
Phase 14 of the roadmap ([TODO_NOW.md](../../TODO_NOW.md)); it is being built
in milestones:

| Milestone | What | Status |
|---|---|---|
| M0 | The renderer: tessellation, anti-aliasing, cached GPU meshes, the Vector Shape node with built-in shapes; proven in the game, the editor and the web | **done** |
| M1 | Shapes in full: fill rules and self-intersections (Clipper2), gradients, dashes, opacity, clip paths; drawing from Lua (`on_draw` + the `Vector` module) | **done** |
| M2 | Vector assets: SVG import, the node drawing assets, picking, culling, instancing | next |
| M3 | Characters: symbols and instances, part swapping, lip-sync, timeline keys | |
| M5 | Shape tweens, vector skinning on skeletons, filters | |
| M6 | Boolean path operations, collision from shapes | |
| M4 | Drawing tools in the editor | |
| M7 | Crisp text, Adobe Animate import, a sample character | |

## Using it now

Add a **Vector Shape** (Add Node > Graphics & Rendering) and pick its
**Preset**: a star, a ring (a shape with a hole), a badge, or a detailed
cartoon character. **Fill Color**, **Stroke Color** and **Stroke Width**
style it; **Tint** multiplies everything (fade it with the alpha). Scale it,
rotate it, zoom the camera in: it stays sharp.

```lua
-- A star that pulses: only its transform changes, so it costs nothing to redraw.
local Pulse = {}

function Pulse:ready()
    self.t = 0
end

function Pulse:update(dt)
    self.t = self.t + dt
    local s = 1 + 0.1 * math.sin(self.t * 4)
    self.node.scale = Vec2(s, s)
end

return Pulse
```

## Drawing from Lua

A script that defines `on_draw()` draws with the `Vector` module in its
node's local space, in the node's draw order - see the
[scripting guide](../SCRIPTING.md#10-vector-module-vector) for every function.

```lua
-- A clock face with a gradient, ticks and a hand that follows a property.
local Clock = {}
Clock.properties = { hour = { type = "float", default = 3 } }

function Clock:on_draw()
    Vector.begin_path()
    Vector.circle(0, 0, 60)
    Vector.fill_paint(Vector.radial_gradient(-20, -20, 90, { {0, "#ffffff"}, {1, "#b0bec5"} }))
    Vector.fill()
    for i = 0, 11 do
        Vector.save()
        Vector.rotate(i * 30)
        Vector.begin_path()
        Vector.move_to(0, -52); Vector.line_to(0, -44)
        Vector.stroke_width(3)
        Vector.stroke()
        Vector.restore()
    end
    Vector.save()
    Vector.rotate(self.hour * 30)
    Vector.begin_path()
    Vector.move_to(0, 6); Vector.line_to(0, -36)
    Vector.line_cap("round")
    Vector.stroke_width(5)
    Vector.stroke()
    Vector.restore()
end

return Clock
```

The drawing is tessellated once and reused while it stays the same (the
engine hashes what was drawn); changing `hour` re-tessellates it on the next
frame.

## Paints, dashes and clips

- **Gradients**: linear (two points) and radial (centre, radius), up to 16
  colour stops, spread *pad*, *reflect* or *repeat*, and a gradient
  transform (Flash's gradient transform tool, SVG's `gradientTransform`).
  They are computed per pixel by the vector shader - smooth on huge shapes,
  still one draw call per mesh.
- **Dashes**: on / off lengths and an offset; each dash gets the stroke's
  joins, caps and anti-aliasing.
- **Opacity**: per shape, on top of the colours' alpha.
- **Fill rules**: non-zero and even-odd, exact for self-intersecting and
  overlapping outlines (Clipper2 normalizes them; single convex outlines
  skip it).
- **Clip paths**: a shape (fill and stroke) cut to a region with its own fill
  rule - `Vector.clip()` from Lua.

## How it works

1. **Paths** (`engine/vector_path.odin`): move, line, quadratic and cubic
   curves, close. Shapes are a path plus a style (fill colour and rule;
   stroke colour, width, joins, caps, miter limit).
2. **Flattening**: curves become line segments within a quarter of a screen
   pixel (Wang's formula picks the segment count).
3. **Tessellation** (`engine/vector_tess.odin`): fills are normalized by
   the fill rule with Clipper2 (`engine/clipper`: self-intersections,
   overlaps, holes) and triangulated with earcut (`engine/vector_earcut.odin`);
   strokes become strips with miter / round / bevel joins and butt / round /
   square caps; clipped shapes go through Clipper2's intersection.
4. **Anti-aliasing without MSAA**: every edge gets a one-pixel strip that
   fades to transparent (fills are inset half a pixel so they keep their
   size); strokes thinner than a pixel are drawn a pixel wide and fainter.
5. **Caching** (`engine/vector_mesh.odin`): the mesh is made for a *scale
   bucket* - the screen-pixel size rounded to a power of two. Moving,
   rotating and scaling within the bucket only changes the transform;
   zooming past it re-tessellates, so curves stay smooth at 10x and meshes
   stay small when zoomed out.
6. **Drawing**: the mesh is uploaded once as vertex buffers and drawn with a
   matrix (one draw call per 65535 vertices). It goes through raylib, so it
   works in the game, the editor's viewport, render textures, post effects
   and the web (WebGL 2).

## Performance (M0 measurements)

On an Apple M-series Mac, optimized build:

| | |
|---|---|
| Tessellating the benchmark character (198 shapes, ~300 curves) | 0.16 ms (zoomed out) to 0.57 ms (zoomed in 4x); 6,000-16,000 triangles |
| 100 of those characters spinning, cached GPU meshes | **1.7 ms per frame** (~580 fps) |
| The same, sent through raylib's batch every frame | 56 ms per frame (18 fps) - why meshes are cached on the GPU |

`RAYZR_VECTOR_MODE=immediate` switches to the batch path (for comparison).
The benchmark: `tests/vector/project`, scene `scenes/bench.scene.json`
(`runner tests/vector/project --scene scenes/bench.scene.json --bench 300`).

## Tests

- `engine/vector_test.odin`: flattening accuracy, earcut (areas, holes,
  concave and degenerate input, the hashed path for big polygons), fill
  coverage (a ring's hole stays empty), strokes (width, joins, caps,
  hairlines), the cache's buckets, the node; leak-checked.
- `tests/vector/runtime_tests.json`: the runner renders the test scenes and
  the screenshots are compared with `tests/vector/expected/` (both drawing
  paths, a 6x zoom, gradients / dashes / opacity, Lua drawing with a clip),
  and the benchmark scene runs.
- `tests/drive/vector_shape.drive`: the editor - Add Node, editing the
  preset and stroke, the viewport zoomed in, saving.
- `scripts/web/test_project.sh tests/vector/project out.png`: the same scene
  in the web runner (headless Chrome).

## Limits (until the next milestones)

- Stroke ends with butt caps have no anti-aliasing fringe on the end edge.
- A clip inside a clip replaces it (no intersection of nested clips yet);
  soft (alpha) masks come with the filters (M5).
- Radial gradients have no separate focal point yet (Flash's focal ratio,
  SVG's fx / fy).
- The immediate drawing path (`RAYZR_VECTOR_MODE=immediate`) evaluates
  gradients per vertex (an approximation); the default GPU path is exact.
- The node draws presets only; vector assets come with SVG import (M2).
- Selection bounds and picking in the viewport come in M2.
