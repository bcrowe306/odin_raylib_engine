-- Tutorial 2 of engine/docs/state_machine.md: an enemy whose script decides
-- what to do, with Manual arrows and sm_transition.
--
-- The graph says which changes are possible (patrol <-> chase -> attack ->
-- chase, Any -> stunned) and the attack's guard (Leave After 0.5 s) says
-- when it may end; each on_update_<state> decides when to ask. Stunned goes
-- back to patrol by itself: an Automatic arrow with "after 1".
--
-- Scene: Enemy (this script)
--          Brain   StateMachine: patrol, chase, attack, stunned
--        Player    (anything named Player)

---@class EnemyBrain : ScriptInstanceBase
local Enemy = {}

Enemy.properties = {
    sight  = { type = "float", default = 120, label = "Sight Range" },  -- px: starts chasing
    give_up = { type = "float", default = 200, label = "Give Up Range" }, -- px: back to patrolling
    reach  = { type = "float", default = 20, label = "Attack Range" },  -- px
    speed  = { type = "float", default = 60, label = "Speed" },         -- px/s
    route  = { type = "float", default = 40, label = "Patrol Width" },  -- px each side of the start
}

function Enemy:ready()
    self.brain = self.node:get_child("Brain") ---@type StateMachineNode
    self.home_x = self.node.position.x
    self.dir = 1
    self.attacks = 0
end

function Enemy:player_distance()
    local player = Scene.find_node("Player")
    if player == nil then return math.huge end
    return self.node.position:distance(player.position)
end

function Enemy:move_towards(x, dt)
    local dx = x - self.node.position.x
    local step = math.min(math.abs(dx), self.speed * dt)
    if dx < 0 then step = -step end
    self.node:translate(step, 0)
end

-- Patrol: walk the route; seeing the player, chase.
function Enemy:on_update_patrol(dt)
    if self:player_distance() < self.sight then
        self.brain:sm_transition("chase")
        return
    end
    local x = self.node.position.x
    if x >= self.home_x + self.route then self.dir = -1 end
    if x <= self.home_x - self.route then self.dir = 1 end
    self.node:translate(self.dir * self.speed * dt, 0)
end

-- Chase: close in; attack in reach; lose the player, patrol again.
function Enemy:on_update_chase(dt)
    local d = self:player_distance()
    if d < self.reach then
        self.brain:sm_transition("attack")
    elseif d > self.give_up then
        self.brain:sm_transition("patrol")
    else
        self:move_towards(Scene.find_node("Player").position.x, dt)
    end
end

function Enemy:on_enter_attack(previous)
    self.attacks = self.attacks + 1
end

-- Attack: when the player is out of reach, go back to chasing. The attack's
-- Leave After (0.5 s) refuses until then; sm_transition says why.
function Enemy:on_update_attack(dt)
    if self:player_distance() >= self.reach then
        local ok, why = self.brain:sm_transition("chase")
        self.last_refusal = (not ok) and why or nil
    end
end

-- Called by whatever hits the enemy: stunned at once, whatever it was doing
-- (force skips the attack's Leave After).
function Enemy:stun()
    self.brain:sm_transition("stunned", { force = true })
end

return Enemy
