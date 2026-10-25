package editor

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"
import e "../engine"
import buf "../odin_editor/buffer"
import imgui "lib/imgui"

// ============================================================================
// Code tab context menus (Zed-style):
//
//   text    right-click in the code: first what is under the click - a
//           symbol (definition, references, rename, reference), a string
//           naming a node (select it) or a project file (reveal / open), a
//           selection (copy as markdown) - then Edit, Selection, Go To,
//           Lines and Refactor submenus with their shortcuts
//   gutter  right-click a line number: breakpoint, condition, run to here,
//           copy location, select line
//
// Right-click moves the caret to the click unless it is inside a selection.
// ============================================================================

@(private = "file")
Ctx_Info :: struct {
	pos:       buf.Position,
	symbol:    string, // identifier under the click (temp: rebuilt each open)
	qualified: string, // with its module: Audio.play_sound
	literal:   string, // string literal under the click
	asset:     string, // ... naming a project file
	node:      ^e.Node, // ... naming a node of the scene
	hasSel:    bool,
}

@(private = "file")
ctx: struct {
	info:       Ctx_Info,
	symbolBuf:  [128]u8,
	qualBuf:    [160]u8,
	litBuf:     [256]u8,
	gutterLine: int, // gutter menu line (1-based), 0 = closed
	openGutter: bool,
}

// Code_ContextOpen: a right-click at p in the text (call, then OpenPopup).
Code_ContextOpen :: proc(state: ^EditorState, doc: ^Code_Doc, p: buf.Position) {
	b := &doc.buffer
	inside := false
	for c in b.cursors {
		if s, e_, ok := buf.selection_range(c); ok && pos_le(s, p) && pos_le(p, e_) do inside = true
	}
	if !inside do code_set_single_cursor(b, p, false)
	info := Ctx_Info{pos = p}
	for c in b.cursors do if _, _, ok := buf.selection_range(c); ok do info.hasSel = true
	line := buf.buffer_line_str(b, p.line)
	// The identifier (and its module) under the click.
	ident :: proc(ch: u8) -> bool {return ch == '_' || (ch | 0x20 >= 'a' && ch | 0x20 <= 'z') || (ch >= '0' && ch <= '9')}
	s, en := min(p.col, len(line)), min(p.col, len(line))
	for s > 0 && ident(line[s - 1]) do s -= 1
	for en < len(line) && ident(line[en]) do en += 1
	if en > s && !(line[s] >= '0' && line[s] <= '9') {
		info.symbol = keep(ctx.symbolBuf[:], line[s:en])
		info.qualified = info.symbol
		if s > 1 && (line[s - 1] == '.' || line[s - 1] == ':') {
			q := s - 1
			for q > 0 && ident(line[q - 1]) do q -= 1
			if q < s - 1 && line[q] >= 'A' && line[q] <= 'Z' do info.qualified = keep(ctx.qualBuf[:], line[q:en])
		}
	}
	// A string literal around the click: a node name / path or a file.
	open := -1
	for i := min(p.col, len(line)) - 1; i >= 0; i -= 1 do if line[i] == '"' || line[i] == '\'' {open = i; break}
	if open >= 0 {
		if close := strings.index_byte(line[open + 1:], line[open]); close >= 0 && open + 1 + close >= p.col {
			lit := line[open + 1:open + 1 + close]
			if lit != "" {
				info.literal = keep(ctx.litBuf[:], lit)
				info.symbol = ""
				full, _ := filepath.join({state.projectPath, lit}, context.temp_allocator)
				if strings.contains(lit, ".") && os.exists(full) do info.asset = info.literal
				if state.activeScene != nil {
					info.node = e.Scene_FindNodeByName(state.activeScene, lit)
					if info.node == nil {
						if owner := code_script_owner(state, doc); owner != nil do info.node = e.Node_ResolvePath(state.activeScene.manager, owner, lit)
					}
				}
			}
		}
	}
	ctx.info = info
}

@(private = "file")
pos_le :: proc(a, b: buf.Position) -> bool {return a.line < b.line || (a.line == b.line && a.col <= b.col)}

// keep copies s into a fixed buffer (the menu outlives the frame's temp).
@(private = "file")
keep :: proc(dst: []u8, s: string) -> string {
	n := copy(dst, s)
	return string(dst[:n])
}

@(private = "file")
item :: proc(state: ^EditorState, icon: string, id: string, enabled := true) {
	a := Action_Find(id)
	if a == nil do return
	sc := Action_ShortcutText(a)
	ok := enabled && Action_Enabled(state, a)
	if imgui.MenuItem(fmt.ctprintf("%s  %s", icon, a.label), strings.clone_to_cstring(sc, context.temp_allocator) if sc != "" else nil, false, ok) {
		Action_Run(state, a)
		GlobalCode.focusRequest = true // typing goes back to the code
	}
	Drive_Item(fmt.tprintf("ctx:%s", id))
}

