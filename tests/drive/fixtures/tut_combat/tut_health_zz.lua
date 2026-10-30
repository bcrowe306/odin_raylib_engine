---@class TutHealthZz : ResourceBase
local TutHealthZz = {}
TutHealthZz.resource = { local_copy = false }
TutHealthZz.properties = { max = { type = "float", default = 10 } }
function TutHealthZz:on_load() self.current = self.max end
return TutHealthZz
