package engine

import "core:mem"
import vmem "core:mem/virtual"
import "core:slice"

// ============================================================================
// LDtk auto-layer rule engine (port of LayerInstance.applyRuleAt and
// AutoLayerRuleDef.matches from the LDtk sources)
//
// A rule is a size x size pattern over the source IntGrid layer: 0 ignores a
// cell, v requires value v, -v forbids it, +/-1000001 means any / no value,
// and values above 999 test IntGrid groups ((v / 1000) - 1 = group uid).
// Matching rules place one of their tile rectangles (chosen with LDtk's
// coordinate hash), optionally flipped, offset, at random, with modulo /
// checker / chance / Perlin filters. Rules run in group / rule order; a
// rule with "break on match" (or an opaque tile) hides later rules' tiles.
// The hash and noise reproduce LDtk's JavaScript double arithmetic, so the
// generated tiles are the same as LDtk's.
// ============================================================================

// js_toint32: JavaScript ToInt32 of an integral double.
@(private = "file")
js_toint32 :: #force_inline proc(v: f64) -> i32 {
	return i32(u32(u64(i64(v))))
}

// Ldtk_RandSeedCoords is dn.M.randSeedCoords evaluated like LDtk's JS.
Ldtk_RandSeedCoords :: proc(seed, x, y, max: int) -> int {
	h := f64(seed) + f64(x) * 374761393 + f64(y) * 668265263
	t := js_toint32(h)
	t = t ~ (t >> 13)
	h2 := f64(t) * 1274126177
	u := js_toint32(h2)
	u = u ~ (u >> 16)
	if max == 0 do return 0
	return int(u % i32(max))
}

// ldtk_perlin: hxd.Perlin.perlin with normalize on and adjustScale(50, 1)
// (as AutoLayerRuleDef sets it up).
@(private = "file")
ldtk_perlin :: proc(seed: int, x, y: f64, octaves: int) -> f64 {
	REPEAT :: 50
	scurve :: #force_inline proc(a: f64) -> f64 {
		a2 := a * a
		return a2 * a * (6.0 * a2 - 15.0 * a + 10.0)
	}
	linear :: #force_inline proc(a, b, k: f64) -> f64 {return a + k * (b - a)}
	grad :: #force_inline proc(x, y: f64, ix, iy: int, seed: int) -> f64 {
		index := f64(seed) * 1013 + f64(ix % REPEAT) * 1619 + f64(iy % REPEAT) * 31337
		u := u32(u64(i64(index)))
		gi := int((u ~ (u >> 8)) & 0xFF)
		gx := LDTK_PERLIN_GRADIENTS[gi * 3] * 2.12
		gy := LDTK_PERLIN_GRADIENTS[gi * 3 + 1] * 2.12
		return gx * (x - f64(ix)) + gy * (y - f64(iy))
	}
	x, y := x, y
	v, k, sum := 0.0, 1.0, 0.0
	for i in 0 ..< octaves {
		s := seed + i
		ix := int(x)
		xs := scurve(x - f64(ix))
		iy := int(y)
		ys := scurve(y - f64(iy))
		ga := grad(x, y, ix, iy, s)
		gb := grad(x, y, ix + 1, iy, s)
		gc := grad(x, y, ix, iy + 1, s)
		gd := grad(x, y, ix + 1, iy + 1, s)
		v += linear(linear(ga, gb, xs), linear(gc, gd, xs), ys) * k
		sum += k
		k *= 0.5
		x *= 2.0
		y *= 2.0
	}
	if sum != 0 do v /= sum
	return v
}

// Ldtk_RuleSource: the IntGrid layer a layer's rules read (itself for
// IntGrid layers, the auto source for AutoLayers), nil when rules can't run.
Ldtk_RuleSource :: proc(doc: ^Ldtk_Doc, lv: ^Ldtk_DocLevel, ly: ^Ldtk_DocLayer) -> ^Ldtk_DocLayer {
	d := Ldtk_Doc_LayerDef(doc, ly)
	if d == nil do return nil
	if Ldtk_Doc_LayerTileset(doc, ly) == nil && d.tilesetUid < 0 do return nil
	switch d.type {
	case .IntGrid: return d.tilesetUid >= 0 ? ly : nil
	case .AutoLayer:
		src := Ldtk_Doc_LevelLayer(doc, lv, d.autoSourceUid)
		if src == nil do return nil
		sd := Ldtk_Doc_LayerDef(doc, src)
		if sd == nil || sd.type != .IntGrid do return nil
		return src
	case .Entities, .Tiles:
	}
	return nil
}

