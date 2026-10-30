package engine

import "core:math"
import "core:strings"
import "core:testing"
import lua "lua54"

@(test)
test_tweens_and_easing :: proc(t: ^testing.T) {
	// Easing curves: endpoints and shape.
	for e in Ease {
		if e == .Constant do continue
		testing.expectf(t, math.abs(Ease_Apply(e, 0)) < 0.001 && math.abs(Ease_Apply(e, 1) - 1) < 0.001, "%v endpoints", e)
	}
	testing.expect(t, Ease_Apply(.In_Quad, 0.5) == 0.25 && Ease_Apply(.Out_Quad, 0.5) == 0.75, "quad")
	testing.expect(t, Ease_Apply(.Out_Back, 0.6) > 1, "back overshoots")
	e, ok := Ease_Parse("in_out_sine")
	testing.expect(t, ok && e == .In_Out_Sine && Ease_Name(.Out_Bounce) == "out_bounce", "names")

	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("tw", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	n := Node_CreateByTypeName(scene, "TextureNode")
	n.name = "Box"
	n.position = {0, 0}
	n.gameContext = &game.gameContext
	game->run(0.001)

	// Odin: linear tween over 1s.
	id := Tween_To(&game.tweens, n, "position", {100, 50, 0, 0}, 1, .Linear)
	testing.expect(t, id > 0, "started")
	for _ in 0 ..< 5 do game->run(0.1)
	testing.expectf(t, math.abs(n.position.x - 50) < 1.5 && math.abs(n.position.y - 25) < 1, "half way: %v", n.position)
	for _ in 0 ..< 6 do game->run(0.1)
	testing.expectf(t, n.position == {100, 50}, "arrived: %v", n.position)
	testing.expect(t, !Tween_IsRunning(&game.tweens, id), "finished")

	// Lua: easing, delay, on_complete, colours 0..1, shader params, yoyo loops.
	L := game.scriptManager.L
	ok2 := lua.L_dostring(L, `
local b = Scene.find_node("Box")
done = 0
Tween.to(b, "rotation", 90, 0.2, "out_back", {delay = 0.1, on_complete = function(node) done = done + 1; finished_name = node:get_name() end})
Tween.to(b, "tint", {1, 0, 0}, 0.2, "linear")
b:set_shader("builtin:flash")
Tween.to(b, "shader:amount", 0, 0.2, "linear")
pulse = Tween.to(b, "scale", {2, 2}, 0.1, "linear", {loops = -1, yoyo = true})
eased = Tween.ease("in_quad", 0.5)
`) == 0
	testing.expect(t, ok2, "Lua ran")
	for _ in 0 ..< 5 do game->run(0.1)
	tn := cast(^TextureNode)n
	testing.expectf(t, math.abs(n.rotation - 90) < 0.01, "rotation tweened (after the delay): %v", n.rotation)
	testing.expectf(t, tn.tint == {255, 0, 0, 255}, "colour from 0..1: %v", tn.tint)
	amount, _, _ := Material_GetParam(n, "amount")
	testing.expectf(t, amount.x == 0, "shader param tweened: %v", amount)
	lua.getglobal(L, "done")
	testing.expect_value(t, int(lua.tointeger(L, -1)), 1)
	lua.getglobal(L, "finished_name")
	testing.expect_value(t, string(lua.tostring(L, -1)), "Box")
	lua.getglobal(L, "eased")
	testing.expect_value(t, f32(lua.tonumber(L, -1)), f32(0.25))
	lua.pop(L, 3)
	testing.expect_value(t, len(game.tweens.tweens), 1) // the looping pulse
	testing.expect(t, n.scale.x >= 1 && n.scale.x <= 2, "yoyo stays in range")

	// A destroyed node's tweens end.
	RemoveNode(scene.manager, n)
	game->run(0.1)
	game->run(0.1)
	testing.expect_value(t, len(game.tweens.tweens), 0)

	// Track keys keep their easing in saved files.
	key := Track_Key{time = 0, value = {0, 0, 0, 0}, ease = .Out_Quad}
	tr := Property_Track{keys = make([dynamic]Track_Key, context.temp_allocator)}
	append(&tr.keys, key, Track_Key{time = 10, value = {100, 0, 0, 0}})
	v, _ := Track_Sample(&tr, 5)
	testing.expect_value(t, v.x, f32(75))
	_ = strings.contains
}
