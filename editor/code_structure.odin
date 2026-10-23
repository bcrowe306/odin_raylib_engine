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

Code_Structure :: struct {
	version:  int,
	valid:    bool,
	brackets: [dynamic]Code_Bracket, // in order of their opener
	blocks:   [dynamic]Code_Block,   // in order of their start
}

code_structure_destroy :: proc(s: ^Code_Structure) {
	delete(s.brackets)
	delete(s.blocks)
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
	s.version = b.version
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
			case ')', ']', '}':
				want: u8 = '(' if line[i] == ')' else ('[' if line[i] == ']' else '{')
				// Pop to the matching opener (skips stray ones).
				for k := len(bstack) - 1; k >= 0; k -= 1 {
					br := &s.brackets[bstack[k]]
					if buf.buffer_line_str(b, br.open.line)[br.open.col] != want do continue
					br.close = {ln, i}
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

// code_bracket_at: the bracket pair with a bracket at p or just before it.
code_bracket_at :: proc(doc: ^Code_Doc, p: buf.Position) -> (Code_Bracket, bool) {
	s := code_structure(doc)
	for br in s.brackets {
		if br.close.line < 0 do continue
		for q in ([2]buf.Position{br.open, br.close}) {
			if q.line == p.line && (q.col == p.col || q.col == p.col - 1) do return br, true
		}
	}
	return {}, false
}
