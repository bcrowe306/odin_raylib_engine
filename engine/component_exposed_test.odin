package engine

import os "osx"
import "core:strings"
import "core:testing"

// #85: a component's root lists exposed properties; the list round-trips
// (document, Apply) and is never an override; editing an exposed value on
// an instance writes an ordinary override.

@(private = "file")
EXPOSED_DIR :: "test_component_exposed"

@(private = "file")
exposed_write :: proc(name, text: string) {
	_ = os.write_entire_file(strings.concatenate({EXPOSED_DIR, "/components/", name}, context.temp_allocator), transmute([]u8)text)
}

@(test)
test_component_exposed_properties :: proc(t: ^testing.T) {
	_ = os.make_directory_all(EXPOSED_DIR + "/components")
	defer os.remove_all(EXPOSED_DIR)
	exposed_write("lid.component.json", `{"type": "Node", "name": "LidRoot", "uid": "lr000000", "children": [{"type": "Node", "name": "Lid", "uid": "l1d00000"}]}`)
	exposed_write("crate.component.json", `{"type": "Node", "name": "Crate", "uid": "cr000000",
		"exposed": [{"uid": "m0v00000", "property": "enableKeyboardInput", "label": "Keyboard"}, {"uid": "t0p00000/l1d00000", "property": "rotation", "label": "Lid angle"}],
		"children": [{"type": "Node", "name": "Top", "uid": "t0p00000", "component": "components/lid.component.json"}, {"type": "CharacterMoverNode", "name": "Mover", "uid": "m0v00000", "properties": {"enableKeyboardInput": false}}]}`)
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	AssetManager_SetProjectDir(&game.assetManager, EXPOSED_DIR)
	ctx := &game.gameContext
	scene := game->createScene("crates", false)
	CRATE :: "components/crate.component.json"

	inst := Scene_InstantiateComponent(scene, CRATE, nil, ctx)
	ProcessNodeQueues(scene.manager, ctx)
	testing.expect_value(t, len(inst.componentExposed), 2)
	if len(inst.componentExposed) == 2 {
		testing.expect_value(t, inst.componentExposed[0].label, "Keyboard")
		mover := Node_FindByUidPath(scene.manager, inst, inst.componentExposed[0].uid)
		testing.expect(t, mover != nil && mover.name == "Mover", "the mover")
		lid := Node_FindByUidPath(scene.manager, inst, inst.componentExposed[1].uid)
		testing.expect(t, lid != nil && lid.name == "Lid", "the lid, through the nested instance")
	}
	testing.expect(t, Node_FindByUidPath(scene.manager, inst, ".") == inst, "the root")
	testing.expect(t, Node_FindByUidPath(scene.manager, inst, "nope0000") == nil, "no such node")

	// Unchanged: no override, and the scene doesn't copy the list.
	saved := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expectf(t, !strings.contains(saved, `"overrides"`), "no overrides: %s", saved)
	testing.expectf(t, !strings.contains(saved, `"exposed"`), "the list stays in the file: %s", saved)

	// Editing an exposed value is an ordinary override.
	(cast(^CharacterMoverNode)Node_FindByUidPath(scene.manager, inst, "m0v00000")).enableKeyboardInput = true
	saved = Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expectf(t, strings.contains(saved, `"m0v00000": {"properties": {"enableKeyboardInput": true}}`), "the override: %s", saved)
	testing.expectf(t, !strings.contains(saved, `"exposed"`), "not an override: %s", saved)

	// Apply keeps the list in the file.
	applied := Component_InstanceJSON(inst, scene.manager, context.temp_allocator)
	testing.expectf(t, strings.contains(applied, `"exposed": [{"uid": "m0v00000", "property": "enableKeyboardInput", "label": "Keyboard"}`), "kept by Apply: %s", applied)

	// The component document: loaded, edited and written back.
	data, _ := os.read_entire_file(EXPOSED_DIR + "/components/crate.component.json", context.temp_allocator)
	doc := game->createScene("component:crate", false)
	root := Scene_InstantiateNodeFromJSON(doc, data, doc.rootNode, ctx)
	ProcessNodeQueues(doc.manager, ctx)
	testing.expect_value(t, len(root.componentExposed), 2)
	body := Node_FindByUidPath(doc.manager, root, "m0v00000")
	added := Scene_InstantiateNodeFromJSON(doc, transmute([]u8)string(`{"type": "Node", "name": "Extra"}`), body, ctx)
	ProcessNodeQueues(doc.manager, ctx)
	path := Node_UidPathBelow(doc.manager, added, root, assign = true)
	testing.expect(t, strings.has_prefix(path, "m0v00000/") && len(path) == 17, "a uid given now")
	Component_Expose(root, path, "scale", "Extra size")
	Component_Expose(root, path, "scale", "again") // (already there)
	testing.expect_value(t, len(root.componentExposed), 3)
	Component_Unexpose(root, Component_ExposedIndex(root, "t0p00000/l1d00000", "rotation"))
	testing.expect_value(t, len(root.componentExposed), 2)
	file := Component_FileJSON(root, doc.manager, context.temp_allocator)
	testing.expectf(t, strings.contains(file, `"label": "Extra size"`) && !strings.contains(file, "Lid angle"), "written: %s", file)
	testing.expectf(t, strings.contains(file, path[9:]), "the new node keeps its uid: %s", file)

	// Unlinked, an instance is ordinary nodes: no list.
	Node_UnlinkComponent(inst)
	testing.expect_value(t, len(inst.componentExposed), 0)
}
