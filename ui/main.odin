package ui

import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"
import rl "vendor:raylib"

// ============================================================================
// Odin Standalone UI Showcase Application
// ============================================================================

ShowcaseState :: struct {
	// Active Tab: 0 = Controls, 1 = Lists & Trees, 2 = Visualizers, 3 = Spatial Grid
	activeTab: int,

	// Tab 0: Controls & Buttons
	buttonClickCount: int,
	lastActionMsg: string,
	actionTimer: f32,
	vsyncChecked: bool,
	wireframeChecked: bool,
	spatialAudioChecked: bool,
	telemetryChecked: bool,
	flightAssistActive: bool,
	plasmaThrustersActive: bool,
	deflectorFieldActive: bool,
	callsignBuffer: [dynamic]u8,
	coarseSliderVal: f32,
	fineSliderVal: f32,
	intSliderVal: f32,
	throttleKnobVal: f32,
	headingKnobVal: f32,
	reactorProgressVal: f32,
	reactorPulseDirection: f32,
	fuelProgressVal: f32,

	// Tab 1: Selection & Trees
	qualityPresetIdx: i32,
	aaPresetIdx: i32,
	displayModeIdx: i32,
	difficultyRadioIdx: int,
	inputDeviceRadioIdx: int,
	selectedListItem: int,
	listScroll: rl.Vector2,
	selectedTreeId: int,
	treeScroll: rl.Vector2,
	treeItems: [dynamic]TreeViewItem,

	// Tab 2: Visualizers & Plots
	pickerColor: rl.Color,
	alphaVal: f32,
	plotTimer: f32,
	plotPoints1: [64][2]f32,
	plotPoints2: [64][2]f32,
	gradientStops: [dynamic]ColorStop,
	selectedGradientStop: int,
	draggingGradientStop: bool,

	// Tab 3: Spatial 2D Grid Demo
	gridClickCounts: [12]int,
	lastNavEvent: string,

	// Tab 4: Vertical Tabs Showcase
	activeSubTab: int,
	warpKnobVal: f32,
	vectorKnobVal: f32,
	shieldHarmonicVal: f32,
	phaseVarianceVal: f32,

	// Tab 5: Audio Faders, Volume Meters & Notched Sliders
	faderValCh1: f32,
	faderValCh2: f32,
	faderValMaster: f32,
	meterStateMaster: VolumeMeterState,
	meterAudioTime: f32,
	meterAudioLevelL: f32,
	meterAudioLevelR: f32,
	horizNotchVal1: f32,
	horizNotchVal2: f32,
	vertNotchVal: f32,

	// Tab 6: Docking Interface System
	dockSpace: DockSpace,
	dockSimWidthRatio: f32,
	dockShowScene: bool,
	dockShowInspector: bool,
	dockShowConsole: bool,
	dockShowViewport: bool,
	dockSceneFilter: [dynamic]u8,
	dockInspectorPosX: f32,
	dockInspectorPosY: f32,
	dockInspectorScale: f32,
	dockInspectorColor: rl.Color,
	dockViewportShipPos: rl.Vector2,
	dockConsoleLogs: [6]string,

	// Tab 7: HTML Lists & Tables
	htmlUlItems: [dynamic]ListItem,
	htmlUlSelected: int,
	htmlUlScroll: rl.Vector2,

	htmlOlItems: [dynamic]ListItem,
	htmlOlSelected: int,
	htmlOlScroll: rl.Vector2,
	htmlOlStyle: NumberingStyle,

	htmlTableColumns: [dynamic]TableColumn,
	htmlTableRows: [dynamic]TableRow,
	htmlTableSelectedRow: int,
	htmlTableSortCol: int,
	htmlTableSortAsc: bool,
	htmlTableScroll: rl.Vector2,
	htmlTableActionMsg: string,

	// Test automation mode
	isTestMode: bool,
	testFrame: int,
}

GuiRadioGroup :: proc(
	rect: rl.Rectangle,
	label: string,
	options: []string,
	selectedIndex: ^int,
	horizontal: bool = false,
	idKey: uintptr = 0,
) -> bool {
	if !rl.IsWindowReady() || selectedIndex == nil do return false
	key := idKey if idKey != 0 else uintptr(selectedIndex)
	ImmediateNav_RegisterFocusable(key, rect)
	isFocused := ImmediateNav_IsFocused(key)

	changed := false
	count := len(options)
	mousePos := rl.GetMousePosition()
	mp := [2]f32{mousePos.x, mousePos.y}

	hoveredOpt := -1
	for i in 0..<count {
		optRect := GetRadioGroupOptionRect(rect, label != "", 110, count, horizontal, i)
		if PointInRect(mp, optRect) {
			hoveredOpt = i
			if IsUIMouseButtonPressed(.LEFT) {
				ImmediateNav_SetFocus(key)
				if selectedIndex^ != i {
					selectedIndex^ = i
					changed = true
				}
			}
		}
	}

	if isFocused && count > 0 {
		if horizontal {
			if rl.IsKeyPressed(.LEFT) || rl.IsKeyPressedRepeat(.LEFT) {
				selectedIndex^ = (selectedIndex^ - 1 + count) % count
				changed = true
			} else if rl.IsKeyPressed(.RIGHT) || rl.IsKeyPressedRepeat(.RIGHT) {
				selectedIndex^ = (selectedIndex^ + 1) % count
				changed = true
			}
		} else {
			if rl.IsKeyPressed(.UP) || rl.IsKeyPressedRepeat(.UP) {
				selectedIndex^ = (selectedIndex^ - 1 + count) % count
				changed = true
			} else if rl.IsKeyPressed(.DOWN) || rl.IsKeyPressedRepeat(.DOWN) {
				selectedIndex^ = (selectedIndex^ + 1) % count
				changed = true
			}
		}
	}

	RenderRadioGroup(rect, label, 110, options, selectedIndex^, hoveredOpt, horizontal, isFocused)
	return changed
}

