A finite state machine for gameplay and animation. Its states and
transitions are edited as a graph in the **State Machine** tab of the bottom
panel (it follows the selected State Machine node) and saved in the scene as
`"state_machine"`.

- **States** play an animation (on an Animation Player) or are pure
  gameplay states; a state can hold a child machine.
- **Transitions** fire when their conditions hold: parameters
  (`speed > 10`), triggers (`jump!`), script functions (`sees_player()`),
  or groups of them (`a | b`), with a blend time.
- **Guards** let a state refuse to be left (for example *Leave After* a
  minimum time) - `sm_request` respects them, `sm_travel` forces the change.
- Scripts get `on_enter_<state>`, `on_update_<state>` and `on_exit_<state>`
  callbacks (right-click a state > **Add Script Callbacks**).

```lua
function Player:update(dt)
    local sm = self.node:get_node("StateMachine") ---@type StateMachineNode
    local vx = self.node:character_get_velocity()
    sm:sm_set("speed", math.abs(vx))
    if Input.is_action_pressed("jump") then sm:sm_trigger("jump") end
end

function Player:on_enter_hurt()
    Audio.play_sound("audio/hurt.wav")
end
```

While the game runs (Simulate or Play) the graph lights the current state
and lists the history of changes.
