package editor

import "core:fmt"
import "core:slice"
import "core:strings"
import "core:text/regex"
import "core:time"
import buf "../odin_editor/buffer"
import lsp "../odin_editor/lsp"
import imgui "lib/imgui"

// ============================================================================
// Code editor commands (bound in actions.odin, Zed-style shortcuts): find
// and replace, multi-cursor, line operations, LSP rename / format /
// references, font size and tab management.
// ============================================================================

Code_Find :: struct {
	open:          bool,
	replace:       bool,
	query:         [256]u8,
	replacement:   [256]u8,
	caseSensitive: bool,
	wholeWord:     bool,
	regex:         bool,
	focusQuery:    bool, // put the caret in the query field next frame
	focused:       bool, // a find-bar field had focus (last frame)
	badRegex:      bool,
}

Code_Match :: struct {
	start, end: buf.Position,
}

CODE_MAX_MATCHES :: 10000

code_active_doc :: proc() -> ^Code_Doc {
	cm := &GlobalCode
	if cm.active < 0 || cm.active >= len(cm.docs) do return nil
	return cm.docs[cm.active]
}

Code_FindBarFocused :: proc() -> bool {
	return GlobalCode.find.open && GlobalCode.find.focused
}

code_find_destroy :: proc() {}

code_font_size :: proc() -> f32 {
	return GlobalCode.fontSize if GlobalCode.fontSize > 0 else CODE_FONT_SIZE
}

// code_touched: common bookkeeping after a command moved/edited carets.
@(private = "file")
code_touched :: proc(doc: ^Code_Doc) {
	cm := &GlobalCode
	code_merge_cursors(&doc.buffer)
	cm.cursorMoved = time.tick_now()
	cm.completion.open = false
	doc.scrollToCursor = true
}

// --- matching ----------------------------------------------------------------------

@(private = "file")
word_ok :: proc(line: string, a, b: int) -> bool {
	return (a == 0 || !code_is_ident_byte(line[a - 1])) && (b >= len(line) || !code_is_ident_byte(line[b]))
}

// code_find_matches: every single-line match of `query` in the buffer.
code_find_matches :: proc(b: ^buf.Buffer, query: string, caseSensitive, wholeWord, useRegex: bool) -> (out: [dynamic]Code_Match, badRegex: bool) {
	out = make([dynamic]Code_Match, context.temp_allocator)
	if query == "" do return
	if useRegex {
		flags: regex.Flags = {.Unicode}
		if !caseSensitive do flags += {.Case_Insensitive}
		re, err := regex.create(query, flags)
		if err != nil do return out, true
		defer regex.destroy(re)
		for ln in 0 ..< buf.buffer_line_count(b) {
			line := buf.buffer_line_str(b, ln)
			off := 0
			for off <= len(line) && len(out) < CODE_MAX_MATCHES {
				cap, ok := regex.match(re, line[off:], context.temp_allocator)
				if !ok || len(cap.pos) == 0 do break
				s, e_ := off + cap.pos[0][0], off + cap.pos[0][1]
				if !wholeWord || word_ok(line, s, e_) do append(&out, Code_Match{{ln, s}, {ln, e_}})
				off = e_ if e_ > s else e_ + 1
			}
		}
		return
	}
	for ln in 0 ..< buf.buffer_line_count(b) {
		line := buf.buffer_line_str(b, ln)
		for i := 0; i + len(query) <= len(line) && len(out) < CODE_MAX_MATCHES; {
			cand := line[i:i + len(query)]
			hit := cand == query if caseSensitive else strings.equal_fold(cand, query)
			if hit && (!wholeWord || word_ok(line, i, i + len(query))) {
				append(&out, Code_Match{{ln, i}, {ln, i + len(query)}})
				i += len(query)
			} else {
				i += 1
			}
		}
	}
	return
}

@(private = "file")
find_query :: proc() -> string {
	return string(cstring(raw_data(GlobalCode.find.query[:])))
}

code_find_all :: proc(doc: ^Code_Doc) -> [dynamic]Code_Match {
	f := &GlobalCode.find
	m, bad := code_find_matches(&doc.buffer, find_query(), f.caseSensitive, f.wholeWord, f.regex)
	f.badRegex = bad
	return m
}

