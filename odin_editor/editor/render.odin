// SDL3 rendering: draws the gutter, current-line highlight, syntax
// highlighted text, selections, and cursors for the visible viewport. Not
// unit tested (requires a real renderer/window); exercised manually via
// the `example` demo app.
package editor

import buf "../buffer"
import syn "../syntax"
import "core:fmt"
import "core:strings"
import "core:unicode/utf8"
import sdl "vendor:sdl3"
import ttf "vendor:sdl3/ttf"

Theme :: struct {
	background:     sdl.Color,
	gutter_bg:      sdl.Color,
	current_line:   sdl.Color,
	selection:      sdl.Color,
	cursor:         sdl.Color,
	text_default:   sdl.Color,
	text_keyword:   sdl.Color,
	text_string:    sdl.Color,
	text_number:    sdl.Color,
	text_comment:   sdl.Color,
	text_type:      sdl.Color,
	text_builtin:   sdl.Color,
	gutter_text:    sdl.Color,

	// Completion / signature-help popups.
	popup_bg:           sdl.Color,
	popup_border:       sdl.Color,
	popup_selected:     sdl.Color,
	popup_text:         sdl.Color,
	popup_text_dim:     sdl.Color,
	popup_match:        sdl.Color,
	popup_active_param: sdl.Color,

	// File-name header.
	header_bg:   sdl.Color,
	header_text: sdl.Color,

	// Diagnostics (squiggles, gutter markers, tooltip labels).
	diag_error:   sdl.Color,
	diag_warning: sdl.Color,
	diag_info:    sdl.Color,
	diag_hint:    sdl.Color,

	// Find highlights.
	find_match:   sdl.Color,
	find_current: sdl.Color,
}

default_theme :: proc() -> Theme {
	return Theme{
		background   = {30, 30, 30, 255},
		gutter_bg    = {24, 24, 24, 255},
		current_line = {45, 45, 45, 255},
		selection    = {60, 90, 130, 140},
		cursor       = {255, 255, 255, 255},
		text_default = {212, 212, 212, 255},
		text_keyword = {197, 134, 192, 255},
		text_string  = {206, 145, 120, 255},
		text_number  = {181, 206, 168, 255},
		text_comment = {106, 153, 85, 255},
		text_type    = {78, 201, 176, 255},
		text_builtin = {220, 220, 170, 255},
		gutter_text  = {133, 133, 133, 255},

		popup_bg           = {37, 37, 38, 255},
		popup_border       = {69, 69, 69, 255},
		popup_selected     = {4, 57, 94, 255},
		popup_text         = {204, 204, 204, 255},
		popup_text_dim     = {140, 140, 140, 255},
		popup_match        = {24, 163, 255, 255},
		popup_active_param = {255, 215, 0, 255},

		header_bg   = {37, 37, 38, 255},
		header_text = {230, 230, 230, 255},

		diag_error   = {244, 71, 71, 255},
		diag_warning = {205, 173, 0, 255},
		diag_info    = {55, 148, 255, 255},
		diag_hint    = {150, 150, 150, 255},

		find_match   = {234, 92, 0, 70},
		find_current = {81, 92, 106, 210},
	}
}

@(private)
token_color :: proc(theme: Theme, kind: syn.TokenKind) -> sdl.Color {
	switch kind {
	case .Keyword: return theme.text_keyword
	case .String: return theme.text_string
	case .Number: return theme.text_number
	case .Comment: return theme.text_comment
	case .Type: return theme.text_type
	case .Builtin: return theme.text_builtin
	case .Identifier, .Operator, .Punctuation, .Default: return theme.text_default
	}
	return theme.text_default
}

MIN_GUTTER_WIDTH :: 56

