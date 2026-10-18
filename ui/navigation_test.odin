package ui

import "core:testing"
import rl "vendor:raylib"

@test
test_ui_nav_cycle :: proc(t: ^testing.T) {
	// Test empty or single-item cycle
	testing.expect_value(t, NavCycle(0, 0, true), -1)
	testing.expect_value(t, NavCycle(1, 0, true), 0)
	testing.expect_value(t, NavCycle(1, 0, false), 0)

	// Test forward cycle across 4 elements: 0 -> 1 -> 2 -> 3 -> 0
	count := 4
	testing.expect_value(t, NavCycle(count, 0, true), 1)
	testing.expect_value(t, NavCycle(count, 1, true), 2)
	testing.expect_value(t, NavCycle(count, 2, true), 3)
	testing.expect_value(t, NavCycle(count, 3, true), 0)

	// Test backward cycle across 4 elements: 0 -> 3 -> 2 -> 1 -> 0
	testing.expect_value(t, NavCycle(count, 0, false), 3)
	testing.expect_value(t, NavCycle(count, 3, false), 2)
	testing.expect_value(t, NavCycle(count, 2, false), 1)
	testing.expect_value(t, NavCycle(count, 1, false), 0)

	// Test unselected starting state (-1)
	testing.expect_value(t, NavCycle(count, -1, true), 0)
	testing.expect_value(t, NavCycle(count, -1, false), 3)
}

@test
test_ui_nav_key_mapping :: proc(t: ^testing.T) {
	// 1. Tab and Shift+Tab
	testing.expect_value(t, GetNavActionFromInput(NavKeyInput{tab = true, shift = false}), NavAction.Next)
	testing.expect_value(t, GetNavActionFromInput(NavKeyInput{tab = true, shift = true}), NavAction.Prev)

	// 2. Directional arrows
	testing.expect_value(t, GetNavActionFromInput(NavKeyInput{up = true}), NavAction.Up)
	testing.expect_value(t, GetNavActionFromInput(NavKeyInput{down = true}), NavAction.Down)
	testing.expect_value(t, GetNavActionFromInput(NavKeyInput{left = true}), NavAction.Left)
	testing.expect_value(t, GetNavActionFromInput(NavKeyInput{right = true}), NavAction.Right)

	// 3. Activation
	testing.expect_value(t, GetNavActionFromInput(NavKeyInput{enter = true}), NavAction.Activate)
	testing.expect_value(t, GetNavActionFromInput(NavKeyInput{space = true}), NavAction.Activate)

	// 4. Cancellation
	testing.expect_value(t, GetNavActionFromInput(NavKeyInput{escape = true}), NavAction.Cancel)
}

@test
test_ui_nav_spatial_2d :: proc(t: ^testing.T) {
	// Layout a 2x2 grid of buttons:
	// [0: Top-Left  {10, 10, 80, 30}]   [1: Top-Right   {120, 10, 80, 30}]
	// [2: Bottom-Left{10, 60, 80, 30}]  [3: Bottom-Right{120, 60, 80, 30}]
	candidates := []rl.Rectangle{
		{10, 10, 80, 30},   // 0
		{120, 10, 80, 30},  // 1
		{10, 60, 80, 30},   // 2
		{120, 60, 80, 30},  // 3
	}

	// From Top-Left (0): Right -> Top-Right (1), Down -> Bottom-Left (2)
	testing.expect_value(t, NavFindNextSpatial(candidates, 0, .Right), 1)
	testing.expect_value(t, NavFindNextSpatial(candidates, 0, .Down), 2)

	// From Top-Right (1): Left -> Top-Left (0), Down -> Bottom-Right (3)
	testing.expect_value(t, NavFindNextSpatial(candidates, 1, .Left), 0)
	testing.expect_value(t, NavFindNextSpatial(candidates, 1, .Down), 3)

	// From Bottom-Left (2): Up -> Top-Left (0), Right -> Bottom-Right (3)
	testing.expect_value(t, NavFindNextSpatial(candidates, 2, .Up), 0)
	testing.expect_value(t, NavFindNextSpatial(candidates, 2, .Right), 3)

	// From Bottom-Right (3): Up -> Top-Right (1), Left -> Bottom-Left (2)
	testing.expect_value(t, NavFindNextSpatial(candidates, 3, .Up), 1)
	testing.expect_value(t, NavFindNextSpatial(candidates, 3, .Left), 2)
}

@test
test_ui_immediate_nav_state :: proc(t: ^testing.T) {
	ImmediateNav_BeginFrame()

	keyA: uintptr = 1001
	keyB: uintptr = 1002
	keyC: uintptr = 1003

	rectA := rl.Rectangle{10, 10, 100, 30}
	rectB := rl.Rectangle{10, 50, 100, 30}
	rectC := rl.Rectangle{10, 90, 100, 30}

	ImmediateNav_RegisterFocusable(keyA, rectA)
	ImmediateNav_RegisterFocusable(keyB, rectB)
	ImmediateNav_RegisterFocusable(keyC, rectC)

	testing.expect_value(t, immediateNav.itemCount, 3)

	// Initially no focus
	ImmediateNav_ClearFocus()
	testing.expect(t, !ImmediateNav_IsFocused(keyA), "No key initially focused")

	// Set focus to keyA
	ImmediateNav_SetFocus(keyA)
	testing.expect(t, ImmediateNav_IsFocused(keyA), "KeyA should be focused")
	testing.expect(t, !ImmediateNav_IsFocused(keyB), "KeyB should not be focused")

	// Press Tab (Next) -> moves to keyB
	ImmediateNav_ProcessKeyInput(NavKeyInput{tab = true})
	testing.expect(t, ImmediateNav_IsFocused(keyB), "Tab should advance focus to KeyB")

	// Press Tab (Next) -> moves to keyC
	ImmediateNav_ProcessKeyInput(NavKeyInput{tab = true})
	testing.expect(t, ImmediateNav_IsFocused(keyC), "Tab should advance focus to KeyC")

	// Press Tab (Next) -> wraps to keyA
	ImmediateNav_ProcessKeyInput(NavKeyInput{tab = true})
	testing.expect(t, ImmediateNav_IsFocused(keyA), "Tab should wrap focus to KeyA")

	// Press Shift+Tab (Prev) -> wraps backward to keyC
	ImmediateNav_ProcessKeyInput(NavKeyInput{tab = true, shift = true})
	testing.expect(t, ImmediateNav_IsFocused(keyC), "Shift+Tab should cycle backward to KeyC")

	// Press Up arrow from keyC -> moves to keyB spatially
	ImmediateNav_ProcessKeyInput(NavKeyInput{up = true})
	testing.expect(t, ImmediateNav_IsFocused(keyB), "Up arrow should navigate spatially to KeyB")

	// Press Down arrow from keyB -> moves to keyC spatially
	ImmediateNav_ProcessKeyInput(NavKeyInput{down = true})
	testing.expect(t, ImmediateNav_IsFocused(keyC), "Down arrow should navigate spatially to KeyC")

	// Press Escape -> clears focus
	ImmediateNav_ProcessKeyInput(NavKeyInput{escape = true})
	testing.expect(t, !ImmediateNav_IsFocused(keyC), "Escape should clear focus")
}
