package editor

import "core:c"
import "core:strings"
import e "../engine"
import lua "../engine/lua54"

// ============================================================================
// The Editor API plugins call (plugins.odin; design: docs/plugins.md):
//   print(...), Editor.log / warn / error(...)   the plugin's log + the console
//   Editor.plugin                               {id, name, version, dir}
// ============================================================================

// PluginAPI_Register puts the Editor table in a plugin's Lua state.
PluginAPI_Register :: proc(L: ^lua.State, p: ^Plugin) {
	lua.pushcfunction(L, plugin_print)
	lua.setglobal(L, "print")
	lua.newtable(L)
	reg :: proc(L: ^lua.State, name: cstring, f: lua.CFunction) {
		lua.pushcfunction(L, f)
		lua.setfield(L, -2, name)
	}
	reg(L, "log", plugin_print)
	reg(L, "warn", plugin_warn)
	reg(L, "error", plugin_error)
	lua.newtable(L)
	set :: proc(L: ^lua.State, k, v: string) {
		lua.pushstring(L, strings.clone_to_cstring(v, context.temp_allocator))
		lua.setfield(L, -2, strings.clone_to_cstring(k, context.temp_allocator))
	}
	set(L, "id", p.id)
	set(L, "name", p.name)
	set(L, "version", p.version)
	set(L, "dir", p.dir)
	lua.setfield(L, -2, "plugin")
	lua.setglobal(L, "Editor")
}

// PluginAPI_Forget drops what a plugin registered (it stops / reloads).
PluginAPI_Forget :: proc(p: ^Plugin) {
}

// plugin_text joins the arguments like print (tostring, tabs).
@(private = "file")
plugin_text :: proc(L: ^lua.State) -> string {
	sb := strings.builder_make(context.temp_allocator)
	n := lua.gettop(L)
	for i in 1 ..= n {
		if i > 1 do strings.write_byte(&sb, '\t')
		strings.write_string(&sb, string(lua.L_tostring(L, i)))
		lua.pop(L, 1)
	}
	return strings.to_string(sb)
}

@(private = "file")
plugin_say :: proc(L: ^lua.State, level: LogLevel) {
	p := Plugin_Of(L)
	if p == nil do return
	text := plugin_text(L)
	plugin_log(p, text)
	Editor_Log(&GlobalEditor, level, "[%s] %s", p.name, text)
}

@(private = "file")
plugin_print :: proc "c" (L: ^lua.State) -> c.int {
	context = e.Script_Context(L)
	plugin_say(L, .Info)
	return 0
}

@(private = "file")
plugin_warn :: proc "c" (L: ^lua.State) -> c.int {
	context = e.Script_Context(L)
	plugin_say(L, .Warn)
	return 0
}

@(private = "file")
plugin_error :: proc "c" (L: ^lua.State) -> c.int {
	context = e.Script_Context(L)
	plugin_say(L, .Error)
	return 0
}
