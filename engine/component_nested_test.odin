package engine

import os "osx"
import "core:strings"
import "core:testing"

// #79: overrides on nodes inside nested instances are kept per node, with
// paths that cross the nested links, so a change at every level (the
// innermost file, the files nesting it, the instance) applies together.

@(private = "file")
NEST_DIR :: "test_component_nested"
@(private = "file")
NEST_C :: `{"type": "Node", "name": "Cc", "uid": "c0000000", "children": [{"type": "Node", "name": "Leaf", "uid": "1eaf0000", "position": [1, 1], "rotation": 0, "scale": [1, 1]}]}`
@(private = "file")
NEST_B :: `{"type": "Node", "name": "Bb", "uid": "b0000000", "children": [{"type": "Node", "name": "CInB", "uid": "cinb0000", "component": "components/c.component.json", "overrides": {"1eaf0000": {"rotation": 30}}}]}`
@(private = "file")
NEST_A :: `{"type": "Node", "name": "Aa", "uid": "a0000000", "children": [{"type": "Node", "name": "BInA", "uid": "bina0000", "component": "components/b.component.json", "overrides": {"cinb0000/1eaf0000": {"scale": [2, 2]}}}]}`

@(private = "file")
nest_write :: proc(name, text: string) {
	_ = os.write_entire_file(strings.concatenate({NEST_DIR, "/components/", name}, context.temp_allocator), transmute([]u8)text)
}

@(private = "file")
nest_load :: proc(game: ^Game, text, name: string) -> ^Scene {
	s := game->createScene(name, false)
	Scene_InstantiateFromJSON(s, transmute([]u8)text, &game.gameContext)
	ProcessNodeQueues(s.manager, &game.gameContext)
	return s
}

@(test)
test_component_nested_overrides :: proc(t: ^testing.T) {
	_ = os.make_directory_all(NEST_DIR + "/components")
	defer os.remove_all(NEST_DIR)
	nest_write("c.component.json", NEST_C)
	nest_write("b.component.json", NEST_B)
	nest_write("a.component.json", NEST_A)
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	defer Component_ClearCaches()
	AssetManager_SetProjectDir(&game.assetManager, NEST_DIR)
	ctx := &game.gameContext

	scene := game->createScene("nest", false)
	inst := Scene_InstantiateComponent(scene, "components/a.component.json", nil, ctx)
	if inst == nil do testing.fail_now(t, "instance")
	inst.name = strings.clone("I", inst.allocator)
	ProcessNodeQueues(scene.manager, ctx)
	leaf := Scene_FindNodeByName(scene, "Leaf")
	if leaf == nil do testing.fail_now(t, "leaf")
	testing.expect(t, leaf.rotation == 30 && leaf.scale == {2, 2} && leaf.position == {1, 1}, "B's and A's overrides apply")
	testing.expect_value(t, strings.join(Node_ComponentOverrides(scene.manager, leaf), ",", context.temp_allocator), "")

	// The instance overrides the leaf's position: one entry, crossing both links.
	leaf.position = {5, 5}
	testing.expect_value(t, strings.join(Node_ComponentOverrides(scene.manager, leaf), ",", context.temp_allocator), "position")
	saved := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expectf(t, strings.contains(saved, `"bina0000/cinb0000/1eaf0000": {"position": [5, 5]}`), "a per-node entry: %s", saved)
	testing.expect(t, strings.count(saved, `"overrides"`) == 1, "no nested overrides object")

	again := nest_load(game, saved, "nest_2")
	l2 := Scene_FindNodeByName(again, "Leaf")
	testing.expect(t, l2 != nil && l2.position == {5, 5} && l2.rotation == 30 && l2.scale == {2, 2}, "reloads")

	// The innermost file changes: every level keeps its own override, the
	// rest follows C.
	nest_write("c.component.json", `{"type": "Node", "name": "Cc", "uid": "c0000000", "children": [{"type": "Node", "name": "Leaf", "uid": "1eaf0000", "position": [9, 9], "rotation": 45, "scale": [3, 3], "visible": false}]}`)
	third := nest_load(game, saved, "nest_3")
	l3 := Scene_FindNodeByName(third, "Leaf")
	testing.expect(t, l3 != nil && l3.position == {5, 5}, "the instance's position")
	testing.expect(t, l3 != nil && l3.rotation == 30, "B's rotation")
	testing.expect(t, l3 != nil && l3.scale == {2, 2}, "A's scale")
	testing.expect(t, l3 != nil && !l3.renderable, "C's new visibility")

	// A changes its override: the instance gets it, and keeps its own.
	nest_write("a.component.json", `{"type": "Node", "name": "Aa", "uid": "a0000000", "children": [{"type": "Node", "name": "BInA", "uid": "bina0000", "component": "components/b.component.json", "overrides": {"cinb0000/1eaf0000": {"scale": [4, 4]}}}]}`)
	fourth := nest_load(game, saved, "nest_4")
	l4 := Scene_FindNodeByName(fourth, "Leaf")
	testing.expect(t, l4 != nil && l4.scale == {4, 4} && l4.position == {5, 5}, "A's new scale and the instance's position")

	// Reverting the leaf drops the instance's override only.
	Scene_RevertComponentOverrides(fourth, l4, ctx)
	l5 := Scene_FindNodeByName(fourth, "Leaf")
	testing.expect(t, l5 != nil && l5.position == {9, 9} && l5.scale == {4, 4} && l5.rotation == 30, "C's position again")

	// Scenes saved before (a whole nested "overrides" object) still load.
	OLD :: `{"name": "s", "root": {"type": "Node", "name": "root", "children": [{"type": "Node", "name": "I", "component": "components/a.component.json", "overrides": {"bina0000": {"overrides": {"cinb0000": {"overrides": {"1eaf0000": {"position": [7, 7], "rotation": 30, "scale": [2, 2]}}}}}}}]}}`
	old := nest_load(game, OLD, "nest_old")
	lo := Scene_FindNodeByName(old, "Leaf")
	testing.expect(t, lo != nil && lo.position == {7, 7}, "an old nested override applies")
	resaved := Scene_SerializeToJSON(old, context.temp_allocator)
	testing.expectf(t, strings.contains(resaved, `"bina0000/cinb0000/1eaf0000": {`) && strings.count(resaved, `"overrides"`) == 1, "saved per node: %s", resaved)
}

