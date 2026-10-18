# Odin UI Library

A high-performance, standalone, hardware-accelerated immediate-mode & retained UI library for [Odin](https://odin-lang.org/) and [Raylib](https://www.raylib.com/).

Designed for game development tools, editor workspaces, simulation interfaces, and audio workstations. The library has **zero dependencies** outside of the Odin core library and Raylib vendor package, and produces **zero memory allocations** during standard rendering frames.

---

## Table of Contents

1. [Architecture & Design Philosophy](#architecture--design-philosophy)
2. [Quickstart Example](#quickstart-example)
3. [Keyboard & 2D Spatial Navigation](#keyboard--2d-spatial-navigation)
4. [Widget Reference & Examples](#widget-reference--examples)
   - [Buttons & Switches](#buttons--switches)
   - [Sliders & Rotary Knobs](#sliders--rotary-knobs)
   - [Audio Faders & Volume Meters](#audio-faders--volume-meters)
   - [Notched Sliders](#notched-sliders)
   - [Dropdowns & Menus](#dropdowns--menus)
   - [Lists & Hierarchical Trees](#lists--hierarchical-trees)
   - [Color Pickers & Gradient Editors](#color-pickers--gradient-editors)
   - [Plots & Waveforms](#plots--waveforms)
   - [HTML-Style Lists & Tables](#html-style-lists--tables)
5. [Layout & Container Engines](#layout--container-engines)
6. [Window-Resize Invariant Docking System](#window-resize-invariant-docking-system)
7. [Automated Testing & Input Injection Hooks](#automated-testing--input-injection-hooks)

---

## Architecture & Design Philosophy

- **Dual-Layer Design**:
  - **Immediate-Mode Layer (`immediate.odin`)**: High-level, ergonomic state-mutating functions (`GuiButton`, `GuiSlider`, `GuiVolumeFader`, `GuiDockSpace`) that register focus, handle keyboard/mouse/gamepad navigation, and manage interaction state.
  - **Retained / Rendering Layer (`widgets.odin`)**: Pure rendering procedures (`RenderSlider`, `RenderVolumeMeter`, `RenderKnob`) that draw primitives with smooth bilinear anti-aliasing and zero side effects.
- **Window-Resize Invariance**: Containers, tab docks, and the multi-zone `DockSpace` compute layout positions using **normalized proportional split ratios** rather than fixed pixel offsets. When the host window or parent container is resized, panel layouts, splitters, and floating windows scale smoothly and remain within viewport bounds without clipping.
- **Crisp High-DPI Font Rendering**: Font glyphs are pre-rasterized using Odin's font atlas pipeline (`font.odin`) with Bilinear texture filtering enabled (`rl.SetTextureFilter(..., .BILINEAR)`), eliminating pixelation and artifacting across arbitrary UI scales.

---

## Quickstart Example

```odin
package main

import "core:fmt"
import rl "vendor:raylib"
import "ui"

main :: proc() {
    rl.InitWindow(1280, 720, "Odin UI Quickstart")
    defer rl.CloseWindow()
    rl.SetTargetFPS(60)

    ui.InitFonts("engine/Open_Sans/static/OpenSans-Regular.ttf")
    defer ui.UnloadFonts()

    sliderVal: f32 = 50.0
    toggleState: bool = true

    for !rl.WindowShouldClose() {
        // 1. Begin UI frame & navigation pass
        ui.ImmediateNav_BeginFrame()

        rl.BeginDrawing()
        rl.ClearBackground(rl.Color{18, 20, 26, 255})

        // 2. Render UI widgets
        if ui.GuiButton(rl.Rectangle{40, 40, 160, 36}, "Click Me", idKey = 100) {
            fmt.println("Button was clicked!")
        }

        ui.GuiSlider(rl.Rectangle{40, 90, 240, 26}, "Volume", "%", &sliderVal, 0.0, 100.0, idKey = 101)
        ui.GuiToggleSwitch(rl.Rectangle{40, 130, 240, 30}, "Flight Assist", &toggleState, idKey = 102)

        // 3. Process navigation & dropdown overlays
        ui.ImmediateNav_Update()
        ui.RenderImmediateDropdownOverlay()

        rl.EndDrawing()
    }
}
```

---

## Keyboard & 2D Spatial Navigation

All interactive widgets register their bounding boxes with `ImmediateNav` every frame. Focus is maintained automatically and can be navigated via multiple paradigms:

| Navigation Mode | Input Controls | Behavior |
| :--- | :--- | :--- |
| **Linear Focus Cycle** | `Tab` / `Shift + Tab` | Cycles focus linearly through all registered widgets in layout order. |
| **2D Spatial Navigation**| Arrow Keys (`Up`, `Down`, `Left`, `Right`) | Evaluates the geometric bounding boxes of all candidate widgets using orthogonal directional scoring to move to the nearest physical neighbor. |
| **Widget Activation** | `Enter` / `Space` | Triggers buttons, toggles switches, activates dropdowns. |
| **Adjustment** | Arrow Keys / `PgUp` / `PgDn` | Increments or decrements focused sliders, knobs, and faders. |
| **Fine Adjustment** | Hold `Shift` | Engages micro-adjustment mode (0.1x scaling) on focused sliders, knobs, and faders. |
| **Dismissal** | `Escape` | Closes active dropdown popups and clears focus. |

---

## Widget Reference & Examples

### Buttons & Switches

```odin
// Standard Action Button
if ui.GuiButton(rect, "Launch Rocket", .Center, isSelected = false, idKey = 1001) {
    // Action triggered
}

// Checkbox
ui.GuiCheckBox(rect, "Enable VSync", &vsyncChecked, idKey = 1010)

// Toggle Switch
ui.GuiToggleSwitch(rect, "Plasma Shield", &shieldActive, idKey = 1020)

// Single-Line Text Input
changed, submitted := ui.GuiTextInput(rect, "Callsign", &buffer, "Enter text...", idKey = 1030)
```

### Sliders & Rotary Knobs

```odin
// Continuous Slider with Unit Suffix and Shift-Fine Mode
ui.GuiSlider(rect, "Main Volume", "%", &volumeVal, 0.0, 100.0, false, idKey = 2001, labelWidth = 100)

// Integer Stepped Slider
ui.GuiSlider(rect, "Buffer Size", "kbps", &bandwidthVal, 128.0, 4096.0, true, idKey = 2002)

// Rotary Dial Knob (supports Shift+Drag for micro-degree adjustment)
ui.GuiKnob(rect, "Engine Throttle", &throttleVal, 0.0, 100.0, 50.0, "%.0f%%", idKey = 2010)
```

### Audio Faders & Volume Meters

The audio suite provides studio-grade console controls with standard logarithmic taper curves:

```odin
// Studio Volume Fader
// - Piecewise logarithmic console curve (+6 dB top, 0 dB Unity at 75% travel, -inf cutoff)
// - Double-click or Right-click resets fader to 0.0 dB Unity Gain
// - Hold Shift while dragging or using Up/Down arrows for micro-dB fine tuning
ui.GuiVolumeFader(faderRect, "MASTER BUS", &masterDbVal, minDb = -60.0, maxDb = 6.0, defaultDb = 0.0, idKey = 3001)

// Stereo Volume Meter (VU / Peak)
// - 24 optical LED ladder segments (Green: -60 to -12 dB, Yellow: -12 to -3 dB, Red: -3 to 0 dB)
// - Transient peak-hold decay bar and 1.2s Clip LED hold indicator
// - Automatically updates timers using rl.GetFrameTime()
meterState: ui.VolumeMeterState
ui.GuiVolumeMeter(meterRect, "OUTPUT VU", audioLevelL, audioLevelR, &meterState, orientation = .Vertical)

// Horizontal Mono Console Monitor
ui.GuiVolumeMeter(horizMeterRect, "BUS MONITOR", audioLevelMono, -120.0, nil, orientation = .Horizontal)
```

### Notched Sliders

Sliders featuring discrete detents/ticks with magnetic snapping:

```odin
// Horizontal Detented Slider (5 Discrete Gear Stages)
notchLabels := []string{"0.25x", "0.5x", "1.0x", "2.0x", "4.0x"}
ui.GuiNotchedSlider(rect, "Simulation Speed", &speedIdx, 0.0, 4.0, 5, notchLabels, snapToNotches = true, orientation = .Horizontal, idKey = 4001)

// Vertical Detented Power Relay
// Note: Holding Shift allows continuous micro-positioning bypass without snapping
relayLabels := []string{"AUX 1", "AUX 2", "AUX 3", "MAIN"}
ui.GuiNotchedSlider(vRect, "Relay Tap", &relayIdx, 0.0, 3.0, 4, relayLabels, snapToNotches = true, orientation = .Vertical, idKey = 4002)
```

### Dropdowns & Menus

Dropdown menus render an inline button and automatically defer their popup list to an overlay pass rendered on top of all sibling containers:

```odin
// Dropdown Box
ui.GuiDropdownBox(rect, "Low;Medium;High;Ultra;Cinematic", &qualityPresetIdx, idKey = 5001)

// Radio Selector Group (Horizontal or Vertical)
options := []string{"Cadet", "Officer", "Commander"}
ui.GuiRadioGroup(rect, "Difficulty", options, &difficultyIdx, horizontal = true, idKey = 5002)
```

### Lists & Hierarchical Trees

```odin
// Scrollable List View
soundList := []string{"Laser Fire", "Plasma Torpedo", "Shield Pulse"}
ui.GuiListView(rect, soundList, &selectedIdx, &listScroll, itemHeight = 24, idKey = 6001)

// Interactive Expandable Tree View
// Returns clicked node index and toggled collapse index
clickedIdx, toggledIdx := ui.GuiTreeView(rect, treeItems[:], &selectedNodeId, &treeScroll, itemHeight = 22)
```

### Color Pickers & Gradient Editors

```odin
// HSV Hue Circle + Saturation-Value Matrix
ui.GuiColorPicker(rect, "Tint Color", &selectedColor)

// Alpha Channel Bar
ui.GuiColorBarAlpha(rect, "Alpha", &alphaVal, idKey = 7001)

// Multi-Stop Gradient Ramp Editor
// Supports adding stops on click, dragging stops, and interpolating output
ui.GuiGradientEditor(rect, &gradientStops, &selectedStopIdx, &isDraggingStop, showAlphaBar = true)
colorAtT := ui.EvaluateGradient(gradientStops[:], 0.75)
```

### Plots & Waveforms

```odin
// Live Oscilloscope / XY Telemetry Plot
ui.GuiXYPlot(
    plotRect,
    "Sensor Telemetry",
    series1Points[:], // [][2]f32
    series2Points[:],
    minVal = {0, 0},
    maxVal = {1, 1},
    showGrid = true,
)
```

### HTML-Style Lists & Tables

Widgets that replicate HTML document semantics with immediate-mode reactivity and keyboard navigation:

#### HTML Unordered List (`<ul>`)
Renders items with customizable bullet graphics (`.Disc`, `.Circle`, `.Square`, `.Dash`, `.Arrow`), indentation levels, and optional badge chips:

```odin
ulItems := []ui.ListItem{
    {text = "Deep Space Arsenal", depth = 0, isHeader = true},
    {text = "Sub-light Ion Thruster Array", depth = 0, bullet = .Disc, badge = "ONLINE"},
    {text = "Dual High-Yield Plasma Cannons", depth = 0, bullet = .Disc, badge = "ARMED"},
    {text = "Forward Deflector Shield Matrix", depth = 0, bullet = .Dash, badge = "98%"},
    {text = "Auxiliary Sub-Systems", depth = 1, bullet = .Circle},
    {text = "Hyperdrive Jump Core", depth = 1, bullet = .Circle, badge = "CHARGED"},
}

changed, clickedIdx := ui.GuiUnorderedList(rect, ulItems, &selectedIdx, &scrollPos, defaultBullet = .Disc)
```

#### HTML Ordered List (`<ol>`)
Renders sequenced items with numerical or alphabetical markers (`.Decimal`, `.AlphaLower`, `.AlphaUpper`, `.RomanLower`, `.RomanUpper`):

```odin
olItems := []ui.ListItem{
    {text = "Pre-Flight Launch Checklist", depth = 0, isHeader = true},
    {text = "Initialize main reactor core flux", depth = 0, number = 1, badge = "DONE"},
    {text = "Establish quantum telemetry comm link", depth = 0, number = 2, badge = "ACTIVE"},
    {text = "Calibrate guidance gyroscopes", depth = 0, number = 3},
    {text = "Confirm magnetic clamp release", depth = 1, number = 1, badge = "VERIFIED"},
    {text = "Fire cold-gas attitude RCS thrusters", depth = 1, number = 2, badge = "NOMINAL"},
}

changed, clickedIdx := ui.GuiOrderedList(rect, olItems, &selectedIdx, &scrollPos, numbering = .Decimal)
```

#### HTML Data Table (`<table>`)
Full-featured table with `<thead>`, `<tbody>`, zebra striping, sticky headers, interactive sorting, and row selection:

```odin
columns := []ui.TableColumn{
    {title = "ID", width = 55.0, align = .Center, sortable = true},
    {title = "Entity Vessel", width = 0.30, align = .Start, sortable = true},
    {title = "Class / Type", width = 0.22, align = .Start, sortable = true},
    {title = "Hull", width = 80.0, align = .End, sortable = true},
    {title = "Shields", width = 80.0, align = .End, sortable = true},
    {title = "Status", width = 95.0, align = .Center, sortable = true},
}

// Renders table with automatic column sizing, header click sorting, and keyboard arrow row navigation
rowClicked, headerClicked := ui.GuiTable(
    tableRect,
    columns,
    rows,
    &selectedRowIdx,
    &sortColIdx,
    &isAscending,
    &tableScroll,
    headerHeight = 32.0,
    rowHeight = 28.0,
)
```

---

## Layout & Container Engines

The library provides layout calculators that position dynamic child elements without heap allocations:

- `ComputeVerticalLayout`: Stacks child elements vertically with `.Start`, `.Center`, `.End`, or `.Stretch` alignments.
- `ComputeHorizontalLayout`: Places child elements side-by-side horizontally.
- `ComputeGridLayout`: Places child elements into responsive multi-column matrices.
- `RenderContainerPanel`: Renders a structured panel with dark glass background, subtle 1px border, and top title header with accent strip.

---

## Window-Resize Invariant Docking System

The `DockSpace` engine partitions a rectangular workspace into docked zones (`Left`, `Right`, `Top`, `Bottom`, `Center`) and `Floating` windows.

### Why Proportional Ratios?

Traditional docking engines store pixel offsets for panels (e.g. `panelWidth = 250px`). When a user resizes the application window from `1280x820` to `1920x1080` or `960x540`, fixed-pixel panels either consume too much screen real estate or cause center viewports to collapse entirely.

`DockSpace` stores **normalized proportional ratios** (`leftRatio = 0.24`, `rightRatio = 0.26`, `bottomRatio = 0.28`). On every frame, `DockSpace_UpdateLayout` computes exact pixel boundaries while respecting strict min/max constraints. Floating windows store normalized anchor coordinates (`floatRelPos`), keeping them clamped safely within the window bounds upon resize.

### DockSpace Usage Example

```odin
// 1. Initialize DockSpace
dockSpace: ui.DockSpace
ui.DockSpace_Init(&dockSpace, rl.Rectangle{0, 60, f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight()) - 60})
defer ui.DockSpace_Destroy(&dockSpace)

// 2. Register Panels
ui.DockSpace_AddPanel(&dockSpace, "scene", "Scene Hierarchy", .Left, {40, 80}, {280, 360})
ui.DockSpace_AddPanel(&dockSpace, "viewport", "2D Viewport", .Center, {340, 80}, {600, 360})
ui.DockSpace_AddPanel(&dockSpace, "inspector", "Properties Inspector", .Right, {960, 80}, {300, 360})
ui.DockSpace_AddPanel(&dockSpace, "console", "Diagnostics Console", .Bottom, {40, 460}, {800, 200})

// 3. Frame Update & Rendering Loop
for !rl.WindowShouldClose() {
    rl.BeginDrawing()
    rl.ClearBackground(rl.Color{16, 18, 24, 255})

    // Dynamically update bounds to current window size
    hostRect := rl.Rectangle{0, 60, f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight()) - 60}
    ui.DockSpace_UpdateLayout(&dockSpace, hostRect)

    // Render Panel: Scene Hierarchy
    if visible, bounds := ui.DockSpace_BeginPanel(&dockSpace, "scene"); visible {
        ui.GuiButton(rl.Rectangle{bounds.x + 10, bounds.y + 10, bounds.width - 20, 30}, "Add Entity")
        ui.DockSpace_EndPanel(&dockSpace)
    }

    // Render Panel: Viewport
    if visible, bounds := ui.DockSpace_BeginPanel(&dockSpace, "viewport"); visible {
        rl.DrawRectangleRec(bounds, rl.Color{10, 12, 16, 255})
        ui.DockSpace_EndPanel(&dockSpace)
    }

    // Render Panel: Inspector
    if visible, bounds := ui.DockSpace_BeginPanel(&dockSpace, "inspector"); visible {
        ui.DockSpace_EndPanel(&dockSpace)
    }

    // Render Panel: Console
    if visible, bounds := ui.DockSpace_BeginPanel(&dockSpace, "console"); visible {
        ui.DockSpace_EndPanel(&dockSpace)
    }

    // Render interactive splitters & drag-and-drop dock target overlays
    ui.DockSpace_RenderOverlays(&dockSpace)

    rl.EndDrawing()
}
```

### Docking Interaction Features

1. **Draggable Splitters**: Click and drag the borders between docked panels to adjust split ratios in real-time.
2. **Interactive Header Drag & Drop with Automatic Panel Displacement**: Drag a panel's title bar to undock it into a floating window. Dragging near any screen edge highlights a translucent blue preview rectangle indicating the target slot and any displaced panel (`DOCK LEFT (MOVES Scene Hierarchy)`). When dropped onto an already occupied slot, the existing panel is automatically moved out (cleanly swapped with the incoming panel's origin slot or moved to an unoccupied slot), preventing any visual overlap.
3. **Zero-Overlap Layout Guarantee**: Even in scenarios where multiple panels share a slot, `DockSpace_UpdateLayout` automatically tiles/partitions them proportionally rather than stacking, ensuring panels never overlap.
4. **Quick Action Header Buttons**:
   - `>`: Cycles dock slots (`Left` -> `Right` -> `Bottom` -> `Center` -> `Left`).
   - `F` / `D`: Toggles between Floating window and docked slot (remembering the previous dock slot).
   - `x`: Hides / closes the panel.

---

## Automated Testing & Input Injection Hooks

The library includes a deterministic input injection framework (`test_hook.odin`) enabling full UI verification without physical human interaction. Tests run headlessly in CI or during developer builds:

```bash
# Run the automated UI test suite and capture screenshot artifacts
./scripts/test_ui_showcase.sh
# or via Taskfile:
task ui:e2e
```

### Injection API

```odin
// Initialize test harness (saves screenshots to ./ui_screenshots/)
ui.TestHook_Init("ui_screenshots", 60)

// Simulate mouse click & release
ui.TestHook_MouseClick(120, 200)
ui.TestHook_MouseRelease(120, 200)

// Simulate keyboard and spatial navigation
ui.TestHook_KeyPress(.ENTER)
ui.TestHook_NavAction(.Right)
ui.TestHook_KeyPress(.UP, shift = true)

// Assert UI state
ui.TestHook_Assert(state.activeTab == 2, "Tab successfully switched")

// Capture PNG screenshot of current frame buffer
ui.TestHook_CaptureScreenshot("test_state.png")
```
