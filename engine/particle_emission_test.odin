package engine

import "core:math"
import "core:strings"
import "core:testing"

// #127: emission shapes, lifetime variance, radial / orbit velocity,
// damping, size / alpha / speed curves over life.

@(private = "file")
fresh :: proc() -> ParticleEmitter {
	e: ParticleEmitter
	ParticleEmitter_Init(&e)
	e.gravityVelocity, e.velocity = 0, 0
	return e
}

@(private = "file")
emit :: proc(e: ^ParticleEmitter, n: int) {
	for _ in 0 ..< n do ParticleEmitter_Emit(e)
}

@(private = "file")
len2 :: proc(v: [2]f32) -> f32 {return math.sqrt(v.x * v.x + v.y * v.y)}

@(test)
test_particle_curve_sample :: proc(t: ^testing.T) {
	c := ParticleCurve{count = 2}
	c.points[0], c.points[1] = {0, 1}, {1, 0}
	testing.expect_value(t, ParticleCurve_Sample(&c, 0.5), 0.5)
	testing.expect_value(t, ParticleCurve_Sample(&c, -1), 1)
	testing.expect_value(t, ParticleCurve_Sample(&c, 2), 0)
	off: ParticleCurve
	testing.expect_value(t, ParticleCurve_Sample(&off, 0.3, 7), 7) // (off: the default)
}

@(test)
test_particle_emission_shapes :: proc(t: ^testing.T) {
	e := fresh()
	defer ParticleEmitter_Destroy(&e)
	e.amount = 200
	e.emissionShape, e.emissionRadius = .Circle, 10
	emit(&e, 200)
	for p in e.particles do if p.alive do testing.expectf(t, len2(p.position) <= 10.01, "in the disc: %v", p.position)

	e2 := fresh()
	defer ParticleEmitter_Destroy(&e2)
	e2.emissionShape, e2.emissionRadius, e2.emissionInnerRadius = .Ring, 10, 8
	e2.emitAlongNormal, e2.velocity = true, 50
	emit(&e2, 200)
	for p in e2.particles do if p.alive {
		r := len2(p.position)
		testing.expectf(t, r >= 7.99 && r <= 10.01, "in the ring: %v", r)
		// Out of the ring: the velocity points away from the centre.
		dot := (p.position.x * p.velocity.x + p.position.y * p.velocity.y) / (r * len2(p.velocity))
		testing.expectf(t, dot > 0.999, "along the normal: %v", dot)
	}

	e3 := fresh()
	defer ParticleEmitter_Destroy(&e3)
	e3.emissionShape, e3.spread = .Line, {20, 50}
	emit(&e3, 100)
	for p in e3.particles do if p.alive do testing.expectf(t, p.position.y == 0 && abs(p.position.x) <= 20, "on the line: %v", p.position)

	e4 := fresh()
	defer ParticleEmitter_Destroy(&e4)
	e4.emissionShape, e4.spread = .RectangleEdge, {20, 10}
	emit(&e4, 200)
	for p in e4.particles do if p.alive {
		onEdge := abs(abs(p.position.x) - 20) < 0.01 || abs(abs(p.position.y) - 10) < 0.01
		testing.expectf(t, onEdge && abs(p.position.x) <= 20.01 && abs(p.position.y) <= 10.01, "on the edge: %v", p.position)
	}

	e5 := fresh()
	defer ParticleEmitter_Destroy(&e5)
	e5.emissionShape, e5.spread = .Point, {20, 10}
	emit(&e5, 10)
	for p in e5.particles do if p.alive do testing.expect_value(t, p.position, [2]f32{0, 0})
}

@(test)
test_particle_lifetime_variance :: proc(t: ^testing.T) {
	e := fresh()
	defer ParticleEmitter_Destroy(&e)
	e.amount, e.lifetime, e.lifetimeVariance = 200, 1, 0.5
	emit(&e, 200)
	lo, hi: f32 = 10, 0
	for p in e.particles do if p.alive {lo = min(lo, p.lifetime); hi = max(hi, p.lifetime)}
	testing.expectf(t, lo >= 0.5 && hi <= 1.5 && hi - lo > 0.3, "lifetimes spread in 0.5..1.5: %v..%v", lo, hi)
}

