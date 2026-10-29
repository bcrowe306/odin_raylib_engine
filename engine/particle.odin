package engine

import "base:runtime"
import "core:mem"

import "core:math/rand"
import "core:crypto"
import "core:math"
import "core:fmt"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import ui "../ui"
import b2 "vendor:box2d"

MAX_COLOR_STOPS :: 8

ColorStop :: struct {
	position: f32, // 0.0 to 1.0 along particle lifetime
	color: rl.Color,
}

ColorRamp :: struct {
	stops: [MAX_COLOR_STOPS]ColorStop,
	count: int,
}

ColorRamp_Init :: proc(ramp: ^ColorRamp) {
	ramp.count = 3
	ramp.stops[0] = {position = 0.0, color = rl.Color{255, 230, 100, 255}} // Warm Yellow-White at spawn
	ramp.stops[1] = {position = 0.5, color = rl.Color{230, 50, 40, 255}}   // Fiery Red at mid-life
	ramp.stops[2] = {position = 1.0, color = rl.Color{40, 40, 40, 0}}      // Fade to transparent at death
}

ColorRamp_Evaluate :: proc(ramp: ^ColorRamp, t: f32) -> rl.Color {
	if ramp.count == 0 do return rl.WHITE
	if ramp.count == 1 do return ramp.stops[0].color

	clampedT := math.clamp(t, 0.0, 1.0)
	if clampedT <= ramp.stops[0].position do return ramp.stops[0].color
	if clampedT >= ramp.stops[ramp.count - 1].position do return ramp.stops[ramp.count - 1].color

	for i in 0..<(ramp.count - 1) {
		p0 := ramp.stops[i].position
		p1 := ramp.stops[i + 1].position
		if clampedT >= p0 && clampedT <= p1 {
			diff := p1 - p0
			localT := (clampedT - p0) / diff if diff > 0.0001 else 0.0
			r := u8(math.clamp(math.lerp(f32(ramp.stops[i].color.r), f32(ramp.stops[i + 1].color.r), localT), 0, 255))
			g := u8(math.clamp(math.lerp(f32(ramp.stops[i].color.g), f32(ramp.stops[i + 1].color.g), localT), 0, 255))
			b := u8(math.clamp(math.lerp(f32(ramp.stops[i].color.b), f32(ramp.stops[i + 1].color.b), localT), 0, 255))
			a := u8(math.clamp(math.lerp(f32(ramp.stops[i].color.a), f32(ramp.stops[i + 1].color.a), localT), 0, 255))
			return rl.Color{r, g, b, a}
		}
	}
	return ramp.stops[ramp.count - 1].color
}

ColorRamp_Sort :: proc(ramp: ^ColorRamp, trackingIdx: ^int = nil) {
	targetStop := ColorStop{}
	if trackingIdx != nil && trackingIdx^ >= 0 && trackingIdx^ < ramp.count {
		targetStop = ramp.stops[trackingIdx^]
	}
	for i in 1..<ramp.count {
		key := ramp.stops[i]
		j := i - 1
		for j >= 0 && ramp.stops[j].position > key.position {
			ramp.stops[j + 1] = ramp.stops[j]
			j -= 1
		}
		ramp.stops[j + 1] = key
	}
	if trackingIdx != nil {
		for i in 0..<ramp.count {
			if ramp.stops[i].position == targetStop.position && ramp.stops[i].color == targetStop.color {
				trackingIdx^ = i
				break
			}
		}
	}
}

ColorRamp_AddStop :: proc(ramp: ^ColorRamp, pos: f32, color: rl.Color) -> int {
	if ramp.count >= MAX_COLOR_STOPS do return -1
	idx := ramp.count
	ramp.stops[idx] = {position = math.clamp(pos, 0.0, 1.0), color = color}
	ramp.count += 1
	selected := idx
	ColorRamp_Sort(ramp, &selected)
	return selected
}

ColorRamp_RemoveStop :: proc(ramp: ^ColorRamp, index: int) -> bool {
	if ramp.count <= 2 || index < 0 || index >= ramp.count do return false
	for i in index..<(ramp.count - 1) {
		ramp.stops[i] = ramp.stops[i + 1]
	}
	ramp.count -= 1
	return true
}

ParticleShape :: enum {
	Circle,
	Ellipse,
	Rectangle,
	Pixel,
	Line,
	Texture,
	Custom,
}

// How particles are blended over what's behind them (#126).
ParticleBlend :: enum {
	Alpha,         // ordinary transparency
	Additive,      // light adds up: fire, glow, sparks, magic
	Multiply,      // darkens: shadows, soot
	Premultiplied, // textures with premultiplied alpha
}

// Which frame of a sprite sheet a particle shows (#126).
ParticleFrameMode :: enum {
	OverLifetime, // the sheet once, from birth to death
	Speed,        // frameSpeed frames per second, looping
	Random,       // one frame per particle, picked at birth
}

// What a particle does when it hits the physics world (#123).
ParticleCollisionMode :: enum {
	Bounce, // reflected (elasticity), slowed along the surface (friction)
	Stop,   // rests where it hit
	Kill,   // dies
}

