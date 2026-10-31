package engine

import "core:strings"
import rl "vendor:raylib"

// ============================================================================
// Particle presets (#130): a starting look for an emitter - fire, smoke,
// sparks, rain, snow, an explosion, magic. Applying one sets the emitter's
// look and motion (everything else back to a common base first, so presets
// don't pile up); its texture, when it has one, stays. The Particles tab's
// Preset menu and Lua's particle_apply_preset use it.
// ============================================================================

ParticlePreset :: enum {
	Fire,
	Smoke,
	Sparks,
	Rain,
	Snow,
	Explosion,
	Magic,
}

ParticlePreset_Name :: proc(p: ParticlePreset) -> string {
	switch p {
	case .Fire:      return "Fire"
	case .Smoke:     return "Smoke"
	case .Sparks:    return "Sparks"
	case .Rain:      return "Rain"
	case .Snow:      return "Snow"
	case .Explosion: return "Explosion"
	case .Magic:     return "Magic"
	}
	return ""
}

ParticlePreset_Parse :: proc(name: string) -> (ParticlePreset, bool) {
	for p in ParticlePreset do if strings.equal_fold(ParticlePreset_Name(p), name) do return p, true
	return .Fire, false
}

@(private = "file")
set_ramp :: proc(e: ^ParticleEmitter, stops: ..ColorStop) {
	e.useColorRamp = true
	e.colorRamp.count = 0
	for s in stops do ColorRamp_AddStop(&e.colorRamp, s.position, s.color)
}

@(private = "file")
set_curve :: proc(c: ^ParticleCurve, points: ..[2]f32) {
	c.count = 0
	for p in points {
		if c.count >= MAX_CURVE_POINTS do break
		c.points[c.count] = p
		c.count += 1
	}
}

// preset_base: the settings every preset starts from (the look and the
// motion; not the texture, collision layers, visibility or GPU mode).
@(private = "file")
preset_base :: proc(e: ^ParticleEmitter) {
	e.burst = 0
	e.continuous = true
	e.emitting = true
	e.lifetimeVariance = 0.2
	e.size, e.sizeVariance, e.sizeSpread = {6, 6}, 0, 0
	e.scaleStart, e.scaleEnd = {1, 1}, {1, 1}
	e.rotation, e.rotationVariance, e.rotationSpread = 0, 0, 0
	e.torque, e.torqueVariance, e.torqueSpread, e.torqueAcceleration = 0, 0, 0, 0
	e.particleColor, e.colorEnd, e.colorVariance = rl.WHITE, rl.WHITE, 0
	e.spread = {0, 0}
	e.velocity, e.velocityVariance, e.velocitySpread, e.velocityScale, e.acceleration = 0, 1, 0, 1, 0
	e.angle, e.angleVariance, e.angleSpread = -90, 1, 0
	e.gravityDirection, e.gravityVelocity, e.wind = {0, 1}, 0, {0, 0}
	e.collisionEnabled = false
	if e.shape != .Texture do e.shape = .Circle
	e.blendMode = .Alpha
	e.alignToVelocity = false
	e.emissionShape, e.emissionRadius, e.emissionInnerRadius, e.emitAlongNormal = .Point, 0, 0, false
	e.radialVelocity, e.orbitVelocity, e.damping = 0, 0, 0
	e.sizeCurve.count, e.alphaCurve.count, e.speedCurve.count = 0, 0, 0
	e.localSpace = true
	e.trailLength, e.trailSegment, e.trailWidth = 0, 6, 1
}

