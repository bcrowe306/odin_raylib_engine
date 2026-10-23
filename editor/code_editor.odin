package editor

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:time"
import "core:unicode/utf8"
import e "../engine"
import buf "../odin_editor/buffer"
import lsp "../odin_editor/lsp"
import syn "../odin_editor/syntax"
import imgui "lib/imgui"

// ============================================================================
// Code editor: Lua scripts open in a "Code" tab docked next to the Viewport.
//
// Text editing reuses odin_editor's host-agnostic packages (buffer: text,
// cursors, undo; syntax: the Lua highlighter; lsp: the language server
// client). This file draws the text with ImGui and maps ImGui input onto
// buffer commands; code_editor_lsp.odin talks to lua-language-server for
// completion, signature help, hover, diagnostics and go-to-definition,
// with the engine's API definitions (engine/definitions) as its library.
//
// Open a script from anywhere with Editor_OpenScript(state, path, line).
// Saving (Ctrl/Cmd+S) writes the file; the running scripts hot-reload.
// ============================================================================

CODE_WINDOW :: "Code###CodeEditorWindow"
// Tab stops come from Settings > Code Editor (code_tab_width()).
CODE_FONT_SIZE :: 14

// CODE_BG: the code area background (a theme colour, theme.odin).

Code_Doc :: struct {
	path:          string, // absolute
	rel:           string, // shown in tabs (project-relative when inside the project)
	uri:           string,
	buffer:        buf.Buffer,
	lang:          syn.Language,
	isLua:         bool,
	useTabs:       bool,
	savedVersion:  int,
	diskTime:      time.Time,
	// LSP: last buffer version sent (didOpen/didChange).
	lspOpen:       bool,
	sentVersion:   int,
	// Tokenizer state at the start of each line, valid for statesVersion.
	lineStates:    [dynamic]int,
	statesVersion: int,
	tokens:        Token_Cache, // per-line tokens (code_token_cache.odin)
	maxCols:       int, // widest line (columns), for widthVersion
	widthVersion:  int,
	widthValid:    bool,
	scrollToCursor: bool,
}

Code_Completion :: struct {
	open:      bool,
	waiting:   bool, // a request is in flight
	seq:       int,  // client.completion_seq when it was sent
	anchor:    buf.Position, // start of the word being completed
	selected:  int,
	filtered:  [dynamic]int, // indices into client.last_completion
	filteredSeq: int,        // the client.completion_seq `filtered` was built from
	scrollTo:  bool,
	// While the server is still loading the workspace it answers with empty
	// lists; those requests are retried for a while.
	retries:   int,
	retryAt:   time.Tick,
	retryPending: bool,
}

Code_LSP_State :: enum {
	Off,
	Starting,
	Ready,
	Failed,
}

Code_Editor :: struct {
	docs:          [dynamic]^Code_Doc,
	active:        int,
	selectRequest: int, // tab to select next frame (-1 = none)
	focusRequest:  bool,
	focused:       bool, // the text area had keyboard focus last frame
	windowFocused: bool, // any part of the Code window (tabs, find bar) had focus
	closePrompt:   int,  // doc waiting for Save / Don't Save (-1 = none)
	closeRequest:  int,  // tab to close at the end of the frame (-1 = none)
	closeOthers:   int,  // close every tab but this one (-2 = all, -1 = none)
	lastDiskCheck: time.Tick,
	cursorMoved:   time.Tick, // caret blink restarts on movement
	// Layout of the last drawn frame (screen space).
	charW, lineH:  f32,
	textOrigin:    [2]f32, // screen position of line 0, column 0
	areaMin, areaMax: [2]f32,
	popupMin, popupMax: [2]f32, // completion popup (clicks there don't hit the text)

	// Language server.
	client:        lsp.Client,
	lspState:      Code_LSP_State,
	lspMessage:    string,
	lspReadyAt:    time.Tick,
	completion:    Code_Completion,
	sigOpen:       bool,
	sigWaiting:    bool,
	sigSeq:        int,
	hoverPos:      buf.Position,
	hoverSince:    time.Tick,
	hoverValid:    bool, // mouse is over text at hoverPos
	hoverSent:     bool,
	hoverSeq:      int,
	defWaiting:    bool,
	defSeq:        int,
	refsWaiting:   bool,
	refsSeq:       int,
	editsWaiting:  bool,
	editsSeq:      int,
	formatDoc:     ^Code_Doc,
	saveAfterFormat: ^Code_Doc, // format-on-save: save when the format edits arrive

	find:          Code_Find,
	fontSize:      f32, // 0 = CODE_FONT_SIZE
	closedFiles:   [dynamic]string, // for Reopen Closed Tab
	renameOpen:    bool,
	renameBuf:     [128]u8,
	renamePos:     buf.Position,
	renameDoc:     ^Code_Doc,
	// Remaining tab stops of the last accepted snippet (code_editor_lsp.odin).
	snippetStops:  [dynamic]Snippet_Pending,
	snippetLine:   int,
	resolveIndex:  int, // completion item whose documentation was requested
	resolveSeq:    int,
}

GlobalCode := Code_Editor{selectRequest = -1, closePrompt = -1, closeRequest = -1, closeOthers = -1}

// --- documents ---------------------------------------------------------------------

// code_abs_path resolves a project-relative path ("scripts/x.lua").
code_abs_path :: proc(state: ^EditorState, path: string) -> string {
	if filepath.is_abs(path) {
		p, _ := filepath.clean(path, context.temp_allocator)
		return p
	}
	p, _ := filepath.join({state.projectPath, path}, context.temp_allocator)
	if !os.exists(p) && os.exists(path) {
		cwd := os.get_working_directory(context.temp_allocator) or_else ""
		p, _ = filepath.join({cwd, path}, context.temp_allocator)
	}
	return p
}

code_rel_path :: proc(state: ^EditorState, abs: string) -> string {
	// macOS: /tmp, /var and /etc are links into /private; tools (the
	// language server) may report either form.
	canon :: proc(p: string) -> string {
		when ODIN_OS == .Darwin {
			if strings.has_prefix(p, "/private/") do return p[len("/private"):]
		}
		return p
	}
	root := canon(strings.trim_suffix(state.projectPath, "/"))
	a := canon(abs)
	if root != "" && strings.has_prefix(a, root) && len(a) > len(root) && a[len(root)] == '/' {
		return a[len(root) + 1:]
	}
	return filepath.base(abs)
}

code_file_mtime :: proc(path: string) -> time.Time {
	info, err := os.stat(path, context.temp_allocator)
	if err != nil do return {}
	return info.modification_time
}

// Editor_OpenScript opens a script (project-relative or absolute) in the
// Code tab, focusing it, and moves the caret to `line`/`col` (0-based) if
// given. Opening an already open file just switches to its tab.
Editor_OpenScript :: proc(state: ^EditorState, path: string, line := -1, col := 0) -> bool {
	cm := &GlobalCode
	abs := code_abs_path(state, path)
	idx := -1
	for d, i in cm.docs do if d.path == abs do idx = i
	if idx < 0 {
		doc := new(Code_Doc)
		doc.buffer = buf.buffer_init()
		if !buf.buffer_load_file(&doc.buffer, abs) {
			buf.buffer_destroy(&doc.buffer)
			free(doc)
			Editor_Log(state, .Error, "Could not open %s", path)
			return false
		}
		doc.buffer.track_changes = false
		doc.path = strings.clone(abs)
		doc.rel = strings.clone(code_rel_path(state, abs))
		doc.uri = lsp.file_uri(abs)
		doc.lang = syn.language_for_path(abs)
		doc.isLua = doc.lang.name == "lua"
		doc.savedVersion = doc.buffer.version
		doc.diskTime = code_file_mtime(abs)
		// Keep the file's indentation style (Settings decide for new files).
		doc.useTabs = !GlobalSettings.insertSpaces
		for i in 0 ..< buf.buffer_line_count(&doc.buffer) {
			l := buf.buffer_line_str(&doc.buffer, i)
			if strings.has_prefix(l, "\t") {doc.useTabs = true; break}
			if strings.has_prefix(l, "  ") {doc.useTabs = false; break}
		}
		append(&cm.docs, doc)
		idx = len(cm.docs) - 1
	}
	doc := cm.docs[idx]
	if line >= 0 {
		b := &doc.buffer
		p := buf.buffer_clamp_position(b, {line, col})
		code_set_single_cursor(b, p, false)
		doc.scrollToCursor = true
	}
	cm.active = idx
	cm.selectRequest = idx
	cm.focusRequest = true
	return true
}

// Code_IsOpen reports whether a file is open in the code editor.
Code_IsOpen :: proc(state: ^EditorState, path: string) -> bool {
	abs := code_abs_path(state, path)
	for d in GlobalCode.docs do if d.path == abs do return true
	return false
}

// Code_DocText: a document's full text (temp).
Code_DocText :: proc(doc: ^Code_Doc) -> string {
	return buf.buffer_to_string(&doc.buffer, context.temp_allocator)
}

// Code_IsDirty: an open file with unsaved changes.
Code_IsDirty :: proc(state: ^EditorState, path: string) -> bool {
	abs := code_abs_path(state, path)
	for d in GlobalCode.docs do if d.path == abs do return code_doc_dirty(d)
	return false
}

// Code_HasFocus: the text area owns the keyboard (editor shortcuts stay off).
Code_HasFocus :: proc() -> bool {
	return GlobalCode.focused
}

