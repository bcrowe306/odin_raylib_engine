package engine

import "core:testing"
import lua "lua54"

// #220: scripts read and paint tiles; a solid map's colliders follow (once,
// at the end of the frame), and so does path finding.
@(test)
test_tilemap_lua_tiles :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("tiles220", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	tm := TileMapNode_Create(scene, "Map")
	tm.solid = true
	tm.tileSize = {16, 16}
	tm.mapSize = {10, 10}
	tm.position = {100, 50}
	TileMapNode_Layout(tm)
	TileMapNode_Set(tm, 2, 3, 5)
	ProcessNodeQueues(scene.manager, &game.gameContext)
	game->run(0.016)
	shapes := len(tm.staticBody.shapes) if tm.staticBody != nil else -1
	testing.expect_value(t, shapes, 1)

	L := game.scriptManager.L
	ok := lua.L_dostring(L, `
local map = Scene.find_node("Map")
t_get = map:tilemap_get_tile(2, 3)
t_empty = map:tilemap_get_tile(0, 0)
t_set = map:tilemap_set_tile(4, 3, 7)
t_same = map:tilemap_set_tile(4, 3, 7)
map:tilemap_set_tile(2, 3, -1)
cx, cy = map:tilemap_cell_at(100 + 16 * 4 + 3, 50 + 16 * 3 + 3)
wx, wy = map:tilemap_cell_position(4, 3)
`) == 0
	testing.expect(t, ok, "Lua ran")
	num :: proc(L: ^lua.State, name: cstring) -> f64 {
		lua.getglobal(L, name)
		defer lua.pop(L, 1)
		return f64(lua.tonumber(L, -1))
	}
	flag :: proc(L: ^lua.State, name: cstring) -> bool {
		lua.getglobal(L, name)
		defer lua.pop(L, 1)
		return bool(lua.toboolean(L, -1))
	}
	testing.expect_value(t, num(L, "t_get"), 5)
	testing.expect_value(t, num(L, "t_empty"), -1)
	testing.expect(t, flag(L, "t_set") && !flag(L, "t_same"), "set reports a change once")
	testing.expect_value(t, TileMapNode_Get(tm, 4, 3), 7)
	testing.expect_value(t, TileMapNode_Get(tm, 2, 3), -1)
	testing.expect(t, num(L, "cx") == 4 && num(L, "cy") == 3, "the cell under a world position")
	testing.expect(t, num(L, "wx") == 100 + 16 * 4 + 8 && num(L, "wy") == 50 + 16 * 3 + 8, "a cell's centre")

	// The colliders follow at the end of the frame: one shape, at the new tile.
	testing.expect_value(t, tm.staticBody.shapes[0].offset, [2]f32{2 * 16 + 8, 3 * 16 + 8})
	game->run(0.016)
	testing.expect(t, tm.staticBody != nil && len(tm.staticBody.shapes) == 1, "rebuilt with one shape")
	if tm.staticBody != nil && len(tm.staticBody.shapes) == 1 {
		testing.expect_value(t, tm.staticBody.shapes[0].offset, [2]f32{4 * 16 + 8, 3 * 16 + 8})
	}
}
