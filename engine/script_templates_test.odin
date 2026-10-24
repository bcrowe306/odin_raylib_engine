package engine

import "core:fmt"
import "core:strings"
import "core:testing"
import lua "lua54"

// New-script templates: each compiles, declares its properties, and runs;
// the patrol walks and turns, the pickup is collected by a tagged body, the
// trigger opens its door; Scene.change_scene takes a scene file too.
@(test)
test_script_templates :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("templates", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	sm := &game.scriptManager
	L := sm.L

	attach :: proc(t: ^testing.T, game: ^Game, scene: ^Scene, id, type: string, name := "") -> (^Node, ^ScriptInstance) {
		tp, ok := Script_TemplateById(id)
		testing.expect(t, ok, id)
		text, _ := strings.replace_all(tp.text, "$CLASS$", strings.concatenate({"Tpl_", id}, context.temp_allocator), context.temp_allocator)
		text, _ = strings.replace_all(text, "$NAME$", id, context.temp_allocator)
		path := fmt.tprintf("tpl_%s.lua", id)
		ScriptVFS_RegisterEmbedded(path, text)
		n := Node_CreateByTypeName(scene, type)
		n.name = strings.clone(name if name != "" else id, n.allocator)
		n.gameContext = &game.gameContext
		inst := Script_AttachToNode(n, path, nil, &game.scriptManager)
		testing.expectf(t, inst != nil, "%s attaches", id)
		mod := game.scriptManager.modules[ScriptVFS_NormalizePath(path)]
		testing.expectf(t, mod != nil && len(mod.properties) > 0, "%s has properties", id)
		return n, inst
	}
	for tp in Script_Templates() {
		type := "Node"
		if len(tp.suits) > 0 do if info, ok := Node_TypeInfoById(tp.suits[0]); ok do type = info.name
		if id := tp.id; id == "enemy_patrol" || id == "pickup" || id == "door_trigger" do continue // below
		attach(t, game, scene, tp.id, type)
	}
	testing.expect_value(t, Script_TemplateFor(CharacterMoverNode), "platformer")
	testing.expect_value(t, Script_TemplateFor(AreaNode), "pickup")
	testing.expect_value(t, Script_TemplateFor(TextureNode), "empty")

	// Patrol: walks right from where it starts, turns at the end.
	enemy, einst := attach(t, game, scene, "enemy_patrol", "Node")
	enemy.position = {100, 50}
	ProcessNodeQueues(scene.manager, &game.gameContext)
	for _ in 0 ..< 10 do game->run(0.1) // 80 px/s
	testing.expectf(t, enemy.position.x > 150 && enemy.position.x <= 260 && enemy.position.y == 50, "walked: %v", enemy.position)
	for _ in 0 ..< 30 do game->run(0.1)
	testing.expectf(t, enemy.position.x <= 260 && enemy.position.x >= 100, "stays in its range: %v", enemy.position)
	_ = einst

	// Pickup: a body without the tag is ignored; one with it collects it.
	coin, _ := attach(t, game, scene, "pickup", "AreaNode", "Coin")
	hero := Node_CreateByTypeName(scene, "Node")
	hero.name = "Hero"
	ProcessNodeQueues(scene.manager, &game.gameContext)
	game->run(0.016)
	r := lua.L_dostring(L, `
local coin = Scene.find_node("Coin")
local hero = Scene.find_node("Hero")
got = 0
hero:connect("collected", function(v) got = got + v end)
local s = coin:get_script()
s:on_body_entered(hero)
assert(not s.taken, "untagged")
hero:add_tag("player")
s:on_body_entered(hero)
assert(s.taken, "taken")
s:on_body_entered(hero)`)
	if r != 0 do testing.fail_now(t, string(lua.tostring(L, -1)))
	lua.getglobal(L, "got")
	testing.expect_value(t, lua.tointeger(L, -1), 1)
	lua.pop(L, 1)
	_ = coin

	// Door / trigger: the door slides by the offset; a scene by its file.
	trig, tinst := attach(t, game, scene, "door_trigger", "AreaNode", "Trigger")
	door := Node_CreateByTypeName(scene, "Node")
	door.name = "Door"
	door.position = {300, 300}
	door.gameContext = &game.gameContext
	ScriptInstance_SetProperty(tinst, "door", {type = .String, valString = "../Door"}, sm)
	ProcessNodeQueues(scene.manager, &game.gameContext)
	game->run(0.016)
	r = lua.L_dostring(L, `
local s = Scene.find_node("Trigger"):get_script()
local hero = Scene.find_node("Hero")
s:on_body_entered(hero)
assert(s.inside == 1)`)
	if r != 0 do testing.fail_now(t, string(lua.tostring(L, -1)))
	for _ in 0 ..< 30 do game->run(0.05)
	testing.expectf(t, door.position == {300, 204}, "door open: %v", door.position)
	_ = trig

	next := game->createScene("level_two", false)
	next.filePath = "scenes/level_two.scene.json"
	r = lua.L_dostring(L, `Scene.change_scene("scenes/level_two.scene.json")`)
	testing.expect_value(t, r, i32(0))
	testing.expect(t, game.sceneManager.nextScene == next, "change_scene by file")
}
