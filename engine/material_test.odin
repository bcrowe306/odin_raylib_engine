package engine

import "core:strings"
import "core:testing"
import lua "lua54"

@(test)
test_materials_uniforms_serialization_lua :: proc(t: ^testing.T) {
	// Uniforms and their hints.
	src := `#version 330
uniform sampler2D texture0;
uniform vec4 colDiffuse;
uniform float amount; // range 0 2 default 0.5
uniform vec4 tint;    // color
uniform vec2 offset;
uniform sampler2D noise;
uniform float time;
`
	us := Shader_ParseUniforms(src, context.temp_allocator)
	testing.expect_value(t, len(us), 5)
	testing.expect(t, us[0].name == "amount" && us[0].kind == .Float && us[0].hasRange && us[0].max == 2 && us[0].default_.x == 0.5, "float with range and default")
	testing.expect(t, us[1].isColor && us[1].default_ == {1, 1, 1, 1}, "colour defaults to white")
	testing.expect(t, us[3].kind == .Texture && us[4].auto, "texture param; time is automatic")
	for b in BUILTIN_SHADERS {
		testing.expectf(t, Builtin_ShaderSource(b) != "" && len(Shader_ParseUniforms(Builtin_ShaderSource(b), context.temp_allocator)) > 0, "builtin %s", b)
	}

	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("mat", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	n := Node_CreateByTypeName(scene, "TextureNode")
	n.name = "Ship"
	n.gameContext = &game.gameContext
	ProcessNodeQueues(scene.manager, &game.gameContext)

	// Lua API.
	L := game.scriptManager.L
	ok := lua.L_dostring(L, `
local s = Scene.find_node("Ship")
s:set_shader("builtin:flash")
s:set_shader_param("amount", 0.25)
s:set_shader_param("flash_color", {1, 0, 0, 1})
s:set_blend_mode("additive")
local a = s:get_shader_param("amount")
local r, g = s:get_shader_param("flash_color")
default_width = select(1, s:get_shader_param("missing"))
probe = a .. ":" .. r .. ":" .. g
`) == 0
	testing.expect(t, ok, "Lua ran")
	lua.getglobal(L, "probe")
	testing.expect_value(t, string(lua.tostring(L, -1)), "0.25:1.0:0.0")
	lua.pop(L, 1)
	testing.expect(t, n.material != nil && n.material.shader == "builtin:flash" && n.material.blend == .Additive, "material set")

	// Saved and loaded.
	text := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expect(t, strings.contains(text, `"material": {"shader": "builtin:flash", "blend": "additive", "params": {"amount": [0.25, 0, 0, 0], "flash_color": [1, 0, 0, 1]}}`), "material saved")
	s2 := game->createScene("mat2", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	Scene_InstantiateFromJSON(s2, transmute([]u8)text, &game.gameContext)
	ProcessNodeQueues(s2.manager, &game.gameContext)
	ship := Scene_FindNodeByName(s2, "Ship")
	testing.expect(t, ship != nil && ship.material != nil && ship.material.blend == .Additive, "material loaded")
	if ship != nil {
		v, _, found := Material_GetParam(ship, "flash_color")
		testing.expect(t, found && v == {1, 0, 0, 1}, "param loaded")
		v, _, found = Material_GetParam(ship, "outline_free")
		testing.expect(t, !found, "unknown param")
	}
}
