-- engine/docs/custom_nodes.md's Hitbox.
---@class TutHitboxZz : ScriptInstanceBase
local TutHitboxZz = {}
TutHitboxZz.properties = {
    damage = { type = "float", default = 1 },
}

function TutHitboxZz:ready() self.attack = 0 end

function TutHitboxZz:swing() self.attack = self.attack + 1 end

function TutHitboxZz:on_body_entered(other)
    if other:is("TutHurtbox") then
        other:get_script():take_damage(self.damage, self.attack)
    end
end

return TutHitboxZz
