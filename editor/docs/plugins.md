# Editor plugins (design)

Status: designed 2026-10-25 (TODO 13). Plugins extend the **editor** in Lua -
tools, panels, automation, export steps - without rebuilding it. They don't
add game runtime features (new node types in exported games): that's game
code, designed later with how it ships in the runner.

## Decisions

| | Decided |
|---|---|
| Where plugins live | Both: **project plugins** (`<project>/plugins/<name>/`, versioned with the game, shared with the team) and **user plugins** (`<editor config>/plugins/<name>/`, every project) |
| Safety | **Trust prompt + permissions**: a project's plugins run only after "This project has plugins - allow?" (remembered per project, like LDtk custom commands); file access through `Editor.fs` limited to the project and the plugin's folder; processes and network only when `plugin.json` declares them (listed in the prompt) |
| First milestone | **A** commands + edits, **B** panels, **C** events; **D** inspectors / gizmos / importers right after |
| Runtime extensions | Not now (editor-only) |

## A plugin

```
plugins/align_tools/
  plugin.json
  main.lua
```

```json
{
  "name": "Align Tools",
  "version": "1.0.0",
  "description": "Align and distribute the selection",
  "editor": ">=0.2.0",
  "main": "main.lua",
  "permissions": []
}
```

`permissions`: `"process"` (Editor.run), `"network"` (Editor.http). Without
them those calls fail. Settings > Plugins lists every plugin (project / user),
its state (enabled, error, waiting for trust), its log, and Reload / Enable /
Disable.

## Runtime

- One Lua state **per plugin**: an error disables only that plugin (shown in
  Settings > Plugins and the console), never the editor; plugins reload one at
  a time - on save (hot reload) or from the Plugins page.
- The state has the engine's Node API (the same names game scripts use:
  `find_node`, `position`, `get_property`, signals...) bound to the **scene
  being edited**, not the simulation, plus the `Editor` API below. No `io`,
  `os.execute`, `package.loadlib`; `require` loads from the plugin's folder.
- Every call into a plugin is protected; a panel `draw` slower than a few ms is
  flagged in the Plugins page.
- `on_load()` runs when the plugin starts, `on_unload()` before a reload /
  disable / quit; what a plugin registered (commands, panels, hooks) goes with it.

## API (milestone 1)

### A. Commands and edits

```lua
Editor.add_command{
    id = "align.left", label = "Align Left", menu = "Tools/Align",
    shortcut = "ctrl+alt+left",
    enabled = function() return #Editor.selection() >= 2 end,
    run = function()
        local nodes = Editor.selection()
        local x = math.huge
        for _, n in ipairs(nodes) do x = math.min(x, n.position.x) end
        Editor.edit("Align left", function()     -- one undo step
            for _, n in ipairs(nodes) do n.position = Vec2(x, n.position.y) end
        end)
    end,
}
```

Commands go into the editor's action table: menus, the command palette and
the keymap (rebindable like built-in actions; ids become
`plugin.<plugin id>.<id>`). Shortcuts: `"Primary+Shift+L"` (Primary = Cmd on
macOS, Ctrl elsewhere), `"Alt+F3"`, ...; `scope = "scene"` keeps one off
while typing code. Also:

- `Editor.selection()`, `Editor.select(nodes)`, `Editor.scene()` (the open
  scene: root, find_node), `Editor.open_scene(path)`, `Editor.project()`
  (name, path, settings)
- `Editor.edit(label, fn)`: changes inside are one undo step (the editor's
  scene snapshot before `fn`); edits outside `edit` work but can't be undone
  - always use it for scene changes
- `Editor.create_node(type, parent)`, `node:destroy()` (inside `edit`)
- Assets: `Editor.assets(folder?, ext?)`, `Editor.fs.read / write / exists /
  list / mkdir` (project and plugin folders only), `Editor.import(path)`
- `Editor.log / warn / error`, `Editor.notify(text)`, `Editor.prompt(text,
  default, fn)`, `Editor.confirm(text, fn)`, `Editor.pick_file{...}` (native
  dialogs; async: a callback)
- `Editor.run(cmd, args, fn)` (permission `process`, async output),
  `Editor.http(url, opts, fn)` (permission `network`)

### B. Panels

```lua
local count = 0
Editor.add_panel{
    id = "stats", title = "Level Stats", dock = "right",
    draw = function(ui)
        ui.text("Nodes: " .. #Editor.scene():find_all())
        if ui.button("Count again") then count = count + 1 end
        local changed, v = ui.slider("Zoom", Editor.camera().zoom, 0.1, 4)
        if changed then Editor.camera().zoom = v end
    end,
}
```

Dockable windows (View > Plugins > ...), saved with workspaces. `ui` is
immediate mode over Dear ImGui: text, button, input, checkbox, slider, drag,
combo, color, image (an asset), tree / tree_node, table, separator, same_line,
tooltip, child regions. Ids come from labels (`##id` suffixes as in ImGui).

### C. Events

```lua
Editor.on("selection_changed", function(nodes) ... end)
Editor.on("scene_saved", function(path) ... end)
Editor.on("asset_imported", function(path) ... end)
Editor.on("before_play", function(scene) return ok, message end)  -- false: Play is cancelled, message shown
Editor.on("after_export", function(preset, dir) ... end)
Editor.on("project_opened", function(project) ... end)
```

### D (next). Inspectors, viewport, importers

- `Editor.add_inspector{type = "PathNode" | script property type, draw = function(ui, node) ... end}`:
  a section in the Inspector
- `Editor.add_overlay{draw = function(g, view) ... end}` with world-space
  drawing (lines, circles, text) and draggable handles that edit inside an
  undo step
- `Editor.add_importer{ext = ".tsx", import = function(path, out) ... end}`:
  new file types become project assets

## Developer experience

The guide: [plugin_guide.md](plugin_guide.md); examples in
[plugin_examples/](plugin_examples/).


- `editor_api.lua` definitions (generated like the engine's) in
  `.ore/definitions/`: completion and hover docs for `Editor` and `ui` in the
  Code tab and any LuaLS editor
- Tools > New Plugin writes a working plugin (a command, a panel, an event)
- A guide with examples: align / distribute, batch rename, level stats panel,
  export-and-zip
- Drives can run plugin commands (`command <id>`), so plugins are tested like
  the editor

## Build order

13.1 Plugin host: discovery (project + user), plugin.json, one Lua state each,
     protected calls, errors, on_load / on_unload, hot reload, Settings > Plugins
13.2 Trust prompt + permissions (per project, remembered)
13.3 A: commands (action table, menus, palette, keymap), selection, scene,
     `Editor.edit` undo, create / destroy, assets + `Editor.fs`, dialogs
13.4 B: panels + the `ui` widget set
13.5 C: events
13.6 Definitions (editor_api.lua), New Plugin template, guide + examples, drives
13.7 D: inspectors, viewport overlays / handles, importers
