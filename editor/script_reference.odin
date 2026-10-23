package editor

import "core:fmt"
import "core:strings"
import buf "../odin_editor/buffer"
import imgui "lib/imgui"

// ============================================================================
// Scripting Reference window (Help > Scripting Reference; F1 in the Code tab
// on an API name): engine/SCRIPTING.md by section with a search box, and for
// the symbol under the caret its engine_api.lua entry (signature,
// description, example) above the section that covers it.
// ============================================================================

@(private = "file")
SCRIPTING_MD :: #load("../engine/SCRIPTING.md", string)
@(private = "file")
ENGINE_API :: #load("../engine/definitions/engine_api.lua", string)

@(private = "file")
Ref_Section :: struct {
	title: string,
	level: int,
	body:  string,
}

@(private = "file")
ref: struct {
	open:      bool,
	sections:  [dynamic]Ref_Section,
	selected:  int,
	search:    [128]u8,
	symbol:    string, // highlighted in the section, scrolled to
	api:       string, // engine_api.lua entry for the symbol ("" = none)
	scrollTo:  bool,
}

@(private = "file")
ref_parse :: proc() {
	if len(ref.sections) > 0 do return
	lines := strings.split_lines(SCRIPTING_MD)
	defer delete(lines)
	inCode := false
	cur := Ref_Section{title = "Introduction", level = 1}
	start := 0
	flush :: proc(cur: ^Ref_Section, lines: []string, from, to: int) {
		cur.body = strings.join(lines[from:to], "\n")
		append(&ref.sections, cur^)
	}
	for l, i in lines {
		if strings.has_prefix(strings.trim_space(l), "```") do inCode = !inCode
		if inCode || !strings.has_prefix(l, "#") do continue
		level := 0
		for level < len(l) && l[level] == '#' do level += 1
		flush(&cur, lines[:], start, i)
		cur = {title = strings.clone(strings.trim_space(l[level:])), level = level}
		start = i + 1
	}
	flush(&cur, lines[:], start, len(lines))
}

// ScriptReference_Open shows the reference, at the section about symbol
// ("Audio.play_sound", "set_position", "" = where it was).
ScriptReference_Open :: proc(symbol := "") {
	ref_parse()
	ref.open = true
	if symbol == "" do return
	delete(ref.symbol)
	delete(ref.api)
	qual, name := "", symbol
	if i := strings.last_index_any(symbol, ".:"); i >= 0 do qual, name = symbol[:i], symbol[i + 1:]
	ref.symbol = strings.clone(name)
	ref.api = strings.clone(ScriptReference_ApiDoc(qual, name))
	ref.selected = ref_best_section(qual, name)
	ref.scrollTo = true
}

ScriptReference_Selected :: proc() -> string {
	ref_parse()
	return ref.sections[ref.selected].title if ref.selected < len(ref.sections) else ""
}

ScriptReference_Api :: proc() -> string {return ref.api}

ScriptReference_IsOpen :: proc() -> bool {return ref.open}

@(private = "file")
ref_best_section :: proc(qual, name: string) -> int {
	best, bestScore := ref.selected, 0
	lname := strings.to_lower(name, context.temp_allocator)
	for s, i in ref.sections {
		score := 0
		title := strings.to_lower(s.title, context.temp_allocator)
		if strings.contains(title, lname) do score += 6
		if qual != "" && strings.contains(s.title, fmt.tprintf("`%s`", qual)) do score += 5 // the module's own section
		if qual != "" && strings.contains(s.body, fmt.tprintf("%s.%s", qual, name)) do score += 4
		if strings.contains(s.body, fmt.tprintf(":%s(", name)) || strings.contains(s.body, fmt.tprintf(".%s(", name)) do score += 3
		if strings.contains(s.body, fmt.tprintf("`%s`", name)) do score += 2
		if score > bestScore do best, bestScore = i, score
	}
	return best
}

// ScriptReference_ApiDoc: engine_api.lua's entry for a function name
// (the class matching the qualifier first: Audio -> AudioModule), as
// "Class:name(args)\n<description and example>".
ScriptReference_ApiDoc :: proc(qual, name: string) -> string {
	lines := strings.split_lines(ENGINE_API, context.temp_allocator)
	found := -1
	for l, i in lines {
		if !strings.has_prefix(l, "function ") do continue
		sig := l[len("function "):]
		p := strings.index_byte(sig, '(')
		if p < 0 do continue
		head := sig[:p]
		sep := strings.last_index_any(head, ".:")
		if (sep >= 0 && head[sep + 1:] == name) || head == name {
			if found < 0 do found = i
			cls := head[:sep] if sep >= 0 else ""
			if qual != "" && (cls == qual || cls == fmt.tprintf("%sModule", qual)) {found = i; break}
		}
	}
	if found < 0 do return ""
	sb := strings.builder_make(context.temp_allocator)
	sig := strings.trim_suffix(lines[found][len("function "):], " end")
	strings.write_string(&sb, sig)
	start := found
	for start > 0 && strings.has_prefix(lines[start - 1], "---") do start -= 1
	for l in lines[start:found] {
		d := l[3:]
		if strings.has_prefix(d, "@param ") do fmt.sbprintf(&sb, "\n  %s", d[len("@param "):])
		else if strings.has_prefix(d, "@return ") do fmt.sbprintf(&sb, "\n  -> %s", d[len("@return "):])
		else if !strings.has_prefix(d, "@") do fmt.sbprintf(&sb, "\n%s", d)
	}
	return strings.to_string(sb)
}

