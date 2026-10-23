package engine

import "core:fmt"
import "core:reflect"
import "core:strings"
import "core:testing"
import rl "vendor:raylib"

// engine_api.lua's KeyName alias (between the "key names" markers) lists
// every key Input.is_key_* understands. On drift the test prints the block.
@(test)
test_lua_key_names_definitions :: proc(t: ^testing.T) {
	sb := strings.builder_make(context.temp_allocator)
	strings.write_string(&sb, "-- key names begin (generated: lua_keys_definitions_test.odin)\n---Keyboard keys (raylib names; also RETURN, ESC, SHIFT, CTRL, ALT and \"0\"-\"9\").\n---@alias KeyName\n")
	for name in reflect.enum_field_names(rl.KeyboardKey) {
		if name == "KEY_NULL" do continue
		fmt.sbprintf(&sb, "---| %q\n", name)
	}
	for name in ([]string{"RETURN", "ESC", "SHIFT", "CTRL", "ALT"}) do fmt.sbprintf(&sb, "---| %q\n", name)
	strings.write_string(&sb, "-- key names end\n")
	want := strings.to_string(sb)
	api := ENGINE_API_LUA
	a := strings.index(api, "-- key names begin")
	b := strings.index(api, "-- key names end\n")
	have := api[a:b + len("-- key names end\n")] if a >= 0 && b > a else ""
	if have != want {
		fmt.println("---- paste into engine_api.lua ----")
		fmt.print(want)
		fmt.println("---- end ----")
	}
	testing.expect(t, have == want, "engine_api.lua's KeyName alias lists the engine's keys")
}
