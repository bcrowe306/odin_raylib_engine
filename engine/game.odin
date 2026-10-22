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
	game:          ^Game,
	sceneManager:  ^SceneManager,
	scene:         ^Scene,
	input:         ^InputSystem,
	camera:        ^CameraNode,
	scriptManager: ^ScriptManager,
	assetManager:  ^AssetManager,
}


Game :: struct {
	arena:           vmem.Arena,
	state:           GameState,
	sceneManager:    SceneManager,
	physicsWorld:    PhysicsWorld,
	input:           InputSystem,
	scriptManager:   ScriptManager,
	assetManager:    AssetManager,
	backgroundColor: rl.Color `gui:"true"`,
	resourceManager: ResourceManager,
	tweens:          Tween_State,
	gameContext:     GameContext,
	drawBounds:      bool `gui:"true"`,
	shouldQuit:      bool,
	treePaused:      bool, // Engine.set_paused: Pausable nodes stop (scene_flow.odin)
	transition:      Scene_Transition,
	preloads:        map[^Scene]^Scene_Preload,

	// Viewport mapping & UI interaction state
	virtualSize:        [2]f32,
	// Audio buses (project Audio settings): multiply node volumes.
	musicVolume:        f32,
	sfxVolume:          f32,
	masterVolume:       f32,
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
	loadProject: proc(game: ^Game, pathOrDir: string) -> bool,
	exportOre:   proc(projectDir: string, outOrePath: string) -> bool,
}


InitializeGame :: proc(game: ^Game) {
	game.scriptManager.hotReload = true // turned off for .ore packages

	log.info("Initializing game")
	err := vmem.arena_init_growing(&game.arena)
	if err != nil {
		log.error("Error initializing game growing arena: ", err)
	}
	game.backgroundColor = rl.BLACK
	game.shouldQuit = false
	game.virtualSize = {1280, 720}
	game.musicVolume = 1
	game.sfxVolume = 1
	game.masterVolume = 1
	game.viewportCanvasRect = {0, 0, 1280, 720}
	game.activeDropdown = nil
	game.uiMouseConsumed = false

	// Lua hot reload: edited script files take effect while the game runs.
	if game.scriptManager.hotReload do ScriptManager_CheckForChanges(&game.scriptManager)
	game.run = GameRun
	game.terminate = GameTerminate
	game.quit = GameQuit
	game.createScene = GameCreateScene
	game.changeScene = GameChangeScene
	game.loadProject = Game_LoadProject
	game.exportOre = Game_ExportOrePackage

	InputSystem_Init(&game.input)
	PhysicsWorld_Init(&game.physicsWorld)
	ResourceManager_Init(&game.resourceManager)
	AssetManager_Init(&game.assetManager)
	SceneManager_Init(&game.sceneManager, &game.arena)
	ScriptManager_Init(&game.scriptManager, game)
	game.gameContext.game = game
	game.gameContext.sceneManager = &game.sceneManager
	game.gameContext.input = &game.input
	game.gameContext.camera = nil
	game.gameContext.scriptManager = &game.scriptManager
	game.gameContext.assetManager = &game.assetManager
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
	if game.scriptManager.hotReload do Shader_CheckForChanges() // edited .fs files

	// 2. Process Scene Transitions (and load scenes' assets in the background)
	Scene_FlowUpdate(game, deltaTime)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	Scene_FlowAfterChange(game)
	game.gameContext.scene = game.sceneManager.currentScene

	// 3. Step Box2D Physics World (not while the game is paused)
	if !game.treePaused do PhysicsWorld_Step(&game.physicsWorld, deltaTime, &game.gameContext)

	// 4. Run game update proc if defined
	if game.update != nil {
		game->update(game.sceneManager.currentScene, deltaTime)
	}

	if game.shouldQuit || game.state == .Quitting {
		return
	}

	// Process any scene change requested during game.update
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	Scene_FlowAfterChange(game)
	game.gameContext.scene = game.sceneManager.currentScene

	// 5. Update and render active scene nodes
	RunScene(game.sceneManager.currentScene, &game.gameContext, deltaTime)
	Scene_DrawTransition(game)
}

GameTerminate :: proc(game: ^Game) {
	if game == nil do return
	Tween_Destroy(&game.tweens, game.scriptManager.L) // releases Lua callbacks: before the Lua state goes
	Scene_FlowShutdown(game)
	if game.scriptManager.isReady do Save_Flush(game.scriptManager.L) // Save data is written on quit
	Audio_ResetEffects()
	Text_UnloadFonts()
	Locale_Reset()
	Audio_SetListener(nil)
	ScriptManager_Destroy(&game.scriptManager)
	SceneManager_Terminate(&game.sceneManager)
	AssetManager_Destroy(&game.assetManager)
	ResourceManager_Terminate(&game.resourceManager)
	PhysicsWorld_Destroy(&game.physicsWorld)
	Shader_UnloadAll()
	Lighting_Unload()
	InputSystem_Destroy(&game.input)
	Node_ReleaseArenaPool()
	Component_ClearCaches()
	vmem.arena_destroy(&game.arena)
	free(game)
}

GameCreateScene :: proc(game: ^Game, name: string, next_scene: bool, setup: SceneSetupProc = nil) -> ^Scene {
	return CreateScene(&game.sceneManager, name, next_scene, setup)
}

GameChangeScene :: proc(game: ^Game, name: string) {
	ChangeScene_ByName(&game.sceneManager, name)
}

Game_ExportOrePackage :: proc(projectDir: string, outOrePath: string) -> bool {
	return OrePackage_CreateFromDirectory(projectDir, outOrePath, true)
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

// Game_ClearColor: the current scene's background colour, else the game's.
Game_ClearColor :: proc(game: ^Game) -> rl.Color {
	if s := game.sceneManager.currentScene; s != nil && s.backgroundColor.a > 0 do return s.backgroundColor
	return game.backgroundColor
}

// Game_BusVolume: the music or sound-effects bus volume (1 without a game).
Audio_Bus :: enum {
	Master,
	Music,
	Sfx,
}

// Game_SetBusVolume changes a bus volume and applies it to what's playing.
Game_SetBusVolume :: proc(game: ^Game, bus: Audio_Bus, v: f32) {
	v := clamp(v, 0, 1)
	switch bus {
	case .Master:
		game.masterVolume = v
		if rl.IsAudioDeviceReady() do rl.SetMasterVolume(v)
	case .Music:
		game.musicVolume = v
	case .Sfx:
		game.sfxVolume = v
	}
	scene := game.sceneManager.currentScene
	if scene == nil || scene.manager == nil do return
	for n in scene.manager.nodes {
		if n == nil do continue
		#partial switch bus {
		case .Music:
			if n.typeId == MusicNode do MusicNode_ApplyVolume(cast(^MusicNode)n)
		case .Sfx:
			if n.typeId == SoundNode {
				sn := cast(^SoundNode)n
				if sn.audio != nil && rl.IsAudioDeviceReady() {
					vol, _ := SoundNode_Mix(sn, &game.gameContext)
					rl.SetSoundVolume(sn.audio.sound, vol)
					for s in sn.audio.aliases do rl.SetSoundVolume(s, vol)
				}
			}
		}
	}
}

Game_BusVolume :: proc(ctx: ^GameContext, music: bool) -> f32 {
	if ctx == nil || ctx.game == nil do return 1
	return ctx.game.musicVolume if music else ctx.game.sfxVolume
}
