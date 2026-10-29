package editor

import "core:fmt"
import vmem "core:mem/virtual"
import "core:strings"
import cm "lib/cmark"
import syn "../odin_editor/syntax"
import imgui "lib/imgui"
import rl "vendor:raylib"

// ============================================================================
// Markdown view: CommonMark (lib/cmark: cmark linked statically) parsed
// once into blocks - headings, paragraphs with styled inline text (strong,
// emphasis, `code`, links), fenced code, bullet / numbered lists, quotes,
// rules - plus GitHub-style pipe tables (not CommonMark: read from the
// paragraph's lines). Drawn with ImGui, wrapped to the available width.
// Lua (and Odin) code blocks and inline `code` are syntax highlighted with
// the Code tab's tokenizer and colours. Links can be clicked (Md_Draw
// returns the url); a paragraph that is only an image is drawn, fitted to
// the width, from the textures a viewer's loader gives (mdImageLoader).
// ============================================================================

// mdImageLoader: the texture for an image url (nil: shown as its alt text).
mdImageLoader: proc(url: string) -> ^rl.Texture2D

Md_Style :: enum {
	Strong,
	Emph,
	Code,
	Link,
}

Md_Span :: struct {
	text:  string,
	style: bit_set[Md_Style],
	url:   string, // a link's target
}

Md_Block_Kind :: enum {
	Heading,
	Paragraph,
	Code,
	Rule,
	Table,
	Image,
}

Md_Block :: struct {
	kind:   Md_Block_Kind,
	level:  int,       // heading level
	indent: int,       // list / quote depth
	bullet: string,    // "•", "3." (first paragraph of a list item)
	quote:  bool,
	spans:  [dynamic]Md_Span,
	code:   string,    // code block text
	lines:  [dynamic]Md_Code_Line, // code block lines, tokenized (Lua / Odin)
	rows:   [dynamic][dynamic][dynamic]Md_Span, // table: rows -> cells -> spans
	plain:  string,    // the block's text (search / highlight)
	url:    string,    // image
}

Md_Code_Line :: struct {
	text:   string,
	tokens: []syn.Token, // nil = plain
}

Md_Doc :: struct {
	blocks: [dynamic]Md_Block,
	arena:  ^vmem.Arena, // everything the doc holds (Md_Destroy)
}

// Md_Parse parses markdown into a doc that owns its memory.
Md_Parse :: proc(text: string) -> Md_Doc {
	doc: Md_Doc
	doc.arena = new(vmem.Arena)
	if vmem.arena_init_growing(doc.arena) != nil {
		free(doc.arena)
		doc.arena = nil
		return doc
	}
	context.allocator = vmem.arena_allocator(doc.arena)
	root := cm.parse_document(raw_data(text), len(text), {})
	if root == nil do return doc
	defer cm.node_free(root)
	lines := strings.split_lines(text, context.temp_allocator)
	md_blocks(&doc, root, 0, false, lines)
	return doc
}

Md_Destroy :: proc(doc: ^Md_Doc) {
	if doc.arena != nil {
		vmem.arena_destroy(doc.arena)
		free(doc.arena)
	}
	doc^ = {}
}

@(private = "file")
Md_List_State :: struct {
	ordered: bool,
	number:  int,
}

