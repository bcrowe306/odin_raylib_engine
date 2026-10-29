package engine

import "core:strings"
import b2 "vendor:box2d"
import rl "vendor:raylib"


ParticleEmitterNode :: struct {
	using node: Node,
	emitter: ParticleEmitter `gui:"true"`,
	onParticleHit: EventSubject, // "particle_hit"(node): a particle hit a body (collision on)
}

ParticleEmitterNode_Init :: proc(pen: ^ParticleEmitterNode) {
	InitializeNode(pen)
	pen.update = ParticleEmitterNode_Update
	pen.render = ParticleEmitterNode_Render
	pen.onDestroy = ParticleEmitterNode_Destroy
	pen.resource = &pen.emitter
	InitializeSubject(&pen.onParticleHit, "particle_hit", pen)
	pen.emitter.onHitUser = pen
	pen.emitter.onHit = proc(emitter: ^ParticleEmitter, hit: ^Node, user: rawptr) {
		pen := cast(^ParticleEmitterNode)user
		pen.onParticleHit->notify(pen, hit, pen.gameContext)
	}

	ParticleEmitter_Init(&pen.emitter)
	pen.emitter.allocator = pen.allocator
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
		pen.name = strings.clone(name, pen.allocator) // owned: callers pass temp strings too
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

	// The node's global transform: emission follows it; local particles are
	// drawn through it (#124).
	pen.emitter.position = pen.globalPosition
	pen.emitter.originRotation = pen.globalRotation
	pen.emitter.originScale = pen.globalScale

	world := gameContext.game.physicsWorld.worldId if gameContext != nil && gameContext.game != nil else b2.WorldId{}
	ParticleEmitter_Update(&pen.emitter, deltaTime, world)
}

ParticleEmitterNode_Destroy :: proc(node: ^Node, gameContext: ^GameContext) {
	DestroySubject(&(cast(^ParticleEmitterNode)node).onParticleHit)
}

ParticleEmitterNode_Render :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	if !rl.IsWindowReady() do return
	pen := cast(^ParticleEmitterNode)node
	if !pen.renderable do return

	pen.emitter.position, pen.emitter.originRotation, pen.emitter.originScale = pen.globalPosition, pen.globalRotation, pen.globalScale
	ParticleEmitter_Render(&pen.emitter, deltaTime)
}
