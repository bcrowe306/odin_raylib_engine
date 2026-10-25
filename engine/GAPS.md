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
| State machine node | `StateMachineNode`: states (each plays an animation on an AnimationPlayer, auto-found as sibling/child), transitions from a state or any state with crossfade blend and AND-ed conditions (param true/false/==/!=/>/<, trigger, animation finished, after N s); `on_enter_<state>`/`on_exit_<state>` on the machine's and parent's scripts, `state_changed` event; Lua `sm_set/get/trigger/travel/state/previous/time/start/stop`; Inspector editor with From Animations (`test_state_machine`, `state_machine` drive) |
| Save / load | Lua `Save` module (`set/get/has/delete/keys/clear/flush/slot/path`): plain Lua values as JSON in the platform user-data folder (`~/Library/Application Support/<project>`, `%APPDATA%`, XDG), read on first use, written on flush and on quit (temp file + rename), slots as separate files, damaged files ignored; runner `--user-data <dir>`; editor Game > Save Data (open folder / delete) (`test_save_data`; runner end-to-end) |
| Prebuilt runners | Export copies a prebuilt runner per target from `runners/<platform>/` (next to the editor, or `bin/runners/`) into `<output>/<platform>/` as the executable name, with `game.ore` and the font - no compiler at export time; `scripts/build_runners.sh` builds this platform's (release); without one the editor builds it once; Export page lists runner availability; project `icon` (PNG) set as the window icon by the runner (`test_project_icon_and_runner_args`, `export_standalone` drive) |
| macOS .app | `<output>/macos/<Name>.app`: Info.plist (bundle ID, version, icon), runner in MacOS/, libraries in Frameworks/, game.ore + font + AppIcon.icns (written from the project PNG, PNG-encoded entries 16-1024) in Resources/; the runner finds its game in ../Resources; codesign (ad-hoc default, Developer ID with hardened runtime), optional notarytool + stapler in the background. Runners now ship Homebrew's liblua as @rpath/liblua.dylib (exported games no longer need Homebrew); universal binary when x86_64 raylib/Box2D/Lua exist (not with the stock vendored libs: arm64 only) (`export_standalone` drive: plist lint, codesign --verify --deep, app runs from / with Lua from the bundle) |
| Windows / Linux packaging | Windows: `-subsystem:windows` release runner + `lua54.dll`; project icon (RT_ICON/RT_GROUP_ICON, PNG 16-256) and VERSIONINFO written into the exe via the Win32 resource API (`editor/winres`, Windows hosts; type-checked with `-target:windows_amd64`). Linux: AppDir (AppRun, .desktop, icon, usr/bin) and `.AppImage` with appimagetool. Format builders (`Icon_Images`, `Ico_Write`, `Ico_GroupDirectory`, `VersionInfo_Resource`, `Export_LinuxAppDir`) in engine/export_formats.odin (`test_export_formats`; `export_standalone` drive with stand-in runners). Not run on real Windows/Linux machines yet |
| Export presets | `export.presets` in project.json: per preset platform, executable, output folder, version, icon, window title/size, fullscreen, include/exclude patterns, debug runner (`runner-debug` from build_runners.sh); the preset's project.json (overrides applied) and file filter go into its own game.ore (`OrePackage_CreateFromDirectory` filter + overrides); Export page preset editor (add / duplicate / remove, export one or all); projects without presets export one per target (`test_export_presets`, `export_presets` drive) |
| Node diet | The six tree events moved out of every node into `node.events` (made on first subscribe: `Node_Subject` / `Node_NotifyEvent`): `size_of(Node)` 856 -> 344 B. Node arenas are reserved on the first allocation (`node.allocator` unchanged for callers). `place_under` / `RemoveNode` / removal no longer scan lists (`inTree`, `removing`, `managerIndex` flags; parents' child lists filtered once per batch), so building and clearing big scenes is linear. 5000 nodes (bench_scene_hot_paths, -o:speed): create 21.9 -> 2.5 ms, TextureNodes via the registry 39.1 -> 4.6 ms, destroy all 19.2 -> 1.4 ms. Not done: shared vtables and per-type pools (game code assigns node procs and allocates from `node.allocator`), splitting transforms (the global transform pass is 0.04 ms for 5000 nodes) |
| Draw batching & tile caches | (1) Order-preserving draw reordering (batching.odin): plain sprites join an earlier run with the same texture when nothing in between overlaps them (barriers for draws without bounds), so pictures are pixel-identical. (2) raylib batches multi-buffered (8 vertex buffers): each texture/blend/shader flush no longer waits for the GPU (macOS GL synced on every flush). (3) Tile layers (TileMapNode, LDtk tile/auto layers) with >= 2048 tiles in view are drawn from 512 px render-texture chunks (tile_cache.odin), premultiplied, rebuilt per chunk on edits, LRU-capped at 96. Runner `--bench N` / `--no-render-cache` and scripts/make_bench_project.py measure it (update+draw per frame, M2): 5000 sprites over 4 textures 7.8 -> 0.93 ms (overlapping: 8.4 -> 3.9 ms), 400x400 tile map zoomed out 4.8 -> 0.12 ms, demo main scene 0.87 -> 0.17 ms. Identical screenshots without/with (sprites, tiles at 1:1; zoomed-out tiles differ only in which texel nearest sampling picks). Not done: texture atlases (shaders read the sprite's own UVs; batching recovers most of it) |
| Particles (`#soa` / SIMD checked) | `#soa[dynamic]` works with this compiler (2026-03: dynamic arrays, `for &p`, pointers, custom allocators) but made the particle update slower (0.086 vs 0.073 ms for 5000 particles: each update touches ~15 of a particle's fields), so particles stay an array of structs; at ~15 ns per particle SIMD isn't worth it, and tile layers are now drawn from cached chunks (4.2). The real costs were elsewhere: emission used the OS (crypto) random generator per number (now a fast generator seeded once: update 0.112 -> 0.072 ms), circles were drawn with 36 triangles each (now segments from the radius, 0.5 px error: 5000 circles 5.0 -> 1.4 ms per frame), rectangle particles were drawn twice (a stray unrotated copy; 0.76 -> 0.43 ms), and rendering copied each particle (`bench_particles`; runner `--bench` on bench_particles scenes) |
| Editor per-frame work & undo | Profiled the editor on a 5000-node scene (`sample`): about 41% of the main thread was busy, now about 11% (the rest waits for vsync). The asset browser and pickers walked the project folder several times a frame and the Packages list stat-ed every file next to the project: now one cached scan (editor/project_files.odin), refreshed when the editor changes files (the `Lua_MarkProjectTypesDirty` hook) or every second. The Scene panel skips runs of off-screen leaf rows as one spacer (still registered for drives) and no longer allocates a child list per row. Undo snapshots are stored as content-defined chunks shared between snapshots (editor/undo_store.odin) (ten snapshots of the ~6 KB demo scene: 23 KB instead of 60 KB; larger scenes share proportionally more) and a snapshot identical to the last one (a double-click activating a field twice) is skipped, so one edit is one undo step. Modified tracking already used change counters. Scene JSON for 10k nodes: serialize 20 ms, load 39 ms (bench_scene_hot_paths) |
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
| Audio | One-shot voices (sound aliases sharing samples, up to 8; `Audio.play_sound` overlaps 4, SoundNode **Voices**), positional SoundNodes (distance falloff + pan from the camera or `Audio.set_listener`; `Audio.play_sound_at`), bus volumes applied live (`Audio.set_bus_volume`), a master low-pass and Freeverb-style reverb (a mixed-audio processor: raylib's per-stream callbacks carry no user data, so effects can't keep separate state per bus), MusicNode fades and `Audio.crossfade` (`test_audio_mixing` checks the DSP, `test_music_fades_and_buses`; runner smoke test with the effects on). Not listened to on speakers in testing |
| Physics extras | JointNode (revolute, distance, prismatic, weld, wheel, motor between two body nodes; Body A/B pickers, only the active type's parameters in the Inspector, live parameter changes wake the bodies, defaults sized for pixel-scale masses), One Way StaticBody (engine-wide one-way registry + pre-solve callback, moved out of LDtk, "top" follows rotation), named collision layers (project.json `physics.layers`, shown in shape layer lists, `set_collision_layer` / `set_collision_mask` / `Physics.layer_name`; scenes keep stable `LayerN` names), `node:set_property` / `get_property` for any Inspector property (`test_one_way_platform`, `test_joint_node`, `test_collision_layer_names`, `physics_extras` drive) |
| Navigation | A* on TileMap / LDtk grids (engine/navigation.odin): walls from painted tiles (solid maps) or Solid IntGrid rules, 8-way without corner cutting (or 4-way), exact grid line-of-sight smoothing, cached grids rebuilt on map changes; Lua `map:nav_find_path`, `map:nav_is_walkable`, `Navigation.find_path` (`test_navigation_tilemap`, `test_navigation_ldtk`; `bench_navigation`: 256x256, 20% walls, 3.8 ms per corner-to-corner path) |
| Text & localization | Fonts: project TTF/OTF at any size (LoadFontFromMemory, works from .ore), SDF fonts (distance-field atlas + shader), BMFont .fnt (disk), Latin-1 + typographic punctuation; TextNode (wrapping, alignment, rich text `[color] [size] [wave] [shake]`, typewriter + `revealed`, localized keys, rotation/scale, culling bounds); DialogueNode (speaker, typewriter, advance action, `line_shown` / `finished`); localization CSV tables in locale/ (quotes, BOM, several files, hot reload), `tr(key, args)`, `Locale.set/get/languages`, project `language`; editor font picker, Add Node entries (`test_text_layout`, `test_localization_and_text_nodes`, `text` drive; runner screenshot of every font kind) |
| Scene flow | Transitions (`Scene.change_scene(name, {transition = "fade"/"wipe_*"/"circle", duration, color})`: cover, switch once preloaded, uncover), main-thread incremental preloading of a scene's textures / sounds / music / fonts (and its components') within ~4 ms a frame, held until the scene loads (`Scene.preload`, `preload_progress`), pausing (`Engine.set_paused`, node Pause Mode Inherit/Pausable/Always, per-subtree Paused; paused nodes skip updates and tweens, their bodies are disabled, physics stops while the game is paused; Inspector fields, saved) (`test_pausing`, `test_scene_transitions_and_preload`, `scene_flow` drive; runner screenshot mid-iris) |
| Visual extras | NineSliceNode (borders kept at any size), ParallaxNode (camera factor, repeat X/Y, self-scroll), LineNode (local points, width, closed, rounded; Inspector point list; `line_set_points` / `line_add_point`), TrailNode (fading tapering ribbon, rlgl strip), PostEffectNode (Material shader over the whole screen, chained ping-pong targets; built-in vignette / crt / pixelate / chromatic, auto `resolution` uniform; runner and viewport preview) (`test_visual_extras`, `visual_extras` drive; runner screenshot) |
| Inspector help | Every reflected property has a help line (`engine/property_docs.odin`, by declaring struct then shared field name); tooltips show doc, type, range, default and the Lua property name; help pane at the bottom of the Inspector (last hovered property, else the node type's description; View > Inspector Help) (`test_property_docs` fails on an undocumented property; `inspector_help` drive) |
| Multi-edit | Several nodes selected: the Inspector shows the properties they share (Transform, Layer, Pause, reflected properties of the same name and type), "—" for differing values, edits and resets apply to all (pairs per axis, flag sets per flag); banner with the count (`multi_edit` drive) |
| Viewport tools | Rulers (adaptive world ticks, mouse marker), guides dragged from the rulers (saved in the scene as `"guides"`, removed by dropping on a ruler), smart snapping of the moved bounds' edges / centre to other nodes and guides, Alt-drag pivot editing (texture / animation origin, children, line points, shapes compensated), per-node viewport lock and editor-only hide (`editor_locked` / `editor_hidden`, subtree, ignored by the game; tree icons, Cmd+L / Cmd+Shift+H), Show All Colliders (`test_editor_guides_and_flags`, `viewport_tools` drive) |
| Scene tree | Node tags / groups (`tags` saved, `add_tag` / `has_tag` / `Scene.find_by_tag`, Inspector Tags section, `NodeTag` in the generated Lua types), tree filter terms (name, `#tag`, `t:type`), reorder by dropping on a row's edge, paste into another scene at the same world positions, Copy / Move to Scene (`test_node_tags`, `scene_tree` drive) |
| Asset browser | Folders view (real folders, empty ones too) and a thumbnail grid; move by drag / rename / new / delete folders with every reference updated (`AssetPath_Rewrite`: project JSON and Lua files, `project.json` through the config, loaded scenes with unsaved edits and their undo history, open scripts reopened); Find Usages; per-texture import settings (filter, wrap, mipmaps) in `project.json` applied at load (`test_asset_path_rewrite`, `asset_folders` drive) |
| Sprite sheets | Sprite Sheet Slicer window (columns / rows or cell size, margin, spacing, pick cells by click / drag / Shift-range, per-row animations, live preview, new or selected AnimationPlayer); sheet animations with margin, spacing and an explicit cell list (`SpriteSheet_CellRect`, saved as `margin` / `spacing` / `cells`) (`test_sprite_sheet_cells`, `sprite_slicer` drive) |
| Play-in-editor | Editor link (`--editor-link`, stdin commands / `@ore:` replies: tree, inspect, set, pause, resume, step, reload-scene), Game tab with the running game's tree, live editable properties, pause / one-frame step (frozen frames still draw); saved scenes reload in the game; images hot reload (game and editor), scripts already did; `Scene.reload` / changing to the current scene restarts it (it used to do nothing) (`test_editor_link`, `remote_game` drive) |
| Workspaces | Layout presets built with the dock builder (Default, Level Design, Scripting, Animation), user workspaces saved / loaded as ImGui layout text, Reset Layout (`workspaces` drive) |
| Welcome & templates | Welcome window (recent projects, open, first steps, show at startup), new projects from Empty / Platformer / Top-down / Menu templates with generated placeholder images (each verified to play), a distinct icon per node type, empty-state hints (scene tree, viewport, console) (`welcome` drive) |
| Typed Lua nodes | A definitions class per node type (`---@class CameraNode : Node`, mixins `TextHolder` / `NavGrid`) holding its own methods; generated overloads of `Scene.find_node` / `Node:get_child` per project node name returning its type; `self.node` typed per script by the nodes it is attached to (`lua_node_types` drive) |
| Lua definitions in sync | `test_lua_definitions_match_bindings`: every node method and module function registered in Lua is declared in `definitions/engine_api.lua` and every declared one is registered (fails on drift either way) |
| Code tab token cache | Per-line tokens cached by (text hash, start state): an edit re-tokenizes only changed lines (shifted lines still hit), drawing reuses tokens; 10k-line file 20.4 ms -> 1.8 ms per edit (`code_big_file` drive, `scripts/gen_big_lua.py`) |
| Code tab overlays | Hover, signature help and completion docs drawn as bounded boxes (max 560 x 260) inside the Code area, markdown (code fences in the code font) wrapped, mouse-wheel scrolling with a scroll bar, hover kept while the mouse is on it, no clicks / wheel through to the code; widest-line width cached per edit (was every frame) (`code_overlays` drive) |
| Lua debugger | Breakpoints from the Code tab gutter, sent over the editor link; a line hook (only while debugging) pauses the game in the script and reports file, line, call stack (names from the definition line for engine-called functions) and locals (tables one level, nodes as Type(Name)); continue / step over / into / out (F8, F10, F11, Shift+F11), locals per frame, breakpoints changed while running; the paused game keeps handling window events (`test_lua_debugger`, `lua_debugger` drive) |
| Themes & UI polish | Editor themes (Default, Dark, Mid-day, Light presets; per-colour editor with live preview) driving the whole palette (lines, popups, syntax colours adapt to light themes); editor settings in `settings.ini` (core:encoding/ini; JSON migrated once); panel headers on one row with same-size buttons; crisp ruler numbers (own font at native size, whole pixels, rotated on the left ruler); no Scene JSON tab; scene / component names without extensions; Welcome window on its own surface (`ui_theme` drive) |
| Animation player editing | Per-animation range (start / end over the source frames, saved for frame animations too; header handles, fields, menu), reverse and FPS (0 = the player's; `AnimationPlayerNode_SetFPS` sets the player's), default animation on load (`default_animation`), frame selection with delete / copy / paste (buttons, menu, Delete / Cmd+C / Cmd+V owned by the focused timeline), images and sheet cells (`engine/animation_edit.odin`: `test_animation_editing`, `animation_player` drive) |

## Performance baselines

`scripts/bench.sh [engine|rendering|editor]` (`task bench`) runs every
benchmark:

- **engine** (no window): `bench_scene_hot_paths`, `bench_particles`,
  `bench_scripts`, `bench_navigation` (`engine/perf_bench_test.odin`).
- **rendering**: the runner's `--bench 300` (30 warm-up frames, then 300
  uncapped: no vsync, no frame cap) on the scenes of
  `scripts/make_bench_project.py`, with and without the render caches.
- **editor**: `tests/bench/editor.drive` on the same project - the drive's
  `bench <frames> <label>` times uncapped frames by phase
  (`editor/frame_timing.odin`; the Profiler tab shows the same phases live).

**Profiling** (`engine/profiling.odin`): build with `-define:ORE_PROF=true`
(without it the zones compile to nothing) and pass `--prof trace.spall`
(`--prof-skip N`, default 30; `--prof-frames N`, default 300, 0 = until
exit) to the runner, the Play binary or the editor. Zones cover the frame
(input, physics, scene update, transforms, render collect / cull / draw,
lighting, present; the editor's phases and panels); open the trace in
https://gravitymoth.com/spall/ or sum it with `scripts/spall_summary.py
trace.spall`. The same builds count heap allocations and the temp arena per
frame (the Profiler tab, the [bench] lines). E.g.:

    odin build runner -o:speed -define:ORE_PROF=true -out:/tmp/prof_runner
    /tmp/prof_runner /tmp/ore_bench --scene scenes/bench_ysort.scene.json --bench 300 --prof /tmp/ysort.spall
    scripts/spall_summary.py /tmp/ysort.spall

**Leaks** (`engine/mem_track.odin`): `-define:ORE_MEM_TRACK=true` puts the
heap of the editor, the runner or the Play binary through a tracking
allocator: every 600 frames the live heap and the sites that grew since
the last report, at exit what is still allocated and any bad frees. The
game frees everything (bench scenes: no growth from frame 600 to 1200, 0 KB
at exit, no bad frees); the editor keeps a few process-lifetime tables to
exit. Don't profile these builds: tracking is slow.

Recorded 2026-10-24 on an Apple M2 Pro (macOS), Odin dev-2026-03,
`-o:speed`, at the start of the optimization branch. Two runs agree within
~3% on CPU times (update+draw, editor phases); whole-frame times under 2 ms
vary by up to ~25% (they include waiting for the GPU) - compare CPU times.

Earlier baselines (2026-10-22) read the whole frame as "vsync-bound at
~16.8 ms": it was the project's `target_fps` (60), applied when the project
loads, after the runner had turned the cap off. The runner now turns it off
again after loading (`--bench`, and `--uncapped` for playing uncapped with a
frame-time readout). At 60 FPS the CPU also idles between frames and clocks
down, so those CPU times read high too.

| Engine (no window) | 500 nodes | 2000 nodes | 5000 nodes |
|---|---|---|---|
| Create plain nodes | 0.35 ms | 1.05 ms | 2.47 ms |
| Create TextureNodes (registry) | 0.51 ms | 1.77 ms | 4.54 ms |
| Destroy all | 0.13 ms | 0.45 ms | 1.47 ms |
| Respawn | 0.14 ms | 0.60 ms | 1.66 ms |
| Global transform pass | 0.004 ms | 0.019 ms | 0.044 ms |
| RunScene frame (no window) | 0.035 ms | 0.093 ms | 0.288 ms |

`size_of`: Node 440 B, TextureNode 488 B, DynamicBodyNode 752 B.

| Scene JSON | 1000 nodes | 4000 nodes | 10000 nodes |
|---|---|---|---|
| Size | 251 KB | 1006 KB | 2518 KB |
| Serialize (save, undo snapshot) | 2.4 ms | 8.6 ms | 21.7 ms |
| Load (open, undo restore) | 4.0 ms | 15.8 ms | 41.0 ms |

| Simulation | Per frame |
|---|---|
| 5000 particles (83 emitted/frame) | 0.074 ms |
| 1000 Lua scripts `update(dt)` (get/set position) | 0.49 ms (0.49 us each; 0.33 on 2026-10-22) |
| A* path, 256x256 grid, 20% walls, corner to corner | 3.6 ms per path |

The Lua regression: every engine call from Lua now looks its script
manager up in the registry by name (`Script_Context`, for the engine's
allocator and logger); caching it measured 0.41 ms - about half of it.

| Rendering (runner `--bench`), CPU update+draw / whole frame | Cached | `--no-render-cache` |
|---|---|---|
| 5000 sprites, 4 textures, separate | 0.95 / 1.3 ms (750 fps) | 5.0 / 6.4 ms |
| 5000 sprites, 4 textures, overlapping | 4.0 / 4.5 ms (220 fps) | 5.0 / 6.3 ms |
| 400x400 tile map at zoom 0.25 | 0.12 / 1.4 ms (730 fps) | 4.3 / 5.5 ms |
| 5000 rectangle particles | 0.41 / 0.9 ms (1100 fps) | 0.41 / 1.3 ms |
| 5000 circle particles | 1.3 / 1.8 ms (570 fps) | 1.2 / 2.2 ms |
| 24 shadow-casting lights, 300 static boxes | 4.1 / 4.6 ms (220 fps) | 7.1 / 8.2 ms |
| 1000 dynamic bodies + sprites, falling into a pit | 1.8 / 3.0 ms (330 fps) | 2.0 / 3.0 ms |
| 1000 sprites, each moved by a Lua `update(dt)` | 0.97 / 1.6 ms (640 fps) | 1.6 / 2.6 ms |
| 3000 Lua-moved sprites in a y-sorted parent | 7.8 / 9.2 ms (110 fps) | 9.1 / 10.3 ms |
| Demo main scene | 0.07 / 0.6 ms (1650 fps) | 0.18 / 1.1 ms |

(`--no-render-cache` turns off draw reordering, tile chunks and multi-buffered
batches - the pre-4.2 renderer, with the 4.3 particle fixes.)

| Editor (`tests/bench/editor.drive`), ms per frame | Whole | Poll | UI | Viewport | Draw | Present |
|---|---|---|---|---|---|---|
| Demo main scene | 2.67 (375 fps) | 0.01 | 0.38 | 0.09 | 1.43 | 0.77 |
| 5000 sprites | 13.4 (75 fps) | 0.03 | 9.64 | 0.45 | 1.74 | 1.56 |
| 5000 sprites, Simulate | 13.3 (75 fps) | 0.03 | 9.67 | 0.54 | 1.74 | 1.37 |
| 400x400 tile map | 2.67 (375 fps) | 0.01 | 0.36 | 0.16 | 1.41 | 0.73 |
| 5000 particles, Simulate | 3.08 (325 fps) | 0.01 | 0.36 | 0.43 | 1.47 | 0.81 |

UI is building the panels (ImGui) without the viewport; Draw is submitting
ImGui's draw lists; Present is the swap (waiting for the GPU). Leads for
the optimization work: UI with a 5000-node scene (only ~7 scene rows are on
screen), Draw's ~1.4 ms even for an empty scene, the y-sort scene, the
lights.

### Optimization round 1 (2026-10-24, perf/optimization)

Found with the zones and `sample` (macOS); each fix measured on its own.

| | Before | After | Change |
|---|---|---|---|
| Editor, demo scene (whole frame) | 2.67 ms (375 fps) | 0.86 ms (1170 fps) | ImGui's lists from GPU buffers, uploaded once per frame (draw 1.43 -> 0.07 ms) |
| Editor, 5000 sprites | 13.4 ms (75 fps) | 2.57 ms (390 fps) | + the Scene Node Breakdown table builds its visible rows only (UI 9.6 -> 1.4 ms) |
| Editor, 5000 particles simulating | 3.08 ms | 1.26 ms | (the ImGui draw) |
| Y-sort, 3000 Lua-moved sprites (CPU) | 7.8 ms | 2.6 ms | stable merge sort (core:slice's stable sort is O(n^2)): collect 4.6 -> 0.26 ms; + Lua below |
| 24 shadow-casting lights (CPU) | 4.1 ms | 2.9 ms | one quad per edge, culling off; only edges facing the light (same pixels) |
| 1000 Lua `update(dt)` (no window) | 0.49 ms | 0.32 ms | script manager in the Lua state's extra space; node references by slot + generation, not by hashing the UUID; the node metatable by registry index |
| 1000 Lua-scripted sprites (CPU) | 0.97 ms | 0.70 ms | (Lua) |

Heap allocations per frame in steady state: the game 0; the editor ~0 (the
drive harness copied every widget id to the heap each frame: 5000+ with a
5000-node scene, now per-frame arenas).

Still open: overlapping sprites with interleaved textures (3.3 ms of draw
for 5000: every sprite a texture switch - needs atlases); the children
lists are a map lookup per node per walk (`GetChildrenView`), and the update
walk copies each node's children (`GetChildrenTemp`); a Lua call still
copies the context and checks the metatable; lights still switch render
targets twice per light.

| Code tab, 10,000-line Lua file (`code_big_file` drive, debug editor) | Per edit |
|---|---|
| Line states, re-tokenizing every line (before 7.3) | 20.4 ms |
| Line states from the per-line token cache (7.3) | 1.8 ms (0 lines re-tokenized after warm-up; 11x) |