editor_render :: proc(ed: ^Editor, renderer: ^sdl.Renderer, font: ^ttf.Font, theme: Theme, x, y: f32) {
	// Translucent overlays (selection, faded "unnecessary" code) blend.
	sdl.SetRenderDrawBlendMode(renderer, sdl.BLENDMODE_BLEND)
	sdl.SetRenderDrawColor(renderer, theme.background.r, theme.background.g, theme.background.b, theme.background.a)
	sdl.RenderFillRect(renderer, nil)

	// The header (file name) sits on top; everything else — and every
	// coordinate stored for hit-testing — is relative to the text area
	// below it.
	render_header(ed, renderer, font, theme, x, y)
	origin_x := x
	origin_y := y + editor_header_height(ed)
	ed.origin_x = origin_x
	ed.origin_y = origin_y

	gutter_rect := sdl.FRect{origin_x, origin_y, editor_gutter_width(ed), ed.char_h * f32(editor_text_rows(ed))}
	sdl.SetRenderDrawColor(renderer, theme.gutter_bg.r, theme.gutter_bg.g, theme.gutter_bg.b, theme.gutter_bg.a)
	sdl.RenderFillRect(renderer, &gutter_rect)

	primary := editor_primary_cursor(ed)
	line_count := buf.buffer_line_count(&ed.buf)
	state := syn.LINE_STATE_NORMAL

	// Re-derive tokenizer state up to scroll_line so mid-document block
	// comments still highlight correctly after scrolling.
	for ln := 0; ln < ed.scroll_line && ln < line_count; ln += 1 {
		line := buf.buffer_line_str(&ed.buf, ln)
		tokens, next_state := ed.language.tokenize(line, state, context.temp_allocator)
		delete(tokens, context.temp_allocator)
		state = next_state
	}

	// Clip text to the text area so horizontally scrolled lines never
	// spill into the gutter; restore the host's clip state afterwards.
	prev_clip: sdl.Rect
	had_clip := sdl.RenderClipEnabled(renderer)
	if had_clip {
		sdl.GetRenderClipRect(renderer, &prev_clip)
	}
	text_clip := sdl.Rect{
		i32(origin_x + editor_gutter_width(ed)), i32(origin_y),
		i32(ed.char_w * f32(ed.visible_cols) + 1), i32(ed.char_h * f32(editor_text_rows(ed))),
	}
	if had_clip {
		_ = sdl.GetRectIntersection(prev_clip, text_clip, &text_clip)
	}

	diags := editor_diagnostics(ed)

	for row := 0; row < editor_text_rows(ed); row += 1 {
		ln := ed.scroll_line + row
		if ln >= line_count {
			break
		}
		y := origin_y + f32(row) * ed.char_h

		if ln == primary.pos.line {
			hl_rect := sdl.FRect{origin_x + editor_gutter_width(ed), y, ed.char_w * f32(ed.visible_cols), ed.char_h}
			sdl.SetRenderDrawColor(renderer, theme.current_line.r, theme.current_line.g, theme.current_line.b, theme.current_line.a)
			sdl.RenderFillRect(renderer, &hl_rect)
		}

		render_line_number(ed, renderer, font, ln + 1, ln == primary.pos.line, origin_x, y, theme)
		render_gutter_marker(ed, renderer, diags, ln, origin_x, y, theme)

		line := buf.buffer_line_str(&ed.buf, ln)
		tokens, next_state := ed.language.tokenize(line, state, context.temp_allocator)
		sdl.SetRenderClipRect(renderer, &text_clip)
		render_find_highlights(ed, renderer, ln, origin_x + editor_gutter_width(ed), y, theme)
		render_selection(ed, renderer, ln, origin_x + editor_gutter_width(ed), y, theme)
		render_line_tokens(ed, renderer, font, line, tokens, origin_x + editor_gutter_width(ed), y, theme)
		render_squiggles(ed, renderer, diags, ln, origin_x + editor_gutter_width(ed), y, theme)
		render_cursors_on_line(ed, renderer, ln, origin_x + editor_gutter_width(ed), y, theme)
		sdl.SetRenderClipRect(renderer, &prev_clip if had_clip else nil)
		delete(tokens, context.temp_allocator)
		state = next_state
	}

	// Popups draw last so they sit on top of the text.
	render_problems_panel(ed, renderer, font, theme, origin_x, origin_y)
	render_find_bar(ed, renderer, font, theme)
	render_drop_caret(ed, renderer, theme)
	render_popups(ed, renderer, font, theme, origin_x, origin_y)
	render_diag_tooltip(ed, renderer, font, theme)
	render_code_actions(ed, renderer, font, theme)
	render_hover(ed, renderer, font, theme)
	render_context_menu(ed, renderer, font, theme)
}

