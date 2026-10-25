package engine

// ============================================================================
// Rumble (TODO E.4). raylib's SetGamepadVibration does nothing on desktop
// (GLFW has no force feedback), so each OS has a small native layer:
//   Windows: XInput (XInputSetState; pads in XInput's slots),
//   Linux:   evdev force feedback (FF_RUMBLE on the pad's /dev/input/event*),
//   macOS:   GameController + CoreHaptics (the controller's haptics engine).
// (An SDL backend for raylib was tried first: Odin's vendor:raylib links its
// own GLFW build, so it would mean forking the bindings - see
// docs/gamepads.md.) The web build uses the Gamepad API's vibrationActuator
// where the browser has it.
//
// Strength is 0..1 per motor: low = the heavy (left) motor, high = the light
// (right) one; macOS controllers have one haptics engine (the stronger of
// the two). A rumble stops after its seconds, when the pad goes, or with
// Input_StopVibration. Simulated pads record it (tests: Input_Rumble).
// ============================================================================

Rumble_State :: struct {
	low, high: f32,
	remaining: f32, // seconds (0: not rumbling)
	native:    bool, // the OS layer took it
}

// Input_Vibrate rumbles a player's pad (player 1-based). false: no pad.
Input_Vibrate :: proc(input: ^InputSystem, player: int, low, high, seconds: f32) -> bool {
	pad := Input_PlayerPad(input, player)
	if !Input_PadConnected(input, pad) do return false
	low, high := clamp(low, 0, 1), clamp(high, 0, 1)
	seconds := clamp(seconds, 0, 10)
	r := &input.pads.rumble[pad]
	if low == 0 && high == 0 || seconds == 0 {
		Rumble_Stop(input, pad)
		return true
	}
	r.low, r.high, r.remaining = low, high, seconds
	r.native = false
	if !input.pads.sim[pad].active {
		r.native = rumble_native_start(pad, Input_PadName(input, pad), low, high, seconds)
	}
	return true
}

Input_StopVibration :: proc(input: ^InputSystem, player: int) {
	Rumble_Stop(input, Input_PlayerPad(input, player))
}

// Input_Rumble: a pad's rumble now (0, 0: none).
Input_Rumble :: proc(input: ^InputSystem, pad: i32) -> (low, high: f32) {
	if pad < 0 || pad >= MAX_PADS do return 0, 0
	r := input.pads.rumble[pad]
	if r.remaining <= 0 do return 0, 0
	return r.low, r.high
}

Rumble_Stop :: proc(input: ^InputSystem, pad: i32) {
	if pad < 0 || pad >= MAX_PADS do return
	r := &input.pads.rumble[pad]
	if r.native do rumble_native_stop(pad)
	r^ = {}
}

Rumble_Update :: proc(input: ^InputSystem, deltaTime: f32) {
	for &r, pad in input.pads.rumble {
		if r.remaining <= 0 do continue
		r.remaining -= deltaTime
		if r.remaining <= 0 do Rumble_Stop(input, i32(pad)) // (XInput keeps going until told)
	}
}

Rumble_Shutdown :: proc(input: ^InputSystem) {
	for pad in 0 ..< i32(MAX_PADS) do Rumble_Stop(input, pad)
	rumble_native_shutdown()
}
