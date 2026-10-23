package engine

import "base:runtime"
import "core:c"
import "core:log"
import "core:strings"
import lua "vendor:lua/5.4"

// ============================================================================
// Lua Script Manager & Instance Lifecycle Controller
// ============================================================================

scriptManager: ScriptManager

ScriptManager_Init :: proc(sm: ^ScriptManager = nil, game: ^Game = nil) -> bool {
	mgr := sm if sm != nil else &scriptManager
	if mgr.isReady do return true

	// Script logs use the logger the game runs with (script_bindings.odin).
	if scriptLogger.procedure == nil do scriptLogger = context.logger
	mgr.L = lua.L_newstate()
	if mgr.L == nil {
		log.error("[ScriptManager] Failed to create Lua 5.4 state")
		return false
	}

	lua.L_openlibs(mgr.L)

	ScriptVFS_Init()
	ScriptVFS_RegisterLuaSearcher(mgr.L)
	RegisterEngineLuaBindings(mgr.L, mgr)

	mgr.game = game
	mgr.modules = make(map[string]^ScriptModule)
	mgr.instances = make([dynamic]^ScriptInstance)
	mgr.isReady = true

	log.info("[ScriptManager] Lua 5.4 scripting engine successfully initialized")
	return true
}

ScriptManager_Destroy :: proc(sm: ^ScriptManager = nil) {
	mgr := sm if sm != nil else &scriptManager
	if !mgr.isReady do return

	Script_ReleaseAllConnections(mgr)

	// Destroy all active instances
	for len(mgr.instances) > 0 {
		inst := mgr.instances[0]
		ScriptInstance_Destroy(inst, mgr)
	}
	delete(mgr.instances)

	// Clean up cached modules
	for k, mod in mgr.modules {
		delete(k)
		delete(mod.diskPath)
		for p in mod.properties {
			delete(p.name)
			delete(p.label)
			if p.assetKind != "" do delete(p.assetKind)
			if p.type == .String && len(p.defaultVal.valString) > 0 {
				delete(p.defaultVal.valString)
			}
		}
		delete(mod.properties)
		free(mod)
	}
	delete(mgr.modules)

	if mgr.L != nil {
		lua.close(mgr.L)
		mgr.L = nil
	}
	mgr.isReady = false
	log.info("[ScriptManager] Lua scripting engine terminated")
}

lua_traceback_error_handler :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	msg := lua.tostring(L, 1)
	lua.L_traceback(L, L, msg, 1)
	return 1
}

// Loads and compiles a Lua script module, parsing its exported properties
ScriptManager_LoadModule :: proc(path: string, sm: ^ScriptManager = nil) -> (^ScriptModule, bool) {
	mgr := sm if sm != nil else &scriptManager
	if !mgr.isReady {
		if !ScriptManager_Init(mgr) do return nil, false
	}

	normPath := ScriptVFS_NormalizePath(path)
	if existing, exists := mgr.modules[normPath]; exists {
		return existing, true
	}

	// Project scripts resolve through the asset manager first (project
	// directory or mounted .ore package), then the VFS / working directory.
	code, ok := "", false
	if mgr.game != nil {
		am := &mgr.game.assetManager
		rel := normPath
		if dir := strings.trim_suffix(am.projectDir, "/"); dir != "" && strings.has_prefix(rel, dir) && len(rel) > len(dir) && rel[len(dir)] == '/' {
			rel = rel[len(dir) + 1:]
		}
		code, ok = AssetManager_ReadFileString(am, rel)
	}
	if !ok do code, ok = ScriptVFS_Load(normPath)
	if !ok {
		log.errorf("[ScriptManager] Failed to find script file: %s", normPath)
		return nil, false
	}
	defer delete(code)

	L := mgr.L
	chunkNameC := strings.clone_to_cstring(strings.concatenate({"@", normPath}, context.temp_allocator), context.temp_allocator)
	codeC := raw_data(transmute([]u8)code)

	loadStatus := lua.L_loadbuffer(L, cast([^]u8)codeC, c.size_t(len(code)), chunkNameC)
	if loadStatus != .OK {
		errStr := lua.tostring(L, -1)
		log.errorf("[ScriptManager] Syntax error compiling '%s': %s", normPath, errStr)
		lua.pop(L, 1)
		return nil, false
	}

	// Execute chunk with pcall (0 args, 1 return value expected: the module table)
	pcallStatus := lua.pcall(L, 0, 1, 0)
	if pcallStatus != 0 {
		errStr := lua.tostring(L, -1)
		log.errorf("[ScriptManager] Runtime error loading '%s': %s", normPath, errStr)
		lua.pop(L, 1)
		return nil, false
	}

	if lua.type(L, -1) != .TABLE {
		log.warnf("[ScriptManager] Script '%s' did not return a table (got %s). Wrapping in empty table.", normPath, lua.typename(L, lua.type(L, -1)))
		lua.pop(L, 1)
		lua.newtable(L)
	}

	// Store module table in registry so it is not garbage collected
	moduleRefKey := strings.clone_to_cstring(strings.concatenate({"__Engine_Module_", normPath}, context.temp_allocator), context.temp_allocator)
	lua.setfield(L, lua.REGISTRYINDEX, moduleRefKey)

	mod := new(ScriptModule)
	mod.path = strings.clone(normPath)
	mod.properties = make([dynamic]ScriptProperty)
	mod.isLoaded = true

	// Retrieve module table to inspect its properties
	lua.getfield(L, lua.REGISTRYINDEX, moduleRefKey)
	delete(mod.properties)
	mod.properties = Script_ParseProperties(L, lua.gettop(L))
	lua.pop(L, 1) // module table
	ScriptModule_TrackFile(mgr, mod)


	mgr.modules[mod.path] = mod
	return mod, true
}

