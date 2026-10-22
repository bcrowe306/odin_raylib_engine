package engine

import "base:runtime"
import "core:mem"

import "core:math/rand"
import "core:crypto"
import "core:math"
import "core:fmt"
import rl "vendor:raylib"
import ui "../ui"

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
	collisionEnabled: bool `gui:"true"`,
	elasticity: f32 `gui:"true" min:"0" max:"1"`,
	shape: ParticleShape `gui:"true" min:"0" max:"2000"`,
	emitting: bool `gui:"true"`,
	continuous: bool `gui:"true"`,
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
	emitter.elasticity = 0.7
	emitter.emitting = true
	emitter.continuous = true
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

ParticleEmitter_Emit :: proc(emitter: ^ParticleEmitter) {
	context.random_generator = particle_rng()

	ParticleEmitter_Reserve(emitter, clamp(emitter.amount * 2 + 4, 16, PARTICLE_MAX))
	if len(emitter.particles) == 0 do return
	emitter.head %= len(emitter.particles)
	p := &emitter.particles[emitter.head]
	emitter.head = (emitter.head + 1) % len(emitter.particles)

	// Position
	xpos := rand.float32_range(emitter.position[0] - emitter.spread[0], emitter.position[0] + emitter.spread[0])
	ypos := rand.float32_range(emitter.position[1] - emitter.spread[1], emitter.position[1] + emitter.spread[1])
	p.position = {xpos, ypos}
	p.shape = emitter.shape

	// Size
	sizeSpread := emitter.sizeSpread * emitter.sizeVariance
	p.size = {
		emitter.size[0] + rand.float32_range(-sizeSpread, sizeSpread),
		emitter.size[1] + rand.float32_range(-sizeSpread, sizeSpread),
	}

	// Scale
	p.scaleStart = emitter.scaleStart
	p.scaleEnd = emitter.scaleEnd

	// Rotation
	rotationSpread := emitter.rotationSpread * emitter.rotationVariance
	p.rotation = emitter.rotation + rand.float32_range(-rotationSpread, rotationSpread)

	// Angle
	baseSpread := emitter.angleSpread * emitter.angleVariance
	angle := emitter.angle + rand.float32_range(-baseSpread, baseSpread)
	angle_rad := math.to_radians(angle)

	// Torque
	torqueSpread := emitter.torqueSpread * emitter.torqueVariance
	p.torque = emitter.torque + rand.float32_range(-torqueSpread, torqueSpread)
	p.torqueAcceleration = emitter.torqueAcceleration

	// Velocity
	velSpread := emitter.velocitySpread * emitter.velocityVariance
	velocity := emitter.velocity + rand.float32_range(-velSpread, velSpread)
	p.velocity = {math.cos(angle_rad) * velocity, math.sin(angle_rad) * velocity}

	// Texture
	p.texture = emitter.texture

	p.acceleration = {math.cos(angle_rad) * emitter.acceleration, math.sin(angle_rad) * emitter.acceleration}
	p.lifetime = emitter.lifetime
	p.age = 0
	p.agePercent = 0

	// Color Jitter
	if emitter.colorVariance > 0 {
		p.colorJitter = {
			rand.float32_range(-emitter.colorVariance, emitter.colorVariance) * 255,
			rand.float32_range(-emitter.colorVariance, emitter.colorVariance) * 255,
			rand.float32_range(-emitter.colorVariance, emitter.colorVariance) * 255,
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

Particle_Update_Index :: proc(emitter: ^ParticleEmitter, index: int, deltaTime: f32) {
	p := &emitter.particles[index]
	if p.alive {
		// Gravity
		grav_len_sq := emitter.gravityDirection.x * emitter.gravityDirection.x + emitter.gravityDirection.y * emitter.gravityDirection.y
		if grav_len_sq > 0.0001 {
			grav_dir := emitter.gravityDirection / math.sqrt(grav_len_sq)
			p.velocity += grav_dir * emitter.gravityVelocity * deltaTime
		}

		// Wind
		p.velocity += emitter.wind * deltaTime

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
		// Gravity
		grav_len_sq := emitter.gravityDirection.x * emitter.gravityDirection.x + emitter.gravityDirection.y * emitter.gravityDirection.y
		if grav_len_sq > 0.0001 {
			grav_dir := emitter.gravityDirection / math.sqrt(grav_len_sq)
			particle.velocity += grav_dir * emitter.gravityVelocity * deltaTime
		}

		// Wind
		particle.velocity += emitter.wind * deltaTime

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

ParticleEmitter_HandleCollisions :: proc(emitter: ^ParticleEmitter) {
	count := len(emitter.particles)

	// Particle vs Particle collision (fast point/size circle-circle using 1st dimension index)
	for i in 0..<count {
		if !emitter.particles[i].alive do continue

		scale_xi := emitter.particles[i].scale[0]
		r_i := (emitter.particles[i].size[0] * (scale_xi if scale_xi > 0 else 1.0)) * 0.5
		if r_i <= 0.01 do r_i = 1.0

		for j in (i + 1)..<count {
			if !emitter.particles[j].alive do continue

			scale_xj := emitter.particles[j].scale[0]
			r_j := (emitter.particles[j].size[0] * (scale_xj if scale_xj > 0 else 1.0)) * 0.5
			if r_j <= 0.01 do r_j = 1.0

			min_dist := r_i + r_j
			delta := emitter.particles[j].position - emitter.particles[i].position
			dist_sq := delta.x * delta.x + delta.y * delta.y

			if dist_sq < min_dist * min_dist && dist_sq > 0.0001 {
				dist := math.sqrt(dist_sq)
				normal := delta / dist
				overlap := min_dist - dist

				// Separate particles to resolve penetration
				emitter.particles[i].position -= normal * (overlap * 0.5)
				emitter.particles[j].position += normal * (overlap * 0.5)

				// Elastic collision response
				rel_vel := emitter.particles[j].velocity - emitter.particles[i].velocity
				vel_along_normal := rel_vel.x * normal.x + rel_vel.y * normal.y

				if vel_along_normal < 0 {
					elasticity := emitter.elasticity
					impulse := -(1.0 + elasticity) * vel_along_normal * 0.5
					emitter.particles[i].velocity -= normal * impulse
					emitter.particles[j].velocity += normal * impulse
				}
			}
		}

		// Boundary collision (screen borders)
		if rl.IsWindowReady() {
			screen_w := f32(rl.GetScreenWidth())
			screen_h := f32(rl.GetScreenHeight())
			pos := &emitter.particles[i].position
			vel := &emitter.particles[i].velocity

			if pos.x - r_i < 0 {
				pos.x = r_i
				vel.x = -vel.x * emitter.elasticity
			} else if pos.x + r_i > screen_w {
				pos.x = screen_w - r_i
				vel.x = -vel.x * emitter.elasticity
			}

			if pos.y - r_i < 0 {
				pos.y = r_i
				vel.y = -vel.y * emitter.elasticity
			} else if pos.y + r_i > screen_h {
				pos.y = screen_h - r_i
				vel.y = -vel.y * emitter.elasticity
			}
		}
	}
}

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

ParticleEmitter_Update :: proc(emitter: ^ParticleEmitter, deltaTime: f32) {
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

	for i in 0..<len(emitter.particles) {
		if !emitter.particles[i].alive do continue
		Particle_Update(emitter, i, deltaTime)
	}

	if emitter.collisionEnabled {
		ParticleEmitter_HandleCollisions(emitter)
	}
}

ParticleEmitter_Render :: proc(emitter: ^ParticleEmitter, deltaTime: f32 = 0) {
	for i in 0..<len(emitter.particles) {
		if !emitter.particles[i].alive do continue
		p := &emitter.particles[i]
		switch p.shape {
			case ParticleShape.Circle:
				// Segments from the radius (0.5 px error): small particles
				// need ~8 triangles, not DrawCircleV's fixed 36.
				rl.DrawCircleSector(p.position, p.size[0] * p.scale[0], 0, 360, 0, p.color)
			case .Rectangle:
				w := p.size[0] * p.scale[0]
				h := p.size[1] * p.scale[1]
				rl.DrawRectanglePro({p.position[0], p.position[1], w, h}, {w / 2, h / 2}, p.rotation, p.color)
			case .Ellipse:
				rl.DrawEllipse(i32(p.position[0]), i32(p.position[1]), p.size[0] * p.scale[0], p.size[1] * p.scale[1], p.color)
			case .Pixel:
				rl.DrawPixelV(p.position, p.color)
			case .Line:
				// calculate line points from position size scale and rotation
				halfLen := (p.size[0] * p.scale[0]) / 2
				rad := math.to_radians(p.rotation)
				xStart := p.position[0] - halfLen * math.cos(rad)
				yStart := p.position[1] - halfLen * math.sin(rad)
				xEnd := p.position[0] + halfLen * math.cos(rad)
				yEnd := p.position[1] + halfLen * math.sin(rad)
				rl.DrawLineEx({xStart, yStart}, {xEnd, yEnd}, 1 * p.scale[1], p.color)
			case .Custom:
				if p.customShapeProc != nil {
					p_copy := p^
					p.customShapeProc(&p_copy, deltaTime)
				}
			case .Texture:
				if p.texture != nil {
					w := p.size[0] * p.scale[0]
					h := p.size[1] * p.scale[1]
					rl.DrawTexturePro(
						p.texture^,
						{0, 0, f32(p.texture^.width), f32(p.texture^.height)},
						{p.position[0], p.position[1], w, h},
						{w / 2, h / 2},
						p.rotation,
						p.color,
					)
				}
		}
	}
}
