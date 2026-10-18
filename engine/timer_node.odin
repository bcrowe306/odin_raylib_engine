package engine

import "core:time"
TimerNode :: struct {
	using node: Node,
	elapsed: time.Duration,
	running: bool,
	duration: time.Duration,
	loop: bool,
	onTick: EventSubject,
	onExpire: EventSubject,
	start: proc(timer: ^TimerNode),
	setDuration: proc(timer: ^TimerNode, durationSec: f32),
}

TimerNode_Init :: proc(timer: ^TimerNode) {
	InitializeNode(timer)
	InitializeSubject(&timer.onTick)
	InitializeSubject(&timer.onExpire)
	timer.update = TimerNode_Update
	timer.onDestroy = TimerNode_Destroy
	timer.start = TimerNode_Start
	timer.setDuration = TimerNode_SetDuration
	timer.renderable = false
	timer.elapsed = 0
}

TimerNode_Destroy :: proc(node: ^Node, gameContext: ^GameContext) {
	timer := cast(^TimerNode)node
	DestroySubject(&timer.onTick)
	DestroySubject(&timer.onExpire)
}

TimerNode_Start :: proc(timer: ^TimerNode) {
	timer.elapsed = 0
	timer.running = true
}

TimerNode_Create :: proc(scene: ^Scene, durationSeconds: f32, auto_start: bool = false, loop: bool = false) -> ^TimerNode {
	timer := CreateNode(scene.manager, TimerNode)
	TimerNode_Init(timer)
	timer->setDuration(durationSeconds)
	timer.loop = loop
	timer.running = auto_start
	scene->addNode(timer)
	return timer
}

TimerNode_Update :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	timer := cast(^TimerNode)node
	if timer.running {
		timer.elapsed += time.Duration(deltaTime * f32(time.Second))
	}
	if timer.elapsed >= timer.duration {
		timer.onExpire->notify(timer, f32(0), gameContext)
		if timer.loop {
			timer.elapsed = 0
			timer.running = true
		}
		else {
			timer.elapsed = 0
			timer.running = false
		}
	}
}

TimerNode_SetDuration :: proc(timer: ^TimerNode, durationSec: f32) {
	timer.duration = time.Duration(durationSec * f32(time.Second))
}
