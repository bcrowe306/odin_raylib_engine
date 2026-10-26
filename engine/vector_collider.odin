package engine

import "core:c"
import "core:hash"
import "core:math"
import "core:mem"
import lua "lua54"
import b2 "vendor:box2d"
import rl "vendor:raylib"

// ============================================================================
// Collision from vector shapes (Phase 14 V.16), carving and path queries.
//
// A Vector Shape with a `collider` gives a physics body its own shape: what
// the art covers (fills and stroke outlines: vector_ops.odin), simplified
// to colliderDetail, then
//   Solid    convex pieces (earcut triangles merged into convex polygons of
//            at most 8 corners: Hertel-Mehlhorn) - for anything, dynamic too
//   Outline  edge loops round the area (Box2D chains: smooth sliding along
//            terrain; solid from outside, for static ground)
// on the nearest Static / Dynamic Body or Area above it (collision events
// go to that body), or on a static body of its own when there's none.
// Regenerated when the art changes (a new file, a frame, a morph, a cut)
// or the node moves relative to its body; drawn as an overlay with the
// physics debug view.
//
// Carving (destructible art): vector_cut removes a circle or a polygon from
// the drawing - every shape keeps its paint - and the collider follows.
//
// Path queries: the drawing's paths flattened and measured one after
// another (polyline.odin, shared with PathNode): length, the point and
// direction at a distance, the closest point; a Path Follow can ride them.
// ============================================================================

Vector_Collider :: enum u8 {
	None,
	Solid,   // convex pieces: bodies of any kind
	Outline, // edge loops round the outline: terrain (static bodies)
}

// The node's collision geometry and what Box2D holds of it.
Vector_Collision :: struct {
	key:     u64,             // what the geometry was made from
	area:    Vector_Polys,    // the simplified area (node space)
	pieces:  [dynamic][2]f32, // Solid: convex polygons, one after another (node space)
	counts:  [dynamic]int,    // corners of each piece
	// Box2D.
	shapes:    [dynamic]b2.ShapeId,
	chains:    [dynamic]b2.ChainId,
	attachKey: u64,
	body:      b2.BodyId, // where they are (the target body's or its own)
	ownBody:   b2.BodyId, // its own static body (no body above it)
	ownPos:    [2]f32,
	ownRot:    f32,
	built:     int,       // times the geometry was made (tests)
	attached:  int,       // times attached to Box2D (tests)
	// Path queries.
	lineKey: u64,
	line:    Polyline,
	// Point queries: the exact area (node space).
	hitKey:  u64,
	hitArea: Vector_Polys,
}

Vector_Collision_Destroy :: proc(c: ^Vector_Collision) {
	vector_collider_detach(c)
	if b2.Body_IsValid(c.ownBody) do b2.DestroyBody(c.ownBody)
	Vector_Polys_Destroy(&c.area)
	delete(c.pieces)
	delete(c.counts)
	delete(c.shapes)
	delete(c.chains)
	Polyline_Destroy(&c.line)
	Vector_Polys_Destroy(&c.hitArea)
	c^ = {}
}

@(private = "file")
vector_collider_detach :: proc(c: ^Vector_Collision) {
	for id in c.shapes do if b2.Shape_IsValid(id) do b2.DestroyShape(id, true)
	for id in c.chains do if b2.Chain_IsValid(id) do b2.DestroyChain(id)
	clear(&c.shapes)
	clear(&c.chains)
	c.attachKey = 0
}

// --- convex decomposition --------------------------------------------------------------

