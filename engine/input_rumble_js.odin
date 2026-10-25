#+build js
package engine

import rl "vendor:raylib"

// Rumble on the web: raylib's web platform has it (the Gamepad API's
// vibrationActuator, where the browser supports it) - input_rumble.odin.

rumble_native_start :: proc(pad: i32, name: string, low, high, seconds: f32) -> bool {
	rl.SetGamepadVibration(pad, low, high, seconds)
	return true
}

rumble_native_stop :: proc(pad: i32) {rl.SetGamepadVibration(pad, 0, 0, 0)}

rumble_native_shutdown :: proc() {}
