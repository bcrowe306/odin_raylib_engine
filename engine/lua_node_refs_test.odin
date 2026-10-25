package engine

import "core:testing"
import lua "lua54"

// Lua node references (NodeUserData): found by their live-table slot, with
// the id as the truth - a destroyed node is nil, its reused slot doesn't
// hand out another node, a node rebuilt with the same id is found again.
@(test)
test_lua_node_refs :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("refs", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	a := Node_CreateByTypeName(scene, "Node")
	a.name = "A"
	ProcessNodeQueues(scene.manager, &game.gameContext)
	L := game.scriptManager.L
	name_of :: proc(t: ^testing.T, L: ^lua.State, expr: cstring) -> string {
		if lua.L_dostring(L, expr) != 0 do testing.fail_now(t, string(lua.tostring(L, -1)))
		lua.getglobal(L, "r")
		defer lua.pop(L, 1)
		return string(lua.tostring(L, -1))
	}
	testing.expect_value(t, name_of(t, L, `ref = Scene.find_node("A"); r = tostring(ref:get_name())`), "A")
	idA := a.id

	// Destroyed: nil.
	RemoveNode(scene.manager, a)
	ProcessNodeQueues(scene.manager, &game.gameContext)
	testing.expect_value(t, name_of(t, L, `r = tostring(ref:get_name())`), "nil")

	// Its slot taken by another node: still nil.
	c := Node_CreateByTypeName(scene, "Node")
	c.name = "C"
	ProcessNodeQueues(scene.manager, &game.gameContext)
	testing.expect_value(t, name_of(t, L, `r = tostring(ref:get_name())`), "nil")
	testing.expect_value(t, name_of(t, L, `r = tostring(Scene.find_node("C"):get_name())`), "C")

	// A node rebuilt with the same id (a reloaded scene): found again, and
	// by its slot from then on.
	d := Node_CreateByTypeName(scene, "Node")
	d.name = "D"
	Node_Unregister(d)
	d.id = idA
	Node_Register(d)
	ProcessNodeQueues(scene.manager, &game.gameContext)
	testing.expect_value(t, name_of(t, L, `r = tostring(ref:get_name())`), "D")
	testing.expect_value(t, name_of(t, L, `r = tostring(ref:get_name())`), "D")
}
