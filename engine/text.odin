package engine

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:math"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
import "core:unicode/utf8"
import rl "vendor:raylib"

// ============================================================================
// Text: fonts, rich text and TextNode.
//
// Fonts: "" is the engine font; a project .ttf / .otf is rasterised at the
// size asked (or once as a signed distance field with `sdf`, sharp at any
// scale); a .fnt (BMFont) or font image is used as drawn (disk only).
// Latin-1 and common typographic punctuation are included (localized text).
//
// Rich text markup:  [color=#ff8800]...[/color]  [color=red]  [size=32]
// [/size]  [wave]...[/wave]  [shake]...[/shake]  ("[[" is a literal "[").
// ============================================================================

// --- fonts ----------------------------------------------------------------------

Text_Font :: struct {
	font:   rl.Font,
	size:   f32,  // the size it was rasterised at
	sdf:    bool,
	engine: bool, // the engine's font (sized per draw)
}

@(private = "file")
fontCache: map[string]^Text_Font

@(private = "file")
sdfShader: struct {
	shader: rl.Shader,
	ok:     bool,
}

@(private = "file")
SDF_FRAGMENT :: `#version 330
in vec2 fragTexCoord;
in vec4 fragColor;
uniform sampler2D texture0;
uniform vec4 colDiffuse;
out vec4 finalColor;
void main() {
    float d = texture(texture0, fragTexCoord).a;
    float w = fwidth(d);
    float a = smoothstep(0.5 - w, 0.5 + w, d);
    finalColor = vec4(fragColor.rgb, fragColor.a * a) * colDiffuse;
}
`

@(private = "file")
font_codepoints :: proc() -> []rune {
	out := make([dynamic]rune, context.temp_allocator)
	for r in rune(32) ..= 126 do append(&out, r)
	for r in rune(160) ..= 255 do append(&out, r)
	extra := []rune{'…', '‘', '’', '“', '”', '–', '—', '•', '€', '™', 'Œ', 'œ', 'Ÿ', '¿', '¡'}
	append(&out, ..extra)
	return out[:]
}

// Text_GetFont: a font for drawing at `size` (cached). Path "" = engine font.
Text_GetFont :: proc(path: string, size: f32, sdf := false, ctx: ^GameContext = nil) -> ^Text_Font {
	if fontCache == nil do fontCache = make(map[string]^Text_Font, allocator = runtime.heap_allocator())
	ext := strings.to_lower(filepath.ext(path), context.temp_allocator)
	vector := ext == ".ttf" || ext == ".otf"
	px := f32(int(size + 0.5))
	key: string
	switch {
	case path == "":     key = "engine"
	case vector && sdf:  key = fmt.tprintf("%s|sdf", path)
	case vector:         key = fmt.tprintf("%s|%v", path, px)
	case:                key = path
	}
	if f, ok := fontCache[key]; ok do return f
	f := new(Text_Font, runtime.heap_allocator())
	defer fontCache[strings.clone(key, runtime.heap_allocator())] = f
	if path == "" || !rl.IsWindowReady() {
		f.engine = true
		return f
	}
	cps := font_codepoints()
	data: []u8
	if ctx != nil && ctx.game != nil {
		if d, ok := AssetManager_ReadFileBytes(&ctx.game.assetManager, path, context.temp_allocator); ok do data = d
	}
	switch {
	case vector && sdf && data != nil:
		base: c.int = 48
		glyphs := rl.LoadFontData(raw_data(data), c.int(len(data)), base, raw_data(cps), c.int(len(cps)), .SDF)
		recs: [^]rl.Rectangle
		atlas := rl.GenImageFontAtlas(glyphs, &recs, c.int(len(cps)), base, 8, 0)
		f.font = rl.Font{baseSize = base, glyphCount = c.int(len(cps)), glyphPadding = 8, glyphs = glyphs, recs = recs}
		f.font.texture = rl.LoadTextureFromImage(atlas)
		rl.UnloadImage(atlas)
		rl.SetTextureFilter(f.font.texture, .BILINEAR)
		f.size = f32(base)
		f.sdf = true
		if !sdfShader.ok {
			sdfShader.shader = rl.LoadShaderFromMemory(nil, SDF_FRAGMENT)
			sdfShader.ok = rl.IsShaderValid(sdfShader.shader)
		}
	case vector && data != nil:
		f.font = rl.LoadFontFromMemory(strings.clone_to_cstring(ext, context.temp_allocator), raw_data(data), c.int(len(data)), c.int(px), raw_data(cps), c.int(len(cps)))
		rl.SetTextureFilter(f.font.texture, .BILINEAR)
		f.size = px
	case:
		// BMFont / image font from disk.
		disk := path
		if ctx != nil && ctx.game != nil do disk = AssetManager_ResolveDiskPath(&ctx.game.assetManager, path)
		f.font = rl.LoadFont(strings.clone_to_cstring(disk, context.temp_allocator))
		f.size = f32(f.font.baseSize)
	}
	if f.font.texture.id == 0 do f.engine = true // missing: the engine font
	return f
}

