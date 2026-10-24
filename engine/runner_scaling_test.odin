package engine

import "core:testing"
import lua "lua54"
import rl "vendor:raylib"

// The frame fits the window centred (bars where the shapes differ);
// scripts ask for fullscreen; the setting is saved.
@(test)
test_runner_scaling :: proc(t: ^testing.T) {
	testing.expect_value(t, Runner_FitRect(1280, 720, 1280, 720), rl.Rectangle{0, 0, 1280, 720})
	testing.expect_value(t, Runner_FitRect(1280, 720, 1920, 1080), rl.Rectangle{0, 0, 1920, 1080})
	testing.expect_value(t, Runner_FitRect(1280, 720, 1920, 1200), rl.Rectangle{0, 60, 1920, 1080})  // bars top and bottom
	testing.expect_value(t, Runner_FitRect(1280, 720, 2000, 1080), rl.Rectangle{40, 0, 1920, 1080})  // bars at the sides
	testing.expect_value(t, Runner_FitRect(1280, 720, 640, 360), rl.Rectangle{0, 0, 640, 360})

	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	L := game.scriptManager.L
	testing.expect_value(t, lua.L_dostring(L, `a = Engine.is_fullscreen(); Engine.set_fullscreen(true); b = Engine.is_fullscreen()`), i32(0))
	testing.expect(t, game.fullscreenRequest.? or_else false, "asked")
	lua.getglobal(L, "a"); lua.getglobal(L, "b")
	testing.expect(t, !bool(lua.toboolean(L, -2)) && bool(lua.toboolean(L, -1)), "is_fullscreen follows the request")
	lua.pop(L, 2)

	cfg, ok := Project_ParseConfig(transmute([]u8)string(`{"name": "x", "initial_scene": "a.scene.json", "video": {"fullscreen": true, "sharp_scaling": true}}`))
	defer ProjectConfig_Destroy(&cfg)
	testing.expect(t, ok && cfg.fullscreen && cfg.sharpScaling, "read")
}
