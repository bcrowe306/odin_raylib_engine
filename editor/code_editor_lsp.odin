package editor

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:time"
import buf "../odin_editor/buffer"
import lsp "../odin_editor/lsp"
import imgui "lib/imgui"

// ============================================================================
// Code editor <-> lua-language-server (LuaLS, built in lua-language-server/).
//
// The server runs with the project as its workspace and the engine's API
// definitions as a library (compiled into the editor and written to
// <project>/.ore/definitions, see lua_project.odin), so completion, hover
// and signature help know every engine global (Input, Scene, ...), the Node
// methods, and the ScriptInstanceBase callbacks (ready, update, on_*).
// Settings are passed through workspace/configuration (Client.settings).
// ============================================================================

CODE_LUA_GLOBALS :: []string{"Engine", "Input", "Audio", "Camera", "Physics", "Scene", "Log", "Project", "Tween", "Save", "Navigation"}

// code_repo_root finds the engine checkout (lua-language-server/ and
// engine/definitions/ live there): the working directory, or the
// executable's parent (bin/editor).
@(private = "file")
code_repo_root :: proc() -> string {
	candidates := make([dynamic]string, context.temp_allocator)
	if cwd, err := os.get_working_directory(context.temp_allocator); err == nil do append(&candidates, cwd)
	exeDir := filepath.dir(os.args[0], context.temp_allocator)
	if !filepath.is_abs(exeDir) {
		if cwd, err := os.get_working_directory(context.temp_allocator); err == nil {
			exeDir, _ = filepath.join({cwd, exeDir}, context.temp_allocator)
		}
	}
	append(&candidates, exeDir, filepath.dir(exeDir, context.temp_allocator))
	for c in candidates {
		p, _ := filepath.join({c, "lua-language-server", "bin", "lua-language-server"}, context.temp_allocator)
		if os.is_file(p) do return c
	}
	return ""
}

// Code_LuaServerPath is the lua-language-server binary ("" if not found):
// next to the editor (a shipped editor), or in the engine checkout.
Code_LuaServerPath :: proc() -> string {
	root := code_repo_root()
	if root == "" do return ""
	p, _ := filepath.join({root, "lua-language-server", "bin", "lua-language-server"}, context.temp_allocator)
	return p if os.is_file(p) else ""
}

@(private = "file")
json_quote :: proc(sb: ^strings.Builder, s: string) {
	strings.write_byte(sb, '"')
	for ch in s {
		switch ch {
		case '"':  strings.write_string(sb, `\"`)
		case '\\': strings.write_string(sb, `\\`)
		case:      strings.write_rune(sb, ch)
		}
	}
	strings.write_byte(sb, '"')
}

// code_lua_settings builds the LuaLS "Lua" settings section.
@(private = "file")
code_lua_settings :: proc(definitionsDir: string) -> string {
	sb := strings.builder_make(context.temp_allocator)
	strings.write_string(&sb, `{"Lua":{"runtime":{"version":"Lua 5.4"},"workspace":{"library":[`)
	json_quote(&sb, definitionsDir)
	strings.write_string(&sb, `],"checkThirdParty":false},"diagnostics":{"globals":[`)
	for g, i in CODE_LUA_GLOBALS {
		if i > 0 do strings.write_byte(&sb, ',')
		json_quote(&sb, g)
	}
	strings.write_string(&sb, `]},"completion":{"callSnippet":"Replace"},"telemetry":{"enable":false}}}`)
	return strings.to_string(sb)
}

@(private = "file")
code_lsp_start :: proc(state: ^EditorState) {
	cm := &GlobalCode
	cm.client = lsp.client_init()
	if !GlobalSettings.lspEnabled {
		cm.lspState = .Failed
		cm.lspMessage = "Language server off (Settings > Code Editor)"
		return
	}
	server := GlobalSettings.luaServerPath if GlobalSettings.luaServerPath != "" else Code_LuaServerPath()
	if server == "" {
		cm.lspState = .Failed
		cm.lspMessage = "lua-language-server not built (no completion)"
		Editor_Log(state, .Warn, "lua-language-server not found; build it in lua-language-server/ for Lua completion")
		return
	}
	defs := Lua_ProjectSetup(state)
	cm.client.settings = strings.clone(code_lua_settings(defs))
	root := state.projectPath
	if !filepath.is_abs(root) {
		cwd, _ := os.get_working_directory(context.temp_allocator)
		root, _ = filepath.join({cwd, root}, context.temp_allocator)
	}
	if !lsp.client_start(&cm.client, {server}, root) {
		cm.lspState = .Failed
		cm.lspMessage = "lua-language-server failed to start"
		Editor_Log(state, .Warn, "Could not start %s", server)
		return
	}
	lsp.client_initialize(&cm.client, lsp.file_uri(root, context.temp_allocator))
	cm.lspState = .Starting
}

