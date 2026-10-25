-- The door at the end: reaching it finishes the level. Next Level (a scene)
-- goes there; empty plays this level again.

---@class Goal : ScriptInstanceBase
local Goal = {}

Goal.properties = {
    next_level = { type = "scene", default = "", label = "Next Level" },
}

---@param other Node?
function Goal:on_body_entered(other)
    if not other or not other:has_tag("player") then return end
    local hud = Scene.find_node("HUD"):get_script()
    hud:message("Level complete!")
    local next_level = self.next_level
    other:get_script():win(function()
        if next_level ~= nil and next_level ~= "" then
            Scene.change_scene(next_level, { transition = "fade", duration = 0.4 })
        else
            Scene.reload()
        end
    end)
end

return Goal