// Code_WindowFocused: the Code window (text, tabs or find bar) has focus;
// code shortcuts apply.
Code_WindowFocused :: proc() -> bool {
	return len(GlobalCode.docs) > 0 && (GlobalCode.focused || GlobalCode.windowFocused)
}

code_doc_dirty :: proc(doc: ^Code_Doc) -> bool {
	return doc.buffer.version != doc.savedVersion
}

// Code_DirtyCount counts open files with unsaved changes.
Code_DirtyCount :: proc() -> int {
	n := 0
	for d in GlobalCode.docs do if code_doc_dirty(d) do n += 1
	return n
}

Code_SaveDoc :: proc(state: ^EditorState, doc: ^Code_Doc) -> bool {
	CodeRuntime_Clear(doc.rel) // its runtime problems were about the old text
	if !buf.buffer_save_file(&doc.buffer, doc.path) {
		Editor_Log(state, .Error, "Could not save %s", doc.rel)
		return false
	}
	doc.savedVersion = doc.buffer.version
	doc.diskTime = code_file_mtime(doc.path)
	code_lsp_did_save(doc)
	Editor_Log(state, .Info, "Saved %s", doc.rel)
	// Running scripts (Simulate) pick the change up right away.
	if n := e.ScriptManager_CheckForChanges(&state.game.scriptManager, force = true); n > 0 {
		Editor_Log(state, .Info, "Reloaded %d changed script(s)", n)
	}
	return true
}

// Code_SaveAll saves every modified file.
Code_SaveAll :: proc(state: ^EditorState) -> int {
	n := 0
	for d in GlobalCode.docs do if code_doc_dirty(d) && Code_SaveDoc(state, d) do n += 1
	return n
}

code_close_doc :: proc(idx: int) {
	cm := &GlobalCode
	if idx < 0 || idx >= len(cm.docs) do return
	doc := cm.docs[idx]
	append(&cm.closedFiles, strings.clone(doc.path))
	if cm.renameDoc == doc do cm.renameDoc = nil
	if cm.formatDoc == doc do cm.formatDoc = nil
	if cm.saveAfterFormat == doc do cm.saveAfterFormat = nil
	code_lsp_did_close(doc)
	buf.buffer_destroy(&doc.buffer)
	delete(doc.lineStates)
	Token_CacheDestroy(&doc.tokens)
	delete(doc.path)
	delete(doc.rel)
	delete(doc.uri)
	free(doc)
	ordered_remove(&cm.docs, idx)
	if cm.active >= len(cm.docs) do cm.active = len(cm.docs) - 1
	if cm.active > idx do cm.active -= 1
	cm.completion.open = false
	cm.sigOpen = false
	if len(cm.docs) == 0 do cm.focused = false
}

// code_request_close closes a tab at the end of the frame (the document
// may still be in use), asking first when it has unsaved changes.
code_request_close :: proc(idx: int) {
	if idx < 0 || idx >= len(GlobalCode.docs) do return
	if code_doc_dirty(GlobalCode.docs[idx]) {
		GlobalCode.closePrompt = idx
	} else {
		GlobalCode.closeRequest = idx
	}
}

Code_Shutdown :: proc() {
	cm := &GlobalCode
	for len(cm.docs) > 0 do code_close_doc(len(cm.docs) - 1)
	delete(cm.docs)
	delete(cm.completion.filtered)
	for f in cm.closedFiles do delete(f)
	delete(cm.closedFiles)
	delete(cm.snippetStops)
	code_find_destroy()
	code_lsp_shutdown()
}

// code_check_disk reloads files changed on disk (unless edited here).
code_check_disk :: proc(state: ^EditorState) {
	cm := &GlobalCode
	if time.tick_since(cm.lastDiskCheck) < time.Second do return
	cm.lastDiskCheck = time.tick_now()
	for doc in cm.docs {
		mt := code_file_mtime(doc.path)
		if mt == doc.diskTime || mt == {} do continue
		doc.diskTime = mt
		if code_doc_dirty(doc) {
			Editor_Log(state, .Warn, "%s changed on disk; keeping your unsaved edits", doc.rel)
			continue
		}
		cursor := doc.buffer.cursors[0].pos
		data, err := os.read_entire_file(doc.path, context.temp_allocator)
		if err != nil do continue
		buf.buffer_set_text(&doc.buffer, string(data))
		buf.buffer_clear_undo_history(&doc.buffer)
		code_set_single_cursor(&doc.buffer, buf.buffer_clamp_position(&doc.buffer, cursor), false)
		doc.savedVersion = doc.buffer.version
	}
}

// --- text geometry -----------------------------------------------------------------

// code_visual_col: byte column -> screen column (tabs expand, one cell per rune).
code_visual_col :: proc(line: string, byteCol: int) -> int {
	v := 0
	i := 0
	for i < len(line) && i < byteCol {
		r, w := utf8.decode_rune_in_string(line[i:])
		if r == '\t' do v = (v / code_tab_width() + 1) * code_tab_width()
		else do v += 1
		i += max(w, 1)
	}
	return v
}

// code_byte_col: screen column -> nearest byte column.
code_byte_col :: proc(line: string, visual: int) -> int {
	v := 0
	i := 0
	for i < len(line) {
		r, w := utf8.decode_rune_in_string(line[i:])
		next := (v / code_tab_width() + 1) * code_tab_width() if r == '\t' else v + 1
		if visual < next {
			// Closer to the start or the end of this cell?
			return i if visual - v <= (next - v) / 2 else i + max(w, 1)
		}
		v = next
		i += max(w, 1)
	}
	return len(line)
}

// LSP positions count UTF-16 code units.
code_u16_col :: proc(line: string, byteCol: int) -> int {
	n := 0
	for r, i in line {
		if i >= byteCol do break
		n += 2 if r > 0xFFFF else 1
	}
	return n
}

code_byte_from_u16 :: proc(line: string, u16Col: int) -> int {
	n := 0
	for r, i in line {
		if n >= u16Col do return i
		n += 2 if r > 0xFFFF else 1
	}
	return len(line)
}

code_set_single_cursor :: proc(b: ^buf.Buffer, p: buf.Position, extend: bool) {
	if len(b.cursors) == 0 do append(&b.cursors, buf.Cursor{})
	resize(&b.cursors, 1)
	c := &b.cursors[0]
	if extend {
		if !c.sel.active do c.sel = {anchor = c.pos, active = true}
	} else {
		c.sel.active = false
	}
	c.pos = p
	c.has_goal = false
}

