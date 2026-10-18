package asteroids

import "core:math"
import rl "vendor:raylib"
import e "../engine"

globalUIState: ^AsteroidsUIState

AsteroidsUIState :: struct {
	volumeSlider:    ^e.UISliderNode,
	speedSlider:     ^e.UISliderNode,
	gravitySlider:   ^e.UISliderNode,
	freqSlider:      ^e.UISliderNode,
	callsignInput:   ^e.UITextInputNode,
	qualityDropdown: ^e.UIDropdownNode,
	difficultyRadio: ^e.UIRadioGroupNode,
	vsyncCheck:      ^e.UICheckboxNode,
	shakeCheck:      ^e.UICheckboxNode,
	telemetryCheck:  ^e.UICheckboxNode,
	shieldsCheck:    ^e.UICheckboxNode,
	telemetryPlot:   ^e.UIXYPlotNode,
	reactorBar:      ^e.UIProgressBarNode,
	summaryLabel:    ^e.UILabelNode,
	phase:           f32,
}

TitleMenuScene_Build :: proc(scene: ^e.Scene, ctx: ^e.GameContext) {
	// Background cosmic particle emitter
	starEmitter := e.ParticleEmitterNode_Create(scene, "Starfield Emitter")
	starEmitter.position = {640, 360}
	starEmitter.emitter.amount = 65
	starEmitter.emitter.lifetime = 3.5
	starEmitter.emitter.velocity = 60
	starEmitter.emitter.burst = 0.0
	starEmitter.emitter.continuous = true

	// Centered Title Menu Panel
	panel := e.UIPanelNode_Create(
		scene,
		"Title Menu Panel",
		"ASTEROIDS // COMMAND DECK",
		{410, 95},
		{460, 530},
		.Vertical,
	)
	panel.spacing = 12
	panel.paddingTop = 18
	panel.paddingBottom = 18
	panel.paddingLeft = 28
	panel.paddingRight = 28

	// Game Title & Subtitle Labels
	titleLbl := e.UILabelNode_Create(scene, "TitleBanner", "ASTEROIDS", 34, panel)
	titleLbl.align = .Center
	titleLbl.textColor = rl.Color{110, 168, 254, 255}
	titleLbl.size = {400, 42}

	subLbl := e.UILabelNode_Create(scene, "SubtitleBanner", "ODIN + RAYLIB + BOX2D ENGINE", 14, panel)
	subLbl.align = .Center
	subLbl.textColor = rl.Color{155, 164, 182, 255}
	subLbl.size = {400, 22}

	_ = e.UISeparatorNode_Create(scene, "TitleDivider", "NAVIGATION", panel)

	// Vertical Container for Main Action Buttons
	btnBox := e.UIVerticalContainerNode_Create(scene, "MenuButtonsVBox", {400, 230}, 10, .Stretch, panel)

	playBtn := e.UIButtonNode_Create(scene, "PlayButton", "LEVEL 1: ASTEROIDS FIELD", {400, 44}, btnBox)
	playBtn.fontSize = 17
	playBtn.normalColor = rl.Color{30, 64, 175, 255}
	playBtn.hoverColor = rl.Color{37, 99, 235, 255}
	playBtn.borderColor = rl.Color{110, 168, 254, 255}
	playBtn.onClickCallback = proc(btn: ^e.UIButtonNode, ctx: ^e.GameContext) {
		if ctx != nil && ctx.game != nil {
			ctx.game->changeScene("main")
		}
	}

	battleBtn := e.UIButtonNode_Create(scene, "BattleLevelButton", "LEVEL 2: BATTLE ARENA", {400, 44}, btnBox)
	battleBtn.fontSize = 17
	battleBtn.normalColor = rl.Color{16, 120, 150, 255}
	battleBtn.hoverColor = rl.Color{24, 160, 200, 255}
	battleBtn.borderColor = rl.Color{34, 211, 238, 255}
	battleBtn.onClickCallback = proc(btn: ^e.UIButtonNode, ctx: ^e.GameContext) {
		if ctx != nil && ctx.game != nil {
			ctx.game->changeScene("battle_arena")
		}
	}

	settingsBtn := e.UIButtonNode_Create(scene, "SettingsButton", "SETTINGS", {400, 42}, btnBox)
	settingsBtn.fontSize = 16
	settingsBtn.onClickCallback = proc(btn: ^e.UIButtonNode, ctx: ^e.GameContext) {
		if ctx != nil && ctx.game != nil {
			ctx.game->changeScene("settings")
		}
	}

	quitBtn := e.UIButtonNode_Create(scene, "QuitButton", "QUIT GAME", {400, 44}, btnBox)
	quitBtn.fontSize = 16
	quitBtn.normalColor = rl.Color{68, 28, 34, 255}
	quitBtn.hoverColor = rl.Color{120, 38, 48, 255}
	quitBtn.borderColor = rl.Color{248, 113, 113, 255}
	quitBtn.onClickCallback = proc(btn: ^e.UIButtonNode, ctx: ^e.GameContext) {
		if ctx != nil && ctx.game != nil {
			ctx.game->quit()
		}
	}

	_ = e.UISeparatorNode_Create(scene, "FooterDivider", "", panel)

	hintLbl := e.UILabelNode_Create(
		scene,
		"MenuHintLabel",
		"Use Editor [F2] to inspect UI nodes in Scene Hierarchy",
		13,
		panel,
	)
	hintLbl.align = .Center
	hintLbl.textColor = rl.Color{135, 142, 158, 255}
}

