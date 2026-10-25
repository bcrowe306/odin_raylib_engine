package engine

import "core:math"
import "core:slice"

// ============================================================================
// Compositing an Aseprite frame (TODO E.3) the way Aseprite renders it: the
// render plan (layer order + cel z-index, NOTE.5), visible layers only (not
// reference layers), groups composited on their own when the file says so
// (header flag 2), cel opacity x layer opacity, the 19 blend modes, indexed
// (palette, transparent index) and grayscale images, tilemap cels (tileset
// tiles with X / Y / diagonal flips), linked cels.
//
// The blend functions are a port of Aseprite's doc library
// (aseprite/src/doc/blend_funcs.cpp, MIT license, Copyright (c) 2019-2025
// Igara Studio S.A., Copyright (c) 2001-2017 David Capello - see
// licenses/THIRD_PARTY_NOTICES.txt), with pixman's fixed-point helpers, so
// the pixels match Aseprite's (tests: engine/aseprite_test.odin against
// tests/aseprite/expected, rendered by Aseprite itself).
// ============================================================================

Ase_Render_Options :: struct {
	// Layers to show (by index; nil = the file's own visibility).
	visible:   []bool,
	// Aseprite's "new" blending (its default; layers' blend modes merge
	// with the backdrop's alpha). false: the old formulas.
	old_blend: bool,
}

// Ase_RenderFrame composites `frame` into `out` (width * height * 4 bytes,
// RGBA, cleared first).
Ase_RenderFrame :: proc(doc: ^Ase_Document, frame: int, out: []u8, opts := Ase_Render_Options{}) {
	img := slice.reinterpret([]u32, out[:doc.width * doc.height * 4])
	slice.fill(img, 0)
	if frame < 0 || frame >= len(doc.frames) do return
	render_children(doc, frame, -1, img, opts)
	// (u32 pixels are r | g << 8 | b << 16 | a << 24: the bytes are RGBA in memory.)
}

// Ase_RenderLayer composites one layer (a group: its children) of a frame.
Ase_RenderLayer :: proc(doc: ^Ase_Document, frame, layer: int, out: []u8, opts := Ase_Render_Options{}) {
	img := slice.reinterpret([]u32, out[:doc.width * doc.height * 4])
	slice.fill(img, 0)
	if frame < 0 || frame >= len(doc.frames) || layer < 0 || layer >= len(doc.layers) do return
	items := make([dynamic]Plan_Item, context.temp_allocator)
	order := 0
	plan_add(doc, frame, layer, &items, &order)
	render_plan(doc, frame, items[:], img, opts, 255)
}

@(private = "file")
Plan_Item :: struct {
	order: int,
	layer: int,
	cel:   ^Ase_Cel,
}

@(private = "file")
layer_cel :: proc(doc: ^Ase_Document, frame, layer: int) -> ^Ase_Cel {
	for &c in doc.frames[frame].cels do if c.layer == layer do return &c
	return nil
}

@(private = "file")
layer_shown :: proc(doc: ^Ase_Document, layer: int, opts: Ase_Render_Options) -> bool {
	if opts.visible != nil {
		for i := layer; i >= 0; i = doc.layers[i].parent {
			if i < len(opts.visible) && !opts.visible[i] do return false
			if .Reference in doc.layers[i].flags do return false
		}
		return true
	}
	return Ase_LayerVisible(doc, layer)
}

// plan_add: a layer into the render plan (groups: their children, unless
// groups are composited on their own).
@(private = "file")
plan_add :: proc(doc: ^Ase_Document, frame, layer: int, items: ^[dynamic]Plan_Item, order: ^int) {
	order^ += 1
	l := &doc.layers[layer]
	if l.kind == .Group && .Compose_Groups not_in doc.flags {
		for i in 0 ..< len(doc.layers) do if doc.layers[i].parent == layer do plan_add(doc, frame, i, items, order)
		return
	}
	append(items, Plan_Item{order^, layer, layer_cel(doc, frame, layer)})
}