// Standalone reflection helper to inspect properties of a script file without attaching
Script_InspectProperties :: proc(scriptPath: string, sm: ^ScriptManager = nil) -> ([]ScriptProperty, bool) {
	mgr := sm if sm != nil else &scriptManager
	mod, ok := ScriptManager_LoadModule(scriptPath, mgr)
	if !ok do return nil, false
	return mod.properties[:], true
}

// Attaches a script module to an existing node, instantiating its Lua table & properties
Script_AttachToNode :: proc(node: ^Node, scriptPath: string, overrides: map[string]ScriptValue = nil, sm: ^ScriptManager = nil) -> ^ScriptInstance {
	if node == nil do return nil
	mgr := sm
	if mgr == nil && node.gameContext != nil {
		mgr = node.gameContext.scriptManager
	}
	if mgr == nil do mgr = &scriptManager
	if !mgr.isReady {
		if !ScriptManager_Init(mgr) do return nil
	}

	// Detach previous script if one was attached
	if node.scriptInstance != nil {
		ScriptInstance_Destroy(cast(^ScriptInstance)node.scriptInstance, mgr)
		node.scriptInstance = nil
	}

	mod, ok := ScriptManager_LoadModule(scriptPath, mgr)
	if !ok do return nil

	L := mgr.L

	// 1. Create instance table: `local self = {}`
	lua.newtable(L)
	instanceTableIdx := lua.gettop(L)

	// 2. Set self.node = node_userdata
	push_node_userdata(L, node)
	lua.setfield(L, instanceTableIdx, "node")

	// 3. Set metatable: setmetatable(self, { __index = moduleTable })
	normPath := ScriptVFS_NormalizePath(scriptPath)
	moduleRefKey := strings.clone_to_cstring(strings.concatenate({"__Engine_Module_", normPath}, context.temp_allocator), context.temp_allocator)

	lua.newtable(L) // metatable
	lua.getfield(L, lua.REGISTRYINDEX, moduleRefKey) // module table
	lua.setfield(L, -2, "__index")
	lua.setmetatable(L, instanceTableIdx)

	inst := new(ScriptInstance)
	inst.node = node
	inst.scriptManager = mgr
	inst.modulePath = strings.clone(normPath)
	inst.properties = make(map[string]ScriptValue)
	inst.isReady = false

	// 4. Initialize instance properties with defaults, applying any overrides
	for prop in mod.properties {
		val := prop.defaultVal
		if overrides != nil {
			if overrideVal, hasOverride := overrides[prop.name]; hasOverride {
				val = overrideVal
			}
		}
		// The instance owns its strings (the default belongs to the module,
		// overrides are often temp-allocated): sharing them double-freed.
		if val.type == .String do val.valString = strings.clone(val.valString)
		inst.properties[strings.clone(prop.name)] = val

		// Push value to self[prop.name]
		propNameC := strings.clone_to_cstring(prop.name, context.temp_allocator)
		switch val.type {
		case .Float:
			lua.pushnumber(L, lua.Number(val.valFloat))
		case .Int:
			lua.pushinteger(L, lua.Integer(val.valInt))
		case .String:
			sC := strings.clone_to_cstring(val.valString, context.temp_allocator)
			lua.pushstring(L, sC)
		case .Boolean:
			lua.pushboolean(L, b32(val.valBool))
		case .Color:
			lua.createtable(L, 4, 0)
			lua.pushnumber(L, lua.Number(val.valColor.r)); lua.rawseti(L, -2, 1)
			lua.pushnumber(L, lua.Number(val.valColor.g)); lua.rawseti(L, -2, 2)
			lua.pushnumber(L, lua.Number(val.valColor.b)); lua.rawseti(L, -2, 3)
			lua.pushnumber(L, lua.Number(val.valColor.a)); lua.rawseti(L, -2, 4)
		case .Vector2:
			lua.createtable(L, 2, 0)
			lua.pushnumber(L, lua.Number(val.valVec2.x)); lua.rawseti(L, -2, 1)
			lua.pushnumber(L, lua.Number(val.valVec2.y)); lua.rawseti(L, -2, 2)
		}
		lua.setfield(L, instanceTableIdx, propNameC)
	}

	// 5. Save self table into registry to keep it alive
	inst.registryRef = lua.L_ref(L, lua.REGISTRYINDEX)

	node.scriptInstance = inst
	append(&mgr.instances, inst)

	// If node is already ready, invoke script ready immediately
	if node.isReady {
		ScriptInstance_CallReady(inst, mgr)
	}

	return inst
}

