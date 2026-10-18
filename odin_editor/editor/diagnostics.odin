// Diagnostics (errors/warnings from textDocument/publishDiagnostics):
// conversion of the server's UTF-16 ranges to buffer positions, per-line
// severity for gutter markers, lookup at a position, F8 / Shift+F8
// navigation, and the tooltip state for showing a diagnostic's message on
// mouse hover (after a short dwell) or after keyboard navigation.
// Rendering lives in render_diagnostics.odin.
package editor

import buf "../buffer"
import lspc "../lsp"
import "core:slice"
import "core:time"
import "core:unicode/utf8"

DIAG_HOVER_DELAY :: 350 * time.Millisecond

Diagnostic_Severity :: enum {
	Error       = 1,
	Warning     = 2,
	Information = 3,
	Hint        = 4,
}

// Diag is a diagnostic in buffer coordinates. `end` is exclusive and
// always > `start` on the same line for empty server ranges (widened to
// one character, or the phantom cell past the end of the line).
Diag :: struct {
	start, end: buf.Position,
	severity:   Diagnostic_Severity,
	message:    string, // borrowed from the LSP client
	source:     string,
}

Tip_Source :: enum {
	None,
	Mouse,
	Keyboard,
}

Diagnostic_Tooltip :: struct {
	source:    Tip_Source,
	// Diagnostics covering `pos` (or, when line_only, any on pos.line) are
	// shown; the tip disappears as soon as there are none.
	pos:       buf.Position,
	line_only: bool,

	// Pending mouse hover: shown once the pointer rests on the same cell
	// for DIAG_HOVER_DELAY.
	hover_valid:     bool,
	hover_pos:       buf.Position,
	hover_line_only: bool,
	hover_since:     time.Tick,
}

// editor_diagnostics returns the current document's diagnostics in buffer
// coordinates, sorted by start position (temp-allocated).
editor_diagnostics :: proc(ed: ^Editor) -> []Diag {
	if !ed.lsp_enabled || len(ed.document_key) == 0 {
		return nil
	}
	raw := lspc.client_diagnostics_for_key(&ed.lsp, ed.document_key)
	if len(raw) == 0 {
		return nil
	}
	count := buf.buffer_line_count(&ed.buf)
	out := make([dynamic]Diag, 0, len(raw), context.temp_allocator)
	for d in raw {
		start := to_buffer_pos(ed, d.range.start, count)
		end := to_buffer_pos(ed, d.range.end, count)
		if buf.position_less(end, start) {
			start, end = end, start
		}
		if end == start {
			// Zero-width (e.g. "expected ';'"): cover the next character,
			// or the cell just past the end of the line.
			end.col = start.col + 1
			line := buf.buffer_line_str(&ed.buf, start.line)
			if start.col < len(line) {
				_, size := utf8.decode_rune_in_string(line[start.col:])
				end.col = start.col + size
			}
		}
		append(&out, Diag{start, end, Diagnostic_Severity(clamp(d.severity, 1, 4)), d.message, d.source})
	}
	slice.sort_by(out[:], proc(a, b: Diag) -> bool {
		return buf.position_less(a.start, b.start)
	})
	return out[:]
}

@(private)
to_buffer_pos :: proc(ed: ^Editor, p: lspc.Position, line_count: int) -> buf.Position {
	// Ranges can be stale by a keystroke or two (the server answers the
	// previous version); clamp instead of trusting them.
	line := clamp(p.line, 0, max(line_count - 1, 0))
	return {line, lspc.utf16_col_to_byte(buf.buffer_line_str(&ed.buf, line), p.character)}
}

// editor_diagnostic_counts tallies the current document's diagnostics by
// severity (index with Diagnostic_Severity).
editor_diagnostic_counts :: proc(ed: ^Editor) -> (counts: [Diagnostic_Severity]int) {
	for d in editor_diagnostics(ed) {
		counts[d.severity] += 1
	}
	return
}

// diag_covers_line reports whether `d` touches `line`.
diag_covers_line :: proc(d: Diag, line: int) -> bool {
	return d.start.line <= line && line <= d.end.line
}

// diag_contains reports whether the character at `pos` is inside `d`.
diag_contains :: proc(d: Diag, pos: buf.Position) -> bool {
	return !buf.position_less(pos, d.start) && buf.position_less(pos, d.end)
}

// line_severity returns the most severe diagnostic on `line` (ok=false if
// none).
line_severity :: proc(diags: []Diag, line: int) -> (sev: Diagnostic_Severity, ok: bool) {
	sev = .Hint
	for d in diags {
		if diag_covers_line(d, line) && d.severity <= sev {
			sev, ok = d.severity, true
		}
	}
	return
}

