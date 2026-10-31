package engine

import "core:strings"
import "core:testing"
import lua "lua54"

// #294: dialogue choices (picked with move_up / move_down, taken with the
// advance action or dialogue_choose; "chosen", then the next line unless the
// handler showed new ones), auto advance and skip (both stop at choices).
@(test)
test_dialogue_choices :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("choices", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	ctx := &game.gameContext
	input := &game.input
	frames :: proc(game: ^Game, n: int) {for _ in 0 ..< n do game->run(1.0 / 60)}
	tap :: proc(game: ^Game, a: InputAction) {
		Input_SetSimulatedAction(&game.input, a, true)
		game->run(1.0 / 60)
		Input_SetSimulatedAction(&game.input, a, false)
		game->run(1.0 / 60)
	}

	d := cast(^DialogueNode)Node_CreateByTypeName(scene, "DialogueNode")
	d.name = strings.clone("Box", d.allocator)
	d.revealSpeed = 0
	Chosen :: struct {last, count: int}
	chosen: Chosen
	d.onChosen->subscribe(proc(src: rawptr, v: EventValue, ctx: ^GameContext, ud: rawptr) {
		c := cast(^Chosen)ud
		c.last = v.(int) or_else -1
		c.count += 1
	}, &chosen)
	ProcessNodeQueues(scene.manager, ctx)

	// A line with choices waits; move_down picks the second, confirm takes it.
	DialogueNode_Show(d, {{"Ada", "Left or right?", "", {"Left", "Right", "Back"}}, {"Ada", "Off we go.", "", nil}})
	frames(game, 2)
	testing.expect(t, DialogueNode_HasChoices(d) && d.lineDone, "choices up")
	tap(game, .MoveDown)
	tap(game, .MoveDown)
	tap(game, .MoveUp)
	testing.expect_value(t, d.choice, 1)
	tap(game, .Confirm)
	testing.expect_value(t, chosen.last, 2)
	testing.expect_value(t, d.current, 1) // the next line
	testing.expect(t, !DialogueNode_Choose(d, 0, ctx), "no choices on a plain line")
	tap(game, .Confirm)
	testing.expect(t, !DialogueNode_IsOpen(d), "closed after the last line")
	testing.expect(t, chosen.count == 1, "one choice taken")

	// move_up wraps to the last choice.
	DialogueNode_Show(d, {{"", "Pick", "", {"A", "B", "C"}}})
	frames(game, 2)
	tap(game, .MoveUp)
	testing.expect_value(t, d.choice, 2)

	// Auto advance passes plain lines by itself and stops at choices.
	DialogueNode_Show(d, {{"", "One", "", nil}, {"", "Two", "", nil}, {"", "Pick", "", {"A", "B"}}})
	d.autoAdvance, d.autoDelay = true, 0.2
	frames(game, 60)
	testing.expect(t, d.current == 2 && DialogueNode_HasChoices(d), "auto stopped at the choices")
	frames(game, 60)
	testing.expect_value(t, d.current, 2)
	d.autoAdvance = false

	// Skip: lines show and pass at once, typing or not; stops at choices.
	d.revealSpeed = 5
	DialogueNode_Show(d, {{"", "A rather long line that would take a while to type", "", nil}, {"", "Another", "", nil}, {"", "Pick", "", {"A", "B"}}})
	d.skip = true
	frames(game, 12)
	testing.expect(t, d.current == 2 && d.lineDone, "skipped to the choices")
	d.skip, d.revealSpeed = false, 0

	// Lua: choices in the line table, dialogue_choose, the "chosen" event; a
	// handler that shows new lines keeps them.
	L := game.scriptManager.L
	code: cstring = `
local box = Scene.find_node("Box")
picked = 0
box:connect("chosen", function(i)
  picked = i
  box:dialogue_show({ { speaker = "Ada", text = "You chose " .. i } })
end)
box:dialogue_show({ { speaker = "Ada", text = "Which?", choices = { "Tea", "Coffee" } } })`
	if lua.L_dostring(L, code) != 0 do testing.fail_now(t, string(lua.tostring(L, -1)))
	frames(game, 2)
	if lua.L_dostring(L, `waiting = Scene.find_node("Box"):dialogue_has_choices(); ok = Scene.find_node("Box"):dialogue_choose(2); bad = Scene.find_node("Box"):dialogue_choose(5)`) != 0 {
		testing.fail_now(t, string(lua.tostring(L, -1)))
	}
	get :: proc(L: ^lua.State, n: cstring) -> bool {
		lua.getglobal(L, n)
		defer lua.pop(L, 1)
		return bool(lua.toboolean(L, -1))
	}
	testing.expect(t, get(L, "waiting") && get(L, "ok") && !get(L, "bad"), "has_choices, choose, out of range")
	lua.getglobal(L, "picked")
	testing.expect_value(t, int(lua.tointeger(L, -1)), 2)
	lua.pop(L, 1)
	testing.expect(t, DialogueNode_IsOpen(d) && d.current == 0 && d.lines[0].text == "You chose 2", "the handler's lines stay")
	if lua.L_dostring(L, `Scene.find_node("Box"):dialogue_set_auto(true, 0.5); Scene.find_node("Box"):dialogue_set_skip(true)`) != 0 {
		testing.fail_now(t, string(lua.tostring(L, -1)))
	}
	testing.expect(t, d.autoAdvance && d.autoDelay == 0.5 && d.skip, "set_auto / set_skip")
	_ = input
	free_all(context.temp_allocator)
}
