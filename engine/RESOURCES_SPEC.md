# Resources — Design Spec

Status: **agreed design, not implemented**. When it ships, the user-facing parts
move into `SCRIPTING.md` ("Resources") and this file is deleted.

A **Resource** is a data asset whose behaviour comes from Lua: a class script
declares `properties` (edited in the Inspector) and methods (called by any
script that holds the resource). Equivalent to Godot custom Resources / Unity
ScriptableObjects.

## Decisions

| # | Decision |
|---|---|
| 1 | Two files: a **class** (`.lua`) and **instances** (`.resource.json`). Many instances per class. |
| 2 | Resources are **shared** by default; a class or a property can make them **local**. Local copies are scoped **per component instance**. |
| 3 | Runtime changes are never written back to the file (use `Save` for persistence). |
| 4 | One lifecycle callback: `on_load(self)`. No `ready` / `update`. |
| 5 | Nested resources (a resource property inside a resource class) — **later**. |
| 6 | A class is marked explicitly (`Class.resource = {...}`); unmarked scripts are not classes. |
| 7 | Instances live in a fixed `resources/` folder. |
| 8 | Inline / sub-resources (embedded in a scene) — **later**. |
| 9 | Asset Inspector edits **save on commit** (when a field is released), with undo. |
| 10 | Only project files (through the VFS / `.rayzr` package); no external loading. |
| — | One global undo stack: resource entries and scene entries interleave. |

## File formats

### Class script

```lua
---@class Health : ResourceBase
local Health = {}

-- The marker: makes this script a resource class.
-- local_copy: each owner (component instance) gets its own copy. Default false.
Health.resource = { local_copy = true }

Health.properties = {
    --- Maximum hit points.
    max   = { type = "int", default = 100, min = 1 },
    regen = { type = "float", default = 0 },
}

function Health:on_load()          -- after properties are applied, once per table
    self.current = self.max
end

function Health:damage(n)
    self.current = math.max(0, self.current - n)
    return self.current == 0
end

return Health
```

- `resource` must be a table; any other value is a warning, and the script is then not a class.
- Allowed property types: everything except `node` (a resource has no node) and, for now, `resource`. If one is declared, it's ignored with a warning.

### Instance file — `resources/<name>.resource.json`

```json
{
  "type": "resource",
  "script": "scripts/health.lua",
  "properties": {
    "max": 250
  }
}
```

- `properties` stores only values that **differ from the class defaults**, so changing a default in the class still reaches every instance that doesn't override it (same idea as component overrides). Keys are sorted for stable diffs.
- Value encoding is the same as scene script overrides (`write_script_props`).
- Values for properties the class no longer declares are kept in the file but ignored, with a single warning in the Inspector. Renaming a property doesn't silently delete data.

### Referencing a resource

```lua
Enemy.properties = {
    health = { type = "resource", class = "scripts/health.lua" },               -- local_copy from the class
    stats  = { type = "resource", class = "scripts/enemy_stats.lua", local_copy = false }, -- force shared
    drops  = { type = "array", of = "resource", class = "scripts/item.lua" },
}
```

- In scenes and components, a resource property is saved as a project-relative path string, the same as other asset references. *Later, for per-instance values:* the property can also accept `{"path": ..., "properties": {...}}`.
- `class` is optional. It filters the Inspector picker and is checked at runtime: a mismatch gives `nil` plus a warning.
- `local_copy` on the property overrides the class's default.

## Runtime semantics

### Shared vs local

| Mode | Cache key | Lifetime |
|---|---|---|
| Shared | `(nil, path)` | Until the script manager resets: game shutdown, Simulate stop, project change |
| Local | `(scope, path)` | Until the scope is destroyed |