@(private = "file")
md_blocks :: proc(doc: ^Md_Doc, parent: ^cm.Node, indent: int, quote: bool, lines: []string, list: ^Md_List_State = nil, bullet := "") {
	bullet := bullet
	for n := cm.node_first_child(parent); n != nil; n = cm.node_next(n) {
		#partial switch cm.node_get_type(n) {
		case .Heading:
			b := Md_Block{kind = .Heading, level = int(cm.node_get_heading_level(n)), indent = indent}
			md_inlines(&b.spans, n, {})
			b.plain = md_plain(b.spans[:])
			append(&doc.blocks, b)
		case .Paragraph:
			first := md_first_text(n)
			if strings.has_prefix(strings.trim_space(first), "|") {
				append(&doc.blocks, md_table(n, lines, indent))
				continue
			}
			if img := cm.node_first_child(n); img != nil && cm.node_next(img) == nil && cm.node_get_type(img) == .Image {
				b := Md_Block{kind = .Image, indent = indent, url = strings.clone(string(cm.node_get_url(img)))}
				md_inlines(&b.spans, img, {})
				b.plain = md_plain(b.spans[:])
				append(&doc.blocks, b)
				continue
			}
			b := Md_Block{kind = .Paragraph, indent = indent, bullet = bullet, quote = quote}
			bullet = ""
			md_inlines(&b.spans, n, {})
			b.plain = md_plain(b.spans[:])
			append(&doc.blocks, b)
		case .Code_Block:
			code := strings.clone(strings.trim_right(string(cm.node_get_literal(n)), "\n"))
			b := Md_Block{kind = .Code, indent = indent, code = code, plain = code}
			md_tokenize(&b.lines, code, string(cm.node_get_fence_info(n)))
			append(&doc.blocks, b)
		case .Thematic_Break:
			append(&doc.blocks, Md_Block{kind = .Rule})
		case .Block_Quote:
			md_blocks(doc, n, indent + 1, true, lines)
		case .List:
			st := Md_List_State{ordered = cm.node_get_list_type(n) == .Ordered, number = int(cm.node_get_list_start(n))}
			md_blocks(doc, n, indent + 1, quote, lines, &st)
		case .Item:
			mark := "•"
			if list != nil && list.ordered {
				mark = fmt.aprintf("%d.", list.number)
				list.number += 1
			}
			md_blocks(doc, n, indent, quote, lines, nil, mark)
		}
	}
}

// md_tokenize splits a code block into lines, tokenized for lua (the
// default: an untagged block in these docs is Lua) and odin fences.
@(private = "file")
md_tokenize :: proc(out: ^[dynamic]Md_Code_Line, code, info: string) {
	lang := strings.to_lower(strings.trim_space(info), context.temp_allocator)
	tokenize: proc(line: string, state: int, allocator := context.allocator) -> ([]syn.Token, int)
	switch lang {
	case "", "lua": tokenize = proc(line: string, state: int, allocator := context.allocator) -> ([]syn.Token, int) {return syn.tokenize_lua_line(line, state, allocator)}
	case "odin": tokenize = proc(line: string, state: int, allocator := context.allocator) -> ([]syn.Token, int) {return syn.tokenize_odin_line(line, state, allocator)}
	}
	state := 0
	for line in strings.split_lines(code, context.temp_allocator) {
		l := Md_Code_Line{text = line}
		if tokenize != nil do l.tokens, state = tokenize(line, state)
		append(out, l)
	}
}

// md_draw_code draws one line of code at pos in the current (code) font:
// tokens in their syntax colours, the gaps in the default colour.
@(private = "file")
md_draw_code :: proc(dl: ^imgui.DrawList, pos: [2]f32, text: string, tokens: []syn.Token, plain: u32) -> f32 {
	x := pos.x
	put :: proc(dl: ^imgui.DrawList, x: ^f32, y: f32, s: string, col: u32) {
		if len(s) == 0 do return
		cs := strings.clone_to_cstring(s, context.temp_allocator)
		imgui.DrawList_AddText(dl, {x^, y}, col, cs)
		x^ += imgui.CalcTextSize(cs).x
	}
	at := 0
	for t in tokens {
		if t.start < at || t.end > len(text) do continue
		put(dl, &x, pos.y, text[at:t.start], plain)
		col := plain if t.kind == .Identifier || t.kind == .Default else code_token_color(t.kind)
		put(dl, &x, pos.y, text[t.start:t.end], col)
		at = t.end
	}
	put(dl, &x, pos.y, text[at:], plain)
	return x - pos.x
}

