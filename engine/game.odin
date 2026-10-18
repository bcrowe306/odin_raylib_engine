package engine

import vmem "core:mem/virtual"
import "core:log"
import rl "vendor:raylib"

GameState :: enum {
	None,
	Initialized,
	Ready,
	Running,
	Paused,
	Quitting,
}

GameContext :: struct {
	game:         ^Game,
	sceneManager: ^SceneManager,
	scene:        ^Scene,
	input:        ^InputSystem,
	camera:       ^CameraNode,
}


Game :: struct {
	arena:           vmem.Arena,
	state:           GameState,
	sceneManager:    SceneManager,
	physicsWorld:    PhysicsWorld,
	input:           InputSystem,
	backgroundColor: rl.Color `gui:"true"`,
	resourceManager: ResourceManager,
	gameContext:     GameContext,
	drawBounds:      bool `gui:"true"`,
	shouldQuit:      bool,

	// Viewport mapping & UI interaction state
	virtualSize:        [2]f32,
	viewportCanvasRect: rl.Rectangle,
	activeDropdown:     rawptr,
	uiMouseConsumed:    bool,

	// Headless UI test input state (for unit tests in engine_test.odin)
	uiTestInputEnabled:  bool,
	uiTestMousePos:      [2]f32,
	uiTestMouseDown:     bool,
	uiTestMousePressed:  bool,
	uiTestMouseReleased: bool,
	uiTestRightPressed:  bool,
	uiTestShiftDown:     bool,
	uiTestKeyEnter:      bool,
	uiTestKeySpace:      bool,
	uiTestKeyTab:        bool,
	uiTestKeyUp:         bool,
	uiTestKeyDown:       bool,
	uiTestKeyLeft:       bool,
	uiTestKeyRight:      bool,
	uiTestKeyBackspace:  bool,
	uiTestKeyEscape:     bool,
	uiTestCharQueue:     [32]u8,
	uiTestCharCount:     int,

	setup:       proc(game: ^Game),
	run:         proc(game: ^Game, deltaTime: f32),
	update:      proc(game: ^Game, scene: ^Scene, deltaTime: f32),
	terminate:   proc(game: ^Game),
	quit:        proc(game: ^Game),
	createScene: proc(game: ^Game, name: string, next_scene: bool, setup: SceneSetupProc = nil) -> ^Scene,
	changeScene: proc(game: ^Game, name: string),
}


InitializeGame :: proc(game: ^Game) {
	log.info("Initializing game")
	err := vmem.arena_init_growing(&game.arena)
	if err != nil {
		log.error("Error initializing game growing arena: ", err)
	}
	game.backgroundColor = rl.BLACK
	game.shouldQuit = false
	game.virtualSize = {1280, 720}
	game.viewportCanvasRect = {0, 0, 1280, 720}
	game.activeDropdown = nil
	game.uiMouseConsumed = false
	game.run = GameRun
	game.terminate = GameTerminate
	game.quit = GameQuit
	game.createScene = GameCreateScene
	game.changeScene = GameChangeScene

	InputSystem_Init(&game.input)
	PhysicsWorld_Init(&game.physicsWorld)
	ResourceManager_Init(&game.resourceManager)
	SceneManager_Init(&game.sceneManager, &game.arena)
	game.gameContext.game = game
	game.gameContext.sceneManager = &game.sceneManager
	game.gameContext.input = &game.input
	game.gameContext.camera = nil
	game.state = .Initialized
}

Game_SetViewportCanvas :: proc(game: ^Game, canvasRect: rl.Rectangle, virtualSize: [2]f32 = {1280, 720}) {
	if game == nil do return
	game.viewportCanvasRect = canvasRect
	game.virtualSize = virtualSize
}

GameQuit :: proc(game: ^Game) {
	if game == nil do return
	game.shouldQuit = true
	game.state = .Quitting
}

GameRun :: proc(game: ^Game, deltaTime: f32) {
	if game == nil || game.shouldQuit || game.state == .Quitting {
		return
	}

	game.uiMouseConsumed = false

	// 1. Poll and update Two-Tier Input System once per frame (before physics and game/scene update)
	InputSystem_Update(&game.input, deltaTime)

	// 2. Process Scene Transitions
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.gameContext.scene = game.sceneManager.currentScene

	// 3. Step Box2D Physics World
	PhysicsWorld_Step(&game.physicsWorld, deltaTime, &game.gameContext)

	// 4. Run game update proc if defined
	if game.update != nil {
		game->update(game.sceneManager.currentScene, deltaTime)
	}

	if game.shouldQuit || game.state == .Quitting {
		return
	}

	// Process any scene change requested during game.update
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.gameContext.scene = game.sceneManager.currentScene

	// 5. Update and render active scene nodes
	RunScene(game.sceneManager.currentScene, &game.gameContext, deltaTime)
}

GameTerminate :: proc(game: ^Game) {
	if game == nil do return
	SceneManager_Terminate(&game.sceneManager)
	ResourceManager_Terminate(&game.resourceManager)
	PhysicsWorld_Destroy(&game.physicsWorld)
	InputSystem_Destroy(&game.input)
	vmem.arena_destroy(&game.arena)
	free(game)
}

GameCreateScene :: proc(game: ^Game, name: string, next_scene: bool, setup: SceneSetupProc = nil) -> ^Scene {
	return CreateScene(&game.sceneManager, name, next_scene, setup)
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

Game_Alloc :: proc(game: ^Game, size: int) -> rawptr {
	alloc := vmem.arena_allocator(&game.arena)
	ptr, err := alloc.procedure(alloc.data, .Alloc, size, 8, nil, 0, #location())
	if err != nil {
		log.error("Failed to allocate memory from game arena:", err)
		return nil
	}
	return raw_data(ptr)
}
