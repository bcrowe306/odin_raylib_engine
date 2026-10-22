# Engine & Editor Gap Audit

Audit of `engine/` and `editor/` done while making the editor production-ready.
Each finding was confirmed by reproducing it: a unit test, a scripted UI test-drive
(`tests/drive/*.drive`), or a measurement. Section 1 lists what was fixed (four passes).
Section 2 lists what is still open, with priority and a suggested approach.

---

## 1. Fixed in this pass

### Playtesting ("I change the scene, press Play, the game plays the old version")

| Problem | Cause | Fix | Verified by |
|---|---|---|---|
| Play ran a different scene than the one edited | `main.scene.json` and `battle_arena.scene.json` both had `"name": "battle_arena"`. Scenes were keyed by name, so the second file replaced the first and the game started `battle_arena.scene.json`. | Scenes are registered per file. A name collision falls back to the file stem and logs a warning (`Game_SceneNameForFile`). The demo data was fixed too. | `test_duplicate_scene_names_do_not_shadow_the_initial_scene`, `playtest.drive` |
| `currentScene` could dangle | `SceneManager.scenes` stored `Scene` by value in a map while code kept `&scenes[name]` pointers. Map growth moved the scenes. | `map[string]^Scene`. Replacing a scene clears pointers to the old one. | all engine tests |
| Saving lost data, so the game played stale values | The serializer dropped script property values, particle/timer/camera/character/area/raycast settings, body damping and fixed rotation, and every UI field. Static-body materials were ignored on load. Strings weren't escaped. | Rewrote save/load as one symmetric system (`scene_serialization.odin`). Every `gui:"true"` field is saved and loaded via reflection (`node_properties.odin`), plus explicit resources (texture, frames, audio, timer, shapes, LDtk, script and its values). Older files still load. | `test_every_node_type_round_trips` (byte-identical load→save), `test_script_property_values_are_saved`, `test_legacy_scene_file_loads_without_duplicate_cameras` |
| Every save/load cycle added another `MainCamera` | The loader created a camera from the scene-level `"camera"` block *and* from the saved camera node. | The camera node is the source of truth. The legacy block is used only when no camera node exists. | `test_demo_scenes_reach_a_fixed_point` |
| Edits saved only when you pressed Save | Play saved just the active scene, and skipped even that in tests. | Play saves **every** modified scene first. The modified state is tracked per scene (shown in the title, tree and status bar). | `playtest.drive` |
| Engine code changes ignored by Play | Play launched a prebuilt `./odin_raylib_engine`. | If any `.odin` source is newer than `bin/odin_raylib_engine`, Play rebuilds it first (async, output in the console). | manual + `Editor_GameBinaryIsStale` |
| Couldn't play the scene being edited | Only the project's initial scene could be played. | **Play Current Scene (F6)** passes `--scene <file>` to the runner. | `playtest.drive` |
| Camera frame in the editor ≠ what the game shows | The editor drew the camera at (640,360) while the game camera looked at its `targetPosition` (0,0). | One rule for both: with no follow target and no explicit target position, a camera looks at its node position (`CameraNode_ViewCenter`). | game screenshot in `playtest.drive` |
| Editor ran gameplay code while editing | Opening a project ran `ready()` and scripts, which could move nodes, and those moves then got saved. | Edit-mode loading (`Game_LoadProjectForEditing`, `Scene_LoadForEditing`). Scripts start only when you Simulate or Play. | `scripts.drive` |

### Engine bugs

