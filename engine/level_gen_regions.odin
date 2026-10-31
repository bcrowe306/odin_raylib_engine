package engine

import "core:fmt"
import "core:slice"

// ============================================================================
// Playable levels (#171): nodes about the open (walkable) areas of a grid -
// which cells are open is a node's `open` choice: low (below 0.5: caves from
// Cellular, where 1 is rock) or high (0.5 and above: the floors of Rooms and
// Walker). Areas are 4-connected (`diagonal`: 8-connected too).
//
//   flood_fill       the cells reachable from a start cell (1), the rest 0
//   regions          keep the largest open area, or remove the small ones
//   connect_regions  corridors joining every open area to the largest
//   path             a way from a start to an exit, carved where walls are
//   check            refuses a level with too little open, or in pieces
//
// The level nodes (regions, connect, path's "level") give their input back
// as 0 / 1 in the same sense (open stays open); corridors never cut the
// outer row of cells, so a level's walls stay closed.
// ============================================================================

GEN_OPEN_SIDES := []string{"low", "high"}
GEN_REGION_MODES := []string{"keep_largest", "remove_small"}
GEN_PATH_PLACEMENTS := []string{"left_right", "top_bottom", "farthest", "custom"}
GEN_PATH_OUTPUTS := []string{"level", "path", "start", "end"}

@(private)
GEN_OPEN_DOC :: "Which cells are open (walkable): low (below 0.5 - caves from Cellular) or high (0.5 and above - Rooms and Walker floors)"
@(private)
GEN_DIAGONAL_DOC :: "Cells touching at a corner are joined too (8 neighbours, not 4)"

// gen_open_cells: the input's open cells.
@(private)
gen_open_cells :: proc(src: Gen_Grid, high: bool) -> []bool {
	open := make([]bool, len(src.v), context.temp_allocator)
	#no_bounds_check for v, i in src.v do open[i] = (v >= 0.5) == high
	return open
}

// gen_write_open: open cells as the input had them (0 low, 1 high), the
// rest the other way.
@(private)
gen_write_open :: proc(out: Gen_Grid, open: []bool, high: bool) {
	#no_bounds_check for o, i in open do out.v[i] = 1 if o == high else 0
}

// gen_label: each open cell's area (0, 1, ...; -1 for closed cells) and
// every area's size, areas numbered in row order.
@(private)
gen_label :: proc(open: []bool, w, h: int, diagonal: bool) -> (labels: []i32, sizes: [dynamic]int) {
	labels = make([]i32, len(open), context.temp_allocator)
	slice.fill(labels, -1)
	sizes = make([dynamic]int, context.temp_allocator)
	queue := make([]i32, len(open), context.temp_allocator)
	#no_bounds_check for start in 0 ..< len(open) {
		if !open[start] || labels[start] >= 0 do continue
		id := i32(len(sizes))
		labels[start] = id
		queue[0] = i32(start)
		head, tail := 0, 1
		for head < tail {
			c := int(queue[head])
			head += 1
			x, y := c % w, c / w
			for dy in -1 ..= 1 do for dx in -1 ..= 1 {
				if dx == 0 && dy == 0 do continue
				if !diagonal && dx != 0 && dy != 0 do continue
				nx, ny := x + dx, y + dy
				if nx < 0 || ny < 0 || nx >= w || ny >= h do continue
				n := ny * w + nx
				if !open[n] || labels[n] >= 0 do continue
				labels[n] = id
				queue[tail] = i32(n)
				tail += 1
			}
		}
		append(&sizes, tail)
	}
	return
}

// gen_largest: the biggest area (the first in row order of equal ones; -1: none).
@(private)
gen_largest :: proc(sizes: []int) -> int {
	best := -1
	for s, i in sizes do if best < 0 || s > sizes[best] do best = i
	return best
}

GEN_NEIGHBOURS4 :: [4][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}