// Alias for Script_AttachToNode
Node_AttachScript :: Script_AttachToNode

ScriptInstance_CallReady :: proc(inst: ^ScriptInstance, sm: ^ScriptManager = nil) {
	if inst == nil || inst.isReady do return
	mgr := sm
	if mgr == nil && inst.scriptManager != nil do mgr = inst.scriptManager
	if mgr == nil do mgr = &scriptManager
	if !mgr.isReady || mgr.L == nil do return

	L := mgr.L
	lua.pushcfunction(L, lua_traceback_error_handler)
	errHandler := lua.gettop(L)

	lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(inst.registryRef)) // push self
	lua.getfield(L, -1, "ready")
	if lua.type(L, -1) == .FUNCTION {
		lua.pushvalue(L, -2) // pass self as first arg
		prev := mgr.currentInstance
		mgr.currentInstance = inst
		status := lua.pcall(L, 1, 0, errHandler)
		mgr.currentInstance = prev
		if status != 0 {
			errStr := lua.tostring(L, -1)
			log.errorf("[ScriptInstance] Error in ready() for '%s': %s", inst.modulePath, errStr)
			lua.pop(L, 1)
		}
	} else {
		lua.pop(L, 1) // pop non-function
	}

	lua.pop(L, 1) // pop self
	lua.pop(L, 1) // pop errHandler
	inst.isReady = true
}

ScriptInstance_CallUpdate :: proc(inst: ^ScriptInstance, deltaTime: f32, sm: ^ScriptManager = nil) {
	if inst == nil do return
	mgr := sm
	if mgr == nil && inst.scriptManager != nil do mgr = inst.scriptManager
	if mgr == nil do mgr = &scriptManager
	if !mgr.isReady || mgr.L == nil do return

	L := mgr.L
	lua.pushcfunction(L, lua_traceback_error_handler)
	errHandler := lua.gettop(L)

	lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(inst.registryRef)) // push self
	lua.getfield(L, -1, "update")
	if lua.type(L, -1) == .FUNCTION {
		lua.pushvalue(L, -2) // pass self as 1st arg
		lua.pushnumber(L, lua.Number(deltaTime)) // pass dt as 2nd arg
		prev := mgr.currentInstance
		mgr.currentInstance = inst
		status := lua.pcall(L, 2, 0, errHandler)
		mgr.currentInstance = prev
		if status != 0 {
			errStr := lua.tostring(L, -1)
			log.errorf("[ScriptInstance] Error in update() for '%s': %s", inst.modulePath, errStr)
			lua.pop(L, 1)
		}
	} else {
		lua.pop(L, 1)
	}

	lua.pop(L, 1) // pop self
	lua.pop(L, 1) // pop errHandler
}

