#!/usr/bin/env python3
"""Builds the New Project templates (templates/<id>/) from the level maps,
scripts and art below (TODO E.2; editor/project_templates.odin lists them).

    python3 scripts/templates/make_templates.py            # all
    python3 scripts/templates/make_templates.py platformer # one

Each template is a complete project folder: project.json, scenes/, scripts/,
textures/ (Kenney CC0 art from assets/kenney/), a README.md and
template.json (name, description, icon, order). Levels are drawn as text
maps here and turned into TileMap data / nodes, so they're easy to change:
edit, run this, open the template in the editor.
"""
import json
import os
import shutil
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
KENNEY = os.path.join(ROOT, "assets", "kenney")
OUT = os.path.join(ROOT, "templates")
SCRIPTS = os.path.join(os.path.dirname(__file__), "scripts")


# --- helpers -------------------------------------------------------------------

def rle(cells):
    """Row-major tile indices -> TileMap "data" ([[count, tile], ...])."""
    out = []
    for t in cells:
        if out and out[-1][1] == t:
            out[-1][0] += 1
        else:
            out.append([1, t])
    return out


def tilemap(name, tileset, tile, grid, solid=False, layer=1, z=0, pos=(0, 0)):
    h = len(grid)
    w = len(grid[0])
    cells = [grid[r][c] for r in range(h) for c in range(w)]
    return {
        "type": "TileMapNode", "name": name, "position": list(pos), "layer": layer, "z_index": z,
        "tilemap": {"tileset": tileset, "tile_size": [tile, tile], "map_size": [w, h], "data": rle(cells)},
        "properties": {"solid": solid},
    }


def sprite(name, sheet, grid, anims, default=None, pos=(0, 0), pivot=(0.5, 0.5), layer=2, z=0, fps=8):
    """An AnimationPlayerNode: anims = {name: ([cells], fps, loop)}."""
    first = default or next(iter(anims))
    return {
        "type": "AnimationPlayerNode", "name": name, "position": list(pos), "pivot": list(pivot),
        "layer": layer, "z_index": z, "fps": fps, "animation": first, "default_animation": first,
        "animations": [
            {"name": n, "loop": loop, "fps": f, "sheet": sheet, "grid": list(grid), "cells": cells,
             "start": 0, "end": len(cells) - 1}
            for n, (cells, f, loop) in anims.items()
        ],
        "properties": {"autoplay": True},
    }


PIXEL_FONT = "fonts/kenney_pixel.ttf"  # Kenney Pixel (CC0): crisp at 16 / 32 px


def text(name, value, pos, size=16, align="Left", color="#ffffffff", layer=7, pivot=(0, 0)):
    return {"type": "TextNode", "name": name, "position": list(pos), "pivot": list(pivot), "layer": layer,
            "properties": {"text": value, "font": PIXEL_FONT, "fontSize": size, "align": align, "color": color}}


def action(name, *bindings):
    out = []
    for b in bindings:
        if b.startswith("pad:"):
            out.append({"button": b[4:]})
        elif b.startswith("axis:"):
            axis, sign = b[5:].split(":")
            out.append({"axis": axis, "positive": sign == "+", "deadzone": 0.3})
        elif b.startswith("mouse:"):
            out.append({"mouse": b[6:]})
        else:
            out.append({"key": b})
    return {"name": name, "bindings": out}


MOVE_ACTIONS = [
    action("move_left", "A", "LEFT", "pad:LEFT_FACE_LEFT", "axis:LEFT_X:-"),
    action("move_right", "D", "RIGHT", "pad:LEFT_FACE_RIGHT", "axis:LEFT_X:+"),
    action("move_up", "W", "UP", "pad:LEFT_FACE_UP", "axis:LEFT_Y:-"),
    action("move_down", "S", "DOWN", "pad:LEFT_FACE_DOWN", "axis:LEFT_Y:+"),
]


def project(name, scenes, actions, virtual=(320, 180), gravity=(0, 900), pixel=True, globals_=None):
    p = {
        "name": name, "version": "0.1.0", "initial_scene": scenes[0],
        "window": {"title": name, "width": 1280, "height": 720,
                   "virtual_width": virtual[0], "virtual_height": virtual[1], "target_fps": 60},
        "video": {"fullscreen": False, "vsync": True, "resizable": True, "msaa": False, "high_dpi": False,
                  "sharp_scaling": pixel, "integer_scaling": pixel, "pixel_snap": pixel, "smooth_camera": pixel},
        "audio": {"master_volume": 1, "music_volume": 1, "sfx_volume": 1},
        "physics": {"gravity": list(gravity), "debug_draw": False},
        "input": {"actions": actions},
        "scenes": scenes,
    }
    if globals_:
        p["globals"] = globals_
    return p


