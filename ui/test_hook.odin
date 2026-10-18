package ui

import "core:fmt"
import "core:os"
import "core:strings"
import rl "vendor:raylib"

// ============================================================================
// UI Test & Event Injection Hook
// ============================================================================

UITestHook :: struct {
	enabled: bool,
	currentFrame: int,
	totalFrames: int,
	success: bool,
	checksPassed: int,
	checksFailed: int,
	screenshotDir: string,

	// Mouse injection overrides
	overrideMousePos: bool,
	mousePos: rl.Vector2,
	overrideMousePressed: bool,
	mousePressedButton: rl.MouseButton,
	overrideMouseDown: bool,
	mouseDownButton: rl.MouseButton,
	overrideMouseReleased: bool,
	mouseReleasedButton: rl.MouseButton,

	// Keyboard injection overrides
	overrideKey: bool,
	pressedKey: rl.KeyboardKey,
	downKey: rl.KeyboardKey,
	shiftDown: bool,
	overrideNavAction: NavAction,
}

testHook: UITestHook

TestHook_Init :: proc(screenshotDir: string = "ui_screenshots", totalFrames: int = 70) {
	testHook = UITestHook{
		enabled = true,
		currentFrame = 0,
		totalFrames = totalFrames,
		success = true,
		checksPassed = 0,
		checksFailed = 0,
		screenshotDir = screenshotDir,
	}
	if !os.exists(screenshotDir) {
		os.make_directory(screenshotDir)
	}
}

TestHook_ResetInput :: proc() {
	testHook.overrideMousePos = false
	testHook.overrideMousePressed = false
	testHook.overrideMouseDown = false
	testHook.overrideMouseReleased = false
	testHook.overrideKey = false
	testHook.pressedKey = .KEY_NULL
	testHook.downKey = .KEY_NULL
	testHook.shiftDown = false
	testHook.overrideNavAction = .None
}

TestHook_MouseMove :: proc(x, y: f32) {
	testHook.overrideMousePos = true
	testHook.mousePos = {x, y}
}

TestHook_MouseDown :: proc(x, y: f32, button: rl.MouseButton = .LEFT) {
	TestHook_MouseMove(x, y)
	testHook.overrideMouseDown = true
	testHook.mouseDownButton = button
}

TestHook_MouseRelease :: proc(x, y: f32, button: rl.MouseButton = .LEFT) {
	TestHook_MouseMove(x, y)
	testHook.overrideMouseDown = false
	testHook.overrideMouseReleased = true
	testHook.mouseReleasedButton = button
}

TestHook_MouseUp :: proc(x, y: f32, button: rl.MouseButton = .LEFT) {
	TestHook_MouseMove(x, y)
	testHook.overrideMouseDown = false
	testHook.overrideMouseReleased = true
	testHook.mouseReleasedButton = button
}

TestHook_MouseClick :: proc(x, y: f32, button: rl.MouseButton = .LEFT) {
	TestHook_MouseMove(x, y)
	testHook.overrideMousePressed = true
	testHook.mousePressedButton = button
	testHook.overrideMouseDown = true
	testHook.mouseDownButton = button
}

TestHook_KeyPress :: proc(key: rl.KeyboardKey, shift: bool = false) {
	testHook.overrideKey = true
	testHook.pressedKey = key
	testHook.downKey = key
	testHook.shiftDown = shift || testHook.shiftDown
}

TestHook_KeyDown :: proc(key: rl.KeyboardKey) {
	testHook.overrideKey = true
	testHook.downKey = key
	if key == .LEFT_SHIFT || key == .RIGHT_SHIFT {
		testHook.shiftDown = true
	}
}

TestHook_KeyUp :: proc(key: rl.KeyboardKey) {
	if testHook.downKey == key {
		testHook.downKey = .KEY_NULL
	}
	if key == .LEFT_SHIFT || key == .RIGHT_SHIFT {
		testHook.shiftDown = false
	}
}

TestHook_NavAction :: proc(action: NavAction) {
	testHook.overrideNavAction = action
}

TestHook_CaptureScreenshot :: proc(filename: string) {
	if !rl.IsWindowReady() do return
	path := fmt.tprintf("./%s/%s", testHook.screenshotDir, filename)
	img := rl.LoadImageFromScreen()
	defer rl.UnloadImage(img)
	rl.ExportImage(img, strings.clone_to_cstring(path, context.temp_allocator))
	fmt.printf("[UI TEST HOOK] Captured screenshot: %s\n", path)
}

TestHook_Assert :: proc(condition: bool, checkName: string) {
	if !condition {
		testHook.success = false
		testHook.checksFailed += 1
		fmt.printf("[UI TEST HOOK] [FAIL] %s\n", checkName)
	} else {
		testHook.checksPassed += 1
		fmt.printf("[UI TEST HOOK] [PASS] %s\n", checkName)
	}
}

// ----------------------------------------------------------------------------
// Unified Input Polling Procs (transparently hook into all UI widgets)
// ----------------------------------------------------------------------------

GetUIMousePosition :: proc() -> rl.Vector2 {
	if testHook.overrideMousePos {
		return testHook.mousePos
	}
	if !rl.IsWindowReady() do return {}
	return rl.GetMousePosition()
}

IsUIMouseButtonPressed :: proc(button: rl.MouseButton) -> bool {
	if testHook.overrideMousePressed {
		return testHook.mousePressedButton == button
	}
	if !rl.IsWindowReady() do return false
	return rl.IsMouseButtonPressed(button)
}

IsUIMouseButtonDown :: proc(button: rl.MouseButton) -> bool {
	if testHook.overrideMouseDown {
		return testHook.mouseDownButton == button
	}
	if !rl.IsWindowReady() do return false
	return rl.IsMouseButtonDown(button)
}

IsUIMouseButtonReleased :: proc(button: rl.MouseButton) -> bool {
	if testHook.overrideMouseReleased {
		return testHook.mouseReleasedButton == button
	}
	if !rl.IsWindowReady() do return false
	return rl.IsMouseButtonReleased(button)
}

IsUIKeyPressed :: proc(key: rl.KeyboardKey) -> bool {
	if testHook.overrideKey {
		return testHook.pressedKey == key
	}
	if !rl.IsWindowReady() do return false
	return rl.IsKeyPressed(key) || rl.IsKeyPressedRepeat(key)
}

IsUIKeyDown :: proc(key: rl.KeyboardKey) -> bool {
	if testHook.overrideKey {
		return testHook.downKey == key || (testHook.shiftDown && (key == .LEFT_SHIFT || key == .RIGHT_SHIFT))
	}
	if !rl.IsWindowReady() do return false
	return rl.IsKeyDown(key)
}
