package main

import "core:log"
import "core:math"
import "core:os"
import "core:path/filepath"
import "core:strings"
import rl "vendor:raylib"
import "asteroids"
import e "engine"

WINDOW_SIZE :[2]i32: {1280, 720}

DEFAULT_BULLET_VELOCITY : [2]f32 : {0, -500}

ParticleEmitter :: e.ParticleEmitter
ParticleEmitterNode :: e.ParticleEmitterNode
ParticleEmitterNode_Create :: e.ParticleEmitterNode_Create
ParticleEmitter_Start :: e.ParticleEmitter_Start
ParticleEmitter_Stop :: e.ParticleEmitter_Stop
ParticleEmitter_Update :: e.ParticleEmitter_Update
ParticleEmitter_Render :: e.ParticleEmitter_Render
ParticleEmitter_DrawColorRampGui :: e.ParticleEmitter_DrawColorRampGui

ComputeCanvasRect :: proc(viewportRect: rl.Rectangle) -> rl.Rectangle {
	aspect := f32(WINDOW_SIZE[0]) / f32(WINDOW_SIZE[1])
	vW, vH, vX, vY: f32
	if (viewportRect.width / max(viewportRect.height, 1)) > aspect {
		vH = viewportRect.height
		vW = vH * aspect
		vX = viewportRect.x + (viewportRect.width - vW) / 2
		vY = viewportRect.y
	} else {
		vW = viewportRect.width
		vH = vW / aspect
		vX = viewportRect.x
		vY = viewportRect.y + (viewportRect.height - vH) / 2
	}
	return rl.Rectangle{math.round(vX), math.round(vY), math.round(vW), math.round(vH)}
}

Editor_SyncWithCurrentScene :: proc(ed: ^Editor, game: ^e.Game) -> ^e.ParticleEmitterNode {
	ed.staticBody = nil
	ed.dynamicBody = nil
	ed.characterMover = nil
	ed.areaNode = nil
	ed.raycastNode = nil
	particleNode: ^e.ParticleEmitterNode = nil

	if game != nil && game.sceneManager.currentScene != nil && game.sceneManager.currentScene.manager != nil {
		for n in game.sceneManager.currentScene.manager.nodes {
			if n == nil do continue
			if n.name == "StaticBody" {
				ed.staticBody = cast(^e.StaticBodyNode)n
			} else if n.name == "DynamicBody" {
				ed.dynamicBody = cast(^e.DynamicBodyNode)n
			} else if n.name == "CharacterMover" {
				ed.characterMover = cast(^e.CharacterMoverNode)n
			} else if n.name == "Area Sensor" {
				ed.areaNode = cast(^e.AreaNode)n
			} else if n.name == "Raycast" {
				ed.raycastNode = cast(^e.RaycastNode)n
			} else if n.name == "Particle Emitter" {
				particleNode = cast(^e.ParticleEmitterNode)n
			}
		}
	}
	return particleNode
}

