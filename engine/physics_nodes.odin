package engine

import "core:strings"
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
	// One way: bodies pass through from below and land on top (the
	// node's rotation turns "top"); e.g. jump-through platforms.
	oneWay: bool `gui:"true"`,
	oneWayApplied: bool,
	lastSyncedPos: [2]f32,
	lastSyncedRot: f32,
	onCollisionStarted: EventSubject, // "collision_started"(other node)
	onCollisionEnded: EventSubject,   // "collision_ended"(other node)
}

StaticBody :: StaticBodyNode

StaticBodyNode_Create :: proc(scene: ^Scene, name: string = "StaticBody", parent: ^Node = nil) -> ^StaticBodyNode {
	sb := CreateNode(scene.manager, StaticBodyNode)
	sb.name = strings.clone(name, sb.allocator) // owned: callers pass temp strings too
	sb.position = {640, 620}
	sb.debugColor = rl.Color{74, 222, 128, 255} // Green
	sb.shapes = make([dynamic]PhysicsShape, sb.allocator)
	sb.update = StaticBodyNode_Update
	sb.render = StaticBodyNode_Render
	sb.onDestroy = StaticBodyNode_Destroy
	InitializeSubject(&sb.onCollisionStarted, "collision_started", sb)
	InitializeSubject(&sb.onCollisionEnded, "collision_ended", sb)
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
	def.position = sb.globalPosition
	def.rotation = DegreesToRot(sb.globalRotation)
	def.userData = cast(rawptr)(cast(^Node)sb)
	sb.bodyId = b2.CreateBody(worldId, def)
	sb.lastSyncedPos = sb.globalPosition
	sb.lastSyncedRot = sb.globalRotation

	for &shape in sb.shapes {
		PhysicsShape_AttachToBody(&shape, sb.bodyId, cast(rawptr)(cast(^Node)sb), sb.globalScale)
	}
}

StaticBodyNode_AddShape :: proc(sb: ^StaticBodyNode, shape: PhysicsShape, gameContext: ^GameContext = nil) -> ^PhysicsShape {
	shape := shape
	if sb.oneWay do shape.enablePreSolveEvents = true
	append(&sb.shapes, shape)
	ptr := &sb.shapes[len(sb.shapes) - 1]
	if gameContext != nil {
		StaticBodyNode_EnsureBody(sb, gameContext)
	}
	if b2.Body_IsValid(sb.bodyId) {
		PhysicsShape_AttachToBody(ptr, sb.bodyId, cast(rawptr)(cast(^Node)sb), sb.globalScale)
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

	// Follow the node's world transform (moved directly, by a script, or by
	// a moving parent).
	moved := b2.Distance(sb.globalPosition, sb.lastSyncedPos) > 0.01 || abs(sb.globalRotation - sb.lastSyncedRot) > 0.01
	if moved {
		b2.Body_SetTransform(sb.bodyId, sb.globalPosition, DegreesToRot(sb.globalRotation))
		sb.lastSyncedPos = sb.globalPosition
		sb.lastSyncedRot = sb.globalRotation
	}
	if sb.oneWay != sb.oneWayApplied || (sb.oneWay && moved) {
		// Pre-solve events on its shapes; "top" turns with the node.
		for &shape in sb.shapes do shape.enablePreSolveEvents = sb.oneWay
		worldId := gameContext.game.physicsWorld.worldId if gameContext != nil && gameContext.game != nil else b2.WorldId{}
		Physics_SetOneWay(sb, sb.oneWay, rotate_vec({0, -1}, sb.globalRotation), worldId)
		sb.oneWayApplied = sb.oneWay
	}

	for &shape in sb.shapes {
		PhysicsShape_SyncToBox2D(&shape, sb.bodyId, cast(rawptr)node, sb.globalScale)
	}
}

StaticBodyNode_Render :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	sb := cast(^StaticBodyNode)node
	if gameContext != nil && gameContext.game != nil && !gameContext.game.physicsWorld.drawPhysicsDebug {
		return
	}
	for &shape in sb.shapes {
		PhysicsShape_DrawDebug(&shape, sb.globalPosition, sb.globalRotation, sb.debugColor, sb.globalScale)
	}
}

StaticBodyNode_Destroy :: proc(node: ^Node, gameContext: ^GameContext) {
	sb := cast(^StaticBodyNode)node
	Physics_SetOneWay(sb, false)
	DestroySubject(&sb.onCollisionStarted)
	DestroySubject(&sb.onCollisionEnded)
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
	syncedParams:     [5]f32, // damping, angular damping, gravity scale, sleep threshold, sleep enabled
	paramsSynced:     bool,
	onCollisionStarted: EventSubject, // "collision_started"(other node)
	onCollisionEnded: EventSubject,   // "collision_ended"(other node)
}

