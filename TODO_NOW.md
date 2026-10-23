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
  - **Blocked (2026-10-22), needs your go-ahead:** emscripten isn't installed (and the vendored `raylib/wasm` folder is empty, so raylib and Lua need web builds from source); `core:os` panics on js/wasm, so the engine needs a filesystem layer for its ~80 `os.` calls; and the engine imports `ui/`, whose `native_dialog.odin` uses `posix.popen` (not on wasm) - that file needs a `#+build !js` tag or a wasm stub, which is your code.
- [x] 3.5 Export presets per target (icon, version, window, include/exclude, debug/release) in `project.json`

## Phase 4 — Performance (single-threaded)

- [x] 4.1 Node diet: event subjects out of every node (side table), shared vtables, per-type pools instead of an arena per node; split hot transform data
- [x] 4.2 Batching: sort draws by texture per layer, texture atlases, cache static LDtk/tile layers in render textures
- [x] 4.3 `#soa` + SIMD for particles and tile layers (verify the `#soa` compiler issue first)
- [x] 4.4 Editor: incremental undo/modified tracking (change counters, not whole-scene JSON); cache per-frame inspector/LDtk work
- [x] 4.5 Extend `bench_scene_hot_paths` to rendering and scripts; record baselines in GAPS.md

## Phase 5 — Engine features (rest)

- [x] 5.1 Audio: positional audio, bus mixer (volume, low-pass/reverb), music crossfade, one-shot pooling
- [x] 5.2 Physics: joints as editor nodes, one-way platforms for StaticBody, named collision layers
- [x] 5.3 Navigation: A* on tile maps / LDtk grids
- [x] 5.4 Text: bitmap/SDF fonts, rich text, dialogue box; localization string tables
- [x] 5.5 Scene flow: transitions, background scene loading (main thread, incremental), pausing subtrees
- [x] 5.6 Extras: parallax node, 9-slice sprite, trail/line renderer, screen-space post effects

## Phase 6 — Editor workflows & UX

- [x] 6.1 Tooltips & docs on every Inspector property (type, range, doc from tags); Inspector help pane
- [x] 6.2 Multi-edit (mixed values shown as —)
- [x] 6.3 Viewport: rulers/guides, smart snapping to node edges/centres, pivot editing, per-node lock/hide, show-all-colliders
- [x] 6.4 Scene tree: search by type/tag, groups/tags, reorder by drag, cross-scene copy/paste
- [x] 6.5 Asset browser: thumbnail grid, real folders (create/move/rename with reference updates), find usages, per-asset import settings
- [x] 6.6 Sprite-sheet slicer → frame animations
- [x] 6.7 Play-in-editor: remote scene tree of the running game, frame step, hot reload while playing
- [x] 6.8 Layout presets / workspaces and reset layout
- [x] 6.9 Welcome / new-project window with templates; icons for every node type; empty-state guidance

## Phase 7 — Code editor & Lua

- [x] 7.1 Node subtypes in definitions (`TextureNode`, `CameraNode`, …) so methods complete per type
- [x] 7.2 Definitions checked against the registered Lua bindings (test fails on drift)
- [x] 7.3 Per-line token cache keyed on buffer version; measure with a 10k-line file
- [x] 7.4 Overlays: hover / signature / completion docs as bounded, wrapped, scrollable popups clamped to the editor
- [x] 7.5 Lua debugger: breakpoints, stepping, locals (debug hooks)

## Phase 8 — Lua integration (2026-10-23)