// code_find_visible_matches: matches on lines first..last (for highlighting).
code_find_visible_matches :: proc(doc: ^Code_Doc, first, last: int) -> []Code_Match {
	if !GlobalCode.find.open || find_query() == "" do return nil
	all := code_find_all(doc)
	out := make([dynamic]Code_Match, context.temp_allocator)
	for m in all do if m.start.line >= first && m.start.line <= last do append(&out, m)
	return out[:]
}

// --- find bar ----------------------------------------------------------------------

Code_CmdFind :: proc(state: ^EditorState, replace: bool) {
	doc := code_active_doc()
	if doc == nil do return
	f := &GlobalCode.find
	f.open = true
	f.replace = replace
	f.focusQuery = true
	// Seed with the selection (single line) or the word under the caret.
	b := &doc.buffer
	c := code_primary(b)
	text := ""
	if s, e_, ok := buf.selection_range(c^); ok && s.line == e_.line {
		text = buf.buffer_line_str(b, s.line)[s.col:e_.col]
	} else {
		line := buf.buffer_line_str(b, c.pos.line)
		ws := code_word_start(b, c.pos)
		we := c.pos.col
		for we < len(line) && code_is_ident_byte(line[we]) do we += 1
		if we > ws.col do text = line[ws.col:we]
	}
	if text != "" {
		f.query = {}
		copy(f.query[:len(f.query) - 1], text)
	}
}

// Code_CmdFindStep selects the next (dir 1) / previous (-1) match.
Code_CmdFindStep :: proc(state: ^EditorState, dir: int) {
	doc := code_active_doc()
	if doc == nil do return
	f := &GlobalCode.find
	if find_query() == "" {
		Code_CmdFind(state, false)
		if find_query() == "" do return
	}
	f.open = true
	matches := code_find_all(doc)
	if len(matches) == 0 do return
	b := &doc.buffer
	c := code_primary(b)
	from := c.pos
	if s, e_, ok := buf.selection_range(c^); ok do from = e_ if dir > 0 else s
	idx := -1
	if dir > 0 {
		for m, i in matches do if !buf.position_less(m.start, from) {idx = i; break}
		if idx < 0 do idx = 0
	} else {
		for i := len(matches) - 1; i >= 0; i -= 1 do if buf.position_less(matches[i].start, from) {idx = i; break}
		if idx < 0 do idx = len(matches) - 1
	}
	m := matches[idx]
	code_set_single_cursor(b, m.start, false)
	b.cursors[0].sel = {anchor = m.start, active = true}
	b.cursors[0].pos = m.end
	code_touched(doc)
}

@(private = "file")
code_find_index :: proc(doc: ^Code_Doc, matches: []Code_Match) -> int {
	c := code_primary(&doc.buffer)^
	s, e_, ok := buf.selection_range(c)
	if !ok do return -1
	for m, i in matches do if m.start == s && m.end == e_ do return i
	return -1
}

@(private = "file")
replacement_for :: proc(doc: ^Code_Doc, m: Code_Match) -> string {
	f := &GlobalCode.find
	rep := string(cstring(raw_data(f.replacement[:])))
	if !f.regex do return rep
	// $0 / $1.. capture references.
	line := buf.buffer_line_str(&doc.buffer, m.start.line)
	flags: regex.Flags = {.Unicode}
	if !f.caseSensitive do flags += {.Case_Insensitive}
	re, err := regex.create(find_query(), flags)
	if err != nil do return rep
	defer regex.destroy(re)
	cap, ok := regex.match(re, line[m.start.col:m.end.col], context.temp_allocator)
	if !ok do return rep
	sb := strings.builder_make(context.temp_allocator)
	for i := 0; i < len(rep); i += 1 {
		if rep[i] == '$' && i + 1 < len(rep) && rep[i + 1] >= '0' && rep[i + 1] <= '9' {
			n := int(rep[i + 1] - '0')
			if n < len(cap.groups) do strings.write_string(&sb, cap.groups[n])
			i += 1
			continue
		}
		strings.write_byte(&sb, rep[i])
	}
	return strings.to_string(sb)
}

