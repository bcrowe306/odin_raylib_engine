# Odin Raylib Engine - Game Editor

A standalone GUI game engine editor built in Odin with **Dear ImGui** (docking branch) and **Raylib**.

---

## 1. Architecture Overview

The editor is organized as an independent package (`editor/`) that imports and manipulates the core engine (`engine/`) as a library:

- **Standalone Package**: Resides in `editor/` with independent state, assets, and bindings.
- **Dear ImGui Docking**: Full multi-window dockspace via `imgui.DockSpaceOverViewport` and docking layout persistence (`imgui.ini`).
- **Embedded Raylib Viewport**: Raylib offscreen rendering via `rl.RenderTexture2D` embedded into Dear ImGui via `imgui.Image` with inverted UVs (`{0, 1}` to `{1, 0}`).
- **Two-Way Data Serialization**: Projects and scenes load from and serialize to portable JSON (`.scene.json`, `.project.json`) and portable binary packages (`.ore`).
- **Live Scripting Integration**: Automatic reflection of Lua script properties on nodes with interactive editing.

---

## 2. Editor Layout

```
+-----------------------------------------------------------------------------------------+
|                                    Top Toolbar                                          |
|  [Q] Select  [W] Move  [E] Rotate  [R] Scale  [T] Pan  |  ▶ Play  ⏸ Pause  ■ Stop      |
|  Grid Snap [32px]  Angle Snap [15°]  Show Grid  Draw Bounds  |  New  Save  Export .ore   |
+-------------------+-------------------------------------------------+-------------------+
|   Left Sidebar    |                 Center Viewport                 |   Right Sidebar   |
|   Asset Browser   |  [Scene Viewport]  [Component / Prefab Viewport]|  Scene Hierarchy  |
|                   |                                                 |  - RootNode       |
|  📁 scenes/       |  - Interactive 2D Offscreen Canvas              |    ├── Platform   |
|    🎬 main.scene  |  - Adaptive Background Grid & Origin Axes       |    └── Drone      |
|  📁 scripts/      |  - Selection Bounding Box                       |  ---------------- |
|    📜 drone.lua   |  - Transform Gizmos (Translate, Rotate, Scale)  |     Inspector     |
|  📁 components/   |  - Cursor-Centered Smooth Zoom (0.1x - 10.0x)   |  - Transform      |
|  ---------------- |  - Pan via Middle Click or [T] Tool Mode        |  - Lua Properties |
|  Reusable Prefabs |  - Node Picking via Left Click                  |  - Save Prefab    |
+-------------------+-------------------------------------------------+-------------------+
|                                    Bottom Panel                                         |
|  [Console]        [Scene JSON Output]        [Tilemap Editor]        [Animation]        |
|  - Log filters    - Live JSON preview        - 16/32/64px tiles      - Timeline scrubber|
|  - Auto-scroll    - Clipboard export         - Paint/Erase/Fill      - Keyframe tracks  |
+-----------------------------------------------------------------------------------------+
|                                  Bottom Status Bar                                      |
|  Project: demo  |  Scene: main  |  Selected: Drone  |  Cursor: (120, 45)  |  60 FPS     |
+-----------------------------------------------------------------------------------------+
```

---

## 3. Tools & Shortcuts

Every command lives in one action table (`actions.odin`) that drives the
keyboard, the menus, the **command palette** (Cmd+Shift+P or F1) and
**Help > Keyboard Shortcuts** (Cmd+Shift+K), so any shortcut shown is the one
that works. On macOS "Cmd" is the Command key; elsewhere it is Ctrl.