// editor_diagnostics_at returns the diagnostics covering `pos` (or every
// diagnostic on pos.line when `line_only`), most severe first.
editor_diagnostics_at :: proc(ed: ^Editor, pos: buf.Position, line_only := false) -> []Diag {
	hits := make([dynamic]Diag, context.temp_allocator)
	for d in editor_diagnostics(ed) {
		if line_only ? diag_covers_line(d, pos.line) : diag_contains(d, pos) {
			append(&hits, d)
		}
	}
	slice.stable_sort_by(hits[:], proc(a, b: Diag) -> bool {return a.severity < b.severity})
	return hits[:]
}

// editor_goto_diagnostic moves the caret to the next (dir=+1) or previous
// (dir=-1) diagnostic, wrapping around, and shows its message — VSCode's
// F8 / Shift+F8.
editor_goto_diagnostic :: proc(ed: ^Editor, dir: int) -> bool {
	diags := editor_diagnostics(ed)
	if len(diags) == 0 {
		return true
	}
	p := editor_primary_cursor(ed).pos
	target := diags[0] if dir > 0 else diags[len(diags) - 1]
	if dir > 0 {
		for d in diags {
			if buf.position_less(p, d.start) {
				target = d
				break
			}
		}
	} else {
		#reverse for d in diags {
			if buf.position_less(d.start, p) {
				target = d
				break
			}
		}
	}
	resize(&ed.buf.cursors, 1)
	ed.buf.cursors[0] = {pos = target.start}
	editor_close_completion(ed)
	editor_ensure_cursor_visible(ed)
	ed.diag_tip = {source = .Keyboard, pos = target.start}
	return true
}

// editor_diag_tooltip_items returns the diagnostics the tooltip should
// show right now (empty = hidden). Hidden while the completion list is up.
editor_diag_tooltip_items :: proc(ed: ^Editor) -> []Diag {
	tip := &ed.diag_tip
	if tip.source == .None || editor_completion_visible(ed) {
		return nil
	}
	return editor_diagnostics_at(ed, tip.pos, tip.line_only)
}

// editor_track_diag_hover records what the pointer is over (called on
// mouse motion). Resting on the same cell arms the hover tooltip; moving
// to a cell without diagnostics hides a mouse-opened tooltip — unless the
// pointer is over the tooltip itself, so its text can be read.
@(private)
editor_track_diag_hover :: proc(ed: ^Editor, hit: Hit, x, y: f32) {
	tip := &ed.diag_tip
	if layout, ok := editor_diag_tooltip_layout(ed); ok && in_rect(layout.rect, x, y) {
		tip.hover_valid = false
		return
	}
	pos := hit.pos
	line_only := false
	valid := false
	switch hit.zone {
	case .Text:
		if cell, inside := editor_screen_to_cell(ed, x, y); inside {
			pos, valid = cell, true
		}
	case .Gutter:
		line_only, valid = true, true
	case .Outside, .Completion, .Signature:
	}
	if !valid || (tip.hover_valid && (pos != tip.hover_pos || line_only != tip.hover_line_only)) || !tip.hover_valid {
		tip.hover_since = time.tick_now()
	}
	tip.hover_valid = valid
	tip.hover_pos = pos
	tip.hover_line_only = line_only
	if tip.source == .Mouse && (!valid || len(editor_diagnostics_at(ed, pos, line_only)) == 0) {
		tip.source = .None
	}
}

// editor_screen_to_cell maps window pixels to the character cell under
// them (floored, unlike editor_screen_to_position which rounds to the
// nearest caret boundary).
editor_screen_to_cell :: proc(ed: ^Editor, x, y: f32) -> (pos: buf.Position, inside: bool) {
	if ed.char_w <= 0 || ed.char_h <= 0 || y < ed.origin_y {
		return {}, false
	}
	line := ed.scroll_line + int((y - ed.origin_y) / ed.char_h)
	if line >= buf.buffer_line_count(&ed.buf) {
		return {}, false
	}
	vcol := f32(ed.scroll_col) + (x - ed.origin_x - GUTTER_WIDTH) / ed.char_w
	col, ok := byte_col_at_cell(buf.buffer_line_str(&ed.buf, line), vcol, ed.tab_width)
	return {line, col}, ok
}

// editor_update_diagnostics advances the tooltip state each frame.
editor_update_diagnostics :: proc(ed: ^Editor) {
	tip := &ed.diag_tip
	switch tip.source {
	case .Keyboard:
		// A keyboard-opened tip stays until the caret moves away.
		if editor_primary_cursor(ed).pos != tip.pos {
			tip.source = .None
		}
	case .Mouse, .None:
		if tip.hover_valid && ed.mouse.drag == .None &&
		   time.tick_since(tip.hover_since) >= DIAG_HOVER_DELAY &&
		   len(editor_diagnostics_at(ed, tip.hover_pos, tip.hover_line_only)) > 0 {
			tip.source = .Mouse
			tip.pos = tip.hover_pos
			tip.line_only = tip.hover_line_only
		}
	}
}
