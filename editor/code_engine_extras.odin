package editor

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import buf "../odin_editor/buffer"
import imgui "lib/imgui"

// ============================================================================
// Engine-aware extras in the Code tab:
//
//   texture hover   a string naming an image of the project shows it
//                   (thumbnail, size) when hovered
// ============================================================================

TEXTURE_HOVER_EXTS :: []string{".png", ".jpg", ".jpeg", ".bmp", ".tga", ".gif", ".qoi"}

// code_texture_hover: the mouse rests on an image path string: its preview
// (true when shown).
code_texture_hover :: proc(doc: ^Code_Doc, p: buf.Position) -> bool {
	state := code_state()
	b := &doc.buffer
	line := buf.buffer_line_str(b, p.line)
	open := -1
	for i := min(p.col, len(line)) - 1; i >= 0; i -= 1 do if line[i] == '"' || line[i] == '\'' {open = i; break}
	if open < 0 do return false
	close := strings.index_byte(line[open + 1:], line[open])
	if close < 0 || open + 1 + close < p.col do return false
	lit := line[open + 1:open + 1 + close]
	lower := strings.to_lower(lit, context.temp_allocator)
	isImage := false
	for ext in TEXTURE_HOVER_EXTS do if strings.has_suffix(lower, ext) do isImage = true
	if !isImage do return false
	full, _ := filepath.join({state.projectPath, lit}, context.temp_allocator)
	if !os.exists(full) do return false
	tex := Asset_Thumbnail(full)
	imgui.BeginTooltip()
	defer imgui.EndTooltip()
	imgui.TextColored(UI_ACCENT, "%s", fmt.ctprintf("%s  %s", ICON_FA_FILE_IMAGE, lit))
	Drive_Item("code.texture-hover")
	if tex == nil {
		UI_DimText("loading...")
		return true
	}
	// Fit in 256 px, never upscaled more than 4x (pixel art stays crisp enough).
	w, h := f32(tex.width), f32(tex.height)
	s := min(256 / max(w, h), 4)
	imgui.Image(transmute(imgui.TextureID)tex, {w * s, h * s})
	UI_DimText(fmt.tprintf("%d x %d (thumbnail)", tex.width, tex.height))
	return true
}

// --- colour swatches -----------------------------------------------------------------

// code_color_swatches finds colour tables on a line: {r, g, b[, a]} with
// 3-4 numbers that are 0..1 floats, or 0..255 after a key saying colour.
code_color_swatches :: proc(out: ^[dynamic]Code_Inlay, text: string, skip: []bool) {
	for i := 0; i < len(text); i += 1 {
		if text[i] != '{' || skip[i] do continue
		close := strings.index_byte(text[i:], '}')
		if close < 0 do continue
		inner := text[i + 1:i + close]
		parts := strings.split(inner, ",", context.temp_allocator)
		if len(parts) < 3 || len(parts) > 4 do continue
		vals: [4]f32 = {1, 1, 1, 1}
		ok, anyDot, max255 := true, false, false
		for p, k in parts {
			v := strings.trim_space(p)
			f, parsed := strconv_f32(v)
			if !parsed || f < 0 {ok = false; break}
			if strings.contains(v, ".") do anyDot = true
			if f > 1 do max255 = true
			vals[k] = f
		}
		if !ok do continue
		key := strings.to_lower(strings.trim_space(text[:i]), context.temp_allocator)
		colourish := strings.contains(key, "color") || strings.contains(key, "colour") || strings.contains(key, "tint") || strings.contains(key, "rgb")
		switch {
		case max255:
			if !colourish do continue
			for k in 0 ..< len(parts) {
				if vals[k] > 255 {ok = false}
				vals[k] /= 255
			}
		case !anyDot && !colourish:
			continue // {1, 0, 0}: could be anything
		}
		if !ok do continue
		append(out, Code_Inlay{col = i, label = "", swatch = true, color = vals, to = i + close + 1})
		i += close
	}
}

