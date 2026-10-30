## Moving it

A kinematic body moves exactly as you say. Forces and collisions don't move
it, and it pushes dynamic bodies and carries character movers standing on
it. Use it for moving platforms, elevators, doors and conveyor belts.

There are two ways to drive it, and you can mix them:

- **Velocity**: set **Linear Velocity** (px/s) and **Angular Velocity**
  (degrees/s) in the Inspector or from a script. It keeps moving until you
  change them.
- **Position**: move the node yourself (a script, an Animation Player, a
  Path Follower). The body follows the node and gets the velocity of that
  move, so what stands on it is carried along. A jump of more than 256 px in
  one frame is a teleport: it carries nothing.

```lua
-- A platform that goes back and forth every 2 seconds.
function Platform:ready() self.t = 0 end
function Platform:update(dt)
    self.t = self.t + dt
    local dir = (math.floor(self.t / 2) % 2 == 0) and 1 or -1
    self.node:set_linear_velocity(80 * dir, 0)
end
```

Turn on **One Way** for a jump-through platform: bodies and Character
Movers pass up through it and land on top. It raises `collision_started` / `collision_ended` like the
other bodies, once per body touching it even when either one has several
shapes.