CreateTitleMenuScene :: proc(game: ^e.Game, makeActive: bool = true) -> ^e.Scene {
	scene := game->createScene("title_menu", makeActive, TitleMenuScene_Build)
	return scene
}

SettingsMenuScene_Build :: proc(scene: ^e.Scene, ctx: ^e.GameContext) {
	uiState := globalUIState
	if uiState == nil do return

	panel := e.UIPanelNode_Create(
		scene,
		"Settings Panel",
		"SETTINGS // UI WIDGETS & LAYOUT CONTAINERS DEMO",
		{110, 34},
		{1060, 652},
		.Vertical,
	)
	panel.spacing = 12
	panel.paddingTop = 14
	panel.paddingBottom = 14
	panel.paddingLeft = 20
	panel.paddingRight = 20

	// 2-Column Horizontal Container inside Panel
	columnsHBox := e.UIHorizontalContainerNode_Create(
		scene,
		"SettingsColumnsHBox",
		{1020, 535},
		22,
		.Stretch,
		panel,
	)

	// -------------------------------------------------------------------------
	// Left Column: Sliders, TextInput, Dropdown, RadioButtons, Checkboxes Grid
	// -------------------------------------------------------------------------
	leftVBox := e.UIVerticalContainerNode_Create(
		scene,
		"LeftControlsVBox",
		{495, 530},
		9,
		.Stretch,
		columnsHBox,
	)
	leftVBox.autoSizeHeight = false

	_ = e.UISeparatorNode_Create(scene, "SlidersHeader", "Sliders (Click Value=Edit | Shift=Fine | [R]=Reset)", leftVBox)

	uiState.volumeSlider = e.UISliderNode_Create(scene, "MasterVolumeSlider", "Master Volume", 80.0, 0.0, 100.0, leftVBox)
	uiState.volumeSlider.isInteger = true

	uiState.speedSlider = e.UISliderNode_Create(scene, "ThrustSpeedSlider", "Ship Max Speed", 800.0, 200.0, 2000.0, leftVBox)
	uiState.speedSlider.fineScale = 0.05

	uiState.gravitySlider = e.UISliderNode_Create(scene, "GravityScaleSlider", "Gravity Scale", 1.0, 0.0, 5.0, leftVBox)
	uiState.gravitySlider.fineScale = 0.1

	uiState.freqSlider = e.UISliderNode_Create(scene, "PlotFreqSlider", "Telemetry Freq", 2.0, 0.5, 8.0, leftVBox)
	uiState.freqSlider.fineScale = 0.1

	_ = e.UISeparatorNode_Create(scene, "InputsHeader", "Text Input, Dropdown & Radio Buttons", leftVBox)

	uiState.callsignInput = e.UITextInputNode_Create(
		scene,
		"PilotCallsignInput",
		"Pilot Callsign",
		"NOVA-01",
		"Type pilot callsign...",
		leftVBox,
	)

	uiState.qualityDropdown = e.UIDropdownNode_Create(
		scene,
		"GraphicsPresetDropdown",
		"Graphics Preset",
		{"Low", "Medium", "High", "Ultra"},
		2,
		leftVBox,
	)

	uiState.difficultyRadio = e.UIRadioGroupNode_Create(
		scene,
		"DifficultyRadioGroup",
		"Difficulty",
		{"Cadet", "Veteran", "Ace"},
		1,
		true,
		leftVBox,
	)

	_ = e.UISeparatorNode_Create(scene, "CheckboxesHeader", "System Toggles (Grid Container)", leftVBox)

	toggleGrid := e.UIGridContainerNode_Create(scene, "TogglesGridContainer", {485, 68}, 2, 8, leftVBox)
	uiState.vsyncCheck = e.UICheckboxNode_Create(scene, "VSyncCheckbox", "Enable VSync", true, toggleGrid)
	uiState.shakeCheck = e.UICheckboxNode_Create(scene, "ScreenShakeCheckbox", "Screen Shake", true, toggleGrid)
	uiState.telemetryCheck = e.UICheckboxNode_Create(scene, "TelemetryCheckbox", "Telemetry HUD", true, toggleGrid)
	uiState.shieldsCheck = e.UICheckboxNode_Create(scene, "AutoShieldsCheckbox", "Auto-Shields", false, toggleGrid)

	// -------------------------------------------------------------------------
	// Right Column: X/Y Telemetry Plot, Progress Bar, Live Summary Labels
	// -------------------------------------------------------------------------
	rightVBox := e.UIVerticalContainerNode_Create(
		scene,
		"RightTelemetryVBox",
		{495, 530},
		10,
		.Stretch,
		columnsHBox,
	)
	rightVBox.autoSizeHeight = false

	_ = e.UISeparatorNode_Create(scene, "PlotHeader", "X/Y Telemetry Plot (Hover for Crosshair)", rightVBox)

	uiState.telemetryPlot = e.UIXYPlotNode_Create(
		scene,
		"ThrusterXYPlot",
		"Thruster Response & Harmonic Curve",
		{485, 255},
		rightVBox,
	)
	uiState.telemetryPlot.xLabel = "Time (s)"
	uiState.telemetryPlot.yLabel = "Output"
	uiState.telemetryPlot.series1Name = "Thrust"
	uiState.telemetryPlot.series2Name = "Harmonic"
	uiState.telemetryPlot.xMin = 0.0
	uiState.telemetryPlot.xMax = 6.28
	uiState.telemetryPlot.yMin = -1.2
	uiState.telemetryPlot.yMax = 1.2

	uiState.reactorBar = e.UIProgressBarNode_Create(
		scene,
		"ReactorOutputProgress",
		"Master Volume / Power Level",
		80.0,
		0.0,
		100.0,
		rightVBox,
	)

	_ = e.UISeparatorNode_Create(scene, "SummaryHeader", "Live Configuration Readout", rightVBox)

	uiState.summaryLabel = e.UILabelNode_Create(
		scene,
		"LiveConfigSummaryLabel",
		"Pilot: NOVA-01 | Preset: High | Mode: Veteran",
		15,
		rightVBox,
	)
	uiState.summaryLabel.textColor = rl.Color{110, 168, 254, 255}

	tip1 := e.UILabelNode_Create(scene, "TipLabel1", "* Click a slider's value box to type an exact number + ENTER", 13, rightVBox)
	tip1.textColor = rl.Color{170, 178, 195, 255}
	tip2 := e.UILabelNode_Create(scene, "TipLabel2", "* Hold SHIFT while dragging a slider for 10x fine adjustments", 13, rightVBox)
	tip2.textColor = rl.Color{170, 178, 195, 255}
	tip3 := e.UILabelNode_Create(scene, "TipLabel3", "* Click [R] or Right-Click a slider/checkbox to reset to default", 13, rightVBox)
	tip3.textColor = rl.Color{170, 178, 195, 255}

	// -------------------------------------------------------------------------
	// Footer Horizontal Button Bar
	// -------------------------------------------------------------------------
	footerHBox := e.UIHorizontalContainerNode_Create(
		scene,
		"SettingsFooterHBox",
		{1020, 42},
		16,
		.Stretch,
		panel,
	)

	backBtn := e.UIButtonNode_Create(scene, "BackToTitleButton", "< BACK TO TITLE MENU", {320, 38}, footerHBox)
	backBtn.onClickCallback = proc(btn: ^e.UIButtonNode, ctx: ^e.GameContext) {
		if ctx != nil && ctx.game != nil {
			ctx.game->changeScene("title_menu")
		}
	}

	resetAllBtn := e.UIButtonNode_Create(scene, "ResetAllSettingsButton", "RESET ALL DEFAULTS", {320, 38}, footerHBox)
	resetAllBtn.resource = uiState
	resetAllBtn.onClickCallback = proc(btn: ^e.UIButtonNode, ctx: ^e.GameContext) {
		st := cast(^AsteroidsUIState)btn.resource
		if st == nil do return
		e.UISliderNode_Reset(st.volumeSlider, ctx)
		e.UISliderNode_Reset(st.speedSlider, ctx)
		e.UISliderNode_Reset(st.gravitySlider, ctx)
		e.UISliderNode_Reset(st.freqSlider, ctx)
		e.UITextInputNode_SetText(st.callsignInput, "NOVA-01", ctx)
		e.UIDropdownNode_Select(st.qualityDropdown, st.qualityDropdown.defaultIndex, ctx)
		e.UIRadioGroupNode_Select(st.difficultyRadio, st.difficultyRadio.defaultIndex, ctx)
		e.UICheckboxNode_SetChecked(st.vsyncCheck, st.vsyncCheck.defaultChecked, ctx)
		e.UICheckboxNode_SetChecked(st.shakeCheck, st.shakeCheck.defaultChecked, ctx)
		e.UICheckboxNode_SetChecked(st.telemetryCheck, st.telemetryCheck.defaultChecked, ctx)
		e.UICheckboxNode_SetChecked(st.shieldsCheck, st.shieldsCheck.defaultChecked, ctx)
	}

	playFromSettingsBtn := e.UIButtonNode_Create(scene, "PlayFromSettingsButton", "LAUNCH GAME >", {320, 38}, footerHBox)
	playFromSettingsBtn.normalColor = rl.Color{30, 64, 175, 255}
	playFromSettingsBtn.hoverColor = rl.Color{37, 99, 235, 255}
	playFromSettingsBtn.borderColor = rl.Color{110, 168, 254, 255}
	playFromSettingsBtn.onClickCallback = proc(btn: ^e.UIButtonNode, ctx: ^e.GameContext) {
		if ctx != nil && ctx.game != nil {
			ctx.game->changeScene("main")
		}
	}

	UpdateSettingsTelemetryPlot(uiState, 0)
	scene.update = proc(s: ^e.Scene, ctx: ^e.GameContext, dt: f32) {
		if ctx == nil || ctx.game == nil do return
		btnNode, ok := e.GetNodeByPath(s, s.rootNode, "/Settings Panel/SettingsFooterHBox/ResetAllSettingsButton")
		if ok && btnNode != nil && btnNode.resource != nil {
			st := cast(^AsteroidsUIState)btnNode.resource
			UpdateSettingsTelemetryPlot(st, dt)
		}
	}
}

