# Pixel-perfect rendering

Pixel-art games draw at a small **virtual resolution** (320 x 180, 426 x 240,
640 x 360...) that is scaled up to the window. Four Project Settings >
**Video** options control how that looks:

| Setting | What it does | Use it when |
|---|---|---|
| **Sharp Pixels** | Scales the frame nearest-neighbour (crisp) instead of smoothly. | Always for pixel art. |
| **Integer Scaling** | Scales by a whole number (2x, 3x, 4x...) with bars around the frame. Every game pixel is the same size on screen. | You want perfectly even pixels (no 3x/4x mix of rows and columns). |
| **Pixel Snap** | The camera and the sprites sit on whole game pixels. | Moving or scaled sprites shimmer, or their pixels look uneven. |
| **Smooth Camera** | (With Pixel Snap.) Keeps the camera's sub-pixel motion when scaling up, so slow pans glide instead of stepping one game pixel at a time. The UI stays put. | A smoothly following camera in a low-resolution game. |

They apply to the running game (Play, exported builds). The editor's
viewport also snaps sprites when **Pixel Snap** is on, so what you place is
what you get.

## Recipes

**Classic crisp pixel art** (most games):

- Virtual Resolution `320 x 180` (or `640 x 360`), Sharp Pixels, Integer
  Scaling, Pixel Snap, Smooth Camera.
- On a 1920 x 1080 screen that's exactly 6x; on 1280 x 720, 4x; on
  1366 x 768, 4x with bars (1280 x 720 of picture).

**Pixel art that fills the screen** (accepts slightly uneven pixels):

- Sharp Pixels and Pixel Snap, but not Integer Scaling: no bars, but at
  3.125x some game pixels are 3 screen pixels wide and some 4.

**Hi-res art** (painted, vector): leave all four off.

## Why each one matters

**Uneven pixels.** 320 pixels stretched to 1000 is 3.125x: a game pixel can't
be 3.125 screen pixels, so some columns get 3 and some 4. Integer Scaling
picks 3x (960 px) and puts 20 px bars on each side instead.

**Shimmering.** A sprite at x = 10.4 draws between two pixels; as it moves,
its texels fall on different screen pixels from frame to frame and the
sprite seems to wobble. Pixel Snap rounds where each sprite's top-left
corner lands (rotated sprites aren't snapped) and the camera's position.

**Choppy camera.** With the camera snapped too, a slow pan moves the whole
world one game pixel - 4 screen pixels at 4x - at a time. Smooth Camera
draws the world snapped into its own texture (one pixel larger on each
side) and shifts that texture by the leftover fraction when scaling it up:
at 4x the world can move one screen pixel at a time, while every sprite
still sits on the game's pixel grid. Layers the camera doesn't draw (the
UI, usually Layer 8) are drawn on top, not shifted.

## Scripting

These are project settings, not script calls. Scripts that place things by
hand can keep positions whole themselves:

```lua
-- A damage number that floats up smoothly but draws on whole pixels.
function DamageNumber:update(dt)
    self.y = self.y - 20 * dt
    self.node.position = {math.floor(self.start_x + 0.5), math.floor(self.y + 0.5)}
end
```

## Saved as

```json
"window": {"virtual_width": 320, "virtual_height": 180, ...},
"video": {"sharp_scaling": true, "integer_scaling": true, "pixel_snap": true, "smooth_camera": true, ...}
```

## Performance

- Integer Scaling and Pixel Snap cost nothing measurable (a rounding per
  sprite draw and per camera).
- Smooth Camera draws the world into a second render texture (virtual size
  + 2 px) and composites two textures at the end instead of one - one extra
  full-screen textured quad. Post effects apply to the world texture (not
  the UI layers) in this mode.

## Notes

- The mouse still reads in game units (scaled and offset for the bars).
- Lighting's light map is composited inside the world texture, so it moves
  with the world.
- Text drawn with TTF fonts isn't snapped; use bitmap / pixel fonts at their
  native size for crisp text.
