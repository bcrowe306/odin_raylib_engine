-- Tutorial 3 of engine/docs/state_machine.md: a three-hit combo.
--
-- Attack1 -> Attack2 -> Attack3, each when the attack button was pressed AND
-- the current attack's animation finished. The attack trigger has a 0.3 s
-- buffer, so a press during the end of an attack is kept until the
-- animation finishes; a press earlier than that is dropped, and the fighter
-- goes back to Idle. All the rules are in the graph - the script only sets
-- the trigger and deals the damage.
--
-- Scene: Fighter (this script)
--          Sprite  AnimationPlayer: idle (loops), attack1/2/3 (don't loop)
--          Combo   StateMachine; trigger attack with a 0.3 s buffer
-- Input action (Project Settings > Input): attack.

---@class ComboFighter : ScriptInstanceBase
local Fighter = {}

Fighter.properties = {
    damage1 = { type = "int", default = 10, label = "Hit 1 Damage" },
    damage2 = { type = "int", default = 15, label = "Hit 2 Damage" },
    damage3 = { type = "int", default = 30, label = "Finisher Damage" },
}

function Fighter:ready()
    self.combo = self.node:get_child("Combo") ---@type StateMachineNode
    self.damage_dealt = 0
end

function Fighter:update(dt)
    if Input.is_action_pressed("attack") then self.combo:sm_trigger("attack") end
end

function Fighter:on_enter_attack1(previous) self.damage_dealt = self.damage_dealt + self.damage1 end
function Fighter:on_enter_attack2(previous) self.damage_dealt = self.damage_dealt + self.damage2 end
function Fighter:on_enter_attack3(previous) self.damage_dealt = self.damage_dealt + self.damage3 end

return Fighter
