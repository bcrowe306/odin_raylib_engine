package engine

import "core:fmt"
import os "osx"
import "core:strings"
import "core:testing"
import "core:time"
import lua "lua54"

// #153: script inheritance (`extends`) - methods, `super`, merged
// properties, loops, a missing base, hot reload, is().

@(private = "file")
SX_DIR :: "test_script_extends"

@(private = "file")
SX_BASE :: `
local Hurt = {}
Hurt.properties = {
	max_health = { type = "float", default = 10, label = "Max Health", min = 1, max = 100 },
	armor = { type = "float", default = 0 },
}
function Hurt:ready() self.health = self.max_health; self.base_ready = true end
function Hurt:take_damage(amount) self.health = self.health - math.max(amount - self.armor, 0) end
function Hurt:describe() return "hurtbox" end
return Hurt
`

@(private = "file")
SX_CHILD :: `
local Boss = {}
Boss.extends = "scripts/sx_base.lua"
Boss.properties = {
	max_health = { default = 50 },
	enrage_at = { type = "float", default = 20 },
}
function Boss:ready()
	Boss.super.ready(self)
	self.boss_ready = true
end
function Boss:take_damage(amount) Boss.super.take_damage(self, amount * 0.5) end
return Boss
`

@(private = "file")
sx_write :: proc(rel, text: string) {
	full := strings.concatenate({SX_DIR, "/", rel}, context.temp_allocator)
	_ = os.make_directory_all(full[:strings.last_index_byte(full, '/')])
	_ = os.write_entire_file(full, transmute([]u8)text)
}

