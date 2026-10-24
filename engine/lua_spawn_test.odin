package engine

import "core:log"
import os "osx"
import "core:testing"
import lua "lua54"

// Spawning from Lua: Scene.instantiate puts a component instance under a
// parent at a position and returns its root; queue_free removes a node at
// the end of the frame.
@(test)
test_lua_spawning :: proc(t: ^testing.T) {
	dir :: "test_lua_spawn_project"
	defer os.remove_all(dir)
	_ = os.make_directory_all(dir + "/components")
	_ = os.write_entire_file(dir + "/components/bullet.component.json", transmute([]u8)string(`{"type": "Node", "name": "Bullet", "children": [{"type": "TimerNode", "name": "Life"}]}`))
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	AssetManager_SetProjectDir(&game.assetManager, dir)
	scene := game->createScene("spawn", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	gun := Node_CreateByTypeName(scene, "Node")
	gun.name = "Gun"
	ProcessNodeQueues(scene.manager, &game.gameContext)
	L := game.scriptManager.L
	ok := lua.L_dostring(L, `
local gun = Scene.find_node("Gun")
b = Scene.instantiate("components/bullet.component.json", gun, Vec2(5, 6))
b2 = Scene.instantiate("components/bullet.component.json", nil, 1, 2)
`)
	// A missing component logs an error (expected here): quiet for that call.
	logger := game.scriptManager.ctx.logger
	game.scriptManager.ctx.logger = log.nil_logger()
	ok |= lua.L_dostring(L, `missing = Scene.instantiate("components/nope.component.json")`)
	game.scriptManager.ctx.logger = logger
	if ok != 0 do testing.fail_now(t, string(lua.tostring(L, -1)))
	ProcessNodeQueues(scene.manager, &game.gameContext)
	b := Scene_FindNodeByName(scene, "Bullet")
	testing.expect(t, b != nil && GetParent(scene.manager, b) == gun && b.position == {5, 6}, "under the gun, at 5,6")
	lua.getglobal(L, "missing"); testing.expect(t, lua.isnil(L, -1), "missing: nil"); lua.pop(L, 1)
	count :: proc(scene: ^Scene) -> int {
		n := 0
		for x in scene.manager.nodes do if x != nil && x.name == "Bullet" && !x.removing do n += 1
		return n
	}
	testing.expect_value(t, count(scene), 2)
	ok = lua.L_dostring(L, `b:queue_free()`)
	testing.expect_value(t, ok, i32(0))
	testing.expect_value(t, count(scene), 1) // marked; gone after the frame
	ProcessNodeQueues(scene.manager, &game.gameContext)
	testing.expect_value(t, count(scene), 1)
}
