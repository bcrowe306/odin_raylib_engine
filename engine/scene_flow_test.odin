package engine

import os "osx"
import "core:path/filepath"
import "core:testing"
import "core:time"
import b2 "vendor:box2d"
import lua "lua54"

@(test)
test_pausing :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("pause", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running

	world := cast(^TimerNode)Node_CreateByTypeName(scene, "TimerNode")
	world.name = "World"
	world.running = true
	world->setDuration(100)
	menu := cast(^TimerNode)Node_CreateByTypeName(scene, "TimerNode", world)
	menu.name = "Menu"
	menu.running = true
	menu->setDuration(100)
	menu.pauseMode = .Always
	body := cast(^DynamicBodyNode)Node_CreateByTypeName(scene, "DynamicBodyNode", world)
	body.name = "Crate"
	box: PhysicsShape
	PhysicsShape_InitDefault(&box, .Box) // a body needs a shape to have mass
	DynamicBodyNode_AddShape(body, box)
	game->run(1.0 / 60)

	// The game paused: pausable nodes and physics stop, "always" ones run.
	Game_SetPaused(game, true)
	w0, m0 := world.elapsed, menu.elapsed
	y0 := body.globalPosition.y
	for _ in 0 ..< 10 do game->run(1.0 / 60)
	testing.expect(t, world.elapsed == w0 && world.pausedNow, "world paused")
	testing.expect(t, menu.elapsed > m0 && !menu.pausedNow, "menu still runs")
	testing.expect_value(t, body.globalPosition.y, y0)
	Game_SetPaused(game, false)
	for _ in 0 ..< 10 do game->run(1.0 / 60)
	testing.expect(t, world.elapsed > w0 && body.globalPosition.y > y0, "resumed: falling again")

	// A paused subtree: its body is disabled while paused.
	world.paused = true
	game->run(1.0 / 60)
	testing.expect(t, !b2.Body_IsEnabled(body.bodyId) && body.pausedNow, "body frozen with its parent")
	y1 := body.globalPosition.y
	for _ in 0 ..< 10 do game->run(1.0 / 60)
	testing.expect_value(t, body.globalPosition.y, y1)
	testing.expect(t, !menu.pausedNow, "always child runs in a paused subtree")
	world.paused = false
	game->run(1.0 / 60)
	testing.expect(t, b2.Body_IsEnabled(body.bodyId), "body back")

	// Saved and loaded; Lua.
	world.pauseMode = .Pausable
	text := Scene_SerializeToJSON(scene, context.temp_allocator)
	s2 := game->createScene("pause2", false)
	Scene_InstantiateFromJSON(s2, transmute([]u8)text, &game.gameContext)
	ProcessNodeQueues(s2.manager, &game.gameContext)
	m2 := Scene_FindNodeByName(s2, "Menu")
	testing.expect(t, m2 != nil && m2.pauseMode == .Always, "pause mode saved")
	L := game.scriptManager.L
	ok := lua.L_dostring(L, `
Engine.set_paused(true)
p = tostring(Engine.is_paused())
local w = Scene.find_node("World")
w:set_paused(true)
w:set_pause_mode("always")
`)
	testing.expect(t, ok == 0 && game.treePaused && world.paused && world.pauseMode == .Always, "lua pause")
}

@(test)
test_scene_transitions_and_preload :: proc(t: ^testing.T) {
	dir, _ := filepath.join({Engine_TempDir(), "ore_flow_test"}, context.temp_allocator)
	_ = os.remove_all(dir)
	defer os.remove_all(dir)
	write :: proc(dir, rel, text: string) {
		p, _ := filepath.join({dir, rel}, context.temp_allocator)
		_ = os.make_directory_all(filepath.dir(p, context.temp_allocator))
		_ = os.write_entire_file(p, transmute([]u8)text)
	}
	write(dir, "project.json", `{"name": "Flow", "initial_scene": "scenes/a.scene.json", "scenes": ["scenes/a.scene.json", "scenes/b.scene.json"]}`)
	write(dir, "scenes/a.scene.json", `{"name": "a", "root": {"type": "Node", "name": "root"}}`)
	write(dir, "scenes/b.scene.json", `{"name": "b", "root": {"type": "Node", "name": "root", "children": [
		{"type": "TextureNode", "name": "Sky", "texture_path": "textures/sky.png"},
		{"type": "TextureNode", "name": "Ground", "texture": "textures/ground.png"},
		{"type": "NineSliceNode", "name": "Panel", "properties": {"texturePath": "ui/panel.png"}},
		{"type": "SoundNode", "name": "Boom", "audio": "audio/boom.wav"},
		{"type": "MusicNode", "name": "Theme", "audio": "audio/theme.ogg"},
		{"type": "Node", "name": "Enemy", "component": "components/enemy.component.json"}]}}`)
	write(dir, "components/enemy.component.json", `{"type": "TextureNode", "name": "Enemy", "texture_path": "textures/enemy.png"}`)

	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	testing.expect(t, game->loadProject(dir), "loaded")
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	a := game.sceneManager.currentScene
	b := game.sceneManager.scenes["b"]
	testing.expect(t, a != nil && a.name == "a" && b != nil, "two scenes")

	// Preloading collects the scene's (and its components') assets.
	Scene_PreloadBegin(game, b)
	testing.expect_value(t, len(game.preloads[b].items), 6) // "texture", legacy "texture_path", a property's image, audio, a component's texture
	testing.expect_value(t, Scene_PreloadProgress(game, b), 0)
	Scene_PreloadStep(game, time.Second) // headless: counted, nothing to load
	testing.expect_value(t, Scene_PreloadProgress(game, b), 1)

	// Fade over 0.2 s: still on A while covering, switch, then uncover.
	Game_ChangeSceneWith(game, b, .Fade, 0.2)
	game->run(0.1)
	testing.expect(t, game.sceneManager.currentScene == a && Scene_TransitionAmount(game) > 0.3, "covering")
	game->run(0.15)
	game->run(0.01)
	testing.expect(t, game.sceneManager.currentScene == b && game.transition.active, "switched under the cover")
	testing.expect(t, !(b in game.preloads), "preload released once the scene loaded")
	game->run(0.3)
	testing.expect(t, !game.transition.active && Scene_TransitionAmount(game) == 0, "uncovered")

	// From Lua.
	L := game.scriptManager.L
	ok := lua.L_dostring(L, `Scene.change_scene("a", {transition = "circle", duration = 0.1, color = {1, 1, 1}})`)
	testing.expect(t, ok == 0 && game.transition.active && game.transition.kind == .Circle && game.transition.color == {255, 255, 255, 255}, "lua transition")
	for _ in 0 ..< 20 do game->run(0.02)
	testing.expect(t, game.sceneManager.currentScene == a, "back on A")
}
