# TODO_NOW

Work list for the engine + editor, in order. Each item: code, test (engine
test and/or editor drive), verify (screenshots for UI), document, commit.
Multithreading (job pool, Box2D tasks, background loading) is deliberately
out of scope here.

## Phase 1 — Quick wins

- [x] 1.1 Editor viewport renders in one tree pass (`Scene_CollectRenderables`), not one walk per layer
- [x] 1.2 Culling: skip nodes whose bounds are outside the camera view (game and editor); tile maps and LDtk draw only visible tiles
- [x] 1.3 Lua language server: ship engine definitions with the editor (not the repo checkout); write `.luarc.json` into each project
- [x] 1.4 Generated project types (`.ore/project_types.lua`): input action names, scene/asset paths, node names per scene, script classes with their properties, signals, LDtk entities/enums/levels, components

## Phase 2 — Core engine features

- [x] 2.1 Shaders & materials: per-node material (shader + uniforms), blend modes, Inspector editing, Lua `set_shader_param`
- [x] 2.2 2D lighting: light map render target, point/spot lights, ambient colour, occluder shadows from collision shapes; normal maps later
- [x] 2.3 Tweens & easing: `Tween.to(node, "position", {x, y}, 0.3, "out_quad")`, easing curves on animation tracks
- [x] 2.4 Animation tracks: method-call and audio tracks, blending/crossfade between animations
- [x] 2.5 State machine node: states, transitions, conditions, Lua `on_enter_<state>`/`on_exit_<state>`, drives the AnimationPlayer
- [x] 2.6 Save/load: `Save.set/get/flush` JSON in the platform user-data folder

## Phase 3 — Export

- [x] 3.1 Prebuilt runners per platform shipped with the editor; export copies the runner + `.ore` (no compiler needed), name and icon
- [x] 3.2 macOS `.app` bundle (Info.plist, icon, `.ore` in Resources, universal binary); optional codesign/notarize step
- [x] 3.3 Windows packaging (icon, version info, no console in release); Linux AppImage
- [ ] 3.4 Web (emscripten): raylib + Box2D + Lua to wasm, `.ore` preloaded, click-to-start audio
- [ ] 3.5 Export presets per target (icon, version, window, include/exclude, debug/release) in `project.json`

## Phase 4 — Performance (single-threaded)

- [ ] 4.1 Node diet: event subjects out of every node (side table), shared vtables, per-type pools instead of an arena per node; split hot transform data
- [ ] 4.2 Batching: sort draws by texture per layer, texture atlases, cache static LDtk/tile layers in render textures
- [ ] 4.3 `#soa` + SIMD for particles and tile layers (verify the `#soa` compiler issue first)
- [ ] 4.4 Editor: incremental undo/modified tracking (change counters, not whole-scene JSON); cache per-frame inspector/LDtk work
- [ ] 4.5 Extend `bench_scene_hot_paths` to rendering and scripts; record baselines in GAPS.md

## Phase 5 — Engine features (rest)

- [ ] 5.1 Audio: positional audio, bus mixer (volume, low-pass/reverb), music crossfade, one-shot pooling
- [ ] 5.2 Physics: joints as editor nodes, one-way platforms for StaticBody, named collision layers
- [ ] 5.3 Navigation: A* on tile maps / LDtk grids
- [ ] 5.4 Text: bitmap/SDF fonts, rich text, dialogue box; localization string tables
- [ ] 5.5 Scene flow: transitions, background scene loading (main thread, incremental), pausing subtrees
- [ ] 5.6 Extras: parallax node, 9-slice sprite, trail/line renderer, screen-space post effects

## Phase 6 — Editor workflows & UX

- [ ] 6.1 Tooltips & docs on every Inspector property (type, range, doc from tags); Inspector help pane
- [ ] 6.2 Multi-edit (mixed values shown as —)
- [ ] 6.3 Viewport: rulers/guides, smart snapping to node edges/centres, pivot editing, per-node lock/hide, show-all-colliders
- [ ] 6.4 Scene tree: search by type/tag, groups/tags, reorder by drag, cross-scene copy/paste
- [ ] 6.5 Asset browser: thumbnail grid, real folders (create/move/rename with reference updates), find usages, per-asset import settings
- [ ] 6.6 Sprite-sheet slicer → frame animations
- [ ] 6.7 Play-in-editor: remote scene tree of the running game, frame step, hot reload while playing
- [ ] 6.8 Layout presets / workspaces and reset layout
- [ ] 6.9 Welcome / new-project window with templates; icons for every node type; empty-state guidance

## Phase 7 — Code editor & Lua

- [ ] 7.1 Node subtypes in definitions (`TextureNode`, `CameraNode`, …) so methods complete per type
- [ ] 7.2 Definitions checked against the registered Lua bindings (test fails on drift)
- [ ] 7.3 Per-line token cache keyed on buffer version; measure with a 10k-line file
- [ ] 7.4 Overlays: hover / signature / completion docs as bounded, wrapped, scrollable popups clamped to the editor
- [ ] 7.5 Lua debugger: breakpoints, stepping, locals (debug hooks)
