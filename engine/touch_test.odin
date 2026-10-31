package engine

import "core:strings"
import "core:testing"
import lua "lua54"

// #276: fingers - a tap clicks a UI button (touch as mouse), double tap,
// long press, swipe, pinch; a Touch Joystick and a Touch Button press
// input actions with their own fingers (not the mouse, no gestures); the
// controls show once the device is touched; the Lua API.
@(test)
test_touch_input :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("touch", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	ctx := &game.gameContext
	input := &game.input
	frame :: proc(game: ^Game, n := 1) {for _ in 0 ..< n do game->run(1.0 / 60)}
	finger :: proc(game: ^Game, id: i32, pos: [2]f32, down: bool) {Input_SimulateTouch(&game.input, id, pos, down)}

	// A tap on a button clicks it (the finger is the mouse).
	btn := UIButtonNode_Create(scene, "Btn", "OK", {200, 60})
	btn.position = {100, 100}
	clicks := 0
	btn.onClick->subscribe(proc(src: rawptr, v: EventValue, ctx: ^GameContext, ud: rawptr) {(cast(^int)ud)^ += 1}, &clicks)
	ProcessNodeQueues(scene.manager, ctx)
	frame(game)
	finger(game, 1, {150, 120}, true)
	frame(game)
	testing.expect(t, game.touchMouse.active && game.touchMouse.down, "the finger is the mouse")
	tapped := false
	finger(game, 1, {150, 120}, false)
	frame(game)
	if p, ok := input.touch.gestures.tap.?; ok do tapped = p == {150, 120}
	testing.expect(t, tapped, "a tap")
	frame(game, 2)
	testing.expect_value(t, clicks, 1)
	testing.expect(t, !game.touchMouse.active, "no finger: the real mouse")
	testing.expect(t, input.touch.everTouched, "the device was touched")

	// A second tap there: a double tap.
	finger(game, 1, {152, 122}, true); frame(game)
	finger(game, 1, {152, 122}, false); frame(game)
	testing.expect(t, input.touch.gestures.doubleTap != nil, "double tap")

	// Long press: still for over half a second.
	finger(game, 2, {600, 400}, true)
	frame(game, 40)
	finger(game, 2, {600, 400}, false); frame(game)
	frame(game)
	longs := 0
	// (it fired once, while held: replay to count)
	finger(game, 3, {600, 400}, true)
	for _ in 0 ..< 40 {
		frame(game)
		if input.touch.gestures.longPress != nil do longs += 1
	}
	finger(game, 3, {600, 400}, false); frame(game)
	testing.expect_value(t, longs, 1)
	testing.expect(t, input.touch.gestures.tap == nil, "a long press isn't a tap")

	// Swipe: quickly to the right.
	finger(game, 4, {300, 500}, true); frame(game)
	finger(game, 4, {420, 505}, true); frame(game)
	finger(game, 4, {520, 505}, true); frame(game)
	finger(game, 4, {520, 505}, false); frame(game)
	s, swiped := input.touch.gestures.swipe.?
	testing.expect(t, swiped && s.x > 0.95 && s.z > 1000, "a swipe right")

	// Pinch: two fingers moving apart.
	finger(game, 5, {500, 300}, true)
	finger(game, 6, {600, 300}, true)
	frame(game, 2)
	finger(game, 5, {450, 300}, true)
	finger(game, 6, {650, 300}, true)
	frame(game)
	testing.expect(t, input.touch.gestures.pinching && input.touch.gestures.pinchScale > 1.9, "pinch out")
	finger(game, 5, {450, 300}, false)
	finger(game, 6, {650, 300}, false)
	frame(game, 2)
	testing.expect(t, input.touch.gestures.tap == nil, "a pinch's fingers make no tap")

	// A joystick: its finger pushes move_right, isn't the mouse.
	joy := TouchJoystickNode_Create(scene, "Stick")
	joy.position = {200, 600}
	jump := TouchButtonNode_Create(scene, "Jump")
	jump.position = {1100, 600}
	Input_DefineAction(input, "fire", {})
	fire := TouchButtonNode_Create(scene, "Fire")
	fire.position = {1000, 600}
	fire.action = strings.clone("fire", fire.allocator)
	ProcessNodeQueues(scene.manager, ctx)
	frame(game)
	finger(game, 7, {205, 600}, true); frame(game)
	finger(game, 7, {275, 600}, true); frame(game) // (70 px: a full push)
	testing.expect(t, input.states[.MoveRight].down, "joystick right")
	testing.expect(t, input.states[.MoveRight].value > 0.99 && input.states[.MoveLeft].value == 0, "full strength")
	testing.expect(t, joy.vector.x > 0.99, "its vector")
	testing.expect(t, !game.touchMouse.active, "a control's finger isn't the mouse")
	// ...and a button with another finger at the same time.
	finger(game, 8, {1100, 610}, true); frame(game)
	testing.expect(t, input.states[.Jump].pressed && jump.down, "jump pressed")
	finger(game, 9, {1000, 600}, true); frame(game)
	st, _ := Input_ActionStateByName(input, "fire")
	testing.expect(t, st.down, "a project action")
	finger(game, 7, {275, 600}, false)
	finger(game, 8, {1100, 610}, false)
	finger(game, 9, {1000, 600}, false)
	frame(game)
	testing.expect(t, !input.states[.MoveRight].down && input.states[.Jump].released, "let go")
	testing.expect(t, input.touch.gestures.tap == nil, "control fingers make no gestures")

	// Touch as mouse off: fingers aren't the mouse.
	input.touch.asMouse = false
	finger(game, 1, {150, 120}, true); frame(game)
	testing.expect(t, !game.touchMouse.active, "touch as mouse off")
	finger(game, 1, {150, 120}, false); frame(game)
	input.touch.asMouse = true

	// Lua: the touches, the gestures, on_swipe, the controls.
	L := game.scriptManager.L
	finger(game, 1, {10, 20}, true); frame(game)
	run :: proc(t: ^testing.T, L: ^lua.State, code: cstring) {
		if lua.L_dostring(L, code) != 0 do testing.fail_now(t, strings.clone(string(lua.tostring(L, -1)), context.temp_allocator))
	}
	run(t, L, `local ts = Input.get_touches(); n = #ts; tx = ts[1].x; dev = Input.is_touch_device()
		sv = Scene.find_node("Stick"):touch_get_vector()`)
	lua.getglobal(L, "n"); testing.expect_value(t, int(lua.tointeger(L, -1)), 1); lua.pop(L, 1)
	lua.getglobal(L, "tx"); testing.expect_value(t, f32(lua.tonumber(L, -1)), 10); lua.pop(L, 1)
	lua.getglobal(L, "dev"); testing.expect(t, bool(lua.toboolean(L, -1)), "is_touch_device"); lua.pop(L, 1)
	finger(game, 1, {10, 20}, false); frame(game)
	free_all(context.temp_allocator)
}
