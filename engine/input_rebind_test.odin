package engine

import os "osx"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import lua "lua54"
import rl "vendor:raylib"

// Player rebinding: slots, conflicts (clear / swap / allow), names for the
// player, saving and loading over the project's bindings, reset, and the
// Lua API with a captured input calling on_done.
@(test)
test_input_rebinding :: proc(t: ^testing.T) {
	dir, _ := filepath.join({Engine_TempDir(), "ore_rebind_test"}, context.temp_allocator)
	_ = os.remove_all(dir)
	defer os.remove_all(dir)
	Save_SetDirectory(dir)
	defer Save_Reset()

	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	input := &game.input
	actions := make([dynamic]Input_Action_Config, context.temp_allocator)
	jump := Input_Action_Config{name = "jump", bindings = make([dynamic]InputBinding, context.temp_allocator)}
	append(&jump.bindings, InputBinding{deviceType = .KeyboardKey, key = .SPACE}, InputBinding{deviceType = .GamepadButton, gamepadButton = .RIGHT_FACE_DOWN})
	dash := Input_Action_Config{name = "dash", bindings = make([dynamic]InputBinding, context.temp_allocator)}
	append(&dash.bindings, InputBinding{deviceType = .KeyboardKey, key = .LEFT_SHIFT})
	append(&actions, jump, dash)
	Input_ApplyActionConfigs(input, actions[:])
	Input_RebindSetDefaults(input, actions[:])
	input.rebind.autoSave = false

	key :: proc(k: rl.KeyboardKey) -> InputBinding {return {deviceType = .KeyboardKey, key = k}}
	jm := Input_MappingOf(input, "jump")
	// Slot 0: replaces the keyboard binding, keeps the gamepad one.
	Input_SetBinding(input, "jump", 0, key(.W))
	testing.expect(t, jm.bindingCount == 2 && jm.bindings[0].key == .W && jm.bindings[1].deviceType == .GamepadButton, "slot 0: same device kind replaced")
	// Conflicts: clear (default) - dash loses Left Shift.
	Input_SetBinding(input, "jump", 0, key(.LEFT_SHIFT))
	testing.expect_value(t, Input_MappingOf(input, "dash").bindingCount, 0)
	testing.expect_value(t, jm.bindings[0].key, rl.KeyboardKey.LEFT_SHIFT)
	// Swap: dash gets jump's old key.
	Input_SetBinding(input, "dash", 1, key(.E))
	Input_SetBinding(input, "jump", 1, key(.E), .Swap)
	testing.expect(t, Input_MappingOf(input, "dash").bindings[0].key == .LEFT_SHIFT && jm.bindings[0].key == .E, "swapped")
	// Allow: both keep it.
	Input_SetBinding(input, "dash", 1, key(.E), .Allow)
	testing.expect_value(t, len(Input_Conflicts(input, key(.E))), 2)
	// A slot past the end adds; nil removes.
	Input_SetBinding(input, "jump", 9, InputBinding{deviceType = .GamepadAxis, gamepadAxis = .LEFT_Y, axisPositive = false})
	testing.expect_value(t, jm.bindingCount, 3)
	Input_SetBinding(input, "jump", 3, {})
	testing.expect_value(t, jm.bindingCount, 2)

	// Names for the player.
	testing.expect_value(t, InputBinding_DisplayName(key(.LEFT_SHIFT)), "Left Shift")
	testing.expect_value(t, InputBinding_DisplayName(key(.SPACE)), "Space")
	testing.expect_value(t, InputBinding_DisplayName(key(.A)), "A")
	testing.expect_value(t, InputBinding_DisplayName(InputBinding{deviceType = .GamepadButton, gamepadButton = .RIGHT_FACE_DOWN}), "A")
	testing.expect_value(t, InputBinding_DisplayName(InputBinding{deviceType = .GamepadAxis, gamepadAxis = .LEFT_X, axisPositive = true}), "Left Stick Right")
	testing.expect_value(t, InputBinding_DisplayName(key(.KP_5)), "Numpad 5")

	// Saved, reset to the project's, loaded back over them.
	testing.expect(t, Input_SaveUserBindings(input), "saved")
	text, _ := os.read_entire_file(Input_UserBindingsPath(), context.temp_allocator)
	testing.expect(t, strings.contains(string(text), `{"name": "jump", "bindings": [{"key": "E"}`), string(text))
	Input_RebindReset(input)
	testing.expect(t, jm.bindings[0].key == .SPACE && Input_MappingOf(input, "dash").bindings[0].key == .LEFT_SHIFT, "reset to the project's")
	testing.expect(t, Input_LoadUserBindings(input), "loaded")
	testing.expect_value(t, Input_MappingOf(input, "jump").bindings[0].key, rl.KeyboardKey.E)

	// Lua: get_bindings / binding_text / set_binding / listen + on_done.
	L := game.scriptManager.L
	ok := lua.L_dostring(L, `
local b = Input.get_bindings("jump")
first_text = b[1].text
first_key = b[1].key
all = Input.binding_text("jump")
Input.set_binding("jump", 1, {key = "J"})
after = Input.binding_text("jump", 1)
listening = Input.listen("dash", {slot = 1, on_done = function(result, text) done_result = result; done_text = text end})
is_l = tostring(Input.is_listening())
conflicts = #Input.find_conflicts({key = "J"})
`)
	if ok != 0 do testing.fail_now(t, string(lua.tostring(L, -1)))
	gs :: proc(L: ^lua.State, n: cstring) -> string {lua.getglobal(L, n); defer lua.pop(L, 1); return strings.clone(string(lua.tostring(L, -1)), context.temp_allocator)}
	testing.expect_value(t, gs(L, "first_text"), "E")
	testing.expect_value(t, gs(L, "first_key"), "E")
	testing.expect_value(t, gs(L, "all"), "E / A")
	testing.expect_value(t, gs(L, "after"), "J")
	testing.expect_value(t, gs(L, "is_l"), "true")
	testing.expect_value(t, gs(L, "conflicts"), "1")
	// The player presses K (what the capture does), then the frame dispatches on_done.
	Input_RebindApply(input, key(.K))
	Input_RebindDispatch(input, L)
	testing.expect_value(t, gs(L, "done_result"), "bound")
	testing.expect_value(t, gs(L, "done_text"), "K")
	testing.expect_value(t, Input_MappingOf(input, "dash").bindings[0].key, rl.KeyboardKey.K)
	testing.expect(t, input.rebind.callback == 0, "the callback reference is released")
	// Cancel.
	ok = lua.L_dostring(L, `Input.listen("dash", {on_done = function(r) cancel_result = r end}); Input.cancel_listen()`)
	Input_RebindDispatch(input, L)
	testing.expect_value(t, gs(L, "cancel_result"), "cancelled")
}

