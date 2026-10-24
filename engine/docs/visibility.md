# Visibility notifier: on screen / off screen

A **Visibility Notifier** node is a rectangle that knows whether the camera
sees it. Put one under anything that should react to being seen:

- enemies that sleep until the player comes near (and stop thinking when
  far behind),
- bullets and debris that free themselves once they leave the screen,
- effects, sounds or animations that only matter while visible,
- triggering a cutscene or a spawn the first time something is seen.

## In the editor

**Add Node > Physics & Collision > Visibility Notifier** (or search
"visibility" / "on screen"). Add it as a **child** of the node it watches.

| Inspector | |
|---|---|
| **Size** | The rectangle, centred on the notifier, scaled with it. Match it to the sprite (or a bit bigger). |
| **Margin** | Grows the camera's view by this many pixels, so it fires a little *before* it really shows (wake enemies just off screen). |
| **Action** | What happens to the **parent** off screen: **None**, **Pause Parent** (stops updating, scripts and physics; resumes when seen again), **Disable Parent** (also stops drawing), **Remove Parent** (freed once it was on screen and leaves). |
| **On Screen** | Read-only while running: the camera sees it now. |

The viewport draws every notifier's rectangle in yellow (brighter in
Simulate while the game camera sees it). The check uses the **game's**
camera, not the editor's view: in Simulate, pan the editor freely.

Events (**Signals** panel, or script callbacks): `screen_entered` and
`screen_exited`.

## Examples

### A bullet that cleans itself up

```
Bullet (DynamicBody, bullet.lua)
├── Sprite
└── VisibilityNotifier   size 16 x 16, action: Remove Parent
```

No script code: the bullet is removed the frame after it leaves the
screen. (A bullet spawned off screen isn't removed until it has been seen
once - so firing from just outside the view still works.)

### An enemy that sleeps off screen

```
Goblin (CharacterMover, goblin.lua)
├── AnimatedSprite
└── VisibilityNotifier   size 64 x 64, margin 96, action: Pause Parent
```

The goblin and its children stop updating (no AI, no animation, its body
leaves the physics step) while more than 96 px outside the view, and pick
up where they were when the camera comes back.

### Reacting in a script

The notifier's own script gets `on_screen_entered()` / `on_screen_exited()`.
To handle it in the **parent's** script, connect the signal (Signals panel:
`screen_entered` → `..` → `on_seen`), or connect from code:

```lua
---@class Turret : ScriptInstanceBase
local Turret = {}

function Turret:ready()
    local eye = self.node:get_node("VisibilityNotifier")
    eye:connect("screen_entered", function() self.active = true end)
    eye:connect("screen_exited", function() self.active = false end)
end

function Turret:update(dt)
    if not self.active then return end
    self:aim_and_fire(dt)
end

return Turret
```

Polling works too: `if self.node:get_node("VisibilityNotifier").onScreen then ... end`.

### First sighting

```lua
function Boss:ready()
    local eye = self.node:get_node("VisibilityNotifier")
    local id
    id = eye:connect("screen_entered", function()
        eye:disconnect(id)                  -- only the first time
        Scene.find_node("BossMusic"):music_play()
    end)
end
```

## Saved as

```json
{"type": "VisibilityNotifierNode", "name": "VisibilityNotifier",
 "properties": {"size": [64, 64], "margin": 96, "action": "Pause_Parent"}}
```

## How it works (performance)

Notifiers are kept in their scene's node manager in a small list (added and
removed with the nodes), so the check touches only them - not the whole
tree. Once per frame, after the transforms, each notifier's rectangle is
tested against the camera's view rectangle (four comparisons). Events and
actions run after the whole pass, so a handler that removes or spawns
nodes can't disturb it. The pass runs outside the update tree: a paused or
disabled parent is still watched and woken up.

## Notes

- **Pause Parent** / **Disable Parent** own the parent's `paused` /
  `enabled` flag: don't also set it yourself on the same node.
- A rotated notifier uses its axis-aligned bounds (scaled, not rotated).
- With no current camera the view is the game's virtual screen at the
  origin.