ScriptInstance_CallDestroy :: proc(inst: ^ScriptInstance, sm: ^ScriptManager = nil) {
	if inst == nil do return
	mgr := sm
	if mgr == nil && inst.scriptManager != nil do mgr = inst.scriptManager
	if mgr == nil do mgr = &scriptManager
	if !mgr.isReady || mgr.L == nil do return

	L := mgr.L
	lua.pushcfunction(L, lua_traceback_error_handler)
	errHandler := lua.gettop(L)

	lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(inst.registryRef))
	lua.getfield(L, -1, "on_destroy")
	if lua.type(L, -1) == .FUNCTION {
		lua.pushvalue(L, -2) // pass self
		status := lua.pcall(L, 1, 0, errHandler)
		if status != 0 {
			errStr := lua.tostring(L, -1)
			log.errorf("[ScriptInstance] Error in on_destroy() for '%s': %s", inst.modulePath, errStr)
			lua.pop(L, 1)
		}
	} else {
		lua.pop(L, 1)
	}

	lua.pop(L, 1) // pop self
	lua.pop(L, 1) // pop errHandler
}

ScriptInstance_Destroy :: proc(inst: ^ScriptInstance, sm: ^ScriptManager = nil) {
	if inst == nil do return
	mgr := sm
	if mgr == nil && inst.scriptManager != nil do mgr = inst.scriptManager
	if mgr == nil do mgr = &scriptManager

	if inst.node != nil {
		inst.node.scriptInstance = nil
		inst.node = nil
	}

	ScriptInstance_CallDestroy(inst, mgr)
	Script_ForgetInstance(mgr, inst)

	if mgr.L != nil && inst.registryRef != 0 {
		lua.L_unref(mgr.L, lua.REGISTRYINDEX, inst.registryRef)
		inst.registryRef = 0
	}

	// Remove from instances list
	for i in 0..<len(mgr.instances) {
		if mgr.instances[i] == inst {
			unordered_remove(&mgr.instances, i)
			break
		}
	}

	delete(inst.modulePath)
	for k, v in inst.properties {
		delete(k)
		if v.type == .String && len(v.valString) > 0 {
			delete(v.valString)
		}
	}
	delete(inst.properties)
	free(inst)
}

// Set property value live on a ScriptInstance (reactively updates Lua table and Odin cache)
ScriptInstance_SetProperty :: proc(inst: ^ScriptInstance, name: string, val: ScriptValue, sm: ^ScriptManager = nil) -> bool {
	if inst == nil do return false
	mgr := sm
	if mgr == nil && inst.scriptManager != nil do mgr = inst.scriptManager
	if mgr == nil do mgr = &scriptManager
	if !mgr.isReady || mgr.L == nil do return false

	L := mgr.L
	lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(inst.registryRef)) // push self
	propNameC := strings.clone_to_cstring(name, context.temp_allocator)

	switch val.type {
	case .Float:
		lua.pushnumber(L, lua.Number(val.valFloat))
	case .Int:
		lua.pushinteger(L, lua.Integer(val.valInt))
	case .String:
		sC := strings.clone_to_cstring(val.valString, context.temp_allocator)
		lua.pushstring(L, sC)
	case .Boolean:
		lua.pushboolean(L, b32(val.valBool))
	case .Color:
		lua.createtable(L, 4, 0)
		lua.pushnumber(L, lua.Number(val.valColor.r)); lua.rawseti(L, -2, 1)
		lua.pushnumber(L, lua.Number(val.valColor.g)); lua.rawseti(L, -2, 2)
		lua.pushnumber(L, lua.Number(val.valColor.b)); lua.rawseti(L, -2, 3)
		lua.pushnumber(L, lua.Number(val.valColor.a)); lua.rawseti(L, -2, 4)
	case .Vector2:
		lua.createtable(L, 2, 0)
		lua.pushnumber(L, lua.Number(val.valVec2.x)); lua.rawseti(L, -2, 1)
		lua.pushnumber(L, lua.Number(val.valVec2.y)); lua.rawseti(L, -2, 2)
	}
	lua.setfield(L, -2, propNameC)
	lua.pop(L, 1) // pop self

	// Update cached property. Copy the new key/value *before* releasing the
	// old entry: callers commonly pass the map's own key string as `name`
	// (and possibly its old string value), which the release would free.
	key := strings.clone(name)
	newVal := val
	if newVal.type == .String {
		newVal.valString = strings.clone(val.valString)
	}
	if _, exists := inst.properties[key]; exists {
		oldKey, oldVal := delete_key(&inst.properties, key)
		if oldVal.type == .String && len(oldVal.valString) > 0 {
			delete(oldVal.valString)
		}
		delete(oldKey)
	}
	inst.properties[key] = newVal
	return true
}