// Code_CmdReference (F1 in the Code tab): the reference for the name under
// the caret (with its module: Audio.play_sound).
Code_CmdReference :: proc(state: ^EditorState) {
	doc := code_active_doc()
	if doc == nil {
		ScriptReference_Open()
		return
	}
	b := &doc.buffer
	pos := b.cursors[0].pos
	line := buf.buffer_line_str(b, pos.line)
	ident :: proc(ch: u8) -> bool {return ch == '_' || (ch | 0x20 >= 'a' && ch | 0x20 <= 'z') || (ch >= '0' && ch <= '9')}
	s, e := min(pos.col, len(line)), min(pos.col, len(line))
	for s > 0 && ident(line[s - 1]) do s -= 1
	for e < len(line) && ident(line[e]) do e += 1
	name := line[s:e]
	symbol := strings.clone(name, context.temp_allocator)
	if s > 1 && (line[s - 1] == '.' || line[s - 1] == ':') {
		q := s - 1
		for q > 0 && ident(line[q - 1]) do q -= 1
		qual := line[q:s - 1]
		// Modules are capitalized (Audio.play_sound); self.node:x is a method.
		if len(qual) > 0 && qual[0] >= 'A' && qual[0] <= 'Z' do symbol = fmt.tprintf("%s.%s", qual, name)
	}
	ScriptReference_Open(symbol)
}

ScriptReference_Render :: proc(state: ^EditorState) {
	if !ref.open do return
	ref_parse()
	imgui.SetNextWindowSize({940, 640}, .FirstUseEver)
	if !imgui.Begin(fmt.ctprintf("%s  Scripting Reference###ScriptReference", ICON_FA_BOOK), &ref.open, {.NoCollapse}) {
		imgui.End()
		return
	}
	Drive_Item("ref.window")
	h := imgui.GetContentRegionAvail().y
	if imgui.BeginChild("##ref_toc", {250, h}, {.Borders}, {}) {
		imgui.SetNextItemWidth(-1)
		imgui.InputTextWithHint("##ref_search", fmt.ctprintf("%s  Search", ICON_FA_MAGNIFYING_GLASS), cstring(raw_data(ref.search[:])), len(ref.search), {})
		Drive_Item("ref.search")
		q := strings.to_lower(string(cstring(raw_data(ref.search[:]))), context.temp_allocator)
		for s, i in ref.sections {
			if q != "" && !strings.contains(strings.to_lower(s.title, context.temp_allocator), q) && !strings.contains(strings.to_lower(s.body, context.temp_allocator), q) do continue
			imgui.Indent(f32(max(s.level - 1, 0)) * 12)
			if imgui.Selectable(fmt.ctprintf("%s##sec%d", s.title, i), ref.selected == i) {
				ref.selected = i
				ref.scrollTo = true
			}
			Drive_Item(fmt.tprintf("ref.section:%s", s.title))
			imgui.Unindent(f32(max(s.level - 1, 0)) * 12)
		}
	}
	imgui.EndChild()
	imgui.SameLine()
	if imgui.BeginChild("##ref_body", {0, h}, {}, {}) {
		if ref.scrollTo && (ref.symbol == "" || ref.api != "") do imgui.SetScrollY(0) // the API entry is on top
		if ref.api != "" {
			// The API entry for the symbol.
			imgui.PushStyleColorImVec4(.ChildBg, UI_BG_RAISED)
			lines := strings.split_lines(ref.api, context.temp_allocator)
			if imgui.BeginChild("##ref_api", {0, f32(len(lines)) * imgui.GetTextLineHeightWithSpacing() + 18}, {.Borders}, {}) {
				for l, i in lines {
					if i == 0 {
						if GlobalFonts.mono != nil do imgui.PushFont(GlobalFonts.mono)
						imgui.TextColored(UI_ACCENT, "%s", fmt.ctprintf("%s", l))
						if GlobalFonts.mono != nil do imgui.PopFont()
					} else {
						imgui.TextWrapped("%s", fmt.ctprintf("%s", l))
					}
				}
			}
			imgui.EndChild()
			imgui.PopStyleColor()
			Drive_Item("ref.api")
		}
		if ref.selected < len(ref.sections) {
			s := ref.sections[ref.selected]
			imgui.PushFont(GlobalFonts.semibold)
			imgui.TextUnformatted(strings.clone_to_cstring(s.title, context.temp_allocator))
			imgui.PopFont()
			imgui.Separator()
			inCode := false
			scrolled := false
			for l in strings.split_lines(s.body, context.temp_allocator) {
				if strings.has_prefix(strings.trim_space(l), "```") {
					inCode = !inCode
					continue
				}
				hit := ref.symbol != "" && strings.contains(l, ref.symbol)
				col := UI_ACCENT if hit else (UI_TEXT_DIM if inCode else UI_TEXT)
				if inCode || strings.has_prefix(l, "|") {
					if GlobalFonts.mono != nil do imgui.PushFont(GlobalFonts.mono)
					imgui.TextColored(col, "%s", fmt.ctprintf("%s", l))
					if GlobalFonts.mono != nil do imgui.PopFont()
				} else if strings.trim_space(l) == "" {
					imgui.Dummy({0, 4})
				} else {
					text, _ := strings.replace_all(l, "**", "", context.temp_allocator)
					imgui.PushStyleColorImVec4(.Text, col)
					imgui.TextWrapped("%s", fmt.ctprintf("%s", text))
					imgui.PopStyleColor()
				}
				if hit && ref.scrollTo && !scrolled && ref.api == "" {
					imgui.SetScrollHereY(0.3)
					scrolled = true
				}
			}
		}
		ref.scrollTo = false
	}
	imgui.EndChild()
	imgui.End()
}
