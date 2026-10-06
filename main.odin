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



		// Stats
		stats := e.NodeManager_GetStats(game.sceneManager.currentScene.manager)
		rl.DrawText(fmt.ctprintf("Capacity: %d", stats.capacity), 20, 20, 20, rl.WHITE)
		rl.DrawText(fmt.ctprintf("Count: %d", stats.count), 20, 40, 20, rl.WHITE)
		rl.DrawText(fmt.ctprintf("Free: %d", stats.free), 20, 60, 20, rl.WHITE)
		rl.EndDrawing()
	}
}
