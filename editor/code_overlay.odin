package editor

import "core:fmt"
import "core:strings"
import imgui "lib/imgui"

// ============================================================================
// Code tab overlays (hover, signature help, completion docs): drawn on the
// foreground layer (above the completion list's neighbours, without taking
// keyboard focus from the text), sized to their content up to a maximum,
// wrapped, scrolled with the mouse wheel when longer, and kept inside the
// Code area - below the anchor line, or above it when there's no room.
// ============================================================================

Overlay_Block :: struct {
	text:  string,
	mono:  bool, // code (the editor font)
	color: imgui.Vec4,
}

Code_Overlay :: struct {
	min, max: [2]f32, // where it was drawn (screen)
	frame:    i32,
	scroll:   f32,
	content:  f32, // height of the content (drives: > the box = it scrolls)
}

codeOverlays: map[string]Code_Overlay

CODE_OVERLAY_MAX :: [2]f32{560, 260}

@(private = "file")
block_font :: proc(b: Overlay_Block) -> (^imgui.Font, f32) {
	if b.mono do return code_font(), code_font_size() - 1
	return GlobalFonts.regular, imgui.GetFontSize()
}

// Code_Overlay draws an overlay anchored at a line (`anchor` = its top-left
// on screen, `lineH` its height). Returns its rectangle.
Code_Overlay_Draw :: proc(id: string, anchor: [2]f32, lineH: f32, blocks: []Overlay_Block, preferAbove := false, maxSize := CODE_OVERLAY_MAX, at := false) -> (rmin, rmax: [2]f32) {
	cm := &GlobalCode
	if len(blocks) == 0 do return
	area0, area1 := cm.areaMin, cm.areaMax
	PAD :: 9
	GAP :: 5
	room := [2]f32{area1.x - area0.x - 8, area1.y - area0.y - 8}
	maxW := min(maxSize.x, room.x)
	maxH := min(maxSize.y, room.y * 0.6)

	// Width: the widest block unwrapped, up to the maximum.
	w: f32 = 200
	for b in blocks {
		font, size := block_font(b)
		for line in strings.split_lines(b.text, context.temp_allocator) {
			lw := imgui.Font_CalcTextSizeA(font, size, max(f32), 0, strings.clone_to_cstring(line, context.temp_allocator)).x
			w = max(w, lw + 2 * PAD + 6)
		}
	}
	w = min(w, maxW)
	wrapW := w - 2 * PAD - 6
	heights := make([]f32, len(blocks), context.temp_allocator)
	content: f32 = 0
	for b, i in blocks {
		font, size := block_font(b)
		heights[i] = imgui.Font_CalcTextSizeA(font, size, max(f32), wrapW, strings.clone_to_cstring(b.text, context.temp_allocator)).y
		content += heights[i] + (GAP if i > 0 else 0)
	}
	h := min(content + 2 * PAD, maxH)

	below := anchor.y + lineH + 2
	above := anchor.y - 2 - h
	y := below
	if at do y = anchor.y // exactly there (kept inside the area)
	else if (preferAbove || below + h > area1.y - 4) && above >= area0.y + 4 do y = above
	y = clamp(y, area0.y + 4, max(area1.y - h - 4, area0.y + 4))
	x := clamp(anchor.x, area0.x + 4, max(area1.x - w - 4, area0.x + 4))
	rmin, rmax = {x, y}, {x + w, y + h}

	o := codeOverlays[id]
	io := imgui.GetIO()
	mouse := [2]f32{io.MousePos.x, io.MousePos.y}
	overflow := max(content + 2 * PAD - h, 0)
	if point_in_rect(mouse, rmin, rmax) && io.MouseWheel != 0 do o.scroll -= io.MouseWheel * lineH * 3
	o.scroll = clamp(o.scroll, 0, overflow)

	dl := imgui.GetForegroundDrawList()
	imgui.DrawList_AddRectFilled(dl, {x + 2, y + 3}, {rmax.x + 2, rmax.y + 3}, col_u32({0, 0, 0, 0.35}), 7)
	imgui.DrawList_AddRectFilled(dl, rmin, rmax, col_u32(UI_BG_RAISED), 7)
	imgui.DrawList_AddRect(dl, rmin, rmax, col_u32(ui_line(0.08)), 7)
	clip := imgui.Vec4{x + 1, y + 1, rmax.x - 1, rmax.y - 1}
	ty := y + PAD - o.scroll
	for b, i in blocks {
		if i > 0 do ty += GAP
		font, size := block_font(b)
		if ty + heights[i] > y && ty < rmax.y {
			imgui.DrawList_AddTextImFontPtr(dl, font, size, {x + PAD, ty}, col_u32(b.color), strings.clone_to_cstring(b.text, context.temp_allocator), nil, wrapW, &clip)
		}
		ty += heights[i]
	}
	if overflow > 0 {
		// Scroll bar.
		frac := h / (content + 2 * PAD)
		barH := max(h * frac, 16)
		barY := y + (h - barH) * (o.scroll / overflow)
		imgui.DrawList_AddRectFilled(dl, {rmax.x - 5, barY + 3}, {rmax.x - 2, barY + barH - 3}, col_u32(ui_line(0.22)), 2)
	}
	o.min, o.max, o.frame, o.content = rmin, rmax, imgui.GetFrameCount(), content + 2 * PAD
	codeOverlays[id] = o
	Drive_ItemRect(fmt.tprintf("code.overlay:%s", id), rmin, rmax)
	return
}

