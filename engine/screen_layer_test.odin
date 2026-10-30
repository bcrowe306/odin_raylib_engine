package engine

import "core:strings"
import "core:testing"
import rl "vendor:raylib"

// #175: Screen Layer - anchored to the frame (not its parent), drawn apart
// from the world; the editor's mapping puts it over the camera frame.
@(test)
test_screen_layer :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("screen_layer", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	ctx := &game.gameContext
	m := scene.manager

	world := Node_CreateByTypeName(scene, "Node")
	world.position = {5000, 5000} // (its parent's place doesn't matter)
	hud := cast(^ScreenLayerNode)Node_CreateByTypeName(scene, "ScreenLayerNode", world)
	hud.anchor = .TopRight
	hud.position = {-100, 20}
	score := Node_CreateByTypeName(scene, "TextureNode", hud)
	score.position = {10, 0}
	_ = Node_CreateByTypeName(scene, "TextureNode", world) // (a world sprite)
	ProcessNodeQueues(m, ctx)

	// The game: the frame.
	game.virtualSize = {640, 380}
	m.screen = Screen_MappingForGame(ctx)
	Node_SetGlobalPositions(m, scene.rootNode)
	testing.expect_value(t, hud.globalPosition, [2]f32{540, 20})
	testing.expect_value(t, score.globalPosition, [2]f32{550, 20})
	testing.expect_value(t, Node_ComputeWorldPosition(m, score), [2]f32{550, 20})
	// Expand grew the frame: still 100 from the right edge.
	game.virtualSize = {676, 380}
	m.screen = Screen_MappingForGame(ctx)
	Node_SetGlobalPositions(m, scene.rootNode)
	testing.expect_value(t, hud.globalPosition, [2]f32{576, 20})

	// The editor: over the camera's view (centre 1000, 500; zoom 2).
	cam := rl.Camera2D{offset = {320, 190}, target = {1000, 500}, zoom = 2}
	m.screen = Screen_MappingForCamera(cam, 640, 380)
	Node_SetGlobalPositions(m, scene.rootNode)
	// The view's top-left is (840, 405); the anchor is 640 screen px right = 320 world.
	testing.expectf(t, abs(hud.globalPosition.x - (840 + (640 - 100) * 0.5)) < 0.01 && abs(hud.globalPosition.y - (405 + 20 * 0.5)) < 0.01, "over the camera frame: %v", hud.globalPosition)
	testing.expect_value(t, hud.globalScale, [2]f32{0.5, 0.5})
	// Moved in the editor: the position that puts it at a world point.
	testing.expect_value(t, Node_WorldToParent(m, hud, hud.globalPosition), [2]f32{-100, 20})
	testing.expect_value(t, Node_ParentToWorld(m, hud, {-100, 20}), hud.globalPosition)

	// Drawn apart from the world.
	screen: [RenderLayer][dynamic]^Node
	worldBuckets := Scene_CollectRenderables(scene, &screen)
	inWorld, inScreen := false, false
	for b in worldBuckets do for n in b do if n == score do inWorld = true
	for b in screen do for n in b do if n == score do inScreen = true
	testing.expect(t, !inWorld && inScreen, "the HUD's sprite: on the screen, not in the world")
	all := Scene_CollectRenderables(scene)
	found := false
	for b in all do for n in b do if n == score do found = true
	testing.expect(t, found, "(without the split: with the rest)")

	// Saved and loaded: the anchor.
	saved := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expectf(t, strings.contains(saved, `"type": "ScreenLayerNode"`) && strings.contains(saved, `"anchor": "TopRight"`), "saved: %s", saved)
	again := game->createScene("screen_layer2", false)
	_ = Scene_InstantiateFromJSON(again, transmute([]u8)saved, ctx)
	ProcessNodeQueues(again.manager, ctx)
	for n in again.manager.nodes do if n != nil && n.typeId == ScreenLayerNode {
		testing.expect_value(t, (cast(^ScreenLayerNode)n).anchor, Screen_Anchor.TopRight)
	}
}
