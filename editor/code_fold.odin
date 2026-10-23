package editor

import "core:fmt"
import "core:hash"
import "core:slice"
import "core:strings"
import buf "../odin_editor/buffer"
import imgui "lib/imgui"

// ============================================================================
// Code folding: a block (function / if / for / while / repeat / do ... end,
// a multi-line { } table, a run of comment lines - code_structure.odin)
// folds to its first and last line, with a "… N lines" chip after the
// first (the "…" chip). Fold arrows in the gutter (on hover; always when folded), Fold /
// Unfold at the caret, Fold All / Unfold All. Folds follow their first line
// through edits (found again by its text nearby) and are dropped when the
// block is gone.
// ============================================================================

// code_fold_end: the last line of the block folded at ln (folded = true).
code_fold_end :: proc(doc: ^Code_Doc, ln: int) -> (end: int, folded: bool) {
	if len(doc.folds) == 0 || !slice.contains(doc.folds[:], ln) do return 0, false
	if bl, ok := code_foldable_at(doc, ln); ok do return bl.end, true
	return 0, false
}

// code_foldable_at: the outermost block starting on a line that spans more
// than two lines.
code_foldable_at :: proc(doc: ^Code_Doc, ln: int) -> (Code_Block, bool) {
	s := code_structure(doc)
	lo, hi := 0, len(s.blocks)
	for lo < hi {
		mid := (lo + hi) / 2
		if s.blocks[mid].start < ln do lo = mid + 1
		else do hi = mid
	}
	for i := lo; i < len(s.blocks) && s.blocks[i].start == ln; i += 1 {
		if s.blocks[i].end > ln + 1 do return s.blocks[i], true
	}
	return {}, false
}

// code_fold_toggle folds / unfolds the block at ln.
code_fold_toggle :: proc(doc: ^Code_Doc, ln: int) {
	if i, found := slice.linear_search(doc.folds[:], ln); found {
		ordered_remove(&doc.folds, i)
		delete_key(&doc.foldText, ln)
	} else {
		bl, ok := code_foldable_at(doc, ln)
		if !ok do return
		append(&doc.folds, ln)
		doc.foldText[ln] = code_line_hash(&doc.buffer, ln)
		// Carets inside the fold go to its first line.
		b := &doc.buffer
		for &c in b.cursors {
			if c.pos.line > ln && c.pos.line < bl.end {
				c.pos = {ln, buf.buffer_line_len(b, ln)}
				c.sel.active = false
			}
		}
	}
	doc.foldsVersion += 1
}

@(private = "file")
code_line_hash :: proc(b: ^buf.Buffer, ln: int) -> u64 {
	return hash.fnv64a(transmute([]u8)strings.trim_space(buf.buffer_line_str(b, ln)))
}

// code_folds_follow keeps folds on their lines after edits (called when the
// text changed): a fold whose first line moved is found again by its text
// nearby; one whose block is gone is dropped.
code_folds_follow :: proc(doc: ^Code_Doc) {
	if len(doc.folds) == 0 || doc.foldsTextVersion == doc.buffer.version do return
	doc.foldsTextVersion = doc.buffer.version
	b := &doc.buffer
	n := buf.buffer_line_count(b)
	changed := false
	for i := len(doc.folds) - 1; i >= 0; i -= 1 {
		ln := doc.folds[i]
		want := doc.foldText[ln]
		if ln < n && code_line_hash(b, ln) == want {
			if _, ok := code_foldable_at(doc, ln); ok do continue
		}
		moved := -1
		for d in 1 ..= 400 {
			for cand in ([2]int{ln - d, ln + d}) {
				if cand < 0 || cand >= n || moved >= 0 do continue
				if code_line_hash(b, cand) == want {
					if _, ok := code_foldable_at(doc, cand); ok do moved = cand
				}
			}
			if moved >= 0 do break
		}
		delete_key(&doc.foldText, ln)
		if moved >= 0 && !slice.contains(doc.folds[:], moved) {
			doc.folds[i] = moved
			doc.foldText[moved] = want
		} else {
			ordered_remove(&doc.folds, i)
		}
		changed = true
	}
	if changed do doc.foldsVersion += 1
}

// Code_CanFoldAt: a block starts on this line (0-based).
Code_CanFoldAt :: proc(doc: ^Code_Doc, ln: int) -> bool {
	_, ok := code_foldable_at(doc, ln)
	return ok
}