@(private = "file")
Rule_Ctx :: struct {
	doc:      ^Ldtk_Doc,
	lv:       ^Ldtk_DocLevel,
	ly:       ^Ldtk_DocLayer,
	def:      ^Ldtk_DocLayerDef,
	src:      ^Ldtk_DocLayer,
	srcDef:   ^Ldtk_DocLayerDef,
	ts:       ^Ldtk_DocTileset,
	killer:   ^Ldtk_DocLayer,
	rules:    [dynamic]^Ldtk_DocRule, // eval order
	ranks:    [dynamic]i32,           // display rank of rules[i]
	// IntGrid counts per value: whole layer and per 10x10 area
	areaW:    int,
	areaH:    int,
	counts:   map[i32][]i32,
	totals:   map[i32]int,
	a:        mem.Allocator,
}

LDTK_AREA :: 10

@(private = "file")
rule_group_applies :: proc(c: ^Rule_Ctx, g: ^Ldtk_DocRuleGroup) -> bool {
	if g.active && len(g.biomeValues) > 0 && c.def.biomeFieldUid >= 0 {
		for fi in LdtkJson_Arr(c.lv.obj, "fieldInstances") {
			if LdtkJson_Int(fi, "defUid", -1) != c.def.biomeFieldUid do continue
			vals := make([dynamic]string, c.a)
			v := LdtkJson_Get(fi, "realEditorValues")
			if v != nil && v.kind == .Array {
				for it in v.items {
					if p := LdtkJson_Arr(it, "params"); len(p) > 0 && p[0].kind == .String do append(&vals, p[0].text)
				}
			}
			switch g.biomeMode {
			case 0:
				for have in vals do for want in g.biomeValues do if have == want do return true
				return false
			case 1:
				matches := 0
				for want in g.biomeValues {
					for have in vals do if have == want {
						matches += 1
						break
					}
				}
				return matches >= len(g.biomeValues)
			case:
				return false
			}
		}
	}
	optional := false
	for o in LdtkJson_Arr(c.ly.obj, "optionalRules") do if int(o.num) == g.uid do optional = true
	return (g.active && !g.isOptional) || optional
}

@(private = "file")
rule_ctx_init :: proc(c: ^Rule_Ctx, doc: ^Ldtk_Doc, lv: ^Ldtk_DocLevel, ly: ^Ldtk_DocLayer, src: ^Ldtk_DocLayer, a: mem.Allocator) {
	c.doc, c.lv, c.ly, c.src, c.a = doc, lv, ly, src, a
	c.def = Ldtk_Doc_LayerDef(doc, ly)
	c.srcDef = Ldtk_Doc_LayerDef(doc, src)
	c.ts = Ldtk_Doc_LayerTileset(doc, ly)
	c.killer = c.def.autoTilesKilledByUid >= 0 ? Ldtk_Doc_LevelLayer(doc, lv, c.def.autoTilesKilledByUid) : nil
	c.rules = make([dynamic]^Ldtk_DocRule, a)
	c.ranks = make([dynamic]i32, a)
	applied := make([]bool, len(c.def.groups), a)
	for &g, gi in c.def.groups do applied[gi] = rule_group_applies(c, &g)
	// display order: groups and rules from last to first
	rankOf := make(map[int]i32, allocator = a)
	rank: i32 = 0
	#reverse for &g, gi in c.def.groups {
		if !applied[gi] do continue
		#reverse for &r in g.rules {
			if !r.active do continue
			rankOf[r.uid] = rank
			rank += 1
		}
	}
	for &g, gi in c.def.groups {
		if !applied[gi] do continue
		for &r in g.rules {
			if !r.active do continue
			append(&c.rules, &r)
			append(&c.ranks, rankOf[r.uid])
		}
	}
	// value counts (values and their group values)
	c.areaW = src.cWid / LDTK_AREA + 1
	c.areaH = src.cHei / LDTK_AREA + 1
	c.counts = make(map[i32][]i32, allocator = a)
	c.totals = make(map[i32]int, allocator = a)
	for cy in 0 ..< src.cHei {
		for cx in 0 ..< src.cWid {
			v := src.intGrid[cx + cy * src.cWid]
			if v == 0 do continue
			rule_count(c, v, cx, cy)
			if v < 1000 {
				if iv := Ldtk_Doc_IntValue(c.srcDef, int(v)); iv != nil && iv.groupUid >= 0 {
					rule_count(c, i32((iv.groupUid + 1) * 1000), cx, cy)
				}
			}
		}
	}
}