// Vector_ConvexDecompose splits an area (outer rings with holes) into convex
// polygons of at most maxCorners corners, appended to pieces / counts:
// earcut triangles, then neighbours merged across their longest shared
// edges while the union stays convex (Hertel-Mehlhorn).
Vector_ConvexDecompose :: proc(p: ^Vector_Polys, maxCorners: int, pieces: ^[dynamic][2]f32, counts: ^[dynamic]int) {
	ec: Earcut
	defer Earcut_Destroy(&ec)
	coords := make([dynamic][2]f32, context.temp_allocator)
	holes := make([dynamic]int, context.temp_allocator)
	tri := make([dynamic]u32, context.temp_allocator)
	for r, i in p.rings {
		if r.parent >= 0 do continue
		clear(&coords); clear(&holes); clear(&tri)
		append(&coords, ..Vector_Polys_Ring(p, i))
		for h, j in p.rings do if h.parent == i {
			append(&holes, len(coords))
			append(&coords, ..Vector_Polys_Ring(p, j))
		}
		if !Earcut_Triangulate(&ec, coords[:], holes[:], &tri) do continue
		merge_convex(coords[:], tri[:], max(maxCorners, 3), pieces, counts)
	}
}

@(private = "file")
cross2 :: #force_inline proc(o, a, b: [2]f32) -> f32 {return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)}

@(private = "file")
merge_convex :: proc(coords: [][2]f32, tri: []u32, maxCorners: int, pieces: ^[dynamic][2]f32, counts: ^[dynamic]int) {
	// Polygons as index lists, all wound the same way (positive area).
	polys := make([dynamic][dynamic]u32, context.temp_allocator)
	for t := 0; t + 2 < len(tri); t += 3 {
		a, b, cc := tri[t], tri[t + 1], tri[t + 2]
		ar := cross2(coords[a], coords[b], coords[cc])
		if abs(ar) < 1e-6 do continue // (slivers)
		poly := make([dynamic]u32, context.temp_allocator)
		if ar > 0 do append(&poly, a, b, cc)
		else do append(&poly, a, cc, b)
		append(&polys, poly)
	}
	alive := make([]bool, len(polys), context.temp_allocator)
	for &a in alive do a = true
	// Directed edge -> polygon.
	ekey :: proc(a, b: u32) -> u64 {return u64(a) << 32 | u64(b)}
	owner := make(map[u64]int, allocator = context.temp_allocator)
	for poly, i in polys do for k in 0 ..< len(poly) do owner[ekey(poly[k], poly[(k + 1) % len(poly)])] = i
	// Shared edges, longest first.
	Edge :: struct {a, b: u32, l: f32}
	edges := make([dynamic]Edge, context.temp_allocator)
	for poly in polys do for k in 0 ..< len(poly) {
		a, b := poly[k], poly[(k + 1) % len(poly)]
		if a < b && ekey(b, a) in owner {
			d := coords[a] - coords[b]
			append(&edges, Edge{a, b, d.x * d.x + d.y * d.y})
		}
	}
	for i in 1 ..< len(edges) {
		e := edges[i]
		j := i - 1
		for j >= 0 && edges[j].l < e.l {edges[j + 1] = edges[j]; j -= 1}
		edges[j + 1] = e
	}
	for e in edges {
		pi, okp := owner[ekey(e.a, e.b)]
		qi, okq := owner[ekey(e.b, e.a)]
		if !okp || !okq || pi == qi || !alive[pi] || !alive[qi] do continue
		P, Q := polys[pi], polys[qi]
		if len(P) + len(Q) - 2 > maxCorners do continue
		// P has a -> b, Q has b -> a: walk P from b round to a, then Q's
		// corners strictly between a and b.
		ip, iq := -1, -1
		for v, k in P do if v == e.b {ip = k; break}
		for v, k in Q do if v == e.a {iq = k; break}
		if ip < 0 || iq < 0 do continue
		merged := make([dynamic]u32, 0, len(P) + len(Q) - 2, context.temp_allocator)
		for k in 0 ..< len(P) do append(&merged, P[(ip + k) % len(P)]) // b ... a
		for k in 1 ..< len(Q) - 1 do append(&merged, Q[(iq + k) % len(Q)]) // after a, up to before b
		convex := true
		n := len(merged)
		for k in 0 ..< n {
			if cross2(coords[merged[k]], coords[merged[(k + 1) % n]], coords[merged[(k + 2) % n]]) < -1e-4 {convex = false; break}
		}
		if !convex do continue
		polys[pi] = merged
		alive[qi] = false
		for k in 0 ..< n do owner[ekey(merged[k], merged[(k + 1) % n])] = pi
		delete_key(&owner, ekey(e.a, e.b))
		delete_key(&owner, ekey(e.b, e.a))
	}
	for poly, i in polys {
		if !alive[i] do continue
		for v in poly do append(pieces, coords[v])
		append(counts, len(poly))
	}
}

