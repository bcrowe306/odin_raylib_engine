package engine

import "core:encoding/json"
import os "osx"
import "core:path/filepath"
import "core:strings"
import "core:testing"

@(test)
test_editor_link :: proc(t: ^testing.T) {
	dir, _ := filepath.join({Engine_TempDir(), "rayzr_link_test"}, context.temp_allocator)
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
	testing.expect(t, strings.contains(node, `["position", "5.00,6.00", "vec2"`), "position shown")
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

// The Game tab's live script values: inspect lists "script.<name>" read
// from self; set changes them in the running script.
@(test)
test_editor_link_script_props :: proc(t: ^testing.T) {
	ScriptVFS_RegisterEmbedded("link_props.lua", `
local S = {}
S.properties = {
    speed = { type = "float", default = 240 },
    mode  = { type = "enum", values = {"Idle", "Run"} },
    path  = { type = "array", of = "float", default = {1, 2} },
}
return S
`)
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("link", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	n := Node_CreateByTypeName(scene, "Node")
	n.name = "Runner"
	n.gameContext = &game.gameContext
	Script_AttachToNode(n, "link_props.lua", nil, &game.scriptManager)
	ProcessNodeQueues(scene.manager, &game.gameContext)

	text := EditorLink_NodeJSON(game, "Runner")
	testing.expect(t, strings.contains(text, `["script.speed", "240", "float"`), text)
	testing.expect(t, strings.contains(text, `["script.mode", "Idle", "enum", "Idle|Run`), text)
	testing.expect(t, strings.contains(text, `["script.path", "[1, 2]"`) || strings.contains(text, `["script.path", "[1.0, 2.0]"`), text)
	testing.expect(t, EditorLink_Set(game, "Runner", "script.speed", "99.5"), "set number")
	testing.expect(t, EditorLink_Set(game, "Runner", "script.mode", "Run"), "set enum")
	testing.expect(t, !EditorLink_Set(game, "Runner", "script.nope", "1"), "unknown property")
	text = EditorLink_NodeJSON(game, "Runner")
	testing.expect(t, strings.contains(text, `["script.speed", "99.5"`) && strings.contains(text, `["script.mode", "Run"`), text)
}

// The live remote tree's tools: unchanged trees answer "same" by hash,
// properties carry their widget kind (enum names, ranges), pick finds the
// topmost drawn node (UI first), highlight / remove, and Node_SetFromText
// (Apply to Scene).
@(test)
test_editor_link_remote_tools :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("remote", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	game.virtualSize = {1280, 720}
	defer {delete(editorLink.highlight); editorLink.highlight = ""}
	btn := cast(^UIButtonNode)Node_CreateByTypeName(scene, "UIButtonNode")
	btn.name = "OkZz"
	btn.position = {100, 100}
	btn.size = {120, 40}
	cam := cast(^CameraNode)Node_CreateByTypeName(scene, "CameraNode")
	cam.name = "CamZz"
	ProcessNodeQueues(scene.manager, &game.gameContext)
	for _ in 0 ..< 3 do game->run(1.0 / 60)

	// Tree hash: the same tree, the same hash; a new node changes it.
	_, h1 := EditorLink_TreeRootJSON(game)
	_, h2 := EditorLink_TreeRootJSON(game)
	testing.expect(t, h1 == h2, "stable hash")
	extra := Node_CreateByTypeName(scene, "Node")
	ProcessNodeQueues(scene.manager, &game.gameContext)
	_, h3 := EditorLink_TreeRootJSON(game)
	testing.expect(t, h3 != h1, "a new node changes the hash")
	tree := EditorLink_TreeJSON(game)
	testing.expect(t, strings.contains(tree, `"hash": "`), "the hash is sent with the tree")

	// Typed properties.
	node := EditorLink_NodeJSON(game, "CamZz")
	testing.expect(t, strings.contains(node, `["rotation", "0.00", "float"`), "transform kinds")
	testing.expect(t, strings.contains(node, `"followMode", "`) && strings.contains(node, `"enum", "`), "an enum with its names")
	testing.expect(t, strings.contains(node, `["global", `) && strings.contains(node, `"ro"`), "read-only global position")

	// Pick: the button under the point; empty space: nothing.
	cam.currentPosition = {640, 360} // (looking at the screen's middle: world = screen)
	testing.expect(t, EditorLink_Pick(game, {150, 120}) == btn, "picks the UI button")
	testing.expect(t, EditorLink_Pick(game, {900, 600}) == nil, "nothing there")
	testing.expect_value(t, link_path(scene.manager, scene.rootNode, btn), "OkZz")

	// Highlight and remove.
	EditorLink_Command(game, "highlight OkZz")
	testing.expect_value(t, editorLink.highlight, "OkZz")
	EditorLink_Command(game, "highlight")
	testing.expect_value(t, editorLink.highlight, "")
	EditorLink_Command(game, "remove " + "OkZz")
	ProcessNodeQueues(scene.manager, &game.gameContext)
	testing.expect(t, Scene_FindNodeByName(scene, "OkZz") == nil, "removed")
	_ = extra

	// Node_SetFromText (the editor's Apply to Scene).
	testing.expect(t, Node_SetFromText(game, cam, "rotation", "30") && cam.rotation == 30, "transform")
	testing.expect(t, Node_SetFromText(game, cam, "followMode", "Manual"), "enum")
	testing.expect(t, !Node_SetFromText(game, cam, "noSuchProp", "1"), "unknown property")
}
