## Use it for

- **Values over time a designer can shape**: a dash's speed, a jump's gravity, a spawn rate over a wave - a `curve` property edited as a graph in the Inspector, read with `Curve.sample(self.my_curve, t)`.
- **Mapping one range onto another**: damage by distance, engine pitch by speed, camera zoom by player count - sample with the input scaled to 0..1.
- **Custom easing**: a curve drawn by hand where none of the [Tween](Tween.md) eases fits.

## Example

A dash that shoots the node right when **dash** is pressed, fast at first and easing to a stop as the curve says - the script is on the player.

```lua
---@class Dash : ScriptInstanceBase
local Dash = {}

Dash.properties = {
    max_speed   = { type = "float", default = 600, label = "Max Speed" },   -- px/s
    duration    = { type = "float", default = 0.3, label = "Duration" },    -- seconds
    speed_curve = { type = "curve", default = { {0, 1}, {0.3, 1}, {1, 0} }, label = "Speed" },
}

---@param dt number
function Dash:update(dt)
    if not self.elapsed then
        if Input.is_action_pressed("dash") then self.elapsed = 0 end
        return
    end
    self.elapsed = self.elapsed + dt
    local t = self.elapsed / self.duration
    if t >= 1 then
        self.elapsed = nil
        return
    end
    local speed = self.max_speed * Curve.sample(self.speed_curve, t)
    local x, y = self.node:get_position()
    self.node:set_position(x + speed * dt, y)
end

return Dash
```

## Notes

- A curve property's value is a list of `{t, v}` points sorted by `t`; without a `default` it is a straight line from 0 to 1 (`{ {0, 0}, {1, 1} }`).
- Between points the value is linear. Before the first point and after the last one the end values hold, so `t` outside 0..1 is safe.
- An empty list samples as 0. You can build a points list in code too - `Curve.sample({ {0, 0}, {1, 100} }, 0.25)` is 25.
- For colours, use a `gradient` property and [Gradient](Gradient.md).
