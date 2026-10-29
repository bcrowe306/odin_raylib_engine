# Changing scenes: transitions, preloading, loading screens

## Transitions

```lua
Scene.change_scene("level_2")                                        -- at once (or the project's default)
Scene.change_scene("level_2", {transition = "fade", duration = 0.4})  -- behind a fade
Scene.change_scene("level_2", {transition = "circle", color = {1, 1, 1}})
Scene.change_scene("level_2", {transition = "slide_left", duration = 0.6, easing = "out_cubic"})
Scene.change_scene("level_2", {transition = "wipe_right", transition_in = "circle", duration_in = 0.6})
```

There are two families:

**Cover transitions** cover the screen with a colour, switch scenes
underneath **once the new scene's assets are loaded**, then uncover:

| `transition` | |
|---|---|
| `"fade"` | The colour fades in, then out. |
| `"wipe_left"`, `"wipe_right"`, `"wipe_up"`, `"wipe_down"` | The colour sweeps across. |
| `"circle"` | An iris closes on the centre, then opens. |

**Scene transitions** show both scenes: the old scene keeps running while
the new one loads, then its last frame is kept and drawn with the live new
scene:

| `transition` | |
|---|---|
| `"crossfade"` | The old frame fades out over the new scene. |
| `"dissolve"` | The old frame burns away in noise (its rim in `color`). |
| `"pixelate"` | The old frame breaks into blocks; the new scene comes back from blocks. |
| `"slide_left"`, `"slide_right"`, `"slide_up"`, `"slide_down"` | The new scene slides in over the old one, towards that side. |
| `"push_left"`, `"push_right"`, `"push_up"`, `"push_down"` | The new scene pushes the old one out. |
| a shader | Your own (below). |

They need the frame the game draws into, which the game and the editor's
Play have; with the **smooth pixel camera** (Project Settings > Video) they
fall back to a fade over the same time.

| Option | |
|---|---|
| `transition` | A name above, one given to `Scene.register_transition`, or a shader file. |
| `duration` | Seconds: each half of a cover transition (covering, then uncovering), the whole of the others (default 0.4). |
| `easing` | The curve, any [tween easing](../SCRIPTING.md) - `"linear"`, `"out_cubic"`, `"in_out_back"`... (default `"in_out_sine"`). |
| `color` | `{r, g, b[, a]}` 0..1 or `"#rrggbb"`: the cover's colour, the dissolve's rim (default black). |
| `transition_in`, `duration_in`, `easing_in` | The uncover half of a cover transition, when it differs (out with a wipe, in with a circle). |
| `pause` | `true`: the game is paused while it runs (`Engine.set_paused`) - scripts and physics wait, nodes set to *Always* still run - and unpaused after. |
| `loading` | A loading screen scene (below). |
| `min_time` | Seconds the loading screen stays at least (default 0.5). |

`Scene.is_transitioning()` is true meanwhile. A change asked for while one
runs **waits** for it (only the last one asked for is kept); asking for the
same scene again is ignored. The name can also be the scene's file
(`"scenes/level_2.scene.json"`, e.g. from a scene property).

### Events

On the global event bus ([`events.md`](events.md)), with the target scene's
name: `transition_started`, `transition_midpoint` (the scenes switched -
the new scene is loaded) and `transition_finished`.

```lua
-- A global script: knows when the scene changed.
Events.connect("transition_midpoint", function(scene) Log.info("now in " .. scene) end)
-- The new scene's script: start the level once it is fully on screen.
Events.once("transition_finished", function() self:start_countdown() end, self.node)
```

### The project's default

**Project Settings > General > Scene Transitions** picks a transition,
duration and easing for `Scene.change_scene(name)` without options, and
for the options a script leaves out. Saved in `project.json`:

```json
"scene_flow": {"transition": "crossfade", "duration": 0.5, "easing": "in_out_sine"}
```

"None" (the default) changes scenes at once, as before.

### Your own transitions (shaders)

A fragment shader blends the two scenes: `texture0` is the old scene's
last frame, `new_scene` the new scene, `progress` goes from 0 (old) to 1
(new). `resolution` (pixels) and `transition_color` (the `color` option)
are there too.

```glsl
#version 330
in vec2 fragTexCoord;
out vec4 finalColor;
uniform sampler2D texture0;   // the old scene
uniform sampler2D new_scene;  // the new scene
uniform float progress;       // 0 .. 1
uniform vec2 resolution;

void main() {
    // A diagonal wipe with a soft edge.
    float d = (fragTexCoord.x + (1.0 - fragTexCoord.y)) * 0.5;
    float k = smoothstep(progress - 0.05, progress + 0.05, d);
    finalColor = mix(texture(new_scene, fragTexCoord), texture(texture0, fragTexCoord), k);
}
```

