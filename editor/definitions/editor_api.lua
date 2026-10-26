---@meta
-- Rayzr editor plugin API (editor/docs/plugins.md) - for plugins only: these
-- globals exist in a plugin's Lua state, not in game scripts. Written to
-- .rayzr/definitions/ when the project has a plugins/ folder.

---@class EditorPluginInfo
---@field id string The plugin's folder name
---@field name string
---@field version string
---@field dir string The plugin's folder (absolute)

---@class EditorCommand
---@field id string Unique within the plugin (the action id becomes plugin.<plugin id>.<id>)
---@field label string Shown in menus and the command palette
---@field run fun() Runs the command
---@field menu? string Where it goes: "Tools", "Tools/Align" (a submenu), "Edit", ... (none: the palette only)
---@field shortcut? string "Primary+Shift+L" (Primary = Cmd on macOS, Ctrl elsewhere), "Alt+F3", ...
---@field scope? "global"|"scene" "scene": not while typing code (default "global")
---@field enabled? fun(): boolean Greyed out / skipped when false
---@field checked? fun(): boolean A toggle's check mark

---@class EditorPanel
---@field id string Unique within the plugin
---@field title? string The window's title (default: id)
---@field dock? "right"|"left"|"bottom"|"center"|"float" Where it docks the first time (as a tab)
---@field open? boolean Shown at start (default true)
---@field draw fun(ui: EditorUI) Draws it, every frame - keep it cheap

---@class EditorScene
---@field name string
---@field path string Project-relative scene file
---@field root Node The scene's root node

---@class EditorProject
---@field name string
---@field path string The project folder (absolute)

---@class EditorPickFile
---@field fn fun(paths: string[]) Called with the chosen paths (empty: cancelled)
---@field title? string
---@field exts? string[] Extensions without dots ({"png", "jpg"})
---@field folders? boolean Choose folders
---@field multiple? boolean Allow several

---@alias EditorEvent
---| "project_opened"    # fn(project_name) - when the plugin starts
---| "selection_changed" # fn(nodes)
---| "scene_saved"       # fn(path)
---| "asset_imported"    # fn(path)
---| "before_play"       # fn(scene_path) -> false, reason to cancel Play
---| "after_export"      # fn(preset_name, dir)

