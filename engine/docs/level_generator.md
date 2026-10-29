# Procedural levels (level generator)

A **generator** builds a level from a graph of nodes, in the style of the
Gaea add-on for Godot: some nodes make a grid of values (noise, random
fill, shapes), others change it (threshold, cave smoothing, blur, combine),
and the **tile output** turns values into tiles and writes them into a
TileMap. The same generator and **seed** always give the same level, on
every platform - so a seed is a level you can share, replay or test.

So far (#142): the generator file, the nodes, the Lua module and the
**Level Generator** window in the editor. Entity placement, rooms and
corridors, LDtk output and your own nodes follow.

## In the editor

**Assets > + > New Level Generator** creates `levels/new_level.levelgen.json`
(a cave) and opens it in the **Level Generator** window; double-click any
`.levelgen.json` to open it. The window docks like any panel.

- **The canvas** shows the nodes, each with a thumbnail of its grid (a
  tile output shows its tiles in colours; a red border: the node can't be
  computed - its error is in the side panel). Drag a node by its title;
  drag from a node's **output** (the green dot on its right) onto another's
  **input** (a dot on its left) to connect them - a link that would make a
  loop is refused; right-click an input to disconnect it. Right-click the
  canvas to add a node; right-click a node to duplicate it, delete it or
  use it as the output. Delete removes the selected node. The wheel pans,
  Ctrl/Cmd+wheel zooms, F frames everything.
- **The side panel**: the level's **size**, **seed** (the dice picks a new
  one) and **output**; the selected node's parameters and, for a tile
  output, its **rules** (a range and tiles: `3, 4` picks one of them per
  cell); a large **preview** of the selected node (or the output).
- **The toolbar**: **Save** (Ctrl/Cmd+S), **Undo** / **Redo**
  (Ctrl/Cmd+Z, Ctrl/Cmd+Shift+Z: every change), and **Apply to TileMap**,
  which writes the level into the TileMap selected in the scene - baked
  into the scene to paint over by hand; the scene's undo takes it back.

Closing the window with unsaved changes asks first.

## A cave level

```json
{"size": [64, 40], "seed": 7, "nodes": [
  {"id": 1, "type": "random_fill", "params": {"density": 0.48}},
  {"id": 2, "type": "cellular", "inputs": {"in": 1}, "params": {"iterations": 5}},
  {"id": 3, "type": "border", "params": {"width": 1}},
  {"id": 4, "type": "combine", "inputs": {"a": 2, "b": 3}, "params": {"op": "max"}},
  {"id": 5, "type": "tile_output", "inputs": {"in": 4},
   "rules": [{"min": 0.5, "max": 1, "tiles": [12, 13, 14]}]}
]}
```

Random fill scatters walls; the cellular automaton smooths them into cave
walls and open rooms; the border closes the edges; the tile output puts one
of tiles 12-14 (picked at random, the same for a seed) on every wall cell.
Save it as `levels/caves.levelgen.json` and generate from a script:

```lua
function Level:ready()
    local ok, why = LevelGen.generate("levels/caves.levelgen.json", self.node:get_node("Ground"), Save.get("seed", 7))
    if not ok then Log.error(why) end
end
```

The TileMap (with a tileset, **Solid** on for colliders) takes the
generator's size and its cells become the tiles; its colliders are rebuilt.

## Terrain (a side view)

```json
{"size": [120, 40], "seed": 3, "nodes": [
  {"id": 1, "type": "gradient", "params": {"direction": "vertical"}},
  {"id": 2, "type": "noise", "params": {"scale": 18, "octaves": 4}},
  {"id": 3, "type": "remap", "inputs": {"in": 2}, "params": {"to_min": -0.25, "to_max": 0.25}},
  {"id": 4, "type": "combine", "inputs": {"a": 1, "b": 3}, "params": {"op": "add"}},
  {"id": 5, "type": "tile_output", "inputs": {"in": 4}, "rules": [
     {"min": 0.55, "max": 0.62, "tile": 1},
     {"min": 0.62, "max": 9, "tile": 2}]}
]}
```

A top-to-bottom ramp plus noise makes rolling ground: values from 0.55 get
grass (tile 1) and deeper ones dirt (tile 2); above stays empty.

## The file