@(test)
test_particle_radial_orbit_damping :: proc(t: ^testing.T) {
	step :: proc(e: ^ParticleEmitter, seconds: f32) {
		for _ in 0 ..< int(seconds * 100) do for i in 0 ..< len(e.particles) do Particle_Update(e, i, 0.01)
	}
	// Radial: 100 px/s away from the centre.
	e := fresh()
	defer ParticleEmitter_Destroy(&e)
	e.lifetime = 5
	e.emissionShape, e.emissionRadius, e.emissionInnerRadius = .Ring, 10, 10
	e.radialVelocity = 100
	emit(&e, 1)
	step(&e, 1)
	testing.expectf(t, abs(len2(e.particles[0].position) - 110) < 1, "110 from the centre: %v", len2(e.particles[0].position))

	// Orbit: a quarter turn in a second, same distance.
	o := fresh()
	defer ParticleEmitter_Destroy(&o)
	o.lifetime = 5
	o.emissionShape, o.emissionRadius, o.emissionInnerRadius = .Ring, 10, 10
	o.orbitVelocity = 90
	emit(&o, 1)
	start := o.particles[0].position
	step(&o, 1)
	end := o.particles[0].position
	angle := math.to_degrees(math.atan2(start.x * end.y - start.y * end.x, start.x * end.x + start.y * end.y))
	testing.expectf(t, abs(angle - 90) < 1 && abs(len2(end) - 10) < 0.1, "a quarter turn: %v deg, r %v", angle, len2(end))

	// Damping 1: the speed falls to e^-1 in a second.
	d := fresh()
	defer ParticleEmitter_Destroy(&d)
	d.lifetime, d.velocity, d.damping = 5, 100, 1
	emit(&d, 1)
	step(&d, 1)
	testing.expectf(t, abs(len2(d.particles[0].velocity) - 100 * math.exp(f32(-1))) < 0.5, "damped: %v", len2(d.particles[0].velocity))
}

@(test)
test_particle_curves_over_life :: proc(t: ^testing.T) {
	e := fresh()
	defer ParticleEmitter_Destroy(&e)
	e.lifetime, e.velocity = 2, 100
	e.sizeCurve = {count = 2}
	e.sizeCurve.points[0], e.sizeCurve.points[1] = {0, 1}, {1, 3}
	e.alphaCurve = {count = 2}
	e.alphaCurve.points[0], e.alphaCurve.points[1] = {0, 1}, {1, 0}
	e.speedCurve = {count = 1}
	e.speedCurve.points[0] = {0, 0} // (no movement at all)
	emit(&e, 1)
	start := e.particles[0].position
	for _ in 0 ..< 100 do Particle_Update(&e, 0, 0.01) // half the life
	p := e.particles[0]
	testing.expectf(t, abs(p.scale.x - 2) < 0.05, "size halfway: %v", p.scale)
	testing.expectf(t, p.color.a > 115 && p.color.a < 140, "alpha halfway: %v", p.color.a)
	testing.expect_value(t, p.position, start)
}

@(test)
test_particle_emission_saving :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("emission", false)
	pen := ParticleEmitterNode_Create(scene, "Ring")
	em := &pen.emitter
	em.emissionShape, em.emissionRadius, em.emissionInnerRadius, em.emitAlongNormal = .Ring, 40, 30, true
	em.radialVelocity, em.orbitVelocity, em.damping, em.lifetimeVariance = 20, 45, 2, 0.3
	em.sizeCurve = {count = 2}
	em.sizeCurve.points[0], em.sizeCurve.points[1] = {0, 0.5}, {1, 2}
	ProcessNodeQueues(scene.manager, &game.gameContext)
	saved := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expectf(t, strings.contains(saved, `"size_curve": [[0, 0.5], [1, 2]]`), "the curve: %s", saved)
	testing.expect(t, !strings.contains(saved, `"alpha_curve"`), "an unset curve isn't written")
	again := game->createScene("emission2", false)
	_ = Scene_InstantiateFromJSON(again, transmute([]u8)saved, &game.gameContext)
	ProcessNodeQueues(again.manager, &game.gameContext)
	re := cast(^ParticleEmitterNode)Scene_FindNodeByName(again, "Ring")
	if !testing.expect(t, re != nil, "found") do return
	r := &re.emitter
	testing.expect_value(t, r.emissionShape, ParticleEmissionShape.Ring)
	testing.expect_value(t, r.emissionInnerRadius, 30)
	testing.expect(t, r.emitAlongNormal, "along the normal")
	testing.expect_value(t, r.orbitVelocity, 45)
	testing.expect_value(t, r.damping, 2)
	testing.expect_value(t, r.sizeCurve.count, 2)
	testing.expect_value(t, r.sizeCurve.points[1], [2]f32{1, 2})
	testing.expect_value(t, r.alphaCurve.count, 0)
}