code_is_ident_byte :: proc(ch: u8) -> bool {
	return (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') || ch == '_'
}

// code_word_start: start of the identifier ending at `p`.
code_word_start :: proc(b: ^buf.Buffer, p: buf.Position) -> buf.Position {
	line := buf.buffer_line_str(b, p.line)
	col := min(p.col, len(line))
	for col > 0 && code_is_ident_byte(line[col - 1]) do col -= 1
	return {p.line, col}
}

// code_selected_text returns the primary selection ("" if none).
code_selected_text :: proc(b: ^buf.Buffer, allocator := context.temp_allocator) -> string {
	start, end, ok := buf.selection_range(b.cursors[0])
	if !ok do return ""
	sb := strings.builder_make(allocator)
	for ln in start.line ..= end.line {
		line := buf.buffer_line_str(b, ln)
		from := start.col if ln == start.line else 0
		to := end.col if ln == end.line else len(line)
		strings.write_string(&sb, line[min(from, len(line)):min(to, len(line))])
		if ln != end.line do strings.write_byte(&sb, '\n')
	}
	return strings.to_string(sb)
}

// --- rendering ---------------------------------------------------------------------

// code_syntax: a syntax colour, darker on light themes.
code_syntax :: proc(v: imgui.Vec4) -> u32 {
	c := v
	if UI_THEME_LIGHT do c = {v.x * 0.58, v.y * 0.58, v.z * 0.58, v.w}
	return col_u32(c)
}

code_token_color :: proc(k: syn.TokenKind) -> u32 {
	switch k {
	case .Keyword:     return code_syntax({0.78, 0.55, 0.95, 1})
	case .String:      return code_syntax({0.60, 0.82, 0.52, 1})
	case .Number:      return code_syntax({0.96, 0.66, 0.42, 1})
	case .Comment:     return code_syntax({0.42, 0.47, 0.55, 1})
	case .Function:    return code_syntax({0.42, 0.68, 1.00, 1})
	case .Builtin:     return code_syntax({0.35, 0.82, 0.86, 1})
	case .Constant:    return code_syntax({0.96, 0.55, 0.45, 1})
	case .Property:    return code_syntax({0.90, 0.78, 0.55, 1})
	case .Type:        return code_syntax({0.95, 0.80, 0.40, 1})
	case .Operator, .Punctuation: return code_syntax({0.65, 0.70, 0.78, 1})
	case .Directive, .Attribute:  return code_syntax({0.78, 0.55, 0.95, 1})
	case .Identifier, .Default:   return code_syntax(UI_TEXT)
	}
	return code_syntax(UI_TEXT)
}

// code_draw_text draws `text` starting at screen column `vcol`; tabs advance
// to the next tab stop. Returns the column after the text.
code_draw_text :: proc(dl: ^imgui.DrawList, x0, y: f32, vcol: int, text: string, color: u32) -> int {
	cm := &GlobalCode
	font := code_font()
	v := vcol
	segStart := 0
	flush :: proc(dl: ^imgui.DrawList, font: ^imgui.Font, x0, y, charW: f32, v: int, s: string, color: u32) {
		if len(s) == 0 do return
		cs := strings.clone_to_cstring(s, context.temp_allocator)
		imgui.DrawList_AddTextImFontPtr(dl, font, code_font_size(), {x0 + f32(v) * charW, y}, color, cs)
	}
	segV := v
	for i := 0; i < len(text); {
		r, w := utf8.decode_rune_in_string(text[i:])
		if r == '\t' {
			flush(dl, font, x0, y, cm.charW, segV, text[segStart:i], color)
			v = (v / code_tab_width() + 1) * code_tab_width()
			segStart = i + 1
			segV = v
		} else {
			v += 1
		}
		i += max(w, 1)
	}
	flush(dl, font, x0, y, cm.charW, segV, text[segStart:], color)
	return v
}

code_tab_width :: proc() -> int {
	return clamp(GlobalSettings.tabWidth, 1, 16)
}

code_font :: proc() -> ^imgui.Font {
	return GlobalFonts.mono if GlobalFonts.mono != nil else GlobalFonts.regular
}

// code_update_line_states re-runs the tokenizer's line states after edits.
code_update_line_states :: proc(doc: ^Code_Doc) {
	b := &doc.buffer
	n := buf.buffer_line_count(b)
	if doc.statesVersion == b.version && len(doc.lineStates) == n do return
	// Unchanged lines (also shifted ones) come from the token cache.
	start := Token_CacheTimeStart(&doc.tokens)
	resize(&doc.lineStates, n)
	state := syn.LINE_STATE_NORMAL
	for i in 0 ..< n {
		doc.lineStates[i] = state
		_, state = Token_CacheGet(&doc.tokens, doc.lang, buf.buffer_line_str(b, i), state, b.version)
	}
	doc.statesVersion = b.version
	Token_CachePrune(&doc.tokens, n, b.version)
	Token_CacheTimeEnd(&doc.tokens, start)
}

Code_Render :: proc(state: ^EditorState) {
	cm := &GlobalCode
	code_lsp_update(state)
	code_commands_update(state)
	code_check_disk(state)
	if len(cm.docs) == 0 {
		cm.focused = false
		cm.windowFocused = false
		return
	}
	if cm.focusRequest do imgui.SetWindowFocusStr(CODE_WINDOW)
	// First use: a tab next to the Viewport.
	if state.viewportDockId != 0 do imgui.SetNextWindowDockID(state.viewportDockId, .FirstUseEver)
	imgui.PushStyleVarImVec2(.WindowPadding, {0, 0})
	visible := imgui.Begin(CODE_WINDOW, nil, {.NoScrollbar, .NoScrollWithMouse})
	imgui.PopStyleVar()
	cm.windowFocused = imgui.IsWindowFocused(imgui.FocusedFlags_RootAndChildWindows)
	focusedNow := false
	if visible {
		code_tabs(state)
		if cm.active >= 0 && cm.active < len(cm.docs) {
			code_find_bar(state, cm.docs[cm.active])
			focusedNow = code_text_area(state, cm.docs[cm.active])
			code_status_line(state, cm.docs[cm.active])
		}
	}
	imgui.End()
	cm.focused = focusedNow
	if !focusedNow {
		cm.completion.open = false
		cm.sigOpen = false
	}
	if focusedNow && cm.active >= 0 && cm.active < len(cm.docs) {
		code_completion_popup(state, cm.docs[cm.active])
		code_signature_popup(cm.docs[cm.active])
	}
	code_close_prompt(state)
	code_rename_popup(state)
	if cm.closeRequest >= 0 {
		code_close_doc(cm.closeRequest)
		cm.closeRequest = -1
	}
	if cm.closeOthers != -1 {
		keep := cm.docs[cm.closeOthers] if cm.closeOthers >= 0 && cm.closeOthers < len(cm.docs) else nil
		for i := len(cm.docs) - 1; i >= 0; i -= 1 {
			d := cm.docs[i]
			if d == keep do continue
			if code_doc_dirty(d) {
				Editor_Log(state, .Warn, "%s has unsaved changes; not closed", d.rel)
				continue
			}
			code_close_doc(i)
		}
		cm.closeOthers = -1
	}
}

code_tabs :: proc(state: ^EditorState) {
	cm := &GlobalCode
	imgui.PushStyleVarImVec2(.FramePadding, {10, 6})
	defer imgui.PopStyleVar()
	if !imgui.BeginTabBar("##code_tabs", {.Reorderable, .FittingPolicyScroll}) do return
	closeIdx := -1
	for doc, i in cm.docs {
		open := true
		flags: imgui.TabItemFlags = {}
		if code_doc_dirty(doc) do flags += {.UnsavedDocument}
		if cm.selectRequest == i do flags += {.SetSelected}
		label := fmt.ctprintf("%s  %s###codetab_%s", ICON_FA_FILE_CODE, filepath.base(doc.rel), doc.path)
		if imgui.BeginTabItem(label, &open, flags) {
			if cm.selectRequest < 0 && cm.active != i {
				cm.active = i
				cm.completion.open = false
				cm.sigOpen = false
			}
			imgui.EndTabItem()
		}
		Drive_Item(fmt.tprintf("code.tab:%s", doc.rel))
		UI_Tooltip(doc.path)
		if imgui.BeginPopupContextItem(fmt.ctprintf("##tabctx%d", i)) {
			if imgui.MenuItem(fmt.ctprintf("%s  Save", ICON_FA_FLOPPY_DISK), nil, false, code_doc_dirty(doc)) do Code_SaveDoc(state, doc)
			if imgui.MenuItem(fmt.ctprintf("%s  Save As...", ICON_FA_FLOPPY_DISK)) {
				cm.selectRequest = i
				cm.active = i
				Prompt_Open(.SaveScriptAs, doc.rel)
			}
			imgui.Separator()
			if imgui.MenuItem(fmt.ctprintf("%s  Find Usages of This Script", ICON_FA_MAGNIFYING_GLASS)) do Asset_ShowUsages(state, doc.rel, false)
			Drive_Item("ctx:script-usages")
			imgui.Separator()
			if imgui.MenuItem(fmt.ctprintf("%s  Close", ICON_FA_XMARK), "Cmd+W") do closeIdx = i
			Drive_Item("ctx:close-tab")
			if imgui.MenuItem("Close Others", nil, false, len(cm.docs) > 1) do cm.closeOthers = i
			if imgui.MenuItem("Close All") do cm.closeOthers = -2
			imgui.Separator()
			if imgui.MenuItem(fmt.ctprintf("%s  Copy Path", ICON_FA_LINK)) do imgui.SetClipboardText(strings.clone_to_cstring(doc.rel, context.temp_allocator))
			if imgui.MenuItem(fmt.ctprintf("%s  Reveal in Finder", ICON_FA_FOLDER_OPEN)) do Editor_OpenExternally(state, filepath.dir(doc.path, context.temp_allocator))
			imgui.EndPopup()
		}
		if !open do closeIdx = i
	}
	cm.selectRequest = -1
	imgui.EndTabBar()
	if closeIdx >= 0 do code_request_close(closeIdx)
}

code_status_line :: proc(state: ^EditorState, doc: ^Code_Doc) {
	cm := &GlobalCode
	b := &doc.buffer
	c := b.cursors[0]
	imgui.SetCursorPosX(UI_SPACE)
	imgui.SetCursorPosY(imgui.GetCursorPosY() + 3)
	if UI_IconButton(ICON_FA_FLOPPY_DISK, "code.save", "Save (Ctrl/Cmd+S)", size = 22, tint = UI_ACCENT if code_doc_dirty(doc) else {}) {
		Code_SaveDoc(state, doc)
	}
	imgui.SameLine(0, UI_SPACE)
	imgui.AlignTextToFramePadding()
	line := buf.buffer_line_str(b, c.pos.line)
	UI_DimText(fmt.tprintf("Ln %d, Col %d", c.pos.line + 1, code_visual_col(line, c.pos.col) + 1))
	imgui.SameLine(0, UI_SPACE * 2)
	UI_DimText("Lua" if doc.isLua else doc.lang.name)
	errs, warns := code_diagnostic_counts(doc)
	imgui.SameLine(0, UI_SPACE * 2)
	imgui.PushStyleColorImVec4(.Text, UI_DANGER if errs > 0 else UI_TEXT_DIM)
	imgui.TextUnformatted(fmt.ctprintf("%s %d", ICON_FA_CIRCLE_XMARK, errs))
	imgui.PopStyleColor()
	imgui.SameLine(0, UI_SPACE)
	imgui.PushStyleColorImVec4(.Text, UI_WARNING if warns > 0 else UI_TEXT_DIM)
	imgui.TextUnformatted(fmt.ctprintf("%s %d", ICON_FA_TRIANGLE_EXCLAMATION, warns))
	imgui.PopStyleColor()
	imgui.SameLine(0, UI_SPACE * 2)
	status := ""
	col := UI_TEXT_DIM
	switch cm.lspState {
	case .Off:      status = "Language server off"
	case .Starting: status = "Starting lua-language-server…"
	case .Ready:    status = "lua-language-server"; col = UI_SUCCESS
	case .Failed:   status = cm.lspMessage if cm.lspMessage != "" else "Language server unavailable"; col = UI_WARNING
	}
	if !doc.isLua do status = ""
	imgui.PushStyleColorImVec4(.Text, col)
	imgui.TextUnformatted(fmt.ctprintf("%s %s", ICON_FA_CIRCLE if cm.lspState == .Ready else "", status))
	imgui.PopStyleColor()
}

CODE_STATUS_HEIGHT :: 30.0

// code_text_area draws the text and handles its input; returns whether it
// has keyboard focus.
code_text_area :: proc(state: ^EditorState, doc: ^Code_Doc) -> bool {
	cm := &GlobalCode
	b := &doc.buffer
	font := code_font()
	cm.lineH = code_font_size() + 5
	cm.charW = imgui.Font_CalcTextSizeA(font, code_font_size(), max(f32), 0, "M").x
	code_update_line_states(doc)

	avail := imgui.GetContentRegionAvail()
	lineCount := buf.buffer_line_count(b)
	digits := len(fmt.tprint(lineCount))
	gutterW := f32(max(digits, 3) + 2) * cm.charW + 14

	imgui.PushStyleColorImVec4(.ChildBg, CODE_BG)
	if cm.focusRequest {
		imgui.SetNextWindowFocus()
		cm.focusRequest = false
	}
	imgui.BeginChild("##code_area", {avail.x, max(avail.y - CODE_STATUS_HEIGHT, 50)}, {}, {.HorizontalScrollbar, .NoMove})
	imgui.PopStyleColor()
	defer imgui.EndChild()

	winPos := imgui.GetWindowPos()
	winSize := imgui.GetWindowSize()
	// The wheel over an overlay scrolls the overlay, not the code.
	@(static) lastScroll: [2]f32
	defer lastScroll = {imgui.GetScrollX(), imgui.GetScrollY()}
	if Code_OverlayHovered() && imgui.GetIO().MouseWheel != 0 {
		imgui.SetScrollX(lastScroll.x)
		imgui.SetScrollY(lastScroll.y)
	}
	scrollX := imgui.GetScrollX()
	scrollY := imgui.GetScrollY()
	pad := f32(6)

	// Content size (for the scrollbars): the widest line, once per edit.
	if !doc.widthValid || doc.widthVersion != b.version {
		doc.maxCols = 0
		for i in 0 ..< lineCount {
			l := buf.buffer_line_str(b, i)
			doc.maxCols = max(doc.maxCols, code_visual_col(l, len(l)))
		}
		doc.widthVersion = b.version
		doc.widthValid = true
	}
	maxCols := doc.maxCols
	imgui.SetCursorPos({0, 0})
	imgui.Dummy({gutterW + f32(maxCols + 4) * cm.charW, f32(lineCount) * cm.lineH + winSize.y * 0.5})

	// Input catcher covering the visible area.
	imgui.SetCursorPos({scrollX, scrollY})
	imgui.InvisibleButton("##code_input", {max(winSize.x, 1), max(winSize.y, 1)}, {.MouseButtonLeft})
	Drive_Item("code.area")
	hovered := imgui.IsItemHovered()
	active := imgui.IsItemActive()
	focused := imgui.IsWindowFocused()
	code_drop_target(state, doc, {imgui.GetIO().MousePos.x, imgui.GetIO().MousePos.y})
	Code_NodeDropMenu(state, doc) // a node dropped onto a method: its events
	if imgui.BeginPopupContextItem("##code_ctx") {
		code_text_context_menu(state, doc)
		imgui.EndPopup()
	}

	cm.textOrigin = {winPos.x + gutterW + pad - scrollX, winPos.y + pad - scrollY}
	cm.areaMin = {winPos.x, winPos.y}
	cm.areaMax = {winPos.x + winSize.x, winPos.y + winSize.y}

	io := imgui.GetIO()
	mouse := [2]f32{io.MousePos.x, io.MousePos.y}
	inPopup := cm.completion.open && point_in_rect(mouse, cm.popupMin, cm.popupMax)
	overOverlay := Code_OverlayHovered() // hover / signature / docs box: no clicks through

	// Mouse: click places the caret (Shift extends), double-click selects a
	// word, triple-click the line, drag selects.
	if hovered && !inPopup && !overOverlay {
		imgui.SetMouseCursor(.TextInput)
		if imgui.IsMouseClicked(.Left) {
			p := code_pos_at(b, mouse)
			clicks := imgui.GetMouseClickedCount(.Left)
			switch {
			case clicks == 2:
				code_set_single_cursor(b, p, false)
				buf.cursor_select_word(b, &b.cursors[0])
			case clicks >= 3:
				code_set_single_cursor(b, p, false)
				buf.cursor_select_line(b, &b.cursors[0])
			case io.KeyAlt:
				// Alt-click adds a cursor (or removes one already there).
				removed := false
				if len(b.cursors) > 1 {
					for c, i in b.cursors {
						if c.pos == p {ordered_remove(&b.cursors, i); removed = true; break}
					}
				}
				if !removed do append(&b.cursors, buf.Cursor{pos = p})
			case:
				code_set_single_cursor(b, p, io.KeyShift)
			}
			cm.completion.open = false
			cm.sigOpen = false
			cm.cursorMoved = time.tick_now()
			// Cmd+click: a node path (get_node / find_node / get_child) selects
			// the node; anything else goes to its definition.
			if code_primary_down() && clicks == 1 && !Code_GotoNode(state, doc, p) do code_lsp_goto_definition(doc)
		}
	}
	if active && imgui.IsMouseDragging(.Left) && imgui.GetMouseClickedCount(.Left) <= 1 && !io.KeyAlt {
		p := code_pos_at(b, mouse)
		code_set_single_cursor(b, p, true)
		doc.scrollToCursor = true
	}

	if focused do code_handle_keys(state, doc)

	// Hover (diagnostics + LSP hover) after the mouse rests on text.
	code_hover(doc, hovered && !inPopup && !active, mouse)

	if doc.scrollToCursor {
		doc.scrollToCursor = false
		c := code_primary(b).pos
		y := f32(c.line) * cm.lineH
		if y < scrollY do imgui.SetScrollY(y)
		else if y + cm.lineH * 2 > scrollY + winSize.y do imgui.SetScrollY(y + cm.lineH * 2 - winSize.y)
		x := f32(code_visual_col(buf.buffer_line_str(b, c.line), c.col)) * cm.charW
		textW := winSize.x - gutterW - pad * 2
		if x < scrollX do imgui.SetScrollX(max(x - cm.charW * 4, 0))
		else if x > scrollX + textW - cm.charW * 2 do imgui.SetScrollX(x - textW + cm.charW * 6)
	}

	code_draw(doc, winPos, winSize, gutterW, focused)
	return focused
}

// code_pos_at maps a screen position to a buffer position.
code_pos_at :: proc(b: ^buf.Buffer, screen: [2]f32) -> buf.Position {
	cm := &GlobalCode
	line := int((screen.y - cm.textOrigin.y) / cm.lineH)
	if screen.y < cm.textOrigin.y do line = 0
	line = clamp(line, 0, buf.buffer_line_count(b) - 1)
	vcol := int((screen.x - cm.textOrigin.x) / cm.charW + 0.5)
	text := buf.buffer_line_str(b, line)
	return {line, code_byte_col(text, max(vcol, 0))}
}

// code_screen_pos: top-left of the cell at a buffer position.
code_screen_pos :: proc(b: ^buf.Buffer, p: buf.Position) -> [2]f32 {
	cm := &GlobalCode
	line := buf.buffer_line_str(b, p.line)
	return {cm.textOrigin.x + f32(code_visual_col(line, p.col)) * cm.charW, cm.textOrigin.y + f32(p.line) * cm.lineH}
}

code_draw :: proc(doc: ^Code_Doc, winPos, winSize: imgui.Vec2, gutterW: f32, focused: bool) {
	cm := &GlobalCode
	b := &doc.buffer
	code_update_line_states(doc) // keys may have edited the text this frame
	dl := imgui.GetWindowDrawList()
	lineCount := buf.buffer_line_count(b)
	first := max(int((winPos.y - cm.textOrigin.y) / cm.lineH), 0)
	last := min(first + int(winSize.y / cm.lineH) + 2, lineCount - 1)
	c := code_primary(b)^
	_, _, hasSel := buf.selection_range(c)
	textX := cm.textOrigin.x
	findMatches := code_find_visible_matches(doc, first, last)
	textY := (cm.lineH - code_font_size()) * 0.5

	diags := code_diagnostics(doc)

	for ln in first ..= last {
		y := cm.textOrigin.y + f32(ln) * cm.lineH
		text := buf.buffer_line_str(b, ln)

		// Current line / selection backgrounds.
		if !hasSel && ln == c.pos.line && focused {
			imgui.DrawList_AddRectFilled(dl, {winPos.x, y}, {winPos.x + winSize.x, y + cm.lineH}, col_u32(ui_line(0.035)))
		}
		// Find matches.
		for m in findMatches {
			if m.start.line != ln do continue
			from := code_visual_col(text, m.start.col)
			to := code_visual_col(text, m.end.col)
			imgui.DrawList_AddRectFilled(dl, {textX + f32(from) * cm.charW, y + 1}, {textX + f32(max(to, from + 1)) * cm.charW, y + cm.lineH - 1}, col_u32({0.961, 0.722, 0.298, 0.28}), 2)
		}
		for cur in b.cursors {
			selStart, selEnd, curSel := buf.selection_range(cur)
			if !curSel || ln < selStart.line || ln > selEnd.line do continue
			from := code_visual_col(text, selStart.col) if ln == selStart.line else 0
			to := code_visual_col(text, selEnd.col) if ln == selEnd.line else code_visual_col(text, len(text)) + 1
			if to > from || ln != selEnd.line {
				imgui.DrawList_AddRectFilled(dl, {textX + f32(from) * cm.charW, y}, {textX + f32(max(to, from + 1)) * cm.charW, y + cm.lineH}, col_u32(ui_accent(0.30)))
			}
		}

		// Syntax-colored text.
		tokens, _ := Token_CacheGet(&doc.tokens, doc.lang, text, doc.lineStates[ln], b.version)
		v := 0
		at := 0
		for t in tokens {
			if t.start > at do v = code_draw_text(dl, textX, y + textY, v, text[at:t.start], col_u32(UI_TEXT))
			v = code_draw_text(dl, textX, y + textY, v, text[t.start:t.end], code_token_color(t.kind))
			at = t.end
		}
		if at < len(text) do code_draw_text(dl, textX, y + textY, v, text[at:], col_u32(UI_TEXT))
	}

	// Diagnostic squiggles.
	for d in diags {
		sl := d.range.start.line
		el := d.range.end.line
		if el < first || sl > last || sl >= lineCount do continue
		color := code_severity_color(d.severity)
		for ln in max(sl, first) ..= min(el, last, lineCount - 1) {
			text := buf.buffer_line_str(b, ln)
			from := code_byte_from_u16(text, d.range.start.character) if ln == sl else 0
			to := code_byte_from_u16(text, d.range.end.character) if ln == el else len(text)
			vf := code_visual_col(text, from)
			vt := code_visual_col(text, to)
			if vt <= vf do vt = vf + 1
			y := cm.textOrigin.y + f32(ln + 1) * cm.lineH - 2
			code_squiggle(dl, textX + f32(vf) * cm.charW, textX + f32(vt) * cm.charW, y, color, d.unnecessary)
		}
	}

	// Carets (blink while idle).
	if len(b.cursors) > 0 {
		cp := code_screen_pos(b, b.cursors[0].pos)
		Drive_ItemRect("code.caret", {cp.x, cp.y}, {cp.x + cm.charW, cp.y + cm.lineH}, inWindow = true)
	}
	if focused {
		blink := time.duration_seconds(time.tick_since(cm.cursorMoved))
		if blink < 0.6 || int(blink * 1.8) % 2 == 0 {
			for cur in b.cursors {
				p := code_screen_pos(b, cur.pos)
				imgui.DrawList_AddRectFilled(dl, {p.x, p.y + 1}, {p.x + 2, p.y + cm.lineH - 1}, col_u32(UI_ACCENT))
			}
		}
	}

	// Gutter (fixed while scrolling horizontally): line numbers + markers.
	imgui.DrawList_AddRectFilled(dl, {winPos.x, winPos.y}, {winPos.x + gutterW, winPos.y + winSize.y}, col_u32(CODE_BG))
	worst := make(map[int]int, 16, context.temp_allocator)
	for d in diags {
		sev := d.severity if d.severity > 0 else 1
		if old, ok := worst[d.range.start.line]; !ok || sev < old do worst[d.range.start.line] = sev
	}
	font := code_font()
	gutterMouse := [2]f32{imgui.GetIO().MousePos.x, imgui.GetIO().MousePos.y}
	for ln in first ..= last {
		y := cm.textOrigin.y + f32(ln) * cm.lineH + textY
		num := fmt.ctprintf("%d", ln + 1)
		w := imgui.Font_CalcTextSizeA(font, code_font_size(), max(f32), 0, num).x
		color := col_u32(UI_TEXT_DIM if ln == c.pos.line else UI_TEXT_FAINT)
		imgui.DrawList_AddTextImFontPtr(dl, font, code_font_size(), {winPos.x + gutterW - 10 - w, y}, color, num)
		// Breakpoints (click the gutter) and where the game is paused.
		rowMin := [2]f32{winPos.x, cm.textOrigin.y + f32(ln) * cm.lineH}
		rowMax := [2]f32{winPos.x + gutterW, rowMin.y + cm.lineH}
		Drive_ItemRect(fmt.tprintf("code.gutter:%d", ln + 1), rowMin, rowMax, inWindow = true)
		if doc.isLua && imgui.IsWindowHovered(imgui.HoveredFlags_AllowWhenBlockedByActiveItem) && imgui.IsMouseClicked(.Left) && point_in_rect(gutterMouse, rowMin, rowMax) {
			Debug_ToggleBreakpoint(doc.rel, ln + 1)
		}
		if Debug_HasBreakpoint(doc.rel, ln + 1) {
			imgui.DrawList_AddCircleFilled(dl, {winPos.x + 9, y + code_font_size() * 0.5}, 5, col_u32({0.92, 0.30, 0.29, 1}))
		}
		if Debug_CurrentLine(doc.rel) == ln + 1 {
			imgui.DrawList_AddRectFilled(dl, {winPos.x + gutterW, rowMin.y}, {winPos.x + winSize.x, rowMax.y}, col_u32({0.96, 0.72, 0.30, 0.16}))
			imgui.DrawList_AddTriangleFilled(dl, {winPos.x + 3, y + 2}, {winPos.x + 3, y + code_font_size() - 2}, {winPos.x + 13, y + code_font_size() * 0.5}, col_u32(UI_WARNING))
		}
		if sev, ok := worst[ln]; ok {
			imgui.DrawList_AddCircleFilled(dl, {winPos.x + 8, y + code_font_size() * 0.5}, 3.5, code_severity_color(sev))
		}
	}
}

code_squiggle :: proc(dl: ^imgui.DrawList, x0, x1, y: f32, color: u32, faint: bool) {
	if faint {
		imgui.DrawList_AddLine(dl, {x0, y + 1}, {x1, y + 1}, color & 0x80FFFFFF, 1)
		return
	}
	step := f32(3)
	x := x0
	up := true
	for x < x1 {
		nx := min(x + step, x1)
		imgui.DrawList_AddLine(dl, {x, y + (0 if up else 2)}, {nx, y + (2 if up else 0)}, color, 1.2)
		x = nx
		up = !up
	}
}

code_severity_color :: proc(sev: int) -> u32 {
	switch sev {
	case 2: return col_u32(UI_WARNING)
	case 3: return col_u32(UI_ACCENT)
	case 4: return col_u32(UI_TEXT_FAINT)
	}
	return col_u32(UI_DANGER)
}

// --- keyboard ----------------------------------------------------------------------
// Commands (save, undo, clipboard, find, multi-cursor, ...) are actions in
// actions.odin, dispatched before this runs; this handles caret movement,
// editing keys and typed text (with auto-closing pairs).

code_primary_down :: proc() -> bool {
	return imgui.IsKeyDown(.LeftCtrl) || imgui.IsKeyDown(.RightCtrl) || imgui.IsKeyDown(.LeftSuper) || imgui.IsKeyDown(.RightSuper)
}

code_pressed :: proc(k: imgui.Key) -> bool {
	return imgui.IsKeyPressed(k, true)
}

// code_merge_cursors sorts cursors and drops ones at the same position.
code_merge_cursors :: proc(b: ^buf.Buffer) {
	if len(b.cursors) <= 1 do return
	primary := b.cursors[len(b.cursors) - 1].pos
	slice.sort_by(b.cursors[:], proc(x, y: buf.Cursor) -> bool {return buf.position_less(x.pos, y.pos)})
	out := 0
	for i in 0 ..< len(b.cursors) {
		if out > 0 && b.cursors[out - 1].pos == b.cursors[i].pos do continue
		b.cursors[out] = b.cursors[i]
		out += 1
	}
	resize(&b.cursors, out)
	// Keep the most recent cursor last (it's the "primary" for scrolling).
	for c, i in b.cursors {
		if c.pos == primary {
			b.cursors[i], b.cursors[len(b.cursors) - 1] = b.cursors[len(b.cursors) - 1], b.cursors[i]
			break
		}
	}
}

// code_primary: the cursor that drives scrolling / status (last added).
code_primary :: proc(b: ^buf.Buffer) -> ^buf.Cursor {
	return &b.cursors[len(b.cursors) - 1]
}

code_handle_keys :: proc(state: ^EditorState, doc: ^Code_Doc) {
	cm := &GlobalCode
	b := &doc.buffer
	io := imgui.GetIO()
	shift := io.KeyShift
	alt := imgui.IsKeyDown(.LeftAlt) || imgui.IsKeyDown(.RightAlt)
	primary := code_primary_down()
	ctrl := Keys_PhysicalCtrl()
	cmd := Keys_Primary() // Cmd on macOS (ImGui swaps Cmd/Ctrl there)
	// macOS: Alt moves by word, Cmd to line/document ends. Elsewhere Ctrl
	// moves by word.
	wordMod := alt if ODIN_OS == .Darwin else ctrl
	lineMod := cmd if ODIN_OS == .Darwin else false
	versionBefore := b.version
	moved := false
	comp := &cm.completion

	// Completion popup navigation takes priority.
	if comp.open && len(comp.filtered) > 0 {
		switch {
		case code_pressed(.DownArrow) && !alt && !primary:
			comp.selected = (comp.selected + 1) % len(comp.filtered); comp.scrollTo = true; return
		case code_pressed(.UpArrow) && !alt && !primary:
			comp.selected = (comp.selected - 1 + len(comp.filtered)) % len(comp.filtered); comp.scrollTo = true; return
		case code_pressed(.PageDown):
			comp.selected = min(comp.selected + 8, len(comp.filtered) - 1); comp.scrollTo = true; return
		case code_pressed(.PageUp):
			comp.selected = max(comp.selected - 8, 0); comp.scrollTo = true; return
		case (imgui.IsKeyPressed(.Enter, false) || imgui.IsKeyPressed(.KeypadEnter, false) || imgui.IsKeyPressed(.Tab, false)) && !primary:
			code_accept_completion(doc)
			return
		}
	}
	if imgui.IsKeyPressed(.Escape, false) {
		code_snippet_clear()
		switch {
		case comp.open || cm.sigOpen:
			comp.open = false
			cm.sigOpen = false
		case cm.find.open:
			cm.find.open = false
		case len(b.cursors) > 1:
			p := code_primary(b).pos
			code_set_single_cursor(b, p, false)
		case:
			code_set_single_cursor(b, b.cursors[0].pos, false)
		}
		return
	}

	// Plain movement / editing keys (modified chords are actions).
	{
		switch {
		case code_pressed(.LeftArrow) && !(alt && primary):
			if !shift && !wordMod && !lineMod && code_collapse_selections(b, true) {
			} else if lineMod {
				for &cur in b.cursors do code_smart_home(b, &cur, shift)
			} else if wordMod {
				for &cur in b.cursors do buf.cursor_move_word_left(b, &cur, shift)
			} else {
				for &cur in b.cursors do buf.cursor_move_left(b, &cur, shift)
			}
			moved = true
		case code_pressed(.RightArrow) && !(alt && primary):
			if !shift && !wordMod && !lineMod && code_collapse_selections(b, false) {
			} else if lineMod {
				for &cur in b.cursors do buf.cursor_move_line_end(b, &cur, shift)
			} else if wordMod {
				for &cur in b.cursors do buf.cursor_move_word_right(b, &cur, shift)
			} else {
				for &cur in b.cursors do buf.cursor_move_right(b, &cur, shift)
			}
			moved = true
		case code_pressed(.UpArrow) && !alt:
			if lineMod do for &cur in b.cursors do buf.cursor_move_doc_start(b, &cur, shift)
			else do for &cur in b.cursors do buf.cursor_move_up(b, &cur, shift)
			moved = true
		case code_pressed(.DownArrow) && !alt:
			if lineMod do for &cur in b.cursors do buf.cursor_move_doc_end(b, &cur, shift)
			else do for &cur in b.cursors do buf.cursor_move_down(b, &cur, shift)
			moved = true
		case code_pressed(.Home):
			if primary do for &cur in b.cursors do buf.cursor_move_doc_start(b, &cur, shift)
			else do for &cur in b.cursors do code_smart_home(b, &cur, shift)
			moved = true
		case code_pressed(.End):
			if primary do for &cur in b.cursors do buf.cursor_move_doc_end(b, &cur, shift)
			else do for &cur in b.cursors do buf.cursor_move_line_end(b, &cur, shift)
			moved = true
		case code_pressed(.PageUp), code_pressed(.PageDown):
			lines := max(int((cm.areaMax.y - cm.areaMin.y) / cm.lineH) - 2, 1)
			if imgui.IsKeyDown(.PageUp) do lines = -lines
			for &cur in b.cursors do buf.cursor_move_page(b, &cur, lines, shift)
			moved = true
		case code_pressed(.Backspace) && !primary:
			if !wordMod && GlobalSettings.autoClosePairs && code_delete_pair(b) {
			} else {
				buf.buffer_backspace(b, wordMod)
			}
			moved = true
		case code_pressed(.Delete):
			buf.buffer_delete_forward(b, wordMod)
			moved = true
		case (code_pressed(.Enter) || code_pressed(.KeypadEnter)) && !primary:
			code_newline(doc)
			moved = true
		case code_pressed(.Tab) && !ctrl && !primary && !shift && Code_SnippetNext(doc):
		case code_pressed(.Tab) && !ctrl && !primary:
			if shift do buf.buffer_outdent(b)
			else do buf.buffer_indent(b, doc.useTabs)
			moved = true
		}
	}

	// Typed characters.
	typed := ""
	if !primary || alt {
		q := io.InputQueueCharacters
		if q.Size > 0 {
			sb := strings.builder_make(context.temp_allocator)
			chars := ([^]imgui.Wchar)(q.Data)[:q.Size]
			for c in chars {
				r := rune(c)
				if r < 32 || r == 127 do continue
				strings.write_rune(&sb, r)
			}
			typed = strings.to_string(sb)
		}
	}
	if typed != "" {
		if len(typed) == 1 && GlobalSettings.autoClosePairs && code_auto_pair(doc, typed[0]) {
		} else {
			buf.buffer_type_text(b, typed)
		}
		moved = true
	}

	if moved {
		code_merge_cursors(b)
		cm.cursorMoved = time.tick_now()
		doc.scrollToCursor = true
	}
	code_after_edit(doc, typed, b.version != versionBefore)
}

// code_collapse_selections: Left/Right with selections collapse them to
// their start/end. Returns false when nothing was selected.
code_collapse_selections :: proc(b: ^buf.Buffer, toStart: bool) -> bool {
	any := false
	for &c in b.cursors {
		if s, e_, ok := buf.selection_range(c); ok {
			c.pos = s if toStart else e_
			c.sel.active = false
			any = true
		}
	}
	return any
}

// code_smart_home: first non-blank column, or column 0 when already there.
code_smart_home :: proc(b: ^buf.Buffer, c: ^buf.Cursor, extend: bool) {
	line := buf.buffer_line_str(b, c.pos.line)
	first := 0
	for first < len(line) && (line[first] == ' ' || line[first] == '\t') do first += 1
	target := first if c.pos.col != first else 0
	if extend {
		if !c.sel.active do c.sel = {anchor = c.pos, active = true}
	} else {
		c.sel.active = false
	}
	c.pos.col = target
	c.has_goal = false
}

CODE_PAIRS := [?][2]u8{{'(', ')'}, {'[', ']'}, {'{', '}'}, {'"', '"'}, {'\'', '\''}}

// code_auto_pair handles a single typed character: wraps selections in
// brackets/quotes, inserts the closing character, or steps over a closer
// that is already there. Returns false to type the character normally.
code_auto_pair :: proc(doc: ^Code_Doc, ch: u8) -> bool {
	b := &doc.buffer
	opener, closer: u8
	isQuote := false
	for p in CODE_PAIRS {
		if ch == p[0] || ch == p[1] {
			opener, closer = p[0], p[1]
			isQuote = p[0] == p[1]
		}
	}
	if opener == 0 do return false
	group := buf.buffer_next_group(b)
	// Step over an existing closer (every cursor must sit before one).
	if ch == closer {
		all := true
		for c in b.cursors {
			line := buf.buffer_line_str(b, c.pos.line)
			if c.sel.active && c.sel.anchor != c.pos {all = false; break}
			if c.pos.col >= len(line) || line[c.pos.col] != closer {all = false; break}
		}
		if all {
			for &c in b.cursors do c.pos.col += 1
			return true
		}
		if !isQuote do return false
	}
	if ch != opener do return false
	// Wrap selections.
	anySel := false
	for c in b.cursors do if _, _, ok := buf.selection_range(c); ok do anySel = true
	if anySel {
		order := buf.buffer_sorted_cursor_indices(b)
		for i in order {
			c := &b.cursors[i]
			s, e_, ok := buf.selection_range(c^)
			if !ok do continue
			buf.buffer_insert_text(b, e_, string([]u8{closer}), group)
			buf.buffer_insert_text(b, s, string([]u8{opener}), group)
			// Keep the text selected, inside the brackets.
			e2 := e_
			if e_.line == s.line do e2.col += 1
			c.sel = {anchor = {s.line, s.col + 1}, active = true}
			c.pos = e2
		}
		return true
	}
	// Insert a pair only where it makes sense: before whitespace, a closer
	// or the end of the line; quotes not right after a word character.
	for c in b.cursors {
		line := buf.buffer_line_str(b, c.pos.line)
		if c.pos.col < len(line) {
			next := line[c.pos.col]
			if !(next == ' ' || next == '\t' || next == ')' || next == ']' || next == '}' || next == ',' || next == ';') do return false
		}
		if isQuote && c.pos.col > 0 {
			prev := line[c.pos.col - 1]
			if code_is_ident_byte(prev) || prev == opener || prev == '\\' do return false
		}
		// Not inside a string or comment.
		if doc.isLua && code_in_string_or_comment(doc, c.pos) do return false
	}
	buf.buffer_type_text(b, string([]u8{opener, closer}))
	for &c in b.cursors do c.pos.col -= 1
	return true
}

// code_in_string_or_comment: is `p` inside a string/comment token?
code_in_string_or_comment :: proc(doc: ^Code_Doc, p: buf.Position) -> bool {
	code_update_line_states(doc)
	line := buf.buffer_line_str(&doc.buffer, p.line)
	tokens, _ := Token_CacheGet(&doc.tokens, doc.lang, line, doc.lineStates[p.line] if p.line < len(doc.lineStates) else 0, doc.buffer.version)
	for t in tokens {
		if (t.kind == .String || t.kind == .Comment) && p.col > t.start && p.col < t.end do return true
		if t.kind == .Comment && p.col >= t.end && t.end == len(line) && p.col > t.start do return true
	}
	return false
}

// code_delete_pair: Backspace between an empty pair "(|)" removes both.
code_delete_pair :: proc(b: ^buf.Buffer) -> bool {
	for c in b.cursors {
		if c.sel.active && c.sel.anchor != c.pos do return false
		line := buf.buffer_line_str(b, c.pos.line)
		if c.pos.col == 0 || c.pos.col >= len(line) do return false
		ok := false
		for p in CODE_PAIRS do if line[c.pos.col - 1] == p[0] && line[c.pos.col] == p[1] do ok = true
		if !ok do return false
	}
	group := buf.buffer_next_group(b)
	order := buf.buffer_sorted_cursor_indices(b)
	for i in order {
		c := &b.cursors[i]
		buf.buffer_delete_range(b, {c.pos.line, c.pos.col - 1}, {c.pos.line, c.pos.col + 1}, group)
		c.pos.col -= 1
	}
	return true
}

// code_newline: Enter keeps the indentation and indents one more level
// after a line that opens a block (then/do/function/repeat/else/{/().
code_newline :: proc(doc: ^Code_Doc) {
	b := &doc.buffer
	if len(b.cursors) > 1 {
		buf.buffer_newline(b)
		return
	}
	c := b.cursors[0].pos
	before := strings.trim_space(buf.buffer_line_str(b, c.line)[:min(c.col, buf.buffer_line_len(b, c.line))])
	after := strings.trim_space(buf.buffer_line_str(b, c.line)[min(c.col, buf.buffer_line_len(b, c.line)):])
	buf.buffer_newline(b)
	if !doc.isLua do return
	opens := false
	// Drop a trailing comment.
	if i := strings.index(before, "--"); i >= 0 do before = strings.trim_space(before[:i])
	for kw in ([]string{"then", "do", "repeat", "else", "{", "(", "["}) {
		if strings.has_suffix(before, kw) do opens = true
	}
	if strings.has_suffix(before, ")") && (strings.has_prefix(before, "function") || strings.has_prefix(before, "local function") || strings.contains(before, "= function") || strings.contains(before, "(function")) {
		opens = true
	}
	if !opens do return
	indent := "\t" if doc.useTabs else strings.repeat(" ", code_tab_width(), context.temp_allocator)
	buf.buffer_type_text(b, indent)
	// Typing between a block opener and its "end"/"}"/")": push it down.
	if strings.has_prefix(after, "end") || strings.has_prefix(after, "}") || strings.has_prefix(after, ")") || strings.has_prefix(after, "]") {
		saved := b.cursors[0].pos
		buf.buffer_newline(b)
		buf.buffer_outdent(b) // the closer goes back to the opener's level
		code_set_single_cursor(b, saved, false)
	}
}

// --- hover -------------------------------------------------------------------------

code_hover :: proc(doc: ^Code_Doc, hovered: bool, mouse: [2]f32) {
	cm := &GlobalCode
	b := &doc.buffer
	if !hovered {
		cm.hoverValid = false
		return
	}
	p := code_pos_at(b, mouse)
	line := buf.buffer_line_str(b, p.line)
	// The mouse moved onto the hover box (to scroll it): keep it.
	keep := cm.hoverValid && Code_OverlayHovered("hover")
	if keep {
		p = cm.hoverPos
		line = buf.buffer_line_str(b, p.line)
	}
	// Only over actual text.
	endX := cm.textOrigin.x + f32(code_visual_col(line, len(line))) * cm.charW
	if !keep && (mouse.x > endX || mouse.x < cm.textOrigin.x) {
		cm.hoverValid = false
		return
	}
	if !cm.hoverValid || p != cm.hoverPos {
		// Same word? keep the timer.
		if !(cm.hoverValid && p.line == cm.hoverPos.line && code_word_start(b, p) == code_word_start(b, cm.hoverPos) && code_word_start(b, p).col != p.col) {
			cm.hoverSince = time.tick_now()
			cm.hoverSent = false
		}
		cm.hoverPos = p
		cm.hoverValid = true
	}
	if time.tick_since(cm.hoverSince) < 450 * time.Millisecond do return

	// Diagnostics under the mouse.
	msgs := make([dynamic]lsp.Diagnostic, context.temp_allocator)
	for d in code_diagnostics(doc) {
		sl, el := d.range.start.line, d.range.end.line
		if p.line < sl || p.line > el do continue
		from := code_byte_from_u16(buf.buffer_line_str(b, sl), d.range.start.character) if p.line == sl else 0
		to := code_byte_from_u16(buf.buffer_line_str(b, el), d.range.end.character) if p.line == el else len(line)
		if to <= from do to = from + 1
		if p.col >= from && p.col <= to do append(&msgs, d)
	}
	if !cm.hoverSent && doc.isLua {
		cm.hoverSent = true
		code_lsp_request_hover(doc, p)
	}
	hover := code_lsp_hover_text()
	if len(msgs) == 0 && hover == "" do return
	// Diagnostics, then the language server's docs: a bounded, scrollable
	// box under (or over) the word, inside the Code area.
	blocks := make([dynamic]Overlay_Block, context.temp_allocator)
	for d in msgs {
		append(&blocks, Overlay_Block{fmt.tprintf("%s  %s", ICON_FA_CIRCLE_XMARK if d.severity <= 1 else ICON_FA_TRIANGLE_EXCLAMATION, d.message), false, imgui.ColorConvertU32ToFloat4(code_severity_color(d.severity))})
	}
	if hover != "" do markdown_blocks(hover, &blocks)
	ws := code_word_start(b, p)
	anchor := code_screen_pos(b, ws)
	Code_Overlay_Draw("hover", anchor, cm.lineH, blocks[:])
}

// code_markdown renders LSP markdown simply: code fences in the mono font,
// other lines as text.
code_markdown :: proc(text: string) {
	inCode := false
	lines := strings.split_lines(text, context.temp_allocator)
	blank := false
	for l in lines {
		if strings.has_prefix(strings.trim_space(l), "```") {
			inCode = !inCode
			continue
		}
		if strings.trim_space(l) == "" {
			if !blank do imgui.Dummy({0, 2})
			blank = true
			continue
		}
		if strings.trim_space(l) == "---" {
			imgui.Separator()
			continue
		}
		blank = false
		if inCode {
			imgui.PushFont(code_font())
			imgui.PushStyleColorImVec4(.Text, {0.42, 0.68, 1.00, 1})
			imgui.TextUnformatted(strings.clone_to_cstring(l, context.temp_allocator))
			imgui.PopStyleColor()
			imgui.PopFont()
		} else {
			t, _ := strings.replace_all(l, "`", "", context.temp_allocator)
			t, _ = strings.replace_all(t, "**", "", context.temp_allocator)
			t, _ = strings.replace_all(t, "\\", "", context.temp_allocator)
			imgui.TextUnformatted(strings.clone_to_cstring(t, context.temp_allocator))
		}
	}
}

// --- close prompt ------------------------------------------------------------------

code_close_prompt :: proc(state: ^EditorState) {
	cm := &GlobalCode
	if cm.closePrompt < 0 do return
	if cm.closePrompt >= len(cm.docs) {
		cm.closePrompt = -1
		return
	}
	doc := cm.docs[cm.closePrompt]
	imgui.OpenPopup("Unsaved Changes###CodeClosePrompt")
	center := imgui.GetMainViewport().WorkPos + imgui.GetMainViewport().WorkSize * 0.5
	imgui.SetNextWindowPos(center, {}, {0.5, 0.5})
	if !imgui.BeginPopupModal("Unsaved Changes###CodeClosePrompt", nil, {.NoResize, .AlwaysAutoResize, .NoTitleBar}) do return
	UI_PanelTitle(ICON_FA_FILE_CODE, "Unsaved changes")
	imgui.Dummy({0, 4})
	imgui.TextUnformatted(fmt.ctprintf("Save changes to %s before closing?", doc.rel))
	imgui.Dummy({0, 8})
	idx := cm.closePrompt
	if UI_PrimaryButton("Save", "code.close-save", {96, 0}) {
		if Code_SaveDoc(state, doc) do code_close_doc(idx)
		cm.closePrompt = -1
		imgui.CloseCurrentPopup()
	}
	imgui.SameLine()
	if UI_Button("Don't Save", "code.close-discard", {96, 0}) {
		code_close_doc(idx)
		cm.closePrompt = -1
		imgui.CloseCurrentPopup()
	}
	imgui.SameLine()
	if UI_Button("Cancel", "code.close-cancel", {96, 0}) || imgui.IsKeyPressed(.Escape, false) {
		cm.closePrompt = -1
		imgui.CloseCurrentPopup()
	}
	imgui.EndPopup()
}

// --- new scripts -------------------------------------------------------------------

CODE_SCRIPT_TEMPLATE :: `-- $NAME$
---@class $CLASS$ : ScriptInstanceBase
local $CLASS$ = {}

-- Exported properties appear in the Inspector.
$CLASS$.properties = {
    speed = { type = "float", default = 100.0, label = "Speed" },
}

function $CLASS$:ready()
end

---@param dt number
function $CLASS$:update(dt)
end

return $CLASS$
`

// Editor_NewScript creates scripts/<name>.lua from a template (unique
// name) and opens it. Returns the project-relative path.
Editor_NewScript :: proc(state: ^EditorState, baseName := "new_script", template := CODE_SCRIPT_TEMPLATE) -> string {
	Lua_MarkProjectTypesDirty() // generated Lua types follow the project
	dir, _ := filepath.join({state.projectPath, "scripts"}, context.temp_allocator)
	os.make_directory(dir)
	name := baseName
	path := ""
	for i := 1; ; i += 1 {
		if i > 1 do name = fmt.tprintf("%s_%d", baseName, i)
		path, _ = filepath.join({dir, fmt.tprintf("%s.lua", name)}, context.temp_allocator)
		if !os.exists(path) do break
	}
	// PascalCase class name.
	cls := strings.builder_make(context.temp_allocator)
	upper := true
	for ch in name {
		if ch == '_' || ch == '-' {upper = true; continue}
		if upper && ch >= 'a' && ch <= 'z' do strings.write_rune(&cls, ch - 32)
		else do strings.write_rune(&cls, ch)
		upper = false
	}
	cn := strings.to_string(cls)
	text, _ := strings.replace_all(template, "$CLASS$", cn, context.temp_allocator)
	text, _ = strings.replace_all(text, "$NAME$", name, context.temp_allocator)
	if os.write_entire_file(path, transmute([]u8)text) != nil {
		Editor_Log(state, .Error, "Could not create %s", path)
		return ""
	}
	rel := fmt.tprintf("scripts/%s.lua", name)
	Editor_Log(state, .Info, "Created %s", rel)
	// Open at the first method (ready / update) of the template.
	line := 0
	for l, i in strings.split_lines(text, context.temp_allocator) {
		if strings.has_prefix(l, "function ") {line = i + 1; break}
	}
	Editor_OpenScript(state, rel, line, 0)
	return rel
}

// Editor_NewScriptForNode creates a script for a node from the template that
// suits its type: a CharacterMover gets the platformer template and is
// switched to Script mode (the script moves it with character_move_and_slide).
Editor_NewScriptForNode :: proc(state: ^EditorState, node: ^e.Node) -> string {
	// "PatrolDrone" -> patrol_drone.lua with class PatrolDrone.
	base := strings.to_snake_case(node.name, context.temp_allocator)
	if base == "" do base = "new_script"
	if node.typeId == e.CharacterMoverNode {
		rel := Editor_NewScript(state, base, e.CHARACTER_PLATFORMER_TEMPLATE)
		if rel != "" {
			(cast(^e.CharacterMoverNode)node).controlMode = .Script
			Editor_Log(state, .Info, "%s uses the platformer template; %s now moves by script", rel, node.name)
		}
		return rel
	}
	return Editor_NewScript(state, base)
}

// --- drive queries -----------------------------------------------------------------

// Code_DriveQuery answers "code.*" queries for test drives.
Code_DriveQuery :: proc(q: string) -> (string, bool) {
	cm := &GlobalCode
	doc: ^Code_Doc
	if cm.active >= 0 && cm.active < len(cm.docs) do doc = cm.docs[cm.active]
	switch q {
	case "code.open":
		return fmt.tprint(len(cm.docs)), true
	case "code.file":
		return doc.rel if doc != nil else "", true
	case "code.text":
		return buf.buffer_to_string(&doc.buffer, context.temp_allocator) if doc != nil else "", true
	case "code.line":
		if doc == nil do return "", true
		return buf.buffer_line_str(&doc.buffer, doc.buffer.cursors[0].pos.line), true
	case "code.cursor":
		if doc == nil do return "", true
		p := doc.buffer.cursors[0].pos
		return fmt.tprintf("%d:%d", p.line + 1, p.col + 1), true
	case "code.dirty":
		return "true" if doc != nil && code_doc_dirty(doc) else "false", true
	case "code.focused":
		return "true" if cm.focused else "false", true
	case "code.lsp":
		return strings.to_lower(fmt.tprint(cm.lspState), context.temp_allocator), true
	case "code.completion":
		if !cm.completion.open || !completion_indices_valid() do return "", true
		sb := strings.builder_make(context.temp_allocator)
		for i, n in cm.completion.filtered {
			if n > 0 do strings.write_string(&sb, ",")
			strings.write_string(&sb, code_completion_label(&cm.client.last_completion[i]))
		}
		return strings.to_string(sb), true
	case "code.token-bench":
		// "full=<ms> cached=<ms> tokenized=<lines>": re-tokenizing every line
		// (as before the cache) vs. the cached line-state pass.
		doc := code_active_doc()
		if doc == nil do return "", true
		b := &doc.buffer
		t0 := time.tick_now()
		state := syn.LINE_STATE_NORMAL
		for i in 0 ..< buf.buffer_line_count(b) do _, state = doc.lang.tokenize(buf.buffer_line_str(b, i), state, context.temp_allocator)
		full := time.duration_milliseconds(time.tick_since(t0))
		doc.statesVersion = -1
		code_update_line_states(doc)
		return fmt.tprintf("full=%.2f cached=%.2f tokenized=%d lines=%d", full, doc.tokens.lastUpdateMs, doc.tokens.tokenized, buf.buffer_line_count(b)), true
	case "code.token-speedup": // full re-tokenize time / cached pass time
		doc := code_active_doc()
		if doc == nil do return "0", true
		b := &doc.buffer
		t0 := time.tick_now()
		state := syn.LINE_STATE_NORMAL
		for i in 0 ..< buf.buffer_line_count(b) do _, state = doc.lang.tokenize(buf.buffer_line_str(b, i), state, context.temp_allocator)
		full := time.duration_milliseconds(time.tick_since(t0))
		doc.statesVersion = -1
		code_update_line_states(doc)
		return fmt.tprintf("%.1f", full / max(doc.tokens.lastUpdateMs, 0.001)), true
	case "code.overlays": return Code_OverlaysInside(), true // "ok <n>" when all inside the Code area
	case "code.update-ms": // the last line-state pass after an edit
		doc := code_active_doc()
		if doc == nil do return "", true
		return fmt.tprintf("%.2f", doc.tokens.lastUpdateMs), true
	case "code.completion-doc":
		if !cm.completion.open || cm.completion.selected >= len(cm.completion.filtered) do return "", true
		return cm.client.last_completion[cm.completion.filtered[cm.completion.selected]].documentation, true
	case "code.selection":
		if doc == nil do return "", true
		b := &doc.buffer
		s, e_, ok := buf.selection_range(code_primary(b)^)
		if !ok || s.line != e_.line do return "", true
		return buf.buffer_line_str(b, s.line)[s.col:e_.col], true
	case "code.signature":
		return code_signature_label() if cm.sigOpen else "", true
	case "code.errors":
		if doc == nil do return "0", true
		errs, _ := code_diagnostic_counts(doc)
		return fmt.tprint(errs), true
	case "code.diagnostics":
		if doc == nil do return "0", true
		return fmt.tprint(len(code_diagnostics(doc))), true
	case "code.diagnostic-messages":
		if doc == nil do return "", true
		sb := strings.builder_make(context.temp_allocator)
		for d in code_diagnostics(doc) do fmt.sbprintf(&sb, "%d: %s\n", d.range.start.line + 1, d.message)
		return strings.to_string(sb), true
	case "code.cursors":
		return fmt.tprint(len(doc.buffer.cursors)) if doc != nil else "0", true
	case "code.find":
		if doc == nil || !cm.find.open do return "", true
		matches := code_find_all(doc)
		return fmt.tprintf("%d", len(matches)), true
	case "code.font":
		return fmt.tprintf("%.0f", code_font_size()), true
	case "code.hover":
		return code_lsp_hover_text(), true
	}
	return "", false
}

// Code_ParseLocation finds a "path.lua:LINE" location in a log message
// (Lua errors and tracebacks use this form, sometimes with a leading "@").
Code_ParseLocation :: proc(msg: string) -> (path: string, line: int, ok: bool) {
	i := strings.index(msg, ".lua:")
	if i < 0 do return
	start := i
	for start > 0 {
		ch := msg[start - 1]
		if ch == ' ' || ch == '\t' || ch == '"' || ch == '\'' || ch == '[' || ch == '(' || ch == '@' do break
		start -= 1
	}
	j := i + 5
	for j < len(msg) && msg[j] >= '0' && msg[j] <= '9' {
		line = line * 10 + int(msg[j] - '0')
		j += 1
	}
	if line == 0 do return
	return msg[start:i + 4], line, true
}

// code_text_context_menu: right-click in the code.
code_text_context_menu :: proc(state: ^EditorState, doc: ^Code_Doc) {
	run :: proc(state: ^EditorState, id: string) {
		if a := Action_Find(id); a != nil do Action_Run(state, a)
	}
	item :: proc(state: ^EditorState, icon: string, id: string, enabled := true) {
		a := Action_Find(id)
		if a == nil do return
		sc := Action_ShortcutText(a)
		if imgui.MenuItem(fmt.ctprintf("%s  %s", icon, a.label), strings.clone_to_cstring(sc, context.temp_allocator) if sc != "" else nil, false, enabled) do Action_Run(state, a)
		Drive_Item(fmt.tprintf("ctx:%s", id))
	}
	GlobalCode.focusRequest = true
	lsp := GlobalCode.lspState == .Ready && doc.isLua
	item(state, ICON_FA_SCISSORS, "code.cut")
	item(state, ICON_FA_COPY, "code.copy")
	item(state, ICON_FA_PASTE, "code.paste")
	item(state, ICON_FA_CHECK, "code.select_all")
	imgui.Separator()
	item(state, ICON_FA_ARROW_POINTER, "code.definition", lsp)
	item(state, ICON_FA_MAGNIFYING_GLASS, "code.references", lsp)
	item(state, ICON_FA_PEN, "code.rename", lsp)
	item(state, ICON_FA_CODE, "code.format", lsp)
	imgui.Separator()
	item(state, ICON_FA_CODE, "code.comment")
	item(state, ICON_FA_CLONE, "code.duplicate_down")
	item(state, ICON_FA_TRASH, "code.delete_line")
	imgui.Separator()
	item(state, ICON_FA_MAGNIFYING_GLASS, "code.find")
	item(state, ICON_FA_RIGHT_LEFT, "code.replace")
	item(state, ICON_FA_ARROW_DOWN, "code.goto_line")
	_ = run
}