DynamicBody :: DynamicBodyNode

DynamicBodyNode_Create :: proc(scene: ^Scene, name: string = "DynamicBody", parent: ^Node = nil) -> ^DynamicBodyNode {
	db := CreateNode(scene.manager, DynamicBodyNode)
	db.name = strings.clone(name, db.allocator) // owned: callers pass temp strings too
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
	InitializeSubject(&db.onCollisionStarted, "collision_started", db)
	InitializeSubject(&db.onCollisionEnded, "collision_ended", db)
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
	def.position = db.globalPosition
	def.rotation = DegreesToRot(db.globalRotation)
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
	db.paramsSynced = false
	db.lastSyncedPos = db.globalPosition
	db.lastSyncedRot = db.globalRotation
	db.lastSyncedVel = db.linearVelocity
	db.lastSyncedAngVel = db.angularVelocity

	for &shape in db.shapes {
		PhysicsShape_AttachToBody(&shape, db.bodyId, cast(rawptr)(cast(^Node)db), db.globalScale)
	}
}

DynamicBodyNode_AddShape :: proc(db: ^DynamicBodyNode, shape: PhysicsShape, gameContext: ^GameContext = nil) -> ^PhysicsShape {
	append(&db.shapes, shape)
	ptr := &db.shapes[len(db.shapes) - 1]
	if gameContext != nil {
		DynamicBodyNode_EnsureBody(db, gameContext)
	}
	if b2.Body_IsValid(db.bodyId) {
		PhysicsShape_AttachToBody(ptr, db.bodyId, cast(rawptr)(cast(^Node)db), db.globalScale)
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
	if b2.Distance(db.globalPosition, db.lastSyncedPos) > 0.5 || abs(db.globalRotation - db.lastSyncedRot) > 0.5 {
		b2.Body_SetTransform(db.bodyId, db.globalPosition, DegreesToRot(db.globalRotation))
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

	// Sync dynamic parameters (only when they changed).
	params := [5]f32{db.linearDamping, db.angularDamping, db.gravityScale, db.sleepThreshold, 1 if db.enableSleep else 0}
	if !db.paramsSynced || params != db.syncedParams {
		b2.Body_SetLinearDamping(db.bodyId, db.linearDamping)
		b2.Body_SetAngularDamping(db.bodyId, db.angularDamping)
		b2.Body_SetGravityScale(db.bodyId, db.gravityScale)
		b2.Body_SetSleepThreshold(db.bodyId, db.sleepThreshold)
		b2.Body_EnableSleep(db.bodyId, db.enableSleep)
		db.syncedParams = params
		db.paramsSynced = true
	}
	if b2.Body_IsFixedRotation(db.bodyId) != db.fixedRotation {
		b2.Body_SetFixedRotation(db.bodyId, db.fixedRotation)
	}
	if b2.Body_IsBullet(db.bodyId) != db.isBullet {
		b2.Body_SetBullet(db.bodyId, db.isBullet)
	}

	for &shape in db.shapes {
		PhysicsShape_SyncToBox2D(&shape, db.bodyId, cast(rawptr)node, db.globalScale)
	}

	// Read back simulated state from Box2D (world space -> parent space)
	Physics_SetWorldTransform(db, b2.Body_GetPosition(db.bodyId), RotToDegrees(b2.Body_GetRotation(db.bodyId)))
	db.linearVelocity = b2.Body_GetLinearVelocity(db.bodyId)
	db.angularVelocity = math.to_degrees(b2.Body_GetAngularVelocity(db.bodyId))
	db.isAwake = b2.Body_IsAwake(db.bodyId)

	db.lastSyncedPos = db.globalPosition
	db.lastSyncedRot = db.globalRotation
	db.lastSyncedVel = db.linearVelocity
	db.lastSyncedAngVel = db.angularVelocity
}

DynamicBodyNode_Render :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	db := cast(^DynamicBodyNode)node
	if gameContext != nil && gameContext.game != nil && !gameContext.game.physicsWorld.drawPhysicsDebug {
		return
	}
	for &shape in db.shapes {
		PhysicsShape_DrawDebug(&shape, db.globalPosition, db.globalRotation, db.debugColor, db.globalScale)
	}
}

DynamicBodyNode_Destroy :: proc(node: ^Node, gameContext: ^GameContext) {
	db := cast(^DynamicBodyNode)node
	DestroySubject(&db.onCollisionStarted)
	DestroySubject(&db.onCollisionEnded)
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
	velocity: [2]f32 `gui:"true" min:"-1000" max:"1000" save:"false"`,
	targetSpeedX: f32 `gui:"true" min:"-600" max:"600" save:"false"`,
	maxSpeed: f32 `gui:"true" min:"10" max:"1000"`,
	acceleration: f32 `gui:"true" min:"10" max:"5000"`,
	jumpSpeed: f32 `gui:"true" min:"10" max:"1200"`,
	gravityScale: f32 `gui:"true" min:"0" max:"5"`,
	pushLimit: f32 `gui:"true" min:"0" max:"1000"`,
	clipVelocity: bool `gui:"true"`,
	enableKeyboardInput: bool `gui:"true"`,
	isGrounded: bool `gui:"true" save:"false"`,
	categoryLayers: CollisionLayerSet `gui:"true"`,
	maskLayers: CollisionLayerSet `gui:"true"`,
	debugColor: rl.Color `gui:"true"`,
	// Built-in: the node moves itself (maxSpeed, acceleration, jumpSpeed,
	// gravity, optional keyboard input). Script: like Godot's CharacterBody2D,
	// the script sets the velocity and calls character_move_and_slide().
	controlMode: CharacterMoverMode `gui:"true"`,
	isOnFloor: bool `save:"false"`,
	isOnWall: bool `save:"false"`,
	isOnCeiling: bool `save:"false"`,
	floorNormal: [2]f32 `save:"false"`,
	wallNormal: [2]f32 `save:"false"`,
	lastMotion: [2]f32 `save:"false"`,
	frameDelta: f32 `save:"false"`, // delta of the current frame (move_and_slide's default)
	collisionPlanes: [MAX_MOVER_PLANES]b2.CollisionPlane,
	planeCount: int,
	onCollisionStarted: EventSubject, // "collision_started"(other node)
	onCollisionEnded: EventSubject,   // "collision_ended"(other node)
}

CharacterMoverMode :: enum {
	BuiltIn, // moves itself each frame
	Script,  // moves only when the script calls character_move_and_slide()
}

CharacterMover :: CharacterMoverNode

CharacterMoverNode_Create :: proc(scene: ^Scene, name: string = "CharacterMover", parent: ^Node = nil) -> ^CharacterMoverNode {
	cm := CreateNode(scene.manager, CharacterMoverNode)
	cm.name = strings.clone(name, cm.allocator) // owned: callers pass temp strings too
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
	InitializeSubject(&cm.onCollisionStarted, "collision_started", cm)
	InitializeSubject(&cm.onCollisionEnded, "collision_ended", cm)
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
	// Scaled like its collider: radius by x, length by y.
	sc := cm.globalScale
	if sc.x == 0 && sc.y == 0 do sc = {1, 1}
	r *= abs(sc.x)
	h *= abs(sc.y)
	offset *= sc
	halfLen := h * 0.5
	rot := DegreesToRot(cm.globalRotation)
	dir := b2.RotateVector(rot, b2.Vec2{0, halfLen})
	center := cm.globalPosition + b2.RotateVector(rot, offset)
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
	def.position = cm.globalPosition
	def.rotation = DegreesToRot(cm.globalRotation)
	def.userData = cast(rawptr)(cast(^Node)cm)
	cm.bodyId = b2.CreateBody(worldId, def)

	for &shape in cm.shapes {
		shape.categoryLayers = cm.categoryLayers
		shape.maskLayers = cm.maskLayers
		PhysicsShape_AttachToBody(&shape, cm.bodyId, cast(rawptr)(cast(^Node)cm), cm.globalScale)
	}
}

CharacterMoverNode_AddShape :: proc(cm: ^CharacterMoverNode, shape: PhysicsShape, gameContext: ^GameContext = nil) -> ^PhysicsShape {
	append(&cm.shapes, shape)
	ptr := &cm.shapes[len(cm.shapes) - 1]
	if b2.Body_IsValid(cm.bodyId) {
		PhysicsShape_AttachToBody(ptr, cm.bodyId, cast(rawptr)(cast(^Node)cm), cm.globalScale)
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

	cm.frameDelta = deltaTime
	// Script mode: the script moves the node (character_move_and_slide).
	if cm.controlMode == .Script do return

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

	CharacterMoverNode_MoveAndSlide(cm, gameContext, deltaTime)
}

// CharacterMoverNode_Gravity: the world's gravity scaled by gravityScale.
CharacterMoverNode_Gravity :: proc(cm: ^CharacterMoverNode, gameContext: ^GameContext) -> [2]f32 {
	if gameContext == nil || gameContext.game == nil do return {}
	return gameContext.game.physicsWorld.gravity * cm.gravityScale
}

// CharacterMoverNode_MoveAndSlide moves the capsule by velocity * dt,
// sliding along whatever it touches (the velocity loses the part going into
// surfaces when clipVelocity is on), and updates the floor / wall / ceiling
// state. Returns true if it touched anything.
CharacterMoverNode_MoveAndSlide :: proc(cm: ^CharacterMoverNode, gameContext: ^GameContext, deltaTime: f32) -> bool {
	if gameContext == nil || gameContext.game == nil || deltaTime <= 0.00001 do return false
	pw := &gameContext.game.physicsWorld
	if !b2.World_IsValid(pw.worldId) || pw.paused do return false
	CharacterMoverNode_EnsureProxyBody(cm, pw.worldId)

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

	// 3. Contact state from the plane normals (screen coordinates, +Y down:
	// a floor's normal points up, y < -0.5) and velocity clipping.
	cm.isOnFloor, cm.isOnWall, cm.isOnCeiling = false, false, false
	cm.floorNormal, cm.wallNormal = {}, {}
	for i in 0..<cm.planeCount {
		n := cm.collisionPlanes[i].plane.normal
		switch {
		case n.y < -0.5:
			cm.isOnFloor = true
			cm.floorNormal = n
		case n.y > 0.5:
			cm.isOnCeiling = true
		case:
			cm.isOnWall = true
			cm.wallNormal = n
		}
	}
	cm.isGrounded = cm.isOnFloor
	if cm.planeCount > 0 && cm.clipVelocity {
		cm.velocity = b2.ClipVector(cm.velocity, planesSlice)
	}

	// 4. Cast mover along solved translation to prevent tunneling (World_CastMover)
	fraction := b2.World_CastMover(pw.worldId, moverCapsule, solverResult.translation, qFilter)
	delta := solverResult.translation * fraction
	cm.lastMotion = delta
	Physics_SetWorldTransform(cm, cm.globalPosition + delta, cm.globalRotation)

	// Sync kinematic proxy body so sensors (AreaNode) and dynamic bodies interact with the mover
	if b2.Body_IsValid(cm.bodyId) {
		b2.Body_SetTargetTransform(cm.bodyId, b2.Transform{p = cm.globalPosition, q = DegreesToRot(cm.globalRotation)}, deltaTime)
		for &shape in cm.shapes {
			shape.categoryLayers = cm.categoryLayers
			shape.maskLayers = cm.maskLayers
			PhysicsShape_SyncToBox2D(&shape, cm.bodyId, cast(rawptr)(cast(^Node)cm), cm.globalScale)
		}
	}
	return cm.planeCount > 0
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
	DestroySubject(&cm.onCollisionStarted)
	DestroySubject(&cm.onCollisionEnded)
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
	overlapCount: int `gui:"true" min:"0" max:"100" save:"false"`,
	hasOverlaps: bool `gui:"true" save:"false"`,
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
	area.name = strings.clone(name, area.allocator) // owned: callers pass temp strings too
	area.position = {640, 460}
	area.debugColor = rl.Color{168, 85, 247, 255}  // Purple
	area.activeColor = rl.Color{236, 72, 153, 255} // Pink when overlapping
	area.shapes = make([dynamic]PhysicsShape, area.allocator)
	area.overlappingNodes = make([dynamic]^Node, area.allocator)
	InitializeSubject(&area.onBodyEntered, "body_entered", area)
	InitializeSubject(&area.onBodyExited, "body_exited", area)
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
	def.position = area.globalPosition
	def.rotation = DegreesToRot(area.globalRotation)
	def.userData = cast(rawptr)(cast(^Node)area)
	area.bodyId = b2.CreateBody(worldId, def)
	area.lastSyncedPos = area.globalPosition
	area.lastSyncedRot = area.globalRotation

	for &shape in area.shapes {
		shape.isSensor = true
		shape.enableSensorEvents = true
		PhysicsShape_AttachToBody(&shape, area.bodyId, cast(rawptr)(cast(^Node)area), area.globalScale)
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
		PhysicsShape_AttachToBody(ptr, area.bodyId, cast(rawptr)(cast(^Node)area), area.globalScale)
	}
	return ptr
}

AreaNode_RemoveShape :: proc(area: ^AreaNode, index: int) {
	if index < 0 || index >= len(area.shapes) do return
	PhysicsShape_Destroy(&area.shapes[index])
	ordered_remove(&area.shapes, index)
}

AreaNode_HandleEnter :: proc(sensorNode: ^Node, visitorNode_in: ^Node, gameContext: ^GameContext) {
	if sensorNode == nil || !Node_IsAlive(sensorNode) do return
	visitorNode := visitorNode_in if Node_IsAlive(visitorNode_in) else nil

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
	area.onBodyEntered->notify(area, visitorNode, gameContext)
}

AreaNode_HandleExit :: proc(sensorNode: ^Node, visitorNode_in: ^Node, gameContext: ^GameContext) {
	if sensorNode == nil || !Node_IsAlive(sensorNode) do return
	visitorNode := visitorNode_in if Node_IsAlive(visitorNode_in) else nil

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
	area.onBodyExited->notify(area, visitorNode, gameContext)
}

AreaNode_Update :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	area := cast(^AreaNode)node
	// Visitors destroyed while overlapping leave the list (and report exit).
	for i := len(area.overlappingNodes) - 1; i >= 0; i -= 1 {
		if !Node_IsAlive(area.overlappingNodes[i]) {
			unordered_remove(&area.overlappingNodes, i)
			area.onBodyExited->notify(area, nil, gameContext)
		}
	}
	area.overlapCount = len(area.overlappingNodes)
	area.hasOverlaps = area.overlapCount > 0
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

	if b2.Distance(area.globalPosition, area.lastSyncedPos) > 0.01 || abs(area.globalRotation - area.lastSyncedRot) > 0.01 {
		b2.Body_SetTransform(area.bodyId, area.globalPosition, DegreesToRot(area.globalRotation))
		area.lastSyncedPos = area.globalPosition
		area.lastSyncedRot = area.globalRotation
	}

	for &shape in area.shapes {
		shape.isSensor = true
		shape.enableSensorEvents = true
		PhysicsShape_SyncToBox2D(&shape, area.bodyId, cast(rawptr)node, area.globalScale)
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
		PhysicsShape_DrawDebug(&shape, area.globalPosition, area.globalRotation, color, area.globalScale)
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
	isColliding: bool `gui:"true" save:"false"`,
	hitFraction: f32 `gui:"true" min:"0" max:"1" save:"false"`,
	hitPoint: [2]f32 `gui:"true" min:"0" max:"1280" save:"false"`,
	hitNormal: [2]f32 `gui:"true" min:"-1" max:"1" save:"false"`,
	hitShapeId: b2.ShapeId,
	hitNode: ^Node,
	excludeNode: ^Node,
	rayColor: rl.Color `gui:"true"`,
	hitColor: rl.Color `gui:"true"`,
	onHitStarted: EventSubject, // "hit_started"(node): the ray started hitting a node
	onHitEnded: EventSubject,   // "hit_ended"(node): the ray stopped hitting it
}

Raycast :: RaycastNode

RaycastNode_Create :: proc(scene: ^Scene, name: string = "Raycast", parent: ^Node = nil) -> ^RaycastNode {
	rc := CreateNode(scene.manager, RaycastNode)
	rc.name = strings.clone(name, rc.allocator) // owned: callers pass temp strings too
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
	rc.onDestroy = RaycastNode_Destroy
	InitializeSubject(&rc.onHitStarted, "hit_started", rc)
	InitializeSubject(&rc.onHitEnded, "hit_ended", rc)
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

	prevHit := rc.hitNode if rc.isColliding else nil
	RaycastNode_CastNow(rc, gameContext.game.physicsWorld.worldId)
	curHit := rc.hitNode if rc.isColliding else nil
	if prevHit != curHit {
		if prevHit != nil && Node_IsAlive(prevHit) do rc.onHitEnded->notify(rc, prevHit, gameContext)
		if curHit != nil do rc.onHitStarted->notify(rc, curHit, gameContext)
	}
}

RaycastNode_Destroy :: proc(node: ^Node, gameContext: ^GameContext) {
	rc := cast(^RaycastNode)node
	DestroySubject(&rc.onHitStarted)
	DestroySubject(&rc.onHitEnded)
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

// Physics_SetWorldTransform writes a world-space transform from Box2D back to
// a node: local position/rotation are expressed in the parent's space, so
// bodies parented under moved/rotated nodes stay where physics put them.
Physics_SetWorldTransform :: proc(node: ^Node, worldPos: [2]f32, worldRot: f32) {
	parentRot := node.globalRotation - node.rotation
	if node.gameContext != nil && node.gameContext.scene != nil && node.gameContext.scene.manager != nil {
		node.position = Node_WorldToParent(node.gameContext.scene.manager, node, worldPos)
	} else {
		node.position = worldPos - (node.globalPosition - node.position)
	}
	node.rotation = worldRot - parentRot
	node.globalPosition = worldPos
	node.globalRotation = worldRot
}
