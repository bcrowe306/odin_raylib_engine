package editor

import "core:fmt"
import "core:strings"
import buf "../odin_editor/buffer"

// ============================================================================
// Refactors (Refactor submenu / palette):
//
//   Extract Local (Cmd+Alt+V)     the selected expression -> `local value =`
//                                 above the statement; both names selected
//   Extract Method (Cmd+Alt+M)    the selected lines -> `function Cls:new_method()`
//                                 after the current function, a call in their place
//   Inline Variable (Cmd+Alt+N)   `local x = expr` -> expr at its uses (to the
//                                 end of its block), the declaration removed
//   Toggle Property Access        node:get_property("p") <-> node.p,
//                                 node:set_property("p", v) <-> node.p = v
//   Toggle Vec2                   {x, y} <-> Vec2(x, y)
//
// Extract leaves a cursor on each copy of the new name: type to rename both.
// ============================================================================

@(private = "file")
indent_of :: proc(line: string) -> string {return line[:len(line) - len(strings.trim_left(line, " \t"))]}

@(private = "file")
unit_of :: proc(doc: ^Code_Doc) -> string {
	return "\t" if doc.useTabs else strings.repeat(" ", code_tab_width(), context.temp_allocator)
}

// Code_CmdExtractLocal: the selection (one line) becomes a local.
Code_CmdExtractLocal :: proc(state: ^EditorState) {
	doc := code_active_doc()
	if doc == nil do return
	b := &doc.buffer
	s, e, ok := buf.selection_range(b.cursors[len(b.cursors) - 1])
	if !ok || s.line != e.line {
		Editor_Log(state, .Info, "Select an expression on one line to extract it")
		return
	}
	line := strings.clone(buf.buffer_line_str(b, s.line), context.temp_allocator)
	expr := strings.trim_space(line[s.col:e.col])
	name := "value"
	ind := indent_of(line)
	group := buf.buffer_next_group(b)
	buf.buffer_delete_range(b, s, e, group)
	buf.buffer_insert_text(b, s, name, group)
	decl := fmt.tprintf("%slocal %s = %s\n", ind, name, expr)
	buf.buffer_insert_text(b, {s.line, 0}, decl, group)
	// Two cursors on the names: typing renames both.
	clear(&b.cursors)
	dcol := len(ind) + len("local ")
	append(&b.cursors, buf.Cursor{pos = {s.line, dcol + len(name)}, sel = {anchor = {s.line, dcol}, active = true}})
	append(&b.cursors, buf.Cursor{pos = {s.line + 1, s.col + len(name)}, sel = {anchor = {s.line + 1, s.col}, active = true}})
	code_touched(doc)
}

// Code_CmdExtractMethod: the selected lines become a method of the script.
Code_CmdExtractMethod :: proc(state: ^EditorState) {
	doc := code_active_doc()
	if doc == nil do return
	b := &doc.buffer
	s, e, ok := buf.selection_range(b.cursors[len(b.cursors) - 1])
	if !ok {
		Editor_Log(state, .Info, "Select the lines to extract into a method")
		return
	}
	last := e.line if e.col > 0 || e.line == s.line else e.line - 1
	cls := Script_ClassName(buf.buffer_to_string(b, context.temp_allocator))
	// The function the lines are in: the method goes after its `end`.
	fnEnd := -1
	for bl in code_blocks_around(doc, s.line) do if bl.kind == .Function do fnEnd = bl.end
	if fnEnd < 0 {
		Editor_Log(state, .Info, "Extract Method works on lines inside a function")
		return
	}
	first := strings.clone(buf.buffer_line_str(b, s.line), context.temp_allocator)
	ind := indent_of(first)
	unit := unit_of(doc)
	name := "new_method"
	head := fmt.tprintf("function %s:%s()", cls, name) if cls != "" else fmt.tprintf("local function %s()", name)
	sb := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&sb, "\n\n%s\n", head) // a blank line, then the method
	for ln in s.line ..= last {
		l := buf.buffer_line_str(b, ln)
		body := strings.trim_prefix(l, ind)
		if strings.trim_space(l) != "" do strings.write_string(&sb, unit)
		fmt.sbprintf(&sb, "%s\n", body)
	}
	strings.write_string(&sb, "end")
	group := buf.buffer_next_group(b)
	// The method after the function (insert first: below the edit).
	buf.buffer_insert_text(b, {fnEnd, buf.buffer_line_len(b, fnEnd)}, strings.to_string(sb), group)
	call := fmt.tprintf("%sself:%s()", ind, name) if cls != "" else fmt.tprintf("%s%s()", ind, name)
	buf.buffer_delete_range(b, {s.line, 0}, {last, buf.buffer_line_len(b, last)}, group)
	buf.buffer_insert_text(b, {s.line, 0}, call, group)
	// Cursors on the call's name and the definition's.
	removed := last - s.line
	defLine := fnEnd - removed + 2
	callCol := len(ind) + (len("self:") if cls != "" else 0)
	defCol := strings.index(head, name)
	clear(&b.cursors)
	append(&b.cursors, buf.Cursor{pos = {s.line, callCol + len(name)}, sel = {anchor = {s.line, callCol}, active = true}})
	append(&b.cursors, buf.Cursor{pos = {defLine, defCol + len(name)}, sel = {anchor = {defLine, defCol}, active = true}})
	code_touched(doc)
}