// --- geometry ------------------------------------------------------------------------

// vector_collider_source: the shapes the node draws (its carved copy,
// trimmed / morphed shapes, a symbol / frame, the preset) and the offset
// from their space to the node's.
@(private = "file")
vector_collider_source :: proc(v: ^VectorShapeNode) -> (shapes: []Vector_Shape, offset: [2]f32, key: u64, ok: bool) {
	h: [6]u64
	if r := VectorShapeNode_Asset(v); r != nil {
		part, boxMin, boxSize, found := VectorShapeNode_Part(v, r)
		if !found do return
		offset = -boxMin - Node_OriginPx(v, boxSize)
		if VectorShapeNode_FxActive(v) && VectorShapeNode_SkinTarget(v) == nil || v.carving {
			shapes = VectorShapeNode_FxShapes(v)
		} else {
			shapes = Vector_PartShapes(r, part)
		}
		h = {u64(uintptr(r)), u64(r.version), u64(part + 2), 0, 0, 0}
	} else {
		if !v.built.ok || v.built.preset != v.preset || v.built.fill != v.fillColor || v.built.stroke != v.strokeColor || v.built.width != v.strokeWidth {
			VectorShapeNode_Build(v)
		}
		shapes = v.shapes[:]
		if VectorShapeNode_FxActive(v) && VectorShapeNode_SkinTarget(v) == nil || v.carving do shapes = VectorShapeNode_FxShapes(v)
		h = {0, u64(v.built.version), 0, 0, 0, 0}
	}
	fk := v.fxKey
	h[3] = hash.fnv64a(mem.ptr_to_bytes(&fk)) if VectorShapeNode_FxActive(v) || v.carving else 0
	h[4] = u64(v.carveVersion)
	o := offset
	h[5] = hash.fnv64a(mem.ptr_to_bytes(&o))
	return shapes, offset, hash.fnv64a(mem.slice_to_bytes(h[:])), true
}

// VectorShapeNode_ColliderGeometry makes (when out of date) the collision
// geometry in the node's space: the simplified area and, for Solid, its
// convex pieces. ok = false: nothing to collide with.
VectorShapeNode_ColliderGeometry :: proc(v: ^VectorShapeNode) -> (c: ^Vector_Collision, ok: bool) {
	c = &v.collision
	if v.collider == .None do return c, false
	shapes, offset, srcKey, found := vector_collider_source(v)
	if !found do return c, false
	detail := clamp(v.colliderDetail, 0.05, 64)
	k := [3]u64{srcKey, u64(v.collider), u64(transmute(u32)detail)}
	key := hash.fnv64a(mem.slice_to_bytes(k[:]))
	if key == c.key && c.built > 0 do return c, len(c.area.rings) > 0
	c.key = key
	c.built += 1
	context.allocator = Engine_HeapAllocator()
	if c.area.pts == nil {
		c.area.pts = make([dynamic][2]f32)
		c.area.rings = make([dynamic]Vector_Ring)
		c.pieces = make([dynamic][2]f32)
		c.counts = make([dynamic]int)
		c.shapes = make([dynamic]b2.ShapeId)
		c.chains = make([dynamic]b2.ChainId)
	}
	Vector_Polys_Clear(&c.area)
	clear(&c.pieces)
	clear(&c.counts)
	raw: Vector_Polys
	raw.pts = make([dynamic][2]f32, context.temp_allocator)
	raw.rings = make([dynamic]Vector_Ring, context.temp_allocator)
	if !Vector_ShapesArea(shapes, detail * 0.25, &raw) do return c, false
	if !Vector_PolysSimplify(&raw, detail, &c.area) do return c, false
	for &q in c.area.pts do q += offset
	if v.collider == .Solid do Vector_ConvexDecompose(&c.area, int(b2.MAX_POLYGON_VERTICES), &c.pieces, &c.counts)
	return c, len(c.area.rings) > 0
}