@(private = "file")
rule_count :: proc(c: ^Rule_Ctx, v: i32, cx, cy: int) {
	arr, ok := c.counts[v]
	if !ok {
		arr = make([]i32, c.areaW * c.areaH, c.a)
		c.counts[v] = arr
	}
	arr[cx / LDTK_AREA + (cy / LDTK_AREA) * c.areaW] += 1
	c.totals[v] += 1
}

@(private = "file")
rule_in_area :: proc(c: ^Rule_Ctx, v: i32, cx, cy: int) -> bool {
	arr, ok := c.counts[v]
	if !ok do return false
	// Std.int truncates toward zero, like Odin's integer division
	ax := cx / LDTK_AREA
	ay := cy / LDTK_AREA
	if ax < 0 || ay < 0 || ax >= c.areaW || ay >= c.areaH do return false
	return arr[ax + ay * c.areaW] > 0
}

@(private = "file")
rule_relevant_at :: proc(c: ^Rule_Ctx, r: ^Ldtk_DocRule, cx, cy: int) -> bool {
	radius := r.size <= 1 ? 1 : r.size / 2
	for v in r.required {
		if c.totals[v] <= 0 do return false
		if r.size == 1 {
			if !rule_in_area(c, v, cx, cy) do return false
		} else if !rule_in_area(c, v, cx - radius, cy - radius) && !rule_in_area(c, v, cx + radius, cy - radius) && !rule_in_area(c, v, cx + radius, cy + radius) && !rule_in_area(c, v, cx - radius, cy + radius) {
			return false
		}
	}
	return true
}

@(private = "file")
rule_matches :: proc(c: ^Rule_Ctx, r: ^Ldtk_DocRule, cx, cy: int, dirX := 1, dirY := 1) -> bool {
	if len(r.tileRects) == 0 do return false
	if r.chance <= 0 || (r.chance < 1 && f64(Ldtk_RandSeedCoords(c.ly.seed + r.uid, cx, cy, 100)) >= r.chance * 100) do return false
	if r.perlin && ldtk_perlin(c.ly.seed + r.perlinSeed, f64(cx) * r.perlinScale, f64(cy) * r.perlinScale, r.perlinOctaves) < 0 do return false
	radius := r.size / 2
	src := c.src
	for py in 0 ..< r.size {
		for px in 0 ..< r.size {
			p := int(r.pattern[px + py * r.size])
			if p == 0 do continue
			x := cx + dirX * (px - radius)
			y := cy + dirY * (py - radius)
			value: int
			if x >= 0 && y >= 0 && x < src.cWid && y < src.cHei {
				value = int(src.intGrid[x + y * src.cWid])
			} else {
				if !r.hasOutOfBounds do return false
				value = r.outOfBounds
			}
			ap := abs(p)
			if ap == LDTK_AUTO_LAYER_ANYTHING {
				if p > 0 && value == 0 do return false
				if p < 0 && value != 0 do return false
			} else if ap > 999 {
				iv := Ldtk_Doc_IntValue(c.srcDef, value)
				if p > 0 && (iv == nil || iv.groupUid != p / 1000 - 1) do return false
				if p < 0 && (iv != nil && iv.groupUid == (-p) / 1000 - 1) do return false
			} else {
				if p > 0 && value != p do return false
				if p < 0 && value == -p do return false
			}
		}
	}
	return true
}

