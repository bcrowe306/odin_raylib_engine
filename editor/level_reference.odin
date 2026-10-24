package editor

import "core:fmt"
import "core:strings"
import imgui "lib/imgui"

// ============================================================================
// Level Editor Reference (Help > Level Editor Reference; F1 in the Level tab;
// the "?" buttons): engine/docs/level_editor_reference.md by section, like
// the Scripting Reference. A section is tied to topics with comment lines
// under its heading:
//
//     ## Brush
//     <!-- topic: tool.brush -->
//
// level_tip(text, topic) gives an item a tooltip ("F1: more" added) and makes
// F1 open its topic while hovered; LevelRef_Panel(topic) does it for a whole
// panel (the fallback when no item has a topic).
// ============================================================================

@(private = "file")
LEVEL_REF_MD :: #load("../engine/docs/level_editor_reference.md", string)

@(private = "file")
LRef_Section :: struct {
	title:  string,
	level:  int,
	body:   string,
	topics: [dynamic]string,
	doc:    Md_Doc,
	parsed: bool,
}

@(private = "file")
lref: struct {
	open:      bool,
	sections:  [dynamic]LRef_Section,
	selected:  int,
	search:    [128]u8,
	scrollTo:  bool,
	hovered:   string, // topic of the item under the mouse this frame
	panel:     string, // topic of the panel under the mouse this frame
	lastHover: string, // last frame's (F1 is handled before panels draw)
	lastPanel: string,
}

@(private = "file")
lref_parse :: proc() {
	if len(lref.sections) > 0 do return
	lines := strings.split_lines(LEVEL_REF_MD)
	defer delete(lines)
	inCode := false
	cur := LRef_Section{} // text before the first heading (none, normally)
	body := strings.builder_make()
	flush :: proc(cur: ^LRef_Section, body: ^strings.Builder) {
		text := strings.to_string(body^)
		if cur.title == "" && strings.trim_space(text) == "" && len(cur.topics) == 0 {
			strings.builder_reset(body)
			return
		}
		cur.body = strings.clone(text)
		strings.builder_reset(body)
		append(&lref.sections, cur^)
	}
	for l in lines {
		t := strings.trim_space(l)
		if strings.has_prefix(t, "```") do inCode = !inCode
		if !inCode && strings.has_prefix(t, "<!-- topic:") {
			for topic in strings.split(strings.trim_space(strings.trim_suffix(t[len("<!-- topic:"):], "-->")), ",", context.temp_allocator) {
				append(&cur.topics, strings.clone(strings.trim_space(topic)))
			}
			continue
		}
		if !inCode && strings.has_prefix(l, "#") {
			level := 0
			for level < len(l) && l[level] == '#' do level += 1
			flush(&cur, &body)
			cur = {title = strings.clone(strings.trim_space(l[level:])), level = level}
			continue
		}
		strings.write_string(&body, l)
		strings.write_byte(&body, '\n')
	}
	flush(&cur, &body)
	strings.builder_destroy(&body)
}

// LevelRef_Open shows the reference at a topic ("" = where it was).
LevelRef_Open :: proc(topic := "") {
	lref_parse()
	lref.open = true
	if topic == "" do return
	for s, i in lref.sections {
		for t in s.topics {
			if t == topic {
				lref.selected = i
				lref.scrollTo = true
				return
			}
		}
	}
}

LevelRef_IsOpen :: proc() -> bool {return lref.open}

// LevelRef_Selected: the shown section's title (drives).
LevelRef_Selected :: proc() -> string {
	if lref.selected < len(lref.sections) do return lref.sections[lref.selected].title
	return ""
}

// LevelRef_HasTopic: is a topic documented (tests / drives)?
LevelRef_HasTopic :: proc(topic: string) -> bool {
	lref_parse()
	for s in lref.sections do for t in s.topics do if t == topic do return true
	return false
}

// LevelRef_BeginFrame: call once per frame before the Level tab draws.
LevelRef_BeginFrame :: proc() {
	lref.lastHover, lref.lastPanel = lref.hovered, lref.panel
	lref.hovered, lref.panel = "", ""
}

// LevelRef_HelpTopic: the topic F1 opens (the hovered item's, else the
// hovered panel's).
LevelRef_HelpTopic :: proc() -> string {
	return lref.lastHover != "" ? lref.lastHover : lref.lastPanel
}

