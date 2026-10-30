## Use it for

- **Telling whoever cares**: `Events.emit("score_changed", score)` from gameplay; the HUD, the audio and the achievements each `Events.connect` to it - no script needs a reference to another.
- **Game flow**: a level emits `"level_complete"`, a game-flow script listens and changes scene. `Events.once` listens for just the next one.
- **Events raised mid-update**: `Events.emit_deferred` delivers at the end of the frame, after every node has updated - for an enemy dying in the middle of a physics step, say.
- **Passing data**: the value can be anything - a number, a string, a node or a table like `{kind = "slime", points = 50}`.
- **Engine events**: engine code publishes on the same bus (a [Level Generator](../nodes/LevelGeneratorNode.md) emits `"level_generated"`), so scripts connect to those the same way.
- **Checking the wiring**: `Events.listener_count(event)` says how many handlers listen - warn when an important event has none.

## Example

A score counter that adds up the points of every enemy killed, shows them and tells the rest of the game - the script is on a [UI Label](../nodes/UILabelNode.md); enemies call `Events.emit_deferred("enemy_killed", {points = 50})` when they die.

```lua
---@class ScoreLabel : ScriptInstanceBase
local ScoreLabel = {}

function ScoreLabel:ready()
    self.score = 0
    self.label = self.node ---@type UILabelNode
    self.label.text = "Score: 0"
    -- Both connections end by themselves when this label is destroyed.
    Events.connect("enemy_killed", function(info)
        local points = type(info) == "table" and info.points or 0
        self.score = self.score + points
        self.label.text = "Score: " .. self.score
        Events.emit("score_changed", self.score)   -- for audio, achievements...
    end)
    Events.once("player_died", function()
        self.label.text = "Game over - " .. self.score .. " points"
    end)
end

return ScoreLabel
```

## Notes

- Handlers get `(value, source)`: `source` is the node of the script that emitted (or the node passed to `emit`), nil from global code.
- `emit` runs every handler before it returns, in the order they connected. A handler may emit, connect, disconnect or destroy nodes; an error in one is logged and the others still run.
- A connection ends when the connecting script's node is destroyed, or with the `scope` node when you pass one - so handlers never run on dead objects. Keep the id to end it earlier with `Events.disconnect`.
- The bus lasts across scene changes: a connection from a script that stays (a global script) keeps listening in the next scene.
- These are global events. A node's own events (`node:connect("clicked", ...)`, `node:emit`) are separate - see the [scripting guide](../../engine/SCRIPTING.md).
