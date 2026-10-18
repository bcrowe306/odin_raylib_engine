// Viewport/scrolling math. Pure functions over Editor's scroll/visible
// fields and the buffer's line data — no SDL subsystem required, so fully
// unit testable.
package editor

import buf "../buffer"

editor_clamp_scroll :: proc(ed: ^Editor) {
	max_line := max(0, buf.buffer_line_count(&ed.buf) - 1)
	if ed.scroll_line < 0 {
		ed.scroll_line = 0
	}
	if ed.scroll_line > max_line {
		ed.scroll_line = max_line
	}
	if ed.scroll_col < 0 {
		ed.scroll_col = 0
	}
}

editor_clamp_to_buffer :: proc(ed: ^Editor, line, col: int) -> buf.Position {
	return buf.buffer_clamp_position(&ed.buf, buf.Position{line = line, col = col})
}

// editor_ensure_cursor_visible scrolls the viewport (in cell units) just
// enough that the primary cursor's position is within the visible rows and
// columns, matching typical editor "follow the caret" behavior.
editor_ensure_cursor_visible :: proc(ed: ^Editor) {
	c := editor_primary_cursor(ed)

	if c.pos.line < ed.scroll_line {
		ed.scroll_line = c.pos.line
	}
	rows := max(1, ed.visible_rows)
	if c.pos.line >= ed.scroll_line + rows {
		ed.scroll_line = c.pos.line - rows + 1
	}

	if c.pos.col < ed.scroll_col {
		ed.scroll_col = c.pos.col
	}
	cols := max(1, ed.visible_cols)
	if c.pos.col >= ed.scroll_col + cols {
		ed.scroll_col = c.pos.col - cols + 1
	}

	editor_clamp_scroll(ed)
}
