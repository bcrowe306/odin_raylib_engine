package engine

import "core:testing"
import lua "lua54"

// A `type = "node"` property: saved as a path from the script's node, the
// node itself in Lua - resolved before ready(), and on a live edit.
@(test)
test_script_node_property :: proc(t: ^testing.T) {
	ScriptVFS_RegisterEmbedded("node_prop.lua", `
local S = {}
S.properties = { target = { type = "node" } }
function S:ready() seen = self.target and self.target:get_name() or "nil" end
return S
`)
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("nodeprop", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	root := Node_CreateByTypeName(scene, "Node")
	root.name = "Root"
	hero := Node_CreateByTypeName(scene, "Node", root)
	hero.name = "Hero"
	other := Node_CreateByTypeName(scene, "Node", root)
	other.name = "Other"
	for n in ([]^Node{root, hero, other}) do n.gameContext = &game.gameContext
	overrides := make(map[string]ScriptValue)
	defer delete(overrides)
	overrides["target"] = {type = .String, valString = "../Other"}
	inst := Script_AttachToNode(hero, "node_prop.lua", overrides, &game.scriptManager)
	testing.expect(t, inst != nil, "attached")
	ProcessNodeQueues(scene.manager, &game.gameContext)
	game->run(0.016)
	L := game.scriptManager.L
	lua.getglobal(L, "seen")
	testing.expect_value(t, string(lua.tostring(L, -1)), "Other")
	lua.pop(L, 1)
	testing.expect_value(t, inst.properties["target"].valString, "../Other") // saved as the path

	// A live edit points it elsewhere; a missing path gives nil.
	ScriptInstance_SetProperty(inst, "target", {type = .String, valString = "../Hero"}, &game.scriptManager)
	ok := lua.L_dostring(L, `n = Scene.find_node("Hero"):get_script().target; name = n and n:get_name() or "nil"`)
	testing.expect_value(t, ok, i32(0))
	lua.getglobal(L, "name")
	testing.expect_value(t, string(lua.tostring(L, -1)), "Hero")
	lua.pop(L, 1)
	ScriptInstance_SetProperty(inst, "target", {type = .String, valString = "../Nobody"}, &game.scriptManager)
	_ = lua.L_dostring(L, `n2 = Scene.find_node("Hero"):get_script().target`)
	lua.getglobal(L, "n2")
	testing.expect(t, lua.isnil(L, -1), "missing: nil")
	lua.pop(L, 1)
}
