package engine

import "core:fmt"
import os "osx"
import "core:strings"
import "core:testing"

// #171: the playable-level nodes on drawn grids ('#' solid = 1, '.' open =
// 0: caves' sense, open "low") - flood fill, regions, connect regions, the
// start-to-exit path, check - and a Level Generator trying other seeds
// until a Check node takes the level.

@(private = "file")
grid_of :: proc(rows: ..string) -> Gen_Grid {
	w, h := len(rows[0]), len(rows)
	g := Gen_Grid{w, h, make([]f32, w * h, context.temp_allocator)}
	for r, y in rows do for x in 0 ..< w do g.v[y * w + x] = 1 if r[x] == '#' else 0
	return g
}

@(private = "file")
text_of :: proc(g: Gen_Grid, mask := false) -> string {
	b := strings.builder_make(context.temp_allocator)
	for y in 0 ..< g.h {
		if y > 0 do strings.write_byte(&b, '|')
		for x in 0 ..< g.w {
			v := g.v[y * g.w + x]
			strings.write_byte(&b, ('x' if v >= 0.5 else '.') if mask else ('#' if v >= 0.5 else '.'))
		}
	}
	return strings.to_string(b)
}

@(private = "file")
blank :: proc(g: Gen_Grid) -> Gen_Grid {return {g.w, g.h, make([]f32, len(g.v), context.temp_allocator)}}

// Open areas of a result (low = open).
@(private = "file")
areas :: proc(g: Gen_Grid) -> int {
	_, sizes := gen_label(gen_open_cells(g, false), g.w, g.h, false)
	return len(sizes)
}

@(private = "file")
CAVE := []string{
	"##########",
	"#..#.....#",
	"#..#.###.#",
	"####.#.#.#",
	"#....#.#.#",
	"#.#####..#",
	"#.#..#####",
	"##########",
}

@(test)
test_level_gen_flood_and_regions :: proc(t: ^testing.T) {
	src := grid_of(..CAVE)
	testing.expect_value(t, areas(src), 4) // top-left room, the big loop, the inner cell, the bottom pocket
	// Flood fill from (1, 1): its 2x2 room. From a wall: the nearest open cell's area.
	out := blank(src)
	gen_flood_fill(src, out, 1, 1, false, false)
	testing.expect_value(t, text_of(out, true), "..........|.xx.......|.xx.......|..........|..........|..........|..........|..........")
	out = blank(src)
	gen_flood_fill(src, out, 6, 3, false, false) // (the inner cell)
	testing.expect_value(t, text_of(out, true), "..........|..........|..........|......x...|......x...|..........|..........|..........")
	// Keep the largest: only the loop stays open.
	out = blank(src)
	gen_regions(src, out, false, 0, false, false)
	testing.expect_value(t, areas(out), 1)
	testing.expect_value(t, out.v[1 * 10 + 1], 1) // (the small room filled)
	testing.expect_value(t, out.v[1 * 10 + 4], 0) // (the loop open)
	// Remove areas under 4 cells: the room (4) stays, the inner cells (2) and the pocket (2) go.
	out = blank(src)
	gen_regions(src, out, true, 4, false, false)
	testing.expect_value(t, areas(out), 2)
	// "high" open: the solid cells are the areas (the walls are one piece here).
	out = blank(src)
	gen_regions(src, out, false, 0, true, false)
	testing.expect_value(t, text_of(out), text_of(src))
	free_all(context.temp_allocator)
}

@(test)
test_level_gen_connect_regions :: proc(t: ^testing.T) {
	src := grid_of(..CAVE)
	out := blank(src)
	gen_connect_regions(src, out, 1, 0, false, false)
	testing.expect_value(t, areas(out), 1)
	// Only rock was carved (nothing open closed), never the outer row.
	for v, i in src.v do if v < 0.5 do testing.expectf(t, out.v[i] < 0.5, "cell %d closed", i)
	for x in 0 ..< 10 do testing.expect(t, out.v[x] == 1 && out.v[7 * 10 + x] == 1, "top and bottom rows kept")
	for y in 0 ..< 8 do testing.expect(t, out.v[y * 10] == 1 && out.v[y * 10 + 9] == 1, "side columns kept")
	// min_size 3: the 2-cell areas are filled instead of joined.
	out = blank(src)
	gen_connect_regions(src, out, 1, 3, false, false)
	testing.expect_value(t, areas(out), 1)
	testing.expect_value(t, out.v[3 * 10 + 6], 1) // (the inner cell: filled)
	// Nothing open, or all one area: unchanged.
	solid := grid_of("####", "####", "####")
	out = blank(solid)
	gen_connect_regions(solid, out, 1, 0, false, false)
	testing.expect_value(t, text_of(out), text_of(solid))
	free_all(context.temp_allocator)
}

