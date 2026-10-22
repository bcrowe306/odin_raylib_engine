# Portable ORE Format Specification (`.ore`) & JSON Project Architecture

The **Odin Raylib Engine (ORE)** format is a high-performance, single-file container and serialization standard designed for data-driven game development. It decouples game design from compiled Odin source code, allowing complete games, scenes, physics configurations, node graphs, assets, and Lua scripts to be declared in portable files and manipulated via visual GUI editors.

---

## 1. Architectural Overview

```
Development Mode (Loose Files)           Export / Distribution Mode (.ore)
┌─────────────────────────────────┐      ┌─────────────────────────────────┐
│ my_game/                        │      │ release_game.ore                │
│  ├── project.json               │ ───► │  ├── [ORE1 Header: 32 bytes]    │
│  ├── scenes/                    │ Pack │  ├── [Contiguous Compressed     │
│  │    ├── main.scene.json       │      │  │    Payloads: Textures, Audio,│
│  │    └── level2.scene.json     │      │  │    JSON, Lua Scripts]        │
│  └── assets/                    │      │  └── [Table of Contents (TOC)   │
│       ├── textures/hero.png     │      │       Offsets, Sizes, CRC32]    │
│       ├── audio/bgm.ogg         │      └─────────────────────────────────┘
│       └── scripts/player.lua    │
└─────────────────────────────────┘
```

The engine provides seamless **dual-mode resolution**:
1. **Loose Directory Mode (Git-Friendly Development)**: The engine reads loose files directly from disk (`project.json`, `scenes/*.scene.json`, loose PNG/WAV/Lua files). Fast iteration without re-packaging.
2. **Packaged Container Mode (`.ore` Release)**: All assets, scenes, and project configurations are compressed into a single binary archive. Can be embedded directly into release game binaries with `#load` or loaded from disk as a standalone portable package.

---

## 2. Binary Container Specification (`ORE1`)

The `.ore` file format uses an append-friendly layout where data payloads precede the Table of Contents (TOC), allowing high-throughput streaming and memory mapping:

```
+-------------------------------------------------------------+
| Header (32 bytes)                                           |
|   magic: [4]u8 ('O', 'R', 'E', '1')                          |
|   version: u32 (1)                                          |
|   fileCount: u32                                            |
|   tocOffset: u64                                            |
|   tocSize: u64                                              |
|   flags: u32 (reserved)                                     |
+-------------------------------------------------------------+
| Data Payloads (Variable length, contiguous)                 |
|   File 0: [Raw / Zlib-compressed byte slice]                |
|   File 1: [Raw / Zlib-compressed byte slice]                |
|   ...                                                       |
+-------------------------------------------------------------+
| Table of Contents (TOC at tocOffset)                        |
|   For each entry:                                           |
|     pathLen: u16                                            |
|     path: [pathLen]u8 (UTF-8, normalized relative path)     |
|     dataOffset: u64                                         |
|     compressedSize: u64                                     |
|     uncompressedSize: u64                                   |
|     compression: u8 (0 = Store, 1 = Deflate)                |
|     crc32: u32 (IEEE 802.3 CRC32 checksum)                  |
+-------------------------------------------------------------+
```

### Compression Strategy
- Individual files with uncompressed length $\le 64$ bytes or where compressed length $\ge$ uncompressed length are stored uncompressed (`Store`).
- Large files (scripts, scenes, JSON, raw textures, waveforms) are compressed using standard `zlib.deflate` (`Deflate`).
- Compressed payloads are decompressed on-demand with `zlib.uncompress` directly into target buffers.

---

## 3. Project Configuration Schema (`project.json`)

The root configuration defines window settings, physics parameters, and registered scenes:

```json
{
  "name": "My Galactic Game",
  "version": "1.0.0",
  "initial_scene": "scenes/main.scene.json",
  "window": {
    "title": "My Galactic Adventure",
    "width": 1280,
    "height": 720,
    "virtual_width": 1280.0,
    "virtual_height": 720.0,
    "target_fps": 60
  },
  "physics": {
    "gravity": [0.0, 980.0]
  },
  "scenes": [
    "scenes/main.scene.json",
    "scenes/credits.scene.json"
  ]
}
```

