// Maps resolved `keymap.Action`s onto `buffer` operations, applied to every
// cursor. Entirely independent of SDL — testable by constructing an Editor
// and calling `editor_apply_action` directly.
package editor

import buf "../buffer"
import km "../keymap"
import "core:strings"

// editor_apply_action executes a non-text-insertion action (navigation,
// selection, editing commands, clipboard, undo/redo) against every cursor
// in the buffer. Returns false if the action isn't handled here (e.g. it's
// a host-level action like Save/Open that the embedding app must wire up).
editor_apply_action :: proc(ed: ^Editor, action: km.Action) -> bool {
	b := &ed.buf
	switch action {
	case .None:
		return true

	case .MoveLeft, .MoveRight, .MoveUp, .MoveDown,
	     .MoveWordLeft, .MoveWordRight,
	     .MoveLineStart, .MoveLineEnd,
	     .MoveDocStart, .MoveDocEnd,
	     .MovePageUp, .MovePageDown,
	     .ExtendLeft, .ExtendRight, .ExtendUp, .ExtendDown,
	     .ExtendWordLeft, .ExtendWordRight,
	     .ExtendLineStart, .ExtendLineEnd,
	     .ExtendDocStart, .ExtendDocEnd,
	     .ExtendPageUp, .ExtendPageDown:
		for &c in b.cursors {
			apply_movement(b, &c, action)
		}
		return true

	case .SelectAll:
		// Select-all collapses to a single cursor spanning the document.
		resize(&b.cursors, 1)
		buf.cursor_select_all(b, &b.cursors[0])
		return true

	case .SelectLine:
		for &c in b.cursors {
			buf.cursor_select_line(b, &c)
		}
		return true

	case .SelectWord:
		for &c in b.cursors {
			buf.cursor_select_word(b, &c)
		}
		return true

	case .Backspace:
		buf.buffer_backspace(b)
		return true
	case .BackspaceWord:
		buf.buffer_backspace(b, word_mode = true)
		return true
	case .DeleteForward:
		buf.buffer_delete_forward(b)
		return true
	case .DeleteForwardWord:
		buf.buffer_delete_forward(b, word_mode = true)
		return true
	case .Newline:
		buf.buffer_newline(b)
		return true
	case .IndentOrTab:
		buf.buffer_indent(b)
		return true
	case .Outdent:
		buf.buffer_outdent(b)
		return true

	case .Undo:
		buf.buffer_undo(b)
		return true
	case .Redo:
		buf.buffer_redo(b)
		return true

	case .Cut, .Copy, .Paste:
		// Clipboard requires SDL; handled in clipboard.odin, which calls
		// back into buffer ops. Reported as unhandled here so the SDL glue
		// layer takes over.
		return false

	case .Save, .SaveAs, .Open:
		return false

	case .AddCursorAbove, .AddCursorBelow:
		editor_add_cursor(ed, action == .AddCursorAbove ? -1 : 1)
		return true

	case .TriggerCompletion, .TriggerSignatureHelp:
		return false

	case .Escape:
		for &c in b.cursors {
			c.sel.active = false
		}
		if len(b.cursors) > 1 {
			resize(&b.cursors, 1)
		}
		return true
	}
	return false
}

@(private)
apply_movement :: proc(b: ^buf.Buffer, c: ^buf.Cursor, action: km.Action) {
	#partial switch action {
	case .MoveLeft: buf.cursor_move_left(b, c, false)
	case .ExtendLeft: buf.cursor_move_left(b, c, true)
	case .MoveRight: buf.cursor_move_right(b, c, false)
	case .ExtendRight: buf.cursor_move_right(b, c, true)
	case .MoveUp: buf.cursor_move_up(b, c, false)
	case .ExtendUp: buf.cursor_move_up(b, c, true)
	case .MoveDown: buf.cursor_move_down(b, c, false)
	case .ExtendDown: buf.cursor_move_down(b, c, true)
	case .MoveWordLeft: buf.cursor_move_word_left(b, c, false)
	case .ExtendWordLeft: buf.cursor_move_word_left(b, c, true)
	case .MoveWordRight: buf.cursor_move_word_right(b, c, false)
	case .ExtendWordRight: buf.cursor_move_word_right(b, c, true)
	case .MoveLineStart: buf.cursor_move_line_start(b, c, false)
	case .ExtendLineStart: buf.cursor_move_line_start(b, c, true)
	case .MoveLineEnd: buf.cursor_move_line_end(b, c, false)
	case .ExtendLineEnd: buf.cursor_move_line_end(b, c, true)
	case .MoveDocStart: buf.cursor_move_doc_start(b, c, false)
	case .ExtendDocStart: buf.cursor_move_doc_start(b, c, true)
	case .MoveDocEnd: buf.cursor_move_doc_end(b, c, false)
	case .ExtendDocEnd: buf.cursor_move_doc_end(b, c, true)
	case .MovePageUp: buf.cursor_move_page(b, c, -20, false)
	case .ExtendPageUp: buf.cursor_move_page(b, c, -20, true)
	case .MovePageDown: buf.cursor_move_page(b, c, 20, false)
	case .ExtendPageDown: buf.cursor_move_page(b, c, 20, true)
	}
}

// editor_add_cursor adds a new cursor one line above/below (dir = -1/+1)
// the current primary cursor, at the same column — mirrors VSCode/Zed's
// Ctrl/Cmd+Alt+Up/Down multi-cursor shortcut.
editor_add_cursor :: proc(ed: ^Editor, dir: int) {
	b := &ed.buf
	last := b.cursors[len(b.cursors) - 1]
	target_line := last.pos.line + dir
	if target_line < 0 || target_line >= buf.buffer_line_count(b) {
		return
	}
	col := min(last.pos.col, buf.buffer_line_len(b, target_line))
	append(&b.cursors, buf.Cursor{pos = buf.Position{line = target_line, col = col}})
}

// editor_insert_text types `text` at every cursor (used for both regular
// text-input events and programmatic insertion).
editor_insert_text :: proc(ed: ^Editor, text: string) {
	buf.buffer_type_text(&ed.buf, text)
}
