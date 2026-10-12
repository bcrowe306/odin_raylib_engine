package main

import "core:odin/tokenizer"
import "core:slice"
import "core:strings"
import "core:math/ease"
import "core:strconv"
import "base:runtime"
import "core:reflect"
import "core:math/rand"
import "core:crypto"
import "core:math"
import "core:flags/example"
import "core:time"
import "core:log"
import "core:fmt"
import rl "vendor:raylib"
import "asteroids"
import e "engine"

WINDOW_SIZE :[2]i32: {1280, 720}

DEFAULT_BULLET_VELOCITY : [2]f32 : {0, -500}

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
	size: f32 `gui:"true" min:".01" max:"100"`,
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
	particleColor: rl.Color `gui:"true"`,
	spread: [2]f32 `gui:"true" min:"0" max:"1280"`,
	velocity: f32 `gui:"true" min:"0" max:"2000"`,
	velocityVariance: f32 `gui:"true" min:"0" max:"1"`, // 0-1
	velocitySpread: f32 `gui:"true" min:"0" max:"2000"`,
	velocityScale: f32 `gui:"true" min:"0" max:"10"`,
	acceleration: f32 `gui:"true" min:"-2000" max:"2000"`,
	angle: f32 `gui:"true" min:"0" max:"359"`,
	angleVariance: f32 `gui:"true" min:"0" max:"1"`, // 0-1
	angleSpread: f32 `gui:"true" min:"0" max:"360"`,
	shape: ParticleShape `gui:"true" min:"0" max:"2000"`,
	lifetimer: f32,
	particles: [1000]Particle,
	timer: f32,
	head: int,
	count: int,
	texture: ^rl.Texture2D,
	customShapeProc: proc(p: ^Particle, deltaTime: f32),
}

ParticleEmitter_Init :: proc(emitter: ^ParticleEmitter) {
	emitter.amount = 1
	emitter.lifetime = 2
	emitter.size = 5
	emitter.particleColor = rl.WHITE
	emitter.velocity = 100
	emitter.scaleStart = 1
	emitter.scaleEnd = 1
	emitter.velocityScale = 1
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
	size: f32,
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
	p.size = emitter.size + rand.float32_range(-sizeSpread, sizeSpread)

	// Scale
	p.scaleStart = emitter.scaleStart
	p.scaleEnd = emitter.scaleEnd

	// Rotation
	rotationSpread := emitter.rotationSpread * emitter.rotationVariance
	p.rotation = emitter.rotation + rand.float32_range(-rotationSpread, rotationSpread)

	// Angle
	spread := emitter.angleSpread * emitter.angleVariance
	angle := emitter.angle + rand.float32_range(-spread, spread)
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
	p.color = emitter.particleColor
	p.alive = true
}

Particle_Update :: proc(emitter: ^ParticleEmitter, particle: ^Particle, deltaTime: f32) {
	if particle.alive {
		particle.velocity += particle.acceleration * deltaTime
		particle.torque += particle.torqueAcceleration * deltaTime
		particle.rotation += particle.torque * deltaTime
		particle.position += particle.velocity * deltaTime * emitter.velocityScale
		particle.age += deltaTime
		particle.agePercent = particle.age / particle.lifetime
		xScale := math.lerp(particle.scaleStart[0], particle.scaleEnd[0], particle.agePercent)
		yScale := math.lerp(particle.scaleStart[1], particle.scaleEnd[1], particle.agePercent)
		particle.scale = {xScale, yScale}
		if particle.age >= particle.lifetime {
			particle.alive = false
			particle.agePercent = 1.0
		}
	}
}

