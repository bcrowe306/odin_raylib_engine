package engine

import "core:fmt"
import "core:strings"
import "core:testing"
import lua "lua54"

// The global event bus (event_bus.odin): Odin listeners, deferred events,
// scoped subscriptions, and the Lua Events module.

@(private = "file")
Bus_Test_Log :: struct {
	entries: [dynamic]string,
	bus:     ^EventBus,
	lateId:  ListenerId,
}

@(private = "file")
bus_test_record :: proc(d: ^Bus_Test_Log, tag: string, source: rawptr, value: EventValue) {
	src := "nil"
	if n := cast(^Node)source; n != nil do src = n.name
	append(&d.entries, fmt.tprintf("%s:%v:%s", tag, value, src))
}

@(private = "file")
bus_test_joined :: proc(d: ^Bus_Test_Log) -> string {
	return strings.join(d.entries[:], ",", context.temp_allocator)
}

@(test)
test_event_bus_odin_listeners :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("bus", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	bus := &game.events

	d := Bus_Test_Log{entries = make([dynamic]string, context.temp_allocator), bus = bus}
	first := EventBus_Subscribe(bus, "score", proc(source: rawptr, value: EventValue, _: ^GameContext, ud: rawptr) {
		bus_test_record(cast(^Bus_Test_Log)ud, "first", source, value)
	}, &d)
	EventBus_Subscribe(bus, "score", proc(source: rawptr, value: EventValue, _: ^GameContext, ud: rawptr) {
		d := cast(^Bus_Test_Log)ud
		bus_test_record(d, "second", source, value)
		// Re-entrant: publish another event and subscribe while notified.
		if v, ok := value.(int); ok && v == 1 {
			EventBus_Publish(d.bus, "nested", "inner")
			d.lateId = EventBus_Subscribe(d.bus, "score", proc(source: rawptr, value: EventValue, _: ^GameContext, ud: rawptr) {
				bus_test_record(cast(^Bus_Test_Log)ud, "late", source, value)
			}, d)
		}
	}, &d)
	EventBus_Subscribe(bus, "nested", proc(source: rawptr, value: EventValue, _: ^GameContext, ud: rawptr) {
		bus_test_record(cast(^Bus_Test_Log)ud, "nested", source, value)
	}, &d)

	player := Node_CreateByTypeName(scene, "Node")
	player.name = "Player"
	player.gameContext = &game.gameContext

	// Subscription order; a listener added while notified runs from the next publish.
	EventBus_Publish(bus, "score", int(1), player)
	testing.expectf(t, bus_test_joined(&d) == "first:1:Player,second:1:Player,nested:inner:nil", "publish: %s", bus_test_joined(&d))
	clear(&d.entries)
	EventBus_Publish(bus, "score", int(2))
	testing.expectf(t, bus_test_joined(&d) == "first:2:nil,second:2:nil,late:2:nil", "next publish: %s", bus_test_joined(&d))
	testing.expect_value(t, EventBus_ListenerCount(bus, "score"), 3)

	// Unsubscribing.
	testing.expect(t, EventBus_Unsubscribe(bus, "score", first), "unsubscribed")
	testing.expect(t, !EventBus_Unsubscribe(bus, "score", first), "only once")
	testing.expect(t, !EventBus_Unsubscribe(bus, "nobody", first), "unknown event")
	clear(&d.entries)
	EventBus_Publish(bus, "score", int(3))
	testing.expectf(t, bus_test_joined(&d) == "second:3:nil,late:3:nil", "after unsubscribe: %s", bus_test_joined(&d))

	// Deferred: delivered by the flush at the end of the frame, in order;
	// the string value is the bus's own copy.
	clear(&d.entries)
	text := strings.clone("queued", context.temp_allocator)
	EventBus_PublishDeferred(bus, "nested", text, player)
	EventBus_PublishDeferred(bus, "nested", int(42))
	raw := transmute([]u8)text
	raw[0] = 'X' // the publisher's buffer changes; the queued value doesn't
	testing.expect_value(t, len(d.entries), 0)
	game->run(0.016)
	testing.expectf(t, bus_test_joined(&d) == "nested:queued:Player,nested:42:nil", "deferred: %s", bus_test_joined(&d))

	// A source destroyed before the flush arrives as nil; so does a node value.
	clear(&d.entries)
	EventBus_PublishDeferred(bus, "nested", player, player)
	RemoveNode(scene.manager, player)
	ProcessNodeQueues(scene.manager, &game.gameContext)
	EventBus_Flush(bus)
	testing.expectf(t, bus_test_joined(&d) == "nested:nil:nil", "dead source: %s", bus_test_joined(&d))

	// A subscription scoped to a node ends with it.
	guard := Node_CreateByTypeName(scene, "Node")
	guard.gameContext = &game.gameContext
	EventBus_Subscribe(bus, "alarm", proc(source: rawptr, value: EventValue, _: ^GameContext, ud: rawptr) {
		bus_test_record(cast(^Bus_Test_Log)ud, "alarm", source, value)
	}, &d, scope = guard)
	testing.expect_value(t, EventBus_ListenerCount(bus, "alarm"), 1)
	RemoveNode(scene.manager, guard)
	ProcessNodeQueues(scene.manager, &game.gameContext)
	testing.expect_value(t, EventBus_ListenerCount(bus, "alarm"), 0)
	clear(&d.entries)
	EventBus_Publish(bus, "alarm", true)
	testing.expect_value(t, len(d.entries), 0)

	// Undelivered events are freed with the game (the tracking allocator checks).
	EventBus_PublishDeferred(bus, "never", "delivered")
}