// gen_inner: corridors stay off the outer row of cells (a level smaller
// than 3 cells across has none).
@(private)
gen_inner :: #force_inline proc(x, y, w, h: int) -> bool {
	return w < 3 || h < 3 || (x > 0 && y > 0 && x < w - 1 && y < h - 1)
}

// gen_carve_open: a width x width square of open cells around a cell (off
// the outer row).
@(private)
gen_carve_open :: proc(open: []bool, w, h, c, width: int) {
	x0, y0 := c % w - (width - 1) / 2, c / w - (width - 1) / 2
	for y in y0 ..< y0 + width do for x in x0 ..< x0 + width {
		if x < 0 || y < 0 || x >= w || y >= h do continue
		if x == c % w && y == c / w || gen_inner(x, y, w, h) do open[y * w + x] = true
	}
}

// gen_nearest_open: the open cell nearest a cell (by steps; itself if open;
// the cell itself when none is open).
@(private)
gen_nearest_open :: proc(open: []bool, w, h, x, y: int) -> int {
	s := clamp(y, 0, h - 1) * w + clamp(x, 0, w - 1)
	if open[s] do return s
	seen := make([]bool, len(open), context.temp_allocator)
	queue := make([]i32, len(open), context.temp_allocator)
	queue[0], seen[s] = i32(s), true
	head, tail := 0, 1
	for head < tail {
		c := int(queue[head])
		head += 1
		for d in GEN_NEIGHBOURS4 {
			nx, ny := c % w + d.x, c / w + d.y
			if nx < 0 || ny < 0 || nx >= w || ny >= h do continue
			n := ny * w + nx
			if seen[n] do continue
			if open[n] do return n
			seen[n] = true
			queue[tail] = i32(n)
			tail += 1
		}
	}
	return s
}

// gen_flood: the open cells reachable from `start` (marked), and the last
// one reached (the farthest, by steps).
@(private)
gen_flood :: proc(open: []bool, w, h, start: int, diagonal: bool) -> (reached: []bool, farthest: int) {
	reached = make([]bool, len(open), context.temp_allocator)
	farthest = start
	if !open[start] do return
	queue := make([]i32, len(open), context.temp_allocator)
	queue[0], reached[start] = i32(start), true
	head, tail := 0, 1
	#no_bounds_check for head < tail {
		c := int(queue[head])
		head += 1
		farthest = c
		x, y := c % w, c / w
		for dy in -1 ..= 1 do for dx in -1 ..= 1 {
			if dx == 0 && dy == 0 do continue
			if !diagonal && dx != 0 && dy != 0 do continue
			nx, ny := x + dx, y + dy
			if nx < 0 || ny < 0 || nx >= w || ny >= h do continue
			n := ny * w + nx
			if !open[n] || reached[n] do continue
			reached[n] = true
			queue[tail] = i32(n)
			tail += 1
		}
	}
	return
}

@(private)
gen_flood_fill :: proc(src, out: Gen_Grid, x, y: int, high, diagonal: bool) {
	w, h := src.w, src.h
	open := gen_open_cells(src, high)
	sx, sy := x if x >= 0 else w / 2, y if y >= 0 else h / 2
	reached, _ := gen_flood(open, w, h, gen_nearest_open(open, w, h, sx, sy), diagonal)
	#no_bounds_check for r, i in reached do out.v[i] = 1 if r else 0
}

@(private)
gen_regions :: proc(src, out: Gen_Grid, removeSmall: bool, minSize: int, high, diagonal: bool) {
	open := gen_open_cells(src, high)
	labels, sizes := gen_label(open, src.w, src.h, diagonal)
	largest := gen_largest(sizes[:])
	#no_bounds_check for l, i in labels {
		if l < 0 do continue
		open[i] = sizes[l] >= minSize if removeSmall else int(l) == largest
	}
	gen_write_open(out, open, high)
}