// Text_UnloadFonts frees the cached fonts (engine shutdown).
Text_UnloadFonts :: proc() {
	for k, f in fontCache {
		if !f.engine && rl.IsWindowReady() do rl.UnloadFont(f.font)
		delete(k, runtime.heap_allocator())
		free(f, runtime.heap_allocator())
	}
	delete(fontCache)
	fontCache = nil
	if sdfShader.ok && rl.IsWindowReady() do rl.UnloadShader(sdfShader.shader)
	sdfShader = {}
}

// Text_MeasureRune: advance of one character at `size`.
Text_MeasureRune :: proc(f: ^Text_Font, r: rune, size: f32) -> f32 {
	if f == nil || f.engine {
		buf, n := utf8.encode_rune(r)
		return MeasureEngineText(strings.clone_to_cstring(string(buf[:n]), context.temp_allocator), size).x
	}
	scale := size / max(f.size, 1)
	g := rl.GetGlyphIndex(f.font, r)
	adv := f32(f.font.glyphs[g].advanceX)
	if adv == 0 do adv = f.font.recs[g].width
	return adv * scale
}

// --- rich text --------------------------------------------------------------------

Text_Effect :: enum {
	Wave,
	Shake,
}

Text_Glyph :: struct {
	r:       rune,
	pos:     [2]f32, // top-left, from the text's origin
	size:    f32,
	color:   rl.Color,
	effects: bit_set[Text_Effect],
	width:   f32,
}

Text_Style :: struct {
	color: rl.Color,
	size:  f32,
	effects: bit_set[Text_Effect],
}

@(private = "file")
named_color :: proc(s: string) -> (rl.Color, bool) {
	switch strings.to_lower(s, context.temp_allocator) {
	case "white":  return rl.WHITE, true
	case "black":  return rl.BLACK, true
	case "red":    return {239, 68, 68, 255}, true
	case "green":  return {74, 222, 128, 255}, true
	case "blue":   return {96, 165, 250, 255}, true
	case "yellow": return {250, 204, 21, 255}, true
	case "orange": return {251, 146, 60, 255}, true
	case "purple": return {192, 132, 252, 255}, true
	case "gray", "grey": return {156, 163, 175, 255}, true
	}
	h := strings.trim_prefix(s, "#")
	if len(h) == 6 || len(h) == 8 {
		v, ok := strconv.parse_u64_of_base(h, 16)
		if !ok do return {}, false
		if len(h) == 6 do return {u8(v >> 16), u8(v >> 8), u8(v), 255}, true
		return {u8(v >> 24), u8(v >> 16), u8(v >> 8), u8(v)}, true
	}
	return {}, false
}

