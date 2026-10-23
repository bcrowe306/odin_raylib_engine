package editor

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import buf "../odin_editor/buffer"
import lsp "../odin_editor/lsp"
import imgui "lib/imgui"

// ============================================================================
// Rename preview: the language server's rename edits (F2) are listed by
// file - each line before and after - and applied (one undo step per file)
// only when you press Apply.
// ============================================================================

@(private = "file")
Preview_Line :: struct {
	key:           string, // file (uri key / path)
	line:          int,
	before, after: string, // the whole line (heap)
}

@(private = "file")
rp: struct {
	open:  bool,
	edits: [dynamic]lsp.Code_Action_Edit, // owned copies
	lines: [dynamic]Preview_Line,
	name:  string,
}

@(private = "file")
rp_clear :: proc() {
	for e_ in rp.edits {
		delete(e_.key)
		delete(e_.new_text)
	}
	clear(&rp.edits)
	for l in rp.lines {
		delete(l.key)
		delete(l.before)
		delete(l.after)
	}
	clear(&rp.lines)
	delete(rp.name)
	rp.name = ""
}

Code_RenamePreviewShutdown :: proc() {
	rp_clear()
	delete(rp.edits)
	delete(rp.lines)
}

// code_file_lines: a file's lines (an open doc's buffer, else the disk).
@(private = "file")
code_file_lines :: proc(state: ^EditorState, key: string) -> []string {
	for d in GlobalCode.docs {
		if d.path == key || lsp.uri_key(d.uri, context.temp_allocator) == key {
			out := make([dynamic]string, context.temp_allocator)
			for ln in 0 ..< buf.buffer_line_count(&d.buffer) do append(&out, strings.clone(buf.buffer_line_str(&d.buffer, ln), context.temp_allocator))
			return out[:]
		}
	}
	data, err := os.read_entire_file(key, context.temp_allocator)
	if err != nil do return nil
	return strings.split_lines(string(data), context.temp_allocator)
}

// Code_RenamePreviewOpen shows the edits (copied) for confirmation.
Code_RenamePreviewOpen :: proc(state: ^EditorState, edits: []lsp.Code_Action_Edit) {
	rp_clear()
	for e_ in edits do append(&rp.edits, lsp.Code_Action_Edit{strings.clone(e_.key), e_.range, strings.clone(e_.new_text)})
	if len(edits) > 0 do rp.name = strings.clone(edits[0].new_text)
	// One preview line per edited line: the line with all its edits applied.
	keys := make([dynamic]string, context.temp_allocator)
	for e_ in edits do if !slice.contains(keys[:], e_.key) do append(&keys, e_.key)
	for key in keys {
		lines := code_file_lines(state, key)
		lineNos := make([dynamic]int, context.temp_allocator)
		for e_ in edits do if e_.key == key && !slice.contains(lineNos[:], e_.range.start.line) do append(&lineNos, e_.range.start.line)
		slice.sort(lineNos[:])
		for ln in lineNos {
			if ln >= len(lines) do continue
			before := lines[ln]
			list := make([dynamic]lsp.Code_Action_Edit, context.temp_allocator)
			for e_ in edits do if e_.key == key && e_.range.start.line == ln && e_.range.end.line == ln do append(&list, e_)
			slice.sort_by(list[:], proc(x, y: lsp.Code_Action_Edit) -> bool {return x.range.start.character > y.range.start.character})
			after := before
			for e_ in list {
				s := code_byte_from_u16(after, e_.range.start.character)
				en := code_byte_from_u16(after, e_.range.end.character)
				after = strings.concatenate({after[:s], e_.new_text, after[min(en, len(after)):]}, context.temp_allocator)
			}
			append(&rp.lines, Preview_Line{strings.clone(key), ln, strings.clone(strings.trim_space(before)), strings.clone(strings.trim_space(after))})
		}
	}
	rp.open = true
}

// Code_RenamePreviewRender draws the dialog.
Code_RenamePreviewRender :: proc(state: ^EditorState) {
	if rp.open {
		imgui.OpenPopup("Rename Preview###RenamePreview")
		rp.open = false
	}
	io := imgui.GetIO()
	imgui.SetNextWindowSize({720, 440}, .Appearing)
	imgui.SetNextWindowPos({io.DisplaySize.x * 0.5, io.DisplaySize.y * 0.5}, .Appearing, {0.5, 0.5})
	if !imgui.BeginPopupModal("Rename Preview###RenamePreview", nil, {.NoTitleBar}) do return
	defer imgui.EndPopup()
	files := 0
	last := ""
	for l in rp.lines do if l.key != last {files += 1; last = l.key}
	UI_PanelTitle(ICON_FA_PEN, fmt.tprintf("Rename to \"%s\"", rp.name))
	imgui.SameLine(0, UI_SPACE)
	UI_DimText(fmt.tprintf("%d change(s) on %d line(s) in %d file(s)", len(rp.edits), len(rp.lines), files))
	h := imgui.GetContentRegionAvail().y - 44
	if imgui.BeginChild("##rp_list", {0, h}, {.Borders}, {}) {
		last = ""
		for l, i in rp.lines {
			if l.key != last {
				imgui.TextColored(UI_ACCENT, "%s", fmt.ctprintf("%s  %s", ICON_FA_FILE_CODE, code_display_path(state, l.key)))
				last = l.key
			}
			if GlobalFonts.mono != nil do imgui.PushFont(GlobalFonts.mono)
			ns := fmt.tprint(l.line + 1)
			imgui.TextColored(UI_TEXT_FAINT, "%s", fmt.ctprintf("  %s%s ", strings.repeat(" ", max(4 - len(ns), 0), context.temp_allocator), ns))
			imgui.SameLine(0, 0)
			imgui.TextColored(UI_DANGER, "%s", fmt.ctprintf("- %s", l.before))
			imgui.TextColored(UI_TEXT_FAINT, "       ")
			imgui.SameLine(0, 0)
			imgui.TextColored(UI_SUCCESS, "%s", fmt.ctprintf("+ %s", l.after))
			if GlobalFonts.mono != nil do imgui.PopFont()
			Drive_Item(fmt.tprintf("rename.line:%d", i))
		}
	}
	imgui.EndChild()
	imgui.SetCursorPosX(imgui.GetWindowWidth() - 16 - 120 - 90 - UI_SPACE)
	if UI_Button("Cancel", "rename.cancel", {90, 30}) || imgui.IsKeyPressed(.Escape) {
		rp_clear()
		imgui.CloseCurrentPopup()
		GlobalCode.focusRequest = true
		return
	}
	imgui.SameLine(0, UI_SPACE)
	if UI_PrimaryButton("Apply", "rename.apply", {120, 30}) || imgui.IsKeyPressed(.Enter) {
		n := code_apply_edit_list(state, rp.edits[:])
		Editor_Log(state, .Info, "Renamed %d occurrence(s) in %d file(s)", len(rp.edits), n)
		rp_clear()
		imgui.CloseCurrentPopup()
		GlobalCode.focusRequest = true
	}
	_ = filepath.base
}

Code_RenamePreviewLines :: proc() -> int {return len(rp.lines)}
