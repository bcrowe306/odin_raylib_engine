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

dropdownEdit: bool

main :: proc() {


	logger := log.create_console_logger(.Info)
	context.logger = logger

	isTest := UITest_Init()
	if isTest {
		rl.SetConfigFlags({.WINDOW_HIDDEN})
	}

	rl.SetTraceLogLevel(.WARNING)
	rl.InitWindow(WINDOW_SIZE[0], WINDOW_SIZE[1], "Odin Raylib Engine")
	defer rl.CloseWindow()

	// Load Open Sans font and apply Google Material Flat Dark Grey styling
	guiFont := rl.LoadFontEx("engine/Open_Sans/static/OpenSans-Regular.ttf", 15, nil, 0)
	defer rl.UnloadFont(guiFont)
	ApplyMaterialDarkTheme(guiFont)

	rl.InitAudioDevice()

	// Virtual Viewport Render Texture (1280x720 internal resolution)
	viewportTex := rl.LoadRenderTexture(WINDOW_SIZE[0], WINDOW_SIZE[1])
	defer rl.UnloadRenderTexture(viewportTex)

	game := asteroids.CreateGame()
	defer game->terminate()
	game->setup()
	e.ProcessSceneChange(&game.sceneManager)

	// Create Particle Emitter Node in the Scene
	scene := game.sceneManager.currentScene
	particleNode := ParticleEmitterNode_Create(scene, "Particle Emitter")
	particleNode.position = {f32(WINDOW_SIZE[0]) / 2, f32(WINDOW_SIZE[1]) / 2}
	ast := rl.LoadTexture("assets/graphics/Space Pack/Asteroids/Asteroid_1.png")
	particleNode.emitter.texture = &ast

	// Docking and Layout State
	dockSide := DockSide.Right
	inspectorWidth: f32 = 400
	hierarchyWidth: f32 = 200
	inspectorScroll := rl.Vector2{0, 0}
	inspectorContentHeight: f32 = 1400

	selectedTargetIndex := 0
	selectedColorStop := 0
	draggingColorStop := false

	targetNames := [3]cstring{
		"Particle Emitter",
		"Spaceship Node",
		"Spaceship Data",
	}

	// Game loop
	for !rl.WindowShouldClose() {
		deltaTime := rl.GetFrameTime()

		sw := f32(rl.GetScreenWidth())
		sh := f32(rl.GetScreenHeight())

		// -------------------------------------------------------------
		// Compute Docked Layout (Viewport in middle, Inspector on either side)
		// -------------------------------------------------------------
		hierarchyRect: rl.Rectangle
		viewportRect: rl.Rectangle
		inspectorRect: rl.Rectangle

		if dockSide == .Right {
			// [ Hierarchy (Left) ] [ Viewport (Middle) ] [ Inspector (Right) ]
			hierarchyRect = {0, 0, hierarchyWidth, sh}
			viewportRect  = {hierarchyWidth, 0, sw - hierarchyWidth - inspectorWidth, sh}
			inspectorRect = {sw - inspectorWidth, 0, inspectorWidth, sh}
		} else {
			// [ Inspector (Left) ] [ Viewport (Middle) ] [ Hierarchy (Right) ]
			inspectorRect = {0, 0, inspectorWidth, sh}
			viewportRect  = {inspectorWidth, 0, sw - inspectorWidth - hierarchyWidth, sh}
			hierarchyRect = {sw - hierarchyWidth, 0, hierarchyWidth, sh}
		}

		// Automated testing step
		if UITest_Step(&dockSide, &selectedTargetIndex, inspectorRect, viewportRect, hierarchyRect, &particleNode.emitter) {
			break
		}

		// Interactive F1 key to trigger test in window mode
		if rl.IsKeyPressed(.F1) {
			uiTestState.enabled = true
			uiTestState.currentFrame = 0
		}

		// -------------------------------------------------------------
		// 1. Update & Render Game into Virtual Viewport Texture
		// -------------------------------------------------------------
		// Note: The Particle Emitter is now a Node in the scene, so
		// Note: game->run handles all nodes
		rl.BeginTextureMode(viewportTex)
		rl.ClearBackground(game.backgroundColor)

		game->run(deltaTime)

		rl.EndTextureMode()

		// -------------------------------------------------------------
		// 2. Render Main Window GUI
		// -------------------------------------------------------------
		rl.BeginDrawing()
		rl.ClearBackground(rl.Color{20, 21, 23, 255}) // Surface container lowest

		// -------------------------------------------------------------
		// A. Center Viewport (Game Display)
		// -------------------------------------------------------------
		rl.BeginScissorMode(i32(viewportRect.x), i32(viewportRect.y), i32(viewportRect.width), i32(viewportRect.height))
		rl.DrawRectangleRec(viewportRect, rl.Color{14, 15, 17, 255})

		// Fit virtual canvas (1280x720) inside viewportRect preserving aspect ratio
		aspect := f32(WINDOW_SIZE[0]) / f32(WINDOW_SIZE[1])
		vW: f32
		vH: f32
		vX: f32
		vY: f32
		if (viewportRect.width / viewportRect.height) > aspect {
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
		canvasRect := rl.Rectangle{vX, vY, vW, vH}

		// Draw flipped OpenGL render texture
		srcRect := rl.Rectangle{0, 0, f32(viewportTex.texture.width), -f32(viewportTex.texture.height)}
		rl.DrawTexturePro(viewportTex.texture, srcRect, canvasRect, {0, 0}, 0, rl.WHITE)

		// Viewport Header Label
		DrawEngineText("VIEWPORT", viewportRect.x + 14, 13, 14, rl.Color{138, 142, 153, 255})

		// Interactive repositioning of particle emitter node on click inside canvas
		if rl.IsMouseButtonDown(.LEFT) && rl.CheckCollisionPointRec(rl.GetMousePosition(), canvasRect) {
			mp := rl.GetMousePosition()
			particleNode.position = {
				(mp.x - canvasRect.x) * (f32(WINDOW_SIZE[0]) / canvasRect.width),
				(mp.y - canvasRect.y) * (f32(WINDOW_SIZE[1]) / canvasRect.height),
			}
		}

		rl.EndScissorMode()

		// Outer viewport borders
		rl.DrawRectangleLinesEx(viewportRect, 1, rl.Color{55, 57, 63, 255})

		// -------------------------------------------------------------
		// B. Scene Hierarchy Panel
		// -------------------------------------------------------------
		rl.DrawRectangleRec(hierarchyRect, rl.Color{24, 25, 28, 255})
		headerH: f32 = 42

		// Hierarchy Header
		rl.DrawRectangleRec({hierarchyRect.x, 0, hierarchyRect.width, headerH}, rl.Color{30, 31, 35, 255})
		rl.DrawLineEx({hierarchyRect.x, headerH}, {hierarchyRect.x + hierarchyRect.width, headerH}, 1, rl.Color{55, 57, 63, 255})
		DrawEngineText("SCENE HIERARCHY", hierarchyRect.x + 14, 13, 15, rl.Color{226, 226, 233, 255})

		// Hierarchy Tree Items (clickable nodes)
		itemH: f32 = 30
		itemY := headerH + 10
		itemW := hierarchyRect.width - 24

		itemIcons := [3]cstring{"* ", "> ", "$ "}
		for idx in 0..<3 {
			btnBounds := rl.Rectangle{hierarchyRect.x + 12, itemY, itemW, itemH}

			// Highlight active selected node
			if idx == selectedTargetIndex {
				rl.DrawRectangleRec(btnBounds, rl.Color{37, 99, 235, 60})
				rl.DrawRectangleLinesEx(btnBounds, 1, rl.Color{110, 168, 254, 255})
			}

			fullLabel := fmt.ctprintf("%s%s", itemIcons[idx], targetNames[idx])
			if rl.GuiButton(btnBounds, fullLabel) {
				selectedTargetIndex = idx
			}

			itemY += itemH + 6
		}

		// Border between hierarchy and center
		hBorderX := hierarchyRect.x + hierarchyRect.width if dockSide == .Right else hierarchyRect.x
		rl.DrawLineEx({hBorderX, 0}, {hBorderX, sh}, 1, rl.Color{55, 57, 63, 255})

		// -------------------------------------------------------------
		// C. Docked Inspector Panel (Left or Right)
		// -------------------------------------------------------------
		rl.DrawRectangleRec(inspectorRect, rl.Color{24, 25, 28, 255})

		// Inspector Header Bar
		rl.DrawRectangleRec({inspectorRect.x, 0, inspectorRect.width, headerH}, rl.Color{30, 31, 35, 255})
		rl.DrawLineEx({inspectorRect.x, headerH}, {inspectorRect.x + inspectorRect.width, headerH}, 1, rl.Color{55, 57, 63, 255})
		DrawEngineText("INSPECTOR", inspectorRect.x + 16, 13, 16, rl.Color{226, 226, 233, 255})

		// Dock Side Switch Button
		dockBtnText: cstring = "< Dock Left" if dockSide == .Right else "Dock Right >"
		dockBtnRect := rl.Rectangle{inspectorRect.x + inspectorRect.width - 105, 10, 95, 22}
		if rl.GuiButton(dockBtnRect, dockBtnText) {
			dockSide = .Left if dockSide == .Right else .Right
		}

		// Target Selection Tabs inside Inspector
		selectorY := headerH + 6
		selectorH: f32 = 28
		targetBtnW := (inspectorRect.width - 24) / 3
		for tIdx in 0..<3 {
			tBtnX := inspectorRect.x + 12 + f32(tIdx) * targetBtnW
			label := targetNames[tIdx]
			if rl.GuiButton({tBtnX, selectorY, targetBtnW - 2, 22}, label) {
				selectedTargetIndex = tIdx
			}
		}
		rl.DrawLineEx({inspectorRect.x, selectorY + selectorH}, {inspectorRect.x + inspectorRect.width, selectorY + selectorH}, 1, rl.Color{45, 47, 53, 255})

		// Inspector Scroll Panel
		panelY := selectorY + selectorH + 4
		panelBounds := rl.Rectangle{
			inspectorRect.x,
			panelY,
			inspectorRect.width,
			inspectorRect.height - panelY,
		}

		content := rl.Rectangle{
			0,
			0,
			panelBounds.width - 5,
			inspectorContentHeight,
		}

		view := rl.Rectangle{}
		rl.GuiScrollPanel(panelBounds, nil, content, &inspectorScroll, &view)

		rl.BeginScissorMode(i32(view.x), i32(view.y), i32(view.width), i32(view.height))

		nextY := view.y + inspectorScroll.y + 8
		startY := nextY
		x := view.x + inspectorScroll.x + 10
		itemWidth := panelBounds.width - 70
		labelWidth: f32 = 130
		sliderHeight: f32 = 18
		yPadding: f32 = 4

		// Selected Target Rendering
		switch selectedTargetIndex {
		case 0:
			// Target: Particle Emitter Node & Emitter
			DrawEngineText("Particle Emitter Node", x, nextY, 16, rl.Color{110, 168, 254, 255})
			nextY += 24

			// Node transform & state reflection editor
			DrawGenericStructGui(cast(^e.Node)particleNode, x, &nextY, itemWidth, labelWidth, sliderHeight, yPadding)
			nextY += 16

			DrawEngineText("Emitter Settings & FX", x, nextY, 16, rl.Color{110, 168, 254, 255})
			nextY += 24

			// Color Ramp / Gradient Editor
			ParticleEmitter_DrawColorRampGui(&particleNode.emitter, x, &nextY, itemWidth, &selectedColorStop, &draggingColorStop, view)
			nextY += 12

			// Emitter Actions: Start, Stop
			btnW := (itemWidth - labelWidth - 4) / 2
			if rl.GuiButton({x + labelWidth, nextY, btnW, sliderHeight + 4}, "Start") {
				if particleNode.emitter.start != nil {
					particleNode.emitter->start()
				} else {
					ParticleEmitter_Start(&particleNode.emitter)
				}
			}
			if rl.GuiButton({x + labelWidth + btnW + 4, nextY, btnW, sliderHeight + 4}, "Stop") {
				if particleNode.emitter.stop != nil {
					particleNode.emitter->stop()
				} else {
					ParticleEmitter_Stop(&particleNode.emitter)
				}
			}
			nextY += sliderHeight + yPadding + 8

			// Generic struct reflection editor for ParticleEmitter
			DrawGenericStructGui(&particleNode.emitter, x, &nextY, itemWidth, labelWidth, sliderHeight, yPadding)

		case 1:
			// Target: Ship Node
			DrawEngineText("Ship Node Transform & State", x, nextY, 16, rl.Color{110, 168, 254, 255})
			nextY += 24

			if game.sceneManager.currentScene != nil && game.sceneManager.currentScene.manager != nil {
				scene := game.sceneManager.currentScene
				shipNode: ^e.Node = nil
				for n in scene.manager.nodes {
					if n != nil && n.name == "Spaceship" {
						shipNode = n
						break
					}
				}
				if shipNode == nil {
					for n in scene.manager.nodes {
						if n != nil && n != scene.rootNode {
							shipNode = n
							break
						}
					}
				}
				if shipNode != nil {
					DrawGenericStructGui(shipNode, x, &nextY, itemWidth, labelWidth, sliderHeight, yPadding)
				}
			}

		case 2:
			// Target: Spaceship Data
			DrawEngineText("Spaceship Physics & Input", x, nextY, 16, rl.Color{110, 168, 254, 255})
			nextY += 24

			if game.sceneManager.currentScene != nil && game.sceneManager.currentScene.manager != nil {
				scene := game.sceneManager.currentScene
				shipNode: ^e.Node = nil
				for n in scene.manager.nodes {
					if n != nil && n.name == "Spaceship" {
						shipNode = n
						break
					}
				}
				if shipNode == nil {
					for n in scene.manager.nodes {
						if n != nil && n != scene.rootNode {
							shipNode = n
							break
						}
					}
				}
				if shipNode != nil && shipNode.resource != nil {
					shipData := cast(^asteroids.Spaceship)shipNode.resource
					DrawGenericStructGui(shipData, x, &nextY, itemWidth, labelWidth, sliderHeight, yPadding)
				} else {
					DrawEngineText("Spaceship resource data not active", x, nextY, 14, rl.GRAY)
					nextY += 20
				}
			}
		}

		calculatedHeight := (nextY - startY) + 60
		if calculatedHeight > inspectorContentHeight || inspectorContentHeight == 0 {
			inspectorContentHeight = calculatedHeight
		}

		rl.EndScissorMode()

		// Border between inspector and center
		iBorderX := inspectorRect.x if dockSide == .Right else inspectorRect.x + inspectorRect.width
		rl.DrawLineEx({iBorderX, 0}, {iBorderX, sh}, 1, rl.Color{55, 57, 63, 255})

		rl.EndDrawing()
	}
}