// rule_add_tiles appends the tiles of a match; returns false when the cell
// is blocked by the "killed by" layer (no tiles, no entry).
@(private = "file")
rule_add_tiles :: proc(c: ^Rule_Ctx, r: ^Ldtk_DocRule, rank: i32, cx, cy: int, flips: int, out: ^[dynamic]Ldtk_DocTile) -> bool {
	if c.killer != nil && len(Ldtk_Doc_TilesAt(c.killer, cx, cy)) > 0 do return false
	seed := c.ly.seed
	ids := r.tileRects[Ldtk_RandSeedCoords(r.uid + seed + flips, cx, cy, len(r.tileRects))]
	grid := c.def.gridSize
	xr, yr := 0, 0
	if r.tileRandomXMin != 0 || r.tileRandomXMax != 0 {
		xr = Ldtk_RandSeedCoords(r.uid + seed + flips, cx, cy, r.tileRandomXMax - r.tileRandomXMin + 1) + r.tileRandomXMin
	}
	if r.tileRandomYMin != 0 || r.tileRandomYMax != 0 {
		yr = Ldtk_RandSeedCoords(r.uid + seed + 1, cx, cy, r.tileRandomYMax - r.tileRandomYMin + 1) + r.tileRandomYMin
	}
	xOff := ((flips & 1) != 0 ? -1 : 1) * (r.tileXOffset + xr)
	yOff := ((flips & 2) != 0 ? -1 : 1) * (r.tileYOffset + yr)
	// stamp bounds in the tileset
	top, left, right, bottom := 99999, 99999, 0, 0
	stamp := r.stamp && c.ts != nil && c.ts.cWid > 0
	if stamp {
		for tid in ids {
			tcx := int(tid) - c.ts.cWid * (int(tid) / c.ts.cWid)
			tcy := int(tid) / c.ts.cWid
			top = min(top, tcy)
			bottom = max(bottom, tcy)
			left = min(left, tcx)
			right = max(right, tcx)
		}
	}
	coord := i32(cx + cy * c.ly.cWid)
	for tid in ids {
		sx, sy := 0, 0
		if stamp {
			tcx := int(tid) - c.ts.cWid * (int(tid) / c.ts.cWid)
			tcy := int(tid) / c.ts.cWid
			sx = int((f64(tcx - left) - r.pivot.x * f64(right - left) + c.def.tilePivot.x) * f64(grid)) * ((flips & 1) != 0 ? -1 : 1)
			sy = int((f64(tcy - top) - r.pivot.y * f64(bottom - top) + c.def.tilePivot.y) * f64(grid)) * ((flips & 2) != 0 ? -1 : 1)
		}
		append(out, Ldtk_DocTile{
			px = {i32(cx * grid + sx + xOff), i32(cy * grid + sy + yOff)},
			src = Ldtk_Doc_TileSrc(c.ts, int(tid)),
			t = tid,
			coord = coord,
			rule = i32(r.uid),
			rank = rank,
			f = u8(flips),
			a = r.alpha,
		})
	}
	return true
}

// rule_cell runs every rule at one cell (eval order, break-on-match).
@(private = "file")
rule_cell :: proc(c: ^Rule_Ctx, cx, cy: int, out: ^[dynamic]Ldtk_DocTile) {
	locked := false
	for r, ri in c.rules {
		if !rule_relevant_at(c, r, cx, cy) do continue
		// modulos / checker
		if r.checker != .Vertical && (cy - r.yOffset) % r.yModulo != 0 do continue
		if r.checker == .Vertical && (cy + (cx / r.xModulo) % 2) % r.yModulo != 0 do continue
		if r.checker != .Horizontal && (cx - r.xOffset) % r.xModulo != 0 do continue
		if r.checker == .Horizontal && (cx + (cy / r.yModulo) % 2) % r.xModulo != 0 do continue
		start := len(out)
		entry := false
		matched := false
		rank := c.ranks[ri]
		if rule_matches(c, r, cx, cy) {
			entry |= rule_add_tiles(c, r, rank, cx, cy, 0, out)
			matched = true
		}
		if (!matched || !r.breakOnMatch) && r.flipX && rule_matches(c, r, cx, cy, -1) {
			entry |= rule_add_tiles(c, r, rank, cx, cy, 1, out)
			matched = true
		}
		if (!matched || !r.breakOnMatch) && r.flipY && rule_matches(c, r, cx, cy, 1, -1) {
			entry |= rule_add_tiles(c, r, rank, cx, cy, 2, out)
			matched = true
		}
		if (!matched || !r.breakOnMatch) && r.flipX && r.flipY && rule_matches(c, r, cx, cy, -1, -1) {
			entry |= rule_add_tiles(c, r, rank, cx, cy, 3, out)
			matched = true
		}
		if !entry do continue
		if locked {
			resize(out, start) // tiles below a lock are discarded
			continue
		}
		if r.breakOnMatch {
			locked = true
		} else if !(r.tileRandomXMin != 0 || r.tileRandomXMax != 0 || r.tileRandomYMin != 0 || r.tileRandomYMax != 0 || r.tileXOffset != 0 || r.tileYOffset != 0) && r.alpha >= 1 && c.ts != nil && c.ts.opaque != nil {
			for t in out[start:] {
				if int(t.t) >= 0 && int(t.t) < len(c.ts.opaque) && c.ts.opaque[t.t] {
					locked = true
					break
				}
			}
		}
	}
}

