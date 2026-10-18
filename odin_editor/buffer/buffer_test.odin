package buffer

import "core:mem"
import "core:testing"

// run_leak_free wraps a test body in a tracking allocator, failing the test
// on any leak or bad free — mirrors the convention used by the `engine`
// package's test suite.
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
	for bf in track.bad_free_array {
		testing.expectf(t, false, "Bad free: %p at %v", bf.memory, bf.location)
	}
}

@(test)
test_set_and_to_string_roundtrip :: proc(t: ^testing.T) {
	run_leak_free(t, proc(t: ^testing.T) {
		b := buffer_init()
		defer buffer_destroy(&b)

		buffer_set_text(&b, "hello\nworld\n")
		testing.expect_value(t, buffer_line_count(&b), 3)
		testing.expect_value(t, buffer_line_str(&b, 0), "hello")
		testing.expect_value(t, buffer_line_str(&b, 1), "world")
		testing.expect_value(t, buffer_line_str(&b, 2), "")

		out := buffer_to_string(&b, context.temp_allocator)
		testing.expect_value(t, out, "hello\nworld\n")
	})
}

@(test)
test_insert_single_line :: proc(t: ^testing.T) {
	run_leak_free(t, proc(t: ^testing.T) {
		b := buffer_init()
		defer buffer_destroy(&b)
		buffer_set_text(&b, "helloworld")
		end := buffer_insert_text(&b, Position{0, 5}, " ")
		testing.expect_value(t, buffer_line_str(&b, 0), "hello world")
		testing.expect_value(t, end, Position{0, 6})
	})
}

@(test)
test_insert_multiline_splits :: proc(t: ^testing.T) {
	run_leak_free(t, proc(t: ^testing.T) {
		b := buffer_init()
		defer buffer_destroy(&b)
		buffer_set_text(&b, "foobar")
		end := buffer_insert_text(&b, Position{0, 3}, "\nBAZ\n")
		testing.expect_value(t, buffer_line_count(&b), 3)
		testing.expect_value(t, buffer_line_str(&b, 0), "foo")
		testing.expect_value(t, buffer_line_str(&b, 1), "BAZ")
		testing.expect_value(t, buffer_line_str(&b, 2), "bar")
		testing.expect_value(t, end, Position{2, 0})
	})
}

@(test)
test_delete_single_line_range :: proc(t: ^testing.T) {
	run_leak_free(t, proc(t: ^testing.T) {
		b := buffer_init()
		defer buffer_destroy(&b)
		buffer_set_text(&b, "hello world")
		removed := buffer_delete_range(&b, Position{0, 5}, Position{0, 11})
		testing.expect_value(t, buffer_line_str(&b, 0), "hello")
		testing.expect_value(t, removed, " world")
	})
}

@(test)
test_delete_multiline_merges :: proc(t: ^testing.T) {
	run_leak_free(t, proc(t: ^testing.T) {
		b := buffer_init()
		defer buffer_destroy(&b)
		buffer_set_text(&b, "foo\nBAZ\nbar")
		buffer_delete_range(&b, Position{0, 3}, Position{2, 0})
		testing.expect_value(t, buffer_line_count(&b), 1)
		testing.expect_value(t, buffer_line_str(&b, 0), "foobar")
	})
}

@(test)
test_undo_redo_insert :: proc(t: ^testing.T) {
	run_leak_free(t, proc(t: ^testing.T) {
		b := buffer_init()
		defer buffer_destroy(&b)
		buffer_set_text(&b, "abc")
		buffer_insert_text(&b, Position{0, 3}, "def")
		testing.expect_value(t, buffer_line_str(&b, 0), "abcdef")

		ok := buffer_undo(&b)
		testing.expect(t, ok, "expected undo to succeed")
		testing.expect_value(t, buffer_line_str(&b, 0), "abc")

		ok = buffer_redo(&b)
		testing.expect(t, ok, "expected redo to succeed")
		testing.expect_value(t, buffer_line_str(&b, 0), "abcdef")
	})
}

@(test)
test_undo_redo_delete :: proc(t: ^testing.T) {
	run_leak_free(t, proc(t: ^testing.T) {
		b := buffer_init()
		defer buffer_destroy(&b)
		buffer_set_text(&b, "abcdef")
		buffer_delete_range(&b, Position{0, 3}, Position{0, 6})
		testing.expect_value(t, buffer_line_str(&b, 0), "abc")

		testing.expect(t, buffer_undo(&b), "undo should succeed")
		testing.expect_value(t, buffer_line_str(&b, 0), "abcdef")

		testing.expect(t, buffer_redo(&b), "redo should succeed")
		testing.expect_value(t, buffer_line_str(&b, 0), "abc")
	})
}