// The Controls Menu template builds a row per action and rebinds through
// Input.listen (the captured input refreshes the buttons).
@(test)
test_controls_menu_template :: proc(t: ^testing.T) {
	dir, _ := filepath.join({Engine_TempDir(), "ore_controls_test"}, context.temp_allocator)
	_ = os.remove_all(dir)
	defer os.remove_all(dir)
	Save_SetDirectory(dir)
	defer Save_Reset()
	tpl, _ := Script_TemplateById("controls_menu")
	ScriptVFS_RegisterEmbedded("controls_menu_t.lua", CharacterTemplate_Fill(tpl.text, "controls_menu_t", "ControlsMenuT", context.temp_allocator))
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	actions := make([dynamic]Input_Action_Config, context.temp_allocator)
	keys := [3]rl.KeyboardKey{.SPACE, .LEFT_SHIFT, .ENTER}
	for name, k in ([3]string{"jump", "dash", "confirm"}) {
		c := Input_Action_Config{name = name, bindings = make([dynamic]InputBinding, context.temp_allocator)}
		append(&c.bindings, InputBinding{deviceType = .KeyboardKey, key = keys[k]})
		append(&actions, c)
	}
	Input_ApplyActionConfigs(&game.input, actions[:])
	Input_RebindSetDefaults(&game.input, actions[:])
	scene := game->createScene("menu", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	menu := Node_CreateByTypeName(scene, "UIContainerNode")
	menu.name = "Controls"
	menu.gameContext = &game.gameContext
	inst := Script_AttachToNode(menu, "controls_menu_t.lua", nil, &game.scriptManager)
	testing.expect(t, inst != nil, "the template compiles")
	ProcessNodeQueues(scene.manager, &game.gameContext)
	for _ in 0 ..< 3 do game->run(1.0 / 60)
	jumpKeys := Scene_FindNodeByName(scene, "jump_keys")
	testing.expect(t, jumpKeys != nil && jumpKeys.typeId == UIButtonNode, "a row per action, with a button")
	testing.expect(t, Scene_FindNodeByName(scene, "confirm_row") == nil, "hidden actions left out")
	if jumpKeys == nil do return
	testing.expect_value(t, (cast(^UIButtonNode)jumpKeys).text, "Space")
	// Click the jump button (the script's rebind), press Left Shift.
	L := game.scriptManager.L
	ok := lua.L_dostring(L, `Scene.find_node("Controls"):get_script():rebind("jump")`)
	testing.expect_value(t, ok, i32(0))
	testing.expect_value(t, (cast(^UIButtonNode)jumpKeys).text, "Press a key...")
	Input_RebindApply(&game.input, InputBinding{deviceType = .KeyboardKey, key = .LEFT_SHIFT})
	game->run(1.0 / 60)
	testing.expect_value(t, (cast(^UIButtonNode)jumpKeys).text, "Left Shift")
	dashKeys := cast(^UIButtonNode)Scene_FindNodeByName(scene, "dash_keys")
	testing.expect_value(t, dashKeys.text, "-") // dash lost Left Shift (conflict: clear)
	testing.expect(t, os.exists(Input_UserBindingsPath()), "saved for the player")
}
