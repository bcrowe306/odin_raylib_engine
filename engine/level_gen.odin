package engine

import "base:runtime"
import "core:c"
import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:strings"
import lua "lua54"

// ============================================================================
// Procedural level generation (#142): a graph of nodes (Gaea style) whose
// output is a level. Every port carries a grid of numbers the size of the
// level (0 = empty / low, 1 = solid / high): generators make one, modifiers
// turn one (or two) into another, and the tile output maps value ranges to
// tiles and writes them into a TileMapNode (its colliders follow when it is
// Solid).
//
// A generator is a project file (.levelgen.json):
//
//   {"size": [64, 40], "seed": 7, "output": 4, "nodes": [
//     {"id": 1, "type": "random_fill", "params": {"density": 0.48}},
//     {"id": 2, "type": "cellular", "inputs": {"in": 1}, "params": {"iterations": 5}},
//     {"id": 3, "type": "border", "params": {"width": 1}},
//     {"id": 4, "type": "combine", "inputs": {"a": 2, "b": 3}, "params": {"op": "max"}},
//     {"id": 5, "type": "tile_output", "inputs": {"in": 4},
//      "rules": [{"min": 0.5, "max": 1, "tiles": [3, 4]}]}]}
//
// Deterministic: the same graph and seed give the same level on every
// platform (hash noise, no global random state). Each node's own seed mixes
// the graph's seed, its id and its "seed" parameter. Evaluation is
// depth-first with every node's grid computed once (a cycle is an error).
// ============================================================================

Gen_Kind :: enum {
	// Generators
	Constant,
	Noise,
	Random_Fill,
	Gradient,
	Border,
	Rect,
	// Modifiers
	Threshold,
	Invert,
	Remap,
	Blur,
	Cellular,
	Dilate,
	Erode,
	Combine,
	// Output
	Tile_Output,
}

Gen_Param_Def :: struct {
	name:     string,
	default_: f64,
	choices:  []string, // a choice parameter (saved by name; the value is its index)
	doc:      string,
	integer:  bool,     // whole numbers (the editor's widget)
	toggle:   bool,     // on / off (saved as a number, read as true / false)
}

Gen_Kind_Info :: struct {
	name:   string, // in the file ("random_fill")
	label:  string,
	inputs: []string,
	params: []Gen_Param_Def,
	doc:    string,
}

GEN_COMBINE_OPS := []string{"add", "subtract", "multiply", "min", "max", "mask", "average"}
GEN_GRADIENT_DIRS := []string{"horizontal", "vertical", "radial"}

