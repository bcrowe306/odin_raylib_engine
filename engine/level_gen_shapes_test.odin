package engine

import "core:fmt"
import "core:math"
import "core:testing"

// #171: the seeded shape nodes - lines, rectangles, circles - land inside
// the level with the sizes asked for, outlines are hollow, and a seed gives
// the same shapes every time (another seed, others).

@(private = "file")
shape_grid :: proc(t: ^testing.T, size: [2]int, node: string, seed: u64 = 5) -> Gen_Grid {
	text := fmt.tprintf(`{{"size": [%d, %d], "seed": %d, "nodes": [%s]}}`, size.x, size.y, seed, node)
	g, err := Gen_GraphParse(transmute([]u8)text, context.temp_allocator)
	testing.expectf(t, err == "", "parse: %s", err)
	grid, e := Gen_Evaluate(&g, 1, 0, context.temp_allocator)
	testing.expectf(t, e == "", "evaluate: %s", e)
	return grid
}

// The set cells: how many, their bounding box (min, max inclusive).
@(private = "file")
shape_stats :: proc(g: Gen_Grid) -> (cells: int, lo, hi: [2]int) {
	lo, hi = {max(int), max(int)}, {-1, -1}
	for y in 0 ..< g.h do for x in 0 ..< g.w do if g.v[y * g.w + x] >= 0.5 {
		cells += 1
		lo = {min(lo.x, x), min(lo.y, y)}
		hi = {max(hi.x, x), max(hi.y, y)}
	}
	return
}

@(test)
test_level_gen_lines :: proc(t: ^testing.T) {
	for seed in u64(1) ..= 20 {
		// One horizontal line, 3 thick, 5..9 long.
		g := shape_grid(t, {40, 30}, `{"id": 1, "type": "lines", "params": {"count": 1, "min_length": 5, "max_length": 9, "thickness": 3, "direction": "horizontal"}}`, seed)
		n, lo, hi := shape_stats(g)
		size := hi - lo + 1
		testing.expectf(t, size.y == 3 && size.x >= 5 && size.x <= 9 && n == size.x * size.y, "seed %d: horizontal line %v, %d cells", seed, size, n)
		// One vertical line.
		g = shape_grid(t, {40, 30}, `{"id": 1, "type": "lines", "params": {"count": 1, "min_length": 12, "max_length": 12, "thickness": 1, "direction": "vertical"}}`, seed)
		n, lo, hi = shape_stats(g)
		testing.expectf(t, hi - lo + 1 == [2]int{1, 12} && n == 12, "seed %d: vertical line %v", seed, hi - lo + 1)
		// Any angle: one connected line within its length (plus the brush).
		g = shape_grid(t, {40, 30}, `{"id": 1, "type": "lines", "params": {"count": 1, "min_length": 15, "max_length": 15, "thickness": 1, "direction": "any"}}`, seed)
		n, lo, hi = shape_stats(g)
		diag := math.sqrt(f32((hi.x - lo.x) * (hi.x - lo.x) + (hi.y - lo.y) * (hi.y - lo.y)))
		testing.expectf(t, n >= 8 && diag >= 13 && diag <= 15.5, "seed %d: angled line spans %.1f (%d cells)", seed, diag, n)
	}
	// Longer than the level: clipped to it.
	g := shape_grid(t, {10, 6}, `{"id": 1, "type": "lines", "params": {"count": 1, "min_length": 50, "max_length": 50, "direction": "horizontal"}}`)
	n, _, _ := shape_stats(g)
	testing.expect_value(t, n, 10)
	free_all(context.temp_allocator)
}

@(test)
test_level_gen_rectangles :: proc(t: ^testing.T) {
	for seed in u64(1) ..= 20 {
		g := shape_grid(t, {40, 30}, `{"id": 1, "type": "rectangles", "params": {"count": 1, "min_size": 5, "max_size": 10}}`, seed)
		n, lo, hi := shape_stats(g)
		s := hi - lo + 1
		testing.expectf(t, s.x >= 5 && s.x <= 10 && s.y >= 5 && s.y <= 10, "seed %d: rectangle %v", seed, s)
		testing.expectf(t, n == 2 * s.x + 2 * s.y - 4, "seed %d: outline of %v has %d cells", seed, s, n)
		// Thick outline: 2 cells; filled: every cell.
		g = shape_grid(t, {40, 30}, `{"id": 1, "type": "rectangles", "params": {"count": 1, "min_size": 8, "max_size": 8, "thickness": 2}}`, seed)
		n, _, _ = shape_stats(g)
		testing.expect_value(t, n, 8 * 8 - 4 * 4)
		g = shape_grid(t, {40, 30}, `{"id": 1, "type": "rectangles", "params": {"count": 1, "min_size": 6, "max_size": 6, "filled": true}}`, seed)
		n, _, _ = shape_stats(g)
		testing.expect_value(t, n, 36)
	}
	free_all(context.temp_allocator)
}

@(test)
test_level_gen_circles :: proc(t: ^testing.T) {
	for seed in u64(1) ..= 20 {
		g := shape_grid(t, {40, 30}, `{"id": 1, "type": "circles", "params": {"count": 1, "min_radius": 6, "max_radius": 6, "filled": true}}`, seed)
		n, lo, hi := shape_stats(g)
		testing.expectf(t, hi - lo + 1 == [2]int{13, 13}, "seed %d: disc spans %v", seed, hi - lo + 1)
		testing.expectf(t, abs(f32(n) - math.PI * 6.5 * 6.5) < 20, "seed %d: disc of %d cells", seed, n)
		// A ring: the same outline, its middle empty.
		g = shape_grid(t, {40, 30}, `{"id": 1, "type": "circles", "params": {"count": 1, "min_radius": 6, "max_radius": 6}}`, seed)
		rn, rlo, rhi := shape_stats(g)
		c := (rlo + rhi) / 2
		testing.expectf(t, rhi - rlo + 1 == [2]int{13, 13} && rn < n / 2 && g.v[c.y * g.w + c.x] == 0, "seed %d: ring of %d cells", seed, rn)
	}
	// Bigger than the level: clipped, not out of bounds.
	g := shape_grid(t, {10, 8}, `{"id": 1, "type": "circles", "params": {"count": 3, "min_radius": 20, "max_radius": 30}}`)
	_, lo, hi := shape_stats(g)
	testing.expect(t, lo.x >= 0 && lo.y >= 0 && hi.x < 10 && hi.y < 8, "clipped to the level")
	free_all(context.temp_allocator)
}

@(test)
test_level_gen_shapes_seeded :: proc(t: ^testing.T) {
	for kind in ([]string{"lines", "rectangles", "circles"}) {
		node := fmt.tprintf(`{{"id": 1, "type": "%s", "params": {{"count": 8}}}}`, kind)
		a := shape_grid(t, {48, 32}, node, 3)
		b := shape_grid(t, {48, 32}, node, 3)
		c := shape_grid(t, {48, 32}, node, 4)
		same, other := true, false
		for v, i in a.v {
			if v != b.v[i] do same = false
			if v != c.v[i] do other = true
		}
		testing.expectf(t, same, "%s: the same seed, the same shapes", kind)
		testing.expectf(t, other, "%s: another seed, other shapes", kind)
		// No count: nothing.
		n, _, _ := shape_stats(shape_grid(t, {48, 32}, fmt.tprintf(`{{"id": 1, "type": "%s", "params": {{"count": 0}}}}`, kind)))
		testing.expect_value(t, n, 0)
	}
	free_all(context.temp_allocator)
}