// Get property value live from a ScriptInstance
ScriptInstance_GetProperty :: proc(inst: ^ScriptInstance, name: string) -> (ScriptValue, bool) {
	if inst == nil do return {}, false
	val, ok := inst.properties[name]
	return val, ok
}

// Script_ParseProperties reads a module table's `properties` declarations
// (module table at stack index `moduleIdx`). Stack is left unchanged.
Script_ParseProperties :: proc(L: ^lua.State, moduleIdx: c.int) -> [dynamic]ScriptProperty {
	props := make([dynamic]ScriptProperty)
	lua.getfield(L, moduleIdx, "properties")
	if lua.type(L, -1) == .TABLE {
		// Iterate through properties table
		lua.pushnil(L)
		for lua.next(L, -2) != 0 {
			// key is at -2, value (property spec table) is at -1
			propNameC := lua.tostring(L, -2)
			if propNameC != nil && lua.type(L, -1) == .TABLE {
				prop := ScriptProperty{
					name = strings.clone(string(propNameC)),
				}

				// 1. Property Type
				lua.getfield(L, -1, "type")
				typeStr := lua.tostring(L, -1)
				if typeStr != nil {
					switch string(typeStr) {
					case "float", "number": prop.type = .Float
					case "int", "integer":  prop.type = .Int
					case "string":          prop.type = .String
					case "bool", "boolean": prop.type = .Boolean
					case "color":           prop.type = .Color
					case "vector2", "vec2": prop.type = .Vector2
					case "texture", "audio", "scene", "script", "component", "level", "file":
						prop.type = .String
						prop.assetKind = strings.clone(string(typeStr))
					case:                   prop.type = .Float
					}
				}
				lua.pop(L, 1)

				// 2. Default Value
				lua.getfield(L, -1, "default")
				prop.defaultVal.type = prop.type
				switch prop.type {
				case .Float:
					prop.defaultVal.valFloat = f32(lua.tonumber(L, -1))
				case .Int:
					prop.defaultVal.valInt = i64(lua.tointeger(L, -1))
				case .String:
					sC := lua.tostring(L, -1)
					if sC != nil {
						prop.defaultVal.valString = strings.clone(string(sC))
					}
				case .Boolean:
					prop.defaultVal.valBool = bool(lua.toboolean(L, -1))
				case .Color:
					if lua.type(L, -1) == .TABLE {
						lua.rawgeti(L, -1, 1); prop.defaultVal.valColor.r = f32(lua.tonumber(L, -1)); lua.pop(L, 1)
						lua.rawgeti(L, -1, 2); prop.defaultVal.valColor.g = f32(lua.tonumber(L, -1)); lua.pop(L, 1)
						lua.rawgeti(L, -1, 3); prop.defaultVal.valColor.b = f32(lua.tonumber(L, -1)); lua.pop(L, 1)
						lua.rawgeti(L, -1, 4); prop.defaultVal.valColor.a = f32(lua.tonumber(L, -1)); lua.pop(L, 1)
					}
				case .Vector2:
					if lua.type(L, -1) == .TABLE {
						lua.rawgeti(L, -1, 1); prop.defaultVal.valVec2.x = f32(lua.tonumber(L, -1)); lua.pop(L, 1)
						lua.rawgeti(L, -1, 2); prop.defaultVal.valVec2.y = f32(lua.tonumber(L, -1)); lua.pop(L, 1)
					}
				}
				lua.pop(L, 1)

				// 3. Min / Max
				lua.getfield(L, -1, "min")
				if lua.isnumber(L, -1) {
					prop.min = f32(lua.tonumber(L, -1))
				}
				lua.pop(L, 1)

				lua.getfield(L, -1, "max")
				if lua.isnumber(L, -1) {
					prop.max = f32(lua.tonumber(L, -1))
				}
				lua.pop(L, 1)

				// 4. Label / Tooltip
				lua.getfield(L, -1, "label")
				lblC := lua.tostring(L, -1)
				if lblC != nil {
					prop.label = strings.clone(string(lblC))
				}
				lua.pop(L, 1)

				append(&props, prop)
			}
			lua.pop(L, 1) // pop value, keep key for next iteration
		}
	}
	lua.pop(L, 1) // properties value
	return props
}