@(test)
test_undo_group_batches_edits :: proc(t: ^testing.T) {
	run_leak_free(t, proc(t: ^testing.T) {
		b := buffer_init()
		defer buffer_destroy(&b)
		buffer_set_text(&b, "")

		buffer_type_text(&b, "a")
		buffer_type_text(&b, "b")
		buffer_type_text(&b, "c")
		testing.expect_value(t, buffer_line_str(&b, 0), "abc")

		// Each buffer_type_text call is its own undo group, so three undos
		// are required to fully revert three separate typed characters.
		buffer_undo(&b)
		testing.expect_value(t, buffer_line_str(&b, 0), "ab")
		buffer_undo(&b)
		testing.expect_value(t, buffer_line_str(&b, 0), "a")
		buffer_undo(&b)
		testing.expect_value(t, buffer_line_str(&b, 0), "")
	})
}

@(test)
test_cursor_movement_basic :: proc(t: ^testing.T) {
	run_leak_free(t, proc(t: ^testing.T) {
		b := buffer_init()
		defer buffer_destroy(&b)
		buffer_set_text(&b, "hello\nworld")
		c := Cursor{pos = Position{0, 0}}

		cursor_move_right(&b, &c, false)
		testing.expect_value(t, c.pos, Position{0, 1})

		cursor_move_line_end(&b, &c, false)
		testing.expect_value(t, c.pos, Position{0, 5})

		cursor_move_right(&b, &c, false)
		testing.expect_value(t, c.pos, Position{1, 0})

		// At the last line, Down (VSCode-style) jumps to end of that line.
		cursor_move_down(&b, &c, false)
		testing.expect_value(t, c.pos, Position{1, 5})

		cursor_move_left(&b, &c, false)
		testing.expect_value(t, c.pos, Position{1, 4})
	})
}

@(test)
test_cursor_word_movement :: proc(t: ^testing.T) {
	run_leak_free(t, proc(t: ^testing.T) {
		b := buffer_init()
		defer buffer_destroy(&b)
		buffer_set_text(&b, "foo bar_baz  qux")
		c := Cursor{pos = Position{0, 0}}

		cursor_move_word_right(&b, &c, false)
		testing.expect_value(t, c.pos, Position{0, 3})
		cursor_move_word_right(&b, &c, false)
		testing.expect_value(t, c.pos, Position{0, 11})
		cursor_move_word_right(&b, &c, false)
		testing.expect_value(t, c.pos, Position{0, 16})

		cursor_move_word_left(&b, &c, false)
		testing.expect_value(t, c.pos, Position{0, 13})
	})
}

@(test)
test_selection_extend_and_clear :: proc(t: ^testing.T) {
	run_leak_free(t, proc(t: ^testing.T) {
		b := buffer_init()
		defer buffer_destroy(&b)
		buffer_set_text(&b, "hello world")
		c := Cursor{pos = Position{0, 0}}

		cursor_move_right(&b, &c, true)
		cursor_move_right(&b, &c, true)
		cursor_move_right(&b, &c, true)
		start, end, ok := selection_range(c)
		testing.expect(t, ok, "expected active selection")
		testing.expect_value(t, start, Position{0, 0})
		testing.expect_value(t, end, Position{0, 3})

		cursor_move_right(&b, &c, false)
		_, _, ok2 := selection_range(c)
		testing.expect(t, !ok2, "selection should clear on non-extend move")
	})
}

@(test)
test_select_all :: proc(t: ^testing.T) {
	run_leak_free(t, proc(t: ^testing.T) {
		b := buffer_init()
		defer buffer_destroy(&b)
		buffer_set_text(&b, "foo\nbar\nbaz")
		c := Cursor{pos = Position{1, 1}}
		cursor_select_all(&b, &c)
		start, end, ok := selection_range(c)
		testing.expect(t, ok, "expected selection")
		testing.expect_value(t, start, Position{0, 0})
		testing.expect_value(t, end, Position{2, 3})
	})
}

@(test)
test_select_word :: proc(t: ^testing.T) {
	run_leak_free(t, proc(t: ^testing.T) {
		b := buffer_init()
		defer buffer_destroy(&b)
		buffer_set_text(&b, "foo bar_baz qux")
		c := Cursor{pos = Position{0, 6}}
		cursor_select_word(&b, &c)
		start, end, ok := selection_range(c)
		testing.expect(t, ok, "expected selection")
		testing.expect_value(t, start, Position{0, 4})
		testing.expect_value(t, end, Position{0, 11})
	})
}

