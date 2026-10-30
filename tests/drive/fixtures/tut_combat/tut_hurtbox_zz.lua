-- engine/docs/custom_nodes.md's Hurtbox (a log line added for the drive).
---@class TutHurtboxZz : ScriptInstanceBase
local TutHurtboxZz = {}
TutHurtboxZz.properties = {
    health = { type = "resource", class = "scripts/tut_health_zz.lua" },
    invulnerable = { type = "bool", default = false },
}

function TutHurtboxZz:ready()
    self.health = self.health:duplicate()
    self.last_attack = nil
end

function TutHurtboxZz:take_damage(amount, attack_number)
    if self.invulnerable or attack_number == self.last_attack then return end
    self.last_attack = attack_number
    self.health.current = math.max(self.health.current - amount, 0)
    self.node:emit("damaged", amount)
    if self.health.current == 0 then self.node:emit("died") end
    Log.info(string.format("%s took %d (%d left)", self.node:get_name(), amount, self.health.current))
end

return TutHurtboxZz
