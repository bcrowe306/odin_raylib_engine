## What it's for

A Light brightens the scene around it: a torch, a lamp, a glowing crystal, a
flashlight cone. Lights only show when the scene is darker than its art:
set the scene's **Ambient** to a dark colour, then add lights to bring
places back. Lights can cast shadows from physics shapes.

## When to use it

- **Night, caves, interiors**: a dark ambient with torches and lamps.
- **A flashlight or a searchlight**: a **Spot** light, aimed by the node's
  rotation.
- **Shadows behind walls and crates**: **Shadows** on; the walls are
  physics bodies.
- **Not** for a glow that should look bright on a light scene: lights can't
  make anything brighter than its art. Use an additive sprite or a
  [Post Effect](PostEffectNode.md) instead.
- **Not** for tinting the whole screen: set the ambient alone (no lights),
  or use a [Post Effect](PostEffectNode.md).

## Using it

1. Darken the scene: in the Scene panel's **Settings** tab, set **Ambient**
   (or pick a preset: *Dusk*, *Night*, *Dark*; *Day (unlit)* turns it off).
   White means unlit: the scene is drawn as it is.
2. **Add Node** (Ctrl+A) > *Light*. It's a warm point light with a
   256-pixel radius.
3. In the Node tab's **Properties** section: **Kind** (*Point* shines all round, *Spot* shines in
   a cone), **Color**, **Energy** (brightness), **Radius** (pixels),
   **Falloff** (how it fades to the edge), **Spread** (a spot's half-angle
   in degrees) and **Shadows**.
4. For a spot light, rotate the node to aim it: at rotation 0 it points
   right.
5. Selected, the light shows its radius (or its cone) in the viewport. The
   toolbar's sun button switches the lighting preview on and off.

## How it works

- The scene is drawn first. Then a light map is built: it starts as the
  ambient colour and each light adds its colour on top. The light map
  multiplies what was drawn. Where it reaches white, you see the art as
  drawn; it never gets brighter than that.
- Lights light the layers the scene's camera draws (Layer1 to Layer7 by
  default). Layer8 and anything under a
  [Screen Layer](ScreenLayerNode.md) (the HUD) is never darkened.
- **Energy** multiplies the colour (0 to 8); each channel stops at full
  brightness. Overlapping lights add up.
- **Falloff** 1 fades evenly to the edge, 2 (the default) fades smoothly,
  higher values keep the light tight around its centre.
- The radius grows with the node's larger scale axis.
- **Shadows**: shapes of Static, Dynamic and Kinematic bodies and Character
  Movers block the light, except sensors (trigger areas). The colliders a
  [Tile Map](TileMapNode.md) or an [LDtk level](LdtkLevelNode.md) builds are
  static bodies, so they cast shadows too - once they exist, which is when
  the game (or Simulate) runs. Each light's shadows only darken that
  light's own contribution.
- A light whose circle is outside the view is skipped. Each visible light is
  one extra pass, so dozens of large shadowed lights cost more than a few.
- Scripts set the ambient with `Scene.set_ambient(r, g, b)` (0 to 1) and read
  it with `Scene.get_ambient()`.

## Example

A torch that flickers, and a cave that gets dark when the player enters.
The first script is on the Light.

```lua
---@class Torch : ScriptInstanceBase
local Torch = {}

Torch.properties = {
    energy = { type = "float", default = 1.2, label = "Energy" },
    flicker = { type = "float", default = 0.25, label = "Flicker" },
}

function Torch:ready()
    self.node:light_set_color(1.0, 0.75, 0.4)
    self.wait = 0
end

function Torch:update(dt)
    self.wait = self.wait - dt
    if self.wait > 0 then return end
    self.wait = 0.05 + math.random() * 0.1
    self.node:light_set_energy(self.energy + (math.random() - 0.5) * self.flicker)
end

return Torch
```

On a Trigger Area at the cave's entrance:

```lua
function CaveEntrance:on_body_entered(body)
    if body ~= nil and body:get_name() == "Player" then
        Scene.set_ambient(0.08, 0.08, 0.12)
    end
end
```

`light_get_energy()` reads the energy back and `light_set_radius(r)` changes
the reach.

## Screenshot

![A point light over a sprite, with the scene's ambient at Night](../images/node_LightNode.png)
