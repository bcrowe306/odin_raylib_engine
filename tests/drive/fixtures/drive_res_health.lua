-- A resource class for the resource_inspector drive.
---@class DriveResHealth
local DriveResHealth = {}
DriveResHealth.resource = { local_copy = true }
DriveResHealth.properties = {
    max = { type = "int", default = 100, label = "Max" },
    regen = { type = "float", default = 0.5, group = "Recovery" },
    kind = { type = "enum", values = {"Flesh", "Metal"}, default = "Flesh" },
    owner = { type = "node" },
}
function DriveResHealth:on_load() self.current = self.max end
return DriveResHealth
