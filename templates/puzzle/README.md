# Puzzle (Sokoban)

Push every crate onto a target. Crates can only be pushed, one at a time.

| Play | |
|---|---|
| Move | Arrows, WASD, gamepad stick / D-pad (hold to keep going) |
| Undo | Z, U, Backspace, gamepad B |
| Restart the level | R, gamepad Y |

## What's where

| | |
|---|---|
| `scripts/puzzle.lua` | Everything: the levels (as text at the top), building the board, moving, pushing, undo, winning, the next level |
| `scenes/puzzle.scene.json` | The Board node (the script; its *Start Level* property) and the texts |
| `textures/` | Kenney's Sokoban pack (CC0) |

## Make it yours

- **New levels**: add one to `LEVELS` in `puzzle.lua` - `#` wall, `.`
  target, `$` crate, `*` crate on a target, `@` you, `+` you on a target.
  Make sure it can be solved (the template's levels were checked by a
  solver: `scripts/templates/make_templates.py` in the engine repository).
- **Different look**: swap the images in `textures/` (64x64), or change
  *Tile Size* on the Board.
- **Keys / buttons**: Project Settings > Input (move_*, undo, restart).
