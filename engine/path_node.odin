package engine

import "base:runtime"
import "core:c"
import "core:hash"
import "core:math"
import "core:mem"
import "core:strings"
import lua "lua54"
import rl "vendor:raylib"

// ============================================================================
// PathNode: a curve through points (each with Bézier handles), edited in the
// viewport; PathFollowNode: a child that travels along its parent path
// (moving platforms, patrol routes, rails, camera tracks).
//
// - Points are local to the path; a point's `in` / `out` handles are
//   offsets from it (zero = a sharp corner). `closed` joins the last point
//   to the first.
// - The curve is baked into a polyline (a point every `bakeInterval` px,
//   with the cumulative length) the first time it is asked for after an
//   edit: sampling by distance is a binary search, cheap enough for many
//   followers. The bake is kept in heap buffers (freed with the node) and
//   redone only when the points change (a hash of them).
// - A follower's `progress` is the distance along the path (px); `speed`
//   moves it every frame (0 = scripts move it); at the end it stops, loops
//   or ping-pongs, and can face the way it moves.
// ============================================================================

Path_Point :: struct {
	pos:  [2]f32,
	in_:  [2]f32, // handle towards the previous point (offset from pos)
	out:  [2]f32, // handle towards the next point
}

PathNode :: struct {
	using node: Node,
	points:       [dynamic]Path_Point, // local to the node (node arena)
	closed:       bool `gui:"true"`,
	bakeInterval: f32 `gui:"true" min:"1" max:"64"`,  // px between baked samples
	lineWidth:    f32 `gui:"true" min:"0" max:"64"`,  // drawn in the game when > 0 (rails, ropes); 0 = invisible
	color:        rl.Color `gui:"true"`,
	// The bake (heap; path_bake).
	baked:     [dynamic][2]f32, // local polyline
	bakedLen:  [dynamic]f32,    // cumulative length at each baked point
	bakedHash: u64,
	bakeAlloc: runtime.Allocator,
}

PathNode_Create :: proc(scene: ^Scene, name: string = "Path", parent: ^Node = nil) -> ^PathNode {
	p := CreateNode(scene.manager, PathNode)
	p.name = strings.clone(name, p.allocator)
	p.points = make([dynamic]Path_Point, p.allocator)
	append(&p.points, Path_Point{pos = {-100, 0}, out = {50, -60}}, Path_Point{pos = {100, 0}, in_ = {-50, -60}})
	p.bakeInterval = 6
	p.color = {125, 211, 252, 255}
	p.bakeAlloc = context.allocator
	p.render = PathNode_Render
	p.onDestroy = PathNode_Destroy
	scene->addNode(p, parent)
	return p
}

PathNode_Destroy :: proc(node: ^Node, ctx: ^GameContext) {
	p := cast(^PathNode)node
	delete(p.baked)
	delete(p.bakedLen)
}

// path_hash: what the bake depends on.
@(private = "file")
path_hash :: proc(p: ^PathNode) -> u64 {
	h := hash.fnv64a(mem.slice_to_bytes(p.points[:]))
	extra := [2]f32{p.bakeInterval, 1 if p.closed else 0}
	return h ~ hash.fnv64a(mem.slice_to_bytes(extra[:]))
}

// bezier: the point at t on a cubic segment.
@(private = "file")
bezier :: #force_inline proc(p0, c0, c1, p1: [2]f32, t: f32) -> [2]f32 {
	u := 1 - t
	return u * u * u * p0 + 3 * u * u * t * c0 + 3 * u * t * t * c1 + t * t * t * p1
}

// PathNode_Bake rebuilds the polyline if the points changed.
PathNode_Bake :: proc(p: ^PathNode) {
	h := path_hash(p)
	if h == p.bakedHash && len(p.baked) > 0 do return
	p.bakedHash = h
	if p.bakeAlloc.procedure == nil do p.bakeAlloc = context.allocator
	if p.baked.allocator.procedure == nil {
		p.baked = make([dynamic][2]f32, p.bakeAlloc)
		p.bakedLen = make([dynamic]f32, p.bakeAlloc)
	}
	clear(&p.baked)
	clear(&p.bakedLen)
	n := len(p.points)
	if n == 0 do return
	append(&p.baked, p.points[0].pos)
	append(&p.bakedLen, 0)
	segs := n if p.closed && n > 1 else n - 1
	interval := max(p.bakeInterval, 0.5)
	total: f32 = 0
	for i in 0 ..< segs {
		a, b := p.points[i], p.points[(i + 1) % n]
		p0, c0, c1, p1 := a.pos, a.pos + a.out, b.pos + b.in_, b.pos
		approx := linalg_len(c0 - p0) + linalg_len(c1 - c0) + linalg_len(p1 - c1)
		steps := max(1, int(math.ceil(approx / interval)))
		prev := p0
		for s in 1 ..= steps {
			q := bezier(p0, c0, c1, p1, f32(s) / f32(steps))
			total += linalg_len(q - prev)
			append(&p.baked, q)
			append(&p.bakedLen, total)
			prev = q
		}
	}
}