CreateSettingsMenuScene :: proc(game: ^e.Game, uiState: ^AsteroidsUIState) -> ^e.Scene {
	globalUIState = uiState
	scene := game->createScene("settings", false, SettingsMenuScene_Build)
	return scene
}

UpdateSettingsTelemetryPlot :: proc(st: ^AsteroidsUIState, dt: f32) {
	if st == nil || st.telemetryPlot == nil do return
	st.phase += dt * 1.8

	e.UIXYPlotNode_Clear(st.telemetryPlot)
	freq := st.freqSlider.value if st.freqSlider != nil else 2.0
	amp := (st.speedSlider.value / 2000.0) if st.speedSlider != nil else 0.8
	diffScale := f32(st.difficultyRadio.selectedIndex + 1) * 0.35 if st.difficultyRadio != nil else 0.5

	numSamples := 60
	for i in 0..=numSamples {
		x := (f32(i) / f32(numSamples)) * 6.28318
		y1 := math.sin(x * freq + st.phase) * amp
		y2 := math.cos(x * (freq * 0.5) - st.phase * 0.7) * diffScale
		e.UIXYPlotNode_AddPoint(st.telemetryPlot, x, y1)
		e.UIXYPlotNode_AddSecondaryPoint(st.telemetryPlot, x, y2)
	}

	if st.reactorBar != nil && st.volumeSlider != nil {
		st.reactorBar.value = st.volumeSlider.value
	}
}

CreateInGameHUD :: proc(scene: ^e.Scene) {
	hudBar := e.UIHorizontalContainerNode_Create(
		scene,
		"InGameHUD",
		{280, 34},
		8,
		.Stretch,
	)
	hudBar.position = {14, 34}
	hudBar.globalPosition = {14, 34}

	menuBtn := e.UIButtonNode_Create(scene, "ReturnToMenuButton", "< Title Menu", {135, 30}, hudBar)
	menuBtn.fontSize = 14
	menuBtn.onClickCallback = proc(btn: ^e.UIButtonNode, ctx: ^e.GameContext) {
		if ctx != nil && ctx.game != nil {
			ctx.game->changeScene("title_menu")
		}
	}

	settingsBtn := e.UIButtonNode_Create(scene, "InGameSettingsButton", "Settings", {120, 30}, hudBar)
	settingsBtn.fontSize = 14
	settingsBtn.onClickCallback = proc(btn: ^e.UIButtonNode, ctx: ^e.GameContext) {
		if ctx != nil && ctx.game != nil {
			ctx.game->changeScene("settings")
		}
	}
}