@(test)
test_level_gen_path :: proc(t: ^testing.T) {
	// Two rooms with rock between: left to right carves through the wall.
	src := grid_of(
		"############",
		"#...####...#",
		"#...####...#",
		"#...####...#",
		"############",
	)
	out := blank(src)
	gen_path(src, out, 0, {}, 1, false, 0)
	testing.expect_value(t, areas(out), 1)
	carved := 0
	for v, i in src.v do if v >= 0.5 && out.v[i] < 0.5 do carved += 1
	testing.expect_value(t, carved, 4) // (the 4 rock cells between, no more)
	// start / end: the open cells nearest the left and right middles.
	out = blank(src)
	gen_path(src, out, 0, {}, 1, false, 2)
	testing.expect_value(t, out.v[2 * 12 + 1], 1)
	out = blank(src)
	gen_path(src, out, 0, {}, 1, false, 3)
	testing.expect_value(t, out.v[2 * 12 + 10], 1)
	// It follows open cells: a gap in the wall is free.
	gap := grid_of(
		"############",
		"#...####...#",
		"#..........#",
		"#...####...#",
		"############",
	)
	out = blank(gap)
	gen_path(gap, out, 0, {}, 1, false, 0)
	testing.expect_value(t, text_of(out), text_of(gap))
	// Farthest: the two ends of a corridor.
	hall := grid_of(
		"#######",
		"#.....#",
		"#####.#",
		"#.....#",
		"#######",
	)
	out = blank(hall)
	gen_path(hall, out, 2, {}, 1, false, 2)
	a := out
	b := blank(hall)
	gen_path(hall, b, 2, {}, 1, false, 3)
	ends := [2]int{-1, -1}
	for i in 0 ..< len(a.v) {
		if a.v[i] >= 0.5 do ends[0] = i
		if b.v[i] >= 0.5 do ends[1] = i
	}
	testing.expect(t, (ends == [2]int{1 * 7 + 1, 3 * 7 + 1}) || (ends == [2]int{3 * 7 + 1, 1 * 7 + 1}), "farthest: the corridor's two ends")
	// Custom cells, 3 wide: a straight cut.
	out = blank(src)
	gen_path(src, out, 3, {1, 2, 10, 2}, 3, false, 1)
	n := 0
	for v in out.v do if v >= 0.5 do n += 1
	testing.expectf(t, n >= 10 * 3 - 6 && n <= 10 * 3, "a 3-wide path: %d cells", n)
	free_all(context.temp_allocator)
}

@(test)
test_level_gen_check :: proc(t: ^testing.T) {
	src := grid_of(..CAVE)
	testing.expect(t, gen_check(src, 0.1, false, false, false) == "", "enough open")
	testing.expect(t, strings.contains(gen_check(src, 0.9, false, false, false), "needs 90%"), "too little open")
	testing.expect(t, strings.contains(gen_check(src, 0, true, false, false), "4 separate parts"), "in pieces")
	// Through the graph: the error names the node.
	g, err := Gen_GraphParse(transmute([]u8)string(`{"size": [8, 8], "nodes": [
		{"id": 1, "type": "constant", "params": {"value": 1}},
		{"id": 2, "type": "check", "inputs": {"in": 1}}]}`), context.temp_allocator)
	testing.expect(t, err == "", err)
	_, e := Gen_Evaluate(&g, 2, 0, context.temp_allocator)
	testing.expect(t, strings.contains(e, "node 2 (check): only 0% of the level is open"), e)
	free_all(context.temp_allocator)
}

// With Random Seed, a level a Check node refuses is tried again with other
// seeds: a 3x3 random fill must leave the middle open; some seeds don't.
@(test)
test_level_generator_attempts :: proc(t: ^testing.T) {
	DIR :: "test_level_gen_attempts"
	_ = os.make_directory_all(DIR + "/levels")
	defer os.remove_all(DIR)
	_ = os.write_entire_file(DIR + "/levels/picky.levelgen.json", transmute([]u8)string(`{"size": [6, 6], "seed": 1, "nodes": [
		{"id": 1, "type": "random_fill", "params": {"density": 0.45}},
		{"id": 2, "type": "check", "inputs": {"in": 1}, "params": {"min_open": 0.5, "connected": false}},
		{"id": 3, "type": "tile_output", "inputs": {"in": 2}, "rules": [{"min": 0.5, "max": 1, "tiles": [1]}]}]}`))
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	AssetManager_SetProjectDir(&game.assetManager, DIR)
	scene := game->createScene("attempts", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	ctx := &game.gameContext
	lg := LevelGeneratorNode_Create(scene, "Gen")
	lg.gameContext = ctx
	lg.generator = strings.clone("levels/picky.levelgen.json", lg.allocator)
	lg.generateOnReady = false
	tm := cast(^TileMapNode)Node_CreateByTypeName(scene, "TileMapNode", lg)
	tm.gameContext = ctx
	ProcessNodeQueues(scene.manager, ctx)
	// Random seeds with 50 attempts: always a level that passes the check.
	lg.randomSeed, lg.attempts = true, 50
	for _ in 0 ..< 10 {
		ok, why := LevelGeneratorNode_Generate(lg, ctx)
		testing.expectf(t, ok, "generated: %s", why)
		solid := 0
		for y in 0 ..< 6 do for x in 0 ..< 6 do if TileMapNode_Get(tm, x, y) >= 0 do solid += 1
		testing.expectf(t, solid <= 18, "seed %d: %d solid (at least half open)", lg.lastSeed, solid)
	}
	// One attempt, a fixed seed the check refuses: it fails, saying so.
	bad := 0
	for s in 1 ..= 40 {
		g, _ := Gen_LoadFile(ctx, "levels/picky.levelgen.json", context.temp_allocator)
		if _, e := Gen_Generate(&g, u64(s), context.temp_allocator); e != "" {
			bad = s
			break
		}
	}
	testing.expect(t, bad != 0, "some seed fails the check")
	lg.randomSeed, lg.seed = false, bad
	ok, why := LevelGeneratorNode_Generate(lg, ctx)
	testing.expect(t, !ok && strings.contains(why, "check"), fmt.tprintf("a fixed seed isn't replaced: %s", why))
	free_all(context.temp_allocator)
}
