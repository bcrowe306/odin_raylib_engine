package engine

import "core:strings"
import "core:testing"
import rl "vendor:raylib"

@(test)
test_players_read_their_own_pads :: proc(t: ^testing.T) {
	input: InputSystem
	InputSystem_Init(&input)
	defer InputSystem_Destroy(&input)
	Input_DefineAction(&input, "dash", {{deviceType = .KeyboardKey, key = .K}, {deviceType = .GamepadButton, gamepadButton = .RIGHT_FACE_RIGHT}})

	// Player 2's pad (slot 1) presses jump: only player 2 jumps.
	Input_SimulatePad(&input, 1, true, "Xbox Wireless Controller")
	Input_SimulatePadButton(&input, 1, .RIGHT_FACE_DOWN, true)
	InputSystem_Update(&input, 0.016)
	p1, _ := Input_PlayerActionState(&input, "jump", 1)
	p2, _ := Input_PlayerActionState(&input, "jump", 2)
	testing.expect(t, !p1.down, "player 1 doesn't jump")
	testing.expect(t, p2.down && p2.pressed, "player 2 jumps")
	InputSystem_Update(&input, 0.016)
	p2, _ = Input_PlayerActionState(&input, "jump", 2)
	testing.expect(t, p2.down && !p2.pressed, "held, pressed once")

	// The keyboard is player 1's; project actions work per player too.
	Input_SetSimulatedKey(&input, .K, true)
	Input_SimulatePadButton(&input, 1, .RIGHT_FACE_DOWN, false)
	InputSystem_Update(&input, 0.016)
	d1, _ := Input_PlayerActionState(&input, "dash", 1)
	d2, _ := Input_PlayerActionState(&input, "dash", 2)
	p2, _ = Input_PlayerActionState(&input, "jump", 2)
	testing.expect(t, d1.down && !d2.down, "keyboard: player 1")
	testing.expect(t, p2.released, "player 2 let go")
	Input_SetSimulatedKey(&input, .K, false)
	Input_SimulatePadButton(&input, 1, .RIGHT_FACE_RIGHT, true)
	InputSystem_Update(&input, 0.016)
	d2, _ = Input_PlayerActionState(&input, "dash", 2)
	testing.expect(t, d2.down, "player 2's dash on the pad")

	// Player 1's pad (slot 0): sticks are analog.
	Input_SimulatePadAxis(&input, 0, .LEFT_X, 1)
	InputSystem_Update(&input, 0.016)
	r, _ := Input_PlayerActionState(&input, "move_right", 1)
	testing.expect(t, r.down && r.value > 0.99, "player 1's stick")
	r2, _ := Input_PlayerActionState(&input, "move_right", 2)
	testing.expect(t, !r2.down, "not player 2's")
}

@(test)
test_gamepad_hot_plug_and_assignment :: proc(t: ^testing.T) {
	input: InputSystem
	InputSystem_Init(&input)
	defer InputSystem_Destroy(&input)
	testing.expect_value(t, Input_PlayerPad(&input, 1), i32(0))
	testing.expect_value(t, Input_PlayerPad(&input, 3), i32(2))
	InputSystem_Update(&input, 0.016) // (the first poll: what is there)
	testing.expect(t, len(Input_TakePadEvents(&input)) == 0, "nothing at the start")

	Input_SimulatePad(&input, 2, true, "DualSense Wireless Controller")
	InputSystem_Update(&input, 0.016)
	ev := Input_TakePadEvents(&input)
	testing.expect(t, len(ev) == 1 && ev[0].player == 3 && ev[0].connected && ev[0].name == "DualSense Wireless Controller", "player 3 connected")
	testing.expect(t, Input_PlayerConnected(&input, 3), "player 3 has a pad")
	testing.expect_value(t, Input_PlayerDevice(&input, 3), "playstation")
	testing.expect_value(t, Input_PlayerDevice(&input, 2), "none")

	Input_SimulatePad(&input, 2, false)
	InputSystem_Update(&input, 0.016)
	ev = Input_TakePadEvents(&input)
	testing.expect(t, len(ev) == 1 && ev[0].player == 3 && !ev[0].connected, "player 3 disconnected")

	// Swaps: two players never share a pad.
	Input_SetPlayerPad(&input, 2, 0)
	testing.expect_value(t, Input_PlayerPad(&input, 2), i32(0))
	testing.expect_value(t, Input_PlayerPad(&input, 1), i32(1))
	testing.expect_value(t, input.gamepadIndex, i32(1))
	testing.expect_value(t, Input_PlayerOfPad(&input, 0), 2)

	// A pad nobody has goes to the first player without one.
	Input_SetPlayerPad(&input, 4, -1)
	Input_SimulatePad(&input, 3, true, "Pro Controller")
	InputSystem_Update(&input, 0.016)
	ev = Input_TakePadEvents(&input)
	testing.expect(t, len(ev) == 1 && ev[0].player == 1, "player 1 (no pad connected) takes it")
	testing.expect_value(t, Input_PlayerPad(&input, 1), i32(3))
	testing.expect_value(t, Input_PlayerDevice(&input, 1), "switch") // (plugging a pad in: prompts for it)
}

