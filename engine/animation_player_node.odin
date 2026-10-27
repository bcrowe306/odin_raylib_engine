package engine

import "core:log"
import "core:strings"




AnimationPlayerNode :: struct {
	using node: Node,
	animations: [dynamic]^Animation,
	animationIndex: int,
	currentFrame: int,
	ticker: Ticker,
	reverse: bool `gui:"true"`,
	autoplay: bool `gui:"true"`, // start playing when the node becomes ready
	fps: f32, // frames per second of animations without their own
	defaultAnimation: string, // selected when the node becomes ready ("" = the saved current one)
	// "animation_finished"(name): a non-looping animation reached its end.
	onFinished: EventSubject,
	// "animation_event"(method): a Method key fired (also for listeners
	// without a script method of that name).
	onEvent: EventSubject,
	finishedNotified: bool,
	loopsDone:        int, // times a looping animation wrapped since it started (state machines' "animation finished")
	// Animations added with AddFrameAnimation/AddSheetAnimation are owned
	// (freed with the node); AddAnimation keeps caller-owned ones as is.
	owned: [dynamic]^Animation,
	// Crossfade (AnimationPlayerNode_Play with a blend time): property tracks
	// shared with the previous animation blend from it.
	blendFrom:      ^Animation,
	blendFromFrame: f32,
	blendTime:      f32,
	blendElapsed:   f32,
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
		apn.name = strings.clone(name, apn.allocator) // owned: callers pass temp strings too
	}
	return apn
}

AnimationPlayerNode_Init :: proc(apn: ^AnimationPlayerNode) {
	apn.animations = make([dynamic]^Animation, apn.allocator)
	Ticker_Init(&apn.ticker, false)
	apn.update = AnimationPlayerNode_Update
	apn.render = AnimationPlayerNode_Render
	apn.ready = AnimationPlayerNode_Ready
	apn.onDestroy = AnimationPlayerNode_Destroy
	apn.owned = make([dynamic]^Animation, apn.allocator)
	InitializeSubject(&apn.onFinished, "animation_finished", apn)
	InitializeSubject(&apn.onEvent, "animation_event", apn)
	apn.fps = 12
	apn.ticker->setFPS(12)
	apn.ticker->setCallback(proc(ticker: ^Ticker, currentTick: int, user_data: rawptr) {
		apn := cast(^AnimationPlayerNode)user_data
		AnimationPlayerNode_AdvanceFrame(apn)
	}, apn)
}


AnimationPlayerNode_AdvanceFrame :: proc(apn: ^AnimationPlayerNode) {
	if len(apn.animations) == 0 do return
	a := apn.animations[apn.animationIndex]
	reversed := AnimationPlayerNode_IsReversed(apn, a)
	if reversed {
		if apn.currentFrame <= auto_cast a.startFrame {
			if a.loop {
				apn.currentFrame = a.endFrame
				apn.loopsDone += 1
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
				apn.loopsDone += 1
			}
		}
		else {
			apn.currentFrame += 1
		}
	}
	if a.tracks != nil do AnimationPlayerNode_FireEvents(apn, apn.currentFrame - a.startFrame)
	// A non-looping animation that reached its last frame finishes once.
	atEnd := apn.currentFrame <= a.startFrame if reversed else apn.currentFrame >= a.endFrame
	if !a.loop && atEnd && !apn.finishedNotified {
		apn.finishedNotified = true
		apn.ticker->stop()
		apn.onFinished->notify(apn, a.name, apn.gameContext)
	}
}

AnimationPlayerNode_Ready :: proc(node: ^Node, gameContext: ^GameContext) {
	apn := cast(^AnimationPlayerNode)node
	if apn.defaultAnimation != "" {
		for a, i in apn.animations do if a.name == apn.defaultAnimation do AnimationPlayerNode_SetAnimationIndex(apn, i)
	}
	if apn.autoplay && len(apn.animations) > 0 do AnimationPlayerNode_Start(apn)
}

// AnimationPlayerNode_IsReversed: the animation plays backwards (its own
// Reverse, flipped by the player's).
AnimationPlayerNode_IsReversed :: proc(apn: ^AnimationPlayerNode, a: ^Animation) -> bool {
	return apn.reverse != (a != nil && a.reverse)
}

// AnimationPlayerNode_FPS: the current animation's rate (its own, else the
// player's).
AnimationPlayerNode_FPS :: proc(apn: ^AnimationPlayerNode) -> f32 {
	if a := AnimationPlayerNode_GetAnimation(apn); a != nil && a.fps > 0 do return a.fps
	return apn.fps if apn.fps > 0 else 12
}

@(private = "file")
apply_fps :: proc(apn: ^AnimationPlayerNode) {
	fps := AnimationPlayerNode_FPS(apn)
	if apn.ticker.framesPerSecond != fps do apn.ticker->setFPS(fps)
}

AnimationPlayerNode_Destroy :: proc(node: ^Node, gameContext: ^GameContext) {
	apn := cast(^AnimationPlayerNode)node
	DestroySubject(&apn.onFinished)
	DestroySubject(&apn.onEvent)
	rm := &gameContext.game.resourceManager if gameContext != nil && gameContext.game != nil else Node_ResourceManager(apn)
	for a in apn.owned {
		if a.renderFrame == FA_RenderFrame {
			fa := cast(^FrameAnimation)a
			for f in fa.frames do ResourceManager_ReleaseTexture(rm, f)
			FrameAnimation_Destroy(fa)
		} else if a.renderFrame == SSA_RenderFrame {
			ssa := cast(^SpriteSheetAnimation)a
			if ssa.spriteSheet != nil do ResourceManager_ReleaseTexture(rm, ssa.spriteSheet)
		}
	}
	clear(&apn.owned)
	clear(&apn.animations)
}

