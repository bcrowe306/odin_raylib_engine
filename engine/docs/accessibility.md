# Accessibility

Settings that let more people play your game. Each player has their own,
applied at once and saved for them; you choose the defaults.

| Setting | What it does |
|---|---|
| **UI scale** (0.5-3) | Every top-level UI element (a UI node whose parent isn't UI) grows around the corner, edge or centre of the screen it's nearest to: a health bar in the top-left corner grows from that corner, a button at the bottom right grows up and left, a centred menu grows from its centre. Clicks land where things are drawn. |
| **Colour filter** | Protanopia (red), Deuteranopia (green) or Tritanopia (blue): the picture is **corrected** on its way to the screen so colours that would look alike are told apart (daltonization). **Strength** 0-1. **Simulate** shows how it looks *with* the deficiency instead - for testing. |
| **Subtitles** (default on) | Spoken lines on the subtitle track. |
| **Sound captions** (default off) | Sounds' captions on the subtitle track: "[door creaks]". |
| **Subtitle size**, **backdrop** | Text size (0.5-3) and the box behind it (opacity). |
| **Screen shake** (0-2) | Scales every camera shake and trauma - 0 turns it off (motion sensitivity). |
| **Controls** | Rebinding: see [input_rebinding.md](input_rebinding.md) and the Controls Menu template. |

## For players: an options menu

Add a **UI Container** (vertical) to your options screen, **New Script**,
pick **Accessibility Menu**. It builds a row per setting - sliders, check
boxes and a button that cycles the colour filter - applies each change at
once and saves when the menu goes away (or with its Save button). Reset to
defaults puts back yours.

## Your defaults

**Project Settings > Project > Accessibility**: what every player starts
with (saved in project.json as `"accessibility"`; only what differs from
the engine's). Players' own settings are saved in `accessibility.json`
next to their save files and loaded when the game starts.

## Previewing colour vision in the editor

**View > Colour Vision: Protanopia / Deuteranopia / Tritanopia** shows the
viewport as players with that deficiency see it (simulated). Use it to
check that important things - team colours, health / danger, puzzle
pieces - don't rely on red vs green alone. Choose it again to turn it off.

## Subtitles

The subtitle track shows lines at the bottom centre over everything (up to
three; the oldest gives way), each for a time.

**From dialogue.** A **Dialogue** node's **Mode**: **Box** (the dialogue
box) or **Subtitles** - its lines go on the track instead, each for its
voice's length (else its reading time: 0.8 s + 15 characters a second),
then the next follows by itself; the advance action skips. Lines can name
a voice:

```lua
local vo = Scene.find_node("Cutscene")   -- a Dialogue node, Mode: Subtitles
vo:dialogue_show({
    { speaker = "Ada", text = "The storm's coming.", voice = "audio/vo/ada_01.wav" },
    { speaker = "Rex", text = "Then we run.",        voice = "audio/vo/rex_01.wav" },
})
vo:connect("finished", function() Scene.change_scene("scenes/level2.scene.json") end)
```

In Box mode the voice plays too. With the player's subtitles off, the
lines still play and time out (events too) - just unseen.

**Captions on sounds.** A **Sound** or **Music** node's **Caption** shows
when it plays, for players with captions on: `[explosion]`,
`[footsteps behind you]`, `[tense music]`.

**From scripts.**

```lua
Subtitles.show("Over here!", { speaker = "Ada" })                -- spoken
Subtitles.show("[alarm blaring]", { caption = true, duration = 4 })  -- a caption
local id = Subtitles.show("...")
Subtitles.hide(id)
Subtitles.clear()
if Subtitles.count() == 0 then self:next_bark() end
```

## Scripting the settings

```lua
Accessibility.get("ui_scale")                 -- 1
Accessibility.set("colorblind", "deuteranopia")
Accessibility.set("screen_shake", 0)
for k, v in pairs(Accessibility.get_all()) do print(k, v) end
Accessibility.save()                          -- for the player
Accessibility.reset()                         -- your defaults (save to keep)
```

Keys: `ui_scale`, `colorblind` ("none", "protanopia", "deuteranopia",
"tritanopia"), `colorblind_strength`, `colorblind_simulate`, `subtitles`,
`captions`, `subtitle_scale`, `subtitle_background`, `screen_shake`.

## Tutorial: an accessible options screen

1. Make an **Options** scene with a **UI Container** (vertical, 440 wide)
   in the middle; add the **Accessibility Menu** script.
2. Open it from your pause menu: `Scene.change_scene("scenes/options.scene.json")`.
3. Give important sounds captions (Sound node > **Caption**).
4. Put cutscene voice-over in a Dialogue node with **Mode** Subtitles.
5. Check your levels with **View > Colour Vision**.

## How it works / performance

- **UI scale** applies a transform when each UI node draws (no extra
  render pass) and converts the mouse into that element's space when it
  handles input (UI_GetMousePos) - widgets keep their own coordinates.
- **Colour filter**: one fragment shader on the final frame as it is
  drawn to the window (after post effects); free when off. The same maths
  runs on the CPU in `Colorblind_Apply` (tests).
- **Subtitles** are drawn after the scene's layers in the game window
  (Play and exported games); they count down in real time, so a paused
  game keeps their pace.
- **Screen shake** is scaled where the camera builds its view, so the
  basic camera's shakes and the advanced camera's trauma both follow it.

## Limits

- UI scale doesn't move elements apart: a large scale can make elements
  near each other in the middle of the screen overlap - lay menus out in
  containers.
- An open dropdown list follows its dropdown's scale; clicks on it from
  elements of another top-level UI group aren't converted.
- The editor's Simulate doesn't draw the subtitle track (Play does).
