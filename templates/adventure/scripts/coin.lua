-- A coin: the player touching it collects it (the HUD counts them).

---@class Coin : ScriptInstanceBase
local Coin = {}

---@param other Node?
function Coin:on_body_entered(other)
    if self.taken or not other or not other:has_tag("player") then return end
    self.taken = true
    Scene.find_node("HUD"):get_script():add_coin()
    -- A little hop as it goes.
    local x, y = self.node:get_position()
    Tween.to(self.node, "position", Vec2(x, y - 10), 0.2, "out_quad", { on_complete = function(n) n:destroy() end })
end

return Coin