Save it in the project (`shaders/diagonal.fs`) and use its path, or give it
a name once:

```lua
Scene.register_transition("diagonal", "shaders/diagonal.fs")
Scene.change_scene("level_2", {transition = "diagonal", duration = 0.7})
```

The shader reloads when you save it. One that is missing or doesn't
compile crossfades instead (with a warning in the log).

## Preloading

Start loading a scene's assets before you need it, so the change is
instant:

```lua
function Menu:ready()
    Scene.preload("level_1")              -- while the player reads the menu
end

function Menu:on_start_pressed()
    Scene.change_scene("level_1", {transition = "fade"})
end
```

`Scene.preload_progress("level_1")` reports 0..1. Preloading finds the
scene's textures (sprites, nine-slices, particles - any image a node
names), sounds, music and fonts, including those of the components it
uses.

## Loading screens

For big levels, show a scene of your own while the level loads - a progress
bar, tips, an animation:

```lua
Scene.change_scene("world_2", {transition = "fade", loading = "loading", min_time = 0.8})
```

1. A fade into the **loading** scene.
2. `world_2` loads in the background.
3. When it's loaded and the screen has been up for `min_time` (so a fast
   load doesn't just flash it), a fade into `world_2`.

### Tutorial: a loading screen with a progress bar

Create a scene **loading** (Scenes `+`), keep it light (no big textures -
it must appear quickly):

```
root
├── Background   (a ColorRect / TextureNode, or the scene background colour)
├── Title        (Text: "Loading...")
├── Tip          (Text)
├── Bar          (UI Progress Bar, 0..100)
└── Loader       (Node, scripts/loading.lua)
```

```lua
-- scripts/loading.lua
---@class Loading : ScriptInstanceBase
local Loading = {}

local TIPS = {"Press Shift to dash", "Coins heal you a little", "Bosses have a weak spot"}

function Loading:ready()
    self.bar = Scene.find_node("Bar")
    Scene.find_node("Title").text = "Loading " .. (Scene.loading_target() or "") .. "..."
    Scene.find_node("Tip").text = TIPS[math.random(#TIPS)]
    self.shown = 0
end

function Loading:update(dt)
    -- Ease the bar towards the real progress (it can jump in steps).
    self.shown = self.shown + (Scene.loading_progress() - self.shown) * math.min(1, dt * 8)
    self.bar.value = self.shown * 100
end

return Loading
```

Add the scene to the project's scene list (it is, if you made it with
Scenes `+`). Then from anywhere:

```lua
Scene.change_scene("world_2", {transition = "fade", loading = "loading"})
```

| Function | |
|---|---|
| `Scene.loading_progress()` | 0..1: how far the scene behind the loading screen has loaded (1 when nothing loads). |
| `Scene.loading_target()` | That scene's name (nil when nothing loads). |

## How loading works (performance)

- Preloading walks the scene file once and queues each asset.
- **Textures** - usually most of the time - are read on the main thread
  (packed `.rayzr` games read from one archive) and **decoded on two worker
  threads** (PNG decoding is the expensive part); finished images are
  uploaded to the GPU on the main thread, up to 4 a frame. The game keeps
  running smoothly - a loading screen can animate.
- Sounds, music and fonts load on the main thread within a 4 ms budget a
  frame.
- Loaded assets are cached: the scene finds them when it loads, and the
  preload lets go of its references once the scene has its own.
- Threads only touch their own job's memory; a preload that is cancelled
  while an image is decoding leaves the job to be freed when the worker
  finishes.

## From Odin

```odin
Game_ChangeSceneWith(game, scene, .Fade, 0.4)                 // a transition
spec := TRANSITION_DEFAULT                                     // every option
spec.kind, spec.duration, spec.ease = .PushLeft, 0.6, .Out_Cubic
Game_ChangeSceneSpec(game, scene, spec)
Transition_Register(game, "diagonal", "shaders/diagonal.fs")  // a shader transition by name
Game_ChangeSceneVia(game, scene, loadingScene, .Fade, 0.4, rl.BLACK, 0.8) // through a loading screen
Scene_PreloadBegin(game, scene)
progress := Scene_PreloadProgress(game, scene)
```

The transitions are in `engine/scene_transition.odin`, preloading and
loading screens in `engine/scene_flow.odin`.
