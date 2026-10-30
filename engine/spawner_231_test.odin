package engine

import os "osx"
import "core:testing"
import lua "lua54"

// #231: resource and node properties set on a spawned node before its
// ready() keep their values; set_spawn_callback runs for every spawn (by
// call, Auto Spawn, pooled) before ready(), with {component, index};
// spawn_info(node) tells the entry; get_component works on spawned roots.
@(test)
test_spawner_setup_callback_info :: proc(t: ^testing.T) {
	dir :: "test_spawner_231_project"
	defer os.remove_all(dir)
	_ = os.make_directory_all(dir + "/components")
	_ = os.make_directory_all(dir + "/scripts")
	_ = os.make_directory_all(dir + "/resources")
	write :: proc(path, text: string) {_ = os.write_entire_file(path, transmute([]u8)text)}
	write(dir + "/scripts/attack.lua", `
local Attack = {}
Attack.resource = {}
Attack.properties = { power = { type = "int", default = 1 } }
return Attack
`)
	write(dir + "/resources/heavy.resource.json", `{"type": "resource", "script": "scripts/attack.lua", "properties": {"power": 9}}`)
	write(dir + "/resources/light.resource.json", `{"type": "resource", "script": "scripts/attack.lua", "properties": {"power": 2}}`)
	write(dir + "/scripts/bullet.lua", `
local Bullet = {}
Bullet.properties = {
    speed = { type = "float", default = 1 },
    attack = { type = "resource", class = "scripts/attack.lua" },
    target = { type = "node" },
}
function Bullet:ready()
    seen = seen or {}
    seen[#seen + 1] = { speed = self.speed, power = self.attack and self.attack.power or -1, target = self.target and self.target.name or "" }
end
return Bullet
`)
	write(dir + "/components/bullet.component.json", `{"type": "Node", "name": "Bullet", "script": {"path": "scripts/bullet.lua", "properties": {"attack": "resources/light.resource.json"}}}`)
	write(dir + "/components/rock.component.json", `{"type": "Node", "name": "Rock", "script": {"path": "scripts/bullet.lua"}}`)

	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	AssetManager_SetProjectDir(&game.assetManager, dir)
	scene := game->createScene("spawn231", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	gun := SpawnerNode_Create(scene, "Gun")
	SpawnerNode_AddEntry(gun, "components/bullet.component.json")
	SpawnerNode_AddEntry(gun, "components/rock.component.json")
	gun.mode = .All
	aim := Node_CreateByTypeName(scene, "Node")
	aim.name = "Aim"
	game->run(0.016)
	L := game.scriptManager.L
	run :: proc(t: ^testing.T, L: ^lua.State, code: cstring) {
		if lua.L_dostring(L, code) != 0 do testing.fail_now(t, string(lua.tostring(L, -1)))
	}

	// 1. Set right after spawn(): plain, resource and node properties reach ready().
	run(t, L, `
local gun = Scene.find_node("Gun")
for _, b in ipairs(gun:spawn()) do
    local s = b:get_script()
    s.speed = 7
    s.attack = Resource.load("resources/heavy.resource.json")
    s.target = Scene.find_node("Aim")
end
`)
	game->run(0.016)
	run(t, L, `
first = seen[1]
ok1 = #seen == 2 and seen[1].speed == 7 and seen[1].power == 9 and seen[1].target == "Aim" and seen[2].power == 9
`)
	run(t, L, `dbg = #seen .. " " .. tostring(seen[1] and seen[1].speed) .. " " .. tostring(seen[1] and seen[1].power) .. " " .. tostring(seen[1] and seen[1].target) .. " | " .. tostring(seen[2] and seen[2].power)`)
	lua.getglobal(L, "dbg")
	dbg := string(lua.tostring(L, -1))
	lua.pop(L, 1)
	lua.getglobal(L, "ok1")
	testing.expectf(t, bool(lua.toboolean(L, -1)), "speed, attack and target set before ready() are kept: %s", dbg)
	lua.pop(L, 1)

	// 2. The callback: every spawn (Auto Spawn here), before ready(), with the entry.
	run(t, L, `
seen = {}
infos = {}
local gun = Scene.find_node("Gun")
gun:set_spawn_callback(function(node, info, spawner)
    infos[#infos + 1] = info.component .. "#" .. info.index .. "@" .. spawner.name
    node:get_script().speed = info.index * 10
end)
`)
	gun.autoSpawn, gun.interval = true, 0.01
	game->run(0.02)
	gun.autoSpawn = false
	game->run(0.016)
	run(t, L, `
ok2 = #infos >= 2 and infos[1] == "components/bullet.component.json#1@Gun" and infos[2] == "components/rock.component.json#2@Gun"
    and seen[1].speed == 10 and seen[2].speed == 20
`)
	lua.getglobal(L, "ok2")
	testing.expect(t, bool(lua.toboolean(L, -1)), "the callback ran for Auto Spawn, with component and index, before ready()")
	lua.pop(L, 1)

	// 3. spawn_info and get_component on spawned roots; nil clears the callback.
	run(t, L, `
local gun = Scene.find_node("Gun")
gun:set_spawn_callback(nil)
local n = #infos
local made = gun:spawn()
local info = gun:spawn_info(made[2])
ok3 = #infos == n and info and info.index == 2 and info.component == "components/rock.component.json"
    and made[2]:get_component() == "components/rock.component.json"
    and gun:spawn_info(Scene.find_node("Aim")) == nil
`)
	lua.getglobal(L, "ok3")
	testing.expect(t, bool(lua.toboolean(L, -1)), "spawn_info / get_component tell the entry; nil cleared the callback")
	lua.pop(L, 1)

	// 4. Pooled: the callback runs on every take.
	run(t, L, `
local gun = Scene.find_node("Gun")
pooled = 0
gun:set_spawn_callback(function(node, info) pooled = pooled + 1 end)
`)
	gun.usePool = true
	SpawnerNode_Spawn(gun, &game.gameContext)
	game->run(0.016)
	lua.getglobal(L, "pooled")
	testing.expect_value(t, int(lua.tointeger(L, -1)), 2)
	lua.pop(L, 1)
}
