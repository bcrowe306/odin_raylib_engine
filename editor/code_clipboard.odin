package editor

import "core:fmt"
import "core:strings"
import buf "../odin_editor/buffer"
import imgui "lib/imgui"

// ============================================================================
// Code tab clipboard: whole-line copies paste as lines above the cursor,
// multi-line pastes are re-indented to where they go, and the last copies
// and cuts are kept for Cmd+Shift+V (clipboard history). Copy Path /
// Absolute Path / Location.
// ============================================================================

CLIPBOARD_HISTORY_MAX :: 20

Clip_Entry :: struct {
	text:      string,
	wholeLine: bool,
}

@(private = "file")
clip: struct {
	last:       string, // the text of our last copy (heap)
	wholeLine:  bool,   // ... made without a selection: whole lines
	history:    [dynamic]Clip_Entry, // newest first (heap)
	pickerOpen: bool,
	pickerSel:  int,
}

// code_clipboard_set puts text on the system clipboard and remembers it.
code_clipboard_set :: proc(text: string, wholeLine: bool) {
	imgui.SetClipboardText(strings.clone_to_cstring(text, context.temp_allocator))
	delete(clip.last)
	clip.last = strings.clone(text)
	clip.wholeLine = wholeLine
	if strings.trim_space(text) == "" do return
	for h, i in clip.history {
		if h.text != text do continue
		delete(h.text)
		ordered_remove(&clip.history, i)
		break
	}
	inject_at(&clip.history, 0, Clip_Entry{strings.clone(text), wholeLine})
	for len(clip.history) > CLIPBOARD_HISTORY_MAX do delete(pop(&clip.history).text)
}

// code_clipboard_is_whole_line: is this clipboard text our whole-line copy?
code_clipboard_is_whole_line :: proc(text: string) -> bool {
	return clip.wholeLine && text == clip.last
}

Code_ClipboardHistory :: proc() -> []Clip_Entry {return clip.history[:]}

Code_ClipboardShutdown :: proc() {
	delete(clip.last)
	for h in clip.history do delete(h.text)
	delete(clip.history)
	clip = {}
}

// code_reindent re-bases multi-line text pasted at `indent` (the cursor's
// line has only whitespace before it): the lines' common indentation is
// replaced by `indent`; the first line goes where the cursor is.
code_reindent :: proc(text, indent: string) -> string {
	lines := strings.split(text, "\n", context.temp_allocator)
	if len(lines) < 2 do return text
	lead :: proc(l: string) -> string {return l[:len(l) - len(strings.trim_left(l, " \t"))]}
	common := -1
	for l in lines {
		if strings.trim_space(l) == "" do continue
		n := len(lead(l))
		if common < 0 || n < common do common = n
	}
	if common < 0 do common = 0
	sb := strings.builder_make(context.temp_allocator)
	for l, i in lines {
		if i > 0 do strings.write_byte(&sb, '\n')
		body := l
		n := min(common, len(lead(l)))
		body = l[n:]
		if i > 0 && strings.trim_space(l) != "" do strings.write_string(&sb, indent)
		strings.write_string(&sb, body)
	}
	return strings.to_string(sb)
}

// code_paste_text pastes text at every cursor: whole-line copies above the
// cursor's line, one line per cursor when the counts match, else at the
// cursor with re-indentation. Returns false when nothing applied.
code_paste_text :: proc(doc: ^Code_Doc, text: string) {
	b := &doc.buffer
	lines := strings.split(strings.trim_suffix(text, "\n"), "\n", context.temp_allocator)
	anySel := false
	for c in b.cursors do if _, _, ok := buf.selection_range(c); ok do anySel = true
	group := buf.buffer_next_group(b)
	order := buf.buffer_sorted_cursor_indices(b)

	if code_clipboard_is_whole_line(text) && !anySel {
		// Whole lines above each cursor's line (bottom-up: positions stay valid).
		perCursor := len(b.cursors) > 1 && len(lines) == len(b.cursors)
		#reverse for i, n in order {
			c := &b.cursors[i]
			ins := strings.concatenate({lines[n], "\n"}, context.temp_allocator) if perCursor else text
			buf.buffer_insert_text(b, {c.pos.line, 0}, ins, group)
		}
		// Cursors follow their lines down.
		added := 0
		for i in order {
			added += 1 if perCursor else strings.count(text, "\n")
			b.cursors[i].pos.line += added
		}
		return
	}
	if len(b.cursors) > 1 && len(lines) == len(b.cursors) {
		#reverse for i, n in order {
			c := &b.cursors[i]
			if s, e_, ok := buf.selection_range(c^); ok {
				buf.buffer_delete_range(b, s, e_, group)
				c.pos = s
				c.sel.active = false
			}
			c.pos = buf.buffer_insert_text(b, c.pos, lines[n], group)
		}
		return
	}
	#reverse for i in order {
		c := &b.cursors[i]
		if s, e_, ok := buf.selection_range(c^); ok {
			buf.buffer_delete_range(b, s, e_, group)
			c.pos = s
			c.sel.active = false
		}
		t := text
		line := buf.buffer_line_str(b, c.pos.line)
		before := line[:min(c.pos.col, len(line))]
		if strings.contains(text, "\n") && strings.trim_left(before, " \t") == "" {
			t = code_reindent(text, strings.clone(before, context.temp_allocator))
		}
		c.pos = buf.buffer_insert_text(b, c.pos, t, group)
	}
}

