package engine

import "core:math"
import rl "vendor:raylib"

// ============================================================================
// Tile map grids (#278): where a TileMapNode's cells are. Square cells sit
// in rows and columns; Isometric cells are diamonds on a grid turned 45
// degrees (Tiled's "isometric"); Staggered cells are diamonds in rows,
// every other row shifted half a cell (Tiled's "staggered"); Hex Pointy /
// Hex Flat are hexagons in offset rows / columns. Stagger says which rows
// (columns for Hex Flat) are the shifted ones.
//
// Cell Size is the grid's cell (0 = the tile size, as square maps always
// had); a tile image larger than its cell - a wall, a block - is drawn
// standing on it: bottom-aligned, centred across.
//
// Coordinates here are the map's own (unscaled, unrotated) pixels; a
// cell's "box" is its bounding rectangle there.
// ============================================================================

TileMap_Layout :: enum u8 {
	Square,
	Isometric,
	Staggered,
	HexPointy,
	HexFlat,
}

TileMap_Stagger :: enum u8 {Odd, Even}

// TileMapNode_CellSize: the grid's cell in map pixels.
TileMapNode_CellSize :: proc(tm: ^TileMapNode) -> [2]f32 {
	w := tm.cellSize.x if tm.cellSize.x > 0 else f32(max(tm.tileSize.x, 1))
	h := tm.cellSize.y if tm.cellSize.y > 0 else f32(max(tm.tileSize.y, 1))
	return {w, h}
}

// tilemap_shifted: row (column) i is one of the shifted ones.
@(private = "file")
tilemap_shifted :: #force_inline proc(tm: ^TileMapNode, i: int) -> bool {
	return grid_shifted(tm.stagger, i)
}

@(private = "file")
grid_shifted :: #force_inline proc(stagger: TileMap_Stagger, i: int) -> bool {
	odd := i & 1 == 1
	return odd if stagger == .Odd else !odd
}

// TileMapNode_CellBox: a cell's bounding box in map pixels.
TileMapNode_CellBox :: proc(tm: ^TileMapNode, cell: [2]int) -> rl.Rectangle {
	c := TileMapNode_CellSize(tm)
	w, h := c.x, c.y
	x, y := f32(cell.x), f32(cell.y)
	switch tm.layout {
	case .Square:
		return {x * w, y * h, w, h}
	case .Isometric:
		return {(x - y) * w * 0.5, (x + y) * h * 0.5, w, h}
	case .Staggered:
		s: f32 = 0.5 if tilemap_shifted(tm, cell.y) else 0
		return {(x + s) * w, y * h * 0.5, w, h}
	case .HexPointy:
		s: f32 = 0.5 if tilemap_shifted(tm, cell.y) else 0
		return {(x + s) * w, y * h * 0.75, w, h}
	case .HexFlat:
		s: f32 = 0.5 if tilemap_shifted(tm, cell.x) else 0
		return {x * w * 0.75, (y + s) * h, w, h}
	}
	return {}
}

// TileMapNode_CellOutline: a cell's outline in map pixels (clockwise from
// the top); returns the corner count (4 or 6).
TileMapNode_CellOutline :: proc(tm: ^TileMapNode, cell: [2]int) -> (pts: [6][2]f32, n: int) {
	b := TileMapNode_CellBox(tm, cell)
	x, y, w, h := b.x, b.y, b.width, b.height
	switch tm.layout {
	case .Square:
		return {{x, y}, {x + w, y}, {x + w, y + h}, {x, y + h}, {}, {}}, 4
	case .Isometric, .Staggered:
		return {{x + w * 0.5, y}, {x + w, y + h * 0.5}, {x + w * 0.5, y + h}, {x, y + h * 0.5}, {}, {}}, 4
	case .HexPointy:
		return {{x + w * 0.5, y}, {x + w, y + h * 0.25}, {x + w, y + h * 0.75}, {x + w * 0.5, y + h}, {x, y + h * 0.75}, {x, y + h * 0.25}}, 6
	case .HexFlat:
		return {{x + w * 0.25, y}, {x + w * 0.75, y}, {x + w, y + h * 0.5}, {x + w * 0.75, y + h}, {x + w * 0.25, y + h}, {x, y + h * 0.5}}, 6
	}
	return
}

