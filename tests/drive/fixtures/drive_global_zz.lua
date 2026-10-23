-- Drive fixture: a global script (Project Settings > Globals).
local DriveGlobalZz = {points = 0, frames = 0}

function DriveGlobalZz:ready()
    Log.info("drive global ready")
end

function DriveGlobalZz:update(dt)
    self.frames = self.frames + 1
    if self.frames == 3 then Log.info("drive global updating, points " .. self.points) end
end

---Adds to the score.
---@param n number
function DriveGlobalZz:add_points(n)
    self.points = self.points + n
end

return DriveGlobalZz
