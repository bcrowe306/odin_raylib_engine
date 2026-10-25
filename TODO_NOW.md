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
- [x] 3.4 Web (emscripten): raylib + Box2D + Lua to wasm, `.ore` preloaded, click-to-start audio (done as roadmap 5: the prebuilt web runner; `web_export` drive)
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

## Phase 12 — Distribution, CI/CD and export targets (2026-10-25)

Goal: users install the editor like any app (no compiler, no Homebrew, no
repo) and it exports to every desktop platform and the web from any of them;
tagged versions build and publish themselves.

Editor that runs anywhere:
- [x] D.1 Relocatable editor: resources found next to the executable (`Contents/Resources` in a .app) or in the source checkout; fonts and small files embedded (`#load`); no paths relative to the working directory
- [x] D.2 Play runs the prebuilt runner (the one export uses), no Odin compiler; the rebuild-on-change path only in a source checkout with `odin` installed
- [x] D.3 Lua 5.4 as a static library built from source (macOS uses Homebrew's dylib today), in the editor and the runners
- [x] D.4 (was R.1) libcmark for a released editor: the Scripting Reference's markdown (`editor/markdown_view.odin`, `vendor:commonmark`) links the system `libcmark` (`brew install cmark` on dev machines - `/opt/homebrew/opt/cmark/lib/libcmark.dylib`), which users won't have. Before shipping the editor, either
  - a) bundle it as a dynamic lib: copy `libcmark.dylib` (`.so` / `cmark.dll`) next to the editor (macOS: into the .app's `Frameworks`, `install_name_tool -change` to `@rpath/libcmark.dylib`, `-Wl,-rpath,@executable_path/../Frameworks` as `scripts/build_runners.sh` does for the runners), or
  - b) build cmark as a static lib (cmake `-DBUILD_SHARED_LIBS=OFF`, per platform; the vendor's `build.bat` does this on Windows) and link it in, so the editor has no extra file.
  The game runner doesn't use cmark.
  Or c) replace it: the markdown view uses a subset; a small Odin renderer removes the dependency.
