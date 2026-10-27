-- Tutorial 1 of engine/docs/state_machine.md: a platformer character whose
-- State Machine decides idle / run / jump / fall, with input buffering.
--
-- The script does the physics and tells the machine what it knows
-- (parameters) and what just happened (the jump trigger). The machine's
-- Automatic arrows pick the state; on_enter_jump does the jump itself - so
-- a jump only ever starts when the machine allows it.
--
-- Scene: Player (CharacterMover, Control Mode "Script", this script)
--          Sprite        AnimationPlayer: idle, run, jump, fall
--          StateMachine  parameters speed (float), on_floor (bool), vy (float);
--                        trigger jump with a 0.15 s buffer
-- Input actions (Project Settings > Input): move_left, move_right, jump.

---@class PlatformerPlayer : ScriptInstanceBase
local Player = {}

Player.properties = {
    speed         = { type = "float", default = 160, label = "Run Speed" },     -- px/s
    jump_velocity = { type = "float", default = 360, label = "Jump Velocity" }, -- px/s up
}

function Player:ready()
    self.sm = self.node:get_child("StateMachine") ---@type StateMachineNode
end

---@param dt number
function Player:update(dt)
    local node = self.node
    local _, vy = node:character_get_velocity()
    local _, gy = node:character_get_gravity()
    local vx = Input.get_axis("move_left", "move_right") * self.speed
    node:character_set_velocity(vx, vy + gy * dt)
    node:character_move_and_slide(dt)
    vx, vy = node:character_get_velocity()

    -- What the game knows: parameters, set every frame.
    self.sm:sm_set("speed", math.abs(vx))
    self.sm:sm_set("on_floor", node:character_is_on_floor())
    self.sm:sm_set("vy", vy)
    -- What just happened: a trigger. In the air it waits up to its buffer
    -- (0.15 s) for the Fall -> Jump arrow (needs on_floor) to open.
    if Input.is_action_pressed("jump") then self.sm:sm_trigger("jump") end
end

-- The machine entered Jump (from Idle, Run, or Fall the moment it landed):
-- push off.
function Player:on_enter_jump(previous)
    local vx = self.node:character_get_velocity()
    self.node:character_set_velocity(vx, -self.jump_velocity)
end

return Player
