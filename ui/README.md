# Odin UI Library

A high-performance, standalone, hardware-accelerated immediate-mode & retained UI library for [Odin](https://odin-lang.org/) and [Raylib](https://www.raylib.com/).

Designed for game development tools, editor workspaces, simulation interfaces, and audio workstations. The library has **zero dependencies** outside of the Odin core library and Raylib vendor package, and produces **zero memory allocations** during standard rendering frames.

---

## Table of Contents

1. [Architecture & Design Philosophy](#architecture--design-philosophy)
2. [Targeted Example Apps](#targeted-example-apps)
3. [Theming Engine & Visual Styling](#theming-engine--visual-styling)
4. [Automatic Cursor Management](#automatic-cursor-management)
5. [Keyboard & 2D Spatial Navigation](#keyboard--2d-spatial-navigation)
6. [Widget Reference & Examples](#widget-reference--examples)
   - [Buttons, Icons & Switches](#buttons-icons--switches)
   - [Font Awesome Vector Icons (`GuiIcon`)](#font-awesome-vector-icons-guiicon)
   - [Application Toolbar & Icon Buttons](#application-toolbar--icon-buttons)
   - [Sliders & Rotary Knobs](#sliders--rotary-knobs)
   - [Audio Faders & Volume Meters](#audio-faders--volume-meters)
   - [Notched Sliders](#notched-sliders)
   - [Dropdowns & Menus](#dropdowns--menus)
   - [Lists & Hierarchical Trees](#lists--hierarchical-trees)
   - [Color Pickers & Gradient Editors](#color-pickers--gradient-editors)
   - [Plots & Waveforms](#plots--waveforms)
   - [HTML-Style Lists & Tables](#html-style-lists--tables)
7. [Modern Text Engine (`Runa` Integration)](#modern-text-engine-runa-integration)
8. [Dynamic Content: CSS Flexbox Layout Engine](#dynamic-content-css-flexbox-layout-engine)
9. [Cross-Platform Native Dialog Interop](#cross-platform-native-dialog-interop)
10. [Rich Multi-Line Text Wrapping](#rich-multi-line-text-wrapping)
11. [Layout & Container Engines](#layout--container-engines)
12. [Window-Resize Invariant Docking System](#window-resize-invariant-docking-system)
13. [Automated Testing & Input Injection Hooks](#automated-testing--input-injection-hooks)

---

## Architecture & Design Philosophy

- **Dual-Layer Design**:
  - **Immediate-Mode Layer (`immediate.odin`)**: High-level, ergonomic state-mutating functions (`GuiButton`, `GuiSlider`, `GuiVolumeFader`, `GuiDockSpace`) that register focus, handle keyboard/mouse/gamepad navigation, update mouse cursors, and manage interaction state.
  - **Retained / Rendering Layer (`widgets.odin`)**: Pure rendering procedures (`RenderButton`, `RenderSlider`, `RenderVolumeMeter`, `RenderKnob`) that draw primitives using active theme metrics and rounded rectangle shaders with zero side effects.
- **Window-Resize Invariance**: Containers, tab docks, and the multi-zone `DockSpace` compute layout positions using **normalized proportional split ratios** rather than fixed pixel offsets. When the host window or parent container is resized, panel layouts, splitters, and floating windows scale smoothly and remain within viewport bounds without clipping.
- **Crisp High-DPI Font Rendering & Typography Scale**: Font glyphs are pre-rasterized using Odin's font atlas pipeline (`font.odin`) with extended codepoint coverage (ASCII, Latin-1 Supplement, typographical symbols, bullets, arrows), dynamic mipmaps (`rl.GenTextureMipmaps`), and Bilinear texture filtering enabled (`rl.SetTextureFilter(..., .BILINEAR)`), eliminating shimmering and pixelation across arbitrary UI scales. Standard typography constants: `DEFAULT_FONT_SIZE` (18px), `DEFAULT_FONT_SIZE_SM` (14px), and `DEFAULT_FONT_SIZE_LG` (22px).

---

## Targeted Example Apps

To get started quickly, self-contained example applications are located in `ui/examples/`:

### 1. Settings & Preferences Dialog (`ui/examples/settings_dialog`)
Demonstrates building standard dialog forms with:
- Dynamic theme switching (Dark, Light, Cyberpunk)
- Pixel-accurate audio sliders with integer value displays
- Fullscreen toggle switch and VSync checkbox
- Commander callsign text input field
- Simulation difficulty radio button groups
- Icon action buttons (Reset Defaults, Save Preferences)

```bash
# Run interactively
odin run ui/examples/settings_dialog

# Run in headless test mode (ideal for CI)
odin run ui/examples/settings_dialog -- --test
```

### 2. Studio Operations Dashboard (`ui/examples/dashboard`)
Demonstrates productivity tool and editor layouts with:
- Font Awesome vector icon toolbar (`GuiToolbar`)
- Structured system task lists with status badges (`GuiUnorderedList`)
- Telemetry dial knobs (`GuiKnob`) and vertical logarithmic audio faders (`GuiVolumeFader`)
- Interactive multi-column data table (`GuiTable`) with sorting and row selection

```bash
# Run interactively
odin run ui/examples/dashboard

# Run in headless test mode
odin run ui/examples/dashboard -- --test
```

---

## Theming Engine & Visual Styling

The library features a centralized, hierarchical theming system (`ui/theme.odin`) controlling padding, margins, rounded corner radii, and semantic color palettes across all widgets.

### Theme Structure

```odin
Theme :: struct {
    // Spacing & Geometry Metrics
    paddingSm:         f32, // default 4px
    paddingMd:         f32, // default 8px
    paddingLg:         f32, // default 16px
    marginSm:          f32, // default 4px
    marginMd:          f32, // default 8px
    itemSpacing:       f32, // default 8px
    borderRadius:      f32, // default 5.0px for buttons, inputs, panels
    borderRadiusSmall: f32, // default 3.0px for chips, badges, tags
    borderWidth:       f32, // default 1.0px

    // Colors - Backgrounds & Surfaces
    bgApp:            rl.Color,
    bgPanel:          rl.Color,
    bgHeader:         rl.Color,
    bgWidget:         rl.Color,
    bgWidgetHover:    rl.Color,
    bgWidgetPressed:  rl.Color,
    bgWidgetSelected: rl.Color,
    bgInput:          rl.Color,

    // Colors - Borders
    borderNormal:     rl.Color,
    borderHover:      rl.Color,
    borderFocused:    rl.Color,

    // Colors - Typography
    textPrimary:      rl.Color,
    textSecondary:    rl.Color,
    textDisabled:     rl.Color,

    // Colors - Accents & Status
    accent:           rl.Color,
    accentHover:      rl.Color,
    success:          rl.Color,
    warning:          rl.Color,
    danger:           rl.Color,
    info:             rl.Color,
}
```

### Presets and Switching

Three built-in theme presets are provided out of the box:
- `Theme_Dark()`: Modern dark-slate developer interface (default).
- `Theme_Light()`: Clean, high-contrast crisp light theme.
- `Theme_Cyberpunk()`: Neon cyan and magenta dark futuristic aesthetic.

```odin
// Set active global theme
ui.SetTheme(ui.Theme_Light())

// Or push temporary theme overrides
ui.PushTheme(ui.Theme_Cyberpunk())
// ... render specialized HUD elements ...
ui.PopTheme()

// Query current theme
t := ui.GetTheme()

// Draw custom geometry matching active theme corners & borders
ui.DrawThemeRect(rect, t.bgPanel, t.borderNormal, radius = t.borderRadius, borderWidth = 1.0)
```

---

## Automatic Cursor Management

The cursor system (`ui/cursor.odin`) dynamically updates the OS mouse pointer every frame based on the active or hovered widget:

| Cursor Type | Context / Triggered By |
| :--- | :--- |
| `POINTING_HAND` | Hovering buttons, icon buttons, checkboxes, toggle switches, tabs, dropdowns, and toolbar items. |
| `IBEAM` | Hovering text inputs, search boxes, and editable numeric inputs. |
| `RESIZE_EW` (Horizontal) | Hovering vertical splitters or dragging horizontal sliders/faders. |
| `RESIZE_NS` (Vertical) | Hovering horizontal splitters or dragging vertical volume faders. |
| `RESIZE_ALL` | Hovering dock panel title bars or dragging floating dock panels. |
| `DEFAULT` | Default fallback when cursor is over neutral canvas areas. |

Cursor requests support priority levels (`System` > `Drag` > `Hover` > `Default`), ensuring active drags maintain their appropriate cursor even if the mouse pointer transiently crosses other widgets.

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

### Buttons, Icons & Switches

```odin
// Standard Action Button (Uses active Theme.borderRadius)
if ui.GuiButton(rect, "Launch Rocket", align = .Center, isSelected = false, idKey = 1001) {
    // Action triggered
}

// Icon Button with Font Awesome Icon and Text
if ui.GuiIconButton(rect, .Rocket, "Launch", isSelected = false, idKey = 1002) {
    // Action triggered
}

// Standalone Font Awesome Icon
ui.GuiIcon(rect, .Shield, size = 20, color = rl.Color{96, 165, 250, 255})

// Checkbox
ui.GuiCheckBox(rect, "Enable VSync", &vsyncChecked, idKey = 1010)

// Toggle Switch
ui.GuiToggleSwitch(rect, "Plasma Shield", &shieldActive, idKey = 1020)

// Single-Line Text Input
changed, submitted := ui.GuiTextInput(rect, "Callsign", &buffer, "Enter text...", idKey = 1030)
```

### Font Awesome Vector Icons (`GuiIcon`)

The UI library bundles the entire **Font Awesome 6 Solid** vector icon library (1,402 icons) directly into the compiled executable via Odin's `#load(...)` directive.
- **Zero runtime dependencies**: Does not require external font files or assets at runtime.
- **Strongly-typed `Icon` enum**: Reference any icon with autocomplete via `ui.Icon.Play`, `ui.Icon.Gear`, `ui.Icon.Rocket`, `ui.Icon.Save`, etc.
- **High-DPI Glyphs**: Dynamically rasterized with Bilinear filtering at crisp resolution.

```odin
// Draw a standalone Font Awesome icon
ui.GuiIcon(rect, .Rocket, size = 20, color = rl.Color{96, 165, 250, 255})

// Measure icon bounding box
dimensions := ui.MeasureIcon(.Gear, size = 18)

// Convert icon enum to rune or string
r := ui.Icon_ToRune(.Play)
str := ui.Icon_ToString(.FloppyDisk)
```

### Application Toolbar & Icon Buttons

High-performance application toolbars supporting buttons, toggles, separators, and spacers, with automatic tooltip popups and keyboard arrow navigation:

```odin
items: [5]ui.ToolbarItem = {
    {id = 1, icon = .File, label = "New", tooltip = "Create file (Ctrl+N)", itemType = .Button},
    {id = 2, icon = .FolderOpen, label = "Open", tooltip = "Open workspace (Ctrl+O)", itemType = .Button},
    {id = 3, icon = .FloppyDisk, label = "Save", tooltip = "Save changes (Ctrl+S)", itemType = .Button},
    {id = 4, itemType = .Separator},
    {id = 5, icon = .Play, label = "Run", tooltip = "Execute simulation", itemType = .Toggle, isSelected = true},
}

clickedId, clicked := ui.GuiToolbar(toolbarRect, items[:], idKey = 1050)
if clicked {
    fmt.printf("Toolbar item #%d clicked!\n", clickedId)
}
```

### Sliders & Rotary Knobs

The slider system features pixel-accurate track hit-testing: clicking anywhere on the track immediately centers the handle under the mouse pointer, eliminating coordinate drift.

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
```

### Dropdowns & Menus

Dropdown menus render an inline button and automatically defer their popup list to an overlay pass rendered on top of all sibling containers:

```odin
// Dropdown Box
ui.GuiDropdownBox(rect, "Low;Medium;High;Ultra;Cinematic", &qualityPresetIdx, idKey = 5001)

// Radio Selector Group (Horizontal or Vertical)
options := []string{"Casual", "Standard", "Hardcore"}
ui.GuiRadioGroup(rect, "Difficulty", options, &difficultyIdx, horizontal = false, idKey = 5002)
```

### HTML-Style Lists & Tables

#### HTML Unordered List (`<ul>`)
```odin
ulItems := []ui.ListItem{
    {text = "Deep Space Arsenal", depth = 0, isHeader = true},
    {text = "Sub-light Ion Thruster Array", depth = 0, bullet = .Disc, badge = "ONLINE"},
    {text = "Forward Deflector Shield Matrix", depth = 0, bullet = .Dash, badge = "98%"},
}

changed, clickedIdx := ui.GuiUnorderedList(rect, ulItems, &selectedIdx, &scrollPos, defaultBullet = .Disc)
```

#### HTML Data Table (`<table>`)
```odin
columns := []ui.TableColumn{
    {title = "ID", width = 55.0, align = .Center, sortable = true},
    {title = "Entity Vessel", width = 0.30, align = .Start, sortable = true},
    {title = "Hull", width = 80.0, align = .End, sortable = true},
}

rowClicked, headerClicked := ui.GuiTable(
    tableRect,
    columns,
    rows,
    &selectedRowIdx,
    &sortColIdx,
    &isAscending,
    &tableScroll,
)
```

---

---

## Modern Text Engine (`Runa` Integration)

The UI library integrates [Runa](https://github.com/BuLEEto/Runa), a pure-Odin modern text engine providing advanced OpenType typography:
- **OpenType Shaping (GSUB/GPOS)**: Full font kerning pairs, ligatures (e.g., `!=`, `->`, `fi`), and contextual glyph substitutions.
- **Two-Tier Caching**: High-performance shape cache (`(font, text, size) -> glyphs`) and dynamic GPU atlas slot cache (`(glyph_id, size) -> slot`).
- **Dirty-Rect GPU Updates**: Updates only modified sub-rectangles via `rl.UpdateTextureRec` rather than re-uploading full textures.
- **Zero Configuration**: Automatically boots upon calling `ui.InitFonts()`.

```odin
// Runa renders shaped, kerned text with zero allocations on cache hits
ui.DrawTextStr("Transmitting Telemetry -> Status: ONLINE", 40, 100, size = 16, color = rl.WHITE)

// Accurate shaped measurement
textWidth := ui.MeasureTextStr("Viper-MK2", 16).x
```

---

## Dynamic Content: CSS Flexbox Layout Engine

The `ui/flexbox.odin` module provides a full, CSS-compliant Flexbox layout engine for responsive and dynamic UI compositions:
- **Flex Directions**: `.Row`, `.Column`, `.RowReverse`, `.ColumnReverse`
- **Flex Justify**: `.FlexStart`, `.Center`, `.FlexEnd`, `.SpaceBetween`, `.SpaceAround`, `.SpaceEvenly`
- **Flex Align**: `.FlexStart`, `.Center`, `.FlexEnd`, `.Stretch`
- **Proportional Flex Distribution**: Supports `grow`, `shrink`, and `basis`.

```odin
// Immediate-mode Flexbox container
ui.Flex_Begin(containerRect, direction = .Row, gap = 12.0, justify = .SpaceBetween, align = .Center)

// Item 1: Fixed-width avatar (grow = 0, shrink = 0)
slot0 := ui.Flex_AddItem(width = 40, height = 40, grow = 0.0, shrink = 0.0)
// Item 2: Flexible main title (grow = 1, expands to fill remaining space)
slot1 := ui.Flex_AddItem(width = 120, height = 24, grow = 1.0, shrink = 1.0)
// Item 3: Action button
slot2 := ui.Flex_AddItem(width = 80, height = 30, grow = 0.0, shrink = 0.0)

// Retrieve computed geometry
rectAvatar := ui.Flex_GetRect(slot0)
rectTitle  := ui.Flex_GetRect(slot1)
rectButton := ui.Flex_GetRect(slot2)

ui.Flex_End()
```

---

## Cross-Platform Native Dialog Interop

`ui/native_dialog.odin` enables invoking native OS file selection, folder picking, and alert message boxes:
- **macOS**: Native Cocoa/Finder file dialogs via `/usr/bin/osascript`.
- **Windows**: Native Win32 Common Dialogs (`GetOpenFileNameW`, `GetSaveFileNameW`).
- **Linux**: Desktop portal / `zenity` / `kdialog`.
- **Headless Safety**: Automatically returns non-blocking empty states during automated testing (`--test`).

```odin
// 1. Open File Dialog with file extensions filter
if filePath, ok := ui.NativeDialog_OpenFile("Select Asset", filterExts = {"png", "jpg", "wav"}); ok {
    fmt.println("User selected file:", filePath)
}

// 2. Save File Dialog with default filename
if savePath, ok := ui.NativeDialog_SaveFile("Export Preset", defaultName = "preset.json"); ok {
    fmt.println("Saving preset to:", savePath)
}

// 3. Folder Pick Dialog
if folderPath, ok := ui.NativeDialog_OpenFolder("Choose Project Root"); ok {
    fmt.println("Selected folder:", folderPath)
}

// 4. Native Message Box Alert
ui.NativeDialog_MessageBox("Success", "Project saved successfully!", alertType = .Info)
```

---

## Rich Multi-Line Text Wrapping

`ui/text_wrap.odin` provides unicode and whitespace-aware multi-line text wrapping:
- **Intrinsically Measured Heights**: Measures total vertical height consumed to automatically push downstream elements down in Flexbox and cards.
- **Max-Line Truncation & Ellipsis**: Truncates paragraphs at `maxLines` and appends `...`.
- **Wrapped Label Widget**: `ui.GuiLabelWrapped` directly renders multi-line paragraphs.

```odin
longBio := "The Viper-MK2 is a heavy interceptor equipped with twin plasma accelerators, deflector shield matrices, and advanced jump telemetry."

// Immediate-mode wrapped label that returns height consumed
heightConsumed := ui.GuiLabelWrapped(
    rl.Rectangle{x = 24, y = 80, width = 280, height = 200},
    longBio,
    fontSize = 14,
    color = rl.Color{220, 225, 235, 255},
    lineSpacing = 4.0,
    maxLines = 4, // 0 for unlimited
)

// Downstream items push down dynamically using heightConsumed
nextWidgetY := 80 + heightConsumed + 16.0
```

## Window-Resize Invariant Docking System

The `DockSpace` engine partitions a rectangular workspace into docked zones (`Left`, `Right`, `Top`, `Bottom`, `Center`) and `Floating` windows using normalized proportional split ratios (`leftRatio`, `rightRatio`, `bottomRatio`).

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

// 3. Frame Update & Rendering Loop
for !rl.WindowShouldClose() {
    rl.BeginDrawing()
    rl.ClearBackground(rl.Color{16, 18, 24, 255})

    hostRect := rl.Rectangle{0, 60, f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight()) - 60}
    ui.DockSpace_UpdateLayout(&dockSpace, hostRect)

    if visible, bounds := ui.DockSpace_BeginPanel(&dockSpace, "scene"); visible {
        ui.GuiButton(rl.Rectangle{bounds.x + 10, bounds.y + 10, bounds.width - 20, 30}, "Add Entity")
        ui.DockSpace_EndPanel(&dockSpace)
    }

    ui.DockSpace_RenderOverlays(&dockSpace)
    rl.EndDrawing()
}
```

### Docking Interaction Features

1. **Draggable Splitters**: Click and drag the borders between docked panels to adjust split ratios in real-time.
2. **Interactive Header Drag & Drop with Automatic Panel Displacement**: Drag a panel's title bar to undock it into a floating window. Dragging near any screen edge highlights a translucent preview rectangle indicating the target slot. When dropped onto an already occupied slot, the existing panel is automatically displaced and swapped into the source slot or an available adjacent slot, preventing visual overlap.
3. **Zero-Overlap Layout Guarantee**: Multiple panels sharing a slot are tiled proportionally rather than stacked.
4. **Quick Action Header Buttons**:
   - `>`: Cycles dock slots (`Left` -> `Right` -> `Bottom` -> `Center` -> `Left`).
   - `F` / `D`: Toggles between Floating window and docked slot.
   - `x`: Hides / closes the panel.

---

## Automated Testing & Input Injection Hooks

The library includes a deterministic input injection framework (`test_hook.odin`) enabling full UI verification without physical human interaction. Tests run headlessly in CI or during developer builds:

```bash
# Run the automated UI test suite and capture screenshot artifacts
./scripts/test_ui_showcase.sh
```

### Injection API

```odin
// Initialize test harness (saves screenshots to ./ui_screenshots/)
ui.TestHook_Init("ui_screenshots", 130)

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