// TileMapNode_CellLocalCenter: a cell's centre in map pixels.
TileMapNode_CellLocalCenter :: proc(tm: ^TileMapNode, cell: [2]int) -> [2]f32 {
	b := TileMapNode_CellBox(tm, cell)
	return {b.x + b.width * 0.5, b.y + b.height * 0.5}
}

// TileMapNode_LocalToWorld / TileMapNode_WorldToLocal: map pixels <-> world.
TileMapNode_LocalToWorld :: proc(tm: ^TileMapNode, local: [2]f32) -> [2]f32 {
	sx := tm.globalScale.x if tm.globalScale.x != 0 else 1
	sy := tm.globalScale.y if tm.globalScale.y != 0 else 1
	p := [2]f32{local.x * sx, local.y * sy}
	if tm.globalRotation == 0 do return tm.globalPosition + p
	rad := tm.globalRotation * math.RAD_PER_DEG
	c, s := math.cos(rad), math.sin(rad)
	return tm.globalPosition + {p.x * c - p.y * s, p.x * s + p.y * c}
}

TileMapNode_WorldToLocal :: proc(tm: ^TileMapNode, world: [2]f32) -> [2]f32 {
	local := world - tm.globalPosition
	if tm.globalRotation != 0 {
		rad := -tm.globalRotation * math.RAD_PER_DEG
		c, s := math.cos(rad), math.sin(rad)
		local = {local.x * c - local.y * s, local.x * s + local.y * c}
	}
	sx := tm.globalScale.x if tm.globalScale.x != 0 else 1
	sy := tm.globalScale.y if tm.globalScale.y != 0 else 1
	return {local.x / sx, local.y / sy}
}

// TileMapNode_CellCenter: a cell's centre in the world.
TileMapNode_CellCenter :: proc(tm: ^TileMapNode, cell: [2]int) -> [2]f32 {
	return TileMapNode_LocalToWorld(tm, TileMapNode_CellLocalCenter(tm, cell))
}

// TileMapNode_LocalCellAt: the cell under a point in map pixels.
TileMapNode_LocalCellAt :: proc(tm: ^TileMapNode, p: [2]f32) -> [2]int {
	c := TileMapNode_CellSize(tm)
	w, h := c.x, c.y
	switch tm.layout {
	case .Square:
		return {int(math.floor(p.x / w)), int(math.floor(p.y / h))}
	case .Isometric:
		// The grid turned back: x - y and x + y in half cells from cell 0's centre.
		u := (p.x - w * 0.5) / (w * 0.5)
		v := (p.y - h * 0.5) / (h * 0.5)
		return {int(math.floor((u + v) * 0.5 + 0.5)), int(math.floor((v - u) * 0.5 + 0.5))}
	case .Staggered, .HexPointy, .HexFlat:
		// A guess from the box grid, then the neighbour whose outline holds it.
		guess: [2]int
		#partial switch tm.layout {
		case .Staggered: guess = {int(math.floor(p.x / w)), int(math.floor(p.y / (h * 0.5)))}
		case .HexPointy: guess = {int(math.floor(p.x / w)), int(math.floor(p.y / (h * 0.75)))}
		case .HexFlat:   guess = {int(math.floor(p.x / (w * 0.75))), int(math.floor(p.y / h))}
		}
		best := guess
		bestD := f32(math.F32_MAX)
		for dy in -2 ..= 2 do for dx in -2 ..= 2 {
			cell := guess + {dx, dy}
			pts, n := TileMapNode_CellOutline(tm, cell)
			if point_in_convex(p, pts[:n]) do return cell
			ctr := TileMapNode_CellLocalCenter(tm, cell)
			d := (p.x - ctr.x) * (p.x - ctr.x) / (w * w) + (p.y - ctr.y) * (p.y - ctr.y) / (h * h)
			if d < bestD do best, bestD = cell, d
		}
		return best // (on an edge)
	}
	return {}
}

