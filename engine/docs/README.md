# Engine feature guides

One guide per feature: what it does, how to use it in the editor, the
scripting API, examples / tutorials, what is saved, performance notes and
limits. The scripting reference is [`../SCRIPTING.md`](../SCRIPTING.md); the
editor overview is [`../../editor/README.md`](../../editor/README.md).

| Guide | |
|---|---|
| [Level editor](level_editor.md) | The **Level** tab: LDtk projects edited in place - worlds, levels, IntGrid / Tiles / Auto layers with LDtk's rule engine, entities and fields, definitions, terrains, per-tile data and animated tiles; the `Ldtk_Doc` API - with tutorials. |
| [Aseprite](aseprite.md) | .aseprite files used as they are: tags played as Aseprite plays them, layers on / off per node, slices (pivots, hitboxes), user data, tilemap layers as TileMaps; live reload when you save - with a tutorial. |
| [Skeletal animation](skeletal_animation.md) | Spine and DragonBones exports on the engine's own runtime: Skeleton and Bone Attachment nodes, crossfades, skins, IK, events, bone overrides - with a tutorial. |
| [Vector art](vector.md) | Vector shapes crisp at any zoom: tessellation, anti-aliasing, cached GPU meshes, the Vector Shape node - the start of Flash-style vector characters (Phase 14). |
| [Animation editing](animation_editing.md) | Custom key curves (cubic Bezier), method events with arguments and the animation_event signal, onion skin - with tutorials. |
| [Draw order](draw_order.md) | Layers, Z index, Y-sort (top-down / isometric depth). |
| [Navigation](navigation.md) | Path finding on tile maps, LDtk levels and Navigation Regions; agents that walk there (radius, avoidance, doors) - with tutorials. |
| [Accessibility](accessibility.md) | UI scale, colour-blind filters (and an editor preview), subtitles from dialogue and sound captions, screen shake scale; the Accessibility Menu template - with a tutorial. |
| [Advanced camera](advanced_camera.md) | Virtual cameras with priorities and blending, follow modes (group, path, dead zone, look-ahead), limits incl. the LDtk level the target is in, trauma shake - with tutorials. |
| [Web export](web_export.md) | Export to the browser (a static folder for itch.io etc.), what works there, the prebuilt web runner and how the engine runs on WebAssembly. |
| [Sprite atlases](atlas.md) | Tick Atlas on textures: export packs them into pages (fewer draw calls); how it works, what to leave out, helpers for engine code. |
| [Import settings](import_settings.md) | Per-asset settings next to the file: texture filter / wrap / mipmaps / slicing preset / QOI on export, audio gain and default bus - with tutorials. |
| [Audio mixer](audio_mixer.md) | Buses (fader, pan, mute / solo, effects, routing), the Mixer tab, Lua control - with tutorials. |
| [Gamepads and local multiplayer](gamepads.md) | Up to 4 players with their own controllers, hot-plug events, rumble (native per OS), button prompts that match the controller (`Input.glyph`), simulated pads for tests - with a co-op tutorial. |
| [Input and rebinding](input_rebinding.md) | Actions, player rebinding (listen, conflicts, saving), gamepad menus, the Controls Menu template. |
| [Changing scenes](scene_flow.md) | Transitions, preloading, loading screens (background texture decoding) - with a loading screen tutorial. |
| [Paths and followers](paths.md) | Bézier paths edited in the viewport; followers for moving platforms, patrols, rails - with tutorials. |
| [Pixel-perfect rendering](pixel_perfect.md) | Integer scaling, pixel snap, smooth sub-pixel camera - recipes for pixel art. |
| [Object pooling](pooling.md) | Reuse bullets, effects, pickups: `Pool.take`, `on_spawn` / `on_despawn`, prewarm, caps - with a tutorial. |
| [Crash reports](crash_reports.md) | What a crash writes (reason, stack, recent lines), where, the editor's "report on GitHub", and the `Crash` Lua module for games. |
| [Visibility notifier](visibility.md) | On screen / off screen events; pause, disable or remove the parent off screen. |
