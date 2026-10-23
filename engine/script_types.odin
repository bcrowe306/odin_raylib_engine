package engine

import "core:c"
import "core:time"
import lua "vendor:lua/5.4"

// ============================================================================
// Lua Scripting Data Types & Property Definitions
// ============================================================================

ScriptPropertyType :: enum {
	Float,
	Int,
	String,
	Boolean,
	Color,
	Vector2,
}

ScriptValue :: struct {
	type:      ScriptPropertyType,
	valFloat:  f32,
	valInt:    i64,
	valString: string,
	valBool:   bool,
	valColor:  [4]f32,
	valVec2:   [2]f32,
}

ScriptProperty :: struct {
	name:       string,
	type:       ScriptPropertyType,
	defaultVal: ScriptValue,
	min:        f32,
	max:        f32,
	label:      string,
	// Asset reference properties (type = "texture", "audio", "scene",
	// "script", "component", "level", "file"): a project-relative path
	// (String value) that the Inspector edits with an asset picker. Also
	// "node" (a path from the script's node), "enum" (one of `values`), and
	// JSON lists: "array" (of `elem`), "curve" ({{t, v}, ...}), "gradient"
	// ({{t, r, g, b, a}, ...}) - Lua tables.
	assetKind:  string,
	values:     [dynamic]string, // enum choices
	elem:       string,          // array element type ("string", "float", "node", "texture"...)
	slider:     bool,            // a slider between min and max (type = "range" or slider = true)
	group:      string,          // Inspector group header
	tooltip:    string,          // Inspector help
}

// Script_IsJsonKind: a property kind stored as JSON text (a Lua table).
Script_IsJsonKind :: proc(kind: string) -> bool {return kind == "array" || kind == "curve" || kind == "gradient"}

ScriptProperty_Destroy :: proc(p: ^ScriptProperty) {
	delete(p.name)
	delete(p.label)
	if p.assetKind != "" do delete(p.assetKind)
	if p.type == .String && len(p.defaultVal.valString) > 0 do delete(p.defaultVal.valString)
	for v in p.values do delete(v)
	delete(p.values)
	delete(p.elem)
	delete(p.group)
	delete(p.tooltip)
}

ScriptModule :: struct {
	path:        string,
	properties:  [dynamic]ScriptProperty,
	isLoaded:    bool,
	diskPath:    string,    // file the module was loaded from ("" = embedded)
	modTime:     time.Time, // its modification time at the last (re)load
}

// Forward declaration of ScriptManager
ScriptManager :: struct {
	L:         ^lua.State,
	game:      ^Game,
	isReady:   bool,
	modules:   map[string]^ScriptModule,
	instances: [dynamic]^ScriptInstance,
	// Lua event connections (script_events.odin) and the instance whose
	// code is running (owner of new connections).
	connections:      [dynamic]Lua_Connection,
	nextConnectionId: int,
	currentInstance:  ^ScriptInstance,
	// While suspended (the editor, outside Simulate) events are not
	// dispatched to Lua.
	suspended:        bool,
	lastHotReloadCheck: time.Tick,
	hotReload:          bool, // poll script files and reload changed ones
	globals:            [dynamic]Global_Script, // loaded global scripts (script_globals.odin)
}

ScriptInstance :: struct {
	node:          ^Node,
	scriptManager: ^ScriptManager,
	modulePath:    string,
	registryRef:   c.int, // Reference to self table in Lua LUA_REGISTRYINDEX
	properties:    map[string]ScriptValue,
	isReady:       bool,
}
