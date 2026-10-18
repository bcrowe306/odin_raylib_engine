// Package buffer implements a modular, host-agnostic text buffer with
// cursor/selection management and undo/redo history. It has no dependency
// on SDL or rendering and can be unit tested in isolation, then embedded in
// any host application.
package buffer

import "core:mem"
import "core:strings"

// Position is a (line, byte_col) location inside the buffer. `col` is a
// byte offset into the UTF-8 encoded line and is always kept aligned to a
// rune boundary by the editing/movement APIs.
Position :: struct {
	line: int,
	col:  int,
}

position_eq :: proc(a, b: Position) -> bool {
	return a.line == b.line && a.col == b.col
}

// position_less returns true if `a` comes strictly before `b` in document
// order.
position_less :: proc(a, b: Position) -> bool {
	if a.line != b.line {
		return a.line < b.line
	}
	return a.col < b.col
}

position_min :: proc(a, b: Position) -> Position {
	return a if position_less(a, b) else b
}

position_max :: proc(a, b: Position) -> Position {
	return b if position_less(a, b) else a
}

Selection :: struct {
	anchor: Position,
	active: bool,
}

Cursor :: struct {
	pos: Position,
	sel: Selection,
}

// selection_range returns the normalized (start, end) range of a cursor's
// selection. `ok` is false when there is no active selection.
selection_range :: proc(c: Cursor) -> (start: Position, end: Position, ok: bool) {
	if !c.sel.active || position_eq(c.sel.anchor, c.pos) {
		return {}, {}, false
	}
	return position_min(c.sel.anchor, c.pos), position_max(c.sel.anchor, c.pos), true
}

EditKind :: enum {
	Insert,
	Delete,
}

// Edit is a single undoable/redoable operation. `text` is the text that was
// inserted (for Insert) or removed (for Delete), so the inverse operation
// can be replayed without re-deriving it. Edits sharing the same
// `group_id` are undone/redone together as one logical user action.
Edit :: struct {
	kind:     EditKind,
	start:    Position,
	end:      Position,
	text:     string,
	group_id: int,
}

Buffer :: struct {
	lines:      [dynamic]strings.Builder,
	cursors:    [dynamic]Cursor,
	undo_stack: [dynamic]Edit,
	redo_stack: [dynamic]Edit,
	dirty:      bool,
	file_path:  string,
	allocator:  mem.Allocator,
	group_seq:  int,
}

buffer_init :: proc(allocator := context.allocator) -> Buffer {
	b := Buffer {
		allocator = allocator,
	}
	b.lines = make([dynamic]strings.Builder, allocator)
	append(&b.lines, strings.builder_make(allocator))
	b.cursors = make([dynamic]Cursor, allocator)
	append(&b.cursors, Cursor{})
	b.undo_stack = make([dynamic]Edit, allocator)
	b.redo_stack = make([dynamic]Edit, allocator)
	return b
}

buffer_destroy :: proc(b: ^Buffer) {
	for &line in b.lines {
		strings.builder_destroy(&line)
	}
	delete(b.lines)
	delete(b.cursors)
	buffer_clear_undo_history(b)
	delete(b.undo_stack)
	delete(b.redo_stack)
	if len(b.file_path) > 0 {
		delete(b.file_path, b.allocator)
	}
}

buffer_clear_undo_history :: proc(b: ^Buffer) {
	for e in b.undo_stack {
		delete(e.text, b.allocator)
	}
	for e in b.redo_stack {
		delete(e.text, b.allocator)
	}
	clear(&b.undo_stack)
	clear(&b.redo_stack)
}

buffer_line_count :: proc(b: ^Buffer) -> int {
	return len(b.lines)
}

buffer_line_str :: proc(b: ^Buffer, line: int) -> string {
	if line < 0 || line >= len(b.lines) {
		return ""
	}
	return strings.to_string(b.lines[line])
}

buffer_line_len :: proc(b: ^Buffer, line: int) -> int {
	return len(buffer_line_str(b, line))
}

buffer_clamp_position :: proc(b: ^Buffer, pos: Position) -> Position {
	p := pos
	line_count := buffer_line_count(b)
	if p.line < 0 {
		p.line = 0
	}
	if p.line >= line_count {
		p.line = line_count - 1
	}
	line_len := buffer_line_len(b, p.line)
	if p.col < 0 {
		p.col = 0
	}
	if p.col > line_len {
		p.col = line_len
	}
	return p
}

buffer_end_position :: proc(b: ^Buffer) -> Position {
	last := buffer_line_count(b) - 1
	return Position{line = last, col = buffer_line_len(b, last)}
}

// buffer_set_text replaces the entire contents of the buffer with `text`.
// Resets cursors to the start and clears undo history (used for file load).
buffer_set_text :: proc(b: ^Buffer, text: string) {
	for &line in b.lines {
		strings.builder_destroy(&line)
	}
	clear(&b.lines)

	start := 0
	for i := 0; i <= len(text); i += 1 {
		if i == len(text) || text[i] == '\n' {
			segment := text[start:i]
			// Strip a trailing \r for CRLF line endings.
			if len(segment) > 0 && segment[len(segment) - 1] == '\r' {
				segment = segment[:len(segment) - 1]
			}
			sb := strings.builder_make(b.allocator)
			strings.write_string(&sb, segment)
			append(&b.lines, sb)
			start = i + 1
		}
	}
	if len(b.lines) == 0 {
		append(&b.lines, strings.builder_make(b.allocator))
	}

	clear(&b.cursors)
	append(&b.cursors, Cursor{})
	buffer_clear_undo_history(b)
	b.dirty = false
}

// buffer_to_string concatenates all lines with '\n' separators. Caller owns
// the returned string (allocated with `allocator`).
buffer_to_string :: proc(b: ^Buffer, allocator := context.allocator) -> string {
	sb := strings.builder_make(allocator)
	for i := 0; i < len(b.lines); i += 1 {
		strings.write_string(&sb, strings.to_string(b.lines[i]))
		if i != len(b.lines) - 1 {
			strings.write_byte(&sb, '\n')
		}
	}
	return strings.to_string(sb)
}
