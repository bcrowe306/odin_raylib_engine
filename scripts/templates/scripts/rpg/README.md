# Top-down RPG

A small dungeon to escape: talk to the wizard, fight the slimes, take the
key from the chest, unlock the door and reach the way out.

| Play | |
|---|---|
| Move | WASD, arrows, gamepad stick / D-pad |
| Sword | Space, J, gamepad X |
| Talk / open | E, K, gamepad A (also goes on in a dialogue) |

## What's where

| | |
|---|---|
| `scenes/dungeon.scene.json` | Floor and Walls (solid) tile maps, the wizard, slimes, potion, chest, locked door, exit, the player, camera, HUD, dialogue box |
| `scripts/player.lua` | Eight-way movement, the sword, interacting, hearts and knockback |
| `scripts/slime.lua` | Chases the player when close, hurts on touch, two hits to beat |
| `scripts/npc.lua`, `chest.lua`, `locked_door.lua` | Interactables: anything tagged `interactable` with `hint()` / `interact()` |
| `scripts/potion.lua`, `exit.lua`, `hud.lua` | A heal, winning, the HUD |
| `textures/` | Kenney's Tiny Dungeon (CC0); hearts from Pixel Platformer |

## Make it yours

- **Paint rooms**: the *Walls* map is solid, *Floor* isn't (tile brush in
  the viewport).
- **New interactables**: tag a node `interactable` and give its script
  `hint(player)` (what the E prompt says) and `interact(player)`.
- **More dialogue**: edit the lines in `npc.lua` (or give each NPC its own).
- **Tougher slimes**: their Speed / Sight / Hits in the Inspector.
