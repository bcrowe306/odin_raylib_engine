package engine

import os "osx"
import "core:strings"
import "core:testing"

// Component data safety (#71): instances survive problems with their files.

@(private = "file")
SAFETY_DIR :: "test_component_safety"
@(private = "file")
SAFETY_FILE :: SAFETY_DIR + "/components/crate.component.json"
@(private = "file")
CRATE :: `{"type": "Node", "name": "Crate", "children": [{"type": "Node", "name": "Lid", "position": [0, -10]}]}`

@(private = "file")
safety_game :: proc() -> ^Game {
	_ = os.make_directory_all(SAFETY_DIR + "/components")
	_ = os.write_entire_file(SAFETY_FILE, transmute([]u8)string(CRATE))
	game := new(Game)
	InitializeGame(game)
	AssetManager_SetProjectDir(&game.assetManager, SAFETY_DIR)
	return game
}

@(private = "file")
safety_load :: proc(game: ^Game, text, name: string) -> ^Scene {
	s := game->createScene(name, false)
	Scene_InstantiateFromJSON(s, transmute([]u8)text, &game.gameContext)
	ProcessNodeQueues(s.manager, &game.gameContext)
	return s
}

// #72: a scene whose component file is missing keeps the instance's link,
// transform and overrides when saved; when the file is back, it loads again.
@(test)
test_component_missing_file_keeps_instance :: proc(t: ^testing.T) {
	defer os.remove_all(SAFETY_DIR)
	game := safety_game()
	defer game->terminate()
	defer Component_ClearCaches()

	scene := game->createScene("safety", true)
	inst := Scene_InstantiateComponent(scene, "components/crate.component.json", nil, &game.gameContext)
	if inst == nil do testing.fail_now(t, "instance")
	inst.name = strings.clone("CrateA", inst.allocator)
	inst.position = {40, 50}
	ProcessNodeQueues(scene.manager, &game.gameContext)
	lid := Scene_FindNodeByName(scene, "Lid")
	lid.position = {0, -99} // an override
	original := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expect(t, strings.contains(original, `"overrides"`), "has an override")

	// The file goes missing: load and save again.
	os.remove(SAFETY_FILE)
	missing := safety_load(game, original, "safety_missing")
	ph := Scene_FindNodeByName(missing, "CrateA")
	testing.expect(t, ph != nil && ph.componentMissing && ph.componentPath == "components/crate.component.json", "a placeholder keeps the link")
	testing.expect(t, ph != nil && ph.position == {40, 50}, "and the transform")
	saved := Scene_SerializeToJSON(missing, context.temp_allocator)
	testing.expect(t, strings.contains(saved, `"component": "components/crate.component.json"`), "link saved")
	testing.expect(t, strings.contains(saved, `"overrides"`) && strings.contains(saved, "-99"), "overrides saved unchanged")

	// The file is back: the instance loads with its override.
	_ = os.write_entire_file(SAFETY_FILE, transmute([]u8)string(CRATE))
	back := safety_load(game, saved, "safety_back")
	again := Scene_FindNodeByName(back, "CrateA")
	testing.expect(t, again != nil && !again.componentMissing, "an instance again")
	l2 := Scene_FindNodeByName(back, "Lid")
	testing.expect(t, l2 != nil && l2.position == {0, -99}, "its override applies")
}

// #75: components that contain each other (A -> B -> A) are found, and
// loading one doesn't build a deep broken tree: the instance that closes
// the loop is a placeholder (its link kept) with a clear reason.
@(test)
test_component_loops :: proc(t: ^testing.T) {
	defer os.remove_all(SAFETY_DIR)
	game := safety_game()
	defer game->terminate()
	defer Component_ClearCaches()
	a :: SAFETY_DIR + "/components/a.component.json"
	b :: SAFETY_DIR + "/components/b.component.json"
	c :: SAFETY_DIR + "/components/c.component.json"
	_ = os.write_entire_file(a, transmute([]u8)string(`{"type": "Node", "name": "A", "children": [{"type": "Node", "name": "B", "component": "components/b.component.json"}]}`))
	_ = os.write_entire_file(b, transmute([]u8)string(`{"type": "Node", "name": "B", "children": [{"type": "Node", "name": "Inner", "children": [{"type": "Node", "name": "A", "component": "components/a.component.json"}]}]}`))
	_ = os.write_entire_file(c, transmute([]u8)string(`{"type": "Node", "name": "C", "children": [{"type": "Node", "name": "Crate", "component": "components/crate.component.json"}]}`))
	ctx := &game.gameContext

	testing.expect(t, Component_Contains(ctx, "components/a.component.json", "components/b.component.json"), "A contains B")
	testing.expect(t, Component_Contains(ctx, "components/a.component.json", "components/a.component.json"), "A contains A (through B)")
	testing.expect(t, Component_Contains(ctx, "components/c.component.json", "components/crate.component.json"), "C contains Crate")
	testing.expect(t, !Component_Contains(ctx, "components/c.component.json", "components/a.component.json"), "C doesn't contain A")
	testing.expect(t, !Component_Contains(ctx, "components/crate.component.json", "components/c.component.json"), "Crate doesn't contain C")

	scene := game->createScene("loops", true)
	inst := Scene_InstantiateComponent(scene, "components/a.component.json", nil, ctx)
	testing.expect(t, inst != nil, "A loads")
	ProcessNodeQueues(scene.manager, ctx)
	count := 0
	for n in scene.manager.nodes do if n != nil do count += 1
	// root, A, B, Inner, and the placeholder for the inner A: no deeper.
	testing.expectf(t, count == 5, "one level of the loop, not 8 (%d nodes)", count)
	ph: ^Node
	for n in scene.manager.nodes do if n != nil && n.componentMissing do ph = n
	testing.expect(t, ph != nil && ph.componentPath == "components/a.component.json", "the inner A is a placeholder that keeps its link")
	testing.expect(t, ph != nil && strings.contains(ph.componentProblem, "contains itself"), "with the reason")
}