code_lsp_shutdown :: proc() {
	cm := &GlobalCode
	if cm.lspState != .Off do lsp.client_destroy(&cm.client)
	cm.lspState = .Off
}

// code_lsp_update runs every frame: starts the server when the first Lua
// file opens, reads its messages, keeps open documents in sync and acts on
// answers (completion, signature help, go to definition).
code_lsp_update :: proc(state: ^EditorState) {
	cm := &GlobalCode
	if cm.lspState == .Off {
		hasLua := false
		for d in cm.docs do if d.isLua do hasLua = true
		if !hasLua do return
		code_lsp_start(state)
	}
	if cm.lspState == .Failed do return
	lsp.client_poll(&cm.client)
	if cm.client.dead {
		cm.lspState = .Failed
		cm.lspMessage = "lua-language-server stopped"
		Editor_Log(state, .Warn, "lua-language-server exited (code %d)", cm.client.exit_code)
		return
	}
	if cm.lspState == .Starting && cm.client.initialized {
		cm.lspState = .Ready
		cm.lspReadyAt = time.tick_now()
	}
	if cm.lspState != .Ready do return

	for d in cm.docs do code_lsp_sync(d)

	comp := &cm.completion
	hasDoc := cm.active >= 0 && cm.active < len(cm.docs)
	if comp.waiting && cm.client.completion_seq != comp.seq {
		comp.waiting = false
		loading := time.tick_since(cm.lspReadyAt) < 30 * time.Second
		if comp.open && len(cm.client.last_completion) == 0 && loading && comp.retries < 40 {
			comp.retries += 1
			comp.retryPending = true
			comp.retryAt = time.tick_now()
		} else if comp.open && hasDoc {
			code_refilter(cm.docs[cm.active])
		}
	}
	if comp.retryPending && time.tick_since(comp.retryAt) > 250 * time.Millisecond {
		comp.retryPending = false
		if comp.open && hasDoc do code_lsp_request_completion(cm.docs[cm.active], false, retry = true)
	}
	if cm.sigWaiting && cm.client.signature_seq != cm.sigSeq {
		cm.sigWaiting = false
		cm.sigOpen = len(cm.client.last_signatures) > 0
	}
	if cm.defWaiting && cm.client.location_seq != cm.defSeq {
		cm.defWaiting = false
		if len(cm.client.last_locations) > 0 {
			loc := cm.client.last_locations[0]
			path := strings.clone(loc.key, context.temp_allocator)
			if Editor_OpenScript(state, path, loc.range.start.line) {
				doc := cm.docs[cm.active]
				line := buf.buffer_line_str(&doc.buffer, loc.range.start.line)
				doc.buffer.cursors[0].pos.col = code_byte_from_u16(line, loc.range.start.character)
			}
		} else {
			Editor_Log(state, .Info, "No definition found")
		}
	}
}

// code_lsp_sync sends didOpen / didChange for a document.
code_lsp_sync :: proc(doc: ^Code_Doc) {
	cm := &GlobalCode
	if cm.lspState != .Ready || !doc.isLua do return
	if !doc.lspOpen {
		lsp.client_did_open(&cm.client, doc.uri, "lua", buf.buffer_to_string(&doc.buffer, context.temp_allocator), doc.buffer.version)
		doc.lspOpen = true
		doc.sentVersion = doc.buffer.version
		return
	}
	if doc.sentVersion != doc.buffer.version {
		lsp.client_did_change(&cm.client, doc.uri, buf.buffer_to_string(&doc.buffer, context.temp_allocator), doc.buffer.version)
		doc.sentVersion = doc.buffer.version
	}
}