Code_CmdReplaceCurrent :: proc(state: ^EditorState) {
	doc := code_active_doc()
	if doc == nil do return
	matches := code_find_all(doc)
	idx := code_find_index(doc, matches[:])
	if idx < 0 {
		Code_CmdFindStep(state, 1)
		return
	}
	m := matches[idx]
	b := &doc.buffer
	rep := replacement_for(doc, m)
	group := buf.buffer_next_group(b)
	buf.buffer_delete_range(b, m.start, m.end, group)
	end := buf.buffer_insert_text(b, m.start, rep, group)
	code_set_single_cursor(b, end, false)
	Code_CmdFindStep(state, 1)
}

Code_CmdReplaceAll :: proc(state: ^EditorState) -> int {
	doc := code_active_doc()
	if doc == nil do return 0
	matches := code_find_all(doc)
	if len(matches) == 0 do return 0
	b := &doc.buffer
	reps := make([]string, len(matches), context.temp_allocator)
	for m, i in matches do reps[i] = replacement_for(doc, m)
	group := buf.buffer_next_group(b)
	for i := len(matches) - 1; i >= 0; i -= 1 {
		buf.buffer_delete_range(b, matches[i].start, matches[i].end, group)
		buf.buffer_insert_text(b, matches[i].start, reps[i], group)
	}
	code_set_single_cursor(b, buf.buffer_clamp_position(b, matches[0].start), false)
	code_touched(doc)
	Editor_Log(state, .Info, "Replaced %d occurrence(s)", len(matches))
	return len(matches)
}

// code_find_bar draws the find (and replace) bar above the text.
code_find_bar :: proc(state: ^EditorState, doc: ^Code_Doc) {
	cm := &GlobalCode
	f := &cm.find
	if !f.open {
		f.focused = false
		return
	}
	imgui.PushStyleVarImVec2(.FramePadding, {8, 5})
	defer imgui.PopStyleVar()
	imgui.SetCursorPosX(UI_SPACE)
	imgui.SetCursorPosY(imgui.GetCursorPosY() + 4)
	anyFocused := false
	matches := code_find_all(doc)
	idx := code_find_index(doc, matches[:])

	if f.focusQuery {
		imgui.SetKeyboardFocusHere()
		f.focusQuery = false
	}
	imgui.SetNextItemWidth(260)
	enter := imgui.InputTextWithHint("##code_find", "Find", cstring(raw_data(f.query[:])), len(f.query), {.EnterReturnsTrue})
	Drive_Item("code.find-input")
	if imgui.IsItemActive() do anyFocused = true
	shift := imgui.GetIO().KeyShift
	if enter {
		Code_CmdFindStep(state, -1 if shift else 1)
		f.focusQuery = true
	}
	imgui.SameLine(0, 4)
	toggle :: proc(label: string, id: string, v: ^bool, tip: string) {
		if UI_IconButton(label, id, tip, v^, 26) do v^ = !v^
	}
	toggle("Aa", "code.find-case", &f.caseSensitive, "Match case")
	imgui.SameLine(0, 2)
	toggle("ab", "code.find-word", &f.wholeWord, "Whole word")
	imgui.SameLine(0, 2)
	toggle(".*", "code.find-regex", &f.regex, "Regular expression")
	imgui.SameLine(0, UI_SPACE)
	imgui.AlignTextToFramePadding()
	switch {
	case f.badRegex:            imgui.PushStyleColorImVec4(.Text, UI_DANGER); imgui.TextUnformatted("Invalid regex"); imgui.PopStyleColor()
	case find_query() == "":    UI_DimText("")
	case len(matches) == 0:     imgui.PushStyleColorImVec4(.Text, UI_WARNING); imgui.TextUnformatted("No results"); imgui.PopStyleColor()
	case idx >= 0:              UI_DimText(fmt.tprintf("%d of %d", idx + 1, len(matches)))
	case:                       UI_DimText(fmt.tprintf("%d matches", len(matches)))
	}
	imgui.SameLine(0, UI_SPACE)
	if UI_IconButton(ICON_FA_ARROW_UP, "code.find-prev", "Previous (Shift+Enter)", size = 26) do Code_CmdFindStep(state, -1)
	imgui.SameLine(0, 2)
	if UI_IconButton(ICON_FA_ARROW_DOWN, "code.find-next", "Next (Enter)", size = 26) do Code_CmdFindStep(state, 1)
	imgui.SameLine(0, 2)
	if UI_IconButton(ICON_FA_RIGHT_LEFT, "code.find-toggle-replace", "Replace", f.replace, 26) do f.replace = !f.replace
	imgui.SameLine(0, 2)
	if UI_IconButton(ICON_FA_XMARK, "code.find-close", "Close (Esc)", size = 26) {
		f.open = false
		cm.focusRequest = true
	}
	if f.replace {
		imgui.SetCursorPosX(UI_SPACE)
		imgui.SetNextItemWidth(260)
		renter := imgui.InputTextWithHint("##code_replace", "Replace", cstring(raw_data(f.replacement[:])), len(f.replacement), {.EnterReturnsTrue})
		Drive_Item("code.replace-input")
		if imgui.IsItemActive() do anyFocused = true
		if renter do Code_CmdReplaceCurrent(state)
		imgui.SameLine(0, 4)
		if UI_Button("Replace", "code.replace-one") do Code_CmdReplaceCurrent(state)
		imgui.SameLine(0, 4)
		if UI_Button("Replace All", "code.replace-all") do Code_CmdReplaceAll(state)
	}
	if (anyFocused || (cm.windowFocused && !cm.focused)) && imgui.IsKeyPressed(.Escape, false) {
		f.open = false
		cm.focusRequest = true
		anyFocused = false
	}
	f.focused = anyFocused
	imgui.Dummy({0, 2})
}