InitShowcaseState :: proc(state: ^ShowcaseState) {
	state.activeTab = 0
	state.lastActionMsg = "System Ready. Use Mouse or Tab/Arrow keys to navigate."
	state.actionTimer = 5.0
	state.vsyncChecked = true
	state.wireframeChecked = false
	state.spatialAudioChecked = true
	state.telemetryChecked = true
	state.flightAssistActive = true
	state.plasmaThrustersActive = false
	state.deflectorFieldActive = true
	state.callsignBuffer = make([dynamic]u8)
	for b in transmute([]u8)string("VIPER-7") {
		append(&state.callsignBuffer, b)
	}
	state.coarseSliderVal = 65.0
	state.fineSliderVal = 4.25
	state.intSliderVal = 1024.0
	state.throttleKnobVal = 45.0
	state.headingKnobVal = 135.0
	state.reactorProgressVal = 0.72
	state.reactorPulseDirection = 0.2
	state.fuelProgressVal = 0.88

	state.qualityPresetIdx = 2 // High
	state.aaPresetIdx = 3      // MSAA 2x
	state.displayModeIdx = 0   // Windowed
	state.difficultyRadioIdx = 1
	state.inputDeviceRadioIdx = 0
	state.selectedListItem = 2
	state.selectedTreeId = 7

	state.pickerColor = rl.Color{59, 130, 246, 255}
	state.alphaVal = 0.95

	state.treeItems = make([dynamic]TreeViewItem)
	append(&state.treeItems, TreeViewItem{id = 1, label = "Root Universe Scene", depth = 0, hasChildren = true, isCollapsed = false, isSelected = false})
	append(&state.treeItems, TreeViewItem{id = 2, label = "Main Camera [2D Viewport]", depth = 1, hasChildren = false, isCollapsed = false})
	append(&state.treeItems, TreeViewItem{id = 3, label = "Deep Space Environment", depth = 1, hasChildren = true, isCollapsed = false})
	append(&state.treeItems, TreeViewItem{id = 4, label = "Background Nebula", depth = 2, hasChildren = false, isCollapsed = false})
	append(&state.treeItems, TreeViewItem{id = 5, label = "Cosmic Star Emitter", depth = 2, hasChildren = false, isCollapsed = false})
	append(&state.treeItems, TreeViewItem{id = 6, label = "Asteroid Belt Hazard", depth = 2, hasChildren = false, isCollapsed = false})
	append(&state.treeItems, TreeViewItem{id = 7, label = "Interceptor Spaceship", depth = 1, hasChildren = true, isCollapsed = false, isSelected = true})
	append(&state.treeItems, TreeViewItem{id = 8, label = "Reinforced Hull Mesh", depth = 2, hasChildren = false, isCollapsed = false})
	append(&state.treeItems, TreeViewItem{id = 9, label = "Port Plasma Cannon", depth = 2, hasChildren = false, isCollapsed = false})
	append(&state.treeItems, TreeViewItem{id = 10, label = "Starboard Plasma Cannon", depth = 2, hasChildren = false, isCollapsed = false})
	append(&state.treeItems, TreeViewItem{id = 11, label = "Twin Afterburner Thruster", depth = 2, hasChildren = false, isCollapsed = false})
	append(&state.treeItems, TreeViewItem{id = 12, label = "Heads-Up Display Canvas", depth = 1, hasChildren = false, isCollapsed = false})

	state.gradientStops = make([dynamic]ColorStop)
	append(&state.gradientStops, ColorStop{position = 0.0, color = rl.Color{239, 68, 68, 255}})
	append(&state.gradientStops, ColorStop{position = 0.35, color = rl.Color{245, 158, 11, 255}})
	append(&state.gradientStops, ColorStop{position = 0.70, color = rl.Color{59, 130, 246, 255}})
	append(&state.gradientStops, ColorStop{position = 1.0, color = rl.Color{16, 185, 129, 255}})
	state.selectedGradientStop = 0

	state.lastNavEvent = "Spatial Grid Ready. Use Arrow keys to move between cells."

	state.activeSubTab = 0
	state.warpKnobVal = 4.5
	state.vectorKnobVal = 15.0
	state.shieldHarmonicVal = 42.8
	state.phaseVarianceVal = 12.4

	state.faderValCh1 = -6.0
	state.faderValCh2 = -12.0
	state.faderValMaster = 0.0
	state.horizNotchVal1 = 2.0
	state.horizNotchVal2 = 2.0
	state.vertNotchVal = 3.0

	// Initialize DockSpace with 4 default panels
	DockSpace_Init(&state.dockSpace, rl.Rectangle{20, 192, 1240, 560})
	DockSpace_AddPanel(&state.dockSpace, "scene", "Scene Hierarchy", .Left, {50, 220}, {260, 360})
	DockSpace_AddPanel(&state.dockSpace, "viewport", "Interactive 2D Viewport", .Center, {330, 220}, {500, 360})
	DockSpace_AddPanel(&state.dockSpace, "inspector", "Entity Inspector", .Right, {850, 220}, {300, 360})
	DockSpace_AddPanel(&state.dockSpace, "console", "Diagnostics & Console", .Bottom, {50, 480}, {700, 200})

	state.dockSimWidthRatio = 1.0
	state.dockShowScene = true
	state.dockShowInspector = true
	state.dockShowConsole = true
	state.dockShowViewport = true
	state.dockSceneFilter = make([dynamic]u8)
	state.dockInspectorPosX = 640.0
	state.dockInspectorPosY = 380.0
	state.dockInspectorScale = 1.25
	state.dockInspectorColor = rl.Color{59, 130, 246, 255}
	state.dockViewportShipPos = {200, 130}
	state.dockConsoleLogs = [6]string{
		"[10:42:01.102] [CORE] Docking workspace initialized with 4 default panels.",
		"[10:42:01.150] [PHYS] Proportional layout calculated with Left/Right/Bottom splits.",
		"[10:42:01.210] [VIEW] 2D Viewport canvas bound to Center dock zone.",
		"[10:42:02.045] [SCENE] Selected entity: Viper-MK2 (Transform: 640, 380, 1.25x).",
		"[10:42:02.890] [DOCK] Panels survive window resizing via normalized ratio preservation.",
		"[10:42:03.112] [SYSTEM] Ready for interactive drag-and-drop or splitter adjustments.",
	}

	// Initialize HTML Unordered List (<ul>)
	state.htmlUlItems = make([dynamic]ListItem)
	append(&state.htmlUlItems, ListItem{text = "Spacecraft Sub-Systems & Arsenal", depth = 0, isHeader = true})
	append(&state.htmlUlItems, ListItem{text = "Sub-light Ion Thruster Array", depth = 0, bullet = .Disc, badge = "ONLINE", badgeColor = rl.Color{52, 211, 153, 255}, badgeBg = rl.Color{20, 42, 34, 255}})
	append(&state.htmlUlItems, ListItem{text = "Dual High-Yield Plasma Cannons", depth = 0, bullet = .Disc, badge = "ARMED", badgeColor = rl.Color{239, 68, 68, 255}, badgeBg = rl.Color{45, 20, 24, 255}})
	append(&state.htmlUlItems, ListItem{text = "Forward Deflector Shield Matrix", depth = 0, bullet = .Dash, badge = "98%", badgeColor = rl.Color{96, 165, 250, 255}, badgeBg = rl.Color{20, 32, 50, 255}})
	append(&state.htmlUlItems, ListItem{text = "Structural Nanite Repair Cells", depth = 0, bullet = .Square, badge = "STANDBY", badgeColor = rl.Color{251, 191, 36, 255}, badgeBg = rl.Color{45, 38, 20, 255}})
	append(&state.htmlUlItems, ListItem{text = "Auxiliary Core Modules", depth = 1, bullet = .Circle})
	append(&state.htmlUlItems, ListItem{text = "Hyperdrive Jump Computer", depth = 1, bullet = .Circle, badge = "CHARGED", badgeColor = rl.Color{52, 211, 153, 255}, badgeBg = rl.Color{20, 42, 34, 255}})
	append(&state.htmlUlItems, ListItem{text = "Reinforced Escape Cockpit Pod", depth = 1, bullet = .Arrow})
	state.htmlUlSelected = 1

	// Initialize HTML Ordered List (<ol>)
	state.htmlOlItems = make([dynamic]ListItem)
	append(&state.htmlOlItems, ListItem{text = "Pre-Flight Launch Checklist", depth = 0, isHeader = true})
	append(&state.htmlOlItems, ListItem{text = "Initialize main reactor core flux", depth = 0, number = 1, badge = "DONE", badgeColor = rl.Color{52, 211, 153, 255}, badgeBg = rl.Color{20, 42, 34, 255}})
	append(&state.htmlOlItems, ListItem{text = "Establish quantum telemetry comm link", depth = 0, number = 2, badge = "ACTIVE", badgeColor = rl.Color{96, 165, 250, 255}, badgeBg = rl.Color{20, 32, 50, 255}})
	append(&state.htmlOlItems, ListItem{text = "Calibrate celestial guidance gyroscopes", depth = 0, number = 3})
	append(&state.htmlOlItems, ListItem{text = "Disengage orbital dock umbilical clamps", depth = 0, number = 4})
	append(&state.htmlOlItems, ListItem{text = "Confirm magnetic lock release", depth = 1, number = 1, badge = "VERIFIED", badgeColor = rl.Color{52, 211, 153, 255}, badgeBg = rl.Color{20, 42, 34, 255}})
	append(&state.htmlOlItems, ListItem{text = "Fire cold-gas attitude RCS thrusters", depth = 1, number = 2, badge = "NOMINAL", badgeColor = rl.Color{52, 211, 153, 255}, badgeBg = rl.Color{20, 42, 34, 255}})
	append(&state.htmlOlItems, ListItem{text = "Engage sub-light drive for departure", depth = 0, number = 5, badge = "READY", badgeColor = rl.Color{251, 191, 36, 255}, badgeBg = rl.Color{45, 38, 20, 255}})
	state.htmlOlSelected = 2
	state.htmlOlStyle = .Decimal

	// Initialize HTML Table (<table>)
	state.htmlTableColumns = make([dynamic]TableColumn)
	append(&state.htmlTableColumns, TableColumn{title = "ID", width = 52.0, align = .Center, sortable = true})
	append(&state.htmlTableColumns, TableColumn{title = "Entity Vessel", width = 0.28, align = .Start, sortable = true})
	append(&state.htmlTableColumns, TableColumn{title = "Class / Type", width = 0.22, align = .Start, sortable = true})
	append(&state.htmlTableColumns, TableColumn{title = "Hull", width = 75.0, align = .End, sortable = true})
	append(&state.htmlTableColumns, TableColumn{title = "Shields", width = 75.0, align = .End, sortable = true})
	append(&state.htmlTableColumns, TableColumn{title = "Status", width = 95.0, align = .Center, sortable = true})

	rawTableData := [][]string{
		{"#101", "Viper-MK2", "Interceptor", "100%", "95%", "ONLINE"},
		{"#102", "Dreadnought-X", "Heavy Cruiser", "84%", "72%", "COMBAT"},
		{"#103", "Aegis-IV", "Escort Frigate", "92%", "100%", "PATROL"},
		{"#104", "Orion Station", "Orbital Starbase", "100%", "100%", "STABLE"},
		{"#105", "Valkyrie-9", "Stealth Recon", "68%", "45%", "DAMAGED"},
		{"#106", "Titan Hauler", "Bulk Freighter", "78%", "30%", "TRANSIT"},
		{"#107", "Ghost Probe", "Survey Drone", "42%", "0%", "CRITICAL"},
		{"#108", "Solar Array", "Power Station", "99%", "98%", "ONLINE"},
	}

	state.htmlTableRows = make([dynamic]TableRow)
	for rowSlice, idx in rawTableData {
		cells := make([]TableCell, 6)
		cells[0] = TableCell{text = rowSlice[0], color = rl.Color{160, 175, 205, 255}}
		cells[1] = TableCell{text = rowSlice[1], color = rl.Color{240, 244, 255, 255}}
		cells[2] = TableCell{text = rowSlice[2], color = rl.Color{190, 200, 220, 255}}
		cells[3] = TableCell{text = rowSlice[3], color = rl.Color{52, 211, 153, 255}}
		cells[4] = TableCell{text = rowSlice[4], color = rl.Color{96, 165, 250, 255}}

		statusBadge := rowSlice[5]
		bCol := rl.Color{52, 211, 153, 255}
		bBg := rl.Color{20, 42, 34, 255}
		if statusBadge == "COMBAT" || statusBadge == "CRITICAL" {
			bCol = rl.Color{239, 68, 68, 255}
			bBg = rl.Color{45, 20, 24, 255}
		} else if statusBadge == "DAMAGED" {
			bCol = rl.Color{251, 191, 36, 255}
			bBg = rl.Color{45, 38, 20, 255}
		} else if statusBadge == "PATROL" || statusBadge == "TRANSIT" {
			bCol = rl.Color{96, 165, 250, 255}
			bBg = rl.Color{20, 32, 50, 255}
		}
		cells[5] = TableCell{badge = statusBadge, badgeColor = bCol, badgeBg = bBg}

		append(&state.htmlTableRows, TableRow{cells = cells, id = 100 + idx})
	}

	state.htmlTableSelectedRow = 0
	state.htmlTableSortCol = 0
	state.htmlTableSortAsc = true
	state.htmlTableActionMsg = "Vessel #101 (Viper-MK2) telemetry synchronized."
}

DestroyShowcaseState :: proc(state: ^ShowcaseState) {
	delete(state.callsignBuffer)
	delete(state.treeItems)
	delete(state.gradientStops)
	DockSpace_Destroy(&state.dockSpace)
	delete(state.dockSceneFilter)
	delete(state.htmlUlItems)
	delete(state.htmlOlItems)
	delete(state.htmlTableColumns)
	for r in state.htmlTableRows {
		delete(r.cells)
	}
	delete(state.htmlTableRows)
}