ParticleEmitter :: struct {
	amount: int `gui:"true" min:"1" max:"5000"`,
	lifetime: f32 `gui:"true" min:".01" max:"5"`,
	position: [2]f32 `gui:"true" min:"0" max:"1280" save:"false"`,
	burst: f32 `gui:"true" min:"0" max:"1"`,
	size: [2]f32 `gui:"true" min:".01" max:"100"`,
	sizeVariance: f32 `gui:"true" min:"0" max:"1"`, // 0-1
	sizeSpread: f32 `gui:"true" min:"0" max:"50"`,
	scaleStart: [2]f32 `gui:"true" min:"0" max:"1"`,
	scaleEnd: [2]f32 `gui:"true" min:"0" max:"1"`,
	rotation: f32 `gui:"true" min:"0" max:"359"`,
	rotationVariance: f32 `gui:"true" min:"0" max:"1"`, // 0-1
	rotationSpread: f32 `gui:"true" min:"0" max:"359"`,
	torque: f32 `gui:"true" min:"-2000" max:"2000"`,
	torqueVariance: f32 `gui:"true" min:"0" max:"1"`, // 0-1
	torqueSpread: f32 `gui:"true" min:"0" max:"2000"`,
	torqueAcceleration: f32 `gui:"true" min:"-2000" max:"2000"`,
	useColorRamp: bool `gui:"true"`,    // colour over lifetime from colorRamp (else particleColor -> colorEnd)
	colorRamp: ColorRamp,              // saved as "color_ramp" (scene_serialization.odin)
	particleColor: rl.Color `gui:"true"`,
	colorEnd: rl.Color `gui:"true"`,
	colorVariance: f32 `gui:"true" min:"0" max:"1"`,
	spread: [2]f32 `gui:"true" min:"0" max:"1280"`,
	velocity: f32 `gui:"true" min:"0" max:"2000"`,
	velocityVariance: f32 `gui:"true" min:"0" max:"1"`, // 0-1
	velocitySpread: f32 `gui:"true" min:"0" max:"2000"`,
	velocityScale: f32 `gui:"true" min:"0" max:"10"`,
	acceleration: f32 `gui:"true" min:"-2000" max:"2000"`,
	angle: f32 `gui:"true" min:"0" max:"359"`,
	angleVariance: f32 `gui:"true" min:"0" max:"1"`, // 0-1
	angleSpread: f32 `gui:"true" min:"0" max:"360"`,
	gravityDirection: [2]f32 `gui:"true" min:"-1" max:"1"`,
	gravityVelocity: f32 `gui:"true" min:"-2000" max:"2000"`,
	wind: [2]f32 `gui:"true" min:"-1000" max:"1000"`,
	// Collision with the physics world (static / kinematic / dynamic bodies,
	// tile maps, LDtk solids; not trigger areas), on the layers in
	// collisionLayers (#123).
	collisionEnabled: bool `gui:"true"`,
	collisionMode: ParticleCollisionMode `gui:"true"`,
	collisionLayers: CollisionLayerSet `gui:"true"`,
	elasticity: f32 `gui:"true" min:"0" max:"1"`,
	friction: f32 `gui:"true" min:"0" max:"1"`,
	// The last hit (world point, surface normal, the node hit) and who is
	// told about each hit (the node: its particle_hit event).
	lastHitPoint, lastHitNormal: [2]f32,
	lastHitNode: ^Node,
	onHit: proc(emitter: ^ParticleEmitter, hit: ^Node, user: rawptr),
	onHitUser: rawptr,
	shape: ParticleShape `gui:"true" min:"0" max:"2000"`,
	emitting: bool `gui:"true"`,
	continuous: bool `gui:"true"`,
	// Particles live in the emitter's space and move, turn and scale with
	// it (an exhaust, an aura), or stay in the world where they were
	// emitted (smoke left behind). Local by default, also for scenes saved
	// before the option (#124).
	localSpace: bool `gui:"true"`,
	// Look (#126): the blend mode; the texture (shape Texture) as a sprite
	// sheet of columns x rows frames; particles turned to face where they
	// move (rain, sparks, arrows; rotation adds to it).
	blendMode: ParticleBlend `gui:"true"`,
	sheetColumns: int `gui:"true" min:"1" max:"64"`,
	sheetRows: int `gui:"true" min:"1" max:"64"`,
	frameMode: ParticleFrameMode `gui:"true"`,
	frameSpeed: f32 `gui:"true" min:"0" max:"60"`,
	alignToVelocity: bool `gui:"true"`,
	// The owner's global rotation (degrees) and scale, set each update:
	// emission follows them; local particles are drawn through them.
	originRotation: f32,
	originScale: [2]f32,
	start: proc(emitter: ^ParticleEmitter),
	stop: proc(emitter: ^ParticleEmitter),
	lifetimer: f32,
	// Ring buffer of particles, grown on demand to about twice `amount`
	// (allocated from `allocator`: the owning node's arena).
	particles: [dynamic]Particle,
	allocator: mem.Allocator,
	timer: f32,
	head: int,
	count: int,
	emittedInCycle: int,
	cycleStarted: bool,
	texture: ^rl.Texture2D,
	customShapeProc: proc(p: ^Particle, deltaTime: f32),
}

PARTICLE_MAX :: 20000

// ParticleEmitter_Reserve grows the particle ring to `n` slots (keeps the
// live particles).
ParticleEmitter_Reserve :: proc(emitter: ^ParticleEmitter, n: int) {
	if len(emitter.particles) >= n do return
	if emitter.particles == nil {
		alloc := emitter.allocator if emitter.allocator.procedure != nil else context.allocator
		emitter.particles = make([dynamic]Particle, n, n, alloc)
		return
	}
	resize(&emitter.particles, n)
}

