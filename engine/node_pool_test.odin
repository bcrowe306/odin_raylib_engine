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

// Issue #82: pooled instances keep stale local resource copies.
// Test: damage a pooled instance's health, return it, take it again,
// and health is back to max (reloaded from file + on_load re-executed).
@(test)
test_pooled_instance_resource_reload :: proc(t: ^testing.T) {
	dir :: "test_pool_resource_project"
	defer os.remove_all(dir)
	_ = os.make_directory_all(dir + "/components")
	_ = os.make_directory_all(dir + "/scripts")
	_ = os.make_directory_all(dir + "/resources")

	healthClass := `
local Health = {}
Health.resource = { local_copy = true }
Health.properties = { max = { type = "int", default = 100 } }
function Health:on_load() self.current = self.max end
function Health:damage(n) self.current = self.current - n return self.current end
return Health
`
	_ = os.write_entire_file(dir + "/scripts/health.lua", transmute([]u8)healthClass)

	enemyScript := `
local Enemy = {}
Enemy.properties = {
    health = { type = "resource", class = "scripts/health.lua" },
}
return Enemy
`
	_ = os.write_entire_file(dir + "/scripts/enemy.lua", transmute([]u8)enemyScript)

	bossRes := `{"type": "resource", "script": "scripts/health.lua", "properties": {"max": 250}}`
	_ = os.write_entire_file(dir + "/resources/enemy_health.resource.json", transmute([]u8)bossRes)

	enemyComp := `{
  "type": "Node",
  "name": "Enemy",
  "script": { "path": "scripts/enemy.lua", "properties": { "health": "resources/enemy_health.resource.json" } }
}`
	_ = os.write_entire_file(dir + "/components/enemy.component.json", transmute([]u8)enemyComp)

	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	AssetManager_SetProjectDir(&game.assetManager, dir)

	scene := game->createScene("pool_res", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	L := game.scriptManager.L

	// Prewarm 1 enemy into the pool
	ok := lua.L_dostring(L, `Pool.prewarm("components/enemy.component.json", 1)`)
	if ok != 0 do testing.fail_now(t, string(lua.tostring(L, -1)))
	game->run(0.016)

	// Take the enemy: health should start at 250 (from on_load)
	ok = lua.L_dostring(L, `
e1 = Pool.take("components/enemy.component.json")
e1_script = e1:get_script()
h_init = e1_script.health.current
`)
	if ok != 0 do testing.fail_now(t, string(lua.tostring(L, -1)))
	game->run(0.016)

	lua.getglobal(L, "h_init")
	testing.expect_value(t, int(lua.tointeger(L, -1)), 250)
	lua.pop(L, 1)

	// Damage the enemy: health reduces to 150
	ok = lua.L_dostring(L, `
e1_script.health:damage(100)
h_damaged = e1_script.health.current
`)
	if ok != 0 do testing.fail_now(t, string(lua.tostring(L, -1)))
	lua.getglobal(L, "h_damaged")
	testing.expect_value(t, int(lua.tointeger(L, -1)), 150)
	lua.pop(L, 1)

	// Return to pool (destroy)
	ok = lua.L_dostring(L, `e1:destroy()`)
	if ok != 0 do testing.fail_now(t, string(lua.tostring(L, -1)))
	game->run(0.016)

	// Take again from the pool (same node reused)
	ok = lua.L_dostring(L, `
e2 = Pool.take("components/enemy.component.json")
e2_script = e2:get_script()
h_retaken = e2_script.health.current
`)
	if ok != 0 do testing.fail_now(t, string(lua.tostring(L, -1)))
	game->run(0.016)

	lua.getglobal(L, "e1")
	n1, ok1 := to_node_userdata(L, -1)
	lua.pop(L, 1)

	lua.getglobal(L, "e2")
	n2, ok2 := to_node_userdata(L, -1)
	lua.pop(L, 1)

	testing.expect(t, ok1 && ok2 && n1 == n2, "pooled node pointer reused")

	lua.getglobal(L, "h_retaken")
	testing.expect_value(t, int(lua.tointeger(L, -1)), 250) // Reset to 250!
	lua.pop(L, 1)
}

@(private = "file")
contains_str :: proc(s, sub: string) -> bool {
	for i := 0; i + len(sub) <= len(s); i += 1 do if s[i:i + len(sub)] == sub do return true
	return false
}
