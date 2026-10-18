package engine

import "core:math"
import b2 "vendor:box2d"
import rl "vendor:raylib"

// ============================================================================
// 1. StaticBodyNode (StaticBody)
// ============================================================================
StaticBodyNode :: struct {
	using node: Node,
	bodyId: b2.BodyId,
	shapes: [dynamic]PhysicsShape,
	debugColor: rl.Color `gui:"true"`,
	lastSyncedPos: [2]f32,
	lastSyncedRot: f32,
}

StaticBody :: StaticBodyNode

StaticBodyNode_Create :: proc(scene: ^Scene, name: string = "StaticBody", parent: ^Node = nil) -> ^StaticBodyNode {
	sb := CreateNode(scene.manager, StaticBodyNode)
	sb.name = name
	sb.position = {640, 620}
	sb.debugColor = rl.Color{74, 222, 128, 255} // Green
	sb.shapes = make([dynamic]PhysicsShape, sb.allocator)
	sb.update = StaticBodyNode_Update
	sb.render = StaticBodyNode_Render
	sb.onDestroy = StaticBodyNode_Destroy
	scene->addNode(sb, parent)
	return sb
}

StaticBodyNode_EnsureBody :: proc(sb: ^StaticBodyNode, gameContext: ^GameContext) {
	if b2.Body_IsValid(sb.bodyId) do return
	if gameContext == nil || gameContext.game == nil do return
	worldId := gameContext.game.physicsWorld.worldId
	if !b2.World_IsValid(worldId) do return

	def := b2.DefaultBodyDef()
	def.type = .staticBody
	def.position = sb.position
	def.rotation = DegreesToRot(sb.rotation)
	def.userData = cast(rawptr)(cast(^Node)sb)
	sb.bodyId = b2.CreateBody(worldId, def)
	sb.lastSyncedPos = sb.position
	sb.lastSyncedRot = sb.rotation

	for &shape in sb.shapes {
		PhysicsShape_AttachToBody(&shape, sb.bodyId, cast(rawptr)(cast(^Node)sb))
	}
}

StaticBodyNode_AddShape :: proc(sb: ^StaticBodyNode, shape: PhysicsShape, gameContext: ^GameContext = nil) -> ^PhysicsShape {
	append(&sb.shapes, shape)
	ptr := &sb.shapes[len(sb.shapes) - 1]
	if gameContext != nil {
		StaticBodyNode_EnsureBody(sb, gameContext)
	}
	if b2.Body_IsValid(sb.bodyId) {
		PhysicsShape_AttachToBody(ptr, sb.bodyId, cast(rawptr)(cast(^Node)sb))
	}
	return ptr
}

StaticBodyNode_RemoveShape :: proc(sb: ^StaticBodyNode, index: int) {
	if index < 0 || index >= len(sb.shapes) do return
	PhysicsShape_Destroy(&sb.shapes[index])
	ordered_remove(&sb.shapes, index)
}

StaticBodyNode_Update :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	sb := cast(^StaticBodyNode)node
	if !sb.enabled {
		if b2.Body_IsValid(sb.bodyId) && b2.Body_IsEnabled(sb.bodyId) {
			b2.Body_Disable(sb.bodyId)
		}
		return
	}

	StaticBodyNode_EnsureBody(sb, gameContext)
	if !b2.Body_IsValid(sb.bodyId) do return
	if !b2.Body_IsEnabled(sb.bodyId) {
		b2.Body_Enable(sb.bodyId)
	}

	// Sync transform if edited in Inspector
	if b2.Distance(sb.position, sb.lastSyncedPos) > 0.01 || abs(sb.rotation - sb.lastSyncedRot) > 0.01 {
		b2.Body_SetTransform(sb.bodyId, sb.position, DegreesToRot(sb.rotation))
		sb.lastSyncedPos = sb.position
		sb.lastSyncedRot = sb.rotation
	}

	for &shape in sb.shapes {
		PhysicsShape_SyncToBox2D(&shape, sb.bodyId, cast(rawptr)node)
	}
}

StaticBodyNode_Render :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	sb := cast(^StaticBodyNode)node
	if gameContext != nil && gameContext.game != nil && !gameContext.game.physicsWorld.drawPhysicsDebug {
		return
	}
	for &shape in sb.shapes {
		PhysicsShape_DrawDebug(&shape, sb.position, sb.rotation, sb.debugColor)
	}
}

StaticBodyNode_Destroy :: proc(node: ^Node, gameContext: ^GameContext) {
	sb := cast(^StaticBodyNode)node
	if b2.Body_IsValid(sb.bodyId) {
		b2.DestroyBody(sb.bodyId)
		sb.bodyId = b2.nullBodyId
	}
}