// --- multi-cursor ------------------------------------------------------------------

Code_CmdAddCursor :: proc(state: ^EditorState, dir: int) {
	doc := code_active_doc()
	if doc == nil do return
	b := &doc.buffer
	last := code_primary(b)^
	target := last.pos.line + dir
	if target < 0 || target >= buf.buffer_line_count(b) do return
	srcLine := buf.buffer_line_str(b, last.pos.line)
	vcol := code_visual_col(srcLine, last.pos.col)
	col := code_byte_col(buf.buffer_line_str(b, target), vcol)
	append(&b.cursors, buf.Cursor{pos = {target, col}})
	code_touched(doc)
}

// Code_CmdSelectNextOccurrence (Cmd+D): selects the word under the caret,
// then adds a cursor at each next occurrence.
Code_CmdSelectNextOccurrence :: proc(state: ^EditorState) {
	doc := code_active_doc()
	if doc == nil do return
	b := &doc.buffer
	last := code_primary(b)
	ls, le, ok := buf.selection_range(last^)
	if !ok {
		buf.cursor_select_word(b, last)
		code_touched(doc)
		return
	}
	if ls.line != le.line do return
	needle := buf.buffer_line_str(b, ls.line)[ls.col:le.col]
	matches, _ := code_find_matches(b, needle, true, false, false)
	if len(matches) == 0 do return
	start := 0
	for m, i in matches {
		if !buf.position_less(m.start, le) {start = i; break}
		start = (i + 1) % len(matches)
	}
	for k in 0 ..< len(matches) {
		m := matches[(start + k) % len(matches)]
		taken := false
		for c in b.cursors {
			cs, ce, has := buf.selection_range(c)
			if has && cs == m.start && ce == m.end {taken = true; break}
		}
		if !taken {
			append(&b.cursors, buf.Cursor{pos = m.end, sel = {anchor = m.start, active = true}})
			code_touched(doc)
			return
		}
	}
}

Code_CmdSelectAllOccurrences :: proc(state: ^EditorState) {
	doc := code_active_doc()
	if doc == nil do return
	b := &doc.buffer
	c := code_primary(b)
	whole := false
	if _, _, ok := buf.selection_range(c^); !ok {
		buf.cursor_select_word(b, c)
		whole = true
	}
	s, e_, ok := buf.selection_range(c^)
	if !ok || s.line != e_.line do return
	needle := buf.buffer_line_str(b, s.line)[s.col:e_.col]
	matches, _ := code_find_matches(b, needle, true, whole, false)
	if len(matches) == 0 do return
	clear(&b.cursors)
	for m in matches do append(&b.cursors, buf.Cursor{pos = m.end, sel = {anchor = m.start, active = true}})
	code_touched(doc)
}

// --- editing -----------------------------------------------------------------------

