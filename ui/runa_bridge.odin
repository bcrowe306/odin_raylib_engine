package ui

import "core:fmt"
import "core:math"
import "core:os"
import rl "vendor:raylib"
import runa "runa"
import raster "runa/raster"

// ============================================================================
// Runa Modern Text Engine Bridge for Raylib
// Features: OpenType shaping (GSUB/GPOS), kerning, ligatures, sub-pixel raster,
// shape caching, glyph atlas caching, and dirty-rectangle GPU updates.
// ============================================================================

RUNA_ATLAS_SIZE :: 1024

Glyph_Key :: struct {
	gid:    runa.Glyph_ID,
	size_q: u16, // size * 4 quantization
}

RunaEngine :: struct {
	loaded:      bool,
	font_bytes:  []u8,
	font:        runa.Font,
	atlas:       raster.Atlas,
	glyph_cache: map[Glyph_Key]raster.Atlas_Slot,
	shape_cache: runa.Cache,

	tex:         rl.Texture2D,
	mirror_rgba: []u8,
}

runaEngine: RunaEngine

Runa_Init :: proc(font_path: string) -> bool {
	if runaEngine.loaded {
		Runa_Destroy()
	}

	bytes, read_err := os.read_entire_file_from_path(font_path, context.allocator)
	if read_err != nil {
		return false
	}

	font, ferr := runa.font_load(bytes)
	if ferr != .None {
		delete(bytes)
		return false
	}

	runaEngine.font_bytes  = bytes
	runaEngine.font        = font
	runaEngine.atlas       = runa.atlas_make(RUNA_ATLAS_SIZE, RUNA_ATLAS_SIZE)
	runaEngine.shape_cache = runa.cache_make()

	runaEngine.mirror_rgba = make([]u8, RUNA_ATLAS_SIZE * RUNA_ATLAS_SIZE * 4)
	img := rl.Image{
		data    = raw_data(runaEngine.mirror_rgba),
		width   = RUNA_ATLAS_SIZE,
		height  = RUNA_ATLAS_SIZE,
		mipmaps = 1,
		format  = .UNCOMPRESSED_R8G8B8A8,
	}
	runaEngine.tex = rl.LoadTextureFromImage(img)
	rl.SetTextureFilter(runaEngine.tex, .BILINEAR)

	runaEngine.loaded = true

	// Warmup common UI font sizes: 13, 14, 15, 16, 18, 20, 24
	sizes := [7]f32{13.0, 14.0, 15.0, 16.0, 18.0, 20.0, 24.0}
	Runa_Warmup(sizes[:])

	return true
}

Runa_Destroy :: proc() {
	if !runaEngine.loaded do return
	rl.UnloadTexture(runaEngine.tex)
	delete(runaEngine.mirror_rgba)
	delete(runaEngine.glyph_cache)
	runa.cache_destroy(&runaEngine.shape_cache)
	runa.atlas_destroy(&runaEngine.atlas)
	runa.font_destroy(&runaEngine.font)
	delete(runaEngine.font_bytes)
	runaEngine = {}
}

Runa_IsLoaded :: proc() -> bool {
	return runaEngine.loaded
}

@(private="file")
runa_rescale_size :: proc(size: f32) -> f32 {
	extent := f32(runaEngine.font.ascent - runaEngine.font.descent)
	if extent <= 0 || runaEngine.font.units_per_em == 0 { return size }
	return size * f32(runaEngine.font.units_per_em) / extent
}

@(private="file")
runa_upload_page :: proc(page: ^raster.Atlas_Page) {
	x0 := int(page.dirty_min[0])
	y0 := int(page.dirty_min[1])
	x1 := int(page.dirty_max[0])
	y1 := int(page.dirty_max[1])
	w  := x1 - x0
	h  := y1 - y0
	if w <= 0 || h <= 0 { return }

	buf := make([]u8, w * h * 4)
	defer delete(buf)
	for row in 0..<h {
		src_off := (y0 + row) * RUNA_ATLAS_SIZE + x0
		dst_off := row * w * 4
		for col in 0..<w {
			a := page.pixels[src_off + col]
			buf[dst_off + col * 4 + 0] = 255
			buf[dst_off + col * 4 + 1] = 255
			buf[dst_off + col * 4 + 2] = 255
			buf[dst_off + col * 4 + 3] = a
		}
	}
	rl.UpdateTextureRec(
		runaEngine.tex,
		rl.Rectangle{f32(x0), f32(y0), f32(w), f32(h)},
		raw_data(buf),
	)

	page.is_dirty = false
	page.dirty_min = {}
	page.dirty_max = {}
}

@(private="file")
runa_get_slot :: proc(gid: runa.Glyph_ID, size: f32) -> (raster.Atlas_Slot, bool) {
	key := Glyph_Key{gid = gid, size_q = u16(size * 4)}
	if slot, hit := runaEngine.glyph_cache[key]; hit {
		return slot, true
	}

	slot, err := runa.raster_glyph(&runaEngine.font, gid, size, 0, &runaEngine.atlas)
	if err != .None {
		return {}, false
	}
	runaEngine.glyph_cache[key] = slot

	if int(slot.page_index) < len(runaEngine.atlas.pages_alpha) {
		page := &runaEngine.atlas.pages_alpha[slot.page_index]
		if page.is_dirty {
			runa_upload_page(page)
		}
	}
	return slot, true
}

Runa_Warmup :: proc(sizes: []f32) {
	if !runaEngine.loaded do return
	ascii: [95]u8
	for i in 0..<len(ascii) {
		ascii[i] = u8(0x20 + i)
	}
	warm := string(ascii[:])

	for s in sizes {
		rs := runa_rescale_size(s)
		shaped := runa.shape_text_cached(&runaEngine.font, warm, rs, &runaEngine.shape_cache)
		for g in shaped {
			_, _ = runa_get_slot(g.glyph_id, rs)
		}
	}
}

Runa_DrawText :: proc(text: string, x, y, size: f32, color: rl.Color) {
	if !runaEngine.loaded || len(text) == 0 do return
	rs := runa_rescale_size(size)

	shaped := runa.shape_text_cached(&runaEngine.font, text, rs, &runaEngine.shape_cache)

	ascent_em := f32(runaEngine.font.ascent) / f32(runaEngine.font.units_per_em)
	baseline  := y + ascent_em * rs

	pen_x := x
	for g in shaped {
		slot, ok := runa_get_slot(g.glyph_id, rs)
		if !ok {
			pen_x += g.x_advance
			continue
		}
		if slot.px_size.x > 0 && slot.px_size.y > 0 {
			src := rl.Rectangle{
				slot.uv_rect[0] * RUNA_ATLAS_SIZE,
				slot.uv_rect[1] * RUNA_ATLAS_SIZE,
				f32(slot.px_size.x),
				f32(slot.px_size.y),
			}
			dst := rl.Rectangle{
				math.floor(pen_x + g.x_offset + slot.bearing.x),
				math.floor(baseline + g.y_offset + slot.bearing.y),
				f32(slot.px_size.x),
				f32(slot.px_size.y),
			}
			rl.DrawTexturePro(runaEngine.tex, src, dst, {0, 0}, 0, color)
		}
		pen_x += g.x_advance
	}
}

Runa_MeasureText :: proc(text: string, size: f32) -> [2]f32 {
	if !runaEngine.loaded || len(text) == 0 do return {0, size}
	rs := runa_rescale_size(size)
	shaped := runa.shape_text_cached(&runaEngine.font, text, rs, &runaEngine.shape_cache)
	w: f32 = 0
	for g in shaped {
		w += g.x_advance
	}
	return {w, size}
}
