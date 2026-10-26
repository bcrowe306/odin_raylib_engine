A plain node: a transform (position, rotation, scale) and children. Use it
to group nodes - move the group and everything under it moves - or as the
root of a scene or a component, or to hold a script that has nothing to draw.

```lua
-- A spinning group: everything under this node turns with it.
local Spinner = {}
Spinner.properties = { speed = { type = "float", default = 90 } } -- degrees per second

function Spinner:update(dt)
    self.node.rotation = self.node.rotation + self.speed * dt
end

return Spinner
```
