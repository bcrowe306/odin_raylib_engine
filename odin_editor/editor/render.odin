// SDL3 rendering: draws the gutter, current-line highlight, syntax
// highlighted text, selections, and cursors for the visible viewport. Not
// unit tested (requires a real renderer/window); exercised manually via
// the `example` demo app.
package editor

import buf "../buffer"
import syn "../syntax"
import "core:fmt"
import "core:strings"
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

GUTTER_WIDTH :: 56

editor_render :: proc(ed: ^Editor, renderer: ^sdl.Renderer, font: ^ttf.Font, theme: Theme, origin_x, origin_y: f32) {
	ed.origin_x = origin_x
	ed.origin_y = origin_y
	sdl.SetRenderDrawColor(renderer, theme.background.r, theme.background.g, theme.background.b, theme.background.a)
	sdl.RenderFillRect(renderer, nil)

	gutter_rect := sdl.FRect{origin_x, origin_y, GUTTER_WIDTH, ed.char_h * f32(ed.visible_rows)}
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
		i32(origin_x + GUTTER_WIDTH), i32(origin_y),
		i32(ed.char_w * f32(ed.visible_cols) + 1), i32(ed.char_h * f32(ed.visible_rows)),
	}
	if had_clip {
		_ = sdl.GetRectIntersection(prev_clip, text_clip, &text_clip)
	}

	for row := 0; row < ed.visible_rows; row += 1 {
		ln := ed.scroll_line + row
		if ln >= line_count {
			break
		}
		y := origin_y + f32(row) * ed.char_h

		if ln == primary.pos.line {
			hl_rect := sdl.FRect{origin_x + GUTTER_WIDTH, y, ed.char_w * f32(ed.visible_cols), ed.char_h}
			sdl.SetRenderDrawColor(renderer, theme.current_line.r, theme.current_line.g, theme.current_line.b, theme.current_line.a)
			sdl.RenderFillRect(renderer, &hl_rect)
		}

		render_line_number(renderer, font, ln + 1, origin_x, y, theme)

		line := buf.buffer_line_str(&ed.buf, ln)
		tokens, next_state := ed.language.tokenize(line, state, context.temp_allocator)
		sdl.SetRenderClipRect(renderer, &text_clip)
		render_selection(ed, renderer, ln, origin_x + GUTTER_WIDTH, y, theme)
		render_line_tokens(ed, renderer, font, line, tokens, origin_x + GUTTER_WIDTH, y, theme)
		render_cursors_on_line(ed, renderer, ln, origin_x + GUTTER_WIDTH, y, theme)
		sdl.SetRenderClipRect(renderer, &prev_clip if had_clip else nil)
		delete(tokens, context.temp_allocator)
		state = next_state
	}

	// Popups draw last so they sit on top of the text.
	render_popups(ed, renderer, font, theme, origin_x, origin_y)
}

@(private)
render_line_number :: proc(renderer: ^sdl.Renderer, font: ^ttf.Font, number: int, x, y: f32, theme: Theme) {
	if font == nil {
		return
	}
	text := fmt.tprintf("%4d", number)
	draw_text(renderer, font, text, x, y, theme.gutter_text)
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
		run_start := tok.start
		for i := tok.start; i <= tok.end; i += 1 {
			if i < tok.end && line[i] != '\t' {
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
					draw_text(renderer, font, line[run_start:i], x + f32(vcol - ed.scroll_col) * ed.char_w, y, token_color(theme, tok.kind))
				}
			}
			run_start = i + 1
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
		rect := sdl.FRect{
			x + f32(editor_visual_col(ed, c.pos) - ed.scroll_col) * ed.char_w,
			y,
			2,
			ed.char_h,
		}
		sdl.SetRenderDrawColor(renderer, theme.cursor.r, theme.cursor.g, theme.cursor.b, theme.cursor.a)
		sdl.RenderFillRect(renderer, &rect)
	}
}

@(private)
draw_text :: proc(renderer: ^sdl.Renderer, font: ^ttf.Font, text: string, x, y: f32, color: sdl.Color) {
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
	dst := sdl.FRect{x, y, f32(surface.w), f32(surface.h)}
	sdl.RenderTexture(renderer, texture, nil, &dst)
}