// ============================================================================
// 2. DynamicBodyNode (DynamicBody)
// ============================================================================
DynamicBodyNode :: struct {
	using node: Node,
	bodyId: b2.BodyId,
	shapes: [dynamic]PhysicsShape,
	linearVelocity: [2]f32 `gui:"true" min:"-1000" max:"1000"`,
	angularVelocity: f32 `gui:"true" min:"-360" max:"360"`,
	linearDamping: f32 `gui:"true" min:"0" max:"20"`,
	angularDamping: f32 `gui:"true" min:"0" max:"20"`,
	gravityScale: f32 `gui:"true" min:"-5" max:"5"`,
	sleepThreshold: f32 `gui:"true" min:"0" max:"100"`,
	enableSleep: bool `gui:"true"`,
	isAwake: bool `gui:"true"`,
	fixedRotation: bool `gui:"true"`,
	isBullet: bool `gui:"true"`,
	allowFastRotation: bool `gui:"true"`,
	debugColor: rl.Color `gui:"true"`,
	lastSyncedPos: [2]f32,
	lastSyncedRot: f32,
	lastSyncedVel: [2]f32,
	lastSyncedAngVel: f32,
}

DynamicBody :: DynamicBodyNode

DynamicBodyNode_Create :: proc(scene: ^Scene, name: string = "DynamicBody", parent: ^Node = nil) -> ^DynamicBodyNode {
	db := CreateNode(scene.manager, DynamicBodyNode)
	db.name = name
	db.position = {640, 200}
	db.linearVelocity = {0, 0}
	db.angularVelocity = 0
	db.linearDamping = 0.05
	db.angularDamping = 0.05
	db.gravityScale = 1.0
	db.sleepThreshold = 1.5
	db.enableSleep = true
	db.isAwake = true
	db.fixedRotation = false
	db.isBullet = false
	db.allowFastRotation = false
	db.debugColor = rl.Color{96, 165, 250, 255} // Blue
	db.shapes = make([dynamic]PhysicsShape, db.allocator)
	db.update = DynamicBodyNode_Update
	db.render = DynamicBodyNode_Render
	db.onDestroy = DynamicBodyNode_Destroy
	scene->addNode(db, parent)
	return db
}

DynamicBodyNode_EnsureBody :: proc(db: ^DynamicBodyNode, gameContext: ^GameContext) {
	if b2.Body_IsValid(db.bodyId) do return
	if gameContext == nil || gameContext.game == nil do return
	worldId := gameContext.game.physicsWorld.worldId
	if !b2.World_IsValid(worldId) do return

	def := b2.DefaultBodyDef()
	def.type = .dynamicBody
	def.position = db.position
	def.rotation = DegreesToRot(db.rotation)
	def.linearVelocity = db.linearVelocity
	def.angularVelocity = math.to_radians(db.angularVelocity)
	def.linearDamping = db.linearDamping
	def.angularDamping = db.angularDamping
	def.gravityScale = db.gravityScale
	def.sleepThreshold = db.sleepThreshold
	def.enableSleep = db.enableSleep
	def.isAwake = db.isAwake
	def.fixedRotation = db.fixedRotation
	def.isBullet = db.isBullet
	def.allowFastRotation = db.allowFastRotation
	def.userData = cast(rawptr)(cast(^Node)db)

	db.bodyId = b2.CreateBody(worldId, def)
	db.lastSyncedPos = db.position
	db.lastSyncedRot = db.rotation
	db.lastSyncedVel = db.linearVelocity
	db.lastSyncedAngVel = db.angularVelocity

	for &shape in db.shapes {
		PhysicsShape_AttachToBody(&shape, db.bodyId, cast(rawptr)(cast(^Node)db))
	}
}

DynamicBodyNode_AddShape :: proc(db: ^DynamicBodyNode, shape: PhysicsShape, gameContext: ^GameContext = nil) -> ^PhysicsShape {
	append(&db.shapes, shape)
	ptr := &db.shapes[len(db.shapes) - 1]
	if gameContext != nil {
		DynamicBodyNode_EnsureBody(db, gameContext)
	}
	if b2.Body_IsValid(db.bodyId) {
		PhysicsShape_AttachToBody(ptr, db.bodyId, cast(rawptr)(cast(^Node)db))
	}
	return ptr
}

DynamicBodyNode_RemoveShape :: proc(db: ^DynamicBodyNode, index: int) {
	if index < 0 || index >= len(db.shapes) do return
	PhysicsShape_Destroy(&db.shapes[index])
	ordered_remove(&db.shapes, index)
}

DynamicBodyNode_ApplyForce :: proc(db: ^DynamicBodyNode, force: [2]f32) {
	if b2.Body_IsValid(db.bodyId) {
		b2.Body_ApplyForceToCenter(db.bodyId, force, true)
	}
}

DynamicBodyNode_ApplyImpulse :: proc(db: ^DynamicBodyNode, impulse: [2]f32) {
	if b2.Body_IsValid(db.bodyId) {
		b2.Body_ApplyLinearImpulseToCenter(db.bodyId, impulse, true)
	}
}