// ldtk_rule_cells: the cells where one rule matches (the preview).
@(private)
ldtk_rule_cells :: proc(doc: ^Ldtk_Doc, lv: ^Ldtk_DocLevel, ly: ^Ldtk_DocLayer, ruleUid: int, out: ^[dynamic][2]int) {
	src := Ldtk_RuleSource(doc, lv, ly)
	if src == nil do return
	arena: vmem.Arena
	if vmem.arena_init_growing(&arena) != nil do return
	defer vmem.arena_destroy(&arena)
	c: Rule_Ctx
	rule_ctx_init(&c, doc, lv, ly, src, vmem.arena_allocator(&arena))
	r: ^Ldtk_DocRule
	for &g in c.def.groups do for &x in g.rules do if x.uid == ruleUid do r = &x
	if r == nil do return
	for cy in 0 ..< ly.cHei {
		for cx in 0 ..< ly.cWid {
			if !rule_relevant_at(&c, r, cx, cy) do continue
			if r.checker != .Vertical && (cy - r.yOffset) % r.yModulo != 0 do continue
			if r.checker == .Vertical && (cy + (cx / r.xModulo) % 2) % r.yModulo != 0 do continue
			if r.checker != .Horizontal && (cx - r.xOffset) % r.xModulo != 0 do continue
			if r.checker == .Horizontal && (cx + (cy / r.yModulo) % 2) % r.xModulo != 0 do continue
			if rule_matches(&c, r, cx, cy) || (r.flipX && rule_matches(&c, r, cx, cy, -1)) || (r.flipY && rule_matches(&c, r, cx, cy, 1, -1)) || (r.flipX && r.flipY && rule_matches(&c, r, cx, cy, -1, -1)) {
				append(out, [2]int{cx, cy})
			}
		}
	}
}

@(private = "file")
tile_less :: proc(a, b: Ldtk_DocTile) -> bool {
	if a.rank != b.rank do return a.rank < b.rank
	if a.coord != b.coord do return a.coord < b.coord
	return a.seq < b.seq
}

// ldtk_rules_run regenerates a layer's auto tiles in the cell rectangle
// (x0, y0)-(x1, y1) inclusive (the whole layer when full).
@(private = "file")
ldtk_rules_run :: proc(doc: ^Ldtk_Doc, lv: ^Ldtk_DocLevel, ly: ^Ldtk_DocLayer, full: bool, x0, y0, x1, y1: int) {
	src := Ldtk_RuleSource(doc, lv, ly)
	if src == nil {
		if len(ly.autoTiles) > 0 {
			clear(&ly.autoTiles)
			ly.autoDirty = true
		}
		return
	}
	arena: vmem.Arena
	if vmem.arena_init_growing(&arena) != nil do return
	defer vmem.arena_destroy(&arena)
	scratch := vmem.arena_allocator(&arena)
	c: Rule_Ctx
	rule_ctx_init(&c, doc, lv, ly, src, scratch)
	l, t, r, b := 0, 0, ly.cWid - 1, ly.cHei - 1
	if !full {
		rad := LDTK_MAX_AUTO_PATTERN_SIZE / 2
		l, t = max(0, x0 - rad), max(0, y0 - rad)
		r, b = min(ly.cWid - 1, x1 + rad), min(ly.cHei - 1, y1 + rad)
	}
	fresh := make([dynamic]Ldtk_DocTile, scratch)
	cellTiles := make([dynamic]Ldtk_DocTile, scratch)
	for cy in t ..= b {
		for cx in l ..= r {
			clear(&cellTiles)
			rule_cell(&c, cx, cy, &cellTiles)
			for &tile, i in cellTiles do tile.seq = i32(i)
			append(&fresh, ..cellTiles[:])
		}
	}
	if full {
		clear(&ly.autoTiles)
	} else {
		// drop the old tiles anchored in the rectangle
		w := 0
		for tile in ly.autoTiles {
			cx := int(tile.coord) % max(ly.cWid, 1)
			cy := int(tile.coord) / max(ly.cWid, 1)
			if cx >= l && cx <= r && cy >= t && cy <= b do continue
			ly.autoTiles[w] = tile
			w += 1
		}
		resize(&ly.autoTiles, w)
	}
	// Tiles read from a file have no rank; give them their rule's.
	if !full {
		rankOf := make(map[i32]i32, allocator = scratch)
		for rr, i in c.rules do rankOf[i32(rr.uid)] = c.ranks[i]
		for &tile in ly.autoTiles {
			if rk, ok := rankOf[tile.rule]; ok do tile.rank = rk
		}
	}
	append(&ly.autoTiles, ..fresh[:])
	slice.sort_by(ly.autoTiles[:], tile_less)
	ly.autoDirty = true
}

// ldtk_rule_layers_for: layers of the level whose rules read `changed` (or
// are killed by it).
@(private = "file")
ldtk_rule_dependents :: proc(doc: ^Ldtk_Doc, lv: ^Ldtk_DocLevel, changed: ^Ldtk_DocLayer, out: ^[dynamic]^Ldtk_DocLayer) {
	cd := Ldtk_Doc_LayerDef(doc, changed)
	if cd == nil do return
	for &ly in lv.layers {
		d := Ldtk_Doc_LayerDef(doc, &ly)
		if d == nil do continue
		if Ldtk_RuleSource(doc, lv, &ly) == changed || d.autoTilesKilledByUid == cd.uid do append(out, &ly)
	}
}

