package engine

import "core:fmt"
import os "osx"
import "core:strings"
import "core:testing"
import lua "lua54"

// Procedural levels (level_gen.odin): the file format, every node kind on
// small grids, determinism, errors, tile output and the Lua module.

@(private = "file")
gen_parse :: proc(t: ^testing.T, text: string) -> Gen_Graph {
	g, err := Gen_GraphParse(transmute([]u8)text)
	testing.expectf(t, err == "", "parse: %s", err)
	return g
}

// The values of a node's grid as text ("0,1,...", to 2 decimals).
@(private = "file")
gen_values :: proc(t: ^testing.T, g: ^Gen_Graph, id: int, seed: u64 = 0) -> string {
	grid, err := Gen_Evaluate(g, id, seed, context.temp_allocator)
	testing.expectf(t, err == "", "evaluate %d: %s", id, err)
	parts := make([dynamic]string, context.temp_allocator)
	for v in grid.v {
		text := fmt.tprintf("%.2f", v) // (2 decimals, trailing zeros trimmed: "0.5", "1")
		text = strings.trim_right(text, "0")
		text = strings.trim_suffix(text, ".")
		append(&parts, text if text != "-0" && text != "" else "0")
	}
	return strings.join(parts[:], ",", context.temp_allocator)
}

@(test)
test_level_gen_nodes :: proc(t: ^testing.T) {
	g := gen_parse(t, `{"size": [4, 3], "nodes": [
		{"id": 1, "type": "constant", "params": {"value": 0.25}},
		{"id": 2, "type": "border", "params": {"width": 1}},
		{"id": 3, "type": "rect", "params": {"x": 1, "y": 0, "w": 2, "h": 2}},
		{"id": 4, "type": "invert", "inputs": {"in": 2}},
		{"id": 5, "type": "remap", "inputs": {"in": 1}, "params": {"to_min": 10, "to_max": 20}},
		{"id": 6, "type": "combine", "inputs": {"a": 3, "b": 2}, "params": {"op": "mask"}},
		{"id": 7, "type": "combine", "inputs": {"a": 3, "b": 4}, "params": {"op": "max"}},
		{"id": 8, "type": "combine", "inputs": {"a": 1, "b": 1}, "params": {"op": "add"}}]}`)
	defer Gen_GraphDestroy(&g)
	testing.expect_value(t, gen_values(t, &g, 1), "0.25,0.25,0.25,0.25,0.25,0.25,0.25,0.25,0.25,0.25,0.25,0.25")
	testing.expect_value(t, gen_values(t, &g, 2), "1,1,1,1,1,0,0,1,1,1,1,1")
	testing.expect_value(t, gen_values(t, &g, 3), "0,1,1,0,0,1,1,0,0,0,0,0")
	testing.expect_value(t, gen_values(t, &g, 4), "0,0,0,0,0,1,1,0,0,0,0,0")
	testing.expect_value(t, gen_values(t, &g, 5), "12.5,12.5,12.5,12.5,12.5,12.5,12.5,12.5,12.5,12.5,12.5,12.5")
	testing.expect_value(t, gen_values(t, &g, 6), "0,1,1,0,0,0,0,0,0,0,0,0") // (the rect where the border is)
	testing.expect_value(t, gen_values(t, &g, 7), "0,1,1,0,0,1,1,0,0,0,0,0")
	testing.expect_value(t, gen_values(t, &g, 8), "0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5")

	ramp := gen_parse(t, `{"size": [5, 1], "nodes": [
		{"id": 1, "type": "gradient"},
		{"id": 2, "type": "threshold", "inputs": {"in": 1}, "params": {"value": 0.5}},
		{"id": 3, "type": "threshold", "inputs": {"in": 1}, "params": {"value": 0.5, "invert": true}}]}`)
	defer Gen_GraphDestroy(&ramp)
	testing.expect_value(t, gen_values(t, &ramp, 1), "0,0.25,0.5,0.75,1")
	testing.expect_value(t, gen_values(t, &ramp, 2), "0,0,1,1,1")
	testing.expect_value(t, gen_values(t, &ramp, 3), "1,1,0,0,0")

	// Morphology on a dot: dilate makes a plus, erode takes it back to the dot;
	// blur spreads it over its neighbours.
	dot := gen_parse(t, `{"size": [3, 3], "nodes": [
		{"id": 1, "type": "rect", "params": {"x": 1, "y": 1, "w": 1, "h": 1}},
		{"id": 2, "type": "dilate", "inputs": {"in": 1}},
		{"id": 3, "type": "erode", "inputs": {"in": 2}},
		{"id": 4, "type": "blur", "inputs": {"in": 1}}]}`)
	defer Gen_GraphDestroy(&dot)
	testing.expect_value(t, gen_values(t, &dot, 2), "0,1,0,1,1,1,0,1,0")
	testing.expect_value(t, gen_values(t, &dot, 3), "0,0,0,0,1,0,0,0,0")
	testing.expect_value(t, gen_values(t, &dot, 4), "0.25,0.17,0.25,0.17,0.11,0.17,0.25,0.17,0.25")

	// Cellular: a hole surrounded by walls fills in; an empty open map stays empty.
	cave := gen_parse(t, `{"size": [3, 3], "nodes": [
		{"id": 1, "type": "border"},
		{"id": 2, "type": "cellular", "inputs": {"in": 1}, "params": {"iterations": 1}},
		{"id": 3, "type": "constant", "params": {"value": 0}},
		{"id": 4, "type": "cellular", "inputs": {"in": 3}, "params": {"edge_solid": false}}]}`)
	defer Gen_GraphDestroy(&cave)
	testing.expect_value(t, gen_values(t, &cave, 2), "1,1,1,1,1,1,1,1,1")
	testing.expect_value(t, gen_values(t, &cave, 4), "0,0,0,0,0,0,0,0,0")

	// Random fill: density 0 / 1; noise stays in 0..1.
	rnd := gen_parse(t, `{"size": [8, 8], "nodes": [
		{"id": 1, "type": "random_fill", "params": {"density": 0}},
		{"id": 2, "type": "random_fill", "params": {"density": 1}},
		{"id": 3, "type": "noise", "params": {"scale": 3, "octaves": 4}}]}`)
	defer Gen_GraphDestroy(&rnd)
	testing.expect(t, !strings.contains(gen_values(t, &rnd, 1), "1"), "density 0: none")
	testing.expect(t, !strings.contains(gen_values(t, &rnd, 2), "0"), "density 1: all")
	noise, _ := Gen_Evaluate(&rnd, 3, 0, context.temp_allocator)
	lo, hi := f32(1), f32(0)
	for v in noise.v {lo = min(lo, v); hi = max(hi, v)}
	testing.expectf(t, lo >= 0 && hi <= 1 && hi - lo > 0.1, "noise in 0..1 and varied (%v..%v)", lo, hi)
}

