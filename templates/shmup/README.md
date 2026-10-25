# Shoot 'em up

Fly right through waves of enemy planes: shoot them down, dodge their
bullets, keep your three lives. Your best score is saved.

| Play | |
|---|---|
| Fly | WASD, arrows, gamepad stick / D-pad |
| Fire | Space, J, gamepad A (hold) |

## What's where

| | |
|---|---|
| `scenes/game.scene.json` | The sea (scrolls), the player, the spawner, a Shots node holding bullets / enemies / explosions, the HUD |
| `components/` | Player and enemy bullets, the two enemy kinds (drifter, shooter), the explosion - edit them like scenes |
| `scripts/player.lua` | Movement inside the screen, firing (pooled bullets), lives, blinking after a hit |
| `scripts/enemy.lua`, `spawner.lua` | Enemy movement and shooting; waves that speed up |
| `scripts/bullet.lua` | Hits by distance (no physics needed for this) |
| `scripts/hud.lua` | Score, best score (`Save`), lives, game over |
| `textures/` | Kenney's Pixel Shmup (CC0) |

## Make it yours

- **A new enemy**: duplicate `components/drifter.component.json`, change
  its sprite and properties (speed, wobble, hits, shoots, points), and
  spawn it in `spawner.lua`.
- **Power-ups**: a component that moves left like an enemy, and in its
  script checks the distance to the player (see `bullet.lua`).
- **Bullets** come from a pool (`Pool.take`, `destroy()` returns them): no
  allocations while playing, however many you fire.
