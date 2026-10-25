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
---@param path string
---@return string? text, string? err
function EditorFS.read(path) end
---@param path string
---@param text string
---@return boolean ok
function EditorFS.write(path, text) end
---@param path string
---@return boolean
function EditorFS.exists(path) end
---@param path string A folder
---@return string[] names Folders end with "/"
function EditorFS.list(path) end
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
---@param ... any
function Editor.warn(...) end
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
---@param a Vec2
---@param b Vec2
---@param color? string
---@param width? number Pixels
function EditorOverlayDraw.line(a, b, color, width) end
---@param center Vec2
---@param radius number World units
---@param color? string
---@param filled? boolean
function EditorOverlayDraw.circle(center, radius, color, filled) end
---@param min Vec2
---@param max Vec2
---@param color? string
---@param filled? boolean
function EditorOverlayDraw.rect(min, max, color, filled) end
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
---@param text string
function ui.text(text) end
---@param text string Dimmed
function ui.dim(text) end
---@param label? string
function ui.separator(label) end
function ui.same_line() end
function ui.spacing() end
---The next widget's width.
---@param w number
function ui.width(w) end
---@param label string
---@return boolean clicked
function ui.button(label) end
---@param label string
---@param selected? boolean
---@return boolean clicked
function ui.selectable(label, selected) end
---@param label string
---@param value boolean
---@return boolean changed, boolean value
function ui.checkbox(label, value) end
---@param label string
---@param text string
---@return boolean changed, string text
function ui.input(label, text) end
---@param label string
---@param value number
---@param min number
---@param max number
---@return boolean changed, number value
function ui.slider(label, value, min, max) end
---@param label string
---@param value number
---@param speed? number
---@return boolean changed, number value
function ui.drag(label, value, speed) end
---@param label string
---@param index integer 1-based
---@param items string[]
---@return boolean changed, integer index
function ui.combo(label, index, items) end
---@param label string
---@return boolean open Call ui.tree_pop() when open
function ui.tree_node(label) end
function ui.tree_pop() end
---A tooltip for the last widget.
---@param text string
function ui.tooltip(text) end
---@param id string
---@param columns integer
---@return boolean visible Call ui.end_table() when visible
function ui.begin_table(id, columns) end
function ui.next_cell() end
function ui.end_table() end

---(Plugins) Called when the plugin starts.
function on_load() end
---(Plugins) Called before it stops (reload, turned off, the editor quits).
function on_unload() end
