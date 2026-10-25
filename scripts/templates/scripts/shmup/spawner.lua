-- Waves: enemies come in from the right, a little faster each wave (the
-- same pattern every game - use math.random for surprises).
-- A wave = Count drifters, then a shooter.

---@class Spawner : ScriptInstanceBase
local Spawner = {}

Spawner.properties = {
    interval = { type = "float", default = 1.1, label = "Interval" },  -- s between enemies (first wave)
    count    = { type = "int", default = 5, label = "Per Wave" },
}

function Spawner:ready()
    self.timer = 1.5
    self.n = 0
    self.wave = 1
    self.shots = Scene.find_node("Shots")
    self.player = Scene.find_node("Player"):get_script()
end

---@param dt number
function Spawner:update(dt)
    if not self.player:alive() then return end
    self.timer = self.timer - dt
    if self.timer > 0 then return end
    local _, h = Engine.get_virtual_size()
    local w = Engine.get_virtual_size()
    self.n = self.n + 1
    -- Heights sweep up and down the screen (the same every game).
    local y = h / 2 + math.sin(self.n * 1.9) * (h / 2 - 28)
    local kind = self.n % (self.count + 1) == 0 and "shooter" or "drifter"
    Scene.instantiate("components/" .. kind .. ".component.json", self.shots, w + 16, y)
    if self.n % (self.count + 1) == 0 then self.wave = self.wave + 1 end
    self.timer = math.max(0.35, self.interval - (self.wave - 1) * 0.1)
end

return Spawner
