# Sprite atlases

GPUs draw fastest when many sprites come from the **same texture**: raylib
puts consecutive draws with one texture into a single draw call, and every
texture switch starts a new one. A scene with hundreds of enemies, bullets
and pickups from a dozen images switches all the time (the engine's
[draw batching](../batching.odin) regroups what it safely can; its notes
measured 5000 sprites over 4 textures about 11x slower than over one).

An **atlas** packs many images into one big texture (a *page*). The engine
builds atlases **on export** from the textures you tick:

1. Select a texture in Assets; in the preview's **Import** row tick
   **Atlas** (saved in its [import settings](import_settings.md) file).
2. Export (**Export .ore** in the toolbar, or **Project > Export**). The log
   says how many textures were packed into how many pages.

Nothing changes in the project or the editor: scenes, scripts and
animations keep naming `textures/enemy.png`; the exported game finds it
on the atlas page by itself.

## What to atlas

| Good | Leave out |
|---|---|
| Sprites, sprite sheets, frame animations, nine-slice UI panels, tile sets, small parallax layers | Textures with **Mipmaps** or **Trilinear** (skipped automatically - mipmaps would blend neighbours on the page) |
| Many small images used together (one level's enemies) | Images bigger than a page (2048 px; skipped, they stay their own texture) |
| | Textures a **shader** samples as a whole (a material's texture parameters always get their own copy, so this is safe - just not batched) |

Atlased textures are grouped by **filter**: Point and Bilinear textures go
to separate pages, so pixel art stays crisp.

## How it works

- **Export.** The ticked textures (of the files the export preset
  includes) are packed with MaxRects (best short side fit, biggest first)
  into pages up to 2048 x 2048, each 2 px from its neighbours with its edge
  pixels repeated into the gap - no colour bleeding from neighbours when
  sprites are scaled, rotated or filtered. The package gets
  `atlas/page_<n>.png` and `atlas/atlas.json`:

  ```json
  {"pages": [{"file": "atlas/page_0.png", "filter": "point"}],
   "sprites": {
     "textures/enemy.png": {"page": 0, "rect": [2, 2, 64, 48]}
   }}
  ```

  The original files stay in the package too (LDtk levels, particles and
  shaders read images directly).
- **Runtime.** When the game loads from a package with an atlas, loading
  `textures/enemy.png` gives the page and the image's rectangle on it. A
  page loads with the first sprite using it and unloads with the last.
  Sprites, animated sprites (sheets and frame lists), frame animations,
  nine-slice, parallax and tile maps draw from the rectangle.
- **Batching.** The draw batching groups sprites by GPU texture - sprites
  on one page now group together.

## For engine code

If you write a node that draws a `^Texture`, use the helpers so it works
with atlased textures:

```odin
size := Texture_Size(tex)                     // the image's size (not the page's)
src  := Texture_Src(tex, {0, 0, size.x, size.y}) // a rectangle in the image -> in the GPU texture
rl.DrawTexturePro(tex.texture, src, dest, origin, rotation, tint)
// Texture_Full(tex): the whole image as a source rectangle
// ResourceManager_LoadTextureOwn(rm, path): a texture of its own (for shaders)
```

## Verifying

Running the demo project loose and from an atlased package (every texture
ticked: 29 images on 3 pages) gives identical frames for its startup
scene; in the asteroids scene one scanline of one scaled-down sprite picks
the neighbouring texel row (with Point filtering, page coordinates round
slightly differently) - invisible in practice.

## Limits

- Atlases exist only in exported games (the editor and Play use the
  project's files).
- Particles drawing a raw texture don't use atlas rectangles (they load
  their own image).
