package engine

import os "osx"
import "core:strings"
import "core:testing"
import lua "lua54"

// Resources (script_resources.odin): classes, files, shared / scoped
// tables, on_load, duplicate, hot reload, release.

@(private = "file")
HEALTH_CLASS :: `
---@class Health
local Health = {}
Health.resource = { local_copy = true }
Health.properties = {
    max   = { type = "int", default = 100 },
    regen = { type = "float", default = 0 },
    tag   = { type = "string", default = "none" },
    drops = { type = "array", of = "int", default = {1, 2} },
}
function Health:on_load()
    loads = (loads or 0) + 1
    self.current = self.max
end
function Health:damage(n)
    self.current = math.max(0, self.current - n)
    return self.current
end
return Health
`

@(private = "file")
res_game :: proc() -> ^Game {
	ScriptVFS_RegisterEmbedded("res_test/health.lua", HEALTH_CLASS)
	ScriptVFS_RegisterEmbedded("res_test/plain.lua", `local P = {} P.properties = { x = { type = "int", default = 1 } } return P`)
	ScriptVFS_RegisterEmbedded("res_test/boss.resource.json", `{"type": "resource", "script": "res_test/health.lua", "properties": {"max": 250, "tag": "boss"}}`)
	ScriptVFS_RegisterEmbedded("res_test/grunt.resource.json", `{"type": "resource", "script": "res_test/health.lua"}`)
	ScriptVFS_RegisterEmbedded("res_test/not_class.resource.json", `{"type": "resource", "script": "res_test/plain.lua"}`)
	ScriptVFS_RegisterEmbedded("res_test/bad_type.resource.json", `{"type": "scene", "script": "res_test/health.lua"}`)
	game := new(Game)
	InitializeGame(game)
	return game
}

// run runs Lua; fails the test on an error.
@(private = "file")
run :: proc(t: ^testing.T, L: ^lua.State, code: string) -> bool {
	if lua.L_dostring(L, strings.clone_to_cstring(code, context.temp_allocator)) != 0 {
		testing.expectf(t, false, "lua: %s", lua.tostring(L, -1))
		lua.pop(L, 1)
		return false
	}
	return true
}

@(private = "file")
global_int :: proc(L: ^lua.State, name: cstring) -> int {
	lua.getglobal(L, name)
	defer lua.pop(L, 1)
	return int(lua.tointeger(L, -1))
}

@(private = "file")
global_bool :: proc(L: ^lua.State, name: cstring) -> bool {
	lua.getglobal(L, name)
	defer lua.pop(L, 1)
	return bool(lua.toboolean(L, -1))
}

@(test)
test_resource_class_marker :: proc(t: ^testing.T) {
	game := res_game()
	defer game->terminate()
	mgr := &game.scriptManager
	ScriptVFS_RegisterEmbedded("res_test/shared_class.lua", `local S = {} S.resource = {} return S`)
	ScriptVFS_RegisterEmbedded("res_test/bad_marker.lua", `local S = {} S.resource = true return S`)

	h, _ := ScriptManager_LoadModule("res_test/health.lua", mgr)
	testing.expect(t, h != nil && h.isResourceClass && h.resourceLocalCopy, "marked, local_copy = true")
	s, _ := ScriptManager_LoadModule("res_test/shared_class.lua", mgr)
	testing.expect(t, s != nil && s.isResourceClass && !s.resourceLocalCopy, "marked, shared by default")
	p, _ := ScriptManager_LoadModule("res_test/plain.lua", mgr)
	testing.expect(t, p != nil && !p.isResourceClass, "unmarked script is not a class")
	b, _ := ScriptManager_LoadModule("res_test/bad_marker.lua", mgr)
	testing.expect(t, b != nil && !b.isResourceClass, "a non-table marker is not a class")
}

