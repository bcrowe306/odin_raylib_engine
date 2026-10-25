package editor

import "base:runtime"
import "core:c"
import "core:encoding/json"
import "core:fmt"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Lua line under the Console: evaluates in the editor's Lua state while
// simulating, in the running game (editor link "eval") while it plays.
// An expression shows its value(s) (`Scene.find_node("Player").position`),
// a statement runs (`GameState.score = 100`). Up / Down walk the history.
// ============================================================================

@(private = "file")
lua_console: struct {
	buf:     [512]u8,
	history: [dynamic]string,
	pos:     int, // history position while walking it (len = the new line)
	refocus: bool,
}

LUA_CONSOLE_H :: 34

// LuaConsole_Target: where a line runs ("" = nowhere: not simulating or
// playing).
LuaConsole_Target :: proc(state: ^EditorState) -> string {
	if state.isSimulating do return "Simulate"
	if RemoteGame_Connected() do return "Game"
	return ""
}

LuaConsole_Render :: proc(state: ^EditorState) {
	lc := &lua_console
	target := LuaConsole_Target(state)
	imgui.AlignTextToFramePadding()
	imgui.PushStyleColorImVec4(.Text, UI_ACCENT if target != "" else UI_TEXT_FAINT)
	imgui.TextUnformatted(fmt.ctprintf("%s Lua", ICON_FA_CODE))
	imgui.PopStyleColor()
	imgui.SameLine(0, 8)
	hint := fmt.ctprintf("Evaluate in the %s  (Scene.find_node(\"Player\").position, GameState.score = 10)", "running game" if target == "Game" else "simulation") if target != "" else "Simulate (F7) or Play to evaluate Lua here"
	if lc.refocus {
		imgui.SetKeyboardFocusHere()
		lc.refocus = false
	}
	imgui.SetNextItemWidth(-1)
	imgui.BeginDisabled(target == "")
	entered := imgui.InputTextWithHint("##lua_console", hint, cstring(raw_data(lc.buf[:])), len(lc.buf), {.EnterReturnsTrue, .CallbackHistory}, lua_console_history)
	imgui.EndDisabled()
	Drive_Item("console.lua")
	if !entered do return
	code := strings.clone(strings.trim_space(string(cstring(raw_data(lc.buf[:])))), context.temp_allocator)
	lc.buf = {}
	lc.refocus = true
	if code == "" do return
	if len(lc.history) == 0 || lc.history[len(lc.history) - 1] != code do append(&lc.history, strings.clone(code))
	lc.pos = len(lc.history)
	LuaConsole_Eval(state, code)
}

// LuaConsole_Eval runs a line where the Console's Lua line would.
LuaConsole_Eval :: proc(state: ^EditorState, code: string) {
	switch LuaConsole_Target(state) {
	case "Simulate":
		Editor_Log(state, .Info, "› %s", code)
		text, ok := e.Lua_Eval(state.game.scriptManager.L, code, context.temp_allocator)
		lua_console_result(state, ok, text)
	case "Game":
		line, _ := strings.replace_all(code, "\n", " ", context.temp_allocator)
		Editor_Log(state, .Info, "› %s  (game)", line)
		RemoteGame_Send(fmt.tprintf("eval %s", line))
	case:
		Editor_Log(state, .Warn, "Simulate (F7) or Play to evaluate Lua")
	}
}

// LuaConsole_Reply: the game's "@rayzr:eval" answer.
LuaConsole_Reply :: proc(state: ^EditorState, text: string) {
	v, err := json.parse(transmute([]u8)text, allocator = context.temp_allocator)
	if err != .None do return
	obj, isObj := v.(json.Object)
	if !isObj do return
	ok := bool(obj["ok"].(json.Boolean) or_else false)
	lua_console_result(state, ok, string(obj["text"].(json.String) or_else ""))
}

@(private = "file")
lua_console_result :: proc(state: ^EditorState, ok: bool, text: string) {
	if ok do Editor_Log(state, .Info, "= %s", text)
	else do Editor_Log(state, .Error, "%s", text)
}

@(private = "file")
lua_console_history :: proc "c" (data: ^imgui.InputTextCallbackData) -> c.int {
	context = runtime.default_context()
	lc := &lua_console
	if len(lc.history) == 0 do return 0
	prev := lc.pos
	if data.EventKey == .UpArrow do lc.pos = max(lc.pos - 1, 0)
	if data.EventKey == .DownArrow do lc.pos = min(lc.pos + 1, len(lc.history))
	if prev == lc.pos do return 0
	imgui.InputTextCallbackData_DeleteChars(data, 0, data.BufTextLen)
	if lc.pos < len(lc.history) {
		imgui.InputTextCallbackData_InsertChars(data, 0, strings.clone_to_cstring(lc.history[lc.pos], context.temp_allocator))
	}
	return 0
}
