package engine

import "base:runtime"
import "core:container/priority_queue"
import "core:math"

// ============================================================================
// Navigation: A* path finding on the grid of a TileMapNode or an LDtk
// level.
//
// - TileMapNode: painted tiles block when the map is solid (walls), else
//   empty cells block (the painted tiles are the walkable floor) - or
//   either way with Nav_Options.walkablePainted.
// - LdtkLevelNode (its current level): cells of IntGrid layers whose
//   collision rule is Solid block; the grid is the finest such layer's.
// - NavigationRegionNode (navigation_nodes.odin): a rectangle baked from
//   static physics shapes, solid tile maps and LDtk Solid cells, plus cells
//   scripts block (doors).
// Paths move in 8 directions without cutting corners past blocked cells
// (or 4 with diagonal = false) and are straightened where the line of
// sight is clear (smooth). An agent radius keeps paths that far from walls:
// a clearance map (each cell's distance to the nearest blocked one) is made
// once per grid version, then it's one comparison per cell. Grids are
// cached per map and rebuilt when the map changes.
// ============================================================================

Nav_Grid :: struct {
	w, h:     int,
	blocked:  []bool,       // w*h
	origin:   [2]f32,       // world position of cell (0, 0)'s top-left corner
	cell:     [2]f32,       // cell size in world units
	rotation: f32,          // degrees
	key:      u64,          // what it was built from (rebuilt when it changes)
	clear:    []f32,        // distance (cells) to the nearest blocked cell (agent radius); made on demand
	clearKey: u64,          // the key `clear` was made for (+1)
}

Nav_Options :: struct {
	diagonal:        bool, // 8 directions (default true via Nav_DefaultOptions)
	smooth:          bool, // drop waypoints with a clear line of sight
	walkablePainted: Maybe(bool), // TileMap: painted tiles are the floor (default: !solid)
	radius:          f32,         // agent radius (world px): paths keep this far from walls
}

Nav_DefaultOptions :: proc() -> Nav_Options {
	return {diagonal = true, smooth = true}
}

// --- grid from a map ------------------------------------------------------------------

@(private = "file")
navCache: map[rawptr]^Nav_Grid

@(private = "file")
grid_alloc :: proc(g: ^Nav_Grid, w, h: int) {
	if len(g.blocked) != w * h {
		delete(g.blocked, Engine_HeapAllocator())
		g.blocked = make([]bool, w * h, Engine_HeapAllocator())
	} else {
		for &b in g.blocked do b = false
	}
	g.w, g.h = w, h
}