---

## 4. Scene Graph Schema (`*.scene.json`)

Scenes define the active camera, debug boundaries, and hierarchical node graphs. Node types and properties map directly to engine structures:

```json
{
  "name": "MainScene",
  "draw_bounds": false,
  "camera": {
    "target_position": [640.0, 360.0],
    "zoom": 1.0
  },
  "root": {
    "type": "Node",
    "name": "RootNode",
    "children": [
      {
        "type": "StaticBodyNode",
        "name": "GroundPlatform",
        "position": [640.0, 680.0],
        "scale": [1.0, 1.0],
        "rotation": 0.0,
        "enabled": true,
        "visible": true,
        "layer": 0,
        "physics": {
          "shape": {
            "type": "box",
            "size": [1280.0, 40.0],
            "density": 0.0,
            "friction": 0.8,
            "restitution": 0.0
          }
        }
      },
      {
        "type": "DynamicBodyNode",
        "name": "PlayerCrate",
        "position": [640.0, 150.0],
        "scale": [1.0, 1.0],
        "rotation": 0.0,
        "enabled": true,
        "visible": true,
        "layer": 1,
        "physics": {
          "gravity_scale": 1.0,
          "fixed_rotation": false,
          "linear_damping": 0.05,
          "angular_damping": 0.1,
          "shape": {
            "type": "box",
            "size": [48.0, 48.0],
            "density": 1.5,
            "friction": 0.5,
            "restitution": 0.2
          }
        },
        "script": {
          "path": "assets/scripts/crate_physics.lua",
          "properties": {
            "bounciness": 1.2,
            "can_shatter": true
          }
        }
      },
      {
        "type": "TextureNode",
        "name": "HeroSprite",
        "position": [400.0, 300.0],
        "texture_path": "assets/textures/hero.png",
        "origin": [32.0, 32.0]
      }
    ]
  }
}
```

---

## 5. Supported Node Types in JSON

| Node Type | Key Properties | Physics Support |
|---|---|---|
| `Node` | Basic transform (`position`, `scale`, `rotation`, `enabled`, `visible`, `layer`) | Hierarchy transform |
| `TextureNode` | `texture_path`, `origin` | Sprite rendering |
| `DynamicBodyNode` | `physics.gravity_scale`, `physics.fixed_rotation`, `physics.shape` | Box2D dynamic body |
| `StaticBodyNode` | `physics.shape` | Box2D static geometry |
| `CharacterMoverNode` | `character.speed`, `character.jump_speed`, `character.radius`, `character.height` | Kinematic character controller |
| `AreaNode` | `area.shape` | Overlap & trigger sensor |
| `RaycastNode` | `raycast.direction`, `raycast.length` | Geometric raycaster |
| `ParticleEmitterNode` | `particles.amount`, `particles.lifetime`, `particles.emitting` | Particle simulation |
| `TimerNode` | `timer.duration`, `timer.auto_start`, `timer.loop` | Frame-independent timer |
| `CameraNode` | `camera.zoom`, `camera.target_position` | 2D camera controls |

---

## 6. Engine API Usage in Odin

```odin
// 1. Load project directly from loose folder during development
game->loadProject("my_project_folder")

// 2. Export folder into standalone .ore container package
game.exportOre("my_project_folder", "exports/game.ore")

// 3. Load project directly from .ore container package
game->loadProject("exports/game.ore")

// 4. Serialize active scene to JSON string (for editor save operations)
jsonString := e.Scene_SerializeToJSON(activeScene)
```

---

## 7. Engine API Usage in Lua

```lua
-- Load a complete project (.ore or directory)
Project.load("assets/demo_project.ore")

-- Read arbitrary asset file from mounted .ore archive or disk
local scriptSource = Project.read_file("assets/scripts/orbiting_drone.lua")

-- Check file existence
if Project.has_file("scenes/bonus.scene.json") then
    -- File exists
end

-- Serialize current scene to JSON
local jsonStr = Project.serialize_scene()

-- Pack loose project directory into .ore package
Project.export_ore("assets/demo_project", "assets/demo_project.ore")
```
