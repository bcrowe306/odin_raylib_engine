local DriveRefZz = {}
function DriveRefZz:update(dt)
    local speed = 10 * dt
    self.node.position = self.node.position + Vec2(speed, 0)
    self.node:set_property("rotation", 45)
    local p = {1, 2}
end
return DriveRefZz
