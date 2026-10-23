package editor

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import buf "../odin_editor/buffer"
import lsp "../odin_editor/lsp"
import syn "../odin_editor/syntax"
import imgui "lib/imgui"

// ============================================================================
// Peek definition (Alt+F12) / peek references (Alt+Shift+F12): the target's
// code in a box under the caret line - syntax coloured, the line marked -
// without leaving the file; with several references a list on the left.
// Up / Down pick, Enter (or double-click) opens it, Esc / a click outside
// closes.
// ============================================================================

@(private = "file")
Peek_Loc :: struct {
	path:      string, // heap
	line, col: int,
	label:     string, // heap: "file:line  text"
}

@(private = "file")
peek: struct {
	waiting:  bool,
	refs:     bool,
	seq:      int,
	open:     bool,
	locs:     [dynamic]Peek_Loc,
	selected: int,
	anchor:   [2]f32,
	width:    f32,
	scrollTo: bool,
	// The selected location's file, split into lines (heap).
	textPath: string,
	text:     string,
	lines:    []string,
}

// Code_CmdPeek asks the language server; the box opens on the answer.
Code_CmdPeek :: proc(state: ^EditorState, refs: bool) {
	cm := &GlobalCode
	doc := code_active_doc()
	if doc == nil || cm.lspState != .Ready || !doc.isLua do return
	code_lsp_sync(doc)
	p := code_primary(&doc.buffer).pos
	line, ch := p.line, code_u16_col(buf.buffer_line_str(&doc.buffer, p.line), p.col)
	peek.seq = cm.client.location_seq
	if refs do lsp.client_request_references(&cm.client, doc.uri, line, ch)
	else do lsp.client_request_definition(&cm.client, doc.uri, line, ch)
	peek.waiting = true
	peek.refs = refs
	cm.defWaiting = false
	cm.refsWaiting = false
	sp := code_screen_pos(&doc.buffer, p)
	peek.anchor = {cm.areaMin.x + 8, sp.y + cm.lineH + 2}
	peek.width = cm.areaMax.x - cm.areaMin.x - 24
}

@(private = "file")
peek_clear :: proc() {
	for l in peek.locs {
		delete(l.path)
		delete(l.label)
	}
	clear(&peek.locs)
	delete(peek.textPath)
	delete(peek.text)
	delete(peek.lines)
	peek.textPath, peek.text, peek.lines = "", "", nil
}

Code_PeekShutdown :: proc() {
	peek_clear()
	delete(peek.locs)
}

// peek_load reads the selected location's file (open buffer or disk).
@(private = "file")
peek_load :: proc(path: string) {
	if peek.textPath == path do return
	delete(peek.textPath)
	delete(peek.text)
	delete(peek.lines)
	peek.textPath = strings.clone(path)
	if doc := code_doc_for_path(path); doc != nil {
		peek.text = buf.buffer_to_string(&doc.buffer)
	} else if data, err := os.read_entire_file(path, context.allocator); err == nil {
		peek.text = string(data)
	} else {
		peek.text = strings.clone("")
	}
	peek.lines = strings.split_lines(peek.text)
}

// Code_PeekUpdate takes the server's answer (each frame).
Code_PeekUpdate :: proc(state: ^EditorState) {
	cm := &GlobalCode
	if !peek.waiting || cm.client.location_seq == peek.seq do return
	peek.waiting = false
	peek_clear()
	for l in cm.client.last_locations {
		text := ""
		if data, err := os.read_entire_file(l.key, context.temp_allocator); err == nil {
			ls := strings.split_lines(string(data), context.temp_allocator)
			if l.range.start.line < len(ls) do text = strings.trim_space(ls[l.range.start.line])
		}
		append(&peek.locs, Peek_Loc{strings.clone(l.key), l.range.start.line, l.range.start.character, fmt.aprintf("%s:%d  %s", code_display_path(state, l.key), l.range.start.line + 1, text)})
	}
	if len(peek.locs) == 0 {
		Editor_Log(state, .Info, "No %s found", "references" if peek.refs else "definition")
		return
	}
	peek.selected = 0
	peek.open = true
	peek.scrollTo = true
}