@(private = "file")
linalg_len :: #force_inline proc(v: [2]f32) -> f32 {return math.sqrt(v.x * v.x + v.y * v.y)}

// PathNode_Length: the curve's length (px, local units).
PathNode_Length :: proc(p: ^PathNode) -> f32 {
	PathNode_Bake(p)
	return p.bakedLen[len(p.bakedLen) - 1] if len(p.bakedLen) > 0 else 0
}

// PathNode_SampleLocal: the point at `dist` along the curve (clamped) and
// the direction it goes there (unit), local to the path.
PathNode_SampleLocal :: proc(p: ^PathNode, dist: f32) -> (pos, dir: [2]f32) {
	PathNode_Bake(p)
	n := len(p.baked)
	if n == 0 do return {}, {1, 0}
	if n == 1 do return p.baked[0], {1, 0}
	d := clamp(dist, 0, p.bakedLen[n - 1])
	// The baked segment holding d (binary search on the lengths).
	lo, hi := 0, n - 1
	for hi - lo > 1 {
		mid := (lo + hi) / 2
		if p.bakedLen[mid] <= d do lo = mid
		else do hi = mid
	}
	seg := p.bakedLen[hi] - p.bakedLen[lo]
	t := (d - p.bakedLen[lo]) / seg if seg > 0 else 0
	a, b := p.baked[lo], p.baked[hi]
	pos = a + (b - a) * t
	l := linalg_len(b - a)
	dir = (b - a) / l if l > 0 else {1, 0}
	return
}

// PathNode_ToWorld: a local point of the path in world space.
PathNode_ToWorld :: proc(p: ^PathNode, local: [2]f32) -> [2]f32 {
	return p.globalPosition + rotate_vec(local * p.globalScale, p.globalRotation)
}

// PathNode_ClosestOffset: the distance along the curve of the point
// nearest to a world position.
PathNode_ClosestOffset :: proc(p: ^PathNode, world: [2]f32) -> f32 {
	PathNode_Bake(p)
	if len(p.baked) < 2 do return 0
	// Into the path's local space.
	s := p.globalScale
	local := rotate_vec(world - p.globalPosition, -p.globalRotation)
	local = {local.x / s.x if s.x != 0 else local.x, local.y / s.y if s.y != 0 else local.y}
	best, bestD := f32(0), max(f32)
	for i in 0 ..< len(p.baked) - 1 {
		a, b := p.baked[i], p.baked[i + 1]
		ab := b - a
		ll := ab.x * ab.x + ab.y * ab.y
		t := clamp(((local.x - a.x) * ab.x + (local.y - a.y) * ab.y) / ll, 0, 1) if ll > 0 else 0
		q := a + ab * t
		d := (local.x - q.x) * (local.x - q.x) + (local.y - q.y) * (local.y - q.y)
		if d < bestD {
			bestD = d
			best = p.bakedLen[i] + (p.bakedLen[i + 1] - p.bakedLen[i]) * t
		}
	}
	return best
}

PathNode_Render :: proc(node: ^Node, ctx: ^GameContext, dt: f32) {
	p := cast(^PathNode)node
	if p.lineWidth <= 0 do return
	PathNode_Bake(p)
	for i in 0 ..< len(p.baked) - 1 {
		rl.DrawLineEx(PathNode_ToWorld(p, p.baked[i]), PathNode_ToWorld(p, p.baked[i + 1]), p.lineWidth, p.color)
	}
}

// --- PathFollowNode --------------------------------------------------------------------

Path_Loop :: enum u8 {
	Stop,     // stays at the end ("path_finished")
	Loop,     // back to the start (or round a closed path)
	PingPong, // turns around at each end
}

PathFollowNode :: struct {
	using node: Node,
	progress:     f32 `gui:"true" min:"0" max:"10000"`, // px along the parent path
	speed:        f32 `gui:"true" min:"-2000" max:"2000"`, // px/s (0: scripts move it)
	loop:         Path_Loop `gui:"true"`,
	rotate:       bool `gui:"true"`, // face the way it travels
	sideOffset:   f32 `gui:"true" min:"-500" max:"500"`, // px to the side of the path (right of travel)
	direction:    f32, // runtime: 1 or -1 (ping-pong)
	finished:     bool,
	onFinished:   EventSubject, // "path_finished": reached the end (Stop)
	onLooped:     EventSubject, // "path_looped": wrapped round or turned (Loop / PingPong)
}

