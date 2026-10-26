## Settings

The Inspector's **Timer** section (saved in the scene as `"timer"`):

| Setting | Scene key | Default | |
|---|---|---|---|
| Duration | `duration` | `1` | Seconds until `timeout` |
| Auto Start | `auto_start` | `false` | Start counting when the scene starts |
| Loop | `loop` | `false` | Start again after each `timeout` (otherwise it stops) |

It raises **`timeout`** when the duration has passed and **`tick`** every
frame while it runs. Connect them in the Inspector's **Signals** section or
from a script:

```lua
function Spawner:ready()
    local timer = self.node:get_node("SpawnTimer") ---@type TimerNode
    timer:timer_set_duration(2.0)
    timer:timer_set_loop(true)
    timer:connect("timeout", function() self:spawn_enemy() end)
    timer:timer_start()
end
```
