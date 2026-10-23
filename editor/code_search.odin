package editor

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import buf "../odin_editor/buffer"
import imgui "lib/imgui"

// ============================================================================
// Find in files (Cmd+Shift+F): the bottom panel's Search tab searches the
// project's scripts and shaders (open files from their buffers) - case,
// whole word, regex - and lists the matches by file with the line around
// each; click one to open it there. Replace All edits open files through
// their undo history and writes the others.
// ============================================================================

SEARCH_EXTS :: []string{".lua", ".fs", ".vs", ".glsl"}
SEARCH_MAX :: 2000

Search_Hit :: struct {
	line, from, to: int,
	text:           string, // the line (heap)
}

Search_File :: struct {
	path, rel: string, // heap
	hits:      [dynamic]Search_Hit,
	collapsed: bool,
}

@(private = "file")
srch: struct {
	query:     [256]u8,
	replace:   [256]u8,
	caseSens:  bool,
	word:      bool,
	regex:     bool,
	files:     [dynamic]Search_File,
	total:     int,
	ran:       bool,
	badRegex:  bool,
	focus:     bool,
	truncated: bool,
}

// Code_CmdFindInFiles (Cmd+Shift+F): the Search tab, with the selection as
// the query.
Code_CmdFindInFiles :: proc(state: ^EditorState) {
	if doc := code_active_doc(); doc != nil {
		if sel := code_selection_text(doc); sel != "" && !strings.contains(sel, "\n") {
			srch.query = {}
			copy(srch.query[:len(srch.query) - 1], sel)
		}
	}
	srch.focus = true
	bottomTabRequest = .Search
}

@(private = "file")
search_clear :: proc() {
	for &f in srch.files {
		delete(f.path)
		delete(f.rel)
		for h in f.hits do delete(h.text)
		delete(f.hits)
	}
	clear(&srch.files)
	srch.total = 0
	srch.truncated = false
}

Code_SearchShutdown :: proc() {
	search_clear()
	delete(srch.files)
}

// Code_SearchRun searches every project script / shader for the query.
Code_SearchRun :: proc(state: ^EditorState) {
	search_clear()
	srch.ran = true
	srch.badRegex = false
	q := string(cstring(raw_data(srch.query[:])))
	if q == "" do return
	for rel in Editor_ListProjectFiles(state, "", SEARCH_EXTS) {
		if strings.has_prefix(rel, ".") do continue
		full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
		b: ^buf.Buffer
		tmp: buf.Buffer
		if doc := code_doc_for_path(full); doc != nil {
			b = &doc.buffer
		} else {
			data, err := os.read_entire_file(full, context.temp_allocator)
			if err != nil do continue
			tmp = buf.buffer_init(context.temp_allocator)
			buf.buffer_set_text(&tmp, string(data))
			b = &tmp
		}
		matches, bad := code_find_matches(b, q, srch.caseSens, srch.word, srch.regex)
		if bad {
			srch.badRegex = true
			return
		}
		if len(matches) == 0 do continue
		f := Search_File{path = strings.clone(full), rel = strings.clone(rel)}
		for m in matches {
			if srch.total >= SEARCH_MAX {srch.truncated = true; break}
			append(&f.hits, Search_Hit{m.start.line, m.start.col, m.end.col, strings.clone(buf.buffer_line_str(b, m.start.line))})
			srch.total += 1
		}
		append(&srch.files, f)
		if srch.truncated do break
	}
}

// Code_SearchReplaceAll replaces every match (open files: undoable edits;
// the others: written). Returns the count.
Code_SearchReplaceAll :: proc(state: ^EditorState) -> int {
	q := string(cstring(raw_data(srch.query[:])))
	with := string(cstring(raw_data(srch.replace[:])))
	if q == "" || srch.regex do return 0 // regex replace: not supported here
	n := 0
	for f in srch.files {
		if doc := code_doc_for_path(f.path); doc != nil {
			b := &doc.buffer
			matches, _ := code_find_matches(b, q, srch.caseSens, srch.word, false)
			group := buf.buffer_next_group(b)
			#reverse for m in matches {
				buf.buffer_delete_range(b, m.start, m.end, group)
				buf.buffer_insert_text(b, m.start, with, group)
				n += 1
			}
			code_touched(doc)
		} else {
			data, err := os.read_entire_file(f.path, context.temp_allocator)
			if err != nil do continue
			tmp := buf.buffer_init(context.temp_allocator)
			buf.buffer_set_text(&tmp, string(data))
			matches, _ := code_find_matches(&tmp, q, srch.caseSens, srch.word, false)
			group := buf.buffer_next_group(&tmp)
			#reverse for m in matches {
				buf.buffer_delete_range(&tmp, m.start, m.end, group)
				buf.buffer_insert_text(&tmp, m.start, with, group)
				n += 1
			}
			if os.write_entire_file(f.path, transmute([]u8)buf.buffer_to_string(&tmp, context.temp_allocator)) != nil {
				Editor_Log(state, .Error, "Could not write %s", f.rel)
			}
		}
	}
	Lua_MarkProjectTypesDirty()
	Editor_Log(state, .Info, "Replaced %d match(es) in %d file(s)", n, len(srch.files))
	Code_SearchRun(state)
	return n
}