GEN_KINDS := [Gen_Kind]Gen_Kind_Info{
	.Constant = {"constant", "Constant", {}, {{name = "value", default_ = 1, doc = "Every cell's value"}}, "The same value everywhere."},
	.Noise = {"noise", "Noise", {}, {
		{name = "scale", default_ = 16, doc = "Size of the features (cells)"},
		{name = "octaves", default_ = 3, doc = "Layers of detail (1-8)", integer = true},
		{name = "persistence", default_ = 0.5, doc = "How much each finer layer adds"},
		{name = "seed", default_ = 0, doc = "Added to the graph's seed", integer = true},
	}, "Smooth value noise (fBm), 0..1: hills, islands, caves before a threshold."},
	.Random_Fill = {"random_fill", "Random Fill", {}, {
		{name = "density", default_ = 0.45, doc = "Fraction of cells set to 1"},
		{name = "seed", default_ = 0, doc = "Added to the graph's seed", integer = true},
	}, "Each cell 1 with a chance of `density`, else 0 (the start of cellular caves)."},
	.Gradient = {"gradient", "Gradient", {}, {
		{name = "direction", default_ = 0, choices = GEN_GRADIENT_DIRS, doc = "horizontal (0 left .. 1 right), vertical (0 top .. 1 bottom), radial (1 centre .. 0 corners)"},
	}, "A ramp across the level (a ground line with a threshold, an island with radial)."},
	.Border = {"border", "Border", {}, {{name = "width", default_ = 1, doc = "Cells from each edge", integer = true}}, "1 within `width` cells of the edge, else 0 (walls around a level)."},
	.Rect = {"rect", "Rectangle", {}, {
		{name = "x", default_ = 0, doc = "Left cell", integer = true},
		{name = "y", default_ = 0, doc = "Top cell", integer = true},
		{name = "w", default_ = 8, doc = "Width (cells)", integer = true},
		{name = "h", default_ = 8, doc = "Height (cells)", integer = true},
		{name = "value", default_ = 1, doc = "Inside (0 outside)"},
	}, "A filled rectangle (a spawn room, a floor)."},
	.Threshold = {"threshold", "Threshold", {"in"}, {
		{name = "value", default_ = 0.5, doc = "Cells at or above it become 1, the rest 0"},
		{name = "invert", default_ = 0, doc = "1: below becomes 1 instead", toggle = true},
	}, "Turns values into solid (1) and empty (0)."},
	.Invert = {"invert", "Invert", {"in"}, {}, "1 - value (solid <-> empty)."},
	.Remap = {"remap", "Remap", {"in"}, {
		{name = "from_min", default_ = 0, doc = ""},
		{name = "from_max", default_ = 1, doc = ""},
		{name = "to_min", default_ = 0, doc = ""},
		{name = "to_max", default_ = 1, doc = ""},
	}, "Maps one range of values onto another (clamped to it)."},
	.Blur = {"blur", "Blur", {"in"}, {{name = "radius", default_ = 1, doc = "Cells averaged on each side", integer = true}}, "Averages each cell with its neighbours (smooths noise and edges)."},
	.Cellular = {"cellular", "Cellular Automaton", {"in"}, {
		{name = "iterations", default_ = 4, doc = "Smoothing passes", integer = true},
		{name = "birth", default_ = 5, doc = "An empty cell with at least this many solid neighbours (of 8) becomes solid", integer = true},
		{name = "survive", default_ = 4, doc = "A solid cell with fewer solid neighbours becomes empty", integer = true},
		{name = "edge_solid", default_ = 1, doc = "1: cells beyond the edge count as solid (closed caves)", toggle = true},
	}, "Cave smoothing: random fill becomes cave walls and open rooms."},
	.Dilate = {"dilate", "Dilate", {"in"}, {{name = "iterations", default_ = 1, doc = "", integer = true}}, "Grows solid areas by a cell per iteration."},
	.Erode = {"erode", "Erode", {"in"}, {{name = "iterations", default_ = 1, doc = "", integer = true}}, "Shrinks solid areas by a cell per iteration."},
	.Combine = {"combine", "Combine", {"a", "b"}, {
		{name = "op", default_ = 0, choices = GEN_COMBINE_OPS, doc = "add, subtract, multiply, min, max, mask (a where b is solid), average"},
	}, "Two grids into one."},
	.Tile_Output = {"tile_output", "Tile Output", {"in"}, {
		{name = "empty", default_ = -1, doc = "The tile for cells no rule takes (-1 = none)", integer = true},
	}, "Rules turn value ranges into tiles (a random one of each rule's tiles, the same for a seed); written into a TileMap."},
}

// A tile rule: cells with min <= value <= max get one of `tiles`.
Gen_Tile_Rule :: struct {
	min, max: f32,
	tiles:    [dynamic]i32,
}

Gen_Node :: struct {
	id:     int,
	kind:   Gen_Kind,
	inputs: [2]int, // source node ids, in the kind's input order (0 = not connected)
	params: [8]f64, // in the kind's parameter order
	rules:  [dynamic]Gen_Tile_Rule, // Tile_Output
	pos:    [2]f32, // where the editor draws it
}

Gen_Graph :: struct {
	size:      [2]int,
	seed:      u64,
	output:    int, // the node whose grid is the result (0 = the last Tile_Output, else the last node)
	nodes:     [dynamic]Gen_Node,
	allocator: runtime.Allocator,
}

// A grid of values (row-major, w * h).
Gen_Grid :: struct {
	w, h: int,
	v:    []f32,
}

Gen_GridAt :: #force_inline proc(g: Gen_Grid, x, y: int) -> f32 {return g.v[y * g.w + x]}

// --- the graph ------------------------------------------------------------------------

Gen_Kind_FromName :: proc(name: string) -> (Gen_Kind, bool) {
	for info, k in GEN_KINDS do if info.name == name do return k, true
	return .Constant, false
}

// Gen_NodeDefaults: a node of a kind with its default parameters.
Gen_NodeDefaults :: proc(kind: Gen_Kind, id: int) -> Gen_Node {
	n := Gen_Node{id = id, kind = kind}
	for p, i in GEN_KINDS[kind].params do n.params[i] = p.default_
	return n
}

// Gen_Param reads a node's parameter by name (its default when unknown).
Gen_Param :: proc(n: ^Gen_Node, name: string) -> f64 {
	for p, i in GEN_KINDS[n.kind].params do if p.name == name do return n.params[i]
	return 0
}

Gen_SetParam :: proc(n: ^Gen_Node, name: string, value: f64) -> bool {
	for p, i in GEN_KINDS[n.kind].params do if p.name == name {
		n.params[i] = value
		return true
	}
	return false
}

Gen_FindNode :: proc(g: ^Gen_Graph, id: int) -> ^Gen_Node {
	for &n in g.nodes do if n.id == id do return &n
	return nil
}

