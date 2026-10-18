package ui

import "core:math"
import "core:strings"
import rl "vendor:raylib"

MIN_CACHED_FONT_SIZE :: 8
MAX_CACHED_FONT_SIZE :: 72

guiFont: rl.Font
fontPath: cstring = "engine/Open_Sans/static/OpenSans-Regular.ttf"
fontsBySize: [MAX_CACHED_FONT_SIZE + 1]rl.Font

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
	fontPath = path
	if !rl.IsWindowReady() do return {}

	// Preload common UI pixel sizes (both full-scale and docked-viewport scale)
	for sz in i32(MIN_CACHED_FONT_SIZE)..=36 {
		_ = GetFont(f32(sz))
	}
	guiFont = GetFont(15)
	return guiFont
}

UnloadFonts :: proc() {
	if !rl.IsWindowReady() do return
	for i in MIN_CACHED_FONT_SIZE..=MAX_CACHED_FONT_SIZE {
		if fontsBySize[i].baseSize > 0 {
			rl.UnloadFont(fontsBySize[i])
			fontsBySize[i] = {}
		}
	}
	guiFont = {}
}

GetFont :: proc(size: f32) -> rl.Font {
	if !rl.IsWindowReady() do return guiFont

	pxSize := clamp(i32(math.round(size)), MIN_CACHED_FONT_SIZE, MAX_CACHED_FONT_SIZE)
	if fontsBySize[pxSize].baseSize > 0 {
		return fontsBySize[pxSize]
	}

	// Rasterize TTF at the exact 1:1 target pixel size so DrawTextEx uses scaleFactor = 1.0
	// with integer glyph advances and zero sub-pixel blurring.
	font := rl.LoadFontEx(fontPath, pxSize, nil, 0)
	if font.baseSize > 0 && font.texture.id > 0 {
		rl.SetTextureFilter(font.texture, .BILINEAR)
		fontsBySize[pxSize] = font
		return font
	}

	return guiFont
}

DrawText :: proc(text: cstring, x, y: f32, size: f32, color: rl.Color) {
	if !rl.IsWindowReady() do return

	if viewportMode && viewportCamera.zoom > 0 {
		zoom := viewportCamera.zoom
		sx := math.round(viewportCamera.offset.x + x * zoom)
		sy := math.round(viewportCamera.offset.y + y * zoom)
		sSize := clamp(math.round(size * zoom), f32(MIN_CACHED_FONT_SIZE), f32(MAX_CACHED_FONT_SIZE))
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

	targetSize := clamp(math.round(size), f32(MIN_CACHED_FONT_SIZE), f32(MAX_CACHED_FONT_SIZE))
	font := GetFont(targetSize)
	rx := math.round(x)
	ry := math.round(y)
	if font.baseSize > 0 {
		rl.DrawTextEx(font, text, {rx, ry}, targetSize, 0.0, color)
	} else {
		rl.DrawText(text, i32(rx), i32(ry), i32(targetSize), color)
	}
}

DrawTextStr :: proc(text: string, x, y: f32, size: f32, color: rl.Color) {
	cstr := strings.clone_to_cstring(text, context.temp_allocator)
	DrawText(cstr, x, y, size, color)
}

MeasureText :: proc(text: cstring, size: f32) -> [2]f32 {
	if !rl.IsWindowReady() {
		targetSize := math.round(size)
		return {f32(len(text)) * targetSize * 0.55, targetSize}
	}

	if viewportMode && viewportCamera.zoom > 0 {
		zoom := viewportCamera.zoom
		sSize := clamp(math.round(size * zoom), f32(MIN_CACHED_FONT_SIZE), f32(MAX_CACHED_FONT_SIZE))
		font := GetFont(sSize)
		if font.baseSize > 0 {
			m := rl.MeasureTextEx(font, text, sSize, 0.0)
			return {m.x / zoom, m.y / zoom}
		}
	}

	targetSize := clamp(math.round(size), f32(MIN_CACHED_FONT_SIZE), f32(MAX_CACHED_FONT_SIZE))
	font := GetFont(targetSize)
	if font.baseSize > 0 {
		return rl.MeasureTextEx(font, text, targetSize, 0.0)
	}
	return {f32(rl.MeasureText(text, i32(targetSize))), targetSize}
}

MeasureTextStr :: proc(text: string, size: f32) -> [2]f32 {
	cstr := strings.clone_to_cstring(text, context.temp_allocator)
	return MeasureText(cstr, size)
}

PointInRect :: proc(pt: [2]f32, rect: rl.Rectangle) -> bool {
	return pt.x >= rect.x && pt.x <= (rect.x + rect.width) && pt.y >= rect.y && pt.y <= (rect.y + rect.height)
}
