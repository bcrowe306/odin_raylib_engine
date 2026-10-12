package engine

import vmem "core:mem/virtual"
import "core:fmt"
import "core:log"
import rl "vendor:raylib"

GameState :: enum {
	None,
	Initialized,
	Ready,
	Running,
	Paused,
}

GameContext :: struct {
	game: ^Game,
	sceneManager: ^SceneManager,
	scene: ^Scene,
}


Game :: struct {
	arena: vmem.Arena,
	state:      GameState,
	sceneManager: SceneManager,
	backgroundColor: rl.Color,
	resourceManager: ResourceManager,
	gameContext: GameContext,
	drawBounds: bool,
	setup:      proc(game: ^Game),
	run:        proc(game: ^Game, deltaTime: f32),
	update:     proc(game: ^Game, scene: ^Scene, deltaTime: f32),
	terminate:  proc(game: ^Game),
	createScene: proc(game: ^Game, name: string, next_scene: bool) -> ^Scene,
	changeScene: proc(game: ^Game, name: string),
}


InitializeGame :: proc(game: ^Game) {
	log.info("Initializing game")
	err := vmem.arena_init_growing(&game.arena)
	if err != nil {
		log.error("Error initializing game growing arena: ", err)
	}
	game.backgroundColor = rl.BLACK
	game.run = GameRun
	game.terminate = GameTerminate
	game.createScene = GameCreateScene
	game.changeScene = GameChangeScene

	ResourceManager_Init(&game.resourceManager)
	SceneManager_Init(&game.sceneManager, &game.arena)
	game.gameContext.game = game
	game.gameContext.sceneManager = &game.sceneManager
	game.state = .Initialized

}

GameRun :: proc(game: ^Game, deltaTime: f32) {
	// Process Node Queues
	ProcessSceneChange(&game.sceneManager)

	// Run game update proc if defined
	if game.update != nil {
		game->update(game.sceneManager.currentScene, deltaTime)
	}

	game.gameContext.scene = game.sceneManager.currentScene
	RunScene(game.sceneManager.currentScene, &game.gameContext, deltaTime)
}

GameTerminate :: proc(game: ^Game) {
	vmem.arena_free_all(&game.arena)
	free(game)
}

GameCreateScene :: proc(game: ^Game, name: string, next_scene: bool) -> ^Scene {
	return CreateScene(&game.sceneManager, name, next_scene)
}

GameChangeScene :: proc(game: ^Game, name: string) {
	ChangeScene_ByName(&game.sceneManager, name)
}

// Use this to allocate resources that should share lifetime with the game
GameCreateResource :: proc(game: ^Game, $T: typeid) -> ^T {
	allocator := vmem.arena_allocator(&game.arena)
	resource, err := new(T, allocator)
	if err != nil {
		log.error("Error allocating resource: ", err)
		return nil
	}
	return resource
}