@(private = "file")
strconv_f32 :: proc(s: string) -> (f32, bool) {
	if s == "" do return 0, false
	v: f64 = 0
	frac: f64 = 0
	scale: f64 = 1
	dot := false
	for ch in transmute([]u8)s {
		switch {
		case ch >= '0' && ch <= '9':
			if dot {scale /= 10; frac += f64(ch - '0') * scale}
			else do v = v * 10 + f64(ch - '0')
		case ch == '.' && !dot: dot = true
		case: return 0, false
		}
	}
	return f32(v + frac), true
}

@(private = "file")
swatch_edit: struct {
	open:   bool,
	doc:    ^Code_Doc,
	line:   int,
	from:   int,
	color:  [4]f32,
	count:  int,  // 3 or 4 numbers
	ints:   bool, // written as 0..255
}

// code_draw_swatch draws a swatch at column v (a click opens the picker).
code_draw_swatch :: proc(dl: ^imgui.DrawList, x0, y: f32, v: int, h: Code_Inlay, doc: ^Code_Doc, line: int) -> int {
	cm := &GlobalCode
	x := x0 + f32(v) * cm.charW + 1
	sz := code_font_size() - 3
	mn, mx := [2]f32{x, y + 2}, [2]f32{x + sz, y + 2 + sz}
	c := h.color
	imgui.DrawList_AddRectFilled(dl, mn, mx, col_u32({c[0], c[1], c[2], 1}), 2)
	imgui.DrawList_AddRect(dl, mn, mx, col_u32(ui_line(0.35)), 2)
	Drive_ItemRect(fmt.tprintf("code.swatch:%d:%d", line + 1, h.col), mn, mx, inWindow = true)
	io := imgui.GetIO()
	if doc != nil && point_in_rect({io.MousePos.x, io.MousePos.y}, mn, mx) && imgui.IsWindowHovered(imgui.HoveredFlags_AllowWhenBlockedByActiveItem) {
		imgui.SetMouseCursor(.Hand)
		UI_Tooltip("Click to pick the colour")
		if imgui.IsMouseClicked(.Left) {
			text := buf.buffer_line_str(&doc.buffer, line)
			inner := text[h.col + 1:h.to - 1]
			swatch_edit = {open = true, doc = doc, line = line, from = h.col, color = h.color, count = strings.count(inner, ",") + 1, ints = !strings.contains(inner, ".")}
		}
	}
	return v + code_inlay_width(h)
}

// Code_SwatchPicker: the colour picker of a clicked swatch (Code window).
Code_SwatchPicker :: proc(doc: ^Code_Doc) {
	se := &swatch_edit
	if se.open {
		imgui.OpenPopup("##swatch_picker")
		se.open = false
	}
	if !imgui.BeginPopup("##swatch_picker") do return
	defer imgui.EndPopup()
	if se.doc != doc {
		imgui.CloseCurrentPopup()
		return
	}
	flags: imgui.ColorEditFlags = {.AlphaBar} if se.count == 4 else {.NoAlpha}
	if imgui.ColorPicker4("##swatch", &se.color, flags) {
		// Rewrite the table in place (same count and style).
		b := &doc.buffer
		text := buf.buffer_line_str(b, se.line)
		if se.from < len(text) && text[se.from] == '{' {
			close := strings.index_byte(text[se.from:], '}')
			if close > 0 {
				sb := strings.builder_make(context.temp_allocator)
				strings.write_byte(&sb, '{')
				for k in 0 ..< se.count {
					if k > 0 do strings.write_string(&sb, ", ")
					if se.ints do fmt.sbprintf(&sb, "%d", int(se.color[k] * 255 + 0.5))
					else do fmt.sbprintf(&sb, "%.2f", se.color[k])
				}
				strings.write_byte(&sb, '}')
				group := buf.buffer_next_group(b)
				buf.buffer_delete_range(b, {se.line, se.from}, {se.line, se.from + close + 1}, group)
				buf.buffer_insert_text(b, {se.line, se.from}, strings.to_string(sb), group)
				code_touched(doc)
			}
		}
	}
	Drive_Item("code.swatch-picker")
	if imgui.IsKeyPressed(.Escape) do imgui.CloseCurrentPopup()
}