// Text_Layout lays out (rich) text into glyphs: wrapped at maxWidth (0 =
// no wrapping; at spaces, or anywhere in a word longer than a line),
// aligned (0 left, 1 centre, 2 right) and with lines lineSpacing apart
// (times the line's largest size). `measure` gives a character's advance.
// Returns the glyphs (temp) and the text block's size.
Text_Layout :: proc(text: string, base: Text_Style, maxWidth: f32, align: int, lineSpacing: f32, rich: bool, measure: proc(r: rune, size: f32, data: rawptr) -> f32, data: rawptr) -> (glyphs: []Text_Glyph, size: [2]f32) {
	// 1. Characters with their style.
	chars := make([dynamic]Text_Glyph, context.temp_allocator)
	stack := make([dynamic]Text_Style, context.temp_allocator)
	style := base
	i := 0
	for i < len(text) {
		if rich && text[i] == '[' {
			if i + 1 < len(text) && text[i + 1] == '[' {
				append(&chars, Text_Glyph{r = '[', size = style.size, color = style.color, effects = style.effects})
				i += 2
				continue
			}
			if end := strings.index_byte(text[i:], ']'); end > 0 {
				tag := text[i + 1:i + end]
				handled := true
				switch {
				case strings.has_prefix(tag, "/"):
					if len(stack) > 0 do style = pop(&stack)
				case strings.has_prefix(tag, "color="):
					if col, ok := named_color(tag[6:]); ok {append(&stack, style); style.color = col}
					else do handled = false
				case strings.has_prefix(tag, "size="):
					if v, ok := strconv.parse_f32(tag[5:]); ok {append(&stack, style); style.size = v}
					else do handled = false
				case tag == "wave":
					append(&stack, style); style.effects += {.Wave}
				case tag == "shake":
					append(&stack, style); style.effects += {.Shake}
				case:
					handled = false
				}
				if handled {
					i += end + 1
					continue
				}
			}
		}
		r, n := utf8.decode_rune_in_string(text[i:])
		append(&chars, Text_Glyph{r = r, size = style.size, color = style.color, effects = style.effects})
		i += n
	}
	for &g in chars do if g.r != '\n' do g.width = measure(g.r, g.size, data)

	// 2. Lines: break at newlines and, past maxWidth, at the last space.
	Line :: struct {start, end: int, width, height: f32}
	lines := make([dynamic]Line, context.temp_allocator)
	start := 0
	x: f32
	lastSpace := -1
	for k := 0; k < len(chars); k += 1 {
		g := chars[k]
		if g.r == '\n' {
			append(&lines, Line{start = start, end = k})
			start, x, lastSpace = k + 1, 0, -1
			continue
		}
		if maxWidth > 0 && x + g.width > maxWidth && k > start {
			// At a space the space ends the line (not drawn, but counted, so
			// typewriter positions match the text).
			atSpace := lastSpace > start
			cut := lastSpace + 1 if atSpace else k
			append(&lines, Line{start = start, end = cut})
			start = cut
			x, lastSpace = 0, -1
			k = start - 1
			continue
		}
		if g.r == ' ' do lastSpace = k
		x += g.width
	}
	append(&lines, Line{start = start, end = len(chars)})

	// 3. Positions.
	out := make([dynamic]Text_Glyph, 0, len(chars), context.temp_allocator)
	y: f32
	for &ln in lines {
		// Trailing spaces don't count towards alignment.
		e := ln.end
		for e > ln.start && chars[e - 1].r == ' ' do e -= 1
		for k in ln.start ..< e do ln.width += chars[k].width
		ln.height = base.size
		for k in ln.start ..< ln.end do ln.height = max(ln.height, chars[k].size)
		size.x = max(size.x, ln.width)
	}
	for ln, li in lines {
		lx: f32
		switch align {
		case 1: lx = (size.x - ln.width) * 0.5
		case 2: lx = size.x - ln.width
		}
		for k in ln.start ..< ln.end {
			g := chars[k]
			if g.r == '\n' do continue
			g.pos = {lx, y + (ln.height - g.size)} // baseline-ish: bottoms aligned
			append(&out, g)
			lx += g.width
		}
		y += ln.height * (lineSpacing if li < len(lines) - 1 else 1)
	}
	size.y = y
	return out[:], size
}