// --- Box2D ---------------------------------------------------------------------------

// vector_collider_body: the body the collider joins - the nearest Static /
// Dynamic Body or Area above the node - and the node's transform into its
// shape space (scaled by the body's scale, like authored shapes).
@(private = "file")
vector_collider_body :: proc(v: ^VectorShapeNode) -> (owner: ^Node, body: b2.BodyId, toBody: Vector_Affine, found: bool) {
	m := VECTOR_AFFINE_IDENTITY
	for n: ^Node = v; n != nil; n = n.parent {
		if n != v {
			bid: b2.BodyId
			is_body := true
			switch {
			case n.typeId == StaticBodyNode: bid = (cast(^StaticBodyNode)n).bodyId
			case n.typeId == DynamicBodyNode: bid = (cast(^DynamicBodyNode)n).bodyId
			case n.typeId == AreaNode: bid = (cast(^AreaNode)n).bodyId
			case: is_body = false
			}
			if is_body {
				return n, bid, Vector_AffineMul(Vector_AffineTRS({}, 0, n.globalScale), m), true
			}
		}
		m = Vector_AffineMul(Vector_AffineTRS(n.position, n.rotation, n.scale), m)
	}
	return nil, {}, {}, false
}

// vector_collider_sync keeps the Box2D shapes in step (the game's update).
@(private = "file")
vector_collider_sync :: proc(v: ^VectorShapeNode, ctx: ^GameContext) {
	c := &v.collision
	geo, ok := VectorShapeNode_ColliderGeometry(v)
	if !ok || !v.enabled {
		vector_collider_detach(c)
		return
	}
	if ctx == nil || ctx.game == nil do return
	worldId := ctx.game.physicsWorld.worldId
	if !b2.World_IsValid(worldId) do return
	owner, body, toBody, hasOwner := vector_collider_body(v)
	userData := rawptr(owner)
	if !hasOwner {
		// Its own static body, following the node.
		if !b2.Body_IsValid(c.ownBody) {
			def := b2.DefaultBodyDef()
			def.type = .staticBody
			def.position = v.globalPosition
			def.rotation = DegreesToRot(v.globalRotation)
			def.userData = rawptr(cast(^Node)v)
			c.ownBody = b2.CreateBody(worldId, def)
			c.ownPos, c.ownRot = v.globalPosition, v.globalRotation
		} else if b2.Distance(v.globalPosition, c.ownPos) > 0.01 || abs(v.globalRotation - c.ownRot) > 0.01 {
			b2.Body_SetTransform(c.ownBody, v.globalPosition, DegreesToRot(v.globalRotation))
			c.ownPos, c.ownRot = v.globalPosition, v.globalRotation
		}
		body = c.ownBody
		toBody = Vector_AffineTRS({}, 0, v.globalScale)
		userData = rawptr(cast(^Node)v)
	} else if b2.Body_IsValid(c.ownBody) {
		b2.DestroyBody(c.ownBody)
		c.ownBody = {}
	}
	if !b2.Body_IsValid(body) do return // (the body isn't made yet: next frame)
	ak := struct {geo: u64, body: b2.BodyId, xf: Vector_Affine, fr, bo, de: f32, sensor: bool}{geo.key, body, toBody, v.colliderFriction, v.colliderBounce, v.colliderDensity, owner != nil && owner.typeId == AreaNode}
	attachKey := hash.fnv64a(mem.ptr_to_bytes(&ak))
	if attachKey == c.attachKey && c.body == body {
		// (Still there? A body re-made by its node drops our shapes.)
		live := len(c.shapes) + len(c.chains) > 0
		for id in c.shapes do if !b2.Shape_IsValid(id) {live = false; break}
		for id in c.chains do if !b2.Chain_IsValid(id) {live = false; break}
		if live do return
	}
	vector_collider_detach(c)
	c.attachKey = attachKey
	c.body = body
	c.attached += 1
	def := b2.DefaultShapeDef()
	def.userData = userData
	def.density = v.colliderDensity
	def.material.friction = v.colliderFriction
	def.material.restitution = v.colliderBounce
	def.isSensor = ak.sensor
	def.enableSensorEvents = true
	def.enableContactEvents = true
	def.filter = {categoryBits = CollisionLayerSet_ToBits(DEFAULT_COLLISION_CATEGORIES), maskBits = CollisionLayerSet_ToBits(DEFAULT_COLLISION_MASK)}
	mirrored := toBody[0] * toBody[3] - toBody[1] * toBody[2] < 0
	if v.collider == .Solid || ak.sensor {
		k := 0
		for n in geo.counts {
			pts := make([][2]f32, n, context.temp_allocator)
			for i in 0 ..< n do pts[i] = Vector_AffineApply(toBody, geo.pieces[k + i])
			k += n
			hull := b2.ComputeHull(pts)
			if hull.count < 3 || !b2.ValidateHull(hull) do continue
			append(&c.shapes, b2.CreatePolygonShape(body, def, b2.MakePolygon(hull, 0)))
		}
	} else {
		// Loops: solid on the right of travel in Box2D (outer rings wound so
		// their right is outside, holes the other way).
		for r, i in geo.area.rings {
			src := Vector_Polys_Ring(&geo.area, i)
			if len(src) < 3 do continue
			pts := make([][2]f32, len(src), context.temp_allocator)
			for q, j in src do pts[j] = Vector_AffineApply(toBody, q)
			want_positive := r.parent < 0
			if (Vector_SignedArea(pts) > 0) != want_positive {
				for j in 0 ..< len(pts) / 2 do pts[j], pts[len(pts) - 1 - j] = pts[len(pts) - 1 - j], pts[j]
			}
			_ = mirrored
			if len(pts) < 4 {
				hull := b2.ComputeHull(pts)
				if hull.count >= 3 && b2.ValidateHull(hull) do append(&c.shapes, b2.CreatePolygonShape(body, def, b2.MakePolygon(hull, 0)))
				continue
			}
			cdef := b2.DefaultChainDef()
			cdef.userData = userData
			cdef.points = raw_data(pts)
			cdef.count = i32(len(pts))
			cdef.isLoop = true
			cdef.filter = def.filter
			mat := b2.DefaultSurfaceMaterial()
			mat.friction, mat.restitution = v.colliderFriction, v.colliderBounce
			cdef.materials = &mat
			cdef.materialCount = 1
			cdef.enableSensorEvents = true
			append(&c.chains, b2.CreateChain(body, cdef))
		}
	}
	if b2.Body_GetType(body) == .dynamicBody do b2.Body_ApplyMassFromShapes(body)
}