@(private = "file")
submenu :: proc(icon, label, id: string) -> bool {
	open := imgui.BeginMenu(fmt.ctprintf("%s  %s", icon, label))
	Drive_Item(fmt.tprintf("ctx:%s", id))
	return open
}

// code_text_context_menu: right-click in the code (inside its popup).
code_text_context_menu :: proc(state: ^EditorState, doc: ^Code_Doc) {
	// (No focus request while open: focusing the code window closes popups.)
	if imgui.IsKeyPressed(.Escape) {
		imgui.CloseCurrentPopup()
		GlobalCode.focusRequest = true
		return
	}
	info := &ctx.info
	lsp := GlobalCode.lspState == .Ready && doc.isLua

	// What is under the click.
	contextual := false
	if info.node != nil {
		UI_DimText(fmt.tprintf("\"%s\"", info.literal))
		if imgui.MenuItem(fmt.ctprintf("%s  Select %s in the Scene Tree", ICON_FA_SITEMAP, info.node.name)) {
			Editor_SelectNode(state, info.node, false)
			state.cameraPos = info.node.globalPosition
		}
		Drive_Item("ctx:select-node")
		contextual = true
	}
	if info.asset != "" {
		if !contextual do UI_DimText(fmt.tprintf("\"%s\"", info.literal))
		if imgui.MenuItem(fmt.ctprintf("%s  Reveal in Assets", ICON_FA_FOLDER_OPEN)) do Asset_Reveal(state, info.asset)
		Drive_Item("ctx:reveal-asset")
		if strings.has_suffix(info.asset, ".lua") || strings.has_suffix(info.asset, ".fs") {
			if imgui.MenuItem(fmt.ctprintf("%s  Open %s", ICON_FA_FILE_CODE, filepath.base(info.asset))) do Editor_OpenScript(state, info.asset)
			Drive_Item("ctx:open-asset")
		}
		contextual = true
	}
	if info.symbol != "" && info.literal == "" {
		UI_DimText(info.qualified)
		item(state, ICON_FA_ARROW_POINTER, "code.definition", lsp)
		item(state, ICON_FA_EYE, "code.peek_definition", lsp)
		item(state, ICON_FA_MAGNIFYING_GLASS, "code.references", lsp)
		item(state, ICON_FA_PEN, "code.rename", lsp)
		item(state, ICON_FA_BOOK, "code.reference")
		item(state, ICON_FA_SLIDERS, "code.show_in_inspector")
		contextual = true
	}
	if info.hasSel {
		item(state, ICON_FA_COPY, "code.copy_markdown")
		if submenu(ICON_FA_CODE, "Wrap In", "wrap") {
			item(state, ICON_FA_CODE, "code.wrap_if")
			item(state, ICON_FA_CODE, "code.wrap_do")
			item(state, ICON_FA_CODE, "code.wrap_function")
			imgui.EndMenu()
		}
		contextual = true
	}
	if contextual do imgui.Separator()

	item(state, ICON_FA_SCISSORS, "code.cut")
	item(state, ICON_FA_COPY, "code.copy")
	item(state, ICON_FA_PASTE, "code.paste")
	item(state, ICON_FA_PASTE, "code.clipboard_history")
	imgui.Separator()
	if submenu(ICON_FA_I_CURSOR, "Selection", "selection") {
		item(state, ICON_FA_CHECK, "code.select_all")
		item(state, ICON_FA_GRIP_LINES, "code.select_line")
		item(state, ICON_FA_EXPAND, "code.expand_selection")
		item(state, ICON_FA_COMPRESS, "code.shrink_selection")
		item(state, ICON_FA_BRACKET, "code.select_inside")
		imgui.Separator()
		item(state, ICON_FA_I_CURSOR, "code.select_next")
		item(state, ICON_FA_FORWARD, "code.skip_occurrence")
		item(state, ICON_FA_I_CURSOR, "code.select_all_occurrences")
		item(state, ICON_FA_ARROW_UP, "code.cursor_above")
		item(state, ICON_FA_ARROW_DOWN, "code.cursor_below")
		item(state, ICON_FA_I_CURSOR, "code.cursors_line_ends")
		item(state, ICON_FA_ROTATE_LEFT, "code.undo_cursor")
		imgui.EndMenu()
	}
	if submenu(ICON_FA_ARROW_RIGHT, "Go To", "goto") {
		item(state, ICON_FA_ARROW_POINTER, "code.definition", lsp)
		item(state, ICON_FA_MAGNIFYING_GLASS, "code.references", lsp)
		item(state, ICON_FA_LIST, "code.outline")
		item(state, ICON_FA_MAGNIFYING_GLASS, "code.workspace_symbols", lsp)
		item(state, ICON_FA_ARROW_DOWN, "code.goto_line")
		item(state, ICON_FA_BRACKET, "code.matching_bracket")
		imgui.Separator()
		item(state, ICON_FA_TRIANGLE_EXCLAMATION, "code.next_diagnostic")
		item(state, ICON_FA_TRIANGLE_EXCLAMATION, "code.prev_diagnostic")
		item(state, ICON_FA_CIRCLE, "code.next_change")
		item(state, ICON_FA_CIRCLE, "code.prev_change")
		imgui.Separator()
		item(state, ICON_FA_ARROW_LEFT, "code.nav_back")
		item(state, ICON_FA_ARROW_RIGHT, "code.nav_forward")
		imgui.EndMenu()
	}
	if submenu(ICON_FA_GRIP_LINES, "Lines", "lines") {
		item(state, ICON_FA_CODE, "code.comment")
		item(state, ICON_FA_CLONE, "code.duplicate_down")
		item(state, ICON_FA_ARROW_UP, "code.move_up")
		item(state, ICON_FA_ARROW_DOWN, "code.move_down")
		item(state, ICON_FA_TRASH, "code.delete_line")
		item(state, ICON_FA_GRIP_LINES, "code.join_lines")
		item(state, ICON_FA_INDENT, "code.indent")
		item(state, ICON_FA_OUTDENT, "code.outdent")
		imgui.Separator()
		item(state, ICON_FA_CARET_DOWN, "code.fold")
		item(state, ICON_FA_CARET_RIGHT, "code.unfold")
		item(state, ICON_FA_CARET_DOWN, "code.fold_all")
		item(state, ICON_FA_CARET_RIGHT, "code.unfold_all")
		imgui.EndMenu()
	}
	if submenu(ICON_FA_WAND_MAGIC_SPARKLES, "Refactor", "refactor") {
		item(state, ICON_FA_LIGHTBULB, "code.code_actions")
		item(state, ICON_FA_PEN, "code.rename", lsp)
		item(state, ICON_FA_ARROW_RIGHT, "code.extract_local")
		item(state, ICON_FA_ARROW_RIGHT, "code.extract_method")
		item(state, ICON_FA_ARROW_LEFT, "code.inline_variable")
		item(state, ICON_FA_RIGHT_LEFT, "code.toggle_property_access")
		item(state, ICON_FA_RIGHT_LEFT, "code.toggle_vec2")
		imgui.Separator()
		item(state, ICON_FA_CODE, "code.wrap_if")
		item(state, ICON_FA_CODE, "code.wrap_do")
		item(state, ICON_FA_CODE, "code.wrap_function")
		imgui.EndMenu()
	}
	item(state, ICON_FA_CODE, "code.format", lsp)
	imgui.Separator()
	item(state, ICON_FA_MAGNIFYING_GLASS, "code.find")
	item(state, ICON_FA_RIGHT_LEFT, "code.replace")
	item(state, ICON_FA_MAGNIFYING_GLASS, "code.find_in_files")
	imgui.Separator()
	item(state, ICON_FA_LINK, "code.copy_path")
	item(state, ICON_FA_LINK, "code.copy_location")
}

