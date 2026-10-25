package editor

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:time"
import buf "../odin_editor/buffer"
import syn "../odin_editor/syntax"
import imgui "lib/imgui"

// ============================================================================
// Files changed on disk and local history.
//
//   A script changed outside the editor reloads by itself when it has no
//   unsaved edits (one undoable edit); with edits, a bar over the code asks:
//   Reload (also undoable) or Keep Mine.
//   Every save keeps a copy in <project>/.rayzr/history/<script>/ (the 30
//   newest; .rayzr is never packaged). Local History lists them with a
//   preview; Restore puts one in the buffer (undoable, not saved).
// ============================================================================

HISTORY_KEEP :: 30

// code_replace_text replaces a doc's whole text as one undo step.
code_replace_text :: proc(doc: ^Code_Doc, text: string) {
	b := &doc.buffer
	cursor := b.cursors[0].pos
	last := buf.buffer_line_count(b) - 1
	group := buf.buffer_next_group(b)
	buf.buffer_delete_range(b, {0, 0}, {last, buf.buffer_line_len(b, last)}, group)
	buf.buffer_insert_text(b, {0, 0}, text, group)
	code_set_single_cursor(b, buf.buffer_clamp_position(b, cursor), false)
}

// Code_DiskBanner: the "changed on disk" bar (above the code area).
Code_DiskBanner :: proc(state: ^EditorState, doc: ^Code_Doc) {
	if !doc.diskConflict do return
	imgui.PushStyleColorImVec4(.ChildBg, {0.96, 0.72, 0.30, 0.16})
	defer imgui.PopStyleColor()
	if imgui.BeginChild("##disk_banner", {0, 32}, {}, {.NoScrollbar}) {
		imgui.SetCursorPos({10, 6})
		imgui.TextColored(UI_WARNING, "%s", fmt.ctprintf("%s  %s changed on disk while you have unsaved edits.", ICON_FA_TRIANGLE_EXCLAMATION, doc.rel))
		imgui.SameLine(0, UI_SPACE * 2)
		if UI_Button("Reload", "code.disk-reload") {
			if data, err := os.read_entire_file(doc.path, context.temp_allocator); err == nil {
				code_replace_text(doc, string(data))
				doc.savedVersion = doc.buffer.version
				Editor_Log(state, .Info, "Reloaded %s from disk (Undo brings your edits back)", doc.rel)
			}
			doc.diskConflict = false
		}
		UI_Tooltip("Take the file on disk (your edits stay in Undo)")
		imgui.SameLine()
		if UI_Button("Keep Mine", "code.disk-keep") do doc.diskConflict = false
		UI_Tooltip("Keep your edits; saving writes them over the file on disk")
	}
	imgui.EndChild()
}

// --- local history -------------------------------------------------------------------

@(private = "file")
history_dir :: proc(state: ^EditorState, doc: ^Code_Doc) -> string {
	name, _ := strings.replace_all(doc.rel, "/", "__", context.temp_allocator)
	dir, _ := filepath.join({state.projectPath, ".rayzr", "history", name}, context.temp_allocator)
	return dir
}

// Code_HistorySave keeps a copy of a saved script (call after a save).
Code_HistorySave :: proc(state: ^EditorState, doc: ^Code_Doc) {
	if state.projectPath == "" do return
	dir := history_dir(state, doc)
	_ = os.make_directory_all(dir)
	now := time.now()
	y, mo, d := time.date(now)
	h, mi, s := time.clock(now)
	ns := time.to_unix_nanoseconds(now) % 1_000_000_000 / 1_000_000
	name := fmt.tprintf("%04d%02d%02d-%02d%02d%02d-%03d.lua", y, int(mo), d, h, mi, s, ns)
	path, _ := filepath.join({dir, name}, context.temp_allocator)
	_ = os.write_entire_file(path, transmute([]u8)buf.buffer_to_string(&doc.buffer, context.temp_allocator))
	// Keep the newest HISTORY_KEEP.
	files := history_list(dir)
	for i in HISTORY_KEEP ..< len(files) {
		old, _ := filepath.join({dir, files[i]}, context.temp_allocator)
		_ = os.remove(old)
	}
}

// history_list: snapshot file names, newest first.
@(private = "file")
history_list :: proc(dir: string) -> []string {
	out := make([dynamic]string, context.temp_allocator)
	f, err := os.open(dir)
	if err != nil do return nil
	defer os.close(f)
	infos, _ := os.read_dir(f, -1, context.temp_allocator)
	for fi in infos do if strings.has_suffix(fi.name, ".lua") do append(&out, strings.clone(fi.name, context.temp_allocator))
	slice.sort_by(out[:], proc(a, b: string) -> bool {return a > b})
	return out[:]
}

@(private = "file")
hist: struct {
	open:     bool,
	doc:      ^Code_Doc,
	files:    [dynamic]string, // heap
	selected: int,
	text:     string, // the selected snapshot (heap)
	textFor:  int,
}

@(private = "file")
hist_clear :: proc() {
	for f in hist.files do delete(f)
	clear(&hist.files)
	delete(hist.text)
	hist.text = ""
	hist.textFor = -1
}

