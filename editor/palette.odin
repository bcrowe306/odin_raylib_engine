package editor

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strconv"
import "core:strings"
import buf "../odin_editor/buffer"
import lsp "../odin_editor/lsp"
import imgui "lib/imgui"

// ============================================================================
// Command palette (Cmd+Shift+P / F1), file finder (Cmd+P), go to line
// (Ctrl+G, or ":<line>" in the palette) and location lists (references).
// Typing ">" in the file finder switches to commands, ":" to go to line.
// ============================================================================

Palette_Mode :: enum {
	Commands,
	Files,
	GotoLine,
	Locations,
}

Palette_Location :: struct {
	path:    string,
	line:    int,
	col:     int, // byte column
	label:   string,
	detail:  string,
}

@(private = "file")
Palette_Item :: struct {
	label:    string,
	detail:   string,
	shortcut: string,
	score:    int,
	index:    int, // action index / file index / location index
	disabled: bool,
}

@(private = "file")
Palette_State :: struct {
	open:       bool,
	justOpened: bool,
	mode:       Palette_Mode,
	query:      [256]u8,
	selected:   int,
	title:      string,
	locations:  [dynamic]Palette_Location,
	files:      [dynamic]string,
}

@(private = "file")
pal: Palette_State

Palette_IsOpen :: proc() -> bool {
	return pal.open
}

Palette_Open :: proc(mode: Palette_Mode) {
	pal.open = true
	pal.justOpened = true
	pal.mode = mode
	pal.selected = 0
	pal.query = {}
	if mode == .GotoLine do pal.query[0] = ':'
}

// Palette_ShowLocations lists LSP locations (references) to jump to.
Palette_ShowLocations :: proc(state: ^EditorState, title: string, locs: []lsp.Location) {
	palette_clear_locations()
	for l in locs {
		path := l.key
		text := ""
		if data, err := os.read_entire_file(path, context.temp_allocator); err == nil {
			lines := strings.split_lines(string(data), context.temp_allocator)
			if l.range.start.line < len(lines) do text = strings.trim_space(lines[l.range.start.line])
		}
		lineText := ""
		col := l.range.start.character
		if data, err := os.read_entire_file(path, context.temp_allocator); err == nil {
			lines := strings.split_lines(string(data), context.temp_allocator)
			if l.range.start.line < len(lines) {
				lineText = lines[l.range.start.line]
				col = code_byte_from_u16(lineText, l.range.start.character)
			}
		}
		append(&pal.locations, Palette_Location{
			path   = strings.clone(path),
			line   = l.range.start.line,
			col    = col,
			label  = strings.clone(text),
			detail = strings.clone(fmt.tprintf("%s:%d", code_display_path(state, path), l.range.start.line + 1)),
		})
	}
	pal.title = title
	if len(pal.locations) == 0 {
		Editor_Log(state, .Info, "No %s found", strings.to_lower(title, context.temp_allocator))
		return
	}
	Palette_Open(.Locations)
}

// Palette_ShowList opens the palette on a list of places (copied).
Palette_ShowList :: proc(title: string, entries: []Palette_Location) {
	palette_clear_locations()
	for e in entries {
		append(&pal.locations, Palette_Location{strings.clone(e.path), e.line, e.col, strings.clone(e.label), strings.clone(e.detail)})
	}
	pal.title = title
	Palette_Open(.Locations)
}

@(private = "file")
palette_clear_locations :: proc() {
	for l in pal.locations {
		delete(l.path)
		delete(l.label)
		delete(l.detail)
	}
	clear(&pal.locations)
}

Palette_Shutdown :: proc() {
	palette_clear_locations()
	delete(pal.locations)
	for f in pal.files do delete(f)
	delete(pal.files)
}

code_display_path :: proc(state: ^EditorState, abs: string) -> string {
	root := strings.trim_suffix(state.projectPath, "/")
	if root != "" && strings.has_prefix(abs, root) && len(abs) > len(root) do return abs[len(root) + 1:]
	return filepath.base(abs)
}

// fuzzy_score: higher is better; -1 = no match. Consecutive characters and
// word starts score more (like Zed / VSCode).
fuzzy_score :: proc(text, query: string) -> int {
	if query == "" do return 0
	score := 0
	j := 0
	prevMatch := -2
	for i in 0 ..< len(text) {
		if j >= len(query) do break
		a := text[i]
		b := query[j]
		if a >= 'A' && a <= 'Z' do a += 32
		if b >= 'A' && b <= 'Z' do b += 32
		if a != b do continue
		score += 1
		if prevMatch == i - 1 do score += 4
		if i == 0 || text[i - 1] == ' ' || text[i - 1] == '/' || text[i - 1] == '_' || text[i - 1] == '.' || text[i - 1] == ':' do score += 6
		prevMatch = i
		j += 1
	}
	if j < len(query) do return -1
	return score * 10 - len(text) / 4
}