// point_in_convex: p inside (or on) a convex polygon, either winding.
point_in_convex :: proc(p: [2]f32, pts: [][2]f32) -> bool {
	sign: f32 = 0
	for a, i in pts {
		b := pts[(i + 1) % len(pts)]
		cr := (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
		if cr == 0 do continue
		if sign == 0 do sign = cr
		else if (cr > 0) != (sign > 0) do return false
	}
	return true
}

// TileMapNode_TileRect: where a cell's tile image is drawn, in map pixels -
// standing on the cell (bottom-aligned, centred across), moved by Tile
// Offset.
TileMapNode_TileRect :: proc(tm: ^TileMapNode, cell: [2]int) -> rl.Rectangle {
	b := TileMapNode_CellBox(tm, cell)
	tw, th := f32(tm.tileSize.x), f32(tm.tileSize.y)
	return {b.x + (b.width - tw) * 0.5 + tm.tileOffset.x, b.y + b.height - th + tm.tileOffset.y, tw, th}
}

// TileMapNode_IsPlainGrid: square cells the size of the tiles (the fast,
// chunk-cached path).
TileMapNode_IsPlainGrid :: proc(tm: ^TileMapNode) -> bool {
	if tm.layout != .Square || tm.tileOffset != {} do return false
	c := TileMapNode_CellSize(tm)
	return int(c.x) == tm.tileSize.x && int(c.y) == tm.tileSize.y && c.x == f32(int(c.x)) && c.y == f32(int(c.y))
}

// Bands: the cells that share a box top - drawn together, back (top) to
// front; with Y Sort on, each band sorts with Y-sorted sprites (a character
// behind a wall's band is hidden by it). Square, Staggered and Hex Pointy:
// a row. Isometric: a diagonal (x + y). Hex Flat: half a row (the shifted
// columns are lower).

// TileMapNode_BandOf: a cell's band.
TileMapNode_BandOf :: proc(tm: ^TileMapNode, cell: [2]int) -> int {
	switch tm.layout {
	case .Square, .Staggered, .HexPointy: return cell.y
	case .Isometric: return cell.x + cell.y
	case .HexFlat: return cell.y * 2 + (1 if tilemap_shifted(tm, cell.x) else 0)
	}
	return cell.y
}

// TileMapNode_BandRange: the bands of the cells in [lo, hi).
TileMapNode_BandRange :: proc(tm: ^TileMapNode, lo, hi: [2]int) -> (b0, b1: int) {
	if hi.x <= lo.x || hi.y <= lo.y do return 0, 0
	switch tm.layout {
	case .Square, .Staggered, .HexPointy: return lo.y, hi.y
	case .Isometric: return lo.x + lo.y, hi.x + hi.y - 1
	case .HexFlat: return lo.y * 2, hi.y * 2
	}
	return lo.y, hi.y
}

// TileMapNode_BandCells calls fn for the cells of band b inside [lo, hi),
// left to right.
TileMapNode_BandCells :: proc(tm: ^TileMapNode, b: int, lo, hi: [2]int, data: rawptr, fn: proc(tm: ^TileMapNode, cell: [2]int, data: rawptr)) {
	switch tm.layout {
	case .Square, .Staggered, .HexPointy:
		if b < lo.y || b >= hi.y do return
		for x in lo.x ..< hi.x do fn(tm, {x, b}, data)
	case .Isometric:
		// x - y grows to the right: x up, y down.
		for x in max(lo.x, b - (hi.y - 1)) ..= min(hi.x - 1, b - lo.y) do fn(tm, {x, b - x}, data)
	case .HexFlat:
		y := b >> 1
		if y < lo.y || y >= hi.y do return
		shifted := b & 1 == 1
		for x in lo.x ..< hi.x do if tilemap_shifted(tm, x) == shifted do fn(tm, {x, y}, data)
	}
}

// TileMapNode_BandBottom: band b's feet line in map pixels (its cells' box
// bottom) - the Y it sorts by.
TileMapNode_BandBottom :: proc(tm: ^TileMapNode, b: int) -> f32 {
	h := TileMapNode_CellSize(tm).y
	switch tm.layout {
	case .Square: return f32(b + 1) * h
	case .Isometric, .Staggered: return f32(b) * h * 0.5 + h
	case .HexPointy: return f32(b) * h * 0.75 + h
	case .HexFlat: return f32(b) * h * 0.5 + h
	}
	return 0
}

// TileMapNode_CellsInLocalRect: a cell range [lo, hi) covering a rectangle
// in map pixels (with the room tall tiles need), clipped to [clipLo, clipHi).
TileMapNode_CellsInLocalRect :: proc(tm: ^TileMapNode, r: rl.Rectangle, clipLo, clipHi: [2]int) -> (lo, hi: [2]int) {
	c := TileMapNode_CellSize(tm)
	tall := max(f32(tm.tileSize.y) - c.y, 0)
	wide := max(f32(tm.tileSize.x) - c.x, 0) * 0.5
	r := rl.Rectangle{r.x - wide, r.y, r.width + wide * 2, r.height + tall}
	corners := [4][2]f32{{r.x, r.y}, {r.x + r.width, r.y}, {r.x, r.y + r.height}, {r.x + r.width, r.y + r.height}}
	for p, i in corners {
		cell := TileMapNode_LocalCellAt(tm, p)
		if i == 0 do lo, hi = cell, cell
		lo = {min(lo.x, cell.x), min(lo.y, cell.y)}
		hi = {max(hi.x, cell.x), max(hi.y, cell.y)}
	}
	lo -= 1
	hi += 2
	lo = {clamp(lo.x, clipLo.x, clipHi.x), clamp(lo.y, clipLo.y, clipHi.y)}
	hi = {clamp(hi.x, clipLo.x, clipHi.x), clamp(hi.y, clipLo.y, clipHi.y)}
	return
}

// TileMapNode_MapLocalBounds: the map's outline cells' bounding box in map
// pixels, tiles standing on them included.
TileMapNode_MapLocalBounds :: proc(tm: ^TileMapNode, lo, hi: [2]int) -> rl.Rectangle {
	if hi.x <= lo.x || hi.y <= lo.y do return {}
	mn, mx: [2]f32
	first := true
	add :: proc(mn, mx: ^[2]f32, first: ^bool, r: rl.Rectangle) {
		if first^ {
			mn^, mx^ = {r.x, r.y}, {r.x + r.width, r.y + r.height}
			first^ = false
			return
		}
		mn^ = {min(mn.x, r.x), min(mn.y, r.y)}
		mx^ = {max(mx.x, r.x + r.width), max(mx.y, r.y + r.height)}
	}
	// (The extremes are on the edge cells; both parities for the shifted layouts.)
	for x in ([4]int{lo.x, lo.x + 1, hi.x - 2, hi.x - 1}) do for y in ([4]int{lo.y, lo.y + 1, hi.y - 2, hi.y - 1}) {
		if x < lo.x || y < lo.y || x >= hi.x || y >= hi.y do continue
		add(&mn, &mx, &first, TileMapNode_CellBox(tm, {x, y}))
		add(&mn, &mx, &first, TileMapNode_TileRect(tm, {x, y}))
	}
	return {mn.x, mn.y, mx.x - mn.x, mx.y - mn.y}
}

// TileMapNode_WorldAABB: the world rectangle around cells [lo, hi) and the
// tiles standing on them.
TileMapNode_WorldAABB :: proc(tm: ^TileMapNode, lo, hi: [2]int) -> rl.Rectangle {
	r := TileMapNode_MapLocalBounds(tm, lo, hi)
	return tilemap_aabb({
		TileMapNode_LocalToWorld(tm, {r.x, r.y}), TileMapNode_LocalToWorld(tm, {r.x + r.width, r.y}),
		TileMapNode_LocalToWorld(tm, {r.x + r.width, r.y + r.height}), TileMapNode_LocalToWorld(tm, {r.x, r.y + r.height}),
	})
}

tilemap_aabb :: proc(pts: [4][2]f32) -> rl.Rectangle {
	mn, mx := pts[0], pts[0]
	for p in pts {
		mn = {min(mn.x, p.x), min(mn.y, p.y)}
		mx = {max(mx.x, p.x), max(mx.y, p.y)}
	}
	return {mn.x, mn.y, mx.x - mn.x, mx.y - mn.y}
}

// TileMapNode_MapOutline: the map's (0..mapSize) outline in the world, for
// the editor: its four corners - a diamond for Isometric, the bounding box
// of the cells otherwise.
TileMapNode_MapOutline :: proc(tm: ^TileMapNode) -> [4][2]f32 {
	if tm.layout == .Isometric {
		w, h := tm.mapSize.x, tm.mapSize.y
		t, _ := TileMapNode_CellOutline(tm, {0, 0})
		r, _ := TileMapNode_CellOutline(tm, {w - 1, 0})
		b, _ := TileMapNode_CellOutline(tm, {w - 1, h - 1})
		l, _ := TileMapNode_CellOutline(tm, {0, h - 1})
		return {TileMapNode_LocalToWorld(tm, t[0]), TileMapNode_LocalToWorld(tm, r[1]), TileMapNode_LocalToWorld(tm, b[2]), TileMapNode_LocalToWorld(tm, l[3])}
	}
	lo, hi := [2]f32{}, [2]f32{}
	if tm.layout == .Square {
		c := TileMapNode_CellSize(tm)
		hi = {f32(tm.mapSize.x) * c.x, f32(tm.mapSize.y) * c.y}
	} else {
		mn := [2]f32{math.F32_MAX, math.F32_MAX}
		mx := [2]f32{-math.F32_MAX, -math.F32_MAX}
		for x in ([4]int{0, 1, tm.mapSize.x - 2, tm.mapSize.x - 1}) do for y in ([4]int{0, 1, tm.mapSize.y - 2, tm.mapSize.y - 1}) {
			if x < 0 || y < 0 || x >= tm.mapSize.x || y >= tm.mapSize.y do continue
			b := TileMapNode_CellBox(tm, {x, y})
			mn = {min(mn.x, b.x), min(mn.y, b.y)}
			mx = {max(mx.x, b.x + b.width), max(mx.y, b.y + b.height)}
		}
		lo, hi = mn, mx
	}
	return {TileMapNode_LocalToWorld(tm, lo), TileMapNode_LocalToWorld(tm, {hi.x, lo.y}), TileMapNode_LocalToWorld(tm, hi), TileMapNode_LocalToWorld(tm, {lo.x, hi.y})}
}

// TileMapNode_Neighbors: the cells sharing a side with this one (4 or 6).
TileMapNode_Neighbors :: proc(tm: ^TileMapNode, cell: [2]int) -> (out: [6][2]int, n: int) {
	return Grid_Neighbors(tm.layout, tm.stagger, cell)
}

Grid_Neighbors :: proc(layout: TileMap_Layout, stagger: TileMap_Stagger, cell: [2]int) -> (out: [6][2]int, n: int) {
	x, y := cell.x, cell.y
	switch layout {
	case .Square, .Isometric:
		return {{x - 1, y}, {x + 1, y}, {x, y - 1}, {x, y + 1}, {}, {}}, 4
	case .Staggered:
		d := 0 if grid_shifted(stagger, y) else -1
		return {{x + d, y - 1}, {x + d + 1, y - 1}, {x + d, y + 1}, {x + d + 1, y + 1}, {}, {}}, 4
	case .HexPointy, .HexFlat:
		return Grid_HexSides(layout, stagger, cell), 6
	}
	return
}

// Grid_HexSides: a hex cell's six neighbours clockwise - Hex Pointy from
// the right (E, SE, SW, W, NW, NE), Hex Flat from the top (N, NE, SE, S,
// SW, NW). The Hex terrain kind's mask bits follow this order.
Grid_HexSides :: proc(layout: TileMap_Layout, stagger: TileMap_Stagger, cell: [2]int) -> [6][2]int {
	x, y := cell.x, cell.y
	if layout == .HexFlat {
		d := 0 if grid_shifted(stagger, x) else -1
		return {{x, y - 1}, {x + 1, y + d}, {x + 1, y + d + 1}, {x, y + 1}, {x - 1, y + d + 1}, {x - 1, y + d}}
	}
	d := 0 if grid_shifted(stagger, y) else -1
	return {{x + 1, y}, {x + d + 1, y + 1}, {x + d, y + 1}, {x - 1, y}, {x + d, y - 1}, {x + d + 1, y - 1}}
}

// Grid_Compass: the cells around one by the grid's directions, nb[dy][dx]
// as on a square grid (nb[0][1] north, nb[1][2] east, ...): the edge and
// blob terrains' neighbourhood. Isometric: the turned square grid itself
// (north is the diamond's upper-right side). Staggered: the same
// directions on its diamonds. Hex grids: the index grid (use the Hex kind).
Grid_Compass :: proc(layout: TileMap_Layout, stagger: TileMap_Stagger, cell: [2]int) -> (nb: [3][3][2]int) {
	x, y := cell.x, cell.y
	if layout == .Staggered {
		d := 0 if grid_shifted(stagger, y) else -1
		nb[0][1], nb[1][2], nb[2][1], nb[1][0] = {x + d + 1, y - 1}, {x + d + 1, y + 1}, {x + d, y + 1}, {x + d, y - 1}
		nb[0][2], nb[2][2], nb[2][0], nb[0][0] = {x + 1, y}, {x, y + 2}, {x - 1, y}, {x, y - 2}
		nb[1][1] = cell
		return
	}
	for dy in 0 ..< 3 do for dx in 0 ..< 3 do nb[dy][dx] = {x + dx - 1, y + dy - 1}
	return
}
