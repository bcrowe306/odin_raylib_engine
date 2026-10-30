package engine

import "core:testing"

// #192: a component made from scratch - just its root's type and name; it
// loads as that type with the type's defaults.
@(test)
test_component_new_json :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("component_new", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	json := Component_NewJSON("KinematicBodyNode", "Enemy \"A\"", context.temp_allocator)
	node := Scene_InstantiateNodeFromJSON(scene, transmute([]u8)json, scene.rootNode, &game.gameContext)
	if !testing.expect(t, node != nil, "loads") do return
	testing.expect(t, node.typeId == KinematicBodyNode, "the root's type")
	testing.expect_value(t, node.name, `Enemy "A"`)
	testing.expect_value(t, Component_NewJSON("NoSuchNode", "X", context.temp_allocator), "")
}