DynamicBodyNode_Update :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	db := cast(^DynamicBodyNode)node
	if !db.enabled {
		if b2.Body_IsValid(db.bodyId) && b2.Body_IsEnabled(db.bodyId) {
			b2.Body_Disable(db.bodyId)
		}
		return
	}

	DynamicBodyNode_EnsureBody(db, gameContext)
	if !b2.Body_IsValid(db.bodyId) do return
	if !b2.Body_IsEnabled(db.bodyId) {
		b2.Body_Enable(db.bodyId)
	}

	// If user manually moved node position/rotation via Inspector slider, teleport Box2D body
	if b2.Distance(db.position, db.lastSyncedPos) > 0.5 || abs(db.rotation - db.lastSyncedRot) > 0.5 {
		b2.Body_SetTransform(db.bodyId, db.position, DegreesToRot(db.rotation))
		b2.Body_SetAwake(db.bodyId, true)
	}

	// If user manually edited velocity in Inspector, apply it to Box2D body
	if b2.Distance(db.linearVelocity, db.lastSyncedVel) > 0.5 {
		b2.Body_SetLinearVelocity(db.bodyId, db.linearVelocity)
		b2.Body_SetAwake(db.bodyId, true)
	}
	if abs(db.angularVelocity - db.lastSyncedAngVel) > 0.5 {
		b2.Body_SetAngularVelocity(db.bodyId, math.to_radians(db.angularVelocity))
		b2.Body_SetAwake(db.bodyId, true)
	}

	// Sync dynamic parameters
	b2.Body_SetLinearDamping(db.bodyId, db.linearDamping)
	b2.Body_SetAngularDamping(db.bodyId, db.angularDamping)
	b2.Body_SetGravityScale(db.bodyId, db.gravityScale)
	b2.Body_SetSleepThreshold(db.bodyId, db.sleepThreshold)
	b2.Body_EnableSleep(db.bodyId, db.enableSleep)
	if b2.Body_IsFixedRotation(db.bodyId) != db.fixedRotation {
		b2.Body_SetFixedRotation(db.bodyId, db.fixedRotation)
	}
	if b2.Body_IsBullet(db.bodyId) != db.isBullet {
		b2.Body_SetBullet(db.bodyId, db.isBullet)
	}

	for &shape in db.shapes {
		PhysicsShape_SyncToBox2D(&shape, db.bodyId, cast(rawptr)node)
	}

	// Read back simulated state from Box2D
	db.position = b2.Body_GetPosition(db.bodyId)
	db.rotation = RotToDegrees(b2.Body_GetRotation(db.bodyId))
	db.linearVelocity = b2.Body_GetLinearVelocity(db.bodyId)
	db.angularVelocity = math.to_degrees(b2.Body_GetAngularVelocity(db.bodyId))
	db.isAwake = b2.Body_IsAwake(db.bodyId)

	db.lastSyncedPos = db.position
	db.lastSyncedRot = db.rotation
	db.lastSyncedVel = db.linearVelocity
	db.lastSyncedAngVel = db.angularVelocity
}

DynamicBodyNode_Render :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	db := cast(^DynamicBodyNode)node
	if gameContext != nil && gameContext.game != nil && !gameContext.game.physicsWorld.drawPhysicsDebug {
		return
	}
	for &shape in db.shapes {
		PhysicsShape_DrawDebug(&shape, db.position, db.rotation, db.debugColor)
	}
}

DynamicBodyNode_Destroy :: proc(node: ^Node, gameContext: ^GameContext) {
	db := cast(^DynamicBodyNode)node
	if b2.Body_IsValid(db.bodyId) {
		b2.DestroyBody(db.bodyId)
		db.bodyId = b2.nullBodyId
	}
}

// ============================================================================
// 3. CharacterMoverNode (CharacterMover - Box2D v3 Capsule Character Mover)
// ============================================================================
MAX_MOVER_PLANES :: 16

CharacterMoverNode :: struct {
	using node: Node,
	bodyId: b2.BodyId, // Optional kinematic proxy body so dynamic bodies & sensors also see the character
	shapes: [dynamic]PhysicsShape,
	radius: f32 `gui:"true" min:"2" max:"200"`,
	height: f32 `gui:"true" min:"2" max:"400"`,
	velocity: [2]f32 `gui:"true" min:"-1000" max:"1000"`,
	targetSpeedX: f32 `gui:"true" min:"-600" max:"600"`,
	maxSpeed: f32 `gui:"true" min:"10" max:"1000"`,
	acceleration: f32 `gui:"true" min:"10" max:"5000"`,
	jumpSpeed: f32 `gui:"true" min:"10" max:"1200"`,
	gravityScale: f32 `gui:"true" min:"0" max:"5"`,
	pushLimit: f32 `gui:"true" min:"0" max:"1000"`,
	clipVelocity: bool `gui:"true"`,
	enableKeyboardInput: bool `gui:"true"`,
	isGrounded: bool `gui:"true"`,
	categoryLayers: CollisionLayerSet `gui:"true"`,
	maskLayers: CollisionLayerSet `gui:"true"`,
	debugColor: rl.Color `gui:"true"`,
	collisionPlanes: [MAX_MOVER_PLANES]b2.CollisionPlane,
	planeCount: int,
}

