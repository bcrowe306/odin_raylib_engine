package editor

import "core:strings"
import buf "../odin_editor/buffer"
import syn "../odin_editor/syntax"

// ============================================================================
// Code structure of a document (Lua): bracket pairs and blocks (function /
// if / for / while / repeat / do ... end, multi-line { } tables, comment
// runs), outside strings and comments. Computed once per buffer version,
// only when something asks (expand selection, bracket matching, folding,
// sticky scroll), from the per-line tokens the drawing already caches.
// Owned by the doc (code_structure_destroy on close).
// ============================================================================

Code_Bracket :: struct {
	open, close: buf.Position, // close.line = -1: unmatched
	depth:       int,
}

Code_Block_Kind :: enum {
	Function,
	If,
	For,
	While,
	Repeat,
	Do,
	Table,   // a { } spanning lines
	Comment, // consecutive comment lines / --[[ ]]
}

Code_Block :: struct {
	kind:       Code_Block_Kind,
	start, end: int, // lines (header, closer)
	col:        int, // the keyword / bracket column on the start line
}

// Code_Bracket_Mark: one bracket character, in document order (drawing).
Code_Bracket_Mark :: struct {
	pos:     buf.Position,
	depth:   int,
	matched: bool,
}

Code_Structure :: struct {
	version:  int,
	valid:    bool,
	brackets: [dynamic]Code_Bracket,      // in order of their opener
	blocks:   [dynamic]Code_Block,        // in order of their start
	marks:    [dynamic]Code_Bracket_Mark, // every bracket character, in order
	// Matching bracket for the caret (cached per version + caret).
	matchFor:     buf.Position,
	matchVersion: int,
	match:        Code_Bracket,
	matchOk:      bool,
}

code_structure_destroy :: proc(s: ^Code_Structure) {
	delete(s.brackets)
	delete(s.blocks)
	delete(s.marks)
	s^ = {}
}

// code_structure: the doc's structure for its current version.
code_structure :: proc(doc: ^Code_Doc) -> ^Code_Structure {
	s := &doc.structure
	b := &doc.buffer
	if s.valid && s.version == b.version do return s
	code_update_line_states(doc)
	clear(&s.brackets)
	clear(&s.blocks)
	clear(&s.marks)
	s.version = b.version
	s.matchVersion = -1
	s.valid = true

	Open :: struct {
		kind:     Code_Block_Kind,
		line, col: int,
		expectDo: bool, // for / while: their `do` belongs to them
	}
	opens := make([dynamic]Open, context.temp_allocator)
	bstack := make([dynamic]int, context.temp_allocator) // indices into s.brackets
	commentStart := -1
	n := buf.buffer_line_count(b)
	for ln in 0 ..< n {
		line := buf.buffer_line_str(b, ln)
		state := doc.lineStates[ln] if ln < len(doc.lineStates) else 0
		tokens, _ := Token_CacheGet(&doc.tokens, doc.lang, line, state, b.version)
		// Comment runs (2+ lines whose code is only a comment).
		isComment := len(tokens) > 0 && tokens[0].kind == .Comment && strings.trim_space(line[:tokens[0].start]) == "" && len(tokens) == 1
		if isComment && commentStart < 0 do commentStart = ln
		if !isComment && commentStart >= 0 {
			if ln - 1 > commentStart do append(&s.blocks, Code_Block{.Comment, commentStart, ln - 1, 0})
			commentStart = -1
		}
		// Brackets outside strings / comments.
		ti := 0
		for i := 0; i < len(line); i += 1 {
			for ti < len(tokens) && tokens[ti].end <= i do ti += 1
			if ti < len(tokens) && tokens[ti].start <= i && (tokens[ti].kind == .String || tokens[ti].kind == .Comment) {
				i = tokens[ti].end - 1
				continue
			}
			switch line[i] {
			case '(', '[', '{':
				append(&bstack, len(s.brackets))
				append(&s.brackets, Code_Bracket{open = {ln, i}, close = {-1, -1}, depth = len(bstack) - 1})
				append(&s.marks, Code_Bracket_Mark{{ln, i}, len(bstack) - 1, false})
			case ')', ']', '}':
				want: u8 = '(' if line[i] == ')' else ('[' if line[i] == ']' else '{')
				// Pop to the matching opener (skips stray ones).
				append(&s.marks, Code_Bracket_Mark{{ln, i}, 0, false})
				closeMark := &s.marks[len(s.marks) - 1]
				for k := len(bstack) - 1; k >= 0; k -= 1 {
					br := &s.brackets[bstack[k]]
					if buf.buffer_line_str(b, br.open.line)[br.open.col] != want do continue
					br.close = {ln, i}
					closeMark.depth, closeMark.matched = br.depth, true
					// Its opener's mark (the last mark at that position).
					for mi := len(s.marks) - 2; mi >= 0; mi -= 1 {
						if s.marks[mi].pos == br.open {s.marks[mi].matched = true; break}
					}
					if want == '{' && br.close.line > br.open.line do append(&s.blocks, Code_Block{.Table, br.open.line, ln, br.open.col})
					resize(&bstack, k)
					break
				}
			}
		}
		if !doc.isLua do continue
		// Block keywords.
		for t in tokens {
			if t.kind != .Keyword do continue
			switch line[t.start:t.end] {
			case "function": append(&opens, Open{.Function, ln, t.start, false})
			case "if": append(&opens, Open{.If, ln, t.start, false})
			case "for": append(&opens, Open{.For, ln, t.start, true})
			case "while": append(&opens, Open{.While, ln, t.start, true})
			case "repeat": append(&opens, Open{.Repeat, ln, t.start, false})
			case "do":
				if len(opens) > 0 && opens[len(opens) - 1].expectDo {
					opens[len(opens) - 1].expectDo = false
				} else {
					append(&opens, Open{.Do, ln, t.start, false})
				}
			case "end", "until":
				if len(opens) == 0 do continue
				o := pop(&opens)
				append(&s.blocks, Code_Block{o.kind, o.line, ln, o.col})
			}
		}
	}
	if commentStart >= 0 && n - 1 > commentStart do append(&s.blocks, Code_Block{.Comment, commentStart, n - 1, 0})
	// By start line (then the outer one first).
	sort_blocks(s.blocks[:])
	return s
}

