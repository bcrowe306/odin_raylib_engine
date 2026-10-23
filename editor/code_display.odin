package editor

import "core:strings"
import buf "../odin_editor/buffer"

// ============================================================================
// Display map (Zed's DisplayMap, simplified): the rows the Code tab draws.
// Folded lines are left out (a folded block shows its first and last line)
// and, with soft wrap on, long lines are split into several rows at word
// boundaries, continuation rows indented like the line. Every buffer <->
// screen mapping (drawing, clicks, carets, scrolling, Up / Down) goes
// through it. Rebuilt only when the text, the wrap width or the folds
// change; owned by the doc.
// ============================================================================

Display_Row :: struct {
	line:     int,
	from, to: int, // bytes of the line on this row ([from, to); the last row ends at the line end)
	indent:   int, // columns before the text (continuation rows)
}

Code_Display :: struct {
	valid:        bool,
	version:      int,
	wrapCols:     int, // 0 = no wrap
	foldsVersion: int,
	rows:         [dynamic]Display_Row,
	lineRow:      [dynamic]int, // first row of each line (a hidden line: its fold header's row)
}

code_display_destroy :: proc(d: ^Code_Display) {
	delete(d.rows)
	delete(d.lineRow)
	d^ = {}
}

// code_display: the doc's display map, rebuilt when stale.
code_display :: proc(doc: ^Code_Doc) -> ^Code_Display {
	d := &doc.display
	b := &doc.buffer
	cols := code_wrap_cols()
	if d.valid && d.version == b.version && d.wrapCols == cols && d.foldsVersion == doc.foldsVersion do return d
	d.valid, d.version, d.wrapCols, d.foldsVersion = true, b.version, cols, doc.foldsVersion
	clear(&d.rows)
	n := buf.buffer_line_count(b)
	resize(&d.lineRow, n)
	tab := code_tab_width()
	hideUntil := -1 // lines up to here are inside a fold
	for ln in 0 ..< n {
		if ln <= hideUntil {
			d.lineRow[ln] = len(d.rows) - 1
			continue
		}
		d.lineRow[ln] = len(d.rows)
		text := buf.buffer_line_str(b, ln)
		if cols <= 0 || code_visual_col(text, len(text)) <= cols {
			append(&d.rows, Display_Row{ln, 0, len(text), 0})
		} else {
			code_wrap_line(&d.rows, ln, text, cols, tab)
		}
		if end, folded := code_fold_end(doc, ln); folded do hideUntil = end - 1
	}
	if len(d.rows) == 0 do append(&d.rows, Display_Row{0, 0, 0, 0})
	return d
}

// code_wrap_line splits a long line into rows of at most cols columns,
// breaking after a space when there is one in the row.
@(private = "file")
code_wrap_line :: proc(rows: ^[dynamic]Display_Row, ln: int, text: string, cols, tab: int) {
	indent := min(code_line_indent(text, tab), cols / 2)
	from := 0
	first := true
	for from < len(text) {
		room := cols if first else cols - indent
		// The byte where `room` columns from `from` end.
		v0 := code_visual_col(text, from)
		end := code_byte_col(text, v0 + room)
		if end >= len(text) {
			append(rows, Display_Row{ln, from, len(text), 0 if first else indent})
			return
		}
		// Prefer the last space in the row.
		brk := end
		if sp := strings.last_index_byte(text[from:end], ' '); sp > 0 do brk = from + sp + 1
		if brk <= from do brk = max(end, from + 1)
		append(rows, Display_Row{ln, from, brk, 0 if first else indent})
		from = brk
		first = false
	}
	if from == 0 do append(rows, Display_Row{ln, 0, 0, 0})
}

// code_wrap_cols: columns that fit the code area with soft wrap on (0 = off).
code_wrap_cols :: proc() -> int {
	if !GlobalSettings.softWrap do return 0
	cm := &GlobalCode
	w := cm.areaMax.x - cm.textOrigin.x - cm.charW * 2
	if cm.charW <= 0 || w <= 0 do return 0
	return max(int(w / cm.charW), 20)
}

// code_row_of: the row showing a buffer position.
code_row_of :: proc(doc: ^Code_Doc, p: buf.Position) -> int {
	d := code_display(doc)
	if len(d.lineRow) == 0 do return 0
	line := clamp(p.line, 0, len(d.lineRow) - 1)
	r := d.lineRow[line]
	if r < 0 || r >= len(d.rows) || d.rows[r].line != line do return max(r, 0) // hidden: the fold header
	for r + 1 < len(d.rows) && d.rows[r + 1].line == line && d.rows[r + 1].from <= p.col do r += 1
	return r
}

// code_row_x: columns from the text's left edge to byte col on a row
// (inlay hints before it included).
code_row_x :: proc(text: string, row: Display_Row, col: int, hints: []Code_Inlay = nil) -> int {
	c := clamp(col, row.from, len(text))
	return row.indent + code_visual_col(text, c) - code_visual_col(text, row.from) + code_inlay_before(hints, row.from, c)
}

// code_row_col: the byte of a row at a column from the text's left edge
// (a column inside a hint maps to the text after it).
code_row_col :: proc(text: string, row: Display_Row, vcol: int, hints: []Code_Inlay = nil) -> int {
	base := code_visual_col(text, row.from)
	v := max(vcol - row.indent, 0)
	last := row.to == len(text)
	hi := row.to if last else max(row.to - 1, row.from)
	col := code_byte_col(text, v + base)
	if len(hints) > 0 {
		// Walk the row: text columns and hint widths.
		x := 0
		col = hi // past the last character: the row's end
		for k := row.from; k < hi; k += 1 {
			for h in hints do if h.col == k do x += code_inlay_width(h)
			w := code_visual_col(text, k + 1) - code_visual_col(text, k)
			if v < x + (w + 1) / 2 {col = k; break}
			x += w
		}
	}
	return clamp(col, row.from, hi)
}

// code_display_move: Up / Down by display rows, keeping the column.
code_display_move :: proc(doc: ^Code_Doc, c: ^buf.Cursor, rowsDelta: int, extend: bool) {
	b := &doc.buffer
	d := code_display(doc)
	r := code_row_of(doc, c.pos)
	row := d.rows[r]
	text := buf.buffer_line_str(b, row.line)
	x := code_row_x(text, row, c.pos.col, code_inlays(doc, row.line))
	t := clamp(r + rowsDelta, 0, len(d.rows) - 1)
	if extend && !c.sel.active do c.sel = {anchor = c.pos, active = true}
	if t == r {
		c.pos = {row.line, 0} if rowsDelta < 0 else {row.line, len(text)}
	} else {
		tr := d.rows[t]
		c.pos = {tr.line, code_row_col(buf.buffer_line_str(b, tr.line), tr, x, code_inlays(doc, tr.line))}
	}
	if !extend do c.sel.active = false
}
