# Engine feature guides

One guide per feature: what it does, how to use it in the editor, the
scripting API, examples / tutorials, what is saved, performance notes and
limits. The scripting reference is [`../SCRIPTING.md`](../SCRIPTING.md); the
editor overview is [`../../editor/README.md`](../../editor/README.md).

| Guide | |
|---|---|
| [Animation editing](animation_editing.md) | Custom key curves (cubic Bezier), method events with arguments and the animation_event signal, onion skin - with tutorials. |
| [Draw order](draw_order.md) | Layers, Z index, Y-sort (top-down / isometric depth). |
| [Navigation](navigation.md) | Path finding on tile maps, LDtk levels and Navigation Regions; agents that walk there (radius, avoidance, doors) - with tutorials. |
| [Accessibility](accessibility.md) | UI scale, colour-blind filters (and an editor preview), subtitles from dialogue and sound captions, screen shake scale; the Accessibility Menu template - with a tutorial. |
| [Advanced camera](advanced_camera.md) | Virtual cameras with priorities and blending, follow modes (group, path, dead zone, look-ahead), limits incl. the LDtk level the target is in, trauma shake - with tutorials. |
| [Web export](web_export.md) | Export to the browser (a static folder for itch.io etc.), what works there, the prebuilt web runner and how the engine runs on WebAssembly. |
| [Sprite atlases](atlas.md) | Tick Atlas on textures: export packs them into pages (fewer draw calls); how it works, what to leave out, helpers for engine code. |
| [Import settings](import_settings.md) | Per-asset settings next to the file: texture filter / wrap / mipmaps / slicing preset / QOI on export, audio gain and default bus - with tutorials. |
| [Audio mixer](audio_mixer.md) | Buses (fader, pan, mute / solo, effects, routing), the Mixer tab, Lua control - with tutorials. |
| [Input and rebinding](input_rebinding.md) | Actions, player rebinding (listen, conflicts, saving), gamepad menus, the Controls Menu template. |
| [Changing scenes](scene_flow.md) | Transitions, preloading, loading screens (background texture decoding) - with a loading screen tutorial. |
| [Paths and followers](paths.md) | Bézier paths edited in the viewport; followers for moving platforms, patrols, rails - with tutorials. |
| [Pixel-perfect rendering](pixel_perfect.md) | Integer scaling, pixel snap, smooth sub-pixel camera - recipes for pixel art. |
| [Object pooling](pooling.md) | Reuse bullets, effects, pickups: `Pool.take`, `on_spawn` / `on_despawn`, prewarm, caps - with a tutorial. |
| [Visibility notifier](visibility.md) | On screen / off screen events; pause, disable or remove the parent off screen. |
