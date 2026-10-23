package engine

import "core:fmt"
import "core:strings"
import "core:testing"

// The per-class get_property / set_property declarations in engine_api.lua
// (between the "node properties" markers): each class's property paths as
// an alias (type and help on completion) and overloads typing the value.
// On drift the test prints the block to paste.
@(test)
test_lua_node_properties_definitions :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("props", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)

	sb := strings.builder_make(context.temp_allocator)
	strings.write_string(&sb, "-- node properties begin (generated from the engine: lua_properties_definitions_test.odin)\n")
	for info in NODE_TYPES {
		n := Node_CreateByTypeName(scene, info.name)
		if n == nil do continue
		props := make([dynamic]Node_Property, context.temp_allocator)
		for name in ([]string{"position", "scale", "rotation", "origin", "layer", "pauseMode", "paused", "enabled"}) {
			if p, ok := Node_BaseProperty(n, name); ok do append(&props, p)
		}
		own := Node_CollectProperties(n)
		for p in own do append(&props, p)
		for name in ([]string{"fps", "defaultAnimation"}) {
			if p, ok := Node_BaseProperty(n, name); ok do append(&props, p)
		}
		if info.name != "Node" && len(own) == 0 && !Node_HasOrigin(n) && n.typeId != AnimationPlayerNode do continue // Node's own declarations cover it
		cls := info.name
		fmt.sbprintf(&sb, "\n---@alias %sProperty\n", cls)
		for p in props {
			ty := lua_prop_type(p)
			if ty == "" do continue
			doc := Property_Doc(p)
			if len(doc) > 90 do doc = strings.concatenate({doc[:87], "..."}, context.temp_allocator)
			fmt.sbprintf(&sb, "---| %q # %s%s%s\n", p.name, ty, " (runtime)" if p.runtime else "", fmt.tprintf(" - %s", doc) if doc != "" else "")
		}
		fmt.sbprintf(&sb, "\n---Reads an Inspector property by its path (vectors and colours as tables); \"script.<name>\" reads a field of the node's script.\n---@param path %sProperty|string\n---@return any\n", cls)
		for p in props {
			if ty := lua_prop_type(p); ty != "" do fmt.sbprintf(&sb, "---@overload fun(self: %s, path: %q): %s\n", cls, p.name, ty)
		}
		fmt.sbprintf(&sb, "function %s:get_property(path) end\n", cls)
		fmt.sbprintf(&sb, "\n---Sets an Inspector property by its path: vectors as {{x, y}} or x, y; colours as {{r, g, b[, a]}} 0..1; enums by name; \"script.<name>\" a field of the node's script.\n---@param path %sProperty|string\n---@param value any\n---@param y? number\n", cls)
		for p in props {
			ty := lua_prop_type(p)
			if ty == "" do continue
			if p.kind == .Vec2 do fmt.sbprintf(&sb, "---@overload fun(self: %s, path: %q, x: number|number[], y?: number)\n", cls, p.name)
			else do fmt.sbprintf(&sb, "---@overload fun(self: %s, path: %q, value: %s)\n", cls, p.name, ty)
		}
		fmt.sbprintf(&sb, "function %s:set_property(path, value, y) end\n", cls)
	}
	strings.write_string(&sb, "-- node properties end\n")
	want := strings.to_string(sb)

	api := ENGINE_API_LUA
	a := strings.index(api, "-- node properties begin")
	b := strings.index(api, "-- node properties end\n")
	have := api[a:b + len("-- node properties end\n")] if a >= 0 && b > a else ""
	if have != want {
		fmt.println("---- paste into engine_api.lua ----")
		fmt.print(want)
		fmt.println("---- end ----")
	}
	testing.expect(t, have == want, "engine_api.lua's per-class property declarations match the engine")
}

// lua_prop_type: the Lua type of a property's value ("" = not scriptable).
@(private = "file")
lua_prop_type :: proc(p: Node_Property) -> string {
	switch p.kind {
	case .Float:  return "number"
	case .Int:    return "integer"
	case .Bool:   return "boolean"
	case .Vec2:   return "number[]"
	case .Color:  return "number[]"
	case .String: return "string"
	case .Enum:
		names := make([dynamic]string, context.temp_allocator)
		for e in Property_EnumNames(p) do append(&names, fmt.tprintf("%q", e))
		return strings.join(names[:], "|", context.temp_allocator)
	case .Bit_Set:
	}
	return ""
}
