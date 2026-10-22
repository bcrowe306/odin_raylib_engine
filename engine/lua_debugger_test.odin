package engine

import "core:encoding/json"
import "core:strings"
import "core:testing"
import lua "vendor:lua/5.4"

@(private = "file")
dbg_queue: [dynamic]string
@(private = "file")
dbg_stops: [dynamic]string // "file:line locals..."

@(private = "file")
dbg_wait :: proc() -> string {
	if len(dbg_queue) == 0 do return ""
	return pop_front(&dbg_queue)
}

@(private = "file")
dbg_reply :: proc(kind, text: string) {
	if kind != "stopped" do return
	v, err := json.parse(transmute([]u8)text, allocator = context.temp_allocator)
	if err != .None do return
	o := v.(json.Object)
	sb := strings.builder_make(context.temp_allocator)
	strings.write_string(&sb, string(o["file"].(json.String)))
	#partial switch l in o["line"] {
	case json.Integer: strings.write_string(&sb, ":"); strings.write_int(&sb, int(l))
	case json.Float: strings.write_string(&sb, ":"); strings.write_int(&sb, int(l))
	}
	for lv in o["locals"].(json.Array) {
		pair := lv.(json.Array)
		strings.write_string(&sb, " ")
		strings.write_string(&sb, string(pair[0].(json.String)))
		strings.write_string(&sb, "=")
		strings.write_string(&sb, string(pair[1].(json.String)))
	}
	append(&dbg_stops, strings.clone(strings.to_string(sb)))
}

@(test)
test_lua_debugger :: proc(t: ^testing.T) {
	L := lua.L_newstate()
	defer lua.close(L)
	lua.L_openlibs(L)
	defer {
		LuaDebugger_ClearBreakpoints()
		luaDebugger.L = nil
		for s in dbg_stops do delete(s)
		delete(dbg_stops)
		delete(dbg_queue)
		dbg_stops, dbg_queue = nil, nil
	}
	code := `local function add(a, b)
  local s = a + b
  return s
end
function run()
  local x = 10
  local y = add(x, 5)
  local z = y * 2
  return z
end`
	testing.expect(t, lua.L_loadbuffer(L, raw_data(code), len(code), "@scripts/dbg.lua") == .OK, "loaded")
	testing.expect(t, lua.pcall(L, 0, 0, 0) == 0, "ran")

	LuaDebugger_Attach(L, dbg_wait, dbg_reply)
	LuaDebugger_Command("/abs/project/scripts/dbg.lua 7") // absolute paths match too
	append(&dbg_queue, "step-in", "step-out", "step-over", "continue")
	lua.getglobal(L, "run")
	testing.expect(t, lua.pcall(L, 0, 1, 0) == 0, "run() finished")
	testing.expect_value(t, lua.tointeger(L, -1), 30)
	lua.pop(L, 1)
	want := []string{
		"scripts/dbg.lua:7 x=10",              // the breakpoint
		"scripts/dbg.lua:2 a=10 b=5",          // step in: into add
		"scripts/dbg.lua:8 x=10 y=15",         // step out: back in run, past the call
		"scripts/dbg.lua:9 x=10 y=15 z=30",    // step over
	}
	testing.expect_value(t, len(dbg_stops), len(want))
	for w, i in want do if i < len(dbg_stops) do testing.expect_value(t, dbg_stops[i], w)

	// Without breakpoints the hook is off.
	LuaDebugger_ClearBreakpoints()
	testing.expect(t, lua.gethook(L) == nil, "no hook when not debugging")
	// The host going away ("") clears the breakpoints and lets the script run.
	LuaDebugger_Command("scripts/dbg.lua 6")
	lua.getglobal(L, "run")
	testing.expect(t, lua.pcall(L, 0, 1, 0) == 0, "ran to the end")
	lua.pop(L, 1)
	testing.expect(t, len(luaDebugger.breakpoints) == 0 && lua.gethook(L) == nil, "detached")
}
