package engine

import "core:fmt"
import "core:math"
import "core:strings"
import rl "vendor:raylib"

// ============================================================================
// TileMapNode: a grid of tiles from one tileset image, painted in the
// editor (Inspector "Tile Map" section + viewport brush). Tile indices
// count left-to-right, top-to-bottom in the tileset; -1 is empty.
//
// With `solid` on, ready() builds static colliders for every painted tile
// (horizontal runs merged into single boxes), in a transient child body.
//
// Saved as reflected properties (solid, tint) plus "tilemap": {"tileset",
// "tile_size", "map_size", "data": [[count, tile], ...]} (run-length
// encoded, row-major).
// ============================================================================

TileMapNode :: struct {
	using node: Node,
	tilesetPath: string,
	tileset:     ^Texture,
	tileSize:    [2]int, // pixels per tile (in the tileset and in the world)
	mapSize:     [2]int, // cells
	solid:       bool `gui:"true"`,                      // build colliders for painted tiles
	tint:        rl.Color `gui:"true"`,
	tiles:       [dynamic]i32,
	staticBody:  ^StaticBodyNode,
	builtSize:   [2]int, // mapSize the tiles array was laid out for
}

TileMapNode_Create :: proc(scene: ^Scene, name: string = "TileMap", parent: ^Node = nil) -> ^TileMapNode {
	tm := CreateNode(scene.manager, TileMapNode)
	tm.name = name
	tm.tileSize = {32, 32}
	tm.mapSize = {20, 12}
	tm.tint = rl.WHITE
	tm.tiles = make([dynamic]i32, tm.allocator)
	TileMapNode_Layout(tm)
	tm.ready = TileMapNode_Ready
	tm.render = TileMapNode_Render
	tm.onDestroy = TileMapNode_Destroy
	scene->addNode(tm, parent)
	return tm
}

// TileMapNode_Layout resizes the tile array to mapSize, keeping the
// overlapping cells (call after changing mapSize).
TileMapNode_Layout :: proc(tm: ^TileMapNode) {
	w, h := max(tm.mapSize.x, 1), max(tm.mapSize.y, 1)
	tm.mapSize = {w, h}
	if tm.builtSize == tm.mapSize && len(tm.tiles) == w * h do return
	old := make([]i32, len(tm.tiles), context.temp_allocator)
	copy(old, tm.tiles[:])
	ow, oh := tm.builtSize.x, tm.builtSize.y
	resize(&tm.tiles, w * h)
	for i in 0 ..< w * h do tm.tiles[i] = -1
	for y in 0 ..< min(h, oh) {
		for x in 0 ..< min(w, ow) {
			if y * ow + x < len(old) do tm.tiles[y * w + x] = old[y * ow + x]
		}
	}
	tm.builtSize = tm.mapSize
}

TileMapNode_Get :: proc(tm: ^TileMapNode, x, y: int) -> i32 {
	TileMapNode_Layout(tm)
	if x < 0 || y < 0 || x >= tm.mapSize.x || y >= tm.mapSize.y do return -1
	return tm.tiles[y * tm.mapSize.x + x]
}

// TileMapNode_Set paints one cell (-1 erases). Returns true if it changed.
TileMapNode_Set :: proc(tm: ^TileMapNode, x, y: int, tile: i32) -> bool {
	TileMapNode_Layout(tm)
	if x < 0 || y < 0 || x >= tm.mapSize.x || y >= tm.mapSize.y do return false
	i := y * tm.mapSize.x + x
	if tm.tiles[i] == tile do return false
	tm.tiles[i] = tile
	return true
}