// VectorShapeNode_Update: the collider (when it has one).
VectorShapeNode_Update :: proc(node: ^Node, ctx: ^GameContext, dt: f32) {
	v := cast(^VectorShapeNode)node
	if v.collider == .None && len(v.collision.shapes) + len(v.collision.chains) == 0 && !b2.Body_IsValid(v.collision.ownBody) do return
	if v.collider == .None {
		vector_collider_detach(&v.collision)
		if b2.Body_IsValid(v.collision.ownBody) {b2.DestroyBody(v.collision.ownBody); v.collision.ownBody = {}}
		return
	}
	vector_collider_sync(v, ctx)
}

// VectorShapeNode_DrawCollider: the collision geometry over the art (the
// physics debug view): convex pieces or the outline loops.
VectorShapeNode_DrawCollider :: proc(v: ^VectorShapeNode, color: rl.Color = {74, 222, 128, 255}) {
	c, ok := VectorShapeNode_ColliderGeometry(v)
	if !ok || !rl.IsWindowReady() do return
	xf := Vector_AffineTRS(v.globalPosition, v.globalRotation, v.globalScale)
	fill := rl.Color{color.r, color.g, color.b, 50}
	if v.collider == .Solid {
		k := 0
		for n in c.counts {
			p0 := Vector_AffineApply(xf, c.pieces[k])
			for i in 1 ..< n - 1 {
				// (Pieces are wound counter-clockwise on screen: raylib's front face.)
				rl.DrawTriangle(p0, Vector_AffineApply(xf, c.pieces[k + i + 1]), Vector_AffineApply(xf, c.pieces[k + i]), fill)
				rl.DrawTriangle(p0, Vector_AffineApply(xf, c.pieces[k + i]), Vector_AffineApply(xf, c.pieces[k + i + 1]), fill)
			}
			for i in 0 ..< n do rl.DrawLineV(Vector_AffineApply(xf, c.pieces[k + i]), Vector_AffineApply(xf, c.pieces[k + (i + 1) % n]), color)
			k += n
		}
		return
	}
	for _, i in c.area.rings {
		ring := Vector_Polys_Ring(&c.area, i)
		for j in 0 ..< len(ring) do rl.DrawLineEx(Vector_AffineApply(xf, ring[j]), Vector_AffineApply(xf, ring[(j + 1) % len(ring)]), 2, color)
	}
}

