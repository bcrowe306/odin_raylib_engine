package engine

import "core:testing"
import lua "lua54"

// Property-style access: node.<property> reads / writes like
// get_property / set_property; methods and `name` still work.
@(test)
test_lua_property_access :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("access", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	cam := cast(^CameraNode)Node_CreateByTypeName(scene, "CameraNode")
	cam.name = "Cam"
	ProcessNodeQueues(scene.manager, &game.gameContext)
	L := game.scriptManager.L
	ok := lua.L_dostring(L, `
local c = Scene.find_node("Cam")
c.position = Vec2(10, 20)
c.position = c.position + Vec2(1, 1)
c.rotation = c.rotation + 45
c.followMode = "SingleTarget"
c.name = "Camera2"
r1 = string.format("%g,%g|%g|%s|%s|%s", c.position.x, c.position.y, c.rotation, c.followMode, c.name, c:get_name())
r2 = pcall(function() c.nope = 1 end)   -- unknown: an error
r3 = type(c.get_property)                -- methods still there
`)
	if ok != 0 do testing.fail_now(t, string(lua.tostring(L, -1)))
	lua.getglobal(L, "r1")
	testing.expect_value(t, string(lua.tostring(L, -1)), "11,21|45|SingleTarget|Camera2|Camera2")
	lua.pop(L, 1)
	lua.getglobal(L, "r2"); testing.expect(t, !bool(lua.toboolean(L, -1)), "unknown property errors"); lua.pop(L, 1)
	lua.getglobal(L, "r3"); testing.expect_value(t, string(lua.tostring(L, -1)), "function"); lua.pop(L, 1)
	testing.expect_value(t, cam.followMode, CameraFollowMode.SingleTarget)
}
