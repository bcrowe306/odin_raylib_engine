package engine

import "core:c"
import "core:fmt"
import "core:strings"
import lua "lua54"

// ============================================================================
// Script inheritance (#153): a script builds on another one.
//
//   local BossHurtbox = {}
//   BossHurtbox.extends = "scripts/hurtbox.lua"
//   BossHurtbox.properties = {
//       max_health = { default = 50 },          -- the base's property, another default
//       enrage_at = { type = "float", default = 10 },
//   }
//   function BossHurtbox:take_damage(amount, attack)
//       BossHurtbox.super.take_damage(self, amount * 0.5, attack)
//   end
//   return BossHurtbox
//
// - Methods: the module table's metatable __index is the base's table, so
//   whatever the script doesn't define comes from its base (and its base's).
//   `Class.super` is the base's table: `Class.super.method(self, ...)` calls
//   the base's version. (Named by class, not `self.super`, which would loop
//   in a base that also calls its super.) ready / update / ... the script
//   defines replace the base's: call the base's from them when wanted.
// - Properties: the base's (with its own base's) and then the script's own;
//   an entry without a `type` changes only the fields it gives (a default,
//   a label) of the base's entry with that name.
// - Hot reload: a script or any script it builds on changing updates the
//   scripts built on it and their instances.
// - A loop (A extends B extends A) or a missing base: reported, and the
//   script runs without inheritance.
// ============================================================================

// The Lua merge of property tables: (base merged, own) -> merged.
@(private = "file")
MERGE_PROPERTIES_LUA :: `
local base, own = ...
local out = {}
if type(base) == "table" then for k, v in pairs(base) do out[k] = v end end
if type(own) == "table" then
	for k, v in pairs(own) do
		local b = out[k]
		if type(v) == "table" and type(b) == "table" and v.type == nil then
			local m = {}
			for bk, bv in pairs(b) do m[bk] = bv end
			for vk, vv in pairs(v) do m[vk] = vv end
			out[k] = m
		else
			out[k] = v
		end
	end
end
return out
`

// The scripts being linked to their bases, innermost last (loops; no
// allocation: a fixed stack).
@(private = "file")
extendsLinking: [64]string
@(private = "file")
extendsDepth: int

@(private = "file")
own_props_key :: proc(path: string) -> cstring {
	return strings.clone_to_cstring(strings.concatenate({"__Engine_OwnProperties_", path}, context.temp_allocator), context.temp_allocator)
}

@(private = "file")
module_key :: proc(path: string) -> cstring {
	return strings.clone_to_cstring(strings.concatenate({"__Engine_Module_", path}, context.temp_allocator), context.temp_allocator)
}

// script_extends_apply links a module table (at `modIdx`) to the script it
// extends: its metatable, `super`, and its merged `properties`. `fresh`: the
// table was just (re)loaded, so its `properties` are its own (kept for later
// merges); otherwise they're merged again from the kept ones (its base
// changed).
@(private)
script_extends_apply :: proc(mgr: ^ScriptManager, mod: ^ScriptModule, modIdx: c.int, fresh: bool) {
	L := mgr.L
	modIdx := lua.absindex(L, modIdx)
	if fresh {
		lua.pushstring(L, "properties")
		lua.rawget(L, modIdx)
		lua.setfield(L, lua.REGISTRYINDEX, own_props_key(mod.path))
	}

	lua.pushstring(L, "extends")
	lua.rawget(L, modIdx)
	ext := ""
	if lua.type(L, -1) == .STRING do ext = ScriptVFS_NormalizePath(strings.clone(string(lua.tostring(L, -1)), context.temp_allocator))
	lua.pop(L, 1)

	base: ^ScriptModule
	if ext != "" {
		problem := ""
		loop := ext == mod.path || extendsDepth >= len(extendsLinking)
		for p in extendsLinking[:extendsDepth] do if p == ext do loop = true
		if loop {
			problem = "extends itself (through a loop)"
		} else if !script_exists(mgr, ext) {
			problem = "no such script"
		} else {
			extendsLinking[extendsDepth] = mod.path
			extendsDepth += 1
			b, ok := ScriptManager_LoadModule(ext, mgr)
			extendsDepth -= 1
			if ok do base = b
			else do problem = "its base can't be loaded"
		}
		if base == nil do Script_Problem(.Warning, "[ScriptManager] %s extends \"%s\": %s - it runs without inheritance", mod.path, ext, problem)
	}

	if mod.extends != "" do delete(mod.extends)
	mod.extends = ""
	if base == nil {
		// (No base, or no more: its own properties, no metatable.)
		lua.pushnil(L)
		lua.setmetatable(L, modIdx)
		lua.pushstring(L, "properties")
		lua.getfield(L, lua.REGISTRYINDEX, own_props_key(mod.path))
		lua.rawset(L, modIdx)
		return
	}
	mod.extends = strings.clone(base.path)

	lua.getfield(L, lua.REGISTRYINDEX, module_key(base.path))
	baseIdx := lua.gettop(L)
	lua.newtable(L)
	lua.pushvalue(L, baseIdx)
	lua.setfield(L, -2, "__index")
	lua.setmetatable(L, modIdx)
	lua.pushstring(L, "super")
	lua.pushvalue(L, baseIdx)
	lua.rawset(L, modIdx)

	// properties = merge(base.properties, own)
	if lua.L_loadstring(L, MERGE_PROPERTIES_LUA) == .OK {
		lua.pushstring(L, "properties")
		lua.rawget(L, baseIdx)
		lua.getfield(L, lua.REGISTRYINDEX, own_props_key(mod.path))
		if lua.pcall(L, 2, 1, 0) == 0 {
			lua.pushstring(L, "properties")
			lua.insert(L, -2)
			lua.rawset(L, modIdx)
		} else {
			lua.pop(L, 1)
		}
	} else {
		lua.pop(L, 1)
	}
	lua.pop(L, 1) // base table
}