// code_gutter_fold draws a line's fold arrow (at pos, a lineH-high cell):
// on gutter hover, or always when folded; click toggles.
code_gutter_fold :: proc(doc: ^Code_Doc, ln: int, pos: [2]f32, lineH: f32, mouse: [2]f32, gutterHovered: bool) {
	_, folded := code_fold_end(doc, ln)
	if !folded && !(gutterHovered && Code_CanFoldAt(doc, ln)) do return
	dl := imgui.GetWindowDrawList()
	mn, mx := pos, [2]f32{pos.x + 12, pos.y + lineH}
	hot := point_in_rect(mouse, mn, mx)
	col := col_u32(UI_TEXT if hot else UI_TEXT_DIM)
	cx, cy := pos.x + 6, pos.y + lineH * 0.5
	if folded {
		imgui.DrawList_AddTriangleFilled(dl, {cx - 2.5, cy - 4}, {cx - 2.5, cy + 4}, {cx + 3, cy}, col)
	} else {
		imgui.DrawList_AddTriangleFilled(dl, {cx - 4, cy - 2.5}, {cx + 4, cy - 2.5}, {cx, cy + 3}, col)
	}
	Drive_ItemRect(fmt.tprintf("code.fold:%d", ln + 1), mn, mx, inWindow = true)
	if hot && imgui.IsWindowHovered(imgui.HoveredFlags_AllowWhenBlockedByActiveItem) && imgui.IsMouseClicked(.Left) do code_fold_toggle(doc, ln)
}

// Code_CmdFold (Cmd+Alt+[): folds the innermost block around the caret.
Code_CmdFold :: proc(state: ^EditorState) {
	doc := code_active_doc()
	if doc == nil do return
	ln := doc.buffer.cursors[len(doc.buffer.cursors) - 1].pos.line
	best := -1
	for bl in code_structure(doc).blocks {
		if bl.start > ln do break
		if bl.end <= bl.start + 1 || bl.end < ln || slice.contains(doc.folds[:], bl.start) do continue
		best = bl.start // later starts are inner
	}
	if best >= 0 do code_fold_toggle(doc, best)
}

// Code_CmdUnfold (Cmd+Alt+]): unfolds the fold on the caret's line.
Code_CmdUnfold :: proc(state: ^EditorState) {
	doc := code_active_doc()
	if doc == nil do return
	ln := doc.buffer.cursors[len(doc.buffer.cursors) - 1].pos.line
	if slice.contains(doc.folds[:], ln) do code_fold_toggle(doc, ln)
}

// Code_CmdFoldAll: folds every function (and table / comment run) not
// inside another one.
Code_CmdFoldAll :: proc(state: ^EditorState) {
	doc := code_active_doc()
	if doc == nil do return
	coveredTo := -1
	for bl in code_structure(doc).blocks {
		if bl.end <= bl.start + 1 || bl.start <= coveredTo do continue
		if bl.kind != .Function && bl.kind != .Table && bl.kind != .Comment do continue
		if !slice.contains(doc.folds[:], bl.start) do code_fold_toggle(doc, bl.start)
		coveredTo = bl.end
	}
}

Code_CmdUnfoldAll :: proc(state: ^EditorState) {
	doc := code_active_doc()
	if doc == nil do return
	clear(&doc.folds)
	clear(&doc.foldText)
	doc.foldsVersion += 1
}

// --- symbol occurrences / whitespace ---------------------------------------------------

Sym_Range :: struct {
	line, from, to: int,
}

// code_symbol_occurrences: on lines first..last, the other uses of the
// identifier at the caret (not in strings or comments).
code_symbol_occurrences :: proc(doc: ^Code_Doc, first, last: int) -> []Sym_Range {
	b := &doc.buffer
	p := b.cursors[len(b.cursors) - 1].pos
	line := buf.buffer_line_str(b, p.line)
	ident :: proc(ch: u8) -> bool {return ch == '_' || (ch | 0x20 >= 'a' && ch | 0x20 <= 'z') || (ch >= '0' && ch <= '9')}
	s, e := min(p.col, len(line)), min(p.col, len(line))
	for s > 0 && ident(line[s - 1]) do s -= 1
	for e < len(line) && ident(line[e]) do e += 1
	if e - s < 2 do return nil
	word := strings.clone(line[s:e], context.temp_allocator)
	code_update_line_states(doc)
	out := make([dynamic]Sym_Range, context.temp_allocator)
	for ln in first ..= last {
		text := buf.buffer_line_str(b, ln)
		tokens, _ := Token_CacheGet(&doc.tokens, doc.lang, text, doc.lineStates[ln] if ln < len(doc.lineStates) else 0, b.version)
		for t in tokens {
			#partial switch t.kind {
			case .Identifier, .Function, .Property, .Builtin, .Constant, .Type:
				if text[t.start:t.end] == word do append(&out, Sym_Range{ln, t.start, t.end})
			}
		}
	}
	if len(out) < 2 do return nil // only itself
	return out[:]
}

// code_in_selection: p is inside one of the selections.
code_in_selection :: proc(b: ^buf.Buffer, p: buf.Position) -> bool {
	for c in b.cursors {
		s, e, ok := buf.selection_range(c)
		if ok && !buf.position_less(p, s) && buf.position_less(p, e) do return true
	}
	return false
}

// Code_CmdToggleSoftWrap (Alt+Z).
Code_CmdToggleSoftWrap :: proc(state: ^EditorState) {
	GlobalSettings.softWrap = !GlobalSettings.softWrap
	_ = Editor_SaveSettings()
	if doc := code_active_doc(); doc != nil do doc.scrollToCursor = true
}
