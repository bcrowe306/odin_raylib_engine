package main

import "core:fmt"
import "core:os"
import rl "vendor:raylib"

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
) -> bool {
	if !uiTestState.enabled do return false

	uiTestState.currentFrame += 1
	f := uiTestState.currentFrame

	dockBtnPos := rl.Vector2{inspectorRect.x + inspectorRect.width - 55, inspectorRect.y + 21}

	switch f {
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
		// Hierarchy item 1: Spaceship (Node)
		hItemY := hierarchyRect.y + 42 + 10 + 36 / 2
		hItemX := hierarchyRect.x + hierarchyRect.width / 2
		fmt.printf("[UI TEST] Frame 12: Clicking 'Spaceship Node' in Hierarchy at (%v, %v)...\n", hItemX, hItemY + 36)
		UITest_InjectClick(hItemX, hItemY + 36)

	case 13:
		hItemY := hierarchyRect.y + 42 + 10 + 36 / 2
		hItemX := hierarchyRect.x + hierarchyRect.width / 2
		UITest_InjectRelease(hItemX, hItemY + 36)

	case 15:
		fmt.printf("[UI TEST] Frame 15: Checking selectedTargetIndex: %d\n", selectedTargetIndex^)
		if selectedTargetIndex^ != 1 {
			fmt.printf("[UI TEST] FAILURE: selectedTargetIndex expected 1, got %d\n", selectedTargetIndex^)
			uiTestState.success = false
		} else {
			fmt.println("[UI TEST] SUCCESS: Spaceship Node selected from Hierarchy!")
		}

	case 17:
		// Hierarchy item 2: Spaceship Data
		hItemY := hierarchyRect.y + 42 + 10 + 36 / 2
		hItemX := hierarchyRect.x + hierarchyRect.width / 2
		fmt.printf("[UI TEST] Frame 17: Clicking 'Spaceship Data' in Hierarchy at (%v, %v)...\n", hItemX, hItemY + 72)
		UITest_InjectClick(hItemX, hItemY + 72)

	case 18:
		hItemY := hierarchyRect.y + 42 + 10 + 36 / 2
		hItemX := hierarchyRect.x + hierarchyRect.width / 2
		UITest_InjectRelease(hItemX, hItemY + 72)

	case 20:
		fmt.printf("[UI TEST] Frame 20: Checking selectedTargetIndex: %d\n", selectedTargetIndex^)
		if selectedTargetIndex^ != 2 {
			fmt.printf("[UI TEST] FAILURE: selectedTargetIndex expected 2, got %d\n", selectedTargetIndex^)
			uiTestState.success = false
		} else {
			fmt.println("[UI TEST] SUCCESS: Spaceship Data selected from Hierarchy!")
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
		// Click Particle Emitter item in Hierarchy (item 0)
		hItemY := hierarchyRect.y + 42 + 10 + 36 / 2
		hItemX := hierarchyRect.x + hierarchyRect.width / 2
		fmt.printf("[UI TEST] Frame 26: Clicking 'Particle Emitter Node' in Hierarchy at (%v, %v)...\n", hItemX, hItemY)
		UITest_InjectClick(hItemX, hItemY)

	case 27:
		hItemY := hierarchyRect.y + 42 + 10 + 36 / 2
		hItemX := hierarchyRect.x + hierarchyRect.width / 2
		UITest_InjectRelease(hItemX, hItemY)

	case 29:
		fmt.printf("[UI TEST] Frame 29: Checking selectedTargetIndex: %d\n", selectedTargetIndex^)
		if selectedTargetIndex^ != 0 {
			fmt.printf("[UI TEST] FAILURE: selectedTargetIndex expected 0, got %d\n", selectedTargetIndex^)
			uiTestState.success = false
		} else {
			fmt.println("[UI TEST] SUCCESS: Particle Emitter Node re-selected from Hierarchy!")
		}

	case 30:
		// Test start, stop, emitting, continuous lifecycle
		if emitter != nil {
			fmt.println("[UI TEST] Frame 30: Testing emitting, continuous, and start method...")

			// 1. Test continuous = false stops after 1 lifecycle
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

			// Simulate lifecycle completion (advance by full lifetime)
			ParticleEmitter_Update(emitter, emitter.lifetime + 0.1)

			if emitter.emitting {
				fmt.println("[UI TEST] ERROR: Expected emitter.emitting to be false after 1 lifecycle when continuous=false")
				uiTestState.success = false
			} else {
				fmt.println("[UI TEST] SUCCESS: Non-continuous emitter stopped emitting after 1 lifecycle!")
			}

			// 2. Call start() again to restart
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

			// 3. Test burst = 1: all amount particles emitted simultaneously
			emitter.amount = 25
			emitter.lifetime = 2.0
			emitter.burst = 1.0
			emitter.continuous = true
			if emitter.start != nil do emitter->start()
			ParticleEmitter_Update(emitter, 0.016)
			if emitter.emittedInCycle != 25 {
				fmt.println("[UI TEST] ERROR: Expected 25 particles emitted at burst=1, got", emitter.emittedInCycle)
				uiTestState.success = false
			} else {
				fmt.println("[UI TEST] SUCCESS: Burst=1 emitted all particles simultaneously!")
			}

			// Advance time within same lifecycle: verify no more particles are emitted
			ParticleEmitter_Update(emitter, 1.0)
			if emitter.emittedInCycle != 25 {
				fmt.println("[UI TEST] ERROR: Expected emittedInCycle to stay 25 during cycle, got", emitter.emittedInCycle)
				uiTestState.success = false
			} else {
				fmt.println("[UI TEST] SUCCESS: No additional particles emitted once amount reached in lifecycle!")
			}

			// Advance past lifetime in continuous mode: verify new cycle starts and emits again
			ParticleEmitter_Update(emitter, 1.1)
			if emitter.emittedInCycle != 25 {
				fmt.println("[UI TEST] ERROR: Expected next lifecycle in continuous mode to burst 25 particles, got", emitter.emittedInCycle)
				uiTestState.success = false
			} else {
				fmt.println("[UI TEST] SUCCESS: Continuous mode restarted emitting in next lifecycle!")
			}

			// 4. Test burst = 0: particles emitted evenly across lifecycle
			emitter.amount = 10
			emitter.lifetime = 2.0
			emitter.burst = 0.0
			if emitter.start != nil do emitter->start()
			ParticleEmitter_Update(emitter, 0.016)
			if emitter.emittedInCycle != 1 {
				fmt.println("[UI TEST] ERROR: Expected 1 initial particle at start for burst=0, got", emitter.emittedInCycle)
				uiTestState.success = false
			} else {
				fmt.println("[UI TEST] SUCCESS: Burst=0 begins even emission at start of cycle!")
			}

			// Reset to default settings
			emitter.amount = 100
			emitter.burst = 0.5
			emitter.continuous = true
			if emitter.start != nil do emitter->start()
		}

	case 32:
		rl.TakeScreenshot("test_ui_dock_right.png")
		fmt.println("[UI TEST] Frame 32: Captured test_ui_dock_right.png")
		fmt.printf("[UI TEST] COMPLETE. Overall Success: %v\n", uiTestState.success)
		return true
	}

	return false
}