@(private)
// render_line_number draws a line number right-aligned against the
// gutter's diagnostic-marker column; the caret's line is brighter.
render_line_number :: proc(ed: ^Editor, renderer: ^sdl.Renderer, font: ^ttf.Font, number: int, current: bool, x, y: f32, theme: Theme) {
	if font == nil {
		return
	}
	text := fmt.tprint(number)
	right := x + editor_gutter_width(ed) - GUTTER_MARKER_SPACE
	color := theme.text_default if current else theme.gutter_text
	draw_text(renderer, font, text, right - f32(len(text)) * ed.char_w, y, color, ed.char_h)
}

// render_header draws the file-name strip at the top of the editor: the
// base name, its directory (dimmed), and a marker when there are unsaved
// changes.
render_header :: proc(ed: ^Editor, renderer: ^sdl.Renderer, font: ^ttf.Font, theme: Theme, x, y: f32) {
	h := editor_header_height(ed)
	if h <= 0 {
		return
	}
	w := editor_gutter_width(ed) + f32(ed.visible_cols) * ed.char_w
	fill_rect(renderer, {x, y, w, h}, theme.header_bg)
	fill_rect(renderer, {x, y + h - 1, w, 1}, theme.popup_border)
	if font == nil {
		return
	}
	name, dir := editor_display_name(ed)
	tx := x + 12
	draw_text(renderer, font, name, tx, y, theme.header_text, h)
	tx += f32(text_cols(name)) * ed.char_w
	if ed.buf.dirty {
		// U+25CF if the font has it, like VSCode's tab dot.
		marker := " ●" if ttf.FontHasGlyph(font, 0x25CF) else " *"
		draw_text(renderer, font, marker, tx, y, theme.header_text, h)
		tx += 2 * ed.char_w
	}
	if len(dir) > 0 {
		room := int((x + w - tx) / ed.char_w) - 3
		draw_text(renderer, font, truncate_cols(dir, room), tx + 2 * ed.char_w, y, theme.popup_text_dim, h)
	}
}

// render_line_tokens draws each token at its visual column. Tokens are
// split at tab characters, which are skipped (they only advance to the
// next tab stop), so tab-indented code lines up with the caret.
@(private)
render_line_tokens :: proc(ed: ^Editor, renderer: ^sdl.Renderer, font: ^ttf.Font, line: string, tokens: []syn.Token, x, y: f32, theme: Theme) {
	if font == nil {
		return
	}
	last_visible := ed.scroll_col + ed.visible_cols
	for tok in tokens {
		color := token_color(theme, tok.kind)
		run_start := tok.start
		i := tok.start
		for i <= tok.end {
			// ASCII runs are drawn as one surface; tabs only advance; any
			// other rune is drawn on its own, centred in its cell(s), so
			// glyphs from fallback fonts (emoji, CJK, symbols) — whose
			// advance needn't match the grid — can't shift later text.
			special := i < tok.end && (line[i] == '\t' || line[i] >= 0x80)
			if i < tok.end && !special {
				i += 1
				continue
			}
			if i > run_start {
				vcol := visual_col_of(line, run_start, ed.tab_width)
				if vcol > last_visible {
					return
				}
				// Runs starting left of the viewport still draw; the
				// clip rect trims the part over the gutter.
				if vcol + (i - run_start) >= ed.scroll_col {
					draw_text(renderer, font, line[run_start:i], x + f32(vcol - ed.scroll_col) * ed.char_w, y, color, ed.char_h)
				}
			}
			if i == tok.end {
				break
			}
			r, size := utf8.decode_rune_in_string(line[i:])
			if r != '\t' {
				if cells := rune_cells(r); cells > 0 {
					vcol := visual_col_of(line, i, ed.tab_width)
					if vcol > last_visible {
						return
					}
					draw_glyph_centered(renderer, font, line[i:i + size], x + f32(vcol - ed.scroll_col) * ed.char_w, y, f32(cells) * ed.char_w, ed.char_h, color)
				}
			}
			i += size
			run_start = i
		}
	}
}