@(private = "file")
md_first_text :: proc(n: ^cm.Node) -> string {
	c := cm.node_first_child(n)
	if c != nil && cm.node_get_type(c) == .Text do return string(cm.node_get_literal(c))
	return ""
}

@(private = "file")
md_inlines :: proc(out: ^[dynamic]Md_Span, parent: ^cm.Node, style: bit_set[Md_Style], url := "") {
	for n := cm.node_first_child(parent); n != nil; n = cm.node_next(n) {
		#partial switch cm.node_get_type(n) {
		case .Text: append(out, Md_Span{strings.clone(string(cm.node_get_literal(n))), style, url})
		case .Code: append(out, Md_Span{strings.clone(string(cm.node_get_literal(n))), style + {.Code}, url})
		case .Soft_Break: append(out, Md_Span{" ", style, url})
		case .Line_Break: append(out, Md_Span{"\n", style, url})
		case .Strong: md_inlines(out, n, style + {.Strong}, url)
		case .Emph: md_inlines(out, n, style + {.Emph}, url)
		case .Link: md_inlines(out, n, style + {.Link}, strings.clone(string(cm.node_get_url(n))))
		case .Image: md_inlines(out, n, style + {.Link}, url)
		case .HTML_Inline: // not shown
		}
	}
}

@(private = "file")
md_plain :: proc(spans: []Md_Span) -> string {
	sb := strings.builder_make()
	for s in spans do strings.write_string(&sb, s.text)
	return strings.to_string(sb)
}

// md_table: a pipe table from the paragraph's source lines (the |---| row
// dropped); each cell's inline markdown parsed on its own.
@(private = "file")
md_table :: proc(n: ^cm.Node, lines: []string, indent: int) -> Md_Block {
	b := Md_Block{kind = .Table, indent = indent}
	from, to := int(cm.node_get_start_line(n)) - 1, int(cm.node_get_end_line(n))
	sb := strings.builder_make()
	for li in max(from, 0) ..< min(to, len(lines)) {
		l := strings.trim_space(lines[li])
		l = strings.trim_prefix(strings.trim_suffix(l, "|"), "|")
		cells := md_split_cells(l)
		sep := true
		for c in cells do if strings.trim(c, " -:") != "" do sep = false
		if sep do continue
		row := make([dynamic][dynamic]Md_Span)
		for c in cells {
			spans := make([dynamic]Md_Span)
			cell := strings.trim_space(c)
			if root := cm.parse_document(raw_data(cell), len(cell), {}); root != nil {
				if p := cm.node_first_child(root); p != nil do md_inlines(&spans, p, {})
				cm.node_free(root)
			}
			append(&row, spans)
			fmt.sbprintf(&sb, "%s ", cell)
		}
		append(&b.rows, row)
	}
	b.plain = strings.to_string(sb)
	return b
}

// md_split_cells splits on '|' outside `code` (code may contain pipes).
@(private = "file")
md_split_cells :: proc(l: string) -> []string {
	out := make([dynamic]string, context.temp_allocator)
	inCode := false
	start := 0
	for i in 0 ..< len(l) {
		switch l[i] {
		case '`': inCode = !inCode
		case '|':
			if inCode || (i > 0 && l[i - 1] == '\\') do continue
			append(&out, l[start:i])
			start = i + 1
		}
	}
	append(&out, l[start:])
	return out[:]
}

// Md_Draw draws the document; blocks whose text contains highlight are
// marked, and the first one is scrolled to when scrollTo is set.
// Md_Draw draws the doc; returns the url of a link clicked this frame ("").
Md_Draw :: proc(doc: ^Md_Doc, highlight := "", scrollTo := false) -> string {
	mdClicked = ""
	scrolled := false
	for &b in doc.blocks {
		hit := highlight != "" && strings.contains(b.plain, highlight)
		if hit && scrollTo && !scrolled {
			imgui.SetScrollHereY(0.25)
			scrolled = true
		}
		md_draw_block(&b, hit)
	}
	return mdClicked
}

