-- The way out: reaching it wins (then the dungeon starts again).

---@class Exit : ScriptInstanceBase
local Exit = {}

function Exit:ready() self.timer = nil end

---@param other Node?
function Exit:on_body_entered(other)
    if self.timer or not other or not other:has_tag("player") then return end
    Scene.find_node("HUD"):get_script():message("You escaped!")
    self.timer = 2
end

function Exit:update(dt)
    if not self.timer then return end
    self.timer = self.timer - dt
    if self.timer <= 0 then Scene.reload(); self.timer = 1e9 end
end

return Exit