@(test)
test_type_text_with_selection_replaces :: proc(t: ^testing.T) {
	run_leak_free(t, proc(t: ^testing.T) {
		b := buffer_init()
		defer buffer_destroy(&b)
		buffer_set_text(&b, "hello world")
		b.cursors[0] = Cursor{pos = Position{0, 11}, sel = Selection{anchor = Position{0, 6}, active = true}}
		buffer_type_text(&b, "there")
		testing.expect_value(t, buffer_line_str(&b, 0), "hello there")
	})
}

@(test)
test_backspace_and_delete_forward :: proc(t: ^testing.T) {
	run_leak_free(t, proc(t: ^testing.T) {
		b := buffer_init()
		defer buffer_destroy(&b)
		buffer_set_text(&b, "hello")
		b.cursors[0] = Cursor{pos = Position{0, 5}}
		buffer_backspace(&b)
		testing.expect_value(t, buffer_line_str(&b, 0), "hell")

		b.cursors[0] = Cursor{pos = Position{0, 0}}
		buffer_delete_forward(&b)
		testing.expect_value(t, buffer_line_str(&b, 0), "ell")
	})
}

@(test)
test_backspace_merges_lines :: proc(t: ^testing.T) {
	run_leak_free(t, proc(t: ^testing.T) {
		b := buffer_init()
		defer buffer_destroy(&b)
		buffer_set_text(&b, "foo\nbar")
		b.cursors[0] = Cursor{pos = Position{1, 0}}
		buffer_backspace(&b)
		testing.expect_value(t, buffer_line_count(&b), 1)
		testing.expect_value(t, buffer_line_str(&b, 0), "foobar")
	})
}

@(test)
test_newline_auto_indent :: proc(t: ^testing.T) {
	run_leak_free(t, proc(t: ^testing.T) {
		b := buffer_init()
		defer buffer_destroy(&b)
		buffer_set_text(&b, "    foo")
		b.cursors[0] = Cursor{pos = Position{0, 7}}
		buffer_newline(&b)
		testing.expect_value(t, buffer_line_count(&b), 2)
		testing.expect_value(t, buffer_line_str(&b, 1), "    ")
		testing.expect_value(t, b.cursors[0].pos, Position{1, 4})
	})
}

@(test)
test_indent_and_outdent_selection :: proc(t: ^testing.T) {
	run_leak_free(t, proc(t: ^testing.T) {
		b := buffer_init()
		defer buffer_destroy(&b)
		buffer_set_text(&b, "foo\nbar")
		b.cursors[0] = Cursor{pos = Position{1, 3}, sel = Selection{anchor = Position{0, 0}, active = true}}
		buffer_indent(&b)
		testing.expect_value(t, buffer_line_str(&b, 0), "    foo")
		testing.expect_value(t, buffer_line_str(&b, 1), "    bar")

		b.cursors[0] = Cursor{pos = Position{1, 7}, sel = Selection{anchor = Position{0, 0}, active = true}}
		buffer_outdent(&b)
		testing.expect_value(t, buffer_line_str(&b, 0), "foo")
		testing.expect_value(t, buffer_line_str(&b, 1), "bar")
	})
}

@(test)
test_multi_cursor_type_text :: proc(t: ^testing.T) {
	run_leak_free(t, proc(t: ^testing.T) {
		b := buffer_init()
		defer buffer_destroy(&b)
		buffer_set_text(&b, "foo\nfoo\nfoo")
		clear(&b.cursors)
		append(&b.cursors, Cursor{pos = Position{0, 3}})
		append(&b.cursors, Cursor{pos = Position{1, 3}})
		append(&b.cursors, Cursor{pos = Position{2, 3}})

		buffer_type_text(&b, "!")

		testing.expect_value(t, buffer_line_str(&b, 0), "foo!")
		testing.expect_value(t, buffer_line_str(&b, 1), "foo!")
		testing.expect_value(t, buffer_line_str(&b, 2), "foo!")
	})
}

@(test)
test_file_save_and_load_roundtrip :: proc(t: ^testing.T) {
	run_leak_free(t, proc(t: ^testing.T) {
		b := buffer_init()
		defer buffer_destroy(&b)
		buffer_set_text(&b, "line one\nline two\n")

		path := "/tmp/odin_editor_buffer_test.txt"
		ok := buffer_save_file(&b, path)
		testing.expect(t, ok, "expected save to succeed")

		b2 := buffer_init()
		defer buffer_destroy(&b2)
		ok2 := buffer_load_file(&b2, path)
		testing.expect(t, ok2, "expected load to succeed")
		testing.expect_value(t, buffer_to_string(&b2, context.temp_allocator), "line one\nline two\n")
	})
}
