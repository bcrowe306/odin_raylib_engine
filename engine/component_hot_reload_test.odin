package engine

import os "osx"
import "core:strings"
import "core:testing"

// #83: a running game (no component bases kept) rebuilds the instances of a
// component file that changed on disk, keeping their overrides, transform
// and place in the tree.

@(private = "file")
HOT_DIR :: "test_component_hot_reload"

@(private = "file")
hot_write :: proc(name, text: string) {
	_ = os.write_entire_file(strings.concatenate({HOT_DIR, "/components/", name}, context.temp_allocator), transmute([]u8)text)
}

@(private = "file")
hot_find :: proc(scene: ^Scene, inst: ^Node, name: string) -> ^Node {
	for n in scene.manager.nodes {
		if n == nil || n.name != name do continue
		for p := GetParent(scene.manager, n); p != nil; p = GetParent(scene.manager, p) do if p == inst do return n
	}
	return nil
}

@(test)
test_component_hot_reload :: proc(t: ^testing.T) {
	_ = os.make_directory_all(HOT_DIR + "/components")
	defer os.remove_all(HOT_DIR)
	hot_write("lid.component.json", `{"type": "Node", "name": "LidRoot", "uid": "lr000000", "children": [{"type": "Node", "name": "Lid", "uid": "l1d00000", "position": [0, -10]}]}`)
	hot_write("crate.component.json", `{"type": "Node", "name": "Crate", "uid": "cr000000", "children": [{"type": "Node", "name": "Top", "uid": "t0p00000", "component": "components/lid.component.json"}, {"type": "Node", "name": "Body", "uid": "b0d00000", "position": [0, 5]}]}`)
	hot_write("other.component.json", `{"type": "Node", "name": "Other", "uid": "ot000000"}`)
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	AssetManager_SetProjectDir(&game.assetManager, HOT_DIR)
	Component_KeepBases = false
	defer Component_KeepBases = true
	ctx := &game.gameContext
	scene := game->createScene("hot", false)
	scene.isLoaded = true
	game.sceneManager.currentScene = scene
	CRATE :: "components/crate.component.json"

	a := Scene_InstantiateComponent(scene, CRATE, nil, ctx)
	other := Scene_InstantiateComponent(scene, "components/other.component.json", nil, ctx)
	ProcessNodeQueues(scene.manager, ctx)
	a.position = {100, 200}
	hot_find(scene, a, "Lid").rotation = 45 // an override inside the nested instance
	hot_find(scene, a, "Body").position = {7, 7} // an override of the outer one
	testing.expect_value(t, Component_HotReload(game, force = true), 0) // nothing changed

	// The nested file changes: the outer instance is rebuilt.
	hot_write("lid.component.json", `{"type": "Node", "name": "LidRoot", "uid": "lr000000", "children": [{"type": "Node", "name": "Lid", "uid": "l1d00000", "position": [0, -99]}]}`)
	testing.expect_value(t, Component_HotReload(game, force = true), 1)
	kids := GetChildrenView(scene.manager, scene.rootNode)
	testing.expect_value(t, len(kids), 2)
	b := kids[0]
	testing.expect_value(t, b.componentPath, CRATE)
	testing.expect(t, kids[1] == other, "the unrelated instance stays")
	testing.expect_value(t, b.position, [2]f32{100, 200})
	lid := hot_find(scene, b, "Lid")
	testing.expect(t, lid != nil, "the lid is there")
	if lid != nil {
		testing.expect_value(t, lid.position.y, -99) // the file's change
		testing.expect_value(t, lid.rotation, 45) // the override stays
	}
	if body := hot_find(scene, b, "Body"); body != nil do testing.expect_value(t, body.position, [2]f32{7, 7})

	// The outer file changes: a value without an override follows it.
	hot_write("crate.component.json", `{"type": "Node", "name": "Crate", "uid": "cr000000", "children": [{"type": "Node", "name": "Top", "uid": "t0p00000", "component": "components/lid.component.json"}, {"type": "Node", "name": "Body", "uid": "b0d00000", "position": [0, 5], "rotation": 30}]}`)
	testing.expect_value(t, Component_HotReload(game, force = true), 1)
	c := GetChildrenView(scene.manager, scene.rootNode)[0]
	if body := hot_find(scene, c, "Body"); body != nil {
		testing.expect_value(t, body.rotation, 30)
		testing.expect_value(t, body.position, [2]f32{7, 7})
	}
	if lid := hot_find(scene, c, "Lid"); lid != nil do testing.expect_value(t, lid.rotation, 45)

	// Saved afterwards, the overrides are the same ones.
	saved := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expectf(t, strings.contains(saved, `"t0p00000/l1d00000": {"rotation": 45}`), "the nested override: %s", saved)
	testing.expectf(t, !strings.contains(saved, `-99`), "the file's value isn't pinned: %s", saved)
}