// A cave level: the same seed gives the same level, another seed another;
// the border keeps it closed.
@(test)
test_level_gen_cave_determinism :: proc(t: ^testing.T) {
	g := gen_parse(t, `{"size": [40, 30], "seed": 9, "nodes": [
		{"id": 1, "type": "random_fill", "params": {"density": 0.48}},
		{"id": 2, "type": "cellular", "inputs": {"in": 1}, "params": {"iterations": 5}},
		{"id": 3, "type": "border", "params": {"width": 1}},
		{"id": 4, "type": "combine", "inputs": {"a": 2, "b": 3}, "params": {"op": "max"}},
		{"id": 5, "type": "tile_output", "inputs": {"in": 4}, "rules": [{"min": 0.5, "max": 1, "tiles": [3, 4]}]}]}`)
	defer Gen_GraphDestroy(&g)
	a := gen_values(t, &g, 0)
	testing.expect_value(t, gen_values(t, &g, 0), a)
	testing.expect(t, gen_values(t, &g, 0, 10) != a, "another seed, another cave")
	testing.expect_value(t, gen_values(t, &g, 0, 9), a) // (the graph's own seed)
	grid, _ := Gen_Evaluate(&g, 0, 0, context.temp_allocator)
	for x in 0 ..< grid.w do testing.expect(t, Gen_GridAt(grid, x, 0) == 1 && Gen_GridAt(grid, x, grid.h - 1) == 1, "closed top and bottom")
	solid := 0
	for v in grid.v do if v >= 0.5 do solid += 1
	testing.expectf(t, solid > len(grid.v) / 5 && solid < len(grid.v) * 9 / 10, "walls and open space (%d of %d solid)", solid, len(grid.v))

	// Tiles: solid cells get 3 or 4 (the same for a seed), open ones none.
	tiles, size, err := Gen_Tiles(&g, 0, 0, context.temp_allocator)
	testing.expect(t, err == "" && size == {40, 30}, "tiles")
	again, _, _ := Gen_Tiles(&g, 0, 0, context.temp_allocator)
	seen3, seen4 := false, false
	for v, i in grid.v {
		want_solid := v >= 0.5
		testing.expect(t, (tiles[i] >= 0) == want_solid && tiles[i] == again[i], "a tile where solid, the same each time")
		if tiles[i] == 3 do seen3 = true
		if tiles[i] == 4 do seen4 = true
	}
	testing.expect(t, seen3 && seen4, "both variants used")
}