| Key | |
|---|---|
| `size` | `[width, height]` in cells (1-4096). |
| `seed` | The default seed (scripts can pass another). |
| `output` | The id of the node whose result is the level (default: the last tile output). |
| `nodes` | Each with an `id` (a positive number), its `type`, `inputs` (port -> id of the node it reads), `params` (missing ones take their defaults), and for the tile output `rules`; `pos` is where the editor draws it. |

Every port carries a grid of numbers the size of the level - usually 0
(empty / low) to 1 (solid / high). An input that isn't connected reads 0
everywhere. A node may feed any number of others (computed once); a cycle
is an error.

## Nodes

**Generators**

| Type | Parameters | |
|---|---|---|
| `constant` | `value` (1) | The same value everywhere. |
| `noise` | `scale` (16), `octaves` (3), `persistence` (0.5), `seed` (0) | Smooth value noise (fBm), 0..1. |
| `random_fill` | `density` (0.45), `seed` (0) | Each cell 1 with that chance, else 0. |
| `gradient` | `direction`: `horizontal` (0 left .. 1 right), `vertical` (0 top .. 1 bottom), `radial` (1 centre .. 0 corners) | A ramp. |
| `border` | `width` (1) | 1 within that many cells of the edge. |
| `rect` | `x`, `y`, `w`, `h` (8), `value` (1) | A filled rectangle. |

**Modifiers** (input `in`, or `a` and `b`)

| Type | Parameters | |
|---|---|---|
| `threshold` | `value` (0.5), `invert` (false) | 1 at or above the value, else 0. |
| `invert` | | 1 - value. |
| `remap` | `from_min`, `from_max` (0, 1), `to_min`, `to_max` (0, 1) | One range onto another (clamped). |
| `blur` | `radius` (1) | The average of each cell's square of neighbours. |
| `cellular` | `iterations` (4), `birth` (5), `survive` (4), `edge_solid` (true) | Cave smoothing: an empty cell with at least `birth` solid neighbours (of 8) becomes solid, a solid one with fewer than `survive` empties. |
| `dilate` / `erode` | `iterations` (1) | Grow / shrink solid areas a cell at a time. |
| `combine` | `op`: `add`, `subtract`, `multiply`, `min`, `max`, `mask` (a where b is solid), `average` | Two grids into one. |

**Output**

| Type | | |
|---|---|---|
| `tile_output` | `empty` (-1), `rules` | Each cell takes the first rule whose `min`..`max` holds its value: one of its `tiles` (or `tile`), picked by the cell and the seed. Cells no rule takes get `empty` (-1: none). |

`seed` on a node adds to the graph's seed, so two noise nodes can differ.

## Lua

| Function | |
|---|---|
| `LevelGen.generate(file, tilemap [, seed])` -> ok, why | Writes the level into a TileMap node; `level_generated` (the map's name) is emitted on the event bus. |
| `LevelGen.values(file [, seed [, node_id]])` -> `{width, height, values}` | The grid without a tile map (row-major: `values[y * width + x + 1]`) - any node's with `node_id`. Place enemies, pickups or the player on it yourself until entity placement lands. |

```lua
-- Put the player on the first open cell of the cave.
local g = LevelGen.values("levels/caves.levelgen.json", seed)
for y = 0, g.height - 1 do
    for x = 0, g.width - 1 do
        if g.values[y * g.width + x + 1] < 0.5 then
            player.position = Vec2((x + 0.5) * 16, (y + 0.5) * 16)
            return
        end
    end
end
```

Generate during a loading screen ([`scene_flow.md`](scene_flow.md)) for big
levels.

## From Odin

```odin
g, err := Gen_LoadFile(ctx, "levels/caves.levelgen.json")
defer Gen_GraphDestroy(&g)
Gen_ApplyTileMap(&g, tilemap, seed, ctx)               // into a TileMapNode
grid, _ := Gen_Evaluate(&g, 0, seed)                   // the output's values (any node: its id)
tiles, size, _ := Gen_Tiles(&g, 0, seed)               // tile indices (-1 = none)
text := Gen_GraphSerialize(&g)                         // back to .levelgen.json
```

`GEN_KINDS` (engine/level_gen.odin) describes every node type - its
inputs, parameters with defaults and help - for tools.