code_lsp_did_save :: proc(doc: ^Code_Doc) {
	cm := &GlobalCode
	if cm.lspState != .Ready || !doc.lspOpen do return
	code_lsp_sync(doc)
	lsp.client_did_save(&cm.client, doc.uri, buf.buffer_to_string(&doc.buffer, context.temp_allocator))
}

code_lsp_did_close :: proc(doc: ^Code_Doc) {
	cm := &GlobalCode
	if cm.lspState != .Ready || !doc.lspOpen do return
	lsp.client_did_close(&cm.client, doc.uri)
	doc.lspOpen = false
}

@(private = "file")
code_lsp_position :: proc(doc: ^Code_Doc, p: buf.Position) -> (line, character: int) {
	return p.line, code_u16_col(buf.buffer_line_str(&doc.buffer, p.line), p.col)
}

// --- diagnostics -------------------------------------------------------------------

code_diagnostics :: proc(doc: ^Code_Doc) -> []lsp.Diagnostic {
	cm := &GlobalCode
	if cm.lspState == .Off || cm.lspState == .Failed || !doc.isLua do return nil
	return lsp.client_diagnostics_for(&cm.client, doc.uri)
}

code_diagnostic_counts :: proc(doc: ^Code_Doc) -> (errors, warnings: int) {
	for d in code_diagnostics(doc) {
		switch d.severity {
		case 0, 1: errors += 1
		case 2:    warnings += 1
		}
	}
	return
}

// --- completion --------------------------------------------------------------------

// code_lsp_request_completion asks for completions at the caret. The popup
// filters the answer locally as the user keeps typing.
code_lsp_request_completion :: proc(doc: ^Code_Doc, explicit: bool, retry := false) {
	cm := &GlobalCode
	if cm.lspState != .Ready || !doc.isLua do return
	b := &doc.buffer
	c := b.cursors[0].pos
	code_lsp_sync(doc)
	comp := &cm.completion
	if !retry {
		comp.retries = 0
		comp.retryPending = false
	}
	if !comp.open || explicit {
		comp.anchor = code_word_start(b, c)
		comp.selected = 0
	}
	line, ch := code_lsp_position(doc, c)
	comp.seq = cm.client.completion_seq
	lsp.client_request_completion(&cm.client, doc.uri, line, ch)
	comp.waiting = true
	comp.open = true
}

code_completion_label :: proc(item: ^lsp.CompletionItem) -> string {
	// LuaLS labels functions as "name(args)"; show/filter by the name.
	return item.filter_text if item.filter_text != "" else item.label
}

// code_fuzzy reports whether `pattern` is a case-insensitive subsequence of
// `s`; `prefix` when it also matches at the start.
@(private = "file")
code_fuzzy :: proc(s, pattern: string) -> (match, prefix: bool) {
	if pattern == "" do return true, true
	j := 0
	for i in 0 ..< len(s) {
		if j < len(pattern) && lower_byte(s[i]) == lower_byte(pattern[j]) do j += 1
	}
	if j < len(pattern) do return false, false
	return true, len(s) >= len(pattern) && strings.equal_fold(s[:len(pattern)], pattern)
}

@(private = "file")
lower_byte :: proc(c: u8) -> u8 {
	return c + 32 if c >= 'A' && c <= 'Z' else c
}

// code_refilter narrows the last completion list to the typed prefix.
code_refilter :: proc(doc: ^Code_Doc) {
	cm := &GlobalCode
	comp := &cm.completion
	b := &doc.buffer
	c := b.cursors[0].pos
	if c.line != comp.anchor.line || c.col < comp.anchor.col {
		comp.open = false
		return
	}
	line := buf.buffer_line_str(b, c.line)
	prefix := line[comp.anchor.col:min(c.col, len(line))]
	clear(&comp.filtered)
	prefixed := make([dynamic]int, context.temp_allocator)
	others := make([dynamic]int, context.temp_allocator)
	for &item, i in cm.client.last_completion {
		ok, pre := code_fuzzy(code_completion_label(&item), prefix)
		if !ok do continue
		if pre do append(&prefixed, i)
		else do append(&others, i)
	}
	append(&comp.filtered, ..prefixed[:])
	append(&comp.filtered, ..others[:])
	// An exact match of the only candidate has nothing left to offer.
	if len(comp.filtered) == 1 && code_completion_label(&cm.client.last_completion[comp.filtered[0]]) == prefix && !comp.waiting {
		clear(&comp.filtered)
	}
	if len(comp.filtered) == 0 && !comp.waiting && !comp.retryPending do comp.open = false
	comp.selected = clamp(comp.selected, 0, max(len(comp.filtered) - 1, 0))
}

