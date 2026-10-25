#+build freebsd, openbsd, netbsd, haiku, wasi, freestanding
package engine

// Rumble elsewhere: none (input_rumble.odin).

rumble_native_start :: proc(pad: i32, name: string, low, high, seconds: f32) -> bool {return false}
rumble_native_stop :: proc(pad: i32) {}
rumble_native_shutdown :: proc() {}
