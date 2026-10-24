package engine

import os "osx"
import "core:testing"
import lua "lua54"

@(test)
test_navigation_tilemap :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("nav", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	tm := TileMapNode_Create(scene, "Walls")
	tm.solid = true
	tm.tileSize = {10, 10}
	tm.mapSize = {10, 10}
	TileMapNode_Layout(tm)
	// A wall down x = 5 with a gap at the bottom row.
	for y in 0 ..< 9 do TileMapNode_Set(tm, 5, y, 0)
	game->run(0.016)

	g := Nav_GridFor(tm)
	testing.expect(t, g != nil && g.w == 10 && !Nav_Walkable(g, {5, 0}) && Nav_Walkable(g, {5, 9}), "grid from painted walls")
	cells := Nav_FindCells(g, {1, 1}, {8, 1})
	testing.expectf(t, len(cells) > 14, "around the wall through the gap: %d cells", len(cells))
	through_gap := false
	for c in cells {
		testing.expect(t, Nav_Walkable(g, c), "only walkable cells")
		if c == {5, 9} do through_gap = true
	}
	testing.expect(t, through_gap, "uses the gap")

	// Smoothed world path: fewer points, starts and ends where asked.
	path := Nav_FindPath(g, {15, 15}, {85, 15})
	testing.expect(t, len(path) >= 3 && len(path) < len(cells), "smoothed")
	testing.expect(t, path[0] == {15, 15} && path[len(path) - 1] == {85, 15}, "ends")

	// No corner cutting; 4 directions.
	g2 := Nav_Grid{w = 3, h = 3, blocked = make([]bool, 9, context.temp_allocator), cell = {1, 1}}
	g2.blocked[1] = true // (1, 0)
	g2.blocked[3] = true // (0, 1)
	testing.expect(t, Nav_FindCells(&g2, {0, 0}, {1, 1}) == nil, "can't squeeze between two blocked corners")
	testing.expect(t, !Nav_LineClear(&g2, {0, 0}, {1, 1}), "no line of sight through a closed corner")
	g2.blocked[3] = false
	testing.expect(t, !Nav_LineClear(&g2, {0, 0}, {1, 1}), "nor past one blocked side")
	testing.expect(t, Nav_LineClear(&g2, {0, 1}, {2, 1}), "clear row")
	testing.expect_value(t, len(Nav_FindCells(&g2, {0, 0}, {2, 2}, diagonal = false)), 5)

	// Closing the gap: no way through; blocked ends: nil.
	TileMapNode_Set(tm, 5, 9, 0)
	g = Nav_GridFor(tm) // rebuilt: the map changed
	testing.expect(t, Nav_FindPath(g, {15, 15}, {85, 15}) == nil, "walled off")
	testing.expect(t, Nav_FindPath(g, {55, 15}, {15, 15}) == nil, "start inside a wall")

	// Lua.
	TileMapNode_Set(tm, 5, 9, -1)
	L := game.scriptManager.L
	ok := lua.L_dostring(L, `
local map = Scene.find_node("Walls")
local path = map:nav_find_path(15, 15, 85, 15)
n = #path
first_x = path[1][1]
same = #Navigation.find_path(map, 15, 15, 85, 15, {smooth = false}) > n
walk = tostring(map:nav_is_walkable(15, 15)) .. tostring(map:nav_is_walkable(55, 15))
none = tostring(map:nav_find_path(15, 15, 55, 15) == nil)
`)
	testing.expect(t, ok == 0, "lua ran")
	lua.getglobal(L, "n")
	testing.expect(t, lua.tointeger(L, -1) >= 3, "path from Lua")
	lua.pop(L, 1)
	Check :: struct {name: cstring, want: string}
	for ch in ([]Check{{"walk", "truefalse"}, {"none", "true"}}) {
		lua.getglobal(L, ch.name)
		testing.expect_value(t, string(lua.tostring(L, -1)), ch.want)
		lua.pop(L, 1)
	}
	lua.getglobal(L, "same")
	testing.expect(t, bool(lua.toboolean(L, -1)), "unsmoothed path has more points")
	lua.pop(L, 1)
}

@(test)
test_navigation_ldtk :: proc(t: ^testing.T) {
	_ = os.make_directory_all("test_ldtk_nav")
	defer os.remove_all("test_ldtk_nav")
	_ = os.write_entire_file("test_ldtk_nav/game.ldtk", transmute([]u8)string(LDTK_WORLDS_PROJECT))
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("ldtk_nav", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	ln := cast(^LdtkLevelNode)Node_CreateByTypeName(scene, "LdtkLevelNode")
	ln.gameContext = &game.gameContext
	ln.spawnEntities = false
	ln.scale = {2, 3}
	ln.position = {100, 50}
	LdtkLevelNode_SetCollisionRule(ln, {layer = "Collisions", value = 1, type = .Solid})
	LdtkLevelNode_SetProject(ln, "test_ldtk_nav/game.ldtk", "A")
	game->run(0.016)

	// Level A: [wall wall platform platform / water water . wall]; walls block.
	g := Nav_GridFor(ln)
	testing.expect(t, g != nil && g.w == 4 && g.h == 2, "grid from the Collisions layer")
	if g == nil do return
	blocked := 0
	for b in g.blocked do if b do blocked += 1
	testing.expect_value(t, blocked, 3)
	testing.expect(t, g.cell == {32, 48} && g.origin == {100, 50}, "follows the level's scale and position")
	// (2,1) -> (3,0): not diagonally past the wall at (3,1).
	path := Nav_FindPath(g, Nav_CellCenter(g, {2, 1}), Nav_CellCenter(g, {3, 0}))
	testing.expect_value(t, len(path), 3)
	if len(path) == 3 do testing.expect(t, Nav_CellAt(g, path[1]) == {2, 0}, "via (2, 0)")
}
