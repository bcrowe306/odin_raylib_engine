-- A node script holding a resource of one class.
local DriveResUser = {}
DriveResUser.properties = {
    health = { type = "resource", class = "scripts/drive_res_health.lua" },
}
return DriveResUser