- [x] D.5 lua-language-server built per platform and bundled (the Code tab's completion / diagnostics)
- [x] D.6 The editor ships the runners for every platform (`runners/{macos,windows,linux,web}`), so any editor exports every desktop target and the web
- [x] D.7 One version string (from the git tag) in the editor, the runner and each `.ore`; the runner warns about a project from a newer version
- [x] D.8 Third-party license notices bundled (raylib, Lua, Box2D, Dear ImGui, LuaLS, cmark, Open Sans, Font Awesome)
- [x] D.9 Check for updates against GitHub Releases (Help > Check for Updates, at startup unless turned off; status bar link; later: an auto-updater)

CI/CD (GitHub Actions):
- [x] C.1 CI on pushes / pull requests: build the editor, the runner and the Play binary, engine + ui unit tests, on macOS (arm64), Windows (x64) and Linux (x64)
- [x] C.2 Smoke test in CI: the runner plays the demo project and the packaged editor plays, exports and starts its language server (scripts/test_package.sh) - on Linux under Xvfb (hosted macOS runners have no GPU); editor drives stay local
- [x] C.3 Release workflow on `v*` tags: build the editor and runners per platform, put every platform's runners in each editor package, publish a GitHub Release with checksums
- [ ] C.4 macOS signing + notarization (Developer ID, hardened runtime, every dylib signed; certificates as repository secrets) - needs an Apple Developer account
- [ ] C.5 Windows code signing (Azure Trusted Signing or an OV certificate) - optional for early releases (SmartScreen warns without it)
- [x] C.6 Linux glibc baseline: built on Ubuntu 22.04 (glibc 2.35: Ubuntu 22.04+, Debian 12+, Fedora 36+); Ubuntu 20.04 is past its standard support, so no older container
- [x] C.7 Packages: .dmg (macOS), .zip (Windows; an installer later if wanted), AppImage + .deb + .tar.gz (Linux) - checked with a dry run (release-dryrun branch): the CI-built app carries all four runners and passes scripts/test_package.sh

Export targets:
- [x] X.1 Linux .deb of the editor in releases (scripts/ci/deb_editor.sh; with the AppImage and .tar.gz). Not .rpm / Flatpak: the AppImage and .tar.gz run on those distributions, and games export as AppImages
- [x] X.2 Web polish: no worker threads on the web (textures decode on the main thread: async_decode.odin), so no COOP / COEP headers are needed; the runner is 3.2 MB of wasm (1.24 MB gzip, 0.98 MB brotli - hosts like itch.io serve it compressed)
- [ ] X.3 Steam (roadmap 19): Steamworks as a Lua module (achievements, overlay, cloud saves); Steam Deck (gamepad-first UI, 1280x800; the Linux runner, or Windows under Proton)
- [ ] X.4 Android (roadmap 18): NDK build, touch input, app lifecycle (pause / resume, GL context loss), assets read from the APK, signed AAB
- [ ] X.5 iOS (roadmap 18): raylib has no official iOS backend (a fork or Metal path), Xcode project, provisioning, App Store review
- [ ] X.6 Consoles (PS5, Xbox, Switch): not now - devkits under NDA, a renderer port per console (no raylib backends), unofficial Odin toolchains; keep the platform layer contained and the C dependencies portable

Testing:
- [x] T.1 Editor drives in the background and in parallel: hidden windows that never take the focus (editor and game `--hidden`), JOBS at a time, `# drive: serial` drives after the others (`scripts/editor_drive.sh`, VISIBLE=1 to watch)

## Phase 10 — State machines for gameplay (2026-10-23)

- [x] 10.1 Engine: on_update_<state>(dt), "script says" conditions, or-groups, child machines, history (sm_history), graph positions
- [x] 10.2 State Machine graph tab (add / connect / move / delete states, side panel, script callbacks)
- [x] 10.3 Live debugging: current state + fired transition (Simulate and Play), history, break on enter
- [x] 10.4 Lua / docs polish: generated types, drives, README

## Roadmap — 2D engine gaps (2026-10-24)

Numbers are the user's (referenced in comments).

Decisions (2026-10-24): 3 saves **.ldtk** directly (round-trips with the LDtk app; extras in LDtk custom fields). 24 = virtual cameras + host (many AdvancedCamera nodes with priorities; CameraNode hosts and blends) and must work with LDtk level / room linking (neighbours, room limits). 7 = own runtime + DragonBones / Spine importers + light editing (a rig editor may come later). 5: install emscripten with Homebrew; shipping the editor needs a way to bundle it (note for release packaging). A: buses route to master (or another bus); effects per bus.

Every feature: works with the rest of the engine and the editor (integration); memory layout / cache misses / rendering cost / parallelism considered (performance); leak and use-after-free checked, arenas where lifetimes are shared (safety); documented for the engine API and the editor, with examples / tutorials (docs). Tests + drives per feature.

Missing (all):
- [x] 1 Navigation: (A* on TileMap / LDtk grids existed) NavigationRegionNode (a rectangle baked from static physics shapes, solid tile maps, LDtk Solid cells; script-blocked cells for doors), agent radius via a clearance map (radius option everywhere), NavigationAgentNode (path following, repath interval, moves a CharacterMover / DynamicBody / node, separation avoidance, events); Lua; viewport cells / paths, Inspector Bake; guide with tutorials, test, drive
- [x] 2 Y-sort / depth sorting (top-down, isometric): zIndex (relative), ySort, ySortOffset; sorted in the one render walk (stable sorts only where used); picking follows draw order; guide engine/docs/draw_order.md, test, y_sort drive
- [x] 3 Level editor: root tabs **Game** / **Level** (Cmd+Shift+1/2); the Level tab edits LDtk projects in place (`.ldtk` + external `.ldtkl`) - an order-preserving JSON tree with LDtk's own formatter (byte-exact round trips), LDtk's auto-layer rule engine ported (JS double arithmetic, Perlin, stamps, flips, chance, modulo / checker, break on match, killed-by, optional groups, biomes; regenerates LDtk's tiles exactly on its 1.5 samples), toc / neighbours like LDtk; worlds and levels (add / delete / rename / move / resize / depth / colour / fields), IntGrid / Tiles painting (brush, rectangle, fill, erase, pick, stamps, flips, incremental rules), entities (place / move / resize / fields), definitions (layers, IntGrid values, entities and fields, enums, tilesets, rule groups and a rule pattern editor), terrain rules from a 3x3 block, per-tile custom data / enum tags, animated tiles (custom data `anim=` / `fps=`, played by the engine's LdtkLevelNode and the editors); undo (cell strokes, level / project snapshots, coalesced live edits); Ldtk_Doc engine API; guide with tutorials, tests, drive
- [x] 4 Paths: PathNode (Bézier points, baked polyline by distance, closest offset, drawn line), PathFollowNode (speed, Stop / Loop / PingPong, rotate, side offset, events); viewport editing (drag points / handles, double-click insert keeping the shape, Alt+click remove), Inspector points; CharacterMover rides moving floors; Lua path_* / follow_*; guide with tutorials, test, drive
- [x] 5 Web export: a prebuilt web runner (scripts/build_web_runner.sh: raylib 5.5 WebGL 2, Lua 5.4.7, Box2D 3.1.1 and zlib with emcc; the engine for js_wasm32 from a patched source copy) - exporting needs no compiler, ship runners/web/ with the editor; the engine runs per animation frame (Runner_Start / Frame / Stop), osx / pathx / vmemx web packages, malloc-backed allocators (built with -default-to-panic-allocator), vendored Lua bindings (64-bit numbers everywhere), GLSL 330 -> ES 300, synchronous decoding; page shell (click to play / ?autostart, IndexedDB saves, fonts, favicon, title); Web export target, File > Export > Open Web Export in Browser (local server); headless Chrome capture tool; guide, drive
- [x] 6 Visibility notifier: VisibilityNotifierNode (size, margin, action: pause / disable / remove the parent), screen_entered / exited, onScreen; per-manager notifier list, one pass after the transforms (game + Simulate); guide engine/docs/visibility.md, test, drive

Common:
- [x] A Audio mixer: our own mixer behind one raylib stream (sounds decoded to 48 kHz floats, music streamed from raylib's decoders; miniaudio's node graph can't link next to raylib's copy), buses (fader, pan, mute / solo, routing, up to 8 effects: EQ, low/high-pass, compressor, limiter, delay, reverb, distortion), meters; Sound / Music nodes' bus; project.json buses; Mixer tab (DAW strips, Master at the right, live over the link in Play); Lua Audio.* bus / effect API; guide with tutorials, tests, a real-device run, drive
- [x] 7 Skeletal / cutout animation: our own runtime (bones with shear and inherit modes, slots, skins, regions, weighted / linked meshes, 1-2 bone IK, rotate / translate / scale / shear / attachment / colour / draw order / event timelines, linear / stepped / Bezier curves, crossfades); Spine 3.8-4.2 JSON + .atlas and DragonBones 5.x _ske.json + _tex.json importers (axes / skew converted); SkeletonNode (shared counted data cache, events, finished, bone rotation overrides) and BoneAttachmentNode (in game and editor); Lua skeleton_*; Inspector (file / animation / skin pickers, preview play / scrub, bones list with highlight, attach); guide with a tutorial, test with hand-made fixtures, real renders, drive. (Rig editor: later)
- [x] 8 Object pooling: Pool.take / release / prewarm / set_max / stats, destroy() returns pooled nodes, on_spawn / on_despawn, bodies off while parked, per-scene pools freed on unload; Profiler rows; guide + tutorial engine/docs/pooling.md, test, drive. Also: Lua C callbacks now run with their script manager's context (Script_Context: the engine's allocator and logger - no more bad frees under the leak tracker; errors from Lua-triggered engine code are logged)
- [x] 9 Pixel-perfect rendering: Integer Scaling, Pixel Snap (camera + sprites), Smooth Camera (world in a margin texture shifted by the leftover fraction at the upscale; UI layers on top); Project Settings > Video; guide engine/docs/pixel_perfect.md, test, runner screenshots, drive
- [x] 10 Sprite atlas packing on export: Atlas in a texture's import settings; export packs the ticked textures (by filter; mipmapped / too big skipped) with MaxRects into pages up to 2048 px, 2 px gaps with edge extrusion, atlas/page_n.png + atlas.json (originals kept); the game mounts it from the package and atlased textures load as page + rectangle (pages refcounted), Texture_Size / Texture_Src / Texture_Full at every draw site (sprites, sheets, frame animations, nine-slice, parallax, tile maps), materials load their own copy; verified pixel-identical against the loose project; guide, test, drive
- [x] 11 Input rebinding: Input.listen (release-first, keys / mouse / pad buttons / sticks, conflicts clear / swap / allow, on_done), set / get / reset bindings, player-facing names, saved to input_bindings.json and loaded at start; gamepad UI navigation (D-pad / stick with repeat, A); Controls Menu template; Scene.create_node makes any node type; guide, tests, drive
- [x] 12 Scene transitions: (transitions + preload existed) loading screens (change_scene loading / min_time, Scene.loading_progress / loading_target, Game_ChangeSceneVia), textures decoded on worker threads (async_decode.odin; jobs owned by the decoder, abandon-safe), preload finds "texture" (it only read legacy "texture_path") and images named by properties; guide with a tutorial, tests, a real-game run

