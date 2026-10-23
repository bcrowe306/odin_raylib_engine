package engine

import "core:testing"
import lua "vendor:lua/5.4"

// Vec2 / Vec3 / Vec4: operators, methods, v[1] compatibility; the API
// returns Vec2 for vector properties and setters take a vector.
@(test)
test_lua_vectors :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("vectors", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	n := Node_CreateByTypeName(scene, "Node")
	n.name = "Mover"
	ProcessNodeQueues(scene.manager, &game.gameContext)
	L := game.scriptManager.L
	ok := lua.L_dostring(L, `
local a, b = Vec2(3, 4), Vec2(1, 2)
local c = (a + b) * 2 - Vec2(1, 1)                 -- (7, 11)
r1 = string.format("%g,%g|%g|%s|%g", c.x, c.y, a:length(), tostring(-b), a:dot(b))
r2 = (Vec2(10, 0):normalized() == Vec2(1, 0)) and c[1] == 7 and c[2] == 11 and #c == 2
local x, y = Vec2(5, 6):unpack()
r3 = x + y
local v3 = Vec3(1, 2, 3) * Vec3(2, 2, 2)
r4 = v3.z + Vec4(1, 1, 1, 1):length()
local m = Scene.find_node("Mover")
m:set_position(Vec2(12, 34))                           -- a vector setter
local p = m:get_property("position")                   -- a Vec2 back
r5 = getmetatable(p) == getmetatable(Vec2.ZERO) and p.x == 12 and p[2] == 34
m:set_property("position", Vec2(1, 2) + Vec2.ONE)       -- set_property with a vector
m:set_position(7, 8)                                    -- numbers still work
r6 = string.format("%g,%g", Vec2(1, 0):rotated(90).x, Vec2(0, 1):angle())
`)
	if ok != 0 do testing.fail_now(t, string(lua.tostring(L, -1)))
	str :: proc(L: ^lua.State, g: cstring) -> string {
		lua.getglobal(L, g)
		defer lua.pop(L, 1)
		return string(lua.tostring(L, -1))
	}
	testing.expect_value(t, str(L, "r1"), "7,11|5|Vec2(-1, -2)|11")
	lua.getglobal(L, "r2"); testing.expect(t, bool(lua.toboolean(L, -1)), "normalized / [1] / #"); lua.pop(L, 1)
	testing.expect_value(t, str(L, "r3"), "11")
	testing.expect_value(t, str(L, "r4"), "8.0")
	lua.getglobal(L, "r5"); testing.expect(t, bool(lua.toboolean(L, -1)), "get_property: a Vec2"); lua.pop(L, 1)
	testing.expect_value(t, n.position, [2]f32{7, 8})
	testing.expect_value(t, str(L, "r6"), "6.12323e-17,90")
}
