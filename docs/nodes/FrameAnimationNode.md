## Settings

Saved in the scene beside the common properties:

| Setting | Scene key | |
|---|---|---|
| Frames | `frames` | The images, in order (project paths) |
| FPS | `fps` | Frames per second |
| Loop | `loop` | Start over after the last frame |

A Frame Animation plays a list of separate images. For sprite sheets,
several named animations, property tracks and events, use an
**Animation Player** (the Animation tab edits it); for `.aseprite` files, an
**Aseprite** node.

```json
{
  "type": "FrameAnimationNode",
  "name": "Flame",
  "fps": 12,
  "loop": true,
  "frames": ["textures/flame_1.png", "textures/flame_2.png", "textures/flame_3.png"]
}
```