// Code_SearchPanel draws the Search tab.
Code_SearchPanel :: proc(state: ^EditorState) {
	imgui.Dummy({0, 2})
	toggle :: proc(label: cstring, id: string, v: ^bool, tip: string) -> bool {
		imgui.PushStyleColorImVec4(.Button, UI_ACCENT_SOFT if v^ else {0, 0, 0, 0})
		clicked := imgui.Button(label)
		imgui.PopStyleColor()
		Drive_Item(id)
		UI_Tooltip(tip)
		if clicked do v^ = !v^
		return clicked
	}
	if srch.focus {
		imgui.SetKeyboardFocusHere()
		srch.focus = false
	}
	imgui.SetNextItemWidth(320)
	run := imgui.InputTextWithHint("##search_query", fmt.ctprintf("%s  Find in project scripts", ICON_FA_MAGNIFYING_GLASS), cstring(raw_data(srch.query[:])), len(srch.query), {.EnterReturnsTrue})
	Drive_Item("search.query")
	imgui.SameLine()
	if toggle("Aa", "search.case", &srch.caseSens, "Match case") do run = true
	imgui.SameLine()
	if toggle("ab", "search.word", &srch.word, "Whole word") do run = true
	imgui.SameLine()
	if toggle(".*", "search.regex", &srch.regex, "Regular expression") do run = true
	imgui.SameLine()
	if UI_Button(fmt.tprintf("%s  Search", ICON_FA_MAGNIFYING_GLASS), "search.run") do run = true
	imgui.SameLine(0, UI_SPACE * 2)
	imgui.SetNextItemWidth(220)
	imgui.InputTextWithHint("##search_replace", "Replace with", cstring(raw_data(srch.replace[:])), len(srch.replace), {})
	Drive_Item("search.replace")
	imgui.SameLine()
	imgui.BeginDisabled(srch.total == 0 || srch.regex)
	if UI_Button("Replace All", "search.replace-all") do Code_SearchReplaceAll(state)
	imgui.EndDisabled()
	if run do Code_SearchRun(state)

	switch {
	case srch.badRegex: imgui.TextColored(UI_DANGER, "Invalid regular expression")
	case srch.ran: UI_DimText(fmt.tprintf("%d match(es) in %d file(s)%s", srch.total, len(srch.files), " (stopped at 2000)" if srch.truncated else ""))
	}
	Drive_Item("search.summary")
	if !imgui.BeginChild("##search_results", {0, 0}, {}, {}) {
		imgui.EndChild()
		return
	}
	defer imgui.EndChild()
	for &f, fi in srch.files {
		imgui.PushIDInt(i32(fi))
		open := imgui.TreeNodeEx(fmt.ctprintf("%s  %s  (%d)", ICON_FA_FILE_CODE, f.rel, len(f.hits)), {.DefaultOpen, .SpanAvailWidth})
		Drive_Item(fmt.tprintf("search.file:%s", f.rel))
		if open {
			for h, hi in f.hits {
				imgui.PushIDInt(i32(hi))
				// "  12  local x = <match> ..." with the match highlighted.
				lead := strings.trim_left(h.text, " \t")
				cut := len(h.text) - len(lead)
				from, to := max(h.from - cut, 0), max(h.to - cut, 0)
				if from > 60 {
					lead = lead[from - 40:]
					to -= from - 40
					from = 40
				}
				if imgui.Selectable("##hit", false, {}, {0, 0}) {
					Editor_OpenScript(state, f.path, h.line, h.from, preview = true)
				}
				Drive_Item(fmt.tprintf("search.hit:%s:%d", f.rel, h.line + 1))
				imgui.SameLine(0, 0)
				num := fmt.tprint(h.line + 1)
				imgui.TextColored(UI_TEXT_FAINT, "%s", fmt.ctprintf("%s%s  ", strings.repeat(" ", max(5 - len(num), 0), context.temp_allocator), num))
				imgui.SameLine(0, 0)
				imgui.TextUnformatted(strings.clone_to_cstring(lead[:min(from, len(lead))], context.temp_allocator))
				imgui.SameLine(0, 0)
				imgui.TextColored(UI_WARNING, "%s", strings.clone_to_cstring(lead[min(from, len(lead)):min(to, len(lead))], context.temp_allocator))
				imgui.SameLine(0, 0)
				imgui.TextUnformatted(strings.clone_to_cstring(lead[min(to, len(lead)):], context.temp_allocator))
				imgui.PopID()
			}
			imgui.TreePop()
		}
		imgui.PopID()
	}
}

// Code_SearchQuery: drive queries search-*.
Code_SearchQuery :: proc(q: string) -> (string, bool) {
	switch q {
	case "search-total": return fmt.tprint(srch.total), true
	case "search-files": return fmt.tprint(len(srch.files)), true
	}
	return "", false
}
