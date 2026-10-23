package engine

import "core:os"
import "core:strings"
import "core:testing"
import lua "vendor:lua/5.4"

// Global scripts: project.json "globals" round-trips; each script's table
// is a Lua global, ready runs at start, update every frame (not paused).
@(test)
test_script_globals :: proc(t: ^testing.T) {
	dir :: "test_script_globals_project"
	defer os.remove_all(dir)
	_ = os.make_directory_all(dir + "/scripts")
	_ = os.write_entire_file(dir + "/scripts/game_state.lua", transmute([]u8)string(`
local GameState = {score = 0, readies = 0, time = 0}
function GameState:ready() self.readies = self.readies + 1 end
function GameState:update(dt) self.time = self.time + dt end
function GameState:add(n) self.score = self.score + n end
return GameState`))

	// Parse / serialize.
	cfg, ok := Project_ParseConfig(transmute([]u8)string(`{"name": "g", "globals": [{"name": "GameState", "script": "scripts/game_state.lua"}, {"name": "", "script": "x.lua"}]}`))
	testing.expect(t, ok, "parsed")
	defer ProjectConfig_Destroy(&cfg)
	testing.expect_value(t, len(cfg.globals), 1)
	json := Project_SerializeToJSON(&cfg, context.temp_allocator)
	testing.expect(t, strings.contains(json, `{"name": "GameState", "script": "scripts/game_state.lua"}`), json)
	clone := ProjectConfig_Clone(&cfg)
	testing.expect(t, len(clone.globals) == 1 && clone.globals[0].name == "GameState", "cloned")
	ProjectConfig_Destroy(&clone)
	testing.expect_value(t, Globals_NameOf(cfg.globals[:], "scripts/game_state.lua"), "GameState")
	testing.expect(t, !Globals_ValidName("2fast") && !Globals_ValidName("a-b") && Globals_ValidName("_Game2"), "names")

	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	AssetManager_SetProjectDir(&game.assetManager, dir)
	testing.expect(t, Game_LoadProjectConfig(game, &cfg), "loaded")
	L := game.scriptManager.L
	scene := game->createScene("g", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	Scene_UpdateNodeHirearchy(scene, scene.rootNode, &game.gameContext, 0.5)
	game.treePaused = true
	Scene_UpdateNodeHirearchy(scene, scene.rootNode, &game.gameContext, 0.5) // paused: no update
	game.treePaused = false
	r := lua.L_dostring(L, `
GameState:add(3)
assert(GameState.readies == 1, "ready once")
assert(GameState.time == 0.5, "updated once: " .. GameState.time)
assert(GameState.score == 3)`)
	if r != 0 do testing.fail_now(t, string(lua.tostring(L, -1)))

	// Reloading the list drops removed globals.
	Globals_Load(&game.scriptManager, {})
	lua.getglobal(L, "GameState")
	testing.expect(t, lua.isnil(L, -1), "removed")
	lua.pop(L, 1)
}