// ParticleEmitter_Destroy frees the particles (only needed when the
// emitter isn't owned by a node, whose arena frees them).
ParticleEmitter_Destroy :: proc(emitter: ^ParticleEmitter) {
	if emitter.particles != nil && emitter.allocator.procedure == nil do delete(emitter.particles)
	emitter.particles = nil
}

ParticleEmitter_Start :: proc(emitter: ^ParticleEmitter) {
	emitter.emitting = true
	emitter.cycleStarted = false
	emitter.lifetimer = 0
	emitter.timer = 0
	emitter.emittedInCycle = 0
}

ParticleEmitter_Stop :: proc(emitter: ^ParticleEmitter) {
	emitter.emitting = false
	emitter.cycleStarted = false
}

ParticleEmitter_Init :: proc(emitter: ^ParticleEmitter) {
	emitter.amount = 1
	emitter.lifetime = 2
	emitter.burst = 0
	emitter.size = {5, 5}
	emitter.useColorRamp = true
	ColorRamp_Init(&emitter.colorRamp)
	emitter.particleColor = rl.WHITE
	emitter.colorEnd = rl.WHITE
	emitter.colorVariance = 0
	emitter.velocity = 100
	emitter.scaleStart = 1
	emitter.scaleEnd = 1
	emitter.velocityScale = 1
	emitter.gravityDirection = {0, 1}
	emitter.gravityVelocity = 200
	emitter.wind = {0, 0}
	emitter.collisionEnabled = false
	emitter.collisionMode = .Bounce
	emitter.collisionLayers = DEFAULT_COLLISION_MASK
	emitter.elasticity = 0.7
	emitter.friction = 0.1
	emitter.emitting = true
	emitter.continuous = true
	emitter.localSpace = true
	emitter.originScale = {1, 1}
	emitter.sheetColumns = 1
	emitter.sheetRows = 1
	emitter.frameSpeed = 12
	emitter.start = ParticleEmitter_Start
	emitter.stop = ParticleEmitter_Stop
	emitter.lifetimer = 0
	emitter.timer = 0
	emitter.head = 0
	emitter.count = 0
	emitter.emittedInCycle = 0
	emitter.cycleStarted = false
}


Particle :: struct {
	position: [2]f32,
	scaleStart: [2]f32,
	scaleEnd: [2]f32,
	scale: [2]f32,
	rotation: f32,
	torque: f32,
	torqueAcceleration: f32,
	velocity: [2]f32,
	acceleration: [2]f32,
	lifetime: f32,
	age: f32,
	agePercent: f32,
	size: [2]f32,
	colorStart: rl.Color,
	colorEnd: rl.Color,
	colorJitter: [3]f32,
	color: rl.Color,
	alive: bool,
	frameSeed: u32, // a random number per particle (its sheet frame: Random)
	shape: ParticleShape,
	texture: ^rl.Texture2D,
	customShapeProc: proc(p: ^Particle, deltaTime: f32),
}

// Particles use a fast generator seeded once from the OS (they need
// variety, not unpredictability; the OS generator cost per number).
@(private = "file")
particleRandom: struct {
	state:  rand.Default_Random_State,
	seeded: bool,
}

@(private = "file")
particle_rng :: proc() -> runtime.Random_Generator {
	if !particleRandom.seeded {
		seed: [8]u8
		crypto.rand_bytes(seed[:])
		particleRandom.state = rand.create((^u64)(&seed[0])^)
		particleRandom.seeded = true
	}
	return runtime.default_random_generator(&particleRandom.state)
}

@(private = "file")
safe_float32_range :: proc(a, b: f32) -> f32 {
	low := min(a, b)
	high := max(a, b)
	if low >= high do return low
	return rand.float32_range(low, high)
}