@(private = "file")
render_children :: proc(doc: ^Ase_Document, frame, parent: int, img: []u32, opts: Ase_Render_Options) {
	items := make([dynamic]Plan_Item, context.temp_allocator)
	order := 0
	for i in 0 ..< len(doc.layers) do if doc.layers[i].parent == parent do plan_add(doc, frame, i, &items, &order)
	render_plan(doc, frame, items[:], img, opts, 255)
}

@(private = "file")
render_plan :: proc(doc: ^Ase_Document, frame: int, items: []Plan_Item, img: []u32, opts: Ase_Render_Options, _: int) {
	// Z-index (NOTE.5): order + z, ties by z.
	z :: proc(it: Plan_Item) -> int {return it.cel.z_index if it.cel != nil else 0}
	hasZ := false
	for it in items do if z(it) != 0 do hasZ = true
	if hasZ {
		for &it in items do it.order += z(it)
		slice.sort_by(items, proc(a, b: Plan_Item) -> bool {
			za := a.cel.z_index if a.cel != nil else 0
			zb := b.cel.z_index if b.cel != nil else 0
			return a.order < b.order || (a.order == b.order && za < zb)
		})
	}
	for it in items {
		if !layer_shown(doc, it.layer, opts) do continue
		l := &doc.layers[it.layer]
		switch l.kind {
		case .Group:
			// Composited on its own, then onto the image with the group's
			// opacity and blend mode.
			group := make([]u32, len(img), context.temp_allocator)
			render_children(doc, frame, it.layer, group, opts)
			blend := blender(l.blend, !opts.old_blend)
			for i in 0 ..< len(img) do if group[i] & 0xff000000 != 0 do img[i] = blend(img[i], group[i], int(l.opacity))
		case .Image, .Tilemap:
			c := it.cel
			if c == nil do continue
			opacity := mul_un8(int(c.opacity), int(l.opacity))
			draw_cel(doc, l, c, img, opacity, blender(l.blend, !opts.old_blend))
		}
	}
}

// src_pixel: a pixel of the sprite's depth as RGBA (ok = false: the
// transparent index / nothing to draw).
@(private = "file")
src_pixel :: #force_inline proc(doc: ^Ase_Document, px: []u8, i: int, background := false) -> (u32, bool) {
	switch doc.depth {
	case .RGBA:
		return u32(px[i * 4]) | u32(px[i * 4 + 1]) << 8 | u32(px[i * 4 + 2]) << 16 | u32(px[i * 4 + 3]) << 24, true
	case .Grayscale:
		v, a := u32(px[i * 2]), u32(px[i * 2 + 1])
		return v | v << 8 | v << 16 | a << 24, true
	case .Indexed:
		idx := px[i]
		// (Background layers are opaque: even the transparent index shows.)
		if idx == doc.transparent_index && !background do return 0, false
		if int(idx) >= len(doc.palette) do return 0, false
		c := doc.palette[idx].color
		if background do c[3] = 255 // (a background layer is opaque: palette alpha doesn't apply)
		return u32(c[0]) | u32(c[1]) << 8 | u32(c[2]) << 16 | u32(c[3]) << 24, true
	}
	return 0, false
}