// script_exists: is there a script at `path` (loaded, in the project or
// the VFS)?
@(private = "file")
script_exists :: proc(mgr: ^ScriptManager, path: string) -> bool {
	if path in mgr.modules do return true
	if mgr.game != nil {
		if _, ok := AssetManager_ReadFileBytes(&mgr.game.assetManager, path, context.temp_allocator); ok do return true
	}
	code, ok := ScriptVFS_Load(path)
	if ok do delete(code)
	return ok
}

// script_extends_refresh: the scripts built on `base` (directly or not)
// merge its properties again and update their instances (it was reloaded).
@(private)
script_extends_refresh :: proc(mgr: ^ScriptManager, base: string) {
	L := mgr.L
	for _, m in mgr.modules {
		if m == nil || m.extends != base do continue
		lua.getfield(L, lua.REGISTRYINDEX, module_key(m.path))
		idx := lua.gettop(L)
		script_extends_apply(mgr, m, idx, false)
		props := Script_ParseProperties(L, idx)
		lua.pop(L, 1)
		script_module_set_properties(mgr, m, props)
		script_extends_refresh(mgr, m.path)
	}
}

// Script_Extends: does the script at `path` build on `base` (directly or
// through others), or is it `base`?
Script_Extends :: proc(mgr: ^ScriptManager, path, base: string) -> bool {
	if mgr == nil || path == "" || base == "" do return false
	b := ScriptVFS_NormalizePath(base)
	p := ScriptVFS_NormalizePath(path)
	for _ in 0 ..< 64 { // (a chain, not a loop)
		if p == b do return true
		m, ok := mgr.modules[p]
		if !ok || m == nil || m.extends == "" do return false
		p = m.extends
	}
	return false
}

// Script_ExtendsTemplate: a new script built on `basePath` ($CLASS$ for its
// class): `extends`, a properties table to change inherited defaults in, and
// a ready that calls the base's (when it has one).
Script_ExtendsTemplate :: proc(mgr: ^ScriptManager, basePath: string, allocator := context.temp_allocator) -> string {
	base := ScriptVFS_NormalizePath(basePath)
	baseClass := "ScriptInstanceBase"
	if mgr != nil && mgr.game != nil {
		if src, ok := AssetManager_ReadFileString(&mgr.game.assetManager, base, context.temp_allocator); ok {
			for line in strings.split_lines(src, context.temp_allocator) {
				l := strings.trim_space(line)
				if !strings.has_prefix(l, "---@class ") do continue
				f := strings.fields(l[len("---@class "):], context.temp_allocator)
				if len(f) > 0 do baseClass = f[0]
				break
			}
		}
	}
	hasReady := false
	if mgr != nil {
		if _, ok := ScriptManager_LoadModule(base, mgr); ok {
			L := mgr.L
			lua.getfield(L, lua.REGISTRYINDEX, module_key(base))
			lua.getfield(L, -1, "ready") // (its own or its base's)
			hasReady = lua.type(L, -1) == .FUNCTION
			lua.pop(L, 2)
		}
	}
	sb := strings.builder_make(allocator)
	fmt.sbprintf(&sb, "-- Built on %s: what this script doesn't define comes from it, its\n", base)
	strings.write_string(&sb, "-- properties included (list one below to give it another default).\n")
	fmt.sbprintf(&sb, "---@class $CLASS$ : %s\n", baseClass)
	strings.write_string(&sb, "local $CLASS$ = {}\n")
	fmt.sbprintf(&sb, "$CLASS$.extends = \"%s\"\n\n", base)
	strings.write_string(&sb, "$CLASS$.properties = {\n    -- max_health = { default = 20 }, -- (an inherited one: another default)\n}\n\n")
	if hasReady {
		strings.write_string(&sb, "function $CLASS$:ready()\n    $CLASS$.super.ready(self) -- (the base's first)\nend\n\n")
	} else {
		strings.write_string(&sb, "function $CLASS$:ready()\nend\n\n")
	}
	strings.write_string(&sb, "return $CLASS$\n")
	return strings.to_string(sb)
}
