// Rendering for the LSP popups: the completion list (below the cursor) and
// the signature-help tooltip (above the cursor). Layout is computed by
// `editor_popup_layout`, which is pure math over editor state so it can be
// unit tested and reported by automation hooks without a renderer.
package editor

import buf "../buffer"
import "core:unicode/utf8"
import sdl "vendor:sdl3"
import ttf "vendor:sdl3/ttf"

POPUP_PAD :: 4
COMPLETION_KIND_COLS :: 6
COMPLETION_MIN_COLS :: 24
COMPLETION_MAX_COLS :: 72
COMPLETION_DETAIL_MAX_COLS :: 40

Popup_Layout :: struct {
	completion:         sdl.FRect,
	completion_visible: bool,
	signature:          sdl.FRect,
	signature_visible:  bool,
}

// completion_kind_tag returns a short label for an LSP CompletionItemKind.
completion_kind_tag :: proc(kind: int) -> string {
	switch kind {
	case 2, 3, 4: return "fn"
	case 5, 10:   return "field"
	case 6:       return "var"
	case 7, 8, 22, 25: return "type"
	case 9:       return "pkg"
	case 13:      return "enum"
	case 14:      return "kw"
	case 15:      return "snip"
	case 20:      return "case"
	case 21:      return "const"
	}
	return "  "
}

@(private)
text_cols :: proc(s: string) -> int {
	return utf8.rune_count_in_string(s)
}

// editor_cursor_screen_pos returns the top-left pixel of the primary
// cursor's cell, using the origin recorded by the last editor_render.
editor_cursor_screen_pos :: proc(ed: ^Editor) -> (x, y: f32) {
	return editor_position_to_screen(ed, editor_primary_cursor(ed).pos)
}

// editor_position_to_screen returns the top-left pixel of the cell at a
// buffer position (the caret's x for that position), using the origin
// recorded by the last editor_render.
editor_position_to_screen :: proc(ed: ^Editor, pos: buf.Position) -> (x, y: f32) {
	x = ed.origin_x + editor_gutter_width(ed) + f32(editor_visual_col(ed, pos) - ed.scroll_col) * ed.char_w
	y = ed.origin_y + f32(pos.line - ed.scroll_line) * ed.char_h
	return
}

@(private)
completion_popup_cols :: proc(ed: ^Editor) -> int {
	label_cols, detail_cols := 0, 0
	for idx in ed.completion.filtered {
		item := ed.lsp.last_completion[idx]
		label_cols = max(label_cols, text_cols(item.label))
		detail_cols = max(detail_cols, text_cols(item.detail))
	}
	detail_cols = min(detail_cols, COMPLETION_DETAIL_MAX_COLS)
	cols := COMPLETION_KIND_COLS + label_cols + (detail_cols > 0 ? 2 + detail_cols : 0)
	return clamp(cols, COMPLETION_MIN_COLS, COMPLETION_MAX_COLS)
}

// editor_popup_layout positions the popups relative to the primary
// cursor. The signature tooltip prefers the line above the cursor and the
// completion list prefers the space below; each flips to the other side
// when it would run off the editor's visible area.
editor_popup_layout :: proc(ed: ^Editor) -> (layout: Popup_Layout) {
	if !editor_completion_visible(ed) && !editor_signature_visible(ed) {
		return
	}
	cx, cy := editor_cursor_screen_pos(ed)
	view_top := ed.origin_y
	view_bottom := ed.origin_y + f32(editor_text_rows(ed)) * ed.char_h
	view_right := ed.origin_x + editor_gutter_width(ed) + f32(ed.visible_cols) * ed.char_w

	below_y := cy + ed.char_h + 2

	if editor_signature_visible(ed) {
		label, _, _, _ := editor_signature_active_parts(ed)
		w := f32(text_cols(label)) * ed.char_w + 2 * POPUP_PAD
		h := ed.char_h + 2 * POPUP_PAD
		y := cy - h - 2
		if y < view_top {
			y = below_y
			below_y += h + 2
		}
		x := min(cx, max(ed.origin_x + editor_gutter_width(ed), view_right - w))
		layout.signature = {x, y, w, h}
		layout.signature_visible = true
	}

	if editor_completion_visible(ed) {
		rows := min(len(ed.completion.filtered), COMPLETION_MAX_VISIBLE)
		w := f32(completion_popup_cols(ed)) * ed.char_w + 2 * POPUP_PAD
		h := f32(rows) * ed.char_h + 2 * POPUP_PAD
		y := below_y
		if y + h > view_bottom && cy - h - 2 >= view_top {
			y = cy - h - 2
			// Don't cover the signature tooltip if it's also above.
			if layout.signature_visible && layout.signature.y < cy {
				y = layout.signature.y - h - 2
			}
		}
		// Align the list's label column under the start of the word.
		ax, _ := editor_position_to_screen(ed, ed.completion.anchor)
		x := ax - f32(COMPLETION_KIND_COLS) * ed.char_w - POPUP_PAD
		x = clamp(x, ed.origin_x + editor_gutter_width(ed), max(ed.origin_x + editor_gutter_width(ed), view_right - w))
		layout.completion = {x, y, w, h}
		layout.completion_visible = true
	}
	return
}