ParticleEmitter_Emit :: proc(emitter: ^ParticleEmitter) {
	context.random_generator = particle_rng()

	ParticleEmitter_Reserve(emitter, clamp(emitter.amount * 2 + 4, 16, PARTICLE_MAX))
	if len(emitter.particles) == 0 do return
	emitter.head %= len(emitter.particles)
	p := &emitter.particles[emitter.head]
	emitter.head = (emitter.head + 1) % len(emitter.particles)

	// Position: an offset in the emitter's space (the spread box). Local
	// particles keep it; world ones go through the owner's transform.
	spread_x := math.abs(emitter.spread[0])
	spread_y := math.abs(emitter.spread[1])
	offset := [2]f32{safe_float32_range(-spread_x, spread_x), safe_float32_range(-spread_y, spread_y)}
	p.position = offset if emitter.localSpace else particle_to_world(emitter, offset)
	p.shape = emitter.shape

	// Size
	sizeSpread := math.abs(emitter.sizeSpread * emitter.sizeVariance)
	p.size = {
		emitter.size[0] + safe_float32_range(-sizeSpread, sizeSpread),
		emitter.size[1] + safe_float32_range(-sizeSpread, sizeSpread),
	}

	// Scale
	p.scaleStart = emitter.scaleStart
	p.scaleEnd = emitter.scaleEnd

	// Rotation
	rotationSpread := math.abs(emitter.rotationSpread * emitter.rotationVariance)
	p.rotation = emitter.rotation + safe_float32_range(-rotationSpread, rotationSpread)

	// Angle (world particles: turned with the owner)
	baseSpread := math.abs(emitter.angleSpread * emitter.angleVariance)
	angle := emitter.angle + safe_float32_range(-baseSpread, baseSpread)
	if !emitter.localSpace {
		angle += emitter.originRotation
		p.rotation += emitter.originRotation
	}
	angle_rad := math.to_radians(angle)

	// Torque
	torqueSpread := math.abs(emitter.torqueSpread * emitter.torqueVariance)
	p.torque = emitter.torque + safe_float32_range(-torqueSpread, torqueSpread)
	p.torqueAcceleration = emitter.torqueAcceleration

	// Velocity
	velSpread := math.abs(emitter.velocitySpread * emitter.velocityVariance)
	velocity := emitter.velocity + safe_float32_range(-velSpread, velSpread)
	p.velocity = {math.cos(angle_rad) * velocity, math.sin(angle_rad) * velocity}

	// Texture (drawn with the emitter's: a particle doesn't keep a pointer
	// that a texture change would leave dangling)
	p.frameSeed = rand.uint32()

	p.acceleration = {math.cos(angle_rad) * emitter.acceleration, math.sin(angle_rad) * emitter.acceleration}
	if !emitter.localSpace {
		// (Sizes and speeds scaled with the owner; local ones when drawn.)
		sc := particle_scale(emitter)
		p.size *= {abs(sc.x), abs(sc.y)}
		uniform := (abs(sc.x) + abs(sc.y)) * 0.5
		p.velocity *= uniform
		p.acceleration *= uniform
	}
	p.lifetime = emitter.lifetime
	p.age = 0
	p.agePercent = 0

	// Color Jitter
	cVar := math.abs(emitter.colorVariance)
	if cVar > 0 {
		p.colorJitter = {
			safe_float32_range(-cVar, cVar) * 255,
			safe_float32_range(-cVar, cVar) * 255,
			safe_float32_range(-cVar, cVar) * 255,
		}
	} else {
		p.colorJitter = {0, 0, 0}
	}

	// Colors
	if emitter.useColorRamp {
		baseColor := ColorRamp_Evaluate(&emitter.colorRamp, 0.0)
		r := u8(math.clamp(f32(baseColor.r) + p.colorJitter.x, 0, 255))
		g := u8(math.clamp(f32(baseColor.g) + p.colorJitter.y, 0, 255))
		b := u8(math.clamp(f32(baseColor.b) + p.colorJitter.z, 0, 255))
		p.color = {r, g, b, baseColor.a}
	} else {
		startColor := emitter.particleColor
		endColor := emitter.colorEnd
		if emitter.colorVariance > 0 {
			startColor.r = u8(math.clamp(f32(startColor.r) + p.colorJitter.x, 0, 255))
			startColor.g = u8(math.clamp(f32(startColor.g) + p.colorJitter.y, 0, 255))
			startColor.b = u8(math.clamp(f32(startColor.b) + p.colorJitter.z, 0, 255))
			endColor.r = u8(math.clamp(f32(endColor.r) + p.colorJitter.x, 0, 255))
			endColor.g = u8(math.clamp(f32(endColor.g) + p.colorJitter.y, 0, 255))
			endColor.b = u8(math.clamp(f32(endColor.b) + p.colorJitter.z, 0, 255))
		}
		p.colorStart = startColor
		p.colorEnd = endColor
		p.color = startColor
	}

	p.alive = true
}

// --- the owner's transform (#124) ----------------------------------------------------

@(private = "file")
particle_scale :: proc(emitter: ^ParticleEmitter) -> [2]f32 {
	return emitter.originScale if emitter.originScale != {} else {1, 1}
}

@(private = "file")
particle_rotate :: proc(v: [2]f32, deg: f32) -> [2]f32 {
	if deg == 0 do return v
	r := math.to_radians(deg)
	c, s := math.cos(r), math.sin(r)
	return {v.x * c - v.y * s, v.x * s + v.y * c}
}

// particle_to_world: a point in the emitter's space -> the world.
particle_to_world :: proc(emitter: ^ParticleEmitter, local: [2]f32) -> [2]f32 {
	return emitter.position + particle_rotate(local * particle_scale(emitter), emitter.originRotation)
}

// particle_to_local: a world point -> the emitter's space.
particle_to_local :: proc(emitter: ^ParticleEmitter, world: [2]f32) -> [2]f32 {
	sc := particle_scale(emitter)
	v := particle_rotate(world - emitter.position, -emitter.originRotation)
	return {v.x / (sc.x if sc.x != 0 else 1), v.y / (sc.y if sc.y != 0 else 1)}
}

@(private = "file")
particle_dir_to_world :: proc(emitter: ^ParticleEmitter, v: [2]f32) -> [2]f32 {
	return particle_rotate(v * particle_scale(emitter), emitter.originRotation)
}

@(private = "file")
particle_dir_to_local :: proc(emitter: ^ParticleEmitter, v: [2]f32) -> [2]f32 {
	sc := particle_scale(emitter)
	w := particle_rotate(v, -emitter.originRotation)
	return {w.x / (sc.x if sc.x != 0 else 1), w.y / (sc.y if sc.y != 0 else 1)}
}

// particle_forces: gravity and wind (world directions) in the particles'
// space - for local particles, turned back and unscaled, so "down" stays
// down on screen whatever the owner's rotation.
@(private = "file")
particle_forces :: proc(emitter: ^ParticleEmitter) -> (gravity, wind: [2]f32) {
	grav_len_sq := emitter.gravityDirection.x * emitter.gravityDirection.x + emitter.gravityDirection.y * emitter.gravityDirection.y
	if grav_len_sq > 0.0001 do gravity = emitter.gravityDirection / math.sqrt(grav_len_sq) * emitter.gravityVelocity
	wind = emitter.wind
	if emitter.localSpace {
		gravity = particle_dir_to_local(emitter, gravity)
		wind = particle_dir_to_local(emitter, wind)
	}
	return
}