// palette_project_files lists files worth opening (scenes, scripts,
// components, levels, textures, audio).
@(private = "file")
palette_project_files :: proc(state: ^EditorState) {
	for f in pal.files do delete(f)
	clear(&pal.files)
	walk :: proc(dir, rel: string, depth: int) {
		if depth > 6 do return
		h, err := os.open(dir)
		if err != nil do return
		infos, _ := os.read_dir(h, -1, context.temp_allocator)
		os.close(h)
		for fi in infos {
			if strings.has_prefix(fi.name, ".") do continue
			childRel := fi.name if rel == "" else fmt.tprintf("%s/%s", rel, fi.name)
			full, _ := filepath.join({dir, fi.name}, context.temp_allocator)
			if fi.type == .Directory {
				walk(full, childRel, depth + 1)
				continue
			}
			lower := strings.to_lower(fi.name, context.temp_allocator)
			for ext in ([]string{".lua", ".json", ".ldtk", ".png", ".jpg", ".wav", ".ogg", ".mp3", ".ore"}) {
				if strings.has_suffix(lower, ext) {
					append(&pal.files, strings.clone(childRel))
					break
				}
			}
		}
	}
	walk(state.projectPath, "", 0)
	slice.sort(pal.files[:])
}

@(private = "file")
palette_open_file :: proc(state: ^EditorState, rel: string) {
	full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
	switch Asset_KindOf(rel) {
	case .Scene: Editor_OpenScene(state, rel)
	case .Script, .Shader: Editor_OpenScript(state, rel)
	case .Component: Editor_OpenComponent(state, rel)
	case .Level: Editor_AddLevel(state, rel, state.cameraPos)
	case .Texture, .Audio, .Package, .Other:
		if strings.has_suffix(rel, ".ldtk") {
			Editor_OpenExternally(state, full)
			return
		}
		Editor_SelectAsset(state, full)
	}
}

