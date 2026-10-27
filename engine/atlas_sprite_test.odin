package engine

import "core:strings"
import "core:testing"
import lua "lua54"
import rl "vendor:raylib"

@(test)
test_atlas_sprite_node :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()

	scene := game->createScene("atlas_test", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)

	// 1. Create AtlasSpriteNode
	node := Node_CreateByTypeName(scene, "AtlasSpriteNode")
	testing.expect(t, node != nil, "AtlasSpriteNode created")
	testing.expect_value(t, node.typeId, AtlasSpriteNode)

	an := cast(^AtlasSpriteNode)node
	an.name = "AtlasPlayer"

	// Check default region and size
	testing.expect_value(t, an.region, rl.Rectangle{})
	testing.expect_value(t, an.size, [2]f32{0, 0})

	// 2. Set Region
	AtlasSpriteNode_SetRegion(an, rl.Rectangle{16, 32, 64, 48})
	testing.expect_value(t, an.region, rl.Rectangle{16, 32, 64, 48})
	testing.expect_value(t, an.size, [2]f32{64, 48})

	// 3. Origin & Culling
	testing.expect(t, Node_HasOrigin(an), "has origin")
	testing.expect_value(t, an.pivot, [2]f32{0.5, 0.5})
	testing.expect_value(t, Node_OriginPx(an, an.size), [2]f32{32, 24})

	dummy := new(Texture)
	defer free(dummy)
	an.texture = dummy

	ProcessNodeQueues(scene.manager, &game.gameContext)
	Node_SetGlobalPositions(scene.manager, scene.rootNode)

	cullRect, okBounds := Node_RenderBounds(an)
	testing.expect(t, okBounds, "render bounds ok")
	testing.expect_value(t, cullRect.width, f32(64))
	testing.expect_value(t, cullRect.height, f32(48))

	// 4. JSON Serialization & Deserialization
	jsonText := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expect(t, strings.contains(jsonText, `"type": "AtlasSpriteNode"`), "serialized type")
	testing.expect(t, strings.contains(jsonText, `"region": [16, 32, 64, 48]`), "serialized region")

	s2 := game->createScene("atlas_deser", false)
	Scene_InstantiateFromJSON(s2, transmute([]u8)jsonText, &game.gameContext)
	ProcessNodeQueues(s2.manager, &game.gameContext)

	loaded := Scene_FindNodeByName(s2, "AtlasPlayer")
	testing.expect(t, loaded != nil, "found loaded AtlasPlayer")
	testing.expect_value(t, loaded.typeId, AtlasSpriteNode)

	anLoaded := cast(^AtlasSpriteNode)loaded
	testing.expect_value(t, anLoaded.region, rl.Rectangle{16, 32, 64, 48})
	testing.expect_value(t, anLoaded.size, [2]f32{64, 48})
	testing.expect_value(t, anLoaded.pivot, [2]f32{0.5, 0.5})

	// 5. Script Lua API
	L := game.scriptManager.L
	code := `
		local n = Scene.find_node("AtlasPlayer")
		local w, h = n:texture_get_size()
		assert(w == 64 and h == 48, "initial size")
		n:atlas_set_region(10, 20, 30, 40)
		local rx, ry, rw, rh = n:atlas_get_region()
		assert(rx == 10 and ry == 20 and rw == 30 and rh == 40, "get region")
		local nw, nh = n:texture_get_size()
		assert(nw == 30 and nh == 40, "updated size")
	`
	err := lua.L_dostring(L, strings.clone_to_cstring(code, context.temp_allocator))
	testing.expect_value(t, err, i32(0))
	testing.expect_value(t, an.region, rl.Rectangle{10, 20, 30, 40})
	testing.expect_value(t, an.size, [2]f32{30, 40})
}
