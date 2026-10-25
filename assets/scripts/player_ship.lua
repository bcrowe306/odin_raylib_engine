-- Player Spaceship Behavior Script (Asteroids Demo Game)
-- Controls ship orientation, inertial thrust, velocity drag, and screen wrapping.

---@class PlayerShip : ScriptInstanceBase
local PlayerShip = {}

PlayerShip.properties = {
    ship_name = { type = "string", default = "Vanguard-Interceptor", label = "Ship Codename" },
    thrust_power = { type = "float", default = 520.0, min = 100.0, max = 2000.0, label = "Engine Thrust" },
    rotation_speed = { type = "float", default = 210.0, min = 60.0, max = 500.0, label = "Turn Rate (deg/s)" },
    drag = { type = "float", default = 0.985, min = 0.90, max = 1.0, label = "Inertial Drag" },
    max_speed = { type = "float", default = 650.0, min = 100.0, max = 1500.0, label = "Max Speed" },
    weapon_cooldown = { type = "float", default = 0.22, min = 0.05, max = 1.0, label = "Laser Fire Cooldown" },
}

function PlayerShip:ready()
    Log.info("[Lua:PlayerShip] Initializing spaceship:", self.ship_name)
    self.vx = 0.0
    self.vy = 0.0
    self.cooldown_timer = 0.0
    self.rotation = self.node:get_rotation() or 0.0
end

function PlayerShip:update(dt)
    -- 1. Steer Ship (Left / Right / A / D)
    if Input.is_key_down("A") or Input.is_key_down("Left") then
        self.rotation = self.rotation - self.rotation_speed * dt
    end
    if Input.is_key_down("D") or Input.is_key_down("Right") then
        self.rotation = self.rotation + self.rotation_speed * dt
    end
    self.node:set_rotation(self.rotation)

    -- 2. Forward Thrust (W / Up)
    if Input.is_key_down("W") or Input.is_key_down("Up") then
        -- Convert forward orientation (0 deg points right, -90 points up)
        local rad = (self.rotation - 90.0) * (math.pi / 180.0)
        self.vx = self.vx + math.cos(rad) * self.thrust_power * dt
        self.vy = self.vy + math.sin(rad) * self.thrust_power * dt

        -- Speed clamp
        local current_speed = math.sqrt(self.vx * self.vx + self.vy * self.vy)
        if current_speed > self.max_speed then
            local scale = self.max_speed / current_speed
            self.vx = self.vx * scale
            self.vy = self.vy * scale
        end
    end

    -- 3. Inertial Drag Decay
    local decay = self.drag ^ (dt * 60.0)
    self.vx = self.vx * decay
    self.vy = self.vy * decay

    -- 4. Translation
    local px, py = self.node:get_position()
    px = px + self.vx * dt
    py = py + self.vy * dt

    -- 5. Classic Asteroids Screen Wrapping
    local screen_w, screen_h = 1280.0, 720.0
    local pad = 36.0
    if px < -pad then px = screen_w + pad end
    if px > screen_w + pad then px = -pad end
    if py < -pad then py = screen_h + pad end
    if py > screen_h + pad then py = -pad end

    self.node:set_position(px, py)

    -- 6. Weapon Firing Logic
    if self.cooldown_timer > 0.0 then
        self.cooldown_timer = self.cooldown_timer - dt
    end

    if Input.is_key_pressed("Space") and self.cooldown_timer <= 0.0 then
        self.cooldown_timer = self.weapon_cooldown
        Log.info("[Lua:PlayerShip] Fired plasma blaster from", self.ship_name)
    end
end

function PlayerShip:on_destroy()
    Log.info("[Lua:PlayerShip] Ship destroyed:", self.ship_name)
end

return PlayerShip
