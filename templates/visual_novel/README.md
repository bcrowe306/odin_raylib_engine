# Visual Novel

A short branching story on the road to an old castle: Ada, Theo and a lost
robot. A choice early on decides whether the gate opens, and the story
has three endings. Write your own story in `scripts/story.lua`.

| Play | |
|---|---|
| Next line | Space, Enter, a click, gamepad A |
| Pick a choice | Up / down (W / S, D-pad) and Space, or click it |
| Auto | A, or the **Auto** button: lines go on by themselves |
| Skip | Hold Ctrl (gamepad R1), or the **Skip** button: passes lines you've read, stops at new ones and at choices |
| Backlog | L, the mouse wheel up, or **Log**: the lines so far (scroll with the wheel or up / down) |
| Save / Load | The **Save** and **Load** buttons: three slots. F5 / F9: quick save / quick load. The game also autosaves at every line (**Continue** on the title screen) |
| Close a panel | Esc |

## What's where

| | |
|---|---|
| `scenes/title.scene.json` | The title screen: New game, Continue, Load, Settings (text speed, auto delay, music and sound volume) |
| `scenes/story.scene.json` | The background, three character places (SlotLeft / SlotCenter / SlotRight), the Dialogue box, the buttons under it, the backlog and the save slots |
| `scripts/story.lua` | **The story**: the characters and the chapters. Its top comment lists every kind of step |
| `scripts/vn.lua` | Plays the story: lines, choices, flags, the stage, auto / skip, the backlog, saving and loading |
| `scripts/slots.lua` | The save / load panel (both scenes) |
| `scripts/title.lua` | The title screen and its settings |
| `textures/` | Kenney's Toon Characters and Background Elements (CC0) |

## Make it yours

- **Write the story**: chapters in `story.lua` are lists of steps:
  `"narration"`, `{ "ada", "A line." }`, `{ bg = "forest" }`,
  `{ show = "theo", at = "right", pose = "cheer" }`, `{ choice = ...,
  options = ... }`, `{ jump = "chapter", when = "flag" }`,
  `{ the_end = "Name" }`.
- **New characters**: add them to `characters` and put their pictures in
  `textures/` as `<key>_<pose>.png` (idle, talk, think, cheer, hurt, or
  any poses you name).
- **New backgrounds**: `textures/bg_<name>.png`, 1024 x 576 (shown at
  1280 x 720). `bg_desert.png` is there but not used yet: try it.
- **Choices that remember**: an option's `set = "flag"` sets a flag, and a
  later `need = "flag"` (an option) or `when = "flag"` (a jump) checks it.
- **The look**: the Dialogue box's colours, font and reveal speed are in the
  Inspector; its **Choice Color** fills the selected choice.
- **Endings**: the title screen counts the endings found (`title.lua`
  says out of how many).
