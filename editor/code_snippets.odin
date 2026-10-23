package editor

import "core:fmt"
import "core:strings"
import buf "../odin_editor/buffer"

// ============================================================================
// Lua snippets: type a snippet's name and press Tab (also with the
// completion list open) to expand it - the script's class and the line's
// indentation filled in - then Tab moves through its placeholders.
// Bodies use LSP snippet syntax (${1:placeholder}, $0 = the final caret);
// $CLASS is the script's class, a tab one indent level.
// ============================================================================

Code_Snippet :: struct {
	name, description, body: string,
}

CODE_SNIPPETS := [?]Code_Snippet{
	{"ready", "ready(): runs once, when the node enters the game", "function $CLASS:ready()\n\t$0\nend"},
	{"update", "update(dt): runs every frame", "---@param dt number\nfunction $CLASS:update(dt)\n\t$0\nend"},
	{"connect", "Connect a node's event to a function", "${1:self.node}:connect(\"${2:timeout}\", function(value, source)\n\t$0\nend)"},
	{"properties", "Inspector properties table", "$CLASS.properties = {\n\t${1:speed} = { type = \"${2:float}\", default = ${3:100} },$0\n}"},
	{"tween", "Animate a property over time", "Tween.to(${1:self.node}, \"${2:position}\", ${3:{0, 0}}, ${4:0.5}, \"${5:out_quad}\")$0"},
	{"on", "on_<event>: an event of this script's node", "function $CLASS:on_${1:body_entered}(${2:other})\n\t$0\nend"},
	{"method", "A method of this script", "function $CLASS:${1:name}(${2})\n\t$0\nend"},
}

// code_snippet_word: the identifier before the caret, if it names a snippet
// and starts the statement (only whitespace before it on the line).
code_snippet_word :: proc(doc: ^Code_Doc) -> (^Code_Snippet, int) {
	b := &doc.buffer
	if len(b.cursors) != 1 || b.cursors[0].sel.active do return nil, 0
	pos := b.cursors[0].pos
	line := buf.buffer_line_str(b, pos.line)
	if pos.col > len(line) do return nil, 0
	start := pos.col
	for start > 0 && (line[start - 1] == '_' || (line[start - 1] | 0x20 >= 'a' && line[start - 1] | 0x20 <= 'z')) do start -= 1
	if start == pos.col || strings.trim_space(line[:start]) != "" do return nil, 0
	word := line[start:pos.col]
	for &s in CODE_SNIPPETS do if s.name == word do return &s, start
	return nil, 0
}

// Code_ExpandSnippet expands the snippet named before the caret (Tab).
// Returns false when there is none.
Code_ExpandSnippet :: proc(doc: ^Code_Doc) -> bool {
	s, startCol := code_snippet_word(doc)
	if s == nil do return false
	b := &doc.buffer
	pos := b.cursors[0].pos
	line := strings.clone(buf.buffer_line_str(b, pos.line), context.temp_allocator)
	indent := line[:len(line) - len(strings.trim_left_space(line))]
	unit := "\t" if doc.useTabs else "    "
	cls := Script_ClassName(buf.buffer_to_string(b, context.temp_allocator))
	if cls == "" do cls = "M"
	body, _ := strings.replace_all(s.body, "$CLASS", cls, context.temp_allocator)
	body, _ = strings.replace_all(body, "\t", unit, context.temp_allocator)
	body, _ = strings.replace_all(body, "\n", fmt.tprintf("\n%s", indent), context.temp_allocator)
	text, stops := code_expand_snippet(body)
	group := buf.buffer_next_group(b)
	start := buf.Position{pos.line, startCol}
	buf.buffer_delete_range(b, start, pos, group)
	end := buf.buffer_insert_text(b, start, text, group)
	b.cursors[0].sel.active = false
	b.cursors[0].pos = end
	if len(stops) > 0 do code_snippet_start(b, start, text, stops[:])
	GlobalCode.completion.open = false
	doc.scrollToCursor = true
	return true
}

// Code_SnippetHint: a line for the completion popup when Tab would expand
// a snippet ("" = none).
Code_SnippetHint :: proc(doc: ^Code_Doc) -> string {
	s, _ := code_snippet_word(doc)
	return fmt.tprintf("Tab: %s snippet - %s", s.name, s.description) if s != nil else ""
}