| Problem | Fix | Verified by |
|---|---|---|
| A JSON scene came back **empty** when re-entered (no setup proc) | JSON scenes keep their source and rebuild on every entry (`Scene_JsonSetup`), which also means they load lazily | `test_json_scene_is_rebuilt_when_re_entered` |
| `TimerNode` durations over ~2.1 s broke (f32 → Duration overflow) | Compute in f64 | `test_every_node_type_round_trips` |
| `ScriptInstance_SetProperty` freed the map key it was given, then used it. Every inspector edit corrupted the property name | Copy key/value before releasing the old entry | `test_script_set_property_with_map_key_string` |
| Script string defaults/overrides shared between module and instance → double free (crash on exit) | Instances own their strings | `scripts.drive` (used to abort) |
| Texture/sound/music paths stored without copying (callers pass temp strings), so cache lookups compared freed memory | Owned copies, freed on terminate | leak-checked tests |
| **Exported `.ore` games couldn't load textures or audio** (disk-only loader) | ResourceManager falls back to the mounted package (`LoadImageFromMemory`, `LoadWaveFromMemory`, in-memory music streams) | `export.drive` runs the game from the exported package; manual run from `/tmp` |
| Scripts resolved only relative to the working directory, never from the project or a `.ore` | Resolve via AssetManager first (project dir / package) | `scripts.drive` (project-relative `scripts/...`) |
| `CreateNodeScene` set `typeId = Node` for every type, so nodes added from the editor saved as plain `Node` and lacked their update/render procs | One node factory (`node_registry.odin`) used by the loader and the editor | `test_node_factory_creates_every_registered_type` |
| Editor *Duplicate* built a `Node` and cast it to the original type (memory corruption) | Duplicate = serialize + instantiate the subtree | `nodes.drive` |
| *Save as Component* wrote only `{"name": ...}` | Saves the full subtree | `components.drive` |
| Child nodes ignored parent rotation/scale (a thruster didn't follow a turning ship) | Global transforms compose position/rotation/scale; `Node_WorldToParent`/`Node_ParentToWorld` | `test_children_inherit_parent_rotation_and_scale` |
| `AddChild` allowed a node to have two parents | One parent per node; moving a node re-parents it | factory test |
| Loader reset `context` to the default allocator/logger, losing the caller's | Removed | engine tests run with no "bad free" reports |
| `SoundNode` had no volume/pitch/autoplay and wasn't added to the scene | Added properties + `ready` | round-trip test |
| LDtk node didn't remember its project path, so it wasn't saved | `projectPath` saved and loaded | round-trip test |

### Performance (`bench_scene_hot_paths`, plain nodes, `-o:speed`)

| Nodes | Frame (`RunScene`) before | after | Global transforms before | after |
|---|---|---|---|---|
| 500  | 1.09 ms | 0.020 ms | 0.091 ms | 0.003 ms |
| 2000 | 16.2 ms | 0.081 ms | 1.32 ms | 0.015 ms |
| 5000 | **100 ms** | **0.20 ms** | 8.54 ms | 0.046 ms |

Causes: every child lookup scanned one flat relationship array (O(n²) per frame); `GetChildren` heap-allocated a copy for every node at every traversal; rendering walked the whole tree once per layer (8×). Now there are indexed `childrenOf`/`parentOf` maps, non-allocating `GetChildrenView`, and one traversal bucketed by layer (`Scene_CollectRenderables`).

### Editor features that were broken or mocked

- Gizmos used the node's *local* position as world, so children jumped. Now world-space with parent conversion, and snapping in world space.
- Bounds and picking ignored rotation and texture origin and could pick the root. Rotated outlines are now shared by drawing and picking, with top-most-layer picking.
- No undo/redo. Added snapshot undo for every edit (inspector, gizmos, tree, dialogs).
- The inspector edited only transform + numeric script values. It now covers every reflected property of every node type (enums, bit sets, colours, strings), textures/audio/frames/timer/shapes/LDtk pickers, script attach/change/detach with all value types.
- *Add Node* placed nodes at root regardless of selection. They now go under the selection with unique names, and physics nodes start with a collision shape.
- Hierarchy: drag-and-drop re-parenting, context menu, filter, visibility toggles.
- Assets: drag textures/components/audio/scripts into the viewport.
- Project Settings: Cancel now discards edits. Gravity applies to the editor world. Virtual resolution and the scene list are editable.
- The Tilemap and Animation tabs were **mock UIs** (fake state, nothing edited). They've been removed; see open gaps.
- *Quit* didn't close the editor; Ctrl+N/Ctrl+D/Ctrl+A were advertised but unbound. All fixed.
- Export wrote to a hardcoded path inside the repo. It now writes next to the project (`<project>.ore`).

---

### Second pass: physics, resources, prefabs, scripting, LDtk, code editor

| Problem | Fix | Verified by |
|---|---|---|
| Physics bodies ignored the hierarchy (bodies under a moved/rotated parent were misplaced) | Bodies are created and synced from `globalPosition`/`globalRotation`; simulated transforms are written back into parent space (`Physics_SetWorldTransform`) | `test_physics_bodies_follow_the_hierarchy` |
| Textures and audio were never unloaded | `ResourceManager_Release*` frees at refcount 0 and reuses audio slots; Texture/Frame/AnimationPlayer/Sound/Music nodes release on destroy; the inspector releases on swap | `test_resources_are_released_with_their_nodes` |
| `AnimationPlayerNode` wasn't saved and had no UI | Saved/loaded (frame lists or sprite-sheet grid + range, fps, autoplay, reverse); Inspector section to add/edit animations; `animation_finished` event | `test_animation_player_round_trips` |
| Prefabs were copies | Instances store `"component": "<file>"` and are rebuilt from it (with root overrides); editing a component file updates every instance; Edit Component / Unlink in the inspector; children of an instance are locked | `test_component_instances_are_links`, `components.drive` |
| No Lua hot reload | Saved `.lua` files reload in place (module table swapped, instances keep state, new properties get defaults); syntax errors keep the old code running | `test_lua_hot_reload_updates_running_instances` |
| LDtk import was partial | External levels, all field types, entity tiles, parallax, backgrounds, visibility, tile custom data, colliders, entity spawning into linked components with field → script property mapping, live reload, Lua API, "Open in LDtk" | `test_ldtk_external_levels_fields_spawning_and_lua` (see `LDTK.md`) |
| Events were incomplete and unsafe from Lua | Every node type emits named events, all reachable from Lua (`on_<event>` methods, `node:connect/disconnect/emit`); listeners are snapshotted during dispatch; Lua connections are released with their node or script (no leaks, no dangling callbacks) | `test_lua_receives_node_events`, `test_area_and_collision_events_reach_lua` |
| Scripts could only be edited outside the editor | **Code tab** (see below) | `code_editor.drive` |

**Code editor.** Scripts open in a *Code* tab docked next to the Viewport (double-click a script, the Inspector's edit button, a hierarchy node's *Open Script*, double-click a `file.lua:line` console message, or *New Script*). It reuses odin_editor's buffer/undo, Lua highlighter and LSP client, with lua-language-server (`lua-language-server/`) loaded with `engine/definitions` for completion, signature help, hover, diagnostics and go-to-definition (F12 / Ctrl-click). Saving hot-reloads the running scripts.

---

### Third pass: editor workflow, signals, prefab overrides, remaining gaps

| Problem | Fix | Verified by |
|---|---|---|
| Linked prefab instances only kept root changes | Instances save a per-node diff against the component (`"overrides": {"Child/Path": {...}}`, keyed by child name path); unchanged values keep following the component file; Inspector lists overridden values with **Revert** (`component_overrides.odin`) | `test_component_child_overrides`, `prefab_overrides.drive` |
| Events couldn't be wired up in the editor | Godot-style **Signals** section in the Inspector: connect any event to a method on any node's script (new script created if needed); the handler is written into the script; connections are saved on the source node and dispatched at runtime; disconnect removes the generated handler (asks if it has code) (`engine/signals.odin`, `signals_panel.odin`) | `test_saved_signal_connections_call_script_methods`, `signals.drive` |
| Shortcuts were scattered and partly unbound; no command palette | One action table (`actions.odin`) drives keyboard dispatch, menus, the **command palette** (Cmd+Shift+P, Go to File Cmd+P, `:line`) and a generated **Keyboard Shortcuts** window; code-editor bindings follow Zed | `code_shortcuts.drive`, `scene_editing.drive` |
| No multi-select, copy/paste or align tools | Cmd/Shift-click in tree and viewport, viewport box select, multi-node gizmo moves, copy/cut/paste (also across editors via the clipboard), delete/duplicate selection, arrow-key nudge, align/distribute, F2 rename, select all (`scene_selection.odin`) | `scene_editing.drive` |
| No quit prompt for unsaved work; Esc quit the editor (raylib's default exit key) | Cmd+Q / window close ask to Save All / Don't Save / Cancel; Esc no longer quits | `scene_editing.drive` |
| Code editor lacked editing conveniences | Auto-closing pairs (insert, step over, delete together, wrap selection), find/replace bar (case/word/regex), multi-cursor (Cmd+D, Cmd+Shift+L, Cmd+Alt+arrows, Alt+click), line ops, go to line, LSP rename (F2), format (Cmd+Shift+I), references (Shift+F12), completion docs via `completionItem/resolve`, snippet tab stops, font size, reopen closed tab | `code_shortcuts.drive`, `code_editor.drive`, odin_editor `lsp` tests |
| Assets couldn't be referenced from scripts by dragging | Drop an asset on the code: its path; with Cmd: an exported **asset property** (`type = "texture"` / audio / scene / script / component / level / file) that the Inspector edits with a picker; dropping a node inserts `self.node:get_node("path")` | `signals.drive` |
| Only 6 of ~24 UI widget types could be created | Every UI widget type is in the node registry and the Add Node dialog | `test_every_node_type_round_trips`, `test_node_factory_creates_every_registered_type` |
| Scene-level properties had no UI | Scene section (root selected): background colour, draw bounds; the game clears with the scene's colour | build + manual |
| Simulation leaked Lua state into later runs | Simulate snapshots the Lua globals; Stop restores them and re-runs every module (fresh module-level locals) | `test_simulation_globals_are_restored` |
| The game runner was tied to the Asteroids demo | `Engine_RunProject` (engine/runner.odin) and a standalone `runner/` program; **File > Export Standalone Game** writes a folder with the runner, `game.ore` and the font | runner run on the demo project |
| Two resource caches | `AssetManager` is the file layer only (project dir / `.ore`); `ResourceManager` is the single texture/audio cache (the unused second cache was removed) | engine tests |
| No tilemap editor | `TileMapNode` (tileset, grid, run-length saved, optional merged colliders) with an Inspector palette and viewport paint / erase / flood fill, one undo step per stroke | `test_tilemap_paint_fill_save_and_colliders`, `tilemap.drive` |
| No animation timeline / property animation | Animation tab: frame strip (thumbnails, scrub, drag-reorder, drop textures to add, remove), play/stop preview that restores the scene, and keyframed **property tracks** on any float/int/vector/colour property of the player or its children (`engine/animation_tracks.odin`) | `test_animation_property_tracks`, `animation.drive` |
| Particle emitters were capped at 1000 particles (~140 KB each) | Ring buffer grows to ~2x `amount` (up to 20000) from the node's arena | `test_particle_emitter_grows_past_1000` |
| Box2D sync rewrote every body/shape property every frame | Shapes re-apply only when their parameter hash changes; body parameters only when changed | `test_physics_sync_applies_only_changes` |
| Modified-state checks re-serialized scenes | Edit versions: every recorded edit bumps the scene's version, undo/redo restore it, modified = version differs from the saved one | all drives |
| Hidden fallback to `assets/demo_project` in path resolution | Removed: projects resolve through the project directory only | engine tests, drives |
| Node creation cost (~3.5 µs, VM reservation + crypto UUID per node) | UUIDs from a seeded fast generator; destroyed nodes' arenas are recycled: respawning costs ~0.3 µs/node | `bench_scene_hot_paths` (create vs respawn) |

### Fourth pass: UI/UX

| Problem | Fix | Verified by |
|---|---|---|
| File menu lacked standard operations | New/Open Project (recents, folder browser, relaunch), Open File, Save (focused document), Save As (scene / script / component), Save All, Revert, Export submenu, Settings | `ui_ux.drive` |
| No editor settings; project settings were one small dialog | Settings dialog: General (Basic, Keymap with recording/conflicts/reset), Code Editor, Project (General, **Input**, Video, Audio, Export); editor settings persisted per user | `ui_ux.drive`, `test_project_input_actions_video_audio_export` |
| Input was a fixed enum queried by raw keys | Named project actions with key/mouse/gamepad bindings in project.json; Lua queries any action name | `test_project_input_actions_video_audio_export` |
| Video/audio/export settings didn't exist | Fullscreen, vsync, resizable, MSAA, high-DPI applied by the runner; master/music/SFX bus volumes; export name/folder/targets/compression/font | `test_project_input_actions_video_audio_export` |
| X/Y fields couldn't be linked; no reset to default | Link toggle on every vector field; reset button on every Inspector field (type defaults, script defaults, fixed defaults) | `ui_ux.drive` |
| Particle colours weren't saved; no colour-over-life editor | Colour ramp, start/end colours saved; Particles tab with sub-tabs, gradient stops editor and RGBA plot with draggable alpha, live preview | `test_every_node_type_round_trips`, `ui_ux.drive` |
| LDtk projects weren't assets | Levels section; add / drag a level into the scene, open in LDtk, import | `ui_ux.drive` |
| Few context menus | Context menus on assets, folders, scene tree (incl. empty space), code tabs, code text, console, templates, packages | `ui_ux.drive` |
| Prefab instances couldn't add/remove children; no way to push edits back | Instances save added and removed children (`$added` / `$removed` overrides); Apply Changes to Component; Save as New Component; component documents Save / Save As | `test_component_instances_add_and_remove_children`, `ui_ux.drive`, `components.drive` |
| No fit-to-view | Fit Scene (Home), Fit Game View (Shift+Home), Fit Selection (Shift+F), zoom menu | `ui_ux.drive` |

---

### Fifth pass: assets and LDtk

| Area | Change |
|---|---|
| Asset importer | **+** menu, multi-select system file dialog, OS drag & drop (files and folders; on the viewport also placed), content validation, per-file errors in Import Results, LDtk projects bring their tileset images |
| LDtk data | worlds, layer/entity/enum/level-field definitions, IntGrid value names, tile enum tags, full EntityRef references; one arena per project; all 68 LDtk sample/test files parse |
| LDtk node | world mode, per-value collision rules (solid / one-way / trigger), entity → component mappings, link rules (signal / parenting), LDtk's exact parallax, editor-only layer visibility, saved configuration |
| LDtk editor | **LDtk** bottom tab: Layers, Entities (Create Component), Collision, Links, Level Fields, Enums, World mini-map; reference arrows in the viewport |
| LDtk Lua | ~40 methods: worlds, levels, layers, IntGrid names/cells/collision, tiles and enums, entities by tag/iid, links both ways from any spawned node |

### Sixth pass: physics shapes

| Area | Change |
|---|---|
| Shapes follow node scale | every body's shapes are scaled by the node's world scale (per axis; mirrored; changes at runtime re-sync; dynamic bodies' mass follows); CharacterMover capsules too; LDtk colliders inherit their level's scale |
| Shape sync fixes | polygons and chains now update after creation; chain points keep their authored values (they were freed on attach) and use the shape's offset and rotation |
| Viewport shape editing | Edit Shapes: move / rotate / resize handles, polygon/chain/segment points (add, drag, remove), snapping, undo; type changes keep the footprint; selection outlines cover every shape |

### TODO_NOW pass

| Item | Change |
|---|---|
| Editor rendering | the viewport draws every layer from one traversal (it walked the tree once per layer) |
| Lua tooling | engine definitions compiled into the editor and written to `<project>/.ore/definitions`, plus `.luarc.json` (works outside the engine checkout and in VS Code); the language server is found next to the editor too; `/private` paths on macOS map to project paths; hidden files aren't packaged (`test_pack_skips_hidden_files`, `lua_tooling` drive) |
| Project types | `.ore/definitions/project_types.lua` generated from the project (input actions, scene names, node names, asset paths, LDtk names, script classes with properties); the API uses them (`Input.*` takes `InputAction`, `Scene.change_scene` a `SceneName`); regenerated after changes (`lua_types` drive) |
| Materials | shader + blend mode + parameters on any node (`engine/material.odin`); 5 built-in shaders; project `.fs` shaders (cached, hot reloaded, read through the asset manager so packages work); uniforms parsed with hints for the Inspector; saved with the scene; Lua `set_shader`/`set_shader_param`/`set_blend_mode`; Shaders asset kind, New Shader template, drop-to-apply (`test_materials_uniforms_serialization_lua`, `materials` drive) |
| 2D lighting | `LightNode` (point/spot, colour, energy, radius, falloff), scene ambient; a light map (shader-drawn lights, shadows cut from physics shapes) multiplied over the world layers, in the game and the editor (preview toggle); Scene settings shown with nothing selected, ambient presets; Lua `Scene.set_ambient`, `light_set_*` (`test_lighting_scene_lights_ambient_lua`, `lighting` drive). Normal maps: later |
| Tweens & easing | `Tween.to(node, property, value, duration, ease, {delay, loops, yoyo, on_complete})` on any reflected property or `shader:<param>`, cancel / cancel_all / is_running / ease; 26 easing curves shared with animation track keys (timeline: right-click a key > Easing, saved as a 6th key element); sprites gained a `tint` (`test_tweens_and_easing`, `animation` drive) |
| Animation events & crossfade | Method-call tracks (`@call`, keys `[frame, "method"]` -> `self:<method>(frame)` on the target script) and audio tracks (`@audio`, keys `[frame, "path"]`), fired as frames advance; `animation_play(name, blend)` crossfades property tracks from the previous animation; timeline Add Track > Events with per-key method/sound fields (`test_animation_events`, `animation` drive) |
| Culling | world layers skip nodes whose bounds are outside the camera view (`engine/culling.odin`: sprites and tile maps have bounds; unknown nodes always draw); tile maps draw only the visible cell range, LDtk only visible tiles; the editor culls to its own view. Profiler tab: drawn / culled counts. `test_view_culling` |

## 2. Open gaps (prioritized)

### P2 — features

1. **First-time node creation** still reserves a virtual-memory arena per node (~3.5 µs; respawns reuse arenas and cost ~0.3 µs). *Approach:* a per-NodeManager pool allocator instead of per-node arenas.
2. **List-like UI widgets' items** (dropdown/list/table rows) aren't editable in the Inspector; they keep their factory defaults or are set from Lua.
3. **Tile maps have one layer and no auto-tiling**; use several TileMapNodes, or LDtk for rule-based maps.
4. **Property tracks interpolate linearly per frame**; no easing curves or method-call tracks.
5. **Animation timeline**: sprite-sheet animations show their frame range but can't be reordered (frame animations can).
6. **Export targets**: only the runner for the platform the editor runs on is built; other targets need a build on that platform (the `.ore` package itself is portable).
7. **Renaming or deleting an asset** doesn't update scenes, scripts or components that reference it (the scene list in project.json is updated).
8. **Native file dialogs** are used for importing assets (macOS verified; Linux zenity/kdialog and Windows PowerShell untested); Open Project still uses the editor's own folder browser.
9. **LDtk one-way platforms** assume gravity pointing down (+y): they block bodies coming from above. Top-down games should use Solid or Trigger.
10. **LDtk world mode** loads every level of the world at once (no streaming of neighbours by camera distance); for large GridVania worlds load a level at a time and switch with `ldtk_level_at` / `ldtk_load_level`.
11. **LDtk level data is read-only in the editor** by design (edit in LDtk; saving reloads). Entity tiles from LDtk's embedded icon atlas aren't drawn.
12. **Non-uniform scale on round shapes**: a circle takes the larger scale axis and a capsule its radius from x (Box2D has no ellipses); a rotated box under non-uniform node scale stays a rectangle (no skew).

---

## 3. How to verify

```bash
odin test engine -define:ODIN_TEST_THREADS=1   # unit, round-trip, leak and benchmark tests
./scripts/editor_drive.sh                      # all UI test-drives (or: task editor:drive)
```

