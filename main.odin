package main

import "core:time"
import "core:log"
import "core:fmt"
import rl "vendor:raylib"
import "asteroids"
import e "engine"

WINDOW_SIZE :[2]i32: {1280, 720}

DEFAULT_BULLET_VELOCITY : [2]f32 : {0, -500}

main :: proc() {

	logger := log.create_console_logger( .Info)
	context.logger = logger

	rl.SetTraceLogLevel(.WARNING)
	rl.InitWindow(WINDOW_SIZE[0], WINDOW_SIZE[1], "Plane Game")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	rl.InitAudioDevice()

	game := asteroids.CreateGame()
	defer game->terminate()
	game->setup()

	// Game loop
	for !rl.WindowShouldClose() {
		rl.BeginDrawing()
		rl.ClearBackground(rl.DARKGRAY)
		deltaTime := rl.GetFrameTime()
		game->run(deltaTime)

		particleEmitter.emitTimer += deltaTime
		if particleEmitter.emitTimer >= 1.0 / particleEmitter.rate {
			particleEmitter.emitTimer = 0
			p := &particleEmitter.particles[particleEmitter.head]
			particleEmitter.head = (particleEmitter.head + 1) % len(particleEmitter.particles)
			p.position = {f32(WINDOW_SIZE[0] / 2), f32(WINDOW_SIZE[1] / 2)}
			p.velocity = {math.cos(particleEmitter.) * particleEmitter.velocity, math.sin(0) * particleEmitter.velocity}
			p.lifetime = particleEmitter.lifetime
			p.size = particleEmitter.particleSize
			p.color = particleEmitter.particleColor
			p.alive = true


		// Stats
		stats := e.NodeManager_GetStats(game.sceneManager.currentScene.manager)
		rl.DrawText(fmt.ctprintf("Capacity: %d", stats.capacity), 20, 20, 20, rl.WHITE)
		rl.DrawText(fmt.ctprintf("Count: %d", stats.count), 20, 40, 20, rl.WHITE)
		rl.DrawText(fmt.ctprintf("Free: %d", stats.free), 20, 60, 20, rl.WHITE)
		rl.EndDrawing()
	}
}
