package engine

import os "osx"
import "core:fmt"
import "core:strings"
import "core:testing"

// #80: Component caching, cache invalidation, and skipping componentBase outside editor.

@(private = "file")
CACHE_TEST_DIR :: "test_component_cache"

@(test)
test_component_cache_hit_and_invalidate :: proc(t: ^testing.T) {
	_ = os.make_directory_all(CACHE_TEST_DIR + "/components")
	defer os.remove_all(CACHE_TEST_DIR)

	compRel :: "components/test_box.component.json"
	compFile :: CACHE_TEST_DIR + "/" + compRel
	_ = os.write_entire_file(compFile, transmute([]u8)string(`{"type": "Node", "name": "Box", "position": [10, 20]}`))

	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	defer Component_ClearCaches()
	AssetManager_SetProjectDir(&game.assetManager, CACHE_TEST_DIR)
	ctx := &game.gameContext

	// 1. Initial instantiate should populate the cache.
	scene := game->createScene("cache_scene", false)
	inst1 := Scene_InstantiateComponent(scene, compRel, nil, ctx)
	testing.expect(t, inst1 != nil, "first instantiation failed")
	testing.expect_value(t, inst1.position, [2]f32{10, 20})

	entry, inCache := Component_Cache_Get(ctx, compRel)
	testing.expect(t, inCache, "component was not cached after instantiate")
	testing.expect(t, strings.contains(entry.baseText, `"name": "Box"`), "cached base text mismatch")

	// 2. Second instantiate uses cache.
	inst2 := Scene_InstantiateComponent(scene, compRel, nil, ctx)
	testing.expect(t, inst2 != nil, "second instantiation failed")
	testing.expect_value(t, inst2.position, [2]f32{10, 20})
	ProcessNodeQueues(scene.manager, ctx)

	// 3. Invalidate specific component path.
	Component_Cache_Invalidate(compRel)
	_, stillInCache := Component_Cache_Get(ctx, compRel)
	testing.expect(t, !stillInCache, "component should have been invalidated")

	// 4. Modify file on disk and re-instantiate: should read new values into cache.
	_ = os.write_entire_file(compFile, transmute([]u8)string(`{"type": "Node", "name": "BoxModified", "position": [99, 99]}`))
	inst3 := Scene_InstantiateComponent(scene, compRel, nil, ctx)
	testing.expect(t, inst3 != nil, "third instantiation failed")
	testing.expect_value(t, inst3.position, [2]f32{99, 99})
	ProcessNodeQueues(scene.manager, ctx)

	entry3, inCache3 := Component_Cache_Get(ctx, compRel)
	testing.expect(t, inCache3, "component was not re-cached")
	testing.expect(t, strings.contains(entry3.baseText, `"name": "BoxModified"`), "new content not in cache")

	// 5. Scene_RefreshComponentInstances clears stale cache and rebuilds with new content.
	_ = os.write_entire_file(compFile, transmute([]u8)string(`{"type": "Node", "name": "BoxRefreshed", "position": [77, 77]}`))
	testing.expect_value(t, Scene_RefreshComponentInstances(scene, compRel, ctx), 3)

	entryAfterRefresh, inCacheAfterRefresh := Component_Cache_Get(ctx, compRel)
	testing.expect(t, inCacheAfterRefresh, "cache should be populated with refreshed content")
	testing.expect(t, strings.contains(entryAfterRefresh.baseText, `"name": "BoxRefreshed"`), "refreshed content not in cache")
}

@(test)
test_component_base_omitted_outside_editor :: proc(t: ^testing.T) {
	_ = os.make_directory_all(CACHE_TEST_DIR + "/components")
	defer os.remove_all(CACHE_TEST_DIR)

	compRel :: "components/test_omitted.component.json"
	compFile :: CACHE_TEST_DIR + "/" + compRel
	_ = os.write_entire_file(compFile, transmute([]u8)string(`{"type": "Node", "name": "Om", "position": [5, 5]}`))

	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	defer Component_ClearCaches()
	AssetManager_SetProjectDir(&game.assetManager, CACHE_TEST_DIR)

	// In runtime games (!isEditor), componentBase must be empty to avoid memory overhead.
	game.gameContext.isEditor = false
	sceneGame := game->createScene("game_scene", false)
	gameInst := Scene_InstantiateComponent(sceneGame, compRel, nil, &game.gameContext)
	testing.expect(t, gameInst != nil, "game instantiation failed")
	testing.expect_value(t, gameInst.componentBase, "")

	// In the editor (isEditor), componentBase is retained so the editor can diff overrides against it.
	game.gameContext.isEditor = true
	sceneEditor := game->createScene("editor_scene", false)
	editorInst := Scene_InstantiateComponent(sceneEditor, compRel, nil, &game.gameContext)
	testing.expect(t, editorInst != nil, "editor instantiation failed")
	testing.expect(t, editorInst.componentBase != "", "editor instance componentBase should not be empty")

	// Even with empty componentBase in game scene, Component_OverridesJSON computes correctly via fallback.
	ProcessNodeQueues(sceneGame.manager, &game.gameContext)
	gameInst.zIndex = 42
	ov := Component_OverridesJSON(gameInst, sceneGame.manager)
	testing.expect(t, strings.contains(ov, `"z_index": 42`), "overrides fallback failed with empty componentBase")
}
