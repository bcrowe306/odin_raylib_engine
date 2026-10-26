A node whose job is to run a script - a manager, a spawner, game rules.
Any node can run a script (Inspector > **Script**); a Script node is simply
an empty node made for it.

```lua
-- scripts/game_rules.lua on a Script node named "Rules"
local Rules = {}

function Rules:ready()
    self.score = 0
end

function Rules:add_points(n)
    self.score = self.score + n
end

return Rules
```

Other scripts reach it with `Scene.find_node("Rules"):get_script():add_points(10)`.
For a script that should outlive scene changes, make it a **global script**
instead (see the scripting guide).
