Vector art drawn as cached, anti-aliased meshes: crisp at any zoom (see the
[vector art guide](../../engine/docs/vector.md)). For now it draws built-in
presets (Star, Ring, Badge, Character); SVG assets come with the next
milestones.

```lua
-- Recolour a vector shape from a script: the mesh is rebuilt once.
local v = self.node:get_node("Badge")
v.fillColor = {0.9, 0.3, 0.3, 1}
v.strokeWidth = 6
```
