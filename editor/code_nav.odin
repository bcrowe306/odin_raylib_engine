package editor

import "core:strings"
import buf "../odin_editor/buffer"

// ============================================================================
// Back / forward (Ctrl+- / Ctrl+Shift+-): the places the caret jumped from.
// Any move of more than NAV_JUMP_LINES lines, or to another file, records
// where it was - so go to definition, references, go to line, outline,
// breadcrumbs, search results, diagnostics all come back here.
// ============================================================================

NAV_JUMP_LINES :: 10
NAV_MAX :: 100

Nav_Entry :: struct {
	path: string, // absolute (heap)
	pos:  buf.Position,
}

@(private = "file")
nav: struct {
	back, forward: [dynamic]Nav_Entry,
	lastPath:      string, // where the caret was last frame (heap)
	lastPos:       buf.Position,
	navigating:    bool, // our own jump: not recorded
}

@(private = "file")
nav_push :: proc(list: ^[dynamic]Nav_Entry, path: string, pos: buf.Position) {
	if n := len(list); n > 0 && list[n - 1].path == path && abs(list[n - 1].pos.line - pos.line) <= NAV_JUMP_LINES do return
	append(list, Nav_Entry{strings.clone(path), pos})
	if len(list) > NAV_MAX {
		delete(list[0].path)
		ordered_remove(list, 0)
	}
}

@(private = "file")
nav_clear :: proc(list: ^[dynamic]Nav_Entry) {
	for e in list do delete(e.path)
	clear(list)
}

// Code_NavTrack runs once a frame: a jump records the previous place.
Code_NavTrack :: proc() {
	doc := code_active_doc()
	if doc == nil do return
	p := doc.buffer.cursors[len(doc.buffer.cursors) - 1].pos
	if nav.lastPath != "" && !nav.navigating {
		jumped := nav.lastPath != doc.path || abs(p.line - nav.lastPos.line) > NAV_JUMP_LINES
		if jumped {
			nav_push(&nav.back, nav.lastPath, nav.lastPos)
			nav_clear(&nav.forward)
		}
	}
	nav.navigating = false
	if nav.lastPath != doc.path {
		delete(nav.lastPath)
		nav.lastPath = strings.clone(doc.path)
	}
	nav.lastPos = p
}

@(private = "file")
nav_go :: proc(state: ^EditorState, from, to: ^[dynamic]Nav_Entry) {
	doc := code_active_doc()
	for len(from) > 0 {
		e := pop(from)
		defer delete(e.path)
		if doc != nil do nav_push(to, doc.path, doc.buffer.cursors[len(doc.buffer.cursors) - 1].pos)
		nav.navigating = true
		if Editor_OpenScript(state, e.path, e.pos.line, e.pos.col) do return
	}
}

// Code_CmdNavBack (Ctrl+-) / Code_CmdNavForward (Ctrl+Shift+-).
Code_CmdNavBack :: proc(state: ^EditorState) {nav_go(state, &nav.back, &nav.forward)}
Code_CmdNavForward :: proc(state: ^EditorState) {nav_go(state, &nav.forward, &nav.back)}

Code_NavCounts :: proc() -> (back, forward: int) {return len(nav.back), len(nav.forward)}

Code_NavShutdown :: proc() {
	nav_clear(&nav.back)
	nav_clear(&nav.forward)
	delete(nav.back)
	delete(nav.forward)
	delete(nav.lastPath)
	nav = {}
}

// --- next / previous diagnostic and change -------------------------------------------

// code_goto_line_col moves the caret (and scrolls) to a position.
@(private = "file")
code_goto :: proc(doc: ^Code_Doc, p: buf.Position) {
	code_set_single_cursor(&doc.buffer, buf.buffer_clamp_position(&doc.buffer, p), false)
	doc.scrollToCursor = true
	code_touched(doc)
}

// Code_CmdNextDiagnostic (F8 / Shift+F8): the next / previous error or
// warning after the caret, wrapping around.
Code_CmdNextDiagnostic :: proc(state: ^EditorState, dir: int) {
	doc := code_active_doc()
	if doc == nil do return
	diags := code_diagnostics(doc)
	if len(diags) == 0 do return
	cur := doc.buffer.cursors[len(doc.buffer.cursors) - 1].pos
	best := -1
	bestKey := 0
	key :: proc(line, col: int) -> int {return line * 100000 + col}
	ck := key(cur.line, cur.col)
	for d, i in diags {
		text := buf.buffer_line_str(&doc.buffer, min(d.range.start.line, buf.buffer_line_count(&doc.buffer) - 1))
		k := key(d.range.start.line, code_byte_from_u16(text, d.range.start.character))
		if dir > 0 {
			if k > ck && (best < 0 || k < bestKey) {best, bestKey = i, k}
		} else {
			if k < ck && (best < 0 || k > bestKey) {best, bestKey = i, k}
		}
	}
	if best < 0 {
		// Wrap: the first / last one.
		for d, i in diags {
			k := key(d.range.start.line, d.range.start.character)
			if best < 0 || (dir > 0 && k < bestKey) || (dir < 0 && k > bestKey) {best, bestKey = i, k}
		}
	}
	d := diags[best]
	text := buf.buffer_line_str(&doc.buffer, min(d.range.start.line, buf.buffer_line_count(&doc.buffer) - 1))
	code_goto(doc, {d.range.start.line, code_byte_from_u16(text, d.range.start.character)})
}

// Code_CmdNextChange (Alt+F8 / Alt+Shift+F8): the next / previous changed
// block since the last commit (code_git.odin), wrapping around.
Code_CmdNextChange :: proc(state: ^EditorState, dir: int) {
	doc := code_active_doc()
	if doc == nil do return
	marks := Code_ChangedLines(doc)
	if len(marks) == 0 do return
	cur := doc.buffer.cursors[len(doc.buffer.cursors) - 1].pos.line
	// Block starts: a changed line whose line above isn't changed.
	isChanged :: proc(marks: []Code_Change_Mark, ln: int) -> bool {
		for m in marks do if m.line == ln && m.color != CHANGE_DELETED do return true
		return false
	}
	best := -1
	first, last := max(int), -1
	for m in marks {
		if m.color != CHANGE_DELETED && isChanged(marks, m.line - 1) do continue
		first, last = min(first, m.line), max(last, m.line)
		if dir > 0 && m.line > cur && (best < 0 || m.line < best) do best = m.line
		if dir < 0 && m.line < cur && (best < 0 || m.line > best) do best = m.line
	}
	if best < 0 do best = first if dir > 0 else last
	if best >= 0 do code_goto(doc, {best, 0})
}
