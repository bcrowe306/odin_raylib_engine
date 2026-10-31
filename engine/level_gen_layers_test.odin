package engine

import "core:strings"
import "core:testing"

// #171: tile outputs know their tileset and tile size (the editor's picker
// and previews) and a layer - the TileMap of that name next to the main
// one - so one generator fills ground, walls and decoration at once.

@(private = "file")
LAYERED :: `{"size": [6, 4], "seed": 2, "output": 3, "nodes": [
	{"id": 1, "type": "border", "params": {"width": 1}},
	{"id": 2, "type": "invert", "inputs": {"in": 1}},
	{"id": 3, "type": "tile_output", "inputs": {"in": 1}, "params": {"tile_w": 32, "tile_h": 24}, "rules": [{"min": 0.5, "max": 1, "tiles": [7]}], "tileset": "textures/walls.png"},
	{"id": 4, "type": "tile_output", "inputs": {"in": 2}, "rules": [{"min": 0.5, "max": 1, "tiles": [2]}], "layer": "FloorZz", "tileset": "textures/floor.png"},
	{"id": 5, "type": "tile_output", "inputs": {"in": 2}, "rules": [{"min": 0.5, "max": 1, "tiles": [9]}], "layer": "Missing"}]}`

@(test)
test_level_gen_layers :: proc(t: ^testing.T) {
	g, err := Gen_GraphParse(transmute([]u8)string(LAYERED))
	testing.expectf(t, err == "", "parse: %s", err)
	defer Gen_GraphDestroy(&g)
	out := Gen_FindNode(&g, 3)
	testing.expect_value(t, out.tileset, "textures/walls.png")
	testing.expect_value(t, Gen_Param(out, "tile_w"), 32)
	testing.expect_value(t, Gen_FindNode(&g, 4).layer, "FloorZz")
	// Saved and read back.
	text := Gen_GraphSerialize(&g, context.temp_allocator)
	testing.expect(t, strings.contains(text, `"layer": "FloorZz"`) && strings.contains(text, `"tileset": "textures/floor.png"`), text)
	g2, _ := Gen_GraphParse(transmute([]u8)text, context.temp_allocator)
	testing.expect_value(t, Gen_FindNode(&g2, 4).layer, "FloorZz")
	// Duplicated with them.
	dup := Gen_DuplicateNode(&g, 4)
	testing.expect(t, dup.layer == "FloorZz" && dup.tileset == "textures/floor.png" && raw_data(dup.layer) != raw_data(Gen_FindNode(&g, 4).layer), "duplicate owns its strings")
	Gen_RemoveNode(&g, dup.id)

	// One generation: the output's tiles and each layer's.
	r, gerr := Gen_Generate(&g, 0, context.temp_allocator)
	testing.expectf(t, gerr == "", "generate: %s", gerr)
	testing.expect_value(t, len(r.layers), 2)
	testing.expect_value(t, r.layers[0].name, "FloorZz")
	testing.expect_value(t, r.tiles[0], 7) // (border)
	testing.expect_value(t, r.layers[0].tiles[0], -1)
	testing.expect_value(t, r.layers[0].tiles[1 * 6 + 1], 2) // (inside)

	// Into a map with a FloorZz next to it: both filled; "Missing" reported.
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("layers", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	root := CreateNode(scene.manager, Node)
	scene->addNode(root)
	ground := TileMapNode_Create(scene, "Ground", root)
	floor := TileMapNode_Create(scene, "FloorZz", root)
	ProcessNodeQueues(scene.manager, &game.gameContext)
	testing.expect(t, Gen_LayerTileMap(ground, "FloorZz") == floor, "the sibling")
	testing.expect(t, Gen_LayerTileMap(ground, "Ground") == nil, "not itself")
	why := Gen_ApplyResult(&r, ground, &game.gameContext, scene)
	testing.expect(t, strings.contains(why, `no TileMap "Missing" next to Ground`), why)
	testing.expect_value(t, TileMapNode_Get(ground, 0, 0), 7)
	testing.expect_value(t, TileMapNode_Get(floor, 1, 1), 2)
	testing.expect_value(t, TileMapNode_Get(floor, 0, 0), -1)
	testing.expect_value(t, floor.mapSize, [2]int{6, 4})
	free_all(context.temp_allocator)
}
