package editor

import "core:testing"

// Call snippets from the language server: optional parameters (`player?`)
// are left out, so accepting a call never leaves invalid Lua behind.
@(test)
test_code_expand_snippet_drops_optional_params :: proc(t: ^testing.T) {
	text, stops := code_expand_snippet("get_axis(${1:neg_action}, ${2:pos_action}, ${3:player?})")
	testing.expect_value(t, text, "get_axis(neg_action, pos_action)")
	testing.expect_value(t, len(stops), 2)
	if len(stops) == 2 {
		testing.expect_value(t, stops[0].offset, len("get_axis("))
		testing.expect_value(t, stops[0].length, len("neg_action"))
		testing.expect_value(t, stops[1].offset, len("get_axis(neg_action, "))
	}

	only, s2 := code_expand_snippet("get_actions(${1:player?})")
	testing.expect_value(t, only, "get_actions()")
	testing.expect_value(t, len(s2), 0)

	// Required parameters, $0 and plain tab stops are unchanged.
	plain, s3 := code_expand_snippet("set_position(${1:x}, ${2:y})$0")
	testing.expect_value(t, plain, "set_position(x, y)")
	testing.expect_value(t, len(s3), 3)
}
