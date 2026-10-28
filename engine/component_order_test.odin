package engine

import os "osx"
import "core:strings"
import "core:testing"

// #78: an instance saves the order of its children where it differs from
// the component ($order), and nodes added to it keep their place.

@(private = "file")
ORDER_DIR :: "test_component_order"
@(private = "file")
ORDER_FILE :: ORDER_DIR + "/components/crate.component.json"
@(private = "file")
ORDER_REL :: "components/crate.component.json"
@(private = "file")
ABC :: `{"type": "Node", "name": "Crate", "uid": "r00t0000", "children": [{"type": "Node", "name": "A", "uid": "aaaaaaaa"}, {"type": "Node", "name": "B", "uid": "bbbbbbbb"}, {"type": "Node", "name": "C", "uid": "cccccccc"}]}`

@(private = "file")
order_names :: proc(scene: ^Scene, inst: string) -> string {
	root := Scene_FindNodeByName(scene, inst)
	if root == nil do return "?"
	names := make([dynamic]string, context.temp_allocator)
	for c in GetChildrenView(scene.manager, root) do append(&names, c.name)
	return strings.join(names[:], ",", context.temp_allocator)
}

@(private = "file")
order_load :: proc(game: ^Game, text, name: string) -> ^Scene {
	s := game->createScene(name, false)
	Scene_InstantiateFromJSON(s, transmute([]u8)text, &game.gameContext)
	ProcessNodeQueues(s.manager, &game.gameContext)
	return s
}

@(test)
test_component_child_order :: proc(t: ^testing.T) {
	_ = os.make_directory_all(ORDER_DIR + "/components")
	_ = os.write_entire_file(ORDER_FILE, transmute([]u8)string(ABC))
	defer os.remove_all(ORDER_DIR)
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	defer Component_ClearCaches()
	AssetManager_SetProjectDir(&game.assetManager, ORDER_DIR)
	ctx := &game.gameContext

	scene := game->createScene("order", false)
	one := Scene_InstantiateComponent(scene, ORDER_REL, nil, ctx)
	two := Scene_InstantiateComponent(scene, ORDER_REL, nil, ctx)
	three := Scene_InstantiateComponent(scene, ORDER_REL, nil, ctx)
	if one == nil || two == nil || three == nil do testing.fail_now(t, "instances")
	one.name = strings.clone("One", one.allocator)
	two.name = strings.clone("Two", two.allocator)
	three.name = strings.clone("Three", three.allocator)
	ProcessNodeQueues(scene.manager, ctx)

	// One: C moved first, a node added between C and A.
	MoveChild(scene.manager, one, Scene_FindNodeByName(scene, "C"), 0)
	added := Node_CreateByTypeName(scene, "Node", one)
	added.name = strings.clone("N", added.allocator)
	ProcessNodeQueues(scene.manager, ctx)
	MoveChild(scene.manager, one, added, 1)
	testing.expect_value(t, order_names(scene, "One"), "C,N,A,B")
	// Three: a node added at the end only (the natural place: no order).
	extra := Node_CreateByTypeName(scene, "Node", three)
	extra.name = strings.clone("X", extra.allocator)
	ProcessNodeQueues(scene.manager, ctx)

	saved := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expectf(t, strings.count(saved, `"$order"`) == 1, "one instance stores an order: %s", saved)
	testing.expect(t, strings.contains(saved, `"$order": {".": ["cccccccc", "+N", "aaaaaaaa", "bbbbbbbb"]}`), "by uid, added nodes by +name")

	again := order_load(game, saved, "order_2")
	testing.expect_value(t, order_names(again, "One"), "C,N,A,B")
	testing.expect_value(t, order_names(again, "Two"), "A,B,C")
	testing.expect_value(t, order_names(again, "Three"), "A,B,C,X")
	resaved := Scene_SerializeToJSON(again, context.temp_allocator)
	testing.expect(t, strings.contains(resaved, `"$order": {".": ["cccccccc", "+N", "aaaaaaaa", "bbbbbbbb"]}`) && strings.count(resaved, `"$order"`) == 1, "saved again: the same order")

	// The component reorders its children (and gains one): instances that
	// didn't reorder follow it; One keeps its order, the new child last.
	_ = os.write_entire_file(ORDER_FILE, transmute([]u8)string(`{"type": "Node", "name": "Crate", "uid": "r00t0000", "children": [{"type": "Node", "name": "B", "uid": "bbbbbbbb"}, {"type": "Node", "name": "D", "uid": "dddddddd"}, {"type": "Node", "name": "A", "uid": "aaaaaaaa"}, {"type": "Node", "name": "C", "uid": "cccccccc"}]}`))
	third := order_load(game, saved, "order_3")
	testing.expect_value(t, order_names(third, "Two"), "B,D,A,C")
	testing.expect_value(t, order_names(third, "Three"), "B,D,A,C,X")
	testing.expect_value(t, order_names(third, "One"), "C,N,A,B,D")

	// Reverting the instance root's overrides drops its order.
	fresh := Scene_RevertComponentOverrides(third, Scene_FindNodeByName(third, "One"), ctx)
	testing.expect(t, fresh != nil, "reverted")
	testing.expect_value(t, order_names(third, "One"), "B,D,A,C")
}

// Node_ComponentOverrides lists a changed order on the parent, and Revert on
// that node drops it.
@(test)
test_component_child_order_revert :: proc(t: ^testing.T) {
	_ = os.make_directory_all(ORDER_DIR + "/components")
	_ = os.write_entire_file(ORDER_FILE, transmute([]u8)string(`{"type": "Node", "name": "Crate", "uid": "r00t0000", "children": [{"type": "Node", "name": "P", "uid": "pppppppp", "children": [{"type": "Node", "name": "A", "uid": "aaaaaaaa"}, {"type": "Node", "name": "B", "uid": "bbbbbbbb"}]}]}`))
	defer os.remove_all(ORDER_DIR)
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	defer Component_ClearCaches()
	AssetManager_SetProjectDir(&game.assetManager, ORDER_DIR)
	ctx := &game.gameContext
	scene := game->createScene("order_rv", false)
	inst := Scene_InstantiateComponent(scene, ORDER_REL, nil, ctx)
	if inst == nil do testing.fail_now(t, "instance")
	ProcessNodeQueues(scene.manager, ctx)
	p := Scene_FindNodeByName(scene, "P")
	MoveChild(scene.manager, p, Scene_FindNodeByName(scene, "B"), 0)
	testing.expect_value(t, strings.join(Node_ComponentOverrides(scene.manager, p), ",", context.temp_allocator), "child order")
	Scene_RevertComponentOverrides(scene, p, ctx)
	p = Scene_FindNodeByName(scene, "P")
	kids := GetChildrenView(scene.manager, p)
	testing.expect(t, len(kids) == 2 && kids[0].name == "A", "the component's order again")
}