CharacterMover :: CharacterMoverNode

CharacterMoverNode_Create :: proc(scene: ^Scene, name: string = "CharacterMover", parent: ^Node = nil) -> ^CharacterMoverNode {
	cm := CreateNode(scene.manager, CharacterMoverNode)
	cm.name = name
	cm.position = {540, 300}
	cm.radius = 14.0
	cm.height = 28.0
	cm.velocity = {0, 0}
	cm.targetSpeedX = 0
	cm.maxSpeed = 240.0
	cm.acceleration = 1200.0
	cm.jumpSpeed = 320.0
	cm.gravityScale = 1.0
	cm.pushLimit = 500.0
	cm.clipVelocity = true
	cm.enableKeyboardInput = true
	cm.isGrounded = false
	cm.categoryLayers = {CollisionLayer.Layer1}
	cm.maskLayers = DEFAULT_COLLISION_MASK
	cm.debugColor = rl.Color{250, 204, 21, 255} // Yellow/Gold
	cm.shapes = make([dynamic]PhysicsShape, cm.allocator)

	// Add default capsule shape representation
	capShape := MakeCapsulePhysicsShape(cm.radius, cm.height)
	append(&cm.shapes, capShape)

	cm.update = CharacterMoverNode_Update
	cm.render = CharacterMoverNode_Render
	cm.onDestroy = CharacterMoverNode_Destroy
	scene->addNode(cm, parent)
	return cm
}

CharacterMoverNode_GetWorldCapsule :: proc(cm: ^CharacterMoverNode) -> b2.Capsule {
	r := max(cm.radius, 1.0)
	h := max(cm.height, 1.0)
	offset: [2]f32 = {0, 0}
	if len(cm.shapes) > 0 {
		s := &cm.shapes[0]
		if s.type == .Capsule || s.type == .Circle {
			r = max(s.radius, 1.0)
			h = max(s.size[1], 1.0)
			offset = s.offset
			cm.radius = r
			cm.height = h
		}
	}
	halfLen := h * 0.5
	rot := DegreesToRot(cm.rotation)
	dir := b2.RotateVector(rot, b2.Vec2{0, halfLen})
	center := cm.position + b2.RotateVector(rot, offset)
	return b2.Capsule{
		center1 = center - dir,
		center2 = center + dir,
		radius  = r,
	}
}

CharacterMover_PlaneResultCallback :: proc "c" (shapeId: b2.ShapeId, planeResult: ^b2.PlaneResult, ctx: rawptr) -> bool {
	if planeResult == nil || !planeResult.hit || ctx == nil {
		return true
	}
	cm := cast(^CharacterMoverNode)ctx

	// Ignore self kinematic proxy body if present
	if b2.Shape_IsValid(shapeId) && b2.Body_IsValid(cm.bodyId) {
		if b2.Shape_GetBody(shapeId) == cm.bodyId {
			return true
		}
	}
	// Ignore sensors in mover plane solver
	if b2.Shape_IsValid(shapeId) && b2.Shape_IsSensor(shapeId) {
		return true
	}

	if cm.planeCount < MAX_MOVER_PLANES {
		pushLim := cm.pushLimit if cm.pushLimit > 0 else max(f32)
		cm.collisionPlanes[cm.planeCount] = b2.CollisionPlane{
			plane        = planeResult.plane,
			pushLimit    = pushLim,
			push         = 0,
			clipVelocity = cm.clipVelocity,
		}
		cm.planeCount += 1
	}
	return true
}

CharacterMoverNode_EnsureProxyBody :: proc(cm: ^CharacterMoverNode, worldId: b2.WorldId) {
	if b2.Body_IsValid(cm.bodyId) || !b2.World_IsValid(worldId) do return

	def := b2.DefaultBodyDef()
	def.type = .kinematicBody
	def.position = cm.position
	def.rotation = DegreesToRot(cm.rotation)
	def.userData = cast(rawptr)(cast(^Node)cm)
	cm.bodyId = b2.CreateBody(worldId, def)

	for &shape in cm.shapes {
		shape.categoryLayers = cm.categoryLayers
		shape.maskLayers = cm.maskLayers
		PhysicsShape_AttachToBody(&shape, cm.bodyId, cast(rawptr)(cast(^Node)cm))
	}
}

CharacterMoverNode_AddShape :: proc(cm: ^CharacterMoverNode, shape: PhysicsShape, gameContext: ^GameContext = nil) -> ^PhysicsShape {
	append(&cm.shapes, shape)
	ptr := &cm.shapes[len(cm.shapes) - 1]
	if b2.Body_IsValid(cm.bodyId) {
		PhysicsShape_AttachToBody(ptr, cm.bodyId, cast(rawptr)(cast(^Node)cm))
	}
	return ptr
}