@(private = "file")
draw_cel :: proc(doc: ^Ase_Document, l: ^Ase_Layer, c: ^Ase_Cel, img: []u32, opacity: int, blend: Blend_Func) {
	W, H := doc.width, doc.height
	if l.kind == .Tilemap {
		if l.tileset < 0 || l.tileset >= len(doc.tilesets) do return
		ts := &doc.tilesets[l.tileset]
		if ts.pixels == nil do return
		zeroEmpty := ts.flags & 4 != 0
		tw, th := ts.tile_w, ts.tile_h
		for ty in 0 ..< c.h {
			for tx in 0 ..< c.w {
				t := c.tiles[ty * c.w + tx]
				if zeroEmpty && t.index == 0 do continue
				if !zeroEmpty && t.index == 0xffffffff do continue
				if int(t.index) >= ts.count do continue
				base := int(t.index) * tw * th
				ox, oy := c.x + tx * tw, c.y + ty * th
				for y in 0 ..< th {
					dy := oy + y
					if dy < 0 || dy >= H do continue
					for x in 0 ..< tw {
						dx := ox + x
						if dx < 0 || dx >= W do continue
						sx := tw - 1 - x if t.xflip else x
						sy := th - 1 - y if t.yflip else y
						if t.dflip {
							sx, sy = sy, sx
							if sx >= min(tw, th) || sy >= min(tw, th) do continue
						}
						p, ok := src_pixel(doc, ts.pixels[base * bpp_of(doc):], sy * tw + sx)
						if !ok do continue
						img[dy * W + dx] = blend(img[dy * W + dx], p, opacity)
					}
				}
			}
		}
		return
	}
	if c.pixels == nil do return
	bg := .Background in l.flags
	for y in 0 ..< c.h {
		dy := c.y + y
		if dy < 0 || dy >= H do continue
		for x in 0 ..< c.w {
			dx := c.x + x
			if dx < 0 || dx >= W do continue
			p, ok := src_pixel(doc, c.pixels, y * c.w + x, bg)
			if !ok do continue
			img[dy * W + dx] = blend(img[dy * W + dx], p, opacity)
		}
	}
}

// Ase_TileImage: one tile of a tileset as RGBA (tile_w * tile_h * 4 bytes),
// flipped as a tilemap cel shows it.
Ase_TileImage :: proc(doc: ^Ase_Document, ts: ^Ase_Tileset, index: int, xflip, yflip, dflip: bool, out: []u8) {
	tw, th := ts.tile_w, ts.tile_h
	img := slice.reinterpret([]u32, out[:tw * th * 4])
	slice.fill(img, 0)
	if ts.pixels == nil || index < 0 || index >= ts.count do return
	base := index * tw * th
	for y in 0 ..< th {
		for x in 0 ..< tw {
			sx := tw - 1 - x if xflip else x
			sy := th - 1 - y if yflip else y
			if dflip {
				sx, sy = sy, sx
				if sx >= min(tw, th) || sy >= min(tw, th) do continue
			}
			if p, ok := src_pixel(doc, ts.pixels[base * bpp_of(doc):], sy * tw + sx); ok do img[y * tw + x] = p
		}
	}
}

@(private = "file")
bpp_of :: proc(doc: ^Ase_Document) -> int {
	switch doc.depth {
	case .RGBA: return 4
	case .Grayscale: return 2
	case .Indexed: return 1
	}
	return 4
}

// --- blend functions (a port of aseprite/src/doc/blend_funcs.cpp, MIT) -------------

Blend_Func :: #type proc(backdrop, src: u32, opacity: int) -> u32

@(private = "file") getr :: #force_inline proc(c: u32) -> int {return int(c & 0xff)}
@(private = "file") getg :: #force_inline proc(c: u32) -> int {return int(c >> 8 & 0xff)}
@(private = "file") getb :: #force_inline proc(c: u32) -> int {return int(c >> 16 & 0xff)}
@(private = "file") geta :: #force_inline proc(c: u32) -> int {return int(c >> 24 & 0xff)}
@(private = "file") rgba :: #force_inline proc(r, g, b, a: int) -> u32 {return u32(r & 0xff) | u32(g & 0xff) << 8 | u32(b & 0xff) << 16 | u32(a & 0xff) << 24}

// pixman's MUL_UN8 / DIV_UN8 (8-bit fixed point a*b/255, a/b).
@(private = "file")
mul_un8 :: #force_inline proc(a, b: int) -> int {
	t := a * b + 0x80
	return ((t >> 8) + t) >> 8
}
@(private = "file")
div_un8 :: #force_inline proc(a, b: int) -> int {return (a * 0xff + b / 2) / b}

