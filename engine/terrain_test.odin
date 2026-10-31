package engine

import "core:strings"
import "core:testing"

// #171: terrain sets - the 16 / 47 patterns, a cell's pattern from its
// neighbours, the tile for a pattern (variants, fallbacks), the file, and
// auto-tiling on a TileMap (painting, erasing, filling) and in a generator.

// A terrain whose tile for each pattern is the mask itself + 100 (so a
// cell's tile tells its pattern).
@(private = "file")
mask_terrain :: proc(ts: ^Tile_Terrains, kind: Terrain_Kind) -> ^Tile_Terrain {
	t := Terrains_Add(ts, "Grass")
	t.kind = kind
	for m in Terrain_Patterns(kind) do append(&t.tiles[m], i32(m) + 100)
	return t
}

@(test)
test_terrain_patterns :: proc(t: ^testing.T) {
	testing.expect_value(t, len(Terrain_Patterns(.Blob)), 47)
	testing.expect_value(t, len(Terrain_Patterns(.Edges)), 16)
	// A corner counts only with both its sides.
	testing.expect_value(t, Terrain_Reduce(TERRAIN_NE), 0)
	testing.expect_value(t, Terrain_Reduce(TERRAIN_N | TERRAIN_E | TERRAIN_NE), TERRAIN_N | TERRAIN_E | TERRAIN_NE)
	testing.expect_value(t, Terrain_Reduce(TERRAIN_N | TERRAIN_NE), TERRAIN_N)
	nb := [3][3]bool{{true, true, false}, {true, true, true}, {false, false, false}}
	testing.expect_value(t, Terrain_Mask(.Blob, nb), TERRAIN_N | TERRAIN_E | TERRAIN_W | TERRAIN_NW)
	testing.expect_value(t, Terrain_Mask(.Edges, nb), 1 | 2 | 8)
	testing.expect_value(t, Terrain_SidecarPath("textures/Tiles.png"), "textures/Tiles.tileset.json")
	testing.expect_value(t, Terrain_SidecarPath("tiles"), "tiles.tileset.json")
	free_all(context.temp_allocator)
}

@(test)
test_terrain_tile_choice :: proc(t: ^testing.T) {
	ts, _ := Terrains_Parse(nil)
	defer Terrains_Destroy(&ts)
	g := Terrains_Add(&ts, "Rock")
	append(&g.tiles[255], 1)
	append(&g.tiles[TERRAIN_N | TERRAIN_S], 2)
	append(&g.tiles[TERRAIN_N | TERRAIN_S], 3)
	// Exact; variants from the cell; corners dropped; then the full tile.
	got := map[i32]bool{}
	defer delete(got)
	for x in 0 ..< 40 do got[Terrain_Tile(g, TERRAIN_N | TERRAIN_S, x, 0)] = true
	testing.expect(t, len(got) == 2 && 2 in got && 3 in got, "both variants used")
	testing.expect_value(t, Terrain_Tile(g, TERRAIN_N | TERRAIN_S, 7, 3), Terrain_Tile(g, TERRAIN_N | TERRAIN_S, 7, 3))
	testing.expect_value(t, Terrain_Tile(g, 255, 0, 0), 1)
	testing.expect_value(t, Terrain_Tile(g, TERRAIN_E, 0, 0), 1) // (none: the full one)
	testing.expect(t, Terrain_Has(g, 3) && !Terrain_Has(g, 9), "membership")
	// Saved and read back.
	text := Terrains_Serialize(&ts, context.temp_allocator)
	back, err := Terrains_Parse(transmute([]u8)text, context.temp_allocator)
	testing.expectf(t, err == "", "parse: %s", err)
	r, i := Terrains_Find(&back, "Rock")
	testing.expect(t, i == 0 && r.kind == .Blob && len(r.tiles[TERRAIN_N | TERRAIN_S]) == 2 && r.tiles[255][0] == 1, text)
	free_all(context.temp_allocator)
}