Gen_GraphDestroy :: proc(g: ^Gen_Graph) {
	for &n in g.nodes do Gen_NodeClearRules(&n)
	delete(g.nodes)
	g.nodes = nil
}

Gen_NodeClearRules :: proc(n: ^Gen_Node) {
	for r in n.rules do delete(r.tiles)
	delete(n.rules)
	n.rules = nil
}

// Gen_GraphParse reads a .levelgen.json (allocator: the graph's).
Gen_GraphParse :: proc(data: []u8, allocator := context.allocator) -> (g: Gen_Graph, err: string) {
	g.allocator = allocator
	g.nodes = make([dynamic]Gen_Node, allocator)
	g.size = {32, 24}
	value, perr := json.parse(data, allocator = context.temp_allocator)
	if perr != .None do return g, fmt.tprintf("not valid JSON (%v)", perr)
	root, ok := value.(json.Object)
	if !ok do return g, "not a JSON object"
	if sz, sok := root["size"].(json.Array); sok && len(sz) >= 2 {
		w, _ := json_number(sz[0])
		h, _ := json_number(sz[1])
		g.size = {clamp(int(w), 1, 4096), clamp(int(h), 1, 4096)}
	}
	if s, sok := json_number(root["seed"]); sok do g.seed = u64(s)
	if o, ook := json_number(root["output"]); ook do g.output = int(o)
	nodes, nok := root["nodes"].(json.Array)
	if !nok do return g, ""
	for v in nodes {
		obj, isObj := v.(json.Object)
		if !isObj do continue
		typeName, _ := obj["type"].(json.String)
		kind, known := Gen_Kind_FromName(string(typeName))
		if !known do return g, fmt.tprintf("unknown node type %q", string(typeName))
		idf, _ := json_number(obj["id"])
		n := Gen_NodeDefaults(kind, int(idf))
		if n.id <= 0 do return g, fmt.tprintf("a %s node has no id", string(typeName))
		if Gen_FindNode(&g, n.id) != nil do return g, fmt.tprintf("two nodes have the id %d", n.id)
		if ins, iok := obj["inputs"].(json.Object); iok {
			for port, i in GEN_KINDS[kind].inputs {
				if src, sok := json_number(ins[port]); sok do n.inputs[i] = int(src)
			}
		}
		if ps, pok := obj["params"].(json.Object); pok {
			for p, i in GEN_KINDS[kind].params {
				pv, has := ps[p.name]
				if !has do continue
				if num, isNum := json_number(pv); isNum {
					n.params[i] = f64(num)
				} else if b, isBool := pv.(json.Boolean); isBool {
					n.params[i] = 1 if b else 0
				} else if s, isStr := pv.(json.String); isStr && len(p.choices) > 0 {
					for ch, ci in p.choices do if ch == string(s) do n.params[i] = f64(ci)
				}
			}
		}
		if pos, pok := obj["pos"].(json.Array); pok && len(pos) >= 2 {
			n.pos.x, _ = json_number(pos[0])
			n.pos.y, _ = json_number(pos[1])
		}
		if rules, rok := obj["rules"].(json.Array); rok {
			n.rules = make([dynamic]Gen_Tile_Rule, allocator)
			for rv in rules {
				ro, isObj2 := rv.(json.Object)
				if !isObj2 do continue
				r := Gen_Tile_Rule{min = 0, max = 1, tiles = make([dynamic]i32, allocator)}
				if m, mok := json_number(ro["min"]); mok do r.min = m
				if m, mok := json_number(ro["max"]); mok do r.max = m
				if t, tok := json_number(ro["tile"]); tok do append(&r.tiles, i32(t))
				if ts, tok := ro["tiles"].(json.Array); tok do for tv in ts do if t, isNum := json_number(tv); isNum do append(&r.tiles, i32(t))
				append(&n.rules, r)
			}
		}
		append(&g.nodes, n)
	}
	return g, ""
}

