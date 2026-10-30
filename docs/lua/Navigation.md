## Use it for

- **A path without an agent**: `Navigation.find_path(map, x1, y1, x2, y2)` returns the waypoints from one world point to another around walls - when your script moves the character itself.
- **Checking a route exists**: a nil result means there is no way there - before sending a unit, or to grey out a destination.
- **Big and small characters**: pass `{radius = 12}` so the path keeps that far from walls (a troll won't try a gap a goblin fits through).
- **Grid-style movement**: `{diagonal = false, smooth = false}` gives a 4-direction path through cell centres, for tile-by-tile games.

## Example

An enemy that walks to the player along a path, asking for a new path twice a second; the script is on the enemy, a node at the scene's top level (so its position is its world position), and the level is a [Tile Map](../nodes/TileMapNode.md) named *Level*.

```lua
---@class Walker : ScriptInstanceBase
local Walker = {}

Walker.properties = {
    speed = { type = "float", default = 60, label = "Speed" }, -- px/s
}

function Walker:ready()
    self.level = Scene.find_node("Level")
    self.player = Scene.find_node("Player")
    self.path, self.next, self.repath = nil, 2, 0
end

---@param dt number
function Walker:update(dt)
    if not self.level or not self.player then return end
    local x, y = self.node:get_position()

    self.repath = self.repath - dt
    if self.repath <= 0 then
        self.repath = 0.5
        local px, py = self.player:get_global_position()
        self.path = Navigation.find_path(self.level, x, y, px, py, {radius = 6})
        self.next = 2 -- waypoint 1 is where we stand
    end

    local p = self.path and self.path[self.next]
    if not p then return end
    local dx, dy = p[1] - x, p[2] - y
    local dist = math.sqrt(dx * dx + dy * dy)
    local step = self.speed * dt
    if dist <= step then
        self.node:set_position(p[1], p[2])
        self.next = self.next + 1
    else
        self.node:set_position(x + dx / dist * step, y + dy / dist * step)
    end
end

return Walker
```

## Notes

- `map` is a [Tile Map](../nodes/TileMapNode.md) (painted tiles are walls when it is solid), an [LDtk Level](../nodes/LdtkLevelNode.md) (IntGrid cells whose collision rule is **Solid**) or a [Navigation Region](../nodes/NavigationRegionNode.md) (what it baked). Any other node gives nil.
- `Navigation.find_path(map, ...)` is the same as `map:nav_find_path(...)`.
- The path is a list of `{x, y}` world points: the first is the start, the last the goal (or, with a radius, the nearest spot that fits).
- A start or goal inside a wall gives nil, as does a goal with no way to it.
- For a character that walks paths by itself - repathing, avoidance, arrival events - use a [Navigation Agent](../nodes/NavigationAgentNode.md). See also [Navigation](../../engine/docs/navigation.md).