// level_tip: tooltip for the last item; F1 opens `topic` while it is hovered.
level_tip :: proc(text: string, topic := "") {
	if topic != "" && imgui.IsItemHovered(imgui.HoveredFlags_AllowWhenDisabled) do lref.hovered = topic
	if text == "" do return
	UI_Tooltip(topic != "" ? fmt.tprintf("%s\n\nF1: more", text) : text)
}

// LevelRef_Panel: the current window's topic (call inside the panel).
LevelRef_Panel :: proc(topic: string) {
	if imgui.IsWindowHovered(imgui.HoveredFlags_ChildWindows) do lref.panel = topic
}

// level_help_button: a small "?" opening a topic.
level_help_button :: proc(topic: string, id: string) -> bool {
	pressed := UI_IconButton(ICON_FA_CIRCLE_QUESTION, id, "", false, 22)
	level_tip("Open the reference for this", topic)
	if pressed do LevelRef_Open(topic)
	return pressed
}

LevelRef_Render :: proc(state: ^EditorState) {
	if !lref.open do return
	lref_parse()
	imgui.SetNextWindowSize({900, 620}, .FirstUseEver)
	imgui.PushStyleColorImVec4(.WindowBg, UI_BG_PANEL)
	imgui.PushStyleColorImVec4(.Border, ui_line(0.22))
	imgui.PushStyleColorImVec4(.TitleBg, UI_BG_RAISED)
	imgui.PushStyleColorImVec4(.TitleBgActive, UI_BG_ACTIVE)
	imgui.PushStyleVar(.WindowBorderSize, 1)
	imgui.PushStyleVar(.WindowRounding, 8)
	visible := imgui.Begin(fmt.ctprintf("%s  Level Editor Reference###LevelReference", ICON_FA_BOOK), &lref.open, {.NoCollapse})
	imgui.PopStyleVar(2)
	imgui.PopStyleColor(4)
	if !visible {
		imgui.End()
		return
	}
	Drive_Item("lref.window")
	h := imgui.GetContentRegionAvail().y
	imgui.PushStyleColorImVec4(.ChildBg, UI_BG_APP)
	tocOpen := imgui.BeginChild("##lref_toc", {240, h}, {.Borders}, {})
	imgui.PopStyleColor()
	if tocOpen {
		imgui.SetNextItemWidth(-1)
		imgui.InputTextWithHint("##lref_search", fmt.ctprintf("%s  Search", ICON_FA_MAGNIFYING_GLASS), cstring(raw_data(lref.search[:])), len(lref.search), {})
		Drive_Item("lref.search")
		q := strings.to_lower(string(cstring(raw_data(lref.search[:]))), context.temp_allocator)
		for s, i in lref.sections {
			if q != "" && !strings.contains(strings.to_lower(s.title, context.temp_allocator), q) && !strings.contains(strings.to_lower(s.body, context.temp_allocator), q) do continue
			imgui.Indent(f32(max(s.level - 1, 0)) * 12)
			if imgui.Selectable(fmt.ctprintf("%s##lsec%d", s.title, i), lref.selected == i) {
				lref.selected = i
				lref.scrollTo = true
			}
			Drive_Item(fmt.tprintf("lref.section:%s", s.title))
			imgui.Unindent(f32(max(s.level - 1, 0)) * 12)
		}
	}
	imgui.EndChild()
	imgui.SameLine()
	if imgui.BeginChild("##lref_body", {0, h}, {}, {.HorizontalScrollbar}) {
		if lref.scrollTo do imgui.SetScrollY(0)
		if lref.selected < len(lref.sections) {
			s := &lref.sections[lref.selected]
			if !s.parsed {
				s.doc = Md_Parse(fmt.tprintf("%s %s\n\n%s", strings.repeat("#", max(s.level, 1), context.temp_allocator), s.title, s.body))
				s.parsed = true
			}
			Md_Draw(&s.doc)
		}
		lref.scrollTo = false
	}
	imgui.EndChild()
	imgui.End()
}

// LevelRef_Shutdown frees the parsed sections.
LevelRef_Shutdown :: proc() {
	for &s in lref.sections {
		delete(s.title)
		delete(s.body)
		for t in s.topics do delete(t)
		delete(s.topics)
		if s.parsed do Md_Destroy(&s.doc)
	}
	delete(lref.sections)
	lref.sections = nil
}