// Code_CmdClipboardHistory (Cmd+Shift+V) opens the history picker.
Code_CmdClipboardHistory :: proc(state: ^EditorState) {
	if code_active_doc() == nil || len(clip.history) == 0 do return
	clip.pickerOpen = true
	clip.pickerSel = 0
}

// Code_ClipboardPicker draws the history picker at the caret (Code window).
Code_ClipboardPicker :: proc(state: ^EditorState, doc: ^Code_Doc) {
	if clip.pickerOpen {
		imgui.OpenPopup("##clip_history")
		clip.pickerOpen = false
		p := code_screen_pos(&doc.buffer, doc.buffer.cursors[0].pos)
		imgui.SetNextWindowPos({p.x, p.y + GlobalCode.lineH + 2})
	}
	imgui.SetNextWindowSizeConstraints({320, 0}, {560, 420})
	if !imgui.BeginPopup("##clip_history") do return
	defer imgui.EndPopup()
	UI_DimText(fmt.tprintf("%s  Clipboard history - Enter pastes", ICON_FA_PASTE))
	n := len(clip.history)
	if n == 0 {
		imgui.CloseCurrentPopup()
		return
	}
	if imgui.IsKeyPressed(.DownArrow) do clip.pickerSel = (clip.pickerSel + 1) % n
	if imgui.IsKeyPressed(.UpArrow) do clip.pickerSel = (clip.pickerSel + n - 1) % n
	pick := -1
	for e, i in clip.history {
		h := e.text
		first := strings.trim_space(h)
		if j := strings.index_byte(first, '\n'); j >= 0 do first = first[:j]
		if len(first) > 70 do first = fmt.tprintf("%s…", first[:68])
		more := strings.count(strings.trim_suffix(h, "\n"), "\n")
		label := fmt.ctprintf("%s%s##clip%d", first, fmt.tprintf("   (+%d lines)", more) if more > 0 else "", i)
		if GlobalFonts.mono != nil do imgui.PushFont(GlobalFonts.mono)
		if imgui.Selectable(label, clip.pickerSel == i) do pick = i
		if GlobalFonts.mono != nil do imgui.PopFont()
		Drive_Item(fmt.tprintf("clip.item:%d", i))
		if clip.pickerSel == i && imgui.IsItemVisible() == false do imgui.SetScrollHereY()
	}
	if imgui.IsKeyPressed(.Enter) || imgui.IsKeyPressed(.KeypadEnter) do pick = clip.pickerSel
	if imgui.IsKeyPressed(.Escape) do imgui.CloseCurrentPopup()
	if pick >= 0 {
		e := clip.history[pick]
		text := strings.clone(e.text, context.temp_allocator)
		code_clipboard_set(text, e.wholeLine) // becomes the newest entry, with its kind
		code_paste_text(doc, text)
		code_touched(doc)
		imgui.CloseCurrentPopup()
	}
}

// Code_CmdCopyPath copies the active script's path: project-relative,
// absolute, or with the caret's line ("scripts/x.lua:12").
Code_CmdCopyPath :: proc(state: ^EditorState, kind: enum {Relative, Absolute, Location}) {
	doc := code_active_doc()
	if doc == nil do return
	text := doc.rel
	switch kind {
	case .Relative:
	case .Absolute: text = doc.path
	case .Location: text = fmt.tprintf("%s:%d", doc.rel, doc.buffer.cursors[0].pos.line + 1)
	}
	imgui.SetClipboardText(strings.clone_to_cstring(text, context.temp_allocator))
	Editor_Log(state, .Info, "Copied %s", text)
}