@(private = "file")
blend_normal :: proc(backdrop, src: u32, opacity: int) -> u32 {
	if backdrop & 0xff000000 == 0 {
		a := mul_un8(geta(src), opacity)
		return src & 0x00ffffff | u32(a) << 24
	} else if src & 0xff000000 == 0 {
		return backdrop
	}
	Br, Bg, Bb, Ba := getr(backdrop), getg(backdrop), getb(backdrop), geta(backdrop)
	Sr, Sg, Sb := getr(src), getg(src), getb(src)
	Sa := mul_un8(geta(src), opacity)
	Ra := Sa + Ba - mul_un8(Ba, Sa)
	// (C's integer division truncates toward zero; so does Odin's.)
	Rr := Br + (Sr - Br) * Sa / Ra
	Rg := Bg + (Sg - Bg) * Sa / Ra
	Rb := Bb + (Sb - Bb) * Sa / Ra
	return rgba(Rr, Rg, Rb, Ra)
}

@(private = "file")
blend_merge :: proc(backdrop, src: u32, opacity: int) -> u32 {
	Br, Bg, Bb, Ba := getr(backdrop), getg(backdrop), getb(backdrop), geta(backdrop)
	Sr, Sg, Sb, Sa := getr(src), getg(src), getb(src), geta(src)
	Rr, Rg, Rb: int
	if Ba == 0 {
		Rr, Rg, Rb = Sr, Sg, Sb
	} else if Sa == 0 {
		Rr, Rg, Rb = Br, Bg, Bb
	} else {
		Rr = Br + mul_un8_signed(Sr - Br, opacity)
		Rg = Bg + mul_un8_signed(Sg - Bg, opacity)
		Rb = Bb + mul_un8_signed(Sb - Bb, opacity)
	}
	Ra := Ba + mul_un8_signed(Sa - Ba, opacity)
	if Ra == 0 do Rr, Rg, Rb = 0, 0, 0
	return rgba(Rr, Rg, Rb, Ra)
}

// MUL_UN8 on a (possibly negative) difference, as the C macro computes it
// with ints.
@(private = "file")
mul_un8_signed :: #force_inline proc(a, b: int) -> int {
	t := a * b + 0x80
	return ((t >> 8) + t) >> 8
}

// The channel formulas (b = backdrop, s = source).
@(private = "file") ch_multiply :: #force_inline proc(b, s: int) -> int {return mul_un8(b, s)}
@(private = "file") ch_screen :: #force_inline proc(b, s: int) -> int {return b + s - mul_un8(b, s)}
@(private = "file") ch_hard_light :: #force_inline proc(b, s: int) -> int {
	return ch_multiply(b, s << 1) if s < 128 else ch_screen(b, (s << 1) - 255)
}
@(private = "file") ch_overlay :: #force_inline proc(b, s: int) -> int {return ch_hard_light(s, b)}
@(private = "file") ch_darken :: #force_inline proc(b, s: int) -> int {return min(b, s)}
@(private = "file") ch_lighten :: #force_inline proc(b, s: int) -> int {return max(b, s)}
@(private = "file") ch_difference :: #force_inline proc(b, s: int) -> int {return abs(b - s)}
@(private = "file") ch_exclusion :: #force_inline proc(b, s: int) -> int {
	t := mul_un8(b, s)
	return b + s - 2 * t
}
@(private = "file") ch_divide :: #force_inline proc(b, s: int) -> int {
	if b == 0 do return 0
	if b >= s do return 255
	return div_un8(b, s)
}
@(private = "file") ch_color_dodge :: #force_inline proc(b, s: int) -> int {
	if b == 0 do return 0
	s2 := 255 - s
	if b >= s2 do return 255
	return div_un8(b, s2)
}
@(private = "file") ch_color_burn :: #force_inline proc(b, s: int) -> int {
	if b == 255 do return 255
	b2 := 255 - b
	if b2 >= s do return 0
	return 255 - div_un8(b2, s)
}
@(private = "file") ch_soft_light :: proc(_b, _s: int) -> int {
	b := f64(_b) / 255
	s := f64(_s) / 255
	d := ((16 * b - 12) * b + 4) * b if b <= 0.25 else math.sqrt(b)
	r := b - (1 - 2 * s) * b * (1 - b) if s <= 0.5 else b + (2 * s - 1) * (d - b)
	return int(r * 255 + 0.5)
}
@(private = "file") ch_addition :: #force_inline proc(b, s: int) -> int {return min(b + s, 255)}
@(private = "file") ch_subtract :: #force_inline proc(b, s: int) -> int {return max(b - s, 0)}

