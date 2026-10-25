-- The enemy's hitbox: the player landing on it from above stomps the enemy
-- (and bounces); touching it any other way hurts the player.

---@class EnemyHitbox : ScriptInstanceBase
local EnemyHitbox = {}

---@param other Node?
function EnemyHitbox:on_body_entered(other)
    if not other or not other:has_tag("player") then return end
    local enemy = self.node:get_parent()
    local player = other:get_script()
    local _, py = other:get_position()
    local _, ey = enemy:get_position()
    if player:falling() and py < ey - 4 then
        enemy:get_script():squash()
        player:stomped()
    else
        player:die()
    end
end

return EnemyHitbox
