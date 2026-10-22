package engine

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import lua "vendor:lua/5.4"

// ============================================================================
// Lua debugger: breakpoints, stepping and locals through a line hook.
//
// The hook is installed only while there are breakpoints or a step is
// pending (scripts run at full speed otherwise). When a script reaches a
// breakpoint (or the line a step was waiting for) the debugger reports
// where it stopped - file, line, call stack, the top frame's locals - and
// waits for a command, so the game is paused inside the script:
//
//   continue | step-in | step-over | step-out
//   locals <level>          -> the locals of another stack frame
//   break-set <file> <l,l>  /  break-clear
//
// The host supplies the two ends: the editor link (editor_link.odin) prints
// "@ore:stopped {...}" and reads commands from stdin; tests use a queue.
// ============================================================================

Debug_Step :: enum {
	Run,
	In,   // the next line anywhere
	Over, // the next line in this function or a caller
	Out,  // the next line in a caller
}

Lua_Debugger :: struct {
	breakpoints:  map[string][dynamic]int, // project-relative script -> lines
	step:         Debug_Step,
	stepDepth:    int,
	L:            ^lua.State,
	// Host: block until the next command ("" = the debugger went away);
	// send a reply line ("stopped {...}", "locals {...}", "running").
	wait_command: proc() -> string,
	reply:        proc(kind, json: string),
	stopped:      bool, // inside a stop right now
	hits:         int,
	projectDir:   string, // to read function names from scripts on disk
}

luaDebugger: Lua_Debugger

// LuaDebugger_Attach: debug this Lua state (with these host procs).
LuaDebugger_Attach :: proc(L: ^lua.State, wait_command: proc() -> string, reply: proc(kind, json: string)) {
	luaDebugger.L = L
	luaDebugger.wait_command = wait_command
	luaDebugger.reply = reply
	debugger_update_hook()
}

// (The debugger's state lives on the heap allocator: it is changed from the
// Lua hook, which runs with a default context.)
LuaDebugger_SetBreakpoints :: proc(file: string, lines: []int) {
	heap := runtime.heap_allocator()
	if luaDebugger.breakpoints == nil do luaDebugger.breakpoints = make(map[string][dynamic]int, heap)
	key := debug_norm(file)
	if old, ok := luaDebugger.breakpoints[key]; ok {
		oldKey := key
		for k in luaDebugger.breakpoints do if k == key do oldKey = k
		delete(old)
		delete_key(&luaDebugger.breakpoints, key)
		delete(oldKey, heap)
	}
	if len(lines) > 0 {
		l := make([dynamic]int, heap)
		append(&l, ..lines)
		luaDebugger.breakpoints[strings.clone(key, heap)] = l
	}
	debugger_update_hook()
}

LuaDebugger_ClearBreakpoints :: proc() {
	heap := runtime.heap_allocator()
	for k, v in luaDebugger.breakpoints {
		delete(v)
		delete(k, heap)
	}
	clear(&luaDebugger.breakpoints)
	luaDebugger.step = .Run
	debugger_update_hook()
}

@(private = "file")
debugger_update_hook :: proc() {
	L := luaDebugger.L
	if L == nil do return
	if len(luaDebugger.breakpoints) > 0 || luaDebugger.step != .Run {
		lua.sethook(L, debug_hook, lua.MASKLINE, 0)
	} else {
		lua.sethook(L, nil, {}, 0)
	}
}

// debug_norm: "@scripts/a.lua", "/abs/project/scripts/a.lua" -> a comparable
// project-relative path.
@(private = "file")
debug_norm :: proc(source: string) -> string {
	s := strings.trim_prefix(source, "@")
	s, _ = strings.replace_all(s, "\\", "/", context.temp_allocator)
	return strings.trim_prefix(s, "./")
}

@(private = "file")
breakpoint_at :: proc(source: string, line: int) -> bool {
	src := debug_norm(source)
	for file, lines in luaDebugger.breakpoints {
		// Absolute vs. relative paths: the shorter one ends the longer one.
		match := src == file || strings.has_suffix(src, strings.concatenate({"/", file}, context.temp_allocator)) || strings.has_suffix(file, strings.concatenate({"/", src}, context.temp_allocator))
		if !match do continue
		for l in lines do if l == line do return true
	}
	return false
}

