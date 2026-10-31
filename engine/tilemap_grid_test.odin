package engine

import "core:testing"

// #278: isometric, staggered and hex grids - a cell's centre picks the cell
// back (negative cells too), bands hold every cell once, back to front,
// colliders per layout, a Y-sorted map's bands sort with a sprite.
@(test)
test_tilemap_grids :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("grids", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	ctx := &game.gameContext

	tm := TileMapNode_Create(scene, "Map")
	tm.tileSize = {64, 64}
	tm.cellSize = {64, 32}
	tm.mapSize = {6, 5}
	TileMapNode_Layout(tm)
	ProcessNodeQueues(scene.manager, ctx)

	for layout in TileMap_Layout do for stagger in TileMap_Stagger {
		tm.layout, tm.stagger = layout, stagger
		// Picking: every cell's centre (and a point near its edge) is that cell.
		for y in -3 ..< 6 do for x in -3 ..< 7 {
			c := TileMapNode_CellLocalCenter(tm, {x, y})
			testing.expectf(t, TileMapNode_LocalCellAt(tm, c) == {x, y}, "%v %v: centre of %v picks %v", layout, stagger, [2]int{x, y}, TileMapNode_LocalCellAt(tm, c))
			pts, n := TileMapNode_CellOutline(tm, {x, y})
			near := c + (pts[0] - c) * 0.9 // (just inside the top corner)
			_ = n
			testing.expectf(t, TileMapNode_LocalCellAt(tm, near) == {x, y}, "%v %v: near the top of %v picks %v", layout, stagger, [2]int{x, y}, TileMapNode_LocalCellAt(tm, near))
			w := TileMapNode_LocalToWorld(tm, c)
			testing.expect(t, TileMapNode_CellAt(tm, w) == {x, y}, "world picking")
		}
		// Bands: each cell once; bands back (higher on screen) to front.
		lo, hi := [2]int{-2, -1}, [2]int{5, 4}
		seen := make(map[[2]int]int, context.temp_allocator)
		b0, b1 := TileMapNode_BandRange(tm, lo, hi)
		Seen :: struct {m: ^map[[2]int]int, band: int, t: ^testing.T, tm: ^TileMapNode}
		lastBottom := f32(-1e9)
		for b in b0 ..< b1 {
			bottom := TileMapNode_BandBottom(tm, b)
			testing.expect(t, bottom > lastBottom, "bands go down the screen")
			lastBottom = bottom
			s := Seen{&seen, b, t, tm}
			TileMapNode_BandCells(tm, b, lo, hi, &s, proc(tm: ^TileMapNode, cell: [2]int, data: rawptr) {
				s := cast(^Seen)data
				s.m[cell] += 1
				box := TileMapNode_CellBox(tm, cell)
				testing.expectf(s.t, box.y + box.height == TileMapNode_BandBottom(tm, s.band), "%v: cell %v sits on its band", tm.layout, cell)
				testing.expect(s.t, TileMapNode_BandOf(tm, cell) == s.band, "BandOf")
			})
		}
		testing.expectf(t, len(seen) == (hi.x - lo.x) * (hi.y - lo.y), "%v: every cell in a band (%d)", layout, len(seen))
		for _, k in seen do testing.expect(t, k == 1, "once")
	}

	// Neighbours share a side: their outlines have two corners in common.
	for layout in TileMap_Layout do for stagger in TileMap_Stagger {
		tm.layout, tm.stagger = layout, stagger
		for y in -1 ..< 3 do for x in -1 ..< 3 {
			a, an := TileMapNode_CellOutline(tm, {x, y})
			nb, k := TileMapNode_Neighbors(tm, {x, y})
			for q in nb[:k] {
				b, bn := TileMapNode_CellOutline(tm, q)
				shared := 0
				for p in a[:an] do for r in b[:bn] do if abs(p.x - r.x) < 0.01 && abs(p.y - r.y) < 0.01 do shared += 1
				testing.expectf(t, shared == 2, "%v %v: %v and %v share %d corners", layout, stagger, [2]int{x, y}, q, shared)
			}
		}
	}

	// Tall tiles stand on their cell.
	tm.layout = .Isometric
	r := TileMapNode_TileRect(tm, {0, 0})
	testing.expect(t, r == {0, -32, 64, 64}, "a 64 x 64 tile on a 64 x 32 diamond")

	// Colliders: isometric rows merge into one parallelogram; hex: one each.
	for x in 0 ..< 4 do TileMapNode_Set(tm, x, 2, 0)
	TileMapNode_Set(tm, 1, 4, 0)
	shapes :: proc(tm: ^TileMapNode, ctx: ^GameContext) -> int {
		TileMapNode_BuildColliders(tm, ctx)
		return len(tm.staticBody.shapes)
	}
	testing.expect_value(t, shapes(tm, ctx), 2)
	testing.expect_value(t, tm.staticBody.shapes[0].type, PhysicsShapeType.Polygon)
	tm.layout = .HexPointy
	testing.expect_value(t, shapes(tm, ctx), 5)
	tm.layout = .Square
	testing.expect_value(t, shapes(tm, ctx), 2)

	// Y Sort: under a Y-sorted parent the map's bands and a sprite interleave.
	world := CreateNode(scene.manager, Node)
	world.name = "World"
	world.ySort = true
	scene->addNode(world)
	walls := TileMapNode_Create(scene, "Walls", world)
	walls.tileSize, walls.mapSize = {32, 32}, {4, 4}
	walls.ySort = true
	TileMapNode_Layout(walls)
	for y in 0 ..< 4 do TileMapNode_Set(walls, 0, y, 0)
	hero := CreateNode(scene.manager, TextureNode)
	hero.name = "Hero"
	hero.render = proc(n: ^Node, c: ^GameContext, dt: f32) {}
	hero.layer = walls.layer
	hero.position = {16, 70} // (feet between band 1's line, 64, and band 2's, 96)
	scene->addNode(hero, world)
	ProcessNodeQueues(scene.manager, ctx)
	Node_SetGlobalPositions(scene.manager, scene.rootNode)
	buckets := Scene_CollectRenderables(scene)
	order := make([dynamic]string, context.temp_allocator)
	for n in buckets[walls.layer] do if n == walls || n == hero do append(&order, n.name)
	testing.expect_value(t, len(order), 5)
	if len(order) == 5 do testing.expect(t, order[0] == "Walls" && order[1] == "Walls" && order[2] == "Hero" && order[3] == "Walls", "hero between bands 1 and 2")
	testing.expect(t, walls.bandMode && walls.bandHi - walls.bandLo == 4, "four bands")
	free_all(context.temp_allocator)
}