// Code_CmdInlineVariable: the caret's `local x = expr` replaced at its uses.
Code_CmdInlineVariable :: proc(state: ^EditorState) {
	doc := code_active_doc()
	if doc == nil do return
	b := &doc.buffer
	ln := b.cursors[len(b.cursors) - 1].pos.line
	line := strings.trim_space(buf.buffer_line_str(b, ln))
	if !strings.has_prefix(line, "local ") || !strings.contains(line, "=") {
		Editor_Log(state, .Info, "Put the caret on a `local name = value` line to inline it")
		return
	}
	eq := strings.index_byte(line, '=')
	name := strings.trim_space(line[len("local "):eq])
	expr := strings.trim_space(line[eq + 1:])
	if strings.contains(name, ",") || name == "" || expr == "" {
		Editor_Log(state, .Info, "Inline works on a single local")
		return
	}
	// Parenthesize anything that isn't a plain value.
	simple := true
	for ch in transmute([]u8)expr do if !(code_is_ident_byte(ch) || ch == '.' || ch == ':' || ch == '"' || ch == '\'') do simple = false
	repl := expr if simple else fmt.tprintf("(%s)", expr)
	// Uses: identifier tokens named `name` after the line, to its block's end.
	scopeEnd := buf.buffer_line_count(b) - 1
	if blocks := code_blocks_around(doc, ln, includeStart = false); len(blocks) > 0 do scopeEnd = blocks[len(blocks) - 1].end
	code_update_line_states(doc)
	Use :: struct {line, from, to: int}
	uses := make([dynamic]Use, context.temp_allocator)
	for k in ln + 1 ..= scopeEnd {
		text := buf.buffer_line_str(b, k)
		tokens, _ := Token_CacheGet(&doc.tokens, doc.lang, text, doc.lineStates[k] if k < len(doc.lineStates) else 0, b.version)
		for t in tokens {
			if t.kind != .Identifier || text[t.start:t.end] != name do continue
			if t.start > 0 && (text[t.start - 1] == '.' || text[t.start - 1] == ':') do continue // a field, not the local
			append(&uses, Use{k, t.start, t.end})
		}
		// Reassigned: stop (it's no longer the same value).
		trimmed := strings.trim_space(text)
		if strings.has_prefix(trimmed, fmt.tprintf("%s =", name)) || strings.has_prefix(trimmed, fmt.tprintf("local %s", name)) do break
	}
	group := buf.buffer_next_group(b)
	#reverse for u in uses {
		buf.buffer_delete_range(b, {u.line, u.from}, {u.line, u.to}, group)
		buf.buffer_insert_text(b, {u.line, u.from}, repl, group)
	}
	// The declaration line goes.
	if ln + 1 < buf.buffer_line_count(b) do buf.buffer_delete_range(b, {ln, 0}, {ln + 1, 0}, group)
	else do buf.buffer_delete_range(b, {ln, 0}, {ln, buf.buffer_line_len(b, ln)}, group)
	code_set_single_cursor(b, {ln, 0}, false)
	code_touched(doc)
	Editor_Log(state, .Info, "Inlined %s at %d use(s)", name, len(uses))
}