// An instance added to another instance is saved as a link with its own
// overrides (not expanded into the outer one's).
@(test)
test_component_nested_added_instance :: proc(t: ^testing.T) {
	_ = os.make_directory_all(NEST_DIR + "/components")
	defer os.remove_all(NEST_DIR)
	nest_write("c.component.json", NEST_C)
	nest_write("b.component.json", NEST_B)
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	defer Component_ClearCaches()
	AssetManager_SetProjectDir(&game.assetManager, NEST_DIR)
	ctx := &game.gameContext
	scene := game->createScene("nest_add", false)
	inst := Scene_InstantiateComponent(scene, "components/b.component.json", nil, ctx)
	if inst == nil do testing.fail_now(t, "instance")
	inst.name = strings.clone("I", inst.allocator)
	extra := Scene_InstantiateComponent(scene, "components/c.component.json", inst, ctx)
	if extra == nil do testing.fail_now(t, "added instance")
	extra.name = strings.clone("Extra", extra.allocator)
	ProcessNodeQueues(scene.manager, ctx)
	for c in GetChildrenView(scene.manager, extra) do c.position = {8, 8}
	root, path := Node_ComponentOverridePath(scene.manager, GetChildrenView(scene.manager, extra)[0])
	testing.expect(t, root == extra && path == "1eaf0000", "its own overrides")

	saved := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expectf(t, strings.contains(saved, `"$added"`) && strings.contains(saved, `"overrides": {"1eaf0000": {"position": [8, 8]}}`) && !strings.contains(saved, `"children": [{`), "added as a link with its overrides: %s", saved)
	again := nest_load(game, saved, "nest_add_2")
	ex := Scene_FindNodeByName(again, "Extra")
	testing.expect(t, ex != nil && ex.componentPath == "components/c.component.json", "still an instance")
	if ex != nil {
		kids := GetChildrenView(again.manager, ex)
		testing.expect(t, len(kids) == 1 && kids[0].position == {8, 8}, "its override")
	}
}

// An instance of B inside a component document of A follows B when B's
// file changes (Scene_RefreshComponentInstances rebuilds the outermost
// instance, so the nesting levels stay consistent).
@(test)
test_component_nested_refresh :: proc(t: ^testing.T) {
	_ = os.make_directory_all(NEST_DIR + "/components")
	defer os.remove_all(NEST_DIR)
	nest_write("c.component.json", NEST_C)
	nest_write("b.component.json", NEST_B)
	nest_write("a.component.json", NEST_A)
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	defer Component_ClearCaches()
	AssetManager_SetProjectDir(&game.assetManager, NEST_DIR)
	ctx := &game.gameContext
	scene := game->createScene("nest_rf", false)
	inst := Scene_InstantiateComponent(scene, "components/a.component.json", nil, ctx)
	if inst == nil do testing.fail_now(t, "instance")
	ProcessNodeQueues(scene.manager, ctx)
	Scene_FindNodeByName(scene, "Leaf").position = {5, 5}

	nest_write("c.component.json", `{"type": "Node", "name": "Cc", "uid": "c0000000", "children": [{"type": "Node", "name": "Leaf", "uid": "1eaf0000", "position": [9, 9], "rotation": 45, "scale": [3, 3], "visible": false}]}`)
	testing.expect_value(t, Scene_RefreshComponentInstances(scene, "components/c.component.json", ctx), 1)
	leaf := Scene_FindNodeByName(scene, "Leaf")
	testing.expect(t, leaf != nil && leaf.position == {5, 5} && leaf.rotation == 30 && leaf.scale == {2, 2} && !leaf.renderable, "every level after the refresh")
	saved := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expectf(t, strings.contains(saved, `"overrides": {"bina0000/cinb0000/1eaf0000": {"position": [5, 5]}}`), "only the instance's override, C's change isn't pinned: %s", saved)
}
