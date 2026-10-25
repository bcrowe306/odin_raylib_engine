-- Asteroid Drift and Tumble Behavior Script (Asteroids Demo Game)
-- Simulates continuous tumbling, initial drift vector, and screen wrapping.

---@class Asteroid : ScriptInstanceBase
local Asteroid = {}

Asteroid.properties = {
    asteroid_name = { type = "string", default = "Asteroid-Alpha", label = "Asteroid Label" },
    tumble_speed = { type = "float", default = 28.0, min = -180.0, max = 180.0, label = "Tumble Rate (deg/s)" },
    drift_vx = { type = "float", default = 45.0, min = -300.0, max = 300.0, label = "Drift Velocity X" },
    drift_vy = { type = "float", default = -30.0, min = -300.0, max = 300.0, label = "Drift Velocity Y" },
}

function Asteroid:ready()
    self.current_rot = self.node:get_rotation() or 0.0
end

function Asteroid:update(dt)
    -- 1. Continuous Tumble
    self.current_rot = self.current_rot + self.tumble_speed * dt
    self.node:set_rotation(self.current_rot)

    -- 2. Drift Translation
    local px, py = self.node:get_position()
    px = px + self.drift_vx * dt
    py = py + self.drift_vy * dt

    -- 3. Screen Wrap
    local screen_w, screen_h = 1280.0, 720.0
    local pad = 64.0
    if px < -pad then px = screen_w + pad end
    if px > screen_w + pad then px = -pad end
    if py < -pad then py = screen_h + pad end
    if py > screen_h + pad then py = -pad end

    self.node:set_position(px, py)
end

return Asteroid