// code_after_edit decides when to open, refresh or close the completion and
// signature popups after keyboard input.
code_after_edit :: proc(doc: ^Code_Doc, typed: string, changed: bool) {
	cm := &GlobalCode
	comp := &cm.completion
	b := &doc.buffer
	if !doc.isLua do return
	if typed != "" {
		last := typed[len(typed) - 1]
		switch {
		case last == '.' || last == ':':
			comp.open = false
			code_lsp_request_completion(doc, true)
		case code_is_ident_byte(last):
			ws := code_word_start(b, b.cursors[0].pos)
			line := buf.buffer_line_str(b, ws.line)
			startsWithDigit := ws.col < len(line) && line[ws.col] >= '0' && line[ws.col] <= '9'
			if startsWithDigit {
				comp.open = false
			} else if !comp.open || cm.client.completion_incomplete {
				code_lsp_request_completion(doc, !comp.open)
			} else {
				code_refilter(doc)
			}
		case:
			comp.open = false
		}
		switch last {
		case '(', ',':
			code_lsp_request_signature(doc)
		case ')':
			cm.sigOpen = false
		}
		return
	}
	if changed {
		if comp.open do code_refilter(doc)
		if cm.sigOpen do code_lsp_request_signature(doc)
	} else if comp.open {
		code_refilter(doc)
	}
}

Snippet_Stop :: struct {
	index:  int, // $N (0 = final caret)
	offset: int, // byte offset in the expanded text
	length: int, // placeholder length
}

// code_expand_snippet turns LSP snippet syntax into plain text and returns
// its tab stops in visiting order ($1, $2, ..., then $0).
code_expand_snippet :: proc(snippet: string) -> (text: string, stops: [dynamic]Snippet_Stop) {
	sb := strings.builder_make(context.temp_allocator)
	stops = make([dynamic]Snippet_Stop, context.temp_allocator)
	i := 0
	for i < len(snippet) {
		ch := snippet[i]
		if ch == '\\' && i + 1 < len(snippet) {
			strings.write_byte(&sb, snippet[i + 1])
			i += 2
			continue
		}
		if ch == '$' && i + 1 < len(snippet) {
			j := i + 1
			if snippet[j] == '{' {
				// ${N:placeholder} / ${N}
				k := j + 1
				n := 0
				for k < len(snippet) && snippet[k] >= '0' && snippet[k] <= '9' {n = n * 10 + int(snippet[k] - '0'); k += 1}
				placeholder := ""
				if k < len(snippet) && snippet[k] == ':' {
					depth := 1
					m := k + 1
					for m < len(snippet) && depth > 0 {
						if snippet[m] == '{' do depth += 1
						if snippet[m] == '}' do depth -= 1
						if depth > 0 do m += 1
					}
					placeholder = snippet[k + 1:min(m, len(snippet))]
					k = m
				}
				for k < len(snippet) && snippet[k] != '}' do k += 1
				append(&stops, Snippet_Stop{n, strings.builder_len(sb), len(placeholder)})
				strings.write_string(&sb, placeholder)
				i = k + 1
				continue
			}
			if snippet[j] >= '0' && snippet[j] <= '9' {
				n := 0
				for j < len(snippet) && snippet[j] >= '0' && snippet[j] <= '9' {n = n * 10 + int(snippet[j] - '0'); j += 1}
				append(&stops, Snippet_Stop{n, strings.builder_len(sb), 0})
				i = j
				continue
			}
		}
		strings.write_byte(&sb, ch)
		i += 1
	}
	// Visit $1..$N in order, $0 last.
	slice.sort_by(stops[:], proc(a, b: Snippet_Stop) -> bool {
		ka := a.index if a.index > 0 else max(int)
		kb := b.index if b.index > 0 else max(int)
		return ka < kb
	})
	return strings.to_string(sb), stops
}

