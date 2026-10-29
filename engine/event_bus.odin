package engine

import "core:c"
import "core:strings"
import lua "lua54"

// ============================================================================
// Global event bus
//
// Named events anyone can publish and anyone can listen to, without a
// reference to each other: gameplay -> UI ("score_changed"), a level -> the
// game flow ("level_complete"), audio / achievements reacting to gameplay.
// (Node events - EventSubject, node:emit / node:connect - need the source
// node; these don't.) The bus is the game's (game.events) and lasts across
// scene changes.
//
// Odin:
//   id := EventBus_Subscribe(&game.events, "player_died", on_player_died, data, scope = node)
//   EventBus_Publish(&game.events, "player_died", value, source = node)
//   EventBus_PublishDeferred(...)  delivered at the end of the frame
//   EventBus_Unsubscribe(&game.events, "player_died", id)
// Lua (the Events global, script_events.odin):
//   local id = Events.connect("player_died", function(value, source) ... end)
//   Events.emit("player_died", { lives = 0 })
//
// A publish reaches the Odin listeners, then the Lua handlers, each in
// subscription order. Handlers may publish, (un)subscribe or destroy nodes
// while an event is delivered. Deferred events are delivered by
// EventBus_Flush (after the scene's update each frame); those published
// while flushing wait for the next flush. Subscriptions with a scope node
// end when that node is destroyed; Lua handlers also end with the script
// that connected them.
// ============================================================================

EventBus :: struct {
	ctx:      ^GameContext,                // the game's (publish delivers to its scripts)
	subjects: map[string]^EventSubject,    // Odin listeners per event name (heap: stable while notifying)
	scoped:   [dynamic]Bus_Scoped,         // Odin subscriptions that end with a node
	queue:    [dynamic]Bus_Queued,         // deferred events (EventBus_Flush)
}

@(private = "file")
Bus_Scoped :: struct {
	name: string, // the subject's name (owned by the subject)
	id:   ListenerId,
	node: ^Node,
}

@(private = "file")
Bus_Queued :: struct {
	name:   string,     // heap
	value:  EventValue, // a string value on the heap
	source: ^Node,
	luaRef: c.int,      // the Lua value (Events.emit_deferred) for Lua handlers; 0 = none
}

EventBus_Init :: proc(bus: ^EventBus, ctx: ^GameContext) {
	bus.ctx = ctx
}

// EventBus_Destroy frees the listeners and drops undelivered events (L
// releases their Lua values: call it before the Lua state closes).
EventBus_Destroy :: proc(bus: ^EventBus, L: ^lua.State) {
	if bus == nil do return
	for _, s in bus.subjects {
		DestroySubject(s)
		delete(s.name, Engine_HeapAllocator())
		free(s, Engine_HeapAllocator())
	}
	delete(bus.subjects)
	bus.subjects = nil
	delete(bus.scoped)
	bus.scoped = nil
	for q in bus.queue do queued_free(q, L)
	delete(bus.queue)
	bus.queue = nil
}

// EventBus_Subscribe calls `callback` for every publish of `name` (source:
// the publishing ^Node, or nil). With a scope, the subscription ends when
// that node is destroyed.
EventBus_Subscribe :: proc(bus: ^EventBus, name: string, callback: proc(source: rawptr, value: EventValue, gameContext: ^GameContext, user_data: rawptr), user_data: rawptr = nil, scope: ^Node = nil) -> ListenerId {
	s := bus.subjects[name]
	if s == nil {
		if bus.subjects == nil do bus.subjects = make(map[string]^EventSubject, allocator = Engine_HeapAllocator())
		s = new(EventSubject, Engine_HeapAllocator())
		InitializeSubject(s, strings.clone(name, Engine_HeapAllocator())) // no owner: nothing for node scripts
		s.listeners = make([dynamic]EventSubscription, Engine_HeapAllocator())
		bus.subjects[s.name] = s
	}
	id := Subscribe(s, callback, user_data)
	if scope != nil {
		if bus.scoped == nil do bus.scoped = make([dynamic]Bus_Scoped, Engine_HeapAllocator())
		append(&bus.scoped, Bus_Scoped{s.name, id, scope})
	}
	return id
}

