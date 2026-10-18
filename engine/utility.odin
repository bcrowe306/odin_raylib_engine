package engine

import rl "vendor:raylib"
import ui "../ui"

MIN_CACHED_FONT_SIZE :: ui.MIN_CACHED_FONT_SIZE
MAX_CACHED_FONT_SIZE :: ui.MAX_CACHED_FONT_SIZE

engineGuiFont: rl.Font

BeginEngineViewportMode :: proc(camera: rl.Camera2D) {
	ui.BeginViewportMode(camera)
}

EndEngineViewportMode :: proc() {
	ui.EndViewportMode()
}

InitEngineFonts :: proc(fontPath: cstring = "engine/Open_Sans/static/OpenSans-Regular.ttf") -> rl.Font {
	engineGuiFont = ui.InitFonts(fontPath)
	return engineGuiFont
}

UnloadEngineFonts :: proc() {
	ui.UnloadFonts()
	engineGuiFont = {}
}

GetEngineFont :: proc(size: f32) -> rl.Font {
	return ui.GetFont(size)
}

DrawEngineText :: proc(text: cstring, x, y: f32, size: f32, color: rl.Color) {
	ui.DrawText(text, x, y, size, color)
}

MeasureEngineText :: proc(text: cstring, size: f32) -> [2]f32 {
	return ui.MeasureText(text, size)
}

RectangleFlipHorizontal :: proc(rect: rl.Rectangle) -> rl.Rectangle {
	return rl.Rectangle{
		x = rect.x,
		y = rect.y,
		width = -rect.width,
		height = rect.height,
	}
}

RectangleFlipAxis :: proc(rect: ^rl.Rectangle, x: bool, y: bool) {
	if x {
		rect.width = -rect.width
	}
	if y {
		rect.height = -rect.height
	}
}