@(private = "file")
code_advance :: proc(p: buf.Position, text: string) -> buf.Position {
	q := p
	for i in 0 ..< len(text) {
		if text[i] == '\n' {
			q.line += 1
			q.col = 0
		} else {
			q.col += 1
		}
	}
	return q
}

// code_accept_completion replaces the typed word with the chosen item.
code_accept_completion :: proc(doc: ^Code_Doc) {
	cm := &GlobalCode
	comp := &cm.completion
	if !comp.open || comp.selected >= len(comp.filtered) do return
	item := &cm.client.last_completion[comp.filtered[comp.selected]]
	b := &doc.buffer
	cursor := b.cursors[0].pos
	start := comp.anchor
	if item.has_text_edit && item.text_edit_range.start.line == cursor.line {
		line := buf.buffer_line_str(b, cursor.line)
		start = {cursor.line, min(code_byte_from_u16(line, item.text_edit_range.start.character), cursor.col)}
	}
	text := item.insert_text if item.insert_text != "" else item.label
	stops: [dynamic]Snippet_Stop
	if item.is_snippet do text, stops = code_expand_snippet(text)
	group := buf.buffer_next_group(b)
	if start != cursor do buf.buffer_delete_range(b, start, cursor, group)
	end := buf.buffer_insert_text(b, start, text, group)
	b.cursors[0].sel.active = false
	b.cursors[0].pos = end
	if len(stops) > 0 {
		// Remember the later stops (single-line snippets) as distances from
		// the line end: typing into the current placeholder doesn't move them.
		code_snippet_clear()
		cm.snippetLine = start.line
		lineLen := buf.buffer_line_len(b, start.line)
		for st, n in stops {
			if n == 0 do continue
			if strings.contains(text[:st.offset], "\n") do continue
			append(&cm.snippetStops, Snippet_Pending{fromEnd = lineLen - (start.col + st.offset), length = st.length})
		}
		code_snippet_select(b, start.line, start.col + stops[0].offset, stops[0].length)
	}
	comp.open = false
	doc.scrollToCursor = true
	if strings.contains(text, "(") do code_lsp_request_signature(doc)
}

@(private = "file")
code_kind_tag :: proc(kind: int) -> (string, imgui.Vec4) {
	switch lsp.CompletionKind(kind) {
	case .Function, .Method, .Constructor: return "fn", {0.42, 0.68, 1.00, 1}
	case .Field, .Property:                return "fld", {0.90, 0.78, 0.55, 1}
	case .Variable:                        return "var", {0.75, 0.80, 0.88, 1}
	case .Class, .Struct, .Interface:      return "cls", {0.95, 0.80, 0.40, 1}
	case .Module:                          return "mod", {0.35, 0.82, 0.86, 1}
	case .Keyword:                         return "kw", {0.78, 0.55, 0.95, 1}
	case .Snippet:                         return "snip", {0.60, 0.82, 0.52, 1}
	case .Enum, .EnumMember, .Constant, .Value: return "const", {0.96, 0.55, 0.45, 1}
	case .Event:                           return "evt", {0.96, 0.66, 0.42, 1}
	case .Text, .Unit, .Color, .File, .Reference, .Folder, .Operator, .TypeParameter:
	}
	return "txt", UI_TEXT_DIM
}