@(private = "file")
stack_depth :: proc(L: ^lua.State) -> int {
	ar: lua.Debug
	n := 0
	for lua.getstack(L, i32(n), &ar) != 0 do n += 1
	return n
}

@(private = "file")
debug_hook :: proc "c" (L: ^lua.State, ar: ^lua.Debug) {
	context = runtime.default_context()
	if ar.event != lua.HOOKLINE || luaDebugger.stopped do return
	lua.getinfo(L, "Sl", ar)
	source := string(ar.source)
	if !strings.has_prefix(source, "@") do return // C, strings run with dostring
	line := int(ar.currentline)
	stop := false
	switch luaDebugger.step {
	case .In: stop = true
	case .Over: stop = stack_depth(L) <= luaDebugger.stepDepth
	case .Out: stop = stack_depth(L) < luaDebugger.stepDepth
	case .Run:
	}
	if !stop do stop = breakpoint_at(source, line)
	if stop do debugger_stop(L, debug_norm(source), line)
}

@(private = "file")
debugger_stop :: proc(L: ^lua.State, file: string, line: int) {
	luaDebugger.stopped = true
	defer luaDebugger.stopped = false
	luaDebugger.hits += 1
	luaDebugger.step = .Run
	depth := stack_depth(L)
	if luaDebugger.reply != nil do luaDebugger.reply("stopped", debugger_state_json(L, file, line))
	for {
		cmd := luaDebugger.wait_command() if luaDebugger.wait_command != nil else ""
		verb, rest := cmd, ""
		if i := strings.index_byte(cmd, ' '); i >= 0 do verb, rest = cmd[:i], strings.trim_space(cmd[i + 1:])
		switch verb {
		case "", "continue":
			if cmd == "" do LuaDebugger_ClearBreakpoints() // the host went away: run freely
		case "step-in":
			luaDebugger.step = .In
		case "step-over":
			luaDebugger.step = .Over
			luaDebugger.stepDepth = depth
		case "step-out":
			luaDebugger.step = .Out
			luaDebugger.stepDepth = depth
		case "locals":
			level := 0
			for r in rest do if r >= '0' && r <= '9' do level = level * 10 + int(r - '0')
			if luaDebugger.reply != nil do luaDebugger.reply("locals", fmt.tprintf("{{\"level\": %d, \"locals\": %s}}", level, debugger_locals_json(L, level)))
			continue
		case "break-set":
			LuaDebugger_Command(rest)
			continue
		case "break-clear":
			LuaDebugger_ClearBreakpoints()
			continue
		case:
			continue // not a debugger command: still stopped
		}
		break
	}
	debugger_update_hook()
	if luaDebugger.reply != nil do luaDebugger.reply("running", "{}")
}

// LuaDebugger_Command: "break-set <file> <l1,l2,...>" (also used while running).
LuaDebugger_Command :: proc(args: string) {
	parts := strings.fields(args, context.temp_allocator)
	if len(parts) == 0 do return
	lines := make([dynamic]int, context.temp_allocator)
	if len(parts) > 1 {
		for f in strings.split(parts[1], ",", context.temp_allocator) {
			n, ok := 0, false
			for r in f do if r >= '0' && r <= '9' {n = n * 10 + int(r - '0'); ok = true}
			if ok do append(&lines, n)
		}
	}
	LuaDebugger_SetBreakpoints(parts[0], lines[:])
}

@(private = "file")
debugger_state_json :: proc(L: ^lua.State, file: string, line: int) -> string {
	sb := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&sb, "{{\"file\": %q, \"line\": %d, \"stack\": [", file, line)
	ar: lua.Debug
	n := 0
	for level := 0; lua.getstack(L, i32(level), &ar) != 0; level += 1 {
		lua.getinfo(L, "Sln", &ar)
		src := string(ar.source)
		if !strings.has_prefix(src, "@") do continue
		if n > 0 do strings.write_string(&sb, ", ")
		name := string(ar.name) if ar.name != nil else debug_function_name(src, int(ar.linedefined))
		fmt.sbprintf(&sb, "{{\"level\": %d, \"name\": %q, \"file\": %q, \"line\": %d}}", level, name, debug_norm(src), ar.currentline)
		n += 1
	}
	fmt.sbprintf(&sb, "], \"locals\": %s}}", debugger_locals_json(L, 0))
	return strings.to_string(sb)
}