// Nav_GridFor: the (cached) grid of a TileMapNode or LdtkLevelNode, or nil.
Nav_GridFor :: proc(n: ^Node, opts: Nav_Options = {}) -> ^Nav_Grid {
	if n == nil do return nil
	if navCache == nil do navCache = make(map[rawptr]^Nav_Grid, allocator = Engine_HeapAllocator())
	g := navCache[n]
	if g == nil {
		g = new(Nav_Grid, Engine_HeapAllocator())
		navCache[n] = g
	}
	switch n.typeId {
	case TileMapNode:
		tm := cast(^TileMapNode)n
		TileMapNode_Layout(tm)
		painted := opts.walkablePainted.? or_else !tm.solid
		key := tm.cacheVersion * 31 + u64(len(tm.chunkVer)) * 7 + (1 if painted else 0)
		for _, v in tm.chunkVer do key += v * 0x9E3779B97F4A7C15
		if g.key != key || g.w != tm.mapSize.x || g.h != tm.mapSize.y {
			g.clearKey = 0
			grid_alloc(g, tm.mapSize.x, tm.mapSize.y)
			for t, i in tm.tiles do g.blocked[i] = (t < 0) == painted
			g.key = key
		}
		sx := tm.globalScale.x if tm.globalScale.x != 0 else 1
		sy := tm.globalScale.y if tm.globalScale.y != 0 else 1
		g.origin = TileMapNode_CellCorner(tm, {0, 0})
		g.cell = {f32(tm.tileSize.x) * sx, f32(tm.tileSize.y) * sy}
		g.rotation = tm.globalRotation
		return g
	case LdtkLevelNode:
		ln := cast(^LdtkLevelNode)n
		if ln.level == nil || ln.project == nil do return nil
		lvl := ln.level
		key := ln.project.loadId * 1_000_003 + u64(uintptr(lvl)) + u64(len(ln.collisionRules)) * 13
		// The finest IntGrid layer with solid cells sets the grid.
		base: ^LdtkLayerInstance
		for &layer in lvl.layers {
			if layer.type != .IntGrid || layer.cWid <= 0 do continue
			has := false
			for v in layer.intGrid do if v != 0 && LdtkLevelNode_CollisionRule(ln, layer.identifier, v).type == .Solid {has = true; break}
			if has && (base == nil || layer.gridSize < base.gridSize) do base = &layer
		}
		if base == nil do return nil
		scale := ln.globalScale
		levelOrigin := ln.globalPosition + LdtkLevelNode_LevelOffset(ln, lvl) * scale
		if g.key != key || g.w != base.cWid || g.h != base.cHei {
			g.clearKey = 0
			grid_alloc(g, base.cWid, base.cHei)
			gs := f32(base.gridSize)
			for &layer in lvl.layers {
				if layer.type != .IntGrid || layer.cWid <= 0 do continue
				ls := f32(layer.gridSize)
				for v, i in layer.intGrid {
					if v == 0 || LdtkLevelNode_CollisionRule(ln, layer.identifier, v).type != .Solid do continue
					// This cell's area in the base grid's cells.
					px := layer.offset + [2]f32{f32(i % layer.cWid), f32(i / layer.cWid)} * ls - base.offset
					x0, y0 := int(math.floor(px.x / gs)), int(math.floor(px.y / gs))
					x1, y1 := int(math.ceil((px.x + ls) / gs)), int(math.ceil((px.y + ls) / gs))
					for y in max(y0, 0) ..< min(y1, g.h) do for x in max(x0, 0) ..< min(x1, g.w) do g.blocked[y * g.w + x] = true
				}
			}
			g.key = key
		}
		g.origin = levelOrigin + base.offset * scale
		g.cell = {f32(base.gridSize) * scale.x, f32(base.gridSize) * scale.y}
		g.rotation = 0
		return g
	case NavigationRegionNode:
		r := cast(^NavigationRegionNode)n
		if !r.baked do NavRegion_Bake(r)
		key := r.bakeVersion
		if g.key != key || g.w != r.cells.x || g.h != r.cells.y {
			g.clearKey = 0
			grid_alloc(g, r.cells.x, r.cells.y)
			for b, i in r.blocked do g.blocked[i] = b != 0
			g.key = key
		}
		g.origin = r.bakedAt // (the cells line up with the world as baked)
		g.cell = {r.cellSize, r.cellSize}
		g.rotation = 0
		return g
	}
	return nil
}

// Nav_Clearance: the grid's clearance map (made when the grid changed).
Nav_Clearance :: proc(g: ^Nav_Grid) -> []f32 {
	if g.clearKey == g.key + 1 && len(g.clear) == g.w * g.h do return g.clear
	if len(g.clear) != g.w * g.h {
		delete(g.clear, Engine_HeapAllocator())
		g.clear = make([]f32, g.w * g.h, Engine_HeapAllocator())
	}
	INF :: f32(1e9)
	D2 :: f32(math.SQRT_TWO)
	w, h := g.w, g.h
	for b, i in g.blocked do g.clear[i] = 0 if b else INF
	for y in 0 ..< h do for x in 0 ..< w {
		i := y * w + x
		v := g.clear[i]
		if x > 0 do v = min(v, g.clear[i - 1] + 1)
		if y > 0 {
			v = min(v, g.clear[i - w] + 1)
			if x > 0 do v = min(v, g.clear[i - w - 1] + D2)
			if x < w - 1 do v = min(v, g.clear[i - w + 1] + D2)
		}
		g.clear[i] = v
	}
	for y := h - 1; y >= 0; y -= 1 do for x := w - 1; x >= 0; x -= 1 {
		i := y * w + x
		v := g.clear[i]
		if x < w - 1 do v = min(v, g.clear[i + 1] + 1)
		if y < h - 1 {
			v = min(v, g.clear[i + w] + 1)
			if x < w - 1 do v = min(v, g.clear[i + w + 1] + D2)
			if x > 0 do v = min(v, g.clear[i + w - 1] + D2)
		}
		g.clear[i] = v
	}
	g.clearKey = g.key + 1
	return g.clear
}

// nav_radius_cells: an agent radius in cells (0: just not blocked).
@(private = "file")
nav_radius_cells :: proc(g: ^Nav_Grid, radius: f32) -> f32 {
	if radius <= 0 do return 0
	return radius / max(min(g.cell.x, g.cell.y), 0.0001)
}

// Nav_Forget drops a map's cached grid (the map node is going away).
Nav_Forget :: proc(n: ^Node) {
	if g, ok := navCache[n]; ok {
		delete(g.blocked, Engine_HeapAllocator())
		delete(g.clear, Engine_HeapAllocator())
		free(g, Engine_HeapAllocator())
		delete_key(&navCache, n)
	}
}

