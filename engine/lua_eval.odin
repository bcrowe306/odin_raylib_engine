package engine

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:strings"
import lua "lua54"

// ============================================================================
// Lua console: evaluate a line typed in the editor's Console - in the
// editor's Lua state while simulating, in the game over the editor link
// ("eval <code>" -> "@ore:eval {...}") while it runs. An expression shows
// its value(s); a statement runs (`GameState.score = 10`).
// ============================================================================

// Lua_Eval runs code; text is its results (", "-separated) or the error.
// With env (a stack index of a table), the code's globals are that table
// (the debugger: a frame's locals over _G).
Lua_Eval :: proc(L: ^lua.State, code: string, allocator := context.allocator, env: c.int = 0) -> (text: string, ok: bool) {
	if L == nil do return strings.clone("no Lua state", allocator), false
	env := lua.absindex(L, env) if env != 0 else 0
	top := lua.gettop(L)
	defer lua.settop(L, top)
	src := strings.trim_space(code)
	if strings.has_prefix(src, "=") do src = src[1:] // Lua 5.1 style "=expr"
	asExpr := strings.concatenate({"return ", src}, context.temp_allocator)
	chunk: cstring = "=console"
	if lua.L_loadbuffer(L, cast([^]u8)raw_data(asExpr), c.size_t(len(asExpr)), chunk) != .OK {
		lua.settop(L, top)
		if lua.L_loadbuffer(L, cast([^]u8)raw_data(src), c.size_t(len(src)), chunk) != .OK {
			return strings.clone(string(lua.tostring(L, -1)), allocator), false
		}
	}
	if env != 0 {
		lua.pushvalue(L, env)
		_ = lua.setupvalue(L, -2, 1) // the chunk's _ENV
	}
	if lua.pcall(L, 0, lua.MULTRET, 0) != 0 {
		return strings.clone(string(lua.tostring(L, -1)), allocator), false
	}
	n := lua.gettop(L) - top
	if n == 0 do return strings.clone("ok", allocator), true
	sb := strings.builder_make(allocator)
	for i in 1 ..= n {
		if i > 1 do strings.write_string(&sb, ", ")
		Lua_FormatValue(&sb, L, top + c.int(i), 0)
	}
	return strings.to_string(sb), true
}

// Lua_FormatValue writes a readable value: strings quoted, tables shallow
// ({1, 2, x = 3}, up to 12 entries, 2 levels), nodes and vectors by name.
Lua_FormatValue :: proc(sb: ^strings.Builder, L: ^lua.State, idx: c.int, depth: int) {
	idx := lua.absindex(L, idx)
	#partial switch lua.type(L, idx) {
	case .NIL: strings.write_string(sb, "nil")
	case .BOOLEAN: strings.write_string(sb, "true" if lua.toboolean(L, idx) else "false")
	case .NUMBER:
		if lua.isinteger(L, idx) do fmt.sbprintf(sb, "%d", lua.tointeger(L, idx))
		else do fmt.sbprintf(sb, "%.6g", f64(lua.tonumber(L, idx)))
	case .STRING: fmt.sbprintf(sb, "%q", string(lua.tostring(L, idx)))
	case .TABLE:
		if lua.L_getmetafield(L, idx, "__tostring") != c.int(lua.Type.NIL) {
			lua.pop(L, 1)
			strings.write_string(sb, string(lua.L_tostring(L, idx)))
			lua.pop(L, 1)
			return
		}
		if depth >= 2 {
			strings.write_string(sb, "{...}")
			return
		}
		strings.write_byte(sb, '{')
		count := 0
		arrayLen := int(lua.rawlen(L, idx))
		lua.pushnil(L)
		for lua.next(L, idx) != 0 {
			if count == 12 {
				strings.write_string(sb, ", ...")
				lua.pop(L, 2)
				break
			}
			if count > 0 do strings.write_string(sb, ", ")
			isArray := lua.isinteger(L, -2) && lua.tointeger(L, -2) >= 1 && int(lua.tointeger(L, -2)) <= arrayLen
			if !isArray {
				if lua.type(L, -2) == .STRING {
					strings.write_string(sb, string(lua.tostring(L, -2)))
				} else {
					strings.write_byte(sb, '[')
					Lua_FormatValue(sb, L, -2, depth + 1)
					strings.write_byte(sb, ']')
				}
				strings.write_string(sb, " = ")
			}
			Lua_FormatValue(sb, L, -1, depth + 1)
			lua.pop(L, 1)
			count += 1
		}
		strings.write_byte(sb, '}')
	case:
		strings.write_string(sb, string(lua.L_tostring(L, idx))) // __tostring / __name
		lua.pop(L, 1)
	}
}

// lua_node_tostring: Node "Player" (CharacterMoverNode) - or a freed node.
lua_node_tostring :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	node, ok := to_node_userdata(L, 1)
	if !ok {
		lua.pushstring(L, "Node (freed)")
		return 1
	}
	lua.pushstring(L, fmt.ctprintf("Node %q (%s)", node.name, Node_TypeName(node)))
	return 1
}
