package engine

import "core:strings"
import "core:testing"
import lua "lua54"

// Script property types: enum, range (slider), array, curve, gradient,
// group / tooltip; lists are Lua tables, saved as JSON, read back.
@(test)
test_script_property_types :: proc(t: ^testing.T) {
	ScriptVFS_RegisterEmbedded("prop_types.lua", `
local S = {}
S.properties = {
    mode   = { type = "enum", values = {"Idle", "Run", "Jump"}, default = "Run", group = "State", tooltip = "What it does" },
    volume = { type = "range", min = 0, max = 1, default = 0.5 },
    speeds = { type = "array", of = "float", default = {1, 2, 3} },
    names  = { type = "array" },
    ease   = { type = "curve" },
    tint   = { type = "gradient", default = {{0, 1, 0, 0, 1}, {1, 0, 0, 1, 1}} },
}
function S:ready()
    got = string.format("%s|%d|%s|%.2f|%.2f", self.mode, #self.speeds, tostring(self.speeds[3]), Curve.sample(self.ease, 0.25), select(3, Gradient.sample(self.tint, 0.5)))
end
return S
`)
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("types", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	n := Node_CreateByTypeName(scene, "Node")
	n.name = "Holder"
	n.gameContext = &game.gameContext
	inst := Script_AttachToNode(n, "prop_types.lua", nil, &game.scriptManager)
	ProcessNodeQueues(scene.manager, &game.gameContext)
	game->run(0.016)

	mod := game.scriptManager.modules["prop_types.lua"]
	testing.expect(t, mod != nil, "module")
	byName :: proc(mod: ^ScriptModule, name: string) -> ^ScriptProperty {
		for &p in mod.properties do if p.name == name do return &p
		return nil
	}
	mode := byName(mod, "mode")
	testing.expect(t, mode.assetKind == "enum" && len(mode.values) == 3 && mode.group == "State" && mode.tooltip == "What it does", "enum")
	testing.expect(t, byName(mod, "volume").slider, "range: slider")
	testing.expect(t, byName(mod, "speeds").elem == "float" && byName(mod, "names").elem == "string", "array elem")
	testing.expect_value(t, byName(mod, "ease").defaultVal.valString, "[[0, 0], [1, 1]]")
	L := game.scriptManager.L
	lua.getglobal(L, "got")
	testing.expect_value(t, string(lua.tostring(L, -1)), "Run|3|3.0|0.25|0.50")
	lua.pop(L, 1)

	// Saved as JSON; a two-item array survives a reload (not read as a vector).
	ScriptInstance_SetProperty(inst, "speeds", {type = .String, valString = "[4, 5]"}, &game.scriptManager)
	text := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expect(t, strings.contains(text, `"speeds": [4, 5]`), "saved as JSON")
	s2 := game->createScene("types2", false)
	Scene_InstantiateFromJSON(s2, transmute([]u8)text, &game.gameContext)
	ProcessNodeQueues(s2.manager, &game.gameContext)
	h := Scene_FindNodeByName(s2, "Holder")
	testing.expect(t, h != nil && h.scriptInstance != nil, "reloaded")
	if h == nil || h.scriptInstance == nil do return
	i2 := cast(^ScriptInstance)h.scriptInstance
	testing.expect_value(t, i2.properties["speeds"].valString, "[4, 5]")
	testing.expect_value(t, i2.properties["mode"].valString, "Run")
}

// Numbers from a scene file take the declared type: an "int" property set
// to 3 is the Lua integer 3 ("Level 3", not "Level 3.0").
@(test)
test_script_int_property_from_scene_is_an_integer :: proc(t: ^testing.T) {
	ScriptVFS_RegisterEmbedded("int_prop.lua", `
local S = {}
S.properties = { level = { type = "int", default = 1 }, speed = { type = "float", default = 1.5 } }
function S:ready() int_prop_got = math.type(self.level) .. " " .. tostring(self.level) .. " " .. math.type(self.speed) end
return S
`)
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("ints", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	n := Node_CreateByTypeName(scene, "Node")
	n.gameContext = &game.gameContext
	overrides := make(map[string]ScriptValue, context.temp_allocator)
	overrides["level"] = {type = .Float, valFloat = 3} // (what a scene file's 3 reads as)
	overrides["speed"] = {type = .Int, valInt = 2}
	_ = Script_AttachToNode(n, "int_prop.lua", overrides, &game.scriptManager)
	ProcessNodeQueues(scene.manager, &game.gameContext)
	game->run(0.016)
	L := game.scriptManager.L
	lua.getglobal(L, "int_prop_got")
	testing.expect_value(t, string(lua.tostring(L, -1)), "integer 3 float")
	lua.pop(L, 1)
}