// --- carving -------------------------------------------------------------------------

// VectorShapeNode_Cut removes an area (node space) from the drawing - each
// shape keeps its paint - and the collider follows. The node draws its own
// carved copy from then on (until VectorShapeNode_ResetCuts).
VectorShapeNode_Cut :: proc(v: ^VectorShapeNode, area: ^Vector_Polys) {
	context.allocator = Engine_HeapAllocator()
	if !v.carving {
		// The shapes it draws now, as its own copy (curves kept until cut).
		src: []Vector_Shape
		offset: [2]f32
		if r := VectorShapeNode_Asset(v); r != nil {
			part, boxMin, boxSize, found := VectorShapeNode_Part(v, r)
			if !found do return
			src = Vector_PartShapes(r, part)
			offset = -boxMin - Node_OriginPx(v, boxSize)
		} else {
			if !v.built.ok do VectorShapeNode_Build(v)
			src = v.shapes[:]
		}
		if v.carved == nil do v.carved = make([dynamic]Vector_Shape)
		for &sh in src {
			s := sh
			Vector_Path_Init(&s.path)
			vector_path_append(&s.path, &sh.path)
			append(&v.carved, s)
		}
		v.carveOffset = offset
		v.carving = true
	}
	// Into the shapes' own space.
	cut: Vector_Polys
	cut.pts = make([dynamic][2]f32, context.temp_allocator)
	cut.rings = make([dynamic]Vector_Ring, context.temp_allocator)
	for r, i in area.rings {
		ring := Vector_Polys_Ring(area, i)
		pts := make([][2]f32, len(ring), context.temp_allocator)
		for q, j in ring do pts[j] = q - v.carveOffset
		Vector_PolysAddRing(&cut, pts, r.parent)
	}
	norm: Vector_Polys
	norm.pts = make([dynamic][2]f32, context.temp_allocator)
	norm.rings = make([dynamic]Vector_Ring, context.temp_allocator)
	if !Vector_PolysNormalize(&cut, .NonZero, 0.1, &norm) do return
	Vector_ShapesCut(&v.carved, &norm, 0.2)
	v.carveVersion += 1
}

// VectorShapeNode_ResetCuts brings the drawing back as it was.
VectorShapeNode_ResetCuts :: proc(v: ^VectorShapeNode) {
	for &s in v.carved do Vector_Path_Destroy(&s.path)
	clear(&v.carved)
	if v.carving do v.carveVersion += 1
	v.carving = false
}

// VectorShapeNode_WorldToLocal: a world point in the node's space.
VectorShapeNode_WorldToLocal :: proc(v: ^VectorShapeNode, world: [2]f32) -> [2]f32 {
	inv, _ := Vector_AffineInverse(Vector_AffineTRS(v.globalPosition, v.globalRotation, v.globalScale))
	return Vector_AffineApply(inv, world)
}

