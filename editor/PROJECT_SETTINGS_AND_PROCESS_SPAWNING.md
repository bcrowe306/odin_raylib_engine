# Viewport Texture/Animation Rendering & Standalone Game Process Spawning

## Overview
This document details the fixes and features implemented to resolve:
1. **Viewport Texture & Animation Rendering**: Textures and multi-frame animations (e.g. ship hulls, asteroids, and animated exhaust plumes) rendering directly in the ImGui viewport texture target rather than blank bounding boxes.
2. **Project Settings & Default Scene Selection**: An interactive settings modal to configure project parameters, window properties, physics gravity presets, and specify the `initial_scene` saved into `project.json`.
3. **Standalone Game Process Architecture**: Launching the game engine in a distinct OS process (`os.process_start`) with `--project <path_or_rayzr>`, receiving the project definition and running the default scene independently of the editor.

---

## 1. Viewport Rendering Fixes

### A. Resource Manager Texture Pointer Stability
- **Issue**: `ResourceManager.textures` was previously stored as a dynamic array of value types (`[dynamic]Texture`). When loading multiple textures into the project, dynamic array growth triggered reallocations that invalidated pointers returned to nodes (`^Texture`), causing textures to become corrupt or fail to render.
- **Fix in [resource_manager.odin](../engine/resource_manager.odin)**: Changed storage to `textures: [dynamic]^Texture` with individual heap allocations (`new(Texture)`), ensuring permanent pointer stability throughout the application lifecycle.

### B. Texture Node Pivot & Coordinate Scaling
- **Issue**: Rotation origins were unscaled pixel coordinates (`textureNode.origin`), causing scaled nodes (e.g. `0.2` scale spaceships) to calculate wrong Raylib origin offsets and fly off-screen during drawing.
- **Fix in [texture_node.odin](../engine/texture_node.odin)**:
  ```odin
  origin := rl.Vector2{ textureNode.origin.x * scl.x, textureNode.origin.y * scl.y }
  rl.DrawTexturePro(tex^, src, dest, origin, rot, col)
  ```

### C. Live Animation Processing in Viewport
- **Fix in [frame_animation_node.odin](../engine/frame_animation_node.odin)**:
  Integrated real-time ticker processing (`fan.ticker->process()`) directly in `FrameAnimationNode_Render`. Animated exhaust plumes and multi-frame sprite sequences now advance frames and play smoothly in real-time in both the editor viewport and the running game.

### D. Viewport Bounding Box Polish
- **Update in [viewport.odin](viewport.odin)**:
  Replaced arbitrary 64x64 debug boxes with dimension calculations derived from actual sprite textures and physics collision shape definitions (`CircleShape.radius`, `BoxShape.size`).
  Bounding boxes are now focused on the actively selected node, or toggled on globally via the **Bounds** icon button (`ICON_FA_EYE`) in the toolbar.

---

## 2. Project Settings Dialog & Default Scene Selection

Implemented in [project_settings_dialog.odin](project_settings_dialog.odin) and accessible via the **Gear** icon (`ICON_FA_GEAR`) in the toolbar, the breadcrumb folder button, or menu bar (`File -> Project Settings...`):

- **Default Startup Scene Dropdown**:
  - Dynamically populates all scenes in the project directory (`scenes/main.scene.json`, `scenes/battle_arena.scene.json`).
  - Includes **"Use Current Scene"** button to immediately set the actively edited scene as startup.
  - Persists directly to `"initial_scene"` inside `project.json` using `Project_SaveConfigToFile`.
- **Display & Window Properties**:
  - Window title, target resolution width/height, target framerate (FPS).
- **Physics Configuration**:
  - 2D gravity vector with single-click presets for **Zero-G Space (0, 0)** and **Standard 2D Platformer (0, 9.8)**.

---

## 3. Launching Game in a Separate Process

### A. Engine Standalone Execution (`--project`)
Implemented in [main.odin](../main.odin):
- Added CLI parsing for `--project <path>` and `-p <path>`, supporting both project directories and `.rayzr` archive containers.
- `RunDataDrivenGame(projectPath)`:
  1. Inspects `project.json` for customized window title, resolution, and target FPS.
  2. Initializes Raylib and audio subsystem.
  3. Loads all project scenes and assets via `game->loadProject(projectPath)`.
  4. Activates the `initial_scene` configured in `project.json`.
  5. Executes the clean runtime game loop without editor ImGui overhead.

### B. Editor Process Management
Implemented in [editor_state.odin](editor_state.odin) and [toolbar.odin](toolbar.odin):
- **Play Button (`ICON_FA_PLAY`)**:
  - Automatically saves the active scene to disk.
  - Spawns the separate engine process: `os.process_start(os.Process_Desc{ command = {"./rayzr", "--project", state.projectPath} })`.
  - Captures PID and sets `state.gameProcessRunning = true`.
- **Stop Button (`ICON_FA_STOP`)**:
  - Safely sends `SIGTERM` / kills child process and resets running state.
- **Process Polling**:
  - Polled every editor frame via `Editor_CheckGameProcess` with non-blocking `os.process_wait(process, 0)`.

---

## 4. Verification & Automated Test-Drive Suite

The test suite was executed via `task editor:e2e` (`./bin/editor --test-e2e`):
```text
=================================================================
 [TEST HARNESS SUMMARY] Total Checks: 15 | Passed: 15 | Failed: 0
 Automated UI test-drive completed successfully!
=================================================================
```

### Visual Verification Artifacts
- **Docked Editor & Textured Viewport**: [01_docked_layout.png](file:///Users/brandoncrowe/.gemini/antigravity-acp/brain/fb7ed7b0-9418-41a5-a3a4-eac3c12aa7be/screenshots/01_docked_layout.png)
- **Transform Gizmo on Textured Node**: [02_transform_gizmo_selected.png](file:///Users/brandoncrowe/.gemini/antigravity-acp/brain/fb7ed7b0-9418-41a5-a3a4-eac3c12aa7be/screenshots/02_transform_gizmo_selected.png)
- **Rotate Gizmo**: [03_rotate_gizmo.png](file:///Users/brandoncrowe/.gemini/antigravity-acp/brain/fb7ed7b0-9418-41a5-a3a4-eac3c12aa7be/screenshots/03_rotate_gizmo.png)
- **Project Settings Dialog (Default Scene Selector)**: [14_project_settings_dialog.png](file:///Users/brandoncrowe/.gemini/antigravity-acp/brain/fb7ed7b0-9418-41a5-a3a4-eac3c12aa7be/screenshots/14_project_settings_dialog.png)
- **Game Engine Running in Separate Process**: [15_game_process_running.png](file:///Users/brandoncrowe/.gemini/antigravity-acp/brain/fb7ed7b0-9418-41a5-a3a4-eac3c12aa7be/screenshots/15_game_process_running.png)
- **Game Process Stopped**: [16_game_process_stopped.png](file:///Users/brandoncrowe/.gemini/antigravity-acp/brain/fb7ed7b0-9418-41a5-a3a4-eac3c12aa7be/screenshots/16_game_process_stopped.png)
