package engine

import "core:testing"
import rl "vendor:raylib"

// #203: an animated file's frames as one strip (top to bottom) with each
// frame's time - previews in the File Browser and the Assets panel.
@(test)
test_anim_file_strip :: proc(t: ^testing.T) {
	strip, ok := Anim_LoadFileStrip("tests/aseprite/fixtures/animation.aseprite")
	if !testing.expect(t, ok, "loads") do return
	defer Anim_StripDestroy(&strip)
	n := len(strip.durations)
	testing.expectf(t, n > 1, "frames: %d", n)
	testing.expect_value(t, int(strip.image.height), strip.frameSize.y * n)
	testing.expect_value(t, int(strip.image.width), strip.frameSize.x)
	for d in strip.durations do testing.expect(t, d > 0, "each frame has a time")
	// Frame i's rect in the strip.
	r := Anim_StripFrameRect(strip, 1)
	testing.expect_value(t, r, rl.Rectangle{0, f32(strip.frameSize.y), f32(strip.frameSize.x), f32(strip.frameSize.y)})
	// Not an animation: no.
	_, ok2 := Anim_LoadFileStrip("tests/drive/fixtures/import/crate.png")
	testing.expect(t, !ok2, "a still image isn't one")
}

@(test)
test_anim_strip_frame_at :: proc(t: ^testing.T) {
	d := []f32{0.1, 0.2, 0.1}
	testing.expect_value(t, Anim_StripFrameAt(d, 0.05, true), 0)
	testing.expect_value(t, Anim_StripFrameAt(d, 0.15, true), 1)
	testing.expect_value(t, Anim_StripFrameAt(d, 0.35, true), 2)
	testing.expect_value(t, Anim_StripFrameAt(d, 0.45, true), 0) // (looped)
	testing.expect_value(t, Anim_StripFrameAt(d, 0.45, false), 2) // (held)
}