@(test)
test_resource_file_roundtrip :: proc(t: ^testing.T) {
	game := res_game()
	defer game->terminate()
	mgr := &game.scriptManager
	mod, _ := ScriptManager_LoadModule("res_test/health.lua", mgr)
	if mod == nil do testing.fail_now(t, "class")

	file, ok := Resource_ParseText("x.resource.json", `{"type": "resource", "script": "res_test/health.lua",
		"properties": {"tag": "boss", "max": 100, "old_field": {"a": [1, 2]}, "drops": [3, 4, 5]}}`)
	testing.expect(t, ok, "parsed")
	values := make(map[string]ScriptValue, allocator = context.temp_allocator)
	for p in mod.properties do values[p.name] = script_property_value(p, file.values)
	defer for _, v in values do if v.type == .String do delete(v.valString)
	text := Resource_FileText(file.script, values, mod, file.raw, context.temp_allocator)

	// max = 100 is the default: dropped. Undeclared old_field kept. Sorted.
	testing.expect(t, !strings.contains(text, `"max"`), "default value omitted")
	testing.expect(t, strings.contains(text, `"old_field": {"a":[1,2]}`) || strings.contains(text, `"old_field": {"a": [1, 2]}`), text)
	testing.expect(t, strings.contains(text, `"drops": [3,4,5]`) || strings.contains(text, `"drops": [3, 4, 5]`), text)
	di, oi, ti := strings.index(text, `"drops"`), strings.index(text, `"old_field"`), strings.index(text, `"tag"`)
	testing.expect(t, di < oi && oi < ti, "keys sorted")

	again, ok2 := Resource_ParseText("x.resource.json", text)
	testing.expect(t, ok2 && again.script == "res_test/health.lua", "re-reads")
	testing.expect_value(t, again.values["tag"].valString, "boss")

	_, bad := Resource_ParseText("x.resource.json", `{"type": "resource"}`)
	testing.expect(t, !bad, "no script: rejected")
}

@(test)
test_resource_shared_identity_and_on_load :: proc(t: ^testing.T) {
	game := res_game()
	defer game->terminate()
	L := game.scriptManager.L
	ok := run(t, L, `
local a = Resource.load("res_test/boss.resource.json")
local b = Resource.load("res_test/boss.resource.json")
same = rawequal(a, b)
max_v, tag_v, regen_v = a.max, a.tag, a.regen
path_ok = a.resource_path == "res_test/boss.resource.json"
drops_n = #a.drops
left = a:damage(50)
via_b = b.current
has_dup = type(a.duplicate) == "function"
`)
	if !ok do return
	testing.expect(t, global_bool(L, "same"), "one shared table per file")
	testing.expect_value(t, global_int(L, "max_v"), 250)
	testing.expect_value(t, global_int(L, "loads"), 1) // on_load once
	testing.expect_value(t, global_int(L, "left"), 200)
	testing.expect_value(t, global_int(L, "via_b"), 200)
	testing.expect_value(t, global_int(L, "drops_n"), 2)
	testing.expect(t, global_bool(L, "path_ok"), "resource_path")
	testing.expect(t, global_bool(L, "has_dup"), "ResourceBase methods after the class's")

	// Resource.new: a fresh table (on_load again), not the shared one.
	if !run(t, L, `local c = Resource.new("res_test/boss.resource.json"); fresh = c.current; differs = not rawequal(c, Resource.load("res_test/boss.resource.json"))`) do return
	testing.expect_value(t, global_int(L, "fresh"), 250)
	testing.expect(t, global_bool(L, "differs"), "new is its own table")
	testing.expect_value(t, global_int(L, "loads"), 2)
}

@(test)
test_resource_errors :: proc(t: ^testing.T) {
	game := res_game()
	defer game->terminate()

	mgr := &game.scriptManager
	testing.expect(t, Resource_Load(mgr, "res_test/missing.resource.json", nil) == nil, "missing file")
	testing.expect(t, Resource_Load(mgr, "res_test/not_class.resource.json", nil) == nil, "class without the marker")
	testing.expect(t, Resource_Load(mgr, "res_test/bad_type.resource.json", nil) == nil, "wrong type")
	testing.expect_value(t, len(mgr.resources), 0)
	if !run(t, mgr.L, `r = Resource.load("res_test/missing.resource.json"); is_nil = r == nil`) do return
	testing.expect(t, global_bool(mgr.L, "is_nil"), "nil in Lua")
}

