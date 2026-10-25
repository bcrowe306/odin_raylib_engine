#+build windows
package engine

import win "core:sys/windows"

// Rumble on Windows: XInput (input_rumble.odin). GLFW lists XInput pads
// first, in their XInput slots' order, so raylib's pad N is the Nth
// connected XInput slot. Pads that aren't XInput (a DualShock without
// Steam Input) can't rumble here.

@(private = "file")
xinput_slot :: proc(pad: i32) -> (win.XUSER, bool) {
	n: i32 = 0
	for slot in 0 ..< u32(win.XUSER_MAX_COUNT) {
		state: win.XINPUT_STATE
		if win.XInputGetState(win.XUSER(slot), &state) != .SUCCESS do continue
		if n == pad do return win.XUSER(slot), true
		n += 1
	}
	return .One, false
}

rumble_native_start :: proc(pad: i32, name: string, low, high, seconds: f32) -> bool {
	slot, ok := xinput_slot(pad)
	if !ok do return false
	v := win.XINPUT_VIBRATION{wLeftMotorSpeed = u16(low * 65535), wRightMotorSpeed = u16(high * 65535)}
	return win.XInputSetState(slot, &v) == .SUCCESS
}

rumble_native_stop :: proc(pad: i32) {
	slot, ok := xinput_slot(pad)
	if !ok do return
	v: win.XINPUT_VIBRATION
	win.XInputSetState(slot, &v)
}

rumble_native_shutdown :: proc() {}
