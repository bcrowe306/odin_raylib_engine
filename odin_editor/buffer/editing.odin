// Low-level and history-recording text mutation for Buffer. Low-level
// `raw_` procs never touch undo/redo; the public `buffer_insert_text` /
// `buffer_delete_range` wrap them and push onto the undo stack.
package buffer

import "core:strings"

// buffer_raw_insert inserts `text` at `pos`, splitting it across newlines as
// needed, and returns the position immediately after the inserted text.
// Does not record undo history.
buffer_raw_insert :: proc(b: ^Buffer, pos: Position, text: string) -> Position {
	if len(text) == 0 {
		return pos
	}
	p := buffer_clamp_position(b, pos)
	line_str := buffer_line_str(b, p.line)
	before := line_str[:p.col]
	after := line_str[p.col:]

	// Split incoming text on '\n'.
	segments := make([dynamic]string, 0, 4, context.temp_allocator)
	start := 0
	for i := 0; i <= len(text); i += 1 {
		if i == len(text) || text[i] == '\n' {
			segment := text[start:i]
			if len(segment) > 0 && segment[len(segment) - 1] == '\r' {
				segment = segment[:len(segment) - 1]
			}
			append(&segments, segment)
			start = i + 1
		}
	}

	if len(segments) == 1 {
		// Single-line insert: just splice into the existing line builder.
		new_line := strings.builder_make(b.allocator)
		strings.write_string(&new_line, before)
		strings.write_string(&new_line, segments[0])
		strings.write_string(&new_line, after)
		strings.builder_destroy(&b.lines[p.line])
		b.lines[p.line] = new_line
		end := Position{line = p.line, col = len(before) + len(segments[0])}
		b.dirty = true
		return end
	}

	// Multi-line insert: first segment stays on the original line, middle
	// segments become new lines, last segment + `after` becomes the final
	// new line.
	first_line := strings.builder_make(b.allocator)
	strings.write_string(&first_line, before)
	strings.write_string(&first_line, segments[0])
	strings.builder_destroy(&b.lines[p.line])
	b.lines[p.line] = first_line

	new_lines := make([dynamic]strings.Builder, 0, len(segments) - 1, context.temp_allocator)
	for i := 1; i < len(segments) - 1; i += 1 {
		sb := strings.builder_make(b.allocator)
		strings.write_string(&sb, segments[i])
		append(&new_lines, sb)
	}
	last_line := strings.builder_make(b.allocator)
	strings.write_string(&last_line, segments[len(segments) - 1])
	strings.write_string(&last_line, after)
	append(&new_lines, last_line)

	// Shift existing lines down and insert new_lines after p.line.
	insert_at := p.line + 1
	for nl, i in new_lines {
		inject_at(&b.lines, insert_at + i, nl)
	}

	end := Position{
		line = p.line + len(segments) - 1,
		col  = len(segments[len(segments) - 1]),
	}
	b.dirty = true
	return end
}

// buffer_raw_delete removes text in [start, end) (document order assumed
// normalized by caller) and returns the removed text (allocated with
// `b.allocator`; caller owns it). Does not record undo history.
buffer_raw_delete :: proc(b: ^Buffer, start, end: Position) -> string {
	s := buffer_clamp_position(b, start)
	e := buffer_clamp_position(b, end)
	if position_eq(s, e) {
		return ""
	}
	if position_less(e, s) {
		s, e = e, s
	}

	if s.line == e.line {
		line_str := buffer_line_str(b, s.line)
		removed := strings.clone(line_str[s.col:e.col], b.allocator)
		new_line := strings.builder_make(b.allocator)
		strings.write_string(&new_line, line_str[:s.col])
		strings.write_string(&new_line, line_str[e.col:])
		strings.builder_destroy(&b.lines[s.line])
		b.lines[s.line] = new_line
		b.dirty = true
		return removed
	}

	// Multi-line delete: build removed text from the affected lines, then
	// merge first/last remnants into s.line and remove the lines in between.
	sb := strings.builder_make(context.temp_allocator)
	first_str := buffer_line_str(b, s.line)
	strings.write_string(&sb, first_str[s.col:])
	for ln := s.line + 1; ln < e.line; ln += 1 {
		strings.write_byte(&sb, '\n')
		strings.write_string(&sb, buffer_line_str(b, ln))
	}
	strings.write_byte(&sb, '\n')
	last_str := buffer_line_str(b, e.line)
	strings.write_string(&sb, last_str[:e.col])
	removed := strings.clone(strings.to_string(sb), b.allocator)

	merged := strings.builder_make(b.allocator)
	strings.write_string(&merged, first_str[:s.col])
	strings.write_string(&merged, last_str[e.col:])
	strings.builder_destroy(&b.lines[s.line])
	b.lines[s.line] = merged

	// Remove lines (s.line+1 ..= e.line).
	remove_count := e.line - s.line
	for i := 0; i < remove_count; i += 1 {
		idx := s.line + 1
		strings.builder_destroy(&b.lines[idx])
		ordered_remove(&b.lines, idx)
	}

	b.dirty = true
	return removed
}