// Gen_GraphSerialize writes a graph as .levelgen.json text.
Gen_GraphSerialize :: proc(g: ^Gen_Graph, allocator := context.allocator) -> string {
	w: Json_Writer
	w.sb = strings.builder_make(allocator)
	fmt.sbprintf(&w.sb, "{{\"size\": [%d, %d], \"seed\": %d", g.size.x, g.size.y, g.seed)
	if g.output != 0 do fmt.sbprintf(&w.sb, ", \"output\": %d", g.output)
	strings.write_string(&w.sb, ", \"nodes\": [")
	for &n, i in g.nodes {
		strings.write_string(&w.sb, "," if i > 0 else "")
		strings.write_string(&w.sb, "\n  {\"id\": ")
		fmt.sbprintf(&w.sb, "%d, \"type\": ", n.id)
		Json_String(&w, GEN_KINDS[n.kind].name)
		info := GEN_KINDS[n.kind]
		if len(info.inputs) > 0 {
			strings.write_string(&w.sb, ", \"inputs\": {")
			k := 0
			for port, pi in info.inputs {
				if n.inputs[pi] == 0 do continue
				if k > 0 do strings.write_string(&w.sb, ", ")
				Json_String(&w, port)
				fmt.sbprintf(&w.sb, ": %d", n.inputs[pi])
				k += 1
			}
			strings.write_byte(&w.sb, '}')
		}
		if len(info.params) > 0 {
			strings.write_string(&w.sb, ", \"params\": {")
			for p, pi in info.params {
				if pi > 0 do strings.write_string(&w.sb, ", ")
				Json_String(&w, p.name)
				strings.write_string(&w.sb, ": ")
				if len(p.choices) > 0 do Json_String(&w, p.choices[clamp(int(n.params[pi]), 0, len(p.choices) - 1)])
				else do Json_Float(&w, f32(n.params[pi]))
			}
			strings.write_byte(&w.sb, '}')
		}
		if n.kind == .Tile_Output {
			strings.write_string(&w.sb, ", \"rules\": [")
			for r, ri in n.rules {
				if ri > 0 do strings.write_string(&w.sb, ", ")
				strings.write_string(&w.sb, "{\"min\": ")
				Json_Float(&w, r.min)
				strings.write_string(&w.sb, ", \"max\": ")
				Json_Float(&w, r.max)
				strings.write_string(&w.sb, ", \"tiles\": [")
				for t, ti in r.tiles do fmt.sbprintf(&w.sb, "%s%d", ", " if ti > 0 else "", t)
				strings.write_string(&w.sb, "]}")
			}
			strings.write_byte(&w.sb, ']')
		}
		if n.pos != {} {
			strings.write_string(&w.sb, ", \"pos\": ")
			Json_Vec2(&w, n.pos)
		}
		strings.write_byte(&w.sb, '}')
	}
	strings.write_string(&w.sb, "\n]}\n")
	return strings.to_string(w.sb)
}

// --- editing (the editor's Generator window) -------------------------------------------

// GEN_TEMPLATE_CAVE: a new generator - a closed cave on 48 x 32 cells.
GEN_TEMPLATE_CAVE :: `{"size": [48, 32], "seed": 1, "nodes": [
  {"id": 1, "type": "random_fill", "params": {"density": 0.48}, "pos": [0, 0]},
  {"id": 2, "type": "cellular", "inputs": {"in": 1}, "params": {"iterations": 5}, "pos": [220, 0]},
  {"id": 3, "type": "border", "params": {"width": 1}, "pos": [220, 170]},
  {"id": 4, "type": "combine", "inputs": {"a": 2, "b": 3}, "params": {"op": "max"}, "pos": [440, 60]},
  {"id": 5, "type": "tile_output", "inputs": {"in": 4}, "rules": [{"min": 0.5, "max": 1, "tiles": [0]}], "pos": [660, 60]}
]}
`

// Gen_AddNode adds a node of a kind (default parameters; a tile output gets
// one rule for solid cells) with a new id.
Gen_AddNode :: proc(g: ^Gen_Graph, kind: Gen_Kind, pos: [2]f32) -> ^Gen_Node {
	id := 1
	for n in g.nodes do id = max(id, n.id + 1)
	n := Gen_NodeDefaults(kind, id)
	n.pos = pos
	if kind == .Tile_Output {
		n.rules = make([dynamic]Gen_Tile_Rule, g.allocator)
		r := Gen_Tile_Rule{min = 0.5, max = 1, tiles = make([dynamic]i32, g.allocator)}
		append(&r.tiles, 0)
		append(&n.rules, r)
	}
	append(&g.nodes, n)
	return &g.nodes[len(g.nodes) - 1]
}

// Gen_DuplicateNode copies a node (parameters, rules; not its inputs).
Gen_DuplicateNode :: proc(g: ^Gen_Graph, id: int, offset := [2]f32{30, 30}) -> ^Gen_Node {
	src := Gen_FindNode(g, id)
	if src == nil do return nil
	copied := src^
	n := Gen_AddNode(g, copied.kind, copied.pos + offset)
	newId := n.id
	Gen_NodeClearRules(n)
	n^ = copied
	n.id, n.pos, n.inputs = newId, copied.pos + offset, {}
	n.rules = nil
	if len(copied.rules) > 0 {
		n.rules = make([dynamic]Gen_Tile_Rule, g.allocator)
		for r in copied.rules {
			c := Gen_Tile_Rule{min = r.min, max = r.max, tiles = make([dynamic]i32, g.allocator)}
			append(&c.tiles, ..r.tiles[:])
			append(&n.rules, c)
		}
	}
	return n
}