// code_completion_popup draws the completion list under the word being
// completed (foreground layer, so it can extend past the code window).
code_completion_popup :: proc(state: ^EditorState, doc: ^Code_Doc) {
	cm := &GlobalCode
	comp := &cm.completion
	cm.popupMin, cm.popupMax = {}, {}
	if !comp.open || len(comp.filtered) == 0 do return
	b := &doc.buffer
	items := cm.client.last_completion[:]
	font := code_font()
	dl := imgui.GetForegroundDrawList()
	io := imgui.GetIO()

	rowH := cm.lineH + 4
	maxRows := 10
	rows := min(len(comp.filtered), maxRows)
	// Width from the labels.
	labelW: f32 = 0
	detailW: f32 = 0
	for idx, n in comp.filtered {
		if n > 200 do break
		item := &items[idx]
		labelW = max(labelW, imgui.Font_CalcTextSizeA(font, code_font_size(), max(f32), 0, strings.clone_to_cstring(item.label, context.temp_allocator)).x)
		if item.detail != "" do detailW = max(detailW, imgui.CalcTextSize(strings.clone_to_cstring(item.detail, context.temp_allocator)).x)
	}
	tagW := cm.charW * 5 + 8
	w := clamp(tagW + labelW + 24 + min(detailW, 220), 260, 640)
	h := f32(rows) * rowH + 8

	// Selected item's documentation below the list (resolved on demand).
	sel := &items[comp.filtered[comp.selected]]
	if !sel.resolved && sel.documentation == "" && (cm.resolveIndex != comp.filtered[comp.selected] || cm.resolveSeq != cm.client.completion_seq) {
		cm.resolveIndex = comp.filtered[comp.selected]
		cm.resolveSeq = cm.client.completion_seq
		lsp.client_request_resolve(&cm.client, cm.resolveIndex)
	}
	doc_text := sel.documentation
	if len(doc_text) > 600 do doc_text = doc_text[:600]
	docH: f32 = 0
	if doc_text != "" {
		docH = imgui.CalcTextSize(strings.clone_to_cstring(doc_text, context.temp_allocator), nil, false, w - 16).y + 12
		docH = min(docH, 160)
	}

	anchor := code_screen_pos(b, comp.anchor)
	pos := [2]f32{anchor.x - tagW, anchor.y + cm.lineH + 2}
	display := io.DisplaySize
	if pos.y + h + docH > display.y - 8 do pos.y = anchor.y - h - docH - 2 // flip above
	pos.x = clamp(pos.x, 4, max(display.x - w - 4, 4))
	cm.popupMin = pos
	cm.popupMax = {pos.x + w, pos.y + h + docH}

	// Scroll the list to keep the selection visible.
	@(static) top := 0
	if comp.scrollTo || comp.selected < top || comp.selected >= top + rows {
		if comp.selected < top do top = comp.selected
		if comp.selected >= top + rows do top = comp.selected - rows + 1
		comp.scrollTo = false
	}
	top = clamp(top, 0, max(len(comp.filtered) - rows, 0))
	mouse := [2]f32{io.MousePos.x, io.MousePos.y}
	if point_in_rect(mouse, {pos.x, pos.y}, {pos.x + w, pos.y + h}) && io.MouseWheel != 0 {
		top = clamp(top - int(io.MouseWheel * 3), 0, max(len(comp.filtered) - rows, 0))
	}

	imgui.DrawList_AddRectFilled(dl, {pos.x + 2, pos.y + 3}, {cm.popupMax.x + 2, cm.popupMax.y + 3}, col_u32({0, 0, 0, 0.35}), 8)
	imgui.DrawList_AddRectFilled(dl, {pos.x, pos.y}, {cm.popupMax.x, cm.popupMax.y}, col_u32(UI_BG_RAISED), 8)
	imgui.DrawList_AddRect(dl, {pos.x, pos.y}, {cm.popupMax.x, cm.popupMax.y}, col_u32({1, 1, 1, 0.08}), 8)

	clicked := -1
	for r in 0 ..< rows {
		n := top + r
		if n >= len(comp.filtered) do break
		item := &items[comp.filtered[n]]
		y := pos.y + 4 + f32(r) * rowH
		mn := [2]f32{pos.x + 4, y}
		mx := [2]f32{pos.x + w - 4, y + rowH}
		hot := point_in_rect(mouse, mn, mx)
		if n == comp.selected {
			imgui.DrawList_AddRectFilled(dl, mn, mx, col_u32(UI_ACCENT_SOFT), 5)
		} else if hot {
			imgui.DrawList_AddRectFilled(dl, mn, mx, col_u32(UI_BG_HOVER), 5)
		}
		if hot && imgui.IsMouseClicked(.Left) do clicked = n
		tag, tagCol := code_kind_tag(item.kind)
		ty := y + (rowH - code_font_size()) * 0.5
		imgui.DrawList_AddTextImFontPtr(dl, font, code_font_size() - 2, {mn.x + 6, ty + 1}, col_u32(tagCol), strings.clone_to_cstring(tag, context.temp_allocator))
		imgui.DrawList_AddTextImFontPtr(dl, font, code_font_size(), {mn.x + tagW, ty}, col_u32(UI_TEXT), strings.clone_to_cstring(item.label, context.temp_allocator))
		if item.detail != "" {
			d := item.detail
			if len(d) > 40 do d = fmt.tprintf("%s…", d[:38])
			dc := strings.clone_to_cstring(d, context.temp_allocator)
			dw := imgui.CalcTextSize(dc).x
			if mn.x + tagW + labelW + 24 + dw < mx.x {
				imgui.DrawList_AddText(dl, {mx.x - 8 - dw, y + (rowH - imgui.GetFontSize()) * 0.5}, col_u32(UI_TEXT_DIM), dc)
			}
		}
		Drive_ItemRect(fmt.tprintf("code.completion:%s", code_completion_label(item)), mn, mx)
	}
	if len(comp.filtered) > rows {
		// Scroll indicator.
		frac := f32(rows) / f32(len(comp.filtered))
		barH := h * frac
		barY := pos.y + (h - barH) * f32(top) / f32(max(len(comp.filtered) - rows, 1))
		imgui.DrawList_AddRectFilled(dl, {pos.x + w - 4, barY + 2}, {pos.x + w - 1, barY + barH - 2}, col_u32({1, 1, 1, 0.18}), 2)
	}
	if doc_text != "" {
		y := pos.y + h
		imgui.DrawList_AddLine(dl, {pos.x + 8, y}, {pos.x + w - 8, y}, col_u32({1, 1, 1, 0.06}), 1)
		clip := imgui.Vec4{pos.x, y, pos.x + w, y + docH}
		imgui.DrawList_AddTextImFontPtr(dl, GlobalFonts.regular, imgui.GetFontSize(), {pos.x + 8, y + 6}, col_u32(UI_TEXT_DIM), strings.clone_to_cstring(doc_text, context.temp_allocator), nil, w - 16, &clip)
	}
	if clicked >= 0 {
		comp.selected = clicked
		code_accept_completion(doc)
		cm.focusRequest = true
	}
}

