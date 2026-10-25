-- An enemy that walks back and forth: it turns at walls and at ledges.
-- Its Hitbox child (enemy_hitbox.lua) decides who gets hurt.

---@class Enemy : ScriptInstanceBase
local Enemy = {}

Enemy.properties = {
    speed = { type = "float", default = 30, label = "Walk Speed" }, -- px/s
}

function Enemy:ready()
    self.dir = -1
    self.sprite = self.node:get_child("Sprite")
    self.dead = false
end

---@param dt number
function Enemy:update(dt)
    if self.dead then
        self.timer = self.timer - dt
        if self.timer <= 0 then self.node:destroy() end
        return
    end
    local node = self.node
    local _, vy = node:character_get_velocity()
    local _, gy = node:character_get_gravity()
    -- Turn at a ledge: nothing under the front foot.
    local x, y = node:get_position()
    if node:character_is_on_floor() and not Physics.raycast(x + self.dir * 8, y, x + self.dir * 8, y + 16) then
        self.dir = -self.dir
    end
    node:character_set_velocity(self.dir * self.speed, math.min(vy + gy * dt, 500))
    node:character_move_and_slide()
    if node:character_is_on_wall() then self.dir = -self.dir end
    local sx, sy = self.sprite:get_scale()
    self.sprite:set_scale(-self.dir * math.abs(sx), sy)
end

-- squash: stomped. It stops, flattens and goes.
function Enemy:squash()
    if self.dead then return end
    self.dead, self.timer = true, 0.4
    self.sprite:animation_play("squashed")
    self.node:get_child("Hitbox"):set_enabled(false)
end

return Enemy
