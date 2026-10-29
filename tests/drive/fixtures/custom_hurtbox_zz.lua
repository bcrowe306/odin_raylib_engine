-- A custom node type's script (tests/drive/custom_node_load.drive).
---@class HurtboxZz : ScriptInstanceBase
local HurtboxZz = {}
HurtboxZz.properties = {
    max_health = { type = "float", default = 10 },
    armor = { type = "float", default = 0 },
}
function HurtboxZz:ready() self.health = self.max_health end
function HurtboxZz:take_damage(amount) self.health = self.health - amount end
return HurtboxZz