def scene(name, children, background=(0, 0, 0, 255)):
    return {"name": name, "background": list(background),
            "root": {"type": "Node", "name": "root", "children": children}}


def grid_of(rows, width=None):
    width = width or max(len(r) for r in rows)
    for i, r in enumerate(rows):
        assert len(r) <= width, f"row {i} is {len(r)} wide (max {width})"
    return [r.ljust(width, ".") for r in rows]


class Template:
    def __init__(self, tid, name, description, icon, order):
        self.id = tid
        self.dir = os.path.join(OUT, tid)
        self.meta = {"name": name, "description": description, "icon": icon, "order": order}

    def begin(self):
        # (preview.png is made by test_templates.py --previews: kept.)
        pv = os.path.join(self.dir, "preview.png")
        preview = open(pv, "rb").read() if os.path.isfile(pv) else None
        if os.path.isdir(self.dir):
            shutil.rmtree(self.dir)
        if preview:
            os.makedirs(self.dir)
            open(pv, "wb").write(preview)
        for sub in ("scenes", "scripts", "textures", "audio", "components"):
            os.makedirs(os.path.join(self.dir, sub), exist_ok=True)
        self.write("template.json", json.dumps(self.meta, indent=2) + "\n")
        self.art("fonts/kenney_pixel.ttf", PIXEL_FONT)

    def write(self, rel, data):
        p = os.path.join(self.dir, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w") as f:
            f.write(data)

    def json(self, rel, obj):
        self.write(rel, json.dumps(obj, indent=1) + "\n")

    def art(self, src, rel):
        dst = os.path.join(self.dir, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copyfile(os.path.join(KENNEY, src), dst)

    def script(self, name, rel=None, src=None):
        """scripts/<name>.lua from scripts/templates/scripts/<template>/<name>.lua"""
        with open(os.path.join(SCRIPTS, src or self.id, name + ".lua")) as f:
            self.write(rel or f"scripts/{name}.lua", f.read())

    def license(self, *packs):
        lines = ["Art and font: Kenney (www.kenney.nl), Creative Commons Zero (CC0) - free for any",
                 "use, no attribution required. Packs: " + ", ".join(packs + ("Kenney Fonts",)) + ".", ""]
        self.write("textures/LICENSE-ART.txt", "\n".join(lines))


# --- platformer ------------------------------------------------------------------

PLATFORMER_LEVEL = [
    "............................................................",
    "............................................................",
    "............................................................",
    "...........................ooo..............................",
    "..........................=====..............ooo............",
    "................ooo............................===..........",
    "...............=====....................###.............D..",
    "......o.o..............................#####..........######",
    ".P.................e........^^......########....e....#######",
    "################################..##########################",
    "################################..##########################",
    "################################..##########################",
]


def _level2():
    """Level 2 (built here: gaps a jump clears - 2 tiles; steps of 2 tiles)."""
    W, H = 68, 11
    g = [["."] * W for _ in range(H)]

    def put(c, r, ch):
        g[r][c] = ch

    for c in range(W):  # ground (rows 8-10), two pits
        if c not in range(10, 12) and c not in range(28, 30):
            for r in range(8, H):
                put(c, r, "#")
    for c in range(49, 54):  # a block to climb (2 tiles)
        put(c, 6, "#"); put(c, 7, "#")
    for c in range(60, W):  # the door's ledge (2 tiles up)
        put(c, 6, "#"); put(c, 7, "#")
    for c in range(14, 19):
        put(c, 5, "=")
    for c in range(31, 36):
        put(c, 5, "=")
    for c, r in ((7, 6), (9, 6), (15, 4), (16, 4), (17, 4), (10, 5), (28, 5), (32, 4), (33, 4), (34, 4),
                 (50, 4), (51, 4), (52, 4), (63, 5)):
        put(c, r, "o")
    for c in (39, 40):  # (two: a jump clears them)
        put(c, 7, "^")
    put(23, 7, "e"); put(51, 5, "e")  # (the second patrols the block)
    put(1, 7, "P")
    put(65, 5, "D")
    return ["".join(row) for row in g]


PLATFORMER_LEVEL2 = _level2()


def platformer_scene(t, rows, name, next_level=""):
    """A platformer level (scene children) from a text map:
    # ground, = one-way platform, o coin, ^ spikes, e enemy, P player, D door."""
    T = 18  # tile size
    TILES, CHARS = "textures/tiles.png", "textures/characters.png"
    TG, CG = (20, 9), (9, 3)  # sheet grids
    rows = grid_of(rows)
    H, W = len(rows), len(rows[0])

    def at(c, r):
        return rows[r][c] if 0 <= r < H and 0 <= c < W else "."

    solid = [[-1] * W for _ in range(H)]
    decor = [[-1] * W for _ in range(H)]
    children = []
    platforms, coins, spikes, enemies = [], [], [], []
    player = door = None
    for r in range(H):
        for c in range(W):
            ch = rows[r][c]
            if ch == "#":
                left, right = at(c - 1, r) == "#", at(c + 1, r) == "#"
                if at(c, r - 1) != "#":  # grass on top
                    solid[r][c] = 2 if left and right else (1 if right else (3 if left else 0))
                    if at(c, r - 1) == "." and (c * 7 + r * 3) % 9 == 0:
                        decor[r - 1][c] = 124 if c % 2 else 125  # grass tufts
                else:
                    solid[r][c] = (4, 5, 24, 25)[(c * 5 + r * 3) % 4]  # plain dirt
            elif ch == "=":
                left, right = at(c - 1, r) == "=", at(c + 1, r) == "="
                decor[r][c] = 49 if left and right else (48 if right else (50 if left else 47))
                if not left:
                    n = 0
                    while at(c + n, r) == "=":
                        n += 1
                    platforms.append((c, r, n))
            elif ch == "o":
                coins.append((c, r))
            elif ch == "^":
                spikes.append((c, r))
            elif ch == "e":
                enemies.append((c, r))
            elif ch == "P":
                player = (c, r)
            elif ch == "D":
                door = (c, r)
    assert player and door

    def center(c, r):
        return [c * T + T / 2, r * T + T / 2]

    children.append({"type": "CameraNode", "name": "Camera", "position": center(*player), "follow": "../Player",
                     "properties": {"isCurrent": True, "followMode": "SingleTarget", "dragType": "SmoothDamp",
                                    "hasLimits": True, "leftLimit": 0, "rightLimit": W * T, "topLimit": -4 * T,
                                    "bottomLimit": H * T}})
    # The backdrop: sky, then trees and clouds, then fill - scrolled slower than
    # the level (parallax.lua).
    BW = (W * T) // 24 + 2
    back = [[(9, 11)[c % 2] for c in range(BW)]] + [[16 + c % 4 for c in range(BW)] for _ in range(4)]
    children.append({**tilemap("Backdrop", "textures/backgrounds.png", 24, back, layer=0, pos=(0, (H - 6) * T)),
                     "script": {"path": "scripts/parallax.lua", "properties": {"factor": 0.5}}})
    children.append(tilemap("Decor", TILES, T, decor, layer=1, z=-1))
    children.append(tilemap("Level", TILES, T, solid, solid=True, layer=1))
    for i, (c, r, n) in enumerate(platforms):
        children.append({"type": "StaticBodyNode", "name": f"Platform{i + 1}", "position": [c * T + n * T / 2, r * T + 3],
                         "properties": {"oneWay": True}, "shapes": [{"type": "Box", "size": [n * T, 6]}]})
    for i, (c, r) in enumerate(coins):
        children.append({"type": "AreaNode", "name": f"Coin{i + 1}", "position": center(c, r), "tags": ["coin"],
                         "shapes": [{"type": "Circle", "radius": 6}], "script": {"path": "scripts/coin.lua"},
                         "children": [sprite("Sprite", TILES, TG, {"spin": ([151, 152], 6, True)}, layer=2)]})
    for i, (c, r) in enumerate(spikes):
        children.append({"type": "AreaNode", "name": f"Spikes{i + 1}", "position": center(c, r),
                         "shapes": [{"type": "Box", "size": [14, 6], "offset": [0, 5]}], "script": {"path": "scripts/hazard.lua"},
                         "children": [sprite("Sprite", TILES, TG, {"idle": ([68], 1, False)}, layer=2)]})
    for i, (c, r) in enumerate(enemies):
        children.append({
            "type": "CharacterMoverNode", "name": f"Enemy{i + 1}", "position": center(c, r), "tags": ["enemy"],
            "shapes": [{"type": "Capsule", "radius": 6, "size": [12, 4]}],
            "properties": {"controlMode": "Script", "categoryLayers": ["Layer3"], "maskLayers": ["Layer1"]},
            "script": {"path": "scripts/enemy.lua", "properties": {"speed": 30}},
            "children": [
                sprite("Sprite", CHARS, CG, {"walk": ([18, 19], 4, True), "squashed": ([20], 1, False)},
                       pos=(0, -3), layer=2),
                {"type": "AreaNode", "name": "Hitbox", "shapes": [{"type": "Box", "size": [16, 14]}],
                 "script": {"path": "scripts/enemy_hitbox.lua"}},
            ]})
    dc, dr = door
    children.append({"type": "AreaNode", "name": "Door", "position": [dc * T + T / 2, dr * T + T / 2],
                     "shapes": [{"type": "Box", "size": [10, 16]}],
                     "script": {"path": "scripts/goal.lua", "properties": {"next_level": next_level}},
                     "children": [sprite("Top", TILES, TG, {"idle": ([130], 1, False)}, pos=(0, -T), layer=1),
                                  sprite("Bottom", TILES, TG, {"idle": ([150], 1, False)}, layer=1)]})
    children.append({
        "type": "CharacterMoverNode", "name": "Player", "position": center(*player), "tags": ["player"],
        "shapes": [{"type": "Capsule", "radius": 6, "size": [12, 6]}],
        "properties": {"controlMode": "Script", "categoryLayers": ["Layer2"], "maskLayers": ["Layer1"]},
        "script": {"path": "scripts/player.lua", "properties": {"fall_limit": H * T + 40}},
        "children": [sprite("Sprite", CHARS, CG, {"idle": ([0], 1, True), "run": ([0, 1], 8, True),
                                                  "jump": ([1], 1, False)}, pos=(0, -3), layer=3)]})
    children.append({"type": "Node", "name": "HUD", "script": {"path": "scripts/hud.lua"}, "children": [
        text("Coins", "Coins 0", (8, 4), color="#3c3c5aff"),
        text("Message", "", (160, 70), size=32, align="Center", pivot=(0.5, 0.5), color="#3c3c5aff"),
    ]})
    return scene(name, children, background=(223, 246, 245, 255))


def platformer_art(t):
    t.art("pixel-platformer/tilemap_packed.png", "textures/tiles.png")
    t.art("pixel-platformer/tilemap-characters_packed.png", "textures/characters.png")
    t.art("pixel-platformer/tilemap-backgrounds_packed.png", "textures/backgrounds.png")
    t.license("Pixel Platformer")


PLATFORMER_SCRIPTS = ("player", "enemy", "enemy_hitbox", "coin", "hazard", "goal", "hud", "parallax")
PLATFORMER_ACTIONS = MOVE_ACTIONS + [action("jump", "SPACE", "W", "UP", "pad:RIGHT_FACE_DOWN")]


def platformer():
    t = Template("platformer", "Platformer",
                 "Run and jump through a level: coins, spikes, an enemy to stomp, a door to the end. "
                 "Pixel art, a camera that follows, a HUD.", "person-running", 1)
    t.begin()
    platformer_art(t)
    t.json("scenes/level1.scene.json", platformer_scene(t, PLATFORMER_LEVEL, "level1"))
    t.json("project.json", project("Platformer", ["scenes/level1.scene.json"], PLATFORMER_ACTIONS))
    for s_ in PLATFORMER_SCRIPTS:
        t.script(s_)
    with open(os.path.join(SCRIPTS, "platformer", "README.md")) as f:
        t.write("README.md", f.read())
    return t


def adventure():
    """A sample: the platformer grown into a small game - a title screen
    (Play / Continue), two levels with saved progress, a pause menu."""
    t = Template("adventure", "Platformer Adventure (sample)",
                 "The platformer grown into a small game: a title screen, two levels, saved progress, "
                 "a pause menu - how the pieces fit together.", "gamepad", 50)
    t.meta["kind"] = "sample"
    t.begin()
    platformer_art(t)

    def with_pause(sc):
        sc["root"]["children"].append({
            "type": "Node", "name": "PauseMenu", "layer": 7, "pause_mode": "always", "visible": False,
            "script": {"path": "scripts/menu.lua", "properties": {"kind": "pause"}},
            "children": [
                {"type": "UIContainerNode", "name": "Shade", "layer": 7, "position": [0, 0],
                 "properties": {"size": [320, 180], "drawBackground": True, "drawBorder": False, "showHeader": False,
                                "backgroundColor": "#14141ec8"}},
                text("Title", "Paused", (160, 46), size=32, align="Center", pivot=(0.5, 0.5)),
                text("Item1", "Resume", (160, 84), align="Center", pivot=(0.5, 0.5)),
                text("Item2", "Restart level", (160, 102), align="Center", pivot=(0.5, 0.5)),
                text("Item3", "Title screen", (160, 120), align="Center", pivot=(0.5, 0.5)),
            ]})
        return sc

    t.json("scenes/level1.scene.json", with_pause(platformer_scene(t, PLATFORMER_LEVEL, "level1", "scenes/level2.scene.json")))
    t.json("scenes/level2.scene.json", with_pause(platformer_scene(t, PLATFORMER_LEVEL2, "level2", "scenes/title.scene.json")))
    t.json("scenes/title.scene.json", scene("title", [
        {"type": "CameraNode", "name": "Camera", "position": [160, 90], "properties": {"isCurrent": True}},
        tilemap("Backdrop", "textures/backgrounds.png", 24, [[(9, 11)[c % 2] for c in range(15)]] + [[16 + c % 4 for c in range(15)] for _ in range(3)], layer=0, pos=(0, 84)),
        {"type": "Node", "name": "Menu", "layer": 7, "script": {"path": "scripts/menu.lua", "properties": {"kind": "title"}},
         "children": [
             text("Title", "Platformer Adventure", (160, 40), size=32, align="Center", pivot=(0.5, 0.5), color="#3c3c5aff"),
             text("Item1", "New game", (160, 88), align="Center", pivot=(0.5, 0.5), color="#3c3c5aff"),
             text("Item2", "Continue", (160, 106), align="Center", pivot=(0.5, 0.5), color="#3c3c5aff"),
             text("Hint", "", (160, 160), align="Center", pivot=(0.5, 0.5), color="#3c3c5a99"),
         ]},
    ], background=(223, 246, 245, 255)))
    t.json("project.json", project("Platformer Adventure",
                                   ["scenes/title.scene.json", "scenes/level1.scene.json", "scenes/level2.scene.json"],
                                   PLATFORMER_ACTIONS + [action("pause", "ESCAPE", "P", "pad:MIDDLE_RIGHT"),
                                                         action("confirm", "ENTER", "SPACE", "pad:RIGHT_FACE_DOWN")]))
    for s_ in PLATFORMER_SCRIPTS:
        if s_ != "goal":
            t.script(s_, src="platformer")
    for s_ in ("goal", "menu"):
        with open(os.path.join(SCRIPTS, "adventure", s_ + ".lua")) as f:
            t.write(f"scripts/{s_}.lua", f.read())
    with open(os.path.join(SCRIPTS, "adventure", "README.md")) as f:
        t.write("README.md", f.read())
    return t


# --- top-down RPG -------------------------------------------------------------------

RPG_MAP = [
    "##############################",
    "#.......#..........#.........#",
    "#.P.....#...s......#.........#",
    "#.......#.......s..#....X....#",
    "#...N...+..........L.........#",
    "#.......#....s.....#.........#",
    "#.......#.........c#.........#",
    "#..p....#..........#.........#",
    "#.......#..........#.........#",
    "##############################",
]


def rpg():
    t = Template("rpg", "Top-down RPG",
                 "Explore a small dungeon: talk to a wizard, fight slimes with a sword, find the key in a "
                 "chest, unlock the door and escape. Hearts, a potion, dialogue.", "dungeon", 2)
    t.begin()
    t.art("tiny-dungeon/tilemap_packed.png", "textures/dungeon.png")
    t.art("pixel-platformer/tilemap_packed.png", "textures/ui.png")  # hearts
    t.license("Tiny Dungeon", "Pixel Platformer (hearts)")
    T = 16
    SHEET, SG = "textures/dungeon.png", (12, 11)
    rows = grid_of(RPG_MAP)
    H, W = len(rows), len(rows[0])
    walls = [[-1] * W for _ in range(H)]
    floor = [[-1] * W for _ in range(H)]
    ents = {}
    for r in range(H):
        for c in range(W):
            ch = rows[r][c]
            if ch == "#":
                walls[r][c] = 40
            else:
                floor[r][c] = (48, 48, 49, 50, 48, 48)[(c * 7 + r * 5) % 6]
                if ch not in ".+":
                    ents.setdefault(ch, []).append((c, r))

    def center(c, r):
        return [c * T + T / 2, r * T + T / 2]

    def char(name, cell, pos, script, tags=(), props=None, extra=()):
        return {"type": "CharacterMoverNode", "name": name, "position": pos, "tags": list(tags),
                "shapes": [{"type": "Capsule", "radius": 5, "size": [10, 2]}],
                "properties": {"controlMode": "Script", "categoryLayers": ["Layer2"], "maskLayers": ["Layer1"]},
                "script": {"path": script, "properties": props or {}},
                "children": [sprite("Sprite", SHEET, SG, {"idle": ([cell], 1, True)}, pos=(0, -3), layer=2)] + list(extra)}

    (pc, pr), = ents["P"]
    children = [
        {"type": "CameraNode", "name": "Camera", "position": center(pc, pr), "follow": "../Player",
         "properties": {"isCurrent": True, "followMode": "SingleTarget", "dragType": "SmoothDamp",
                        "hasLimits": True, "leftLimit": 0, "rightLimit": W * T, "topLimit": -T, "bottomLimit": H * T + T}},
        tilemap("Floor", SHEET, T, floor, layer=1, z=-1),
        tilemap("Walls", SHEET, T, walls, solid=True, layer=1),
    ]
    (nc, nr), = ents["N"]
    children.append({"type": "Node", "name": "Wizard", "position": center(nc, nr), "tags": ["interactable"],
                     "script": {"path": "scripts/npc.lua"},
                     "children": [sprite("Sprite", SHEET, SG, {"idle": ([84], 1, True)}, pos=(0, -2), layer=2)]})
    for i, (c, r) in enumerate(ents.get("s", [])):
        children.append(char(f"Slime{i + 1}", 108, center(c, r), "scripts/slime.lua", tags=["enemy"]))
    for i, (c, r) in enumerate(ents.get("p", [])):
        children.append({"type": "AreaNode", "name": f"Potion{i + 1}", "position": center(c, r),
                         "shapes": [{"type": "Circle", "radius": 6}], "script": {"path": "scripts/potion.lua"},
                         "children": [sprite("Sprite", SHEET, SG, {"idle": ([115], 1, True)}, layer=2)]})
    (cc, cr), = ents["c"]
    children.append({"type": "Node", "name": "Chest", "position": center(cc, cr), "tags": ["interactable"],
                     "script": {"path": "scripts/chest.lua"},
                     "children": [sprite("Sprite", SHEET, SG, {"closed": ([89], 1, True), "open": ([91], 1, True)}, layer=2)]})
    (lc, lr), = ents["L"]
    children.append({"type": "StaticBodyNode", "name": "LockedDoor", "position": center(lc, lr), "tags": ["interactable"],
                     "shapes": [{"type": "Box", "size": [T, T]}], "script": {"path": "scripts/locked_door.lua"},
                     "children": [sprite("Sprite", SHEET, SG, {"closed": ([46], 1, True), "open": ([34], 1, True)}, layer=1)]})
    (xc, xr), = ents["X"]
    children.append({"type": "AreaNode", "name": "Exit", "position": center(xc, xr),
                     "shapes": [{"type": "Box", "size": [10, 10]}], "script": {"path": "scripts/exit.lua"},
                     "children": [sprite("Sprite", SHEET, SG, {"idle": ([22], 1, True)}, layer=1)]})
    children.append(char("Player", 96, center(pc, pr), "scripts/player.lua", tags=["player"], extra=[
        sprite("Sword", SHEET, SG, {"idle": ([104], 1, True)}, pos=(8, -2), layer=3),
    ]))
    hearts = [sprite(f"Heart{i + 1}", "textures/ui.png", (20, 9), {"full": ([44], 1, True), "empty": ([46], 1, True)},
                     pos=(10 + i * 14, 10), layer=7) for i in range(3)]
    children.append({"type": "Node", "name": "HUD", "script": {"path": "scripts/hud.lua"}, "children": hearts + [
        text("Key", "", (56, 2), color="#f5d76eff"),
        text("Hint", "", (160, 158), align="Center", pivot=(0.5, 0)),
        text("Message", "", (160, 60), size=32, align="Center", pivot=(0.5, 0.5)),
    ]})
    children.append({"type": "DialogueNode", "name": "Dialogue", "position": [10, 118], "layer": 7,
                     "properties": {"size": [300, 52], "font": PIXEL_FONT, "fontSize": 16, "padding": 6, "revealSpeed": 60,
                                    "panelColor": "#1c1820f5", "advanceAction": "confirm"}})
    t.json("scenes/dungeon.scene.json", scene("dungeon", children, background=(37, 19, 26, 255)))
    t.json("project.json", project("Top-down RPG", ["scenes/dungeon.scene.json"], MOVE_ACTIONS + [
        action("attack", "SPACE", "J", "pad:RIGHT_FACE_LEFT"),
        action("interact", "E", "K", "pad:RIGHT_FACE_DOWN"),
        action("confirm", "E", "ENTER", "K", "pad:RIGHT_FACE_DOWN"),
    ], gravity=(0, 0)))
    for s_ in ("player", "slime", "npc", "chest", "locked_door", "potion", "exit", "hud"):
        t.script(s_)
    with open(os.path.join(SCRIPTS, "rpg", "README.md")) as f:
        t.write("README.md", f.read())
    return t


# --- shmup ----------------------------------------------------------------------

def shmup():
    t = Template("shmup", "Shoot 'em up",
                 "Fly right through waves of enemies: shoot, dodge their bullets, keep your three lives. "
                 "Pooled bullets, explosions, a scrolling sea, a saved high score.", "jet-fighter", 3)
    t.begin()
    t.art("pixel-shmup/ships_packed.png", "textures/ships.png")
    t.art("pixel-shmup/tiles_packed.png", "textures/tiles.png")
    t.license("Pixel Shmup")
    SHIPS, SG = "textures/ships.png", (4, 6)
    TILES, TG = "textures/tiles.png", (12, 10)
    # The sea: water with islands, 2 screens wide (the second repeats the
    # first: scroll.lua wraps it).
    W, H = 40, 12
    sea = [[42] * W for _ in range(H)]
    for (ic, ir) in ((3, 2), (12, 7), (22, 1), (31, 6)):
        for dr, row in enumerate(((37, 38, 39), (49, 50, 51), (61, 62, 63))):
            for dc, cell in enumerate(row):
                sea[ir + dr][ic + dc] = cell
                sea[ir + dr][(ic + dc + 20) % W] = cell
    explosion = sprite("Sprite", TILES, TG, {"boom": ([4, 5, 6, 7, 8], 14, False)}, layer=3)
    t.json("components/player_bullet.component.json", {
        "type": "Node", "name": "PlayerBullet", "tags": ["player_bullet"],
        "script": {"path": "scripts/bullet.lua", "properties": {"speed": 260, "dir_x": 1, "radius": 3}},
        "children": [{**sprite("Sprite", TILES, TG, {"idle": ([0], 1, True)}, layer=3), "rotation": 90}]})
    t.json("components/enemy_bullet.component.json", {
        "type": "Node", "name": "EnemyBullet", "tags": ["enemy_bullet"],
        "script": {"path": "scripts/bullet.lua", "properties": {"speed": 110, "dir_x": -1, "radius": 3}},
        "children": [sprite("Sprite", TILES, TG, {"idle": ([3], 1, True)}, layer=3)]})
    for kind, cell, props in (("drifter", 17, {"speed": 50, "wobble": 18, "hp": 1, "shoots": False, "points": 100}),
                              ("shooter", 21, {"speed": 35, "wobble": 6, "hp": 3, "shoots": True, "points": 300})):
        t.json(f"components/{kind}.component.json", {
            "type": "Node", "name": kind.capitalize(), "tags": ["enemy"],
            "script": {"path": "scripts/enemy.lua", "properties": props},
            "children": [{**sprite("Sprite", SHIPS, SG, {"idle": ([cell], 1, True)}, layer=2), "rotation": 90}]})
    t.json("components/explosion.component.json", {
        "type": "Node", "name": "Explosion", "script": {"path": "scripts/explosion.lua"}, "children": [explosion]})
    children = [
        {"type": "CameraNode", "name": "Camera", "position": [160, 90], "properties": {"isCurrent": True}},
        {**tilemap("Sea", TILES, 16, sea, layer=0, pos=(0, -6)),
         "script": {"path": "scripts/scroll.lua", "properties": {"speed": 20, "wrap": 320}}},
        {"type": "Node", "name": "Player", "position": [40, 90], "tags": ["player"],
         "script": {"path": "scripts/player.lua"},
         "children": [{**sprite("Sprite", SHIPS, SG, {"idle": ([1], 1, True)}, layer=2), "rotation": -90}]},
        {"type": "Node", "name": "Spawner", "script": {"path": "scripts/spawner.lua"}},
        {"type": "Node", "name": "Shots"},  # bullets, enemies, explosions go here
        {"type": "Node", "name": "HUD", "script": {"path": "scripts/hud.lua"}, "children": [
            text("Score", "Score 0", (6, 2), color="#1d3b4cff"),
            text("High", "Best 0", (314, 2), align="Right", pivot=(1, 0), color="#1d3b4cff"),
            text("Lives", "Lives 3", (6, 162), color="#1d3b4cff"),
            text("Message", "", (160, 80), size=32, align="Center", pivot=(0.5, 0.5), color="#1d3b4cff"),
        ]},
    ]
    t.json("scenes/game.scene.json", scene("game", children, background=(140, 214, 225, 255)))
    t.json("project.json", project("Shoot 'em up", ["scenes/game.scene.json"], MOVE_ACTIONS + [
        action("fire", "SPACE", "J", "pad:RIGHT_FACE_DOWN"),
    ], gravity=(0, 0)))
    for s_ in ("player", "bullet", "enemy", "spawner", "explosion", "scroll", "hud"):
        t.script(s_)
    with open(os.path.join(SCRIPTS, "shmup", "README.md")) as f:
        t.write("README.md", f.read())
    return t


# --- puzzle (Sokoban) ------------------------------------------------------------------

# The levels (also in scripts/puzzle.lua - this list checks they can be solved):
# # wall, . goal, $ crate, * crate on a goal, @ player, + player on a goal.
PUZZLE_LEVELS = [
    ["#######", "#     #", "# @$ .#", "#     #", "#######"],
    ["########", "#      #", "#  $ . #", "# @$ . #", "#      #", "########"],
    ["#########", "#   #   #", "# $ $ $ #", "#  . .  #", "## ### .#", " #  @   #", " ########"],
]


def sokoban_solve(rows, limit=2_000_000):
    """Breadth-first: the shortest solution as moves (UDLR), None if none."""
    from collections import deque
    walls, goals, crates, player = set(), set(), set(), None
    for r, row in enumerate(rows):
        for c, ch in enumerate(row):
            if ch == "#":
                walls.add((c, r))
            if ch in ".*+":
                goals.add((c, r))
            if ch in "$*":
                crates.add((c, r))
            if ch in "@+":
                player = (c, r)
    moves = {"U": (0, -1), "D": (0, 1), "L": (-1, 0), "R": (1, 0)}
    start = (player, frozenset(crates))
    seen, q = {start: None}, deque([start])
    while q:
        st = q.popleft()
        p, cr = st
        if all(x in goals for x in cr):
            path = []
            while seen[st]:
                st, m = seen[st]
                path.append(m)
            return "".join(reversed(path))
        for m, (dx, dy) in moves.items():
            n = (p[0] + dx, p[1] + dy)
            if n in walls:
                continue
            ncr = cr
            if n in cr:
                b = (n[0] + dx, n[1] + dy)
                if b in walls or b in cr:
                    continue
                ncr = (cr - {n}) | {b}
            ns = (n, frozenset(ncr))
            if ns not in seen:
                seen[ns] = (st, m)
                q.append(ns)
                if len(seen) > limit:
                    return None
    return None


def puzzle():
    t = Template("puzzle", "Puzzle (Sokoban)",
                 "Push every crate onto a target. Three levels written as text in a script, undo, restart, "
                 "a move counter, smooth moves. Add levels by typing them.", "puzzle-piece", 4)
    for i, lv in enumerate(PUZZLE_LEVELS):
        assert sokoban_solve(lv) is not None, f"puzzle level {i + 1} can't be solved"
    t.begin()
    for name in ("ground", "wall", "crate", "crate_on_goal", "goal", "player"):
        t.art(f"sokoban/{name}.png", f"textures/{name}.png")
    t.license("Sokoban")
    # The levels go into the script as Lua strings.
    lua_levels = ",\n".join("    {\n" + ",\n".join(f'        "{row}"' for row in lv) + ",\n    }" for lv in PUZZLE_LEVELS)
    with open(os.path.join(SCRIPTS, "puzzle", "puzzle.lua")) as f:
        t.write("scripts/puzzle.lua", f.read().replace("--$LEVELS$", lua_levels))
    children = [
        {"type": "CameraNode", "name": "Camera", "position": [640, 360], "properties": {"isCurrent": True}},
        {"type": "Node", "name": "Board", "script": {"path": "scripts/puzzle.lua", "properties": {"start_level": 1}}},
        text("Level", "Level 1", (24, 16), size=32, color="#3b2a20ff"),
        text("Moves", "Moves 0", (1256, 16), size=32, align="Right", pivot=(1, 0), color="#3b2a20ff"),
        text("Help", "Arrows / WASD move   Z undo   R restart", (640, 690), size=32, align="Center", pivot=(0.5, 1), color="#3b2a20aa"),
        text("Message", "", (640, 80), size=48, align="Center", pivot=(0.5, 0.5), color="#3b2a20ff"),
    ]
    t.json("scenes/puzzle.scene.json", scene("puzzle", children, background=(229, 207, 167, 255)))
    t.json("project.json", project("Puzzle", ["scenes/puzzle.scene.json"], MOVE_ACTIONS + [
        action("undo", "Z", "U", "BACKSPACE", "pad:RIGHT_FACE_RIGHT"),
        action("restart", "R", "pad:RIGHT_FACE_UP"),
    ], virtual=(1280, 720), gravity=(0, 0), pixel=False))
    with open(os.path.join(SCRIPTS, "puzzle", "README.md")) as f:
        t.write("README.md", f.read())
    return t


TEMPLATES = {"platformer": platformer, "rpg": rpg, "shmup": shmup, "puzzle": puzzle, "adventure": adventure}

if __name__ == "__main__":
    which = sys.argv[1:] or list(TEMPLATES)
    for name in which:
        tpl = TEMPLATES[name]()
        print(f"templates/{tpl.id}")
