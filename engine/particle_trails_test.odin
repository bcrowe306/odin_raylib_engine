package engine

import "core:testing"

// #130: trails keep a particle's recent path, a point every trailSegment
// pixels, at most trailLength points; off: nothing is kept.

@(test)
test_particle_trails :: proc(t: ^testing.T) {
	em: ParticleEmitter
	ParticleEmitter_Init(&em)
	defer ParticleEmitter_Destroy(&em)
	em.emitting = false
	em.localSpace = false
	em.position = {0, 0}
	em.lifetime = 10
	em.angle, em.angleSpread, em.velocity, em.velocitySpread = 0, 0, 100, 0
	em.gravityVelocity = 0

	// Off: no trail buffer.
	ParticleEmitter_EmitBurst(&em, 1)
	for _ in 0 ..< 10 do ParticleEmitter_Update(&em, 0.1)
	testing.expect_value(t, len(em.trails), 0)

	// On: 10px a step, a point every 25px, at most 4.
	ParticleEmitter_Restart(&em)
	em.emitting = false
	em.trailLength, em.trailSegment = 4, 25
	ParticleEmitter_EmitBurst(&em, 1)
	i := -1
	for p, k in em.particles do if p.alive do i = k
	testing.expect(t, i >= 0, "a particle")
	ParticleEmitter_Update(&em, 0.1) // x 10: the first point
	testing.expect_value(t, len(em.trails), len(em.particles))
	testing.expect_value(t, em.trails[i].count, u8(1))
	for _ in 0 ..< 2 do ParticleEmitter_Update(&em, 0.1) // x 30: 20 from it, none yet
	testing.expect_value(t, em.trails[i].count, u8(1))
	ParticleEmitter_Update(&em, 0.1) // x 40
	testing.expect_value(t, em.trails[i].count, u8(2))
	for _ in 0 ..< 30 do ParticleEmitter_Update(&em, 0.1)
	tr := em.trails[i]
	testing.expect_value(t, tr.count, u8(4))
	newest := tr.points[tr.head]
	testing.expect(t, newest.x <= em.particles[i].position.x && newest.x > em.particles[i].position.x - 25, "newest point just behind")

	// A new particle in that slot starts a new trail.
	ParticleEmitter_Restart(&em)
	em.emitting = false
	ParticleEmitter_EmitBurst(&em, 1)
	for p, k in em.particles do if p.alive && k < len(em.trails) do testing.expect_value(t, em.trails[k].count, u8(0))
}
