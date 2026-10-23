package editor

import "core:fmt"
import "core:strings"
import buf "../odin_editor/buffer"
import imgui "lib/imgui"

// ============================================================================
// Breadcrumbs (a bar above the code: file > function > blocks around the
// caret, each clickable) and sticky scroll (the first lines of the blocks
// the top of the view is inside stay pinned at the top, up to 3, with
// their line numbers; click one to go there). Both from code_structure.odin.
// ============================================================================

CODE_CRUMBS_H :: 24
STICKY_MAX :: 3

// code_block_label: a short name for a block's first line.
code_block_label :: proc(doc: ^Code_Doc, bl: Code_Block) -> string {
	line := strings.trim_space(buf.buffer_line_str(&doc.buffer, bl.start))
	#partial switch bl.kind {
	case .Function:
		// "function PlayerShip:update(dt)" / "local function f(x)" / "x = function(...)" -> the name
		if i := strings.index(line, "function"); i >= 0 {
			rest := strings.trim_space(line[i + len("function"):])
			if p := strings.index_byte(rest, '('); p > 0 do return strings.clone(rest[:p], context.temp_allocator)
			if eq := strings.index_byte(line, '='); eq > 0 && eq < i do return strings.clone(strings.trim_space(strings.trim_prefix(line[:eq], "local ")), context.temp_allocator)
			return "function"
		}
	case .Table:
		if eq := strings.index_byte(line, '='); eq > 0 do return strings.clone(strings.trim_space(strings.trim_prefix(line[:eq], "local ")), context.temp_allocator)
		return "{ }"
	}
	if len(line) > 40 do return fmt.tprintf("%s…", line[:38])
	return strings.clone(line, context.temp_allocator)
}

// code_blocks_around: the blocks containing a line, outermost first
// (comments left out; a block's own first line counts as inside it).
code_blocks_around :: proc(doc: ^Code_Doc, line: int, includeStart := true) -> []Code_Block {
	out := make([dynamic]Code_Block, context.temp_allocator)
	for bl in code_structure(doc).blocks {
		if bl.start > line do break
		if bl.kind == .Comment || bl.end <= bl.start || bl.end < line do continue
		if !includeStart && bl.start == line do continue
		append(&out, bl)
	}
	return out[:]
}

// Code_Breadcrumbs draws the bar (before the code area).
Code_Breadcrumbs :: proc(state: ^EditorState, doc: ^Code_Doc) {
	b := &doc.buffer
	p := b.cursors[len(b.cursors) - 1].pos
	imgui.PushStyleColorImVec4(.ChildBg, CODE_BG)
	defer imgui.PopStyleColor()
	if !imgui.BeginChild("##code_crumbs", {0, CODE_CRUMBS_H}, {}, {.NoScrollbar}) {
		imgui.EndChild()
		return
	}
	defer imgui.EndChild()
	imgui.SetCursorPos({8, 4})
	imgui.PushStyleVarImVec2(.ItemSpacing, {4, 0})
	defer imgui.PopStyleVar()
	imgui.TextColored(UI_TEXT_DIM, "%s", fmt.ctprintf("%s", doc.rel))
	for bl, i in code_blocks_around(doc, p.line) {
		imgui.SameLine()
		imgui.TextColored(UI_TEXT_FAINT, "›")
		imgui.SameLine()
		label := code_block_label(doc, bl)
		col := UI_TEXT if bl.kind == .Function else UI_TEXT_DIM
		imgui.PushStyleColorImVec4(.Text, col)
		if imgui.Selectable(fmt.ctprintf("%s##crumb%d", label, i), false, {}, {imgui.CalcTextSize(strings.clone_to_cstring(label, context.temp_allocator)).x, 0}) {
			code_set_single_cursor(b, {bl.start, bl.col}, false)
			doc.scrollToCursor = true
			GlobalCode.focusRequest = true
		}
		imgui.PopStyleColor()
		Drive_Item(fmt.tprintf("code.crumb:%d", i))
	}
}

// code_sticky_lines: the first lines to pin for a top line (outermost first).
code_sticky_lines :: proc(doc: ^Code_Doc, topLine: int) -> []int {
	out := make([dynamic]int, context.temp_allocator)
	blocks := code_blocks_around(doc, topLine, includeStart = false)
	from := max(len(blocks) - STICKY_MAX, 0)
	for bl in blocks[from:] do append(&out, bl.start)
	return out[:]
}