// AnimationPlayerNode_AddFrameAnimation adds an owned animation that plays
// a list of image files.
AnimationPlayerNode_AddFrameAnimation :: proc(apn: ^AnimationPlayerNode, rm: ^ResourceManager, name: string, framePaths: []string, loop := true) -> ^FrameAnimation {
	fa := new(FrameAnimation, apn.allocator)
	fa.frames = make([dynamic]^Texture, apn.allocator)
	FrameAnimation_Init(fa, strings.clone(name, apn.allocator))
	fa.loop = loop
	if rm != nil {
		for p in framePaths do FrameAnimation_AddFrame(fa, rm, p)
	}
	append(&apn.owned, cast(^Animation)fa)
	AnimationPlayerNode_AddAnimation(apn, fa)
	return fa
}

// AnimationPlayerNode_AddSheetAnimation adds an owned sprite-sheet animation
// (grid columns x rows, frames start..end in reading order).
AnimationPlayerNode_AddSheetAnimation :: proc(apn: ^AnimationPlayerNode, rm: ^ResourceManager, name: string, sheetPath: string, grid: [2]int, start, end: int, loop := true) -> ^SpriteSheetAnimation {
	ssa := new(SpriteSheetAnimation, apn.allocator)
	SpriteSheetAnimation_Init(ssa, strings.clone(name, apn.allocator))
	ssa.grid = {max(grid.x, 1), max(grid.y, 1)}
	ssa.startFrame, ssa.endFrame = start, end
	ssa.loop = loop
	if rm != nil && sheetPath != "" do SpriteSheetAnimation_LoadSpirteSheet(ssa, rm, sheetPath)
	append(&apn.owned, cast(^Animation)ssa)
	AnimationPlayerNode_AddAnimation(apn, ssa)
	return ssa
}

AnimationPlayerNode_Update :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	apn := cast(^AnimationPlayerNode)node
	apn.ticker->process()
	if apn.blendFrom != nil {
		apn.blendElapsed += deltaTime
		if apn.blendElapsed >= apn.blendTime do apn.blendFrom = nil
	}
	if a := AnimationPlayerNode_GetAnimation(apn); a != nil && len(a.tracks) > 0 {
		AnimationPlayerNode_ApplyTracks(apn, f32(apn.currentFrame - a.startFrame))
	}
}

AnimationPlayerNode_Render :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	apn := cast(^AnimationPlayerNode)node
	if len(apn.animations) == 0 do return
	animation := apn.animations[apn.animationIndex]
	if animation != nil && animation.renderFrame != nil {
		animation->renderFrame(apn.currentFrame, node)
	}
}

AnimationPlayerNode_Start :: proc(apn: ^AnimationPlayerNode) {
	apn.finishedNotified = false
	apn.loopsDone = 0
	apply_fps(apn)
	if a := AnimationPlayerNode_GetAnimation(apn); a != nil {
		apn.currentFrame = a.endFrame if AnimationPlayerNode_IsReversed(apn, a) else a.startFrame
		if a.tracks != nil do AnimationPlayerNode_FireEvents(apn, apn.currentFrame - a.startFrame)
	}
	apn.ticker->start(true)
}

// AnimationPlayerNode_Play switches to an animation (by name) and starts
// it; with blend > 0 its property tracks crossfade from the current
// animation's values over `blend` seconds.
AnimationPlayerNode_Play :: proc(apn: ^AnimationPlayerNode, name: string, blend: f32 = 0) {
	prev := AnimationPlayerNode_GetAnimation(apn)
	prevFrame := f32(apn.currentFrame - prev.startFrame) if prev != nil else 0
	if name != "" do AnimationPlayerNode_SetAnimationByName(apn, name)
	next := AnimationPlayerNode_GetAnimation(apn)
	apn.blendFrom = nil
	if blend > 0 && prev != nil && prev != next && len(prev.tracks) > 0 {
		apn.blendFrom = prev
		apn.blendFromFrame = prevFrame
		apn.blendTime = blend
		apn.blendElapsed = 0
	}
	AnimationPlayerNode_Start(apn)
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

// AnimationPlayerNode_SetFPS: the player's rate (animations with their own
// FPS keep it).
AnimationPlayerNode_SetFPS :: proc(apn: ^AnimationPlayerNode, fps: f32) {
	apn.fps = max(fps, 0.1)
	apply_fps(apn)
}

AnimationPlayerNode_SetAnimationIndex :: proc(apn: ^AnimationPlayerNode, index: int) {
	if len(apn.animations) == 0 do return
	index := clamp(index, 0, len(apn.animations) - 1)
	apn.animationIndex = index
	apply_fps(apn)
}

AnimationPlayerNode_SetAnimationByName :: proc(apn: ^AnimationPlayerNode, name: string) {
	index := -1
	for animation, i in apn.animations {

		if animation.name == name {
			index = i
			break
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