@(private = "file")
mdClicked: string

@(private = "file")
md_draw_block :: proc(b: ^Md_Block, hit: bool) {
	INDENT :: 18
	ind := f32(b.indent) * INDENT
	if ind > 0 do imgui.Indent(ind)
	defer if ind > 0 do imgui.Unindent(ind)
	start := imgui.GetCursorScreenPos()
	switch b.kind {
	case .Heading:
		imgui.Dummy({0, 6 if b.level <= 2 else 2})
		imgui.PushFont(GlobalFonts.semibold)
		col := UI_TEXT if b.level <= 2 else UI_ACCENT
		md_flow(b.spans[:], col)
		imgui.PopFont()
		if b.level <= 2 {
			p := imgui.GetCursorScreenPos()
			imgui.DrawList_AddLine(imgui.GetWindowDrawList(), {p.x, p.y + 1}, {p.x + imgui.GetContentRegionAvail().x, p.y + 1}, col_u32(ui_line(0.10)))
			imgui.Dummy({0, 4})
		}
	case .Paragraph:
		if b.bullet != "" {
			imgui.TextColored(UI_TEXT_DIM, "%s", fmt.ctprintf("%s", b.bullet))
			imgui.SameLine(0, 6)
		}
		md_flow(b.spans[:], UI_TEXT_DIM if b.quote else UI_TEXT)
		if b.bullet == "" do imgui.Dummy({0, 3}) // list items sit closer
	case .Code:
		dl := imgui.GetWindowDrawList()
		imgui.DrawList_ChannelsSplit(dl, 2)
		imgui.DrawList_ChannelsSetCurrent(dl, 1)
		imgui.Dummy({0, 2})
		imgui.Indent(10)
		if GlobalFonts.mono != nil do imgui.PushFont(GlobalFonts.mono)
		plain := code_syntax({0.80, 0.86, 0.95, 1})
		lh := imgui.GetTextLineHeight()
		imgui.PushStyleVarImVec2(.ItemSpacing, {0, 1}) // lines as tight as plain text
		for l in b.lines {
			w := md_draw_code(dl, imgui.GetCursorScreenPos(), l.text, l.tokens, plain)
			imgui.Dummy({max(w, 1), lh})
		}
		imgui.PopStyleVar()
		if GlobalFonts.mono != nil do imgui.PopFont()
		imgui.Unindent(10)
		imgui.Dummy({0, 2})
		end := imgui.GetCursorScreenPos()
		imgui.DrawList_ChannelsSetCurrent(dl, 0)
		w := max(imgui.GetContentRegionAvail().x, imgui.GetItemRectMax().x - start.x)
		imgui.DrawList_AddRectFilled(dl, start, {start.x + w, end.y - 2}, col_u32(UI_BG_APP), 5)
		imgui.DrawList_AddRect(dl, start, {start.x + w, end.y - 2}, col_u32(ui_line(0.08)), 5)
		imgui.DrawList_ChannelsMerge(dl)
		imgui.Dummy({0, 4})
	case .Rule:
		imgui.Separator()
	case .Image:
		tex := mdImageLoader(b.url) if mdImageLoader != nil else nil
		if tex == nil || tex.id == 0 {
			md_flow(b.spans[:], UI_TEXT_DIM) // (its alt text)
			break
		}
		w := min(f32(tex.width), imgui.GetContentRegionAvail().x)
		h := w * f32(tex.height) / max(f32(tex.width), 1)
		imgui.Image(transmute(imgui.TextureID)tex, {w, h})
		if alt := md_plain(b.spans[:]); alt != "" && imgui.IsItemHovered() do UI_Tooltip(alt)
		imgui.Dummy({0, 4})
	case .Table:
		cols := 0
		for r in b.rows do cols = max(cols, len(r))
		if cols > 0 && imgui.BeginTable(fmt.ctprintf("##mdtable%p", b), i32(cols), imgui.TableFlags_Borders | imgui.TableFlags_RowBg | imgui.TableFlags_SizingStretchProp) {
			for r, ri in b.rows {
				imgui.TableNextRow()
				for c in r {
					imgui.TableNextColumn()
					if ri == 0 do imgui.PushFont(GlobalFonts.semibold)
					md_flow(c[:], UI_TEXT)
					if ri == 0 do imgui.PopFont()
				}
			}
			imgui.EndTable()
		}
		imgui.Dummy({0, 4})
	}
	if hit {
		// A bar left of the block that mentions the symbol.
		end := imgui.GetCursorScreenPos()
		imgui.DrawList_AddRectFilled(imgui.GetWindowDrawList(), {start.x - 8, start.y}, {start.x - 5, end.y - 4}, col_u32(UI_ACCENT), 1)
	}
}