// Asset_Reveal shows a project file in Assets: its folder opened, selected
// and highlighted for a moment.
Asset_Reveal :: proc(state: ^EditorState, rel: string) {
	for s in importHighlight.rels do delete(s)
	clear(&importHighlight.rels)
	append(&importHighlight.rels, strings.clone(rel))
	if dir, ok := Asset_ImportDir(rel); ok {
		title := strings.concatenate({strings.to_upper(dir[:1], context.temp_allocator), dir[1:]}, context.temp_allocator)
		if title in assetFolderClosed do assetFolderClosed[title] = false
	}
	importHighlight.until = time.time_add(time.now(), 2 * time.Second)
	importHighlight.focus = true
	full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
	Editor_SelectAsset(state, full)
}

// --- gutter ------------------------------------------------------------------------

// Code_GutterMenuOpen: right-click on a line number (1-based).
Code_GutterMenuOpen :: proc(line: int) {
	ctx.gutterLine = line
	ctx.openGutter = true
}

// Code_GutterMenu draws the line-number menu (Code window).
Code_GutterMenu :: proc(state: ^EditorState, doc: ^Code_Doc) {
	if ctx.openGutter {
		imgui.OpenPopup("##gutter_ctx")
		ctx.openGutter = false
	}
	if !imgui.BeginPopup("##gutter_ctx") do return
	defer imgui.EndPopup()
	if imgui.IsKeyPressed(.Escape) {
		imgui.CloseCurrentPopup()
		return
	}
	ln := ctx.gutterLine
	UI_DimText(fmt.tprintf("Line %d", ln))
	has := Debug_HasBreakpoint(doc.rel, ln)
	if doc.isLua {
		if imgui.MenuItem(fmt.ctprintf("%s  %s", ICON_FA_CIRCLE, "Remove Breakpoint" if has else "Add Breakpoint")) do Debug_ToggleBreakpoint(doc.rel, ln)
		Drive_Item("ctx:gutter-breakpoint")
		if imgui.MenuItem(fmt.ctprintf("%s  %s", ICON_FA_FILTER, "Edit Condition..." if Debug_Condition(doc.rel, ln) != "" else "Add Condition...")) do Debug_EditCondition(doc.rel, ln)
		Drive_Item("ctx:gutter-condition")
		if imgui.MenuItem(fmt.ctprintf("%s  Run to Here", ICON_FA_PLAY), nil, false, Debug_IsStopped()) do Debug_RunTo(doc.rel, ln)
		Drive_Item("ctx:gutter-run-to")
		imgui.Separator()
	}
	if imgui.MenuItem(fmt.ctprintf("%s  Select Line", ICON_FA_GRIP_LINES)) {
		b := &doc.buffer
		code_set_single_cursor(b, {ln - 1, 0}, false)
		buf.cursor_select_line(b, &b.cursors[0])
	}
	if imgui.MenuItem(fmt.ctprintf("%s  Copy Location", ICON_FA_LINK)) {
		imgui.SetClipboardText(fmt.ctprintf("%s:%d", doc.rel, ln))
	}
	Drive_Item("ctx:gutter-copy-location")
}

