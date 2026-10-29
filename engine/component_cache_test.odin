package engine

import cos "core:os"
import os "osx"
import "core:strings"
import "core:testing"
import "core:time"

// #80: prepared components are cached per path; the cache follows the files
// (the component and every file it nests), and games don't keep a copy of
// the component JSON on each instance.

@(private = "file")
CACHE_DIR :: "test_component_cache"

@(private = "file")
cache_write :: proc(name, text: string) {
	_ = os.write_entire_file(strings.concatenate({CACHE_DIR, "/components/", name}, context.temp_allocator), transmute([]u8)text)
}

@(private = "file")
lid_y :: proc(scene: ^Scene, inst: ^Node) -> f32 {
	for n in scene.manager.nodes {
		if n == nil || n.name != "Lid" do continue
		for p := GetParent(scene.manager, n); p != nil; p = GetParent(scene.manager, p) do if p == inst do return n.position.y
	}
	return 999
}

@(test)
test_component_prepared_cache :: proc(t: ^testing.T) {
	_ = os.make_directory_all(CACHE_DIR + "/components")
	defer os.remove_all(CACHE_DIR)
	cache_write("lid.component.json", `{"type": "Node", "name": "LidRoot", "uid": "lr000000", "children": [{"type": "Node", "name": "Lid", "uid": "l1d00000", "position": [0, -10]}]}`)
	cache_write("crate.component.json", `{"type": "Node", "name": "Crate", "uid": "cr000000", "children": [{"type": "Node", "name": "Top", "uid": "t0p00000", "component": "components/lid.component.json"}]}`)
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	AssetManager_SetProjectDir(&game.assetManager, CACHE_DIR)
	ctx := &game.gameContext
	scene := game->createScene("cache", false)
	REL :: "components/crate.component.json"

	a := Scene_InstantiateComponent(scene, REL, nil, ctx)
	ProcessNodeQueues(scene.manager, ctx)
	testing.expect_value(t, lid_y(scene, a), -10)
	testing.expect_value(t, Component_PreparedCount(), 1)
	b := Scene_InstantiateComponent(scene, REL, nil, ctx)
	ProcessNodeQueues(scene.manager, ctx)
	testing.expect_value(t, lid_y(scene, b), -10)
	testing.expect(t, b.componentBase == a.componentBase && a.componentBase != "", "the same base, from the cache")

	// A nested file changes on disk: the crate's entry is stale.
	cache_write("lid.component.json", `{"type": "Node", "name": "LidRoot", "uid": "lr000000", "children": [{"type": "Node", "name": "Lid", "uid": "l1d00000", "position": [0, -1234]}]}`)
	c := Scene_InstantiateComponent(scene, REL, nil, ctx)
	ProcessNodeQueues(scene.manager, ctx)
	testing.expect_value(t, lid_y(scene, c), -1234)

	// The same size and time can't be told apart: writers forget the entry.
	cache_write("lid.component.json", `{"type": "Node", "name": "LidRoot", "uid": "lr000000", "children": [{"type": "Node", "name": "Lid", "uid": "l1d00000", "position": [0, -4321]}]}`)
	Component_ForgetPrepared()
	testing.expect_value(t, Component_PreparedCount(), 0)
	d := Scene_InstantiateComponent(scene, REL, nil, ctx)
	ProcessNodeQueues(scene.manager, ctx)
	testing.expect_value(t, lid_y(scene, d), -4321)

	// A missing file isn't cached (it may come back).
	e := Scene_InstantiateComponent(scene, "components/nope.component.json", nil, ctx)
	testing.expect(t, e == nil, "no instance")
	testing.expect_value(t, Component_PreparedCount(), 1)
}

// Without bases (games: Engine_RunProject), instances still save their
// overrides correctly - against the file as it is.
@(test)
test_component_without_bases :: proc(t: ^testing.T) {
	_ = os.make_directory_all(CACHE_DIR + "/components")
	defer os.remove_all(CACHE_DIR)
	cache_write("lid.component.json", `{"type": "Node", "name": "LidRoot", "uid": "lr000000", "children": [{"type": "Node", "name": "Lid", "uid": "l1d00000", "position": [0, -10]}]}`)
	cache_write("crate.component.json", `{"type": "Node", "name": "Crate", "uid": "cr000000", "children": [{"type": "Node", "name": "Top", "uid": "t0p00000", "component": "components/lid.component.json"}]}`)
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	AssetManager_SetProjectDir(&game.assetManager, CACHE_DIR)
	Component_KeepBases = false
	defer Component_KeepBases = true
	ctx := &game.gameContext
	scene := game->createScene("nobase", false)
	inst := Scene_InstantiateComponent(scene, "components/crate.component.json", nil, ctx)
	ProcessNodeQueues(scene.manager, ctx)
	for n in scene.manager.nodes do if n != nil do testing.expectf(t, n.componentBase == "", "%s keeps no base", n.name)
	saved := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expectf(t, !strings.contains(saved, `"overrides"`), "unchanged: no overrides: %s", saved)
	for n in scene.manager.nodes do if n != nil && n.name == "Lid" do n.position = {0, -50}
	saved = Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expectf(t, strings.contains(saved, `"t0p00000/l1d00000": {"position": [0, -50]}`), "the override: %s", saved)
	_ = inst
}

// A file rewritten in the same instant it was read (same size and file
// time: Windows' file times in a test) isn't served from the cache: an
// entry whose files were modified just before it was made is checked again.
@(test)
test_component_prepared_cache_racy :: proc(t: ^testing.T) {
	_ = os.make_directory_all(CACHE_DIR + "/components")
	defer os.remove_all(CACHE_DIR)
	LID :: CACHE_DIR + "/components/lid.component.json"
	cache_write("lid.component.json", `{"type": "Node", "name": "LidRoot", "uid": "lr000000", "children": [{"type": "Node", "name": "Lid", "uid": "l1d00000", "position": [0, -10]}]}`)
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	AssetManager_SetProjectDir(&game.assetManager, CACHE_DIR)
	ctx := &game.gameContext
	scene := game->createScene("racy", false)
	REL :: "components/lid.component.json"
	// A whole second, set again after the rewrite: the same file time.
	stamp := time.from_nanoseconds(time.to_unix_nanoseconds(time.now()) / 1e9 * 1e9)
	testing.expect_value(t, cos.change_times(LID, stamp, stamp), nil)

	a := Scene_InstantiateComponent(scene, REL, nil, ctx)
	ProcessNodeQueues(scene.manager, ctx)
	testing.expect_value(t, lid_y(scene, a), -10)
	// The same size and time: only "just modified" tells.
	cache_write("lid.component.json", `{"type": "Node", "name": "LidRoot", "uid": "lr000000", "children": [{"type": "Node", "name": "Lid", "uid": "l1d00000", "position": [0, -20]}]}`)
	testing.expect_value(t, cos.change_times(LID, stamp, stamp), nil)
	b := Scene_InstantiateComponent(scene, REL, nil, ctx)
	ProcessNodeQueues(scene.manager, ctx)
	testing.expect_value(t, lid_y(scene, b), -20)
}