@(test)
test_rumble_requests :: proc(t: ^testing.T) {
	input: InputSystem
	InputSystem_Init(&input)
	defer InputSystem_Destroy(&input)
	testing.expect(t, !Input_Vibrate(&input, 2, 1, 1, 0.5), "no pad: no rumble")
	Input_SimulatePad(&input, 1, true)
	testing.expect(t, Input_Vibrate(&input, 2, 0.25, 2, 0.5), "player 2 rumbles")
	low, high := Input_Rumble(&input, 1)
	testing.expect(t, low == 0.25 && high == 1, "strengths clamped to 0..1")
	for _ in 0 ..< 20 do InputSystem_Update(&input, 0.016)
	low, high = Input_Rumble(&input, 1)
	testing.expect(t, low == 0.25, "still going at 0.32 s")
	for _ in 0 ..< 20 do InputSystem_Update(&input, 0.016)
	low, high = Input_Rumble(&input, 1)
	testing.expect(t, low == 0 && high == 0, "stopped after its seconds")
	Input_Vibrate(&input, 2, 1, 1, 5)
	Input_StopVibration(&input, 2)
	low, _ = Input_Rumble(&input, 1)
	testing.expect(t, low == 0, "stopped")
	Input_Vibrate(&input, 2, 1, 1, 5)
	Input_SimulatePad(&input, 1, false)
	InputSystem_Update(&input, 0.016)
	low, _ = Input_Rumble(&input, 1)
	testing.expect(t, low == 0, "unplugged: stopped")
}

