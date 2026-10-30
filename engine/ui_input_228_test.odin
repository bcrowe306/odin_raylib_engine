package engine

import "core:testing"
import rl "vendor:raylib"

// #228: a hidden button isn't clickable or focusable; a widget with the
// mouse blocks gameplay mouse input; lists / tables / faders are focusable;
// a widget drawn in the world reads the mouse through the camera; picking a
// dropdown item with Enter doesn't open it again.
@(test)
test_ui_input_hidden_mouse_focus_world_dropdown :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	game.uiTestInputEnabled = true
	scene := game->createScene("ui228", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	layer := ScreenLayerNode_Create(scene, "HUD")
	clicks := 0
	btn := UIButtonNode_Create(scene, "Btn", "Go", {200, 36}, layer)
	btn.position = {100, 100}
	btn.onClick->subscribe(proc(source: rawptr, val: EventValue, ctx: ^GameContext, ud: rawptr) {(cast(^int)ud)^ += 1}, &clicks)
	tbl := UITableNode_Create(scene, "Tbl", parent = layer)
	tbl.position = {400, 300}
	dd := UIDropdownNode_Create(scene, "Dd", "Pick", {"A", "B", "C"}, 0, layer)
	dd.position = {600, 100}
	game->run(0.016)

	click :: proc(game: ^Game, at: [2]f32) {
		game.uiTestMousePos = at
		game.uiTestMousePressed, game.uiTestMouseDown = true, true
		game->run(0.016)
		game.uiTestMousePressed, game.uiTestMouseDown, game.uiTestMouseReleased = false, false, true
		game->run(0.016)
		game.uiTestMouseReleased = false
	}
	r := UI_GetElementRect(&btn.ui)
	at := [2]f32{r.x + 20, r.y + 10}
	click(game, at)
	testing.expect_value(t, clicks, 1)
	// The button has the mouse: gameplay mouse input skips it.
	testing.expect(t, Game_UIHasMouse(game), "the UI has the mouse")
	game->run(0.016)
	testing.expect(t, game.input.mouseBlocked, "mouse-bound actions are blocked")

	// Hidden: not clickable, not focusable.
	btn.renderable = false
	click(game, at)
	testing.expect_value(t, clicks, 1)
	testing.expect(t, !UI_IsFocusable(&btn.ui), "a hidden button isn't focusable")
	btn.renderable = true
	game.uiTestMousePos = {5, 700} // (off the UI)
	game->run(0.016)
	game->run(0.016)
	testing.expect(t, !Game_UIHasMouse(game) && !game.input.mouseBlocked, "off the UI: gameplay has the mouse")

	// Tables, lists, faders and notched sliders take focus (their keys work).
	testing.expect(t, UI_IsFocusable(&tbl.ui), "a table is focusable")

	// Picking with Enter closes the dropdown (it used to open again).
	UI_SetFocus(scene, &dd.ui)
	game->run(0.016)
	game.uiTestKeyEnter = true
	game->run(0.016)
	game.uiTestKeyEnter = false
	testing.expect(t, dd.isOpen, "Enter opens it")
	game.uiTestKeyDown = true
	game->run(0.016)
	game.uiTestKeyDown = false
	game.uiTestKeyEnter = true
	game->run(0.016)
	game.uiTestKeyEnter = false
	testing.expect(t, !dd.isOpen, "Enter picks and closes it")
	testing.expect_value(t, dd.selectedIndex, dd.hoveredItemIndex) // (the highlighted item)

	// In the world (not under a Screen Layer): the mouse goes through the camera.
	cam := CameraNode_Create(scene, "Cam", true)
	cam.targetPosition, cam.currentPosition, cam.zoom, cam.currentZoom, cam.targetZoom = {0, 0}, {0, 0}, 2, 2, 2
	cam.smoothDrag = false
	wbtn := UIButtonNode_Create(scene, "World", "W", {100, 40})
	wbtn.position = {50, 50}
	wclicks := 0
	wbtn.onClick->subscribe(proc(source: rawptr, val: EventValue, ctx: ^GameContext, ud: rawptr) {(cast(^int)ud)^ += 1}, &wclicks)
	game->run(0.016)
	testing.expect(t, wbtn.layer in cam.targetLayers, "the camera shows the button's layer")
	{
		c2d := CameraNode_GetCamera2D(cam, game.virtualSize[0], game.virtualSize[1])
		wr := UI_GetElementRect(&wbtn.ui)
		screen := rl.GetWorldToScreen2D({wr.x + 10, wr.y + 10}, c2d)
		click(game, screen)
		testing.expectf(t, wclicks == 1, "a world button clicks where it's drawn (screen %v)", screen)
	}
}