CharacterMoverNode_RemoveShape :: proc(cm: ^CharacterMoverNode, index: int) {
	if index < 0 || index >= len(cm.shapes) do return
	PhysicsShape_Destroy(&cm.shapes[index])
	ordered_remove(&cm.shapes, index)
}

CharacterMoverNode_Update :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	cm := cast(^CharacterMoverNode)node
	if !cm.enabled {
		if b2.Body_IsValid(cm.bodyId) && b2.Body_IsEnabled(cm.bodyId) {
			b2.Body_Disable(cm.bodyId)
		}
		return
	}
	if deltaTime <= 0.00001 do return
	if gameContext == nil || gameContext.game == nil do return

	pw := &gameContext.game.physicsWorld
	if !b2.World_IsValid(pw.worldId) || pw.paused do return

	CharacterMoverNode_EnsureProxyBody(cm, pw.worldId)
	if b2.Body_IsValid(cm.bodyId) && !b2.Body_IsEnabled(cm.bodyId) {
		b2.Body_Enable(cm.bodyId)
	}

	// Query Logical Actions via the Two-Tier Input System (MoveLeft, MoveRight, Jump)
	desiredVX := cm.targetSpeedX
	if cm.enableKeyboardInput {
		moveAxis := GetActionAxis(gameContext, .MoveLeft, .MoveRight)
		if moveAxis != 0.0 {
			desiredVX = moveAxis * cm.maxSpeed
		}
		if IsActionPressed(gameContext, .Jump) && cm.isGrounded {
			cm.velocity.y = -cm.jumpSpeed
			cm.isGrounded = false
		}
	}

	// Horizontal acceleration toward desiredVX
	diffX := desiredVX - cm.velocity.x
	maxDeltaV := cm.acceleration * deltaTime
	if abs(diffX) <= maxDeltaV {
		cm.velocity.x = desiredVX
	} else {
		cm.velocity.x += math.copy_sign(maxDeltaV, diffX)
	}

	// Apply world gravity
	cm.velocity += pw.gravity * cm.gravityScale * deltaTime

	// Build query filter from CharacterMover's collision layers
	qFilter := b2.QueryFilter{
		categoryBits = CollisionLayerSet_ToBits(cm.categoryLayers),
		maskBits     = CollisionLayerSet_ToBits(cm.maskLayers),
	}

	// 1. Gather collision planes around the capsule mover using Box2D v3 World_CollideMover
	moverCapsule := CharacterMoverNode_GetWorldCapsule(cm)
	cm.planeCount = 0
	b2.World_CollideMover(pw.worldId, moverCapsule, qFilter, CharacterMover_PlaneResultCallback, cast(rawptr)cm)

	// 2. Solve collision planes for target translation using Box2D v3 SolvePlanes
	targetDelta := cm.velocity * deltaTime
	planesSlice := cm.collisionPlanes[:cm.planeCount]
	solverResult := b2.SolvePlanes(targetDelta, planesSlice)

	// 3. Clip velocity against active collision planes using Box2D v3 ClipVector
	cm.isGrounded = false
	for i in 0..<cm.planeCount {
		// In screen coordinates (+Y down), an upward floor normal has normal.y < -0.5
		if cm.collisionPlanes[i].plane.normal.y < -0.5 {
			cm.isGrounded = true
		}
	}
	if cm.planeCount > 0 {
		cm.velocity = b2.ClipVector(cm.velocity, planesSlice)
	}

	// 4. Cast mover along solved translation to prevent tunneling (World_CastMover)
	fraction := b2.World_CastMover(pw.worldId, moverCapsule, solverResult.translation, qFilter)
	delta := solverResult.translation * fraction
	cm.position += delta

	// Sync kinematic proxy body so sensors (AreaNode) and dynamic bodies interact with the mover
	if b2.Body_IsValid(cm.bodyId) {
		b2.Body_SetTargetTransform(cm.bodyId, b2.Transform{p = cm.position, q = DegreesToRot(cm.rotation)}, deltaTime)
		for &shape in cm.shapes {
			shape.categoryLayers = cm.categoryLayers
			shape.maskLayers = cm.maskLayers
			PhysicsShape_SyncToBox2D(&shape, cm.bodyId, cast(rawptr)node)
		}
	}
}