@(test)
test_terrain_on_tilemap :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("terrain", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	tm := TileMapNode_Create(scene, "Map")
	tm.mapSize = {8, 8}
	ProcessNodeQueues(scene.manager, &game.gameContext)
	ts, _ := Terrains_Parse(nil)
	defer Terrains_Destroy(&ts)
	grass := mask_terrain(&ts, .Blob)
	// A 3x3 block: the middle full, the corners and sides their patterns.
	for y in 2 ..= 4 do for x in 2 ..= 4 do TileMapNode_PaintTerrain(tm, grass, x, y, true)
	testing.expect_value(t, TileMapNode_Get(tm, 3, 3), 255 + 100)
	testing.expect_value(t, TileMapNode_Get(tm, 2, 2), i32(TERRAIN_E | TERRAIN_SE | TERRAIN_S) + 100) // top-left
	testing.expect_value(t, TileMapNode_Get(tm, 3, 2), i32(TERRAIN_E | TERRAIN_SE | TERRAIN_S | TERRAIN_SW | TERRAIN_W) + 100) // top
	testing.expect_value(t, TileMapNode_Get(tm, 4, 4), i32(TERRAIN_N | TERRAIN_W | TERRAIN_NW) + 100) // bottom-right
	// Erase the middle: the ring's cells see the hole.
	TileMapNode_PaintTerrain(tm, grass, 3, 3, false)
	testing.expect_value(t, TileMapNode_Get(tm, 3, 3), -1)
	testing.expect_value(t, TileMapNode_Get(tm, 3, 2), i32(TERRAIN_E | TERRAIN_W) + 100)
	// Fill an empty area: all of it the terrain, its rim tiled.
	tm2 := TileMapNode_Create(scene, "Map2")
	tm2.mapSize = {5, 4}
	ProcessNodeQueues(scene.manager, &game.gameContext)
	n := TileMapNode_FillTerrain(tm2, grass, 1, 1)
	testing.expect_value(t, n, 20)
	testing.expect_value(t, TileMapNode_Get(tm2, 2, 1), 255 + 100)
	testing.expect_value(t, TileMapNode_Get(tm2, 0, 0), i32(TERRAIN_E | TERRAIN_SE | TERRAIN_S) + 100)
	free_all(context.temp_allocator)
}

@(test)
test_terrain_in_generator :: proc(t: ^testing.T) {
	g, err := Gen_GraphParse(transmute([]u8)string(`{"size": [6, 5], "nodes": [
		{"id": 1, "type": "rect", "params": {"x": 1, "y": 1, "w": 3, "h": 3}},
		{"id": 2, "type": "tile_output", "inputs": {"in": 1}, "tileset": "textures/t.png",
		 "rules": [{"min": 0.5, "max": 1, "tiles": [], "terrain": "Grass"}, {"min": 0, "max": 0.4, "tiles": [], "terrain": "Nope"}]}]}`))
	testing.expectf(t, err == "", "parse: %s", err)
	defer Gen_GraphDestroy(&g)
	testing.expect_value(t, Gen_FindNode(&g, 2).rules[0].terrain, "Grass")
	testing.expect(t, strings.contains(Gen_GraphSerialize(&g, context.temp_allocator), `"terrain": "Grass"`), "saved")
	ts, _ := Terrains_Parse(nil, context.temp_allocator)
	mask_terrain(&ts, .Blob)
	Gen_SetTerrainSource(&g, "textures/t.png", Terrains_Serialize(&ts, context.temp_allocator))
	tiles, _, terr := Gen_Tiles(&g, 2)
	defer delete(tiles)
	testing.expectf(t, terr == "", "tiles: %s", terr)
	at :: proc(tiles: []i32, x, y: int) -> i32 {return tiles[y * 6 + x]}
	testing.expect_value(t, at(tiles, 2, 2), 255 + 100)
	testing.expect_value(t, at(tiles, 1, 1), i32(TERRAIN_E | TERRAIN_SE | TERRAIN_S) + 100)
	testing.expect_value(t, at(tiles, 0, 0), -1) // ("Nope": no such terrain - empty)
	// No terrains file: the terrain's cells are empty, nothing fails.
	Gen_LoadTerrains(&g, nil) // (none read: cleared)
	tiles2, _, _ := Gen_Tiles(&g, 2, 0, context.temp_allocator)
	testing.expect_value(t, at(tiles2, 2, 2), -1)
	// Duplicated with its rules' terrain.
	dup := Gen_DuplicateNode(&g, 2)
	testing.expect_value(t, dup.rules[0].terrain, "Grass")
	free_all(context.temp_allocator)
}
