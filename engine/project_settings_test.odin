package engine

import "core:strings"
import "core:testing"

@(test)
test_project_input_actions_video_audio_export :: proc(t: ^testing.T) {
	src := `{"name": "P", "input": {"actions": [
		{"name": "dash", "bindings": [{"key": "K"}, {"button": "RIGHT_FACE_RIGHT"}]},
		{"name": "jump", "bindings": [{"key": "W"}, {"axis": "LEFT_Y", "positive": false, "deadzone": 0.4}]}]},
		"video": {"fullscreen": true, "vsync": false},
		"audio": {"master_volume": 0.5, "music_volume": 0.25, "sfx_volume": 0.75},
		"export": {"executable": "MyGame", "targets": ["windows", "linux"], "compress": false}}`
	cfg, ok := Project_ParseConfig(transmute([]u8)string(src))
	defer ProjectConfig_Destroy(&cfg)
	testing.expect(t, ok, "parsed")
	testing.expect_value(t, len(cfg.actions), 2)
	testing.expect_value(t, len(cfg.actions[1].bindings), 2)
	testing.expect(t, cfg.actions[1].bindings[1].deviceType == .GamepadAxis && !cfg.actions[1].bindings[1].axisPositive, "axis binding")
	testing.expect(t, cfg.fullscreen && !cfg.vsync && cfg.resizable, "video")
	testing.expect(t, cfg.musicVolume == 0.25 && cfg.sfxVolume == 0.75, "audio")
	testing.expect(t, cfg.export.targets == {.Windows, .Linux} && !cfg.export.compress && cfg.export.executableName == "MyGame", "export")

	// Round trip.
	text := Project_SerializeToJSON(&cfg, context.temp_allocator)
	testing.expect(t, strings.contains(text, `{"name": "dash", "bindings": [{"key": "K"}, {"button": "RIGHT_FACE_RIGHT"}]}`), "actions saved")
	cfg2, ok2 := Project_ParseConfig(transmute([]u8)text)
	defer ProjectConfig_Destroy(&cfg2)
	testing.expect(t, ok2 && len(cfg2.actions) == 2 && cfg2.export.targets == cfg.export.targets && cfg2.fullscreen, "round trip")
	clone := ProjectConfig_Clone(&cfg2)
	defer ProjectConfig_Destroy(&clone)
	testing.expect_value(t, clone.actions[0].name, "dash")

	// Applied to the input system: a new action and a rebound built-in.
	input: InputSystem
	InputSystem_Init(&input)
	defer InputSystem_Destroy(&input)
	Input_ApplyActionConfigs(&input, cfg.actions[:])
	Input_SetSimulatedKey(&input, .K, true)
	InputSystem_Update(&input, 0.016)
	st, found := Input_ActionStateByName(&input, "Dash")
	testing.expect(t, found && st.down && st.pressed, "custom action fires")
	Input_SetSimulatedKey(&input, .K, false)
	Input_SetSimulatedKey(&input, .W, true)
	InputSystem_Update(&input, 0.016)
	jump, _ := Input_ActionStateByName(&input, "jump")
	testing.expect(t, jump.down, "jump rebound to W")
	Input_SetSimulatedKey(&input, .W, false)
	Input_SetSimulatedKey(&input, .SPACE, true)
	InputSystem_Update(&input, 0.016)
	jump, _ = Input_ActionStateByName(&input, "jump")
	testing.expect(t, !jump.down, "old SPACE binding replaced")
}

@(test)
test_project_icon_and_runner_args :: proc(t: ^testing.T) {
	cfg, ok := Project_ParseConfig(transmute([]u8)string(`{"name": "Game", "icon": "textures/icon.png"}`))
	defer ProjectConfig_Destroy(&cfg)
	testing.expect(t, ok, "parsed")
	testing.expect_value(t, cfg.icon, "textures/icon.png")
	text := Project_SerializeToJSON(&cfg, context.temp_allocator)
	testing.expect(t, strings.contains(text, `"icon": "textures/icon.png"`), "icon saved")
	c2 := ProjectConfig_Clone(&cfg)
	defer ProjectConfig_Destroy(&c2)
	testing.expect_value(t, c2.icon, "textures/icon.png")

	opts := Engine_ParseRunArgs({"game.ore", "--user-data", "/tmp/saves", "--frames", "5"})
	testing.expect_value(t, opts.projectPath, "game.ore")
	testing.expect_value(t, opts.userDataDir, "/tmp/saves")
	testing.expect_value(t, opts.maxFrames, 5)
}