@(private)
render_popups :: proc(ed: ^Editor, renderer: ^sdl.Renderer, font: ^ttf.Font, theme: Theme, origin_x, origin_y: f32) {
	if font == nil {
		return
	}
	layout := editor_popup_layout(ed)
	if layout.signature_visible {
		render_signature_popup(ed, renderer, font, theme, layout.signature)
	}
	if layout.completion_visible {
		render_completion_popup(ed, renderer, font, theme, layout.completion)
	}
}

@(private)
fill_rect :: proc(renderer: ^sdl.Renderer, rect: sdl.FRect, color: sdl.Color) {
	r := rect
	sdl.SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a)
	sdl.RenderFillRect(renderer, &r)
}

@(private)
draw_popup_box :: proc(renderer: ^sdl.Renderer, rect: sdl.FRect, theme: Theme) {
	fill_rect(renderer, rect, theme.popup_bg)
	r := rect
	sdl.SetRenderDrawColor(renderer, theme.popup_border.r, theme.popup_border.g, theme.popup_border.b, theme.popup_border.a)
	sdl.RenderRect(renderer, &r)
}

// truncate_cols cuts `s` to at most `cols` runes, ending in "…" if cut.
@(private)
truncate_cols :: proc(s: string, cols: int) -> string {
	if cols <= 0 {
		return ""
	}
	if text_cols(s) <= cols {
		return s
	}
	n := 0
	for _, i in s {
		if n == cols - 1 {
			return concat_ellipsis(s[:i])
		}
		n += 1
	}
	return s
}

@(private)
concat_ellipsis :: proc(s: string) -> string {
	out := make([]u8, len(s) + 3, context.temp_allocator)
	copy(out, s)
	copy(out[len(s):], "…")
	return string(out)
}

@(private)
render_completion_popup :: proc(ed: ^Editor, renderer: ^sdl.Renderer, font: ^ttf.Font, theme: Theme, rect: sdl.FRect) {
	draw_popup_box(renderer, rect, theme)
	cs := &ed.completion
	prefix, _ := editor_completion_prefix(ed)
	total_cols := int((rect.w - 2 * POPUP_PAD) / ed.char_w)

	last := min(cs.scroll + COMPLETION_MAX_VISIBLE, len(cs.filtered))
	for row in cs.scroll ..< last {
		item := ed.lsp.last_completion[cs.filtered[row]]
		y := rect.y + POPUP_PAD + f32(row - cs.scroll) * ed.char_h
		x := rect.x + POPUP_PAD

		if row == cs.selected {
			fill_rect(renderer, {rect.x + 1, y, rect.w - 2, ed.char_h}, theme.popup_selected)
		}

		draw_text(renderer, font, completion_kind_tag(item.kind), x, y, theme.text_type, ed.char_h)
		x += f32(COMPLETION_KIND_COLS) * ed.char_w

		label_cols := min(text_cols(item.label), total_cols - COMPLETION_KIND_COLS)
		label := truncate_cols(item.label, label_cols)
		// Highlight the typed prefix when it matches the label's start.
		match_len := 0
		if completion_match(label, prefix) == 2 && len(prefix) <= len(label) {
			match_len = len(prefix)
		}
		draw_text(renderer, font, label[:match_len], x, y, theme.popup_match, ed.char_h)
		draw_text(renderer, font, label[match_len:], x + f32(text_cols(label[:match_len])) * ed.char_w, y, theme.popup_text, ed.char_h)

		detail_cols := total_cols - COMPLETION_KIND_COLS - label_cols - 2
		if len(item.detail) > 0 && detail_cols > 3 {
			detail := truncate_cols(item.detail, min(detail_cols, COMPLETION_DETAIL_MAX_COLS))
			dx := rect.x + rect.w - POPUP_PAD - f32(text_cols(detail)) * ed.char_w
			draw_text(renderer, font, detail, dx, y, theme.popup_text_dim, ed.char_h)
		}
	}

	// Scroll indicator when the list is longer than the popup.
	if len(cs.filtered) > COMPLETION_MAX_VISIBLE {
		track_h := rect.h - 2
		thumb_h := max(track_h * f32(COMPLETION_MAX_VISIBLE) / f32(len(cs.filtered)), 6)
		thumb_y := rect.y + 1 + (track_h - thumb_h) * f32(cs.scroll) / f32(len(cs.filtered) - COMPLETION_MAX_VISIBLE)
		fill_rect(renderer, {rect.x + rect.w - 4, thumb_y, 3, thumb_h}, theme.popup_border)
	}
}

@(private)
render_signature_popup :: proc(ed: ^Editor, renderer: ^sdl.Renderer, font: ^ttf.Font, theme: Theme, rect: sdl.FRect) {
	draw_popup_box(renderer, rect, theme)
	_, before, active, after := editor_signature_active_parts(ed)
	x := rect.x + POPUP_PAD
	y := rect.y + POPUP_PAD
	draw_text(renderer, font, before, x, y, theme.popup_text, ed.char_h)
	x += f32(text_cols(before)) * ed.char_w
	draw_text(renderer, font, active, x, y, theme.popup_active_param, ed.char_h)
	if len(active) > 0 {
		// Underline the active parameter so it reads even without color.
		fill_rect(renderer, {x, y + ed.char_h - 2, f32(text_cols(active)) * ed.char_w, 1}, theme.popup_active_param)
	}
	x += f32(text_cols(active)) * ed.char_w
	draw_text(renderer, font, after, x, y, theme.popup_text, ed.char_h)
}