// ParticleEmitter_ApplyPreset gives the emitter a preset's look and restarts it.
ParticleEmitter_ApplyPreset :: proc(e: ^ParticleEmitter, preset: ParticlePreset) {
	if e == nil do return
	preset_base(e)
	switch preset {
	case .Fire:
		// Flames licking up from a small disc, bright where they overlap.
		e.amount, e.lifetime = 60, 1.0
		e.size, e.sizeVariance = {14, 14}, 0.4
		e.angleSpread, e.velocity, e.velocitySpread = 15, 90, 30
		e.gravityDirection, e.gravityVelocity = {0, -1}, 60
		e.emissionShape, e.emissionRadius = .Circle, 10
		e.blendMode = .Additive
		set_ramp(e, {0, {255, 240, 180, 255}}, {0.4, {255, 140, 30, 220}}, {0.75, {200, 40, 20, 120}}, {1, {60, 20, 10, 0}})
		set_curve(&e.sizeCurve, {0, 1}, {1, 0.3})
	case .Smoke:
		// Soft puffs that rise, grow and fade, left behind where they rose.
		e.amount, e.lifetime = 30, 3
		e.size, e.sizeVariance = {20, 20}, 0.3
		e.rotationSpread, e.rotationVariance = 180, 1
		e.angleSpread, e.velocity, e.velocitySpread = 20, 40, 15
		e.gravityDirection, e.gravityVelocity = {0, -1}, 10
		e.damping = 0.3
		e.emissionShape, e.emissionRadius = .Circle, 12
		e.localSpace = false
		set_ramp(e, {0, {120, 120, 120, 0}}, {0.15, {110, 110, 110, 160}}, {1, {90, 90, 90, 0}})
		set_curve(&e.sizeCurve, {0, 0.5}, {1, 2})
	case .Sparks:
		// Fast streaks thrown up and out, falling as they cool.
		e.amount, e.lifetime = 40, 0.6
		e.shape, e.size = .Line, {8, 2}
		e.alignToVelocity = true
		e.angleSpread, e.velocity, e.velocitySpread = 60, 300, 120
		e.gravityVelocity = 600
		e.damping = 0.5
		e.blendMode = .Additive
		set_ramp(e, {0, {255, 255, 220, 255}}, {0.5, {255, 180, 60, 255}}, {1, {255, 80, 0, 0}})
	case .Rain:
		// Thin drops falling across a wide line (put the emitter above the view).
		e.amount, e.lifetime = 150, 1.2
		e.shape, e.size = .Line, {14, 2}
		e.alignToVelocity = true
		e.angle, e.angleSpread = 95, 2
		e.velocity, e.velocitySpread = 700, 50
		e.emissionShape, e.spread = .Line, {640, 0}
		e.localSpace = false
		e.useColorRamp = false
		e.particleColor, e.colorEnd = {170, 190, 230, 170}, {170, 190, 230, 170}
	case .Snow:
		// Flakes drifting down and sideways over a wide line.
		e.amount, e.lifetime = 120, 6
		e.size, e.sizeVariance = {4, 4}, 0.5
		e.angle, e.angleSpread = 90, 20
		e.velocity, e.velocitySpread = 40, 15
		e.wind = {15, 0}
		e.emissionShape, e.spread = .Line, {640, 0}
		e.localSpace = false
		set_ramp(e, {0, {255, 255, 255, 0}}, {0.1, {255, 255, 255, 230}}, {0.85, {255, 255, 255, 230}}, {1, {255, 255, 255, 0}})
	case .Explosion:
		// One burst in every direction that slows, cools and turns to smoke.
		e.amount, e.lifetime, e.lifetimeVariance = 80, 0.9, 0.3
		e.burst, e.continuous = 1, false
		e.size, e.sizeVariance = {10, 10}, 0.5
		e.angle, e.angleSpread = 0, 180
		e.velocity, e.velocitySpread = 260, 140
		e.damping = 2.5
		e.blendMode = .Additive
		set_ramp(e, {0, {255, 255, 230, 255}}, {0.25, {255, 150, 40, 255}}, {0.6, {180, 40, 20, 180}}, {1, {50, 50, 50, 0}})
		set_curve(&e.sizeCurve, {0, 0.6}, {0.2, 1.2}, {1, 0.4})
	case .Magic:
		// Glowing motes circling a disc and drifting up.
		e.amount, e.lifetime = 50, 1.6
		e.size, e.sizeVariance = {6, 6}, 0.5
		e.angleSpread, e.velocity, e.velocitySpread = 180, 30, 20
		e.emissionShape, e.emissionRadius = .Circle, 24
		e.orbitVelocity = 90
		e.trailLength, e.trailSegment, e.trailWidth = 8, 4, 0.8
		e.gravityDirection, e.gravityVelocity = {0, -1}, 20
		e.blendMode = .Additive
		set_ramp(e, {0, {180, 120, 255, 0}}, {0.2, {200, 160, 255, 255}}, {0.7, {120, 220, 255, 200}}, {1, {80, 120, 255, 0}})
	}
	ParticleEmitter_Restart(e)
}