@(private = "file")
per_channel :: #force_inline proc(backdrop, src: u32, opacity: int, f: proc(b, s: int) -> int) -> u32 {
	r := f(getr(backdrop), getr(src))
	g := f(getg(backdrop), getg(src))
	b := f(getb(backdrop), getb(src))
	return blend_normal(backdrop, rgba(r, g, b, 0) | src & 0xff000000, opacity)
}

@(private = "file") blend_multiply :: proc(b, s: u32, o: int) -> u32 {return per_channel(b, s, o, ch_multiply)}
@(private = "file") blend_screen :: proc(b, s: u32, o: int) -> u32 {return per_channel(b, s, o, ch_screen)}
@(private = "file") blend_overlay :: proc(b, s: u32, o: int) -> u32 {return per_channel(b, s, o, ch_overlay)}
@(private = "file") blend_darken :: proc(b, s: u32, o: int) -> u32 {return per_channel(b, s, o, ch_darken)}
@(private = "file") blend_lighten :: proc(b, s: u32, o: int) -> u32 {return per_channel(b, s, o, ch_lighten)}
@(private = "file") blend_color_dodge :: proc(b, s: u32, o: int) -> u32 {return per_channel(b, s, o, ch_color_dodge)}
@(private = "file") blend_color_burn :: proc(b, s: u32, o: int) -> u32 {return per_channel(b, s, o, ch_color_burn)}
@(private = "file") blend_hard_light :: proc(b, s: u32, o: int) -> u32 {return per_channel(b, s, o, ch_hard_light)}
@(private = "file") blend_soft_light :: proc(b, s: u32, o: int) -> u32 {return per_channel(b, s, o, ch_soft_light)}
@(private = "file") blend_difference :: proc(b, s: u32, o: int) -> u32 {return per_channel(b, s, o, ch_difference)}
@(private = "file") blend_exclusion :: proc(b, s: u32, o: int) -> u32 {return per_channel(b, s, o, ch_exclusion)}
@(private = "file") blend_addition :: proc(b, s: u32, o: int) -> u32 {return per_channel(b, s, o, ch_addition)}
@(private = "file") blend_subtract :: proc(b, s: u32, o: int) -> u32 {return per_channel(b, s, o, ch_subtract)}
@(private = "file") blend_divide :: proc(b, s: u32, o: int) -> u32 {return per_channel(b, s, o, ch_divide)}

