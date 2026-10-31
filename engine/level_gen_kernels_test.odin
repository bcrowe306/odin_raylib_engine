package engine

import "core:fmt"
import "core:testing"

// #171: the fast kernels (level_gen_eval.odin) give what the plain
// algorithms give - cellular, blur, dilate / erode, scatter, noise - on odd
// sizes and on grids big enough to be split across the worker threads.

@(private = "file")
ref_cellular :: proc(src: []f32, w, h, iterations, birth, survive: int, edge: bool) -> []f32 {
	cur := make([]f32, len(src), context.temp_allocator)
	out := make([]f32, len(src), context.temp_allocator)
	for v, i in src do cur[i] = 1 if v >= 0.5 else 0
	for _ in 0 ..< iterations {
		for y in 0 ..< h do for x in 0 ..< w {
			count := 0
			for dy in -1 ..= 1 do for dx in -1 ..= 1 {
				if dx == 0 && dy == 0 do continue
				xx, yy := x + dx, y + dy
				if xx < 0 || yy < 0 || xx >= w || yy >= h {
					if edge do count += 1
				} else if cur[yy * w + xx] >= 0.5 {
					count += 1
				}
			}
			solid := cur[y * w + x] >= 0.5
			out[y * w + x] = 1 if (solid && count >= survive) || (!solid && count >= birth) else 0
		}
		copy(cur, out)
	}
	return cur
}

@(private = "file")
ref_blur :: proc(src: []f32, w, h, r: int) -> []f32 {
	out := make([]f32, len(src), context.temp_allocator)
	for y in 0 ..< h do for x in 0 ..< w {
		sum, cnt: f32
		for yy in max(y - r, 0) ..= min(y + r, h - 1) do for xx in max(x - r, 0) ..= min(x + r, w - 1) {
			sum += src[yy * w + xx]
			cnt += 1
		}
		out[y * w + x] = sum / cnt
	}
	return out
}