CharacterMoverNode_Render :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	if !rl.IsWindowReady() do return
	cm := cast(^CharacterMoverNode)node
	if gameContext != nil && gameContext.game != nil && !gameContext.game.physicsWorld.drawPhysicsDebug {
		return
	}
	cap := CharacterMoverNode_GetWorldCapsule(cm)
	fillColor := rl.Color{cm.debugColor.r, cm.debugColor.g, cm.debugColor.b, 70}
	rl.DrawCircleV(cap.center1, cap.radius, fillColor)
	rl.DrawCircleV(cap.center2, cap.radius, fillColor)
	rl.DrawLineEx(cap.center1, cap.center2, cap.radius * 2.0, fillColor)
	rl.DrawCircleLinesV(cap.center1, cap.radius, cm.debugColor)
	rl.DrawCircleLinesV(cap.center2, cap.radius, cm.debugColor)
	rot := DegreesToRot(cm.rotation)
	perp := b2.RotateVector(rot, b2.Vec2{cap.radius, 0})
	rl.DrawLineV(cap.center1 + perp, cap.center2 + perp, cm.debugColor)
	rl.DrawLineV(cap.center1 - perp, cap.center2 - perp, cm.debugColor)
}

CharacterMoverNode_Destroy :: proc(node: ^Node, gameContext: ^GameContext) {
	cm := cast(^CharacterMoverNode)node
	if b2.Body_IsValid(cm.bodyId) {
		b2.DestroyBody(cm.bodyId)
		cm.bodyId = b2.nullBodyId
	}
}

// ============================================================================
// 4. AreaNode (Area - Sensor that detects bodies entering and leaving)
// ============================================================================
AreaNode :: struct {
	using node: Node,
	bodyId: b2.BodyId,
	shapes: [dynamic]PhysicsShape,
	overlappingNodes: [dynamic]^Node,
	overlapCount: int `gui:"true" min:"0" max:"100"`,
	hasOverlaps: bool `gui:"true"`,
	onBodyEntered: EventSubject,
	onBodyExited: EventSubject,
	debugColor: rl.Color `gui:"true"`,
	activeColor: rl.Color `gui:"true"`,
	lastSyncedPos: [2]f32,
	lastSyncedRot: f32,
}

Area :: AreaNode

AreaNode_Create :: proc(scene: ^Scene, name: string = "Area", parent: ^Node = nil) -> ^AreaNode {
	area := CreateNode(scene.manager, AreaNode)
	area.name = name
	area.position = {640, 460}
	area.debugColor = rl.Color{168, 85, 247, 255}  // Purple
	area.activeColor = rl.Color{236, 72, 153, 255} // Pink when overlapping
	area.shapes = make([dynamic]PhysicsShape, area.allocator)
	area.overlappingNodes = make([dynamic]^Node, area.allocator)
	InitializeSubject(&area.onBodyEntered)
	InitializeSubject(&area.onBodyExited)
	area.update = AreaNode_Update
	area.render = AreaNode_Render
	area.onDestroy = AreaNode_Destroy
	scene->addNode(area, parent)
	return area
}

AreaNode_EnsureBody :: proc(area: ^AreaNode, gameContext: ^GameContext) {
	if b2.Body_IsValid(area.bodyId) do return
	if gameContext == nil || gameContext.game == nil do return
	worldId := gameContext.game.physicsWorld.worldId
	if !b2.World_IsValid(worldId) do return

	def := b2.DefaultBodyDef()
	def.type = .staticBody
	def.position = area.position
	def.rotation = DegreesToRot(area.rotation)
	def.userData = cast(rawptr)(cast(^Node)area)
	area.bodyId = b2.CreateBody(worldId, def)
	area.lastSyncedPos = area.position
	area.lastSyncedRot = area.rotation

	for &shape in area.shapes {
		shape.isSensor = true
		shape.enableSensorEvents = true
		PhysicsShape_AttachToBody(&shape, area.bodyId, cast(rawptr)(cast(^Node)area))
	}
}

AreaNode_AddShape :: proc(area: ^AreaNode, shape: PhysicsShape, gameContext: ^GameContext = nil) -> ^PhysicsShape {
	s := shape
	s.isSensor = true
	s.enableSensorEvents = true
	append(&area.shapes, s)
	ptr := &area.shapes[len(area.shapes) - 1]
	if gameContext != nil {
		AreaNode_EnsureBody(area, gameContext)
	}
	if b2.Body_IsValid(area.bodyId) {
		PhysicsShape_AttachToBody(ptr, area.bodyId, cast(rawptr)(cast(^Node)area))
	}
	return ptr
}

AreaNode_RemoveShape :: proc(area: ^AreaNode, index: int) {
	if index < 0 || index >= len(area.shapes) do return
	PhysicsShape_Destroy(&area.shapes[index])
	ordered_remove(&area.shapes, index)
}

AreaNode_HandleEnter :: proc(sensorNode: ^Node, visitorNode: ^Node, gameContext: ^GameContext) {
	if sensorNode == nil do return
	sensorNode.onEnter->notify(visitorNode, true, gameContext)

	// Update AreaNode overlap state
	area := cast(^AreaNode)sensorNode
	if visitorNode != nil {
		alreadyPresent := false
		for n in area.overlappingNodes {
			if n == visitorNode {
				alreadyPresent = true
				break
			}
		}
		if !alreadyPresent {
			append(&area.overlappingNodes, visitorNode)
		}
	}
	area.overlapCount = len(area.overlappingNodes)
	area.hasOverlaps = area.overlapCount > 0
	area.onBodyEntered->notify(visitorNode, true, gameContext)
}