// md_flow lays out styled spans word by word, wrapping at the available
// width (ImGui has no rich text): strong in semibold, `code` in the code
// font on a chip, emphasis and links coloured.
@(private = "file")
md_flow :: proc(spans: []Md_Span, color: imgui.Vec4) {
	wrapX := imgui.GetCursorPosX() + imgui.GetContentRegionAvail().x
	lineStart := imgui.GetCursorPosX()
	first := true
	dl := imgui.GetWindowDrawList()
	for s in spans {
		font: ^imgui.Font = nil
		if .Code in s.style && GlobalFonts.mono != nil do font = GlobalFonts.mono
		else if .Strong in s.style do font = GlobalFonts.semibold
		if font != nil do imgui.PushFont(font)
		col := color
		if .Code in s.style do col = {0.85, 0.74, 0.55, 1}
		else if .Link in s.style do col = UI_ACCENT
		else if .Emph in s.style do col = UI_TEXT_DIM
		// Words (keeping their trailing space); `code` stays whole.
		text := s.text
		for len(text) > 0 {
			if text[0] == '\n' {
				text = text[1:]
				first = true
				continue
			}
			end := len(text)
			if .Code not_in s.style {
				if i := strings.index_byte(text, ' '); i >= 0 do end = i + 1
			}
			word := text[:end]
			text = text[end:]
			wc := strings.clone_to_cstring(word, context.temp_allocator)
			w := imgui.CalcTextSize(wc).x
			if !first {
				imgui.SameLine(0, 0)
				if imgui.GetCursorPosX() + w > wrapX && imgui.GetCursorPosX() > lineStart + 1 {
					imgui.NewLine()
					if strings.trim_space(word) == "" do continue
				}
			}
			if .Code in s.style {
				// A chip, the code highlighted as Lua.
				p := imgui.GetCursorScreenPos()
				imgui.DrawList_AddRectFilled(dl, {p.x - 1, p.y}, {p.x + w + 1, p.y + imgui.GetTextLineHeight()}, col_u32(ui_line(0.07)), 3)
				toks, _ := syn.tokenize_lua_line(word, 0, context.temp_allocator)
				md_draw_code(dl, p, word, toks, col_u32(col))
				imgui.Dummy({w, imgui.GetTextLineHeight()})
			} else {
				imgui.TextColored(col, "%s", wc)
			}
			if .Link in s.style {
				mn, mx := imgui.GetItemRectMin(), imgui.GetItemRectMax()
				imgui.DrawList_AddLine(dl, {mn.x, mx.y}, {mx.x, mx.y}, col_u32(UI_ACCENT_SOFT))
				if s.url != "" && imgui.IsItemHovered() {
					imgui.SetMouseCursor(.Hand)
					if imgui.IsMouseClicked(.Left) do mdClicked = s.url
				}
			}
			first = false
		}
		if font != nil do imgui.PopFont()
	}
	if first do imgui.NewLine() // empty
}