@(test)
test_button_prompts :: proc(t: ^testing.T) {
	testing.expect_value(t, Pad_Family("Xbox Wireless Controller"), "xbox")
	testing.expect_value(t, Pad_Family("XInput Gamepad (GLFW)"), "xbox")
	testing.expect_value(t, Pad_Family("PS4 Controller"), "playstation")
	testing.expect_value(t, Pad_Family("DualSense Wireless Controller"), "playstation")
	testing.expect_value(t, Pad_Family("Nintendo Switch Pro Controller"), "switch")
	testing.expect_value(t, Pad_Family("Steam Deck"), "steamdeck")
	testing.expect_value(t, Pad_Family("8BitDo SN30"), "generic")

	input: InputSystem
	InputSystem_Init(&input)
	defer InputSystem_Destroy(&input)
	testing.expect_value(t, Input_Glyph(&input, "jump", 1, "xbox"), "prompts:xbox/xbox_button_a")
	testing.expect_value(t, Input_Glyph(&input, "jump", 1, "playstation"), "prompts:playstation/playstation_button_cross")
	testing.expect_value(t, Input_Glyph(&input, "jump", 1, "switch"), "prompts:switch/switch_button_b")
	testing.expect_value(t, Input_Glyph(&input, "jump", 1, "steamdeck"), "prompts:steamdeck/steamdeck_button_a")
	testing.expect_value(t, Input_Glyph(&input, "jump", 1, "generic"), "prompts:xbox/xbox_button_a")
	testing.expect_value(t, Input_Glyph(&input, "jump", 1, "keyboard"), "prompts:keyboard/keyboard_space")
	testing.expect_value(t, Input_Glyph(&input, "move_left", 1, "keyboard"), "prompts:keyboard/keyboard_a")
	testing.expect_value(t, Input_Glyph(&input, "confirm", 1, "xbox"), "") // (keys only)
	testing.expect_value(t, Input_Glyph(&input, "nope", 1, "xbox"), "")

	// The device now: player 1 has no pad - the keyboard; player 2's pad.
	testing.expect_value(t, Input_Glyph(&input, "jump"), "prompts:keyboard/keyboard_space")
	Input_SimulatePad(&input, 1, true, "DualSense Wireless Controller")
	testing.expect_value(t, Input_Glyph(&input, "jump", 2), "prompts:playstation/playstation_button_cross")
	// Player 1 picks a pad up: its prompts; a key press: the keyboard's.
	Input_SimulatePad(&input, 0, true, "Nintendo Switch Pro Controller")
	Input_SimulatePadButton(&input, 0, .RIGHT_FACE_DOWN, true)
	InputSystem_Update(&input, 0.016)
	testing.expect_value(t, Input_Glyph(&input, "jump"), "prompts:switch/switch_button_b")
	Input_SetSimulatedKey(&input, .SPACE, true)
	InputSystem_Update(&input, 0.016)
	testing.expect_value(t, Input_Glyph(&input, "jump"), "prompts:keyboard/keyboard_space")

	// Every pad button and stick direction has an image, in every family.
	for family in ([]string{"xbox", "playstation", "switch", "steamdeck"}) {
		for b in rl.GamepadButton {
			if b == .UNKNOWN || family == "playstation" && b == .MIDDLE do continue
			p := Binding_Glyph({deviceType = .GamepadButton, gamepadButton = b}, family)
			testing.expectf(t, p != "", "%s %v has an image", family, b)
		}
		for a in rl.GamepadAxis do for pos in ([]bool{false, true}) {
			p := Binding_Glyph({deviceType = .GamepadAxis, gamepadAxis = a, axisPositive = pos}, family)
			testing.expectf(t, p != "", "%s %v %v has an image", family, a, pos)
		}
	}
	testing.expect_value(t, Binding_Glyph({deviceType = .GamepadButton, gamepadButton = .MIDDLE_RIGHT}, "playstation", "Wireless Controller"), "prompts:playstation/playstation4_button_options")
	for k in ([]string{"A", "Z", "ZERO", "NINE", "F1", "F12", "SPACE", "ENTER", "ESCAPE", "TAB", "LEFT_SHIFT", "LEFT_CONTROL", "LEFT_ALT", "UP", "DOWN", "LEFT", "RIGHT", "BACKSPACE", "KP_5", "COMMA", "PERIOD"}) {
		key, _ := parse_keyboard_key(k)
		p := Binding_Glyph({deviceType = .KeyboardKey, key = key}, "keyboard")
		testing.expectf(t, p != "", "key %s has an image", k)
	}
	testing.expect_value(t, Binding_Glyph({deviceType = .MouseButton, mouseButton = .LEFT}, "keyboard"), "prompts:keyboard/mouse_left")

	// The images: 64 x 64 cut from the sheets.
	img, ok := Prompt_Image("prompts:xbox/xbox_button_a")
	testing.expect(t, ok && img.width == 64 && img.height == 64, "an image")
	if ok do rl.UnloadImage(img)
	_, ok = Prompt_Image("prompts:xbox/nope")
	testing.expect(t, !ok, "no such prompt")
	testing.expect(t, len(Prompt_Names("keyboard")) > 100, "the keyboard sheet")
	r, _ := Prompt_Rect("prompts:keyboard/keyboard_space")
	testing.expect_value(t, r, rl.Rectangle{1024, 1024 - 704 - 64, 64, 64}) // (Kenney's y is from the bottom)

	// Every image in every sheet is an icon - opaque and transparent pixels,
	// not the sheets' unused (flat grey) corner: the rects are read the
	// right way up.
	for family in ([]string{"keyboard", "xbox", "playstation", "switch", "steamdeck"}) {
		sheet := Prompt_SheetImage(family)
		defer rl.UnloadImage(sheet)
		px := ([^]u8)(sheet.data)
		for name in Prompt_Names(family) {
			pr, _ := Prompt_Rect(strings.concatenate({"prompts:", family, "/", name}, context.temp_allocator))
			opaque, clear := 0, 0
			for y in int(pr.y) ..< int(pr.y + pr.height) do for x in int(pr.x) ..< int(pr.x + pr.width) {
				if px[(y * int(sheet.width) + x) * 4 + 3] > 128 do opaque += 1
				else do clear += 1
			}
			testing.expectf(t, opaque > 40 && clear > 40, "%s/%s is an icon (%d opaque, %d clear)", family, name, opaque, clear)
		}
	}
}

@(test)
test_input_script_gamepads :: proc(t: ^testing.T) {
	script := `
5 pad2 connect Xbox Wireless Controller
10 pad2 RIGHT_FACE_DOWN tap 3
12 pad2 LEFT_X -0.5
20 SPACE down
30 pad2 disconnect
`
	events, err := Runner_LoadInputScript(script, context.temp_allocator)
	testing.expect_value(t, err, "")
	testing.expect_value(t, len(events), 6)
	testing.expect(t, events[0].pad == 1 && events[0].kind == .Connect && events[0].name == "Xbox Wireless Controller", "connect")
	testing.expect(t, events[1].kind == .Button && events[1].down && events[2].frame == 13 && !events[2].down, "tap")
	testing.expect(t, events[3].kind == .Axis && events[3].axis == .LEFT_X && events[3].value == -0.5, "axis")
	testing.expect(t, events[4].pad == -1 && events[4].key == .SPACE, "a key")
	testing.expect(t, events[5].kind == .Disconnect, "disconnect")

	input: InputSystem
	InputSystem_Init(&input)
	defer InputSystem_Destroy(&input)
	for ev in events[:2] do Runner_ApplyInputEvent(&input, ev)
	InputSystem_Update(&input, 0.016)
	j, _ := Input_PlayerActionState(&input, "jump", 2)
	testing.expect(t, j.down, "the script's pad jumps for player 2")
	_, bad := Runner_LoadInputScript("1 pad2 NOPE down", context.temp_allocator)
	testing.expect(t, strings.contains(bad, "NOPE"), "bad pad input")
}
