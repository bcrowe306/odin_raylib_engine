-- Drive fixture: every exported property type.
---@class DriveTypes : ScriptInstanceBase
local T = {}
T.properties = {
    mode   = { type = "enum", values = {"Idle", "Run", "Jump"}, default = "Idle", group = "State", tooltip = "The current behaviour" },
    volume = { type = "range", min = 0, max = 1, default = 0.5, group = "Audio" },
    speeds = { type = "array", of = "float", default = {1, 2} },
    ease   = { type = "curve" },
    tint   = { type = "gradient" },
}
return T
