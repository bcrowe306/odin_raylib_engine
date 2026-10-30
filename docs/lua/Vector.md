## Use it for

- **Procedural shapes from a script**: give a script `on_draw()` and draw with `Vector` in the node's local space - health rings, radar sweeps, laser beams, debug overlays, crisp at any zoom.
- **Paths**: `begin_path`, then `move_to` / `line_to` / `quad_to` / `cubic_to` / `arc` / `close_path`, or the shapes `rect`, `circle` and `ellipse`; then `fill()`, `stroke()` or both.
- **Style**: `fill_color` and `stroke_color` (`"#rrggbb[aa]"`, `{r, g, b, a}` or r, g, b, a), `stroke_width`, `line_join`, `line_cap`, `dash`, `fill_rule` (`"evenodd"` cuts holes) and `opacity`.
- **Gradients**: `linear_gradient` / `radial_gradient` make a paint for `fill_paint` / `stroke_paint`.
- **Transforms and clipping**: `translate`, `rotate` (degrees) and `scale` move what comes next; `save` / `restore` bracket them; `clip()` limits drawing to the current path until `restore`.

## Example

A ring around a unit that shows its health as a green-to-red arc - the script is on a plain Node under the unit; other scripts set its `health` (0..1).

```lua
---@class HealthRing : ScriptInstanceBase
local HealthRing = {}

HealthRing.properties = {
    radius = { type = "float", default = 24, label = "Radius" },               -- px
    health = { type = "range", min = 0, max = 1, default = 1, label = "Health" },
}

function HealthRing:on_draw()
    -- The dark track: a full circle outline.
    Vector.begin_path()
    Vector.circle(0, 0, self.radius)
    Vector.stroke_color(0, 0, 0, 0.4)
    Vector.stroke_width(6)
    Vector.stroke()
    if self.health <= 0 then return end
    -- The health: an arc from the top, clockwise.
    Vector.begin_path()
    Vector.arc(0, 0, self.radius, -90, -90 + 360 * self.health)
    Vector.stroke_paint(Vector.linear_gradient(-self.radius, 0, self.radius, 0, { {0, "#ef5350"}, {1, "#66bb6a"} }))
    Vector.line_cap("round")
    Vector.stroke()
end

return HealthRing
```

## Notes

- Call `Vector` only inside `on_draw()` - anywhere else it raises an error. `on_draw` runs every frame, after the node's own drawing, starting from the defaults: white fill, black 1 px stroke, no transform.
- The drawing is tessellated once and reused while it stays the same, so redrawing the same shapes each frame is cheap; changing a value (here `health`) re-tessellates on the next frame.
- Coordinates are px in the node's local space (+y down), so the drawing moves, turns and scales with the node. Angles are degrees, clockwise on screen. Points are plain numbers - pass `v.x, v.y` for a Vec2.
- `fill()` and `stroke()` keep the path: fill then stroke the same shape. `begin_path()` starts a new one.
- For art drawn in Inkscape, Illustrator or Figma, use a [Vector Shape](../nodes/VectorShapeNode.md) instead. The [vector art guide](../../engine/docs/vector.md) covers both.