@(test)
test_resource_scopes_released_with_node :: proc(t: ^testing.T) {
	game := res_game()
	defer game->terminate()
	mgr := &game.scriptManager
	scene := game->createScene("res_scopes", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	a := Node_CreateByTypeName(scene, "Node")
	a.name = "EnemyA"
	a.componentPath = strings.clone("components/enemy.component.json", a.allocator)
	b := Node_CreateByTypeName(scene, "Node")
	b.name = "EnemyB"
	b.componentPath = strings.clone("components/enemy.component.json", b.allocator)
	bar := Node_CreateByTypeName(scene, "Node")
	bar.name = "Bar"
	ProcessNodeQueues(scene.manager, &game.gameContext)
	AddChild(scene.manager, a, bar)
	loose := Node_CreateByTypeName(scene, "Node")
	ProcessNodeQueues(scene.manager, &game.gameContext)

	// Scope: nearest component instance root, else the tree's root.
	testing.expect(t, Resource_ScopeOf(a) == a, "an instance root is its own scope")
	testing.expect(t, Resource_ScopeOf(bar) == a, "a child: its instance root")
	testing.expect(t, Resource_ScopeOf(loose) == scene.rootNode, "outside instances: the tree's root")

	// Cached per (scope, path): A's root and child share, B has its own.
	ra := Resource_Load(mgr, "res_test/grunt.resource.json", Resource_ScopeOf(a))
	rbar := Resource_Load(mgr, "res_test/grunt.resource.json", Resource_ScopeOf(bar))
	rb := Resource_Load(mgr, "res_test/grunt.resource.json", Resource_ScopeOf(b))
	shared := Resource_Load(mgr, "res_test/grunt.resource.json", nil)
	testing.expect(t, ra != nil && ra == rbar, "same instance: one copy")
	testing.expect(t, rb != nil && rb != ra && shared != ra && shared != rb, "other instance / shared: other tables")
	testing.expect_value(t, len(mgr.resources), 3)

	// Destroying A releases its copy only.
	SceneRemoveNode(scene, a)
	ProcessNodeQueues(scene.manager, &game.gameContext)
	testing.expect_value(t, len(mgr.resources), 2)
	for r in mgr.resources do testing.expect(t, r.scope != rawptr(a), "A's copy released")

	// Resource.new from a script: owned by its node's scope.
	b.gameContext = &game.gameContext
	ScriptVFS_RegisterEmbedded("res_test/user.lua", `local U = {} function U:ready() mine = Resource.new("res_test/grunt.resource.json") end return U`)
	Script_AttachToNode(b, "res_test/user.lua", nil, mgr)
	ProcessNodeQueues(scene.manager, &game.gameContext)
	game.state = .Running
	game->run(0.016)
	owned := 0
	for r in mgr.resources do if r.scope == rawptr(b) do owned += 1
	testing.expect_value(t, owned, 2) // rb + the script's Resource.new copy
}

@(test)
test_resource_duplicate :: proc(t: ^testing.T) {
	game := res_game()
	defer game->terminate()
	L := game.scriptManager.L
	ok := run(t, L, `
local other = Resource.load("res_test/grunt.resource.json")
local a = Resource.load("res_test/boss.resource.json")
a.current = 7
a.friend = other
local d = a:duplicate()
d.drops[1] = 99
d.current = 1
dup_current, a_current = d.current, a.current
a_drop = a.drops[1]
friend_shared = rawequal(d.friend, other)
dup_method = d:damage(1)
dup_path = d.resource_path
not_res = Resource.load("res_test/boss.resource.json").duplicate({}) == nil
`)
	if !ok do return
	testing.expect_value(t, global_int(L, "a_current"), 7)
	testing.expect_value(t, global_int(L, "dup_current"), 1)
	testing.expect_value(t, global_int(L, "a_drop"), 1) // tables deep-copied
	testing.expect(t, global_bool(L, "friend_shared"), "other resources stay references")
	testing.expect_value(t, global_int(L, "dup_method"), 0)
	testing.expect(t, global_bool(L, "not_res"), "duplicate on a plain table: nil")
	testing.expect_value(t, global_int(L, "loads"), 2) // grunt + boss; duplicate doesn't run on_load
	testing.expect_value(t, len(game.scriptManager.resources), 3)
}

@(test)
test_resource_hot_reload :: proc(t: ^testing.T) {
	dir :: "test_resource_hot"
	_ = os.make_directory_all(dir + "/resources")
	_ = os.make_directory_all(dir + "/scripts")
	defer os.remove_all(dir)
	_ = os.write_entire_file(dir + "/scripts/health.lua", transmute([]u8)string(HEALTH_CLASS))
	_ = os.write_entire_file(dir + "/resources/boss.resource.json", transmute([]u8)string(`{"type": "resource", "script": "scripts/health.lua", "properties": {"max": 250}}`))

	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	AssetManager_SetProjectDir(&game.assetManager, dir)
	mgr := &game.scriptManager
	L := mgr.L
	if !run(t, L, `boss = Resource.load("resources/boss.resource.json"); boss.current = 5`) do return
	testing.expect_value(t, len(mgr.resources), 1)
	testing.expect(t, mgr.resources[0].diskPath != "", "tracks its file")

	// The file changes: changed values re-applied, runtime fields kept, no on_load.
	_ = os.write_entire_file(dir + "/resources/boss.resource.json", transmute([]u8)string(`{"type": "resource", "script": "scripts/health.lua", "properties": {"max": 400, "tag": "big"}}`))
	mgr.resources[0].modTime = {}
	testing.expect_value(t, ScriptManager_CheckForChanges(mgr, force = true), 1)
	if !run(t, L, `m, cur, tg = boss.max, boss.current, boss.tag`) do return
	testing.expect_value(t, global_int(L, "m"), 400)
	testing.expect_value(t, global_int(L, "cur"), 5)
	testing.expect_value(t, global_int(L, "loads"), 1)

	// The class changes: new methods and new properties reach the table.
	_ = os.write_entire_file(dir + "/scripts/health.lua", transmute([]u8)string(strings.concatenate({
		strings.trim_suffix(strings.trim_space(HEALTH_CLASS), "return Health"),
		"Health.properties.armor = { type = \"int\", default = 3 }\nfunction Health:heal(n) self.current = self.current + n return self.current end\nreturn Health\n",
	}, context.temp_allocator)))
	mgr.modules["scripts/health.lua"].modTime = {}
	ScriptManager_CheckForChanges(mgr, force = true)
	if !run(t, L, `healed = boss:heal(10); armor = boss.armor`) do return
	testing.expect_value(t, global_int(L, "healed"), 15)
	testing.expect_value(t, global_int(L, "armor"), 3)
}

@(test)
test_resource_cleared_when_simulation_stops :: proc(t: ^testing.T) {
	game := res_game()
	defer game->terminate()
	mgr := &game.scriptManager
	ScriptManager_SnapshotGlobals(mgr)
	if !run(t, mgr.L, `local r = Resource.load("res_test/boss.resource.json"); r.max = 1`) do return
	testing.expect_value(t, len(mgr.resources), 1)
	testing.expect(t, ScriptManager_RestoreGlobals(mgr), "restored")
	testing.expect_value(t, len(mgr.resources), 0)
	// Loads fresh from the file again.
	if !run(t, mgr.L, `again = Resource.load("res_test/boss.resource.json").max`) do return
	testing.expect_value(t, global_int(mgr.L, "again"), 250)
}
