// Mouse integration: hit-testing (text / gutter / popups), click-to-place,
// drag-select (by character, word or line), Shift+click extend,
// double/triple-click word/line selection, Alt+click multi-cursor,
// gutter line selection, wheel scrolling (vertical, horizontal, and the
// completion list), auto-scroll while dragging past the viewport edge, and
// the mouse-cursor shape the host should show. No SDL rendering here; the
// logic is unit tested with synthetic SDL events in mouse_test.odin.
package editor

import buf "../buffer"
import km "../keymap"
import "core:time"
import sdl "vendor:sdl3"

WHEEL_LINES :: 3
AUTOSCROLL_INTERVAL :: 30 * time.Millisecond

Mouse_Zone :: enum {
	Outside,
	Gutter,
	Text,
	Completion,
	Signature,
	Problems, // the problems panel (row = problem index, -1 = header)
	Code_Actions, // the quick-fix menu (row = action index)
}

Drag_Mode :: enum {
	None,
	Chars,
	Words,
	Lines,
}

// Mouse_Cursor is the pointer shape the host should display (the editor
// doesn't own SDL cursor objects, since several editors may share a
// window); see editor_mouse_cursor.
Mouse_Cursor :: enum {
	Default,
	Text,
}

Mouse_State :: struct {
	x, y:  f32,
	zone:  Mouse_Zone,
	drag:  Drag_Mode,
	// Index into buf.cursors of the cursor the drag is extending.
	drag_cursor: int,
	// The word/line picked by the double/triple click that started a
	// word/line drag; the selection always includes it.
	unit_start, unit_end: buf.Position,
	last_autoscroll: time.Tick,
	// Fractional wheel deltas (trackpads) carried between events.
	wheel_acc_x, wheel_acc_y: f32,
}

Hit :: struct {
	zone: Mouse_Zone,
	pos:  buf.Position, // nearest caret position (valid for every zone)
	row:  int,          // filtered completion index, for .Completion
}

@(private)
in_rect :: proc(r: sdl.FRect, x, y: f32) -> bool {
	return x >= r.x && x < r.x + r.w && y >= r.y && y < r.y + r.h
}

// editor_screen_to_position maps window pixels to the nearest caret
// position. Points above the document map to its start, below to its end,
// left of the text to column 0 — which is what drag-selection wants.
editor_screen_to_position :: proc(ed: ^Editor, x, y: f32) -> buf.Position {
	if ed.char_w <= 0 || ed.char_h <= 0 {
		return {}
	}
	row_f := (y - ed.origin_y) / ed.char_h
	line := ed.scroll_line + (int(row_f) if row_f >= 0 else int(row_f) - 1)
	count := buf.buffer_line_count(&ed.buf)
	if line < 0 {
		return {0, 0}
	}
	if line >= count {
		return buf.buffer_end_position(&ed.buf)
	}
	vcol := f32(ed.scroll_col) + (x - ed.origin_x - GUTTER_WIDTH) / ed.char_w
	return {line, byte_col_at_visual(buf.buffer_line_str(&ed.buf, line), vcol, ed.tab_width)}
}

// editor_hit_test classifies a window-pixel point.
editor_hit_test :: proc(ed: ^Editor, x, y: f32) -> Hit {
	hit := Hit{pos = editor_screen_to_position(ed, x, y)}
	if rect, ok := editor_code_actions_layout(ed); ok && in_rect(rect, x, y) {
		hit.zone = .Code_Actions
		hit.row = int((y - rect.y - POPUP_PAD) / ed.char_h)
		return hit
	}
	layout := editor_popup_layout(ed)
	if layout.completion_visible && in_rect(layout.completion, x, y) {
		row := ed.completion.scroll + int((y - layout.completion.y - POPUP_PAD) / ed.char_h)
		hit.zone = .Completion
		hit.row = clamp(row, 0, len(ed.completion.filtered) - 1)
		return hit
	}
	if layout.signature_visible && in_rect(layout.signature, x, y) {
		hit.zone = .Signature
		return hit
	}
	right := ed.origin_x + GUTTER_WIDTH + f32(ed.visible_cols) * ed.char_w
	bottom := ed.origin_y + f32(editor_text_rows(ed)) * ed.char_h
	panel_bottom := ed.origin_y + f32(ed.visible_rows) * ed.char_h
	switch {
	case x < ed.origin_x || x >= right || y < ed.origin_y || y >= panel_bottom:
		hit.zone = .Outside
	case y >= bottom:
		hit.zone = .Problems
		hit.row = problems_row_at(ed, y)
	case x < ed.origin_x + GUTTER_WIDTH:
		hit.zone = .Gutter
	case:
		hit.zone = .Text
	}
	return hit
}

// editor_mouse_cursor is the pointer shape for the current hover/drag
// state: an I-beam over text (and throughout a drag), an arrow elsewhere.
editor_mouse_cursor :: proc(ed: ^Editor) -> Mouse_Cursor {
	if ed.mouse.drag != .None || ed.mouse.zone == .Text {
		return .Text
	}
	return .Default
}

