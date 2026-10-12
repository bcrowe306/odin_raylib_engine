package engine

import "core:fmt"
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
	rl.DrawTexturePro(texture.texture, animation.source, animation.dest, {0, 0}, node.globalRotation, rl.WHITE)
}


SpriteSheetAnimation :: struct {
	using animation: Animation,
	spriteSheet:     ^Texture,
	loadSpriteSheet: proc(ssa: ^SpriteSheetAnimation, rm: ^ResourceManager, filePath: string),
	grid:            [2]int,
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
	tex := animation.spriteSheet.texture
	grid := animation.grid
	frameSize: [2]f32 = {f32(tex.width) / f32(grid.x), f32(tex.height) / f32(grid.y)}
	x: int = (frame % grid.x) * auto_cast frameSize.x
	y: int = (frame / grid.x) * auto_cast frameSize.y

	animation.source = rl.Rectangle {
		x      = auto_cast x,
		y      = auto_cast y,
		width  = frameSize.x,
		height = frameSize.y,
	}
	animation.dest = rl.Rectangle {
		x      = node.globalPosition.x,
		y      = node.globalPosition.y,
		width  = frameSize.x * node.globalScale.x,
		height = frameSize.y * node.globalScale.y,
	}
	RectangleFlipAxis(&animation.source, animation.flipX, animation.flipY)
	rl.DrawTexturePro(
		animation.spriteSheet.texture,
		animation.source,
		animation.dest,
		{0, 0},
		node.globalRotation,
		rl.WHITE,
	)

}
