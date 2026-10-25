-- charactermover
---@class Charactermover : ScriptInstanceBase
local Charactermover = {}

-- Exported properties appear in the Inspector.
Charactermover.properties = {
    speed = { type = "float", default = 100.0, label = "Speed" },
}

function Charactermover:ready()
end

---@param dt number
function Charactermover:update(dt)
    local axis = Input.get_axis("move_left", "move_right")
    Log.info(axis)
end

return Charactermover
