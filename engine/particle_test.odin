package engine

import "core:math"
import "core:testing"
import rl "vendor:raylib"

@(test)
test_particle_emitter_negative_spread_and_variance :: proc(t: ^testing.T) {
	emitter: ParticleEmitter
	ParticleEmitter_Init(&emitter)

	// Inverted/negative parameters that previously triggered Odin's rand.float32_range assertion (Issue #21)
	emitter.spread = {-100, -200}
	emitter.sizeSpread = -50
	emitter.sizeVariance = -1
	emitter.rotationSpread = -180
	emitter.rotationVariance = -0.5
	emitter.angleSpread = -360
	emitter.angleVariance = -1
	emitter.torqueSpread = -500
	emitter.torqueVariance = -0.8
	emitter.velocitySpread = -200
	emitter.velocityVariance = -1
	emitter.colorVariance = -0.5

	for _ in 0..<50 {
		ParticleEmitter_Emit(&emitter)
	}

	testing.expect(t, len(emitter.particles) >= 16, "Particles ring buffer allocated")
	p := emitter.particles[0]
	testing.expect(t, p.alive, "Emitted particle is alive")
	testing.expect(t, !math.is_nan(p.position.x) && !math.is_nan(p.position.y), "Position is valid finite number")
	testing.expect(t, !math.is_nan(p.size.x) && !math.is_nan(p.size.y), "Size is valid finite number")
	testing.expect(t, !math.is_nan(p.velocity.x) && !math.is_nan(p.velocity.y), "Velocity is valid finite number")
}

@(test)
test_particle_emitter_node_lifecycle_negative_props :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer {
		game->terminate()
		free(game)
	}

	scene := game->createScene("emitter_test", true)
	testing.expect(t, scene != nil, "Scene created")

	pen := ParticleEmitterNode_Create(scene, "BuggyEmitter")
	testing.expect(t, pen != nil, "Emitter node created")

	// Set negative properties
	pen.emitter.spread = {-20, -40}
	pen.emitter.sizeSpread = -10
	pen.emitter.sizeVariance = -0.5
	pen.emitter.velocitySpread = -50
	pen.emitter.colorVariance = -0.3

	// Run updates which invoke ParticleEmitter_Emit internally
	game->run(0.016)
	game->run(0.05)
	testing.expect(t, pen.emitter.count > 0, "Particles emitted successfully without crashing")
}