// Text_PlainLength: the characters a text shows (markup tags don't count).
Text_PlainLength :: proc(text: string, rich: bool) -> int {
	measure :: proc(r: rune, size: f32, data: rawptr) -> f32 {return 1}
	glyphs, _ := Text_Layout(text, {rl.WHITE, 1, {}}, 0, 0, 1, rich, measure, nil)
	return len(glyphs)
}

// Text_DrawGlyphs draws laid-out glyphs at `origin` (the first `reveal`
// of them; < 0 = all), rotated about the origin, with effects at `time`.
Text_DrawGlyphs :: proc(f: ^Text_Font, glyphs: []Text_Glyph, origin: [2]f32, rotation: f32, scale: f32, reveal: int, time: f32, tint: rl.Color = rl.WHITE) {
	if f == nil do return
	n := len(glyphs) if reveal < 0 else min(reveal, len(glyphs))
	if f.sdf && sdfShader.ok do rl.BeginShaderMode(sdfShader.shader)
	defer if f.sdf && sdfShader.ok do rl.EndShaderMode()
	for g, i in glyphs[:n] {
		if g.r == ' ' do continue
		p := g.pos
		if .Wave in g.effects do p.y += math.sin(time * 6 + f32(i) * 0.6) * g.size * 0.12
		if .Shake in g.effects {
			seed := f32(int(time * 30)) * 13.7 + f32(i) * 7.1
			p += {math.sin(seed) * g.size * 0.06, math.cos(seed * 1.3) * g.size * 0.06}
		}
		world := origin + rotate_vec(p * scale, rotation)
		col := g.color
		if tint != rl.WHITE {
			col = {u8(u32(col.r) * u32(tint.r) / 255), u8(u32(col.g) * u32(tint.g) / 255), u8(u32(col.b) * u32(tint.b) / 255), u8(u32(col.a) * u32(tint.a) / 255)}
		}
		if f.engine {
			buf, bn := utf8.encode_rune(g.r)
			font := GetEngineFont(g.size * scale)
			rl.DrawTextPro(font, strings.clone_to_cstring(string(buf[:bn]), context.temp_allocator), world, {0, 0}, rotation, g.size * scale, 0, col)
		} else {
			// DrawTextCodepoint has no rotation: draw the glyph quad directly.
			idx := rl.GetGlyphIndex(f.font, g.r)
			rec := f.font.recs[idx]
			gi := f.font.glyphs[idx]
			pad := f32(f.font.glyphPadding)
			k := g.size * scale / max(f.size, 1)
			off := rotate_vec({(f32(gi.offsetX) - pad) * k, (f32(gi.offsetY) - pad) * k}, rotation)
			src := rl.Rectangle{rec.x - pad, rec.y - pad, rec.width + 2 * pad, rec.height + 2 * pad}
			rl.DrawTexturePro(f.font.texture, src, {world.x + off.x, world.y + off.y, src.width * k, src.height * k}, {0, 0}, rotation, col)
		}
	}
}

// --- TextNode ----------------------------------------------------------------------

Text_Align :: enum {
	Left,
	Center,
	Right,
}

// TextNode: text in the world (or on a UI layer): a font, size, colour,
// wrapping width, alignment, rich text markup, a localization key, and a
// typewriter reveal.
TextNode :: struct {
	using node:  Node,
	text:        string `gui:"true"`,
	font:        string `gui:"true"`, // project font ("" = the engine font)
	fontSize:    f32 `gui:"true" min:"4" max:"256"`,
	color:       rl.Color `gui:"true"`,
	align:       Text_Align `gui:"true"`,
	maxWidth:    f32 `gui:"true" min:"0" max:"4000"`, // wrap width (0 = one line per \n)
	lineSpacing: f32 `gui:"true" min:"0.5" max:"3"`,
	richText:    bool `gui:"true"`, // [color=..] [size=..] [wave] [shake]
	localized:   bool `gui:"true"`, // `text` is a key in the locale tables
	sdf:         bool `gui:"true"`, // sharp at any scale (vector fonts)
	revealSpeed: f32 `gui:"true" min:"0" max:"500"`, // characters per second (0 = all at once)
	revealed:    f32, // characters shown (typewriter)
	time:        f32,
	onRevealed:  EventSubject, // "revealed": the typewriter reached the end
	revealDone:  bool,
}