@(private = "file")
ref_morph :: proc(src: []f32, w, h, iterations: int, grow: bool) -> []f32 {
	out := make([]f32, len(src), context.temp_allocator)
	cur := make([]f32, len(src), context.temp_allocator)
	copy(out, src)
	for _ in 0 ..< iterations {
		copy(cur, out)
		for y in 0 ..< h do for x in 0 ..< w {
			v := cur[y * w + x]
			for d in ([4][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) {
				xx, yy := x + d.x, y + d.y
				if xx < 0 || yy < 0 || xx >= w || yy >= h do continue
				v = max(v, cur[yy * w + xx]) if grow else min(v, cur[yy * w + xx])
			}
			out[y * w + x] = v
		}
	}
	return out
}

@(private = "file")
ref_scatter :: proc(src: []f32, w, h: int, masked: bool, chance: f32, spacing: int, seed: u64) -> []f32 {
	out := make([]f32, len(src), context.temp_allocator)
	for y in 0 ..< h do for x in 0 ..< w {
		if masked && src[y * w + x] < 0.5 do continue
		if gen_hash01(x, y, seed) >= chance do continue
		near := false
		for yy in max(y - spacing + 1, 0) ..= y do for xx in max(x - spacing + 1, 0) ..< min(x + spacing, w) {
			if (yy < y || xx < x) && out[yy * w + xx] >= 0.5 do near = true
		}
		if !near do out[y * w + x] = 1
	}
	return out
}

@(private = "file")
ref_noise :: proc(w, h: int, scale: f32, octaves: int, persistence: f32, seed: u64) -> []f32 {
	out := make([]f32, w * h, context.temp_allocator)
	for y in 0 ..< h do for x in 0 ..< w {
		amp, freq, sum, norm: f32 = 1, 1 / scale, 0, 0
		for o in 0 ..< octaves {
			sum += gen_value_noise(f32(x) * freq, f32(y) * freq, seed + u64(o) * 7919) * amp
			norm += amp
			amp *= persistence
			freq *= 2
		}
		out[y * w + x] = sum / max(norm, 0.0001)
	}
	return out
}

@(private = "file")
expect_grids :: proc(t: ^testing.T, what: string, got, want: []f32, tolerance: f32 = 0) {
	testing.expect_value(t, len(got), len(want))
	bad := 0
	for i in 0 ..< min(len(got), len(want)) do if abs(got[i] - want[i]) > tolerance {
		if bad == 0 do testing.expectf(t, false, "%s: cell %d is %v, want %v", what, i, got[i], want[i])
		bad += 1
	}
	if bad > 1 do testing.expectf(t, false, "%s: %d cells differ", what, bad)
}

@(test)
test_level_gen_kernels_match_reference :: proc(t: ^testing.T) {
	// 37x23: odd, smaller than a blur band; 300x211: split across workers.
	for size in ([][2]int{{37, 23}, {300, 211}, {1, 1}, {2, 70}}) {
		w, h := size.x, size.y
		text := fmt.tprintf(`{{"size": [%d, %d], "seed": 11, "nodes": [
			{{"id": 1, "type": "random_fill", "params": {{"density": 0.47}}}},
			{{"id": 2, "type": "noise", "params": {{"scale": 7.5, "octaves": 5, "persistence": 0.6}}}},
			{{"id": 3, "type": "cellular", "inputs": {{"in": 1}}, "params": {{"iterations": 4, "birth": 5, "survive": 4, "edge_solid": 1}}}},
			{{"id": 4, "type": "cellular", "inputs": {{"in": 1}}, "params": {{"iterations": 3, "birth": 4, "survive": 3, "edge_solid": 0}}}},
			{{"id": 5, "type": "blur", "inputs": {{"in": 2}}, "params": {{"radius": 1}}}},
			{{"id": 6, "type": "blur", "inputs": {{"in": 1}}, "params": {{"radius": 9}}}},
			{{"id": 7, "type": "dilate", "inputs": {{"in": 2}}, "params": {{"iterations": 3}}}},
			{{"id": 8, "type": "erode", "inputs": {{"in": 2}}, "params": {{"iterations": 2}}}},
			{{"id": 9, "type": "scatter", "inputs": {{"in": 3}}, "params": {{"chance": 0.3, "spacing": 4}}}},
			{{"id": 10, "type": "scatter", "params": {{"chance": 0.2, "spacing": 1}}}},
			{{"id": 11, "type": "noise", "params": {{"scale": 0.5, "octaves": 8, "persistence": 0.5}}}},
			{{"id": 12, "type": "rect", "params": {{"x": -3, "y": 2, "w": 500, "h": 4}}}},
			{{"id": 13, "type": "rect", "params": {{"x": 900, "y": 0, "w": 5, "h": 5}}}}]}}`, w, h)
		g, err := Gen_GraphParse(transmute([]u8)text)
		testing.expectf(t, err == "", "parse: %s", err)
		defer Gen_GraphDestroy(&g)
		grid :: proc(t: ^testing.T, g: ^Gen_Graph, id: int) -> []f32 {
			r, e := Gen_Evaluate(g, id, 0, context.temp_allocator)
			testing.expectf(t, e == "", "evaluate %d: %s", id, e)
			return r.v
		}
		fill, noise := grid(t, &g, 1), grid(t, &g, 2)
		seedOf :: proc(g: ^Gen_Graph, id: int) -> u64 {return gen_mix(gen_mix(g.seed, u64(id)), 0)}
		label :: proc(what: string, w, h: int) -> string {return fmt.tprintf("%s %dx%d", what, w, h)}
		expect_grids(t, label("noise", w, h), noise, ref_noise(w, h, 7.5, 5, 0.6, seedOf(&g, 2)), 1e-6)
		expect_grids(t, label("cellular closed", w, h), grid(t, &g, 3), ref_cellular(fill, w, h, 4, 5, 4, true))
		expect_grids(t, label("cellular open", w, h), grid(t, &g, 4), ref_cellular(fill, w, h, 3, 4, 3, false))
		expect_grids(t, label("blur 1", w, h), grid(t, &g, 5), ref_blur(noise, w, h, 1), 1e-5)
		expect_grids(t, label("blur 9", w, h), grid(t, &g, 6), ref_blur(fill, w, h, 9), 1e-5)
		expect_grids(t, label("dilate", w, h), grid(t, &g, 7), ref_morph(noise, w, h, 3, true))
		expect_grids(t, label("erode", w, h), grid(t, &g, 8), ref_morph(noise, w, h, 2, false))
		expect_grids(t, label("scatter masked", w, h), grid(t, &g, 9), ref_scatter(grid(t, &g, 3), w, h, true, 0.3, 4, seedOf(&g, 9)))
		expect_grids(t, label("scatter", w, h), grid(t, &g, 10), ref_scatter(make([]f32, w * h, context.temp_allocator), w, h, false, 0.2, 1, seedOf(&g, 10)))
		expect_grids(t, label("tiny noise", w, h), grid(t, &g, 11), ref_noise(w, h, 0.5, 8, 0.5, seedOf(&g, 11)), 1e-6)
		rect := make([]f32, w * h, context.temp_allocator)
		for y in 2 ..< min(6, h) do for x in 0 ..< w do rect[y * w + x] = 1
		expect_grids(t, label("rect clipped", w, h), grid(t, &g, 12), rect)
		expect_grids(t, label("rect outside", w, h), grid(t, &g, 13), make([]f32, w * h, context.temp_allocator))
		free_all(context.temp_allocator)
	}
}

// A cache reuses what didn't change and recomputes what did (and what
// reads it), the same grids as without one.
@(test)
test_level_gen_cache :: proc(t: ^testing.T) {
	g, err := Gen_GraphParse(transmute([]u8)string(`{"size": [24, 16], "seed": 3, "nodes": [
		{"id": 1, "type": "random_fill", "params": {"density": 0.5}},
		{"id": 2, "type": "cellular", "inputs": {"in": 1}},
		{"id": 3, "type": "noise"},
		{"id": 4, "type": "combine", "inputs": {"a": 2, "b": 3}, "params": {"op": "max"}}]}`))
	testing.expectf(t, err == "", "parse: %s", err)
	defer Gen_GraphDestroy(&g)
	cache: Gen_Cache
	Gen_CacheInit(&cache)
	defer Gen_CacheDestroy(&cache)
	same :: proc(t: ^testing.T, g: ^Gen_Graph, cache: ^Gen_Cache, what: string) {
		for n in g.nodes {
			a, _ := Gen_Evaluate(g, n.id, 0, context.temp_allocator, cache)
			b, _ := Gen_Evaluate(g, n.id, 0, context.temp_allocator)
			expect_grids(t, fmt.tprintf("%s: node %d", what, n.id), a.v, b.v)
		}
	}
	same(t, &g, &cache, "cold")
	g1, _ := Gen_CacheGrid(&cache, 1)
	before := raw_data(g1.v)
	// Node 3 changes: 1 and 2 are reused, 3 and 4 recomputed.
	Gen_SetParam(Gen_FindNode(&g, 3), "scale", 4)
	same(t, &g, &cache, "noise changed")
	g1, _ = Gen_CacheGrid(&cache, 1)
	testing.expect(t, raw_data(g1.v) == before, "node 1 reused")
	// A new seed: all recomputed.
	g.seed = 99
	same(t, &g, &cache, "new seed")
	// A removed node is forgotten.
	Gen_RemoveNode(&g, 4)
	Gen_CachePrune(&cache, &g)
	_, kept := Gen_CacheGrid(&cache, 4)
	testing.expect(t, !kept, "removed node pruned")
	free_all(context.temp_allocator)
}
