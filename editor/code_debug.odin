package editor

import "core:encoding/json"
import "core:fmt"
import "core:slice"
import "core:strings"
import imgui "lib/imgui"

// ============================================================================
// Lua debugging while the game plays (engine/lua_debugger.odin over the
// editor link): click the Code tab's gutter to toggle a breakpoint; when the
// game reaches it, it pauses there, the script opens at that line, and the
// Game tab shows the call stack and locals with Continue (F8), Step Over
// (F10), Step Into (F11) and Step Out (Shift+F11).
// ============================================================================

Debug_Frame :: struct {
	level: int,
	name, file: string,
	line: int,
}

@(private = "file")
dbg: struct {
	breakpoints: map[string][dynamic]int, // project-relative script -> lines (1-based)
	stopped:     bool,
	file:        string,
	line:        int,
	stack:       [dynamic]Debug_Frame,
	locals:      [dynamic][3]string, // name, value, type
	level:       int,
}

Debug_IsStopped :: proc() -> bool {return dbg.stopped}

Debug_HasBreakpoint :: proc(rel: string, line: int) -> bool {
	lines, ok := dbg.breakpoints[rel]
	return ok && slice.contains(lines[:], line)
}

// Debug_ToggleBreakpoint (line is 1-based).
Debug_ToggleBreakpoint :: proc(rel: string, line: int) {
	if rel not_in dbg.breakpoints do dbg.breakpoints[strings.clone(rel)] = make([dynamic]int)
	lines := &dbg.breakpoints[rel]
	if i, found := slice.linear_search(lines[:], line); found {
		ordered_remove(lines, i)
	} else {
		append(lines, line)
		slice.sort(lines[:])
	}
	debug_send(rel)
}

@(private = "file")
debug_send :: proc(rel: string) {
	if !RemoteGame_Connected() do return
	lines := dbg.breakpoints[rel]
	parts := make([dynamic]string, context.temp_allocator)
	for l in lines do append(&parts, fmt.tprint(l))
	RemoteGame_Send(fmt.tprintf("break-set %s %s", rel, strings.join(parts[:], ",", context.temp_allocator)))
}

// Debug_SendAll: every breakpoint to a game that just connected.
Debug_SendAll :: proc() {
	for rel in dbg.breakpoints do debug_send(rel)
}

Debug_Reset :: proc() {
	dbg.stopped = false
	clear(&dbg.stack)
	clear(&dbg.locals)
}

Debug_Command :: proc(cmd: string) {
	if !dbg.stopped do return
	RemoteGame_Send(cmd)
}

// Debug_HandleReply: "@ore:stopped / locals / running" from the game.
Debug_HandleReply :: proc(state: ^EditorState, kind, rest: string) {
	switch kind {
	case "running":
		dbg.stopped = false
	case "stopped":
		v, err := json.parse(transmute([]u8)rest, allocator = context.temp_allocator)
		if err != .None do return
		o, _ := v.(json.Object)
		dbg.stopped = true
		delete(dbg.file)
		dbg.file = strings.clone(string(o["file"].(json.String) or_else ""))
		dbg.line = json_int(o["line"])
		dbg.level = 0
		clear(&dbg.stack)
		if st, ok := o["stack"].(json.Array); ok {
			for fv in st {
				f, _ := fv.(json.Object)
				append(&dbg.stack, Debug_Frame{json_int(f["level"]), strings.clone(string(f["name"].(json.String) or_else "?")), strings.clone(string(f["file"].(json.String) or_else "")), json_int(f["line"])})
			}
		}
		debug_set_locals(o["locals"])
		Editor_OpenScript(state, dbg.file, dbg.line - 1)
		Editor_Log(state, .Info, "Paused at %s:%d", dbg.file, dbg.line)
	case "locals":
		v, err := json.parse(transmute([]u8)rest, allocator = context.temp_allocator)
		if err != .None do return
		o, _ := v.(json.Object)
		dbg.level = json_int(o["level"])
		debug_set_locals(o["locals"])
	}
}

@(private = "file")
json_int :: proc(v: json.Value) -> int {
	#partial switch x in v {
	case json.Integer: return int(x)
	case json.Float: return int(x)
	}
	return 0
}

