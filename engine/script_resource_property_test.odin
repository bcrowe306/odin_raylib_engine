package engine

import "core:strings"
import "core:testing"
import lua "lua54"

// `type = "resource"` script properties: parsed (class, local_copy, lists),
// nil until ready, then the resource's table - shared or one copy per
// component instance - with the class checked.

@(private = "file")
setup :: proc() -> (^Game, ^Scene) {
	ScriptVFS_RegisterEmbedded("rprop/health.lua", `
local Health = {}
Health.resource = { local_copy = true }
Health.properties = { max = { type = "int", default = 100 } }
function Health:on_load() self.current = self.max end
function Health:damage(n) self.current = self.current - n return self.current end
return Health
`)
	ScriptVFS_RegisterEmbedded("rprop/item.lua", `
local Item = {}
Item.resource = {}
Item.properties = { name = { type = "string", default = "?" } }
return Item
`)
	ScriptVFS_RegisterEmbedded("rprop/boss.resource.json", `{"type": "resource", "script": "rprop/health.lua", "properties": {"max": 250}}`)
	ScriptVFS_RegisterEmbedded("rprop/sword.resource.json", `{"type": "resource", "script": "rprop/item.lua", "properties": {"name": "Sword"}}`)
	ScriptVFS_RegisterEmbedded("rprop/shield.resource.json", `{"type": "resource", "script": "rprop/item.lua", "properties": {"name": "Shield"}}`)
	ScriptVFS_RegisterEmbedded("rprop/enemy.lua", `
local Enemy = {}
Enemy.properties = {
    health = { type = "resource", class = "rprop/health.lua" },
    shared_health = { type = "resource", local_copy = false },
    loot   = { type = "array", of = "resource", class = "rprop/item.lua" },
    wrong  = { type = "resource", class = "rprop/item.lua" },
}
function Enemy:ready()
    seen_before_ready = seen_before_ready or {}
    table.insert(seen_before_ready, self.health ~= nil)
end
return Enemy
`)
	game := new(Game)
	InitializeGame(game)
	scene := game->createScene("rprop", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	return game, scene
}

@(private = "file")
OVERRIDES :: `{"health": "rprop/boss.resource.json", "shared_health": "rprop/boss.resource.json",
	"loot": ["rprop/sword.resource.json", "rprop/shield.resource.json"], "wrong": "rprop/boss.resource.json"}`

// enemy makes a component-instance-like node (componentPath set) with the
// Enemy script, plus a child with the same script.
@(private = "file")
enemy :: proc(game: ^Game, scene: ^Scene, name: string) -> (root, child: ^Node) {
	file, _ := Resource_ParseText("x", strings.concatenate({`{"script": "x", "properties": `, OVERRIDES, `}`}, context.temp_allocator))
	root = Node_CreateByTypeName(scene, "Node")
	root.name = strings.clone(name, root.allocator)
	root.componentPath = strings.clone("components/enemy.component.json", root.allocator)
	root.gameContext = &game.gameContext
	child = Node_CreateByTypeName(scene, "Node")
	child.gameContext = &game.gameContext
	ProcessNodeQueues(scene.manager, &game.gameContext)
	AddChild(scene.manager, root, child)
	Script_AttachToNode(root, "rprop/enemy.lua", file.values, &game.scriptManager)
	Script_AttachToNode(child, "rprop/enemy.lua", file.values, &game.scriptManager)
	return
}

@(private = "file")
self_of :: proc(L: ^lua.State, n: ^Node) {
	lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer((cast(^ScriptInstance)n.scriptInstance).registryRef))
}

@(test)
test_resource_property_parsed :: proc(t: ^testing.T) {
	game, _ := setup()
	defer game->terminate()
	mod, ok := ScriptManager_LoadModule("rprop/enemy.lua", &game.scriptManager)
	if !ok do testing.fail_now(t, "module")
	byName :: proc(mod: ^ScriptModule, name: string) -> ScriptProperty {
		for p in mod.properties do if p.name == name do return p
		return {}
	}
	h := byName(mod, "health")
	testing.expect(t, h.type == .String && h.assetKind == "resource" && h.resourceClass == "rprop/health.lua" && h.resourceLocal == .Default, "resource, class, default local")
	testing.expect_value(t, byName(mod, "shared_health").resourceLocal, Resource_LocalMode.Shared)
	l := byName(mod, "loot")
	testing.expect(t, l.assetKind == "array" && l.elem == "resource" && Script_IsResourceProp(l), "list of resources")
}