TextNode_Create :: proc(scene: ^Scene, name: string = "Text", parent: ^Node = nil) -> ^TextNode {
	t := CreateNode(scene.manager, TextNode)
	TextNode_Init(t)
	t.name = strings.clone(name, t.allocator) // owned: callers pass temp strings too
	scene->addNode(t, parent)
	return t
}

TextNode_Init :: proc(t: ^TextNode) {
	t.text = "Text"
	t.layer = .Layer4 // in front of sprites (layers 1-3), under UI (7)
	t.fontSize = 24
	t.color = rl.WHITE
	t.lineSpacing = 1.2
	t.richText = true
	t.update = TextNode_Update
	t.render = TextNode_Render
	t.onDestroy = TextNode_Destroy
	InitializeSubject(&t.onRevealed, "revealed", t)
}

TextNode_Destroy :: proc(node: ^Node, ctx: ^GameContext) {
	t := cast(^TextNode)node
	DestroySubject(&t.onRevealed)
}

// TextNode_DisplayText: what it shows (the translation when localized).
TextNode_DisplayText :: proc(t: ^TextNode, ctx: ^GameContext) -> string {
	gc := ctx if ctx != nil else t.gameContext
	if t.localized && gc != nil do return Locale_Get(gc.game, t.text)
	return t.text
}

// TextNode_SetText changes the text and restarts the typewriter.
TextNode_SetText :: proc(t: ^TextNode, text: string) {
	t.text = strings.clone(text, t.allocator)
	t.revealed = 0
	t.revealDone = false
}

@(private = "file")
measure_with :: proc(r: rune, size: f32, data: rawptr) -> f32 {
	return Text_MeasureRune(cast(^Text_Font)data, r, size)
}

// TextNode_Layout: the glyphs and block size as drawn (unscaled).
TextNode_Layout :: proc(t: ^TextNode, ctx: ^GameContext) -> ([]Text_Glyph, [2]f32, ^Text_Font) {
	f := Text_GetFont(t.font, t.fontSize, t.sdf, ctx if ctx != nil else t.gameContext)
	glyphs, size := Text_Layout(TextNode_DisplayText(t, ctx), {t.color, t.fontSize, {}}, t.maxWidth, int(t.align), t.lineSpacing, t.richText, measure_with, f)
	return glyphs, size, f
}

TextNode_Update :: proc(node: ^Node, ctx: ^GameContext, dt: f32) {
	t := cast(^TextNode)node
	t.time += dt
	if t.revealSpeed > 0 && !t.revealDone {
		t.revealed += t.revealSpeed * dt
		total := Text_PlainLength(TextNode_DisplayText(t, ctx), t.richText)
		if int(t.revealed) >= total {
			t.revealDone = true
			t.onRevealed->notify(t, nil, ctx)
		}
	}
}

TextNode_Render :: proc(node: ^Node, ctx: ^GameContext, dt: f32) {
	t := cast(^TextNode)node
	if !rl.IsWindowReady() do return
	glyphs, size, f := TextNode_Layout(t, ctx)
	scale := t.globalScale.x if t.globalScale.x != 0 else 1
	origin := t.globalPosition
	origin -= rotate_vec(size * t.pivot * scale, t.globalRotation) // the origin (node_origin.odin)
	reveal := -1
	if t.revealSpeed > 0 && !t.revealDone do reveal = int(t.revealed)
	Text_DrawGlyphs(f, glyphs, origin, t.globalRotation, scale, reveal, t.time)
}

// TextNode_Bounds: the text's world rectangle (unrotated), for culling.
TextNode_Bounds :: proc(t: ^TextNode, ctx: ^GameContext) -> rl.Rectangle {
	_, size, _ := TextNode_Layout(t, ctx)
	scale := t.globalScale.x if t.globalScale.x != 0 else 1
	o := t.globalPosition
	o -= size * t.pivot * scale
	return {o.x, o.y, size.x * scale, size.y * scale}
}
