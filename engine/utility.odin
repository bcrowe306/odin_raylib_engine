package engine

import rl "vendor:raylib"


RectangleFlipHorizontal :: proc(rect: rl.Rectangle) -> rl.Rectangle {
	return rl.Rectangle{
		x = rect.x,
		y = rect.y,
		width = -rect.width,
		height = rect.height
	}
}

RectangleFlipAxis :: proc(rect : ^rl.Rectangle, x: bool, y:bool) {
	if x {
		rect.width = -rect.width
	}
	if y {
		rect.height = -rect.height
		}
}