main :: proc() {
	state: ShowcaseState
	InitShowcaseState(&state)
	defer DestroyShowcaseState(&state)

	hideWindow := false
	for arg in os.args[1:] {
		if arg == "--test" || arg == "--headless" || arg == "-t" || arg == "-test" {
			state.isTestMode = true
		hideWindow = true
		} else if arg == "--e2e" || arg == "--record" || arg == "-e2e" {
			state.isTestMode = true
		hideWindow = false
		}
	}

	if hideWindow {
		TestHook_Init("ui_screenshots", 60)
	}

	windowWidth: i32 = 1280
	windowHeight: i32 = 820

	if state.isTestMode {
		rl.SetConfigFlags({.WINDOW_HIDDEN})
	} else {
		rl.SetConfigFlags({.WINDOW_RESIZABLE})
	}

	rl.InitWindow(windowWidth, windowHeight, "Odin UI Showcase - Standalone UI Library & Navigation Demo")
	defer rl.CloseWindow()

	rl.SetTargetFPS(60)

	// Initialize UI fonts
	fontP: cstring = "engine/Open_Sans/static/OpenSans-Regular.ttf"
	if !os.exists("engine/Open_Sans/static/OpenSans-Regular.ttf") && os.exists("../engine/Open_Sans/static/OpenSans-Regular.ttf") {
		fontP = "../engine/Open_Sans/static/OpenSans-Regular.ttf"
	}
	InitFonts(fontP)
	defer UnloadFonts()

	soundItems := []string{
		"Laser Cannon Fire Alpha",
		"Heavy Plasma Torpedo",
		"Shield Deflector Pulse",
		"Hull Repair Nanites",
		"Sub-light Ion Booster",
		"Hyperdrive Jump Sequence",
		"Proximity Warning Siren",
		"Tactical Radar Ping",
		"Countermeasure Flare",
		"Point Defense Turret",
	}

	tabNames := []string{
		"1. Controls & Buttons",
		"2. Lists & Trees",
		"3. Visualizers & Plots",
		"4. 2D Spatial Grid",
		"5. Vertical Tabs",
		"6. Audio & Detents",
		"7. Docking System",
		"8. HTML Lists & Tables",
	}

	diffOptions := []string{"Cadet", "Officer", "Commander", "Legendary"}
	deviceOptions := []string{"Keyboard & Mouse", "Gamepad", "HOTAS Stick"}

	main_loop: for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()
		if dt <= 0.0 || dt > 0.1 do dt = 0.016

		// Update telemetry animations
		state.plotTimer += dt
		for i in 0..<64 {
			t := f32(i) / 63.0
			state.plotPoints1[i] = {t, 0.5 + 0.35 * math.sin(t * 10.0 + state.plotTimer * 2.5)}
			state.plotPoints2[i] = {t, 0.5 + 0.25 * math.cos(t * 7.0 - state.plotTimer * 1.8) * math.sin(t * 3.5)}
		}

		// Update reactor progress animation
		state.reactorProgressVal += state.reactorPulseDirection * dt * 0.15
		if state.reactorProgressVal >= 0.98 {
			state.reactorProgressVal = 0.98
			state.reactorPulseDirection = -0.2
		} else if state.reactorProgressVal <= 0.20 {
			state.reactorProgressVal = 0.20
			state.reactorPulseDirection = 0.2
		}

		if state.actionTimer > 0 {
			state.actionTimer -= dt
		}

		// Update audio meter telemetry signal
		state.meterAudioTime += dt
		baseSignal := math.sin(state.meterAudioTime * 5.5) * 8.0 + math.cos(state.meterAudioTime * 13.0) * 4.0
		state.meterAudioLevelL = clamp(state.faderValMaster + baseSignal - 6.0, -60.0, 3.0)
		state.meterAudioLevelR = clamp(state.faderValMaster + baseSignal * 0.85 - 8.0, -60.0, 3.0)

		// Begin Immediate-mode UI Frame
		ImmediateNav_BeginFrame()

		rl.BeginDrawing()
		rl.ClearBackground(rl.Color{16, 18, 23, 255})

		// --------------------------------------------------------------------
		// 1. Top Header Banner
		// --------------------------------------------------------------------
		headerRect := rl.Rectangle{0, 0, f32(rl.GetScreenWidth()), 72}
		rl.DrawRectangleRec(headerRect, rl.Color{22, 25, 32, 255})
		rl.DrawLineEx({0, 72}, {f32(rl.GetScreenWidth()), 72}, 1, rl.Color{45, 50, 64, 255})

		// Title and Badges
		DrawTextStr("ODIN STANDALONE UI SHOWCASE", 24, 14, 20, rl.Color{245, 247, 250, 255})
		DrawTextStr("Hardware-accelerated immediate & retained widgets with Tab & 2D spatial keyboard navigation", 24, 38, 12, rl.Color{140, 148, 168, 255})

		// Navigation Hotkeys Legend
		legendX: f32 = f32(rl.GetScreenWidth()) - 540
		DrawTextStr("Tab / Shift+Tab: Cycle Focus", legendX, 14, 12, rl.Color{96, 165, 250, 255})
		DrawTextStr("Arrows: 2D Spatial / Adjust", legendX + 200, 14, 12, rl.Color{52, 211, 153, 255})
		DrawTextStr("Enter/Space: Activate", legendX, 36, 12, rl.Color{251, 191, 36, 255})
		DrawTextStr("Esc: Close/Clear", legendX + 200, 36, 12, rl.Color{248, 113, 113, 255})

		// Live Focus Indicator Badge
		curFocusKey := immediateNav.focusedKey
		focusText := fmt.tprintf("Focused Key: 0x%X  |  Items: %d", curFocusKey, immediateNav.itemCount) if curFocusKey != 0 else fmt.tprintf("No Focused Item  |  Items: %d", immediateNav.itemCount)
		DrawTextStr(focusText, legendX + 350, 25, 11, rl.Color{170, 175, 190, 255})

		// --------------------------------------------------------------------
		// 2. Tab Bar
		// --------------------------------------------------------------------
		tabBarRect := rl.Rectangle{20, 84, f32(rl.GetScreenWidth()) - 40, 34}
		tabChanged, _, contentBounds := GuiTabBar(tabBarRect, tabNames, &state.activeTab, .Horizontal, 32, idKey = 99990)
		_ = tabChanged
		_ = contentBounds

		// Content area layout
		contentArea := rl.Rectangle{20, 128, f32(rl.GetScreenWidth()) - 40, f32(rl.GetScreenHeight()) - 170}

		// --------------------------------------------------------------------
		// TAB 0: Controls & Buttons
		// --------------------------------------------------------------------
		if state.activeTab == 0 {
			halfW := (contentArea.width - 20) * 0.5

			// Left Panel: Action Buttons, Checkboxes, Toggle Switches
			leftPanelRect := rl.Rectangle{contentArea.x, contentArea.y, halfW, contentArea.height}
			RenderContainerPanel(
				leftPanelRect,
				"Action Controls & Discrete Switches",
				true, true, true, 34,
				rl.Color{22, 25, 33, 240},
				rl.Color{28, 33, 44, 255},
				rl.Color{50, 56, 74, 255},
				rl.Color{230, 235, 245, 255},
			)

			btnY := leftPanelRect.y + 48
			btnW: f32 = (leftPanelRect.width - 48) / 3.0

			// Button 1: Primary
			if GuiButton(rl.Rectangle{leftPanelRect.x + 16, btnY, btnW, 36}, "Launch Rocket", .Center, isSelected = false, idKey = 1001) {
				state.buttonClickCount += 1
				state.lastActionMsg = fmt.tprintf("Launch Rocket clicked! Total clicks: %d", state.buttonClickCount)
				state.actionTimer = 4.0
			}

			// Button 2: Calibrate
			if GuiButton(rl.Rectangle{leftPanelRect.x + 24 + btnW, btnY, btnW, 36}, "Calibrate", .Center, isSelected = true, idKey = 1002) {
				state.buttonClickCount += 1
				state.lastActionMsg = "Guidance gyro successfully calibrated."
				state.actionTimer = 4.0
			}

			// Button 3: Emergency Vent
			if GuiButton(rl.Rectangle{leftPanelRect.x + 32 + btnW * 2.0, btnY, btnW, 36}, "Emergency Vent", .Center, isSelected = false, idKey = 1003) {
				state.buttonClickCount += 1
				state.lastActionMsg = "Emergency Vent valves purged!"
				state.actionTimer = 4.0
			}

			// Feedback status line
			statusRect := rl.Rectangle{leftPanelRect.x + 16, btnY + 44, leftPanelRect.width - 32, 26}
			rl.DrawRectangleRec(statusRect, rl.Color{28, 32, 42, 200})
			rl.DrawRectangleLinesEx(statusRect, 1, rl.Color{45, 52, 70, 255})
			DrawTextStr(state.lastActionMsg, statusRect.x + 10, statusRect.y + 7, 12, rl.Color{52, 211, 153, 255})

			// Checkboxes
			chkY := statusRect.y + 36
			DrawTextStr("SYSTEM SETTINGS (CHECKBOXES)", leftPanelRect.x + 16, chkY, 11, rl.Color{130, 140, 165, 255})
			chkY += 18

			if GuiCheckBox(rl.Rectangle{leftPanelRect.x + 16, chkY, leftPanelRect.width - 32, 26}, "Enable VSync (Hardware Refresh Lock)", &state.vsyncChecked, idKey = 1010) {
				state.lastActionMsg = fmt.tprintf("VSync set to: %v", state.vsyncChecked)
			}
			chkY += 30

			if GuiCheckBox(rl.Rectangle{leftPanelRect.x + 16, chkY, leftPanelRect.width - 32, 26}, "Show Collision Wireframes & Geometry", &state.wireframeChecked, idKey = 1011) {
				state.lastActionMsg = fmt.tprintf("Wireframes set to: %v", state.wireframeChecked)
			}
			chkY += 30

			if GuiCheckBox(rl.Rectangle{leftPanelRect.x + 16, chkY, leftPanelRect.width - 32, 26}, "3D Positional Audio & Doppler Shift", &state.spatialAudioChecked, idKey = 1012) {
				state.lastActionMsg = fmt.tprintf("Spatial audio set to: %v", state.spatialAudioChecked)
			}
			chkY += 30

			if GuiCheckBox(rl.Rectangle{leftPanelRect.x + 16, chkY, leftPanelRect.width - 32, 26}, "Record Telemetry Diagnostics to Memory", &state.telemetryChecked, idKey = 1013) {
				state.lastActionMsg = fmt.tprintf("Telemetry logging set to: %v", state.telemetryChecked)
			}

			// Toggle Switches
			swY := chkY + 44
			DrawTextStr("PROPULSION & SHIELDS (TOGGLE SWITCHES)", leftPanelRect.x + 16, swY, 11, rl.Color{130, 140, 165, 255})
			swY += 18

			if GuiToggleSwitch(rl.Rectangle{leftPanelRect.x + 16, swY, leftPanelRect.width - 32, 30}, "Fly-By-Wire Flight Computer", &state.flightAssistActive, idKey = 1020) {
				state.lastActionMsg = fmt.tprintf("Flight Computer: %v", state.flightAssistActive)
			}
			swY += 36

			if GuiToggleSwitch(rl.Rectangle{leftPanelRect.x + 16, swY, leftPanelRect.width - 32, 30}, "High-Energy Plasma Thrusters", &state.plasmaThrustersActive, idKey = 1021) {
				state.lastActionMsg = fmt.tprintf("Plasma Thrusters: %v", state.plasmaThrustersActive)
			}
			swY += 36

			if GuiToggleSwitch(rl.Rectangle{leftPanelRect.x + 16, swY, leftPanelRect.width - 32, 30}, "Forward Deflector Shield Matrix", &state.deflectorFieldActive, idKey = 1022) {
				state.lastActionMsg = fmt.tprintf("Deflector Field: %v", state.deflectorFieldActive)
			}

			// Text Input for Callsign
			tiY := swY + 44
			DrawTextStr("VESSEL COMMUNICATIONS (TEXT INPUT)", leftPanelRect.x + 16, tiY, 11, rl.Color{130, 140, 165, 255})
			tiY += 18
			tiChanged, tiSubmitted := GuiTextInput(
				rl.Rectangle{leftPanelRect.x + 16, tiY, leftPanelRect.width - 32, 28},
				"Pilot Callsign",
				&state.callsignBuffer,
				"Enter callsign...",
				110,
				idKey = 1025,
			)
			if tiChanged || tiSubmitted {
				state.lastActionMsg = fmt.tprintf("Callsign updated: %s", string(state.callsignBuffer[:]))
			}

			// Transmit Callsign Action Button
			if GuiButton(rl.Rectangle{leftPanelRect.x + 16, tiY + 36, 170, 28}, "Transmit Callsign", .Center, isSelected = false, idKey = 1026) {
				state.lastActionMsg = fmt.tprintf("Callsign [%s] transmitted to fleet command!", string(state.callsignBuffer[:]))
				state.actionTimer = 4.0
			}

			// Right Panel: Sliders, Knobs, Progress Bars
			rightPanelRect := rl.Rectangle{contentArea.x + halfW + 20, contentArea.y, halfW, contentArea.height}
			RenderContainerPanel(
				rightPanelRect,
				"Continuous Sliders, Rotary Knobs & Progress",
				true, true, true, 34,
				rl.Color{22, 25, 33, 240},
				rl.Color{28, 33, 44, 255},
				rl.Color{50, 56, 74, 255},
				rl.Color{230, 235, 245, 255},
			)

			slY := rightPanelRect.y + 48
			DrawTextStr("CONTINUOUS SLIDERS (DRAG OR USE ARROW KEYS)", rightPanelRect.x + 16, slY, 11, rl.Color{130, 140, 165, 255})
			slY += 18

			// Slider 1: Coarse Volume
			_ = GuiSlider(rl.Rectangle{rightPanelRect.x + 16, slY, rightPanelRect.width - 32, 26}, "Main Volume", "%", &state.coarseSliderVal, 0.0, 100.0, false, idKey = 1030, labelWidth = 100)
			slY += 36

			// Slider 2: Fine with Shift-Drag
			_ = GuiSlider(rl.Rectangle{rightPanelRect.x + 16, slY, rightPanelRect.width - 32, 26}, "Tuning Freq", "kHz", &state.fineSliderVal, 0.0, 10.0, false, idKey = 1031, labelWidth = 100)
			slY += 36

			// Slider 3: Integer with Inline Text Edit
			_ = GuiSlider(rl.Rectangle{rightPanelRect.x + 16, slY, rightPanelRect.width - 32, 26}, "Bandwidth", "kbps", &state.intSliderVal, 128.0, 4096.0, true, idKey = 1032, labelWidth = 100)

			// Rotary Knobs (Fine adjustment supported via Shift+Drag, Shift+Wheel, or Shift+Arrows)
			knobY := slY + 48
			DrawTextStr("ROTARY DIAL KNOBS (DRAG VERTICALLY OR SHIFT FOR FINE ADJUST)", rightPanelRect.x + 16, knobY, 11, rl.Color{130, 140, 165, 255})
			knobY += 18

			knobW: f32 = (rightPanelRect.width - 48) * 0.5
			_ = GuiKnob(rl.Rectangle{rightPanelRect.x + 16, knobY, knobW, 80}, "Engine Throttle", &state.throttleKnobVal, 0.0, 100.0, 50.0, "%.0f%%", idKey = 1040)
			_ = GuiKnob(rl.Rectangle{rightPanelRect.x + 32 + knobW, knobY, knobW, 80}, "Nav Heading", &state.headingKnobVal, 0.0, 360.0, 0.0, "%.0f deg", idKey = 1041)

			// Progress Bars
			progY := knobY + 98
			DrawTextStr("SYSTEM METERS (PROGRESS BARS)", rightPanelRect.x + 16, progY, 11, rl.Color{130, 140, 165, 255})
			progY += 24

			// Meter 1: Reactor Core Flux
			GuiProgressBar(rl.Rectangle{rightPanelRect.x + 16, progY, rightPanelRect.width - 120, 24}, "Reactor Core Flux", state.reactorProgressVal * 100.0, 0.0, 100.0, .Horizontal, true)

			// Meter 2: Deflector Shield Capacity
			shieldProgressVal: f32 = 94.5
			GuiProgressBar(rl.Rectangle{rightPanelRect.x + 16, progY + 34, rightPanelRect.width - 120, 24}, "Deflector Shield Capacity", shieldProgressVal, 0.0, 100.0, .Horizontal, true)

			// Meter 3: Vertical Fuel Cell Gauge (Starts below header, aligns with horizontal meters)
			vProgRect := rl.Rectangle{rightPanelRect.x + rightPanelRect.width - 80, progY + 16, 40, 78}
			GuiProgressBar(vProgRect, "Fuel", state.fuelProgressVal * 100.0, 0.0, 100.0, .Vertical, true)
		}

		// --------------------------------------------------------------------
		// TAB 1: Lists, Trees & Menus
		// --------------------------------------------------------------------
		if state.activeTab == 1 {
			halfW := (contentArea.width - 20) * 0.5

			// Left Panel: Dropdowns & Radio Selectors
			leftPanelRect := rl.Rectangle{contentArea.x, contentArea.y, halfW, contentArea.height}
			RenderContainerPanel(
				leftPanelRect,
				"Dropdown Combos & Radio Groups",
				true, true, true, 34,
				rl.Color{22, 25, 33, 240},
				rl.Color{28, 33, 44, 255},
				rl.Color{50, 56, 74, 255},
				rl.Color{230, 235, 245, 255},
			)

			ddY := leftPanelRect.y + 48
			DrawTextStr("POPUP DROPDOWNS (KEYBOARD ARROWS + ENTER)", leftPanelRect.x + 16, ddY, 11, rl.Color{130, 140, 165, 255})
			ddY += 18

			DrawTextStr("Render Quality Preset:", leftPanelRect.x + 16, ddY, 12, rl.Color{200, 205, 220, 255})
			_ = GuiDropdownBox(rl.Rectangle{leftPanelRect.x + 180, ddY - 4, leftPanelRect.width - 200, 26}, "Low;Medium;High;Ultra;Cinematic", &state.qualityPresetIdx, idKey = 2001)
			ddY += 38

			DrawTextStr("Anti-Aliasing Mode:", leftPanelRect.x + 16, ddY, 12, rl.Color{200, 205, 220, 255})
			_ = GuiDropdownBox(rl.Rectangle{leftPanelRect.x + 180, ddY - 4, leftPanelRect.width - 200, 26}, "None;FXAA;SMAA;MSAA 2x;MSAA 4x;MSAA 8x", &state.aaPresetIdx, idKey = 2002)
			ddY += 38

			DrawTextStr("Display Resolution:", leftPanelRect.x + 16, ddY, 12, rl.Color{200, 205, 220, 255})
			_ = GuiDropdownBox(rl.Rectangle{leftPanelRect.x + 180, ddY - 4, leftPanelRect.width - 200, 26}, "Windowed 1280x820;Windowed 1920x1080;Borderless Fullscreen;Exclusive 4K", &state.displayModeIdx, idKey = 2003)
			ddY += 46

			// Radio Groups
			DrawTextStr("DIFFICULTY TIER (VERTICAL RADIO GROUP)", leftPanelRect.x + 16, ddY, 11, rl.Color{130, 140, 165, 255})
			ddY += 18
			GuiRadioGroup(rl.Rectangle{leftPanelRect.x + 16, ddY, leftPanelRect.width - 32, 108}, "Difficulty", diffOptions, &state.difficultyRadioIdx, false, idKey = 2010)
			ddY += 124

			DrawTextStr("CONTROL DEVICE (HORIZONTAL RADIO GROUP)", leftPanelRect.x + 16, ddY, 11, rl.Color{130, 140, 165, 255})
			ddY += 18
			GuiRadioGroup(rl.Rectangle{leftPanelRect.x + 16, ddY, leftPanelRect.width - 32, 30}, "Device", deviceOptions, &state.inputDeviceRadioIdx, true, idKey = 2011)

			// Inspection Card & Selection Details
			cardY := ddY + 46
			DrawTextStr("INSPECTION CARD (DATA BINDING FEEDBACK)", leftPanelRect.x + 16, cardY, 11, rl.Color{130, 140, 165, 255})
			cardY += 18

			cardRect := rl.Rectangle{leftPanelRect.x + 16, cardY, leftPanelRect.width - 32, 110}
			rl.DrawRectangleRec(cardRect, rl.Color{28, 33, 44, 220})
			rl.DrawRectangleLinesEx(cardRect, 1, rl.Color{55, 65, 88, 255})

			selSoundName := soundItems[state.selectedListItem] if state.selectedListItem >= 0 && state.selectedListItem < len(soundItems) else "None"
			selTreeName := "None"
			selTreeDepth := 0
			for item in state.treeItems {
				if item.id == state.selectedTreeId {
					selTreeName = item.label
					selTreeDepth = item.depth
					break
				}
			}

			DrawTextStr(fmt.tprintf("Selected Audio Asset:  %s (Index %d)", selSoundName, state.selectedListItem), cardRect.x + 12, cardRect.y + 12, 12, rl.Color{96, 165, 250, 255})
			DrawTextStr(fmt.tprintf("Selected Scene Node:   %s (ID #%d, Depth %d)", selTreeName, state.selectedTreeId, selTreeDepth), cardRect.x + 12, cardRect.y + 36, 12, rl.Color{52, 211, 153, 255})
			DrawTextStr(fmt.tprintf("Quality: Preset #%d  |  AA: %s  |  Difficulty: %s", state.qualityPresetIdx, "MSAA 2x" if state.aaPresetIdx == 3 else "Active", diffOptions[state.difficultyRadioIdx]), cardRect.x + 12, cardRect.y + 60, 11, rl.Color{200, 205, 225, 255})
			DrawTextStr(fmt.tprintf("Active Device Input:   %s", deviceOptions[state.inputDeviceRadioIdx]), cardRect.x + 12, cardRect.y + 84, 11, rl.Color{251, 191, 36, 255})

			// Right Panel: List View & Tree View
			rightPanelRect := rl.Rectangle{contentArea.x + halfW + 20, contentArea.y, halfW, contentArea.height}
			RenderContainerPanel(
				rightPanelRect,
				"Scrollable List View & Scene Hierarchy Tree",
				true, true, true, 34,
				rl.Color{22, 25, 33, 240},
				rl.Color{28, 33, 44, 255},
				rl.Color{50, 56, 74, 255},
				rl.Color{230, 235, 245, 255},
			)

			rvY := rightPanelRect.y + 48
			DrawTextStr("AUDIO ASSETS (SCROLLABLE LIST VIEW)", rightPanelRect.x + 16, rvY, 11, rl.Color{130, 140, 165, 255})
			rvY += 18

			listRect := rl.Rectangle{rightPanelRect.x + 16, rvY, rightPanelRect.width - 32, 150}
			listChanged, _ := GuiListView(listRect, soundItems, &state.selectedListItem, &state.listScroll, itemHeight = 24, idKey = 2020)
			_ = listChanged

			// Tree View
			treeY := listRect.y + listRect.height + 20
			DrawTextStr("SCENE HIERARCHY (INTERACTIVE EXPANDABLE TREE)", rightPanelRect.x + 16, treeY, 11, rl.Color{130, 140, 165, 255})
			treeY += 18

			treeRect := rl.Rectangle{rightPanelRect.x + 16, treeY, rightPanelRect.width - 32, rightPanelRect.height - (treeY - rightPanelRect.y) - 16}
			clickedIdx, toggledIdx := GuiTreeView(treeRect, state.treeItems[:], &state.selectedTreeId, &state.treeScroll, itemHeight = 22)
			_ = toggledIdx
			if clickedIdx >= 0 && clickedIdx < len(state.treeItems) {
				for i in 0..<len(state.treeItems) {
					state.treeItems[i].isSelected = (i == clickedIdx)
				}
				state.selectedTreeId = state.treeItems[clickedIdx].id
			}
		}

		// --------------------------------------------------------------------
		// TAB 2: Visualizers & Plots
		// --------------------------------------------------------------------
		if state.activeTab == 2 {
			halfW := (contentArea.width - 20) * 0.5

			// Left Panel: Color Picker & Gradient Editor
			leftPanelRect := rl.Rectangle{contentArea.x, contentArea.y, halfW, contentArea.height}
			RenderContainerPanel(
				leftPanelRect,
				"Color Palette & Multi-Stop Gradient Editor",
				true, true, true, 34,
				rl.Color{22, 25, 33, 240},
				rl.Color{28, 33, 44, 255},
				rl.Color{50, 56, 74, 255},
				rl.Color{230, 235, 245, 255},
			)

			cpY := leftPanelRect.y + 48
			DrawTextStr("HSV COLOR WHEEL & PICKER", leftPanelRect.x + 16, cpY, 11, rl.Color{130, 140, 165, 255})
			cpY += 18

			pickerRect := rl.Rectangle{leftPanelRect.x + 16, cpY, leftPanelRect.width - 150, 130}
			_ = GuiColorPicker(pickerRect, "Tint Color", &state.pickerColor)

			// Color Preview Swatch
			swatchRect := rl.Rectangle{leftPanelRect.x + leftPanelRect.width - 110, cpY, 94, 80}
			rl.DrawRectangleRec(swatchRect, state.pickerColor)
			rl.DrawRectangleLinesEx(swatchRect, 2, rl.Color{220, 225, 240, 255})
			rgbaText := fmt.tprintf("R: %d\nG: %d\nB: %d\nA: %d", state.pickerColor.r, state.pickerColor.g, state.pickerColor.b, state.pickerColor.a)
			DrawTextStr(rgbaText, swatchRect.x, swatchRect.y + 90, 11, rl.Color{160, 170, 190, 255})

			alphaY := pickerRect.y + pickerRect.height + 16
			DrawTextStr("OPACITY / ALPHA CHANNEL", leftPanelRect.x + 16, alphaY, 11, rl.Color{130, 140, 165, 255})
			alphaY += 18
			_ = GuiColorBarAlpha(rl.Rectangle{leftPanelRect.x + 16, alphaY, leftPanelRect.width - 32, 20}, "Alpha", &state.alphaVal, idKey = 3005)

			// Gradient Editor
			gradY := alphaY + 32
			DrawTextStr("COLOR RAMP GRADIENT EDITOR", leftPanelRect.x + 16, gradY, 11, rl.Color{130, 140, 165, 255})
			gradY += 18

			gradRect := rl.Rectangle{leftPanelRect.x + 16, gradY, leftPanelRect.width - 32, 120}
			_ = GuiGradientEditor(gradRect, &state.gradientStops, &state.selectedGradientStop, &state.draggingGradientStop, true)

			// Gradient Live Preview Bar
			prevY := gradRect.y + gradRect.height + 14
			DrawTextStr("INTERPOLATED COLOR RAMP OUTPUT", leftPanelRect.x + 16, prevY, 11, rl.Color{130, 140, 165, 255})
			prevY += 18
			prevRect := rl.Rectangle{leftPanelRect.x + 16, prevY, leftPanelRect.width - 32, 28}
			for px in 0..<i32(prevRect.width) {
				t := f32(px) / prevRect.width
				c := EvaluateGradient(state.gradientStops[:], t)
				rl.DrawLineV({prevRect.x + f32(px), prevRect.y}, {prevRect.x + f32(px), prevRect.y + prevRect.height}, c)
			}
			rl.DrawRectangleLinesEx(prevRect, 1, rl.Color{85, 95, 120, 255})

			// Right Panel: Real-Time Waveform & XY Plot
			rightPanelRect := rl.Rectangle{contentArea.x + halfW + 20, contentArea.y, halfW, contentArea.height}
			RenderContainerPanel(
				rightPanelRect,
				"Real-Time Waveform & Telemetry XY Plot",
				true, true, true, 34,
				rl.Color{22, 25, 33, 240},
				rl.Color{28, 33, 44, 255},
				rl.Color{50, 56, 74, 255},
				rl.Color{230, 235, 245, 255},
			)

			pltY := rightPanelRect.y + 48
			DrawTextStr("DUAL-CHANNEL SENSOR TELEMETRY (LIVE OSCILLOSCOPE)", rightPanelRect.x + 16, pltY, 11, rl.Color{130, 140, 165, 255})
			pltY += 18

			plotRect := rl.Rectangle{rightPanelRect.x + 16, pltY, rightPanelRect.width - 32, rightPanelRect.height - 110}
			GuiXYPlot(plotRect, "Signal Waveform (Ch1: Sine | Ch2: Harmonic)", state.plotPoints1[:], state.plotPoints2[:], {0, 0}, {1, 1}, true)

			statsY := plotRect.y + plotRect.height + 10
			freqText := fmt.tprintf("Sample Rate: 60 Hz  |  Peak-to-Peak: 0.70 V  |  Sine Wave Frequency: 2.50 rad/s")
			DrawTextStr(freqText, rightPanelRect.x + 16, statsY, 11, rl.Color{140, 150, 175, 255})
		}

		// --------------------------------------------------------------------
		// TAB 3: Spatial 2D Grid Demo
		// --------------------------------------------------------------------
		if state.activeTab == 3 {
			gridPanelRect := rl.Rectangle{contentArea.x, contentArea.y, contentArea.width, contentArea.height}
			RenderContainerPanel(
				gridPanelRect,
				"2D Spatial Arrow Navigation Matrix (Press Up / Down / Left / Right)",
				true, true, true, 34,
				rl.Color{22, 25, 33, 240},
				rl.Color{28, 33, 44, 255},
				rl.Color{50, 56, 74, 255},
				rl.Color{230, 235, 245, 255},
			)

			descY := gridPanelRect.y + 46
			DrawTextStr("This 4x3 matrix demonstrates geometric 2D navigation: arrow keys select the closest adjacent cell using orthogonal distance scoring.", gridPanelRect.x + 20, descY, 12, rl.Color{180, 185, 205, 255})

			startX := gridPanelRect.x + 30
			startY := descY + 28
			cols := 4
			rows := 3
			gapX: f32 = 18.0
			gapY: f32 = 18.0
			btnW := (gridPanelRect.width - 60 - gapX * f32(cols - 1)) / f32(cols)
			btnH: f32 = 72.0

			for r in 0..<rows {
				for c in 0..<cols {
					idx := r * cols + c
					cellX := startX + f32(c) * (btnW + gapX)
					cellY := startY + f32(r) * (btnH + gapY)
					cellRect := rl.Rectangle{cellX, cellY, btnW, btnH}
					cellKey := uintptr(4000 + idx)

					label := fmt.tprintf("Node [%d, %d]\nClicks: %d", r, c, state.gridClickCounts[idx])
					isCurFocused := ImmediateNav_IsFocused(cellKey)

					if GuiButton(cellRect, strings.clone_to_cstring(label, context.temp_allocator), .Center, isSelected = isCurFocused, idKey = cellKey) {
						state.gridClickCounts[idx] += 1
						state.lastNavEvent = fmt.tprintf("Activated Node [%d, %d]! Total triggers: %d", r, c, state.gridClickCounts[idx])
					}
				}
			}

			// Info card at bottom
			infoY := startY + f32(rows) * (btnH + gapY) + 20
			infoRect := rl.Rectangle{startX, infoY, gridPanelRect.width - 60, 68}
			rl.DrawRectangleRec(infoRect, rl.Color{28, 33, 46, 220})
			rl.DrawRectangleLinesEx(infoRect, 1, rl.Color{55, 65, 90, 255})

			DrawTextStr("LAST NAVIGATION EVENT:", infoRect.x + 14, infoRect.y + 10, 11, rl.Color{120, 130, 155, 255})
			DrawTextStr(state.lastNavEvent, infoRect.x + 14, infoRect.y + 26, 14, rl.Color{52, 211, 153, 255})
			curKeyStr := fmt.tprintf("Active Key: 0x%X  |  Geometric Direction: Closest candidate via 2D bounding boxes", immediateNav.focusedKey)
			DrawTextStr(curKeyStr, infoRect.x + 14, infoRect.y + 46, 11, rl.Color{160, 170, 195, 255})
		}

		// --------------------------------------------------------------------
		// TAB 4: Vertical Tabs Showcase
		// --------------------------------------------------------------------
		if state.activeTab == 4 {
			vTabNames := []string{
				"1. Navigation & Radar",
				"2. Propulsion Dynamics",
				"3. Defense Shields",
				"4. Life Support Systems",
			}

			// Main Container panel
			tabPanelRect := rl.Rectangle{contentArea.x, contentArea.y, contentArea.width, contentArea.height}
			RenderContainerPanel(
				tabPanelRect,
				"Vertical Tab Container & Docking Showcase (Direction: .Vertical)",
				true, true, true, 34,
				rl.Color{22, 25, 33, 240},
				rl.Color{28, 33, 44, 255},
				rl.Color{50, 56, 74, 255},
				rl.Color{230, 235, 245, 255},
			)

			innerArea := rl.Rectangle{tabPanelRect.x + 16, tabPanelRect.y + 48, tabPanelRect.width - 32, tabPanelRect.height - 64}

			// Vertical Tab Bar on the left: tabSize = 220
			vTabWidth: f32 = 220
			vTabChanged, tabBounds, contentBounds := GuiTabBar(
				innerArea,
				vTabNames,
				&state.activeSubTab,
				.Vertical,
				vTabWidth,
				idKey = 50000,
			)
			_ = vTabChanged
			_ = tabBounds

			// Content Area on the right of the vertical tabs
			contentPad := rl.Rectangle{contentBounds.x + 24, contentBounds.y + 16, contentBounds.width - 48, contentBounds.height - 32}

			switch state.activeSubTab {
			case 0:
				// Sub-tab 0: Navigation & Radar
				DrawTextStr("SUB-SYSTEM: LONG-RANGE NAVIGATION & RADAR", contentPad.x, contentPad.y, 14, rl.Color{96, 165, 250, 255})
				DrawTextStr("Vertical tab docking layout allows side-by-side hierarchical navigation with minimal vertical footprint.", contentPad.x, contentPad.y + 24, 12, rl.Color{160, 170, 190, 255})

				subY := contentPad.y + 60
				DrawTextStr("SECTOR WAYPOINTS & CELESTIAL TARGETS", contentPad.x, subY, 11, rl.Color{130, 140, 165, 255})
				subY += 18
				if GuiButton(rl.Rectangle{contentPad.x, subY, 220, 32}, "Lock Target: Alpha Centauri", .Center, isSelected = true, idKey = 50101) {
					state.lastActionMsg = "Target locked on Alpha Centauri."
				}
				if GuiButton(rl.Rectangle{contentPad.x + 236, subY, 200, 32}, "Engage Auto-Pilot", .Center, isSelected = false, idKey = 50102) {
					state.lastActionMsg = "Auto-pilot course plotted."
				}
				subY += 52
				GuiProgressBar(rl.Rectangle{contentPad.x, subY, 436, 24}, "Radar Transceiver Signal", 88.0, 0.0, 100.0, .Horizontal, true)

			case 1:
				// Sub-tab 1: Propulsion Dynamics
				DrawTextStr("SUB-SYSTEM: PROPULSION & HYPERDRIVE VECTORING", contentPad.x, contentPad.y, 14, rl.Color{52, 211, 153, 255})
				DrawTextStr("Rotary dial knobs with Shift fine adjustment mode inside a vertical tab sub-panel.", contentPad.x, contentPad.y + 24, 12, rl.Color{160, 170, 190, 255})

				subY := contentPad.y + 60
				DrawTextStr("WARP DRIVE THROTTLE & MANEUVERING", contentPad.x, subY, 11, rl.Color{130, 140, 165, 255})
				subY += 18
				_ = GuiKnob(rl.Rectangle{contentPad.x, subY, 120, 80}, "Warp Factor", &state.warpKnobVal, 1.0, 9.9, 1.0, "%.1f", idKey = 50201)
				_ = GuiKnob(rl.Rectangle{contentPad.x + 140, subY, 120, 80}, "Vector Pitch", &state.vectorKnobVal, -90.0, 90.0, 0.0, "%.0f deg", idKey = 50202)

			case 2:
				// Sub-tab 2: Defense Shields
				DrawTextStr("SUB-SYSTEM: DEFLECTOR SHIELD GENERATOR", contentPad.x, contentPad.y, 14, rl.Color{251, 191, 36, 255})
				DrawTextStr("Shield harmonic balance and frequency modulation.", contentPad.x, contentPad.y + 24, 12, rl.Color{160, 170, 190, 255})

				subY := contentPad.y + 60
				_ = GuiSlider(rl.Rectangle{contentPad.x, subY, 440, 26}, "Shield Harmonic", "GHz", &state.shieldHarmonicVal, 10.0, 100.0, false, idKey = 50301, labelWidth = 120)
				subY += 38
				_ = GuiSlider(rl.Rectangle{contentPad.x, subY, 440, 26}, "Phase Variance", "%", &state.phaseVarianceVal, 0.0, 100.0, false, idKey = 50302, labelWidth = 120)

			case 3:
				// Sub-tab 3: Life Support Diagnostics
				DrawTextStr("SUB-SYSTEM: ENVIRONMENTAL & LIFE SUPPORT", contentPad.x, contentPad.y, 14, rl.Color{248, 113, 113, 255})
				DrawTextStr("Atmospheric pressure, oxygen recycling, and gravity generator telemetry.", contentPad.x, contentPad.y + 24, 12, rl.Color{160, 170, 190, 255})

				subY := contentPad.y + 60
				GuiProgressBar(rl.Rectangle{contentPad.x, subY, 440, 24}, "O2 Saturation", 99.2, 0.0, 100.0, .Horizontal, true)
				subY += 36
				GuiProgressBar(rl.Rectangle{contentPad.x, subY, 440, 24}, "Cabin Pressure", 101.3, 0.0, 120.0, .Horizontal, true)
				subY += 36
				GuiProgressBar(rl.Rectangle{contentPad.x, subY, 440, 24}, "Artificial Gravity (1.00 G)", 100.0, 0.0, 100.0, .Horizontal, true)
			}
		}

		// --------------------------------------------------------------------
		// TAB 5: Audio Faders, Volume Meters & Notched Detents
		// --------------------------------------------------------------------
		if state.activeTab == 5 {
			halfW := (contentArea.width - 20) * 0.5

			// Left Panel: Studio Audio Console & Dual-Ladder VU Meters
			leftPanelRect := rl.Rectangle{contentArea.x, contentArea.y, halfW, contentArea.height}
			RenderContainerPanel(
				leftPanelRect,
				"Studio Audio Console & Dual-Ladder VU Meters",
				true, true, true, 34,
				rl.Color{22, 25, 33, 240},
				rl.Color{28, 33, 44, 255},
				rl.Color{50, 56, 74, 255},
				rl.Color{230, 235, 245, 255},
			)

			faderAreaY := leftPanelRect.y + 48
			DrawTextStr("MULTI-CHANNEL STUDIO FADERS & PEAK-HOLD VU METER", leftPanelRect.x + 16, faderAreaY, 11, rl.Color{130, 140, 165, 255})

			// 3 Faders + 1 Stereo Meter
			faderH: f32 = 360.0
			faderY := faderAreaY + 22

			// Channel 1: Synth Lead
			fader1Rect := rl.Rectangle{leftPanelRect.x + 28, faderY, 96, faderH}
			_ = GuiVolumeFader(fader1Rect, "CH 1 SYNTH", &state.faderValCh1, -60.0, 6.0, 0.0, idKey = 60101)

			// Channel 2: SFX Foley
			fader2Rect := rl.Rectangle{leftPanelRect.x + 148, faderY, 96, faderH}
			_ = GuiVolumeFader(fader2Rect, "CH 2 SFX", &state.faderValCh2, -60.0, 6.0, 0.0, idKey = 60102)

			// Master Fader
			fader3Rect := rl.Rectangle{leftPanelRect.x + 268, faderY, 104, faderH}
			_ = GuiVolumeFader(fader3Rect, "MASTER BUS", &state.faderValMaster, -60.0, 6.0, 0.0, idKey = 60103)

			// Stereo Output VU Meter
			meterRect := rl.Rectangle{leftPanelRect.x + 398, faderY, 148, faderH}
			_ = GuiVolumeMeter(meterRect, "STEREO VU / PEAK", state.meterAudioLevelL, state.meterAudioLevelR, &state.meterStateMaster, .Vertical, -60.0, 3.0)

			// Console Status Info Card
			cardY := faderY + faderH + 18
			cardRect := rl.Rectangle{leftPanelRect.x + 16, cardY, leftPanelRect.width - 32, leftPanelRect.height - (cardY - leftPanelRect.y) - 16}
			rl.DrawRectangleRec(cardRect, rl.Color{28, 33, 44, 220})
			rl.DrawRectangleLinesEx(cardRect, 1, rl.Color{55, 65, 88, 255})

			masterDbStr := fmt.tprintf("Master Gain: %+.1f dB (Unity: 0.0 dB) | Norm: %.2f", state.faderValMaster, FaderDbToNorm(state.faderValMaster, -60.0, 6.0))
			DrawTextStr(masterDbStr, cardRect.x + 14, cardRect.y + 12, 12, rl.Color{96, 165, 250, 255})

			meterPeakStr := fmt.tprintf("Peak Hold L: %+.1f dB  |  Peak Hold R: %+.1f dB  |  Clip LEDs: %s",
				FaderNormToDb(state.meterStateMaster.peakL, -60.0, 3.0),
				FaderNormToDb(state.meterStateMaster.peakR, -60.0, 3.0),
				"TRIGGERED" if (state.meterStateMaster.clipL || state.meterStateMaster.clipR) else "NORMAL")
			DrawTextStr(meterPeakStr, cardRect.x + 14, cardRect.y + 36, 11, rl.Color{52, 211, 153, 255})

			DrawTextStr("Features: 0dB Unity gain notch, Shift micro-dB fine drag, double-click / right-click reset.", cardRect.x + 14, cardRect.y + 60, 11, rl.Color{200, 205, 225, 255})
			DrawTextStr("Navigation: Up/Down (0.5 dB), PgUp/PgDn (3.0 dB), Home (+6 dB), End (-inf cutoff).", cardRect.x + 14, cardRect.y + 80, 11, rl.Color{251, 191, 36, 255})

			// Right Panel: Notched Detent Sliders & Horizontal VU Meters
			rightPanelRect := rl.Rectangle{contentArea.x + halfW + 20, contentArea.y, halfW, contentArea.height}
			RenderContainerPanel(
				rightPanelRect,
				"Notched Detent Sliders & Horizontal VU Meters",
				true, true, true, 34,
				rl.Color{22, 25, 33, 240},
				rl.Color{28, 33, 44, 255},
				rl.Color{50, 56, 74, 255},
				rl.Color{230, 235, 245, 255},
			)

			detentY := rightPanelRect.y + 48
			DrawTextStr("HORIZONTAL NOTCHED SLIDERS (DISCRETE DETENTS WITH SNAPPING)", rightPanelRect.x + 16, detentY, 11, rl.Color{130, 140, 165, 255})

			// Slider 1: Simulation Speed Detents
			notchLabels1 := []string{"0.25x", "0.5x", "1.0x", "2.0x", "4.0x"}
			slider1Rect := rl.Rectangle{rightPanelRect.x + 16, detentY + 22, rightPanelRect.width - 32, 46}
			_ = GuiNotchedSlider(slider1Rect, "Simulation Time Warp Scale", &state.horizNotchVal1, 0.0, 4.0, 5, notchLabels1, snapToNotches = true, orientation = .Horizontal, idKey = 60201)

			// Slider 2: Engine Thrust Stages (7 notches)
			thrustY := slider1Rect.y + slider1Rect.height + 24
			notchLabels2 := []string{"OFF", "IDLE", "CRUISE", "COMBAT", "AFTERBURN", "OVERDRIVE", "MAX"}
			slider2Rect := rl.Rectangle{rightPanelRect.x + 16, thrustY, rightPanelRect.width - 32, 46}
			_ = GuiNotchedSlider(slider2Rect, "Propulsion Detent Stages", &state.horizNotchVal2, 0.0, 6.0, 7, notchLabels2, snapToNotches = true, orientation = .Horizontal, idKey = 60202)

			// Horizontal Volume Meter
			horizMeterY := slider2Rect.y + slider2Rect.height + 26
			DrawTextStr("HORIZONTAL VOLUME METER (MONO CONSOLE MONITOR)", rightPanelRect.x + 16, horizMeterY, 11, rl.Color{130, 140, 165, 255})
			horizMeterRect := rl.Rectangle{rightPanelRect.x + 16, horizMeterY + 20, rightPanelRect.width - 32, 44}
			_ = GuiVolumeMeter(horizMeterRect, "BUS MONITOR (MONO)", state.meterAudioLevelL, -120.0, nil, .Horizontal, -60.0, 3.0)

			// Vertical Notched Slider & Relays Side-by-Side
			vSecY := horizMeterRect.y + horizMeterRect.height + 26
			DrawTextStr("VERTICAL DETENT SLIDER & RELAY SPECIFICATIONS", rightPanelRect.x + 16, vSecY, 11, rl.Color{130, 140, 165, 255})

			vSliderY := vSecY + 20
			vSliderH := rightPanelRect.height - (vSliderY - rightPanelRect.y) - 16

			// Vertical Notched Slider
			notchLabelsV := []string{"AUX 1", "AUX 2", "AUX 3", "MAIN"}
			vertSliderRect := rl.Rectangle{rightPanelRect.x + 24, vSliderY, 110, vSliderH}
			_ = GuiNotchedSlider(vertSliderRect, "Relay Tap", &state.vertNotchVal, 0.0, 3.0, 4, notchLabelsV, snapToNotches = true, orientation = .Vertical, idKey = 60203)

			// Spec Card beside vertical slider
			specCardRect := rl.Rectangle{rightPanelRect.x + 150, vSliderY, rightPanelRect.width - 166, vSliderH}
			rl.DrawRectangleRec(specCardRect, rl.Color{28, 33, 44, 220})
			rl.DrawRectangleLinesEx(specCardRect, 1, rl.Color{55, 65, 88, 255})

			DrawTextStr("DETENT & SNAPPING ARCHITECTURE", specCardRect.x + 14, specCardRect.y + 14, 12, rl.Color{96, 165, 250, 255})

			curNotchIdx1 := int(math.round(state.horizNotchVal1))
			timeScaleStr := notchLabels1[clamp(curNotchIdx1, 0, len(notchLabels1)-1)]
			curNotchIdx2 := int(math.round(state.horizNotchVal2))
			thrustStr := notchLabels2[clamp(curNotchIdx2, 0, len(notchLabels2)-1)]
			curNotchIdxV := int(math.round(state.vertNotchVal))
			relayStr := notchLabelsV[clamp(curNotchIdxV, 0, len(notchLabelsV)-1)]

			DrawTextStr(fmt.tprintf("Active Time Detent:    %s (Index %d)", timeScaleStr, curNotchIdx1), specCardRect.x + 14, specCardRect.y + 38, 11, rl.Color{52, 211, 153, 255})
			DrawTextStr(fmt.tprintf("Active Thrust Detent:  %s (Stage %d)", thrustStr, curNotchIdx2), specCardRect.x + 14, specCardRect.y + 58, 11, rl.Color{251, 191, 36, 255})
			DrawTextStr(fmt.tprintf("Selected Power Relay:  %s (Tap #%d)", relayStr, curNotchIdxV), specCardRect.x + 14, specCardRect.y + 78, 11, rl.Color{248, 113, 113, 255})

			DrawTextStr("- Snap To Notches: Automatic magnetic pull to closest detent tick.", specCardRect.x + 14, specCardRect.y + 110, 11, rl.Color{180, 185, 205, 255})
			DrawTextStr("- Continuous Bypass: Hold Shift while dragging or using arrows.", specCardRect.x + 14, specCardRect.y + 130, 11, rl.Color{180, 185, 205, 255})
			DrawTextStr("- Custom Labels: Rendered above ticks with active detent glow.", specCardRect.x + 14, specCardRect.y + 150, 11, rl.Color{180, 185, 205, 255})
		}

		// --------------------------------------------------------------------
		// TAB 6: Window-Resize Invariant Docking System
		// --------------------------------------------------------------------
		if state.activeTab == 6 {
			// 1. Control Toolbar above the DockSpace
			toolbarRect := rl.Rectangle{contentArea.x, contentArea.y, contentArea.width, 50}
			rl.DrawRectangleRec(toolbarRect, rl.Color{24, 28, 38, 240})
			rl.DrawRectangleLinesEx(toolbarRect, 1, rl.Color{45, 52, 70, 255})

			DrawTextStr("DOCKING WORKSPACE", toolbarRect.x + 14, toolbarRect.y + 10, 13, rl.Color{96, 165, 250, 255})
			DrawTextStr("Drag titlebars to float/dock, drag splitters to resize, or use quick buttons", toolbarRect.x + 14, toolbarRect.y + 28, 10, rl.Color{140, 148, 168, 255})

			// Window Resize Simulation Slider (Proves that panels survive dynamic resize!)
			simSliderRect := rl.Rectangle{toolbarRect.x + 440, toolbarRect.y + 12, 280, 26}
			_ = GuiSlider(simSliderRect, "Simulate Width", "%", &state.dockSimWidthRatio, 0.65, 1.00, false, idKey = 70001, labelWidth = 110)

			// Quick preset / docking action buttons
			btnX := simSliderRect.x + simSliderRect.width + 20
			if GuiButton(rl.Rectangle{btnX, toolbarRect.y + 11, 130, 28}, "Reset 4-Pane IDE", .Center, idKey = 70002) {
				DockSpace_SetSlot(&state.dockSpace, "scene", .Left)
				DockSpace_SetSlot(&state.dockSpace, "viewport", .Center)
				DockSpace_SetSlot(&state.dockSpace, "inspector", .Right)
				DockSpace_SetSlot(&state.dockSpace, "console", .Bottom)
				state.dockSpace.leftRatio = 0.24
				state.dockSpace.rightRatio = 0.26
				state.dockSpace.bottomRatio = 0.28
			}

			if GuiButton(rl.Rectangle{btnX + 138, toolbarRect.y + 11, 145, 28}, "Toggle Float Inspector", .Center, idKey = 70003) {
				DockSpace_ToggleFloating(&state.dockSpace, "inspector")
			}

			if GuiButton(rl.Rectangle{btnX + 291, toolbarRect.y + 11, 145, 28}, "Toggle Float Scene", .Center, idKey = 70004) {
				DockSpace_ToggleFloating(&state.dockSpace, "scene")
			}

			// 2. Compute dynamic host bounds (adapts smoothly to slider simulation or real window resize)
			curHostW := contentArea.width * state.dockSimWidthRatio
			dockBounds := rl.Rectangle{
				contentArea.x + (contentArea.width - curHostW) * 0.5,
				contentArea.y + 58,
				curHostW,
				contentArea.height - 62,
			}

			// Visual backdrop border when resized smaller
			if state.dockSimWidthRatio < 0.999 {
				rl.DrawRectangleLinesEx(dockBounds, 1, rl.Color{96, 165, 250, 150})
			}

			// 3. Update DockSpace Layout
			DockSpace_UpdateLayout(&state.dockSpace, dockBounds)

			// 4. Panel: Scene Hierarchy (Left)
			if vis, b := DockSpace_BeginPanel(&state.dockSpace, "scene"); vis {
				_, _ = GuiTextInput(rl.Rectangle{b.x, b.y, b.width, 24}, "Filter", &state.dockSceneFilter, "Search entities...", 50, idKey = 70101)
				nodes := []string{
					"Root Universe",
					"  └ Main Camera [2D]",
					"  └ Cosmic Star Emitter",
					"  └ Interceptor Spacecraft",
					"      └ Port Laser Cannon",
					"      └ Deflector Shield Matrix",
					"  └ Asteroid Belt Hazard",
				}
				for n, idx in nodes {
					nY := b.y + 32 + f32(idx) * 22
					if nY + 20 > b.y + b.height - 32 do break
					isSel := (idx == 3)
					nR := rl.Rectangle{b.x, nY, b.width, 20}
					if isSel {
						rl.DrawRectangleRec(nR, rl.Color{45, 90, 180, 200})
					}
					tCol := rl.WHITE if isSel else rl.Color{190, 200, 220, 255}
					DrawTextStr(n, nR.x + 6, nR.y + 3, 11, tCol)
				}
				if b.height > 160 {
					btnY := b.y + b.height - 28
					_ = GuiButton(rl.Rectangle{b.x, btnY, b.width, 26}, "+ Add Child Node", .Center, idKey = 70102)
				}
				DockSpace_EndPanel(&state.dockSpace)
			}

			// 5. Panel: Interactive 2D Viewport (Center)
			if vis, b := DockSpace_BeginPanel(&state.dockSpace, "viewport"); vis {
				rl.DrawRectangleRec(b, rl.Color{12, 14, 18, 255})

				// Grid lines
				gridStep: f32 = 32.0
				for gx := b.x; gx < b.x + b.width; gx += gridStep {
					rl.DrawLineV({gx, b.y}, {gx, b.y + b.height}, rl.Color{22, 26, 36, 255})
				}
				for gy := b.y; gy < b.y + b.height; gy += gridStep {
					rl.DrawLineV({b.x, gy}, {b.x + b.width, gy}, rl.Color{22, 26, 36, 255})
				}

				midX := b.x + b.width * 0.5
				midY := b.y + b.height * 0.5
				rl.DrawLineV({midX, b.y}, {midX, b.y + b.height}, rl.Color{40, 50, 70, 255})
				rl.DrawLineV({b.x, midY}, {b.x + b.width, midY}, rl.Color{40, 50, 70, 255})

				shipX := b.x + state.dockViewportShipPos.x
				shipY := b.y + state.dockViewportShipPos.y
				p1 := rl.Vector2{shipX, shipY - 14}
				p2 := rl.Vector2{shipX - 11, shipY + 12}
				p3 := rl.Vector2{shipX + 11, shipY + 12}
				rl.DrawTriangle(p1, p2, p3, state.dockInspectorColor)
				rl.DrawTriangleLines(p1, p2, p3, rl.WHITE)
				rl.DrawCircleLines(i32(shipX), i32(shipY), 22, rl.Color{59, 130, 246, 180})
				DrawTextStr("Viper-MK2", shipX - 26, shipY + 18, 10, rl.Color{160, 180, 220, 255})

				hudText := fmt.tprintf("Viewport: %.0fx%.0f | Ship: (%.0f, %.0f) | Ratio: Left=%.2f Right=%.2f Bottom=%.2f",
					b.width, b.height, state.dockViewportShipPos.x, state.dockViewportShipPos.y,
					state.dockSpace.leftRatio, state.dockSpace.rightRatio, state.dockSpace.bottomRatio)
				DrawTextStr(hudText, b.x + 10, b.y + b.height - 20, 11, rl.Color{130, 140, 165, 255})
				DockSpace_EndPanel(&state.dockSpace)
			}

			// 6. Panel: Entity Inspector (Right)
			if vis, b := DockSpace_BeginPanel(&state.dockSpace, "inspector"); vis {
				DrawTextStr("SELECTED: Interceptor Spacecraft", b.x + 4, b.y + 4, 12, rl.Color{96, 165, 250, 255})
				_ = GuiSlider(rl.Rectangle{b.x + 4, b.y + 24, b.width - 8, 24}, "Pos X", "px", &state.dockInspectorPosX, 0.0, 1920.0, true, idKey = 70201, labelWidth = 70)
				_ = GuiSlider(rl.Rectangle{b.x + 4, b.y + 54, b.width - 8, 24}, "Pos Y", "px", &state.dockInspectorPosY, 0.0, 1080.0, true, idKey = 70202, labelWidth = 70)
				_ = GuiSlider(rl.Rectangle{b.x + 4, b.y + 84, b.width - 8, 24}, "Scale", "x", &state.dockInspectorScale, 0.1, 4.0, false, idKey = 70203, labelWidth = 70)

				if b.height > 180 {
					DrawTextStr("Hull Tint Swatch:", b.x + 4, b.y + 118, 11, rl.Color{170, 180, 200, 255})
					rl.DrawRectangleRec(rl.Rectangle{b.x + 110, b.y + 116, 50, 18}, state.dockInspectorColor)
					rl.DrawRectangleLinesEx(rl.Rectangle{b.x + 110, b.y + 116, 50, 18}, 1, rl.WHITE)

					chkY := b.y + 144
					_ = GuiCheckBox(rl.Rectangle{b.x + 4, chkY, b.width - 8, 22}, "Collision Wireframe", &state.wireframeChecked, idKey = 70204)
					_ = GuiCheckBox(rl.Rectangle{b.x + 4, chkY + 24, b.width - 8, 22}, "Planetary Shadow", &state.flightAssistActive, idKey = 70205)
				}
				DockSpace_EndPanel(&state.dockSpace)
			}

			// 7. Panel: Diagnostics Console (Bottom)
			if vis, b := DockSpace_BeginPanel(&state.dockSpace, "console"); vis {
				for logLine, idx in state.dockConsoleLogs {
					lY := b.y + 4 + f32(idx) * 18
					if lY + 16 > b.y + b.height do break
					logCol := rl.Color{52, 211, 153, 255} if idx % 2 == 0 else rl.Color{200, 205, 225, 255}
					DrawTextStr(logLine, b.x + 6, lY, 11, logCol)
				}
				DockSpace_EndPanel(&state.dockSpace)
			}

			// 8. Render interactive splitters & drag-and-drop dock target overlays
			DockSpace_RenderOverlays(&state.dockSpace)
		}

		// --------------------------------------------------------------------
		// TAB 7: HTML-Style Elements (<ul>, <ol>, <table>)
		// --------------------------------------------------------------------
		if state.activeTab == 7 {
			listColW: f32 = 470.0
			tableColW := contentArea.width - listColW - 20.0

			// Left Column: HTML Lists (<ul> and <ol>)
			leftColRect := rl.Rectangle{contentArea.x, contentArea.y, listColW, contentArea.height}
			RenderContainerPanel(
				leftColRect,
				"HTML Lists (<ul> Unordered & <ol> Ordered Lists)",
				true, true, true, 34,
				rl.Color{22, 25, 33, 240},
				rl.Color{28, 33, 44, 255},
				rl.Color{50, 56, 74, 255},
				rl.Color{230, 235, 245, 255},
			)

			// Section 1: Unordered List <ul>
			ulH := (leftColRect.height - 110.0) * 0.5
			ulY := leftColRect.y + 46
			DrawTextStr("UNORDERED LIST (<ul> with Disc / Circle / Dash / Square Bullets)", leftColRect.x + 16, ulY, 11, rl.Color{130, 140, 165, 255})

			ulRect := rl.Rectangle{leftColRect.x + 16, ulY + 18, leftColRect.width - 32, ulH}
			ulChanged, _ := GuiUnorderedList(ulRect, state.htmlUlItems[:], &state.htmlUlSelected, &state.htmlUlScroll, defaultBullet = .Disc, idKey = 80101)
			_ = ulChanged

			// Section 2: Ordered List <ol>
			olY := ulRect.y + ulRect.height + 16
			DrawTextStr("ORDERED LIST (<ol> with 1., 2., 3. & a., b., c. Numbering)", leftColRect.x + 16, olY, 11, rl.Color{130, 140, 165, 255})

			olRect := rl.Rectangle{leftColRect.x + 16, olY + 18, leftColRect.width - 32, ulH}
			olChanged, _ := GuiOrderedList(olRect, state.htmlOlItems[:], &state.htmlOlSelected, &state.htmlOlScroll, numbering = state.htmlOlStyle, idKey = 80102)
			_ = olChanged

			// Right Column: HTML Table <table>
			rightColRect := rl.Rectangle{contentArea.x + listColW + 20.0, contentArea.y, tableColW, contentArea.height}
			RenderContainerPanel(
				rightColRect,
				"HTML Data Table (<table> with <thead>, <tbody>, Sorting & Selection)",
				true, true, true, 34,
				rl.Color{22, 25, 33, 240},
				rl.Color{28, 33, 44, 255},
				rl.Color{50, 56, 74, 255},
				rl.Color{230, 235, 245, 255},
			)

			tblDescY := rightColRect.y + 46
			DrawTextStr("INTERACTIVE DATA TABLE (CLICK HEADERS TO SORT | ARROWS/CLICK TO SELECT)", rightColRect.x + 16, tblDescY, 11, rl.Color{130, 140, 165, 255})

			tblH := rightColRect.height - 180.0
			tableRect := rl.Rectangle{rightColRect.x + 16, tblDescY + 18, rightColRect.width - 32, tblH}

			rClicked, hClicked := GuiTable(
				tableRect,
				state.htmlTableColumns[:],
				state.htmlTableRows[:],
				&state.htmlTableSelectedRow,
				&state.htmlTableSortCol,
				&state.htmlTableSortAsc,
				&state.htmlTableScroll,
				headerHeight = 32.0,
				rowHeight = 28.0,
				idKey = 80201,
			)
			if rClicked >= 0 && rClicked < len(state.htmlTableRows) {
				selVessel := state.htmlTableRows[rClicked].cells[1].text
				state.htmlTableActionMsg = fmt.tprintf("Selected Vessel: %s (Row #%d)", selVessel, rClicked + 1)
			}
			if hClicked >= 0 && hClicked < len(state.htmlTableColumns) {
				hdrTitle := state.htmlTableColumns[hClicked].title
				orderStr := "ASC" if state.htmlTableSortAsc else "DESC"
				state.htmlTableActionMsg = fmt.tprintf("Sorted by Column: [%s] (%s)", hdrTitle, orderStr)
			}

			// Table Selected Row Inspection & Action Card
			cardY := tableRect.y + tableRect.height + 16
			cardH := rightColRect.height - (cardY - rightColRect.y) - 16
			cardRect := rl.Rectangle{rightColRect.x + 16, cardY, rightColRect.width - 32, cardH}
			rl.DrawRectangleRec(cardRect, rl.Color{28, 33, 44, 220})
			rl.DrawRectangleLinesEx(cardRect, 1, rl.Color{55, 65, 88, 255})

			selIdx := state.htmlTableSelectedRow
		if selIdx >= 0 && selIdx < len(state.htmlTableRows) {
			row := state.htmlTableRows[selIdx]
			vId := row.cells[0].text
			vName := row.cells[1].text
			vClass := row.cells[2].text
			vHull := row.cells[3].text
			vShield := row.cells[4].text
			vStatus := row.cells[5].badge

			detailStr := fmt.tprintf("VESSEL TELEMETRY: %s (%s)  |  Class: %s  |  Hull: %s  |  Shields: %s  |  Status: %s",
				vName, vId, vClass, vHull, vShield, vStatus)
			DrawTextStr(detailStr, cardRect.x + 14, cardRect.y + 12, 12, rl.Color{96, 165, 250, 255})
		}

			DrawTextStr(state.htmlTableActionMsg, cardRect.x + 14, cardRect.y + 34, 11, rl.Color{52, 211, 153, 255})

			// Action buttons inside table card
			if GuiButton(rl.Rectangle{cardRect.x + 14, cardRect.y + 54, 140, 26}, "Repair Vessel", .Center, idKey = 80301) {
				state.htmlTableActionMsg = "Repair Nanites deployed to vessel!"
			}
			if GuiButton(rl.Rectangle{cardRect.x + 162, cardRect.y + 54, 150, 26}, "Recharge Shields", .Center, idKey = 80302) {
				state.htmlTableActionMsg = "Shield harmonic pulse initiated."
			}
			if GuiButton(rl.Rectangle{cardRect.x + 320, cardRect.y + 54, 130, 26}, "Scan Telemetry", .Center, idKey = 80303) {
				state.htmlTableActionMsg = "Deep subspace telemetry scan complete."
			}
		}

		// --------------------------------------------------------------------
		// 3. Process Immediate Navigation Inputs for Next Frame
		// --------------------------------------------------------------------
		ImmediateNav_Update()

		// --------------------------------------------------------------------
		// 4. Render Active Dropdown Overlay on Top of Everything
		// --------------------------------------------------------------------
		RenderImmediateDropdownOverlay()

		rl.EndDrawing()

		// --------------------------------------------------------------------
		// 5. Automated Event Injection & Screenshot Verification Suite
		// --------------------------------------------------------------------
		if state.isTestMode {
			TestHook_ResetInput()
			state.testFrame += 1
			f := state.testFrame

			switch f {
			case 1:
				TestHook_Assert(state.activeTab == 0, "Initial active tab is 0 (Controls)")

			case 2:
				// Inject click on Primary Button \"Launch Rocket\" at (129, 194)
				TestHook_MouseClick(129, 194)

			case 3:
				TestHook_MouseRelease(129, 194)
				TestHook_Assert(state.buttonClickCount == 1, "Primary button click increments count to 1")

			case 5:
				// Inject click on VSync checkbox at (50, 313)
				TestHook_MouseClick(45, 287)

			case 6:
				TestHook_MouseRelease(45, 287)
				TestHook_Assert(state.vsyncChecked == false, "VSync checkbox toggled to false")

			case 8:
				// Inject click on Toggle Switch \"Flight Computer\" at (500, 497)
				TestHook_MouseClick(100, 441)

			case 9:
				TestHook_MouseRelease(100, 441)
				TestHook_Assert(state.flightAssistActive == false, "Flight assist toggle switch toggled to false")

			case 10:
				TestHook_Assert(string(state.callsignBuffer[:]) == "VIPER-7", "Callsign buffer initialized to VIPER-7")

			case 11:
				// Inject click on "Transmit Callsign" button at (121, 610)
				TestHook_MouseClick(121, 610)

			case 12:
				TestHook_MouseRelease(121, 610)
				TestHook_Assert(strings.contains(state.lastActionMsg, "transmitted"), "Callsign transmitted successfully")

			case 14:
				// Focus coarse slider via ImmediateNav_SetFocus
				ImmediateNav_SetFocus(1030)
				TestHook_Assert(ImmediateNav_IsFocused(1030), "Coarse slider focused")

			case 15:
				// Inject Right arrow key to increment slider
				TestHook_KeyPress(.RIGHT)

			case 16:
				TestHook_Assert(state.coarseSliderVal > 65.0, "Right arrow key increments slider value")
				TestHook_CaptureScreenshot("01_controls_and_buttons.png")

			case 18:
				// Switch to Tab 1 (Lists & Trees) via mouse click on TabBar at (330, 100)
				TestHook_MouseClick(252, 100)

			case 19:
				TestHook_MouseRelease(252, 100)
				TestHook_Assert(state.activeTab == 1, "Switched to Tab 1 (Lists & Trees)")

			case 21:
				// Click Dropdown \"Render Quality Preset\" at (300, 203) to open popup
				TestHook_MouseClick(300, 203)

			case 22:
				TestHook_MouseRelease(300, 203)
				TestHook_Assert(immediateDropdown.active == true, "Dropdown popup opened")

			case 24:
				TestHook_CaptureScreenshot("02_dropdown_opened.png")

			case 26:
				// Press Down arrow to navigate dropdown item
				TestHook_KeyPress(.DOWN)

			case 27:
				// Press Enter to confirm selection
				TestHook_KeyPress(.ENTER)

			case 28:
				TestHook_Assert(immediateDropdown.active == false, "Dropdown popup closed after selection")

			case 30:
				// Click List View item 3 (\"Hull Repair Nanites\") at (750, 278)
				TestHook_MouseClick(750, 278)

			case 31:
				TestHook_MouseRelease(750, 278)
				TestHook_Assert(state.selectedListItem == 3, "List View item 3 selected")

			case 33:
				// Click Tree View collapse arrow on node 3 at (690, 434)
				TestHook_MouseClick(691, 437)

			case 34:
				TestHook_MouseRelease(691, 437)
				TestHook_Assert(state.treeItems[2].isCollapsed == true, "Tree node 3 collapsed")
				TestHook_CaptureScreenshot("03_lists_and_trees.png")

			case 37:
				// Switch to Tab 2 (Visualizers & Plots) at (536, 100)
				TestHook_MouseClick(408, 100)

			case 38:
				TestHook_MouseRelease(408, 100)
				TestHook_Assert(state.activeTab == 2, "Switched to Tab 2 (Visualizers & Plots)")

			case 40:
				// Drag Color Picker SV Box
				TestHook_MouseClick(120, 240)

			case 41:
				TestHook_MouseMove(160, 220)

			case 42:
				TestHook_MouseRelease(160, 220)

			case 44:
				// Click Gradient Stop 1 marker at (238, 545)
				TestHook_MouseClick(238, 517)

			case 45:
				TestHook_MouseRelease(238, 517)
				TestHook_Assert(state.selectedGradientStop == 1, "Gradient Stop 1 marker selected")
				TestHook_CaptureScreenshot("04_visualizers_and_plots.png")

			case 48:
				// Switch to Tab 3 (2D Spatial Grid) at (743, 100)
				TestHook_MouseClick(562, 100)

			case 49:
				TestHook_MouseRelease(562, 100)
				TestHook_Assert(state.activeTab == 3, "Switched to Tab 3 (Spatial 2D Grid)")

			case 51:
				// Focus top-left node [0, 0] (key = 4000)
				ImmediateNav_SetFocus(4000)
				TestHook_Assert(ImmediateNav_IsFocused(4000), "Node [0, 0] focused")

			case 53:
				// Inject spatial navigation: Right arrow -> moves to Node [0, 1] (4001)
				TestHook_NavAction(.Right)

			case 54:
				TestHook_Assert(ImmediateNav_IsFocused(4001), "Spatial arrow Right moved focus to Node [0, 1]")

			case 56:
				// Inject spatial navigation: Down arrow -> moves to Node [1, 1] (4005)
				TestHook_NavAction(.Down)

			case 57:
				TestHook_Assert(ImmediateNav_IsFocused(4005), "Spatial arrow Down moved focus to Node [1, 1]")

			case 59:
				// Inject spatial navigation: Right arrow -> moves to Node [1, 2] (4006)
				TestHook_NavAction(.Right)

			case 60:
				TestHook_Assert(ImmediateNav_IsFocused(4006), "Spatial arrow Right moved focus to Node [1, 2]")

			case 62:
				// Inject Enter key to activate Node [1, 2]
				TestHook_KeyPress(.ENTER)

			case 63:
				TestHook_Assert(state.gridClickCounts[6] == 1, "Enter key activated focused Node [1, 2]")
				TestHook_CaptureScreenshot("05_spatial_2d_navigation_grid.png")

			case 66:
				// Switch to Tab 4 (Vertical Tabs) at (950, 100)
				TestHook_MouseClick(718, 100)

			case 67:
				TestHook_MouseRelease(718, 100)
				TestHook_Assert(state.activeTab == 4, "Switched to Tab 4 (Vertical Tabs Showcase)")

			case 69:
				// Click on second vertical tab "Propulsion Dynamics" at (80, 220)
				TestHook_MouseClick(80, 220)

			case 70:
				TestHook_MouseRelease(80, 220)
				TestHook_Assert(state.activeSubTab == 1, "Switched vertical sub-tab to 1 (Propulsion Dynamics)")

			case 72:
				// Focus Warp knob in vertical tab sub-panel and inject Shift+Right arrow for fine adjustment
				ImmediateNav_SetFocus(50201)
				TestHook_Assert(ImmediateNav_IsFocused(50201), "Warp knob focused in vertical tab container")
				TestHook_KeyPress(.RIGHT, shift = true)

			case 73:
				TestHook_Assert(state.warpKnobVal > 4.5, "Knob fine adjustment incremented warp factor")
				TestHook_KeyDown(.LEFT_SHIFT)

			case 74:
				TestHook_CaptureScreenshot("06_vertical_tab_container.png")
				TestHook_KeyUp(.LEFT_SHIFT)

			case 76:
				// Switch to Tab 5 (Audio Faders & Notched Sliders) at (1156, 100)
				TestHook_MouseClick(872, 100)

			case 77:
				TestHook_MouseRelease(872, 100)
				TestHook_Assert(state.activeTab == 5, "Switched to Tab 5 (Audio Faders & Notched Sliders)")

			case 79:
				// Focus Master Fader (60103)
				ImmediateNav_SetFocus(60103)
				TestHook_Assert(ImmediateNav_IsFocused(60103), "Master fader focused")

			case 80:
				// Press Up arrow to increment fader dB
				TestHook_KeyPress(.UP)

			case 81:
				TestHook_Assert(state.faderValMaster > 0.0, "Master fader Up arrow increments dB above Unity")

			case 83:
				// Focus Simulation Time Warp notched slider (60201)
				ImmediateNav_SetFocus(60201)
				TestHook_Assert(ImmediateNav_IsFocused(60201), "Notched slider focused")

			case 84:
				// Press Right arrow to step to next detent
				TestHook_KeyPress(.RIGHT)

			case 85:
				TestHook_Assert(state.horizNotchVal1 == 3.0, "Notched slider stepped to next detent (3.0)")
				TestHook_CaptureScreenshot("07_audio_faders_and_notched_sliders.png")

			case 87:
				// Switch to Tab 6 (Docking System) at (1171, 100)
				TestHook_MouseClick(1028, 100)

			case 88:
				TestHook_MouseRelease(1028, 100)
				TestHook_Assert(state.activeTab == 6, "Switched to Tab 6 (Docking System)")

			case 90:
				// Test undocking Inspector panel to floating window
				DockSpace_ToggleFloating(&state.dockSpace, "inspector")

			case 91:
				inspPanel := DockSpace_FindPanel(&state.dockSpace, "inspector")
				TestHook_Assert(inspPanel != nil && inspPanel.slot == .Floating, "Inspector panel undocked to Floating window")

			case 93:
				// Test docking Inspector to Left slot (where Scene is already docked)
				DockSpace_SetSlot(&state.dockSpace, "inspector", .Left)

			case 94:
				inspPanel2 := DockSpace_FindPanel(&state.dockSpace, "inspector")
				scenePanel2 := DockSpace_FindPanel(&state.dockSpace, "scene")
				TestHook_Assert(inspPanel2 != nil && inspPanel2.slot == .Left, "Inspector panel docked to Left slot")
				TestHook_Assert(scenePanel2 != nil && scenePanel2.slot != .Left, "Existing Scene panel moved out of Left slot to avoid overlap")
				TestHook_Assert(scenePanel2 != nil && scenePanel2.slot == .Right, "Existing Scene panel moved to Right slot (swapped)")

			case 95:
				// Test swapping back: dock Scene to Left slot (where Inspector is now docked)
				DockSpace_SetSlot(&state.dockSpace, "scene", .Left)

			case 96:
				inspPanel3 := DockSpace_FindPanel(&state.dockSpace, "inspector")
				scenePanel3 := DockSpace_FindPanel(&state.dockSpace, "scene")
				TestHook_Assert(scenePanel3 != nil && scenePanel3.slot == .Left, "Scene panel docked to Left slot")
				TestHook_Assert(inspPanel3 != nil && inspPanel3.slot == .Right, "Inspector panel moved to Right slot (swapped)")

			case 97:
				// Test window resize survival: change simulated width ratio to 0.85
				state.dockSimWidthRatio = 0.85

			case 98:
				TestHook_Assert(state.dockSpace.hostBounds.width > 0, "Docking host bounds adapted to resized width")
				TestHook_CaptureScreenshot("08_docking_system.png")

			case 100:
				// Switch to Tab 7 (HTML Lists & Tables) at (1182, 100)
				TestHook_MouseClick(1182, 100)

			case 101:
				TestHook_MouseRelease(1182, 100)
				TestHook_Assert(state.activeTab == 7, "Switched to Tab 7 (HTML Lists & Tables)")

			case 103:
				// Click on Unordered List <ul> item 2 at (150, 246)
				TestHook_MouseClick(150, 246)

			case 104:
				TestHook_MouseRelease(150, 246)
				TestHook_Assert(state.htmlUlSelected == 2, "Unordered list <ul> item 2 selected")

			case 106:
				// Click on HTML Table row 1 ("Dreadnought-X") at (700, 248)
				TestHook_MouseClick(700, 266)

			case 107:
				TestHook_MouseRelease(700, 266)
				TestHook_Assert(state.htmlTableSelectedRow == 1, "HTML Table row 1 selected")

			case 109:
				// Click on Table header column 1 ("Entity Vessel") at (600, 208) to test sorting
				TestHook_MouseClick(600, 208)

			case 110:
				TestHook_MouseRelease(600, 208)
				TestHook_Assert(state.htmlTableSortCol == 1, "HTML Table column 1 sorted")
				TestHook_CaptureScreenshot("09_html_lists_and_tables.png")

			case 112:
				fmt.println("=================================================================")
				fmt.printf("[UI TEST HOOK SUMMARY] Total Checks: %d | Passed: %d | Failed: %d\n",
					testHook.checksPassed + testHook.checksFailed, testHook.checksPassed, testHook.checksFailed)
				fmt.println("=================================================================")
				if testHook.checksFailed > 0 {
					os.exit(1)
				} else {
					break main_loop
				}
			}
		}
	}
}