// Code_PeekRender draws the box (in the Code window).
Code_PeekRender :: proc(state: ^EditorState) {
	if peek.open {
		imgui.OpenPopup("##peek")
		peek.open = false
	}
	imgui.SetNextWindowPos(peek.anchor, .Always)
	imgui.SetNextWindowSize({max(peek.width, 400), GlobalCode.lineH * 13 + 40}, .Always)
	imgui.PushStyleColorImVec4(.PopupBg, CODE_BG)
	imgui.PushStyleColorImVec4(.Border, UI_ACCENT_SOFT)
	imgui.PushStyleVar(.PopupBorderSize, 1.5)
	open := imgui.BeginPopup("##peek")
	imgui.PopStyleVar()
	imgui.PopStyleColor(2)
	if !open do return
	defer imgui.EndPopup()
	Drive_Item("code.peek")
	n := len(peek.locs)
	if n == 0 {
		imgui.CloseCurrentPopup()
		return
	}
	if imgui.IsKeyPressed(.Escape) {
		imgui.CloseCurrentPopup()
		GlobalCode.focusRequest = true
		return
	}
	if imgui.IsKeyPressed(.DownArrow) {peek.selected = (peek.selected + 1) % n; peek.scrollTo = true}
	if imgui.IsKeyPressed(.UpArrow) {peek.selected = (peek.selected + n - 1) % n; peek.scrollTo = true}
	loc := peek.locs[peek.selected]
	openIt := imgui.IsKeyPressed(.Enter) || imgui.IsKeyPressed(.KeypadEnter)
	// Header.
	imgui.TextColored(UI_ACCENT, "%s", fmt.ctprintf("%s  %s:%d", ICON_FA_EYE, filepath.base(loc.path), loc.line + 1))
	imgui.SameLine()
	UI_DimText(fmt.tprintf("%s - Enter opens, Esc closes", fmt.tprintf("%d references", n) if peek.refs else "definition"))
	h := imgui.GetContentRegionAvail().y
	if n > 1 {
		if imgui.BeginChild("##peek_list", {260, h}, {.Borders}, {}) {
			for l, i in peek.locs {
				if imgui.Selectable(fmt.ctprintf("%s##pl%d", l.label, i), peek.selected == i) {peek.selected = i; peek.scrollTo = true}
				Drive_Item(fmt.tprintf("code.peek-loc:%d", i))
				if peek.selected == i && peek.scrollTo do imgui.SetScrollHereY()
				if imgui.IsItemHovered() && imgui.IsMouseDoubleClicked(.Left) do openIt = true
			}
		}
		imgui.EndChild()
		imgui.SameLine()
	}
	peek_load(loc.path)
	if imgui.BeginChild("##peek_code", {0, h}, {}, {.HorizontalScrollbar}) {
		cm := &GlobalCode
		dl := imgui.GetWindowDrawList()
		font := code_font()
		imgui.PushFont(font)
		imgui.PushStyleVarImVec2(.ItemSpacing, {0, 0}) // rows as tight as the editor's
		defer imgui.PopStyleVar()
		state := syn.LINE_STATE_NORMAL
		lua := strings.has_suffix(loc.path, ".lua")
		for line, i in peek.lines {
			p := imgui.GetCursorScreenPos()
			if i == loc.line {
				imgui.DrawList_AddRectFilled(dl, p, {p.x + imgui.GetContentRegionAvail().x + 2000, p.y + cm.lineH}, col_u32(ui_accent(0.18)))
				if peek.scrollTo do imgui.SetScrollHereY(0.3)
			}
			ns := fmt.tprint(i + 1)
			num := fmt.ctprintf("%s%s  ", strings.repeat(" ", max(4 - len(ns), 0), context.temp_allocator), ns)
			imgui.DrawList_AddTextImFontPtr(dl, font, code_font_size(), {p.x, p.y + (cm.lineH - code_font_size()) * 0.5}, col_u32(UI_TEXT_FAINT), num)
			x0 := p.x + cm.charW * 6
			y := p.y + (cm.lineH - code_font_size()) * 0.5
			if lua {
				tokens: []syn.Token
				tokens, state = syn.tokenize_lua_line(line, state, context.temp_allocator)
				v, at := 0, 0
				for t in tokens {
					if t.start > at do v = code_draw_text(dl, x0, y, v, line[at:t.start], col_u32(UI_TEXT))
					v = code_draw_text(dl, x0, y, v, line[t.start:t.end], code_token_color(t.kind))
					at = t.end
				}
				if at < len(line) do code_draw_text(dl, x0, y, v, line[at:], col_u32(UI_TEXT))
			} else {
				code_draw_text(dl, x0, y, 0, line, col_u32(UI_TEXT))
			}
			imgui.Dummy({cm.charW * f32(len(line) + 8), cm.lineH})
			if imgui.IsItemHovered() && imgui.IsMouseDoubleClicked(.Left) {
				peek.locs[peek.selected].line = i
				openIt = true
			}
		}
		imgui.PopFont()
	}
	imgui.EndChild()
	peek.scrollTo = false
	if openIt {
		l := peek.locs[peek.selected]
		path := strings.clone(l.path, context.temp_allocator)
		imgui.CloseCurrentPopup()
		if Editor_OpenScript(state, path, l.line) {
			if d := code_active_doc(); d != nil {
				line := buf.buffer_line_str(&d.buffer, l.line)
				d.buffer.cursors[0].pos.col = code_byte_from_u16(line, l.col)
			}
		}
	}
}