@(private = "file")
sort_blocks :: proc(blocks: []Code_Block) {
	// Insertion sort: blocks arrive nearly sorted (by end).
	for i in 1 ..< len(blocks) {
		x := blocks[i]
		j := i - 1
		for j >= 0 && (blocks[j].start > x.start || (blocks[j].start == x.start && blocks[j].end < x.end)) {
			blocks[j + 1] = blocks[j]
			j -= 1
		}
		blocks[j + 1] = x
	}
}

// code_bracket_at: the bracket pair with a bracket at p or just before it
// (cached for the caret).
code_bracket_at :: proc(doc: ^Code_Doc, p: buf.Position) -> (Code_Bracket, bool) {
	s := code_structure(doc)
	if s.matchVersion == s.version && s.matchFor == p do return s.match, s.matchOk
	s.matchVersion, s.matchFor, s.matchOk = s.version, p, false
	for br in s.brackets {
		if br.close.line < 0 do continue
		if br.open.line > p.line do break
		if br.close.line < p.line do continue
		for q in ([2]buf.Position{br.open, br.close}) {
			if q.line == p.line && (q.col == p.col || q.col == p.col - 1) {
				s.match, s.matchOk = br, true
				return br, true
			}
		}
	}
	return {}, false
}

// code_marks_from: index of the first bracket mark on or after line.
code_marks_from :: proc(s: ^Code_Structure, line: int) -> int {
	lo, hi := 0, len(s.marks)
	for lo < hi {
		mid := (lo + hi) / 2
		if s.marks[mid].pos.line < line do lo = mid + 1
		else do hi = mid
	}
	return lo
}

// code_block_at: the innermost block (not a comment) containing a line.
code_block_at :: proc(doc: ^Code_Doc, line: int) -> (Code_Block, bool) {
	s := code_structure(doc)
	best: Code_Block
	found := false
	for bl in s.blocks {
		if bl.start > line do break
		if bl.kind == .Comment || bl.end < line || bl.end == bl.start do continue
		if !found || bl.start >= best.start do best, found = bl, true
	}
	return best, found
}

// Code_CmdMatchingBracket (Cmd+Shift+\): to the bracket matching the one at
// the caret; elsewhere, to the closer of the brackets around it.
Code_CmdMatchingBracket :: proc(state: ^EditorState) {
	doc := code_active_doc()
	if doc == nil do return
	b := &doc.buffer
	p := b.cursors[len(b.cursors) - 1].pos
	target: buf.Position
	if br, ok := code_bracket_at(doc, p); ok {
		atOpen := br.open.line == p.line && (br.open.col == p.col || br.open.col == p.col - 1)
		target = br.close if atOpen else br.open
	} else {
		found := false
		for br in code_structure(doc).brackets {
			if br.close.line < 0 do continue
			if buf.position_less(p, {br.open.line, br.open.col + 1}) || buf.position_less(br.close, p) do continue
			target, found = br.close, true // the last one found is the innermost
		}
		if !found do return
	}
	code_set_single_cursor(b, target, false)
	doc.scrollToCursor = true
	code_touched(doc)
}
