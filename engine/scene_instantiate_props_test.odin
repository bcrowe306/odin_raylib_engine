package engine

import os "osx"
import "core:testing"
import lua "lua54"

// Issue #81: Scene.instantiate with property values; Lua instance queries.
// Verifies:
// 1. Scene.instantiate(path, parent, pos, { speed = 300 }) applies properties before ready() runs.
// 2. node:get_component() returns component path on root, nil on non-root or unlinked node.
// 3. node:get_instance_root() returns root on root and children, nil on unlinked node.
@(test)
test_scene_instantiate_props_and_queries :: proc(t: ^testing.T) {
	dir :: "test_instantiate_props_project"
	defer os.remove_all(dir)
	_ = os.make_directory_all(dir + "/components")
	_ = os.make_directory_all(dir + "/scripts")

	// Script that records speed in ready()
	bulletScript := `local B = {}
B.properties = {
    speed = { type = "float", default = 100 },
    tag = { type = "string", default = "default" },
}
function B:ready()
    ready_speed = self.speed
    ready_tag = self.tag
end
return B
`
	_ = os.write_entire_file(dir + "/scripts/bullet.lua", transmute([]u8)bulletScript)

	bulletComp := `{
  "type": "Node",
  "name": "Bullet",
  "script": { "path": "scripts/bullet.lua" },
  "children": [
    { "type": "Node", "name": "Tip" }
  ]
}`
	_ = os.write_entire_file(dir + "/components/bullet.component.json", transmute([]u8)bulletComp)

	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	AssetManager_SetProjectDir(&game.assetManager, dir)

	scene := game->createScene("test", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	L := game.scriptManager.L

	// 1. Test Scene.instantiate with 4th arg properties: pos as Vec2, props as table
	ok := lua.L_dostring(L, `
ready_speed = nil
ready_tag = nil
b1 = Scene.instantiate("components/bullet.component.json", nil, Vec2(10, 20), { speed = 300, tag = "fast" })
`)
	if ok != 0 do testing.fail_now(t, string(lua.tostring(L, -1)))

	// Run 1 frame so ready() executes for newly added nodes
	game->run(0.016)

	lua.getglobal(L, "ready_speed")
	testing.expect_value(t, f32(lua.tonumber(L, -1)), f32(300))
	lua.pop(L, 1)

	lua.getglobal(L, "ready_tag")
	testing.expect_value(t, string(lua.tostring(L, -1)), "fast")
	lua.pop(L, 1)

	// 2. Test Scene.instantiate with x, y as numbers and 5th arg properties:
	ok = lua.L_dostring(L, `
ready_speed = nil
ready_tag = nil
b2 = Scene.instantiate("components/bullet.component.json", nil, 5, 15, { speed = 450, tag = "sniper" })
`)
	if ok != 0 do testing.fail_now(t, string(lua.tostring(L, -1)))
	game->run(0.016)

	lua.getglobal(L, "ready_speed")
	testing.expect_value(t, f32(lua.tonumber(L, -1)), f32(450))
	lua.pop(L, 1)

	lua.getglobal(L, "ready_tag")
	testing.expect_value(t, string(lua.tostring(L, -1)), "sniper")
	lua.pop(L, 1)

	// 3. Test Scene.instantiate with pos omitted (props table passed as 3rd arg):
	ok = lua.L_dostring(L, `
ready_speed = nil
ready_tag = nil
b3 = Scene.instantiate("components/bullet.component.json", nil, { speed = 600, tag = "laser" })
`)
	if ok != 0 do testing.fail_now(t, string(lua.tostring(L, -1)))
	game->run(0.016)

	lua.getglobal(L, "ready_speed")
	testing.expect_value(t, f32(lua.tonumber(L, -1)), f32(600))
	lua.pop(L, 1)

	lua.getglobal(L, "ready_tag")
	testing.expect_value(t, string(lua.tostring(L, -1)), "laser")
	lua.pop(L, 1)

	// 4. Test node:get_component() and node:get_instance_root()
	ok = lua.L_dostring(L, `
comp_root_path = b1:get_component()
local tip = b1:get_child("Tip")
comp_child_path = tip:get_component()

root_from_root = b1:get_instance_root()
root_from_child = tip:get_instance_root()

local plain = Scene.create_node("Node", "Plain")
comp_plain_path = plain:get_component()
root_from_plain = plain:get_instance_root()
`)
	if ok != 0 do testing.fail_now(t, string(lua.tostring(L, -1)))

	lua.getglobal(L, "comp_root_path")
	testing.expect_value(t, string(lua.tostring(L, -1)), "components/bullet.component.json")
	lua.pop(L, 1)

	lua.getglobal(L, "comp_child_path")
	testing.expect(t, lua.isnil(L, -1), "child get_component should be nil")
	lua.pop(L, 1)

	lua.getglobal(L, "comp_plain_path")
	testing.expect(t, lua.isnil(L, -1), "plain node get_component should be nil")
	lua.pop(L, 1)

	lua.getglobal(L, "root_from_root")
	r1, ok1 := to_node_userdata(L, -1)
	testing.expect(t, ok1 && r1 != nil && r1.name == "Bullet", "root from root should return b1")
	lua.pop(L, 1)

	lua.getglobal(L, "root_from_child")
	r2, ok2 := to_node_userdata(L, -1)
	testing.expect(t, ok2 && r2 != nil && r2 == r1, "root from child should return b1")
	lua.pop(L, 1)

	lua.getglobal(L, "root_from_plain")
	testing.expect(t, lua.isnil(L, -1), "root from plain unlinked node should be nil")
	lua.pop(L, 1)
}
