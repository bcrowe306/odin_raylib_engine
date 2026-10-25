package main

import "core:fmt"
import "core:os"
import rl "vendor:raylib"
import ui "../.."

// ============================================================================
// Simple Targeted Example: Settings & Preferences Dialog
// Demonstrates:
//   - Theme switching (Dark, Light, Cyberpunk) with unified rounded corners & metrics
//   - Automatic cursor handling (Pointing hand on buttons, I-beam on inputs, etc.)
//   - Fixed pixel-accurate slider dragging and value display
//   - Text input, dropdown box, checkboxes, toggle switches, and radio groups
//   - Crisp typography and font loading
// ============================================================================

SettingsState :: struct {
	// Theme: 0 = Dark, 1 = Light, 2 = Cyberpunk
	currentThemeIdx: int,

	// Audio Settings
	masterVolume: f32,
	musicVolume:  f32,
	sfxMute:      bool,

	// Graphics Settings
	qualityIdx:       i32,
	fullscreenActive: bool,
	vsyncActive:      bool,

	// Profile Settings
	callsignBuffer:   [dynamic]u8,
	difficultyIdx:    int,

	// Feedback status
	statusMessage:    string,
	statusTimer:      f32,
}

InitSettingsState :: proc(state: ^SettingsState) {
	state.currentThemeIdx = 0
	ui.SetTheme(ui.Theme_Dark())

	state.masterVolume = 85.0
	state.musicVolume = 60.0
	state.sfxMute = false

	state.qualityIdx = 2 // "High"
	state.fullscreenActive = false
	state.vsyncActive = true

	state.callsignBuffer = make([dynamic]u8)
	defaultName := "AstroPilot-01"
	for b in transmute([]u8)defaultName {
		append(&state.callsignBuffer, b)
	}

	state.difficultyIdx = 1 // "Standard"
	state.statusMessage = "Settings loaded. Ready."
	state.statusTimer = 3.0
}

DestroySettingsState :: proc(state: ^SettingsState) {
	delete(state.callsignBuffer)
}

