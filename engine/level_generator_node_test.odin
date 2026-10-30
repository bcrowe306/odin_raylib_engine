package engine

import "core:fmt"
import os "osx"
import "core:strings"
import "core:testing"
import "core:time"
import lua "lua54"

// LevelGeneratorNode (level_generator_node.odin): generating on ready into
// its TileMap child, seeds, parameters set on the node, the background
// worker, failures, saving, Lua and a signal to `generate`.

@(private = "file")
LGN_DIR :: "test_level_generator_node"

// A 4 x 1 generator: a constant (node 1, value 0) through a tile output
// (tile 3 where >= 0.5); a random fill (node 3) for seeds.
@(private = "file")
lgn_game :: proc() -> (^Game, ^Scene) {
	_ = os.make_directory_all(LGN_DIR + "/levels")
	_ = os.write_entire_file(LGN_DIR + "/levels/flat.levelgen.json", transmute([]u8)string(`{"size": [4, 1], "seed": 5, "nodes": [
		{"id": 1, "type": "constant", "params": {"value": 0}},
		{"id": 2, "type": "tile_output", "inputs": {"in": 1}, "rules": [{"min": 0.5, "max": 1, "tile": 3}]}]}`))
	_ = os.write_entire_file(LGN_DIR + "/levels/noisy.levelgen.json", transmute([]u8)string(`{"size": [64, 64], "seed": 5, "nodes": [
		{"id": 1, "type": "random_fill", "params": {"density": 0.5}},
		{"id": 2, "type": "cellular", "inputs": {"in": 1}, "params": {"iterations": 3}},
		{"id": 3, "type": "tile_output", "inputs": {"in": 2}, "rules": [{"min": 0.5, "max": 1, "tile": 1}]}]}`))
	game := new(Game)
	InitializeGame(game)
	AssetManager_SetProjectDir(&game.assetManager, LGN_DIR)
	scene := game->createScene("lgn", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	return game, scene
}

// A generator with a TileMap child (added to the running scene: ready runs).
@(private = "file")
lgn_node :: proc(scene: ^Scene, ctx: ^GameContext, file: string, onReady := true) -> (^LevelGeneratorNode, ^TileMapNode) {
	lg := LevelGeneratorNode_Create(scene, "Gen")
	lg.gameContext = ctx
	lg.generator = strings.clone(file, lg.allocator)
	lg.generateOnReady = onReady
	tm := cast(^TileMapNode)Node_CreateByTypeName(scene, "TileMapNode", lg)
	tm.name = "Ground"
	tm.gameContext = ctx
	ProcessNodeQueues(scene.manager, ctx)
	LevelGeneratorNode_Update(lg, ctx, 0.016) // (generateOnReady: the first update)
	return lg, tm
}

@(private = "file")
lgn_row :: proc(tm: ^TileMapNode) -> string {
	parts := make([dynamic]string, context.temp_allocator)
	for x in 0 ..< tm.mapSize.x do append(&parts, fmt.tprint(TileMapNode_Get(tm, x, 0)))
	return strings.join(parts[:], ",", context.temp_allocator)
}

@(private = "file")
lgn_tiles :: proc(tm: ^TileMapNode) -> string {
	sb := strings.builder_make(context.temp_allocator)
	for y in 0 ..< tm.mapSize.y do for x in 0 ..< tm.mapSize.x do strings.write_byte(&sb, '#' if TileMapNode_Get(tm, x, y) >= 0 else '.')
	return strings.to_string(sb)
}

@(test)
test_level_generator_node :: proc(t: ^testing.T) {
	game, scene := lgn_game()
	defer os.remove_all(LGN_DIR)
	defer game->terminate()
	ctx := &game.gameContext

	// On ready: the generator's seed, its TileMap child filled.
	events := make([dynamic]string, context.temp_allocator)
	lg, tm := lgn_node(scene, ctx, "levels/noisy.levelgen.json")
	testing.expect_value(t, tm.mapSize, [2]int{64, 64})
	testing.expect_value(t, lg.lastSeed, 5)
	first := lgn_tiles(tm)
	testing.expect(t, strings.contains(first, "#") && strings.contains(first, "."), "walls and floor")

	record :: proc(source: rawptr, value: EventValue, ctx: ^GameContext, user: rawptr) {
		append(cast(^[dynamic]string)user, fmt.tprintf("%v", value))
	}
	lg.onGenerated->subscribe(record, &events)
	lg.onFailed->subscribe(record, &events)

	// A seed: another level; the same seed: the same level.
	ok, why := LevelGeneratorNode_Generate(lg, ctx, 9)
	testing.expectf(t, ok, "generate: %s", why)
	nine := lgn_tiles(tm)
	testing.expect(t, nine != first && lg.lastSeed == 9, "seed 9")
	LevelGeneratorNode_Generate(lg, ctx, 9)
	testing.expect_value(t, lgn_tiles(tm), nine)
	lg.seed = 0
	lg.randomSeed = true
	LevelGeneratorNode_Generate(lg, ctx)
	testing.expect(t, lg.lastSeed != 5 && lg.lastSeed != 0, "a random seed")
	testing.expect_value(t, len(events), 3)
	testing.expect_value(t, events[0], "9")

	// In the background: started, the map untouched until it is done.
	lg.randomSeed = false
	lg.seed = 9
	lg.background = true
	TileMapNode_Reset(tm)
	ok, _ = LevelGeneratorNode_Generate(lg, ctx)
	testing.expect(t, ok && LevelGeneratorNode_Generating(lg), "started")
	again, busy := LevelGeneratorNode_Generate(lg, ctx)
	testing.expect(t, !again && busy == "already generating", "one at a time")
	for i := 0; i < 500 && LevelGeneratorNode_Generating(lg); i += 1 {
		time.sleep(2 * time.Millisecond)
		LevelGeneratorNode_Update(lg, ctx, 0.016)
	}
	testing.expect(t, !LevelGeneratorNode_Generating(lg), "done")
	testing.expect_value(t, lgn_tiles(tm), nine) // (the same level as on the main thread)
	testing.expect_value(t, events[len(events) - 1], "9")

	// Destroyed while generating: waits for the worker, nothing leaks.
	LevelGeneratorNode_Generate(lg, ctx, 3)
	RemoveNode(scene.manager, lg)
	ProcessNodeQueues(scene.manager, ctx)
}

@(test)
test_level_generator_node_params_failures :: proc(t: ^testing.T) {
	game, scene := lgn_game()
	defer os.remove_all(LGN_DIR)
	defer game->terminate()
	ctx := &game.gameContext

	// A parameter set on the node: node 1's value 1 makes every cell a tile.
	lg, tm := lgn_node(scene, ctx, "levels/flat.levelgen.json")
	testing.expect_value(t, lgn_row(tm), "-1,-1,-1,-1")
	LevelGeneratorNode_SetParam(lg, 1, "value", 1)
	LevelGeneratorNode_Generate(lg, ctx)
	testing.expect_value(t, lgn_row(tm), "3,3,3,3")
	v, set := LevelGeneratorNode_Param(lg, 1, "value")
	testing.expect(t, set && v == 1, "read back")
	LevelGeneratorNode_SetParam(lg, 1, "value", 0.75) // (replaced, not added)
	testing.expect_value(t, len(lg.params), 1)
	LevelGeneratorNode_ClearParam(lg, 1, "value")
	LevelGeneratorNode_Generate(lg, ctx)
	testing.expect_value(t, lgn_row(tm), "-1,-1,-1,-1")

	// Failures: "generation_failed" with why.
	why: string
	lg.onFailed->subscribe(proc(source: rawptr, value: EventValue, ctx: ^GameContext, user: rawptr) {
		(cast(^string)user)^ = strings.clone(value.(string), context.temp_allocator)
	}, &why)
	delete(lg.generator, lg.allocator)
	lg.generator = strings.clone("levels/none.levelgen.json", lg.allocator)
	ok, _ := LevelGeneratorNode_Generate(lg, ctx)
	testing.expect(t, !ok && strings.contains(why, "no file"), "no file")
	lone := LevelGeneratorNode_Create(scene, "Lone")
	lone.gameContext = ctx
	lone.generator = strings.clone("levels/flat.levelgen.json", lone.allocator)
	ProcessNodeQueues(scene.manager, ctx)
	ok, why = LevelGeneratorNode_Generate(lone, ctx)
	testing.expect(t, !ok && strings.contains(why, "no TileMap"), "no map")
	lone.tilemap = strings.clone("../Gen/Ground", lone.allocator) // (a path to another's)
	ok, why = LevelGeneratorNode_Generate(lone, ctx)
	testing.expectf(t, ok, "by path: %s", why)
}

@(test)
test_level_generator_node_save_lua_signal :: proc(t: ^testing.T) {
	game, scene := lgn_game()
	defer os.remove_all(LGN_DIR)
	defer game->terminate()
	ctx := &game.gameContext
	lg, tm := lgn_node(scene, ctx, "levels/flat.levelgen.json", false)
	testing.expect_value(t, tm.mapSize == {4, 1}, false) // (not generated: generateOnReady off)
	lg.seed = 12
	lg.background = true
	LevelGeneratorNode_SetParam(lg, 1, "value", 1)

	// Saved and read back.
	text := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expectf(t, strings.contains(text, `"level_generator": {"params": [{"node": 1, "name": "value", "value": 1}]}`), "saved: %s", text)
	s2 := game->createScene("lgn2", false)
	Scene_InstantiateFromJSON(s2, transmute([]u8)text, ctx)
	ProcessNodeQueues(s2.manager, ctx)
	back := cast(^LevelGeneratorNode)Scene_FindNodeByName(s2, "Gen")
	testing.expect(t, back != nil && back.generator == "levels/flat.levelgen.json" && back.seed == 12 && back.background && !back.generateOnReady, "read back")
	if back != nil {
		v, set := LevelGeneratorNode_Param(back, 1, "value")
		testing.expect(t, set && v == 1, "its parameter")
	}
	LevelGeneratorNode_ClearParam(lg)
	lg.background = false

	// Lua.
	L := game.scriptManager.L
	ok := lua.L_dostring(L, `
local gen = Scene.find_node("Gen")
gen:set_level_param(1, "value", 1)
param = gen:level_param(1, "value")
unset = gen:level_param(2, "empty") == nil
done = gen:generate(7)
busy = gen:is_generating()
gen:clear_level_params()
cleared = gen:level_param(1, "value") == nil
`)
	testing.expectf(t, ok == 0, "lua: %s", lua.tostring(L, -1) if ok != 0 else "")
	gets :: proc(L: ^lua.State, name: cstring) -> string {
		lua.getglobal(L, name)
		defer lua.pop(L, 1)
		if lua.type(L, -1) == .BOOLEAN do return "true" if lua.toboolean(L, -1) else "false"
		return strings.clone(string(lua.tostring(L, -1)), context.temp_allocator)
	}
	testing.expect_value(t, gets(L, "param"), "1.0")
	testing.expect_value(t, gets(L, "unset"), "true")
	testing.expect_value(t, gets(L, "done"), "true")
	testing.expect_value(t, gets(L, "busy"), "false")
	testing.expect_value(t, gets(L, "cleared"), "true")
	testing.expect(t, lgn_row(tm) == "3,3,3,3" && lg.lastSeed == 7, "generated from Lua")

	// A signal to `generate` (no script): a timer fires it.
	TileMapNode_Reset(tm)
	LevelGeneratorNode_SetParam(lg, 1, "value", 1)
	timer := cast(^TimerNode)Node_CreateByTypeName(scene, "TimerNode")
	timer.name = "Clock"
	timer.gameContext = ctx
	ProcessNodeQueues(scene.manager, ctx)
	testing.expect(t, Node_AddConnection(timer, "timeout", Node_RelativePath(scene.manager, timer, lg), "generate"), "connected")
	timer->setDuration(0.05)
	timer.running = true
	game->run(0.016)
	game->run(0.06)
	testing.expect_value(t, lgn_row(tm), "3,3,3,3")
}
