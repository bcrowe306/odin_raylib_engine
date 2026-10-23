package engine

import "core:log"
import "core:strings"
import "core:testing"
import lua "vendor:lua/5.4"

// Script problems reach the sink with the Lua location: a get_node that
// finds nothing and an unknown get_property path warn once per call site.
@(test)
test_script_problems :: proc(t: ^testing.T) {
	@(static) got: [dynamic]string
	clear(&got)
	scriptLogSink = proc(level: log.Level, text: string) {
		if level == .Warning do append(&got, strings.clone(text, context.temp_allocator))
	}
	defer scriptLogSink = nil
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("problems", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	n := Node_CreateByTypeName(scene, "Node")
	n.name = "Hero"
	ProcessNodeQueues(scene.manager, &game.gameContext)
	ok := lua.L_dostring(game.scriptManager.L, `
local hero = Scene.find_node("Hero")
for i = 1, 3 do hero:get_node("Missing") end
local v = hero:get_property("nope")
`)
	testing.expect_value(t, ok, i32(0))
	testing.expect_value(t, len(got), 2) // once per site, not three times
	if len(got) < 2 do return
	testing.expect(t, strings.contains(got[0], `:3: get_node: no node at "Missing" from Hero`), got[0])
	testing.expect(t, strings.contains(got[1], `:4: get_property: Hero has no property "nope"`), got[1])
	delete(got)
	got = nil
}
