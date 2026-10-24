package engine

import "core:strings"
import "core:testing"
import lua "lua54"

@(test)
test_visual_extras :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("extras", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running

	// Trail: records points as its parent moves (at least minDistance apart),
	// they expire after `lifetime`.
	ship := Node_CreateByTypeName(scene, "Node")
	ship.name = "Ship"
	trail := cast(^TrailNode)Node_CreateByTypeName(scene, "TrailNode", ship)
	trail.lifetime = 0.5
	trail.minDistance = 5
	for i in 0 ..< 10 {
		ship.position = {f32(i) * 10, 0}
		game->run(0.05)
	}
	testing.expectf(t, len(trail.trail) >= 9, "points recorded: %d", len(trail.trail))
	ship.position.x += 2 // under minDistance: no new point
	n := len(trail.trail)
	game->run(0.01)
	testing.expect_value(t, len(trail.trail), n)
	trail.emitting = false
	game->run(0.6)
	testing.expect_value(t, len(trail.trail), 0)

	// Parallax: half the camera's movement, plus its own drift.
	par := cast(^ParallaxNode)Node_CreateByTypeName(scene, "ParallaxNode")
	par.factor = {0.5, 1}
	testing.expect_value(t, ParallaxNode_Offset(par, {100, 40}), [2]f32{50, 0})
	par.scrollSpeed = {10, 0}
	game->run(0.5)
	testing.expect_value(t, ParallaxNode_Offset(par, {0, 0}), [2]f32{5, 0})

	// Line: points from Lua, saved and loaded.
	line := cast(^LineNode)Node_CreateByTypeName(scene, "LineNode")
	line.name = "Laser"
	L := game.scriptManager.L
	ok := lua.L_dostring(L, `
local l = Scene.find_node("Laser")
l:line_set_points({ {0, 0}, {100, 0} })
l:line_add_point(100, 50)
`)
	testing.expect(t, ok == 0 && len(line.points) == 3 && line.points[2] == {100, 50}, "points from Lua")
	slice := cast(^NineSliceNode)Node_CreateByTypeName(scene, "NineSliceNode")
	slice.name = "Panel"
	slice.texturePath = "textures/panel.png"
	slice.marginsLT = {12, 8}

	// Post effects: enabled ones with a shader, in tree order.
	a := Node_CreateByTypeName(scene, "PostEffectNode")
	a.name = "Vignette"
	b := Node_CreateByTypeName(scene, "PostEffectNode")
	b.name = "Crt"
	Material_SetShader(b, "builtin:crt")
	off := Node_CreateByTypeName(scene, "PostEffectNode")
	off.name = "Off"
	off.enabled = false
	game->run(0.016)
	effects := Scene_PostEffects(scene)
	testing.expect(t, len(effects) == 2 && effects[0] == a && effects[1] == b, "two effects in order")
	testing.expect_value(t, a.material.shader, "builtin:vignette")

	text := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expect(t, strings.contains(text, `"points": [[0, 0], [100, 0], [100, 50]]`), "points saved")
	s2 := game->createScene("extras2", false)
	Scene_InstantiateFromJSON(s2, transmute([]u8)text, &game.gameContext)
	ProcessNodeQueues(s2.manager, &game.gameContext)
	l2 := cast(^LineNode)Scene_FindNodeByName(s2, "Laser")
	p2 := cast(^NineSliceNode)Scene_FindNodeByName(s2, "Panel")
	c2 := Scene_FindNodeByName(s2, "Crt")
	testing.expect(t, l2 != nil && len(l2.points) == 3 && l2.points[1] == {100, 0}, "line loaded")
	testing.expect(t, p2 != nil && p2.texturePath == "textures/panel.png" && p2.marginsLT == {12, 8}, "nine-slice loaded")
	testing.expect(t, c2 != nil && c2.material != nil && c2.material.shader == "builtin:crt", "post effect loaded")
}