Particle_Update_Index :: proc(emitter: ^ParticleEmitter, index: int, deltaTime: f32) {
	p := &emitter.particles[index]
	if p.alive {
		gravity, wind := particle_forces(emitter)
		p.velocity += gravity * deltaTime
		p.velocity += wind * deltaTime

		p.velocity += p.acceleration * deltaTime
		p.torque += p.torqueAcceleration * deltaTime
		p.rotation += p.torque * deltaTime
		p.position += p.velocity * deltaTime * emitter.velocityScale
		p.age += deltaTime
		p.agePercent = math.clamp(p.age / p.lifetime, 0, 1)

		xScale := math.lerp(p.scaleStart[0], p.scaleEnd[0], p.agePercent)
		yScale := math.lerp(p.scaleStart[1], p.scaleEnd[1], p.agePercent)
		p.scale = {xScale, yScale}

		// Color update over lifespan
		if emitter.useColorRamp {
			baseColor := ColorRamp_Evaluate(&emitter.colorRamp, p.agePercent)
			r := u8(math.clamp(f32(baseColor.r) + p.colorJitter.x, 0, 255))
			g := u8(math.clamp(f32(baseColor.g) + p.colorJitter.y, 0, 255))
			b := u8(math.clamp(f32(baseColor.b) + p.colorJitter.z, 0, 255))
			p.color = {r, g, b, baseColor.a}
		} else {
			t := p.agePercent
			r := u8(math.clamp(math.lerp(f32(p.colorStart.r), f32(p.colorEnd.r), t), 0, 255))
			g := u8(math.clamp(math.lerp(f32(p.colorStart.g), f32(p.colorEnd.g), t), 0, 255))
			b := u8(math.clamp(math.lerp(f32(p.colorStart.b), f32(p.colorEnd.b), t), 0, 255))
			a := u8(math.clamp(math.lerp(f32(p.colorStart.a), f32(p.colorEnd.a), t), 0, 255))
			p.color = {r, g, b, a}
		}

		if p.age >= p.lifetime {
			p.alive = false
			p.agePercent = 1.0
		}
	}
}

Particle_Update_Particle :: proc(emitter: ^ParticleEmitter, particle: ^Particle, deltaTime: f32) {
	if particle.alive {
		gravity, wind := particle_forces(emitter)
		particle.velocity += gravity * deltaTime
		particle.velocity += wind * deltaTime

		particle.velocity += particle.acceleration * deltaTime
		particle.torque += particle.torqueAcceleration * deltaTime
		particle.rotation += particle.torque * deltaTime
		particle.position += particle.velocity * deltaTime * emitter.velocityScale
		particle.age += deltaTime
		particle.agePercent = math.clamp(particle.age / particle.lifetime, 0, 1)

		xScale := math.lerp(particle.scaleStart[0], particle.scaleEnd[0], particle.agePercent)
		yScale := math.lerp(particle.scaleStart[1], particle.scaleEnd[1], particle.agePercent)
		particle.scale = {xScale, yScale}

		// Color update over lifespan
		if emitter.useColorRamp {
			baseColor := ColorRamp_Evaluate(&emitter.colorRamp, particle.agePercent)
			r := u8(math.clamp(f32(baseColor.r) + particle.colorJitter.x, 0, 255))
			g := u8(math.clamp(f32(baseColor.g) + particle.colorJitter.y, 0, 255))
			b := u8(math.clamp(f32(baseColor.b) + particle.colorJitter.z, 0, 255))
			particle.color = {r, g, b, baseColor.a}
		} else {
			t := particle.agePercent
			r := u8(math.clamp(math.lerp(f32(particle.colorStart.r), f32(particle.colorEnd.r), t), 0, 255))
			g := u8(math.clamp(math.lerp(f32(particle.colorStart.g), f32(particle.colorEnd.g), t), 0, 255))
			b := u8(math.clamp(math.lerp(f32(particle.colorStart.b), f32(particle.colorEnd.b), t), 0, 255))
			a := u8(math.clamp(math.lerp(f32(particle.colorStart.a), f32(particle.colorEnd.a), t), 0, 255))
			particle.color = {r, g, b, a}
		}

		if particle.age >= particle.lifetime {
			particle.alive = false
			particle.agePercent = 1.0
		}
	}
}

Particle_Update :: proc{Particle_Update_Index, Particle_Update_Particle}

