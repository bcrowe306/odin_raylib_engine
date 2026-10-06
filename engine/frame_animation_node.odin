package engine

import "core:terminal"
import "core:fmt"
import rl "vendor:raylib"
import "core:log"

FrameAnimationNode :: struct {
	using node: Node,
	ticker: Ticker,
	start: u32,
	end: u32,
	currentFrame: u32,
	reverse: bool,
	loop: bool,
	origin: [2]f32,
	frames: [dynamic]^Texture,

}

FrameAnimationNode_Create :: proc(scene: ^Scene) -> ^FrameAnimationNode {
	fan := CreateNode(scene.manager, FrameAnimationNode)
	FrameAnimationNode_Init(fan)
	return fan
}

FrameAnimationNode_Init :: proc(fan: ^FrameAnimationNode) {
	Ticker_Init(&fan.ticker, false)
	fan.update = FrameAnimationNode_Update
	fan.render = FrameAnimationNode_Render
	fan.ticker->setFPS(12)
	fan.ticker->setCallback(proc(ticker: ^Ticker, currentTick: int, user_data: rawptr) {
		fan := cast(^FrameAnimationNode)user_data
		FrameAnimationNode_AdvanceFrame(fan)
	}, fan)
}


FrameAnimationNode_AddFrame :: proc(fan: ^FrameAnimationNode, rm: ^ResourceManager, filePath: string) {
	texture, ok := rm->loadTexture(filePath)
	if ok && texture != nil {
		append(&fan.frames, texture)
		fan.end = auto_cast len(fan.frames) - 1

	}
	else {
		log.error("Error adding frame. Texture file loading error.")
	}
}


FrameAnimationNode_AdvanceFrame :: proc(fan: ^FrameAnimationNode) {
	if fan.reverse {
		if fan.currentFrame <= auto_cast fan.start {
			if fan.loop {
				fan.currentFrame = fan.end
			}
		}
		else {
			fan.currentFrame -= 1
		}
	}
	else {
		if fan.currentFrame >= auto_cast fan.end {
			if fan.loop {
				fan.currentFrame = fan.start
			}
		}
		else {
			fan.currentFrame += 1
		}
	}
}

FrameAnimationNode_Update :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	fan := cast(^FrameAnimationNode)node

	fan.ticker->process()
}

FrameAnimationNode_Render :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	fan := cast(^FrameAnimationNode)node
	if fan.currentFrame < 0 && fan.currentFrame >= auto_cast len(fan.frames) {
		log.errorf("fan.currentFrame: %d is out of bounds with fan.frames: &d", fan.currentFrame, len(fan.frames))
		return
	}
	if !fan.enabled {
		log.warn("Node is disabled. Not rendering")
		return
	}
	texture := fan.frames[fan.currentFrame]
	source := rl.Rectangle{
		x = 0,
		y = 0,
		width = auto_cast texture.texture.width,
		height = auto_cast texture.texture.height,
	}

	destination := rl.Rectangle{
		x = fan.globalPosition.x,
		y = fan.globalPosition.y,
		width = f32(texture.texture.width) * fan.globalScale.x,
		height = f32(texture.texture.height) * fan.globalScale.y
	}
	rl.DrawTexturePro(texture.texture, source, destination, fan.origin, fan.rotation, rl.WHITE)
}

FrameAnimationNode_Start :: proc(fan: ^FrameAnimationNode) {
	fan.ticker->start(true)
}
FrameAnimationNode_Stop :: proc(fan: ^FrameAnimationNode) {
	fan.ticker->stop()
}
FrameAnimationNode_Reset :: proc(fan: ^FrameAnimationNode) {
	fan.ticker->reset()
}
FrameAnimationNode_Pause :: proc(fan: ^FrameAnimationNode) {
	fan.ticker->pause()
}
FrameAnimationNode_Resume :: proc(fan: ^FrameAnimationNode) {
	fan.ticker->resume()
}

FrameAnimationNode_SetFPS :: proc(fan: ^FrameAnimationNode, fps: f32) {
	fan.ticker->setFPS(fps)
}