main :: proc() {
	logger := log.create_console_logger(.Info)
	context.logger = logger

	// Parse command line arguments
	projectPath := ""
	for i := 0; i < len(os.args); i += 1 {
		arg := os.args[i]
		if (arg == "--project" || arg == "-p") && i + 1 < len(os.args) {
			projectPath = os.args[i + 1]
		} else if strings.has_prefix(arg, "--project=") {
			projectPath = arg[10:]
		}
	}

	// A project plays with the engine's generic runner (engine/runner.odin;
	// the standalone runner/ uses it too), which reads every run option
	// (--user-data, --uncapped, --bench, ...).
	if projectPath != "" {
		e.Engine_RunProject(e.Engine_ParseRunArgs(os.args[1:]))
		return
	}

	isTest := UITest_Init()
	if isTest {
		rl.SetConfigFlags({.WINDOW_HIDDEN})
	} else {
		rl.SetConfigFlags({.WINDOW_RESIZABLE})
	}

	rl.SetTraceLogLevel(.WARNING)
	rl.InitWindow(WINDOW_SIZE[0], WINDOW_SIZE[1], "Rayzr")
	defer rl.CloseWindow()

	rl.SetTargetFPS(60)

	// Initialize Multi-Size 1:1 Engine Font Cache (Open Sans)
	guiFont := e.InitEngineFonts("engine/Open_Sans/static/OpenSans-Regular.ttf")
	defer e.UnloadEngineFonts()
	ApplyMaterialDarkTheme(guiFont)

	rl.InitAudioDevice()

	// Game Setup (creates "title_menu", "settings", and "main" scenes)
	game := asteroids.CreateGame()
	defer game->terminate()
	game->setup()
	e.ProcessSceneChange(&game.sceneManager, &game.gameContext)

	// Physics Joint (Optional joint configurable in Inspector)
	physicsJoint := e.PhysicsJoint{}
	e.PhysicsJoint_Init(&physicsJoint, .Distance)
	physicsJoint.distance.enableSpring = true
	physicsJoint.distance.hertz = 2.0
	physicsJoint.distance.dampingRatio = 0.4
	physicsJoint.distance.length = 180.0

	// Modular Editor State
	editor := Editor{}
	Editor_Init(&editor)
	editor.joint = &physicsJoint

	// Game loop
	for !rl.WindowShouldClose() && !game.shouldQuit {
		deltaTime := rl.GetFrameTime()

		sw := f32(rl.GetScreenWidth())
		sh := f32(rl.GetScreenHeight())

		// Update Editor & compute layout
		Editor_Update(&editor)
		Editor_ComputeLayout(&editor, sw, sh)
		canvasRect := ComputeCanvasRect(editor.viewportRect)
		e.Game_SetViewportCanvas(game, canvasRect, {f32(WINDOW_SIZE[0]), f32(WINDOW_SIZE[1])})

		// Sync Editor references with active scene nodes
		particleNode := Editor_SyncWithCurrentScene(&editor, game)

		// Automated testing step
		if UITest_Step(&editor.inspector.dockSide, &editor.selectedTargetIndex, editor.inspectorRect, editor.viewportRect, editor.hierarchyRect, &particleNode.emitter if particleNode != nil else nil, &editor, game) {
			break
		}

		// Interactive F1 key to trigger test in window mode
		if rl.IsKeyPressed(.F1) {
			uiTestState.enabled = true
			uiTestState.currentFrame = 0
		}

		// -------------------------------------------------------------
		// Render Main Window GUI & Direct 1:1 Game Viewport
		// -------------------------------------------------------------
		rl.BeginDrawing()
		rl.ClearBackground(rl.Color{20, 21, 23, 255}) // Surface container lowest

		// -------------------------------------------------------------
		// A. Viewport (Game Display - rendered directly without FBO resampling blur)
		// -------------------------------------------------------------
		rl.BeginScissorMode(i32(editor.viewportRect.x), i32(editor.viewportRect.y), i32(editor.viewportRect.width), i32(editor.viewportRect.height))
		rl.DrawRectangleRec(editor.viewportRect, rl.Color{14, 15, 17, 255})
		rl.DrawRectangleRec(canvasRect, game.backgroundColor)

		// Clip to the active 16:9 canvasRect and transform virtual 1280x720 coordinates directly
		rl.BeginScissorMode(i32(canvasRect.x), i32(canvasRect.y), i32(canvasRect.width), i32(canvasRect.height))
		viewportCamera := rl.Camera2D{
			offset = {canvasRect.x, canvasRect.y},
			zoom   = canvasRect.width / f32(WINDOW_SIZE[0]),
		}
		e.BeginEngineViewportMode(viewportCamera)

		game->run(deltaTime)
		if game.sceneManager.currentScene != nil && game.sceneManager.currentScene.name == "main" && game.physicsWorld.drawPhysicsDebug {
			e.PhysicsJoint_DrawDebug(&physicsJoint)
		}

		e.EndEngineViewportMode()
		rl.EndScissorMode()

		// Viewport Header Label when editor is active
		if editor.enabled {
			rl.BeginScissorMode(i32(editor.viewportRect.x), i32(editor.viewportRect.y), i32(editor.viewportRect.width), i32(editor.viewportRect.height))
			DrawEngineText("VIEWPORT", editor.viewportRect.x + 14, 13, 14, rl.Color{138, 142, 153, 255})

			// Interactive repositioning of particle emitter node on click inside canvas when in main scene (and not clicking a UI widget)
			if particleNode != nil && game.sceneManager.currentScene != nil && game.sceneManager.currentScene.name == "main" && !game.uiMouseConsumed {
				if rl.IsMouseButtonDown(.LEFT) && rl.CheckCollisionPointRec(rl.GetMousePosition(), canvasRect) {
					mp := rl.GetMousePosition()
					particleNode.position = {
						(mp.x - canvasRect.x) * (f32(WINDOW_SIZE[0]) / canvasRect.width),
						(mp.y - canvasRect.y) * (f32(WINDOW_SIZE[1]) / canvasRect.height),
					}
				}
			}
			rl.EndScissorMode()
		}

		// Outer viewport borders when editor is active
		if editor.enabled {
			rl.DrawRectangleLinesEx(editor.viewportRect, 1, rl.Color{55, 57, 63, 255})
		}

		// -------------------------------------------------------------
		// B & C. Modular Editor Panels (Scene Hierarchy & Inspector)
		// -------------------------------------------------------------
		Editor_Render(&editor, game, particleNode, sh)

		rl.EndDrawing()
	}
}
