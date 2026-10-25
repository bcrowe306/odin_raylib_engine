#+build darwin
package engine

import "base:intrinsics"
import "core:strings"
import NS "core:sys/darwin/Foundation"

// Rumble on macOS: GameController + CoreHaptics (input_rumble.odin). The
// pad's GCController is found by name (GLFW names pads by their HID product
// name, GameController by the same; several of the same name: in order),
// its haptics engine plays a continuous event for the duration. One engine
// per controller: the stronger motor's strength.

foreign import GameController "system:GameController.framework"
foreign import CoreHaptics "system:CoreHaptics.framework"

@(private = "file")
foreign GameController {
	GCHapticsLocalityDefault: ^NS.String
}

@(private = "file")
foreign CoreHaptics {
	CHHapticEventTypeHapticContinuous:       ^NS.String
	CHHapticEventParameterIDHapticIntensity: ^NS.String
	CHHapticEventParameterIDHapticSharpness: ^NS.String
}

@(private = "file", objc_class = "GCController") GCController :: struct {using _: NS.Object}
@(private = "file", objc_class = "CHHapticEventParameter") CHHapticEventParameter :: struct {using _: NS.Object}
@(private = "file", objc_class = "CHHapticEvent") CHHapticEvent :: struct {using _: NS.Object}
@(private = "file", objc_class = "CHHapticPattern") CHHapticPattern :: struct {using _: NS.Object}

@(private = "file")
Haptic_Pad :: struct {
	name:   string,
	engine: ^NS.Object, // CHHapticEngine (retained)
	player: ^NS.Object, // the playing CHHapticPatternPlayer (retained)
}

@(private = "file")
haptics: [MAX_PADS]Haptic_Pad

@(private = "file")
msg :: intrinsics.objc_send

// The haptics engine of the `nth` controller named `name` (nil: none).
@(private = "file")
find_engine :: proc(name: string, nth: int) -> ^NS.Object {
	list := msg(^NS.Array, GCController, "controllers")
	if list == nil do return nil
	n := int(list->count())
	pick: ^NS.Object
	seen := 0
	for i in 0 ..< n {
		c := list->object(NS.UInteger(i))
		vendor := msg(^NS.String, c, "vendorName")
		vn := string(vendor->UTF8String()) if vendor != nil else ""
		if strings.equal_fold(vn, name) {
			if seen == nth {pick = c; break}
			seen += 1
		}
	}
	if pick == nil && n == 1 do pick = list->object(0) // (a single controller, named differently)
	if pick == nil do return nil
	h := msg(^NS.Object, pick, "haptics")
	if h == nil do return nil // (no haptics: older controllers, or macOS < 11)
	engine := msg(^NS.Object, h, "createEngineWithLocality:", GCHapticsLocalityDefault)
	if engine == nil do return nil
	if !msg(NS.BOOL, engine, "startAndReturnError:", rawptr(nil)) do return nil
	NS.retain(engine)
	return engine
}

@(private = "file")
release_pad :: proc(h: ^Haptic_Pad) {
	if h.player != nil {
		msg(NS.BOOL, h.player, "stopAtTime:error:", f64(0), rawptr(nil))
		NS.release(h.player)
	}
	if h.engine != nil {
		msg(nil, h.engine, "stopWithCompletionHandler:", rawptr(nil))
		NS.release(h.engine)
	}
	delete(h.name)
	h^ = {}
}

rumble_native_start :: proc(pad: i32, name: string, low, high, seconds: f32) -> bool {
	if pad < 0 || pad >= MAX_PADS do return false
	pool := NS.AutoreleasePool.alloc()->init()
	defer pool->drain()
	h := &haptics[pad]
	if h.engine == nil || h.name != name {
		release_pad(h)
		nth := 0
		for p in 0 ..< pad do if haptics[p].engine != nil && haptics[p].name == name do nth += 1
		h.engine = find_engine(name, nth)
		if h.engine == nil do return false
		h.name = strings.clone(name)
	}
	if h.player != nil {
		msg(NS.BOOL, h.player, "stopAtTime:error:", f64(0), rawptr(nil))
		NS.release(h.player)
		h.player = nil
	}
	intensity := msg(^NS.Object, msg(^NS.Object, CHHapticEventParameter, "alloc"), "initWithParameterID:value:", CHHapticEventParameterIDHapticIntensity, max(low, high))
	sharpness := msg(^NS.Object, msg(^NS.Object, CHHapticEventParameter, "alloc"), "initWithParameterID:value:", CHHapticEventParameterIDHapticSharpness, f32(0.8 if high > low else 0.3))
	params := [2]^NS.Object{intensity, sharpness}
	paramList := NS.Array.alloc()->initWithObjects(&params[0], 2)
	event := msg(^NS.Object, msg(^NS.Object, CHHapticEvent, "alloc"), "initWithEventType:parameters:relativeTime:duration:", CHHapticEventTypeHapticContinuous, paramList, f64(0), f64(seconds))
	events := [1]^NS.Object{event}
	eventList := NS.Array.alloc()->initWithObjects(&events[0], 1)
	empty := NS.Array.alloc()->init()
	pattern := msg(^NS.Object, msg(^NS.Object, CHHapticPattern, "alloc"), "initWithEvents:parameters:error:", eventList, empty, rawptr(nil))
	defer {
		for o in ([]^NS.Object{intensity, sharpness, paramList, event, eventList, empty, pattern}) do if o != nil do NS.release(o)
	}
	if pattern == nil do return false
	player := msg(^NS.Object, h.engine, "createPlayerWithPattern:error:", pattern, rawptr(nil))
	if player == nil do return false
	NS.retain(player)
	h.player = player
	return bool(msg(NS.BOOL, player, "startAtTime:error:", f64(0), rawptr(nil)))
}

rumble_native_stop :: proc(pad: i32) {
	if pad < 0 || pad >= MAX_PADS do return
	h := &haptics[pad]
	if h.player == nil do return
	msg(NS.BOOL, h.player, "stopAtTime:error:", f64(0), rawptr(nil))
	NS.release(h.player)
	h.player = nil
}

rumble_native_shutdown :: proc() {
	for &h in haptics do release_pad(&h)
}