**Scope** (`Resource_ScopeOf(node)`): walk from the node up through its parents. The scope is the first node with `componentPath != ""` (the **nearest** component instance root, so a nested component gets its own scope). If there's none, the scope is the root of the node's tree (the scene's root node). A scope is always a `^Node`, and `Node_Terminate` releases the copies it owns (`Resource_ForgetScope`), so unloading a scene releases its scene-scoped copies too.

So:
- Two `Enemy` instances each get their own `Health`.
- Inside one `Enemy`, the root script and a child `HealthBar` script that both reference `health.resource.json` share one table.
- `Scene.spawn` / `Scene_InstantiateComponent`, tilemap components and LDtk entity spawns all set `componentPath`, so each one gets its own scope automatically.
- Edge case: `Node_UnlinkComponent` clears `componentPath`. An unlinked subtree is then scoped by its next ancestor instance or the scene. That's fine because the scope is computed when properties are resolved (before `ready`).

A local copy is **reloaded from the file** (file values + `on_load`). It is **not** a copy of another table's runtime state.

### The Lua table

- Fields: one per declared property, plus `resource_path` (string, read-only by convention).
- The metatable's `__index` looks up the class module first, then `ResourceBase`. Methods and hot-reloaded functions work exactly like node scripts, and nothing is injected into the user's module table.
- `ResourceBase` methods:
  - `res:duplicate()` returns a new table with a **deep copy of the current state**: nested tables are copied (cycles and metatables kept), while other resources stay shared references. It's owned by the caller's scope and does **not** call `on_load`.
- Scripts can write fields at runtime. Writes are never saved.

### Lua API

| Call | Returns |
|---|---|
| `Resource.load(path)` | The shared table (loaded on first use). |
| `Resource.new(path)` | A fresh local table scoped to the **calling script's** scope (released with it). Inside `on_load` it uses the loading resource's scope; from global scripts it's owned by the manager. |
| `self.<resource prop>` | Resolved before `ready()`: shared or scoped-local, depending on `local_copy`. |

Errors: a missing file, a script that isn't a resource class, or a `class` mismatch all give `nil` plus a `Script_Problem` warning (shown as a squiggle at the call site / property, as with `get_node`).

### `on_load`

- Called once per table, after property values are applied, before the first script that receives it runs `ready()`.
- Runs only in Simulate and in the game. The editor (not simulating) never builds resource tables: the Inspector reads the class's parsed `properties` and the JSON.
- Errors go through the usual traceback handler and become a `Script_Problem` error; the table is still returned.

### Hot reload

- **Class `.lua` saved:** the module updates in place (existing mechanism), so every live table runs the new methods. New properties appear on live tables with their file value or default; removed ones are left alone.
- **`.resource.json` saved** (e.g. an Inspector commit): every live table for that path, shared and local, gets the **changed values** re-applied. `on_load` is **not** re-run, consistent with script hot reload keeping state.
- This needs a new watcher. `ScriptManager_CheckForChanges` only tracks `.lua` modules. Track `.resource.json` mtimes the same way.

### Simulate

Stopping Simulate calls `Resource_ClearAll`, alongside the existing globals snapshot and restore and module re-run.

## Engine implementation

New file `engine/script_resources.odin`:

```odin
ResourceInstance :: struct {
	path:        string,                 // "resources/sword.resource.json"
	modulePath:  string,                 // the class script
	scope:       rawptr,                 // nil = shared; else ^Node (instance root) or ^Scene
	properties:  map[string]ScriptValue, // applied values (file over defaults)
	registryRef: c.int,                  // the Lua table
}

Resource_Key :: struct { scope: rawptr, path: string }

// ScriptModule gains:     isResourceClass: bool, resourceLocalCopy: bool
// ScriptProperty gains:   resourceClass: string, resourceLocal: enum {Default, Shared, Local}
// ScriptManager gains:    resources: map[Resource_Key]^ResourceInstance, resourceFiles (mtimes)

Resource_Load        :: proc(mgr: ^ScriptManager, path: string, scope: rawptr, cached := true) -> ^ResourceInstance
Resource_Push        :: proc(L: ^lua.State, res: ^ResourceInstance)
Resource_ScopeOf     :: proc(node: ^Node) -> rawptr
Resource_ReleaseScope:: proc(mgr: ^ScriptManager, scope: rawptr)
Resource_ForgetScope :: proc(node: ^Node)                         // Node_Terminate
Resource_ClearAll    :: proc(mgr: ^ScriptManager)                 // ScriptManager_RestoreGlobals (Simulate stop), shutdown
Resource_ReloadFile  :: proc(mgr: ^ScriptManager, path: string) -> bool // hot reload of a .resource.json
Resource_ReadFile    :: proc(mgr: ^ScriptManager, path: string) -> (Resource_File, bool) // temp allocated
Resource_ParseText   :: proc(path, text: string) -> (Resource_File, bool)
Resource_FileText    :: proc(script: string, values: map[string]ScriptValue, mod: ^ScriptModule, extra: map[string]string = nil, allocator := context.allocator) -> string // non-defaults + undeclared raw keys, sorted
// Resource_File :: struct { script: string, values: map[string]ScriptValue, raw: map[string]string }
// The editor writes the file itself (PR 5) with Resource_FileText.
```

Lua side: the `Resource` global (`load`, `new`) and, in the registry, `ResourceBase`, a weak set of resource tables, and two Lua helpers (the metatable factory and the deep copy for `duplicate`). They're registered from `RegisterEngineLuaBindings` (`Script_RegisterResourceModule`).

Refactors (behaviour-preserving, done first in #47):
- Move the property-application loop out of `Script_AttachToNode` (steps 4–5) into `script_apply_properties(L, tableIdx, mod, overrides, &props)`, used by both node scripts and resources.
- Extend `Script_ParseProperties` with `"resource"` (`prop.type = .String`, `assetKind = "resource"`, plus `class` and `local_copy`), and with `of = "resource"` for arrays.
- Extend `script_resolve_node_props` (or add a sibling `script_resolve_resource_props`) so resource properties resolve before `ready()`.
- Parse the `resource` marker in `ScriptManager_LoadModule`, next to `Script_ParseProperties`.

Memory: every string in `ResourceInstance` is owned by the script manager's allocator. `Resource_ReleaseScope` unrefs the Lua table and frees the instance. Tests run under the tracking allocator.

## Editor implementation

### Asset browser (`editor/asset_browser.odin`, `asset_actions.odin`, `asset_import.odin`)
- Add `Asset_Kind.Resource`. `Asset_KindOf` checks the `.resource.json` suffix next to `.scene.json` / `.component.json`.
- `kind_icon`: a new icon constant. `ICON_FA_GEM` (U+F3A5) isn't defined in `font_awesome.odin` yet, so add it and **check that the glyph is in the atlas's merged range**.
- `Asset_DisplayName` strips `.resource.json`.
- Types view: a "Resources" section listing `resources/` with `{".resource.json"}`, plus a `+` header button for New Resource.
- `asset_tooltip`, `Asset_ContextMenu`: Open Class Script, Duplicate, Find Usages, Rename, Delete.
- `Asset_ImportDir`: `.Resource` maps to `"resources"`. `validate`: a JSON object with `"type": "resource"` and a `"script"` string.
- `Script_AssetKind`: `.Resource` maps to `"resource"` (Cmd/Ctrl+drop into code adds `type = "resource"`).
- Rename, move and Find Usages work as-is: `.json` files are already scanned for quoted paths, and that includes the `"script"` path inside the file.
- `.rayzr` export: no change, because the whole project folder is packed.

### New Resource
- A dialog with a name field and a class combo listing scripts whose module has `isResourceClass`, loaded through `Script_InspectProperties`.
- Writes `resources/<name>.resource.json` with `properties: {}`, selects it and opens it in the Inspector.
- `script_templates.odin`: add a "Resource class" template (marker, `properties`, `on_load`).

### Asset Inspector (`editor/inspector.odin`)
- New state `state.inspectedResource: string`. It's set when you click a `.resource.json` in Assets and cleared when you select a node. `inspector_body` shows the resource when it's set: a header with the file, the class (link to open it) and a missing-class warning, followed by the properties.
- Refactor the property widgets in `inspector_script` into one shared editor that works on `(mod, ^map[string]ScriptValue)`, so node scripts and resources draw identical controls (groups, tooltips, help pane, curves...).
- A "Reset to default" item on each property removes its key from the file.
- Resource-typed properties on node scripts: an asset picker filtered to `resources/` and, when `class` is set, to instances of that class. Assets can be dropped onto the field. There's also an "Open" button that inspects the resource.

### Saving (save on commit)
- Text and drag fields write on `IsItemDeactivatedAfterEdit`. Checkboxes, combos and pickers write as soon as they change. Curve and gradient editors write when the mouse is released.
- Write with `Resource_WriteFile`, then log `Saved resources/x.resource.json` to the Console. A running game or Simulate picks the change up through hot reload.
- There's no unsaved state, so the quit prompt, tab dots and save-before-Play don't change.

### Undo (one global stack)
- `Undo_Entry` gains `kind: enum {Scene, Resource}` and `resourcePath: string`. For `.Resource`, `json` holds the file text **before** the edit (an `Undo_Snapshot`).
- `Editor_RecordResourceUndo(state, path, label)` is called on `IsItemActivated` (as `undo_on_activate` does), with the same "unchanged snapshot = no new step" rule.
- `undo_redo`: take the most recent entry that is `.Resource` **or** belongs to the active scene. Today it only accepts the active scene. For a resource entry, write the file back, push the opposite entry, refresh the Inspector if it's showing that file, and log `Undo: <label> (resource x)`.
- `Editor_RecordResourceUndo` doesn't record while Simulate is running, matching `Editor_RecordUndo`.

### Completion (`editor/lua_project_types.odin`, `lua_types/`)
- `ResourceBase` class: `resource_path`, `duplicate()`, `on_load()`.
- `ResourcePath` alias listing `resources/**/*.resource.json`.
- `Resource.load` / `Resource.new` overloads per file, returning that file's class (like `component_overloads`): `---@overload fun(path: "resources/sword.resource.json"): WeaponData`.
- A resource property with `class` is typed as that class, so `self.health:` completes `damage`.

## Tests

`engine/script_resources_test.odin` (`odin test engine -define:ODIN_TEST_THREADS=1 -- -tests:<name>`):
- `test_resource_class_marker` — marker parsed; unmarked script rejected; bad marker warns.
- `test_resource_file_roundtrip` — read/write, defaults omitted, sorted keys, unknown keys kept.
- `test_resource_shared_identity` — two `Resource.load` calls return the same table.
- `test_resource_local_per_component_instance` — two instances differ; root and child in one instance share.
- `test_resource_local_nested_component` — a nested component gets its own scope.
- `test_resource_property_override_local_copy` — a property's `local_copy = false` beats the class default.
- `test_resource_on_load_once` — once per table, before the owner's `ready`; an error is reported.
- `test_resource_class_mismatch` — `nil` plus a warning.
- `test_resource_hot_reload` — methods update; changed file values re-applied; `on_load` not re-run.
- `test_resource_released_with_scope` — destroying the instance root frees its local copies (no leaks).
- `test_resource_simulate_clear` — `Resource_ClearAll` frees everything.
- `test_resource_duplicate` — deep copy; independent tables.

Editor: `Asset_KindOf` / `Asset_DisplayName` cases, and the resource undo/redo round trip.
Drive: `tests/drive/resource_basic.drive` — create a class from the template, New Resource, edit a field in the Inspector, check the file, undo, check the file again.

## PR plan

1. **Refactor** — pull out `script_apply_properties` and the shared Inspector property editor. No behaviour change; the existing tests must stay green.
2. **Engine: resources** — marker, file IO, cache and scopes, `Resource.load/new`, `on_load`, `duplicate`, hot-reload watcher, Simulate clear, plus tests.
3. **Engine: `type = "resource"` property** — parsing, resolution before `ready`, arrays, class check, plus tests.
4. **Editor: asset kind** — browser section, icon, import/validate, context menu, New Resource dialog, class template.
5. **Editor: asset Inspector** — selection model, save on commit, global undo, plus a drive test.
6. **Completion + docs** — `ResourceBase`, aliases and overloads; a `SCRIPTING.md` section; a `docs/editor` page; `odin_editor/TODO.md` / backlog entry; delete this spec.