// HSL modes.
@(private = "file") lum :: #force_inline proc(r, g, b: f64) -> f64 {return 0.3 * r + 0.59 * g + 0.11 * b}
@(private = "file") sat :: #force_inline proc(r, g, b: f64) -> f64 {return max(r, g, b) - min(r, g, b)}
@(private = "file")
clip_color :: proc(r, g, b: ^f64) {
	l := lum(r^, g^, b^)
	n := min(r^, g^, b^)
	x := max(r^, g^, b^)
	if n < 0 {
		r^ = l + (r^ - l) * l / (l - n)
		g^ = l + (g^ - l) * l / (l - n)
		b^ = l + (b^ - l) * l / (l - n)
	}
	if x > 1 {
		r^ = l + (r^ - l) * (1 - l) / (x - l)
		g^ = l + (g^ - l) * (1 - l) / (x - l)
		b^ = l + (b^ - l) * (1 - l) / (x - l)
	}
}
@(private = "file")
set_lum :: proc(r, g, b: ^f64, l: f64) {
	d := l - lum(r^, g^, b^)
	r^ += d
	g^ += d
	b^ += d
	clip_color(r, g, b)
}
@(private = "file")
set_sat :: proc(r, g, b: ^f64, s: f64) {
	mn := min(r^, g^, b^)
	mx := max(r^, g^, b^)
	rng := mx - mn
	if rng > 0 {
		r^ = (r^ - mn) * s / rng
		g^ = (g^ - mn) * s / rng
		b^ = (b^ - mn) * s / rng
	} else {
		r^, g^, b^ = 0, 0, 0
	}
}
@(private = "file") f01 :: #force_inline proc(c: u32) -> (f64, f64, f64) {return f64(getr(c)) / 255, f64(getg(c)) / 255, f64(getb(c)) / 255}
@(private = "file") hsl_out :: #force_inline proc(r, g, b: f64, src: u32) -> u32 {
	return rgba(int(255 * r), int(255 * g), int(255 * b), 0) | src & 0xff000000
}

@(private = "file")
blend_hue :: proc(backdrop, src: u32, opacity: int) -> u32 {
	r, g, b := f01(backdrop)
	s := sat(r, g, b)
	l := lum(r, g, b)
	r, g, b = f01(src)
	set_sat(&r, &g, &b, s)
	set_lum(&r, &g, &b, l)
	return blend_normal(backdrop, hsl_out(r, g, b, src), opacity)
}
@(private = "file")
blend_saturation :: proc(backdrop, src: u32, opacity: int) -> u32 {
	r, g, b := f01(src)
	s := sat(r, g, b)
	r, g, b = f01(backdrop)
	l := lum(r, g, b)
	set_sat(&r, &g, &b, s)
	set_lum(&r, &g, &b, l)
	return blend_normal(backdrop, hsl_out(r, g, b, src), opacity)
}
@(private = "file")
blend_color :: proc(backdrop, src: u32, opacity: int) -> u32 {
	r, g, b := f01(backdrop)
	l := lum(r, g, b)
	r, g, b = f01(src)
	set_lum(&r, &g, &b, l)
	return blend_normal(backdrop, hsl_out(r, g, b, src), opacity)
}
@(private = "file")
blend_luminosity :: proc(backdrop, src: u32, opacity: int) -> u32 {
	r, g, b := f01(src)
	l := lum(r, g, b)
	r, g, b = f01(backdrop)
	set_lum(&r, &g, &b, l)
	return blend_normal(backdrop, hsl_out(r, g, b, src), opacity)
}

// The "new" blending (RGBA_BLENDER_N): the mode's result is merged with a
// plain normal blend by how opaque the backdrop is.
@(private = "file")
new_blend :: #force_inline proc(backdrop, src: u32, opacity: int, f: Blend_Func) -> u32 {
	if backdrop & 0xff000000 == 0 do return blend_normal(backdrop, src, opacity)
	normal := blend_normal(backdrop, src, opacity)
	blend := f(backdrop, src, opacity)
	Ba := geta(backdrop)
	normalToBlend := blend_merge(normal, blend, Ba)
	srcTotalAlpha := mul_un8(geta(src), opacity)
	compositeAlpha := mul_un8(Ba, srcTotalAlpha)
	return blend_merge(normalToBlend, blend, compositeAlpha)
}

@(private = "file")
OLD_BLENDERS := [Ase_Blend]Blend_Func {
	.Normal      = blend_normal,
	.Multiply    = blend_multiply,
	.Screen      = blend_screen,
	.Overlay     = blend_overlay,
	.Darken      = blend_darken,
	.Lighten     = blend_lighten,
	.Color_Dodge = blend_color_dodge,
	.Color_Burn  = blend_color_burn,
	.Hard_Light  = blend_hard_light,
	.Soft_Light  = blend_soft_light,
	.Difference  = blend_difference,
	.Exclusion   = blend_exclusion,
	.Hue         = blend_hue,
	.Saturation  = blend_saturation,
	.Color       = blend_color,
	.Luminosity  = blend_luminosity,
	.Addition    = blend_addition,
	.Subtract    = blend_subtract,
	.Divide      = blend_divide,
}

