local DriveSwZz = {}
DriveSwZz.properties = {
    tint = { type = "color", default = {1, 0.5, 0, 1} },
}
function DriveSwZz:ready()
    self.node:set_texture("textures/Spaceship_1.png")
    local c = {0.2, 0.4, 0.8}
    local v = {1, 2, 3}
end
return DriveSwZz