Editor:
- [x] 13 Editor plugins in Lua - designed 2026-10-25, built 13.1-13.7: editor/docs/plugins.md (project + user plugins, trust prompt + permissions, editor-only)
  - [x] 13.1 Plugin host: discovery, plugin.json, a Lua state per plugin, protected calls, on_load / on_unload, hot reload, Settings > Plugins
  - [x] 13.2 Trust prompt + permissions (per project, remembered)
  - [x] 13.3 A: commands (menus, palette, keymap), selection, scene, Editor.edit undo, create / destroy, assets + Editor.fs, dialogs
  - [x] 13.4 B: dockable panels + the `ui` widget set
  - [x] 13.5 C: events (selection, save, import, before Play, after export, project opened)
  - [x] 13.6 editor_api.lua definitions, Tools > New Plugin, guide + examples, drives
  - [x] 13.7 D: inspectors, viewport overlays / handles, importers
- [x] 14 Live remote scene tree in Play: (the Game tab's tree / text props existed) the Scene panel's Local / Remote view and the Inspector on the running game's node; typed live properties (drags, check boxes, colours, enum lists incl. script enums, ranges; throttled while dragging); enabled / visible toggles, Remove from Game, Pick (click in the game window; topmost node per layer space), amber outline of the selection in the game, Apply to Scene (undoable, Node_SetFromText); trees re-sent only when their hash changed; README, tests, drive
- [x] 15 Multiple open scenes as tabs: a tab per open scene / component document above the viewport (reorder, unsaved dot, tooltip, context menu), per-tab camera / selection / undo, close with Save / Don't Save / Cancel (unloads the scene, frees its undo entries; closed component documents reuse their scene), Cmd+W, Cmd+Alt+Right/Left, Ctrl+PageDown/Up, Ctrl+Tab; open tabs restored per project (.ore/open_scenes.json); README, drive
- [x] 16 Animation editor depth: (easing presets and method / sound event tracks existed) custom key curves (cubic Bezier editor with handles and presets, saved as a 7th key element, drawn on the timeline rows), method keys with an argument and a method picker from the target script, the player's animation_event signal, onion skin in the viewport (before / after counts, opacity, follows the player's own tracks, wraps looping animations); toolbar wraps in narrow panels; guide with tutorials, test, drive
- [x] 17 Per-asset import settings: `<asset>.import.json` next to the file (hidden in Assets, moved / copied / deleted with it, read through the package in exported games, cached per path in one arena): textures filter / wrap / mipmaps / slicing preset (the Sprite Sheet Slicer opens with it, Save Preset) / Export Keep or QOI (re-encoded into the package; loaders sniff QOI headers); audio gain (baked into decoded sounds, music volume) and default bus (nodes / Audio calls without one); old project.json texture_import still read and moved on the first change; preview panel rows (wrapping); guide with tutorials, test, drive. Also: two process-lifetime caches no longer show as leaks