@(private)
render_selection :: proc(ed: ^Editor, renderer: ^sdl.Renderer, line: int, x, y: f32, theme: Theme) {
	text := buf.buffer_line_str(&ed.buf, line)
	for c in ed.buf.cursors {
		start, end, ok := buf.selection_range(c)
		if !ok || line < start.line || line > end.line {
			continue
		}
		col_start := line == start.line ? start.col : 0
		col_end := line == end.line ? end.col : len(text)
		v_start := visual_col_of(text, col_start, ed.tab_width)
		v_end := visual_col_of(text, col_end, ed.tab_width)
		// A selection that continues onto the next line shows one extra
		// cell for the newline, like VSCode.
		if line != end.line {
			v_end += 1
		}
		if v_end <= v_start {
			continue
		}
		rect := sdl.FRect{
			x + f32(v_start - ed.scroll_col) * ed.char_w,
			y,
			f32(v_end - v_start) * ed.char_w,
			ed.char_h,
		}
		sdl.SetRenderDrawColor(renderer, theme.selection.r, theme.selection.g, theme.selection.b, theme.selection.a)
		sdl.RenderFillRect(renderer, &rect)
	}
}

@(private)
render_cursors_on_line :: proc(ed: ^Editor, renderer: ^sdl.Renderer, line: int, x, y: f32, theme: Theme) {
	for c in ed.buf.cursors {
		if c.pos.line != line {
			continue
		}
		// The caret spans the glyph height (plus a little), centred in the
		// row, rather than the full spaced-out row.
		ch := min(ed.char_h, editor_glyph_height(ed) + 4)
		rect := sdl.FRect{
			x + f32(editor_visual_col(ed, c.pos) - ed.scroll_col) * ed.char_w,
			y + f32(int((ed.char_h - ch) / 2)),
			2,
			ch,
		}
		sdl.SetRenderDrawColor(renderer, theme.cursor.r, theme.cursor.g, theme.cursor.b, theme.cursor.a)
		sdl.RenderFillRect(renderer, &rect)
	}
}

// draw_glyph_centered draws one character centred in a box of cell_w x
// row_h (scaled down if a fallback font's glyph is wider than the box).
@(private)
draw_glyph_centered :: proc(renderer: ^sdl.Renderer, font: ^ttf.Font, text: string, x, y, cell_w, row_h: f32, color: sdl.Color) {
	cstr := strings.clone_to_cstring(text, context.temp_allocator)
	surface := ttf.RenderText_Blended(font, cstr, len(text), color)
	if surface == nil {
		return
	}
	defer sdl.DestroySurface(surface)
	texture := sdl.CreateTextureFromSurface(renderer, surface)
	if texture == nil {
		return
	}
	defer sdl.DestroyTexture(texture)
	w, h := f32(surface.w), f32(surface.h)
	if w > cell_w + 1 || h > row_h {
		k := min(cell_w / w, row_h / h)
		w, h = w * k, h * k
	}
	dst := sdl.FRect{x + f32(int((cell_w - w) / 2)), y + f32(int((row_h - h) / 2)), w, h}
	sdl.RenderTexture(renderer, texture, nil, &dst)
}

@(private)
// draw_text renders `text` at (x, y). With `row_h` > 0 the text is
// centred vertically in a row of that height (rows are taller than the
// glyphs when line spacing is > 1).
draw_text :: proc(renderer: ^sdl.Renderer, font: ^ttf.Font, text: string, x, y: f32, color: sdl.Color, row_h: f32 = 0) {
	if len(text) == 0 {
		return
	}
	cstr := strings.clone_to_cstring(text, context.temp_allocator)
	surface := ttf.RenderText_Blended(font, cstr, len(text), color)
	if surface == nil {
		return
	}
	defer sdl.DestroySurface(surface)
	texture := sdl.CreateTextureFromSurface(renderer, surface)
	if texture == nil {
		return
	}
	defer sdl.DestroyTexture(texture)
	top := y
	if row_h > 0 {
		top = y + f32(int((row_h - f32(surface.h)) / 2))
	}
	dst := sdl.FRect{x, top, f32(surface.w), f32(surface.h)}
	sdl.RenderTexture(renderer, texture, nil, &dst)
}