// EventBus_Unsubscribe ends a subscription; false when there was none.
EventBus_Unsubscribe :: proc(bus: ^EventBus, name: string, id: ListenerId) -> bool {
	s := bus.subjects[name]
	if s == nil do return false
	for l, i in s.listeners {
		if l.id == id {
			ordered_remove(&s.listeners, i) // keep notification order
			for sc, j in bus.scoped do if sc.id == id {unordered_remove(&bus.scoped, j); break}
			return true
		}
	}
	return false
}

// EventBus_ForgetNode ends the subscriptions scoped to a node (it is being
// destroyed).
EventBus_ForgetNode :: proc(bus: ^EventBus, node: ^Node) {
	for i := len(bus.scoped) - 1; i >= 0; i -= 1 {
		if sc := bus.scoped[i]; sc.node == node do EventBus_Unsubscribe(bus, sc.name, sc.id)
	}
}

// EventBus_Publish delivers an event now: the Odin listeners, then the
// Lua handlers (Events.connect).
EventBus_Publish :: proc(bus: ^EventBus, name: string, value: EventValue = nil, source: ^Node = nil) {
	EventBus_PublishLua(bus, name, value, source, 0)
}

// EventBus_PublishLua: EventBus_Publish with the Lua value Lua handlers
// get instead of `value` (a registry ref; 0 = push `value`).
EventBus_PublishLua :: proc(bus: ^EventBus, name: string, value: EventValue, source: ^Node, luaRef: c.int) {
	if bus == nil || name == "" do return
	if s := bus.subjects[name]; s != nil && len(s.listeners) > 0 do Notify(s, source, value, bus.ctx)
	if bus.ctx != nil do Script_DispatchBusEvent(bus.ctx.scriptManager, name, value, source, luaRef)
}

// EventBus_PublishDeferred queues an event for the next EventBus_Flush (the
// end of the frame): publishers in the middle of an update don't run
// listeners there.
EventBus_PublishDeferred :: proc(bus: ^EventBus, name: string, value: EventValue = nil, source: ^Node = nil) {
	EventBus_PublishDeferredLua(bus, name, value, source, 0)
}

// EventBus_PublishDeferredLua: EventBus_PublishDeferred holding a Lua value
// (a registry ref the bus releases once delivered).
EventBus_PublishDeferredLua :: proc(bus: ^EventBus, name: string, value: EventValue, source: ^Node, luaRef: c.int) {
	if bus == nil || name == "" do return
	if bus.queue == nil do bus.queue = make([dynamic]Bus_Queued, Engine_HeapAllocator())
	v := value
	if s, ok := value.(string); ok do v = strings.clone(s, Engine_HeapAllocator())
	append(&bus.queue, Bus_Queued{strings.clone(name, Engine_HeapAllocator()), v, source, luaRef})
}

// EventBus_Flush delivers the deferred events, in publish order. A source
// or node value destroyed since the publish arrives as nil.
EventBus_Flush :: proc(bus: ^EventBus) {
	if bus == nil || len(bus.queue) == 0 do return
	pending := bus.queue
	bus.queue = nil // what handlers publish now waits for the next flush
	L: ^lua.State
	if bus.ctx != nil && bus.ctx.scriptManager != nil do L = bus.ctx.scriptManager.L
	for q in pending {
		source := q.source if Node_IsAlive(q.source) else nil
		value := q.value
		if n, ok := value.(^Node); ok && !Node_IsAlive(n) do value = nil
		EventBus_PublishLua(bus, q.name, value, source, q.luaRef)
		queued_free(q, L)
	}
	delete(pending)
}

// EventBus_ListenerCount: the Odin listeners and Lua handlers of an event.
EventBus_ListenerCount :: proc(bus: ^EventBus, name: string) -> int {
	n := 0
	if s := bus.subjects[name]; s != nil do n = len(s.listeners)
	if bus.ctx != nil do n += Script_BusConnectionCount(bus.ctx.scriptManager, name)
	return n
}

@(private = "file")
queued_free :: proc(q: Bus_Queued, L: ^lua.State) {
	delete(q.name, Engine_HeapAllocator())
	if s, ok := q.value.(string); ok do delete(s, Engine_HeapAllocator())
	if q.luaRef != 0 && L != nil do lua.L_unref(L, lua.REGISTRYINDEX, q.luaRef)
}
