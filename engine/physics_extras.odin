package engine

import "base:runtime"
import "core:fmt"
import "core:strings"
import b2 "vendor:box2d"

// ============================================================================
// Physics helpers shared by bodies, joints and LDtk levels:
//   - one-way bodies (platforms you jump up through)
//   - named collision layers (project settings)
//   - the Box2D body behind a body node
// ============================================================================

// --- one-way bodies -----------------------------------------------------------------

// Bodies whose contacts only count from one side: body user data -> the
// direction contacts are allowed from (up = {0, -1}). Read by the
// pre-solve callback on Box2D's worker threads; changed between steps.
@(private = "file")
oneWayBodies: map[rawptr][2]f32

// Physics_SetOneWay makes a body node one-way (passable except from
// `side`, a direction: {0, -1} = landing on top) or normal again.
Physics_SetOneWay :: proc(node: ^Node, on: bool, side: [2]f32 = {0, -1}, worldId: b2.WorldId = {}) {
	if node == nil do return
	key := rawptr(node)
	if on {
		if oneWayBodies == nil do oneWayBodies = make(map[rawptr][2]f32, allocator = Engine_HeapAllocator())
		oneWayBodies[key] = side
		if b2.World_IsValid(worldId) do b2.World_SetPreSolveCallback(worldId, physics_pre_solve, nil)
	} else if key in oneWayBodies {
		delete_key(&oneWayBodies, key)
	}
}

Physics_IsOneWay :: proc(node: ^Node) -> bool {
	return rawptr(node) in oneWayBodies
}

// A contact with a one-way body counts only when it comes from its side.
@(private = "file")
physics_pre_solve :: proc "c" (shapeA, shapeB: b2.ShapeId, manifold: ^b2.Manifold, ctx: rawptr) -> bool {
	side_of :: proc "contextless" (s: b2.ShapeId) -> ([2]f32, bool) {
		ud := b2.Body_GetUserData(b2.Shape_GetBody(s))
		d, ok := oneWayBodies[ud]
		return d, ok
	}
	n := [2]f32{manifold.normal.x, manifold.normal.y} // from A to B
	if d, ok := side_of(shapeA); ok do return n.x * d.x + n.y * d.y > 0.5
	if d, ok := side_of(shapeB); ok do return -(n.x * d.x + n.y * d.y) > 0.5
	return true
}

// --- named collision layers --------------------------------------------------------------

// Names from the project's Physics settings ("" = unnamed). Scenes keep
// saving the stable enum names (Layer1..Layer16); these are for display
// and scripts.
collisionLayerNames: [16]string

Physics_SetLayerNames :: proc(names: []string) {
	for &n in collisionLayerNames {
		if n != "" do delete(n, Engine_HeapAllocator())
		n = ""
	}
	for name, i in names {
		if i >= 16 do break
		collisionLayerNames[i] = strings.clone(strings.trim_space(name), Engine_HeapAllocator())
	}
}

// CollisionLayer_DisplayName: "Player (1)" or "Layer 1".
CollisionLayer_DisplayName :: proc(l: CollisionLayer, allocator := context.temp_allocator) -> string {
	i := int(l)
	if collisionLayerNames[i] != "" do return fmt.aprintf("%s (%d)", collisionLayerNames[i], i + 1, allocator = allocator)
	return fmt.aprintf("Layer %d", i + 1, allocator = allocator)
}

// CollisionLayer_Parse: a project layer name, "LayerN" / "N" (1-16).
CollisionLayer_Parse :: proc(s: string) -> (CollisionLayer, bool) {
	for name, i in collisionLayerNames do if name != "" && strings.equal_fold(name, s) do return CollisionLayer(i), true
	digits := strings.trim_prefix(strings.trim_prefix(s, "Layer"), "layer")
	n := 0
	if len(digits) == 0 do return .Layer1, false
	for ch in digits {
		if ch < '0' || ch > '9' do return .Layer1, false
		n = n * 10 + int(ch - '0')
	}
	if n < 1 || n > 16 do return .Layer1, false
	return CollisionLayer(n - 1), true
}

// --- bodies ---------------------------------------------------------------------------------

// Physics_BodyOf: the Box2D body of a body node (static, dynamic,
// character mover), or a null id.
Physics_BodyOf :: proc(n: ^Node) -> b2.BodyId {
	if n == nil || !Node_IsAlive(n) do return b2.nullBodyId
	switch n.typeId {
	case StaticBodyNode:     return (cast(^StaticBodyNode)n).bodyId
	case DynamicBodyNode:    return (cast(^DynamicBodyNode)n).bodyId
	case CharacterMoverNode: return (cast(^CharacterMoverNode)n).bodyId
	}
	return b2.nullBodyId
}

// Physics_BodyShapes: a body node's shapes (nil for other nodes).
Physics_BodyShapes :: proc(n: ^Node) -> []PhysicsShape {
	if n == nil do return nil
	switch n.typeId {
	case StaticBodyNode:     return (cast(^StaticBodyNode)n).shapes[:]
	case DynamicBodyNode:    return (cast(^DynamicBodyNode)n).shapes[:]
	case CharacterMoverNode: return (cast(^CharacterMoverNode)n).shapes[:]
	case AreaNode:           return (cast(^AreaNode)n).shapes[:]
	}
	return nil
}

// b2_is_body_node: a node with a Box2D body a joint can attach to.
b2_is_body_node :: proc(n: ^Node) -> bool {
	return n.typeId == StaticBodyNode || n.typeId == DynamicBodyNode || n.typeId == CharacterMoverNode
}