ParticleEmitter_Update :: proc(emitter: ^ParticleEmitter, deltaTime: f32) {
	// how many particles should i emit this frame based on the amount and deltaTime and lifetime
	emitter.timer += deltaTime
	emitter.lifetimer += deltaTime
	rate := 1 / f32(emitter.amount) * (emitter.lifetime * (1 - emitter.burst))
	if emitter.timer >= rate {
		emitter.timer = 0
		if emitter.count <= emitter.amount {
			ParticleEmitter_Emit(emitter)
			emitter.count += 1
		}
	}


	if emitter.lifetimer >= emitter.lifetime {
		emitter.lifetimer = 0
		emitter.count = 0
	}

	for &p in emitter.particles {
		Particle_Update(emitter, &p, deltaTime)
		if p.alive {
			switch p.shape {
				case ParticleShape.Circle:
					rl.DrawCircleV(p.position, p.size * p.scale[0], p.color)
				case .Rectangle:
					rl.DrawRectangleV(p.position, p.scale, p.color)
					rl.DrawRectanglePro({p.position[0], p.position[1], p.size * p.scale[0], p.size * p.scale[1]}, {p.size * p.scale[0] / 2, p.size * p.scale[1] / 2}, p.rotation, p.color)
				case .Ellipse:
					rl.DrawEllipse(i32(p.position[0]), i32(p.position[1]), p.size * p.scale[0], p.size * p.scale[1], p.color)
				case .Pixel:
					rl.DrawPixelV(p.position, p.color)
				case .Line:
					// calculate line points from position size scale and rotation

					xStart := p.position[0] - (p.size * p.scale[0] / 2) * math.cos(math.to_radians(p.rotation))
					yStart := p.position[1] - (p.size * p.scale[1]/ 2) * math.sin(math.to_radians(p.rotation))
					xEnd := p.position[0] + (p.size * p.scale[0] / 2) * math.cos(math.to_radians(p.rotation))
					yEnd := p.position[1] + (p.size * p.scale[1] / 2) * math.sin(math.to_radians(p.rotation))
					rl.DrawLineEx({xStart, yStart}, {xEnd, yEnd}, 1 * p.scale[1], p.color)
				case .Custom:
					if p.customShapeProc != nil {
						p.customShapeProc(&p, deltaTime)
					}
				case .Texture:
					if p.texture != nil {
						rl.DrawTexturePro(
							p.texture^,
							{0, 0, f32(p.texture^.width), f32(p.texture^.height)},
							{p.position[0], p.position[1], p.size * p.scale[0], p.size * p.scale[1]},
							{p.size * p.scale[0] / 2, p.size * p.scale[1] / 2},
							p.rotation,
							p.color
						)
					}
			}
		}
	}
}
dropdownEdit: bool