// gen_connect_regions joins the open areas (of at least minSize cells -
// smaller ones are filled) into one with the shortest corridors: a search
// spreads through rock (off the outer row) from every area at once; where
// two areas' fronts meet is the shortest bridge between them; the cheapest
// bridges that join every area (Kruskal's spanning tree) are carved,
// `width` cells wide. One pass over the grid, however many areas.
@(private)
gen_connect_regions :: proc(src, out: Gen_Grid, width, minSize: int, high, diagonal: bool) #no_bounds_check {
	w, h := src.w, src.h
	open := gen_open_cells(src, high)
	labels, sizes := gen_label(open, w, h, diagonal)
	largest := gen_largest(sizes[:])
	if minSize > 0 && largest >= 0 {
		for l, i in labels do if l >= 0 && int(l) != largest && sizes[l] < minSize {
			open[i] = false
			labels[i] = -1
		}
	}
	// The fronts: every open cell starts at distance 0 owned by its area.
	owner := make([]i32, len(open), context.temp_allocator)
	dist := make([]i32, len(open), context.temp_allocator)
	parent := make([]i32, len(open), context.temp_allocator)
	queue := make([]i32, len(open), context.temp_allocator)
	slice.fill(owner, -1)
	head, tail := 0, 0
	for l, i in labels do if l >= 0 {
		owner[i], dist[i], parent[i] = l, 0, -1
		queue[tail] = i32(i)
		tail += 1
	}
	Bridge :: struct {
		cost:  i32,
		a, b:  i32, // the two cells where the fronts met
		la, lb: i32, // their areas (la < lb)
	}
	best := make(map[[2]i32]Bridge, allocator = context.temp_allocator)
	for head < tail {
		c := int(queue[head])
		head += 1
		for d in GEN_NEIGHBOURS4 {
			nx, ny := c % w + d.x, c / w + d.y
			if nx < 0 || ny < 0 || nx >= w || ny >= h do continue
			n := ny * w + nx
			if owner[n] < 0 {
				if open[n] || !gen_inner(nx, ny, w, h) do continue
				owner[n], dist[n], parent[n] = owner[c], dist[c] + 1, i32(c)
				queue[tail] = i32(n)
				tail += 1
			} else if owner[n] != owner[c] {
				la, lb, ca, cb := owner[c], owner[n], i32(c), i32(n)
				if la > lb do la, lb, ca, cb = lb, la, cb, ca
				br := Bridge{dist[c] + dist[n], ca, cb, la, lb}
				if old, ok := best[{la, lb}]; !ok || br.cost < old.cost || (br.cost == old.cost && (br.a < old.a || (br.a == old.a && br.b < old.b))) do best[{la, lb}] = br
			}
		}
	}
	bridges := make([dynamic]Bridge, 0, len(best), context.temp_allocator)
	for _, br in best do append(&bridges, br)
	slice.sort_by(bridges[:], proc(x, y: Bridge) -> bool {
		if x.cost != y.cost do return x.cost < y.cost
		if x.la != y.la do return x.la < y.la
		return x.lb < y.lb
	})
	// Kruskal: a bridge is carved when its areas aren't joined yet.
	group := make([]i32, len(sizes), context.temp_allocator)
	for &g, i in group do g = i32(i)
	find :: proc(group: []i32, x: i32) -> i32 {
		x := x
		for group[x] != x {
			group[x] = group[group[x]]
			x = group[x]
		}
		return x
	}
	for br in bridges {
		ra, rb := find(group, br.la), find(group, br.lb)
		if ra == rb do continue
		group[max(ra, rb)] = min(ra, rb)
		for end in ([2]i32{br.a, br.b}) do for c := int(end); c >= 0 && dist[c] > 0; c = int(parent[c]) do gen_carve_open(open, w, h, c, width)
	}
	gen_write_open(out, open, high)
}

