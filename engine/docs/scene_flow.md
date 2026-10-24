# Changing scenes: transitions, preloading, loading screens

## Transitions

```lua
Scene.change_scene("level_2")                                       -- at once
Scene.change_scene("level_2", {transition = "fade", duration = 0.4}) -- behind a fade
Scene.change_scene("level_2", {transition = "circle", color = {1, 1, 1}})
```

| Option | |
|---|---|
| `transition` | `"fade"`, `"wipe_left"`, `"wipe_right"`, `"wipe_up"`, `"wipe_down"`, `"circle"` (an iris). |
| `duration` | Seconds for each half - covering, then uncovering (default 0.4). |
| `color` | `{r, g, b}` 0..1 (default black). |
| `loading` | A loading screen scene (below). |
| `min_time` | Seconds the loading screen stays at least (default 0.5). |

The screen is covered, the new scene switches in **once its assets are
loaded**, then it's uncovered. `Scene.is_transitioning()` is true meanwhile
(ignore input, don't start another change). The name can also be the
scene's file (`"scenes/level_2.scene.json"`, e.g. from a scene property).

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
  (packed `.ore` games read from one archive) and **decoded on two worker
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
Game_ChangeSceneVia(game, scene, loadingScene, .Fade, 0.4, rl.BLACK, 0.8) // through a loading screen
Scene_PreloadBegin(game, scene)
progress := Scene_PreloadProgress(game, scene)
```