// --- signature help ----------------------------------------------------------------

code_lsp_request_signature :: proc(doc: ^Code_Doc) {
	cm := &GlobalCode
	if cm.lspState != .Ready || !doc.isLua do return
	code_lsp_sync(doc)
	line, ch := code_lsp_position(doc, doc.buffer.cursors[0].pos)
	cm.sigSeq = cm.client.signature_seq
	lsp.client_request_signature_help(&cm.client, doc.uri, line, ch)
	cm.sigWaiting = true
}

@(private = "file")
code_active_signature :: proc() -> (sig: ^lsp.SignatureInformation, param: int) {
	cm := &GlobalCode
	sigs := cm.client.last_signatures[:]
	if len(sigs) == 0 do return nil, -1
	i := clamp(cm.client.active_signature, 0, len(sigs) - 1)
	sig = &sigs[i]
	param = sig.active_parameter if sig.active_parameter >= 0 else cm.client.active_parameter
	return
}

code_signature_label :: proc() -> string {
	sig, _ := code_active_signature()
	return sig.label if sig != nil else ""
}

// code_signature_popup shows the call's signature above the caret with the
// current parameter highlighted.
code_signature_popup :: proc(doc: ^Code_Doc) {
	cm := &GlobalCode
	if !cm.sigOpen do return
	sig, param := code_active_signature()
	if sig == nil do return
	label := sig.label
	hiStart, hiEnd := -1, -1
	if param >= 0 && param < len(sig.parameters) && sig.parameters[param].label != "" {
		pl := sig.parameters[param].label
		// Search after the opening parenthesis (the name may contain it too).
		from := max(strings.index_byte(label, '('), 0)
		if i := strings.index(label[from:], pl); i >= 0 {
			hiStart = from + i
			hiEnd = hiStart + len(pl)
		}
	}
	font := code_font()
	dl := imgui.GetForegroundDrawList()
	measure :: proc(font: ^imgui.Font, s: string) -> f32 {
		return imgui.Font_CalcTextSizeA(font, code_font_size(), max(f32), 0, strings.clone_to_cstring(s, context.temp_allocator)).x
	}
	w := measure(font, label) + 20
	h := cm.lineH + 10
	caret := code_screen_pos(&doc.buffer, doc.buffer.cursors[0].pos)
	pos := [2]f32{caret.x - 12, caret.y - h - 4}
	if pos.y < cm.areaMin.y do pos.y = caret.y + cm.lineH + 4
	if cm.completion.open && pos.y > caret.y do pos.y = caret.y - h - 4
	pos.x = clamp(pos.x, 4, max(imgui.GetIO().DisplaySize.x - w - 4, 4))
	imgui.DrawList_AddRectFilled(dl, pos, {pos.x + w, pos.y + h}, col_u32(UI_BG_RAISED), 6)
	imgui.DrawList_AddRect(dl, pos, {pos.x + w, pos.y + h}, col_u32({1, 1, 1, 0.08}), 6)
	x := pos.x + 10
	y := pos.y + (h - code_font_size()) * 0.5
	draw :: proc(dl: ^imgui.DrawList, font: ^imgui.Font, x: ^f32, y: f32, s: string, col: u32) {
		if s == "" do return
		cs := strings.clone_to_cstring(s, context.temp_allocator)
		imgui.DrawList_AddTextImFontPtr(dl, font, code_font_size(), {x^, y}, col, cs)
		x^ += imgui.Font_CalcTextSizeA(font, code_font_size(), max(f32), 0, cs).x
	}
	if hiStart >= 0 {
		draw(dl, font, &x, y, label[:hiStart], col_u32(UI_TEXT_DIM))
		draw(dl, font, &x, y, label[hiStart:hiEnd], col_u32(UI_ACCENT))
		draw(dl, font, &x, y, label[hiEnd:], col_u32(UI_TEXT_DIM))
	} else {
		draw(dl, font, &x, y, label, col_u32(UI_TEXT_DIM))
	}
}

