package ui

import "core:math"
import "core:os"
import "core:strings"
import rl "vendor:raylib"

MIN_CACHED_FONT_SIZE :: 8
MAX_CACHED_FONT_SIZE :: 72

DEFAULT_FONT_SIZE: f32 : 18.0
DEFAULT_FONT_SIZE_SM: f32 : 14.0
DEFAULT_FONT_SIZE_LG: f32 : 22.0

guiFont: rl.Font
fontPath: cstring = "engine/Open_Sans/static/OpenSans-Regular.ttf"
fontsBySize: [MAX_CACHED_FONT_SIZE + 1]rl.Font

EXTENDED_UI_CODEPOINTS := []rune{
	// Standard ASCII printable 32..126
	32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47,
	48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63,
	64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79,
	80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95,
	96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111,
	112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126,
	// Latin-1 Supplement (degrees, currency, math, common symbols)
	160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175,
	176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191,
	192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207,
	208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223,
	224, 225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239,
	240, 241, 242, 243, 244, 245, 246, 247, 248, 249, 250, 251, 252, 253, 254, 255,
	// Typographical & UI Symbols
	0x2013, 0x2014, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2026,
	0x2500, 0x2502, 0x2514, 0x251C, 0x2524, 0x25B6, 0x25BC, 0x25C0, 0x25B2,
	0x2713, 0x2715,
}

// Active viewport camera state so DrawText can render glyphs 1:1 in native screen pixels
// without FBO resampling blur or non-integer Camera2D scaling.
viewportMode: bool
viewportCamera: rl.Camera2D

BeginViewportMode :: proc(camera: rl.Camera2D) {
	viewportCamera = camera
	viewportMode = true
	rl.BeginMode2D(camera)
}

EndViewportMode :: proc() {
	if viewportMode {
		rl.EndMode2D()
		viewportMode = false
	}
}

InitFonts :: proc(path: cstring = "engine/Open_Sans/static/OpenSans-Regular.ttf") -> rl.Font {
	resolvedPath := path
	pStr := string(path)
	if !os.exists(pStr) {
		if os.exists("../engine/Open_Sans/static/OpenSans-Regular.ttf") {
			resolvedPath = "../engine/Open_Sans/static/OpenSans-Regular.ttf"
		} else if os.exists("../../engine/Open_Sans/static/OpenSans-Regular.ttf") {
			resolvedPath = "../../engine/Open_Sans/static/OpenSans-Regular.ttf"
		}
	}
	fontPath = resolvedPath

	if !rl.IsWindowReady() do return {}

	// Initialize Runa modern text engine with active TTF font
	_ = Runa_Init(string(resolvedPath))

	// Preload common UI pixel sizes
	for sz in i32(MIN_CACHED_FONT_SIZE)..=36 {
		_ = GetFont(f32(sz))
	}
	guiFont = GetFont(DEFAULT_FONT_SIZE)
	_ = InitIconFonts()
	return guiFont
}

UnloadFonts :: proc() {
	if !rl.IsWindowReady() do return
	Runa_Destroy()
	for i in MIN_CACHED_FONT_SIZE..=MAX_CACHED_FONT_SIZE {
		if fontsBySize[i].baseSize > 0 {
			rl.UnloadFont(fontsBySize[i])
			fontsBySize[i] = {}
		}
	}
	guiFont = {}
	UnloadIconFonts()
}

GetFont :: proc(size: f32) -> rl.Font {
	if !rl.IsWindowReady() do return guiFont

	sz := size if size > 0 else DEFAULT_FONT_SIZE
	pxSize := clamp(i32(math.round(sz)), MIN_CACHED_FONT_SIZE, MAX_CACHED_FONT_SIZE)
	if fontsBySize[pxSize].baseSize > 0 {
		return fontsBySize[pxSize]
	}

	// Rasterize TTF with extended glyphs and generate mipmaps for smooth scaling
	font := rl.LoadFontEx(fontPath, pxSize, raw_data(EXTENDED_UI_CODEPOINTS[:]), i32(len(EXTENDED_UI_CODEPOINTS)))
	if font.baseSize > 0 && font.texture.id > 0 {
		rl.GenTextureMipmaps(&font.texture)
		rl.SetTextureFilter(font.texture, .BILINEAR)
		fontsBySize[pxSize] = font
		return font
	}

	return guiFont
}

