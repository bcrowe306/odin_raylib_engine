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
		render_selection(ed, renderer, ln, origin_x + GUTTER_WIDTH, y, theme)
		render_line_tokens(renderer, font, line, tokens, ed.scroll_col, origin_x + GUTTER_WIDTH, y, ed.char_w, theme)
		render_cursors_on_line(ed, renderer, ln, origin_x + GUTTER_WIDTH, y, theme)
		delete(tokens, context.temp_allocator)
		state = next_state
	}
}

@(private)
render_line_number :: proc(renderer: ^sdl.Renderer, font: ^ttf.Font, number: int, x, y: f32, theme: Theme) {
	if font == nil {
		return
	}
	text := fmt.tprintf("%4d", number)
	draw_text(renderer, font, text, x, y, theme.gutter_text)
}

@(private)
render_line_tokens :: proc(renderer: ^sdl.Renderer, font: ^ttf.Font, line: string, tokens: []syn.Token, scroll_col: int, x, y, char_w: f32, theme: Theme) {
	if font == nil {
		return
	}
	for tok in tokens {
		start := max(tok.start, scroll_col)
		if start >= tok.end {
			continue
		}
		segment := line[start:tok.end]
		if len(segment) == 0 {
			continue
		}
		col_offset := f32(start - scroll_col)
		draw_text(renderer, font, segment, x + col_offset * char_w, y, token_color(theme, tok.kind))
	}
}

@(private)
render_selection :: proc(ed: ^Editor, renderer: ^sdl.Renderer, line: int, x, y: f32, theme: Theme) {
	for c in ed.buf.cursors {
		start, end, ok := buf.selection_range(c)
		if !ok || line < start.line || line > end.line {
			continue
		}
		col_start := line == start.line ? start.col : 0
		col_end := line == end.line ? end.col : buf.buffer_line_len(&ed.buf, line)
		if col_end <= col_start {
			continue
		}
		rect := sdl.FRect{
			x + f32(col_start - ed.scroll_col) * ed.char_w,
			y,
			f32(col_end - col_start) * ed.char_w,
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
			x + f32(c.pos.col - ed.scroll_col) * ed.char_w,
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