// Ldtk_Doc_ApplyRules updates the auto tiles that depend on a change of
// layer `layer` inside the cell rectangle (x0, y0)-(x1, y1).
Ldtk_Doc_ApplyRules :: proc(doc: ^Ldtk_Doc, li, layer: int, x0, y0, x1, y1: int) {
	lv := &doc.levels[li]
	deps := make([dynamic]^Ldtk_DocLayer, context.temp_allocator)
	ldtk_rule_dependents(doc, lv, &lv.layers[layer], &deps)
	for ly in deps do ldtk_rules_run(doc, lv, ly, false, x0, y0, x1, y1)
	if len(deps) > 0 {
		lv.dirty = true
		Ldtk_Doc_Touch(doc)
	}
}

// Ldtk_Doc_ApplyRulesFull regenerates every auto layer of a level (li < 0:
// every level).
Ldtk_Doc_ApplyRulesFull :: proc(doc: ^Ldtk_Doc, li: int) {
	for &lv, i in doc.levels {
		if li >= 0 && i != li do continue
		for &ly in lv.layers {
			d := Ldtk_Doc_LayerDef(doc, &ly)
			if d == nil do continue
			if d.type == .AutoLayer || (d.type == .IntGrid && (d.tilesetUid >= 0 || len(ly.autoTiles) > 0)) {
				ldtk_rules_run(doc, &lv, &ly, true, 0, 0, 0, 0)
				lv.dirty = true
			}
		}
	}
	Ldtk_Doc_Touch(doc)
}