@(private = "file")
sx_game :: proc() -> (^Game, ^Scene) {
	CustomNodes_Forget()
	sx_write("scripts/sx_base.lua", SX_BASE)
	sx_write("scripts/sx_boss.lua", SX_CHILD)
	game := new(Game)
	InitializeGame(game)
	AssetManager_SetProjectDir(&game.assetManager, SX_DIR)
	scene := game->createScene("extends", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	return game, scene
}

@(private = "file")
sx_done :: proc(game: ^Game) {
	game->terminate()
	CustomNodes_Forget()
	os.remove_all(SX_DIR)
}

@(private = "file")
sx_get :: proc(L: ^lua.State, expr: string) -> string {
	_ = lua.L_dostring(L, strings.clone_to_cstring(fmt.tprintf("return tostring(%s)", expr), context.temp_allocator))
	defer lua.pop(L, 1)
	return strings.clone(string(lua.tostring(L, -1)), context.temp_allocator)
}

@(private = "file")
sx_prop :: proc(mod: ^ScriptModule, name: string) -> (ScriptProperty, bool) {
	for p in mod.properties do if p.name == name do return p, true
	return {}, false
}

@(test)
test_script_extends_methods_and_properties :: proc(t: ^testing.T) {
	game, scene := sx_game()
	defer sx_done(game)
	mgr := &game.scriptManager
	boss, ok := ScriptManager_LoadModule("scripts/sx_boss.lua", mgr)
	if !testing.expect(t, ok, "loads") do return
	testing.expect_value(t, boss.extends, "scripts/sx_base.lua")

	// Properties: the base's, max_health's default changed (its label and
	// range kept), and its own.
	mh, has := sx_prop(boss, "max_health")
	testing.expect(t, has && mh.type == .Float && mh.defaultVal.valFloat == 50 && mh.label == "Max Health" && mh.max == 100, "max_health: another default, the rest kept")
	_, hasArmor := sx_prop(boss, "armor")
	_, hasEnrage := sx_prop(boss, "enrage_at")
	testing.expect(t, hasArmor && hasEnrage, "the base's and its own")
	base, _ := ScriptManager_LoadModule("scripts/sx_base.lua", mgr)
	bmh, _ := sx_prop(base, "max_health")
	testing.expect_value(t, bmh.defaultVal.valFloat, 10) // (the base unchanged)

	// Methods: overridden ones call the base's; others come from it.
	n := Node_CreateByTypeName(scene, "AreaNode")
	n.name = "Boss"
	n.gameContext = &game.gameContext
	Script_AttachToNode(n, "scripts/sx_boss.lua", nil, mgr)
	ProcessNodeQueues(scene.manager, &game.gameContext)
	game->run(1.0 / 60)
	L := mgr.L
	_ = lua.L_dostring(L, `b = Scene.find_node("Boss"):get_script(); b:take_damage(10)`)
	testing.expect_value(t, sx_get(L, "b.health"), "45.0") // 50 - 10 * 0.5
	testing.expect_value(t, sx_get(L, "b.base_ready and b.boss_ready"), "true")
	testing.expect_value(t, sx_get(L, "b:describe()"), "hurtbox")
}

@(test)
test_script_extends_loops_and_missing :: proc(t: ^testing.T) {
	game, _ := sx_game()
	defer sx_done(game)
	mgr := &game.scriptManager
	sx_write("scripts/sx_a.lua", `local A = {}; A.extends = "scripts/sx_b.lua"; A.properties = { a = { type = "float", default = 1 } }; return A`)
	sx_write("scripts/sx_b.lua", `local B = {}; B.extends = "scripts/sx_a.lua"; B.properties = { b = { type = "float", default = 2 } }; return B`)
	sx_write("scripts/sx_orphan.lua", `local O = {}; O.extends = "scripts/nowhere.lua"; O.properties = { o = { type = "float", default = 3 } }; function O:hi() return "hi" end; return O`)
	a, okA := ScriptManager_LoadModule("scripts/sx_a.lua", mgr)
	testing.expect(t, okA && a != nil, "a loop still loads")
	o, okO := ScriptManager_LoadModule("scripts/sx_orphan.lua", mgr)
	testing.expect(t, okO && o.extends == "", "a missing base: no inheritance")
	_, hasO := sx_prop(o, "o")
	testing.expect(t, hasO, "its own properties")
}

@(test)
test_script_extends_hot_reload :: proc(t: ^testing.T) {
	game, scene := sx_game()
	defer sx_done(game)
	mgr := &game.scriptManager
	n := Node_CreateByTypeName(scene, "AreaNode")
	n.gameContext = &game.gameContext
	Script_AttachToNode(n, "scripts/sx_boss.lua", nil, mgr)
	ProcessNodeQueues(scene.manager, &game.gameContext)
	inst := cast(^ScriptInstance)n.scriptInstance
	if !testing.expect(t, inst != nil, "attached") do return

	// The base gains a property and a method: the child's instance has both.
	time.sleep(10 * time.Millisecond)
	more, _ := strings.replace(SX_BASE, `armor = { type = "float", default = 0 },`, `armor = { type = "float", default = 0 }, speed = { type = "float", default = 7 },`, 1, context.temp_allocator)
	more, _ = strings.replace(more, `return Hurt`, `function Hurt:shout() return "ow" end
return Hurt`, 1, context.temp_allocator)
	sx_write("scripts/sx_base.lua", more)
	testing.expect(t, ScriptManager_ReloadModule(mgr, "scripts/sx_base.lua", true), "reloaded")
	boss := mgr.modules["scripts/sx_boss.lua"]
	_, hasSpeed := sx_prop(boss, "speed")
	testing.expect(t, hasSpeed, "the child's properties: the base's new one")
	v, hasValue := ScriptInstance_GetProperty(inst, "speed")
	testing.expect(t, hasValue && v.valFloat == 7, "the instance: its default")
	L := mgr.L
	lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(inst.registryRef))
	lua.setglobal(L, "inst")
	testing.expect_value(t, sx_get(L, "inst:shout()"), "ow")

	// The child itself reloads: still linked.
	sx_write("scripts/sx_boss.lua", strings.concatenate({SX_CHILD[:len(SX_CHILD) - len("return Boss\n")], "function Boss:shout() return 'GRR' end\nreturn Boss\n"}, context.temp_allocator))
	testing.expect(t, ScriptManager_ReloadModule(mgr, "scripts/sx_boss.lua", true), "child reloaded")
	testing.expect_value(t, sx_get(L, "inst:shout()"), "GRR")
	testing.expect_value(t, sx_get(L, "inst:describe()"), "hurtbox")
	testing.expect_value(t, boss.extends, "scripts/sx_base.lua")
}

@(test)
test_script_extends_is_custom_type :: proc(t: ^testing.T) {
	game, scene := sx_game()
	defer sx_done(game)
	sx_write("nodes/Hurt.node.json", `{"name": "Hurt", "base": "AreaNode", "script": "scripts/sx_base.lua"}`)
	n := Node_CreateByTypeName(scene, "AreaNode")
	n.gameContext = &game.gameContext
	Script_AttachToNode(n, "scripts/sx_boss.lua", nil, &game.scriptManager)
	ProcessNodeQueues(scene.manager, &game.gameContext)
	testing.expect(t, Node_Is(n, "Hurt"), "a script built on Hurt's: a Hurt")
	testing.expect(t, !Node_Is(n, "Other"), "not another type")
}