Code_HistoryShutdown :: proc() {
	hist_clear()
	delete(hist.files)
}

// Code_CmdLocalHistory opens the list for the active script.
Code_CmdLocalHistory :: proc(state: ^EditorState) {
	doc := code_active_doc()
	if doc == nil do return
	hist_clear()
	for f in history_list(history_dir(state, doc)) do append(&hist.files, strings.clone(f))
	if len(hist.files) == 0 {
		Editor_Log(state, .Info, "No local history for %s yet (it is kept when you save)", doc.rel)
		return
	}
	hist.doc = doc
	hist.selected = 0
	hist.open = true
}

// Code_HistoryRender draws the Local History dialog.
Code_HistoryRender :: proc(state: ^EditorState) {
	if hist.open {
		imgui.OpenPopup("Local History###LocalHistory")
		hist.open = false
	}
	io := imgui.GetIO()
	imgui.SetNextWindowSize({820, 500}, .Appearing)
	imgui.SetNextWindowPos({io.DisplaySize.x * 0.5, io.DisplaySize.y * 0.5}, .Appearing, {0.5, 0.5})
	if !imgui.BeginPopupModal("Local History###LocalHistory", nil, {.NoTitleBar}) do return
	defer imgui.EndPopup()
	doc := hist.doc
	if doc == nil || len(hist.files) == 0 || code_doc_for_path(doc.path) == nil {
		imgui.CloseCurrentPopup()
		return
	}
	UI_PanelTitle(ICON_FA_ROTATE_LEFT, fmt.tprintf("Local History - %s", doc.rel))
	imgui.SameLine(0, UI_SPACE)
	UI_DimText(fmt.tprintf("%d saved version(s)", len(hist.files)))
	h := imgui.GetContentRegionAvail().y - 44
	n := len(hist.files)
	if imgui.IsKeyPressed(.DownArrow) do hist.selected = (hist.selected + 1) % n
	if imgui.IsKeyPressed(.UpArrow) do hist.selected = (hist.selected + n - 1) % n
	if imgui.BeginChild("##hist_list", {230, h}, {.Borders}, {}) {
		for f, i in hist.files {
			// "20261023-171455-123.lua" -> "2026-10-23 17:14:55"
			label := f
			if len(f) >= 15 do label = fmt.tprintf("%s-%s-%s  %s:%s:%s", f[0:4], f[4:6], f[6:8], f[9:11], f[11:13], f[13:15])
			if imgui.Selectable(fmt.ctprintf("%s##h%d", label, i), hist.selected == i) do hist.selected = i
			Drive_Item(fmt.tprintf("history.item:%d", i))
		}
	}
	imgui.EndChild()
	imgui.SameLine()
	if hist.textFor != hist.selected {
		delete(hist.text)
		path, _ := filepath.join({history_dir(state, doc), hist.files[hist.selected]}, context.temp_allocator)
		data, err := os.read_entire_file(path, context.allocator)
		hist.text = string(data) if err == nil else strings.clone("")
		hist.textFor = hist.selected
	}
	if imgui.BeginChild("##hist_text", {0, h}, {.Borders}, {.HorizontalScrollbar}) {
		cm := &GlobalCode
		dl := imgui.GetWindowDrawList()
		imgui.PushFont(code_font())
		imgui.PushStyleVarImVec2(.ItemSpacing, {0, 0})
		st := syn.LINE_STATE_NORMAL
		for line in strings.split_lines(hist.text, context.temp_allocator) {
			p := imgui.GetCursorScreenPos()
			y := p.y + (cm.lineH - code_font_size()) * 0.5
			tokens: []syn.Token
			tokens, st = syn.tokenize_lua_line(line, st, context.temp_allocator)
			v, at := 0, 0
			for t in tokens {
				if t.start > at do v = code_draw_text(dl, p.x + 6, y, v, line[at:t.start], col_u32(UI_TEXT))
				v = code_draw_text(dl, p.x + 6, y, v, line[t.start:t.end], code_token_color(t.kind))
				at = t.end
			}
			if at < len(line) do code_draw_text(dl, p.x + 6, y, v, line[at:], col_u32(UI_TEXT))
			imgui.Dummy({cm.charW * f32(len(line) + 2), cm.lineH})
		}
		imgui.PopStyleVar()
		imgui.PopFont()
	}
	imgui.EndChild()
	imgui.SetCursorPosX(imgui.GetWindowWidth() - 16 - 120 - 90 - UI_SPACE)
	if UI_Button("Close", "history.close", {90, 30}) || imgui.IsKeyPressed(.Escape) {
		imgui.CloseCurrentPopup()
		return
	}
	imgui.SameLine(0, UI_SPACE)
	if UI_PrimaryButton("Restore", "history.restore", {120, 30}) {
		code_replace_text(doc, hist.text)
		Editor_Log(state, .Info, "Restored %s from %s (not saved; Undo goes back)", doc.rel, hist.files[hist.selected])
		imgui.CloseCurrentPopup()
		GlobalCode.focusRequest = true
	}
}