// Code_CmdTogglePropertyAccess: get_property / set_property <-> fields.
Code_CmdTogglePropertyAccess :: proc(state: ^EditorState) {
	doc := code_active_doc()
	if doc == nil do return
	b := &doc.buffer
	ln := b.cursors[len(b.cursors) - 1].pos.line
	text := strings.clone(buf.buffer_line_str(b, ln), context.temp_allocator)
	out, changed := code_toggle_property(text)
	if !changed {
		Editor_Log(state, .Info, "No get_property / set_property call or node field on this line")
		return
	}
	group := buf.buffer_next_group(b)
	buf.buffer_delete_range(b, {ln, 0}, {ln, len(text)}, group)
	buf.buffer_insert_text(b, {ln, 0}, out, group)
	code_set_single_cursor(b, {ln, min(b.cursors[0].pos.col, len(out))}, false)
	code_touched(doc)
}

// code_toggle_property rewrites one line (see above).
code_toggle_property :: proc(text: string) -> (string, bool) {
	// obj:set_property("p", v) -> obj.p = v
	if i := strings.index(text, ":set_property(\""); i >= 0 {
		rest := text[i + len(":set_property(\""):]
		if q := strings.index_byte(rest, '"'); q > 0 && strings.has_prefix(rest[q + 1:], ",") {
			args := rest[q + 2:]
			if c := strings.last_index_byte(args, ')'); c >= 0 {
				return fmt.tprintf("%s.%s = %s%s", text[:i], rest[:q], strings.trim_space(args[:c]), args[c + 1:]), true
			}
		}
	}
	// obj:get_property("p") -> obj.p
	if i := strings.index(text, ":get_property(\""); i >= 0 {
		rest := text[i + len(":get_property(\""):]
		if q := strings.index(rest, "\")"); q > 0 && !strings.contains(rest[:q], ".") {
			return fmt.tprintf("%s.%s%s", text[:i], rest[:q], rest[q + 2:]), true
		}
	}
	// obj.p = v -> obj:set_property("p", v) (a node-looking target: node / x.node)
	trimmed := strings.trim_space(text)
	ind := indent_of(text)
	if eq := strings.index(trimmed, " = "); eq > 0 && !strings.has_prefix(trimmed, "local ") {
		lhs := trimmed[:eq]
		if dot := strings.last_index_byte(lhs, '.'); dot > 0 && strings.has_suffix(lhs[:dot], "node") {
			return fmt.tprintf("%s%s:set_property(\"%s\", %s)", ind, lhs[:dot], lhs[dot + 1:], trimmed[eq + 3:]), true
		}
	}
	// x.node.p (read) -> x.node:get_property("p")
	if i := strings.index(text, "node."); i >= 0 {
		start := i + len("node.")
		end := start
		for end < len(text) && code_is_ident_byte(text[end]) do end += 1
		if end > start && (end >= len(text) || text[end] != '(') {
			return fmt.tprintf("%snode:get_property(\"%s\")%s", text[:i], text[start:end], text[end:]), true
		}
	}
	return text, false
}

// Code_CmdToggleVec2: {x, y} <-> Vec2(x, y) around the caret.
Code_CmdToggleVec2 :: proc(state: ^EditorState) {
	doc := code_active_doc()
	if doc == nil do return
	b := &doc.buffer
	p := b.cursors[len(b.cursors) - 1].pos
	text := strings.clone(buf.buffer_line_str(b, p.line), context.temp_allocator)
	group := buf.buffer_next_group(b)
	// Vec2( ... ) around the caret.
	for i := min(p.col, len(text) - 1); i >= 0; i -= 1 {
		if i + 5 <= len(text) && text[i:i + 5] == "Vec2(" {
			if c := strings.index_byte(text[i:], ')'); c > 0 && i + c >= p.col - 1 {
				inner := text[i + 5:i + c]
				buf.buffer_delete_range(b, {p.line, i}, {p.line, i + c + 1}, group)
				buf.buffer_insert_text(b, {p.line, i}, fmt.tprintf("{%s}", inner), group)
				code_touched(doc)
				return
			}
		}
	}
	// { a, b } around the caret.
	open := -1
	for i := min(p.col, len(text) - 1); i >= 0; i -= 1 do if text[i] == '{' {open = i; break}
	if open >= 0 {
		if c := strings.index_byte(text[open:], '}'); c > 0 {
			inner := text[open + 1:open + c]
			if strings.count(inner, ",") == 1 {
				buf.buffer_delete_range(b, {p.line, open}, {p.line, open + c + 1}, group)
				buf.buffer_insert_text(b, {p.line, open}, fmt.tprintf("Vec2(%s)", strings.trim_space(inner)), group)
				code_touched(doc)
				return
			}
		}
	}
	Editor_Log(state, .Info, "Put the caret in a {x, y} table or a Vec2(x, y)")
}