@(private = "file")
debug_set_locals :: proc(v: json.Value) {
	clear(&dbg.locals)
	arr, ok := v.(json.Array)
	if !ok do return
	for lv in arr {
		t, isArr := lv.(json.Array)
		if !isArr || len(t) != 3 do continue
		append(&dbg.locals, [3]string{strings.clone(string(t[0].(json.String) or_else "")), strings.clone(string(t[1].(json.String) or_else "")), strings.clone(string(t[2].(json.String) or_else ""))})
	}
}

// Debug_CurrentLine: the line (1-based) the game is paused at in `rel`, else 0.
Debug_CurrentLine :: proc(rel: string) -> int {
	if !dbg.stopped do return 0
	f := dbg.file
	if dbg.level > 0 {
		for fr in dbg.stack do if fr.level == dbg.level {return fr.line if fr.file == rel else 0}
	}
	return dbg.line if f == rel else 0
}

// Debug_Panel: the Game tab's debugger section (when paused).
Debug_Panel :: proc(state: ^EditorState) {
	if !dbg.stopped do return
	imgui.PushStyleColorImVec4(.Text, UI_WARNING)
	imgui.TextUnformatted(fmt.ctprintf("%s  Paused at %s:%d", ICON_FA_PAUSE, dbg.file, dbg.line))
	imgui.PopStyleColor()
	Drive_Item("debug.where")
	imgui.SameLine()
	if UI_PrimaryButton(fmt.tprintf("%s  Continue", ICON_FA_PLAY), "debug.continue") do Debug_Command("continue")
	UI_Tooltip("Continue (F8)")
	imgui.SameLine()
	if UI_Button("Step Over", "debug.step-over") do Debug_Command("step-over")
	UI_Tooltip("Step Over (F10)")
	imgui.SameLine()
	if UI_Button("Step Into", "debug.step-in") do Debug_Command("step-in")
	UI_Tooltip("Step Into (F11)")
	imgui.SameLine()
	if UI_Button("Step Out", "debug.step-out") do Debug_Command("step-out")
	UI_Tooltip("Step Out (Shift+F11)")
	h := imgui.GetContentRegionAvail().y * 0.5
	if imgui.BeginChild("##dbg_stack", {imgui.GetContentRegionAvail().x * 0.4, h}, {.Borders}, {}) {
		UI_DimText("Call stack")
		for fr in dbg.stack {
			if imgui.Selectable(fmt.ctprintf("%s  %s:%d##fr%d", fr.name, fr.file, fr.line, fr.level), fr.level == dbg.level) {
				RemoteGame_Send(fmt.tprintf("locals %d", fr.level))
				Editor_OpenScript(state, fr.file, fr.line - 1)
			}
			Drive_Item(fmt.tprintf("debug.frame:%d", fr.level))
		}
	}
	imgui.EndChild()
	imgui.SameLine()
	if imgui.BeginChild("##dbg_locals", {0, h}, {.Borders}, {}) {
		UI_DimText(fmt.tprintf("Locals (frame %d)", dbg.level))
		if UI_BeginProps("##dbglocals") {
			for l in dbg.locals {
				UI_PropLabel(l[0])
				imgui.PushTextWrapPos(0)
				imgui.TextWrapped("%s", fmt.ctprintf("%s", l[1]))
				imgui.PopTextWrapPos()
				UI_Tooltip(l[2])
			}
			UI_EndProps()
		}
	}
	imgui.EndChild()
	imgui.Separator()
}

// Debug_Query: drive queries debug-*.
Debug_Query :: proc(q: string) -> (string, bool) {
	switch q {
	case "debug-stopped": return "true" if dbg.stopped else "false", true
	case "debug-line": return fmt.tprintf("%s:%d", dbg.file, dbg.line) if dbg.stopped else "", true
	case "debug-stack":
		names := make([dynamic]string, context.temp_allocator)
		for f in dbg.stack do append(&names, f.name)
		return strings.join(names[:], ",", context.temp_allocator), true
	}
	if strings.has_prefix(q, "debug-local:") {
		for l in dbg.locals do if l[0] == q[len("debug-local:"):] do return l[1], true
		return "<none>", true
	}
	return "", false
}