Code_CmdSave :: proc(state: ^EditorState) {
	Lua_MarkProjectTypesDirty() // generated Lua types follow the project
	doc := code_active_doc()
	if doc == nil do return
	// Format on save: format first, save when the edits arrive.
	if GlobalSettings.formatOnSave && doc.isLua && GlobalCode.lspState == .Ready {
		GlobalCode.saveAfterFormat = doc
		Code_CmdFormat(state)
		return
	}
	Code_SaveDoc(state, doc)
}

Code_CmdClose :: proc(state: ^EditorState) {
	code_request_close(GlobalCode.active)
}

Code_CmdReopen :: proc(state: ^EditorState) {
	cm := &GlobalCode
	for len(cm.closedFiles) > 0 {
		path := pop(&cm.closedFiles)
		defer delete(path)
		if Editor_OpenScript(state, path) do return
	}
}

Code_CmdCycleTab :: proc(dir: int) {
	cm := &GlobalCode
	if len(cm.docs) < 2 do return
	cm.active = (cm.active + dir + len(cm.docs)) % len(cm.docs)
	cm.selectRequest = cm.active
	cm.focusRequest = true
}

Code_CmdUndo :: proc(state: ^EditorState) {
	if doc := code_active_doc(); doc != nil {
		buf.buffer_undo(&doc.buffer)
		code_touched(doc)
	}
}

Code_CmdRedo :: proc(state: ^EditorState) {
	if doc := code_active_doc(); doc != nil {
		buf.buffer_redo(&doc.buffer)
		code_touched(doc)
	}
}

Code_CmdCopy :: proc(cut: bool) {
	doc := code_active_doc()
	if doc == nil do return
	b := &doc.buffer
	// Every cursor's selection, one per line; no selection = whole lines.
	sb := strings.builder_make(context.temp_allocator)
	anySel := false
	for c in b.cursors do if _, _, ok := buf.selection_range(c); ok do anySel = true
	order := buf.buffer_sorted_cursor_indices(b)
	for i, n in order {
		c := b.cursors[i]
		if n > 0 do strings.write_byte(&sb, '\n')
		if anySel {
			s, e_, ok := buf.selection_range(c)
			if !ok do continue
			for ln in s.line ..= e_.line {
				line := buf.buffer_line_str(b, ln)
				from := s.col if ln == s.line else 0
				to := e_.col if ln == e_.line else len(line)
				strings.write_string(&sb, line[min(from, len(line)):min(to, len(line))])
				if ln != e_.line do strings.write_byte(&sb, '\n')
			}
		} else {
			strings.write_string(&sb, buf.buffer_line_str(b, c.pos.line))
		}
	}
	if !anySel do strings.write_byte(&sb, '\n')
	imgui.SetClipboardText(strings.clone_to_cstring(strings.to_string(sb), context.temp_allocator))
	if cut {
		if anySel do buf.buffer_backspace(b)
		else do buf.buffer_delete_lines(b)
		code_touched(doc)
	}
}

Code_CmdPaste :: proc(state: ^EditorState) {
	doc := code_active_doc()
	if doc == nil do return
	clip := imgui.GetClipboardText()
	if clip == nil do return
	text, _ := strings.replace_all(string(clip), "\r\n", "\n", context.temp_allocator)
	b := &doc.buffer
	// One line per cursor: distribute (VSCode/Zed).
	lines := strings.split(strings.trim_suffix(text, "\n"), "\n", context.temp_allocator)
	if len(b.cursors) > 1 && len(lines) == len(b.cursors) {
		group := buf.buffer_next_group(b)
		order := buf.buffer_sorted_cursor_indices(b)
		// Insert from the bottom so earlier positions stay valid.
		#reverse for i, n in order {
			c := &b.cursors[i]
			if s, e_, ok := buf.selection_range(c^); ok {
				buf.buffer_delete_range(b, s, e_, group)
				c.pos = s
				c.sel.active = false
			}
			c.pos = buf.buffer_insert_text(b, c.pos, lines[n], group)
		}
	} else {
		buf.buffer_type_text(b, text)
	}
	code_touched(doc)
}

Code_CmdSelectAll :: proc(state: ^EditorState) {
	if doc := code_active_doc(); doc != nil {
		b := &doc.buffer
		code_set_single_cursor(b, b.cursors[0].pos, false)
		buf.cursor_select_all(b, &b.cursors[0])
		GlobalCode.cursorMoved = time.tick_now()
	}
}

