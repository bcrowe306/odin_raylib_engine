-- An enemy ship: flies left with a wobble; shooters fire at the player.
-- Touching the player hurts it; enough hits and it explodes for points.

---@class Enemy : ScriptInstanceBase
local Enemy = {}

Enemy.properties = {
    speed  = { type = "float", default = 50, label = "Speed" },    -- px/s
    wobble = { type = "float", default = 18, label = "Wobble" },   -- px up / down
    hp     = { type = "int", default = 1, label = "Hits" },
    shoots = { type = "bool", default = false, label = "Shoots" },
    points = { type = "int", default = 100, label = "Points" },
    radius = { type = "float", default = 10, label = "Hit Radius" },
}

local SHOT = "components/enemy_bullet.component.json"
local EXPLOSION = "components/explosion.component.json"

function Enemy:ready()
    local _, y = self.node:get_position()
    self.base_y = y
    self.t = self.base_y -- (a different wobble phase per height)
    self.reload = 1.2
    self.player = Scene.find_node("Player")
end

---@param dt number
function Enemy:update(dt)
    self.t = self.t + dt
    local x = self.node:get_position()
    x = x - self.speed * dt
    local y = self.base_y + math.sin(self.t * 2) * self.wobble
    self.node:set_position(x, y)
    if x < -24 then self.node:destroy() return end

    local ps = self.player:get_script()
    local px, py = self.player:get_position()
    if ps:alive() and Vec2(px - x, py - y):length() < self.radius + ps.radius then ps:hit() end
    if self.shoots and ps:alive() then
        self.reload = self.reload - dt
        if self.reload <= 0 and x < 300 then
            self.reload = 1.6
            local b = Pool.take(SHOT, self.node:get_parent(), x - 10, y)
            if b then b:get_script():aim(px, py) end
        end
    end
end

-- hit: a player bullet.
function Enemy:hit()
    self.hp = self.hp - 1
    if self.hp > 0 then return end
    local x, y = self.node:get_position()
    Scene.instantiate(EXPLOSION, self.node:get_parent(), x, y)
    Scene.find_node("HUD"):get_script():add_score(self.points)
    self.node:destroy()
end

return Enemy
