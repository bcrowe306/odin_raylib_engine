package editor

import "core:c"
import "core:fmt"
import "core:slice"
import "core:strings"
import e "../engine"
import lua "../engine/lua54"

// ============================================================================
// Plugin events (TODO 13.5; docs/plugins.md): Editor.on(event, fn).
//
//   project_opened(project)        when the plugin starts (the project is open)
//   selection_changed(nodes)       the selection changed (checked once a frame)
//   scene_saved(path)              a scene was written (project-relative path)
//   asset_imported(path)           an asset was imported into the project
//   before_play(scene_path)        Play / Play Scene is about to start: a
//                                  handler returning false (, reason) cancels it
//   after_export(preset, dir)      an export preset was exported to dir
//
// Handlers run protected: an error stops that plugin (Plugin_Call).
// ============================================================================

@(private = "file")
Plugin_Hook :: struct {
	plugin: ^Plugin,
	event:  string,
	ref:    c.int,
}

@(private = "file")
events: struct {
	hooks:         [dynamic]Plugin_Hook,
	lastSelection: [dynamic]^e.Node,
}

PLUGIN_EVENTS := [?]string{"project_opened", "selection_changed", "scene_saved", "asset_imported", "before_play", "after_export"}

// Editor.on(event, fn)
api_on :: proc "c" (L: ^lua.State) -> c.int {
	context = e.Script_Context(L)
	name := string(lua.L_checkstring(L, 1))
	lua.L_checktype(L, 2, c.int(lua.Type.FUNCTION))
	if !slice.contains(PLUGIN_EVENTS[:], name) {
		lua.pushstring(L, strings.clone_to_cstring(fmt.tprintf("on: unknown event %q (%s)", name, strings.join(PLUGIN_EVENTS[:], ", ", context.temp_allocator)), context.temp_allocator))
		return c.int(lua.error(L))
	}
	lua.pushvalue(L, 2)
	append(&events.hooks, Plugin_Hook{Plugin_Of(L), strings.clone(name), lua.L_ref(L, lua.REGISTRYINDEX)})
	return 0
}

// PluginEvents_Forget drops a plugin's handlers (it stops / reloads).
PluginEvents_Forget :: proc(p: ^Plugin) {
	for i := len(events.hooks) - 1; i >= 0; i -= 1 {
		if events.hooks[i].plugin != p do continue
		delete(events.hooks[i].event)
		ordered_remove(&events.hooks, i)
	}
}

// Event arguments.
Plugin_Event_Arg :: union {
	string,
	[]^e.Node,
	^e.Node,
}

// PluginEvents_Emit calls every handler of `event` with `args`. The first
// handler that returns false stops it: ok = false, reason = its 2nd result.
PluginEvents_Emit :: proc(state: ^EditorState, event: string, args: ..Plugin_Event_Arg) -> (ok: bool, reason: string) {
	ok = true
	// (Copied: a handler may add or drop handlers.)
	hooks := slice.clone(events.hooks[:], context.temp_allocator)
	for h in hooks {
		if h.event != event do continue
		p := h.plugin
		if p.state != .Running || p.mgr == nil do continue
		L := p.mgr.L
		lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(h.ref))
		for a in args do push_event_arg(L, a)
		if !Plugin_Call(state, p, c.int(len(args)), 2, fmt.tprintf("on %s", event)) do continue
		if lua.type(L, -2) == .BOOLEAN && !lua.toboolean(L, -2) {
			ok = false
			reason = strings.clone(string(lua.tostring(L, -1)), context.temp_allocator) if lua.type(L, -1) == .STRING else fmt.tprintf("%s said no", p.name)
		}
		lua.pop(L, 2)
		if !ok do return
	}
	return
}

// PluginEvents_EmitTo: one plugin's handlers (project_opened as it starts).
PluginEvents_EmitTo :: proc(state: ^EditorState, p: ^Plugin, event: string, args: ..Plugin_Event_Arg) {
	for h in slice.clone(events.hooks[:], context.temp_allocator) {
		if h.plugin != p || h.event != event || p.state != .Running || p.mgr == nil do continue
		L := p.mgr.L
		lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(h.ref))
		for a in args do push_event_arg(L, a)
		_ = Plugin_Call(state, p, c.int(len(args)), 0, fmt.tprintf("on %s", event))
	}
}

// PluginEvents_Update: selection_changed (once a frame).
PluginEvents_Update :: proc(state: ^EditorState) {
	if len(events.hooks) == 0 do return
	now := state.selection[:]
	if len(now) == 0 && state.selectedNode != nil do now = {state.selectedNode}
	if slice.equal(now, events.lastSelection[:]) do return
	clear(&events.lastSelection)
	append(&events.lastSelection, ..now)
	_, _ = PluginEvents_Emit(state, "selection_changed", now)
}

@(private = "file")
push_event_arg :: proc(L: ^lua.State, a: Plugin_Event_Arg) {
	switch v in a {
	case string:
		lua.pushstring(L, strings.clone_to_cstring(v, context.temp_allocator))
	case ^e.Node:
		e.push_node_userdata(L, v)
	case []^e.Node:
		lua.newtable(L)
		for n, i in v {
			e.push_node_userdata(L, n)
			lua.rawseti(L, -2, lua.Integer(i + 1))
		}
	case:
		lua.pushnil(L)
	}
}