// TileMapNode_Fill flood-fills the region of equal tiles around (x, y).
TileMapNode_Fill :: proc(tm: ^TileMapNode, x, y: int, tile: i32) -> int {
	TileMapNode_Layout(tm)
	target := TileMapNode_Get(tm, x, y)
	if x < 0 || y < 0 || x >= tm.mapSize.x || y >= tm.mapSize.y || target == tile do return 0
	stack := make([dynamic][2]int, context.temp_allocator)
	append(&stack, [2]int{x, y})
	n := 0
	for len(stack) > 0 {
		p := pop(&stack)
		if TileMapNode_Get(tm, p.x, p.y) != target do continue
		TileMapNode_Set(tm, p.x, p.y, tile)
		n += 1
		if p.x > 0 do append(&stack, [2]int{p.x - 1, p.y})
		if p.y > 0 do append(&stack, [2]int{p.x, p.y - 1})
		if p.x < tm.mapSize.x - 1 do append(&stack, [2]int{p.x + 1, p.y})
		if p.y < tm.mapSize.y - 1 do append(&stack, [2]int{p.x, p.y + 1})
	}
	return n
}

// TileMapNode_Columns: tiles per row in the tileset image.
TileMapNode_Columns :: proc(tm: ^TileMapNode) -> int {
	if tm.tileset == nil || tm.tileSize.x <= 0 do return 0
	return max(int(tm.tileset.texture.width) / tm.tileSize.x, 1)
}

TileMapNode_TileCount :: proc(tm: ^TileMapNode) -> int {
	if tm.tileset == nil || tm.tileSize.y <= 0 do return 0
	return TileMapNode_Columns(tm) * max(int(tm.tileset.texture.height) / tm.tileSize.y, 1)
}

// TileMapNode_SetTileset loads the tileset image (project-relative path).
TileMapNode_SetTileset :: proc(tm: ^TileMapNode, path: string, ctx: ^GameContext) {
	rm := Node_ResourceManager(tm)
	if tm.tileset != nil && rm != nil do ResourceManager_ReleaseTexture(rm, tm.tileset)
	tm.tileset = nil
	tm.tilesetPath = strings.clone(path, tm.allocator)
	if path == "" || rm == nil || !rl.IsWindowReady() do return
	if tex, ok := rm.loadTexture(rm, Project_ResolveAssetPath(ctx, path)); ok do tm.tileset = tex
}

// TileMapNode_CellAt: the cell under a world position (may be outside the map).
TileMapNode_CellAt :: proc(tm: ^TileMapNode, world: [2]f32) -> [2]int {
	local := world - tm.globalPosition
	rad := -tm.globalRotation * math.RAD_PER_DEG
	c, s := math.cos(rad), math.sin(rad)
	local = {local.x * c - local.y * s, local.x * s + local.y * c}
	sx := tm.globalScale.x if tm.globalScale.x != 0 else 1
	sy := tm.globalScale.y if tm.globalScale.y != 0 else 1
	return {int(math.floor(local.x / sx / f32(tm.tileSize.x))), int(math.floor(local.y / sy / f32(tm.tileSize.y)))}
}

// TileMapNode_CellCorner: world position of a cell's top-left corner.
TileMapNode_CellCorner :: proc(tm: ^TileMapNode, cell: [2]int) -> [2]f32 {
	sx := tm.globalScale.x if tm.globalScale.x != 0 else 1
	sy := tm.globalScale.y if tm.globalScale.y != 0 else 1
	local := [2]f32{f32(cell.x * tm.tileSize.x) * sx, f32(cell.y * tm.tileSize.y) * sy}
	rad := tm.globalRotation * math.RAD_PER_DEG
	c, s := math.cos(rad), math.sin(rad)
	return tm.globalPosition + {local.x * c - local.y * s, local.x * s + local.y * c}
}

