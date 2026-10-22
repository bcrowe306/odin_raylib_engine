package engine

import "core:slice"
import "core:strings"
import "core:testing"

// Editor-only scene data: guides and per-node lock / hide, saved with the
// scene; hidden nodes (and their children) skipped only when the editor asks.
@(test)
test_editor_guides_and_flags :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("flags", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)

	bg := Node_CreateByTypeName(scene, "TextureNode")
	bg.name = "Background"
	bg.editorLocked = true
	group := Node_CreateByTypeName(scene, "TextureNode")
	group.name = "Group"
	group.editorHidden = true
	child := Node_CreateByTypeName(scene, "TextureNode", group)
	child.name = "Child"
	ProcessNodeQueues(scene.manager, &game.gameContext)
	scene.guides[0] = {true, 120}
	scene.guides[1] = {false, -40.5}
	scene.guideCount = 2

	// Hidden subtree: drawn by the game, skipped in the editor.
	count :: proc(scene: ^Scene) -> int {
		n := 0
		for b in Scene_CollectRenderables(scene) do n += len(b)
		return n
	}
	all := count(scene)
	Render_HideEditorHidden = true
	hidden := count(scene)
	Render_HideEditorHidden = false
	testing.expect_value(t, all - hidden, 2)
	b := Scene_CollectRenderables(scene)
	testing.expect(t, slice.contains(b[child.layer][:], child), "the game still draws it")

	text := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expect(t, strings.contains(text, `"guides": [{"x": 120}, {"y": -40.5}]`), "guides saved")
	testing.expect(t, strings.contains(text, `"editor_locked": true`) && strings.contains(text, `"editor_hidden": true`), "flags saved")
	s2 := game->createScene("flags2", false)
	Scene_InstantiateFromJSON(s2, transmute([]u8)text, &game.gameContext)
	ProcessNodeQueues(s2.manager, &game.gameContext)
	testing.expect_value(t, s2.guideCount, 2)
	testing.expect(t, s2.guides[0] == {true, 120} && s2.guides[1] == {false, -40.5}, "guides loaded")
	bg2 := Scene_FindNodeByName(s2, "Background")
	g2 := Scene_FindNodeByName(s2, "Group")
	c2 := Scene_FindNodeByName(s2, "Child")
	testing.expect(t, bg2 != nil && bg2.editorLocked && !bg2.editorHidden, "lock loaded")
	testing.expect(t, g2 != nil && g2.editorHidden && c2 != nil && !c2.editorHidden, "hide loaded")
}