// Code_CmdSelectLine (Cmd+L): selects the line; again extends by a line.
Code_CmdSelectLine :: proc(state: ^EditorState) {
	doc := code_active_doc()
	if doc == nil do return
	b := &doc.buffer
	for &c in b.cursors {
		if s, e_, ok := buf.selection_range(c); ok && s.col == 0 && e_.col == 0 && e_.line > s.line {
			if e_.line < buf.buffer_line_count(b) - 1 {
				c.pos = {e_.line + 1, 0}
			} else {
				c.pos = {e_.line, buf.buffer_line_len(b, e_.line)}
			}
			continue
		}
		ln := c.pos.line
		c.sel = {anchor = {ln, 0}, active = true}
		c.pos = {ln + 1, 0} if ln < buf.buffer_line_count(b) - 1 else {ln, buf.buffer_line_len(b, ln)}
	}
	code_touched(doc)
}

Code_CmdToggleComment :: proc(state: ^EditorState) {
	if doc := code_active_doc(); doc != nil {
		buf.buffer_toggle_line_comment(&doc.buffer, doc.lang.line_comment)
		code_touched(doc)
	}
}

// Code_CmdIndent (Cmd+]) indents the caret lines (with or without a selection).
Code_CmdIndent :: proc(state: ^EditorState) {
	doc := code_active_doc()
	if doc == nil do return
	b := &doc.buffer
	pad := "\t" if doc.useTabs else "    "
	group := buf.buffer_next_group(b)
	done := make(map[int]bool, 16, context.temp_allocator)
	lines := make([dynamic]int, context.temp_allocator)
	for c in b.cursors {
		first, last := c.pos.line, c.pos.line
		if s, e_, ok := buf.selection_range(c); ok {
			first, last = s.line, e_.line
			if e_.col == 0 && e_.line > s.line do last -= 1
		}
		for ln in first ..= last do if !done[ln] {done[ln] = true; append(&lines, ln)}
	}
	slice.sort(lines[:])
	#reverse for ln in lines do buf.buffer_insert_text(b, {ln, 0}, pad, group)
	for &c in b.cursors {
		if done[c.pos.line] && c.pos.col > 0 || done[c.pos.line] && !c.sel.active do c.pos.col += len(pad)
		if c.sel.active && done[c.sel.anchor.line] && c.sel.anchor.col > 0 do c.sel.anchor.col += len(pad)
	}
	code_touched(doc)
}

Code_CmdOutdent :: proc(state: ^EditorState) {
	if doc := code_active_doc(); doc != nil {
		buf.buffer_outdent(&doc.buffer)
		code_touched(doc)
	}
}

Code_CmdMoveLines :: proc(state: ^EditorState, dir: int) {
	if doc := code_active_doc(); doc != nil {
		buf.buffer_move_lines(&doc.buffer, dir)
		code_touched(doc)
	}
}

Code_CmdDuplicate :: proc(state: ^EditorState, down: bool) {
	if doc := code_active_doc(); doc != nil {
		buf.buffer_duplicate_lines(&doc.buffer, down)
		code_touched(doc)
	}
}

Code_CmdDeleteLine :: proc(state: ^EditorState) {
	if doc := code_active_doc(); doc != nil {
		buf.buffer_delete_lines(&doc.buffer)
		code_touched(doc)
	}
}

Code_CmdInsertLine :: proc(state: ^EditorState, above: bool) {
	if doc := code_active_doc(); doc != nil {
		buf.buffer_insert_line(&doc.buffer, above)
		code_touched(doc)
	}
}

// Code_CmdJoinLines (Ctrl+J) joins each caret line with the next.
Code_CmdJoinLines :: proc(state: ^EditorState) {
	doc := code_active_doc()
	if doc == nil do return
	b := &doc.buffer
	group := buf.buffer_next_group(b)
	order := buf.buffer_sorted_cursor_indices(b)
	#reverse for i in order {
		c := &b.cursors[i]
		ln := c.pos.line
		if ln >= buf.buffer_line_count(b) - 1 do continue
		cur := buf.buffer_line_str(b, ln)
		next := buf.buffer_line_str(b, ln + 1)
		ws := 0
		for ws < len(next) && (next[ws] == ' ' || next[ws] == '\t') do ws += 1
		trimmedEnd := len(strings.trim_right_space(cur))
		buf.buffer_delete_range(b, {ln, trimmedEnd}, {ln + 1, ws}, group)
		sep := " " if trimmedEnd > 0 && ws < len(next) else ""
		buf.buffer_insert_text(b, {ln, trimmedEnd}, sep, group)
		c.pos = {ln, trimmedEnd}
		c.sel.active = false
	}
	code_touched(doc)
}

