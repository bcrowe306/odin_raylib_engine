## The spawn list

The Inspector's **Spawn List** section holds the components it spawns
(saved in the scene as `"spawner": {"entries": [...]}`): pick each one, or
drag `.component.json` files onto the list from Assets. Each entry has a
**weight** (Random mode), a **count** (spawned each time it is picked) and
its own **offset**. The arrow moves an entry up: Sequential spawns in list
order.

| Mode | One spawn makes |
|---|---|
| Single | The first entry |
| All | Every entry |
| Random | One entry, picked by weight |
| Sequential | The next entry (then Loop, Ping Pong or Stop at the end) |
| Shuffle | A random entry - each one once before any repeats |

**Count** repeats the pick (a burst of 3 bullets: count 3).

## Where spawned nodes go

A spawned node starts at the spawner's **world** position (plus its
offsets, which turn and flip with it), rotation (**Inherit Rotation**) and
scale (**Inherit Scale**: a flipped player fires flipped bullets). The
spawner is an ordinary child, so it moves with its parent: put it in the
player's hand.

**Parent Mode** says where the nodes go: under the scene's root (the default
- a fireball doesn't follow the player once fired), the spawner's parent or
the spawner (they move with it), or the node at **Parent Path**.

**Spread** turns each one randomly (degrees), **Jitter** moves it randomly
(px), and **Speed** gives a dynamic or kinematic body root a velocity along
the facing.

## Spawning

```lua
-- A player's script: fire from the hand.
function Player:update(dt)
    if Input.is_action_pressed("fire") then
        self.node:get_node("Hand/Muzzle"):spawn()   -- the roots spawned (empty if held back)
    end
end
```

- From a script: `spawn([index])`, `spawn_at(x, y)`, `spawn_reset()`,
  `spawn_alive_count()`, `spawn_entries()`, `spawn_add(component)`.
- From a signal, no script: in the Inspector's **Signals**, connect any
  event (a timer's `timeout`, a button's `clicked`, an area's
  `body_entered`) to the spawner and pick **Spawn (no script)**.
- By itself: **Auto Spawn** every **Interval** seconds (+ **Interval
  Jitter**) after **Start Delay**.

**Cooldown** (seconds between spawns: a fire rate), **Chance**, **Max Alive**
(at most that many at once) and **Total Limit** (then `limit_reached`)
hold spawns back. **Use Pool** takes instances from the scene's
[pool](../../engine/docs/pooling.md) instead of making new ones.

Events: **`spawned`** (the new root - set it up in a handler),
**`limit_reached`**, **`list_finished`** (Sequential with Stop).

In the editor the selected spawner shows its spawn point, facing and
spread; in *Simulate* the Inspector has **Spawn Now** and the count of what
is alive.