// Code_OverlayHovered: the mouse is over an overlay shown last frame ("" =
// any of them).
Code_OverlayHovered :: proc(id: string = "") -> bool {
	m := imgui.GetIO().MousePos
	for k, o in codeOverlays {
		if id != "" && k != id do continue
		if imgui.GetFrameCount() - o.frame > 1 do continue
		if m.x >= o.min.x && m.x <= o.max.x && m.y >= o.min.y && m.y <= o.max.y do return true
	}
	return false
}

// Code_OverlaysInside: every overlay shown now is inside the Code area and
// within its maximum size (drives).
Code_OverlaysInside :: proc() -> string {
	cm := &GlobalCode
	n := 0
	for id, o in codeOverlays {
		if imgui.GetFrameCount() - o.frame > 1 do continue
		n += 1
		if o.min.x < cm.areaMin.x - 1 || o.min.y < cm.areaMin.y - 1 || o.max.x > cm.areaMax.x + 1 || o.max.y > cm.areaMax.y + 1 do return fmt.tprintf("%s outside", id)
		if o.max.x - o.min.x > CODE_OVERLAY_MAX.x + 1 || o.max.y - o.min.y > CODE_OVERLAY_MAX.y + 1 do return fmt.tprintf("%s too big", id)
	}
	return fmt.tprintf("ok %d", n)
}

// markdown_blocks: LSP markdown as overlay blocks (code fences in the code
// font, other paragraphs as text).
markdown_blocks :: proc(text: string, out: ^[dynamic]Overlay_Block, color := UI_TEXT) {
	inCode := false
	cur := strings.builder_make(context.temp_allocator)
	flush :: proc(out: ^[dynamic]Overlay_Block, sb: ^strings.Builder, mono: bool, color: imgui.Vec4) {
		t := strings.trim(strings.to_string(sb^), "\n ")
		if t != "" && t != "---" do append(out, Overlay_Block{strings.clone(t, context.temp_allocator), mono, UI_ACCENT if mono else color})
		strings.builder_reset(sb)
	}
	for line in strings.split_lines(text, context.temp_allocator) {
		l := strings.trim_right_space(line)
		if strings.has_prefix(strings.trim_space(l), "```") {
			flush(out, &cur, inCode, color)
			inCode = !inCode
			continue
		}
		if !inCode && strings.trim_space(l) == "---" {
			flush(out, &cur, false, color)
			continue
		}
		strings.write_string(&cur, l)
		strings.write_byte(&cur, '\n')
	}
	flush(out, &cur, inCode, color)
}
