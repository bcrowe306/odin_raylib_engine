Vector art drawn as cached, anti-aliased meshes: crisp at any zoom (see the
[vector art guide](../../engine/docs/vector.md)). Give it an SVG **file**
(drag one from Assets into the viewport) - every node drawing the same file
shares its meshes, and saving the file reloads it - or leave the file empty
to draw a built-in **preset** (Star, Ring, Badge, Character, Gradients).

```lua
-- Swap the art a vector shape draws (e.g. a character's outfit).
local hero = self.node:get_node("Hero")
hero.file = "vectors/hero_winter.svg"
```

Its **Origin** is a fraction of the SVG's box (centred by default; the
file's import settings can choose another for new nodes).
