-- A bullet (pooled: Pool.take / destroy() returns it). The player's hit
-- enemies, the enemies' hit the player - by distance, no physics needed.

---@class Bullet : ScriptInstanceBase
local Bullet = {}

Bullet.properties = {
    speed  = { type = "float", default = 260, label = "Speed" },   -- px/s
    dir_x  = { type = "float", default = 1, label = "Direction X" },
    dir_y  = { type = "float", default = 0, label = "Direction Y" },
    radius = { type = "float", default = 3, label = "Radius" },
}

-- (Each time it's taken from the pool.)
function Bullet:on_spawn()
    self.vx, self.vy = self.dir_x * self.speed, self.dir_y * self.speed
end

function Bullet:ready() self:on_spawn() end

-- aim: fly toward a point (enemy shots).
function Bullet:aim(tx, ty)
    local x, y = self.node:get_position()
    local d = Vec2(tx - x, ty - y)
    if d:length() > 0 then
        d = d:normalized() * self.speed
        self.vx, self.vy = d.x, d.y
    end
end

---@param dt number
function Bullet:update(dt)
    local x, y = self.node:get_position()
    x, y = x + self.vx * dt, y + self.vy * dt
    self.node:set_position(x, y)
    local w, h = Engine.get_virtual_size()
    if x < -16 or x > w + 16 or y < -16 or y > h + 16 then self.node:destroy() return end
    if self.node:has_tag("player_bullet") then
        for _, e in ipairs(Scene.find_by_tag("enemy")) do
            local ex, ey = e:get_position()
            local s = e:get_script()
            if s and Vec2(ex - x, ey - y):length() < s.radius + self.radius then
                s:hit()
                self.node:destroy()
                return
            end
        end
    else
        local p = Scene.find_node("Player")
        local px, py = p:get_position()
        local ps = p:get_script()
        if Vec2(px - x, py - y):length() < ps.radius + self.radius then
            ps:hit()
            self.node:destroy()
        end
    end
end

return Bullet
