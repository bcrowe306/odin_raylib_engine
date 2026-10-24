package engine

import "core:testing"
import lua "vendor:lua/5.4"

// Visibility notifiers: entered / exited against the view (no camera: the
// virtual screen), the script's on_screen_* callbacks, Pause / Remove
// actions on the parent, no "exited" for one that starts off screen, and
// the manager's list following additions and removals.
@(test)
test_visibility_notifier :: proc(t: ^testing.T) {
	ScriptVFS_RegisterEmbedded("vis_counter.lua", `
local V = {}
V.properties = {}
function V:ready() entered = 0; exited = 0 end
function V:on_screen_entered() entered = entered + 1 end
function V:on_screen_exited() exited = exited + 1 end
return V
`)
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("vis", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running

	enemy := Node_CreateByTypeName(scene, "Node")
	enemy.name = "Enemy"
	enemy.position = {2000, 300} // off screen (the view: 0..1280 x 0..720)
	eye := cast(^VisibilityNotifierNode)Node_CreateByTypeName(scene, "VisibilityNotifierNode", enemy)
	eye.action = .Pause_Parent
	eye.gameContext = &game.gameContext
	Script_AttachToNode(eye, "vis_counter.lua", nil, &game.scriptManager)
	bullet := Node_CreateByTypeName(scene, "Node")
	bullet.name = "Bullet"
	bullet.position = {600, 300} // on screen
	life := cast(^VisibilityNotifierNode)Node_CreateByTypeName(scene, "VisibilityNotifierNode", bullet)
	life.action = .Remove_Parent
	life.size = {8, 8}
	ProcessNodeQueues(scene.manager, &game.gameContext)
	testing.expect_value(t, len(scene.manager.notifiers), 2)

	game->run(0.016)
	L := game.scriptManager.L
	get :: proc(L: ^lua.State, name: cstring) -> i64 {
		lua.getglobal(L, name)
		defer lua.pop(L, 1)
		return i64(lua.tointeger(L, -1))
	}
	testing.expect(t, enemy.paused && !eye.onScreen, "off screen at the start: paused")
	testing.expect_value(t, get(L, "exited"), 0) // no exited for a start off screen
	testing.expect(t, life.onScreen && life.seen, "the bullet is seen")

	// The enemy comes into view: resumed, entered.
	enemy.position = {1200, 300}
	game->run(0.016)
	testing.expect(t, !enemy.paused && eye.onScreen, "on screen: resumed")
	testing.expect_value(t, get(L, "entered"), 1)
	// Margin: a little outside still counts.
	enemy.position = {1340, 300} // rect 1308..1372: outside by 28
	eye.margin = 40
	game->run(0.016)
	testing.expect(t, eye.onScreen, "within the margin")
	eye.margin = 0
	game->run(0.016)
	testing.expect(t, !eye.onScreen && enemy.paused, "left: paused again")
	testing.expect_value(t, get(L, "exited"), 1)

	// The bullet flies off: removed with its notifier, the list follows.
	bullet.position = {-100, 300}
	game->run(0.016)
	game->run(0.016)
	testing.expect(t, Scene_FindNodeByName(scene, "Bullet") == nil, "bullet removed off screen")
	testing.expect_value(t, len(scene.manager.notifiers), 1)
	// Removing the enemy takes its notifier out of the list too.
	RemoveNode(scene.manager, enemy)
	game->run(0.016)
	testing.expect_value(t, len(scene.manager.notifiers), 0)

	// Saved and read back.
	n2 := cast(^VisibilityNotifierNode)Node_CreateByTypeName(scene, "VisibilityNotifierNode")
	n2.size = {100, 50}
	n2.action = .Disable_Parent
	ProcessNodeQueues(scene.manager, &game.gameContext)
	json := Scene_SerializeToJSON(scene)
	defer delete(json)
	testing.expect(t, contains(json, `"type": "VisibilityNotifierNode"`) && contains(json, `"size": [100, 50]`) && contains(json, `"action": "Disable_Parent"`), json)
}

@(private = "file")
contains :: proc(s, sub: string) -> bool {
	for i := 0; i + len(sub) <= len(s); i += 1 do if s[i:i + len(sub)] == sub do return true
	return false
}
