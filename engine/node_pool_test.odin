package engine

import os "osx"
import "core:testing"
import b2 "vendor:box2d"
import lua "lua54"

// Node pools: take makes or reuses instances (parked ones disabled with
// their bodies off), destroy() returns a pooled node, on_spawn / on_despawn
// run, max caps, a removed parent frees its pooled children (the pool
// forgets them), stats, and unloading the scene frees the pools.
@(test)
test_node_pool :: proc(t: ^testing.T) {
	dir :: "test_node_pool_project"
	defer os.remove_all(dir)
	_ = os.make_directory_all(dir + "/components")
	_ = os.write_entire_file(dir + "/components/shot.component.json", transmute([]u8)string(`{"type": "DynamicBodyNode", "name": "Shot", "script": {"path": "pool_shot.lua"}, "children": [{"type": "Node", "name": "Glow"}]}`))
	ScriptVFS_RegisterEmbedded("pool_shot.lua", `
local S = {}
S.properties = {}
function S:ready() readies = (readies or 0) + 1 end
function S:on_spawn() spawns = (spawns or 0) + 1; self.life = 3 end
function S:on_despawn() despawns = (despawns or 0) + 1 end
return S
`)
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	AssetManager_SetProjectDir(&game.assetManager, dir)
	scene := game->createScene("pool", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	gun := Node_CreateByTypeName(scene, "Node")
	gun.name = "Gun"
	gun.position = {100, 0}
	ProcessNodeQueues(scene.manager, &game.gameContext)
	L := game.scriptManager.L
	run :: proc(t: ^testing.T, L: ^lua.State, code: cstring) {
		if lua.L_dostring(L, code) != 0 do testing.fail_now(t, string(lua.tostring(L, -1)))
	}
	geti :: proc(L: ^lua.State, name: cstring) -> int {
		lua.getglobal(L, name)
		defer lua.pop(L, 1)
		return int(lua.tointeger(L, -1))
	}
	path :: "components/shot.component.json"

	run(t, L, `Pool.prewarm("components/shot.component.json", 2)`)
	pool := Pool_Get(scene, path)
	testing.expect(t, pool.created == 2 && len(pool.free) == 2 && pool.active == 0, "prewarmed 2, parked")
	game->run(0.016)
	// Take: a parked one, under the gun, at 5,0 (world 105,0); on_spawn once.
	run(t, L, `a = Pool.take("components/shot.component.json", Scene.find_node("Gun"), 5, 0)`)
	game->run(0.016)
	lua.getglobal(L, "a")
	a, aok := to_node_userdata(L, -1)
	lua.pop(L, 1)
	testing.expect(t, aok && a.enabled && GetParent(scene.manager, a) == gun && a.globalPosition == {105, 0}, "taken under the gun")
	testing.expect(t, pool.created == 2 && pool.active == 1 && len(pool.free) == 1, "reused a parked one")
	testing.expect_value(t, geti(L, "spawns"), 1)
	body := Physics_BodyOf(a)
	testing.expect(t, !b2.Body_IsValid(body) || b2.Body_IsEnabled(body), "its body on")

	// destroy() returns it: disabled, parked, body off, on_despawn.
	run(t, L, `a:destroy()`)
	testing.expect(t, !a.enabled && !a.removing && len(pool.free) == 2 && pool.active == 0, "returned, not removed")
	testing.expect_value(t, geti(L, "despawns"), 1)
	if b2.Body_IsValid(body) do testing.expect(t, !b2.Body_IsEnabled(body), "its body off while parked")
	game->run(0.016)
	testing.expect(t, Node_IsAlive(a), "still alive after the frame")

	// The cap: max 3 -> three takes, the fourth is nil.
	run(t, L, `
Pool.set_max("components/shot.component.json", 3)
t1 = Pool.take("components/shot.component.json")
t2 = Pool.take("components/shot.component.json")
t3 = Pool.take("components/shot.component.json")
t4 = Pool.take("components/shot.component.json")
active, parked, made = Pool.stats("components/shot.component.json")`)
	lua.getglobal(L, "t4")
	testing.expect(t, lua.isnil(L, -1), "at the cap: nil")
	lua.pop(L, 1)
	testing.expect(t, geti(L, "active") == 3 && geti(L, "parked") == 0 && geti(L, "made") == 3, "stats")
	game->run(0.016)
	testing.expect_value(t, geti(L, "spawns"), 4)

	// A pooled node under a removed parent is freed with it; the pool forgets it.
	run(t, L, `Pool.release(t1); t5 = Pool.take("components/shot.component.json", Scene.find_node("Gun"))`)
	RemoveNode(scene.manager, gun)
	game->run(0.016)
	testing.expect(t, pool.created == 2 && pool.active == 2, "the one under the gun was forgotten")
	for f in pool.free do testing.expect(t, Node_IsAlive(f), "parked ones alive")

	// Saved scenes skip pooled instances; unloading frees the pools.
	json := Scene_SerializeToJSON(scene)
	defer delete(json)
	testing.expect(t, !contains_str(json, `"Shot"`), "pooled instances aren't saved")
	Scene_Unload(scene, &game.gameContext)
	testing.expect(t, len(scene.pools) == 0, "pools freed on unload")
}

@(private = "file")
contains_str :: proc(s, sub: string) -> bool {
	for i := 0; i + len(sub) <= len(s); i += 1 do if s[i:i + len(sub)] == sub do return true
	return false
}