// editor_current_mods combines modifiers seen as key events (the only way
// injected input can express them) with SDL's live keyboard state.
editor_current_mods :: proc(ed: ^Editor) -> km.Modifiers {
	return ed.key_mods | sdl_mod_to_keymap_mods(sdl.GetModState())
}

// editor_track_modifier_key updates key_mods from a modifier key's
// press/release. Non-modifier keys are ignored on purpose: their `mod`
// field describes chords (e.g. an injected Shift+End), not held keys.
@(private)
editor_track_modifier_key :: proc(ed: ^Editor, key: sdl.KeyboardEvent) {
	m: km.Modifier
	switch key.key {
	case sdl.K_LSHIFT, sdl.K_RSHIFT: m = .Shift
	case sdl.K_LCTRL, sdl.K_RCTRL:   m = .Ctrl
	case sdl.K_LALT, sdl.K_RALT:     m = .Alt
	case sdl.K_LGUI, sdl.K_RGUI:     m = .Super
	case: return
	}
	if key.down {
		ed.key_mods += {m}
	} else {
		ed.key_mods -= {m}
	}
}

// --- word / line units ----------------------------------------------------

@(private)
word_range_at :: proc(ed: ^Editor, pos: buf.Position) -> (start, end: buf.Position) {
	tmp := buf.Cursor{pos = pos}
	buf.cursor_select_word(&ed.buf, &tmp)
	if !tmp.sel.active {
		return pos, pos
	}
	return buf.position_min(tmp.sel.anchor, tmp.pos), buf.position_max(tmp.sel.anchor, tmp.pos)
}

@(private)
line_range_at :: proc(ed: ^Editor, line: int) -> (start, end: buf.Position) {
	tmp := buf.Cursor{pos = {line, 0}}
	buf.cursor_select_line(&ed.buf, &tmp)
	return tmp.sel.anchor, tmp.pos
}

// --- buttons ----------------------------------------------------------------

@(private)
editor_handle_mouse_down :: proc(ed: ^Editor, ev: sdl.MouseButtonEvent) -> bool {
	ed.mouse.x, ed.mouse.y = ev.x, ev.y
	hit := editor_hit_test(ed, ev.x, ev.y)
	ed.mouse.zone = hit.zone
	if hit.zone == .Outside {
		return false
	}
	if ev.button != 1 { // only the left button does anything (yet)
		return true
	}

	b := &ed.buf
	mods := editor_current_mods(ed)
	switch hit.zone {
	case .Outside:
	case .Code_Actions:
		if hit.row >= 0 && hit.row < len(ed.lsp.last_code_actions) {
			editor_apply_code_action(ed, hit.row)
		}
	case .Problems:
		editor_open_problem(ed, hit.row)
	case .Completion:
		ed.completion.selected = hit.row
		editor_accept_completion(ed)
	case .Signature:
	case .Gutter:
		editor_close_completion(ed)
		resize(&b.cursors, 1)
		start, end := line_range_at(ed, hit.pos.line)
		b.cursors[0] = {pos = end, sel = {anchor = start, active = true}}
		ed.mouse.drag = .Lines
		ed.mouse.drag_cursor = 0
		ed.mouse.unit_start, ed.mouse.unit_end = start, end
	case .Text:
		editor_close_completion(ed)
		if .Alt in mods && .Shift not_in mods {
			editor_toggle_cursor_at(ed, hit.pos)
			return true
		}
		if .Shift in mods {
			// Extend the primary cursor's selection; others collapse.
			resize(&b.cursors, 1)
			c := &b.cursors[0]
			if !c.sel.active {
				c.sel.anchor = c.pos
			}
			c.pos = hit.pos
			c.sel.active = c.pos != c.sel.anchor
			ed.mouse.drag = .Chars
			ed.mouse.drag_cursor = 0
			return true
		}
		resize(&b.cursors, 1)
		c := &b.cursors[0]
		c.pos = hit.pos
		ed.mouse.drag_cursor = 0
		switch {
		case ev.clicks == 2:
			start, end := word_range_at(ed, hit.pos)
			c^ = {pos = end, sel = {anchor = start, active = start != end}}
			ed.mouse.drag = .Words
			ed.mouse.unit_start, ed.mouse.unit_end = start, end
		case ev.clicks >= 3:
			start, end := line_range_at(ed, hit.pos.line)
			c^ = {pos = end, sel = {anchor = start, active = true}}
			ed.mouse.drag = .Lines
			ed.mouse.unit_start, ed.mouse.unit_end = start, end
		case:
			c.sel = {anchor = hit.pos, active = false}
			ed.mouse.drag = .Chars
		}
	}
	return true
}

// editor_toggle_cursor_at adds a cursor at `pos`, or removes the one that
// is already there (keeping at least one) — Alt+click.
editor_toggle_cursor_at :: proc(ed: ^Editor, pos: buf.Position) {
	b := &ed.buf
	for c, i in b.cursors {
		if c.pos == pos && !c.sel.active {
			if len(b.cursors) > 1 {
				ordered_remove(&b.cursors, i)
			}
			return
		}
	}
	append(&b.cursors, buf.Cursor{pos = pos})
}

