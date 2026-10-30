# Animation editing: curves, events, onion skin

The **Animation** tab (bottom panel) edits the selected AnimationPlayer:
frames, property tracks and event tracks. This guide covers the tools for
polishing motion: per-key curves, events that call your scripts, and onion
skinning. The basics (frames, ranges, tracks, easing presets) are in the
editor README's *Animation timeline*.

## Keys in seconds

Keys are timed in seconds: the timeline shows frames (keys snap to them),
but a track plays smoothly between frames, so a slow sprite animation (say
2 fps) still moves its properties every game frame. When the keys run past
the last sprite frame, the tracks set the animation's length: it loops (and
finishes) when its last key is reached, holding the last frame meanwhile.

Enum properties (a particle shape, a body type) and text (a label's text, a
TextureNode's **texture**) can be keyed too: they step, holding each key
until the next.

Scenes saved before keys were in seconds (keys as frame numbers) still load:
their keys move to the times of those frames.

## Curves between keys

A property track interpolates from each key to the next. Right-click a key:

- **Easing** - a preset (sine, quad, cubic, back, elastic, bounce, ...).
- **Edit Curve...** - your own curve: drag its two handles (time across,
  progress up; handles may go above 1 or below 0 to overshoot or
  anticipate), or start from **Ease In / Ease Out / Ease In Out / Back Out /
  Anticipate / Snap**. **Use Easing** goes back to the preset.

The curve is a cubic Bezier from (0,0) to (1,1), the same as CSS
`cubic-bezier(x1, y1, x2, y2)` - values from web tools or other animation
software can be typed straight in by matching the handles. Keys with an
easing or curve show a small dot, and the timeline row draws the shape of
the motion between them.

A curve is kept as bezier handles on the two keys (each key's out handle
and the next key's in handle, as a time and value offset per component), so
the graph editor can shape each one. Saved with the track in seconds:

```json
"units": "seconds",
"keys": [{"t": 0, "bezier": true, "out": [[0.21, 0], ...]}, {"t": 0.5, "v": [90, 0, 0, 0], "in": [[-0.21, -90], ...]}]
```

(`"ease"` names a preset; values default to 0 and are left out.)

### Tutorial: a jump that feels right

1. Track **position** on the player; key the ground at frame 1, the top at
   frame 6, the ground again at frame 12.
2. Key 1: **Edit Curve > Ease Out** (fast take-off, slowing at the top).
3. Key 6: **Ease In** (slow at the top, falling faster).
4. A squash before take-off: track **scale**, key (1, 1) at frame 1 and
   (1.2, 0.8) at frame 3 with **Anticipate** from the first key.

## Events: calling scripts from an animation

**Add Track > Events > Call Script Methods** adds a track whose keys call a
method on the target node's script when playback reaches the key (not when
you scrub). Right-click a key: type the method or pick it from the target
script's methods (the list button), and an optional **argument** - a number
when it reads as one (`2.5`), `true` / `false`, else text (`"heavy"`);
empty passes the frame.

```lua
-- on the target's script
function Hero:footstep(volume)      -- argument "0.6"
    Audio.play_sound("audio/step.wav", volume)
end

function Hero:attack_hit(kind)      -- argument "heavy"
    self:deal_damage(kind == "heavy" and 20 or 10)
end
```

Every Method key also makes the player emit **animation_event** with the
method's name - listen to it from any script (no method needed on the
target):

```lua
player:connect("animation_event", function(method)
    if method == "spawn_dust" then Pool.take("components/dust.component.json", nil, self.node.position) end
end)
```

**Play Sounds** tracks play a sound per key (into its import settings' bus,
else SFX).

### Shortcut Event Tracks

To keep scripting callbacks to a minimum, common gameplay actions can be triggered directly from timeline tracks under **Add Track > Events**:

- **Emit Particles**: Acts on one of the scene's `ParticleEmitterNode`s (the menu lists them) without custom script callbacks. Each key picks an action: **Restart** (start over), **Emit a burst** of N particles (without starting it), **Start** or **Stop** emitting.
- **Spawn Component**: Instantiates a component or prefab scene at the target node's global position.
- **Enable / Disable**: Directly activates or deactivates target nodes (such as hitboxes on `AreaNode` or collision checks on `RaycastNode`).

Each key's action is written next to it on the timeline; the track's
**sliders** button lists its keys to edit them together (and its target).

Saved as `{"t": seconds, "text": "action or path", "arg": "argument"}` with `"kind": "particles"`, `"spawn"`, or `"enable"` (particle actions: `"restart"`, `"emit 12"`, `"start"`, `"stop"`).

## Frame durations & Empty frames

- **Per-Frame Durations**: Individual frames can have custom durations in seconds via the toolbar or frame context menu. When set to `0` (or reset with right-click), the frame defaults to standard `1.0 / fps`.
- **Empty / Rest Frames**: Ad-hoc empty frames (blank pauses without rendering) can be inserted or appended to frame animations and sprite sheets via right-click in the frame strip.
- **Delta-Time Simulation**: Animation ticking advances deterministically based on frame simulation `dt` rather than wall clock time, ensuring animations pause, resume, and scale accurately with game speed.

## Scene-Wide Property Animation

Animation players can drive properties on any node in the scene tree (not just immediate children) using relative paths (e.g. `../../Enemy`). Reflective property tracks support float, integer, 2D vector, color, and boolean values (such as `enabled`, `zIndex`, `origin`, and component settings).

## Onion skin

The toolbar's **onion** button (overlapping squares) draws the frames
around the playhead ghosted in the viewport - before in red, after in blue,
fading with distance - where the player's own position / rotation / scale
tracks put it at those frames. Right-click it for how many frames
before and after (0-5) and the opacity. Use it to check spacing (are the
steps even?), arcs and that a cycle's last frame leads into its first
(looping animations wrap around).

## Performance notes

- Curves are evaluated per sample with a few Newton steps (a bisection
  fallback) - cheap enough for every property every frame.
- Events fire once per key when playback passes its time; the
  `animation_event` signal is a plain event (no allocation).
- Onion skin is editor-only drawing.