Autocomplete and type safety
- [x] 8.1 Typed `get_script()`: returns the script's generated class (methods, fields)
- [x] 8.2 Event names complete in `connect` / `emit` (engine events per node type + custom ones scripts emit) and `on_<event>` methods
- [x] 8.3 Typed `get_property` / `set_property` paths per node class
- [x] 8.4 Typed `get_node("path")` (paths relative to each script's nodes)
- [x] 8.5 Asset / scene / action aliases on more API parameters
- [x] 8.6 Diagnostics: Lua runtime errors as squiggles in the Code tab (Play / Simulate); warnings for unknown node paths / property names

Drag and drop, editor ↔ code
- [x] 8.7 Drop an animation / input action / scene / sound into code
- [x] 8.8 Drop a Signals-panel event row into code: a `connect` with the handler signature
- [x] 8.9 Drop a node onto a method: a `connect` to one of its events
- [x] 8.10 Node-reference exported properties (`type = "node"`, Inspector picker); dropping a node on the `properties` table adds one
- [x] 8.11 Rename-safe references: renaming / moving a node offers to update `get_node` / `find_node` in scripts
- [x] 8.12 Code → scene: Cmd+click a `get_node("...")` path selects the node; find a script's usages

Exported properties
- [x] 8.13 More types: enum, range/slider, array, curve, gradient, colour alpha; `group` / `header`, `tooltip`
- [x] 8.14 `---` comments above a property become its help-pane text
- [x] 8.15 Live editing of exported values in the running game (Game tab)

Engine API
- [x] 8.16 Vec2 / Vec3 / Vec4 types with operators, used by the API
- [x] 8.17 Property-style access (`self.node.position = ...`), old methods kept
- [x] 8.18 Spawning: `Scene.instantiate(component, parent, x, y)` (typed root), `node:queue_free()`
- [x] 8.19 Global scripts (autoloads) in Project Settings, reachable from every script; globe marker in the asset browser
- (on hold) coroutines (`wait` / `await` / `tween`) - not wanted yet; (not chosen) lifecycle hooks

Script authoring
- [x] 8.20 New-script templates (character, enemy patrol, UI menu, pickup, door/trigger)
- [x] 8.21 Snippets (Tab-expanded): ready, update, connect, properties, tween
- [x] 8.22 Attach by dropping a `.lua` onto a scene-tree node
- [x] 8.23 Lua console: evaluate expressions in the simulating / running game
- [x] 8.24 Debugger: watch expressions, conditional breakpoints

Docs in place
- [x] 8.25 Every API function documented in `engine_api.lua` (description + example) for hover
- [x] 8.26 F1 on an API symbol opens its section of the scripting reference in the editor

## Release packaging (editor)

- [ ] R.1 libcmark for a released editor: the Scripting Reference's markdown (`editor/markdown_view.odin`, `vendor:commonmark`) links the system `libcmark` (`brew install cmark` on dev machines - `/opt/homebrew/opt/cmark/lib/libcmark.dylib`), which users won't have. Before shipping the editor, either
  - a) bundle it as a dynamic lib: copy `libcmark.dylib` (`.so` / `cmark.dll`) next to the editor (macOS: into the .app's `Frameworks`, `install_name_tool -change` to `@rpath/libcmark.dylib`, `-Wl,-rpath,@executable_path/../Frameworks` as `scripts/build_runners.sh` does for the runners), or
  - b) build cmark as a static lib (cmake `-DBUILD_SHARED_LIBS=OFF`, per platform; the vendor's `build.bat` does this on Windows) and link it in, so the editor has no extra file.
  The game runner doesn't use cmark.

## Phase 9 — Code editor on par with Zed (2026-10-23)

Docs: `editor/CODE_EDITOR.md`. Constraints: no frame-time cost (cache per buffer version, draw only visible lines), no leaks (owned allocations freed with the doc / on close).

Copy / paste
- [x] 9.1 Whole-line paste (a whole-line copy pastes as a line above), paste re-indent, clipboard history (Cmd+Shift+V), Copy Path / Absolute Path / Location
Context menus
- [x] 9.2 Grouped context menu with shortcuts; context items (symbol, selection, node / asset path strings); gutter menu; tab menu (close others / right / saved, copy path, reveal, pin)
Selection & multi-cursor
- [x] 9.3 Expand / shrink selection (word -> string / brackets -> line -> block -> function -> file)
- [x] 9.4 Column selection (Alt+drag), cursors at line ends (Shift+Alt+I), skip occurrence, select inside brackets / quotes, undo last cursor
Display
- [x] 9.5 Matching bracket highlight + jump, rainbow brackets, indent guides
- [x] 9.6 Symbol highlights (LSP document highlight), visible whitespace, soft wrap
- [x] 9.7 Code folding (gutter arrows; functions, tables, comment blocks)
- [x] 9.8 Scrollbar markers (errors, find matches, breakpoints, changes) - the minimap
- [x] 9.9 Sticky scroll + breadcrumbs
- [x] 9.10 Inlay hints (LSP)
- [x] 9.11 Git gutter (added / modified / removed)
Navigation
- [x] 9.12 Back / forward history
- [x] 9.13 Outline (Cmd+Shift+O) and workspace symbols (Cmd+T)
- [x] 9.14 Next / previous diagnostic (F8), next / previous change
- [x] 9.15 Find in files (Cmd+Shift+F) with a results pane
- [x] 9.16 Peek definition / references inline
Refactoring
- [x] 9.17 Code actions / lightbulb (Cmd+.): LSP quick fixes + engine fixes (unknown node path, unknown input action)
- [x] 9.18 Extract local / extract method / inline variable; wrap in if / function / do; get_property <-> field, strings <-> Vec2
- [x] 9.19 Rename across files with a preview
Files
- [x] 9.20 Tab pinning + preview tab
- [x] 9.21 Files changed on disk: reload prompt; local history (restore earlier saves)
Engine
- [x] 9.22 Inline values while debugging
- [x] 9.23 Property in code <-> Inspector (click to select)
- [x] 9.24 Colour swatches beside {r, g, b, a} with a picker
- [x] 9.25 Texture path hover preview
