#!/usr/bin/env python3
"""Writes a rendering benchmark project: a copy of the demo project with
scenes/bench_tiles.scene.json (a 400x400 tile map seen zoomed out) and
scenes/bench_sprites.scene.json (5000 separate sprites, 4 textures
interleaved) and bench_sprites_overlap.scene.json (the same, overlapping),
bench_particles / bench_particles_circles (5000 live particles), bench_particles_20k (20000 circles),
bench_lights (24 shadow-casting point lights over 300 static boxes),
bench_physics (1000 dynamic boxes falling into a walled pit),
bench_scripts (1000 sprites, each moved by a Lua update(dt)) and
bench_ysort (3000 sprites in a y-sorted parent, moving every frame).

  scripts/make_bench_project.py /tmp/rayzr_bench
  bin/runners/macos/runner /tmp/rayzr_bench --scene scenes/bench_tiles.scene.json --bench 300
"""
import json, random, shutil, sys
from pathlib import Path

out = Path(sys.argv[1] if len(sys.argv) > 1 else "/tmp/rayzr_bench")
root = Path(__file__).resolve().parent.parent
if out.exists():
    shutil.rmtree(out)
shutil.copytree(root / "assets" / "demo_project", out)

def node(type_, name, pos=(0, 0), scale=(1, 1), layer=0, **extra):
    n = {"type": type_, "name": name, "position": list(pos), "scale": list(scale), "rotation": 0.0,
         "enabled": True, "visible": True, "layer": layer}
    n.update(extra)
    return n

def scene(name, children):
    return {"name": name, "root": dict(node("Node", "root"), children=children)}

random.seed(7)
W = H = 400
tiles = [random.randrange(16) for _ in range(W * H)]
runs, i = [], 0
while i < len(tiles):
    j = i
    while j < len(tiles) and tiles[j] == tiles[i]:
        j += 1
    runs.append([j - i, tiles[i]])
    i = j
tilemap = node("TileMapNode", "Map", tilemap={"tileset": "textures/Tiles.png", "tile_size": [16, 16], "map_size": [W, H], "data": runs})
cam = node("CameraNode", "Cam", pos=(W * 8, H * 8), camera={"zoom": 0.25})
(out / "scenes" / "bench_tiles.scene.json").write_text(json.dumps(scene("bench_tiles", [cam, tilemap])))

# Sprites ~40 px wide: 50 px apart (separate) and 26 px apart (overlapping
# neighbours, which keep their order).
for name, step in (("bench_sprites", 50), ("bench_sprites_overlap", 26)):
    sprites = [node("CameraNode", "Cam", pos=(50 * step - 640, 25 * step - 360), camera={"zoom": 26 / step * 0.5})]
    for k in range(5000):
        sprites.append(node("TextureNode", f"S{k}", pos=((k % 100) * step - 640, (k // 100) * step - 360), scale=(0.08, 0.08), layer=1,
                            texture_path=f"textures/Asteroid_{k % 4 + 1}.png"))
    (out / "scenes" / f"{name}.scene.json").write_text(json.dumps(scene(name, sprites)))
# 5000 live particles (rectangles; circles).
for name, shape, amount in (("bench_particles", "Rectangle", 5000), ("bench_particles_circles", "Circle", 5000),
                            ("bench_particles_20k", "Circle", 20000)):
    emitter = node("ParticleEmitterNode", "Emitter", pos=(640, 360), layer=1,
                   particles={"amount": amount, "lifetime": 1.0, "emitting": True, "continuous": True, "velocity": 150},
                   properties={"emitter.shape": shape, "emitter.size": [4, 4], "emitter.spread": [300, 200],
                               "emitter.velocitySpread": 100, "emitter.velocityVariance": 1, "emitter.angleSpread": 180,
                               "emitter.angleVariance": 1, "emitter.colorVariance": 0.2})
    (out / "scenes" / f"{name}.scene.json").write_text(json.dumps(scene(name, [node("CameraNode", "Cam", pos=(640, 360)), emitter])))

def write(name, children, **extra):
    sc = scene(name, children)
    sc.update(extra)
    (out / "scenes" / f"{name}.scene.json").write_text(json.dumps(sc))

def box(type_, name, pos, size, **physics):
    physics["shape"] = {"type": "box", "size": list(size)}
    return node(type_, name, pos=pos, physics=physics)

# Lights: 24 shadow-casting point lights, 300 static boxes blocking them.
cam = node("CameraNode", "Cam", pos=(640, 360))
boxes = [box("StaticBodyNode", f"B{k}", ((k % 20) * 64 + 32, (k // 20) * 48 + 24), (24, 24)) for k in range(300)]
for k, b in enumerate(boxes):
    b["children"] = [node("TextureNode", "Sprite", scale=(0.05, 0.05), texture_path=f"textures/Asteroid_{k % 4 + 1}.png")]
lights = [node("LightNode", f"L{k}", pos=((k % 6) * 220 + 90, (k // 6) * 180 + 90), properties={"radius": 300, "energy": 1.2, "shadows": True})
          for k in range(24)]
write("bench_lights", [cam] + boxes + lights, ambient=[40, 40, 60, 255])

# Physics: 1000 dynamic boxes (with a sprite each) falling into a pit.
cam = node("CameraNode", "Cam", pos=(640, 360))
walls = [box("StaticBodyNode", "Floor", (640, 700), (1280, 40)),
         box("StaticBodyNode", "Left", (20, 360), (40, 720)),
         box("StaticBodyNode", "Right", (1260, 360), (40, 720))]
bodies = []
for k in range(1000):
    b = box("DynamicBodyNode", f"D{k}", ((k % 50) * 24 + 52, (k // 50) * 24 - 300), (16, 16), gravity_scale=1.0)
    b["children"] = [node("TextureNode", "Sprite", scale=(0.03, 0.03), texture_path=f"textures/Asteroid_{k % 4 + 1}.png")]
    bodies.append(b)
write("bench_physics", [cam] + walls + bodies)

# Lua: 1000 sprites, each with the demo's asteroid script (tumble, drift, wrap).
cam = node("CameraNode", "Cam", pos=(640, 360))
scripted = [node("TextureNode", f"A{k}", pos=((k % 40) * 32 + 16, (k // 40) * 28 + 16), scale=(0.05, 0.05), layer=1,
                 texture_path=f"textures/Asteroid_{k % 4 + 1}.png",
                 script={"path": "scripts/asteroid.lua", "properties": {"tumble_speed": 45.0, "drift_vx": 30.0 + k % 7, "drift_vy": -20.0}})
            for k in range(1000)]
write("bench_scripts", [cam] + scripted)

# Y-sort: 3000 sprites under a y_sort parent; a script moves the parent's
# children so the order changes every frame.
cam = node("CameraNode", "Cam", pos=(640, 360))
sorted_ = dict(node("Node", "World", layer=1), y_sort=True,
               children=[node("TextureNode", f"Y{k}", pos=(random.uniform(0, 1280), random.uniform(0, 720)), scale=(0.05, 0.05),
                              texture_path=f"textures/Asteroid_{k % 4 + 1}.png",
                              script={"path": "scripts/asteroid.lua", "properties": {"tumble_speed": 0.0, "drift_vx": 0.0, "drift_vy": random.uniform(-40, 40)}})
                         for k in range(3000)])
write("bench_ysort", [cam, sorted_])
print(f"Wrote {out}")