// #278: paths on hex / staggered / isometric maps go round walls through
// cells sharing a side; a navigation region bakes an isometric wall.
@(test)
test_tilemap_grid_navigation :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("gridnav", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	ctx := &game.gameContext

	tm := TileMapNode_Create(scene, "Walls")
	tm.tileSize, tm.cellSize, tm.mapSize = {32, 32}, {32, 32}, {9, 9}
	tm.solid = true
	TileMapNode_Layout(tm)
	ProcessNodeQueues(scene.manager, ctx)
	// A wall down column 4, open at the bottom two rows (a staggered grid's
	// rows are half rows: one isn't a way through).
	for y in 0 ..< 7 do TileMapNode_Set(tm, 4, y, 0)

	for layout in ([]TileMap_Layout{.Isometric, .Staggered, .HexPointy, .HexFlat}) {
		tm.layout = layout
		TileMapNode_Changed(tm)
		g := Nav_GridFor(tm)
		testing.expect(t, g != nil && g.tilemap == tm, "the map's own grid")
		from, to := TileMapNode_CellCenter(tm, {1, 1}), TileMapNode_CellCenter(tm, {7, 1})
		testing.expect_value(t, Nav_CellAt(g, from), [2]int{1, 1})
		opts := Nav_DefaultOptions()
		opts.smooth = false
		cells := Nav_FindCells(g, {1, 1}, {7, 1}, true)
		testing.expectf(t, len(cells) > 0, "%v: a path", layout)
		through := false
		for c, i in cells {
			testing.expectf(t, TileMapNode_Get(tm, c.x, c.y) < 0, "%v: %v is open", layout, c)
			if c.y >= 7 do through = true
			if i == 0 || layout == .Isometric do continue
			nb, k := TileMapNode_Neighbors(tm, cells[i - 1])
			ok := false
			for q in nb[:k] do if q == c do ok = true
			testing.expectf(t, ok, "%v: %v -> %v shares a side", layout, cells[i - 1], c)
		}
		testing.expectf(t, through, "%v: round the bottom of the wall", layout)
		path := Nav_FindPath(g, from, to, opts)
		testing.expectf(t, len(path) > 2 && path[0] == from && path[len(path) - 1] == to, "%v: world path", layout)
		testing.expect(t, !Nav_LineClear(g, {1, 1}, {7, 1}), "no line through the wall")
		testing.expect(t, Nav_LineClear(g, {1, 1}, {2, 2}) || layout != .Isometric, "a clear short line")
		// An agent radius keeps the path off the wall.
		Nav_Clearance(g)
		testing.expect(t, g.clear[1 * g.w + 4] == 0 && g.clear[1 * g.w + 3] >= 1, "clearance")
	}

	// A region baked from the isometric wall blocks the diamonds' area.
	tm.layout = .Isometric
	tm.position = {300, 0}
	Node_SetGlobalPositions(scene.manager, scene.rootNode)
	region := NavigationRegionNode_Create(scene, "Nav")
	region.size, region.cellSize = {600, 400}, 8
	region.usePhysics, region.useTileMaps, region.useLdtk = false, true, false
	region.gameContext = ctx
	ProcessNodeQueues(scene.manager, ctx)
	NavRegion_Bake(region, ctx)
	wall := TileMapNode_CellCenter(tm, {4, 3})
	open := TileMapNode_CellCenter(tm, {2, 3})
	at :: proc(r: ^NavigationRegionNode, p: [2]f32) -> u8 {
		c := [2]int{int((p.x - r.bakedAt.x) / r.cellSize), int((p.y - r.bakedAt.y) / r.cellSize)}
		return r.blocked[c.y * r.cells.x + c.x]
	}
	testing.expect(t, at(region, wall) != 0, "the wall's diamond is blocked")
	testing.expect(t, at(region, open) == 0, "a floor diamond is open")
	free_all(context.temp_allocator)
}