Platform and shipping (later): 18 mobile export + touch, 19 Steam, 20 gamepad rumble / multiple controllers / glyphs, 21 networking, 22 crash reports.

Quality of life:
- [x] 23 Accessibility: settings per player (accessibility.json, over project.json defaults; Project Settings > Accessibility), UI scale (top-level UI elements grow around their nearest screen corner / edge / centre; UI input mouse in the same space), colour-blind filters (daltonize correction / simulate shader on the final frame; View > Colour Vision preview in the editor), subtitle track (dialogue / captions, size, backdrop), Dialogue Mode Subtitles with per-line voice sounds, Sound / Music captions, screen shake scale (both cameras), remappable controls (11); Lua Accessibility.* / Subtitles.*; Accessibility Menu template; guide with a tutorial, test, real-game screenshots, drive
- [x] 24 Advanced camera: AdvancedCameraNode virtual cameras hosted by the scene's CameraNode (highest priority shown, eased blends of position / zoom / rotation, a transient host when the scene has no camera); follow modes None / Glued / Simple (offset, damping, look-ahead) / Group (auto zoom) / Path / Framed (dead zone), axis lock; limits Rect / Node bounds / the LDtk level the target is in (glides between linked levels); trauma shake (trauma ^ exponent, noise, decay); Lua add_trauma / make_active / is_active / snap, Camera.add_trauma / get_active, became_active / inactive; Inspector node pickers, viewport frames / dead zone / limits (preview on a copy); guide with tutorials, tests, drive

## Phase 11 — State transition guards (2026-10-23)

Arrows allow a change (their conditions: when it goes by itself); states can refuse. Chosen: full guards, sm_travel stays forced + sm_request, a per-state "Any state interrupts" toggle, blocked attempts shown live only (not in the history).

- [x] 11.1 Engine: minTime, noInterrupt, leaveWhen / enterWhen on states, can_exit_ / can_enter_ script guards, StateMachine_Request / sm_request (ok, reason), explain (ways out with each condition's result and the block), saved; tests
- [x] 11.2 Editor: Guards in the state side panel (shared condition list), lock badge, Add Guard Callbacks, Ways out (live, Simulate and Play), blocked arrows red, live condition marks; generated types for can_exit_ / can_enter_
- [x] 11.3 Drive state_guards, docs

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