main :: proc() {
	// Check for headless/test flag for automated test suites
	isTestMode := false
	for arg in os.args[1:] {
		if arg == "--test" || arg == "--headless" || arg == "-t" {
			isTestMode = true
		}
	}

	windowWidth: i32 = 860
	windowHeight: i32 = 680

	if isTestMode {
		rl.SetConfigFlags({.WINDOW_HIDDEN})
	} else {
		rl.SetConfigFlags({.WINDOW_RESIZABLE})
	}

	rl.InitWindow(windowWidth, windowHeight, "UI Example - Settings Dialog")
	defer rl.CloseWindow()

	rl.SetTargetFPS(60)

	// Initialize UI fonts (searches local paths)
	ui.InitFonts()

	state: SettingsState
	InitSettingsState(&state)
	defer DestroySettingsState(&state)

	diffOptions := [3]string{"Casual", "Standard", "Hardcore"}

	frameCount := 0

	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()
		frameCount += 1

		// In test mode, exit cleanly after 10 frames
		if isTestMode && frameCount >= 10 {
			break
		}

		if state.statusTimer > 0.0 {
			state.statusTimer -= dt
		}

		// 1. Begin UI frame for navigation and cursor tracking
		ui.ImmediateNav_BeginFrame()

		theme := ui.GetTheme()

		// 2. Render UI
		rl.BeginDrawing()
		rl.ClearBackground(theme.bgApp)

		// Top Header Bar
		headerRect := rl.Rectangle{20, 16, f32(rl.GetScreenWidth() - 40), 54}
		ui.DrawThemeRect(headerRect, theme.bgHeader, theme.borderNormal, theme.borderRadius, 1.0)

		// Header Title & Icon
		ui.GuiIcon(rl.Rectangle{headerRect.x + 14, headerRect.y + 16, 22, 22}, .Gear, 20, theme.accent)
		ui.DrawTextStr("System Preferences & Audio Settings", headerRect.x + 46, headerRect.y + 18, 18, theme.textPrimary)

		// Theme Switching Buttons on Right of Header
		themeDarkBtn := rl.Rectangle{headerRect.x + headerRect.width - 250, headerRect.y + 12, 70, 30}
		themeLightBtn := rl.Rectangle{headerRect.x + headerRect.width - 172, headerRect.y + 12, 74, 30}
		themeCyberBtn := rl.Rectangle{headerRect.x + headerRect.width - 90, headerRect.y + 12, 80, 30}

		if ui.GuiButton(themeDarkBtn, "Dark", .Center, idKey = 101) {
			state.currentThemeIdx = 0
			ui.SetTheme(ui.Theme_Dark())
			state.statusMessage = "Switched to Dark Theme"
			state.statusTimer = 2.0
		}
		if ui.GuiButton(themeLightBtn, "Light", .Center, idKey = 102) {
			state.currentThemeIdx = 1
			ui.SetTheme(ui.Theme_Light())
			state.statusMessage = "Switched to Light Theme"
			state.statusTimer = 2.0
		}
		if ui.GuiButton(themeCyberBtn, "Cyberpunk", .Center, idKey = 103) {
			state.currentThemeIdx = 2
			ui.SetTheme(ui.Theme_Cyberpunk())
			state.statusMessage = "Switched to Cyberpunk Theme"
			state.statusTimer = 2.0
		}

		// Main Card Panel
		panelRect := rl.Rectangle{20, 84, f32(rl.GetScreenWidth() - 40), f32(rl.GetScreenHeight() - 150)}
		ui.DrawThemeRect(panelRect, theme.bgPanel, theme.borderNormal, theme.borderRadius, 1.0)

		contentX := panelRect.x + 24
		contentY := panelRect.y + 20
		colWidth := (panelRect.width - 72) / 2

		// -------------------------------------------------------------
		// Column 1: Audio & Sound Controls
		// -------------------------------------------------------------
		ui.DrawTextStr("AUDIO & SOUND", contentX, contentY, 14, theme.accent)
		rl.DrawLineEx({contentX, contentY + 20}, {contentX + colWidth, contentY + 20}, 1.0, theme.borderNormal)

		audioY := contentY + 32

		// Master Volume Slider
		ui.DrawTextStr("Master Output Volume", contentX, audioY, 13, theme.textPrimary)
		audioY += 20
		ui.GuiSlider(rl.Rectangle{contentX, audioY, colWidth, 26}, "", "%", &state.masterVolume, 0.0, 100.0, isInteger = true, idKey = 201)
		audioY += 36

		// Music Volume Slider
		ui.DrawTextStr("Background Music Level", contentX, audioY, 13, theme.textPrimary)
		audioY += 20
		ui.GuiSlider(rl.Rectangle{contentX, audioY, colWidth, 26}, "", "%", &state.musicVolume, 0.0, 100.0, isInteger = true, idKey = 202)
		audioY += 36

		// SFX Mute Checkbox
		ui.GuiCheckBox(rl.Rectangle{contentX, audioY, colWidth, 22}, "Mute all sound effects", &state.sfxMute, idKey = 203)
		audioY += 40

		// -------------------------------------------------------------
		// Column 1 Bottom: Display & Video Controls
		// -------------------------------------------------------------
		ui.DrawTextStr("DISPLAY & GRAPHICS", contentX, audioY, 14, theme.accent)
		rl.DrawLineEx({contentX, audioY + 20}, {contentX + colWidth, audioY + 20}, 1.0, theme.borderNormal)

		dispY := audioY + 32

		// Quality Preset Dropdown
		ui.DrawTextStr("Graphics Quality Preset", contentX, dispY, 13, theme.textPrimary)
		dispY += 20
		ui.GuiDropdownBox(rl.Rectangle{contentX, dispY, colWidth, 28}, "Low;Medium;High;Ultra", &state.qualityIdx, idKey = 301)
		dispY += 38

		// Fullscreen Toggle
		ui.GuiToggleSwitch(rl.Rectangle{contentX, dispY, colWidth, 24}, "Enable Fullscreen", &state.fullscreenActive, idKey = 302)
		dispY += 32

		// VSync Checkbox
		ui.GuiCheckBox(rl.Rectangle{contentX, dispY, colWidth, 22}, "Vertical Sync (VSync Lock)", &state.vsyncActive, idKey = 303)

		// -------------------------------------------------------------
		// Column 2: Player Profile & Campaign
		// -------------------------------------------------------------
		col2X := contentX + colWidth + 24
		col2Y := contentY

		ui.DrawTextStr("PLAYER PROFILE & CAMPAIGN", col2X, col2Y, 14, theme.accent)
		rl.DrawLineEx({col2X, col2Y + 20}, {col2X + colWidth, col2Y + 20}, 1.0, theme.borderNormal)

		profY := col2Y + 32

		// Callsign Input
		_, _ = ui.GuiTextInput(rl.Rectangle{col2X, profY, colWidth, 30}, "Callsign", &state.callsignBuffer, "Enter callsign...", 90, idKey = 401)
		profY += 44

		// Difficulty Radio Group
		ui.DrawTextStr("Simulation Difficulty:", col2X, profY, 13, theme.textPrimary)
		profY += 22
		ui.GuiRadioGroup(rl.Rectangle{col2X, profY, colWidth, 90}, "Difficulty", diffOptions[:], &state.difficultyIdx, horizontal = false, idKey = 410)
		profY += 100

		// Info Box
		infoRect := rl.Rectangle{col2X, profY, colWidth, 68}
		ui.DrawThemeRect(infoRect, theme.bgWidget, theme.borderNormal, theme.borderRadiusSmall, 1.0)
		ui.GuiIcon(rl.Rectangle{infoRect.x + 10, infoRect.y + 10, 18, 18}, .Info, 16, theme.info)
		ui.DrawTextStr("Theme and widget metrics are automatically", infoRect.x + 36, infoRect.y + 12, 12, theme.textSecondary)
		ui.DrawTextStr("propagated. Hover buttons, drag sliders, or focus", infoRect.x + 36, infoRect.y + 28, 12, theme.textSecondary)
		ui.DrawTextStr("inputs with keyboard Tab navigation.", infoRect.x + 36, infoRect.y + 44, 12, theme.textSecondary)

		// -------------------------------------------------------------
		// Bottom Action Bar & Status
		// -------------------------------------------------------------
		statusY := panelRect.y + panelRect.height - 38
		if state.statusTimer > 0.0 {
			ui.GuiIcon(rl.Rectangle{contentX, statusY + 2, 16, 16}, .Check, 14, theme.success)
			ui.DrawTextStr(state.statusMessage, contentX + 22, statusY, 13, theme.success)
		}

		// Action Buttons on Bottom-Right
		resetBtnRect := rl.Rectangle{panelRect.x + panelRect.width - 250, statusY - 6, 110, 32}
		saveBtnRect  := rl.Rectangle{panelRect.x + panelRect.width - 130, statusY - 6, 118, 32}

		if ui.GuiIconButton(resetBtnRect, .RotateLeft, "Reset", isSelected = false, idKey = 501) {
			state.masterVolume = 85.0
			state.musicVolume = 60.0
			state.sfxMute = false
			state.qualityIdx = 2
			state.difficultyIdx = 1
			state.statusMessage = "Settings restored to defaults"
			state.statusTimer = 2.5
		}

		if ui.GuiIconButton(saveBtnRect, .FloppyDisk, "Save", isSelected = true, idKey = 502) {
			state.statusMessage = fmt.tprintf("Saved preferences for %s!", string(state.callsignBuffer[:]))
			state.statusTimer = 3.0
		}

		// Footer info
		ui.DrawTextStr("Odin UI Engine Demo \u2022 Use mouse or Tab/Shift-Tab/Arrows/Space to interact", 24, f32(rl.GetScreenHeight() - 32), 12, theme.textSecondary)

		// 3. Process navigation and update cursor
		ui.ImmediateNav_Update()

		// 4. Render active dropdown overlay on top of other content
		ui.RenderImmediateDropdownOverlay()

		rl.EndDrawing()
	}
}
