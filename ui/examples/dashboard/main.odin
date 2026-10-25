package main

import "core:fmt"
import "core:os"
import rl "vendor:raylib"
import ui "../.."

// ============================================================================
// Simple Targeted Example: Operations Dashboard & Studio Controls
// Demonstrates:
//   - Font Awesome Icon Toolbar (GuiToolbar, ToolbarItem)
//   - HTML Unordered List with status badges (GuiUnorderedList, ListItem)
//   - Precision Rotational Knobs (GuiKnob) & Volume Faders (GuiVolumeFader)
//   - Multi-column telemetry data table (GuiTable, TableColumn, TableRow)
//   - Unified theme metrics and crisp typography
// ============================================================================

DashboardState :: struct {
	// Toolbar items & state
	toolbarItems:        [dynamic]ui.ToolbarItem,
	activeSimState:      int, // 12=Play, 13=Pause, 14=Stop
	lastActionMsg:       string,

	// Telemetry Knobs & Faders
	reactorFluxKnob:     f32,
	attitudeHeadingKnob: f32,
	warpFactorKnob:      f32,
	audioMasterFader:    f32,
	audioSfxFader:       f32,

	// HTML List (System Tasks)
	taskItems:           [dynamic]ui.ListItem,
	selectedTaskIdx:     int,
	taskScroll:          rl.Vector2,

	// Data Table (Telemetry Sensors)
	tableColumns:        [dynamic]ui.TableColumn,
	tableRows:           [dynamic]ui.TableRow,
	selectedTableRow:    int,
	tableSortCol:        int,
	tableSortAsc:        bool,
}

InitDashboardState :: proc(state: ^DashboardState) {
	ui.SetTheme(ui.Theme_Dark())

	state.lastActionMsg = "Operations Dashboard ready."
	state.reactorFluxKnob = 68.5
	state.attitudeHeadingKnob = 142.0
	state.warpFactorKnob = 3.2
	state.audioMasterFader = 0.0
	state.audioSfxFader = -6.0

	// 1. Setup Toolbar
	state.toolbarItems = make([dynamic]ui.ToolbarItem)
	append(&state.toolbarItems, ui.ToolbarItem{id = 1, icon = .File, label = "New", tooltip = "New Workspace", itemType = .Button})
	append(&state.toolbarItems, ui.ToolbarItem{id = 2, icon = .FolderOpen, label = "Open", tooltip = "Open File", itemType = .Button})
	append(&state.toolbarItems, ui.ToolbarItem{id = 3, icon = .FloppyDisk, label = "Save", tooltip = "Save Dashboard", itemType = .Button})
	append(&state.toolbarItems, ui.ToolbarItem{id = 4, itemType = .Separator})
	append(&state.toolbarItems, ui.ToolbarItem{id = 12, icon = .Play, label = "Run", tooltip = "Start Reactor", itemType = .Toggle, isSelected = true})
	append(&state.toolbarItems, ui.ToolbarItem{id = 13, icon = .Pause, tooltip = "Pause Loop", itemType = .Toggle})
	append(&state.toolbarItems, ui.ToolbarItem{id = 14, icon = .Stop, tooltip = "Emergency Halt", itemType = .Button})
	append(&state.toolbarItems, ui.ToolbarItem{id = 15, itemType = .Spacer})
	append(&state.toolbarItems, ui.ToolbarItem{id = 20, icon = .Moon, label = "Theme", tooltip = "Cycle Visual Theme", itemType = .Button})
	state.activeSimState = 12

	// 2. Setup System Task List
	state.taskItems = make([dynamic]ui.ListItem)
	append(&state.taskItems, ui.ListItem{text = "Core Subsystems", depth = 0, isHeader = true})
	append(&state.taskItems, ui.ListItem{text = "Quantum Primary Reactor", depth = 0, bullet = .Disc, badge = "NOMINAL", badgeColor = rl.Color{52, 211, 153, 255}, badgeBg = rl.Color{20, 42, 34, 255}})
	append(&state.taskItems, ui.ListItem{text = "Auxiliary Sublight Drive", depth = 0, bullet = .Disc, badge = "ARMED", badgeColor = rl.Color{96, 165, 250, 255}, badgeBg = rl.Color{20, 32, 50, 255}})
	append(&state.taskItems, ui.ListItem{text = "Deflector Shield Emitters", depth = 0, bullet = .Square, badge = "94%", badgeColor = rl.Color{251, 191, 36, 255}, badgeBg = rl.Color{45, 38, 20, 255}})
	append(&state.taskItems, ui.ListItem{text = "Long-Range Sensor Array", depth = 0, bullet = .Circle, badge = "STANDBY", badgeColor = rl.Color{160, 175, 205, 255}, badgeBg = rl.Color{30, 35, 48, 255}})
	state.selectedTaskIdx = 1

	// 3. Setup Telemetry Data Table
	state.tableColumns = make([dynamic]ui.TableColumn)
	append(&state.tableColumns, ui.TableColumn{title = "ID", width = 70, align = .Center, sortable = true})
	append(&state.tableColumns, ui.TableColumn{title = "Sensor Node", width = 170, align = .Start, sortable = true})
	append(&state.tableColumns, ui.TableColumn{title = "Reading", width = 110, align = .End, sortable = true})
	append(&state.tableColumns, ui.TableColumn{title = "State", width = 100, align = .Center, sortable = true})

	state.tableRows = make([dynamic]ui.TableRow)
	telemetryData := [4][4]string{
		{"#001", "Plasma Thermal Sensor", "1,420 K", "STABLE"},
		{"#002", "Graviton Detector", "0.98 G", "OPTIMAL"},
		{"#003", "Antimatter Containment", "99.4%", "ACTIVE"},
		{"#004", "Exhaust Port Vacuum", "10^-9 Pa", "NORMAL"},
	}

	for rowSlice, idx in telemetryData {
		cells := make([]ui.TableCell, 4)
		cells[0] = ui.TableCell{text = rowSlice[0], color = rl.Color{160, 175, 205, 255}}
		cells[1] = ui.TableCell{text = rowSlice[1], color = rl.Color{240, 244, 255, 255}}
		cells[2] = ui.TableCell{text = rowSlice[2], color = rl.Color{52, 211, 153, 255}}
		cells[3] = ui.TableCell{badge = rowSlice[3], badgeColor = rl.Color{52, 211, 153, 255}, badgeBg = rl.Color{20, 42, 34, 255}}
		append(&state.tableRows, ui.TableRow{cells = cells, id = 100 + idx})
	}
	state.selectedTableRow = 0
	state.tableSortCol = 0
	state.tableSortAsc = true
}