ParticleEmitter_DrawColorRampGui :: proc(emitter: ^ParticleEmitter, x: f32, nextY: ^f32, width: f32, selectedStop: ^int, draggingStop: ^bool, view: rl.Rectangle) {
	ramp := &emitter.colorRamp

	ui.GuiToggleSwitch({x, nextY^, width, 22}, "Enable Color Ramp (Gradient)", &emitter.useColorRamp)
	nextY^ += 26

	if !emitter.useColorRamp do return

	// Convert fixed stops array to dynamic array for GuiGradientEditor
	stopsDyn := make([dynamic]ui.ColorStop, context.temp_allocator)
	for i in 0..<ramp.count {
		append(&stopsDyn, ui.ColorStop{position = ramp.stops[i].position, color = ramp.stops[i].color})
	}

	gradRect := rl.Rectangle{x, nextY^, width, 120}
	changed := ui.GuiGradientEditor(gradRect, &stopsDyn, selectedStop, draggingStop, true)
	nextY^ += 130

	if changed {
		ramp.count = min(len(stopsDyn), MAX_COLOR_STOPS)
		for i in 0..<ramp.count {
			ramp.stops[i] = ColorStop{position = stopsDyn[i].position, color = stopsDyn[i].color}
		}
		ColorRamp_Sort(ramp, selectedStop)
	}

	// Selected Stop Controls (Color Picker, Alpha, Position, Add/Del)
	if selectedStop^ < 0 do selectedStop^ = 0
	if selectedStop^ >= ramp.count do selectedStop^ = ramp.count - 1

	ctrlY := nextY^
	DrawEngineText(fmt.ctprintf("Stop %d / %d", selectedStop^ + 1, ramp.count), x, ctrlY, 14, rl.WHITE)

	posVal := ramp.stops[selectedStop^].position
	sliderW := width - 180
	ui.GuiSlider({x + 70, ctrlY, sliderW, 18}, "", fmt.ctprintf("%.2f", posVal), &posVal, 0.0, 1.0)
	if posVal != ramp.stops[selectedStop^].position {
		ramp.stops[selectedStop^].position = posVal
		ColorRamp_Sort(ramp, selectedStop)
	}

	btnX := x + 70 + sliderW + 10
	if ramp.count < MAX_COLOR_STOPS {
		if ui.GuiButton({btnX, ctrlY, 40, 18}, "Add") {
			midT: f32 = 0.5
			idx := ColorRamp_AddStop(ramp, midT, ColorRamp_Evaluate(ramp, midT))
			if idx >= 0 do selectedStop^ = idx
		}
	}
	if ramp.count > 2 {
		if ui.GuiButton({btnX + 45, ctrlY, 40, 18}, "Del") {
			ColorRamp_RemoveStop(ramp, selectedStop^)
			if selectedStop^ >= ramp.count do selectedStop^ = ramp.count - 1
		}
	}

	ctrlY += 24
	c := &ramp.stops[selectedStop^].color
	alpha := f32(c.a) / 255.0
	pickerW := width - 70
	ui.GuiColorPicker({x + 70, ctrlY, pickerW, 55}, "Stop Color", c)
	ctrlY += 60
	ui.GuiColorBarAlpha({x + 70, ctrlY, pickerW, 18}, "Stop Alpha", &alpha)
	c.a = u8(math.round(alpha * 255.0))

	nextY^ = ctrlY + 26
}

// ParticleEmitter_Update emits and moves the particles; with collision on,
// they collide with `world`'s shapes (none: no collision).
ParticleEmitter_Update :: proc(emitter: ^ParticleEmitter, deltaTime: f32, world := b2.WorldId{}) {
	if emitter.emitting {
		targetAmount := max(emitter.amount, 0)
		cycleDuration := max(emitter.lifetime, 0.0001)
		burstVal := math.clamp(emitter.burst, 0.0, 1.0)
		emissionDuration := cycleDuration * (1.0 - burstVal)
		interval := emissionDuration / f32(targetAmount) if targetAmount > 0 else 0.0

		// Lifecycle start or loop (when continuous and lifetimer reaches lifetime)
		if !emitter.cycleStarted || (emitter.continuous && emitter.lifetimer >= emitter.lifetime) {
			emitter.lifetimer = 0
			emitter.timer = interval
			emitter.emittedInCycle = 0
			emitter.cycleStarted = true
		}

		emitter.lifetimer += deltaTime

		if emitter.emittedInCycle < targetAmount {
			if burstVal >= 1.0 || emissionDuration <= 0.0001 {
				for emitter.emittedInCycle < targetAmount {
					ParticleEmitter_Emit(emitter)
					emitter.emittedInCycle += 1
				}
			} else if interval > 0.00001 {
				emitter.timer += deltaTime
				for emitter.timer >= interval && emitter.emittedInCycle < targetAmount {
					ParticleEmitter_Emit(emitter)
					emitter.emittedInCycle += 1
					emitter.timer -= interval
				}
			}
		}
		emitter.count = emitter.emittedInCycle

		if !emitter.continuous && emitter.lifetimer >= emitter.lifetime {
			emitter.emitting = false
			emitter.cycleStarted = false
		}
	}

	collide := emitter.collisionEnabled && b2.World_IsValid(world)
	for i in 0..<len(emitter.particles) {
		if !emitter.particles[i].alive do continue
		prev := emitter.particles[i].position
		Particle_Update(emitter, i, deltaTime)
		if collide && emitter.particles[i].alive do particle_collide(emitter, &emitter.particles[i], prev, world)
	}
}

@(private = "file")
Particle_Ray_Hit :: struct {
	hit:      bool,
	point:    [2]f32,
	normal:   [2]f32,
	fraction: f32,
	shape:    b2.ShapeId,
}

// particle_ray_callback: the closest solid shape along the move (trigger
// areas - sensors - don't stop particles).
@(private = "file")
particle_ray_callback :: proc "c" (shapeId: b2.ShapeId, point: b2.Vec2, normal: b2.Vec2, fraction: f32, ctx: rawptr) -> f32 {
	if b2.Shape_IsSensor(shapeId) do return -1
	r := cast(^Particle_Ray_Hit)ctx
	r^ = {true, point, normal, fraction, shapeId}
	return fraction
}

