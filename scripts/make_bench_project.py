#!/usr/bin/env python3
"""Writes a rendering benchmark project: a copy of the demo project with
scenes/bench_tiles.scene.json (a 400x400 tile map seen zoomed out) and
scenes/bench_sprites.scene.json (5000 separate sprites, 4 textures
interleaved) and bench_sprites_overlap.scene.json (the same, overlapping).

  scripts/make_bench_project.py /tmp/ore_bench
  bin/runners/macos/runner /tmp/ore_bench --scene scenes/bench_tiles.scene.json --bench 300
"""
import json, random, shutil, sys
from pathlib import Path

out = Path(sys.argv[1] if len(sys.argv) > 1 else "/tmp/ore_bench")
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
print(f"Wrote {out}")