DestroyDashboardState :: proc(state: ^DashboardState) {
	delete(state.toolbarItems)
	delete(state.taskItems)
	delete(state.tableColumns)
	for r in state.tableRows {
		delete(r.cells)
	}
	delete(state.tableRows)
}

main :: proc() {
	// Headless / automated testing support
	isTestMode := false
	for arg in os.args[1:] {
		if arg == "--test" || arg == "--headless" || arg == "-t" {
			isTestMode = true
		}
	}

	windowWidth: i32 = 980
	windowHeight: i32 = 680

	if isTestMode {
		rl.SetConfigFlags({.WINDOW_HIDDEN})
	} else {
		rl.SetConfigFlags({.WINDOW_RESIZABLE})
	}

	rl.InitWindow(windowWidth, windowHeight, "UI Example - Studio & Operations Dashboard")
	defer rl.CloseWindow()

	rl.SetTargetFPS(60)

	ui.InitFonts()

	state: DashboardState
	InitDashboardState(&state)
	defer DestroyDashboardState(&state)

	themeIdx := 0
	frameCount := 0

	for !rl.WindowShouldClose() {
		frameCount += 1
		if isTestMode && frameCount >= 10 {
			break
		}

		// 1. Begin UI frame
		ui.ImmediateNav_BeginFrame()
		theme := ui.GetTheme()

		// 2. Render UI
		rl.BeginDrawing()
		rl.ClearBackground(theme.bgApp)

		// Top Toolbar
		toolbarRect := rl.Rectangle{16, 12, f32(rl.GetScreenWidth() - 32), 44}
		tClickedId, tClicked := ui.GuiToolbar(toolbarRect, state.toolbarItems[:], idKey = 1000)
		if tClicked {
			switch tClickedId {
			case 1:
				state.lastActionMsg = "Created new studio project."
			case 2:
				state.lastActionMsg = "Workspace file loaded."
			case 3:
				state.lastActionMsg = "Dashboard state persisted to disk."
			case 12:
				state.activeSimState = 12
				state.toolbarItems[4].isSelected = true
				state.toolbarItems[5].isSelected = false
				state.lastActionMsg = "Reactor simulation running."
			case 13:
				state.activeSimState = 13
				state.toolbarItems[4].isSelected = false
				state.toolbarItems[5].isSelected = true
				state.lastActionMsg = "Simulation paused."
			case 14:
				state.activeSimState = 14
				state.toolbarItems[4].isSelected = false
				state.toolbarItems[5].isSelected = false
				state.lastActionMsg = "Emergency halt initiated!"
			case 20:
				themeIdx = (themeIdx + 1) % 3
				if themeIdx == 0 do ui.SetTheme(ui.Theme_Dark())
				else if themeIdx == 1 do ui.SetTheme(ui.Theme_Light())
				else do ui.SetTheme(ui.Theme_Cyberpunk())
				state.lastActionMsg = "Theme toggled."
			}
		}

		mainW := f32(rl.GetScreenWidth() - 32)
		mainH := f32(rl.GetScreenHeight() - 100)
		leftW: f32 = 330.0
		rightW := mainW - leftW - 16.0

		// Left Card: System Task Explorer
		leftRect := rl.Rectangle{16, 68, leftW, mainH}
		ui.DrawThemeRect(leftRect, theme.bgPanel, theme.borderNormal, theme.borderRadius, 1.0)

		ui.GuiIcon(rl.Rectangle{leftRect.x + 16, leftRect.y + 14, 18, 18}, .ListUl, 16, theme.accent)
		ui.DrawTextStr("System Modules & Arsenal", leftRect.x + 40, leftRect.y + 14, 14, theme.textPrimary)

		listBounds := rl.Rectangle{leftRect.x + 14, leftRect.y + 42, leftRect.width - 28, leftRect.height - 56}
		_, clickedTask := ui.GuiUnorderedList(listBounds, state.taskItems[:], &state.selectedTaskIdx, &state.taskScroll, idKey = 2000)
		if clickedTask >= 0 {
			state.lastActionMsg = fmt.tprintf("Selected system: %s", state.taskItems[clickedTask].text)
		}

		// Right Card: Controls & Telemetry
		rightRect := rl.Rectangle{16 + leftW + 16, 68, rightW, mainH}
		ui.DrawThemeRect(rightRect, theme.bgPanel, theme.borderNormal, theme.borderRadius, 1.0)

		ui.GuiIcon(rl.Rectangle{rightRect.x + 16, rightRect.y + 14, 18, 18}, .Gauge, 16, theme.accent)
		ui.DrawTextStr("Telemetry Sensors & Audio Master", rightRect.x + 40, rightRect.y + 14, 14, theme.textPrimary)

		// Top Section of Right Card: Knobs & Faders
		knobW: f32 = 100.0
		knobY := rightRect.y + 46
		ui.GuiKnob(rl.Rectangle{rightRect.x + 16, knobY, knobW, 80}, "Flux Level", &state.reactorFluxKnob, 0.0, 100.0, 50.0, "%.1f%%", idKey = 3001)
		ui.GuiKnob(rl.Rectangle{rightRect.x + 128, knobY, knobW, 80}, "Attitude", &state.attitudeHeadingKnob, 0.0, 360.0, 0.0, "%.0f deg", idKey = 3002)
		ui.GuiKnob(rl.Rectangle{rightRect.x + 240, knobY, knobW, 80}, "Warp Drive", &state.warpFactorKnob, 1.0, 9.9, 1.0, "%.1f", idKey = 3003)

		// Vertical Audio Faders
		faderX := rightRect.x + 360
		ui.GuiVolumeFader(rl.Rectangle{faderX, knobY, 70, 120}, "MASTER", &state.audioMasterFader, -60.0, 6.0, 0.0, idKey = 3010)
		ui.GuiVolumeFader(rl.Rectangle{faderX + 80, knobY, 70, 120}, "SFX CH", &state.audioSfxFader, -60.0, 6.0, 0.0, idKey = 3011)

		// Bottom Section of Right Card: Telemetry Table
		tableY := knobY + 130
		ui.DrawTextStr("DIAGNOSTIC SENSOR TELEMETRY", rightRect.x + 16, tableY, 12, theme.textSecondary)
		tableBounds := rl.Rectangle{rightRect.x + 16, tableY + 20, rightRect.width - 32, rightRect.height - 210}
		_, clickedRow := ui.GuiTable(
			tableBounds,
			state.tableColumns[:],
			state.tableRows[:],
			&state.selectedTableRow,
			&state.tableSortCol,
			&state.tableSortAsc,
			idKey = 4000,
		)
		if clickedRow >= 0 {
			state.lastActionMsg = fmt.tprintf("Inspecting sensor: %s", state.tableRows[clickedRow].cells[1].text)
		}

		// Status Bar at Bottom
		statusRect := rl.Rectangle{16, f32(rl.GetScreenHeight() - 26), f32(rl.GetScreenWidth() - 32), 20}
		ui.GuiIcon(rl.Rectangle{statusRect.x, statusRect.y + 2, 14, 14}, .Info, 13, theme.info)
		ui.DrawTextStr(state.lastActionMsg, statusRect.x + 20, statusRect.y + 2, 12, theme.textSecondary)

		// 3. Process navigation and update cursor
		ui.ImmediateNav_Update()

		// 4. Render active dropdown overlay
		ui.RenderImmediateDropdownOverlay()

		rl.EndDrawing()
	}
}
