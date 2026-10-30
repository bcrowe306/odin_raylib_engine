# Import settings (per asset)

Each texture and audio file can carry its own settings in a small JSON
file **next to it**: `textures/hero.png` → `textures/hero.png.import.json`.
Because the file sits beside the asset, the settings travel with it - when
you copy the asset to another project, rename or move it in the Assets
panel, commit it to version control, or export the game.

The Assets panel hides these files; you edit them in the **preview panel**
(select the asset). A file only exists when something differs from the
defaults; setting everything back deletes it.

## Textures

| Setting | |
|---|---|
| **Filter** | **Point** (default) keeps pixel art crisp; **Bilinear** / **Trilinear** smooth scaled images (Trilinear uses mipmaps). |
| **Wrap** | **Repeat** tiles past the edges (parallax, scrolling shaders); **Clamp** stretches the edge pixels. |
| **Mipmaps** | Smaller copies for drawing far below the texture's size (less shimmer when zoomed out). |
| **Export** | **Keep** stores the file as it is; **QOI** re-encodes it as QOI in the exported package - it decodes several times faster than PNG (faster loading, especially big backgrounds and tile sheets), usually a bigger file. The project keeps the PNG. |
| **Atlas** | Pack it into a sprite atlas on export - sprites on one atlas page draw in one batch. See [atlas.md](atlas.md). |
| **Slice** | A slicing preset (columns x rows, or a cell size in pixels; margin, spacing): the **Sprite Sheet Slicer** opens the sheet with it. Set it with **Save Preset** in the slicer; the x in the preview forgets it. |

Filter, wrap and mipmaps apply at once to every copy loaded in the editor
and when the game loads the texture.

Example file:

```json
{
  "filter": "bilinear",
  "mipmaps": true,
  "slice": {"grid": [8, 4], "margin": [0, 0], "spacing": [2, 2]},
  "compress": "qoi",
  "atlas": true
}
```

Sliced by cell size, the preset also has `"cell_size": [32, 32]`: cells of
exactly 32 px, as many as fit (`grid` is then what fits). Sprite-sheet
animations save it the same way, next to their `grid`; files without it
slice by the grid.

## Audio

| Setting | |
|---|---|
| **Gain** | Louder / quieter wherever it plays (-24 to +12 dB) - even out sounds recorded at different levels without touching every node. Sounds get it once when decoded; music streams through the mixer with it. |
| **Bus** | The mixer bus it plays into when the node's **Bus** is empty or a script doesn't name one (else SFX for sounds, Music for music). E.g. every UI click sound into a "UI" bus. See [audio_mixer.md](audio_mixer.md). |

```json
{"gain_db": -4.5, "bus": "UI"}
```

## Tutorial: crisp pixel art, smooth backgrounds

1. Keep sprites at **Point** (the default).
2. Select the painted background in Assets; in the preview set **Filter**
   **Bilinear** and **Mipmaps** on - it no longer shimmers when the camera
   zooms out.
3. For the same background set **Export: QOI** - the exported game loads it
   faster.

## Tutorial: a sprite sheet preset

1. Right-click `textures/hero.png` > **Slice Sprite Sheet...**
2. Set Columns 8, Rows 4, Spacing 2 x 2; press **Save Preset**.
3. Next time (or for a teammate) the slicer opens the sheet already cut.

## Tutorial: one bus for all UI sounds

1. In the **Mixer** tab add a bus **UI**.
2. Select each UI sound in Assets; set its **Bus** to UI.
3. `Audio.play_sound("audio/click.wav")` and Sound nodes with an empty Bus
   now play into UI - one fader (and an options-menu slider:
   `Audio.set_bus_volume("UI", v)`) controls them.

## From scripts

Nothing to call: the settings apply when an asset loads. A script that
names a bus (`Audio.play_sound(path, 1, 1, "SFX")`) overrides the import bus.

## Older projects

Projects from before per-asset files kept texture settings in
`project.json` (`"texture_import"`). Those still apply to textures without
a file; the first change in the preview moves a texture's entry into its
own file.

## How it works / performance

- Settings are read the first time an asset loads (one small file, or a
  lookup in the exported package) and cached per path - misses too, so a
  texture without settings costs one lookup per project load. The cache
  lives in one arena, freed as a whole when the project changes.
- Gain is applied to a sound's samples once when decoded - no cost per
  voice.
- QOI is detected by its header, so a QOI file stored under `.png` loads
  through the same paths (the background decoder too).
- Export converts on the editor's side; the game never sees the PNG.

## Vector art (SVG)

| Key | | |
|---|---|---|
| `vector_scale` | `1` | Document units to pixels for every Vector Shape drawing the file (`0.5`: art drawn at twice the needed size). Changing it reloads the file. |
| `origin` | centre | The origin (`[x, y]`, a fraction of the document box) new Vector Shapes of the file get; each node's Origin row can still change it. |

Set them in the Preview panel when the SVG is selected in Assets
([vector art](vector.md)).
