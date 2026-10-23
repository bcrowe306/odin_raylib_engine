package editor

import "core:fmt"
import "core:strings"
import buf "../odin_editor/buffer"
import imgui "lib/imgui"

// ============================================================================
// Overview strip (scrollbar markers) at the right of the code: where the
// errors / warnings, find matches, uses of the caret's word, breakpoints,
// changes since the last commit and the caret are in the whole file, and
// the visible part. Click or drag in it to scroll there. Rows come from
// the display map, so folds and soft wrap are taken into account.
// ============================================================================

CODE_STRIP_W :: 10

// Code_Sym_Cache: whole-file occurrences of the caret's word (per edit + word).
Code_Sym_Cache :: struct {
	version: int,
	word:    [64]u8,
	wordLen: int,
	lines:   [dynamic]int,
}

code_sym_cache_destroy :: proc(c: ^Code_Sym_Cache) {
	delete(c.lines)
	c^ = {}
}

@(private = "file")
code_sym_lines :: proc(doc: ^Code_Doc) -> []int {
	b := &doc.buffer
	p := b.cursors[len(b.cursors) - 1].pos
	line := buf.buffer_line_str(b, p.line)
	s, e := min(p.col, len(line)), min(p.col, len(line))
	for s > 0 && code_is_ident_byte(line[s - 1]) do s -= 1
	for e < len(line) && code_is_ident_byte(line[e]) do e += 1
	c := &doc.symCache
	word := line[s:e]
	if c.version == b.version && string(c.word[:c.wordLen]) == word do return c.lines[:]
	c.version = b.version
	c.wordLen = copy(c.word[:], word)
	clear(&c.lines)
	if e - s < 2 do return nil
	for r in code_symbol_occurrences(doc, 0, buf.buffer_line_count(b) - 1) do append(&c.lines, r.line)
	return c.lines[:]
}

// code_overview draws the strip; rowCount display rows, lineH per row.
code_overview :: proc(state: ^EditorState, doc: ^Code_Doc, winPos, winSize: imgui.Vec2, findAll: []Code_Match, diags: []Code_Diag_View) {
	cm := &GlobalCode
	disp := code_display(doc)
	rows := max(len(disp.rows), 1)
	dl := imgui.GetWindowDrawList()
	sb := imgui.GetStyle().ScrollbarSize
	x1 := winPos.x + winSize.x - sb - 1
	x0 := x1 - CODE_STRIP_W
	top := winPos.y + 2
	h := winSize.y - 4
	yOf :: proc(doc: ^Code_Doc, line, rows: int, top, h: f32) -> f32 {
		return top + f32(code_row_of(doc, {line, 0})) / f32(rows) * h
	}
	imgui.DrawList_AddRectFilled(dl, {x0, top}, {x1, top + h}, col_u32(ui_line(0.025)))
	// The visible part.
	scroll := imgui.GetScrollY()
	vis0 := top + scroll / cm.lineH / f32(rows) * h
	vis1 := top + (scroll + winSize.y) / cm.lineH / f32(rows) * h
	imgui.DrawList_AddRectFilled(dl, {x0, vis0}, {x1, min(vis1, top + h)}, col_u32(ui_line(0.06)))
	mark :: proc(dl: ^imgui.DrawList, x0, x1, y: f32, col: u32, full := true, hgt: f32 = 2) {
		a := x0 if full else x0 + (x1 - x0) * 0.5
		imgui.DrawList_AddRectFilled(dl, {a, y}, {x1, y + hgt}, col)
	}
	for ln in code_sym_lines(doc) do mark(dl, x0, x1, yOf(doc, ln, rows, top, h), col_u32(ui_line(0.30)), false)
	for m in findAll do mark(dl, x0, x1, yOf(doc, m.start.line, rows, top, h), col_u32({0.961, 0.722, 0.298, 0.9}))
	for ln in Code_ChangedLines(doc) do mark(dl, x0, x0 + 3, yOf(doc, ln.line, rows, top, h), col_u32(ln.color), true, 3)
	if doc.isLua {
		for ln in Debug_BreakpointLines(doc.rel) do mark(dl, x0, x1, yOf(doc, ln - 1, rows, top, h), col_u32({0.92, 0.30, 0.29, 1}), false, 3)
	}
	for d in diags do mark(dl, x0, x1, yOf(doc, d.line, rows, top, h), d.color, true, 3)
	cy := yOf(doc, doc.buffer.cursors[len(doc.buffer.cursors) - 1].pos.line, rows, top, h)
	imgui.DrawList_AddRectFilled(dl, {x0, cy}, {x1, cy + 2}, col_u32(UI_ACCENT))
	// Click / drag: scroll there.
	io := imgui.GetIO()
	mouse := [2]f32{io.MousePos.x, io.MousePos.y}
	Drive_ItemRect("code.overview", {x0, top}, {x1, top + h}, inWindow = true)
	@(static) dragging: bool
	inStrip := point_in_rect(mouse, {x0, top}, {x1, top + h}) && imgui.IsWindowHovered(imgui.HoveredFlags_AllowWhenBlockedByActiveItem)
	if inStrip && imgui.IsMouseClicked(.Left) do dragging = true
	if !imgui.IsMouseDown(.Left) do dragging = false
	if dragging {
		row := clamp((mouse.y - top) / h, 0, 1) * f32(rows)
		imgui.SetScrollY(max(row * cm.lineH - winSize.y * 0.5, 0))
	}
	if inStrip do UI_Tooltip(fmt.tprintf("Line %d - click to scroll there", disp.rows[clamp(int((mouse.y - top) / h * f32(rows)), 0, rows - 1)].line + 1))
	_ = strings.trim_space
}

// Code_Diag_View: a diagnostic's line and colour for the strip.
Code_Diag_View :: struct {
	line:  int,
	color: u32,
}

// Code_OverviewHovered: the mouse is over the strip (no text clicks there).
Code_OverviewHovered :: proc(winPos, winSize: imgui.Vec2) -> bool {
	io := imgui.GetIO()
	sb := imgui.GetStyle().ScrollbarSize
	x1 := winPos.x + winSize.x - sb - 1
	return point_in_rect({io.MousePos.x, io.MousePos.y}, {x1 - CODE_STRIP_W, winPos.y}, {x1 + sb + 1, winPos.y + winSize.y})
}

// Code_Change_Mark: a changed line for the gutter / strip (code_git.odin).
Code_Change_Mark :: struct {
	line:  int,
	color: imgui.Vec4,
}