| Shortcut | Action |
| :--- | :--- |
| **Cmd+Shift+P / F1** | Command palette (any action, fuzzy search, recent first) |
| **Cmd+P** | Go to file (scenes, scripts, components, assets; `>` for commands, `:` for a line) |
| **Q / W / E / R / T** | Select / Move / Rotate / Scale / Pan tool (gizmos work in world space and snap to the grid) |
| **Middle mouse / wheel** | Pan / zoom around the cursor (Cmd+= / Cmd+- / Cmd+0 too) |
| **F** | Frame the selection |
| **Alt + drag the move handle** | Move the pivot (what the node shows stays in place) |
| **Cmd+L / Cmd+Shift+H** | Lock in viewport / hide in editor |
| **Cmd+Shift+R** | Rulers & guides (drag from a ruler to add a guide) |
| **Cmd+A** | Add Node (under the selected node) |
| **Cmd/Shift+click, drag a box** | Multi-select (tree and viewport); the gizmo moves the whole selection |
| **Cmd+C / X / V, Cmd+D, Del** | Copy / cut / paste / duplicate / delete the selection |
| **Arrows (Shift: grid step)** | Nudge the selection |
| **F2** | Rename the selected node |
| **Cmd+Shift+A, Esc** | Select all / deselect |
| **Edit > Align** | Align edges or centres, distribute |
| **Cmd+Z / Cmd+Shift+Z** | Undo / redo (every edit) |
| **Cmd+S / Cmd+Shift+S** | Save scene / save all scenes and scripts |
| **Cmd+N** | New scene (added to the project) |
| **F5 / F6 / F7 / Shift+F5** | Play project / play the current scene / simulate in editor / stop |
| **F9 / Shift+F9 / Cmd+Shift+F5** | Pause or resume the game / step one frame / restart it |
| **Cmd+1 / Cmd+2 / Cmd+J** | Focus Viewport / Code / Console |
| **Cmd+Q** | Quit (asks about unsaved scenes and scripts) |

Scene tree: drag a node onto another to re-parent it (onto empty space = root), onto the top / bottom edge of a row to place it before / after; right-click for actions (Copy / Move to Scene puts the selection into another scene at the same world position - pasting into another scene does that too).
Filter the tree by name, `#tag` or `t:type` (`t:sprite`, `type:CameraNode`); terms combine.
Tags (groups) are edited in the Inspector's **Tags** section (type one and press Enter, or pick one used in the scene; click a tag to remove it); scripts use `has_tag` / `Scene.find_by_tag`, and the generated Lua types list the project's tags (`NodeTag`).
Assets: drag textures, audio, components or scripts into the viewport.

### Welcome and new projects

The **Welcome** window opens at startup (untick *Show at startup* to stop
it; **Help > Welcome** brings it back): recent projects, **Open
Project...**, a few first steps, and **New Project** from a template -
**Empty** (a camera), **Platformer** (a player that runs and jumps with the
built-in character controller, ground, one-way platforms, a following
camera), **Top-down** (a player moved by a short Lua script with the
`move_*` actions) or **Menu** (a title screen whose Play button opens the
game scene). Templates come with placeholder images, so they play right
away. Every node type has its own icon (Add Node, scene tree, Inspector),
and empty places say what to do (an empty scene in the tree and viewport,
the console).

### Workspaces

The bottom panel (Console, Game, Animation, ...) starts 100 px tall in
the Default layout - drag its edge, or pick a workspace with a taller one.
**View > Workspaces** switches the panel layout: **Default**, **Level
Design** (a larger viewport), **Scripting** (the Code tab in the middle,
in front), **Animation** (a tall bottom panel on the Animation tab) - or a
layout of your own: arrange the panels, **Save Workspace As...**, and pick
it from the same menu later (saved in `~/.config/ore_editor/workspaces/`;
**Delete Workspace** removes one). **Reset Layout** returns to Default.

The bottom panel **follows the selection**: selecting an AnimationPlayer
shows the Animation tab, a particle emitter Particles, an LDtk level LDtk;
selecting something else goes back to the tab you had (a tab you pick by
hand stays). Turn it off in Settings > General > Basic (**Bottom Panel
Follows Selection**; `auto_bottom_panel` in settings.ini).

A docked window alone in its space hides its tab (the panels have their own
headers), so after closing a window docked next to another, the one left
loses its tab. **View > Show Tab Bars** gives every docked window its tab
(to see what is docked where, drag a window out or re-dock it); turn it off
for the clean look again. Saved in settings.ini (`show_tab_bars`).

### File menu

New Scene / Script / Project, **Open Project** (recent projects and a
folder browser; the editor reopens on the chosen project after asking about
unsaved work), **Open File** (Cmd+P), **Save** (Cmd+S: the focused script or
the scene), **Save As** (Cmd+Shift+S: scene, script, or a component as a new
component), **Save All** (Cmd+Alt+S), **Revert**, **Export** (.ore package /
standalone game), **Settings** (Cmd+,) and Quit.

### Settings (Cmd+,)

- **General** — Basic: UI scale, grid size and snapping, autosave, quit
  confirmation. Keymap: every command with its shortcuts; record a new one,
  clear it or reset it (conflicts are flagged). **Theme**: the presets
  Default, Dark, Mid-day and Light, and every colour of the current theme
  (backgrounds, text, accent, status colours, code background) - changes
  preview live; Save keeps them, Cancel goes back.
