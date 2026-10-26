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

**Symbols and part swapping**: **group** draws one named group of the file
(an Inkscape / Illustrator / Affinity layer; `head/mouth` for nested ones),
and **frame** shows one of that group's child groups at a time - mouths,
hands, eyes - without the part moving. Groups hidden in the file are kept
as frames. **brightness** and **colorAdd** are Flash's colour effects (a
hit flash: `colorAdd = {255, 0, 0, 255}`). The Inspector's *Explode into
Parts* turns a layered character into a Vector Shape per layer, and a
[Lip Sync](../../engine/docs/vector.md#lip-sync) node moves a mouth with a
voice.

```lua
local mouth = self.node:get_node("Mouth")
mouth:vector_swap("O")   -- by name; false when there's no such frame
```