AreaNode_HandleExit :: proc(sensorNode: ^Node, visitorNode: ^Node, gameContext: ^GameContext) {
	if sensorNode == nil do return
	sensorNode.onExit->notify(visitorNode, false, gameContext)

	area := cast(^AreaNode)sensorNode
	if visitorNode != nil {
		for n, i in area.overlappingNodes {
			if n == visitorNode {
				unordered_remove(&area.overlappingNodes, i)
				break
			}
		}
	}
	area.overlapCount = len(area.overlappingNodes)
	area.hasOverlaps = area.overlapCount > 0
	area.onBodyExited->notify(visitorNode, false, gameContext)
}

AreaNode_Update :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	area := cast(^AreaNode)node
	if !area.enabled {
		if b2.Body_IsValid(area.bodyId) && b2.Body_IsEnabled(area.bodyId) {
			b2.Body_Disable(area.bodyId)
		}
		return
	}

	AreaNode_EnsureBody(area, gameContext)
	if !b2.Body_IsValid(area.bodyId) do return
	if !b2.Body_IsEnabled(area.bodyId) {
		b2.Body_Enable(area.bodyId)
	}

	if b2.Distance(area.position, area.lastSyncedPos) > 0.01 || abs(area.rotation - area.lastSyncedRot) > 0.01 {
		b2.Body_SetTransform(area.bodyId, area.position, DegreesToRot(area.rotation))
		area.lastSyncedPos = area.position
		area.lastSyncedRot = area.rotation
	}

	for &shape in area.shapes {
		shape.isSensor = true
		shape.enableSensorEvents = true
		PhysicsShape_SyncToBox2D(&shape, area.bodyId, cast(rawptr)node)
	}

	area.overlapCount = len(area.overlappingNodes)
	area.hasOverlaps = area.overlapCount > 0
}

AreaNode_Render :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	area := cast(^AreaNode)node
	if gameContext != nil && gameContext.game != nil && !gameContext.game.physicsWorld.drawPhysicsDebug {
		return
	}
	color := area.activeColor if area.hasOverlaps else area.debugColor
	for &shape in area.shapes {
		PhysicsShape_DrawDebug(&shape, area.position, area.rotation, color)
	}
}

AreaNode_Destroy :: proc(node: ^Node, gameContext: ^GameContext) {
	area := cast(^AreaNode)node
	DestroySubject(&area.onBodyEntered)
	DestroySubject(&area.onBodyExited)
	if b2.Body_IsValid(area.bodyId) {
		b2.DestroyBody(area.bodyId)
		area.bodyId = b2.nullBodyId
	}
}

// ============================================================================
// 5. RaycastNode (Raycast - Casts a ray in a direction and length)
// ============================================================================
RaycastNode :: struct {
	using node: Node,
	direction: [2]f32 `gui:"true" min:"-1" max:"1"`,
	length: f32 `gui:"true" min:"1" max:"2000"`,
	collideWithSensors: bool `gui:"true"`,
	categoryLayers: CollisionLayerSet `gui:"true"`,
	maskLayers: CollisionLayerSet `gui:"true"`,
	isColliding: bool `gui:"true"`,
	hitFraction: f32 `gui:"true" min:"0" max:"1"`,
	hitPoint: [2]f32 `gui:"true" min:"0" max:"1280"`,
	hitNormal: [2]f32 `gui:"true" min:"-1" max:"1"`,
	hitShapeId: b2.ShapeId,
	hitNode: ^Node,
	excludeNode: ^Node,
	rayColor: rl.Color `gui:"true"`,
	hitColor: rl.Color `gui:"true"`,
}

Raycast :: RaycastNode

RaycastNode_Create :: proc(scene: ^Scene, name: string = "Raycast", parent: ^Node = nil) -> ^RaycastNode {
	rc := CreateNode(scene.manager, RaycastNode)
	rc.name = name
	rc.position = {450, 260}
	rc.direction = {1.0, 0.5}
	rc.length = 450.0
	rc.collideWithSensors = false
	rc.categoryLayers = DEFAULT_COLLISION_CATEGORIES
	rc.maskLayers = DEFAULT_COLLISION_MASK
	rc.rayColor = rl.Color{56, 189, 248, 255} // Cyan
	rc.hitColor = rl.Color{248, 113, 113, 255} // Red
	rc.update = RaycastNode_Update
	rc.render = RaycastNode_Render
	scene->addNode(rc, parent)
	return rc
}

