package engine

import "core:log"
import rl "vendor:raylib"

// Base struct interface for animations
Animation :: struct {
	name:        string,
	startFrame:  int,
	endFrame:    int,
	loop:        bool,
	flipX:       bool,
	flipY:       bool,
	source:      rl.Rectangle,
	dest:        rl.Rectangle,
	frameCount:  proc(animation: ^Animation) -> int,
	// Keyframed property tracks (animation_tracks.odin).
	tracks:      [dynamic]Property_Track,
	renderFrame: proc(animation: ^Animation, frame: int, node: ^Node),
}

FrameAnimation :: struct {
	using animation: Animation,
	frames:          [dynamic]^Texture,
	addFrame:        proc(frameAnimation: ^FrameAnimation, rm: ^ResourceManager, filePath: string),
}

FrameAnimation_Init :: proc(frameAnimation: ^FrameAnimation, name: string = "") {
	if name == "" && frameAnimation.name == "" {
		log.panic("Cannot create animation without name")
	}
	frameAnimation.name = name
	frameAnimation.renderFrame = FA_RenderFrame
	frameAnimation.frameCount = FA_FrameCount
	frameAnimation.addFrame = FrameAnimation_AddFrame
}

FrameAnimation_Destroy :: proc(frameAnimation: ^FrameAnimation) {
	if frameAnimation == nil do return
	delete(frameAnimation.frames)
	frameAnimation.frames = nil
}

FrameAnimation_AddFrame :: proc(
	frameAnimation: ^FrameAnimation,
	rm: ^ResourceManager,
	filePath: string,
) {
	texture, ok := rm->loadTexture(filePath)
	if ok && texture != nil {
		append(&frameAnimation.frames, texture)
		frameAnimation.endFrame = auto_cast len(frameAnimation.frames) - 1

	} else {
		log.error("Error adding frame. Texture file loading error.")
	}
}

FA_FrameCount :: proc(animation: ^Animation) -> int {
	animation := cast(^FrameAnimation)animation
	return animation.endFrame - animation.startFrame + 1
}

FA_RenderFrame :: proc(animation: ^Animation, frame: int, node: ^Node) {
	animation := cast(^FrameAnimation)animation
	if len(animation.frames) == 0 || frame < 0 || frame >= len(animation.frames) do return
	texture := animation.frames[frame]
	animation.source = rl.Rectangle {
		x      = 0,
		y      = 0,
		width  = auto_cast texture.texture.width,
		height = auto_cast texture.texture.height,
	}

	animation.dest = rl.Rectangle {
		x      = node.globalPosition.x,
		y      = node.globalPosition.y,
		width  = f32(texture.texture.width) * node.globalScale.x,
		height = f32(texture.texture.height) * node.globalScale.y,
	}

	RectangleFlipAxis(&animation.source, animation.flipX, animation.flipY)
	if rl.IsWindowReady() && texture.texture.id > 0 {
		rl.DrawTexturePro(texture.texture, animation.source, animation.dest, {0, 0}, node.globalRotation, rl.WHITE)
	}
}


SpriteSheetAnimation :: struct {
	using animation: Animation,
	spriteSheet:     ^Texture,
	loadSpriteSheet: proc(ssa: ^SpriteSheetAnimation, rm: ^ResourceManager, filePath: string),
	grid:            [2]int, // columns, rows
	margin:          [2]int, // px before the first cell (left, top)
	spacing:         [2]int, // px between cells
	// The cells played, in order (row-major indices); empty = start..end.
	cells:           [dynamic]int,
}

// SpriteSheet_CellRect: a cell's pixels in a sheet of `size` cut into
// `grid` cells, after `margin` and with `spacing` between cells.
SpriteSheet_CellRect :: proc(size: [2]f32, grid, margin, spacing: [2]int, cell: int) -> rl.Rectangle {
	cols, rows := max(grid.x, 1), max(grid.y, 1)
	w := (size.x - 2 * f32(margin.x) - f32(cols - 1) * f32(spacing.x)) / f32(cols)
	h := (size.y - 2 * f32(margin.y) - f32(rows - 1) * f32(spacing.y)) / f32(rows)
	col, row := cell % cols, cell / cols
	return {f32(margin.x) + f32(col) * (w + f32(spacing.x)), f32(margin.y) + f32(row) * (h + f32(spacing.y)), w, h}
}

// SpriteSheetAnimation_SetCells plays these cells in order.
SpriteSheetAnimation_SetCells :: proc(ssa: ^SpriteSheetAnimation, cells: []int, allocator := context.allocator) {
	if ssa.cells == nil do ssa.cells = make([dynamic]int, allocator)
	clear(&ssa.cells)
	append(&ssa.cells, ..cells)
	if len(cells) > 0 {
		ssa.startFrame, ssa.endFrame = 0, len(cells) - 1
	}
}


SpriteSheetAnimation_Init :: proc(ssa: ^SpriteSheetAnimation, name: string = "") {
	if name == "" && ssa.name == "" {
		log.panic("Cannot create animation without name")
	}
	if name != "" {
		ssa.name = name
	}
	ssa.renderFrame = SSA_RenderFrame
	ssa.frameCount = SSA_FrameCount
	ssa.loadSpriteSheet = SpriteSheetAnimation_LoadSpirteSheet
	ssa.grid.x = 8
	ssa.grid.y = 1
}

SpriteSheetAnimation_LoadSpirteSheet :: proc(
	ssa: ^SpriteSheetAnimation,
	rm: ^ResourceManager,
	filePath: string,
) {
	texture, ok := rm->loadTexture(filePath)
	if ok && texture != nil {
		ssa.spriteSheet = texture

	} else {
		log.error("Error adding frame. Texture file loading error.")
	}

}

SSA_FrameCount :: proc(animation: ^Animation) -> int {
	animation := cast(^SpriteSheetAnimation)animation
	return animation.endFrame - animation.startFrame + 1
}

SSA_RenderFrame :: proc(animation: ^Animation, frame: int, node: ^Node) {
	animation := cast(^SpriteSheetAnimation)animation
	if animation.spriteSheet == nil do return
	tex := animation.spriteSheet.texture
	cell := frame
	if len(animation.cells) > 0 do cell = animation.cells[clamp(frame, 0, len(animation.cells) - 1)]
	animation.source = SpriteSheet_CellRect({f32(tex.width), f32(tex.height)}, animation.grid, animation.margin, animation.spacing, cell)
	frameSize := [2]f32{animation.source.width, animation.source.height}
	animation.dest = rl.Rectangle {
		x      = node.globalPosition.x,
		y      = node.globalPosition.y,
		width  = frameSize.x * node.globalScale.x,
		height = frameSize.y * node.globalScale.y,
	}
	RectangleFlipAxis(&animation.source, animation.flipX, animation.flipY)
	if rl.IsWindowReady() && tex.id > 0 {
		rl.DrawTexturePro(
			animation.spriteSheet.texture,
			animation.source,
			animation.dest,
			{0, 0},
			node.globalRotation,
			rl.WHITE,
		)
	}
}
