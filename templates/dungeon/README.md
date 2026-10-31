# Isometric Dungeon

A small dungeon room on an isometric grid. Find the key in the chest, then
open the door. The hero walks behind the pillars and the inner wall.

| Play | |
|---|---|
| Walk | Click a cell (the hero finds the way round the walls), or WASD / arrows / gamepad |
| Open | Click the chest or the door, or press E (Enter, Space, gamepad A) next to it |

WASD walk along the grid: W up-right, D down-right, S down-left, A
up-left. Two keys at once go straight up, right, down or left.

## What's where

| | |
|---|---|
| `scenes/dungeon.scene.json` | The maps: **Floor**; under **World** (Y Sort), **Walls** and **Props** (Y Sort, Solid) and the **Hero**; **Walk**, an invisible map of the walkable cells; **Cursor**; the HUD |
| `scripts/dungeon.lua` | Builds Walk from the other maps, handles clicks, the chest and the door |
| `scripts/hero.lua` | Walking: the keys along the grid's axes, clicks through the Navigation Agent; facing 8 ways |
| `scripts/cursor.lua` | Outlines the cell under the mouse and draws the path still to walk |
| `textures/` | Kenney's Isometric Miniature Dungeon (CC0), cut into a tile sheet and the hero's frames |

## How the depth works

The maps are **Isometric** with 128 x 64 cells. The tiles are 128 x 144,
taller than their cells, so walls and pillars stand on their cells; **Tile
Offset** 0, 10 puts the floor's slab under its diamond. **World** has
**Y Sort** on, and so do **Walls** and **Props**: their rows sort with the
hero by the cells' feet. **Y Sort Offset** moves that line. Walls use -56
(a back wall is behind whoever stands in its cell). Props use -24 (a
pillar hides the hero when he's behind it, not when he's in front).

## Make it yours

- **Change the room**: paint the Floor, Walls and Props maps in the
  editor (the Tile Map tab). Walk is rebuilt from them when the scene
  starts. Wall pieces sit on a cell's edge: tile 9 the upper-left one, 10
  the upper-right one, 14 the back corner.
- **More rooms**: paint further out. Walk covers up to 40 x 40 cells
  (`build_walk` in `dungeon.lua`).
- **Things to use**: `Dungeon:what_at` names what's in a cell (the chest,
  the door); `Dungeon:use` does it.
- **Faster hero**: the Hero's **Speed** (keys) and the Agent's **Speed**
  (clicks).