@(test)
test_level_gen_format_and_errors :: proc(t: ^testing.T) {
	src := `{"size": [16, 9], "seed": 3, "output": 3, "nodes": [
		{"id": 1, "type": "noise", "params": {"scale": 6, "seed": 2}, "pos": [10, 20]},
		{"id": 2, "type": "combine", "inputs": {"a": 1, "b": 1}, "params": {"op": "average"}},
		{"id": 3, "type": "tile_output", "inputs": {"in": 2}, "params": {"empty": 0}, "rules": [{"min": 0, "max": 0.5, "tile": 1}, {"min": 0.5, "max": 1, "tiles": [2, 5]}]}]}`
	g := gen_parse(t, src)
	defer Gen_GraphDestroy(&g)
	text := Gen_GraphSerialize(&g, context.temp_allocator)
	back := gen_parse(t, text)
	defer Gen_GraphDestroy(&back)
	testing.expect(t, back.size == {16, 9} && back.seed == 3 && back.output == 3 && len(back.nodes) == 3, "graph read back")
	testing.expect(t, Gen_Param(&back.nodes[0], "scale") == 6 && Gen_Param(&back.nodes[0], "seed") == 2 && back.nodes[0].pos == {10, 20}, "params and position")
	testing.expect(t, back.nodes[1].inputs == {1, 1} && Gen_Param(&back.nodes[1], "op") == 6, "inputs; a choice by name")
	r := back.nodes[2].rules
	testing.expect(t, len(r) == 2 && len(r[0].tiles) == 1 && r[0].tiles[0] == 1 && len(r[1].tiles) == 2 && r[1].tiles[1] == 5, "rules")
	testing.expect_value(t, gen_values(t, &back, 0), gen_values(t, &g, 0))
	testing.expect_value(t, Gen_GraphSerialize(&back, context.temp_allocator), text)

	bad :: proc(t: ^testing.T, text, want: string) {
		g, err := Gen_GraphParse(transmute([]u8)text)
		defer Gen_GraphDestroy(&g)
		if err == "" do _, err = Gen_Evaluate(&g, 0, 0, context.temp_allocator)
		testing.expectf(t, strings.contains(err, want), "%q: got %q", want, err)
	}
	bad(t, `{"nodes": [{"id": 1, "type": "volcano"}]}`, "unknown node type")
	bad(t, `{"nodes": [{"id": 1, "type": "invert"}, {"id": 1, "type": "invert"}]}`, "two nodes have the id 1")
	bad(t, `{"nodes": [{"id": 1, "type": "invert", "inputs": {"in": 2}}, {"id": 2, "type": "blur", "inputs": {"in": 1}}]}`, "cycle")
	bad(t, `{"nodes": [{"id": 1, "type": "invert", "inputs": {"in": 9}}]}`, "doesn't exist")
	bad(t, `{"nodes": []}`, "no nodes")
	bad(t, `not json`, "not valid JSON")
}

