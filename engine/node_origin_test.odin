package engine

import "core:strings"
import "core:testing"
import lua "vendor:lua/5.4"

// The origin (Node.pivot): the centre by default, saved as "pivot", older
// scenes keep their look, scripts set it by the "origin" path.
@(test)
test_node_origin :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("origin", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)

	tn := cast(^TextureNode)Node_CreateByTypeName(scene, "TextureNode")
	tn.name = "Sprite"
	tn.size = {100, 40}
	testing.expect_value(t, tn.pivot, [2]f32{0.5, 0.5})
	testing.expect_value(t, Node_OriginPx(tn, tn.size), [2]f32{50, 20})
	testing.expect(t, Node_HasOrigin(tn) && !Node_HasOrigin(Node_CreateByTypeName(scene, "TimerNode")), "which nodes")
	tn.pivot = {0.5, 1}
	tn.origin = {10, 10} // the pixel override
	testing.expect_value(t, Node_OriginPx(tn, tn.size), [2]f32{10, 10})
	Node_SetOriginPx(tn, {25, 40}, tn.size)
	testing.expect(t, tn.pivot == {0.25, 1} && tn.origin == {}, "pixels -> fraction")

	ns := cast(^NineSliceNode)Node_CreateByTypeName(scene, "NineSliceNode")
	ns.name = "Panel"
	ns.pivot = {0, 0}
	ProcessNodeQueues(scene.manager, &game.gameContext)

	// Saved and loaded.
	text := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expect(t, strings.contains(text, `"pivot": [0.25, 1]`) && strings.contains(text, `"pivot": [0, 0]`), "saved")
	s2 := game->createScene("origin2", false)
	Scene_InstantiateFromJSON(s2, transmute([]u8)text, &game.gameContext)
	ProcessNodeQueues(s2.manager, &game.gameContext)
	testing.expect_value(t, Scene_FindNodeByName(s2, "Sprite").pivot, [2]f32{0.25, 1})
	testing.expect_value(t, Scene_FindNodeByName(s2, "Panel").pivot, [2]f32{0, 0})

	// Older scenes: no "pivot".
	legacy := `{"name": "old", "root": {"type": "Node", "name": "root", "children": [
		{"type": "AnimationPlayerNode", "name": "Anim", "animations": []},
		{"type": "NineSliceNode", "name": "Centred", "properties": {"centered": true}},
		{"type": "TextNode", "name": "Corner", "properties": {"text": "hi"}},
		{"type": "TextureNode", "name": "Ship", "origin": [12, 34]},
		{"type": "TextureNode", "name": "Plain"}
	]}}`
	s3 := game->createScene("legacy", false)
	Scene_InstantiateFromJSON(s3, transmute([]u8)legacy, &game.gameContext)
	ProcessNodeQueues(s3.manager, &game.gameContext)
	testing.expect_value(t, Scene_FindNodeByName(s3, "Anim").pivot, [2]f32{0, 0})       // drawn from the top-left, as before
	testing.expect_value(t, Scene_FindNodeByName(s3, "Centred").pivot, [2]f32{0.5, 0.5})
	testing.expect_value(t, Scene_FindNodeByName(s3, "Corner").pivot, [2]f32{0, 0})
	ship := cast(^TextureNode)Scene_FindNodeByName(s3, "Ship")
	testing.expect_value(t, ship.origin, [2]f32{12, 34}) // headless: no texture size, the pixels stay
	testing.expect_value(t, Scene_FindNodeByName(s3, "Plain").pivot, [2]f32{0.5, 0.5})

	// Scripts: the "origin" path.
	L := game.scriptManager.L
	ok := lua.L_dostring(L, `
local s = Scene.find_node("Sprite")
s:set_property("origin", 0.5, 1)
local o = s:get_property("origin")
ox, oy = o[1], o[2]
`)
	testing.expect_value(t, ok, i32(0))
	testing.expect_value(t, tn.pivot, [2]f32{0.5, 1})
}