// gen_path: the cheapest way from start to end - stepping onto an open
// cell is free, onto rock costs one (it is carved) - so the path follows
// the open areas and cuts as little as it can. `which` 0: the level with
// it carved, 1: the path's cells, 2: the start cell, 3: the end cell.
@(private)
gen_path :: proc(src, out: Gen_Grid, placement: int, custom: [4]int, width: int, high: bool, which: int) {
	w, h := src.w, src.h
	open := gen_open_cells(src, high)
	start, end: int
	switch placement {
	case 1: // top to bottom
		start, end = gen_nearest_open(open, w, h, w / 2, 0), gen_nearest_open(open, w, h, w / 2, h - 1)
	case 2: // the two open cells farthest apart (of the centre's area)
		a := gen_nearest_open(open, w, h, w / 2, h / 2)
		if open[a] {
			_, b := gen_flood(open, w, h, a, false)
			_, c := gen_flood(open, w, h, b, false)
			start, end = b, c
		} else {
			start, end = gen_nearest_open(open, w, h, 0, h / 2), gen_nearest_open(open, w, h, w - 1, h / 2)
		}
	case 3: // custom cells
		start = clamp(custom[1], 0, h - 1) * w + clamp(custom[0], 0, w - 1)
		end = clamp(custom[3], 0, h - 1) * w + clamp(custom[2], 0, w - 1)
	case: // left to right
		start, end = gen_nearest_open(open, w, h, 0, h / 2), gen_nearest_open(open, w, h, w - 1, h / 2)
	}
	// 0-1 search in cost layers: free steps stay in this layer, carving
	// ones go to the next.
	dist := make([]i32, len(open), context.temp_allocator)
	parent := make([]i32, len(open), context.temp_allocator)
	slice.fill(dist, max(i32))
	slice.fill(parent, -1)
	cur := make([dynamic]i32, context.temp_allocator)
	next := make([dynamic]i32, context.temp_allocator)
	dist[start] = 0
	append(&cur, i32(start))
	for k: i32 = 0; len(cur) > 0 && dist[end] == max(i32); k += 1 {
		#no_bounds_check for i := 0; i < len(cur); i += 1 {
			c := int(cur[i])
			if dist[c] != k do continue
			for d in GEN_NEIGHBOURS4 {
				nx, ny := c % w + d.x, c / w + d.y
				if nx < 0 || ny < 0 || nx >= w || ny >= h do continue
				n := ny * w + nx
				if !open[n] && n != end && !gen_inner(nx, ny, w, h) do continue
				nd := k + (0 if open[n] else 1)
				if nd >= dist[n] do continue
				dist[n], parent[n] = nd, i32(c)
				if nd == k do append(&cur, i32(n))
				else do append(&next, i32(n))
			}
		}
		cur, next = next, cur
		clear(&next)
	}
	onPath := make([]bool, len(open), context.temp_allocator)
	if dist[end] != max(i32) do for c := end; c >= 0; c = int(parent[c]) {
		onPath[c] = true
		gen_carve_open(onPath, w, h, c, width)
	}
	switch which {
	case 1:
		#no_bounds_check for p, i in onPath do out.v[i] = 1 if p else 0
	case 2:
		out.v[start] = 1
	case 3:
		out.v[end] = 1
	case:
		#no_bounds_check for p, i in onPath do if p do open[i] = true
		gen_write_open(out, open, high)
	}
}

// gen_check: why the level isn't good enough ("" = it is): less than
// minOpen of it open, or (connected) its open cells in more than one area.
@(private)
gen_check :: proc(src: Gen_Grid, minOpen: f32, connected, high, diagonal: bool) -> string {
	open := gen_open_cells(src, high)
	count := 0
	for o in open do if o do count += 1
	frac := f32(count) / f32(max(len(open), 1))
	if frac < minOpen do return fmt.tprintf("only %.0f%% of the level is open (needs %.0f%%)", frac * 100, minOpen * 100)
	if connected {
		_, sizes := gen_label(open, src.w, src.h, diagonal)
		if len(sizes) > 1 do return fmt.tprintf("the open area is in %d separate parts (needs one)", len(sizes))
	}
	return ""
}
