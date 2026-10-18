package syntax

import "core:mem"
import "core:testing"

run_leak_free :: proc(t: ^testing.T, body: proc(t: ^testing.T)) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)

	old := context.allocator
	context.allocator = mem.tracking_allocator(&track)
	body(t)
	context.allocator = old

	for _, entry in track.allocation_map {
		testing.expectf(t, false, "Memory leak: %v bytes at %v", entry.size, entry.location)
	}
}

@(test)
test_keyword_and_identifier :: proc(t: ^testing.T) {
	run_leak_free(t, proc(t: ^testing.T) {
		tokens, state := tokenize_odin_line("proc foo", ODIN_STATE_NORMAL, context.allocator)
		defer delete(tokens)
		testing.expect_value(t, state, ODIN_STATE_NORMAL)
		testing.expect_value(t, len(tokens), 2)
		testing.expect_value(t, tokens[0].kind, TokenKind.Keyword)
		testing.expect_value(t, tokens[0].start, 0)
		testing.expect_value(t, tokens[0].end, 4)
		testing.expect_value(t, tokens[1].kind, TokenKind.Identifier)
		testing.expect_value(t, tokens[1].start, 5)
		testing.expect_value(t, tokens[1].end, 8)
	})
}

@(test)
test_builtin_type :: proc(t: ^testing.T) {
	run_leak_free(t, proc(t: ^testing.T) {
		tokens, _ := tokenize_odin_line("x: i32", ODIN_STATE_NORMAL, context.allocator)
		defer delete(tokens)
		found := false
		for tok in tokens {
			if tok.kind == .Type {
				found = true
			}
		}
		testing.expect(t, found, "expected i32 to tokenize as Type")
	})
}

@(test)
test_line_comment :: proc(t: ^testing.T) {
	run_leak_free(t, proc(t: ^testing.T) {
		line := "x := 1 // comment"
		tokens, _ := tokenize_odin_line(line, ODIN_STATE_NORMAL, context.allocator)
		defer delete(tokens)
		last := tokens[len(tokens) - 1]
		testing.expect_value(t, last.kind, TokenKind.Comment)
		testing.expect_value(t, line[last.start:last.end], "// comment")
	})
}

@(test)
test_string_literal_with_escape :: proc(t: ^testing.T) {
	run_leak_free(t, proc(t: ^testing.T) {
		line := `s := "a\"b"`
		tokens, _ := tokenize_odin_line(line, ODIN_STATE_NORMAL, context.allocator)
		defer delete(tokens)
		var_tok := tokens[len(tokens) - 1]
		testing.expect_value(t, var_tok.kind, TokenKind.String)
		testing.expect_value(t, line[var_tok.start:var_tok.end], `"a\"b"`)
	})
}

@(test)
test_number_literal :: proc(t: ^testing.T) {
	run_leak_free(t, proc(t: ^testing.T) {
		tokens, _ := tokenize_odin_line("x := 0x1F_2A", ODIN_STATE_NORMAL, context.allocator)
		defer delete(tokens)
		found := false
		for tok in tokens {
			if tok.kind == .Number {
				found = true
			}
		}
		testing.expect(t, found, "expected hex literal to tokenize as Number")
	})
}

@(test)
test_block_comment_single_line :: proc(t: ^testing.T) {
	run_leak_free(t, proc(t: ^testing.T) {
		tokens, state := tokenize_odin_line("/* comment */ x", ODIN_STATE_NORMAL, context.allocator)
		defer delete(tokens)
		testing.expect_value(t, state, ODIN_STATE_NORMAL)
		testing.expect_value(t, tokens[0].kind, TokenKind.Comment)
	})
}

@(test)
test_block_comment_spans_multiple_lines :: proc(t: ^testing.T) {
	run_leak_free(t, proc(t: ^testing.T) {
		tokens1, state1 := tokenize_odin_line("/* start of comment", ODIN_STATE_NORMAL, context.allocator)
		defer delete(tokens1)
		testing.expect_value(t, state1, ODIN_STATE_BLOCK_COMMENT)
		testing.expect_value(t, tokens1[0].kind, TokenKind.Comment)

		tokens2, state2 := tokenize_odin_line("still comment */ code", state1, context.allocator)
		defer delete(tokens2)
		testing.expect_value(t, state2, ODIN_STATE_NORMAL)
		testing.expect_value(t, tokens2[0].kind, TokenKind.Comment)
		// Remaining tokens after the comment closes should tokenize normally.
		testing.expect(t, len(tokens2) > 1, "expected tokens after comment close")
	})
}

@(test)
test_operators :: proc(t: ^testing.T) {
	run_leak_free(t, proc(t: ^testing.T) {
		line := "x := y + 1"
		tokens, _ := tokenize_odin_line(line, ODIN_STATE_NORMAL, context.allocator)
		defer delete(tokens)
		assign_tok := tokens[1]
		testing.expect_value(t, assign_tok.kind, TokenKind.Operator)
		testing.expect_value(t, line[assign_tok.start:assign_tok.end], ":=")
	})
}
