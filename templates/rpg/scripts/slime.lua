-- A slime: bobs about, chases the player when close, hurts on touch.
-- Two sword hits and it's gone.

---@class Slime : ScriptInstanceBase
local Slime = {}

Slime.properties = {
    speed  = { type = "float", default = 28, label = "Speed" },        -- px/s
    sight  = { type = "float", default = 70, label = "Sight" },        -- px: chases inside this
    hp     = { type = "int", default = 2, label = "Hits" },
}

function Slime:ready()
    self.player = Scene.find_node("Player")
    self.knock = Vec2(0, 0)
    self.flash = 0
    self.sprite = self.node:get_child("Sprite")
    self.t = math.random() * 3
end

---@param dt number
function Slime:update(dt)
    local node = self.node
    self.t = self.t + dt
    local x, y = node:get_position()
    local v = Vec2(0, 0)
    if self.player then
        local px, py = self.player:get_position()
        local to = Vec2(px - x, py - y)
        local d = to:length()
        if d < self.sight and d > 0 then v = to:normalized() * self.speed end
        if d < 11 then self.player:get_script():hurt(x, y) end
    end
    v = v + self.knock
    self.knock = self.knock * math.max(0, 1 - 8 * dt)
    node:character_set_velocity(v.x, v.y)
    node:character_move_and_slide()
    -- A squishy bob, and a flash when hit.
    local s = 1 + math.sin(self.t * 6) * 0.08
    self.sprite:set_scale(1 / s, s)
    self.flash = math.max(0, self.flash - dt)
    self.sprite:set_visible(self.flash <= 0 or math.floor(self.flash * 20) % 2 == 0)
end

-- hit: the sword (dir: the swing's direction).
function Slime:hit(dir)
    self.hp = self.hp - 1
    self.knock = dir * 140
    self.flash = 0.3
    if self.hp <= 0 then self.node:destroy() end
end

return Slime
