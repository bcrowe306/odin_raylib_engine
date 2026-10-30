## Use it for

- **Things that come and go often**: bullets, sparks, coins, damage numbers, enemies of a wave. `Pool.take(component, parent, x, y)` instead of `Scene.instantiate` reuses a parked instance; `node:destroy()` on it parks it again.
- **No hitch on the first shot**: `Pool.prewarm(component, count)` makes the instances while the level loads, so the first takes create nothing mid-game.
- **A hard cap**: `Pool.set_max(component, max)` limits how many instances exist; `take` returns nil at the cap (the oldest bullets don't get stolen - the shot just doesn't happen).
- **Returning one by hand**: `Pool.release(node)` is the same as `node:destroy()` on a taken instance, and says whether it was one.
- **Tuning**: `Pool.stats(component)` returns how many are active, parked and made in all - print it to pick a prewarm count and a max.

## Example

A gun that fires pooled bullets while **fire** is held - the script is on the gun's muzzle node; the bullet's own script moves it and calls `self.node:destroy()` when it leaves the screen.

```lua
---@class Gun : ScriptInstanceBase
local Gun = {}

local BULLET = "components/bullet.component.json"

Gun.properties = {
    fire_rate = { type = "float", default = 8, label = "Shots per Second" },
}

function Gun:ready()
    Pool.set_max(BULLET, 64)   -- never more than 64 bullets at once
    Pool.prewarm(BULLET, 32)   -- made now, not mid-fight
    self.cooldown = 0
end

---@param dt number
function Gun:update(dt)
    self.cooldown = self.cooldown - dt
    if self.cooldown > 0 or not Input.is_action_down("fire") then return end
    self.cooldown = 1 / self.fire_rate
    -- Under the scene's root, at the muzzle's world position.
    local bullet = Pool.take(BULLET, nil, self.node:get_global_position())
    if bullet then
        bullet.rotation = self.node:get_global_rotation()
    end
end

return Gun
```

## Notes

- A reused instance keeps the state it had: reset it in its script's `on_spawn()` (called before its first update after every take, after `ready()` the first time), and clean up in `on_despawn()`. `ready()` runs only once.
- Taking moves the instance to the position and zeroes its bodies' velocities; its tweens were cancelled when it was parked.
- Pools belong to the current scene (one per component path) and are freed with it. If a pooled node's parent is destroyed, the node goes with it and the pool forgets it.
- `x, y` are local to `parent` - with no parent, the scene's root.
- A [Spawner](../nodes/SpawnerNode.md) with **Use Pool** takes from the same pools without a script. The [pooling guide](../../engine/docs/pooling.md) has the details.