// --- hover / definition ------------------------------------------------------------

@(private = "file")
hoverRequestSeq := -1

code_lsp_request_hover :: proc(doc: ^Code_Doc, p: buf.Position) {
	cm := &GlobalCode
	if cm.lspState != .Ready do return
	code_lsp_sync(doc)
	line, ch := code_lsp_position(doc, p)
	hoverRequestSeq = cm.client.hover_seq
	lsp.client_request_hover(&cm.client, doc.uri, line, ch)
}

// code_lsp_hover_text: the answer to the latest hover request ("" while
// waiting or when the server had nothing).
code_lsp_hover_text :: proc() -> string {
	cm := &GlobalCode
	if cm.lspState != .Ready || hoverRequestSeq < 0 || cm.client.hover_seq == hoverRequestSeq do return ""
	return cm.client.last_hover
}

// code_lsp_goto_definition: F12 / Ctrl+click opens the definition (engine
// API definitions included).
code_lsp_goto_definition :: proc(doc: ^Code_Doc) {
	cm := &GlobalCode
	if cm.lspState != .Ready || !doc.isLua do return
	code_lsp_sync(doc)
	line, ch := code_lsp_position(doc, doc.buffer.cursors[0].pos)
	cm.defSeq = cm.client.location_seq
	lsp.client_request_definition(&cm.client, doc.uri, line, ch)
	cm.defWaiting = true
}

// --- snippet tab stops -------------------------------------------------------------

Snippet_Pending :: struct {
	fromEnd: int, // byte distance from the end of the line
	length:  int,
}

code_snippet_clear :: proc() {
	clear(&GlobalCode.snippetStops)
	GlobalCode.snippetLine = -1
}

@(private = "file")
code_snippet_select :: proc(b: ^buf.Buffer, line, col, length: int) {
	c := &b.cursors[0]
	c.sel = {anchor = {line, col}, active = length > 0}
	c.pos = {line, col + length}
}

// Code_SnippetNext moves to the next tab stop of the last accepted snippet
// (Tab). Returns false when there is none (Tab indents as usual).
Code_SnippetNext :: proc(doc: ^Code_Doc) -> bool {
	cm := &GlobalCode
	if len(cm.snippetStops) == 0 do return false
	b := &doc.buffer
	if len(b.cursors) != 1 || b.cursors[0].pos.line != cm.snippetLine {
		code_snippet_clear()
		return false
	}
	st := cm.snippetStops[0]
	ordered_remove(&cm.snippetStops, 0)
	lineLen := buf.buffer_line_len(b, cm.snippetLine)
	col := clamp(lineLen - st.fromEnd, 0, lineLen)
	code_snippet_select(b, cm.snippetLine, col, min(st.length, lineLen - col))
	doc.scrollToCursor = true
	return true
}
