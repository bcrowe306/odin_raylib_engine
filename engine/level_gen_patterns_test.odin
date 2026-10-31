package engine

import "core:strings"
import "core:testing"

// #171: a tile output's pattern rules - a 3x3 pattern over the grid (any /
// in range / not) placing tiles after the rules, first match wins, with a
// chance - saved, duplicated.

@(test)
test_level_gen_pattern_rules :: proc(t: ^testing.T) {
	// A floor (rows 3-4 solid); tufts (tile 9) on empty cells with solid
	// below; corners (tile 5) on solid cells with empty above and to the left.
	g, err := Gen_GraphParse(transmute([]u8)string(`{"size": [6, 5], "nodes": [
		{"id": 1, "type": "rect", "params": {"x": 1, "y": 3, "w": 5, "h": 2}},
		{"id": 2, "type": "tile_output", "inputs": {"in": 1}, "rules": [{"min": 0.5, "max": 1, "tiles": [1]}],
		 "patterns": [
			{"min": 0.5, "max": 1, "cells": [0, -1, 0, -1, 1, 0, 0, 0, 0], "tiles": [5]},
			{"min": 0.5, "max": 1, "cells": [0, 0, 0, 0, -1, 0, 0, 1, 0], "tiles": [9]}]},
		{"id": 3, "type": "tile_output", "inputs": {"in": 1},
		 "patterns": [{"min": 0.5, "max": 1, "cells": [0, 0, 0, 0, -1, 0, 0, 1, 0], "tiles": [9], "chance": 0.5}], "layer": "Decor"}]}`))
	testing.expectf(t, err == "", "parse: %s", err)
	defer Gen_GraphDestroy(&g)
	tiles, _, terr := Gen_Tiles(&g, 2, 0, context.temp_allocator)
	testing.expectf(t, terr == "", "tiles: %s", terr)
	row :: proc(tiles: []i32, y: int) -> [6]i32 {
		r: [6]i32
		for x in 0 ..< 6 do r[x] = tiles[y * 6 + x]
		return r
	}
	testing.expect_value(t, row(tiles, 2), [6]i32{-1, 9, 9, 9, 9, 9}) // tufts on top
	testing.expect_value(t, row(tiles, 3), [6]i32{-1, 5, 1, 1, 1, 1}) // the top-left corner
	testing.expect_value(t, row(tiles, 4), [6]i32{9, 1, 1, 1, 1, 1}) // (beyond the bottom counts as solid: a tuft on the empty corner cell)
	// Chance 0.5: some of the 5 tufts, the same ones every time.
	a, _, _ := Gen_Tiles(&g, 3, 0, context.temp_allocator)
	b, _, _ := Gen_Tiles(&g, 3, 0, context.temp_allocator)
	n := 0
	for v, i in a {
		testing.expect_value(t, v, b[i])
		if v == 9 do n += 1
	}
	testing.expect(t, n > 0 && n < 5, "some tufts by chance")
	// Saved, read back, duplicated.
	text := Gen_GraphSerialize(&g, context.temp_allocator)
	testing.expect(t, strings.contains(text, `"cells": [0, -1, 0, -1, 1, 0, 0, 0, 0], "tiles": [5]`), text)
	g2, _ := Gen_GraphParse(transmute([]u8)text, context.temp_allocator)
	testing.expect_value(t, len(Gen_FindNode(&g2, 2).patterns), 2)
	testing.expect_value(t, Gen_FindNode(&g2, 3).patterns[0].chance, 0.5)
	dup := Gen_DuplicateNode(&g, 2)
	testing.expect(t, len(dup.patterns) == 2 && raw_data(dup.patterns[0].tiles) != raw_data(Gen_FindNode(&g, 2).patterns[0].tiles), "duplicate owns its patterns")
	free_all(context.temp_allocator)
}
