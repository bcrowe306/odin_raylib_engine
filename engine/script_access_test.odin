package engine

import "core:testing"
import lua "vendor:lua/5.4"

// Another node's script: "script.<name>" through get/set_property, and
// node:get_script() for its fields and methods.
@(test)
test_script_access_other_node :: proc(t: ^testing.T) {
	ScriptVFS_RegisterEmbedded("access_enemy.lua", `
local E = {}
E.properties = {
    health = { type = "float", default = 100 },
    aim    = { type = "vector2", default = {0, 0} },
}
function E:take_damage(n) self.health = self.health - n; return self.health end
return E
`)
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("access", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	enemy := Node_CreateByTypeName(scene, "Node")
	enemy.name = "Enemy"
	enemy.gameContext = &game.gameContext
	Script_AttachToNode(enemy, "access_enemy.lua", nil, &game.scriptManager)
	plain := Node_CreateByTypeName(scene, "Node")
	plain.name = "Plain"
	ProcessNodeQueues(scene.manager, &game.gameContext)

	L := game.scriptManager.L
	ok := lua.L_dostring(L, `
local e = Scene.find_node("Enemy")
r1 = e:get_property("script.health")
e:set_property("script.health", 40)
r2 = e:get_script().health
r3 = e:get_script():take_damage(15)
r4 = e:get_property("script.health")
e:set_property("script.aim", 3, 4)
local aim = e:get_property("script.aim")
r5 = aim[1] + aim[2]
e:set_property("script.mood", "angry")   -- any field the script keeps
r6 = e:get_script().mood
r7 = Scene.find_node("Plain"):get_script() == nil
r8 = Scene.find_node("Plain"):get_property("script.health") == nil
e:set_property("rotation", 30)
e:set_property("position", 5, 6)
local pos = e:get_property("position")
r10 = e:get_property("rotation") + pos[1] + pos[2]
r9 = pcall(function() Scene.find_node("Plain"):set_property("script.health", 1) end)
`)
	if ok != 0 {
		testing.fail_now(t, string(lua.tostring(L, -1)))
	}
	num :: proc(L: ^lua.State, g: cstring) -> f64 {
		lua.getglobal(L, g)
		defer lua.pop(L, 1)
		return f64(lua.tonumber(L, -1))
	}
	boolean :: proc(L: ^lua.State, g: cstring) -> bool {
		lua.getglobal(L, g)
		defer lua.pop(L, 1)
		return bool(lua.toboolean(L, -1))
	}
	testing.expect_value(t, num(L, "r1"), 100)
	testing.expect_value(t, num(L, "r2"), 40)
	testing.expect_value(t, num(L, "r3"), 25)
	testing.expect_value(t, num(L, "r4"), 25)
	testing.expect_value(t, num(L, "r5"), 7)
	lua.getglobal(L, "r6")
	testing.expect_value(t, string(lua.tostring(L, -1)), "angry")
	lua.pop(L, 1)
	testing.expect(t, boolean(L, "r7") && boolean(L, "r8"), "no script: nil")
	testing.expect(t, !boolean(L, "r9"), "set on a node without a script is an error")
	testing.expect_value(t, num(L, "r10"), 41) // the Transform rows' paths
}
