package editor

import "core:c"
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
// (F10), Step Into (F11) and Step Out (Shift+F11). Right-click the gutter
// for a breakpoint condition (it stops only when the Lua expression is
// true); watch expressions are evaluated in the selected frame at each stop.
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
	reason:      string, // why it stopped ("condition: ...", "")
	conditions:  map[string]map[int]string, // script -> line -> condition
	watches:     [dynamic]Debug_Watch,
	watchBuf:    [256]u8,
	condRel:     string, // the breakpoint whose condition is being edited
	condLine:    int,
	condBuf:     [256]u8,
	condOpen:    bool,
	runToRel:    string, // Run to Here: a temporary breakpoint, removed at the next stop
	runToLine:   int,
}

Debug_Watch :: struct {
	expr, value: string,
	ok:          bool,
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
		Debug_SetCondition(rel, line, "", keep = false)
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
	if conds, ok := dbg.conditions[rel]; ok {
		for line, cond in conds do RemoteGame_Send(fmt.tprintf("break-cond %s %d %s", rel, line, cond))
	}
}

// Debug_Condition: a breakpoint's condition ("" = none).
Debug_Condition :: proc(rel: string, line: int) -> string {
	if conds, ok := dbg.conditions[rel]; ok do return conds[line] or_else ""
	return ""
}

// Debug_SetCondition sets a breakpoint's condition (adding the breakpoint
// unless keep is false) and tells a running game.
Debug_SetCondition :: proc(rel: string, line: int, cond: string, keep := true) {
	cond := strings.trim_space(cond)
	if rel not_in dbg.conditions do dbg.conditions[strings.clone(rel)] = make(map[int]string)
	conds := &dbg.conditions[rel]
	if old, has := conds[line]; has {
		delete(old)
		delete_key(conds, line)
	}
	if cond != "" do conds[line] = strings.clone(cond)
	if keep && !Debug_HasBreakpoint(rel, line) {
		Debug_ToggleBreakpoint(rel, line) // sends the condition with it
		return
	}
	if RemoteGame_Connected() do RemoteGame_Send(fmt.tprintf("break-cond %s %d %s", rel, line, cond))
}

// Debug_EditCondition opens the condition popup for a gutter line.
Debug_EditCondition :: proc(rel: string, line: int) {
	delete(dbg.condRel)
	dbg.condRel = strings.clone(rel)
	dbg.condLine = line
	dbg.condBuf = {}
	copy(dbg.condBuf[:len(dbg.condBuf) - 1], Debug_Condition(rel, line))
	dbg.condOpen = true
}

// Debug_ConditionPopup: the breakpoint condition editor (Code tab).
Debug_ConditionPopup :: proc() {
	if dbg.condOpen {
		imgui.OpenPopup("##bp_condition")
		dbg.condOpen = false
	}
	if !imgui.BeginPopup("##bp_condition") do return
	imgui.TextUnformatted(fmt.ctprintf("%s  Breakpoint condition - %s:%d", ICON_FA_CIRCLE, dbg.condRel, dbg.condLine))
	UI_DimText("Stops only when this Lua expression is true (locals, self, globals).")
	if imgui.IsWindowAppearing() do imgui.SetKeyboardFocusHere()
	imgui.SetNextItemWidth(420)
	enter := imgui.InputTextWithHint("##bp_cond_text", "e.g. self.health <= 0 or i == 10", cstring(raw_data(dbg.condBuf[:])), len(dbg.condBuf), {.EnterReturnsTrue})
	Drive_Item("debug.condition")
	if enter || UI_PrimaryButton("Set", "debug.condition-set") {
		Debug_SetCondition(dbg.condRel, dbg.condLine, string(cstring(raw_data(dbg.condBuf[:]))))
		imgui.CloseCurrentPopup()
	}
	imgui.SameLine()
	if Debug_HasBreakpoint(dbg.condRel, dbg.condLine) && UI_Button("Remove Breakpoint", "debug.condition-remove") {
		Debug_ToggleBreakpoint(dbg.condRel, dbg.condLine)
		imgui.CloseCurrentPopup()
	}
	imgui.EndPopup()
}

