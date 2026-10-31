package engine

import "core:testing"

// #130: a sub-emitter bursts where the parent's particles die (or hit).

@(test)
test_particle_sub_emitter :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("sub", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	parent := ParticleEmitterNode_Create(scene, "Rockets")
	parent.position = {200, 200}
	parent.gameContext = &game.gameContext
	sub := ParticleEmitterNode_Create(scene, "Pop")
	sub.gameContext = &game.gameContext
	AddChild(scene.manager, parent, sub)
	ProcessNodeQueues(scene.manager, &game.gameContext)
	Node_SetGlobalPositions(scene.manager, scene.rootNode)

	// Parent: one particle flying right that lives 0.2s. Sub: only bursts,
	// in the world, slow and long-lived.
	ParticleEmitterNode_Stop(parent)
	parent.emitter.lifetime, parent.emitter.lifetimeVariance = 0.2, 0
	parent.emitter.angle, parent.emitter.angleSpread, parent.emitter.velocity, parent.emitter.velocitySpread = 0, 0, 500, 0
	parent.emitter.gravityVelocity = 0
	ParticleEmitterNode_Stop(sub)
	sub.emitter.localSpace = false
	sub.emitter.lifetime, sub.emitter.velocity, sub.emitter.gravityVelocity = 5, 0, 0
	sub.emitter.spread = {0, 0}

	// Hit only: a death makes nothing.
	parent.subEmitter, parent.subEmitterOn, parent.subEmitterAmount = "Pop", .Hit, 5
	ParticleEmitterNode_EmitBurst(parent, 1)
	for _ in 0 ..< 30 do game->run(1.0 / 60)
	testing.expect_value(t, sub.emitter.aliveCount, 0)

	// Death: 5 where the particle died, ~100px right of the parent.
	parent.subEmitterOn = .Death
	ParticleEmitterNode_EmitBurst(parent, 1)
	for _ in 0 ..< 30 do game->run(1.0 / 60)
	testing.expect_value(t, sub.emitter.aliveCount, 5)
	for p in sub.emitter.particles do if p.alive {
		testing.expectf(t, p.position.x > 280 && p.position.x < 320 && abs(p.position.y - 200) < 1, "born where it died: %v", p.position)
	}

	// Itself, or a path to nothing: no sub-emitter.
	parent.subEmitter = "."
	testing.expect(t, ParticleEmitterNode_SubEmitter(parent) == nil, "not itself")
	parent.subEmitter = "Nothing"
	testing.expect(t, ParticleEmitterNode_SubEmitter(parent) == nil, "missing")
}