VectorShapeNode_LocalToWorld :: proc(v: ^VectorShapeNode, local: [2]f32) -> [2]f32 {
	return Vector_AffineApply(Vector_AffineTRS(v.globalPosition, v.globalRotation, v.globalScale), local)
}

// --- path queries --------------------------------------------------------------------

// VectorShapeNode_Polyline: the drawing's paths flattened and measured one
// after another (node space; remade when the art changes).
VectorShapeNode_Polyline :: proc(v: ^VectorShapeNode) -> ^Polyline {
	c := &v.collision
	shapes, offset, key, ok := vector_collider_source(v)
	if !ok {
		Polyline_Clear(&c.line)
		c.lineKey = 0
		return &c.line
	}
	if key == c.lineKey && len(c.line.pts) > 0 do return &c.line
	c.lineKey = key
	if c.line.pts == nil {
		c.line.pts = make([dynamic][2]f32, Engine_HeapAllocator())
		c.line.lens = make([dynamic]f32, Engine_HeapAllocator())
	}
	Polyline_Clear(&c.line)
	flat: Vector_Flat
	flat.pts = make([dynamic][2]f32, context.temp_allocator)
	flat.contours = make([dynamic]Vector_Contour, context.temp_allocator)
	for &sh in shapes {
		Vector_Flatten(&sh.path, 0.25, &flat)
		for ct in flat.contours {
			pts := Vector_Contour_Points(&flat, ct)
			for q, i in pts do Polyline_Add(&c.line, q + offset, i == 0)
			if ct.closed do Polyline_Add(&c.line, pts[0] + offset)
		}
	}
	return &c.line
}

// VectorShapeNode_Contains: whether a world point is on the art (fills
// and strokes; the area is cached until the art changes).
VectorShapeNode_Contains :: proc(v: ^VectorShapeNode, world: [2]f32) -> bool {
	c := &v.collision
	shapes, offset, key, ok := vector_collider_source(v)
	if !ok do return false
	if key != c.hitKey || c.hitArea.pts == nil {
		c.hitKey = key
		if c.hitArea.pts == nil {
			c.hitArea.pts = make([dynamic][2]f32, Engine_HeapAllocator())
			c.hitArea.rings = make([dynamic]Vector_Ring, Engine_HeapAllocator())
		}
		context.allocator = Engine_HeapAllocator()
		if !Vector_ShapesArea(shapes, 0.25, &c.hitArea) do Vector_Polys_Clear(&c.hitArea)
		for &q in c.hitArea.pts do q += offset
	}
	return Vector_PolysContains(&c.hitArea, VectorShapeNode_WorldToLocal(v, world))
}

// --- Lua -----------------------------------------------------------------------------
// node:vector_cut(x, y, radius | Vec2, radius) / node:vector_cut_polygon({Vec2...}) (world)
// node:vector_reset()
// node:vector_length() / node:vector_point_at(d) -> Vec2, Vec2 (world) / node:vector_closest(x, y | Vec2) -> d, Vec2
// node:vector_contains(x, y | Vec2) -> bool

@(private = "file")
lua_vec_node :: proc(L: ^lua.State) -> ^VectorShapeNode {
	n, ok := to_node_userdata(L, 1)
	if !ok || n.typeId != VectorShapeNode do return nil
	return cast(^VectorShapeNode)n
}

@(private = "file")
lua_vector_cut :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	v := lua_vec_node(L)
	if v == nil do return 0
	x, y := arg_xy(L, 2)
	ri: c.int = 4 if lua.type(L, 2) == .NUMBER else 3 // (x, y, r or Vec2, r)
	r := f32(lua.tonumber(L, ri))
	if r <= 0 do return 0
	// A circle in world space, into the node's (scale and rotation applied).
	ring: Vector_Polys
	ring.pts = make([dynamic][2]f32, context.temp_allocator)
	ring.rings = make([dynamic]Vector_Ring, context.temp_allocator)
	Vector_PolysCircle(&ring, {x, y}, r, 0.25)
	for &q in ring.pts do q = VectorShapeNode_WorldToLocal(v, q)
	VectorShapeNode_Cut(v, &ring)
	return 0
}

