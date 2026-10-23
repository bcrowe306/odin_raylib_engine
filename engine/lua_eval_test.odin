package engine

import "core:strings"
import "core:testing"
import lua "vendor:lua/5.4"

// The Console's Lua line: expressions show their values, statements run,
// errors come back as text; nodes / vectors / tables print readably.
@(test)
test_lua_eval :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("eval", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	hero := Node_CreateByTypeName(scene, "TextureNode")
	hero.name = "Hero"
	ProcessNodeQueues(scene.manager, &game.gameContext)
	L := game.scriptManager.L
	check :: proc(t: ^testing.T, L: ^lua.State, code, want: string, wantOk := true, loc := #caller_location) {
		text, ok := Lua_Eval(L, code, context.temp_allocator)
		testing.expectf(t, ok == wantOk && strings.contains(text, want), "%s -> %v %q", code, ok, text, loc = loc)
	}
	check(t, L, "1 + 2", "3")
	check(t, L, "score = 10", "ok")
	check(t, L, "score * 1.5", "15")
	check(t, L, "=score, 'hi'", `10, "hi"`)
	check(t, L, "Scene.find_node('Hero')", `Node "Hero" (TextureNode)`)
	check(t, L, "Vec2(1, 2) + Vec2(3, 4)", "4")
	check(t, L, "{1, 2, x = 3}", "{1, 2, x = 3}")
	check(t, L, "nosuch.field", "attempt to index", false)
	check(t, L, "local = ", "expected", false)
	testing.expect_value(t, lua.gettop(L), 0) // nothing left on the stack
}