- **Code Editor** — font size, tab width, spaces vs tabs, auto-closing
  brackets, format on save, the language server and its path.
- **Project** — General (name, version, startup scene, icon, physics -
  gravity and **Show Colliders**: whether the running game draws collision
  shapes, joints and areas, on by default; the viewport always can - scenes),
  **Input** (named actions and their key/mouse/gamepad bindings — scripts
  call `Input.is_action_down("jump")`), **Video** (window, virtual
  resolution, FPS, fullscreen, vsync, resizable, MSAA, high-DPI), **Audio**
  (master, music and sound-effect volumes) and **Export** (executable name,
  output folder, targets, compression, font, which prebuilt runners exist).

Editor settings are per user, in `~/.config/ore_editor/settings.ini` -
`[general]`, `[code]`, `[theme]`, `[paths]`, `[recent_projects]` and `[keymap]`
sections (an older `settings.json` is read once and replaced); project
settings live in the project's `project.json`.

The editor remembers folders in `[paths]`: where assets were last imported
from (`import`), where the last `.ore` package or standalone game was
exported (`export`) and where projects were last opened or created
(`projects`). The next import, export, Output Folder **Browse...**, Open
Project and the Welcome window's Location start there (a folder that no
longer exists falls back to the default). **File > Export > .ore Package**
asks for the folder to write `<project>.ore` into.

Scenes and components are listed without their `.scene.json` /
`.component.json` endings (Assets, scene tree, toolbar, status bar).

### Inspector

X/Y fields have a link toggle (linked: changing one scales the other by
the same ratio). Every field has a reset button when its value differs from
the default (the node type's default, a script property's declared default).
Particle emitters open the **Particles** tab (bottom panel): Emission, Shape,
Motion, Size & Rotation, Color (gradient over the particle's life with
draggable stops, plus a red/green/blue/alpha plot whose alpha points you
drag) and Collision, with a live preview in the viewport.

With several nodes selected, the Inspector shows the primary one under a
"N nodes selected" banner and only the properties they all have; values
that differ show **—**, and an edit (or reset) applies to every selected
node - for X/Y pairs only the axis you changed, so differing positions keep
their other coordinate. Enable / visible toggles apply to all; the other
sections (script, material, signals) edit the primary node.

Hover any property (its label or field) for help: a tooltip with what it
does, its type, range and default, and its script path. The **help pane**
at the bottom of the Inspector keeps the last hovered property's help, or
describes the selected node type; its `path = "..."` line is what
`get_property` / `set_property` take (the copy button copies it) - a
script's exported properties are `script.<name>`. **View > Inspector Help**
hides it.

**Drag a node from the Scene tree into a script** to insert a reference to
it, typed for the language server (its class, so its own methods
complete). On an empty line it becomes a declaration:

```lua
---@type CharacterMoverNode
local player = self.node:get_node("../Player")
```

Dropped into an assignment (`self.body = `) the `---@type` line goes above
it; anywhere else (an argument) it gets an inline cast,
`self.node:get_node("../Player") --[[@as CharacterMoverNode]]`. Plain
`Node`s get no annotation.

**Drag a property's name into a script** (the Code tab) to insert a read:
`self.node:get_property("rotation")`. Hold **Shift** when dropping for a
write with the current value: `self.node:set_property("rotation", 45)`.
The node is `self.node` when it runs that script, `self.node:get_node(
"<relative path>")` for another node of the scene (or `Scene.find_node`). The help text lives in
`engine/property_docs.odin` (`test_property_docs` fails when a property has
none).

### Context menus

Every asset, folder, scene-tree node, code tab, the code text and console
lines have a right-click menu with all their actions — for nodes: add child
or component, cut/copy/paste/paste as child, duplicate, rename, delete, move
up/down/to root, select children, enable/show, frame, script actions and
component actions; for assets: open/add/use on the selection, copy/paste,
duplicate, rename, delete, copy path, reveal. LDtk projects (`.ldtk`) are
listed under **Levels** (double-click or drag to add a level).

### Asset folders, grid and usages