main :: proc() {

	logger := log.create_console_logger( .Info)
	context.logger = logger

	rl.SetTraceLogLevel(.WARNING)
	rl.InitWindow(WINDOW_SIZE[0], WINDOW_SIZE[1], "Plane Game")
	defer rl.CloseWindow()
	// rl.SetTargetFPS(120)

	rl.InitAudioDevice()

	game := asteroids.CreateGame()
	defer game->terminate()
	game->setup()

	emitter := ParticleEmitter {
		amount = 1,
		lifetime = 2,
		position = {f32(WINDOW_SIZE[0] / 2), f32(WINDOW_SIZE[1] / 2)},
	}
	ParticleEmitter_Init(&emitter)
	ast := rl.LoadTexture("assets/graphics/Space Pack/Asteroids/Asteroid_1.png")
	emitter.texture = &ast

	// Game loop
	for !rl.WindowShouldClose() {
		rl.BeginDrawing()
		rl.ClearBackground(game.backgroundColor)
		deltaTime := rl.GetFrameTime()
		game->run(deltaTime)

		ParticleEmitter_Update(&emitter, deltaTime)


		xWindow: f32 = 5
		yWindow: f32 = 0
		width:f32 = 250
		height:f32 = 20
		am : f32 = f32(emitter.amount)

		nextY :f32 = yWindow
		yPadding :f32 = 2
		xPadding: f32 = 2
		sliderHeight :f32= 16
		x :f32= xWindow + xPadding + 100
		nextY += xWindow
		for i in 0..<reflect.struct_field_count(ParticleEmitter, .Top_Level) {
			field := reflect.struct_field_at(ParticleEmitter, i)
			if reflect.struct_tag_get(field.tag, "gui") == "" {
				continue
			}
			minStr := reflect.struct_tag_get(field.tag, "min")
			maxStr := reflect.struct_tag_get(field.tag, "max")
			fieldPtr := uintptr(&emitter) + field.offset

			#partial switch v in field.type.variant {
			case runtime.Type_Info_Float:

				valuef := cast(^f32)fieldPtr
				minf:f32 = 0
				maxf:f32 = 1

				if minStr != "" {
					if m, ok := strconv.parse_f32(minStr); ok {
						minf = m
					}
				}
				if maxStr != "" {
					if m, ok := strconv.parse_f32(maxStr); ok {
						maxf = m
					}
				}
				rl.GuiSlider({x, f32(nextY), width, sliderHeight}, fmt.ctprint(field.name), fmt.ctprint(valuef^), valuef, minf, maxf)
				nextY += sliderHeight + yPadding

			case runtime.Type_Info_Integer:
				valueI := cast(^int)fieldPtr
				valueFloat := cast(f32)valueI^
				min:int = 0
				max:int = 100

				if minStr != "" {
					if m, ok := strconv.parse_int(minStr); ok {
						min = m
					}
				}
				if maxStr != "" {
					if m, ok := strconv.parse_int(maxStr); ok {
						max = m
					}
				}
				rl.GuiSlider({x, nextY, width, sliderHeight}, fmt.ctprint(field.name), fmt.ctprint(valueI^), &valueFloat, f32(min), f32(max))
				valueI^ = int(valueFloat)
				nextY += sliderHeight + yPadding

			case runtime.Type_Info_Array:
				for i in 0..<v.count {
					elemPtr := uintptr(&emitter) + field.offset + uintptr(i) * uintptr(v.elem_size)
					#partial switch var in v.elem.variant {
					case runtime.Type_Info_Float:
						valuef := cast(^f32)elemPtr
						minf:f32 = 0
						maxf:f32 = 1

						if minStr != "" {
							if m, ok := strconv.parse_f32(minStr); ok {
								minf = m
							}
						}
						if maxStr != "" {
							if m, ok := strconv.parse_f32(maxStr); ok {
								maxf = m
							}
						}
						rl.GuiSlider({x, f32(nextY), width, sliderHeight}, fmt.ctprint(field.name, "[", i, "]"), fmt.ctprint(valuef^), valuef, minf, maxf)
						nextY += sliderHeight + yPadding
					}
				}
			case runtime.Type_Info_Named:
				base_info := reflect.type_info_base(v.base)
				#partial switch vv in base_info.variant {
					case runtime.Type_Info_Enum:
						valueI := cast(^int)fieldPtr
						active:i32 = i32(valueI^)

						if rl.GuiDropdownBox({x, nextY, width, sliderHeight}, fmt.ctprint(strings.join(vv.names, ";")), &active, dropdownEdit) {
							dropdownEdit = !dropdownEdit
						}
						valueI^ = int(active)
						nextY += sliderHeight + yPadding
					case runtime.Type_Info_Array:
						if field.type.id == rl.Color{
							c := cast(^rl.Color)fieldPtr
							alpha := f32(c^.a) / 255.0
							colorBoxHeight :f32 = 50
							rl.GuiColorPicker({x, nextY, width, colorBoxHeight}, "Color", c)
							nextY += colorBoxHeight + yPadding
							rl.GuiColorBarAlpha({x, nextY, width, sliderHeight}, "Alpha", &alpha)
							c.a = u8(alpha * 255.0)
							nextY += sliderHeight + yPadding
						}
				}
			}

		}

		// Stats
		// stats := e.NodeManager_GetStats(game.sceneManager.currentScene.manager)
		// rl.DrawText(fmt.ctprintf("Capacity: %d", stats.capacity), 20, 20, 20, rl.WHITE)
		// rl.DrawText(fmt.ctprintf("Count: %d", stats.count), 20, 40, 20, rl.WHITE)
		// rl.DrawText(fmt.ctprintf("Free: %d", stats.free), 20, 60, 20, rl.WHITE)
		rl.EndDrawing()
	}
}
