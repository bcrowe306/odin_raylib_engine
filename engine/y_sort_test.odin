package engine

import "core:strings"
import "core:testing"

// Draw order: a ySort node draws its children by Y (each with its subtree,
// nested sorts moving as one), ySortOffset moves the line, zIndex (relative
// to the parent) sorts the layer; saved with the scene.
@(test)
test_y_sort_and_z_index :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("ysort", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)

	mk :: proc(scene: ^Scene, name: string, y: f32, parent: ^Node = nil) -> ^Node {
		n := Node_CreateByTypeName(scene, "TextureNode", parent)
		n.name = name
		n.position = {0, y}
		return n
	}
	world := Node_CreateByTypeName(scene, "Node")
	world.name = "World"
	world.ySort = true
	tree := mk(scene, "Tree", 100, world)
	player := mk(scene, "Player", 50, world)
	sword := mk(scene, "Sword", -500, player) // a child: stays with Player
	rock := mk(scene, "Rock", 80, world)
	rock.ySortOffset = 40 // its feet: 120, below the tree
	camp := Node_CreateByTypeName(scene, "Node", world)
	camp.name = "Camp"
	camp.position = {0, 90}
	camp.ySort = true
	tentB := mk(scene, "TentB", 20, camp)
	tentA := mk(scene, "TentA", 10, camp)
	sky := mk(scene, "Sky", 0)
	sky.zIndex = -1 // drawn first though it comes last in the tree
	ProcessNodeQueues(scene.manager, &game.gameContext)
	Node_SetGlobalPositions(scene.manager, scene.rootNode)

	names :: proc(nodes: []^Node) -> string {
		sb := strings.builder_make(context.temp_allocator)
		for n, i in nodes {
			if i > 0 do strings.write_string(&sb, " ")
			strings.write_string(&sb, n.name)
		}
		return strings.to_string(sb)
	}
	b := Scene_CollectRenderables(scene)
	// Player (50) + Sword, Camp (90: TentA 10, TentB 20 sorted inside), Tree (100), Rock (80+40).
	testing.expect_value(t, names(b[.Layer1][:]), "Sky Player Sword TentA TentB Tree Rock")
	_ = sword; _ = tree; _ = tentA; _ = tentB

	// Moving changes the order next frame.
	player.position.y = 200
	Node_SetGlobalPositions(scene.manager, scene.rootNode)
	b = Scene_CollectRenderables(scene)
	testing.expect_value(t, names(b[.Layer1][:]), "Sky TentA TentB Tree Rock Player Sword")

	// Off: the tree order.
	world.ySort = false
	b = Scene_CollectRenderables(scene)
	testing.expect_value(t, names(b[.Layer1][:]), "Sky Tree Player Sword Rock TentA TentB")
	world.ySort = true

	json := Scene_SerializeToJSON(scene)
	defer delete(json)
	testing.expect(t, strings.contains(json, `"y_sort": true`) && strings.contains(json, `"y_sort_offset": 40`) && strings.contains(json, `"z_index": -1`), json)
	p, ok := Node_BaseProperty(rock, "ySortOffset")
	testing.expect(t, ok && p.kind == .Float, "ySortOffset is a property")
}