Palette_Render :: proc(state: ^EditorState) {
	if !pal.open do return
	if pal.justOpened {
		imgui.OpenPopup("##CommandPalette")
		if pal.mode == .Files do palette_project_files(state)
	}
	vp := imgui.GetMainViewport()
	w := min(f32(640), vp.WorkSize.x - 40)
	imgui.SetNextWindowPos({vp.WorkPos.x + (vp.WorkSize.x - w) * 0.5, vp.WorkPos.y + 60}, .Always)
	imgui.SetNextWindowSize({w, 0})
	imgui.PushStyleVarImVec2(.WindowPadding, {8, 8})
	defer imgui.PopStyleVar()
	if !imgui.BeginPopup("##CommandPalette", {.NoMove, .NoResize, .NoTitleBar}) {
		pal.open = false
		return
	}
	defer imgui.EndPopup()

	// Query field.
	if pal.justOpened {
		imgui.SetKeyboardFocusHere()
		pal.justOpened = false
	}
	hint: cstring = "Type a command"
	switch pal.mode {
	case .Files:     hint = "Search files  ( > commands,  : line )"
	case .GotoLine:  hint = ":line[:column]"
	case .Locations: hint = strings.clone_to_cstring(pal.title, context.temp_allocator)
	case .Commands:
	}
	imgui.SetNextItemWidth(-1)
	imgui.InputTextWithHint("##palette_query", hint, cstring(raw_data(pal.query[:])), len(pal.query), {.AutoSelectAll})
	Drive_Item("palette.input")
	q := string(cstring(raw_data(pal.query[:])))
	// Mode switches by prefix.
	if pal.mode == .Files && strings.has_prefix(q, ">") {pal.mode = .Commands; q = q[1:]}
	if pal.mode == .Commands && strings.has_prefix(q, ">") do q = q[1:]
	if (pal.mode == .Files || pal.mode == .Commands) && strings.has_prefix(q, ":") do pal.mode = .GotoLine
	q = strings.trim_space(q)

	items := make([dynamic]Palette_Item, context.temp_allocator)
	switch pal.mode {
	case .Commands:
		for &a, i in GlobalActions {
			label := fmt.tprintf("%s: %s", a.category, a.label)
			s := fuzzy_score(label, q)
			if s < 0 do continue
			if q == "" {
				r := Action_RecentRank(a.id)
				s = 1000 - r if r >= 0 else 0
			}
			append(&items, Palette_Item{label = label, shortcut = Action_AllShortcutsText(&a), score = s, index = i, disabled = !Action_Enabled(state, &a)})
		}
	case .Files:
		for f, i in pal.files {
			s := fuzzy_score(f, q)
			if s < 0 do continue
			append(&items, Palette_Item{label = filepath.base(f), detail = f, score = s, index = i})
		}
	case .GotoLine:
		doc := code_active_doc()
		if doc == nil {
			append(&items, Palette_Item{label = "Open a script to go to a line", index = -1, disabled = true})
		} else {
			spec := strings.trim_prefix(q, ":")
			parts := strings.split(spec, ":", context.temp_allocator)
			line := 0
			if len(parts) > 0 do line, _ = strconv.parse_int(parts[0])
			n := buf.buffer_line_count(&doc.buffer)
			label := fmt.tprintf("Go to line %d of %d", clamp(line, 1, n), n) if line > 0 else fmt.tprintf("Type a line number (1-%d)", n)
			append(&items, Palette_Item{label = label, index = 0, disabled = line <= 0})
		}
	case .Locations:
		for l, i in pal.locations {
			s := fuzzy_score(fmt.tprintf("%s %s", l.label, l.detail), q)
			if s < 0 do continue
			append(&items, Palette_Item{label = l.label, detail = l.detail, score = s, index = i})
		}
	}
	if q != "" || pal.mode == .Commands {
		slice.stable_sort_by(items[:], proc(a, b: Palette_Item) -> bool {return a.score > b.score})
	}
	pal.selected = clamp(pal.selected, 0, max(len(items) - 1, 0))

	// Keys.
	run := false
	if imgui.IsKeyPressed(.DownArrow, true) do pal.selected = min(pal.selected + 1, max(len(items) - 1, 0))
	if imgui.IsKeyPressed(.UpArrow, true) do pal.selected = max(pal.selected - 1, 0)
	if imgui.IsKeyPressed(.PageDown, true) do pal.selected = min(pal.selected + 10, max(len(items) - 1, 0))
	if imgui.IsKeyPressed(.PageUp, true) do pal.selected = max(pal.selected - 10, 0)
	if imgui.IsKeyPressed(.Enter, false) || imgui.IsKeyPressed(.KeypadEnter, false) do run = true
	if imgui.IsKeyPressed(.Escape, false) {
		imgui.CloseCurrentPopup()
		pal.open = false
		if code_active_doc() != nil && pal.mode == .GotoLine do GlobalCode.focusRequest = true
		return
	}

	// List.
	rowH := f32(28)
	visible := min(len(items), 12)
	if imgui.BeginChild("##palette_list", {0, f32(max(visible, 1)) * rowH + 4}, {}, {}) {
		for it, n in items {
			selected := n == pal.selected
			if it.disabled do imgui.PushStyleColorImVec4(.Text, UI_TEXT_FAINT)
			if imgui.Selectable(fmt.ctprintf("##pal%d", n), selected, {}, {0, rowH}) {
				pal.selected = n
				run = true
			}
			if it.disabled do imgui.PopStyleColor()
			Drive_Item(fmt.tprintf("palette:%s", it.label))
			if selected && (imgui.IsKeyPressed(.DownArrow, true) || imgui.IsKeyPressed(.UpArrow, true) || imgui.IsKeyPressed(.PageDown, true) || imgui.IsKeyPressed(.PageUp, true)) {
				imgui.SetScrollHereY(0.5)
			}
			mn := imgui.GetItemRectMin()
			mx := imgui.GetItemRectMax()
			dl := imgui.GetWindowDrawList()
			y := mn.y + (rowH - imgui.GetFontSize()) * 0.5
			imgui.DrawList_AddText(dl, {mn.x + 8, y}, col_u32(UI_TEXT_FAINT if it.disabled else UI_TEXT), strings.clone_to_cstring(it.label, context.temp_allocator))
			lw := imgui.CalcTextSize(strings.clone_to_cstring(it.label, context.temp_allocator)).x
			if it.detail != "" {
				imgui.DrawList_AddText(dl, {mn.x + 18 + lw, y}, col_u32(UI_TEXT_DIM), strings.clone_to_cstring(it.detail, context.temp_allocator))
			}
			if it.shortcut != "" {
				sc := strings.clone_to_cstring(it.shortcut, context.temp_allocator)
				sw := imgui.CalcTextSize(sc).x
				imgui.DrawList_AddText(dl, {mx.x - sw - 10, y}, col_u32(UI_ACCENT), sc)
			}
		}
		if len(items) == 0 do UI_DimText("  No matches")
	}
	imgui.EndChild()

	if run && pal.selected < len(items) && !items[pal.selected].disabled {
		it := items[pal.selected]
		mode := pal.mode
		imgui.CloseCurrentPopup()
		pal.open = false
		switch mode {
		case .Commands:
			Action_Run(state, &GlobalActions[it.index])
		case .Files:
			palette_open_file(state, pal.files[it.index])
		case .GotoLine:
			spec := strings.trim_prefix(q, ":")
			parts := strings.split(spec, ":", context.temp_allocator)
			line, _ := strconv.parse_int(parts[0])
			col := 0
			if len(parts) > 1 do col, _ = strconv.parse_int(parts[1])
			if doc := code_active_doc(); doc != nil && line > 0 {
				Editor_OpenScript(state, doc.path, line - 1, 0)
				if col > 0 {
					l := buf.buffer_line_str(&doc.buffer, doc.buffer.cursors[0].pos.line)
					doc.buffer.cursors[0].pos.col = code_byte_col(l, col - 1)
				}
			}
		case .Locations:
			l := pal.locations[it.index]
			Editor_OpenScript(state, l.path, l.line, l.col)
		}
	}
}
