# Aseprite

Aseprite files (`.aseprite` / `.ase`) are first-class assets: put them in the
project and use them as they are - no exporting sprite sheets. The engine reads
the format itself and draws frames exactly as Aseprite does (layer order,
every blend mode, opacity, groups, indexed / grayscale colour, tilemaps); save
in Aseprite and the editor - and a running game - update at once.

| What you made in Aseprite | What you get |
|---|---|
| Frames and their durations | Played at those durations (Speed scales them) |
| Tags: direction, repeat count | `AsepriteNode` plays them as Aseprite does: forward, reverse, ping-pong, ping-pong reverse; N repeats then `animation_finished` |
| Layers (hidden, groups, blend modes, opacity) | Composited like Aseprite; per node you can hide / show layers (outfits, equipment) - from the Inspector or `aseprite_set_layer_visible` |
| Slices (9-patch, pivot, per-frame keys) | A pivot slice moves the node's origin frame by frame; scripts read any slice (`aseprite_slice`) for hitboxes, spawn points, panels |
| User data (text, colour, properties) on the sprite, layers, cels, tags, slices, tiles | All of it readable from Lua (`aseprite_info`, `aseprite_layer_data`, `aseprite_cel_data`, `aseprite_slice`) |
| Tilemap layers + tilesets (with flips) | A `TileMapNode` whose tileset is the file and *Aseprite Layer* names the layer: the map, its tiles and flips come from the file (solid colliders too) |
| Any image use | Every place that takes an image takes an Aseprite file too (its first frame): sprites, nine-slices, UI images, `set_texture` |

## In the editor

- **Assets** lists them in an *Aseprite* section (Folders view: wherever they
  are); thumbnails are the first frame. Imported files go to `sprites/`.
- **Drag one into the viewport**: an *Aseprite Sprite* (`AsepriteNode`) playing
  the file's first tag. Or Add Node > Aseprite Sprite and pick the file.
- **Inspector > Aseprite**:
  - *File* and the edit button (opens it in Aseprite);
  - *Animation*: the tags, each with its frames, direction, repeats and length;
  - *Frame* with a play button: previews the tag in the viewport (the editor
    doesn't run nodes otherwise);
  - *Pivot Slice*: the slices with a pivot;
  - *Aseprite Layers*: every layer's visibility for this node - a change from
    the file is saved on the node (*Hide Layers* / *Show Layers*);
  - *Aseprite Data*: the file's slices and the sprite's user data.
  - Also *Autoplay*, *Loop* (tags without a repeat count: loop or play once),
    *Speed*, *Tint*.
- **Edit in Aseprite**: double-click the asset, right-click > Edit in
  Aseprite, or the Inspector's button. Settings > General > Aseprite sets the
  program; empty: found where Aseprite installs (the app, Steam, the PATH).

## Tutorial: an animated character

1. In Aseprite, draw the character with tags `idle`, `run` (forward, looping)
   and `hurt` (forward, repeat 1). Add a slice `feet` with a pivot at the
   bottom centre (Slice tool, then Slice Properties > Pivot).
2. Save it into the project (`sprites/hero.aseprite`), drag it into the
   viewport, and set *Pivot Slice* to `feet`: the sprite now stands on its
   position, even if frames are cropped differently.
3. Give it a script:

```lua
---@class Hero : ScriptInstanceBase
local Hero = {}

function Hero:ready()
    self.node:aseprite_play("idle")
end

function Hero:update(dt)
    local x = Input.get_axis("move_left", "move_right")
    if self.hurting then return end
    local want = x ~= 0 and "run" or "idle"
    if self.playing ~= want then
        self.node:aseprite_play(want)
        self.playing = want
    end
    if x ~= 0 then self.node:set_scale(x, 1) end -- face the way it runs
end

function Hero:hit()
    self.hurting = true
    self.node:aseprite_play("hurt") -- repeat 1: plays once
end

-- A tag's repeats are done.
function Hero:on_animation_finished(tag)
    if tag == "hurt" then
        self.hurting = false
        self.playing = nil
    end
end

return Hero
```

4. Back in Aseprite, change a frame and save: the editor shows it right away;
   so does the game if it's running.

## Scripting

| Method | |
|---|---|
| `aseprite_play([tag])` | Play a tag from its first frame (no tag: every frame) |
| `aseprite_stop()` / `aseprite_resume()` / `aseprite_is_playing()` | |
| `aseprite_frame()` / `aseprite_set_frame(n)` | The frame shown (0-based) |
| `aseprite_info()` | `{width, height, frames = {ms...}, tags = {{name, from, to, direction, repeats, user}...}, layers, user}` |
| `aseprite_slice(name[, frame])` | `{x, y, width, height, center?, pivot?, user}` or nil |
| `aseprite_layer_data(layer)` / `aseprite_cel_data(layer[, frame])` | `{text, color?, properties}` |
| `aseprite_set_layer_visible(layer, on)` | A group covers its layers |

Events: `animation_finished(tag)`, `animation_looped(tag)` (each repeat or
ping-pong turn), `frame_changed(frame)` - as `on_<event>` methods or
`node:connect`.

**Hitboxes from slices**: draw a slice `hitbox` in Aseprite, key it per frame
(the slice moves with the attack), then each frame:

```lua
local s = self.node:aseprite_slice("hitbox")
if s then check_hit(s.x, s.y, s.width, s.height) end
```

**Events from cel data**: in Aseprite, give the cel where the foot lands
user data `step` (Cel Properties > User Data); then:

```lua
function Hero:on_frame_changed(frame)
    local d = self.node:aseprite_cel_data("Body", frame)
    if d and d.text == "step" then Audio.play_sound("audio/step.wav") end
end
```

## Tile maps from Aseprite

Make a tilemap layer in Aseprite (Layer > New > New Tilemap Layer), paint it,
save. In the engine: a TileMap node, its tileset set to the `.aseprite` file
(Assets: right-click > Use as Tileset of Selected Tile Map, or the
`tilemap.tileset` in the scene), and *Aseprite Layer* = the layer's name. The
map's size, tiles (flipped tiles included) and tile size come from the file's
first frame, again on every save; *Solid* builds colliders as usual. Paint the
map in Aseprite (painting it here is overwritten by the next save).

## Exporting

Aseprite files go into `game.rayzr` as they are and are read at runtime - the
same on every platform, the web included.

## How it works

- `engine/aseprite.odin` reads every chunk of the format
  (`aseprite/docs/ase-file-specs.md`); one arena per file.
- `engine/aseprite_render.odin` composites frames: Aseprite's render plan
  (layer order + cel z-index), its blend functions (ported from its MIT
  doc library) and fixed-point maths, groups composed on their own when the
  file says so. `engine/aseprite_test.odin` checks it against Aseprite's own
  renders and metadata (`tests/aseprite/`, rebuilt by
  `scripts/aseprite_fixtures.sh` with Aseprite installed) - pixel for pixel,
  including Aseprite's own test sprites.
- `engine/aseprite_resource.odin`: one copy per file (shared by every node),
  sheets per layer set, reloaded on save.
- `engine/aseprite_node.odin`: the node and its Lua methods.
