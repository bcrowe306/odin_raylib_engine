package engine

import "core:fmt"
import "core:strings"
import "core:testing"

// The per-class `connect` declarations in engine_api.lua (between the
// "node events" markers) list exactly the events each node type raises, so
// `timer:connect("` completes "timeout" / "tick" and a button "clicked".
// On drift the test prints the block to paste.
@(test)
test_lua_node_events_definitions :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("events", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)

	sb := strings.builder_make(context.temp_allocator)
	strings.write_string(&sb, "-- node events begin (generated from the engine: lua_events_definitions_test.odin)\n")
	for info in NODE_TYPES {
		n := Node_CreateByTypeName(scene, info.name)
		if n == nil do continue
		evs := Node_EventNames(n)[len(NODE_EVENT_NAMES):]
		if len(evs) == 0 do continue
		names := make([dynamic]string, context.temp_allocator)
		for e in evs do append(&names, fmt.tprintf("%q", e.name))
		fmt.sbprintf(&sb, "\n---@alias %sEvent NodeTreeEvent|%s|ProjectEvent\n", info.name, strings.join(names[:], "|", context.temp_allocator))
		list := make([dynamic]string, context.temp_allocator)
		for e in evs do append(&list, fmt.tprintf("%s (%s)", e.name, e.doc) if e.doc != "" else e.name)
		fmt.sbprintf(&sb, "---Connects a handler to one of this node's events: %s; the tree events; custom ones.\n", strings.join(list[:], ", ", context.temp_allocator))
		fmt.sbprintf(&sb, "---\n---Example: `self.node:connect(%q, function(value, source) Log.info(%q) end)`\n", evs[0].name, evs[0].name)
		fmt.sbprintf(&sb, "---@param event %sEvent|string The event's name (the Signals tab lists them)\n---@param handler fun(value: any, source: %s) Called with the event's value and the node that raised it\n---@return integer id Connection id for `disconnect`\nfunction %s:connect(event, handler) end\n", info.name, info.name, info.name)
	}
	strings.write_string(&sb, "-- node events end\n")
	want := strings.to_string(sb)

	api := ENGINE_API_LUA
	a := strings.index(api, "-- node events begin")
	b := strings.index(api, "-- node events end\n")
	have := api[a:b + len("-- node events end\n")] if a >= 0 && b > a else ""
	if have != want {
		fmt.println("---- paste into engine_api.lua ----")
		fmt.print(want)
		fmt.println("---- end ----")
	}
	testing.expect(t, have == want, "engine_api.lua's per-class connect declarations match the engine's events")
}
