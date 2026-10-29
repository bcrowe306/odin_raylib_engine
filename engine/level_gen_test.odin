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
	// A script node (the editor's template: stripes every 4 cells), its file read with the generator's.
	_ = os.write_entire_file(dir + "/levels/stripes.gen.lua", transmute([]u8)string(GEN_SCRIPT_TEMPLATE))
	_ = os.write_entire_file(dir + "/levels/scripted.levelgen.json", transmute([]u8)string(`{"size": [5, 1], "nodes": [
		{"id": 1, "type": "script", "script": "levels/stripes.gen.lua"}]}`))
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
local s = LevelGen.values("levels/scripted.levelgen.json")
stripes = s.values[1] + s.values[2] * 10 + s.values[5] * 100
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
	testing.expect_value(t, getv(L, "stripes"), "101.0") // (cells 0 and 4 are stripes)
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

// Phase 3 nodes: rooms & corridors, walker, scatter, surface.
@(test)
test_level_gen_rooms_walker_scatter_surface :: proc(t: ^testing.T) {
	g := gen_parse(t, `{"size": [60, 40], "seed": 4, "nodes": [
		{"id": 1, "type": "rooms", "params": {"min_size": 4, "max_size": 8}},
		{"id": 2, "type": "walker", "params": {"steps": 300, "walkers": 2}},
		{"id": 3, "type": "scatter", "params": {"chance": 0.3, "spacing": 5}},
		{"id": 4, "type": "scatter", "inputs": {"in": 1}, "params": {"chance": 1, "spacing": 0}},
		{"id": 5, "type": "rect", "params": {"x": 0, "y": 30, "w": 60, "h": 10}},
		{"id": 6, "type": "surface", "inputs": {"in": 5}},
		{"id": 7, "type": "surface", "inputs": {"in": 5}, "params": {"side": "bottom"}}]}`)
	defer Gen_GraphDestroy(&g)
	eval :: proc(t: ^testing.T, g: ^Gen_Graph, id: int) -> Gen_Grid {
		grid, err := Gen_Evaluate(g, id, 0, context.temp_allocator)
		testing.expectf(t, err == "", "node %d: %s", id, err)
		return grid
	}
	count :: proc(g: Gen_Grid) -> int {
		n := 0
		for v in g.v do if v >= 0.5 do n += 1
		return n
	}
	// Rooms: floor inside the level, never on its edge; several rooms joined
	// (one flood fill reaches every floor cell).
	rooms := eval(t, &g, 1)
	floor := count(rooms)
	testing.expectf(t, floor > 60 * 40 / 10 && floor < 60 * 40 * 9 / 10, "floor cells: %d", floor)
	for x in 0 ..< 60 do testing.expect(t, Gen_GridAt(rooms, x, 0) == 0 && Gen_GridAt(rooms, x, 39) == 0, "the edge stays wall")
	seen := make([]bool, len(rooms.v), context.temp_allocator)
	stack := make([dynamic]int, context.temp_allocator)
	for v, i in rooms.v do if v >= 0.5 {append(&stack, i); seen[i] = true; break}
	reached := 0
	for len(stack) > 0 {
		i := pop(&stack)
		reached += 1
		x, y := i % 60, i / 60
		for d in ([4][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) {
			xx, yy := x + d.x, y + d.y
			if xx < 0 || yy < 0 || xx >= 60 || yy >= 40 do continue
			j := yy * 60 + xx
			if !seen[j] && rooms.v[j] >= 0.5 {seen[j] = true; append(&stack, j)}
		}
	}
	testing.expectf(t, reached == floor, "every room is reachable (%d of %d)", reached, floor)
	// Walker: a connected tunnel through the centre.
	walk := eval(t, &g, 2)
	testing.expect(t, Gen_GridAt(walk, 30, 20) == 1 && count(walk) > 30, "walked from the centre")
	// Scatter: points spaced at least 5 apart; masked: only on floor.
	pts := eval(t, &g, 3)
	for v, i in pts.v do if v >= 0.5 {
		for w, j in pts.v do if w >= 0.5 && j != i {
			testing.expect(t, max(abs(i % 60 - j % 60), abs(i / 60 - j / 60)) >= 5, "spaced")
		}
	}
	testing.expect(t, count(pts) > 5, "some points")
	masked := eval(t, &g, 4)
	for v, i in masked.v do if v >= 0.5 do testing.expect(t, rooms.v[i] >= 0.5, "only on floor")
	testing.expect_value(t, count(masked), floor) // (chance 1, no spacing: every floor cell)
	// Surface: the row on top of the ground (y 29), and nothing for a ceiling.
	top := eval(t, &g, 6)
	testing.expect_value(t, count(top), 60)
	for x in 0 ..< 60 do testing.expect(t, Gen_GridAt(top, x, 29) == 1, "on the ground")
	testing.expect_value(t, count(eval(t, &g, 7)), 0)
	// Deterministic.
	testing.expect_value(t, gen_values(t, &g, 1), gen_values(t, &g, 1))
}

// Entity outputs: placements (capped by max), spawned under the TileMap
// (regenerating replaces them), from Lua, and the component saved.
@(test)
test_level_gen_entities :: proc(t: ^testing.T) {
	dir :: "test_level_gen_entities"
	defer os.remove_all(dir)
	_ = os.make_directory_all(dir + "/components")
	_ = os.make_directory_all(dir + "/levels")
	_ = os.write_entire_file(dir + "/components/coin.component.json", transmute([]u8)string(`{"type": "Node", "name": "Coin"}`))
	text := `{"size": [10, 4], "nodes": [
		{"id": 1, "type": "rect", "params": {"x": 0, "y": 3, "w": 10, "h": 1}},
		{"id": 2, "type": "surface", "inputs": {"in": 1}},
		{"id": 3, "type": "entity_output", "inputs": {"in": 2}, "params": {"max": 4}, "component": "components/coin.component.json"},
		{"id": 4, "type": "tile_output", "inputs": {"in": 1}, "rules": [{"min": 0.5, "max": 1, "tile": 2}]}]}`
	_ = os.write_entire_file(dir + "/levels/coins.levelgen.json", transmute([]u8)text)
	g := gen_parse(t, text)
	defer Gen_GraphDestroy(&g)
	ents, err := Gen_Entities(&g, 0, context.temp_allocator)
	testing.expect(t, err == "" && len(ents) == 4, "max 4 of the 10 ground cells")
	for en in ents do testing.expect(t, en.cell.y == 2 && en.component == "components/coin.component.json", "on the ground")
	again, _ := Gen_Entities(&g, 0, context.temp_allocator)
	for en, i in ents do testing.expect(t, again[i].cell == en.cell, "the same cells for a seed")
	testing.expect(t, strings.contains(Gen_GraphSerialize(&g, context.temp_allocator), `"component": "components/coin.component.json"`), "saved")
	dup := Gen_DuplicateNode(&g, 3)
	testing.expect_value(t, dup.component, "components/coin.component.json")

	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	AssetManager_SetProjectDir(&game.assetManager, dir)
	scene := game->createScene("ents", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	tm := cast(^TileMapNode)Node_CreateByTypeName(scene, "TileMapNode")
	tm.name = "Ground"
	tm.gameContext = &game.gameContext
	tm.tileSize = {16, 16}
	ProcessNodeQueues(scene.manager, &game.gameContext)
	coins :: proc(scene: ^Scene, tm: ^Node) -> (int, [2]f32) {
		ProcessNodeQueues(scene.manager, scene.rootNode.gameContext)
		n, pos := 0, [2]f32{}
		for c in GetChildrenTemp(scene.manager, tm) do if c != nil && !c.removing && c.name == "Coin" && Node_HasTag(c, GEN_ENTITY_TAG) {n += 1; pos = c.position}
		return n, pos
	}
	game.gameContext.scene = scene
	file, ferr := Gen_LoadFile(&game.gameContext, "levels/coins.levelgen.json")
	testing.expect_value(t, ferr, "")
	testing.expect_value(t, Gen_ApplyTileMap(&file, tm, 0, &game.gameContext, scene), "")
	n, pos := coins(scene, tm)
	testing.expect_value(t, n, 4)
	testing.expect(t, pos.y == 2.5 * 16 && TileMapNode_Get(tm, 0, 3) == 2, "at a cell's centre; the tiles too")
	testing.expect_value(t, Gen_ApplyTileMap(&file, tm, 0, &game.gameContext, scene), "")
	n, _ = coins(scene, tm)
	testing.expect_value(t, n, 4) // (replaced, not added)
	Gen_GraphDestroy(&file)

	L := game.scriptManager.L
	ok := lua.L_dostring(L, `local list = LevelGen.entities("levels/coins.levelgen.json"); count = #list; first = list[1].component; y = list[1].y`)
	testing.expectf(t, ok == 0, "lua: %s", lua.tostring(L, -1) if ok != 0 else "")
	lua.getglobal(L, "count")
	testing.expect_value(t, lua.tointeger(L, -1), lua.Integer(4))
	lua.getglobal(L, "y")
	testing.expect_value(t, lua.tointeger(L, -1), lua.Integer(2))
	lua.pop(L, 2)
}

// LDtk output: the tiles go into an IntGrid layer as values (one undo step);
// a layer of another type is refused.
@(test)
test_level_gen_ldtk_intgrid :: proc(t: ^testing.T) {
	doc, ok := Ldtk_Doc_Load("tests/drive/fixtures/ldtk/topdown.ldtk")
	testing.expect(t, ok, "loaded")
	if !ok do return
	defer Ldtk_Doc_Destroy(doc)
	li, layer, other := 0, -1, -1
	for &ly, j in doc.levels[0].layers {
		d := Ldtk_Doc_LayerDef(doc, &ly)
		if d != nil && d.type == .IntGrid && layer < 0 do layer = j
		if d != nil && d.type == .Tiles do other = j
	}
	testing.expect(t, layer >= 0 && other >= 0, "an IntGrid and a Tiles layer")
	if layer < 0 do return
	g := gen_parse(t, `{"size": [32, 16], "nodes": [
		{"id": 1, "type": "border", "params": {"width": 1}},
		{"id": 2, "type": "tile_output", "inputs": {"in": 1}, "rules": [{"min": 0.5, "max": 1, "tile": 1}]}]}`)
	defer Gen_GraphDestroy(&g)
	undo := len(doc.undo)
	testing.expect_value(t, Gen_ApplyIntGrid(&g, doc, li, layer), "")
	ly := &doc.levels[li].layers[layer]
	testing.expect(t, Ldtk_Doc_GetIntGrid(ly, 0, 0) == 1 && Ldtk_Doc_GetIntGrid(ly, 31, 15) == 1, "the border is 1")
	testing.expect_value(t, Ldtk_Doc_GetIntGrid(ly, 10, 8), 0)
	testing.expect_value(t, len(doc.undo), undo + 1)
	testing.expect_value(t, Gen_ApplyIntGrid(&g, doc, li, other), "not an IntGrid layer")
}

// Phase 4: a Lua script node - its inputs, params, seeded random, the
// returned or filled grid; the sandbox; errors (syntax, runtime, not a
// function, no script, a loop that never ends); saved with its file.
@(test)
test_level_gen_script_node :: proc(t: ^testing.T) {
	g := gen_parse(t, `{"size": [4, 2], "seed": 3, "nodes": [
		{"id": 1, "type": "rect", "params": {"x": 0, "y": 0, "w": 2, "h": 2}},
		{"id": 2, "type": "script", "inputs": {"a": 1}, "params": {"p1": 0.25}, "script": "gen/invert.lua"},
		{"id": 3, "type": "script", "script": "gen/returns.lua"},
		{"id": 4, "type": "script", "script": "gen/random.lua"},
		{"id": 5, "type": "script", "params": {"seed": 1}, "script": "gen/random.lua"},
		{"id": 6, "type": "script", "script": "gen/sandbox.lua"},
		{"id": 7, "type": "script", "inputs": {"a": 1}, "params": {"p1": 3}, "script": "gen/template.lua"}]}`)
	defer Gen_GraphDestroy(&g)
	Gen_SetScriptSource(&g, "gen/invert.lua", `return function(ctx)
		for i = 1, ctx.width * ctx.height do ctx.out[i] = 1 - ctx.a[i] + ctx.b[i] + ctx.params.p1 end
	end`)
	Gen_SetScriptSource(&g, "gen/returns.lua", `return function(ctx)
		local t = {}
		for y = 0, ctx.height - 1 do for x = 0, ctx.width - 1 do t[y * ctx.width + x + 1] = x + y * 10 end end
		return t
	end`)
	Gen_SetScriptSource(&g, "gen/random.lua", `return function(ctx)
		for y = 0, ctx.height - 1 do for x = 0, ctx.width - 1 do ctx.out[y * ctx.width + x + 1] = ctx.random(x, y) end end
	end`)
	Gen_SetScriptSource(&g, "gen/sandbox.lua", `return function(ctx)
		ctx.out[1] = (io == nil and os == nil and dofile == nil and loadfile == nil and require == nil) and 1 or 0
		ctx.out[2] = math.floor(2.5) + #string.rep("x", 3) -- (2 + 3)
	end`)
	testing.expect_value(t, gen_values(t, &g, 2), "0.25,0.25,1.25,1.25,0.25,0.25,1.25,1.25")
	testing.expect_value(t, gen_values(t, &g, 3), "0,1,2,3,10,11,12,13")
	r := gen_values(t, &g, 4)
	testing.expect_value(t, gen_values(t, &g, 4), r) // (the same for a seed)
	testing.expect(t, gen_values(t, &g, 4, 99) != r, "another seed, other numbers")
	testing.expect(t, gen_values(t, &g, 5) != r, "the node's seed counts")
	grid, _ := Gen_Evaluate(&g, 4, 0, context.temp_allocator)
	for v in grid.v do testing.expect(t, v >= 0 && v < 1, "in [0, 1)")
	testing.expect_value(t, gen_values(t, &g, 6), "1,5,0,0,0,0,0,0")
	Gen_SetScriptSource(&g, "gen/template.lua", GEN_SCRIPT_TEMPLATE) // (stripes every p1 cells, over a)
	testing.expect_value(t, gen_values(t, &g, 7), "1,1,0,1,1,1,0,1")

	// Saved with its file; a copy keeps it.
	text := Gen_GraphSerialize(&g, context.temp_allocator)
	testing.expect(t, strings.contains(text, `"script": "gen/invert.lua"`), "saved")
	back := gen_parse(t, text)
	defer Gen_GraphDestroy(&back)
	testing.expect_value(t, Gen_FindNode(&back, 2).script, "gen/invert.lua")
	testing.expect_value(t, Gen_DuplicateNode(&g, 2).script, "gen/invert.lua")

	fails :: proc(t: ^testing.T, src, want: string, script := "gen/bad.lua") {
		g := gen_parse(t, fmt.tprintf(`{{"size": [2, 2], "nodes": [{{"id": 1, "type": "script", "script": %q}}]}}`, script))
		defer Gen_GraphDestroy(&g)
		if src != "" do Gen_SetScriptSource(&g, "gen/bad.lua", src)
		_, err := Gen_Evaluate(&g, 1, 0, context.temp_allocator)
		testing.expectf(t, strings.contains(err, want), "%q: got %q", want, err)
	}
	fails(t, `return function(ctx`, "gen/bad.lua:1")
	fails(t, "return function(ctx)\n  error('no floor')\nend", "gen/bad.lua:2: no floor")
	fails(t, `return 42`, "must return a function")
	fails(t, "", "no such script")
	fails(t, "", "pick its script", "")
	budget := GEN_SCRIPT_BUDGET
	GEN_SCRIPT_BUDGET = 100_000
	defer GEN_SCRIPT_BUDGET = budget
	fails(t, `return function(ctx) while true do end end`, "ran too long")
}

// Phase 4: node types registered from Odin - read and written by name,
// evaluated with their inputs, parameters and seed; refused names; an
// unregistered type in a file is an error.
@(test)
test_level_gen_custom_node :: proc(t: ^testing.T) {
	checker :: proc(call: ^Gen_Custom_Call) -> string {
		size := max(int(Gen_Param(call.node, "size")), 1)
		if size > 100 do return "too big"
		for y in 0 ..< call.out.h do for x in 0 ..< call.out.w {
			i := y * call.out.w + x
			call.out.v[i] = (1 if (x / size + y / size) % 2 == 0 else 0) * (1 - call.inputs[0].v[i])
		}
		return ""
	}
	info := Gen_Kind_Info{name = "test_checker", label = "Checker", inputs = {"mask"}, params = {{name = "size", default_ = 1, integer = true}}, doc = "A checkerboard"}
	testing.expect_value(t, Gen_RegisterNode(info, checker), "")
	defer Gen_UnregisterNode("test_checker")
	testing.expect(t, Gen_RegisterNode({name = "noise", label = "x"}, checker) != "", "a built-in's name is refused")
	testing.expect(t, Gen_RegisterNode({name = "custom", label = "x"}, checker) != "", "so is custom")
	testing.expect(t, Gen_RegisterNode({name = "test_x", inputs = {"a", "b", "c"}}, checker) != "", "at most 2 inputs")
	testing.expect_value(t, len(Gen_CustomKinds()) >= 1, true)

	g := gen_parse(t, `{"size": [4, 2], "nodes": [
		{"id": 1, "type": "rect", "params": {"x": 0, "y": 0, "w": 1, "h": 1}},
		{"id": 2, "type": "test_checker", "inputs": {"mask": 1}, "params": {"size": 2}},
		{"id": 3, "type": "test_checker", "params": {"size": 1000}}]}`)
	defer Gen_GraphDestroy(&g)
	n := Gen_FindNode(&g, 2)
	testing.expect(t, n.kind == .Custom && n.custom == "test_checker" && Gen_NodeInfo(n).label == "Checker", "a custom node")
	testing.expect_value(t, gen_values(t, &g, 2), "0,1,0,0,1,1,0,0") // (cell 0 masked out)
	_, err := Gen_Evaluate(&g, 3, 0, context.temp_allocator)
	testing.expect_value(t, err, "node 3 (test_checker): too big")

	text := Gen_GraphSerialize(&g, context.temp_allocator)
	testing.expect(t, strings.contains(text, `"type": "test_checker", "inputs": {"mask": 1}, "params": {"size": 2}`), "saved by name")
	added := Gen_AddNode(&g, .Custom, {}, "test_checker")
	testing.expect(t, added.custom == "test_checker" && Gen_Param(added, "size") == 1, "added with its defaults")
	testing.expect(t, Gen_Connect(&g, added.id, 0, 1) && !Gen_Connect(&g, added.id, 1, 1), "one input")
	testing.expect_value(t, Gen_DuplicateNode(&g, 2).custom, "test_checker")

	Gen_UnregisterNode("test_checker")
	_, err = Gen_Evaluate(&g, 2, 0, context.temp_allocator)
	testing.expect(t, strings.contains(err, "no node type \"test_checker\" is registered"), "unregistered")
	bad, perr := Gen_GraphParse(transmute([]u8)text)
	defer Gen_GraphDestroy(&bad)
	testing.expect(t, strings.contains(perr, "unknown node type \"test_checker\""), "a file needs it registered")
}
