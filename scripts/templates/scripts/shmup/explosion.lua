-- An explosion: plays once, then goes.

---@class Explosion : ScriptInstanceBase
local Explosion = {}

function Explosion:ready()
    self.left = 0.4
end

function Explosion:update(dt)
    self.left = self.left - dt
    if self.left <= 0 then self.node:destroy() end
end

return Explosion
