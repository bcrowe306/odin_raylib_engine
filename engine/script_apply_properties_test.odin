package engine

import "core:testing"
import lua "lua54"

// script_apply_properties on a plain Lua table (no node): defaults,
// overrides coerced to the declared type, lists as tables, node references
// left nil, and a values map that owns its strings (shared by node scripts
// and, later, resources).
@(test)
test_script_apply_properties_plain_table :: proc(t: ^testing.T) {
	ScriptVFS_RegisterEmbedded("apply_props.lua", `
local S = {}
S.properties = {
    hp     = { type = "int", default = 10 },
    speed  = { type = "float", default = 1.5 },
    tag    = { type = "string", default = "scout" },
    skin   = { type = "texture", default = "textures/a.png" },
    target = { type = "node" },
    drops  = { type = "array", of = "int", default = {1, 2} },
    tint   = { type = "color", default = {1, 0, 0, 1} },
    offset = { type = "vector2", default = {3, 4} },
}
return S
`)
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	mgr := &game.scriptManager
	mod, ok := ScriptManager_LoadModule("apply_props.lua", mgr)
	testing.expect(t, ok && mod != nil, "module loads")
	if !ok do return

	overrides := make(map[string]ScriptValue, allocator = context.temp_allocator)
	overrides["hp"] = {type = .Float, valFloat = 42}  // JSON numbers arrive as floats
	overrides["speed"] = {type = .Int, valInt = 3}
	overrides["tag"] = {type = .String, valString = "boss"}

	props := make(map[string]ScriptValue)
	defer {
		for k, v in props {
			delete(k)
			if v.type == .String do delete(v.valString)
		}
		delete(props)
	}

	L := mgr.L
	top := lua.gettop(L)
	lua.newtable(L)
	script_apply_properties(L, lua.gettop(L), mod, overrides, &props)

	// The recorded values.
	testing.expect_value(t, len(props), 8)
	testing.expect(t, props["hp"].type == .Int && props["hp"].valInt == 42, "int override coerced from float")
	testing.expect(t, props["speed"].type == .Float && props["speed"].valFloat == 3, "float override coerced from int")
	testing.expect_value(t, props["tag"].valString, "boss")
	testing.expect_value(t, props["skin"].valString, "textures/a.png")

	// The Lua table.
	field :: proc(L: ^lua.State, name: cstring) -> lua.Type {
		lua.getfield(L, -1, name)
		return lua.type(L, -1)
	}
	testing.expect(t, field(L, "hp") == .NUMBER && lua.tointeger(L, -1) == 42, "self.hp")
	lua.pop(L, 1)
	testing.expect(t, field(L, "tag") == .STRING && string(lua.tostring(L, -1)) == "boss", "self.tag")
	lua.pop(L, 1)
	testing.expect(t, field(L, "skin") == .STRING, "asset path as a string")
	lua.pop(L, 1)
	testing.expect(t, field(L, "target") == .NIL, "node reference nil until resolved")
	lua.pop(L, 1)
	testing.expect(t, field(L, "drops") == .TABLE && lua.rawlen(L, -1) == 2, "array as a table")
	lua.pop(L, 1)
	testing.expect(t, field(L, "tint") == .TABLE && lua.rawlen(L, -1) == 4, "colour as {r, g, b, a}")
	lua.pop(L, 1)
	testing.expect(t, field(L, "offset") != .NIL, "vector2 set")
	lua.pop(L, 1)

	lua.settop(L, top)
}