Code_CmdDeleteToLineStart :: proc(state: ^EditorState) {
	doc := code_active_doc()
	if doc == nil do return
	b := &doc.buffer
	group := buf.buffer_next_group(b)
	order := buf.buffer_sorted_cursor_indices(b)
	#reverse for i in order {
		c := &b.cursors[i]
		if c.pos.col == 0 do continue
		buf.buffer_delete_range(b, {c.pos.line, 0}, c.pos, group)
		c.pos.col = 0
		c.sel.active = false
	}
	code_touched(doc)
}

Code_CmdFontSize :: proc(state: ^EditorState, delta: int) {
	cm := &GlobalCode
	if delta == 0 {
		cm.fontSize = 0
		return
	}
	cm.fontSize = clamp(code_font_size() + f32(delta), 9, 32)
}

// --- LSP-backed commands -----------------------------------------------------------

Code_CmdComplete :: proc(state: ^EditorState) {
	if doc := code_active_doc(); doc != nil do code_lsp_request_completion(doc, true)
}

Code_CmdSignature :: proc(state: ^EditorState) {
	if doc := code_active_doc(); doc != nil do code_lsp_request_signature(doc)
}

Code_CmdDefinition :: proc(state: ^EditorState) {
	if doc := code_active_doc(); doc != nil do code_lsp_goto_definition(doc)
}

Code_CmdReferences :: proc(state: ^EditorState) {
	cm := &GlobalCode
	doc := code_active_doc()
	if doc == nil || cm.lspState != .Ready || !doc.isLua do return
	code_lsp_sync(doc)
	p := code_primary(&doc.buffer).pos
	cm.refsSeq = cm.client.location_seq
	lsp.client_request_references(&cm.client, doc.uri, p.line, code_u16_col(buf.buffer_line_str(&doc.buffer, p.line), p.col))
	cm.refsWaiting = true
	cm.defWaiting = false
}

Code_CmdFormat :: proc(state: ^EditorState) {
	cm := &GlobalCode
	doc := code_active_doc()
	if doc == nil || cm.lspState != .Ready || !doc.isLua do return
	code_lsp_sync(doc)
	cm.editsSeq = cm.client.edit_seq
	cm.formatDoc = doc
	lsp.client_request_formatting(&cm.client, doc.uri, 4, !doc.useTabs)
	cm.editsWaiting = true
}

Code_CmdRename :: proc(state: ^EditorState) {
	cm := &GlobalCode
	doc := code_active_doc()
	if doc == nil || !doc.isLua do return
	b := &doc.buffer
	p := code_primary(b).pos
	ws := code_word_start(b, p)
	line := buf.buffer_line_str(b, p.line)
	we := p.col
	for we < len(line) && code_is_ident_byte(line[we]) do we += 1
	if we <= ws.col do return
	cm.renameBuf = {}
	copy(cm.renameBuf[:len(cm.renameBuf) - 1], line[ws.col:we])
	cm.renamePos = ws
	cm.renameDoc = doc
	cm.renameOpen = true
}

// code_rename_popup asks for the new name (F2), then requests the edits.
code_rename_popup :: proc(state: ^EditorState) {
	cm := &GlobalCode
	if cm.renameOpen {
		imgui.OpenPopup("Rename Symbol###CodeRename")
		cm.renameOpen = false
	}
	if cm.renameDoc != nil {
		p := code_screen_pos(&cm.renameDoc.buffer, cm.renamePos)
		imgui.SetNextWindowPos({p.x, p.y + cm.lineH + 2}, .Appearing)
	}
	if !imgui.BeginPopup("Rename Symbol###CodeRename") do return
	if imgui.IsWindowAppearing() do imgui.SetKeyboardFocusHere()
	imgui.SetNextItemWidth(240)
	enter := imgui.InputText("##code_rename", cstring(raw_data(cm.renameBuf[:])), len(cm.renameBuf), {.EnterReturnsTrue, .AutoSelectAll})
	Drive_Item("code.rename-input")
	if enter && cm.renameDoc != nil && cm.lspState == .Ready {
		doc := cm.renameDoc
		code_lsp_sync(doc)
		line := buf.buffer_line_str(&doc.buffer, cm.renamePos.line)
		cm.editsSeq = cm.client.edit_seq
		lsp.client_request_rename(&cm.client, doc.uri, cm.renamePos.line, code_u16_col(line, cm.renamePos.col), string(cstring(raw_data(cm.renameBuf[:]))))
		cm.editsWaiting = true
		imgui.CloseCurrentPopup()
		cm.focusRequest = true
	}
	if imgui.IsKeyPressed(.Escape, false) {
		imgui.CloseCurrentPopup()
		cm.focusRequest = true
	}
	imgui.EndPopup()
}