// code_draw_sticky pins the block headers over the top of the code area
// (call after the code and gutter are drawn); returns the pinned height.
code_draw_sticky :: proc(doc: ^Code_Doc, winPos, winSize: imgui.Vec2, gutterW: f32, firstRow: int) -> f32 {
	if !GlobalSettings.stickyScroll do return 0
	cm := &GlobalCode
	b := &doc.buffer
	disp := code_display(doc)
	if firstRow >= len(disp.rows) do return 0
	// The pinned rows push the "top line" down by their count.
	lines := code_sticky_lines(doc, disp.rows[firstRow].line)
	if len(lines) == 0 do return 0
	lines = code_sticky_lines(doc, disp.rows[min(firstRow + len(lines), len(disp.rows) - 1)].line)
	if len(lines) == 0 do return 0
	dl := imgui.GetWindowDrawList()
	textY := (cm.lineH - code_font_size()) * 0.5
	h := f32(len(lines)) * cm.lineH
	top := winPos.y
	imgui.DrawList_AddRectFilled(dl, {winPos.x, top}, {winPos.x + winSize.x - imgui.GetStyle().ScrollbarSize, top + h}, col_u32(CODE_BG))
	imgui.DrawList_AddLine(dl, {winPos.x, top + h}, {winPos.x + winSize.x, top + h}, col_u32(ui_line(0.12)))
	imgui.DrawList_AddRectFilledMultiColor(dl, {winPos.x, top + h}, {winPos.x + winSize.x, top + h + 6}, col_u32({0, 0, 0, 0.25}), col_u32({0, 0, 0, 0.25}), col_u32({0, 0, 0, 0}), col_u32({0, 0, 0, 0}))
	font := code_font()
	io := imgui.GetIO()
	mouse := [2]f32{io.MousePos.x, io.MousePos.y}
	textX := winPos.x + gutterW + 6 // fixed: no horizontal scroll for pinned lines
	for ln, i in lines {
		y := top + f32(i) * cm.lineH
		text := buf.buffer_line_str(b, ln)
		mn, mx := [2]f32{winPos.x, y}, [2]f32{winPos.x + winSize.x, y + cm.lineH}
		hot := point_in_rect(mouse, mn, mx) && imgui.IsWindowHovered(imgui.HoveredFlags_AllowWhenBlockedByActiveItem)
		if hot do imgui.DrawList_AddRectFilled(dl, mn, mx, col_u32(ui_line(0.05)))
		num := fmt.ctprintf("%d", ln + 1)
		w := imgui.Font_CalcTextSizeA(font, code_font_size(), max(f32), 0, num).x
		imgui.DrawList_AddTextImFontPtr(dl, font, code_font_size(), {winPos.x + gutterW - 18 - w, y + textY}, col_u32(UI_TEXT_FAINT), num)
		tokens, _ := Token_CacheGet(&doc.tokens, doc.lang, text, doc.lineStates[ln] if ln < len(doc.lineStates) else 0, b.version)
		v, at := 0, 0
		for t in tokens {
			if t.start > at do v = code_draw_text(dl, textX, y + textY, v, text[at:t.start], col_u32(UI_TEXT))
			v = code_draw_text(dl, textX, y + textY, v, text[t.start:t.end], code_token_color(t.kind))
			at = t.end
		}
		if at < len(text) do code_draw_text(dl, textX, y + textY, v, text[at:], col_u32(UI_TEXT))
		Drive_ItemRect(fmt.tprintf("code.sticky:%d", ln + 1), mn, mx) // always on screen: no scroll into view
		if hot {
			imgui.SetMouseCursor(.Hand)
			if imgui.IsMouseClicked(.Left) {
				code_set_single_cursor(b, {ln, len(text) - len(strings.trim_left(text, " \t"))}, false)
				doc.scrollToCursor = true
				doc.scrollToTop = true
			}
		}
	}
	cm.stickyH = h
	return h
}

// Code_StickyHovered: the mouse is over the pinned lines (no text clicks).
Code_StickyHovered :: proc(winPos, winSize: imgui.Vec2) -> bool {
	io := imgui.GetIO()
	return GlobalCode.stickyH > 0 && point_in_rect({io.MousePos.x, io.MousePos.y}, {winPos.x, winPos.y}, {winPos.x + winSize.x, winPos.y + GlobalCode.stickyH})
}
