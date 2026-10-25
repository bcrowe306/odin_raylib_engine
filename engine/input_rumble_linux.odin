#+build linux
package engine

import "core:fmt"
import "core:strings"
import "core:sys/linux"

// Rumble on Linux: evdev force feedback (input_rumble.odin). The pad's
// /dev/input/event* is found by its name (GLFW names pads by EVIOCGNAME;
// several of the same name: in order), an FF_RUMBLE effect is uploaded and
// played for the duration. Needs read-write access to the device (desktop
// sessions give it to the logged-in user).

@(private = "file")
Ff_Effect :: struct {
	type:      u16,
	id:        i16,
	direction: u16,
	trigger:   struct {button, interval: u16},
	replay:    struct {length, delay: u16},
	_:         [2]u8,
	u:         struct #raw_union {
		rumble: struct {strong, weak: u16},
		_:      [32]u8, // (ff_periodic_effect, the largest member, on 64-bit)
	},
}

@(private = "file")
Input_Event :: struct {
	time:  [2]int, // timeval
	type:  u16,
	code:  u16,
	value: i32,
}

@(private = "file") EV_FF :: 0x15
@(private = "file") FF_RUMBLE :: 0x50

@(private = "file")
ioc :: proc(dir, nr, size: u32) -> u32 {return dir << 30 | size << 16 | u32('E') << 8 | nr}

@(private = "file")
Pad_Device :: struct {
	fd:     linux.Fd,
	effect: i16,
	name:   string,
	open:   bool,
}

@(private = "file")
devices: [MAX_PADS]Pad_Device

// The event device of the `nth` pad named `name` (-1: not found).
@(private = "file")
find_device :: proc(name: string, nth: int) -> linux.Fd {
	seen := 0
	for i in 0 ..< 64 {
		path := fmt.ctprintf("/dev/input/event%d", i)
		fd, err := linux.open(path, {.RDWR, .NONBLOCK, .CLOEXEC})
		if err != .NONE do continue
		buf: [256]u8
		n := int(linux.ioctl(fd, ioc(2, 0x06, len(buf)), uintptr(&buf[0]))) // EVIOCGNAME
		dev := string(buf[:max(n - 1, 0)]) if n > 0 && n <= len(buf) else ""
		if dev == name || strings.equal_fold(dev, name) {
			if seen == nth do return fd
			seen += 1
		}
		linux.close(fd)
	}
	return -1
}

@(private = "file")
device_for :: proc(pad: i32, name: string) -> ^Pad_Device {
	d := &devices[pad]
	if d.open && d.name == name do return d
	if d.open do close_device(d)
	nth := 0 // pads before this one with the same name
	for p in 0 ..< pad do if devices[p].open && devices[p].name == name do nth += 1
	fd := find_device(name, nth)
	if fd < 0 do return nil
	d^ = {fd = fd, effect = -1, name = strings.clone(name), open = true}
	return d
}

@(private = "file")
close_device :: proc(d: ^Pad_Device) {
	if d.effect >= 0 do linux.ioctl(d.fd, ioc(1, 0x81, size_of(i32)), uintptr(d.effect)) // EVIOCRMFF
	linux.close(d.fd)
	delete(d.name)
	d^ = {}
}

rumble_native_start :: proc(pad: i32, name: string, low, high, seconds: f32) -> bool {
	if pad < 0 || pad >= MAX_PADS || name == "" do return false
	d := device_for(pad, name)
	if d == nil do return false
	e := Ff_Effect{type = FF_RUMBLE, id = d.effect}
	e.replay.length = u16(clamp(seconds * 1000, 1, 65535))
	e.u.rumble = {strong = u16(low * 65535), weak = u16(high * 65535)}
	if i32(linux.ioctl(d.fd, ioc(1, 0x80, size_of(Ff_Effect)), uintptr(&e))) < 0 { // EVIOCSFF
		close_device(d) // (gone, or no force feedback)
		return false
	}
	d.effect = e.id
	play := Input_Event{type = EV_FF, code = u16(d.effect), value = 1}
	_, werr := linux.write(d.fd, ([^]u8)(&play)[:size_of(play)])
	return werr == .NONE
}

rumble_native_stop :: proc(pad: i32) {
	if pad < 0 || pad >= MAX_PADS do return
	d := &devices[pad]
	if !d.open || d.effect < 0 do return
	stop := Input_Event{type = EV_FF, code = u16(d.effect), value = 0}
	linux.write(d.fd, ([^]u8)(&stop)[:size_of(stop)])
}

rumble_native_shutdown :: proc() {
	for &d in devices do if d.open do close_device(&d)
}

#assert(size_of(Ff_Effect) == 48 || size_of(rawptr) != 8)
