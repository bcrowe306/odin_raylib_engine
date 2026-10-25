-- The door at the end of a level: finishing it saves the progress (the
-- title screen's Continue) and goes to Next Level.

---@class Goal : ScriptInstanceBase
local Goal = {}

Goal.properties = {
    next_level = { type = "scene", default = "", label = "Next Level" },
}

---@param other Node?
function Goal:on_body_entered(other)
    if not other or not other:has_tag("player") then return end
    local hud = Scene.find_node("HUD"):get_script()
    local next_level = self.next_level
    local last = next_level == "" or next_level == "scenes/title.scene.json"
    hud:message(last and "You made it!" or "Level complete!")
    -- Progress: where Continue starts (back at level 1 after the last one).
    Save.set("level", last and "scenes/level1.scene.json" or next_level)
    if last then Save.set("finished", true) end
    Save.flush()
    other:get_script():win(function()
        Scene.change_scene(next_level ~= "" and next_level or "scenes/title.scene.json", { transition = "fade", duration = 0.4 })
    end)
end

return Goal