@(private)
editor_handle_mouse_up :: proc(ed: ^Editor, ev: sdl.MouseButtonEvent) -> bool {
	ed.mouse.x, ed.mouse.y = ev.x, ev.y
	if ev.button == 1 && ed.mouse.drag != .None {
		editor_drag_to(ed, editor_screen_to_position(ed, ev.x, ev.y))
		ed.mouse.drag = .None
		return true
	}
	return editor_hit_test(ed, ev.x, ev.y).zone != .Outside
}

@(private)
editor_handle_mouse_motion :: proc(ed: ^Editor, ev: sdl.MouseMotionEvent) -> bool {
	ed.mouse.x, ed.mouse.y = ev.x, ev.y
	hit := editor_hit_test(ed, ev.x, ev.y)
	ed.mouse.zone = hit.zone
	editor_track_diag_hover(ed, hit, ev.x, ev.y)
	if ed.mouse.drag != .None {
		editor_drag_to(ed, hit.pos)
		return true
	}
	return hit.zone != .Outside
}

// editor_drag_to extends the dragged cursor's selection to `pos`, in the
// unit (char/word/line) the drag started with.
editor_drag_to :: proc(ed: ^Editor, pos: buf.Position) {
	m := &ed.mouse
	if m.drag == .None || m.drag_cursor >= len(ed.buf.cursors) {
		return
	}
	c := &ed.buf.cursors[m.drag_cursor]
	switch m.drag {
	case .None:
	case .Chars:
		c.pos = pos
	case .Words, .Lines:
		start, end: buf.Position
		if m.drag == .Words {
			start, end = word_range_at(ed, pos)
		} else {
			start, end = line_range_at(ed, pos.line)
		}
		if buf.position_less(start, m.unit_start) {
			c.sel.anchor = m.unit_end
			c.pos = start
		} else {
			c.sel.anchor = m.unit_start
			c.pos = buf.position_max(end, m.unit_end)
		}
	}
	c.sel.active = c.pos != c.sel.anchor
}

// --- wheel & auto-scroll ------------------------------------------------------

@(private)
editor_handle_mouse_wheel :: proc(ed: ^Editor, ev: sdl.MouseWheelEvent) -> bool {
	ed.mouse.x, ed.mouse.y = ev.mouse_x, ev.mouse_y
	hit := editor_hit_test(ed, ev.mouse_x, ev.mouse_y)
	if hit.zone == .Outside {
		return false
	}
	dx, dy := ev.x, ev.y
	if ev.direction == .FLIPPED {
		dx, dy = -dx, -dy
	}
	if .Shift in editor_current_mods(ed) && dx == 0 {
		// Shift+wheel scrolls horizontally (wheel down -> right).
		dx, dy = -dy, 0
	}

	if hit.zone == .Problems {
		problems_scroll_by(ed, -int(dy))
		return true
	}
	if hit.zone == .Completion {
		cs := &ed.completion
		cs.scroll = clamp(cs.scroll - int(dy), 0, max(0, len(cs.filtered) - COMPLETION_MAX_VISIBLE))
		return true
	}

	m := &ed.mouse
	m.wheel_acc_y += -dy * WHEEL_LINES
	m.wheel_acc_x += dx * WHEEL_LINES
	lines := int(m.wheel_acc_y)
	cols := int(m.wheel_acc_x)
	m.wheel_acc_y -= f32(lines)
	m.wheel_acc_x -= f32(cols)
	ed.scroll_line += lines
	ed.scroll_col += cols
	editor_clamp_scroll(ed)
	if m.drag != .None {
		editor_drag_to(ed, editor_screen_to_position(ed, m.x, m.y))
	}
	return true
}

// editor_update_mouse auto-scrolls while a drag is held outside the text
// area, faster the further out the pointer is. Called from editor_update.
editor_update_mouse :: proc(ed: ^Editor) {
	m := &ed.mouse
	if m.drag == .None || ed.char_h <= 0 {
		return
	}
	if time.tick_since(m.last_autoscroll) < AUTOSCROLL_INTERVAL {
		return
	}
	top := ed.origin_y
	bottom := ed.origin_y + f32(editor_text_rows(ed)) * ed.char_h
	left := ed.origin_x + GUTTER_WIDTH
	right := left + f32(ed.visible_cols) * ed.char_w

	dl, dc := 0, 0
	switch {
	case m.y < top: dl = -(1 + int((top - m.y) / ed.char_h))
	case m.y >= bottom: dl = 1 + int((m.y - bottom) / ed.char_h)
	}
	if m.drag == .Chars {
		switch {
		case m.x < left && ed.scroll_col > 0: dc = -(1 + int((left - m.x) / ed.char_w))
		case m.x >= right: dc = 1 + int((m.x - right) / ed.char_w)
		}
	}
	if dl == 0 && dc == 0 {
		return
	}
	m.last_autoscroll = time.tick_now()
	ed.scroll_line += dl
	ed.scroll_col += dc
	editor_clamp_scroll(ed)
	editor_drag_to(ed, editor_screen_to_position(ed, m.x, m.y))
}
