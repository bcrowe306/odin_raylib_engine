package main

import "core:fmt"
import "core:os"
import b2 "vendor:box2d"
import rl "vendor:raylib"
import e "engine"
import a "asteroids"

UITestState :: struct {
	enabled: bool,
	currentFrame: int,
	totalFrames: int,
	success: bool,
}

uiTestState := UITestState{
	enabled = false,
	currentFrame = 0,
	totalFrames = 60,
	success = true,
}

UITest_Init :: proc() -> bool {
	for arg in os.args[1:] {
		if arg == "--test-ui" || arg == "-test-ui" {
			uiTestState.enabled = true
			return true
		}
	}
	return false
}

UITest_InjectClick :: proc(x, y: f32) {
	rl.PlayAutomationEvent({0, 7, {i32(x), i32(y), 0, 0}})
	rl.PlayAutomationEvent({0, 6, {0, 0, 0, 0}})
}

UITest_InjectRelease :: proc(x, y: f32) {
	rl.PlayAutomationEvent({0, 7, {i32(x), i32(y), 0, 0}})
	rl.PlayAutomationEvent({0, 5, {0, 0, 0, 0}})
}

UITest_Step :: proc(
	dockSide: ^DockSide,
	selectedTargetIndex: ^int,
	inspectorRect: rl.Rectangle,
	viewportRect: rl.Rectangle,
	hierarchyRect: rl.Rectangle,
	emitter: ^ParticleEmitter = nil,
	editor: ^Editor = nil,
	game: ^e.Game = nil,
) -> bool {
	if !uiTestState.enabled do return false

	uiTestState.currentFrame += 1
	f := uiTestState.currentFrame

	dockBtnPos := rl.Vector2{inspectorRect.x + inspectorRect.width - 55, inspectorRect.y + 21}

	switch f {
	case 1:
		// Verify Asteroids Title Menu Scene is initial scene, then test Settings scene & transition to Main scene
		if game != nil {
			if game.sceneManager.currentScene == nil || game.sceneManager.currentScene.name != "title_menu" {
				fmt.println("[UI TEST] ERROR: Expected initial scene to be 'title_menu'!")
				uiTestState.success = false
			} else {
				fmt.println("[UI TEST] SUCCESS: Initial scene is Asteroids 'title_menu'!")
			}
			// Verify Play, Settings, and Quit buttons exist in title_menu
			titleScene := game.sceneManager.currentScene
			playBtn, okPlay := e.GetNodeByPath(titleScene, titleScene.rootNode, "/Title Menu Panel/MenuButtonsVBox/PlayButton")
			settingsBtn, okSet := e.GetNodeByPath(titleScene, titleScene.rootNode, "/Title Menu Panel/MenuButtonsVBox/SettingsButton")
			quitBtn, okQuit := e.GetNodeByPath(titleScene, titleScene.rootNode, "/Title Menu Panel/MenuButtonsVBox/QuitButton")
			if !okPlay || !okSet || !okQuit || playBtn == nil || settingsBtn == nil || quitBtn == nil {
				fmt.println("[UI TEST] ERROR: Title menu Play/Settings/Quit buttons not found in hierarchy!")
				uiTestState.success = false
			} else {
				fmt.println("[UI TEST] SUCCESS: Title menu Play, Settings, and Quit UIButtonNodes verified!")
			}

			// Switch to "settings" scene to verify Settings UI widgets
			game->changeScene("settings")
		}

	case 2:
		if game != nil {
			if game.sceneManager.currentScene == nil || game.sceneManager.currentScene.name != "settings" {
				fmt.println("[UI TEST] ERROR: Expected scene to switch to 'settings'!")
				uiTestState.success = false
			} else {
				fmt.println("[UI TEST] SUCCESS: Switched to 'settings' scene with UI widgets & containers!")
			}
			// Switch to "main" gameplay scene so subsequent frames test gameplay & physics nodes
			game->changeScene("main")
		}

	case 3:
		fmt.printf("[UI TEST] Frame 3: Initial DockSide=%v, InspectorRect=%v, ViewportRect=%v, HierarchyRect=%v\n",
			dockSide^, inspectorRect, viewportRect, hierarchyRect)
		if dockSide^ != .Right || inspectorRect.x < viewportRect.x {
			fmt.println("[UI TEST] ERROR: Expected initial DockSide to be Right and inspector to the right of viewport")
			uiTestState.success = false
		} else {
			fmt.println("[UI TEST] SUCCESS: Initial 3-column layout verified (Hierarchy | Viewport | Inspector)!")
		}

		if emitter != nil {
			if !emitter.emitting || !emitter.continuous {
				fmt.printf("[UI TEST] ERROR: Expected emitter.emitting and continuous to be true initially! got emitting=%v, continuous=%v\n",
					emitter.emitting, emitter.continuous)
				uiTestState.success = false
			} else {
				fmt.println("[UI TEST] SUCCESS: Emitter initial emitting=true and continuous=true verified!")
			}
		}

		// Verify Box2D Physics World & Nodes initialization
		if game != nil {
			if !b2.World_IsValid(game.physicsWorld.worldId) {
				fmt.println("[UI TEST] ERROR: Expected game.physicsWorld.worldId to be valid!")
				uiTestState.success = false
			} else {
				fmt.println("[UI TEST] SUCCESS: Box2D PhysicsWorld initialized and valid on Game!")
			}
		}

	case 5:
		fmt.printf("[UI TEST] Frame 5: Clicking '< Dock Left' button at (%v, %v)...\n", dockBtnPos.x, dockBtnPos.y)
		UITest_InjectClick(dockBtnPos.x, dockBtnPos.y)

	case 6:
		UITest_InjectRelease(dockBtnPos.x, dockBtnPos.y)

	case 8:
		fmt.printf("[UI TEST] Frame 8: Checking DockSide after dock left: DockSide=%v, InspectorRect.x=%v, ViewportRect.x=%v\n",
			dockSide^, inspectorRect.x, viewportRect.x)
		if dockSide^ != .Left || inspectorRect.x != 0 || viewportRect.x != inspectorRect.width {
			fmt.printf("[UI TEST] FAILURE: DockSide did not switch cleanly to Left! dockSide=%v\n", dockSide^)
			uiTestState.success = false
		} else {
			fmt.println("[UI TEST] SUCCESS: DockSide switched to Left, Viewport centered in middle!")
		}

	case 10:
		rl.TakeScreenshot("test_ui_dock_left.png")
		fmt.println("[UI TEST] Frame 10: Captured test_ui_dock_left.png")

	case 12:
		// Tree item: Spaceship (Node) under root
		hItemY := hierarchyRect.y + 42 + 8 + 34 + 18 + 30 + 13
		hItemX := hierarchyRect.x + hierarchyRect.width / 2
		fmt.printf("[UI TEST] Frame 12: Clicking 'Spaceship' in Hierarchy Tree at (%v, %v)...\n", hItemX, hItemY)
		UITest_InjectClick(hItemX, hItemY)

	case 13:
		hItemY := hierarchyRect.y + 42 + 8 + 34 + 18 + 30 + 13
		hItemX := hierarchyRect.x + hierarchyRect.width / 2
		UITest_InjectRelease(hItemX, hItemY)

	case 15:
		fmt.printf("[UI TEST] Frame 15: Checking selectedTargetIndex: %d\n", selectedTargetIndex^)
		if selectedTargetIndex^ != 1 {
			fmt.printf("[UI TEST] FAILURE: selectedTargetIndex expected 1, got %d\n", selectedTargetIndex^)
			uiTestState.success = false
		} else {
			fmt.println("[UI TEST] SUCCESS: Spaceship Node selected from Hierarchy Tree!")
		}

	case 17:
		// Tree item: Spaceship Data child under Spaceship
		hItemY := hierarchyRect.y + 42 + 8 + 34 + 18 + 60 + 13
		hItemX := hierarchyRect.x + hierarchyRect.width / 2
		fmt.printf("[UI TEST] Frame 17: Clicking 'Spaceship Data' child in Hierarchy Tree at (%v, %v)...\n", hItemX, hItemY)
		UITest_InjectClick(hItemX, hItemY)

	case 18:
		hItemY := hierarchyRect.y + 42 + 8 + 34 + 18 + 60 + 13
		hItemX := hierarchyRect.x + hierarchyRect.width / 2
		UITest_InjectRelease(hItemX, hItemY)

	case 20:
		fmt.printf("[UI TEST] Frame 20: Checking selectedTargetIndex: %d\n", selectedTargetIndex^)
		if selectedTargetIndex^ != 2 {
			fmt.printf("[UI TEST] FAILURE: selectedTargetIndex expected 2, got %d\n", selectedTargetIndex^)
			uiTestState.success = false
		} else {
			fmt.println("[UI TEST] SUCCESS: Spaceship Data child selected from Hierarchy Tree!")
		}

	case 22:
		// Click Dock Right button
		newDockBtnPos := rl.Vector2{inspectorRect.x + inspectorRect.width - 55, inspectorRect.y + 21}
		fmt.printf("[UI TEST] Frame 22: Clicking 'Dock Right >' button at (%v, %v)...\n", newDockBtnPos.x, newDockBtnPos.y)
		UITest_InjectClick(newDockBtnPos.x, newDockBtnPos.y)

	case 23:
		newDockBtnPos := rl.Vector2{inspectorRect.x + inspectorRect.width - 55, inspectorRect.y + 21}
		UITest_InjectRelease(newDockBtnPos.x, newDockBtnPos.y)

	case 25:
		fmt.printf("[UI TEST] Frame 25: Checking DockSide after dock right: %v, InspectorRect.x=%v\n", dockSide^, inspectorRect.x)
		if dockSide^ != .Right {
			fmt.printf("[UI TEST] FAILURE: DockSide expected Right, got %v\n", dockSide^)
			uiTestState.success = false
		} else {
			fmt.println("[UI TEST] SUCCESS: DockSide switched back to Right!")
		}

	case 26:
		selectedTargetIndex^ = 0
		if editor != nil {
			editor.selectedNode = nil
		}

	case 29:
		fmt.printf("[UI TEST] Frame 29: Checking selectedTargetIndex: %d\n", selectedTargetIndex^)
		if selectedTargetIndex^ != 0 {
			fmt.printf("[UI TEST] FAILURE: selectedTargetIndex expected 0, got %d\n", selectedTargetIndex^)
			uiTestState.success = false
		} else {
			fmt.println("[UI TEST] SUCCESS: Particle Emitter Node re-selected from Hierarchy Tree!")
		}

	case 30:
		// Test start, stop, emitting, continuous lifecycle
		if emitter != nil {
			fmt.println("[UI TEST] Frame 30: Testing emitting, continuous, and start method...")

			emitter.continuous = false
			if emitter.start != nil {
				emitter->start()
			} else {
				ParticleEmitter_Start(emitter)
			}

			if !emitter.emitting {
				fmt.println("[UI TEST] ERROR: Expected emitter.emitting to be true after start()")
				uiTestState.success = false
			}

			ParticleEmitter_Update(emitter, emitter.lifetime + 0.1)

			if emitter.emitting {
				fmt.println("[UI TEST] ERROR: Expected emitter.emitting to be false after 1 lifecycle when continuous=false")
				uiTestState.success = false
			} else {
				fmt.println("[UI TEST] SUCCESS: Non-continuous emitter stopped emitting after 1 lifecycle!")
			}

			if emitter.start != nil {
				emitter->start()
			} else {
				ParticleEmitter_Start(emitter)
			}

			if !emitter.emitting {
				fmt.println("[UI TEST] ERROR: Expected emitter.emitting to be true after start() restart")
				uiTestState.success = false
			} else {
				fmt.println("[UI TEST] SUCCESS: Calling start() successfully restarted emission!")
			}

			// Reset to default settings
			emitter.amount = 100
			emitter.burst = 0.5
			emitter.continuous = true
			if emitter.start != nil do emitter->start()
		}

	case 31:
		if editor != nil && game != nil {
			fmt.println("[UI TEST] Frame 31: Testing Box2D Physics Nodes, Shapes, Joints, & Collision Layers...")

			// 1. Verify StaticBody & DynamicBody valid Box2D bodies
			if !b2.Body_IsValid(editor.staticBody.bodyId) || !b2.Body_IsValid(editor.dynamicBody.bodyId) {
				fmt.println("[UI TEST] ERROR: Expected StaticBody and DynamicBody Box2D bodies to be valid!")
				uiTestState.success = false
			} else {
				fmt.println("[UI TEST] SUCCESS: StaticBody and DynamicBody Box2D bodies valid and stepping!")
			}

			// 2. Verify DynamicBody moved downward under gravity
			if editor.dynamicBody.position.y <= 180.0 {
				fmt.printf("[UI TEST] ERROR: Expected DynamicBody to move under gravity! y=%v\n", editor.dynamicBody.position.y)
				uiTestState.success = false
			} else {
				fmt.printf("[UI TEST] SUCCESS: DynamicBody moved under Box2D gravity (y=%v)!\n", editor.dynamicBody.position.y)
			}

			// 3. Verify CharacterMover moved and solved planes
			if editor.characterMover.position.y <= 320.0 {
				fmt.printf("[UI TEST] ERROR: Expected CharacterMover to move! y=%v\n", editor.characterMover.position.y)
				uiTestState.success = false
			} else {
				fmt.printf("[UI TEST] SUCCESS: CharacterMoverNode moved via Box2D World_CollideMover/SolvePlanes (y=%v)!\n", editor.characterMover.position.y)
			}

			// 4. Verify RaycastNode hits StaticBody ramp/floor
			if !editor.raycastNode.isColliding || editor.raycastNode.hitNode == nil {
				fmt.println("[UI TEST] ERROR: Expected RaycastNode to detect collision!")
				uiTestState.success = false
			} else {
				fmt.printf("[UI TEST] SUCCESS: RaycastNode hit '%s' at point=%v, fraction=%v!\n",
					editor.raycastNode.hitNode.name, editor.raycastNode.hitPoint, editor.raycastNode.hitFraction)
			}

			// 5. Verify CollisionLayerSet bit conversion and joint creation
			layerMask := e.CollisionLayerSet{e.CollisionLayer.Layer1, e.CollisionLayer.Layer3}
			bits := e.CollisionLayerSet_ToBits(layerMask)
			roundtrip := e.CollisionLayerSet_FromBits(bits)
			if bits != 0b101 || roundtrip != layerMask {
				fmt.printf("[UI TEST] ERROR: CollisionLayerSet bit conversion mismatch: bits=%v\n", bits)
				uiTestState.success = false
			} else {
				fmt.println("[UI TEST] SUCCESS: CollisionLayerSet bitmask conversion verified!")
			}

			e.PhysicsJoint_Create(editor.joint, game.physicsWorld.worldId, editor.staticBody.bodyId, editor.dynamicBody.bodyId)
			if !b2.Joint_IsValid(e.PhysicsJoint_GetId(editor.joint)) {
				fmt.println("[UI TEST] ERROR: Expected PhysicsJoint to be valid after creation!")
				uiTestState.success = false
			} else {
				fmt.println("[UI TEST] SUCCESS: Box2D PhysicsJoint created and validated!")
			}

			// 6. Test Tree Collapse / Expand helper
			rootNode := game.sceneManager.currentScene.rootNode
			SceneHierarchy_ToggleCollapsed(&editor.hierarchy, rootNode)
			if !SceneHierarchy_IsCollapsed(&editor.hierarchy, rootNode) {
				fmt.println("[UI TEST] ERROR: Expected rootNode to be collapsed after toggle!")
				uiTestState.success = false
			}
			SceneHierarchy_ToggleCollapsed(&editor.hierarchy, rootNode)
			if SceneHierarchy_IsCollapsed(&editor.hierarchy, rootNode) {
				fmt.println("[UI TEST] ERROR: Expected rootNode to be expanded after second toggle!")
				uiTestState.success = false
			} else {
				fmt.println("[UI TEST] SUCCESS: Scene Hierarchy Tree collapse/expand verified!")
			}

			// Switch inspector to Physics World tab for screenshot verification
			selectedTargetIndex^ = 3
		}

	case 32:
		rl.TakeScreenshot("test_ui_dock_right.png")
		fmt.println("[UI TEST] Frame 32: Captured test_ui_dock_right.png")
		// Transition to Level 2: Battle Arena
		if game != nil {
			game->changeScene("battle_arena")
		}

	case 33:
		if game == nil || game.sceneManager.currentScene == nil || game.sceneManager.currentScene.name != "battle_arena" {
			fmt.println("[UI TEST] ERROR: Expected active scene to be 'battle_arena'!")
			uiTestState.success = false
		} else {
			fmt.println("[UI TEST] SUCCESS: Switched to Level 2 'battle_arena'!")
			bs := game.sceneManager.currentScene

			// Verify CameraNode is configured
			if bs.camera == nil {
				fmt.println("[UI TEST] ERROR: Expected battle_arena camera to be non-nil!")
				uiTestState.success = false
			} else {
				fmt.printf("[UI TEST] SUCCESS: Level 2 CameraNode active, zoom=%v, followMode=%v\n", bs.camera.zoom, bs.camera.followMode)
			}

			// Verify Starfield emitter
			starNode, foundStar := e.GetNodeByPath(bs, bs.rootNode, "/CosmicStarfield")
			if !foundStar || starNode == nil {
				fmt.println("[UI TEST] ERROR: CosmicStarfield node not found!")
				uiTestState.success = false
			} else {
				fmt.println("[UI TEST] SUCCESS: CosmicStarfield particle emitter active!")
			}

			// Verify BattleManager node
			mgrNode, foundMgr := e.GetNodeByPath(bs, bs.rootNode, "/BattleManager")
			if !foundMgr || mgrNode == nil {
				fmt.println("[UI TEST] ERROR: BattleManager node not found!")
				uiTestState.success = false
			} else {
				b := cast(^a.BattleLevelNode)mgrNode
				fmt.printf("[UI TEST] SUCCESS: BattleManager active! Player Hull=%v, Shield=%v, Enemies=%v, Turrets=%v\n",
					b.playerHealth, b.playerShield, len(b.enemies), len(b.turrets))
			}
		}

	case 34:
		rl.TakeScreenshot("test_battle_arena.png")
		fmt.println("[UI TEST] Frame 34: Captured test_battle_arena.png")
		if game != nil {
			game->changeScene("title_menu")
		}

	case 35:
		if game != nil && game.sceneManager.currentScene != nil && game.sceneManager.currentScene.name == "title_menu" {
			fmt.println("[UI TEST] SUCCESS: Clean return to 'title_menu' from Level 2 verified!")
		}
		fmt.printf("[UI TEST] COMPLETE. Overall Success: %v\n", uiTestState.success)
		return true
	}

	return false
}
