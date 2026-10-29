package engine

import "core:encoding/json"
import os "osx"
import "core:slice"
import "core:strings"
import "core:testing"

// #84: one overridden value of a node in an instance can be reverted, or
// written to the component file (Revert / Apply per property).

@(private = "file")
FIELD_DIR :: "test_component_override_field"

@(private = "file")
field_write :: proc(name, text: string) {
	_ = os.write_entire_file(strings.concatenate({FIELD_DIR, "/components/", name}, context.temp_allocator), transmute([]u8)text)
}

@(private = "file")
field_find :: proc(scene: ^Scene, inst: ^Node, name: string) -> ^Node {
	for n in scene.manager.nodes {
		if n == nil || n.name != name do continue
		for p := GetParent(scene.manager, n); p != nil; p = GetParent(scene.manager, p) do if p == inst do return n
	}
	return nil
}

@(private = "file")
field_overrides :: proc(scene: ^Scene, inst: ^Node, name: string) -> []string {
	n := field_find(scene, inst, name)
	if n == nil do return nil
	return Node_ComponentOverrides(scene.manager, n)
}

@(test)
test_component_override_per_field :: proc(t: ^testing.T) {
	_ = os.make_directory_all(FIELD_DIR + "/components")
	defer os.remove_all(FIELD_DIR)
	field_write("lid.component.json", `{"type": "Node", "name": "LidRoot", "uid": "lr000000", "children": [{"type": "Node", "name": "Lid", "uid": "l1d00000", "position": [0, -10]}]}`)
	field_write("crate.component.json", `{"type": "Node", "name": "Crate", "uid": "cr000000", "position": [3, 4], "children": [{"type": "Node", "name": "Top", "uid": "t0p00000", "component": "components/lid.component.json"}, {"type": "CharacterMoverNode", "name": "Mover", "uid": "m0v00000", "properties": {"enableKeyboardInput": false}}]}`)
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	AssetManager_SetProjectDir(&game.assetManager, FIELD_DIR)
	ctx := &game.gameContext
	scene := game->createScene("field", false)
	CRATE :: "components/crate.component.json"

	inst := Scene_InstantiateComponent(scene, CRATE, nil, ctx)
	ProcessNodeQueues(scene.manager, ctx)
	inst.position = {100, 200}
	mover := field_find(scene, inst, "Mover")
	mover.rotation = 15
	(cast(^CharacterMoverNode)mover).enableKeyboardInput = true
	field_find(scene, inst, "Lid").rotation = 45
	testing.expect_value(t, strings.join(field_overrides(scene, inst, "Mover"), ",", context.temp_allocator), "enableKeyboardInput,rotation")

	// Revert one value: the other stays.
	testing.expect(t, Scene_RevertComponentOverride(scene, mover, "rotation", ctx) != nil, "reverted")
	inst = GetChildrenView(scene.manager, scene.rootNode)[0]
	testing.expect_value(t, strings.join(field_overrides(scene, inst, "Mover"), ",", context.temp_allocator), "enableKeyboardInput")
	testing.expect_value(t, field_find(scene, inst, "Mover").rotation, 0)
	testing.expect_value(t, inst.position, [2]f32{100, 200})
	testing.expect(t, Scene_RevertComponentOverride(scene, field_find(scene, inst, "Mover"), "rotation", ctx) == nil, "no such override")

	// Apply a value inside the nested instance: it goes into the crate file
	// (the nested link's overrides), not the lid's.
	rel, text := Component_ApplyOverrideJSON(scene, field_find(scene, inst, "Lid"), "rotation", ctx, context.temp_allocator)
	testing.expect_value(t, rel, CRATE)
	testing.expectf(t, strings.contains(text, `"rotation": 45`), "the value is written: %s", text)
	testing.expectf(t, !strings.contains(text, `"enableKeyboardInput": true`), "only that value: %s", text)
	testing.expectf(t, !strings.contains(text, `100`), "not the instance's transform: %s", text)
	testing.expect_value(t, len(GetChildrenView(scene.manager, scene.rootNode)), 1) // (no node left behind)

	// Written, the instance's override matches the file once dropped.
	field_write("crate.component.json", text)
	Component_ForgetPrepared()
	testing.expect(t, Scene_RevertComponentOverride(scene, field_find(scene, inst, "Lid"), "rotation", ctx) != nil, "reverted")
	inst = GetChildrenView(scene.manager, scene.rootNode)[0]
	testing.expect_value(t, field_find(scene, inst, "Lid").rotation, 45)
	testing.expect_value(t, len(field_overrides(scene, inst, "Lid")), 0)
	lidFile, _ := os.read_entire_file(FIELD_DIR + "/components/lid.component.json", context.temp_allocator)
	testing.expect(t, !strings.contains(string(lidFile), "45"), "the nested file is unchanged")

	// A reflected property: apply it, then every new instance has it.
	rel, text = Component_ApplyOverrideJSON(scene, field_find(scene, inst, "Mover"), "enableKeyboardInput", ctx, context.temp_allocator)
	val, err := json.parse(transmute([]u8)text, allocator = context.temp_allocator)
	testing.expect_value(t, err, json.Error.None)
	_ = val
	field_write("crate.component.json", text)
	Component_ForgetPrepared()
	other := Scene_InstantiateComponent(scene, CRATE, nil, ctx)
	ProcessNodeQueues(scene.manager, ctx)
	testing.expect(t, (cast(^CharacterMoverNode)field_find(scene, other, "Mover")).enableKeyboardInput, "the file has the value")
	testing.expect_value(t, other.position, [2]f32{3, 4})
	keys := field_overrides(scene, other, "Mover")
	testing.expect(t, !slice.contains(keys, "enableKeyboardInput"), "no override on a new instance")
}
