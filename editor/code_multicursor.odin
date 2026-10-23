package editor

import buf "../odin_editor/buffer"

// ============================================================================
// Multi-cursor extras: undo the last cursor change (Cmd+U - every command
// that adds cursors records the previous set), skip an occurrence, a cursor
// at the end of each selected line, select inside brackets / quotes, and
// column (box) selection with Alt+drag.
// ============================================================================

CURSOR_HISTORY_MAX :: 64

// code_cursor_history_push records the cursors before a change adds some.
code_cursor_history_push :: proc(doc: ^Code_Doc) {
	snap := make([]buf.Cursor, len(doc.buffer.cursors))
	copy(snap, doc.buffer.cursors[:])
	append(&doc.cursorHistory, snap)
	if len(doc.cursorHistory) > CURSOR_HISTORY_MAX {
		delete(doc.cursorHistory[0])
		ordered_remove(&doc.cursorHistory, 0)
	}
}

code_cursor_history_destroy :: proc(doc: ^Code_Doc) {
	for s in doc.cursorHistory do delete(s)
	delete(doc.cursorHistory)
}

// Code_CmdUndoCursor (Cmd+U): back to the cursors before the last added one.
Code_CmdUndoCursor :: proc(state: ^EditorState) {
	doc := code_active_doc()
	if doc == nil || len(doc.cursorHistory) == 0 do return
	snap := pop(&doc.cursorHistory)
	defer delete(snap)
	b := &doc.buffer
	clear(&b.cursors)
	for c in snap {
		p := buf.buffer_clamp_position(b, c.pos)
		cc := c
		cc.pos = p
		cc.sel.anchor = buf.buffer_clamp_position(b, c.sel.anchor)
		append(&b.cursors, cc)
	}
	if len(b.cursors) == 0 do append(&b.cursors, buf.Cursor{})
	code_touched(doc)
}

// Code_CmdSkipOccurrence (Cmd+Alt+D): select the next occurrence instead
// of the current one (Cmd+K Cmd+D in VS Code / Zed).
Code_CmdSkipOccurrence :: proc(state: ^EditorState) {
	doc := code_active_doc()
	if doc == nil do return
	b := &doc.buffer
	old := code_primary(b)^
	if _, _, ok := buf.selection_range(old); !ok {
		Code_CmdSelectNextOccurrence(state)
		return
	}
	n := len(b.cursors)
	Code_CmdSelectNextOccurrence(state)
	if len(b.cursors) == n do return // no other occurrence
	// Drop the skipped one (the new one stays the primary).
	for c, i in b.cursors {
		if c.pos == old.pos && c.sel == old.sel && i != len(b.cursors) - 1 {
			ordered_remove(&b.cursors, i)
			break
		}
	}
	code_touched(doc)
}

// Code_CmdCursorsAtLineEnds (Shift+Alt+I): a cursor at the end of every
// line of each selection.
Code_CmdCursorsAtLineEnds :: proc(state: ^EditorState) {
	doc := code_active_doc()
	if doc == nil do return
	b := &doc.buffer
	out := make([dynamic]buf.Cursor, context.temp_allocator)
	for c in b.cursors {
		s, e, ok := buf.selection_range(c)
		if !ok || s.line == e.line {
			append(&out, buf.Cursor{pos = {c.pos.line, buf.buffer_line_len(b, c.pos.line)}})
			continue
		}
		last := e.line if e.col > 0 else e.line - 1
		for ln in s.line ..= last do append(&out, buf.Cursor{pos = {ln, buf.buffer_line_len(b, ln)}})
	}
	code_cursor_history_push(doc)
	clear(&b.cursors)
	append(&b.cursors, ..out[:])
	code_touched(doc)
}

// Code_CmdSelectInside: selects inside the brackets or quotes around the
// caret; again, inside the next pair out.
Code_CmdSelectInside :: proc(state: ^EditorState) {
	doc := code_active_doc()
	if doc == nil do return
	b := &doc.buffer
	c := &b.cursors[len(b.cursors) - 1]
	cur := [2]buf.Position{c.pos, c.pos}
	if s, e, ok := buf.selection_range(c^); ok do cur = {s, e}
	best: [2]buf.Position
	found := false
	inside :: proc(r, cur: [2]buf.Position) -> bool {
		return !buf.position_less(cur[0], r[0]) && !buf.position_less(r[1], cur[1]) && (r[0] != cur[0] || r[1] != cur[1])
	}
	smaller :: proc(r, best: [2]buf.Position) -> bool {
		return !buf.position_less(r[0], best[0]) && !buf.position_less(best[1], r[1])
	}
	for br in code_structure(doc).brackets {
		if br.close.line < 0 do continue
		r := [2]buf.Position{{br.open.line, br.open.col + 1}, br.close}
		if inside(r, cur) && (!found || smaller(r, best)) {best = r; found = true}
	}
	// Quotes on the caret's line.
	if cur[0].line == cur[1].line {
		line := buf.buffer_line_str(b, cur[0].line)
		code_update_line_states(doc)
		state := doc.lineStates[cur[0].line] if cur[0].line < len(doc.lineStates) else 0
		tokens, _ := Token_CacheGet(&doc.tokens, doc.lang, line, state, b.version)
		for t in tokens {
			if t.kind != .String || t.end - t.start < 2 do continue
			r := [2]buf.Position{{cur[0].line, t.start + 1}, {cur[0].line, t.end - 1}}
			if inside(r, cur) && (!found || smaller(r, best)) {best = r; found = true}
		}
	}
	if !found do return
	code_set_single_cursor(b, best[0], false)
	b.cursors[0].sel = {anchor = best[0], active = best[0] != best[1]}
	b.cursors[0].pos = best[1]
	code_touched(doc)
}

// code_column_select: cursors for the box between two screen points (one
// per line; a line too short gets an empty cursor at its end).
code_column_select :: proc(doc: ^Code_Doc, from, to: [2]f32) {
	b := &doc.buffer
	a := code_pos_at(b, from)
	z := code_pos_at(b, to)
	clear(&b.cursors)
	l0, l1 := min(a.line, z.line), max(a.line, z.line)
	for ln in l0 ..= l1 {
		y := GlobalCode.textOrigin.y + f32(ln) * GlobalCode.lineH + GlobalCode.lineH * 0.5
		s := code_pos_at(b, {from.x, y})
		e := code_pos_at(b, {to.x, y})
		append(&b.cursors, buf.Cursor{pos = e, sel = {anchor = s, active = s != e}})
	}
	if len(b.cursors) == 0 do append(&b.cursors, buf.Cursor{pos = a})
}