@(private = "file")
bus_lua_events :: proc(game: ^Game) -> string {
	L := game.scriptManager.L
	lua.getglobal(L, "events")
	defer lua.pop(L, 1)
	if lua.type(L, -1) != .TABLE do return "<no events table>"
	sb := strings.builder_make(context.temp_allocator)
	for i in 1 ..= int(lua.rawlen(L, -1)) {
		lua.rawgeti(L, -1, lua.Integer(i))
		if i > 1 do strings.write_byte(&sb, ',')
		strings.write_string(&sb, string(lua.tostring(L, -1)))
		lua.pop(L, 1)
	}
	return strings.to_string(sb)
}

@(private = "file")
bus_lua_connections :: proc(game: ^Game) -> int {
	n := 0
	for conn in game.scriptManager.connections do if conn.bus do n += 1
	return n
}

@(test)
test_event_bus_lua :: proc(t: ^testing.T) {
	ScriptVFS_RegisterEmbedded("bus_listener.lua", `
local S = {}
S.properties = {}
function S:ready()
    events = events or {}
    self.scoreId = Events.connect("score_changed", function(v, src)
        table.insert(events, "score:" .. tostring(v.points) .. ":" .. (src and src:get_name() or "nil"))
    end)
    Events.once("first_blood", function(v) table.insert(events, "once:" .. tostring(v)) end)
    Events.connect("ping", function(v)
        table.insert(events, "ping:" .. tostring(v))
        if v < 3 then Events.emit("ping", v + 1) end
    end)
    Events.connect("late", function(v) table.insert(events, "late:" .. tostring(v)) end)
    Events.connect("level_complete", function(v, src)
        table.insert(events, "level:" .. tostring(v) .. ":" .. (src and src:get_name() or "nil"))
    end)
end
function S:stop() return Events.disconnect(self.scoreId) end
return S
`)
	ScriptVFS_RegisterEmbedded("bus_emitter.lua", `
local E = {}
E.properties = {}
function E:update(dt)
    if self.sent then return end
    self.sent = true
    Events.emit("score_changed", { points = 10 })
    Events.emit("first_blood", "a")
    Events.emit("first_blood", "b")
    Events.emit("ping", 1)
    Events.emit_deferred("late", 5)
    table.insert(events, "after_emit")
end
return E
`)
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("bus_lua", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	bus := &game.events

	pings := Bus_Test_Log{entries = make([dynamic]string, context.temp_allocator), bus = bus}
	EventBus_Subscribe(bus, "ping", proc(source: rawptr, value: EventValue, _: ^GameContext, ud: rawptr) {
		bus_test_record(cast(^Bus_Test_Log)ud, "odin", source, value)
	}, &pings)

	listener := Node_CreateByTypeName(scene, "Node")
	listener.name = "Listener"
	listener.gameContext = &game.gameContext
	Script_AttachToNode(listener, "bus_listener.lua", nil, &game.scriptManager)
	emitter := Node_CreateByTypeName(scene, "Node")
	emitter.name = "Emitter"
	emitter.gameContext = &game.gameContext
	Script_AttachToNode(emitter, "bus_emitter.lua", nil, &game.scriptManager)

	game->run(0.016) // ready (connects), then the emitter's update; deferred events at the end of the frame
	game->run(0.016) // (the emitter emits once)
	ev := bus_lua_events(game)
	// Lua handlers get the Lua value (a table) and the emitting script's
	// node; once runs once; handlers may emit (nested); deferred comes last.
	testing.expectf(t, ev == "score:10:Emitter,once:a,ping:1,ping:2,ping:3,after_emit,late:5", "lua events: %s", ev)
	// Odin listeners hear Lua's events (before the Lua handlers); the source
	// is the node of the script emitting (the nested pings: the listener's).
	testing.expectf(t, bus_test_joined(&pings) == "odin:1:Emitter,odin:2:Listener,odin:3:Listener", "odin listener: %s", bus_test_joined(&pings))
	testing.expect_value(t, EventBus_ListenerCount(bus, "ping"), 2)
	testing.expect_value(t, EventBus_ListenerCount(bus, "first_blood"), 0)

	// Odin publishes reach Lua.
	EventBus_Publish(bus, "level_complete", "forest", listener)
	testing.expectf(t, strings.has_suffix(bus_lua_events(game), ",level:forest:Listener"), "odin -> lua: %s", bus_lua_events(game))

	L := game.scriptManager.L
	testing.expect(t, lua.L_dostring(L, `
count = Events.listener_count("ping")
stopped = Scene.find_node("Listener"):get_script():stop()
stopped_again = Events.disconnect(-1)
-- Global code, scoped to the emitter: released when the emitter goes.
Events.connect("tick", function() end, Scene.find_node("Emitter"))
`) == 0, "lua calls")
	lua.getglobal(L, "count")
	testing.expect_value(t, lua.tointeger(L, -1), 2)
	lua.getglobal(L, "stopped")
	testing.expect(t, bool(lua.toboolean(L, -1)), "disconnect")
	lua.getglobal(L, "stopped_again")
	testing.expect(t, !bool(lua.toboolean(L, -1)), "unknown id")
	lua.pop(L, 3)
	testing.expect_value(t, EventBus_ListenerCount(bus, "score_changed"), 0)
	testing.expect_value(t, EventBus_ListenerCount(bus, "tick"), 1)

	// Destroying the emitter ends the scoped connection; destroying the
	// listener releases the connections its script made.
	RemoveNode(scene.manager, emitter)
	ProcessNodeQueues(scene.manager, &game.gameContext)
	testing.expect_value(t, EventBus_ListenerCount(bus, "tick"), 0)
	testing.expect_value(t, bus_lua_connections(game), 3) // ping, late, level_complete
	RemoveNode(scene.manager, listener)
	ProcessNodeQueues(scene.manager, &game.gameContext)
	testing.expect_value(t, bus_lua_connections(game), 0)

	// A deferred Lua value still queued when the game ends is released.
	testing.expect(t, lua.L_dostring(L, `Events.emit_deferred("never", { 1, 2, 3 })`) == 0, "queued")
}