// particle_collide: the particle moved from `prev`; if a solid shape was in
// the way, it bounces off it, stops on it or dies there (collisionMode).
// The whole move is cast, so fast particles don't pass through thin walls.
@(private = "file")
particle_collide :: proc(emitter: ^ParticleEmitter, p: ^Particle, prevIn: [2]f32, world: b2.WorldId) {
	// (Local particles: cast in the world, the result brought back.)
	prev, pos, vel := prevIn, p.position, p.velocity
	if emitter.localSpace {
		prev, pos, vel = particle_to_world(emitter, prevIn), particle_to_world(emitter, p.position), particle_dir_to_world(emitter, p.velocity)
	}
	defer if p.alive {
		p.position = particle_to_local(emitter, pos) if emitter.localSpace else pos
		p.velocity = particle_dir_to_local(emitter, vel) if emitter.localSpace else vel
	}
	move := pos - prev
	if move.x * move.x + move.y * move.y < 1e-6 do return
	hit: Particle_Ray_Hit
	filter := b2.QueryFilter{categoryBits = ~u64(0), maskBits = CollisionLayerSet_ToBits(emitter.collisionLayers)}
	_ = b2.World_CastRay(world, prev, move, filter, particle_ray_callback, &hit)
	if !hit.hit do return
	n := hit.normal
	switch emitter.collisionMode {
	case .Kill:
		p.alive = false
	case .Stop:
		pos = hit.point + n * 0.01
		vel = {}
		p.acceleration = {}
	case .Bounce:
		pos = hit.point + n * 0.01
		vn := vel.x * n.x + vel.y * n.y
		if vn < 0 {
			tangent := vel - n * vn
			vel = tangent * (1 - math.clamp(emitter.friction, 0, 1)) - n * vn * math.clamp(emitter.elasticity, 0, 1)
		}
	}
	hitNode: ^Node
	if body := b2.Shape_GetBody(hit.shape); b2.Body_IsValid(body) do hitNode = cast(^Node)b2.Body_GetUserData(body)
	emitter.lastHitPoint, emitter.lastHitNormal, emitter.lastHitNode = hit.point, n, hitNode
	if emitter.onHit != nil do emitter.onHit(emitter, hitNode, emitter.onHitUser)
}

// --- drawing (#125) --------------------------------------------------------------------
// Every live particle of an emitter is one textured quad written straight
// into rlgl's batch: circles and ellipses from a small anti-aliased circle
// texture, rectangles / pixels / lines from the default white texel,
// textured particles from their texture - one draw per texture, not a
// raylib call (and for circles a triangle fan) per particle. Written in
// chunks, each after making room in the batch (rlgl drops vertices past its
// buffer instead of flushing).

@(private = "file")
PARTICLE_CHUNK :: 1024

@(private = "file")
particleCircleTex: rl.Texture2D

// particle_circle_texture: a white disc, anti-aliased edge, alpha outside.
@(private = "file")
particle_circle_texture :: proc() -> u32 {
	if particleCircleTex.id != 0 do return particleCircleTex.id
	N :: 64
	img := rl.GenImageColor(N, N, rl.BLANK)
	defer rl.UnloadImage(img)
	r := f32(N) * 0.5
	for y in 0 ..< N do for x in 0 ..< N {
		d := math.sqrt((f32(x) + 0.5 - r) * (f32(x) + 0.5 - r) + (f32(y) + 0.5 - r) * (f32(y) + 0.5 - r))
		a := math.clamp(r - d, 0, 1)
		if a > 0 do rl.ImageDrawPixel(&img, i32(x), i32(y), {255, 255, 255, u8(a * 255)})
	}
	particleCircleTex = rl.LoadTextureFromImage(img)
	rl.SetTextureFilter(particleCircleTex, .BILINEAR)
	return particleCircleTex.id
}

// Particles_Shutdown frees the shared drawing texture (engine shutdown).
// The runner closes the window first: no GL context to free it in then
// (Mesa crashes on it) - it went with the context.
Particles_Shutdown :: proc() {
	if particleCircleTex.id != 0 && rl.IsWindowReady() do rl.UnloadTexture(particleCircleTex)
	particleCircleTex = {}
}

@(private = "file")
Particle_Batch :: struct {
	tex:  u32,
	n:    int,
	open: bool,
}

@(private = "file")
batch_use :: proc(b: ^Particle_Batch, tex: u32) {
	if b.open && b.tex == tex && b.n < PARTICLE_CHUNK do return
	batch_close(b)
	rlgl.CheckRenderBatchLimit(4 * PARTICLE_CHUNK)
	rlgl.SetTexture(tex)
	rlgl.Begin(rlgl.QUADS)
	b^ = {tex = tex, open = true}
}

@(private = "file")
batch_close :: proc(b: ^Particle_Batch) {
	if !b.open do return
	rlgl.End()
	rlgl.SetTexture(0)
	b.open = false
}

// batch_quad: a w x h quad centred on c, turned by rotDeg, the texture's
// uv rectangle (u0, v0) - (u1, v1) on it.
@(private = "file")
batch_quad :: proc(b: ^Particle_Batch, c: [2]f32, w, h, rotDeg: f32, col: rl.Color, uv := [4]f32{0, 0, 1, 1}) {
	hw, hh := w * 0.5, h * 0.5
	ax, ay := [2]f32{hw, 0}, [2]f32{0, hh}
	if rotDeg != 0 {
		r := math.to_radians(rotDeg)
		cs, sn := math.cos(r), math.sin(r)
		ax, ay = {hw * cs, hw * sn}, {-hh * sn, hh * cs}
	}
	tl, bl, br, tr := c - ax - ay, c - ax + ay, c + ax + ay, c + ax - ay
	rlgl.Color4ub(col.r, col.g, col.b, col.a)
	rlgl.TexCoord2f(uv[0], uv[1]); rlgl.Vertex2f(tl.x, tl.y)
	rlgl.TexCoord2f(uv[0], uv[3]); rlgl.Vertex2f(bl.x, bl.y)
	rlgl.TexCoord2f(uv[2], uv[3]); rlgl.Vertex2f(br.x, br.y)
	rlgl.TexCoord2f(uv[2], uv[1]); rlgl.Vertex2f(tr.x, tr.y)
	b.n += 1
}

