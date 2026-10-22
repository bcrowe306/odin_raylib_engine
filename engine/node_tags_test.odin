package engine

import "core:strings"
import "core:testing"
import lua "vendor:lua/5.4"

@(test)
test_node_tags :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("tags", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)

	a := Node_CreateByTypeName(scene, "Node")
	a.name = "A"
	b := Node_CreateByTypeName(scene, "Node", a)
	b.name = "B"
	c := Node_CreateByTypeName(scene, "Node")
	c.name = "C"
	ProcessNodeQueues(scene.manager, &game.gameContext)
	testing.expect(t, Node_AddTag(a, "enemy") && Node_AddTag(b, " enemy ") && Node_AddTag(b, "boss"), "added")
	testing.expect(t, !Node_AddTag(a, "enemy") && !Node_AddTag(a, ""), "no duplicates or empty tags")
	found := Scene_FindByTag(scene, "enemy")
	testing.expect(t, len(found) == 2 && found[0] == a && found[1] == b, "tree order")

	// Lua.
	L := game.scriptManager.L
	ok := lua.L_dostring(L, `
local c = Scene.find_node("C")
c:add_tag("pickup")
n_enemies = #Scene.find_by_tag("enemy")
b_boss = tostring(Scene.find_node("B"):has_tag("boss"))
Scene.find_node("B"):remove_tag("boss")
tags = table.concat(Scene.find_node("B"):get_tags(), ",")
`)
	testing.expect(t, ok == 0, "lua ran")
	lua.getglobal(L, "n_enemies")
	testing.expect_value(t, lua.tointeger(L, -1), 2)
	lua.getglobal(L, "b_boss")
	testing.expect_value(t, string(lua.tostring(L, -1)), "true")
	lua.getglobal(L, "tags")
	testing.expect_value(t, string(lua.tostring(L, -1)), "enemy")
	lua.pop(L, 3)
	testing.expect(t, Node_HasTag(c, "pickup") && !Node_HasTag(b, "boss"), "lua edits")

	// Saved and loaded.
	text := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expect(t, strings.contains(text, `"tags": ["pickup"]`), "tags saved")
	s2 := game->createScene("tags2", false)
	Scene_InstantiateFromJSON(s2, transmute([]u8)text, &game.gameContext)
	ProcessNodeQueues(s2.manager, &game.gameContext)
	testing.expect_value(t, len(Scene_FindByTag(s2, "enemy")), 2)
	c2 := Scene_FindNodeByName(s2, "C")
	testing.expect(t, c2 != nil && Node_HasTag(c2, "pickup"), "loaded")
}
