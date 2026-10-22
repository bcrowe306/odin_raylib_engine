package engine

import "core:encoding/json"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

@(test)
test_editor_link :: proc(t: ^testing.T) {
	dir, _ := filepath.join({os.get_env("TMPDIR", context.temp_allocator), "ore_link_test"}, context.temp_allocator)
	_ = os.remove_all(dir)
	defer os.remove_all(dir)
	write :: proc(dir, rel, text: string) {
		p, _ := filepath.join({dir, rel}, context.temp_allocator)
		_ = os.make_directory_all(filepath.dir(p, context.temp_allocator))
		_ = os.write_entire_file(p, transmute([]u8)text)
	}
	write(dir, "project.json", `{"name": "Link", "initial_scene": "scenes/a.scene.json", "scenes": ["scenes/a.scene.json"]}`)
	write(dir, "scenes/a.scene.json", `{"name": "a", "root": {"type": "Node", "name": "root", "children": [
		{"type": "TimerNode", "name": "Clock", "timer": {"duration": 100, "auto_start": true, "loop": false},
		 "children": [{"type": "Node", "name": "Hand", "position": [5, 6]}]}]}}`)

	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	testing.expect(t, game->loadProject(dir), "loaded")
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	game->run(1.0 / 60)

	// The tree, as JSON the editor parses.
	tree := EditorLink_TreeJSON(game)
	v, err := json.parse(transmute([]u8)tree, allocator = context.temp_allocator)
	testing.expect(t, err == .None, "tree is JSON")
	root := v.(json.Object)["root"].(json.Object)
	kids := root["children"].(json.Array)
	testing.expect(t, len(kids) == 1 && kids[0].(json.Object)["name"].(json.String) == "Clock", "Clock under root")

	// Inspect and set by path.
	node := EditorLink_NodeJSON(game, "Clock/Hand")
	testing.expect(t, strings.contains(node, `["position", "5.00,6.00"]`), "position shown")
	testing.expect(t, EditorLink_Set(game, "Clock/Hand", "position", "10, 20"), "set position")
	hand := Scene_FindNodeByName(game.sceneManager.currentScene, "Hand")
	testing.expect_value(t, hand.position, [2]f32{10, 20})
	testing.expect(t, !EditorLink_Set(game, "Nope", "position", "1,2"), "missing node")
	cam := Node_CreateByTypeName(game.sceneManager.currentScene, "CameraNode")
	p, _ := Node_FindProperty(cam, "followMode")
	testing.expect(t, Property_FromString(cam, p, "Manual") && Property_ToString(p) == "Manual", "enum from text")
	p2, _ := Node_FindProperty(cam, "shakeTypes")
	testing.expect(t, Property_FromString(cam, p2, "Random|Zoom") && Property_ToString(p2) == "Random|Zoom", "flags from text")

	// Pause freezes everything (the clock stops), step runs one frame.
	clock := cast(^TimerNode)Scene_FindNodeByName(game.sceneManager.currentScene, "Clock")
	EditorLink_Command(game, "pause")
	testing.expect(t, game.linkPaused, "paused")
	game.frozen = true
	e0 := clock.elapsed
	for _ in 0 ..< 5 do game->run(1.0 / 60)
	testing.expect_value(t, clock.elapsed, e0)
	game.frozen = false
	game->run(1.0 / 60)
	testing.expect(t, clock.elapsed > e0, "a step advances")
	EditorLink_Command(game, "resume")
	testing.expect(t, !game.linkPaused, "resumed")

	// A scene file saved by the editor: the running scene restarts with it.
	write(dir, "scenes/a.scene.json", `{"name": "a", "root": {"type": "Node", "name": "root", "children": [{"type": "Node", "name": "Fresh"}]}}`)
	testing.expect(t, Game_ReloadSceneFile(game, "scenes/a.scene.json"), "reloaded")
	game->run(1.0 / 60)
	testing.expect(t, Scene_FindNodeByName(game.sceneManager.currentScene, "Fresh") != nil, "new contents running")
}