---@class EditorFS Files in the project or the plugin's folder (relative paths: the project)
local EditorFS = {}
---Reads a text file in the project (relative paths) or the plugin's folder.
---
---Example: `local text, err = Editor.fs.read("data/items.json")`
---@param path string
---@return string? text, string? err
function EditorFS.read(path) end
---Writes a text file in the project or the plugin's folder (its folders are made).
---
---Example: `Editor.fs.write("data/notes.txt", "Hello")`
---@param path string
---@param text string
---@return boolean ok
function EditorFS.write(path, text) end
---Whether a file or folder exists (false outside the project and the plugin's folder).
---
---Example: `if not Editor.fs.exists("levels") then Editor.fs.mkdir("levels") end`
---@param path string
---@return boolean
function EditorFS.exists(path) end
---The names in a folder, sorted; folders end with "/".
---
---Example: `for _, name in ipairs(Editor.fs.list("scripts")) do print(name) end`
---@param path string A folder
---@return string[] names Folders end with "/"
function EditorFS.list(path) end
---Makes a folder (and its parents) in the project or the plugin's folder.
---
---Example: `Editor.fs.mkdir("generated/levels")`
---@param path string
---@return boolean ok
function EditorFS.mkdir(path) end

---@class EditorAPI
---@field plugin EditorPluginInfo
---@field fs EditorFS
Editor = {}

---Logs to the plugin's log (Settings > Plugins) and the console (print does too).
---@param ... any
function Editor.log(...) end
---Logs a warning to the plugin's log and the console.
---
---Example: `Editor.warn("No player in this scene")`
---@param ... any
function Editor.warn(...) end
---Logs an error to the plugin's log and the console.
---
---Example: `Editor.error("Could not read data/items.json")`
---@param ... any
function Editor.error(...) end

---Adds a command: menus, the command palette, the keymap.
---
---Example: `Editor.add_command{id = "align_left", label = "Align Left", menu = "Tools/Align", run = align_left}`
---@param spec EditorCommand
function Editor.add_command(spec) end

---Adds a dockable panel drawn with the `ui` widgets.
---@param spec EditorPanel
function Editor.add_panel(spec) end

---Shows (in front) or hides one of the plugin's panels.
---@param id string
---@param open? boolean Default true
function Editor.show_panel(id, open) end

---@class EditorInspector
---@field id string Unique within the plugin
---@field title? string The section's header (default: id)
---@field type? string Only for this node type ("TextureNode", ...; default: every node)
---@field draw fun(ui: EditorUI, node: Node) Draws the section, every frame the node is selected

---Adds a section to the Inspector.
---@param spec EditorInspector
function Editor.add_inspector(spec) end

---@class EditorOverlayView
---@field zoom number The viewport's zoom
---@field mouse Vec2 The mouse in world space

---@class EditorOverlay
---@field id string Unique within the plugin
---@field title? string The undo step's name for handle drags (default: id)
---@field draw fun(g: EditorOverlayDraw, view: EditorOverlayView) Draws over the viewport, every frame

---Draws over the viewport (world space) with draggable handles.
---@param spec EditorOverlay
function Editor.add_overlay(spec) end

---@class EditorImporter
---@field ext string ".tsx": the extension it imports
---@field import fun(name: string, data: string): table<string, string>?, string? Returns {["project/path"] = contents} (or nil, "why")

---Imports a new file type (dropped or from Import Assets).
---@param spec EditorImporter
function Editor.add_importer(spec) end

---World-space drawing in an overlay's draw. Colours: "#rrggbb" / "#rrggbbaa".
---@class EditorOverlayDraw
local EditorOverlayDraw = {}
---Draws a line between two world positions.
---
---Example: `g.line(Vec2(0, 0), Vec2(100, 0), "#ff8800", 2)`
---@param a Vec2
---@param b Vec2
---@param color? string
---@param width? number Pixels
function EditorOverlayDraw.line(a, b, color, width) end
---Draws a circle (outline, or filled) in world units.
---
---Example: `g.circle(Vec2(320, 180), 48, "#00ff0080")`
---@param center Vec2
---@param radius number World units
---@param color? string
---@param filled? boolean
function EditorOverlayDraw.circle(center, radius, color, filled) end
---Draws a rectangle between two world corners (outline, or filled).
---
---Example: `g.rect(Vec2(0, 0), Vec2(64, 32), "#ffffff40", true)`
---@param min Vec2
---@param max Vec2
---@param color? string
---@param filled? boolean
function EditorOverlayDraw.rect(min, max, color, filled) end
---Draws a label at a world position.
---
---Example: `g.text(Vec2(320, 150), "Spawn point", "#ffffff")`
---@param pos Vec2
---@param text string
---@param color? string
function EditorOverlayDraw.text(pos, text, color) end
---A draggable point. While dragged: true and where it is now (change the scene
---right away - the drag is one undo step).
---@param id string Unique within the overlay
---@param pos Vec2
---@param color? string
---@return boolean moved, Vec2 pos
function EditorOverlayDraw.handle(id, pos, color) end

---Calls fn on an editor event.
---@param event EditorEvent
---@param fn function
function Editor.on(event, fn) end

---The selected nodes.
---@return Node[]
function Editor.selection() end

---Selects nodes (nil: nothing).
---@param nodes Node|Node[]|nil
function Editor.select(nodes) end

---The scene being edited (nil: none).
---@return EditorScene?
function Editor.scene() end

---The open project: its name and folder.
---
---Example: `local project = Editor.project(); print(project.name, project.path)`
---@return EditorProject
function Editor.project() end

---Changes to the scene inside fn are one undo step. Always use it for scene changes.
---
---Example: `Editor.edit("Align left", function() n.position = Vec2(0, n.position.y) end)`
---@param label string The undo step's name
---@param fn fun()
function Editor.edit(label, fn) end

---Creates a node (inside Editor.edit).
---@param type string "Node", "TextureNode", "CameraNode", ...
---@param parent? Node Default: the scene's root
---@param name? string Default: the type (made unique)
---@return Node
function Editor.create_node(type, parent, name) end

---Deletes a node (inside Editor.edit).
---@param node Node
function Editor.delete(node) end

---Project files (project-relative paths), optionally in a folder / with an extension.
---@param folder? string
---@param ext? string ".png", ".scene.json", ...
---@return string[]
function Editor.assets(folder, ext) end

---A message in the console.
---@param text string
function Editor.notify(text) end

---Asks yes / no.
---@param text string
---@param fn fun(yes: boolean)
function Editor.confirm(text, fn) end

---Asks for text.
---@param text string
---@param default? string
---@param fn fun(value: string?) nil: cancelled
function Editor.prompt(text, default, fn) end

---The system's file dialog.
---@param spec EditorPickFile
function Editor.pick_file(spec) end

---Runs a program (permission "process" in plugin.json); fn gets its result.
---@param cmd string
---@param args? string[]
---@param fn fun(ok: boolean, output: string, exit_code: integer)
function Editor.run(cmd, args, fn) end

---Fetches a URL (permission "network" in plugin.json).
---@param url string
---@param fn fun(ok: boolean, body: string)
function Editor.http(url, fn) end

---Immediate-mode widgets for panels (only inside a panel's draw).
---Labels are ids: "Save##2" shows "Save".
---@class EditorUI
ui = {}
---A line of text.
---
---Example: `ui.text("Enemies: " .. count)`
---@param text string
function ui.text(text) end
---A line of dimmed (secondary) text.
---
---Example: `ui.dim("Select a node to edit it")`
---@param text string Dimmed
function ui.dim(text) end
---A horizontal line, with an optional label.
---
---Example: `ui.separator("Options")`
---@param label? string
function ui.separator(label) end
---Puts the next widget on the same line as the last one.
---
---Example: `if ui.button("OK") then ok() end; ui.same_line(); if ui.button("Cancel") then cancel() end`
function ui.same_line() end
---A little vertical space.
---
---Example: `ui.spacing()`
function ui.spacing() end
---The next widget's width.
---@param w number
function ui.width(w) end
---A button; true on the frame it is clicked.
---
---Example: `if ui.button("Rebuild") then rebuild() end`
---@param label string
---@return boolean clicked
function ui.button(label) end
---A selectable row (lists); true when clicked.
---
---Example: `if ui.selectable(name, name == current) then current = name end`
---@param label string
---@param selected? boolean
---@return boolean clicked
function ui.selectable(label, selected) end
---A check box; returns whether it changed and the new value.
---
---Example: `local changed; changed, opts.snap = ui.checkbox("Snap", opts.snap)`
---@param label string
---@param value boolean
---@return boolean changed, boolean value
function ui.checkbox(label, value) end
---A one-line text field; returns whether it changed and the text.
---
---Example: `local changed; changed, self.filter = ui.input("Filter", self.filter)`
---@param label string
---@param text string
---@return boolean changed, string text
function ui.input(label, text) end
---A slider between min and max; returns whether it changed and the value.
---
---Example: `local changed; changed, opts.size = ui.slider("Size", opts.size, 8, 128)`
---@param label string
---@param value number
---@param min number
---@param max number
---@return boolean changed, number value
function ui.slider(label, value, min, max) end
---A number edited by dragging (or typing); returns whether it changed and the value.
---
---Example: `local changed; changed, opts.speed = ui.drag("Speed", opts.speed, 0.5)`
---@param label string
---@param value number
---@param speed? number
---@return boolean changed, number value
function ui.drag(label, value, speed) end
---A drop-down list; returns whether it changed and the chosen 1-based index.
---
---Example: `local changed; changed, opts.mode = ui.combo("Mode", opts.mode, {"Grid", "Free"})`
---@param label string
---@param index integer 1-based
---@param items string[]
---@return boolean changed, integer index
function ui.combo(label, index, items) end
---A collapsible tree item; true while open (then call ui.tree_pop()).
---
---Example: `if ui.tree_node("Details") then ui.text("..."); ui.tree_pop() end`
---@param label string
---@return boolean open Call ui.tree_pop() when open
function ui.tree_node(label) end
---Ends an open ui.tree_node.
---
---Example: `ui.tree_pop()`
function ui.tree_pop() end
---A tooltip for the last widget.
---@param text string
function ui.tooltip(text) end
---Starts a table with a number of columns; true while visible (then call ui.end_table()).
---
---Example: `if ui.begin_table("nodes", 2) then ui.text("Name"); ui.next_cell(); ui.text("Type"); ui.end_table() end`
---@param id string
---@param columns integer
---@return boolean visible Call ui.end_table() when visible
function ui.begin_table(id, columns) end
---Moves to the next table cell (wrapping to the next row).
---
---Example: `ui.next_cell()`
function ui.next_cell() end
---Ends a table started with ui.begin_table.
---
---Example: `ui.end_table()`
function ui.end_table() end

---(Plugins) Called when the plugin starts.
function on_load() end
---(Plugins) Called before it stops (reload, turned off, the editor quits).
function on_unload() end