// --- selection commands --------------------------------------------------------------

// code_selection_text: the primary selection's text ("" = none).
code_selection_text :: proc(doc: ^Code_Doc) -> string {
	b := &doc.buffer
	s, e_, ok := buf.selection_range(b.cursors[0])
	if !ok do return ""
	sb := strings.builder_make(context.temp_allocator)
	for ln in s.line ..= e_.line {
		line := buf.buffer_line_str(b, ln)
		from := s.col if ln == s.line else 0
		to := e_.col if ln == e_.line else len(line)
		strings.write_string(&sb, line[min(from, len(line)):min(to, len(line))])
		if ln != e_.line do strings.write_byte(&sb, '\n')
	}
	return strings.to_string(sb)
}

// Code_CmdCopyMarkdown copies the selection as a fenced lua block.
Code_CmdCopyMarkdown :: proc(state: ^EditorState) {
	doc := code_active_doc()
	if doc == nil do return
	text := code_selection_text(doc)
	if text == "" do return
	lang := "lua" if doc.isLua else ""
	code_clipboard_set(fmt.tprintf("```%s\n%s\n```\n", lang, strings.trim_right(text, "\n")), false)
}

// Code_CmdWrap wraps the selected lines in a block: `if condition then`,
// `do`, `local function name()` ... `end`, indenting them; the placeholder
// (condition / name) is selected.
Code_CmdWrap :: proc(state: ^EditorState, kind: enum {If, Do, Function}) {
	doc := code_active_doc()
	if doc == nil do return
	b := &doc.buffer
	s, e_, ok := buf.selection_range(b.cursors[0])
	if !ok {
		s, e_ = b.cursors[0].pos, b.cursors[0].pos
	}
	last := e_.line
	if e_.col == 0 && e_.line > s.line do last -= 1 // a selection ending at a line start
	first := strings.clone(buf.buffer_line_str(b, s.line), context.temp_allocator)
	indent := first[:len(first) - len(strings.trim_left(first, " \t"))]
	unit := "\t" if doc.useTabs else strings.repeat(" ", code_tab_width(), context.temp_allocator)
	head, place := "", ""
	switch kind {
	case .If: head, place = "if condition then", "condition"
	case .Do: head = "do"
	case .Function: head, place = "local function name()", "name"
	}
	sb := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&sb, "%s%s\n", indent, head)
	for ln in s.line ..= last {
		l := buf.buffer_line_str(b, ln)
		if strings.trim_space(l) != "" do strings.write_string(&sb, unit)
		fmt.sbprintf(&sb, "%s\n", l)
	}
	fmt.sbprintf(&sb, "%send", indent)
	group := buf.buffer_next_group(b)
	buf.buffer_delete_range(b, {s.line, 0}, {last, buf.buffer_line_len(b, last)}, group)
	buf.buffer_insert_text(b, {s.line, 0}, strings.to_string(sb), group)
	if place != "" {
		col := len(indent) + strings.index(head, place)
		code_set_single_cursor(b, {s.line, col}, false)
		b.cursors[0].sel = {anchor = {s.line, col}, active = true}
		b.cursors[0].pos = {s.line, col + len(place)}
	} else {
		code_set_single_cursor(b, {s.line, len(indent) + len(head)}, false)
	}
	code_touched(doc)
}