// What a particle is drawn with.
Particle_Quad_Texture :: enum {
	None,    // not drawn (no texture) or drawn by its own proc (Custom)
	White,   // the default white texel
	Circle,  // the anti-aliased disc
	Texture, // its own texture
}

// Particle_Quad: one particle as drawn - a w x h quad centred on `center`,
// turned by `rotation` degrees, in world terms.
Particle_Quad :: struct {
	center:   [2]f32,
	size:     [2]f32,
	rotation: f32,
	color:    rl.Color,
	texture:  Particle_Quad_Texture,
	uv:       [4]f32, // u0, v0, u1, v1 (a sprite sheet's frame)
}

// particle_frame: the sheet frame a particle shows now (0-based).
Particle_Frame :: proc(emitter: ^ParticleEmitter, p: Particle) -> int {
	n := max(emitter.sheetColumns, 1) * max(emitter.sheetRows, 1)
	if n <= 1 do return 0
	switch emitter.frameMode {
	case .OverLifetime: return min(int(p.agePercent * f32(n)), n - 1)
	case .Speed:        return int(p.age * max(emitter.frameSpeed, 0)) %% n
	case .Random:       return int(p.frameSeed %% u32(n))
	}
	return 0
}

// Particle_QuadOf: how a live particle is drawn (local particles through
// the owner's transform, #124).
Particle_QuadOf :: proc(emitter: ^ParticleEmitter, particle: Particle) -> Particle_Quad {
	p := particle
	if emitter.alignToVelocity && (p.velocity.x != 0 || p.velocity.y != 0) {
		p.rotation = math.to_degrees(math.atan2(p.velocity.y, p.velocity.x)) + emitter.rotation
	}
	if emitter.localSpace {
		sc := particle_scale(emitter)
		p.position = particle_to_world(emitter, p.position)
		p.size *= {abs(sc.x), abs(sc.y)}
		p.rotation += emitter.originRotation
	}
	q := Particle_Quad{center = p.position, rotation = p.rotation, color = p.color, uv = {0, 0, 1, 1}}
	switch p.shape {
	case .Circle:
		d := 2 * p.size[0] * p.scale[0]
		q.size, q.rotation, q.texture = {d, d}, 0, .Circle
	case .Ellipse:
		q.size, q.rotation, q.texture = {2 * p.size[0] * p.scale[0], 2 * p.size[1] * p.scale[1]}, 0, .Circle
	case .Rectangle:
		q.size, q.texture = {p.size[0] * p.scale[0], p.size[1] * p.scale[1]}, .White
	case .Pixel:
		q.center, q.size, q.rotation, q.texture = p.position + 0.5, {1, 1}, 0, .White
	case .Line:
		q.size, q.texture = {p.size[0] * p.scale[0], max(p.scale[1], 0.01)}, .White
	case .Texture:
		q.size = {p.size[0] * p.scale[0], p.size[1] * p.scale[1]}
		q.texture = .Texture if emitter.texture != nil && emitter.texture.id != 0 else .None
		cols, rows := max(emitter.sheetColumns, 1), max(emitter.sheetRows, 1)
		if cols * rows > 1 {
			f := Particle_Frame(emitter, p)
			c, r := f32(f %% cols), f32(f / cols)
			q.uv = {c / f32(cols), r / f32(rows), (c + 1) / f32(cols), (r + 1) / f32(rows)}
		}
	case .Custom:
		q.texture = .None
	}
	return q
}

ParticleEmitter_Render :: proc(emitter: ^ParticleEmitter, deltaTime: f32 = 0) {
	white := rlgl.GetTextureIdDefault()
	circle := particle_circle_texture()
	b: Particle_Batch
	blend := emitter.blendMode != .Alpha
	if blend {
		switch emitter.blendMode {
		case .Alpha:
		case .Additive:      rl.BeginBlendMode(.ADDITIVE)
		case .Multiply:      rl.BeginBlendMode(.MULTIPLIED)
		case .Premultiplied: rl.BeginBlendMode(.ALPHA_PREMULTIPLY)
		}
	}
	defer if blend do rl.EndBlendMode()
	defer batch_close(&b) // (runs first: the quads go out in the blend mode)
	for i in 0..<len(emitter.particles) {
		if !emitter.particles[i].alive do continue
		p := &emitter.particles[i]
		q := Particle_QuadOf(emitter, p^)
		switch q.texture {
		case .White:   batch_use(&b, white)
		case .Circle:  batch_use(&b, circle)
		case .Texture: batch_use(&b, emitter.texture.id)
		case .None:
			// A Custom shape draws as it likes (the batch closed around it).
			if p.shape == .Custom && p.customShapeProc != nil {
				batch_close(&b)
				c := p^
				c.position, c.rotation = q.center, q.rotation
				p.customShapeProc(&c, deltaTime)
			}
			continue
		}
		batch_quad(&b, q.center, q.size.x, q.size.y, q.rotation, q.color, q.uv)
	}
}
