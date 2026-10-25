-- Scrolls this node left forever: after Wrap pixels it jumps back (the map
-- repeats itself there, so the jump doesn't show).

---@class Scroll : ScriptInstanceBase
local Scroll = {}

Scroll.properties = {
    speed = { type = "float", default = 20, label = "Speed" },  -- px/s
    wrap  = { type = "float", default = 320, label = "Wrap" },  -- px
}

function Scroll:ready()
    local x, y = self.node:get_position()
    self.x, self.y = x, y
end

function Scroll:update(dt)
    self.x = self.x - self.speed * dt
    if self.x <= -self.wrap then self.x = self.x + self.wrap end
    self.node:set_position(math.floor(self.x), self.y)
end

return Scroll