// --- grid geometry -----------------------------------------------------------------

Nav_CellAt :: proc(g: ^Nav_Grid, world: [2]f32) -> [2]int {
	local := rotate_vec(world - g.origin, -g.rotation)
	return {int(math.floor(local.x / g.cell.x)), int(math.floor(local.y / g.cell.y))}
}

Nav_CellCenter :: proc(g: ^Nav_Grid, c: [2]int) -> [2]f32 {
	return g.origin + rotate_vec({(f32(c.x) + 0.5) * g.cell.x, (f32(c.y) + 0.5) * g.cell.y}, g.rotation)
}

// Nav_Walkable: an open cell - for an agent of `rcells` cells' radius, one
// at least that far from walls (Nav_Clearance first).
Nav_Walkable :: proc(g: ^Nav_Grid, c: [2]int, rcells: f32 = 0) -> bool {
	if c.x < 0 || c.y < 0 || c.x >= g.w || c.y >= g.h do return false
	i := c.y * g.w + c.x
	if rcells <= 0 do return !g.blocked[i]
	return g.clear[i] > rcells
}

// --- A* ---------------------------------------------------------------------------------

@(private = "file")
Open_Item :: struct {
	f:    f32,
	cell: i32,
}

// Nav_FindCells: the cells from start to goal (both included), or nil.
// The goal may be blocked only if it's the start (nowhere to go).
Nav_FindCells :: proc(g: ^Nav_Grid, start, goal: [2]int, diagonal := true, allocator := context.temp_allocator, rcells: f32 = 0) -> [][2]int {
	if rcells > 0 do Nav_Clearance(g)
	if !Nav_Walkable(g, start, rcells) || !Nav_Walkable(g, goal, rcells) do return nil
	n := g.w * g.h
	gScore := make([]f32, n, context.temp_allocator)
	came := make([]i32, n, context.temp_allocator)
	closed := make([]bool, n, context.temp_allocator)
	for i in 0 ..< n {gScore[i] = math.F32_MAX; came[i] = -1}
	h :: proc(a, b: [2]int, diagonal: bool) -> f32 {
		dx, dy := f32(abs(a.x - b.x)), f32(abs(a.y - b.y))
		if !diagonal do return dx + dy
		return max(dx, dy) + (math.SQRT_TWO - 1) * min(dx, dy) // octile
	}
	pq: priority_queue.Priority_Queue(Open_Item)
	priority_queue.init(&pq, proc(a, b: Open_Item) -> bool {return a.f < b.f}, priority_queue.default_swap_proc(Open_Item), allocator = context.temp_allocator)
	si := i32(start.y * g.w + start.x)
	gi := i32(goal.y * g.w + goal.x)
	gScore[si] = 0
	priority_queue.push(&pq, Open_Item{h(start, goal, diagonal), si})
	dirs := [8][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}, {1, 1}, {1, -1}, {-1, 1}, {-1, -1}}
	count := 8 if diagonal else 4
	for priority_queue.len(pq) > 0 {
		cur := priority_queue.pop(&pq)
		ci := cur.cell
		if closed[ci] do continue
		if ci == gi do break
		closed[ci] = true
		c := [2]int{int(ci) % g.w, int(ci) / g.w}
		for d in dirs[:count] {
			nb := c + d
			if !Nav_Walkable(g, nb, rcells) do continue
			// No corner cutting: both orthogonal neighbours must be open.
			if d.x != 0 && d.y != 0 && (!Nav_Walkable(g, {c.x + d.x, c.y}, rcells) || !Nav_Walkable(g, {c.x, c.y + d.y}, rcells)) do continue
			ni := i32(nb.y * g.w + nb.x)
			if closed[ni] do continue
			step: f32 = math.SQRT_TWO if d.x != 0 && d.y != 0 else 1
			tentative := gScore[ci] + step
			if tentative < gScore[ni] {
				gScore[ni] = tentative
				came[ni] = ci
				priority_queue.push(&pq, Open_Item{tentative + h(nb, goal, diagonal), ni})
			}
		}
	}
	if gScore[gi] == math.F32_MAX do return nil
	rev := make([dynamic][2]int, context.temp_allocator)
	for i := gi; i != -1; i = came[i] do append(&rev, [2]int{int(i) % g.w, int(i) / g.w})
	out := make([][2]int, len(rev), allocator)
	for p, i in rev do out[len(rev) - 1 - i] = p
	return out
}

