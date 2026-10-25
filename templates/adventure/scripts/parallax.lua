-- Parallax: this node scrolls slower than the camera (a backdrop far away).
-- Factor 0 = stays with the screen, 1 = moves with the level.

---@class Parallax : ScriptInstanceBase
local Parallax = {}

Parallax.properties = {
    factor = { type = "float", default = 0.5, min = 0, max = 1, label = "Factor" },
}

function Parallax:ready()
    self.camera = Scene.find_node("Camera")
    local _, y = self.node:get_position()
    self.y = y
end

function Parallax:update(dt)
    if not self.camera then return end
    local w = Engine.get_virtual_size()
    local cx = self.camera:get_global_position()
    self.node:set_position((cx - w / 2) * (1 - self.factor), self.y)
end

return Parallax
