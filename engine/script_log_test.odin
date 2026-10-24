package engine

import "core:log"
import "core:strings"
import "core:testing"
import lua "lua54"

// Script logs reach the sink (the editor's Console) with every argument
// converted as tostring does.
@(test)
test_script_log :: proc(t: ^testing.T) {
	@(static) got: [dynamic]string
	@(static) levels: [dynamic]log.Level
	clear(&got)
	clear(&levels)
	scriptLogSink = proc(level: log.Level, text: string) {
		append(&got, strings.clone(text, context.temp_allocator))
		append(&levels, level)
	}
	defer scriptLogSink = nil

	sm: ScriptManager
	testing.expect(t, ScriptManager_Init(&sm), "init")
	defer ScriptManager_Destroy(&sm)
	ok := lua.L_dostring(sm.L, `
		Log.info("speed", 240, true, nil)
		Log.warn("low")
		Log.error("bad", false)
		print("hi")
	`)
	testing.expect_value(t, ok, i32(0))
	testing.expect_value(t, len(got), 4)
	if len(got) < 4 do return
	testing.expect_value(t, got[0], "speed\t240\ttrue\tnil")
	testing.expect_value(t, got[1], "low")
	testing.expect_value(t, got[2], "bad\tfalse")
	testing.expect_value(t, got[3], "hi")
	testing.expect(t, levels[0] == .Info && levels[1] == .Warning && levels[2] == .Error && levels[3] == .Info, "levels")
	delete(got)
	delete(levels)
	got, levels = nil, nil
}
