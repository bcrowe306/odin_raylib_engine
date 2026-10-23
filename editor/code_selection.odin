package editor

import "core:strings"
import buf "../odin_editor/buffer"

// ============================================================================
// Expand / shrink selection (Zed's select larger / smaller syntax node):
// each expand grows every cursor's selection to the next enclosing unit -
// word, string contents, string, inside brackets, brackets, line, block
// body, block, file (code_structure.odin) - and shrink steps back.
// ============================================================================

@(private = "file")
Range :: [2]buf.Position

@(private = "file")
lt :: proc(a, b: buf.Position) -> bool {return a.line < b.line || (a.line == b.line && a.col < b.col)}
@(private = "file")
le :: proc(a, b: buf.Position) -> bool {return !lt(b, a)}

// contains: r covers cur and is strictly larger.
@(private = "file")
grows :: proc(r, cur: Range) -> bool {
	return le(r[0], cur[0]) && le(cur[1], r[1]) && (r[0] != cur[0] || r[1] != cur[1])
}

// code_expand_range: the smallest unit strictly enclosing cur.
code_expand_range :: proc(doc: ^Code_Doc, cur: Range) -> (Range, bool) {
	b := &doc.buffer
	best: Range
	found := false
	consider :: proc(best: ^Range, found: ^bool, r, cur: Range) {
		if !grows(r, cur) do return
		if !found^ || (le(best[0], r[0]) && le(r[1], best[1])) {
			best^ = r
			found^ = true
		}
	}
	line := buf.buffer_line_str(b, cur[0].line)
	ident :: proc(ch: u8) -> bool {return ch == '_' || (ch | 0x20 >= 'a' && ch | 0x20 <= 'z') || (ch >= '0' && ch <= '9')}
	// Word.
	if cur[0].line == cur[1].line {
		s, e := cur[0].col, cur[1].col
		for s > 0 && s <= len(line) && ident(line[s - 1]) do s -= 1
		for e < len(line) && ident(line[e]) do e += 1
		if e > s do consider(&best, &found, {{cur[0].line, s}, {cur[0].line, e}}, cur)
		// String literal (contents, then with its quotes).
		code_update_line_states(doc)
		state := doc.lineStates[cur[0].line] if cur[0].line < len(doc.lineStates) else 0
		tokens, _ := Token_CacheGet(&doc.tokens, doc.lang, line, state, b.version)
		for t in tokens {
			if t.kind != .String || t.start > cur[0].col || t.end < cur[1].col do continue
			ln := cur[0].line
			if t.end - t.start >= 2 do consider(&best, &found, {{ln, t.start + 1}, {ln, t.end - 1}}, cur)
			consider(&best, &found, {{ln, t.start}, {ln, t.end}}, cur)
		}
	}
	// Brackets: inside, then including them.
	st := code_structure(doc)
	for br in st.brackets {
		if br.close.line < 0 do continue
		inner := Range{{br.open.line, br.open.col + 1}, br.close}
		outer := Range{br.open, {br.close.line, br.close.col + 1}}
		consider(&best, &found, inner, cur)
		consider(&best, &found, outer, cur)
	}
	// Lines (their text without the indentation).
	{
		first := buf.buffer_line_str(b, cur[0].line)
		lastLen := buf.buffer_line_len(b, cur[1].line)
		consider(&best, &found, {{cur[0].line, len(first) - len(strings.trim_left(first, " \t"))}, {cur[1].line, lastLen}}, cur)
	}
	// Blocks: the body lines, then the whole block.
	for bl in st.blocks {
		if bl.end <= bl.start do continue
		if bl.end - bl.start >= 2 {
			consider(&best, &found, {{bl.start + 1, 0}, {bl.end - 1, buf.buffer_line_len(b, bl.end - 1)}}, cur)
		}
		consider(&best, &found, {{bl.start, bl.col}, {bl.end, buf.buffer_line_len(b, bl.end)}}, cur)
	}
	// The file.
	last := buf.buffer_line_count(b) - 1
	consider(&best, &found, {{0, 0}, {last, buf.buffer_line_len(b, last)}}, cur)
	return best, found
}

// Code_CmdExpandSelection (Alt+Up / Ctrl+Shift+Right).
Code_CmdExpandSelection :: proc(state: ^EditorState) {
	doc := code_active_doc()
	if doc == nil do return
	b := &doc.buffer
	c := &b.cursors[0]
	cur := Range{c.pos, c.pos}
	if s, e, ok := buf.selection_range(c^); ok do cur = {s, e}
	// A selection not made by expanding starts a new history.
	if len(doc.selStack) > 0 && doc.selStack[len(doc.selStack) - 1] != cur do clear(&doc.selStack)
	r, ok := code_expand_range(doc, cur)
	if !ok do return
	if len(doc.selStack) == 0 do append(&doc.selStack, cur)
	append(&doc.selStack, r)
	code_set_single_cursor(b, r[0], false)
	b.cursors[0].sel = {anchor = r[0], active = r[0] != r[1]}
	b.cursors[0].pos = r[1]
	code_touched(doc)
}

// Code_CmdShrinkSelection (Alt+Down / Ctrl+Shift+Left): back one expand.
Code_CmdShrinkSelection :: proc(state: ^EditorState) {
	doc := code_active_doc()
	if doc == nil || len(doc.selStack) < 2 do return
	b := &doc.buffer
	c := b.cursors[0]
	cur := Range{c.pos, c.pos}
	if s, e, ok := buf.selection_range(c); ok do cur = {s, e}
	if doc.selStack[len(doc.selStack) - 1] != cur {
		clear(&doc.selStack)
		return
	}
	pop(&doc.selStack)
	r := doc.selStack[len(doc.selStack) - 1]
	if len(doc.selStack) == 1 do clear(&doc.selStack)
	code_set_single_cursor(b, r[0], false)
	b.cursors[0].sel = {anchor = r[0], active = r[0] != r[1]}
	b.cursors[0].pos = r[1]
	code_touched(doc)
}
