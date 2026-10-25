-- Spikes (any hazard): touching them hurts the player.

---@class Hazard : ScriptInstanceBase
local Hazard = {}

---@param other Node?
function Hazard:on_body_entered(other)
    if other and other:has_tag("player") then other:get_script():die() end
end

return Hazard
