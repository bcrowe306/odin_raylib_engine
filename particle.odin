package main

import "base:runtime"
import "core:math/rand"
import "core:crypto"
import "core:math"
import "core:fmt"
import rl "vendor:raylib"

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
	amount: int `gui:"true" min:"1" max:"500"`,
	lifetime: f32 `gui:"true" min:".01" max:"5"`,
	position: [2]f32 `gui:"true" min:"0" max:"1280"`,
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
	useColorRamp: bool,
	colorRamp: ColorRamp,
	particleColor: rl.Color,
	colorEnd: rl.Color,
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
	particles: #soa[1000]Particle,
	timer: f32,
	head: int,
	count: int,
	emittedInCycle: int,
	cycleStarted: bool,
	texture: ^rl.Texture2D,
	customShapeProc: proc(p: ^Particle, deltaTime: f32),
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

ParticleEmitter_Emit :: proc(emitter: ^ParticleEmitter) {
	context.random_generator = crypto.random_generator()

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
		if !emitter.particles.alive[i] do continue

		scale_xi := emitter.particles.scale[i][0]
		r_i := (emitter.particles.size[i][0] * (scale_xi if scale_xi > 0 else 1.0)) * 0.5
		if r_i <= 0.01 do r_i = 1.0

		for j in (i + 1)..<count {
			if !emitter.particles.alive[j] do continue

			scale_xj := emitter.particles.scale[j][0]
			r_j := (emitter.particles.size[j][0] * (scale_xj if scale_xj > 0 else 1.0)) * 0.5
			if r_j <= 0.01 do r_j = 1.0

			min_dist := r_i + r_j
			delta := emitter.particles.position[j] - emitter.particles.position[i]
			dist_sq := delta.x * delta.x + delta.y * delta.y

			if dist_sq < min_dist * min_dist && dist_sq > 0.0001 {
				dist := math.sqrt(dist_sq)
				normal := delta / dist
				overlap := min_dist - dist

				// Separate particles to resolve penetration
				emitter.particles.position[i] -= normal * (overlap * 0.5)
				emitter.particles.position[j] += normal * (overlap * 0.5)

				// Elastic collision response
				rel_vel := emitter.particles.velocity[j] - emitter.particles.velocity[i]
				vel_along_normal := rel_vel.x * normal.x + rel_vel.y * normal.y

				if vel_along_normal < 0 {
					elasticity := emitter.elasticity
					impulse := -(1.0 + elasticity) * vel_along_normal * 0.5
					emitter.particles.velocity[i] -= normal * impulse
					emitter.particles.velocity[j] += normal * impulse
				}
			}
		}

		// Boundary collision (screen borders)
		if rl.IsWindowReady() {
			screen_w := f32(rl.GetScreenWidth())
			screen_h := f32(rl.GetScreenHeight())
			pos := &emitter.particles.position[i]
			vel := &emitter.particles.velocity[i]

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
	mousePos := rl.GetMousePosition()
	inView := rl.CheckCollisionPointRec(mousePos, view)

	rl.GuiCheckBox({x, nextY^, 16, 16}, "Enable Color Ramp (Gradient)", &emitter.useColorRamp)
	nextY^ += 22

	if !emitter.useColorRamp do return

	// 1. X/Y Gradient Plot (X is lifetime 0..1, Y is alpha/intensity 0..1)
	plotH: f32 = 80
	plotRect := rl.Rectangle{x, nextY^, width, plotH}
	rl.DrawRectangleRec(plotRect, rl.Color{20, 20, 25, 255})
	rl.DrawRectangleLinesEx(plotRect, 1, rl.Color{60, 60, 70, 255})

	// Grid lines
	for step in 1..<4 {
		gy := plotRect.y + f32(step) * (plotH / 4)
		rl.DrawLineEx({plotRect.x, gy}, {plotRect.x + plotRect.width, gy}, 1, rl.Color{35, 35, 45, 255})
		gx := plotRect.x + f32(step) * (width / 4)
		rl.DrawLineEx({gx, plotRect.y}, {gx, plotRect.y + plotH}, 1, rl.Color{35, 35, 45, 255})
	}
	DrawEngineText("Alpha 1.0", plotRect.x + 4, plotRect.y + 4, 10, rl.GRAY)
	DrawEngineText("0.0", plotRect.x + 4, plotRect.y + plotH - 12, 10, rl.GRAY)
	DrawEngineText("0% Lifetime", plotRect.x + 4, plotRect.y + plotH + 2, 10, rl.GRAY)
	DrawEngineText("100% Lifetime", plotRect.x + width - 75, plotRect.y + plotH + 2, 10, rl.GRAY)

	// Plot alpha & color curve across lifetime
	prevPt := rl.Vector2{plotRect.x, plotRect.y + plotH - (f32(ColorRamp_Evaluate(ramp, 0.0).a) / 255.0) * plotH}
	for px in 1..=i32(width) {
		t := f32(px) / width
		col := ColorRamp_Evaluate(ramp, t)
		currY := plotRect.y + plotH - (f32(col.a) / 255.0) * plotH
		currPt := rl.Vector2{plotRect.x + f32(px), currY}
		rl.DrawLineEx(prevPt, currPt, 2, col)
		prevPt = currPt
	}

	// Stop nodes on plot
	for i in 0..<ramp.count {
		stop := ramp.stops[i]
		sx := plotRect.x + stop.position * width
		sy := plotRect.y + plotH - (f32(stop.color.a) / 255.0) * plotH
		rl.DrawCircle(i32(sx), i32(sy), 4, stop.color)
		if i == selectedStop^ {
			rl.DrawCircleLines(i32(sx), i32(sy), 6, rl.GOLD)
		}
	}

	nextY^ += plotH + 16

	// 2. Continuous Gradient Bar
	barH: f32 = 22
	barRect := rl.Rectangle{x, nextY^, width, barH}

	// Draw checkered transparency background
	checkSize: f32 = 6
	for cy := barRect.y; cy < barRect.y + barH; cy += checkSize {
		for cx := barRect.x; cx < barRect.x + width; cx += checkSize {
            isWhite := (i32((cx - barRect.x) / checkSize) + i32((cy - barRect.y) / checkSize)) % 2 == 0
			checkCol := rl.Color{180, 180, 180, 255} if isWhite else rl.Color{130, 130, 130, 255}
			rl.DrawRectangleRec({cx, cy, math.min(checkSize, barRect.x + width - cx), math.min(checkSize, barRect.y + barH - cy)}, checkCol)
		}
	}

	// Draw gradient strip
	for px in 0..<i32(width) {
		t := f32(px) / width
		col := ColorRamp_Evaluate(ramp, t)
		rl.DrawLineV({x + f32(px), barRect.y}, {x + f32(px), barRect.y + barH}, col)
	}
	rl.DrawRectangleLinesEx(barRect, 1, rl.LIGHTGRAY)

	// Stop markers below gradient bar
	markerH: f32 = 14
	markerW: f32 = 10
	markerY := barRect.y + barH + 2

	// Check adding a stop by clicking on the gradient bar
	if inView && rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(mousePos, barRect) {
		clickedStop := false
		for i in 0..<ramp.count {
			mx := barRect.x + ramp.stops[i].position * width
			if math.abs(mousePos.x - mx) <= (markerW * 0.75) {
				clickedStop = true
				selectedStop^ = i
				draggingStop^ = true
				break
			}
		}
		if !clickedStop {
			newT := math.clamp((mousePos.x - barRect.x) / width, 0.0, 1.0)
			newCol := ColorRamp_Evaluate(ramp, newT)
			idx := ColorRamp_AddStop(ramp, newT, newCol)
			if idx >= 0 {
				selectedStop^ = idx
				draggingStop^ = true
			}
		}
	}

	// Check clicking on marker handles
	if inView && rl.IsMouseButtonPressed(.LEFT) && !draggingStop^ {
		for i in 0..<ramp.count {
			mx := barRect.x + ramp.stops[i].position * width
			mRect := rl.Rectangle{mx - markerW/2, markerY, markerW, markerH + 4}
			if rl.CheckCollisionPointRec(mousePos, mRect) {
				selectedStop^ = i
				draggingStop^ = true
				break
			}
		}
	}

	// Dragging stop marker
	if draggingStop^ {
		if rl.IsMouseButtonDown(.LEFT) {
			newPos := math.clamp((mousePos.x - barRect.x) / width, 0.0, 1.0)
			ramp.stops[selectedStop^].position = newPos
			ColorRamp_Sort(ramp, selectedStop)
		} else {
			draggingStop^ = false
		}
	}

	// Draw stop markers
	for i in 0..<ramp.count {
		stop := ramp.stops[i]
		mx := barRect.x + stop.position * width

		// Triangle arrow pointing up
		p1 := rl.Vector2{mx, markerY}
		p2 := rl.Vector2{mx - markerW/2, markerY + 5}
		p3 := rl.Vector2{mx + markerW/2, markerY + 5}
		rl.DrawTriangle(p1, p2, p3, rl.WHITE)

		// Color box
		cRect := rl.Rectangle{mx - markerW/2, markerY + 5, markerW, markerH - 5}
		rl.DrawRectangleRec(cRect, stop.color)
		if i == selectedStop^ {
			rl.DrawRectangleLinesEx({cRect.x - 1, cRect.y - 1, cRect.width + 2, cRect.height + 2}, 2, rl.GOLD)
		} else {
			rl.DrawRectangleLinesEx(cRect, 1, rl.BLACK)
		}
	}

	nextY^ += barH + markerH + 10

	// 3. Selected Stop Controls (Color Picker, Position, Add/Delete)
	if selectedStop^ < 0 do selectedStop^ = 0
	if selectedStop^ >= ramp.count do selectedStop^ = ramp.count - 1

	ctrlY := nextY^
	DrawEngineText(fmt.ctprintf("Stop %d / %d", selectedStop^ + 1, ramp.count), x, ctrlY, 16, rl.WHITE)

	// Position slider
	posVal := ramp.stops[selectedStop^].position
	sliderW := width - 180
	rl.GuiSlider({x + 70, ctrlY, sliderW, 18}, "Position", fmt.ctprintf("%.2f", posVal), &posVal, 0.0, 1.0)
	if posVal != ramp.stops[selectedStop^].position {
		ramp.stops[selectedStop^].position = posVal
		ColorRamp_Sort(ramp, selectedStop)
	}

	// Add / Delete buttons
	btnX := x + 70 + sliderW + 10
	if ramp.count < MAX_COLOR_STOPS {
		if rl.GuiButton({btnX, ctrlY, 40, 18}, "Add") {
			midT: f32 = 0.5
			idx := ColorRamp_AddStop(ramp, midT, ColorRamp_Evaluate(ramp, midT))
			if idx >= 0 do selectedStop^ = idx
		}
	}
	if ramp.count > 2 {
		if rl.GuiButton({btnX + 45, ctrlY, 40, 18}, "Del") {
			ColorRamp_RemoveStop(ramp, selectedStop^)
			if selectedStop^ >= ramp.count do selectedStop^ = ramp.count - 1
		}
	}

	ctrlY += 24
	// Color Picker & Alpha
	c := &ramp.stops[selectedStop^].color
	alpha := f32(c.a) / 255.0
	pickerW := width - 70
	rl.GuiColorPicker({x + 70, ctrlY, pickerW, 55}, "Stop Color", c)
	ctrlY += 60
	rl.GuiColorBarAlpha({x + 70, ctrlY, pickerW, 18}, "Alpha", &alpha)
	c.a = u8(alpha * 255.0)
	ctrlY += 24

	nextY^ = ctrlY
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
			// Pre-fill timer to interval so the first particle is emitted at the very beginning of the cycle
			emitter.timer = interval
			emitter.emittedInCycle = 0
			emitter.cycleStarted = true
		}

		emitter.lifetimer += deltaTime

		if emitter.emittedInCycle < targetAmount {
			if burstVal >= 1.0 || emissionDuration <= 0.0001 {
				// Full burst (1.0): all particles are emitted at the same time
				for emitter.emittedInCycle < targetAmount {
					ParticleEmitter_Emit(emitter)
					emitter.emittedInCycle += 1
				}
			} else if interval > 0.00001 {
				// Burst < 1.0: particles are emitted across emissionDuration
				emitter.timer += deltaTime
				for emitter.timer >= interval && emitter.emittedInCycle < targetAmount {
					ParticleEmitter_Emit(emitter)
					emitter.emittedInCycle += 1
					emitter.timer -= interval
				}
			}
		}
		emitter.count = emitter.emittedInCycle

		// Check if non-continuous emitter has completed its single lifecycle
		if !emitter.continuous && emitter.lifetimer >= emitter.lifetime {
			emitter.emitting = false
			emitter.cycleStarted = false
		}
	}

	// Update all active particles in flight regardless of emission state
	for i in 0..<len(emitter.particles) {
		if !emitter.particles.alive[i] do continue
		Particle_Update(emitter, i, deltaTime)
	}

	if emitter.collisionEnabled {
		ParticleEmitter_HandleCollisions(emitter)
	}
}

ParticleEmitter_Render :: proc(emitter: ^ParticleEmitter, deltaTime: f32 = 0) {
	for i in 0..<len(emitter.particles) {
		if !emitter.particles.alive[i] do continue
		p := emitter.particles[i]
		switch p.shape {
			case ParticleShape.Circle:
				rl.DrawCircleV(p.position, p.size[0] * p.scale[0], p.color)
			case .Rectangle:
				w := p.size[0] * p.scale[0]
				h := p.size[1] * p.scale[1]
				rl.DrawRectangleV(p.position, {w, h}, p.color)
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
					p_copy := p
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