// debug_request_watches evaluates every watch in the selected frame.
@(private = "file")
debug_request_watches :: proc() {
	if !dbg.stopped do return
	for w in dbg.watches do RemoteGame_Send(fmt.tprintf("watch %d %s", dbg.level, w.expr))
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
		if dbg.runToLine > 0 {
			// The Run to Here breakpoint has done its job.
			if Debug_HasBreakpoint(dbg.runToRel, dbg.runToLine) do Debug_ToggleBreakpoint(dbg.runToRel, dbg.runToLine)
			delete(dbg.runToRel)
			dbg.runToRel, dbg.runToLine = "", 0
		}
		dbg.level = 0
		delete(dbg.reason)
		dbg.reason = strings.clone(string(o["reason"].(json.String) or_else ""))
		clear(&dbg.stack)
		if st, ok := o["stack"].(json.Array); ok {
			for fv in st {
				f, _ := fv.(json.Object)
				append(&dbg.stack, Debug_Frame{json_int(f["level"]), strings.clone(string(f["name"].(json.String) or_else "?")), strings.clone(string(f["file"].(json.String) or_else "")), json_int(f["line"])})
			}
		}
		debug_set_locals(o["locals"])
		debug_request_watches()
		Editor_OpenScript(state, dbg.file, dbg.line - 1)
		Editor_Log(state, .Info, "Paused at %s:%d%s", dbg.file, dbg.line, fmt.tprintf(" (%s)", dbg.reason) if dbg.reason != "" else "")
	case "locals":
		v, err := json.parse(transmute([]u8)rest, allocator = context.temp_allocator)
		if err != .None do return
		o, _ := v.(json.Object)
		dbg.level = json_int(o["level"])
		debug_set_locals(o["locals"])
		debug_request_watches()
	case "watch":
		v, err := json.parse(transmute([]u8)rest, allocator = context.temp_allocator)
		if err != .None do return
		o, _ := v.(json.Object)
		expr := string(o["expr"].(json.String) or_else "")
		for &w in dbg.watches do if w.expr == expr {
			delete(w.value)
			w.value = strings.clone(string(o["text"].(json.String) or_else ""))
			w.ok = bool(o["ok"].(json.Boolean) or_else false)
		}
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
	imgui.TextUnformatted(fmt.ctprintf("%s  Paused at %s:%d%s", ICON_FA_PAUSE, dbg.file, dbg.line, fmt.tprintf("  (%s)", dbg.reason) if dbg.reason != "" else ""))
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
	h := max(imgui.GetContentRegionAvail().y * 0.5, 150) // the Game tab scrolls when it is short
	if imgui.BeginChild("##dbg_stack", {imgui.GetContentRegionAvail().x * 0.3, h}, {.Borders}, {}) {
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
	if imgui.BeginChild("##dbg_locals", {imgui.GetContentRegionAvail().x * 0.55, h}, {.Borders}, {}) {
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
	imgui.SameLine()
	if imgui.BeginChild("##dbg_watches", {0, h}, {.Borders}, {}) {
		UI_DimText("Watch")
		remove := -1
		for w, i in dbg.watches {
			imgui.PushIDInt(c.int(i))
			if UI_IconButton(ICON_FA_XMARK, fmt.tprintf("debug.watch-remove:%d", i), "Remove", size = 20) do remove = i
			imgui.SameLine()
			imgui.TextUnformatted(fmt.ctprintf("%s =", w.expr))
			imgui.SameLine()
			imgui.PushStyleColorImVec4(.Text, UI_TEXT if w.ok else UI_DANGER)
			imgui.PushTextWrapPos(0)
			imgui.TextWrapped("%s", fmt.ctprintf("%s", w.value))
			imgui.PopTextWrapPos()
			imgui.PopStyleColor()
			imgui.PopID()
		}
		if remove >= 0 {
			delete(dbg.watches[remove].expr)
			delete(dbg.watches[remove].value)
			ordered_remove(&dbg.watches, remove)
		}
		imgui.SetNextItemWidth(-1)
		if imgui.InputTextWithHint("##dbg_watch_add", "+ expression (self.vx, #enemies)", cstring(raw_data(dbg.watchBuf[:])), len(dbg.watchBuf), {.EnterReturnsTrue}) {
			Debug_AddWatch(string(cstring(raw_data(dbg.watchBuf[:]))))
			dbg.watchBuf = {}
		}
		Drive_Item("debug.watch-add")
	}
	imgui.EndChild()
	imgui.Separator()
}

// Debug_RunTo continues to a line (a temporary breakpoint there unless it
// has one).
Debug_RunTo :: proc(rel: string, line: int) {
	if !dbg.stopped do return
	if !Debug_HasBreakpoint(rel, line) {
		Debug_ToggleBreakpoint(rel, line)
		delete(dbg.runToRel)
		dbg.runToRel = strings.clone(rel)
		dbg.runToLine = line
	}
	Debug_Command("continue")
}

// Debug_AddWatch adds a watch expression (evaluated now when stopped).
Debug_AddWatch :: proc(expr: string) {
	expr := strings.trim_space(expr)
	if expr == "" do return
	for w in dbg.watches do if w.expr == expr do return
	append(&dbg.watches, Debug_Watch{expr = strings.clone(expr), value = strings.clone("")})
	if dbg.stopped do RemoteGame_Send(fmt.tprintf("watch %d %s", dbg.level, expr))
}

// Debug_Query: drive queries debug-*.
Debug_Query :: proc(q: string) -> (string, bool) {
	switch q {
	case "debug-stopped": return "true" if dbg.stopped else "false", true
	case "debug-reason": return dbg.reason, true
	case "debug-line": return fmt.tprintf("%s:%d", dbg.file, dbg.line) if dbg.stopped else "", true
	case "debug-stack":
		names := make([dynamic]string, context.temp_allocator)
		for f in dbg.stack do append(&names, f.name)
		return strings.join(names[:], ",", context.temp_allocator), true
	}
	if strings.has_prefix(q, "debug-watch:") {
		for w in dbg.watches do if w.expr == q[len("debug-watch:"):] do return w.value, true
		return "<none>", true
	}
	if strings.has_prefix(q, "debug-condition:") {
		// debug-condition:<file>:<line>
		rest := q[len("debug-condition:"):]
		if i := strings.last_index_byte(rest, ':'); i > 0 {
			line := 0
			for r in rest[i + 1:] do if r >= '0' && r <= '9' do line = line * 10 + int(r - '0')
			return Debug_Condition(rest[:i], line), true
		}
	}
	if strings.has_prefix(q, "debug-local:") {
		for l in dbg.locals do if l[0] == q[len("debug-local:"):] do return l[1], true
		return "<none>", true
	}
	return "", false
}
