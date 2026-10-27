A finite state machine for gameplay and animation. Its states, arrows,
parameters and triggers are edited in the **State Machine** tab of the
bottom panel (sub-tabs **Graph**, **Parameters & Triggers**, **Settings**;
it follows the selected State Machine node - the Inspector shows a summary
and **Edit in State Machine Tab**) and saved in the scene as
`"state_machine"`. Guide with tutorials:
[State machines](../../engine/docs/state_machine.md).

- **States** play an animation (on an Animation Player) or are pure
  gameplay states; a state can run a child machine, and with **Allow
  Retrigger** go to itself.
- **Arrows** are **Manual** (the default: only a script's `sm_transition`
  takes them; drawn dashed) or **Automatic** (taken when their conditions
  hold: parameters `speed > 10`, triggers `jump!`, script functions
  `sees_player()`, animation finished, time in state, or groups `a | b`),
  with a blend time.
- **Parameters** are typed (bool, int, float); **triggers** are one-shot
  events with an optional buffer time (input buffering).
- **Guards** let a state refuse to be left or entered (for example *Leave
  After* a minimum time); `sm_transition` respects them,
  `sm_transition(state, {force = true})` skips them.
- Scripts get `on_enter_<state>`, `on_update_<state>` and `on_exit_<state>`
  callbacks (right-click a state > **Add Script Callbacks**) and the guards
  `can_exit_<state>` / `can_enter_<state>` (**Add Guard Callbacks**).

```lua
function Player:update(dt)
    local sm = self.node:get_node("StateMachine") ---@type StateMachineNode
    local vx = self.node:character_get_velocity()
    sm:sm_set("speed", math.abs(vx))
    if Input.is_action_pressed("jump") then sm:sm_trigger("jump") end
end

function Player:on_enter_hurt(previous)
    Audio.play_sound("audio/hurt.wav")
end

-- A script decision, along a Manual arrow:
local ok, why = self.node:get_node("Brain"):sm_transition("chase")
```

While the game runs (Simulate or Play) the graph lights the current state
and lists the ways out, the history of changes and pending triggers.