// Ldtk_Doc_ApplyRulesLayer regenerates one layer (after its rules changed).
Ldtk_Doc_ApplyRulesLayer :: proc(doc: ^Ldtk_Doc, li, layer: int) {
	lv := &doc.levels[li]
	ldtk_rules_run(doc, lv, &lv.layers[layer], true, 0, 0, 0, 0)
	lv.dirty = true
	Ldtk_Doc_Touch(doc)
}
@(private = "file")
LDTK_PERLIN_GRADIENTS := [768]f64{
	-0.763874,-0.596439,-0.246489,0.396055,0.904518,-0.158073,
	-0.499004,-0.8665,-0.0131631,0.468724,-0.824756,0.316346,
	0.829598,0.43195,0.353816,-0.454473,0.629497,-0.630228,
	-0.162349,-0.869962,-0.465628,0.932805,0.253451,0.256198,
	-0.345419,0.927299,-0.144227,-0.715026,-0.293698,-0.634413,
	-0.245997,0.717467,-0.651711,-0.967409,-0.250435,-0.037451,
	0.901729,0.397108,-0.170852,0.892657,-0.0720622,-0.444938,
	0.0260084,-0.0361701,0.999007,0.949107,-0.19486,0.247439,
	0.471803,-0.807064,-0.355036,0.879737,0.141845,0.453809,
	0.570747,0.696415,0.435033,-0.141751,-0.988233,-0.0574584,
	-0.58219,-0.0303005,0.812488,-0.60922,0.239482,-0.755975,
	0.299394,-0.197066,-0.933557,-0.851615,-0.220702,-0.47544,
	0.848886,0.341829,-0.403169,-0.156129,-0.687241,0.709453,
	-0.665651,0.626724,0.405124,0.595914,-0.674582,0.43569,
	0.171025,-0.509292,0.843428,0.78605,0.536414,-0.307222,
	0.18905,-0.791613,0.581042,-0.294916,0.844994,0.446105,
	0.342031,-0.58736,-0.7335,0.57155,0.7869,0.232635,
	0.885026,-0.408223,0.223791,-0.789518,0.571645,0.223347,
	0.774571,0.31566,0.548087,-0.79695,-0.0433603,-0.602487,
	-0.142425,-0.473249,-0.869339,-0.0698838,0.170442,0.982886,
	0.687815,-0.484748,0.540306,0.543703,-0.534446,-0.647112,
	0.97186,0.184391,-0.146588,0.707084,0.485713,-0.513921,
	0.942302,0.331945,0.043348,0.499084,0.599922,0.625307,
	-0.289203,0.211107,0.9337,0.412433,-0.71667,-0.56239,
	0.87721,-0.082816,0.47291,-0.420685,-0.214278,0.881538,
	0.752558,-0.0391579,0.657361,0.0765725,-0.996789,0.0234082,
	-0.544312,-0.309435,-0.779727,-0.455358,-0.415572,0.787368,
	-0.874586,0.483746,0.0330131,0.245172,-0.0838623,0.965846,
	0.382293,-0.432813,0.81641,-0.287735,-0.905514,0.311853,
	-0.667704,0.704955,-0.239186,0.717885,-0.464002,-0.518983,
	0.976342,-0.214895,0.0240053,-0.0733096,-0.921136,0.382276,
	-0.986284,0.151224,-0.0661379,-0.899319,-0.429671,0.0812908,
	0.652102,-0.724625,0.222893,0.203761,0.458023,-0.865272,
	-0.030396,0.698724,-0.714745,-0.460232,0.839138,0.289887,
	-0.0898602,0.837894,0.538386,-0.731595,0.0793784,0.677102,
	-0.447236,-0.788397,0.422386,0.186481,0.645855,-0.740335,
	-0.259006,0.935463,0.240467,0.445839,0.819655,-0.359712,
	0.349962,0.755022,-0.554499,-0.997078,-0.0359577,0.0673977,
	-0.431163,-0.147516,-0.890133,0.299648,-0.63914,0.708316,
	0.397043,0.566526,-0.722084,-0.502489,0.438308,-0.745246,
	0.0687235,0.354097,0.93268,-0.0476651,-0.462597,0.885286,
	-0.221934,0.900739,-0.373383,-0.956107,-0.225676,0.186893,
	-0.187627,0.391487,-0.900852,-0.224209,-0.315405,0.92209,
	-0.730807,-0.537068,0.421283,-0.0353135,-0.816748,0.575913,
	-0.941391,0.176991,-0.287153,-0.154174,0.390458,0.90762,
	-0.283847,0.533842,0.796519,-0.482737,-0.850448,0.209052,
	-0.649175,0.477748,0.591886,0.885373,-0.405387,-0.227543,
	-0.147261,0.181623,-0.972279,0.0959236,-0.115847,-0.988624,
	-0.89724,-0.191348,0.397928,0.903553,-0.428461,-0.00350461,
	0.849072,-0.295807,-0.437693,0.65551,0.741754,-0.141804,
	0.61598,-0.178669,0.767232,0.0112967,0.932256,-0.361623,
	-0.793031,0.258012,0.551845,0.421933,0.454311,0.784585,
	-0.319993,0.0401618,-0.946568,-0.81571,0.551307,-0.175151,
	-0.377644,0.00322313,0.925945,0.129759,-0.666581,-0.734052,
	0.601901,-0.654237,-0.457919,-0.927463,-0.0343576,-0.372334,
	-0.438663,-0.868301,-0.231578,-0.648845,-0.749138,-0.133387,
	0.507393,-0.588294,0.629653,0.726958,0.623665,0.287358,
	0.411159,0.367614,-0.834151,0.806333,0.585117,-0.0864016,
	0.263935,-0.880876,0.392932,0.421546,-0.201336,0.884174,
	-0.683198,-0.569557,-0.456996,-0.117116,-0.0406654,-0.992285,
	-0.643679,-0.109196,-0.757465,-0.561559,-0.62989,0.536554,
	0.0628422,0.104677,-0.992519,0.480759,-0.2867,-0.828658,
	-0.228559,-0.228965,-0.946222,-0.10194,-0.65706,-0.746914,
	0.0689193,-0.678236,0.731605,0.401019,-0.754026,0.52022,
	-0.742141,0.547083,-0.387203,-0.00210603,-0.796417,-0.604745,
	0.296725,-0.409909,-0.862513,-0.260932,-0.798201,0.542945,
	-0.641628,0.742379,0.192838,-0.186009,-0.101514,0.97729,
	0.106711,-0.962067,0.251079,-0.743499,0.30988,-0.592607,
	-0.795853,-0.605066,-0.0226607,-0.828661,-0.419471,-0.370628,
	0.0847218,-0.489815,-0.8677,-0.381405,0.788019,-0.483276,
	0.282042,-0.953394,0.107205,0.530774,0.847413,0.0130696,
	0.0515397,0.922524,0.382484,-0.631467,-0.709046,0.313852,
	0.688248,0.517273,0.508668,0.646689,-0.333782,-0.685845,
	-0.932528,-0.247532,-0.262906,0.630609,0.68757,-0.359973,
	0.577805,-0.394189,0.714673,-0.887833,-0.437301,-0.14325,
	0.690982,0.174003,0.701617,-0.866701,0.0118182,0.498689,
	-0.482876,0.727143,0.487949,-0.577567,0.682593,-0.447752,
	0.373768,0.0982991,0.922299,0.170744,0.964243,-0.202687,
	0.993654,-0.035791,-0.106632,0.587065,0.4143,-0.695493,
	-0.396509,0.26509,-0.878924,-0.0866853,0.83553,-0.542563,
	0.923193,0.133398,-0.360443,0.00379108,-0.258618,0.965972,
	0.239144,0.245154,-0.939526,0.758731,-0.555871,0.33961,
	0.295355,0.309513,0.903862,0.0531222,-0.91003,-0.411124,
	0.270452,0.0229439,-0.96246,0.563634,0.0324352,0.825387,
	0.156326,0.147392,0.976646,-0.0410141,0.981824,0.185309,
	-0.385562,-0.576343,-0.720535,0.388281,0.904441,0.176702,
	0.945561,-0.192859,-0.262146,0.844504,0.520193,0.127325,
	0.0330893,0.999121,-0.0257505,-0.592616,-0.482475,-0.644999,
	0.539471,0.631024,-0.557476,0.655851,-0.027319,-0.754396,
	0.274465,0.887659,0.369772,-0.123419,0.975177,-0.183842,
	-0.223429,0.708045,0.66989,-0.908654,0.196302,0.368528,
	-0.95759,-0.00863708,0.288005,0.960535,0.030592,0.276472,
	-0.413146,0.907537,0.0754161,-0.847992,0.350849,-0.397259,
	0.614736,0.395841,0.68221,-0.503504,-0.666128,-0.550234,
	-0.268833,-0.738524,-0.618314,0.792737,-0.60001,-0.107502,
	-0.637582,0.508144,-0.579032,0.750105,0.282165,-0.598101,
	-0.351199,-0.392294,-0.850155,0.250126,-0.960993,-0.118025,
	-0.732341,0.680909,-0.0063274,-0.760674,-0.141009,0.633634,
	0.222823,-0.304012,0.926243,0.209178,0.505671,0.836984,
	0.757914,-0.56629,-0.323857,-0.782926,-0.339196,0.52151,
	-0.462952,0.585565,0.665424,0.61879,0.194119,-0.761194,
	0.741388,-0.276743,0.611357,0.707571,0.702621,0.0752872,
	0.156562,0.819977,0.550569,-0.793606,0.440216,0.42,
	0.234547,0.885309,-0.401517,0.132598,0.80115,-0.58359,
	-0.377899,-0.639179,0.669808,-0.865993,-0.396465,0.304748,
	-0.624815,-0.44283,0.643046,-0.485705,0.825614,-0.287146,
	-0.971788,0.175535,0.157529,-0.456027,0.392629,0.798675,
	-0.0104443,0.521623,-0.853112,-0.660575,-0.74519,0.091282,
	-0.0157698,-0.307475,-0.951425,-0.603467,-0.250192,0.757121,
	0.506876,0.25006,0.824952,0.255404,0.966794,0.00884498,
	0.466764,-0.874228,-0.133625,0.475077,-0.0682351,-0.877295,
	-0.224967,-0.938972,-0.260233,-0.377929,-0.814757,-0.439705,
	-0.305847,0.542333,-0.782517,0.26658,-0.902905,-0.337191,
	0.0275773,0.322158,-0.946284,0.0185422,0.716349,0.697496,
	-0.20483,0.978416,0.0273371,-0.898276,0.373969,0.230752,
	-0.00909378,0.546594,0.837349,0.6602,-0.751089,0.000959236,
	0.855301,-0.303056,0.420259,0.797138,0.0623013,-0.600574,
	0.48947,-0.866813,0.0951509,0.251142,0.674531,0.694216,
	-0.578422,-0.737373,-0.348867,-0.254689,-0.514807,0.818601,
	0.374972,0.761612,0.528529,0.640303,-0.734271,-0.225517,
	-0.638076,0.285527,0.715075,0.772956,-0.15984,-0.613995,
	0.798217,-0.590628,0.118356,-0.986276,-0.0578337,-0.154644,
	-0.312988,-0.94549,0.0899272,-0.497338,0.178325,0.849032,
	-0.101136,-0.981014,0.165477,-0.521688,0.0553434,-0.851339,
	-0.786182,-0.583814,0.202678,-0.565191,0.821858,-0.0714658,
	0.437895,0.152598,-0.885981,-0.92394,0.353436,-0.14635,
	0.212189,-0.815162,-0.538969,-0.859262,0.143405,-0.491024,
	0.991353,0.112814,0.0670273,0.0337884,-0.979891,-0.196654,
}