// Gen_RemoveNode deletes a node; inputs that read it are disconnected.
Gen_RemoveNode :: proc(g: ^Gen_Graph, id: int) -> bool {
	for &n, i in g.nodes {
		if n.id != id do continue
		Gen_NodeClearRules(&n)
		ordered_remove(&g.nodes, i)
		for &o in g.nodes do for &src in o.inputs do if src == id do src = 0
		if g.output == id do g.output = 0
		return true
	}
	return false
}

// Gen_Reads: does node `id` read `src`, directly or through others?
Gen_Reads :: proc(g: ^Gen_Graph, id, src: int, depth := 0) -> bool {
	if id == src do return true
	n := Gen_FindNode(g, id)
	if n == nil || depth > 256 do return false
	for i in n.inputs do if i != 0 && Gen_Reads(g, i, src, depth + 1) do return true
	return false
}

// Gen_Connect links `src`'s output to input `port` of `dst` (0 = none);
// refused when it would make a cycle or the port doesn't exist.
Gen_Connect :: proc(g: ^Gen_Graph, dst: int, port: int, src: int) -> bool {
	n := Gen_FindNode(g, dst)
	if n == nil || port < 0 || port >= len(GEN_KINDS[n.kind].inputs) do return false
	if src != 0 && (Gen_FindNode(g, src) == nil || Gen_Reads(g, src, dst)) do return false
	n.inputs[port] = src
	return true
}

// Gen_OutputNode: the node whose grid is the graph's result.
Gen_OutputNode :: proc(g: ^Gen_Graph) -> ^Gen_Node {
	if g.output != 0 do if n := Gen_FindNode(g, g.output); n != nil do return n
	#reverse for &n in g.nodes do if n.kind == .Tile_Output do return &n
	return &g.nodes[len(g.nodes) - 1] if len(g.nodes) > 0 else nil
}

// --- evaluation -----------------------------------------------------------------------

@(private = "file")
Gen_Eval :: struct {
	g:      ^Gen_Graph,
	seed:   u64,
	done:   map[int]Gen_Grid,
	active: map[int]bool, // being evaluated (a cycle if met again)
	err:    string,
}

// Gen_Evaluate computes a node's grid (id 0: the output node) for a seed
// (the graph's seed when 0). The grid's values are in `allocator`.
Gen_Evaluate :: proc(g: ^Gen_Graph, id := 0, seed: u64 = 0, allocator := context.allocator) -> (grid: Gen_Grid, err: string) {
	target := Gen_OutputNode(g) if id == 0 else Gen_FindNode(g, id)
	if target == nil do return {}, "the graph has no nodes" if id == 0 else fmt.tprintf("no node %d", id)
	ev := Gen_Eval{g = g, seed = seed if seed != 0 else g.seed}
	ev.done = make(map[int]Gen_Grid, allocator = context.temp_allocator)
	ev.active = make(map[int]bool, allocator = context.temp_allocator)
	tmp, ok := gen_eval(&ev, target.id)
	if !ok do return {}, ev.err
	grid = {tmp.w, tmp.h, make([]f32, len(tmp.v), allocator)}
	copy(grid.v, tmp.v)
	return grid, ""
}

Gen_GridDestroy :: proc(grid: ^Gen_Grid, allocator := context.allocator) {
	delete(grid.v, allocator)
	grid.v = nil
}

@(private = "file")
gen_new :: proc(ev: ^Gen_Eval) -> Gen_Grid {
	w, h := ev.g.size.x, ev.g.size.y
	return {w, h, make([]f32, w * h, context.temp_allocator)}
}

// gen_input: a node's input grid (empty - zeros - when not connected).
@(private = "file")
gen_input :: proc(ev: ^Gen_Eval, n: ^Gen_Node, i: int) -> (Gen_Grid, bool) {
	if n.inputs[i] == 0 do return gen_new(ev), true
	return gen_eval(ev, n.inputs[i])
}

