package engine

import "core:fmt"
import "core:log"
import rl "vendor:raylib"




AnimationPlayerNode :: struct {
	using node: Node,
	animations: [dynamic]^Animation,
	animationIndex: int,
	currentFrame: int,
	ticker: Ticker,
	reverse: bool,
}

AnimationPlayerNode_AddAnimation :: proc(animationPlayer: ^AnimationPlayerNode, animation: ^Animation) {
	found:bool
	for a in animationPlayer.animations {
		if a == animation {
			found = true
			break
		}
	}
	if !found {
		_, err := append(&animationPlayer.animations, animation)
		if err != nil {
			log.error("Error appending animation to AnimationPlayerNode: ", err)
			return
		}
		if len(animationPlayer.animations) > 0 {
			animationPlayer.animationIndex = len(animationPlayer.animations) - 1
		}
	}
	else {
		log.warn("Animation is already in the animations collection for this AnimationPlayerNode")
	}
}

AnimationPlayerNode_RemoveAnimation :: proc(animationPlayer: ^AnimationPlayerNode, index: int) -> (success: bool) {
	if index < 0 || index >= len(animationPlayer.animations) {
		log.errorf("Cannot remove animation with index %d. Index is out of bounds", index)
		return false
	}
	ordered_remove(&animationPlayer.animations, index)
	return true

}


AnimationPlayerNode_Create :: proc(scene: ^Scene, name: string = "") -> ^AnimationPlayerNode {

	apn := CreateNode(scene.manager, AnimationPlayerNode)
	AnimationPlayerNode_Init(apn)
	if name != "" {
		apn.name = name
	}
	return apn
}

AnimationPlayerNode_Init :: proc(apn: ^AnimationPlayerNode) {
	Ticker_Init(&apn.ticker, false)
	apn.update = AnimationPlayerNode_Update
	apn.render = AnimationPlayerNode_Render
	apn.ticker->setFPS(12)
	apn.ticker->setCallback(proc(ticker: ^Ticker, currentTick: int, user_data: rawptr) {
		apn := cast(^AnimationPlayerNode)user_data
		AnimationPlayerNode_AdvanceFrame(apn)
	}, apn)
}


AnimationPlayerNode_AdvanceFrame :: proc(apn: ^AnimationPlayerNode) {
	a := apn.animations[apn.animationIndex]
	if apn.reverse {
		if apn.currentFrame <= auto_cast a.startFrame {
			if a.loop {
				apn.currentFrame = a.endFrame
			}
		}
		else {
			apn.currentFrame -= 1
		}
	}
	else {
		if apn.currentFrame >= auto_cast a.endFrame {
			if a.loop {
				apn.currentFrame = a.startFrame
			}
		}
		else {
			apn.currentFrame += 1
		}
	}
}

AnimationPlayerNode_Update :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	apn := cast(^AnimationPlayerNode)node
	apn.ticker->process()
}

AnimationPlayerNode_Render :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	apn := cast(^AnimationPlayerNode)node
	animation := apn.animations[apn.animationIndex]
	animation->renderFrame(apn.currentFrame, node)
}

AnimationPlayerNode_Start :: proc(apn: ^AnimationPlayerNode) {
	apn.ticker->start(true)
}
AnimationPlayerNode_Stop :: proc(apn: ^AnimationPlayerNode) {
	apn.ticker->stop()
}
AnimationPlayerNode_Reset :: proc(apn: ^AnimationPlayerNode) {
	apn.ticker->reset()
}

AnimationPlayerNode_Pause :: proc(apn: ^AnimationPlayerNode) {
	apn.ticker->pause()
}

AnimationPlayerNode_Resume :: proc(apn: ^AnimationPlayerNode) {
	apn.ticker->resume()
}

AnimationPlayerNode_SetFPS :: proc(apn: ^AnimationPlayerNode, fps: f32) {
	apn.ticker->setFPS(fps)
}

AnimationPlayerNode_SetAnimationIndex :: proc(apn: ^AnimationPlayerNode, index: int) {
	index := clamp(index, 0, len(apn.animations))
	apn.animationIndex = index
}

AnimationPlayerNode_SetAnimationByName :: proc(apn: ^AnimationPlayerNode, name: string) {
	index := -1
	for animation, i in apn.animations {

		if animation.name == name {
			index = i
			return
		}
	}
	if index != -1 {
		AnimationPlayerNode_SetAnimationIndex(apn, index)
	}
	else {
		log.warnf("Animation with name '%s' not found in AnimationPlayerNode", name)
	}
}


AnimationPlayerNode_GetAnimation :: proc(apn: ^AnimationPlayerNode) -> ^Animation {
	if len(apn.animations) == 0 {
		return nil
	}
	return apn.animations[apn.animationIndex]
}

AnimationPlayerNode_GetAnimationName :: proc(apn: ^AnimationPlayerNode) -> string {
	animation := AnimationPlayerNode_GetAnimation(apn)
	if animation == nil {
		return ""
	}
	return animation.name
}