// Nav_LineClear: the straight line between two cell centres crosses only
// walkable cells (an exact grid traversal; passing exactly through a
// corner needs both cells beside it open, like a diagonal step).
Nav_LineClear :: proc(g: ^Nav_Grid, a, b: [2]int, rcells: f32 = 0) -> bool {
	x, y := a.x, a.y
	dx, dy := f32(b.x - a.x), f32(b.y - a.y)
	stepX := 1 if dx > 0 else (-1 if dx < 0 else 0)
	stepY := 1 if dy > 0 else (-1 if dy < 0 else 0)
	// From a cell centre, the first boundary is half a cell away.
	tDeltaX := 1 / abs(dx) if dx != 0 else math.F32_MAX
	tDeltaY := 1 / abs(dy) if dy != 0 else math.F32_MAX
	tMaxX := 0.5 * tDeltaX if dx != 0 else math.F32_MAX
	tMaxY := 0.5 * tDeltaY if dy != 0 else math.F32_MAX
	EPS :: 1e-5
	for x != b.x || y != b.y {
		if tMaxX < tMaxY - EPS {
			x += stepX
			tMaxX += tDeltaX
		} else if tMaxY < tMaxX - EPS {
			y += stepY
			tMaxY += tDeltaY
		} else {
			// Through a corner.
			if !Nav_Walkable(g, {x + stepX, y}, rcells) || !Nav_Walkable(g, {x, y + stepY}, rcells) do return false
			x += stepX
			y += stepY
			tMaxX += tDeltaX
			tMaxY += tDeltaY
		}
		if !Nav_Walkable(g, {x, y}, rcells) do return false
	}
	return true
}

// Nav_NearestOpen: the open cell nearest to c (a ring search; ok = false
// when the grid has none).
Nav_NearestOpen :: proc(g: ^Nav_Grid, c: [2]int, rcells: f32 = 0) -> ([2]int, bool) {
	cc := [2]int{clamp(c.x, 0, g.w - 1), clamp(c.y, 0, g.h - 1)}
	if Nav_Walkable(g, cc, rcells) do return cc, true
	for d in 1 ..< max(g.w, g.h) {
		best, found := max(int), [2]int{}
		for oy in -d ..= d do for ox in -d ..= d {
			if abs(ox) != d && abs(oy) != d do continue
			p := cc + {ox, oy}
			if Nav_Walkable(g, p, rcells) && ox * ox + oy * oy < best do best, found = ox * ox + oy * oy, p
		}
		if best < max(int) do return found, true
	}
	return {}, false
}

// Nav_FindPath: world waypoints from `from` to `to` (cell centres between,
// starting at `from` and ending at `to`), or nil when there's no way (or
// either end is blocked or off the grid).
Nav_FindPath :: proc(g: ^Nav_Grid, from, to: [2]f32, opts: Nav_Options = {diagonal = true, smooth = true}, allocator := context.temp_allocator) -> [][2]f32 {
	if g == nil do return nil
	rc := nav_radius_cells(g, opts.radius)
	if rc > 0 do Nav_Clearance(g)
	start, goal := Nav_CellAt(g, from), Nav_CellAt(g, to)
	endAt := to
	if rc > 0 {
		// A big agent standing (or aiming) where only a smaller one fits:
		// from / to the nearest cell it fits in.
		ok: bool
		if !Nav_Walkable(g, start, rc) {
			start, ok = Nav_NearestOpen(g, start, rc)
			if !ok do return nil
		}
		if !Nav_Walkable(g, goal, rc) {
			goal, ok = Nav_NearestOpen(g, goal, rc)
			if !ok do return nil
			endAt = Nav_CellCenter(g, goal)
		}
	}
	cells := Nav_FindCells(g, start, goal, opts.diagonal, context.temp_allocator, rc)
	if cells == nil do return nil
	kept := make([dynamic][2]int, context.temp_allocator)
	append(&kept, cells[0])
	if opts.smooth {
		// String pulling: skip waypoints while the line of sight is clear.
		anchor := 0
		for i in 2 ..< len(cells) {
			if !Nav_LineClear(g, cells[anchor], cells[i], rc) {
				append(&kept, cells[i - 1])
				anchor = i - 1
			}
		}
		if len(cells) > 1 do append(&kept, cells[len(cells) - 1])
	} else {
		append(&kept, ..cells[1:])
	}
	if len(kept) == 1 do append(&kept, kept[0]) // same cell: straight there
	out := make([][2]f32, len(kept), allocator)
	for c, i in kept do out[i] = Nav_CellCenter(g, c)
	out[0] = from
	out[len(out) - 1] = endAt
	return out
}
