package engine

import "core:strings"
import "core:testing"

// #174: fill modes - Expand grows the frame to the screen's shape (no
// bars), Keep is the design size; old projects keep their look.
@(test)
test_screen_fill_size :: proc(t: ^testing.T) {
	// 640x380 (wider than tall-ish) in a 16:9 window: Expand widens it.
	sz := Screen_FillSize({640, 380}, {1280, 720}, .Expand)
	testing.expectf(t, sz.y == 380 && sz.x >= 675 && sz.x <= 676, "the full height, more width: %v", sz)
	r := Pixel_FitRect(sz.x, sz.y, 1280, 720)
	testing.expectf(t, r.width >= 1279 && r.height >= 719, "fills the window (no bars): %v", r)
	// A taller screen: more height.
	sz = Screen_FillSize({640, 360}, {1000, 1000}, .Expand)
	testing.expectf(t, sz.x == 640 && sz.y >= 640, "the full width, more height: %v", sz)
	// The same shape: the design size.
	testing.expect_value(t, Screen_FillSize({640, 360}, {1280, 720}, .Expand), [2]f32{640, 360})
	// Integer scaling: whole game pixels, at least the design.
	sz = Screen_FillSize({320, 180}, {1366, 768}, .Expand, true)
	testing.expectf(t, sz.x == 341 && sz.y == 192, "x4, the rest in whole pixels: %v", sz)
	// Keep: the design size.
	testing.expect_value(t, Screen_FillSize({640, 380}, {1280, 720}, .Keep), [2]f32{640, 380})
}

@(test)
test_screen_fill_saved :: proc(t: ^testing.T) {
	old, ok := Project_ParseConfig(transmute([]u8)string(`{"name": "Old", "video": {"fullscreen": false}}`), context.temp_allocator)
	testing.expect(t, ok, "parsed")
	testing.expect_value(t, old.fill, Screen_Fill.Keep) // (saved before fill modes: bars, as before)
	old.fill = .Expand
	text := Project_SerializeToJSON(&old, context.temp_allocator)
	testing.expectf(t, strings.contains(text, `"fill": "expand"`), "saved: %s", text)
	again, _ := Project_ParseConfig(transmute([]u8)text, context.temp_allocator)
	testing.expect_value(t, again.fill, Screen_Fill.Expand)
}