@(test)
test_resource_property_resolved_per_component_instance :: proc(t: ^testing.T) {
	game, scene := setup()
	defer game->terminate()
	L := game.scriptManager.L
	a, aChild := enemy(game, scene, "A")
	b, _ := enemy(game, scene, "B")

	// Before ready (edit mode): nil, nothing loaded.
	self_of(L, a)
	lua.getfield(L, -1, "health")
	testing.expect(t, lua.type(L, -1) == .NIL, "nil before ready")
	lua.pop(L, 2)
	testing.expect_value(t, len(game.scriptManager.resources), 0)

	game->run(0.016)
	lua.getglobal(L, "seen_before_ready")
	lua.rawgeti(L, -1, 1)
	testing.expect(t, bool(lua.toboolean(L, -1)), "set when ready() runs")
	lua.pop(L, 2)

	push_field :: proc(L: ^lua.State, n: ^Node, field: cstring) {
		self_of(L, n)
		lua.getfield(L, -1, field)
		lua.remove(L, -2)
	}
	same :: proc(L: ^lua.State, x: ^Node, fx: cstring, y: ^Node, fy: cstring) -> bool {
		push_field(L, x, fx)
		push_field(L, y, fy)
		defer lua.pop(L, 2)
		return lua.type(L, -1) == .TABLE && bool(lua.rawequal(L, -1, -2))
	}
	// local_copy from the class: one per instance, shared inside it.
	testing.expect(t, same(L, a, "health", aChild, "health"), "root and child of A share")
	testing.expect(t, !same(L, a, "health", b, "health"), "A and B have their own")
	// local_copy = false on the property: the one shared table everywhere.
	testing.expect(t, same(L, a, "shared_health", b, "shared_health"), "shared across instances")
	testing.expect(t, !same(L, a, "health", a, "shared_health"), "local copy is not the shared one")

	// The table works: values, on_load, methods; copies are independent.
	push_field(L, a, "health")
	lua.getfield(L, -1, "damage")
	lua.pushvalue(L, -2)
	lua.pushinteger(L, 50)
	testing.expect(t, lua.pcall(L, 2, 1, 0) == 0 && lua.tointeger(L, -1) == 200, "a.health:damage(50) == 200")
	lua.pop(L, 2)
	push_field(L, b, "health")
	lua.getfield(L, -1, "current")
	testing.expect_value(t, lua.tointeger(L, -1), 250)
	lua.pop(L, 2)

	// Lists: a table of tables; the class is checked.
	push_field(L, a, "loot")
	testing.expect(t, lua.type(L, -1) == .TABLE && lua.rawlen(L, -1) == 2, "two items")
	lua.rawgeti(L, -1, 2)
	lua.getfield(L, -1, "name")
	testing.expect_value(t, string(lua.tostring(L, -1)), "Shield")
	lua.pop(L, 3)
	push_field(L, a, "wrong")
	testing.expect(t, lua.type(L, -1) == .NIL, "a file of another class: nil")
	lua.pop(L, 1)

	// Destroying instance A releases its local copy (B's and the shared stay).
	before := len(game.scriptManager.resources)
	SceneRemoveNode(scene, a)
	ProcessNodeQueues(scene.manager, &game.gameContext)
	testing.expect_value(t, len(game.scriptManager.resources), before - 1)
}

@(test)
test_resource_property_set_after_ready :: proc(t: ^testing.T) {
	game, scene := setup()
	defer game->terminate()
	L := game.scriptManager.L
	a, _ := enemy(game, scene, "A")
	game->run(0.016)
	inst := cast(^ScriptInstance)a.scriptInstance
	testing.expect(t, ScriptInstance_SetProperty(inst, "shared_health", {type = .String, valString = "rprop/sword.resource.json"}, &game.scriptManager), "set")
	self_of(L, a)
	lua.getfield(L, -1, "shared_health")
	lua.getfield(L, -1, "name")
	testing.expect_value(t, string(lua.tostring(L, -1)), "Sword")
	lua.pop(L, 3)
	testing.expect_value(t, inst.properties["shared_health"].valString, "rprop/sword.resource.json")
}