// debugger_locals_json: [[name, value, type], ...] of a stack frame.
// debug_function_name: a function called from the engine has no name in
// Lua; read it from its definition line ("function Player:update(dt)").
@(private = "file")
debug_function_name :: proc(source: string, lineDefined: int) -> string {
	if lineDefined <= 0 do return "main chunk"
	path := debug_norm(source)
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil && luaDebugger.projectDir != "" {
		full, _ := filepath.join({luaDebugger.projectDir, path}, context.temp_allocator)
		data, err = os.read_entire_file(full, context.temp_allocator)
	}
	if err == nil {
		lines := strings.split_lines(string(data), context.temp_allocator)
		if lineDefined - 1 < len(lines) {
			l := strings.trim_space(lines[lineDefined - 1])
			if i := strings.index(l, "function"); i >= 0 {
				rest := strings.trim_space(l[i + len("function"):])
				if p := strings.index_byte(rest, '('); p > 0 do return strings.trim_space(rest[:p])
			}
		}
	}
	return fmt.tprintf("function@%d", lineDefined)
}

@(private = "file")
debugger_locals_json :: proc(L: ^lua.State, level: int) -> string {
	sb := strings.builder_make(context.temp_allocator)
	strings.write_byte(&sb, '[')
	ar: lua.Debug
	if lua.getstack(L, i32(level), &ar) != 0 {
		n := 0
		for i: i32 = 1; ; i += 1 {
			name := lua.getlocal(L, &ar, i)
			if name == nil do break
			nm := string(name)
			if !strings.has_prefix(nm, "(") {
				if n > 0 do strings.write_string(&sb, ", ")
				fmt.sbprintf(&sb, "[%q, %q, %q]", nm, debug_value(L, -1, 1), string(lua.typename(L, lua.type(L, -1))))
				n += 1
			}
			lua.pop(L, 1)
		}
	}
	strings.write_byte(&sb, ']')
	return strings.to_string(sb)
}

// debug_value: a value as text - tables one level deep (up to 12 entries),
// nodes as Node(Name).
@(private = "file")
debug_value :: proc(L: ^lua.State, idx: i32, depth: int) -> string {
	i := lua.absindex(L, idx)
	#partial switch lua.type(L, i) {
	case .NIL: return "nil"
	case .BOOLEAN: return "true" if lua.toboolean(L, i) else "false"
	case .NUMBER:
		if lua.isinteger(L, i) do return fmt.tprintf("%d", lua.tointeger(L, i))
		return fmt.tprintf("%.6g", lua.tonumber(L, i))
	case .STRING:
		s := string(lua.tostring(L, i))
		if len(s) > 80 do s = strings.concatenate({s[:80], "..."}, context.temp_allocator)
		return fmt.tprintf("%q", s)
	case .USERDATA:
		if node, ok := to_node_userdata(L, i); ok do return fmt.tprintf("%s(%s)", Node_TypeName(node), node.name)
		return "userdata"
	case .FUNCTION: return "function"
	case .TABLE:
		if depth <= 0 do return "{...}"
		sb := strings.builder_make(context.temp_allocator)
		strings.write_byte(&sb, '{')
		n := 0
		lua.pushnil(L)
		for lua.next(L, i) != 0 {
			if n < 12 {
				if n > 0 do strings.write_string(&sb, ", ")
				key := string(lua.tostring(L, -2)) if lua.type(L, -2) == .STRING else debug_value(L, -2, 0)
				fmt.sbprintf(&sb, "%s = %s", key, debug_value(L, -1, depth - 1))
			}
			n += 1
			lua.pop(L, 1)
		}
		if n > 12 do fmt.sbprintf(&sb, ", ... (%d)", n)
		strings.write_byte(&sb, '}')
		return strings.to_string(sb)
	}
	return string(lua.typename(L, lua.type(L, i)))
}