// (Odin procs can't capture: one wrapper per mode for the new blending.)
@(private = "file") n_multiply :: proc(b, s: u32, o: int) -> u32 {return new_blend(b, s, o, blend_multiply)}
@(private = "file") n_screen :: proc(b, s: u32, o: int) -> u32 {return new_blend(b, s, o, blend_screen)}
@(private = "file") n_overlay :: proc(b, s: u32, o: int) -> u32 {return new_blend(b, s, o, blend_overlay)}
@(private = "file") n_darken :: proc(b, s: u32, o: int) -> u32 {return new_blend(b, s, o, blend_darken)}
@(private = "file") n_lighten :: proc(b, s: u32, o: int) -> u32 {return new_blend(b, s, o, blend_lighten)}
@(private = "file") n_color_dodge :: proc(b, s: u32, o: int) -> u32 {return new_blend(b, s, o, blend_color_dodge)}
@(private = "file") n_color_burn :: proc(b, s: u32, o: int) -> u32 {return new_blend(b, s, o, blend_color_burn)}
@(private = "file") n_hard_light :: proc(b, s: u32, o: int) -> u32 {return new_blend(b, s, o, blend_hard_light)}
@(private = "file") n_soft_light :: proc(b, s: u32, o: int) -> u32 {return new_blend(b, s, o, blend_soft_light)}
@(private = "file") n_difference :: proc(b, s: u32, o: int) -> u32 {return new_blend(b, s, o, blend_difference)}
@(private = "file") n_exclusion :: proc(b, s: u32, o: int) -> u32 {return new_blend(b, s, o, blend_exclusion)}
@(private = "file") n_hue :: proc(b, s: u32, o: int) -> u32 {return new_blend(b, s, o, blend_hue)}
@(private = "file") n_saturation :: proc(b, s: u32, o: int) -> u32 {return new_blend(b, s, o, blend_saturation)}
@(private = "file") n_color :: proc(b, s: u32, o: int) -> u32 {return new_blend(b, s, o, blend_color)}
@(private = "file") n_luminosity :: proc(b, s: u32, o: int) -> u32 {return new_blend(b, s, o, blend_luminosity)}
@(private = "file") n_addition :: proc(b, s: u32, o: int) -> u32 {return new_blend(b, s, o, blend_addition)}
@(private = "file") n_subtract :: proc(b, s: u32, o: int) -> u32 {return new_blend(b, s, o, blend_subtract)}
@(private = "file") n_divide :: proc(b, s: u32, o: int) -> u32 {return new_blend(b, s, o, blend_divide)}

@(private = "file")
NEW_BLENDERS := [Ase_Blend]Blend_Func {
	.Normal      = blend_normal,
	.Multiply    = n_multiply,
	.Screen      = n_screen,
	.Overlay     = n_overlay,
	.Darken      = n_darken,
	.Lighten     = n_lighten,
	.Color_Dodge = n_color_dodge,
	.Color_Burn  = n_color_burn,
	.Hard_Light  = n_hard_light,
	.Soft_Light  = n_soft_light,
	.Difference  = n_difference,
	.Exclusion   = n_exclusion,
	.Hue         = n_hue,
	.Saturation  = n_saturation,
	.Color       = n_color,
	.Luminosity  = n_luminosity,
	.Addition    = n_addition,
	.Subtract    = n_subtract,
	.Divide      = n_divide,
}

@(private = "file")
blender :: proc(mode: Ase_Blend, newBlend: bool) -> Blend_Func {
	if int(mode) > int(Ase_Blend.Divide) do return blend_normal
	return NEW_BLENDERS[mode] if newBlend else OLD_BLENDERS[mode]
}