DrawText :: proc(text: cstring, x, y: f32, size: f32 = DEFAULT_FONT_SIZE, color: rl.Color = {238, 240, 246, 255}) {
	if !rl.IsWindowReady() do return
	sz := size if size > 0 else DEFAULT_FONT_SIZE

	if viewportMode && viewportCamera.zoom > 0 {
		zoom := viewportCamera.zoom
		sx := math.round(viewportCamera.offset.x + x * zoom)
		sy := math.round(viewportCamera.offset.y + y * zoom)
		sSize := clamp(math.round(sz * zoom), f32(MIN_CACHED_FONT_SIZE), f32(MAX_CACHED_FONT_SIZE))
		font := GetFont(sSize)

		// Step out of Camera2D to draw glyphs 1:1 on exact integer screen pixels
		rl.EndMode2D()
		if font.baseSize > 0 {
			rl.DrawTextEx(font, text, {sx, sy}, sSize, 0.0, color)
		} else {
			rl.DrawText(text, i32(sx), i32(sy), i32(sSize), color)
		}
		rl.BeginMode2D(viewportCamera)
		return
	}

	targetSize := clamp(math.round(sz), f32(MIN_CACHED_FONT_SIZE), f32(MAX_CACHED_FONT_SIZE))
	font := GetFont(targetSize)
	rx := math.round(x)
	ry := math.round(y)
	if font.baseSize > 0 {
		rl.DrawTextEx(font, text, {rx, ry}, targetSize, 0.0, color)
	} else {
		rl.DrawText(text, i32(rx), i32(ry), i32(targetSize), color)
	}
}

DrawTextStr :: proc(text: string, x, y: f32, size: f32 = DEFAULT_FONT_SIZE, color: rl.Color = {238, 240, 246, 255}) {
	if len(text) == 0 do return
	if !viewportMode && Runa_IsLoaded() {
		Runa_DrawText(text, x, y, size, color)
		return
	}
	cstr := strings.clone_to_cstring(text, context.temp_allocator)
	DrawText(cstr, x, y, size, color)
}

MeasureText :: proc(text: cstring, size: f32 = DEFAULT_FONT_SIZE) -> [2]f32 {
	sz := size if size > 0 else DEFAULT_FONT_SIZE
	if !rl.IsWindowReady() {
		targetSize := math.round(sz)
		return {f32(len(text)) * targetSize * 0.55, targetSize}
	}

	if viewportMode && viewportCamera.zoom > 0 {
		zoom := viewportCamera.zoom
		sSize := clamp(math.round(sz * zoom), f32(MIN_CACHED_FONT_SIZE), f32(MAX_CACHED_FONT_SIZE))
		font := GetFont(sSize)
		if font.baseSize > 0 {
			m := rl.MeasureTextEx(font, text, sSize, 0.0)
			return {m.x / zoom, m.y / zoom}
		}
	}

	targetSize := clamp(math.round(sz), f32(MIN_CACHED_FONT_SIZE), f32(MAX_CACHED_FONT_SIZE))
	font := GetFont(targetSize)
	if font.baseSize > 0 {
		return rl.MeasureTextEx(font, text, targetSize, 0.0)
	}
	return {f32(rl.MeasureText(text, i32(targetSize))), targetSize}
}

MeasureTextStr :: proc(text: string, size: f32 = DEFAULT_FONT_SIZE) -> [2]f32 {
	if len(text) == 0 do return {0, size}
	if !viewportMode && Runa_IsLoaded() {
		return Runa_MeasureText(text, size)
	}
	cstr := strings.clone_to_cstring(text, context.temp_allocator)
	return MeasureText(cstr, size)
}

PointInRect :: proc(pt: [2]f32, rect: rl.Rectangle) -> bool {
	return pt.x >= rect.x && pt.x <= (rect.x + rect.width) && pt.y >= rect.y && pt.y <= (rect.y + rect.height)
}
