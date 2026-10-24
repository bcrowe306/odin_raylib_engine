# Engine feature guides

One guide per feature: what it does, how to use it in the editor, the
scripting API, examples / tutorials, what is saved, performance notes and
limits. The scripting reference is [`../SCRIPTING.md`](../SCRIPTING.md); the
editor overview is [`../../editor/README.md`](../../editor/README.md).

| Guide | |
|---|---|
| [Draw order](draw_order.md) | Layers, Z index, Y-sort (top-down / isometric depth). |
| [Navigation](navigation.md) | Path finding on tile maps, LDtk levels and Navigation Regions; agents that walk there (radius, avoidance, doors) - with tutorials. |
| [Audio mixer](audio_mixer.md) | Buses (fader, pan, mute / solo, effects, routing), the Mixer tab, Lua control - with tutorials. |
| [Input and rebinding](input_rebinding.md) | Actions, player rebinding (listen, conflicts, saving), gamepad menus, the Controls Menu template. |
| [Changing scenes](scene_flow.md) | Transitions, preloading, loading screens (background texture decoding) - with a loading screen tutorial. |
| [Paths and followers](paths.md) | Bézier paths edited in the viewport; followers for moving platforms, patrols, rails - with tutorials. |
| [Pixel-perfect rendering](pixel_perfect.md) | Integer scaling, pixel snap, smooth sub-pixel camera - recipes for pixel art. |
| [Object pooling](pooling.md) | Reuse bullets, effects, pickups: `Pool.take`, `on_spawn` / `on_despawn`, prewarm, caps - with a tutorial. |
| [Visibility notifier](visibility.md) | On screen / off screen events; pause, disable or remove the parent off screen. |