@(test)
test_level_gen_tilemap_and_lua :: proc(t: ^testing.T) {
	dir :: "test_level_gen_project"
	defer os.remove_all(dir)
	_ = os.make_directory_all(dir + "/levels")
	_ = os.write_entire_file(dir + "/levels/ramp.levelgen.json", transmute([]u8)string(`{"size": [5, 2], "nodes": [
		{"id": 1, "type": "gradient"},
		{"id": 2, "type": "tile_output", "inputs": {"in": 1}, "rules": [{"min": 0.5, "max": 1, "tile": 7}]}]}`))
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	AssetManager_SetProjectDir(&game.assetManager, dir)
	scene := game->createScene("gen", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	tm := cast(^TileMapNode)Node_CreateByTypeName(scene, "TileMapNode")
	tm.name = "Ground"
	tm.gameContext = &game.gameContext
	ProcessNodeQueues(scene.manager, &game.gameContext)

	g, err := Gen_LoadFile(&game.gameContext, "levels/ramp.levelgen.json")
	testing.expectf(t, err == "", "load: %s", err)
	testing.expect_value(t, Gen_ApplyTileMap(&g, tm, 0, &game.gameContext), "")
	Gen_GraphDestroy(&g)
	testing.expect_value(t, tm.mapSize, [2]int{5, 2})
	row := make([dynamic]string, context.temp_allocator)
	for x in 0 ..< 5 do append(&row, fmt.tprint(TileMapNode_Get(tm, x, 1)))
	testing.expect_value(t, strings.join(row[:], ",", context.temp_allocator), "-1,-1,7,7,7")

	// Lua: generate (and the level_generated event), values.
	L := game.scriptManager.L
	TileMapNode_Reset(tm)
	ok := lua.L_dostring(L, `
Events.connect("level_generated", function(name) generated = name end)
done, why = LevelGen.generate("levels/ramp.levelgen.json", Scene.find_node("Ground"), 5)
local g = LevelGen.values("levels/ramp.levelgen.json")
w, h, third = g.width, g.height, g.values[3]
missing, missing_why = LevelGen.generate("levels/none.levelgen.json", Scene.find_node("Ground"))
`)
	testing.expectf(t, ok == 0, "lua: %s", lua.tostring(L, -1) if ok != 0 else "")
	getv :: proc(L: ^lua.State, name: cstring) -> string {
		lua.getglobal(L, name)
		defer lua.pop(L, 1)
		#partial switch lua.type(L, -1) {
		case .NIL: return "nil"
		case .BOOLEAN: return "true" if lua.toboolean(L, -1) else "false"
		}
		return strings.clone(string(lua.tostring(L, -1)), context.temp_allocator)
	}
	testing.expect_value(t, getv(L, "done"), "true")
	testing.expect_value(t, getv(L, "generated"), "Ground")
	testing.expect_value(t, TileMapNode_Get(tm, 4, 0), i32(7))
	testing.expect_value(t, getv(L, "w"), "5")
	testing.expect_value(t, getv(L, "h"), "2")
	testing.expect_value(t, getv(L, "third"), "0.5")
	testing.expect_value(t, getv(L, "missing"), "false")
	testing.expect(t, strings.contains(getv(L, "missing_why"), "no file"), "why it failed")
}

// Editing (the Generator window): add, connect (no cycles), duplicate,
// remove (inputs reading it disconnected); the cave template is valid.
@(test)
test_level_gen_editing :: proc(t: ^testing.T) {
	g := gen_parse(t, GEN_TEMPLATE_CAVE)
	defer Gen_GraphDestroy(&g)
	testing.expect(t, len(g.nodes) == 5 && Gen_OutputNode(&g).kind == .Tile_Output, "the template")
	_, err := Gen_Evaluate(&g, 0, 0, context.temp_allocator)
	testing.expect_value(t, err, "")

	blur := Gen_AddNode(&g, .Blur, {10, 20})
	testing.expect(t, blur.id == 6 && blur.pos == {10, 20} && Gen_Param(blur, "radius") == 1, "added with defaults")
	testing.expect(t, Gen_Connect(&g, 6, 0, 4), "4 -> blur")
	testing.expect(t, !Gen_Connect(&g, 4, 0, 6), "blur -> 4 would be a cycle")
	testing.expect(t, !Gen_Connect(&g, 6, 1, 4), "blur has one input")
	testing.expect(t, !Gen_Connect(&g, 6, 0, 99), "no node 99")
	out := Gen_AddNode(&g, .Tile_Output, {})
	testing.expect(t, len(out.rules) == 1 && out.rules[0].tiles[0] == 0, "a tile output starts with a rule")

	dup := Gen_DuplicateNode(&g, 5)
	testing.expect(t, dup != nil && dup.id == 8 && dup.inputs == {} && len(dup.rules) == 1, "a copy without its inputs")
	dup.rules[0].tiles[0] = 9
	testing.expect_value(t, Gen_FindNode(&g, 5).rules[0].tiles[0], i32(0)) // (its own rules)

	testing.expect(t, Gen_RemoveNode(&g, 4), "removed")
	testing.expect(t, Gen_FindNode(&g, 5).inputs[0] == 0 && Gen_FindNode(&g, 6).inputs[0] == 0, "readers disconnected")
	testing.expect(t, !Gen_RemoveNode(&g, 4), "already gone")
	text := Gen_GraphSerialize(&g, context.temp_allocator)
	back := gen_parse(t, text)
	defer Gen_GraphDestroy(&back)
	testing.expect_value(t, len(back.nodes), len(g.nodes))
}
