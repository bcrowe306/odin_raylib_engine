# Editor test-drives

Test-drives operate the editor the way a user does. A script moves the mouse,
clicks, drags, scrolls, presses keys and types. Each action is injected as a
real ImGui input event, and the real mouse and keyboard are ignored meanwhile.
After each step the script checks the editor's state, the files it wrote, and
the game process it launched, and it captures screenshots along the way.

```bash
./scripts/editor_drive.sh                 # every tests/drive/*.drive
./scripts/editor_drive.sh playtest nodes  # selected drives
task editor:drive                         # same as the first line
```

Each drive runs against a **fresh copy** of `assets/demo_project` in `/tmp`, so the
real project is never modified. Results go to `editor_screenshots/drive/<name>/`:
numbered screenshots plus an `index.md` report listing every check. The script
exits non-zero if any check fails.

## Suites

| Drive | Covers |
|---|---|
| `playtest.drive` | Rename and move a node, press Play: the editor saves, the game process starts, and the game's own scene dump contains the edit. Play Current Scene (F6) runs a non-initial scene. |
| `nodes.drive` | Add Node dialog (toolbar and Ctrl+A, search, Create), texture picker, reflected property edit, duplicate, delete, undo/redo, drag-and-drop re-parenting, visibility toggle, save. |
| `viewport.drive` | Click-select, move/rotate/scale gizmos with world-space grid snapping, undo of gizmo edits, pan tool, wheel zoom. |
| `scripts.drive` | Attach a Lua script from the inspector, edit an exported property, save, simulate in the editor (and restore), Play: the game runs with the edited value. |
| `project.drive` | New scene, physics bodies, unsaved edits survive scene switches, Project Settings (gravity, startup scene), simulate a falling crate, Play starts in the new scene. |
| `components.drive` | Save a subtree as a component from the context menu, instantiate it from Assets, built-in templates. |
| `export.drive` | Export `.ore`, then run the game from the package (textures load from inside it). |
| `assets.drive` | Asset folders collapse/expand (folder icons); the Scenes folder's + creates a scene. |
| `code_shortcuts.drive` | Zed-style code editing: auto-closing pairs, line operations, multi-cursor, find/replace, go to line, LSP rename and format, font size, Go to File, reopen tab, command palette, Keyboard Shortcuts window. |
| `scene_editing.drive` | Multi-select (tree, box), align, nudge, copy/paste, multi-delete, F2 rename, select all, quit prompt. |
| `signals.drive` | Connect an event to a script method (handler generated, connection saved), disconnect (handler removed; asks when it has code), drag assets into a script (path / asset property). |
| `prefab_overrides.drive` | Edit a child of a linked instance: saved as an override, other instances unaffected, Revert. |
| `animation.drive` | Animation tab: frames from dropped textures, scrubbing, rotation track with keys, preview restore, save. |
| `tilemap.drive` | Tile map: tileset, palette, paint stroke (undo/redo), flood fill, erase, save. |
| `ui_ux.drive` | Settings (keymap record, input action + key, video, export), linked X/Y and reset, Save As / Revert / Open Project, asset copy/paste/rename/delete, paste as child, LDtk level asset, instance add child + apply to component, particle editor, viewport fit. |
| `animation_player.drive` | The preview right of the timeline (playing, paused on a frame); frames deleted (button, menu, Delete key - the node stays), copied and pasted (buttons, Cmd+C / Cmd+V), the range (fields, menu), per-animation reverse and FPS (right-click: the player's FPS), the default animation, saved. |
| `anim_manage.drive` | Animations renamed (a taken name refused with a warning; the default and a state machine's state follow), duplicated (frames, range, reverse; placed after it), deleted (the copy becomes current, undo restores it), saved. |
| `slicer_zoom_tabs.drive` | Sprite slicer zoom (1:1, + / -, Cmd+wheel, a cell picked zoomed in, Fit); View > Show Tab Bars on (every docked window has its tab) and off, saved in settings.ini. |
| `game_controls.drive` | Play This Scene; toolbar Pause / Resume and Step, F9 / Shift+F9; Restart (a new process, the same scene); Stop, then Game > Restart plays it again; Game > Pause / Stop. |
| `prop_drag.drive` | The help pane's `path = "..."` (a Transform row, a script property `script.<name>`); a property name dragged into a script: get_property, Shift: set_property with the value; another node's via get_node. |
| `bottom_follow.drive` | The AnimationPlayer Inspector (player settings only, `fps` path), the Animation tab's ▾ menu (an animation from a sprite sheet); the bottom panel follows the selection and goes back, a hand-picked tab stays, the setting turns it off. |
| `game_colliders.drive` | The toolbar's Show Colliders button: saved in project.json, switched live in a running game, Game menu entry. |
| `node_drop_typed.drive` | A node dropped into a script: on an empty line a `---@type` local (indented into the function), into an assignment the annotation above it, elsewhere an inline `--[[@as Type]]` cast; undo. |
| `negative_scale.drive` | An AnimationPlayer with scale x -1 draws mirrored around its position; its bounds (selection box, picking) mirror too. |
| `origin.drive` | The Origin row (help path, presets, typed, reset to the centre, undo), none for a camera, a new AnimationPlayer centred, saved as `"pivot"`; a migrated pixel origin. |
| `hier_script.drive` | The scene tree's script marker: shown when a script is attached, opens it, gone when detached. |
| `lua_get_script.drive` | Typed get_script(): a node name that runs a script returns NodeOf_<name>; another script's fields complete through it. |
| `lua_events.drive` | Event names complete: a timer's `connect("` offers timeout, `emit("` the project's custom events, `function X:on_` the on_<event> methods. |
| `lua_properties.drive` | Typed property paths: a camera's set_property(" completes followMode; get_property returns the enum (its names complete in a comparison). |
| `lua_get_node.drive` | Typed get_node: self.node:get_node(" completes the paths in the script's scenes, each typed (EngineExhaust is a FrameAnimationNode). |
| `ui_theme.drive` | No Scene JSON tab; headers, rulers and the Welcome window; theme presets preview live, Save writes `[theme]` to settings.ini, Cancel restores the saved theme. |
| `lua_debugger.drive` | A gutter breakpoint, Play This Scene stops in the script (line, locals, stack), step over, breakpoint removed and Continue, stop. |
| `code_overlays.drive` | Completion docs, signature help and hover boxes inside the Code area and bounded; the hover box stays while the mouse is on it. |
| `code_big_file.drive` | A generated 10,000-line script: an edit's line-state pass stays small, the token cache is >= 5x the full re-tokenize, highlighting far down the file. |
| `lua_node_types.drive` | Typed nodes in Lua: `find_node` overloads per node name, `self.node` typed by where the script is attached, camera methods only on cameras (language-server completion). |
| `welcome.drive` | One icon per node type; Help > Welcome; Platformer, Top-down and Menu projects from templates, each played headless by the game binary; the empty-scene hint. |
| `workspaces.drive` | Animation and Level Design presets (bottom panel height), a saved workspace loaded back, Reset Layout. |
| `remote_game.drive` | Play with the editor link: the Game tab's live tree, pause, one-frame step, inspect and change a node's rotation in the running game, resume, a saved scene reloading in the game, stop. |
| `sprite_slicer.drive` | Slicer: a texture cut 4 x 2, cells picked (click, Shift+click range) as an animation, one per row, a new AnimationPlayer; picked cells saved. |
| `asset_folders.drive` | Folders view: new folder, a texture the scene uses dragged into it (reference updated), Find Usages, folder renamed (references updated), thumbnail grid, texture import settings in project.json, folder deleted. |
| `scene_tree.drive` | Tags in the Inspector (typed, picked, removed), filter by `#tag` / `t:type`, reorder by dropping on a row's edge (undo), Copy to Scene at the same world position, tags in the generated Lua types. |
| `viewport_tools.drive` | Rulers, a guide dragged from the ruler, Alt-drag pivot (image and child stay), smart snap of an edge to the guide, viewport lock (not pickable) and hide in editor, Show All Colliders, saved. |
| `multi_edit.drive` | Two lights selected: mixed value marked, a number / one axis of the position / a checkbox / a combo applied to both, undo. |
| `inspector_help.drive` | Hovering a property fills the tooltip and the Inspector help pane (field or label); View > Inspector Help hides the pane. |
| `remember_dirs.drive` | An import remembers its folder and the next import dialog opens there; Export .ore into a picked folder, the next export and the Output Folder's Browse... start there; a new project's location; all saved in settings.ini `[paths]`. |
| `code_editor.drive` | Open a script in the Code tab; lua-language-server completion of the engine API, signature help, diagnostics, go to definition; save; unsaved-changes prompt; New Script from the Inspector. |

## Script language

One command per line; `#` starts a comment.

```
wait <frames>
wait-until <expr> [timeout=<frames>]
move|hover <target>
click|rclick|dblclick <target>
drag <from> <to> [steps]
scroll <target> <dy>
key <chord>                    # w, delete, f5, escape, ctrl+s, ctrl+shift+z, ctrl+slash, ctrl+rbracket
hold <mods> / release          # keep shift / cmd / alt held for the following clicks/keys
type <text>                    # "\s" types a space (command text is trimmed)
expect <expr>
screenshot <name>
game-args <args...>            # extra args for the game the editor launches
exec <command...>              # run a command to completion
drop-files <target> <path...>  # files/folders dropped from the OS file manager at <target>
dialog-files [<path...>]       # answer for the next system file dialog (none = Cancel)
log <text> | quit
```

**Targets**
- `@<id>`: a widget registered by the UI (`@toolbar.play`, `@hier:PlayerShip`,
  `@insp.position.x`, `@insp.prop:gravityScale`, `@addnode:Texture Sprite`,
  `@asset:scenes/main.scene.json`, `@menu:Game/Simulate in Editor`, `@pick:<value>`,
  `@ctx:duplicate`, `@settings.save`, `@code.area`, `@code.tab:<file>`, `@code.completion:<label>`, ...).
- `@node:<Name>`: a node's position on screen.
- `@world:x,y`: a world position.
- `x,y`: raw window pixels.
- Any target accepts a `+dx,dy` pixel offset.

Clicks scroll the target's panel into view first, like a user would.

**Expressions** have the form `<query> <op> <value>`, where `op` is one of
`== != contains !contains ~= >= <=`. Expected values may use `\n`, `\t`
and `\s` (space). On macOS, Dear ImGui swaps Cmd and Ctrl: `ctrl+` in a
drive is the physical Control key, `cmd+` the Command key; editor shortcuts
accept either (Ctrl-specific bindings such as Ctrl+G win when Ctrl is held),
and `hold cmd` (not ctrl, which macOS turns into a right-click) adds to a
selection. `~=` compares numbers or `x,y` pairs within 0.5.

Queries:
- `selected`, `scene`, `tool`, `zoom`, `camera`, `nodes`, `tile-chunks` (cached tile chunks), `undo-bytes` (memory held by undo snapshots)
- `modified`, `modified-count`, `undo`, `redo`
- `game` (running/stopped), `build`, `log`, `last-log`
- `add-node-open`, `project-settings-open`, `item:<id>`
- `file:<project path>`, `abs-file:<path>`
- `code.open` (tab count), `code.file`, `code.text`, `code.line` (caret line), `code.cursor` (`line:col`),
  `code.dirty`, `code.focused`, `code.lsp` (off/starting/ready/failed), `code.completion` (visible items,
  comma-separated), `code.signature`, `code.errors`, `code.diagnostics`, `code.diagnostic-messages`, `code.hover`
- `code.overlays` (`ok <n>` when every overlay is inside the Code area and bounded), `code.update-ms` (last line-state pass), `code.token-bench` (`full=<ms> cached=<ms> tokenized=<n> lines=<n>`), `code.token-speedup`
- `code.cursors`, `code.selection`, `code.find` (match count), `code.font`, `code.completion-doc`
- `insp-help` (the Inspector help pane: `<Title>: <doc>`), `guides` (`x=704,y=50`), `usages` (files in the Find Usages window, -1 = closed), `folder-open:<dir>`
- `dialog-start` (the folder the last system file dialog opened in), `last-dir:import` / `last-dir:export` / `last-dir:projects` (the remembered folders)
- `slicer-zoom` (the slicer's zoom, `0.00` = Fit), `slicer-selection` (picked cells, `0,1,2`), `hidden-tab-bars` (docked spaces whose tab bar is hidden)
- `game-pid` (the running game's process id, 0 = none), `last-played` (the scene Restart plays, `project` = the initial scene)
- `insp-help-path` (the path the help pane shows)
- `bottom-tab` (the bottom panel tab shown: Console, Profiler, Game, Animation, Particles, Ldtk)
- `remote-debug-draw` (the running game's last debug-draw reply)
- `selected-bounds` (the selected node's world bounds, `minx,miny,maxx,maxy`)
- `anim-names` (the selected AnimationPlayer's animations, the current one in `[brackets]`)
- `anim-preview` (`playing` / `paused`), `anim-info` (`frames=<n> range=<a>-<b> reverse=<b> fps=<f> default=<name>` of the selected AnimationPlayer), `theme` (the saved theme), `theme-panel` (the panel colour in use, `#rrggbbaa`), `node-icons` (`<distinct icons>/<node types>`), `workspace` (the current workspace), `window-h:<item>` (height of the window an item is in)
- `debug-stopped`, `debug-line` (`file:line`), `debug-stack`, `debug-local:<name>` (the Lua debugger)
- `remote-connected`, `remote-paused`, `remote-frame`, `remote-steps`, `remote-reloads`, `remote-nodes`, `remote-names`, `remote-prop:<name>` (the Game tab's link to the running game)
- `palette.open`, `shortcuts-open`, `quit-prompt`, `selection`, `selection-count`, `clipboard-nodes`
- `import.imported`, `import.skipped`, `import.failed` (counts from the last import), `import.report`
  (Import Results open), `import.messages` (one `<file>: <status> <path> <message>` line each), `import.dialog`
- `ldtk.node`, `ldtk.level`, `ldtk.world`, `ldtk.world-mode`, `ldtk.active-levels`, `ldtk.page`, `ldtk.rules`,
  `ldtk.link-rules`, `ldtk.mapping:<Entity>` (`auto` / `component <path>` / `node` / `none`),
  `ldtk.collision:<Layer>:<value>`, `ldtk.layer-visible:<Layer>`, `ldtk.focus`, `ldtk.spawned`, `ldtk.links` (of the
  LDtk tab's level)
- `shape.edit` (shape editing on), `shape:<Node>:<index>:<field>` with field `type offset size radius rotation
  vertices points count`; shape handles are items `shape<i>.<Kind><n>` (Move, Rotate, Radius, Edge 0-3,
  Corner 0-3, CapEnd 0-1, Point n, AddPoint n)
- `node-delta:A,B` (global position of B minus A), `anim` (`<animation>:<frame>/<length>:<tracks>` of the selected AnimationPlayer)
- `node:<Name>.<field>`, where field is one of `exists type parent position global locked editor-hidden tags child-names rotation scale visible enabled children script prop.<path> script.<prop> connections overrides tiles material state` (`state`: a StateMachine's `<current>/<state count>`)

Widgets register themselves with `Drive_Item("<id>")` right after they are drawn
(see `editor/test_drive.odin` and `UI_IconButton`/`UI_Button` in `ui_style.odin`).

**macOS display:** raylib can't create a window while the display sleeps
(the editor hangs or crashes in `InitWindow`). For long runs keep it awake:
`caffeinate -d -i scripts/editor_drive.sh`.