// buffer_insert_text is the public editing API: inserts text at `pos` and
// records an undo entry. Returns the end position of the inserted text.
buffer_insert_text :: proc(b: ^Buffer, pos: Position, text: string, group_id := -1) -> Position {
	end := buffer_raw_insert(b, pos, text)
	append(&b.undo_stack, Edit{
		kind     = .Insert,
		start    = pos,
		end      = end,
		text     = strings.clone(text, b.allocator),
		group_id = group_id,
	})
	buffer_clear_redo(b)
	return end
}

// buffer_delete_range is the public editing API: deletes [start, end) and
// records an undo entry. Returns the removed text (caller does NOT own it;
// it is retained inside the undo stack until the edit is dropped).
buffer_delete_range :: proc(b: ^Buffer, start, end: Position, group_id := -1) -> string {
	s := position_min(start, end)
	e := position_max(start, end)
	removed := buffer_raw_delete(b, s, e)
	append(&b.undo_stack, Edit{
		kind     = .Delete,
		start    = s,
		end      = e,
		text     = removed,
		group_id = group_id,
	})
	buffer_clear_redo(b)
	return removed
}

buffer_clear_redo :: proc(b: ^Buffer) {
	for e in b.redo_stack {
		delete(e.text, b.allocator)
	}
	clear(&b.redo_stack)
}

// buffer_next_group begins a new undo group id. Pass the returned value as
// `group_id` to successive `buffer_insert_text`/`buffer_delete_range` calls
// that should undo/redo together as a single user action (e.g. multi-cursor
// edits or autocomplete expansions).
buffer_next_group :: proc(b: ^Buffer) -> int {
	b.group_seq += 1
	return b.group_seq
}

// buffer_undo reverts the most recent edit (or group of edits sharing a
// group_id). Returns true if an edit was undone.
buffer_undo :: proc(b: ^Buffer) -> bool {
	if len(b.undo_stack) == 0 {
		return false
	}
	group_id := b.undo_stack[len(b.undo_stack) - 1].group_id
	for len(b.undo_stack) > 0 {
		top := b.undo_stack[len(b.undo_stack) - 1]
		if group_id != -1 && top.group_id != group_id {
			break
		}
		pop(&b.undo_stack)
		switch top.kind {
		case .Insert:
			discarded := buffer_raw_delete(b, top.start, top.end)
			delete(discarded, b.allocator)
			append(&b.redo_stack, top)
		case .Delete:
			buffer_raw_insert(b, top.start, top.text)
			append(&b.redo_stack, top)
		}
		if group_id == -1 {
			break
		}
	}
	return true
}

// buffer_redo re-applies the most recently undone edit (or group). Returns
// true if an edit was redone.
buffer_redo :: proc(b: ^Buffer) -> bool {
	if len(b.redo_stack) == 0 {
		return false
	}
	group_id := b.redo_stack[len(b.redo_stack) - 1].group_id
	for len(b.redo_stack) > 0 {
		top := b.redo_stack[len(b.redo_stack) - 1]
		if group_id != -1 && top.group_id != group_id {
			break
		}
		pop(&b.redo_stack)
		switch top.kind {
		case .Insert:
			buffer_raw_insert(b, top.start, top.text)
			append(&b.undo_stack, top)
		case .Delete:
			discarded := buffer_raw_delete(b, top.start, top.end)
			delete(discarded, b.allocator)
			append(&b.undo_stack, top)
		}
		if group_id == -1 {
			break
		}
	}
	return true
}