// code_doc_for_key finds (or opens, without focusing) the document for an
// LSP uri_key ("" = the document being formatted).
@(private = "file")
code_doc_for_key :: proc(state: ^EditorState, key: string) -> ^Code_Doc {
	cm := &GlobalCode
	if key == "" do return cm.formatDoc
	for d in cm.docs {
		if d.path == key || lsp.uri_key(d.uri, context.temp_allocator) == key do return d
	}
	active, sel, focus := cm.active, cm.selectRequest, cm.focusRequest
	if !Editor_OpenScript(state, key) do return nil
	doc := cm.docs[len(cm.docs) - 1]
	cm.active, cm.selectRequest, cm.focusRequest = active, sel, focus
	return doc
}

// code_apply_edits applies the client's last rename/format edits.
code_apply_edits :: proc(state: ^EditorState) {
	cm := &GlobalCode
	edits := cm.client.last_edits[:]
	if len(edits) == 0 {
		if cm.client.edits_kind == .Rename do Editor_Log(state, .Info, "Nothing to rename here")
		return
	}
	keys := make([dynamic]string, context.temp_allocator)
	for e_ in edits do if !slice.contains(keys[:], e_.key) do append(&keys, e_.key)
	files := 0
	for key in keys {
		doc := code_doc_for_key(state, key)
		if doc == nil do continue
		b := &doc.buffer
		list := make([dynamic]lsp.Code_Action_Edit, context.temp_allocator)
		for e_ in edits do if e_.key == key do append(&list, e_)
		// Bottom-up so earlier ranges stay valid.
		slice.sort_by(list[:], proc(x, y: lsp.Code_Action_Edit) -> bool {
			if x.range.start.line != y.range.start.line do return x.range.start.line > y.range.start.line
			return x.range.start.character > y.range.start.character
		})
		group := buf.buffer_next_group(b)
		for e_ in list {
			sl := buf.buffer_line_str(b, min(e_.range.start.line, buf.buffer_line_count(b) - 1))
			el := buf.buffer_line_str(b, min(e_.range.end.line, buf.buffer_line_count(b) - 1))
			s := buf.buffer_clamp_position(b, {e_.range.start.line, code_byte_from_u16(sl, e_.range.start.character)})
			en := buf.buffer_clamp_position(b, {e_.range.end.line, code_byte_from_u16(el, e_.range.end.character)})
			if s != en do buf.buffer_delete_range(b, s, en, group)
			if e_.new_text != "" do buf.buffer_insert_text(b, s, e_.new_text, group)
		}
		for &c in b.cursors do c.pos = buf.buffer_clamp_position(b, c.pos)
		files += 1
	}
	if cm.client.edits_kind == .Rename do Editor_Log(state, .Info, "Renamed %d occurrence(s) in %d file(s)", len(edits), files)
}

// code_commands_update handles LSP answers for the commands above.
code_commands_update :: proc(state: ^EditorState) {
	cm := &GlobalCode
	if cm.lspState != .Ready do return
	if cm.editsWaiting && cm.client.edit_seq != cm.editsSeq {
		cm.editsWaiting = false
		code_apply_edits(state)
		if cm.saveAfterFormat != nil {
			Code_SaveDoc(state, cm.saveAfterFormat)
			cm.saveAfterFormat = nil
		}
	}
	if cm.refsWaiting && cm.client.location_seq != cm.refsSeq {
		cm.refsWaiting = false
		Palette_ShowLocations(state, "References", cm.client.last_locations[:])
	}
}
