package engine

import rl "vendor:raylib"


ParticleEmitterNode :: struct {
	using node: Node,
	emitter: ParticleEmitter,
}

ParticleEmitterNode_Init :: proc(pen: ^ParticleEmitterNode) {
	InitializeNode(pen)
	pen.update = ParticleEmitterNode_Update
	pen.render = ParticleEmitterNode_Render
	pen.resource = &pen.emitter

	ParticleEmitter_Init(&pen.emitter)
	pen.emitter.amount = 100
	pen.emitter.lifetime = 2
	pen.emitter.burst = 0.5
	pen.emitter.size = {5, 5}
	pen.emitter.position = pen.position
	pen.emitter.useColorRamp = true
	pen.emitter.emitting = true
	pen.emitter.continuous = true
}

ParticleEmitterNode_Create :: proc(scene: ^Scene, name: string = "Particle Emitter") -> ^ParticleEmitterNode {
	pen := CreateNode(scene.manager, ParticleEmitterNode)
	ParticleEmitterNode_Init(pen)
	if name != "" {
		pen.name = name
	}
	scene->addNode(pen)
	return pen
}

ParticleEmitterNode_Start :: proc(pen: ^ParticleEmitterNode) {
	if pen.emitter.start != nil {
		pen.emitter->start()
	} else {
		ParticleEmitter_Start(&pen.emitter)
	}
}

ParticleEmitterNode_Stop :: proc(pen: ^ParticleEmitterNode) {
	if pen.emitter.stop != nil {
		pen.emitter->stop()
	} else {
		ParticleEmitter_Stop(&pen.emitter)
	}
}

ParticleEmitterNode_Update :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	pen := cast(^ParticleEmitterNode)node
	if !pen.enabled do return

	// Sync emitter emission center with node's globalPosition in scene graph
	pen.emitter.position = pen.globalPosition

	ParticleEmitter_Update(&pen.emitter, deltaTime)
}

ParticleEmitterNode_Render :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	if !rl.IsWindowReady() do return
	pen := cast(^ParticleEmitterNode)node
	if !pen.renderable do return

	ParticleEmitter_Render(&pen.emitter, deltaTime)
}