The buttons left of **+** switch Assets between the by-type sections and the
project's real **folders** (a tree, the project folder at the top), and
between a list and a **grid** of thumbnails. In the folders view, drag an
asset or folder onto a folder to move it; right-click a folder for **New
Folder**, **Rename**, **Find Usages**, **Delete** (with what it contains)
and **Paste Here**. Moving or renaming updates every reference - in scenes
and components (also the ones open with unsaved edits, and their undo
history), scripts and `project.json` (startup scene, scene list, icon,
import settings); open scripts that move are reopened. **Find Usages** (on
any asset's menu) lists the files that reference it; double-click one to
open it.

**Import settings** for a texture are in the preview panel's Texture tab:
**Filter** (Point keeps pixel art crisp; Bilinear / Trilinear smooth
scaled images), **Wrap** (Repeat / Clamp) and **Mipmaps**. They're saved in
`project.json` (`texture_import`), applied at once in the editor and when
the game loads the texture.

### Importing assets

The **+** at the top right of Assets imports with the system file dialog
(**Import Assets...**, multi-select, or **Import Folder...**) and creates
scenes and scripts; each folder's right-click menu has an Import item
filtered to its file types. Files and folders dragged in from Finder /
Explorer import too — onto the viewport, they are also added to the scene
where they land.

Each file goes to the folder for its type — `textures/` (png, jpg, bmp,
tga), `audio/` (wav, ogg, mp3), `scripts/` (lua), `scenes/`,
`components/`, `levels/` (ldtk) — and a folder keeps its layout below that
(`Pack/Effects/spark.png` -> `textures/Pack/Effects/spark.png`). Contents
are checked (images must decode, audio must have a WAV/Ogg/MP3 header,
JSON must parse), so an unsupported or broken file fails on its own and the
rest still import; failures are listed in the **Import Results** window and
the console. A file already in the project (same contents) is skipped; a
different file with a taken name is imported as `name_2.ext`. An LDtk
project brings its external levels and the tileset/background images it
references (into `textures/`, with the paths in the level rewritten).

### Viewport

**Fit** (Home) zooms to the whole scene; the zoom menu also has Fit Game
View (Shift+Home: the camera's frame at the project resolution), Fit
Selection (Shift+F) and fixed zoom levels.

**Rulers & guides** (View, Cmd+Shift+R): rulers along the top and left edge
show world coordinates and the mouse position. Drag from the left ruler for
a vertical guide, from the top one for a horizontal guide; drag a guide to
move it, back onto a ruler to remove it (View > Clear Guides removes all).
Guides are saved with the scene and ignored by the game.

**Smart snapping** (View, on by default): a moved selection's edges and
centre snap to other nodes' edges / centres and to guides within a few
pixels (a magenta line shows the match); otherwise grid snapping applies.

**Pivot**: Alt + drag the move handle moves the node's pivot without moving
what it shows - a sprite's or animation's origin, its children, a line's
points and collision shapes stay where they are (it snaps to the node's own
edges and centre).

**Lock / hide**: Edit > Lock in Viewport (Cmd+L) makes a node and its
children unpickable and unmovable in the viewport (still editable in the
tree and Inspector); Hide in Editor (Cmd+Shift+H) hides them in the
viewport only - the game still shows them. Both are on the scene tree's
right-click menu and shown as icons on the row (click to clear), and saved
with the scene.

**Show All Colliders** (View) draws every collision shape even when the
project turns physics debug drawing off.

### Signals

The Inspector's **Signals** section lists every event of the selected node
(`timeout`, `body_entered`, `clicked`, ...). **+** connects one to a method on
any node's script (a new script is created and attached if the target has
none): the handler is written into the script, and the connection is saved
on the node and called at runtime as `Target:method(value, source)`. The
link button disconnects and removes the generated handler (asking first if
you added code to it). See `engine/SCRIPTING.md`.

### Sprite Sheet Slicer

**Tools > Sprite Sheet Slicer...** (also a texture's right-click menu and the
AnimationPlayer Inspector) cuts a sheet into cells: **Columns** / **Rows**
or a **Cell Size**, **Margin** and **Spacing**. Click cells to pick them
(drag across to add several, Shift+click for a range; the numbers are the
play order), name the animation and **Add Animation**, or **One Animation
per Row**. **Create Animation Player** adds a new node with the animations
at the chosen FPS - or **Add to <name>** when an AnimationPlayer is
selected. The selection previews as it plays. Animations keep the picked
cells (`"cells"` in the scene; margin / spacing editable in the Inspector).
Zoom the sheet with **-** / **+**, the zoom field, **Fit** (the whole sheet,
the default) or **1:1**, or Cmd+wheel (Ctrl+wheel) around the mouse; the
wheel scrolls (Shift: sideways) and middle-drag pans when zoomed in.

### Animation timeline

The bottom panel's **Animation** tab edits the selected AnimationPlayer's
animations; the Inspector shows only the player's own settings - Current,
**Default** (`defaultAnimation`), **FPS** (`fps`), Preview, Reverse,
Autoplay - with their script paths. Next to the animation picker: **+** adds
an empty animation, its **▾** makes one from a folder of frames or a sprite
sheet (or opens the slicer), the **pen** renames
it (names are unique; the default animation and the states of a State
Machine driving this player follow the new name), **Duplicate** copies it
(frames, range, settings and tracks) right after itself as `<name>_copy`,
and the **trash** deletes it (Cmd+Z brings it back).

**Frames**: the strip shows every frame of the animation; the ones it plays
(its **range**) are under the blue band in the header - drag the band's
handles, type **from / to** under the Frames label, or right-click a frame:
*Start / End the Range Here*; frames outside it are dimmed. Click frames to
select them (Shift: a run, Cmd: add / remove), then **Copy**, **Paste**
(after the selection, else at the end) or **Delete** with the buttons left
of the header, the right-click menu, or Cmd+C / Cmd+V / Delete while the
panel has focus (they act on frames there, not on scene nodes). Images
paste into frame animations, sprite-sheet cells into animations of the same
sheet. Drag frames to reorder; drop textures on **+** to add some. The
toolbar: **Loop**, **Reverse** (this animation plays last to first; the
player's own Reverse flips them all), the animation's **FPS** (the rate it plays at -
the player's, dimmed, until you change it; right-click goes back to the
player's, set in the Inspector) and the **star**: the animation selected -
and autoplayed - when the scene loads (also the Inspector's **Default**).
At the right of the timeline (when the panel is wide enough) a **preview**
plays the animation by itself - its range, FPS and direction, looping;
pause it to see the frame the timeline is on. Then play/stop preview in the
viewport (Stop puts the scene back), and
keyframed **property tracks**: **Add Track** picks the player or a child and
a property (position, rotation, scale, colours, any numeric property); the
yellow dot keys the current value at the playhead; right-click a key to
delete it.
Right-click a key for its **Easing** to the next key (linear, sine, quad,
cubic, quart, expo, back, elastic, bounce, constant; hover one to see its
curve) or to delete it. Eased keys show a dot. Scripts can animate any
property at runtime with `Tween.to` (see `engine/SCRIPTING.md`).
**Add Track > Events** adds a **Call Script Methods** track (the key's
method runs on the target's script on that frame; type the name in the key
field) or a **Play Sounds** track (pick an audio file per key). Event keys
are drawn as squares (methods) or circles (sounds); hover one for its method or sound. Scripts
crossfade between animations with `node:animation_play(name, blend)`.

### State machines

Add a **State Machine** (Animation & Effects) next to an AnimationPlayer.
The Inspector edits its **Player** (Auto finds a sibling or child),
**Initial State** and **Autostart**; **States** (name + the animation it
plays; **From Animations** adds one per animation); **Parameters** (name
and starting value); and **Transitions** (from / any state -> to, crossfade
**blend**, and conditions: parameter compared with a value, trigger,
animation finished, after N seconds). While simulating, the current state
is marked with a play icon. Scripts: `sm_set`, `sm_trigger`, `sm_travel`,
`on_enter_<state>` / `on_exit_<state>` (see `engine/SCRIPTING.md`).

### Materials & shaders

Every drawable node has a **Material** section (collapsed until used): a
shader - built-in Flash, Outline, Dissolve, Grayscale, Wave, or a project
`.fs` file - a blend mode (alpha, additive, multiply, ...) and the shader's
parameters, generated from its `uniform`s (sliders, colour pickers, texture
pickers; the reset arrow returns one to the shader's default). **New
Shader...** (here or Assets **+**) writes a documented template; drop a
shader from Assets on a node to apply it; saving a shader reloads it in the
viewport. Lua: `node:set_shader`, `set_shader_param`, `set_blend_mode`.

### Lighting

Add a **Light** (point or spot cone; colour, energy, radius, falloff,
shadows) and darken the scene with **Ambient** - the Inspector shows the
Scene settings when nothing is selected (presets: Dusk, Night, Dark). Lights
cast shadows from physics shapes. The toolbar's sun toggles the lighting
preview in the viewport; selected lights show their radius or cone.

### Save data

Scripts persist progress with the `Save` module (`Save.set`, `Save.get`,
`Save.flush`; see `engine/SCRIPTING.md`), stored as JSON in the platform
user-data folder under the project's name. **Game > Save Data > Open
Folder** shows it; **Delete Save Files** removes them so the next run
starts fresh.

### Text & dialogue

**Text** (Graphics & Rendering) places text in the scene: pick a project
font in the **Font** section (`.ttf`, `.otf`, `.fnt`; none = the engine
font), size, colour, wrapping width, alignment, rich text, localization
key, SDF and typewriter speed. **Dialogue Box** (UI) is a box scripts fill
with lines (`dialogue_show`). Localization tables are `locale/*.csv`; the
starting language is set in Project Settings > General.

### Visual extras

**Nine Slice Sprite**, **Parallax Background**, **Line** and **Post Effect**
(Graphics & Rendering) and **Trail** (Animation & Effects) nodes. A Line's
points are edited in the Inspector's **Points** section (**Add Point**, the
x removes one). Post effects show in the viewport while the lighting
preview (toolbar) is on; pick the shader in the **Material** section.

### Physics: joints, one-way, layers

Add a **Joint** (Physics & Collision) and pick **Body A** / **Body B** in
the Inspector (static, dynamic or character bodies; A defaults to the
parent); choose its **Type** - only that type's parameters are shown. The
viewport draws a line between the anchors. A StaticBody's **One Way** makes
a jump-through platform. **Project Settings > Physics > Collision Layers**
names the 16 layers; shapes' layer lists show the names.

### Camera follow

Select a Camera and pick its **Follow Target** in the Inspector (or drop a
node from the Scene panel on the field, or right-click any node: *Camera
Follows This*). It is saved with the scene as a path relative to the camera
(`"follow": "../Player"`), so the game follows that node with no script -
including a node that only appears later (e.g. spawned from an LDtk level).
The camera's own offset, smoothing, look-ahead, margins and limits apply.
Lua: `Camera.set_target(node)`, and for groups `Camera.add_target(node,
{weight, radius})` / `remove_target` / `clear_targets`.

### Collision shapes

Physics bodies (Static, Dynamic, Area, CharacterMover) list their shapes in
the Inspector (**Collision Shapes**: type, size, material, filtering).
**Edit Shapes** - the button at the top left of the viewport, or *Edit in
Viewport* in the Inspector - replaces the transform gizmo with handles on
the selected body's shapes:

- the centre moves a shape, the orange knob rotates it;
- box edges and corners resize it (the opposite side stays put; **Shift**
  resizes around the centre); circles and capsules have radius / length handles;
- polygon, chain and segment points drag; click a **+** between two points
  to add one, right-click a point to remove it. Polygons must be convex:
  a non-convex one turns red (it collides as its outline).

Grid snapping applies (rotation snaps to 15°); every drag is one undo step;
**Esc** leaves shape editing (a second Esc deselects). Changing a shape's
type keeps its footprint. Shapes are in the node's local units: they scale
with the node (and its parents), like everything else drawn by it.

### Tile maps

Add a **Tile Map** node, pick a tileset and tile size in the Inspector,
choose a tile in the palette and paint in the viewport (brush, eraser, flood
fill; right button erases; one undo step per stroke). Turn on `solid` for
colliders.

### LDtk levels

Import a `.ldtk` project and double-click it under **Levels** to add an
LDtk level. The **LDtk** tab of the bottom panel (Inspector: *Layers,
Entities, Collision...*) shows the selected level: pick the world and level
(or **world mode**: every level of the world at its world position),
preview parallax around the editor camera, overlay IntGrid values, and:

- **Layers** - read-only list; hide (editor only) or solo a layer, hover to
  outline it.
- **Entities** - what each entity spawns as (Auto by name, a component, a
  plain Node, nothing); **Create Component...** from its fields; the placed
  instances (click to frame).
- **Collision** - None / Solid / One-way / Trigger per IntGrid value, with
  friction and bounce.
- **Links** - rules for EntityRef fields (connect a signal to a method, or
  parent one entity to the other) and the references in the level.
- **Level Fields**, **Enums**, **World** (a mini-map: click a level to open it).

The viewport shows entity placements and reference arrows while editing;
colliders and entities are built when you Simulate or Play. See
`engine/LDTK.md`.

### Playtesting

Play always runs what is in the editor. It saves every modified scene, rebuilds the game
binary (`bin/odin_raylib_engine`) if any engine/game source changed, then starts the game with
`--project <dir>` (plus `--scene <file>` for F6). The game's output streams into the
Console. **Game → Simulate in Editor** runs the scene inside the editor and restores it when stopped.

While the game runs, the toolbar's play controls become **Pause** /
**Resume** (F9), **Step** one frame (Shift+F9; pauses first), **Restart**
(Cmd+Shift+F5: stops and plays the same thing again - the project, the same
scene, or the same exported package - saving and rebuilding first like
Play) and **Stop** (Shift+F5); next to them the game's state - Running,
Paused or Breakpoint (the status bar shows it too). While the game is
building, Stop cancels the build. The same commands are in the **Game**
menu; Restart there also replays the last run after it was stopped. The
**Show Colliders** button next to them (also Game > Show Colliders in Game)
switches whether the game draws collision shapes, joints and areas - the
project setting, saved in project.json, and at once in a running game.

**Debugging Lua**: click a line number in the Code tab to set a breakpoint
(a red dot; click again to remove it) and Play. When a script reaches it,
the game pauses there: the script opens at the line (marked), and the Game
tab shows the call stack (click a frame for its locals) and the locals -
tables one level deep, nodes as `Type(Name)`. **Continue** (F8), **Step
Over** (F10), **Step Into** (F11), **Step Out** (Shift+F11). Breakpoints can
be added or removed while the game runs. (Debugging works in the game
started with Play, not in Simulate in Editor.)

While the game runs, the bottom panel's **Game** tab is linked to it
(`--editor-link`): the running game's scene tree (refreshed twice a
second), the selected node's live properties - type a value and press Enter
to change it in the game - and **Pause** / **Resume** / **Step** (one frame
of 1/60 s; paused, the game is still drawn). Saving a scene while the game
runs reloads it there (the current scene restarts with the saved version);
edited scripts and images reload by themselves, in the game and in the
editor.

### Code tab (Lua scripts)

Scripts open in a **Code** tab next to the Viewport: double-click a script in Assets, use the
edit button beside a node's script in the Inspector, *Open Script* in the scene tree's context
menu, or double-click a console message with `file.lua:LINE`. *New Script* (Inspector, or the
**+** on the Scripts folder) creates one from a template. Completion, signature help, hover,
diagnostics and go to definition (F12 / Ctrl-click) come from `lua-language-server` with the
engine API definitions (`engine/definitions`). Hover docs, signature help and the selected
completion's docs show in boxes that stay inside the Code area, wrap, and scroll with the
mouse wheel when long (move the mouse onto a hover box to scroll it). **Ctrl/Cmd+S** saves and hot-reloads the
script in a running Simulate session; Ctrl+Space completes; Ctrl/Cmd+/ comments; Ctrl/Cmd+W
closes the tab. Zed-style editing: auto-closing brackets and quotes,
find/replace (Cmd+F / Cmd+Alt+F, Cmd+G), multi-cursor (Cmd+D, Cmd+Shift+L,
Cmd+Alt+Up/Down, Alt+click), line operations (Opt+Up/Down, Cmd+Shift+D/K,
Cmd+Enter, Cmd+/, Cmd+]/[), go to line (Ctrl+G), rename (F2), format
(Cmd+Shift+I), references (Shift+F12) and snippet tab stops. Drag an asset
onto the code to insert its path, or hold Cmd to add it as an exported asset
property. Text editing uses the `odin_editor` packages (`buffer`, `syntax`, `lsp`); see
`code_editor.odin` and `code_editor_lsp.odin`.

**Lua tooling files.** The editor writes the engine API definitions to
`<project>/.ore/definitions/` (compiled into the editor, refreshed when it
updates) and a `.luarc.json` pointing at them, so lua-language-server - in
the Code tab or in VS Code / any LuaLS editor opening the project folder -
knows every engine type. A hand-written `.luarc.json` is left alone. Hidden
files and folders (`.ore/`, `.luarc.json`, ...) are never packaged into
games. The language server is looked up next to the editor, then in the
engine checkout (or set its path in Settings > Code Editor).

**Project types.** Next to the engine API the editor generates
`.ore/definitions/project_types.lua` from the project: `InputAction` (the
input actions - a misspelled action is an error and names complete inside
the quotes), `SceneName`, `NodeName`, `ScenePath`/`TexturePath`/`AudioPath`/
`ComponentPath`/`LevelPath`/`ScriptPath`, LDtk entity/level/layer/enum names,
and a class per script with its exported properties (`self.orbit_radius` is
a number). It is rewritten half a second after saves, imports, renames and
settings changes, and the language server is told.


**File > Export Standalone Game** (or Project Settings > Export > **Save and
Export**) writes, for each target platform, `<output>/<platform>/` with the
game runner renamed to the executable name, `game.ore` and the UI font: a
folder you can ship.

**Export presets** (Project Settings > Export > **Use Presets**) give each
export its own settings: platform, executable name, output folder (default
`<output>/<preset name>`), version, icon, window title / size, fullscreen,
**Include** / **Exclude** file patterns (one per line: `audio/` a folder,
`*.psd` a file name anywhere, `levels/*.ldtk` a path), and **Debug** (the
debug runner: debug info, a console on Windows). Add several per platform
(a demo, a debug build); **Save and Export This Preset** exports one, **Save
and Export All** every preset. The packaged `project.json` carries the
preset's overrides. Presets are saved in `project.json` under
`"export": {"presets": [...]}`. The runner is **prebuilt** - no compiler is needed to
export: runners are looked up in `runners/<platform>/` next to the editor
(or `bin/runners/` in a source checkout). `scripts/build_runners.sh` builds
the current platform's; run it on each platform you ship for and copy its
`runners/<platform>/` folder next to the editor. The Export page shows which
runners are ready; without one for this platform the editor builds it once
(needs `odin`). The project's **Icon** (Project > General, a PNG) becomes
the game window's icon.

**macOS** exports are an app bundle, `<output>/macos/<Name>.app`:
`Info.plist` (name, version, bundle ID - Export > macOS Bundle ID, default
`com.ore.<name>`), the runner in `Contents/MacOS`, its libraries (Lua) in
`Contents/Frameworks`, and `game.ore`, the font and `AppIcon.icns` (made
from the project icon) in `Contents/Resources`. The app is signed with
`codesign` - ad-hoc by default (runs on this Mac), or with the **Signing
Identity** you set (a Developer ID to distribute; `none` skips signing).
With a **Notary Profile** (`xcrun notarytool store-credentials`) and a
Developer ID, the app is then notarized and stapled in the background
(progress in the console). The runner is universal (arm64 + x86_64) when
`scripts/build_runners.sh` finds the x86_64 builds of raylib, Box2D and
Lua; otherwise it's built for the Mac's own architecture.

**Windows** exports are a folder with `<Name>.exe`, `lua54.dll`, `game.ore`
and the font. Release runners have no console window
(`-subsystem:windows`). The exe gets the project icon (16-256 px) and
version info (product name, description, version from Project > General) -
written with the Win32 resource API, so this happens when exporting on
Windows; exports made elsewhere keep the runner's own.

**Linux** exports are an AppDir, `<output>/linux/<Name>.AppDir` (`AppRun`,
`<Name>.desktop`, the icon, `usr/bin/` with the runner, `game.ore` and the
font); on Linux with `appimagetool` on `PATH` it's also packed into
`<Name>-<arch>.AppImage`.

The engine's open gaps and everything fixed in this pass are listed in [`engine/GAPS.md`](../engine/GAPS.md).

---

## 4. Reusable Components & Prefabs

- **Definition**: Components are reusable node subtree templates stored as JSON snippets.
- **Built-in Catalog**: Physics Dynamic Box, Static Barrier, Orbiting Drone (Lua scripted), Sensor Trigger Zone, Particle FX.
- **Custom Prefabs**: right-click a node → **Save as Component** writes the subtree to `components/<Name>.component.json` and links the node to it.
- **Instantiation**: double-click a component in Assets (or drag it into the viewport). Instances are **links**: the scene stores `"component": "<file>"` plus **overrides** — values changed on the instance or any of its children, and children added to or deleted from it — so editing the component file updates every instance except what it overrides. The Inspector lists a node's overrides with **Revert**.
- **Changing a component**: edit an instance in the scene (add or delete children, change values) and choose **Apply Changes to Component** (right-click the instance) to write it to the component file and update every instance, or **Save as New Component** to make a new one from it. You can also open the component itself (*Edit Component*) and use **Save** / **Save As** there. *Unlink* turns an instance into plain nodes.

---

## 5. Build and Run Commands

```bash
# Check editor package type-checking
task editor:check
# or: odin check editor

# Build editor binary to bin/editor
task editor:build
# or: odin build editor -out:bin/editor

# Run interactive editor
task editor
# or: odin run editor

# Run complete engine test suite
task test

# Operate the editor through injected input (see TEST_DRIVE.md)
task editor:drive
```
