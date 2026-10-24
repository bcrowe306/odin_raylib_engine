package engine

import "core:strings"
import "core:testing"
import lua "lua54"

@(test)
test_lighting_scene_lights_ambient_lua :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("lit", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	testing.expect(t, !Scene_HasLighting(scene), "no lights, white ambient: unlit")
	scene.ambient = {40, 46, 70, 255}
	testing.expect(t, Scene_HasLighting(scene), "dark ambient lights the scene")
	scene.ambient = {}

	l := cast(^LightNode)Node_CreateByTypeName(scene, "LightNode")
	l.name = "Lamp"
	l.kind = .Spot
	l.radius = 500
	l.spread = 20
	ProcessNodeQueues(scene.manager, &game.gameContext)
	testing.expect(t, Scene_HasLighting(scene), "a light lights the scene")

	// Lua.
	L := game.scriptManager.L
	ok := lua.L_dostring(L, `
Scene.set_ambient(0.2, 0.2, 0.3)
local lamp = Scene.find_node("Lamp")
lamp:light_set_color(1, 0.5, 0)
lamp:light_set_energy(2.5)
lamp:light_set_radius(320)
local r, g, b = Scene.get_ambient()
probe = string.format("%.2f %.2f %.2f %.1f %s", r, g, b, lamp:light_get_energy(), lamp:get_type())
`) == 0
	testing.expect(t, ok, "Lua ran")
	lua.getglobal(L, "probe")
	testing.expect_value(t, string(lua.tostring(L, -1)), "0.20 0.20 0.30 2.5 LightNode")
	lua.pop(L, 1)
	testing.expect(t, l.color == {255, 128, 0, 255} && l.radius == 320, "light set from Lua")

	// Saved and loaded.
	text := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expect(t, strings.contains(text, `"ambient": [51, 51, 77, 255]`), "ambient saved")
	testing.expect(t, strings.contains(text, `"type": "LightNode"`) && strings.contains(text, `"kind": "Spot"`), "light saved")
	s2 := game->createScene("lit2", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	Scene_InstantiateFromJSON(s2, transmute([]u8)text, &game.gameContext)
	ProcessNodeQueues(s2.manager, &game.gameContext)
	lamp := Scene_FindNodeByName(s2, "Lamp")
	testing.expect(t, s2.ambient == {51, 51, 77, 255}, "ambient loaded")
	testing.expect(t, lamp != nil && lamp.typeId == LightNode && (cast(^LightNode)lamp).kind == .Spot && (cast(^LightNode)lamp).energy == 2.5, "light loaded")
}
