## Use it for

- **A new level every run**: `LevelGen.generate(generator, tilemap, seed)` writes a generated level into a [TileMap](../nodes/TileMapNode.md) - its size, its tiles, its colliders and the generator's entities as children.
- **Repeatable levels**: the same generator and seed always give the same level - a daily seed, a seed the player types in, a level number as the seed.
- **Placing things yourself**: `LevelGen.values(generator, seed)` returns the grid of numbers (0..1 usually) without touching a tile map - find a floor cell for the player, the farthest cell for the exit.
- **Entities without tiles**: `LevelGen.entities(generator, seed)` lists the cells the generator's entity outputs picked, each with its component, to instance where and how you like.
- **Reading an inner node**: `values` with a `node_id` reads any node of the graph (a noise, a cave pass) - for a minimap or debugging.

## Example

A cave that is new each time the scene starts or **regenerate** is pressed, with the player put on a floor cell - the script is on the level's root, with a [TileMap](../nodes/TileMapNode.md) named `Ground` at 0, 0 and a `Player` beside it; in this generator, values below 0.5 are floor.

```lua
---@class Cave : ScriptInstanceBase
local Cave = {}

local GEN = "levels/caves.levelgen.json"

Cave.properties = {
    tile_size = { type = "int", default = 16, label = "Tile Size" },  -- px per cell
}

function Cave:ready()
    self.ground = self.node:get_node("Ground") ---@type TileMapNode
    self:build(os.time())
end

---@param dt number
function Cave:update(dt)
    if Input.is_action_pressed("regenerate") then self:build(os.time()) end
end

---@param seed integer
function Cave:build(seed)
    local ok, why = LevelGen.generate(GEN, self.ground, seed)
    if not ok then
        Log.warn("cave: " .. tostring(why))
        return
    end
    -- The first floor cell from the top-left, for the player.
    local g = LevelGen.values(GEN, seed)
    local player = self.node:get_node("Player")
    if not g or not player then return end
    for y = 0, g.height - 1 do
        for x = 0, g.width - 1 do
            if g.values[y * g.width + x + 1] < 0.5 then
                local half = self.tile_size / 2
                player:set_position(x * self.tile_size + half, y * self.tile_size + half)
                return
            end
        end
    end
end

return Cave
```

## Notes

- A nil or 0 seed uses the seed saved in the generator file. Pass `os.time()` (or any changing integer) for a new level each time.
- `values` and `entities` work in cells, from 0, with `values` row-major and 1-based: cell x, y is `values[y * width + x + 1]`. Multiply by the tile size for px.
- `generate` replaces the entities it placed last time, emits `"level_generated"` (the tile map's name) on the [event bus](Events.md), and rebuilds colliders when the tile map is **Solid**.
- Each call evaluates the whole graph - fine at load time or on a key press, not every frame.
- A [Level Generator](../nodes/LevelGeneratorNode.md) node generates without a script; the [generator guide](../../engine/docs/level_generator.md) explains the graph's nodes.
