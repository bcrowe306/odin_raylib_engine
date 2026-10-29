package engine

import "core:fmt"
import os "osx"
import "core:strings"
import "core:testing"
import lua "lua54"

// The Components guide's tutorial (engine/docs/components.md), run for real:
// its slime script, read from the guide, in a component spawned with and
// without values - each slime patrols at its own speed and counts its own
// hits.

@(private = "file")
CG_DIR :: "test_components_guide"

// cg_tutorial_script: the guide's first ```lua block (the slime script),
// its list indentation removed.
@(private = "file")
cg_tutorial_script :: proc(t: ^testing.T) -> (string, bool) {
	data, err := os.read_entire_file("engine/docs/components.md", context.temp_allocator)
	if !testing.expect(t, err == nil, "the guide") do return "", false
	text := string(data)
	at := strings.index(text, "---@class Slime")
	if !testing.expect(t, at >= 0, "the tutorial's script") do return "", false
	start := strings.last_index(text[:at], "```lua\n") + len("```lua\n")
	end := start + strings.index(text[start:], "```")
	sb := strings.builder_make(context.temp_allocator)
	for line in strings.split_lines(text[start:end], context.temp_allocator) {
		strings.write_string(&sb, strings.trim_prefix(line, "   "))
		strings.write_byte(&sb, '\n')
	}
	return strings.to_string(sb), true
}

@(private = "file")
cg_lua :: proc(t: ^testing.T, L: ^lua.State, code: string) -> bool {
	if lua.L_dostring(L, strings.clone_to_cstring(code, context.temp_allocator)) != 0 {
		testing.expectf(t, false, "Lua: %s", lua.tostring(L, -1))
		lua.pop(L, 1)
		return false
	}
	return true
}

@(private = "file")
cg_number :: proc(L: ^lua.State, expr: string) -> f64 {
	if lua.L_dostring(L, strings.clone_to_cstring(fmt.tprintf("return %s", expr), context.temp_allocator)) != 0 {
		lua.pop(L, 1)
		return -9999
	}
	v := f64(lua.tonumber(L, -1))
	lua.pop(L, 1)
	return v
}

@(test)
test_components_guide_tutorial :: proc(t: ^testing.T) {
	script, ok := cg_tutorial_script(t)
	if !ok do return
	_ = os.make_directory_all(CG_DIR + "/components")
	_ = os.make_directory_all(CG_DIR + "/scripts")
	defer os.remove_all(CG_DIR)
	_ = os.write_entire_file(CG_DIR + "/scripts/slime.lua", transmute([]u8)script)
	slime := `{"type": "Node", "name": "Slime", "uid": "s1me0000", "script": {"path": "scripts/slime.lua"},
		"exposed": [{"uid": ".", "property": "script.speed", "label": ""}, {"uid": ".", "property": "script.health", "label": ""}]}`
	_ = os.write_entire_file(CG_DIR + "/components/Slime.component.json", transmute([]u8)slime)

	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	AssetManager_SetProjectDir(&game.assetManager, CG_DIR)
	scene := game->createScene("guide", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	L := game.scriptManager.L

	// Step 8: one with the defaults, a tough one with values.
	SPAWN :: `
slow = Scene.instantiate("components/Slime.component.json", nil, 100, 50)
tough = Scene.instantiate("components/Slime.component.json", nil, 100, 80, { speed = 90, health = 5 })
`
	if !cg_lua(t, L, SPAWN) do return
	game->run(1.0 / 60)
	testing.expect_value(t, cg_number(L, "slow:get_script().speed"), 40)
	testing.expect_value(t, cg_number(L, "tough:get_script().speed"), 90)
	testing.expect_value(t, cg_number(L, "tough:get_script().hp"), 5)
	for n in GetChildrenView(scene.manager, scene.rootNode) do testing.expect_value(t, len(n.componentExposed), 2) // (step 4)

	// Patrol: half a second in, the tough one went further; over five
	// seconds both stay within their range.
	for _ in 0 ..< 30 do game->run(1.0 / 60)
	slowX, toughX := cg_number(L, "(slow:get_position())"), cg_number(L, "(tough:get_position())")
	testing.expectf(t, toughX - 100 > slowX - 100 + 10, "the tough one is faster: %v vs %v", toughX, slowX)
	for _ in 0 ..< 300 {
		game->run(1.0 / 60)
		for name in ([]string{"slow", "tough"}) {
			x := cg_number(L, fmt.tprintf("(%s:get_position())", name))
			if !testing.expectf(t, x > 100 - 48 - 3 && x < 100 + 48 + 3, "%s patrols within its range: %v", name, x) do return
		}
	}

	// Each counts its own hits.
	if !cg_lua(t, L, `for i = 1, 4 do tough:get_script():hit() end`) do return
	testing.expect_value(t, cg_number(L, "tough:get_script().hp"), 1)
	testing.expect_value(t, cg_number(L, "slow:get_script().hp"), 3)
	before := len(GetChildrenView(scene.manager, scene.rootNode))
	if !cg_lua(t, L, `tough:get_script():hit()`) do return
	game->run(1.0 / 60)
	testing.expect_value(t, len(GetChildrenView(scene.manager, scene.rootNode)), before - 1)
}