PathFollowNode_Create :: proc(scene: ^Scene, name: string = "PathFollow", parent: ^Node = nil) -> ^PathFollowNode {
	f := CreateNode(scene.manager, PathFollowNode)
	f.name = strings.clone(name, f.allocator)
	f.direction = 1
	f.rotate = true
	f.update = PathFollowNode_Update
	f.onDestroy = PathFollowNode_Destroy
	InitializeSubject(&f.onFinished, "path_finished", f)
	InitializeSubject(&f.onLooped, "path_looped", f)
	scene->addNode(f, parent)
	return f
}

PathFollowNode_Destroy :: proc(node: ^Node, ctx: ^GameContext) {
	f := cast(^PathFollowNode)node
	DestroySubject(&f.onFinished)
	DestroySubject(&f.onLooped)
}

// PathFollowNode_Path: the PathNode it follows (its parent), or nil.
PathFollowNode_Path :: proc(f: ^PathFollowNode, m: ^NodeManager) -> ^PathNode {
	if m == nil do return nil
	if p := GetParent(m, f); p != nil && p.typeId == PathNode do return cast(^PathNode)p
	return nil
}

PathFollowNode_Update :: proc(node: ^Node, ctx: ^GameContext, dt: f32) {
	f := cast(^PathFollowNode)node
	m := ctx.scene.manager if ctx != nil && ctx.scene != nil else nil
	path := PathFollowNode_Path(f, m)
	if path == nil do return
	if f.direction == 0 do f.direction = 1
	length := PathNode_Length(path)
	if f.speed != 0 && length > 0 && !f.finished {
		f.progress += f.speed * f.direction * dt
		switch f.loop {
		case .Stop:
			if f.progress >= length || f.progress <= 0 {
				f.progress = clamp(f.progress, 0, length)
				f.finished = true
				f.onFinished->notify(f, nil, ctx)
			}
		case .Loop:
			if f.progress >= length || f.progress < 0 {
				f.progress = math.mod(f.progress, length)
				if f.progress < 0 do f.progress += length
				f.onLooped->notify(f, nil, ctx)
			}
		case .PingPong:
			if f.progress >= length {
				f.progress = length - (f.progress - length)
				f.direction = -f.direction
				f.onLooped->notify(f, nil, ctx)
			} else if f.progress <= 0 {
				f.progress = -f.progress
				f.direction = -f.direction
				f.onLooped->notify(f, nil, ctx)
			}
		}
	}
	PathFollowNode_Place(f, path)
}

// PathFollowNode_Place puts the follower at its progress (local to the path).
PathFollowNode_Place :: proc(f: ^PathFollowNode, path: ^PathNode) {
	pos, dir := PathNode_SampleLocal(path, f.progress)
	travel := dir * (f.direction if f.speed >= 0 else -f.direction)
	side := [2]f32{-dir.y, dir.x} * f.sideOffset
	f.position = pos + side
	if f.rotate do f.rotation = math.atan2(travel.y, travel.x) * math.DEG_PER_RAD
}

// --- Lua -------------------------------------------------------------------------------
// path:path_length() -> px
// path:path_point_at(distance) -> Vec2 (world), Vec2 (direction, world)
// path:path_closest_offset(x, y | Vec2) -> distance along the path
// path:path_point_count() / path:path_get_point(i) -> pos, in, out (local Vec2s; 1-based)
// path:path_set_point(i, pos [, in, out]) / path:path_add_point(pos [, in, out]) / path:path_remove_point(i) / path:path_clear()
// follow:follow_ratio() -> 0..1 / follow:follow_set_ratio(r) / follow:follow_restart()

@(private = "file")
lua_path_arg :: proc(L: ^lua.State) -> ^PathNode {
	n, ok := to_node_userdata(L, 1)
	if !ok || n.typeId != PathNode do return nil
	return cast(^PathNode)n
}

@(private = "file")
lua_vec_arg :: proc(L: ^lua.State, idx: c.int) -> [2]f32 {
	x, y := arg_xy(L, idx)
	return {x, y}
}

@(private = "file")
lua_path_length :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	p := lua_path_arg(L)
	lua.pushnumber(L, lua.Number(PathNode_Length(p) if p != nil else 0))
	return 1
}

@(private = "file")
lua_path_point_at :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	p := lua_path_arg(L)
	if p == nil do return 0
	pos, dir := PathNode_SampleLocal(p, f32(lua.tonumber(L, 2)))
	Lua_PushVec2(L, PathNode_ToWorld(p, pos))
	Lua_PushVec2(L, rotate_vec(dir, p.globalRotation))
	return 2
}

