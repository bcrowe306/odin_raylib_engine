package engine

import "core:testing"
import rl "vendor:raylib"

@(test)
test_view_culling :: proc(t: ^testing.T) {
	// Camera view rectangles (rotation enlarges the box).
	cam := rl.Camera2D{offset = {400, 300}, target = {1000, 500}, zoom = 2}
	v := Camera2D_ViewRect(cam, 800, 600)
	testing.expectf(t, abs(v.x - 800) < 0.01 && abs(v.y - 350) < 0.01 && abs(v.width - 400) < 0.01 && abs(v.height - 300) < 0.01, "view rect: %v", v)
	cam.rotation = 90
	v = Camera2D_ViewRect(cam, 800, 600)
	testing.expectf(t, abs(v.width - 300) < 0.01 && abs(v.height - 400) < 0.01, "rotated view rect: %v", v)

	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("cull", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)

	// Sprite bounds follow size, scale, origin and rotation.
	dummy := new(Texture)
	defer free(dummy)
	tn := cast(^TextureNode)Node_CreateByTypeName(scene, "TextureNode")
	tn.texture = dummy
	tn.size = {100, 50}
	tn.position = {0, 0}
	far := cast(^TextureNode)Node_CreateByTypeName(scene, "TextureNode")
	far.texture = dummy
	far.size = {100, 50}
	far.position = {5000, 5000}
	rotated := cast(^TextureNode)Node_CreateByTypeName(scene, "TextureNode")
	rotated.texture = dummy
	rotated.size = {200, 10}
	rotated.rotation = 90
	rotated.position = {-300, 0}
	tm := cast(^TileMapNode)Node_CreateByTypeName(scene, "TileMapNode")
	tm.position = {-2000, -2000}
	tm.tileSize = {16, 16}
	tm.mapSize = {10, 10}
	ProcessNodeQueues(scene.manager, &game.gameContext)
	Node_SetGlobalPositions(scene.manager, scene.rootNode)

	r, ok := Node_RenderBounds(tn)
	testing.expectf(t, ok && r == {-50, -25, 100, 50}, "centred sprite bounds: %v", r)
	r, ok = Node_RenderBounds(rotated)
	testing.expectf(t, ok && abs(r.width - 10) < 0.01 && abs(r.height - 200) < 0.01, "rotated sprite bounds: %v", r)

	// A 600x400 view around the origin: the far sprite and the tile map are
	// culled; the rotated one (x -305..-295) is just inside.
	Scene_RenderAllLayers(scene, &game.gameContext, 0, rl.Rectangle{-320, -200, 640, 400})
	testing.expectf(t, renderStats.culled == 2, "culled far sprite and tile map: %v", renderStats)
	testing.expect(t, !renderView.active, "view cleared after rendering")
	Scene_RenderAllLayers(scene, &game.gameContext, 0)
	testing.expect_value(t, renderStats.culled, 0)
}
