-- Orbiting Drone Behavior Script (Rayzr)
-- Demonstrates Lua 5.4 scripting, exported properties, and runtime node lifecycle.

---@class Drone : ScriptInstanceBase
local Drone = {}

Drone.properties = {
    drone_name = { type = "string", default = "Recon-Drone-Alpha", label = "Drone Codename" },
    orbit_radius = { type = "float", default = 130.0, min = 30.0, max = 350.0, label = "Orbit Radius" },
    rotation_speed = { type = "float", default = 1.8, min = 0.2, max = 5.0, label = "Rotation Speed (rad/s)" },
    center_x = { type = "float", default = 640.0, label = "Orbit Center X" },
    center_y = { type = "float", default = 260.0, label = "Orbit Center Y" },
    pulse_enabled = { type = "bool", default = true, label = "Enable Scale Pulse" },
}

function Drone:ready()
    Log.info("[Lua:Drone] Initializing drone:", self.drone_name)
    self.angle = 0.0
    self.node:set_position(self.center_x + self.orbit_radius, self.center_y)
    self.node:set_scale(0.35, 0.35)
end

function Drone:update(dt)
    -- Advance orbital angle
    self.angle = (self.angle or 0.0) + self.rotation_speed * dt

    -- Smooth elliptical orbit around center
    local px = self.center_x + math.cos(self.angle) * self.orbit_radius
    local py = self.center_y + math.sin(self.angle) * (self.orbit_radius * 0.45)
    self.node:set_position(px, py)

    -- Face along trajectory tangent
    local tangent_deg = (self.angle + math.pi * 0.5) * (180.0 / math.pi)
    self.node:set_rotation(tangent_deg)

    -- Optional scale pulse animation
    if self.pulse_enabled then
        local pulse = 0.35 + math.sin(self.angle * 2.0) * 0.04
        self.node:set_scale(pulse, pulse)
    end
end

function Drone:on_destroy()
    Log.info("[Lua:Drone] Decommissioning drone:", self.drone_name)
end

return Drone
