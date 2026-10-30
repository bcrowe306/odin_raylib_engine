## Use it for

- **Colours a designer can shape**: a `gradient` property, edited as a colour bar in the Inspector, read with `Gradient.sample(self.my_gradient, t)` - four numbers 0..1.
- **State shown as colour**: a health bar from green to red, a heat glow, a charge-up flash - sample with the state scaled to 0..1.
- **Colour over time**: a day-night sky, a fading trail - sample with elapsed time divided by the length.

## Example

A sprite that turns from white to yellow to red as it loses health - the script is on a [Texture](../nodes/TextureNode.md); other scripts call `hit(damage)` on it.

```lua
---@class HealthTint : ScriptInstanceBase
local HealthTint = {}

HealthTint.properties = {
    max_health = { type = "float", default = 10, label = "Max Health" },
    colors = {
        type = "gradient",
        -- {t, r, g, b, a}: t is the health fraction (0 = dead, 1 = full).
        default = { {0, 1, 0.2, 0.2, 1}, {0.5, 1, 0.9, 0.3, 1}, {1, 1, 1, 1, 1} },
        label = "Colors",
    },
}

function HealthTint:ready()
    self.health = self.max_health
    self:refresh()
end

---@param damage number
function HealthTint:hit(damage)
    self.health = math.max(self.health - damage, 0)
    self:refresh()
end

function HealthTint:refresh()
    local r, g, b, a = Gradient.sample(self.colors, self.health / self.max_health)
    self.node.tint = {r, g, b, a}
end

return HealthTint
```

## Notes

- A gradient property's value is a list of `{t, r, g, b, a}` stops sorted by `t`, channels 0..1 (alpha defaults to 1). Without a `default` it is plain white.
- Between stops the colour is linear. Before the first stop and after the last one the end colours hold, so `t` outside 0..1 is safe.
- An empty list gives white (1, 1, 1, 1). Colour node properties take the result as `{r, g, b, a}`.
- For a single number, use a `curve` property and [Curve](Curve.md); for gradients drawn on screen, [Vector](Vector.md)'s `linear_gradient`.
