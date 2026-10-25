package engine

import "core:math"
import rl "vendor:raylib"

// ============================================================================
// View culling
//
// While a world layer is drawn, renderView holds the world rectangle the
// camera sees (with a small margin). Scene rendering skips nodes whose
// Node_RenderBounds don't touch it; nodes without known bounds (UI,
// particles, physics debug, scripts drawing freely) are always drawn.
// Tile maps and LDtk levels also skip their off-screen tiles.
// ============================================================================

Render_View :: struct {
	rect:   rl.Rectangle,
	active: bool,
}

renderView: Render_View

// Statistics of the last frame (profiler / tests).
Render_Stats :: struct {
	drawn, culled: int,
}

renderStats: Render_Stats

CULL_MARGIN :: 16 // world units around the view

Render_SetView :: proc(rect: rl.Rectangle) {
	renderView = {{rect.x - CULL_MARGIN, rect.y - CULL_MARGIN, rect.width + CULL_MARGIN * 2, rect.height + CULL_MARGIN * 2}, true}
}

Render_ClearView :: proc() {
	renderView.active = false
}

// Render_IsVisible: does a world rectangle touch the current view?
Render_IsVisible :: proc(r: rl.Rectangle) -> bool {
	if !renderView.active do return true
	v := renderView.rect
	return r.x <= v.x + v.width && r.x + r.width >= v.x && r.y <= v.y + v.height && r.y + r.height >= v.y
}

// Camera2D_ViewRect: the world rectangle a raylib camera shows on a
// viewport of the given size (enlarged to cover a rotated view).
Camera2D_ViewRect :: proc(cam: rl.Camera2D, viewW, viewH: f32) -> rl.Rectangle {
	z := cam.zoom if cam.zoom > 0.0001 else 1
	// Viewport corners relative to the camera target, in world units.
	corners := [4][2]f32{{-cam.offset.x, -cam.offset.y}, {viewW - cam.offset.x, -cam.offset.y}, {viewW - cam.offset.x, viewH - cam.offset.y}, {-cam.offset.x, viewH - cam.offset.y}}
	r := -cam.rotation * math.RAD_PER_DEG
	c, s := math.cos(r), math.sin(r)
	mn := [2]f32{max(f32), max(f32)}
	mx := [2]f32{min(f32), min(f32)}
	for p in corners {
		q := p / z
		w := [2]f32{q.x * c - q.y * s, q.x * s + q.y * c} + cam.target
		mn = {min(mn.x, w.x), min(mn.y, w.y)}
		mx = {max(mx.x, w.x), max(mx.y, w.y)}
	}
	return {mn.x, mn.y, mx.x - mn.x, mx.y - mn.y}
}

@(private = "file")
aabb_of :: proc(pts: [4][2]f32) -> rl.Rectangle {
	mn, mx := pts[0], pts[0]
	for p in pts {
		mn = {min(mn.x, p.x), min(mn.y, p.y)}
		mx = {max(mx.x, p.x), max(mx.y, p.y)}
	}
	return {mn.x, mn.y, mx.x - mn.x, mx.y - mn.y}
}

// rect_aabb: world AABB of a rect of size `size` drawn at `pos` with
// `origin` (pivot, in drawn units) and rotation in degrees.
@(private = "file")
rect_aabb :: proc(pos, size, origin: [2]f32, rotDeg: f32) -> rl.Rectangle {
	r := rotDeg * math.RAD_PER_DEG
	c, s := math.cos(r), math.sin(r)
	local := [4][2]f32{-origin, [2]f32{size.x, 0} - origin, size - origin, [2]f32{0, size.y} - origin}
	pts: [4][2]f32
	for p, i in local do pts[i] = pos + {p.x * c - p.y * s, p.x * s + p.y * c}
	return aabb_of(pts)
}

// Node_RenderBounds: world AABB of what a node draws (ok = false: unknown,
// so never culled).
Node_RenderBounds :: proc(node: ^Node) -> (rect: rl.Rectangle, ok: bool) {
	if node.isUI do return {}, false
	switch node.typeId {
	case SkeletonNode:
		return SkeletonNode_WorldBounds(cast(^SkeletonNode)node)
	case TextureNode:
		tn := cast(^TextureNode)node
		if tn.texture == nil do return {}, false
		size := tn.size * tn.globalScale
		origin := Node_OriginPx(tn, tn.size) * tn.globalScale
		return rect_aabb(tn.globalPosition, {abs(size.x), abs(size.y)}, {abs(origin.x), abs(origin.y)}, tn.globalRotation), true
	case AsepriteNode:
		an := cast(^AsepriteNode)node
		if an.res == nil do return {}, false
		sz := AsepriteNode_Size(an)
		size := sz * an.globalScale
		origin := Node_OriginPx(an, sz) * an.globalScale
		return rect_aabb(an.globalPosition, {abs(size.x), abs(size.y)}, {abs(origin.x), abs(origin.y)}, an.globalRotation), true
	case TextNode:
		if !rl.IsWindowReady() do return {}, false
		return TextNode_Bounds(cast(^TextNode)node, nil), true
	case TileMapNode:
		tm := cast(^TileMapNode)node
		a := TileMapNode_CellCorner(tm, {0, 0})
		b := TileMapNode_CellCorner(tm, {tm.mapSize.x, 0})
		c := TileMapNode_CellCorner(tm, tm.mapSize)
		d := TileMapNode_CellCorner(tm, {0, tm.mapSize.y})
		return aabb_of({a, b, c, d}), true
	}
	return {}, false
}
