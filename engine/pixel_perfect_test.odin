package engine

import "core:strings"
import "core:testing"
import rl "vendor:raylib"

// Pixel-perfect: integer scaling fits by a whole number, pixel snap puts the
// camera (with the leftover fraction recorded) and sprites on whole pixels,
// the smooth camera's margin shifts the camera, the settings round-trip.
@(test)
test_pixel_perfect :: proc(t: ^testing.T) {
	defer Render_SetPixelSettings({})
	defer renderPixel.margin = 0

	// Integer scaling: 320x180 in 1000x700 -> 3x (960x540), centred.
	Render_SetPixelSettings({integerScaling = true})
	testing.expect_value(t, Pixel_FitRect(320, 180, 1000, 700), rl.Rectangle{20, 80, 960, 540})
	// Smaller than the frame: still fits (not 0x).
	testing.expect_value(t, Pixel_FitRect(320, 180, 160, 90), rl.Rectangle{0, 0, 160, 90})
	Render_SetPixelSettings({})
	testing.expect_value(t, Pixel_FitRect(320, 180, 1000, 700), rl.Rectangle{0, 68.75 - 0.75, 1000, 562.5}) // fractional without it

	// Pixel snap: target to whole pixels at the zoom, the rest kept.
	Render_SetPixelSettings({snap = true, smooth = true})
	testing.expect(t, renderPixel.smooth, "smooth needs snap: on")
	cam := rl.Camera2D{offset = {160, 90}, target = {10.3, 20.75}, zoom = 2}
	Pixel_SnapCamera(&cam)
	testing.expect_value(t, cam.target, [2]f32{10.5, 21})          // 20.6 -> 21 px, 41.5 -> 42 px (/2)
	testing.expect(t, abs(renderPixel.frac.x - (-0.4)) < 0.001 && abs(renderPixel.frac.y - (-0.5)) < 0.001, "the leftover fraction")
	// The smooth camera's world texture: the offset moves by the margin.
	renderPixel.margin = PIXEL_MARGIN
	cam2 := rl.Camera2D{offset = {160, 90}, target = {0, 0}, zoom = 1}
	Pixel_SnapCamera(&cam2)
	testing.expect_value(t, cam2.offset, [2]f32{161, 91})
	renderPixel.margin = 0
	// Sprites: the top-left corner on a whole pixel; rotated ones untouched.
	testing.expect_value(t, Pixel_SnapSprite({10.4, 5.6}, {8, 8}, 0), [2]f32{10, 6})
	testing.expect_value(t, Pixel_SnapSprite({10.4, 5.6}, {8, 8}, 30), [2]f32{10.4, 5.6})
	Render_SetPixelSettings({smooth = true})
	testing.expect(t, !renderPixel.smooth, "smooth without snap: off")

	// The project settings: read, written, applied.
	cfg, ok := Project_ParseConfig(transmute([]u8)string(`{"name": "x", "initial_scene": "a.scene.json", "video": {"integer_scaling": true, "pixel_snap": true, "smooth_camera": true}}`))
	defer ProjectConfig_Destroy(&cfg)
	testing.expect(t, ok && cfg.integerScaling && cfg.pixelSnap && cfg.smoothCamera, "read")
	json := Project_SerializeToJSON(&cfg)
	defer delete(json)
	testing.expect(t, strings.contains(json, `"integer_scaling": true, "pixel_snap": true, "smooth_camera": true`), json)
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	Game_LoadProjectConfig(game, &cfg, activate = false)
	testing.expect(t, renderPixel.integerScaling && renderPixel.snap && renderPixel.smooth, "applied")
}
