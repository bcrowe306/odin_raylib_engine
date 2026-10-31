# Navigation: path finding and agents

Characters that walk somewhere on their own - enemies chasing the player,
units sent with a click, villagers going home - need a path around walls.
The engine finds paths on a **grid** of walkable and blocked cells:

| Grid from | Blocked cells |
|---|---|
| a **TileMap** | its painted tiles when the map is solid (else empty cells - painted tiles are the floor). Isometric maps step in 8 directions like square ones; staggered and hex maps step to the cells sharing a side (hex: six) |
| an **LDtk level** | IntGrid cells whose collision rule is **Solid** |
| a **Navigation Region** | everything inside its rectangle: static bodies' collision shapes, solid tile maps' tiles, LDtk Solid cells - plus cells your scripts block |

A **Navigation Agent** walks its parent (a character) along such paths.

Paths use A* (8 directions, never cutting a blocked corner) and are
straightened wherever the line of sight is clear, so they look like
someone walking, not a staircase.

## Navigation Region

**Add Node > Physics & Collision > Navigation Region**. It covers a
rectangle from its position:

| Inspector | |
|---|---|
| **Size** | The area (px). Drag the node to place its top-left corner. |
| **Cell Size** | Grid resolution: 8-16 px for tight corridors, 32 px for big open maps (faster). |
| **Use Physics** / **Use Tile Maps** / **Use Ldtk** | What blocks. |
| **Bake** | Rebuild the cells now. The viewport shows them (red) while the region is selected; the game bakes when the scene starts. |

Scripts change the map at runtime:

```lua
-- A door: block its cells while closed.
function Door:set_open(open)
    local x, y = self.node.position.x - 16, self.node.position.y - 32
    Scene.find_node("NavigationRegion"):nav_set_blocked(x, y, 32, 64, not open)
end

-- Walls moved / a level was loaded: bake again.
Scene.find_node("NavigationRegion"):nav_rebake()
```

(Cells blocked by scripts stay blocked across rebakes.)

## Navigation Agent

Put **Add Node > Navigation Agent** under the character it moves:

```
Goblin (CharacterMover, goblin.lua)
├── Sprite
└── NavigationAgent   speed 90, radius 12
```

| Inspector | |
|---|---|
| **Speed** | px/s along the path. |
| **Radius** | The character's size: paths keep this far from walls (a big troll won't try a gap a goblin fits through), and agents keep this far from each other. |
| **Arrive Distance** | Close enough to the target. |
| **Repath Interval** | Seconds between new paths while moving - so it follows a moving target and notices opened doors. 0 = only when the target changes. |
| **Nav Map** | The region / tile map / LDtk level to path in. Empty: the Navigation Region it stands in. |
| **Move Parent** | It moves the parent: a CharacterMover (its velocity; moved and slid in Script mode), a DynamicBody (its velocity) or any node (its position). Off: read `velocity` in your script and move it yourself. |
| **Avoidance** | Steer away from other agents (also while standing: a crowd at one spot spreads out). |

Events: `navigation_finished` (arrived), `target_unreachable` (no way).

In **Simulate** the viewport draws each agent's remaining path (green).

## Tutorial: an enemy that chases the player

1. Add a **Navigation Region** covering the level; set **Cell Size** 16;
   press **Bake** - walls show red.
2. Under the enemy (a CharacterMover in **Script** mode, or a plain node)
   add a **Navigation Agent**: Speed 80, Radius 12, Repath Interval 0.4.
3. Script on the enemy:

```lua
---@class Chaser : ScriptInstanceBase
local Chaser = {}

function Chaser:ready()
    self.agent = self.node:get_node("NavigationAgent")
    self.player = Scene.find_node("Player")
    self.agent:connect("navigation_finished", function() self:attack() end)
    self.agent:connect("target_unreachable", function() self.agent:nav_stop() end)
end

function Chaser:update(dt)
    -- A new target each frame is fine: the path is only recomputed every
    -- Repath Interval seconds.
    self.agent:nav_set_target(self.player.position)
end

function Chaser:attack()
    print("caught you")
end

return Chaser
```

## Tutorial: click to move

```lua
function Unit:update(dt)
    if Input.is_mouse_button_pressed("LEFT") then
        local mx, my = Input.get_mouse_position()      -- screen pixels
        local wx, wy = Camera.screen_to_world(mx, my)  -- the world under the camera
        self.node:get_node("NavigationAgent"):nav_set_target(wx, wy)
    end
end
```

## Paths without an agent

```lua
local level = Scene.find_node("Level")              -- TileMap, LDtk level or NavigationRegion
local x, y = self.node:get_position()
local path = level:nav_find_path(x, y, tx, ty, {radius = 12})  -- nil: no way
if path then
    for i, p in ipairs(path) do print(i, p[1], p[2]) end
end
level:nav_is_walkable(tx, ty, {radius = 12})
Navigation.find_path(level, x1, y1, x2, y2, {diagonal = false, smooth = false})
```

| Option | |
|---|---|
| `diagonal` | 8 directions (default) or 4. |
| `smooth` | Straighten the path (default true). |
| `radius` | Keep this far from walls; a goal too close to one moves to the nearest place that fits. |
| `walkable_painted` | TileMap: painted tiles are the floor. |

## Agent API

| Method | |
|---|---|
| `agent:nav_set_target(x, y \| Vec2)` | Go there. |
| `agent:nav_stop()` | Stop. |
| `agent:nav_is_finished()` | Arrived (or no target). |
| `agent:nav_get_path()` | The waypoints still to go. |
| `agent:nav_distance_left()` | Path length still to go (px). |
| `agent.velocity` | The velocity it wants this frame (Move Parent off). |

## Saved as

```json
{"type": "NavigationRegionNode", "properties": {"size": [1280, 720], "cellSize": 16, "usePhysics": true, "useTileMaps": true, "useLdtk": true}}
{"type": "NavigationAgentNode", "properties": {"speed": 90, "radius": 12, "arriveDistance": 6, "repathInterval": 0.4, "navMap": "", "moveParent": true, "avoidance": true}}
```

## Performance

- A grid is a flat array of cells, cached per map and rebuilt only when
  the map (or a region's bake) changes. A search over a 256 x 256 grid
  takes about 4 ms (`bench_navigation`): agents re-path on an interval,
  not every frame.
- Radius: each cell's distance to the nearest wall is computed once per
  grid version (two passes over the grid); then "does a radius-12 agent
  fit here" is one comparison, no matter the radius.
- Regions and agents are kept in short lists by their scene, so finding
  "the region I stand in" or "agents near me" doesn't walk the scene tree.
  Avoidance compares each agent with the others (fine for dozens; for
  hundreds, give background agents Avoidance off).

## Limits

- For top-down games and anything that walks on a floor seen from above
  (or flies). Platformer path finding (jumps, falls) needs its own
  approach.
- A region's cells are blocked where a cell's centre is inside a shape -
  use a smaller Cell Size for thin walls, or give walls some thickness.
