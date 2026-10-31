# Hex Island

An island on a hex grid. Walk round the water, the trees and the rocks,
and pick every flower.

| Play | |
|---|---|
| Walk | Click a hex: the explorer finds the way there, hex by hex |
| One step | D right, A left, E up-right, Q up-left, C down-right, Z down-left (arrows: right / left) |

## What's where

| | |
|---|---|
| `scenes/island.scene.json` | **Ground** (Hex Pointy: land and water), under **World** (Y Sort) **Objects** (trees, rocks, flowers) and the **Explorer**; **Walk**, an invisible map of the hexes that can be walked on; the counter |
| `scripts/island.lua` | Builds Walk, turns clicks and keys into walks, picks the flowers, outlines the hex under the mouse and draws the path |
| `scripts/explorer.lua` | Finds the path (`nav_find_path` in Walk) and walks it centre to centre |
| `textures/` | Kenney's Hexagon Tiles (CC0): the land tiles, the things on them, the alien |

## How it works

The maps' **Grid** is **Hex (pointy)** with 65 x 66 cells, odd rows
shifted. The tiles are 65 x 89, a hexagon on a slab: **Tile Offset** 0, 23
puts the slab under the hexagon. The objects stand on the hex's middle
(offset 0, -25). On a hex map, `tilemap_neighbors` gives the six sides
clockwise from the right, and paths step through them.

## Make it yours

- **Reshape the island**: paint Ground and Objects in the editor (the Tile
  Map tab). Walk is rebuilt from them when the scene starts. Tile 7 of
  Ground is water.
- **Other things to pick**: `FLOWERS` in `island.lua` lists the Objects
  tiles that are picked up. The others block.
- **Turns**: `Explorer:go_to` gets the whole path. Walk only the first N
  steps of it for a move range.