@(private = "file")
gen_eval :: proc(ev: ^Gen_Eval, id: int) -> (result: Gen_Grid, ok: bool) {
	if grid, ok := ev.done[id]; ok do return grid, true
	n := Gen_FindNode(ev.g, id)
	if n == nil {
		ev.err = fmt.tprintf("a node is connected to node %d, which doesn't exist", id)
		return {}, false
	}
	if ev.active[id] {
		ev.err = fmt.tprintf("a cycle through node %d", id)
		return {}, false
	}
	ev.active[id] = true
	defer delete_key(&ev.active, id)
	nodeSeed := gen_mix(gen_mix(ev.seed, u64(n.id)), u64(i64(Gen_Param(n, "seed"))))
	out := gen_new(ev)
	w, h := out.w, out.h
	p :: Gen_Param
	switch n.kind {
	case .Constant:
		for &v in out.v do v = f32(p(n, "value"))
	case .Noise:
		scale := max(f32(p(n, "scale")), 0.5)
		octaves := clamp(int(p(n, "octaves")), 1, 8)
		persistence := f32(p(n, "persistence"))
		for y in 0 ..< h do for x in 0 ..< w {
			amp, freq, sum, norm: f32 = 1, 1 / scale, 0, 0
			for o in 0 ..< octaves {
				sum += gen_value_noise(f32(x) * freq, f32(y) * freq, nodeSeed + u64(o) * 7919) * amp
				norm += amp
				amp *= persistence
				freq *= 2
			}
			out.v[y * w + x] = sum / max(norm, 0.0001)
		}
	case .Random_Fill:
		d := f32(p(n, "density"))
		for y in 0 ..< h do for x in 0 ..< w do out.v[y * w + x] = 1 if gen_hash01(x, y, nodeSeed) < d else 0
	case .Gradient:
		dir := int(p(n, "direction"))
		for y in 0 ..< h do for x in 0 ..< w {
			v: f32
			switch dir {
			case 1: v = f32(y) / f32(max(h - 1, 1))
			case 2:
				dx, dy := (f32(x) - f32(w - 1) * 0.5) / max(f32(w - 1) * 0.5, 1), (f32(y) - f32(h - 1) * 0.5) / max(f32(h - 1) * 0.5, 1)
				v = clamp(1 - math.sqrt(dx * dx + dy * dy) / math.SQRT_TWO, 0, 1)
			case: v = f32(x) / f32(max(w - 1, 1))
			}
			out.v[y * w + x] = v
		}
	case .Border:
		bw := int(p(n, "width"))
		for y in 0 ..< h do for x in 0 ..< w do out.v[y * w + x] = 1 if x < bw || y < bw || x >= w - bw || y >= h - bw else 0
	case .Rect:
		rx, ry, rw, rh := int(p(n, "x")), int(p(n, "y")), int(p(n, "w")), int(p(n, "h"))
		val := f32(p(n, "value"))
		for y in max(ry, 0) ..< min(ry + rh, h) do for x in max(rx, 0) ..< min(rx + rw, w) do out.v[y * w + x] = val
	case .Threshold:
		src := gen_input(ev, n, 0) or_return
		t := f32(p(n, "value"))
		inv := p(n, "invert") != 0
		for v, i in src.v do out.v[i] = 1 if (v >= t) != inv else 0
	case .Invert:
		src := gen_input(ev, n, 0) or_return
		for v, i in src.v do out.v[i] = 1 - v
	case .Remap:
		src := gen_input(ev, n, 0) or_return
		a0, a1, b0, b1 := f32(p(n, "from_min")), f32(p(n, "from_max")), f32(p(n, "to_min")), f32(p(n, "to_max"))
		span := a1 - a0 if a1 != a0 else 1
		for v, i in src.v do out.v[i] = b0 + clamp((v - a0) / span, 0, 1) * (b1 - b0)
	case .Blur:
		src := gen_input(ev, n, 0) or_return
		r := clamp(int(p(n, "radius")), 0, 32)
		for y in 0 ..< h do for x in 0 ..< w {
			sum, cnt: f32 = 0, 0
			for yy in max(y - r, 0) ..= min(y + r, h - 1) do for xx in max(x - r, 0) ..= min(x + r, w - 1) {
				sum += src.v[yy * w + xx]
				cnt += 1
			}
			out.v[y * w + x] = sum / cnt
		}
	case .Cellular:
		src := gen_input(ev, n, 0) or_return
		birth, survive := int(p(n, "birth")), int(p(n, "survive"))
		edge := p(n, "edge_solid") != 0
		cur := gen_new(ev)
		for v, i in src.v do cur.v[i] = 1 if v >= 0.5 else 0
		for _ in 0 ..< clamp(int(p(n, "iterations")), 0, 64) {
			for y in 0 ..< h do for x in 0 ..< w {
				count := 0
				for dy in -1 ..= 1 do for dx in -1 ..= 1 {
					if dx == 0 && dy == 0 do continue
					xx, yy := x + dx, y + dy
					if xx < 0 || yy < 0 || xx >= w || yy >= h {
						if edge do count += 1
					} else if cur.v[yy * w + xx] >= 0.5 {
						count += 1
					}
				}
				solid := cur.v[y * w + x] >= 0.5
				out.v[y * w + x] = 1 if (solid && count >= survive) || (!solid && count >= birth) else 0
			}
			copy(cur.v, out.v)
		}
		copy(out.v, cur.v)
	case .Dilate, .Erode:
		src := gen_input(ev, n, 0) or_return
		copy(out.v, src.v)
		cur := gen_new(ev)
		grow := n.kind == .Dilate
		for _ in 0 ..< clamp(int(p(n, "iterations")), 0, 64) {
			copy(cur.v, out.v)
			for y in 0 ..< h do for x in 0 ..< w {
				v := cur.v[y * w + x]
				for d in ([4][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) {
					xx, yy := x + d.x, y + d.y
					if xx < 0 || yy < 0 || xx >= w || yy >= h do continue
					nv := cur.v[yy * w + xx]
					v = max(v, nv) if grow else min(v, nv)
				}
				out.v[y * w + x] = v
			}
		}
	case .Combine:
		a := gen_input(ev, n, 0) or_return
		b := gen_input(ev, n, 1) or_return
		op := int(p(n, "op"))
		for i in 0 ..< len(out.v) {
			x, y := a.v[i], b.v[i]
			switch op {
			case 1: out.v[i] = x - y
			case 2: out.v[i] = x * y
			case 3: out.v[i] = min(x, y)
			case 4: out.v[i] = max(x, y)
			case 5: out.v[i] = x if y >= 0.5 else 0
			case 6: out.v[i] = (x + y) * 0.5
			case: out.v[i] = x + y
			}
		}
	case .Tile_Output:
		src := gen_input(ev, n, 0) or_return
		copy(out.v, src.v) // (the tiles come from Gen_Tiles: its grid is its input's)
	}
	ev.done[id] = out
	return out, true
}

// Gen_Tiles turns a Tile_Output node's grid into tile indices (row-major;
// -1 = empty): the first rule whose range holds the value, one of its
// tiles picked by a hash of the cell and the seed.
Gen_Tiles :: proc(g: ^Gen_Graph, outputId := 0, seed: u64 = 0, allocator := context.allocator) -> (tiles: []i32, size: [2]int, err: string) {
	out := Gen_OutputNode(g) if outputId == 0 else Gen_FindNode(g, outputId)
	if out == nil do return nil, {}, "the graph has no nodes"
	if out.kind != .Tile_Output do return nil, {}, fmt.tprintf("node %d isn't a tile output", out.id)
	grid, e := Gen_Evaluate(g, out.id, seed, context.temp_allocator)
	if e != "" do return nil, {}, e
	s := seed if seed != 0 else g.seed
	pickSeed := gen_mix(gen_mix(s, u64(out.id)), 0x7111e)
	empty := i32(Gen_Param(out, "empty"))
	tiles = make([]i32, len(grid.v), allocator)
	for v, i in grid.v {
		t := empty
		for r in out.rules {
			if v < r.min || v > r.max || len(r.tiles) == 0 do continue
			t = r.tiles[0] if len(r.tiles) == 1 else r.tiles[int(gen_hash01(i % grid.w, i / grid.w, pickSeed) * f32(len(r.tiles))) % len(r.tiles)]
			break
		}
		tiles[i] = t
	}
	return tiles, {grid.w, grid.h}, ""
}

// Gen_ApplyTileMap generates into a tile map: its map becomes the level's
// size and its cells the tiles (colliders rebuilt when it is Solid and in
// the game).
Gen_ApplyTileMap :: proc(g: ^Gen_Graph, tm: ^TileMapNode, seed: u64 = 0, ctx: ^GameContext = nil) -> string {
	tiles, size, err := Gen_Tiles(g, 0, seed, context.temp_allocator)
	if err != "" do return err
	tm.mapSize = size
	TileMapNode_Reset(tm)
	for t, i in tiles do if t >= 0 do TileMapNode_Set(tm, i % size.x, i / size.x, t)
	TileMapNode_Changed(tm)
	if tm.solid && tm.isReady && ctx != nil do TileMapNode_BuildColliders(tm, ctx)
	return ""
}

// Gen_LoadFile reads a project's .levelgen.json.
Gen_LoadFile :: proc(ctx: ^GameContext, path: string, allocator := context.allocator) -> (Gen_Graph, string) {
	if ctx == nil || ctx.game == nil do return {}, "no game"
	text, ok := AssetManager_ReadFileString(&ctx.game.assetManager, path, context.temp_allocator)
	if !ok do return {}, fmt.tprintf("no file %s", path)
	g, err := Gen_GraphParse(transmute([]u8)text, allocator)
	if err != "" {
		Gen_GraphDestroy(&g)
		return {}, fmt.tprintf("%s: %s", path, err)
	}
	return g, ""
}

// --- deterministic noise --------------------------------------------------------------

@(private = "file")
gen_mix :: proc(a, b: u64) -> u64 {
	// splitmix64 of a combination: stable on every platform.
	z := a ~ (b + 0x9e3779b97f4a7c15 + (a << 6) + (a >> 2))
	z = (z ~ (z >> 30)) * 0xbf58476d1ce4e5b9
	z = (z ~ (z >> 27)) * 0x94d049bb133111eb
	return z ~ (z >> 31)
}

// gen_hash01: a cell's random number in [0, 1) for a seed.
@(private = "file")
gen_hash01 :: proc(x, y: int, seed: u64) -> f32 {
	h := gen_mix(gen_mix(seed, u64(i64(x))), u64(i64(y)) + 0x51ed27)
	return f32(h >> 40) / f32(1 << 24)
}

@(private = "file")
gen_value_noise :: proc(x, y: f32, seed: u64) -> f32 {
	x0, y0 := math.floor(x), math.floor(y)
	fx, fy := x - x0, y - y0
	ix, iy := int(x0), int(y0)
	sx, sy := fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
	a := gen_hash01(ix, iy, seed)
	b := gen_hash01(ix + 1, iy, seed)
	c := gen_hash01(ix, iy + 1, seed)
	d := gen_hash01(ix + 1, iy + 1, seed)
	return math.lerp(math.lerp(a, b, sx), math.lerp(c, d, sx), sy)
}

// --- Lua: LevelGen ------------------------------------------------------------------------
// LevelGen.generate(generator, tilemap [, seed]) -> true | false, why
// LevelGen.values(generator [, seed [, node_id]]) -> {width, height, values = {row-major}} | nil, why

@(private = "file")
lua_levelgen_generate :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sm := get_script_manager(L)
	tmNode, isNode := to_node_userdata(L, 2)
	fail :: proc(L: ^lua.State, why: string) -> c.int {
		lua.pushboolean(L, false)
		lua.pushstring(L, strings.clone_to_cstring(why, context.temp_allocator))
		return 2
	}
	if sm == nil || sm.game == nil || lua.type(L, 1) != .STRING do return fail(L, "usage: LevelGen.generate(\"levels/caves.levelgen.json\", tilemap [, seed])")
	if !isNode || tmNode.typeId != TileMapNode do return fail(L, "the second argument isn't a TileMap node")
	seed := u64(lua.tointeger(L, 3)) if lua.type(L, 3) == .NUMBER else 0
	g, err := Gen_LoadFile(&sm.game.gameContext, string(lua.tostring(L, 1)), context.temp_allocator)
	if err != "" do return fail(L, err)
	defer Gen_GraphDestroy(&g)
	if e := Gen_ApplyTileMap(&g, cast(^TileMapNode)tmNode, seed, &sm.game.gameContext); e != "" do return fail(L, e)
	EventBus_Publish(&sm.game.events, "level_generated", tmNode.name, tmNode)
	lua.pushboolean(L, true)
	return 1
}

