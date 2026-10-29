## Monitoring

An area reports bodies that enter and leave it: `body_entered` and
`body_exited`, and the overlap count in the Inspector. Each body is reported
once, even when the area or the body has several shapes.

Turn **Monitoring** off for an area that shouldn't react itself, such as an
attack's hitbox that only hurtboxes react to. It then raises no events and
keeps no overlaps, but it is still a shape: raycasts that collide with
sensors and physics queries still find it. Turned back on, it reports the
bodies already inside as entering.

```lua
-- Hitbox on only during the attack's active frames.
function Player:attack()
    self.hitbox = self.node:get_node("Hitbox") ---@type AreaNode
    self.hitbox:area_set_monitoring(true)
    self.attack_left = 0.15
end

function Player:update(dt)
    if self.attack_left then
        self.attack_left = self.attack_left - dt
        if self.attack_left <= 0 then
            self.hitbox:area_set_monitoring(false)
            self.attack_left = nil
        end
    end
end
```

A Raycast node has the same **Monitoring** switch (`raycast_set_monitoring`):
off, it doesn't cast and raises no `hit_started` / `hit_ended`.
