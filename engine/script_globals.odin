package engine

import "core:c"
import "core:strings"
import lua "vendor:lua/5.4"

// ============================================================================
// Global scripts (autoloads)
//
// project.json "globals": [{"name": "GameState", "script": "scripts/game_state.lua"}]
// Each script is loaded once, before any scene, and its returned table
// becomes the Lua global <name> - the same table in every script and across
// scene changes. Like node scripts it may define ready(self) (called once
// when the game starts; in the editor, when Simulate starts) and
// update(self, dt) (every frame, not while the game is paused).
// ============================================================================

// Globals_Load (re)loads the global scripts: earlier globals are removed,
// then each script's table is set as its Lua global.
Globals_Load :: proc(mgr: ^ScriptManager, list: []Global_Script) {
	if mgr == nil do return
	if !mgr.isReady && !ScriptManager_Init(mgr) do return
	globals_clear(mgr)
	L := mgr.L
	for g in list {
		if !Globals_ValidName(g.name) {
			Script_Problem(.Warning, "[Globals] '%s' is not a valid Lua name (letters, digits, _; not starting with a digit)", g.name)
			continue
		}
		mod, ok := ScriptManager_LoadModule(g.script, mgr)
		if !ok {
			Script_Problem(.Warning, "[Globals] %s: could not load %s", g.name, g.script)
			continue
		}
		push_module(L, mod.path)
		lua.setglobal(L, strings.clone_to_cstring(g.name, context.temp_allocator))
		append(&mgr.globals, Global_Script{strings.clone(g.name), strings.clone(mod.path)})
	}
}

// Globals_Ready calls each global script's ready(self).
Globals_Ready :: proc(mgr: ^ScriptManager) {
	if mgr == nil || !mgr.isReady do return
	for g in mgr.globals do call_global(mgr, g, "ready", 0, false)
}

// Globals_Update calls each global script's update(self, dt) (not while the
// script manager is suspended: the editor outside Simulate).
Globals_Update :: proc(mgr: ^ScriptManager, dt: f32) {
	if mgr == nil || !mgr.isReady || mgr.suspended do return
	for g in mgr.globals do call_global(mgr, g, "update", dt, true)
}

// Globals_NameOf: the global name a script is loaded as ("" = none).
Globals_NameOf :: proc(list: []Global_Script, script: string) -> string {
	for g in list do if g.script == script do return g.name
	return ""
}

Globals_ValidName :: proc(name: string) -> bool {
	if name == "" do return false
	for r, i in name {
		switch r {
		case 'a' ..= 'z', 'A' ..= 'Z', '_':
		case '0' ..= '9':
			if i == 0 do return false
		case:
			return false
		}
	}
	return true
}

globals_clear :: proc(mgr: ^ScriptManager) {
	for g in mgr.globals {
		if mgr.L != nil {
			lua.pushnil(mgr.L)
			lua.setglobal(mgr.L, strings.clone_to_cstring(g.name, context.temp_allocator))
		}
		delete(g.name)
		delete(g.script)
	}
	clear(&mgr.globals)
}

@(private = "file")
push_module :: proc(L: ^lua.State, path: string) {
	key := strings.clone_to_cstring(strings.concatenate({"__Engine_Module_", path}, context.temp_allocator), context.temp_allocator)
	lua.getfield(L, lua.REGISTRYINDEX, key)
}

@(private = "file")
call_global :: proc(mgr: ^ScriptManager, g: Global_Script, fn: cstring, dt: f32, withDt: bool) {
	L := mgr.L
	lua.pushcfunction(L, lua_traceback_error_handler)
	errHandler := lua.gettop(L)
	push_module(L, g.script)
	if lua.type(L, -1) == .TABLE {
		lua.getfield(L, -1, fn)
		if lua.type(L, -1) == .FUNCTION {
			lua.pushvalue(L, -2) // self = the global's table
			nargs: c.int = 1
			if withDt {
				lua.pushnumber(L, lua.Number(dt))
				nargs = 2
			}
			prev := mgr.currentInstance
			mgr.currentInstance = nil
			if lua.pcall(L, nargs, 0, errHandler) != 0 {
				Script_Problem(.Error, "[Globals] Error in %s:%s(): %s", g.name, fn, lua.tostring(L, -1))
				lua.pop(L, 1)
			}
			mgr.currentInstance = prev
		} else {
			lua.pop(L, 1)
		}
	}
	lua.pop(L, 2) // module, errHandler
}