@(private = "file")
lua_path_closest_offset :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	p := lua_path_arg(L)
	lua.pushnumber(L, lua.Number(PathNode_ClosestOffset(p, lua_vec_arg(L, 2)) if p != nil else 0))
	return 1
}

@(private = "file")
lua_path_point_count :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	p := lua_path_arg(L)
	lua.pushinteger(L, lua.Integer(len(p.points) if p != nil else 0))
	return 1
}

@(private = "file")
lua_path_get_point :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	p := lua_path_arg(L)
	i := int(lua.tointeger(L, 2)) - 1
	if p == nil || i < 0 || i >= len(p.points) do return 0
	Lua_PushVec2(L, p.points[i].pos)
	Lua_PushVec2(L, p.points[i].in_)
	Lua_PushVec2(L, p.points[i].out)
	return 3
}

// lua_path_point_from: pos [, in, out] from the stack at idx.
@(private = "file")
lua_path_point_from :: proc(L: ^lua.State, idx: c.int, old: Path_Point = {}) -> Path_Point {
	pt := old
	pt.pos = lua_vec_arg(L, idx)
	if !lua.isnoneornil(L, idx + 1) do pt.in_ = lua_vec_arg(L, idx + 1)
	if !lua.isnoneornil(L, idx + 2) do pt.out = lua_vec_arg(L, idx + 2)
	return pt
}

@(private = "file")
lua_path_set_point :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	p := lua_path_arg(L)
	i := int(lua.tointeger(L, 2)) - 1
	if p == nil || i < 0 || i >= len(p.points) do return 0
	p.points[i] = lua_path_point_from(L, 3, p.points[i])
	return 0
}

@(private = "file")
lua_path_add_point :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	p := lua_path_arg(L)
	if p == nil do return 0
	append(&p.points, lua_path_point_from(L, 2))
	return 0
}

@(private = "file")
lua_path_remove_point :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	p := lua_path_arg(L)
	i := int(lua.tointeger(L, 2)) - 1
	if p != nil && i >= 0 && i < len(p.points) do ordered_remove(&p.points, i)
	return 0
}

@(private = "file")
lua_path_clear :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if p := lua_path_arg(L); p != nil do clear(&p.points)
	return 0
}

@(private = "file")
lua_follow_arg :: proc(L: ^lua.State) -> (^PathFollowNode, ^PathNode) {
	n, ok := to_node_userdata(L, 1)
	if !ok || n.typeId != PathFollowNode do return nil, nil
	f := cast(^PathFollowNode)n
	sm := get_script_manager(L)
	m := sm.game.sceneManager.currentScene.manager if sm != nil && sm.game != nil && sm.game.sceneManager.currentScene != nil else nil
	return f, PathFollowNode_Path(f, m)
}

@(private = "file")
lua_follow_ratio :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	f, p := lua_follow_arg(L)
	l := PathNode_Length(p) if p != nil else 0
	lua.pushnumber(L, lua.Number(f.progress / l if f != nil && l > 0 else 0))
	return 1
}

@(private = "file")
lua_follow_set_ratio :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	f, p := lua_follow_arg(L)
	if f == nil || p == nil do return 0
	f.progress = clamp(f32(lua.tonumber(L, 2)), 0, 1) * PathNode_Length(p)
	PathFollowNode_Place(f, p)
	return 0
}

@(private = "file")
lua_follow_restart :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	f, p := lua_follow_arg(L)
	if f == nil do return 0
	f.progress, f.direction, f.finished = 0, 1, false
	if p != nil do PathFollowNode_Place(f, p)
	return 0
}

// Script_RegisterPathBindings adds the path / follow methods to the node
// metatable (on the stack).
Script_RegisterPathBindings :: proc(L: ^lua.State) {
	reg :: proc(L: ^lua.State, name: cstring, fn: lua.CFunction) {
		lua.pushcfunction(L, fn)
		lua.setfield(L, -2, name)
	}
	reg(L, "path_length", lua_path_length)
	reg(L, "path_point_at", lua_path_point_at)
	reg(L, "path_closest_offset", lua_path_closest_offset)
	reg(L, "path_point_count", lua_path_point_count)
	reg(L, "path_get_point", lua_path_get_point)
	reg(L, "path_set_point", lua_path_set_point)
	reg(L, "path_add_point", lua_path_add_point)
	reg(L, "path_remove_point", lua_path_remove_point)
	reg(L, "path_clear", lua_path_clear)
	reg(L, "follow_ratio", lua_follow_ratio)
	reg(L, "follow_set_ratio", lua_follow_set_ratio)
	reg(L, "follow_restart", lua_follow_restart)
}