@(private = "file")
lua_vector_cut_polygon :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	v := lua_vec_node(L)
	if v == nil || lua.type(L, 2) != .TABLE do return 0
	n := int(lua.rawlen(L, 2))
	pts := make([dynamic][2]f32, context.temp_allocator)
	for i in 1 ..= n {
		lua.rawgeti(L, 2, lua.Integer(i))
		x, y := arg_xy(L, -1)
		lua.pop(L, 1)
		append(&pts, VectorShapeNode_WorldToLocal(v, {x, y}))
	}
	if len(pts) < 3 do return 0
	ring: Vector_Polys
	ring.pts = make([dynamic][2]f32, context.temp_allocator)
	ring.rings = make([dynamic]Vector_Ring, context.temp_allocator)
	Vector_PolysAddRing(&ring, pts[:])
	VectorShapeNode_Cut(v, &ring)
	return 0
}

@(private = "file")
lua_vector_reset :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	if v := lua_vec_node(L); v != nil do VectorShapeNode_ResetCuts(v)
	return 0
}

@(private = "file")
lua_vector_length :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	v := lua_vec_node(L)
	l: f32
	if v != nil {
		pl := VectorShapeNode_Polyline(v)
		l = Polyline_Length(pl.pts[:], pl.lens[:]) * max(abs(v.globalScale.x), abs(v.globalScale.y))
	}
	lua.pushnumber(L, lua.Number(l))
	return 1
}

@(private = "file")
lua_vector_point_at :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	v := lua_vec_node(L)
	if v == nil do return 0
	pl := VectorShapeNode_Polyline(v)
	s := max(abs(v.globalScale.x), abs(v.globalScale.y), 1e-6)
	pos, dir := Polyline_Sample(pl.pts[:], pl.lens[:], f32(lua.tonumber(L, 2)) / s)
	Lua_PushVec2(L, VectorShapeNode_LocalToWorld(v, pos))
	wd := VectorShapeNode_LocalToWorld(v, pos + dir) - VectorShapeNode_LocalToWorld(v, pos)
	l := math.sqrt(wd.x * wd.x + wd.y * wd.y)
	Lua_PushVec2(L, wd / l if l > 0 else {1, 0})
	return 2
}

@(private = "file")
lua_vector_closest :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	v := lua_vec_node(L)
	if v == nil do return 0
	x, y := arg_xy(L, 2)
	pl := VectorShapeNode_Polyline(v)
	if len(pl.pts) == 0 do return 0
	d, at := Polyline_Closest(pl.pts[:], pl.lens[:], VectorShapeNode_WorldToLocal(v, {x, y}))
	lua.pushnumber(L, lua.Number(d * max(abs(v.globalScale.x), abs(v.globalScale.y))))
	Lua_PushVec2(L, VectorShapeNode_LocalToWorld(v, at))
	return 2
}

@(private = "file")
lua_vector_contains :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	v := lua_vec_node(L)
	x, y := arg_xy(L, 2)
	lua.pushboolean(L, b32(v != nil && VectorShapeNode_Contains(v, {x, y})))
	return 1
}

// Script_RegisterVectorColliderBindings adds the vector_* methods above to
// the node metatable (on the stack).
Script_RegisterVectorColliderBindings :: proc(L: ^lua.State) {
	reg :: proc(L: ^lua.State, name: cstring, fn: lua.CFunction) {
		lua.pushcfunction(L, fn)
		lua.setfield(L, -2, name)
	}
	reg(L, "vector_cut", lua_vector_cut)
	reg(L, "vector_cut_polygon", lua_vector_cut_polygon)
	reg(L, "vector_reset", lua_vector_reset)
	reg(L, "vector_length", lua_vector_length)
	reg(L, "vector_point_at", lua_vector_point_at)
	reg(L, "vector_closest", lua_vector_closest)
	reg(L, "vector_contains", lua_vector_contains)
}
