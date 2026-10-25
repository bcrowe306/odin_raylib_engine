-- A potion: walking over it heals a heart.

---@class Potion : ScriptInstanceBase
local Potion = {}

---@param other Node?
function Potion:on_body_entered(other)
    if self.taken or not other or not other:has_tag("player") then return end
    self.taken = true
    other:get_script():heal(1)
    self.node:destroy()
end

return Potion