@(private = "file")
lua_levelgen_values :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	sm := get_script_manager(L)
	if sm == nil || sm.game == nil || lua.type(L, 1) != .STRING {
		lua.pushnil(L)
		lua.pushstring(L, "usage: LevelGen.values(\"levels/caves.levelgen.json\" [, seed [, node_id]])")
		return 2
	}
	seed := u64(lua.tointeger(L, 2)) if lua.type(L, 2) == .NUMBER else 0
	id := int(lua.tointeger(L, 3)) if lua.type(L, 3) == .NUMBER else 0
	g, err := Gen_LoadFile(&sm.game.gameContext, string(lua.tostring(L, 1)), context.temp_allocator)
	defer Gen_GraphDestroy(&g)
	grid: Gen_Grid
	if err == "" do grid, err = Gen_Evaluate(&g, id, seed, context.temp_allocator)
	if err != "" {
		lua.pushnil(L)
		lua.pushstring(L, strings.clone_to_cstring(err, context.temp_allocator))
		return 2
	}
	lua.createtable(L, 0, 3)
	lua.pushinteger(L, lua.Integer(grid.w))
	lua.setfield(L, -2, "width")
	lua.pushinteger(L, lua.Integer(grid.h))
	lua.setfield(L, -2, "height")
	lua.createtable(L, c.int(len(grid.v)), 0)
	for v, i in grid.v {
		lua.pushnumber(L, lua.Number(v))
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}
	lua.setfield(L, -2, "values")
	return 1
}

// Script_RegisterLevelGenModule creates the global LevelGen table.
Script_RegisterLevelGenModule :: proc(L: ^lua.State) {
	lua.newtable(L)
	lua.pushcfunction(L, lua_levelgen_generate)
	lua.setfield(L, -2, "generate")
	lua.pushcfunction(L, lua_levelgen_values)
	lua.setfield(L, -2, "values")
	lua.setglobal(L, "LevelGen")
}
