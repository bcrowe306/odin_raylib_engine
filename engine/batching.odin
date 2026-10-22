package engine

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

// ============================================================================
// Draw batching. raylib batches consecutive draws that use the same texture
// into one draw call; a texture switch flushes the batch. Scenes interleave
// sprites with different textures (5000 sprites over 4 textures: 11x slower
// than over one), so a layer's draws are reordered to group sprites by
// texture - but only when that can't change the picture:
//
// A plain sprite (TextureNode without a material) may move earlier to join
// a run of sprites with the same texture if nothing drawn in between
// overlaps it (each run's bounds are the union of its sprites' - a
// conservative test). Draws without known bounds (text, particles, custom
// render procs) are barriers nothing moves across; sprites with materials
// keep their place but can be passed when they don't overlap. Draws that
// overlap keep their relative order, so the result is identical.
// ============================================================================

@(private = "file")
BATCH_LOOKBACK :: 16 // runs searched back for a matching texture

@(private = "file")
Draw_Run :: struct {
	key:     u64,          // texture id; 0 = barrier, unique keys for unjoinable draws
	bounds:  rl.Rectangle,
	first:   int,          // items, chained through `next`
	last:    int,
}

@(private = "file")
rects_overlap :: proc(a, b: rl.Rectangle) -> bool {
	return a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height
}

@(private = "file")
rect_union :: proc(a, b: rl.Rectangle) -> rl.Rectangle {
	x0, y0 := min(a.x, b.x), min(a.y, b.y)
	x1, y1 := max(a.x + a.width, b.x + b.width), max(a.y + a.height, b.y + b.height)
	return {x0, y0, x1 - x0, y1 - y0}
}

// draw_key: the texture a draw can batch on (0 = can't be reordered at
// all), and its bounds.
@(private = "file")
draw_key :: proc(n: ^Node, unique: ^u64) -> (key: u64, bounds: rl.Rectangle) {
	r, ok := Node_RenderBounds(n)
	if !ok do return 0, {}
	if n.typeId == TextureNode && n.material == nil {
		tn := cast(^TextureNode)n
		if tn.texture != nil && tn.texture.texture.id != 0 do return u64(tn.texture.texture.id), r
	}
	// Known bounds but its own state (material, tile map, ...): unjoinable.
	unique^ += 1
	return unique^, r
}

@(private = "file")
batchingOff: bool

// Render_SetBatching turns draw reordering on or off (comparisons, debugging).
Render_SetBatching :: proc(on: bool) {batchingOff = !on}

// Render_BatchOrder returns the draws in an order that groups sprites by
// texture without changing the result (temp-allocated).
Render_BatchOrder :: proc(nodes: []^Node) -> []^Node {
	if len(nodes) < 3 || batchingOff do return nodes
	runs := make([dynamic]Draw_Run, 0, len(nodes), context.temp_allocator)
	next := make([]int, len(nodes), context.temp_allocator)
	unique: u64 = 1 << 40 // above any GL texture id
	for n, i in nodes {
		next[i] = -1
		key, r := draw_key(n, &unique)
		joined := false
		if key != 0 && key < 1 << 40 {
			for k := len(runs) - 1; k >= max(0, len(runs) - BATCH_LOOKBACK); k -= 1 {
				run := &runs[k]
				if run.key == 0 do break // barrier
				if run.key == key {
					next[run.last] = i
					run.last = i
					run.bounds = rect_union(run.bounds, r)
					joined = true
					break
				}
				if rects_overlap(run.bounds, r) do break // must stay after this run
			}
		}
		if !joined do append(&runs, Draw_Run{key, r, i, i})
	}
	if len(runs) == len(nodes) do return nodes // nothing moved
	out := make([]^Node, len(nodes), context.temp_allocator)
	o := 0
	for run in runs {
		for i := run.first; i >= 0; i = next[i] {
			out[o] = nodes[i]
			o += 1
		}
	}
	return out
}

// ----------------------------------------------------------------------------
// Multi-buffered batches. raylib flushes its batch on every texture, blend
// or shader change, re-uploading one vertex buffer; on drivers that sync on
// a buffer the GPU still reads (macOS' OpenGL) every flush waits for the
// GPU. Cycling through several buffers lets a frame flush that many times
// without waiting.
// ----------------------------------------------------------------------------

RENDER_BATCH_BUFFERS :: 8

@(private = "file")
renderBatch: struct {
	batch:  rlgl.RenderBatch,
	active: bool,
}

// Render_InitBatching: call once after the window opens.
Render_InitBatching :: proc() {
	if renderBatch.active || !rl.IsWindowReady() do return
	renderBatch.batch = rlgl.LoadRenderBatch(RENDER_BATCH_BUFFERS, rlgl.DEFAULT_BATCH_BUFFER_ELEMENTS)
	rlgl.SetRenderBatchActive(&renderBatch.batch)
	renderBatch.active = true
}

// Render_ReleaseBatching: call before the window closes.
Render_ReleaseBatching :: proc() {
	if !renderBatch.active do return
	rlgl.SetRenderBatchActive(nil)
	rlgl.UnloadRenderBatch(renderBatch.batch)
	renderBatch.active = false
}
