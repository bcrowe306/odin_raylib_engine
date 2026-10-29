# Platformer

A small, complete platformer: run and jump to the door at the end of the
level, collect coins, avoid spikes and stomp the enemies.

| Play | |
|---|---|
| Move | A / D, arrows, gamepad stick / D-pad |
| Jump | Space, W, Up, gamepad A (hold for a higher jump) |

## What's where

| | |
|---|---|
| `scenes/level1.scene.json` | The level: the tile maps (Level is solid, Decor isn't), coins, spikes, enemies, the door, the player, the camera, the HUD |
| `scripts/player.lua` | Movement (coyote time, jump buffer, jump cut), animations, dying and winning - tune it in the Inspector |
| `scripts/enemy.lua`, `enemy_hitbox.lua` | Walks, turns at walls and ledges; stomped from above, hurts otherwise |
| `scripts/coin.lua`, `hazard.lua`, `goal.lua`, `hud.lua` | Pickups, spikes, the door (its **Next Level** property), the coin count and messages |
| `components/` | Starter physics components to drag into a level: a crate that falls and gets pushed, a static platform, a trigger zone (an area that reports what enters it) |
| `textures/` | Kenney's Pixel Platformer (CC0) |

## Make it yours

- **Paint the level**: select *Level* (solid) or *Decor* and use the tile
  brush in the viewport (Inspector > Tile Map).
- **More of something**: duplicate a coin, a spike or an enemy (Cmd/Ctrl+D)
  and move it.
- **A second level**: duplicate the scene (Assets > right-click >
  Duplicate), change it, and set the door's *Next Level* in the first one.
- **Feel**: the player's properties (speed, jump velocity, coyote time...).

The game runs at 320x180, scaled up in whole steps (Project Settings >
Video): crisp pixels at any window size.