Raycast_Callback :: proc "c" (shapeId: b2.ShapeId, point: b2.Vec2, normal: b2.Vec2, fraction: f32, ctx: rawptr) -> f32 {
	if ctx == nil || !b2.Shape_IsValid(shapeId) do return 1.0
	rc := cast(^RaycastNode)ctx

	if !rc.collideWithSensors && b2.Shape_IsSensor(shapeId) {
		return -1.0 // Ignore sensor and continue raycast
	}

	bodyId := b2.Shape_GetBody(shapeId)
	hitNode: ^Node = nil
	if b2.Body_IsValid(bodyId) {
		hitNode = cast(^Node)b2.Body_GetUserData(bodyId)
	}
	if rc.excludeNode != nil && hitNode == rc.excludeNode {
		return -1.0 // Ignore excluded node and continue
	}

	rc.isColliding = true
	rc.hitShapeId = shapeId
	rc.hitPoint = point
	rc.hitNormal = normal
	rc.hitFraction = fraction
	rc.hitNode = hitNode

	return fraction // Clip ray to closest hit
}

RaycastNode_GetTranslation :: proc(rc: ^RaycastNode) -> [2]f32 {
	dir := rc.direction
	if b2.LengthSquared(dir) > 0.0001 {
		dir = b2.Normalize(dir)
	} else {
		dir = {0, 1}
	}
	rot := DegreesToRot(rc.rotation)
	worldDir := b2.RotateVector(rot, dir)
	return worldDir * max(rc.length, 1.0)
}

RaycastNode_CastNow :: proc(rc: ^RaycastNode, worldId: b2.WorldId) {
	rc.isColliding = false
	rc.hitFraction = 1.0
	rc.hitShapeId = b2.nullShapeId
	rc.hitNode = nil

	if !b2.World_IsValid(worldId) do return

	origin := rc.globalPosition if (rc.globalPosition.x != 0 || rc.globalPosition.y != 0) else rc.position
	translation := RaycastNode_GetTranslation(rc)
	rc.hitPoint = origin + translation
	rc.hitNormal = {0, 0}

	qFilter := b2.QueryFilter{
		categoryBits = CollisionLayerSet_ToBits(rc.categoryLayers),
		maskBits     = CollisionLayerSet_ToBits(rc.maskLayers),
	}

	_ = b2.World_CastRay(worldId, origin, translation, qFilter, Raycast_Callback, cast(rawptr)rc)
}

RaycastNode_Update :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	rc := cast(^RaycastNode)node
	if !rc.enabled do return
	if gameContext == nil || gameContext.game == nil do return

	RaycastNode_CastNow(rc, gameContext.game.physicsWorld.worldId)
}

RaycastNode_Render :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	if !rl.IsWindowReady() do return
	rc := cast(^RaycastNode)node
	if gameContext != nil && gameContext.game != nil && !gameContext.game.physicsWorld.drawPhysicsDebug {
		return
	}

	origin := rc.position
	endPt := origin + RaycastNode_GetTranslation(rc)

	rl.DrawCircleV(origin, 4.0, rc.rayColor)
	if rc.isColliding {
		rl.DrawLineEx(origin, rc.hitPoint, 2.0, rc.hitColor)
		rl.DrawLineEx(rc.hitPoint, endPt, 1.0, rl.Color{rc.rayColor.r, rc.rayColor.g, rc.rayColor.b, 80})
		rl.DrawCircleV(rc.hitPoint, 5.0, rc.hitColor)
		// Draw surface normal at hit point
		rl.DrawLineEx(rc.hitPoint, rc.hitPoint + rc.hitNormal * 20.0, 2.0, rl.YELLOW)
	} else {
		rl.DrawLineEx(origin, endPt, 2.0, rc.rayColor)
	}
}

// ============================================================================
// Scene Physics Body Activation Helpers
// ============================================================================
Node_SetPhysicsEnabled :: proc(node: ^Node, enabled: bool) {
	if node == nil do return
	bodyId: b2.BodyId
	if node.onDestroy == StaticBodyNode_Destroy {
		bodyId = (cast(^StaticBodyNode)node).bodyId
	} else if node.onDestroy == DynamicBodyNode_Destroy {
		bodyId = (cast(^DynamicBodyNode)node).bodyId
	} else if node.onDestroy == CharacterMoverNode_Destroy {
		bodyId = (cast(^CharacterMoverNode)node).bodyId
	} else if node.onDestroy == AreaNode_Destroy {
		bodyId = (cast(^AreaNode)node).bodyId
	}
	if b2.Body_IsValid(bodyId) {
		if enabled && node.enabled {
			if !b2.Body_IsEnabled(bodyId) {
				b2.Body_Enable(bodyId)
			}
		} else {
			if b2.Body_IsEnabled(bodyId) {
				b2.Body_Disable(bodyId)
			}
		}
	}
}

Scene_SetPhysicsEnabled :: proc(scene: ^Scene, enabled: bool) {
	if scene == nil || scene.manager == nil do return
	for node in scene.manager.nodes {
		if node != nil {
			Node_SetPhysicsEnabled(node, enabled)
		}
	}
	for addNode in scene.manager.addition {
		if addNode != nil {
			Node_SetPhysicsEnabled(addNode, enabled)
		}
	}
}