TileMapNode_Render :: proc(node: ^Node, ctx: ^GameContext, dt: f32) {
	tm := cast(^TileMapNode)node
	if !tm.renderable || tm.tileset == nil do return
	TileMapNode_Layout(tm)
	cols := TileMapNode_Columns(tm)
	if cols <= 0 do return
	tw, th := f32(tm.tileSize.x), f32(tm.tileSize.y)
	sx := tm.globalScale.x if tm.globalScale.x != 0 else 1
	sy := tm.globalScale.y if tm.globalScale.y != 0 else 1
	// Only the cells in view (unrotated maps; rotated ones draw all).
	x0, y0, x1, y1 := 0, 0, tm.mapSize.x, tm.mapSize.y
	if renderView.active && tm.globalRotation == 0 && sx > 0 && sy > 0 {
		o := TileMapNode_CellCorner(tm, {0, 0})
		v := renderView.rect
		x0 = clamp(int(math.floor((v.x - o.x) / (tw * sx))), 0, tm.mapSize.x)
		y0 = clamp(int(math.floor((v.y - o.y) / (th * sy))), 0, tm.mapSize.y)
		x1 = clamp(int(math.ceil((v.x + v.width - o.x) / (tw * sx))), 0, tm.mapSize.x)
		y1 = clamp(int(math.ceil((v.y + v.height - o.y) / (th * sy))), 0, tm.mapSize.y)
	}
	for y in y0 ..< y1 {
		for x in x0 ..< x1 {
			t := tm.tiles[y * tm.mapSize.x + x]
			if t < 0 do continue
			src := rl.Rectangle{f32(int(t) % cols) * tw, f32(int(t) / cols) * th, tw, th}
			p := TileMapNode_CellCorner(tm, {x, y})
			dst := rl.Rectangle{p.x, p.y, tw * sx, th * sy}
			rl.DrawTexturePro(tm.tileset.texture, src, dst, {0, 0}, tm.globalRotation, tm.tint)
		}
	}
}

// TileMapNode_BuildColliders (re)creates the static colliders for painted
// tiles, merging horizontal runs.
TileMapNode_BuildColliders :: proc(tm: ^TileMapNode, ctx: ^GameContext) {
	scene := ctx.scene if ctx != nil else nil
	if scene == nil && tm.gameContext != nil do scene = tm.gameContext.scene
	if scene == nil do return
	if tm.staticBody != nil && Node_IsAlive(tm.staticBody) {
		RemoveNode(scene.manager, tm.staticBody)
		ProcessNodeQueues(scene.manager, ctx)
	}
	tm.staticBody = StaticBodyNode_Create(scene, fmt.tprintf("%s_Colliders", tm.name), tm)
	tm.staticBody.position = {0, 0}
	tm.staticBody.transient = true
	tm.staticBody.gameContext = ctx
	TileMapNode_Layout(tm)
	tw, th := f32(tm.tileSize.x), f32(tm.tileSize.y)
	for y in 0 ..< tm.mapSize.y {
		x := 0
		for x < tm.mapSize.x {
			if tm.tiles[y * tm.mapSize.x + x] < 0 {
				x += 1
				continue
			}
			start := x
			for x < tm.mapSize.x && tm.tiles[y * tm.mapSize.x + x] >= 0 do x += 1
			w := f32(x - start) * tw
			shape := MakeBoxPhysicsShape(w, th, {f32(start) * tw + w * 0.5, f32(y) * th + th * 0.5}, 0)
			StaticBodyNode_AddShape(tm.staticBody, shape, ctx)
		}
	}
}

TileMapNode_Ready :: proc(node: ^Node, ctx: ^GameContext) {
	tm := cast(^TileMapNode)node
	if tm.solid do TileMapNode_BuildColliders(tm, ctx)
}

TileMapNode_Destroy :: proc(node: ^Node, ctx: ^GameContext) {
	tm := cast(^TileMapNode)node
	if tm.tileset != nil {
		if rm := Node_ResourceManager(tm); rm != nil do ResourceManager_ReleaseTexture(rm, tm.tileset)
		tm.tileset = nil
	}
}

// TileMapNode_EncodeRLE writes the tiles as [[count, tile], ...].
TileMapNode_EncodeRLE :: proc(tm: ^TileMapNode, sb: ^strings.Builder) {
	TileMapNode_Layout(tm)
	strings.write_byte(sb, '[')
	i := 0
	first := true
	for i < len(tm.tiles) {
		t := tm.tiles[i]
		j := i
		for j < len(tm.tiles) && tm.tiles[j] == t do j += 1
		if !first do strings.write_string(sb, ", ")
		first = false
		fmt.sbprintf(sb, "[%d, %d]", j - i, t)
		i = j
	}
	strings.write_byte(sb, ']')
}
