package engine

import b2 "vendor:box2d"
import rl "vendor:raylib"

PhysicsShapeType :: enum {
	Circle,
	Capsule,
	Box,
	RoundedBox,
	Polygon,
	Segment,
	Chain,
}

PhysicsShape :: struct {
	shapeId: b2.ShapeId,
	chainId: b2.ChainId,
	type: PhysicsShapeType `gui:"true"`,
	offset: [2]f32 `gui:"true" min:"-500" max:"500"`,
	rotation: f32 `gui:"true" min:"0" max:"360"`,

	// Dimensions
	radius: f32 `gui:"true" min:"1" max:"500"`,
	size: [2]f32 `gui:"true" min:"1" max:"1000"`, // Width and Height (Box / Capsule)
	cornerRadius: f32 `gui:"true" min:"0" max:"100"`,
	point1: [2]f32 `gui:"true" min:"-500" max:"500"`,
	point2: [2]f32 `gui:"true" min:"-500" max:"500"`,
	vertices: [b2.MAX_POLYGON_VERTICES][2]f32,
	vertexCount: int `gui:"true" min:"3" max:"8"`,
	chainPoints: [dynamic][2]f32,
	isLoop: bool `gui:"true"`,

	// Material & Mass
	density: f32 `gui:"true" min:"0" max:"100"`,
	friction: f32 `gui:"true" min:"0" max:"2"`,
	restitution: f32 `gui:"true" min:"0" max:"1"`,
	rollingResistance: f32 `gui:"true" min:"0" max:"1"`,
	tangentSpeed: f32 `gui:"true" min:"-500" max:"500"`,

	// Events & Sensor
	isSensor: bool `gui:"true"`,
	enableSensorEvents: bool `gui:"true"`,
	enableContactEvents: bool `gui:"true"`,
	enableHitEvents: bool `gui:"true"`,
	enablePreSolveEvents: bool `gui:"true"`,

	// Collision Filtering (Layers)
	categoryLayers: CollisionLayerSet `gui:"true"`,
	maskLayers: CollisionLayerSet `gui:"true"`,
	groupIndex: int `gui:"true" min:"-100" max:"100"`,
}

PhysicsShape_InitDefault :: proc(shape: ^PhysicsShape, type: PhysicsShapeType = .Box) {
	shape.shapeId = b2.nullShapeId
	shape.chainId = b2.nullChainId
	shape.type = type
	shape.offset = {0, 0}
	shape.rotation = 0
	shape.radius = 20
	shape.size = {40, 40}
	shape.cornerRadius = 4
	shape.point1 = {-25, 0}
	shape.point2 = {25, 0}
	shape.vertexCount = 4
	shape.vertices[0] = {-20, -20}
	shape.vertices[1] = {20, -20}
	shape.vertices[2] = {20, 20}
	shape.vertices[3] = {-20, 20}
	shape.isLoop = false

	shape.density = 1.0
	shape.friction = 0.6
	shape.restitution = 0.2
	shape.rollingResistance = 0.0
	shape.tangentSpeed = 0.0

	shape.isSensor = false
	shape.enableSensorEvents = true
	shape.enableContactEvents = true
	shape.enableHitEvents = false
	shape.enablePreSolveEvents = false

	shape.categoryLayers = DEFAULT_COLLISION_CATEGORIES
	shape.maskLayers = DEFAULT_COLLISION_MASK
	shape.groupIndex = 0
}

PhysicsShape_BuildDef :: proc(shape: ^PhysicsShape, userData: rawptr = nil) -> b2.ShapeDef {
	def := b2.DefaultShapeDef()
	def.userData = userData
	def.density = shape.density
	def.material.friction = shape.friction
	def.material.restitution = shape.restitution
	def.material.rollingResistance = shape.rollingResistance
	def.material.tangentSpeed = shape.tangentSpeed
	def.isSensor = shape.isSensor
	def.enableSensorEvents = shape.enableSensorEvents
	def.enableContactEvents = shape.enableContactEvents
	def.enableHitEvents = shape.enableHitEvents
	def.enablePreSolveEvents = shape.enablePreSolveEvents
	def.filter = b2.Filter{
		categoryBits = CollisionLayerSet_ToBits(shape.categoryLayers),
		maskBits     = CollisionLayerSet_ToBits(shape.maskLayers),
		groupIndex   = i32(shape.groupIndex),
	}
	return def
}

PhysicsShape_AttachToBody :: proc(shape: ^PhysicsShape, bodyId: b2.BodyId, userData: rawptr = nil) {
	if !b2.Body_IsValid(bodyId) do return

	PhysicsShape_Destroy(shape)

	def := PhysicsShape_BuildDef(shape, userData)
	rot := DegreesToRot(shape.rotation)

	switch shape.type {
	case .Circle:
		circle := b2.Circle{
			center = shape.offset,
			radius = max(shape.radius, 0.5),
		}
		shape.shapeId = b2.CreateCircleShape(bodyId, def, circle)

	case .Capsule:
		halfLen := max(shape.size[1] * 0.5, 0.5)
		dir := b2.RotateVector(rot, b2.Vec2{0, halfLen})
		capsule := b2.Capsule{
			center1 = shape.offset - dir,
			center2 = shape.offset + dir,
			radius  = max(shape.radius, 0.5),
		}
		shape.shapeId = b2.CreateCapsuleShape(bodyId, def, capsule)

	case .Box:
		hw := max(shape.size[0] * 0.5, 0.5)
		hh := max(shape.size[1] * 0.5, 0.5)
		poly := b2.MakeOffsetBox(hw, hh, shape.offset, rot)
		shape.shapeId = b2.CreatePolygonShape(bodyId, def, poly)

	case .RoundedBox:
		hw := max(shape.size[0] * 0.5, 0.5)
		hh := max(shape.size[1] * 0.5, 0.5)
		r := max(shape.cornerRadius, 0.0)
		poly := b2.MakeOffsetRoundedBox(hw, hh, shape.offset, rot, r)
		shape.shapeId = b2.CreatePolygonShape(bodyId, def, poly)

	case .Polygon:
		count := clamp(shape.vertexCount, 3, int(b2.MAX_POLYGON_VERTICES))
		hull := b2.ComputeHull(shape.vertices[:count])
		if b2.ValidateHull(hull) {
			poly := b2.MakeOffsetPolygon(hull, shape.offset, rot)
			shape.shapeId = b2.CreatePolygonShape(bodyId, def, poly)
		} else {
			hw := max(shape.size[0] * 0.5, 0.5)
			hh := max(shape.size[1] * 0.5, 0.5)
			poly := b2.MakeOffsetBox(hw, hh, shape.offset, rot)
			shape.shapeId = b2.CreatePolygonShape(bodyId, def, poly)
		}

	case .Segment:
		seg := b2.Segment{
			point1 = shape.offset + b2.RotateVector(rot, shape.point1),
			point2 = shape.offset + b2.RotateVector(rot, shape.point2),
		}
		shape.shapeId = b2.CreateSegmentShape(bodyId, def, seg)

	case .Chain:
		if len(shape.chainPoints) >= 4 {
			cdef := b2.DefaultChainDef()
			cdef.userData = userData
			cdef.points = raw_data(shape.chainPoints)
			cdef.count = i32(len(shape.chainPoints))
			cdef.isLoop = shape.isLoop
			cdef.enableSensorEvents = shape.enableSensorEvents
			cdef.filter = def.filter
			shape.chainId = b2.CreateChain(bodyId, cdef)
		} else {
			// Fallback to segment if fewer than 4 chain points
			seg := b2.Segment{
				point1 = shape.offset + shape.point1,
				point2 = shape.offset + shape.point2,
			}
			shape.shapeId = b2.CreateSegmentShape(bodyId, def, seg)
		}
	}
}

PhysicsShape_SyncToBox2D :: proc(shape: ^PhysicsShape, bodyId: b2.BodyId, userData: rawptr = nil) {
	if b2.Shape_IsValid(shape.shapeId) {
		b2.Shape_SetDensity(shape.shapeId, shape.density, true)
		b2.Shape_SetFriction(shape.shapeId, shape.friction)
		b2.Shape_SetRestitution(shape.shapeId, shape.restitution)
		b2.Shape_SetFilter(shape.shapeId, b2.Filter{
			categoryBits = CollisionLayerSet_ToBits(shape.categoryLayers),
			maskBits     = CollisionLayerSet_ToBits(shape.maskLayers),
			groupIndex   = i32(shape.groupIndex),
		})
		b2.Shape_EnableSensorEvents(shape.shapeId, shape.enableSensorEvents)
		b2.Shape_EnableContactEvents(shape.shapeId, shape.enableContactEvents)
		b2.Shape_EnableHitEvents(shape.shapeId, shape.enableHitEvents)
		b2.Shape_EnablePreSolveEvents(shape.shapeId, shape.enablePreSolveEvents)

		rot := DegreesToRot(shape.rotation)
		#partial switch shape.type {
		case .Circle:
			b2.Shape_SetCircle(shape.shapeId, b2.Circle{
				center = shape.offset,
				radius = max(shape.radius, 0.5),
			})
		case .Capsule:
			halfLen := max(shape.size[1] * 0.5, 0.5)
			dir := b2.RotateVector(rot, b2.Vec2{0, halfLen})
			b2.Shape_SetCapsule(shape.shapeId, b2.Capsule{
				center1 = shape.offset - dir,
				center2 = shape.offset + dir,
				radius  = max(shape.radius, 0.5),
			})
		case .Box:
			hw := max(shape.size[0] * 0.5, 0.5)
			hh := max(shape.size[1] * 0.5, 0.5)
			b2.Shape_SetPolygon(shape.shapeId, b2.MakeOffsetBox(hw, hh, shape.offset, rot))
		case .RoundedBox:
			hw := max(shape.size[0] * 0.5, 0.5)
			hh := max(shape.size[1] * 0.5, 0.5)
			b2.Shape_SetPolygon(shape.shapeId, b2.MakeOffsetRoundedBox(hw, hh, shape.offset, rot, max(shape.cornerRadius, 0.0)))
		case .Segment:
			b2.Shape_SetSegment(shape.shapeId, b2.Segment{
				point1 = shape.offset + b2.RotateVector(rot, shape.point1),
				point2 = shape.offset + b2.RotateVector(rot, shape.point2),
			})
		}
	} else if b2.Body_IsValid(bodyId) {
		PhysicsShape_AttachToBody(shape, bodyId, userData)
	}
}

PhysicsShape_Destroy :: proc(shape: ^PhysicsShape) {
	if b2.Shape_IsValid(shape.shapeId) {
		b2.DestroyShape(shape.shapeId, true)
		shape.shapeId = b2.nullShapeId
	}
	if b2.Chain_IsValid(shape.chainId) {
		b2.DestroyChain(shape.chainId)
		shape.chainId = b2.nullChainId
	}
	if shape.chainPoints != nil {
		delete(shape.chainPoints)
		shape.chainPoints = nil
	}
}

PhysicsShape_DrawDebug :: proc(shape: ^PhysicsShape, bodyPos: [2]f32, bodyRotDeg: f32, color: rl.Color) {
	if !rl.IsWindowReady() do return
	bodyRot := DegreesToRot(bodyRotDeg)
	shapeRot := DegreesToRot(bodyRotDeg + shape.rotation)
	worldCenter := bodyPos + b2.RotateVector(bodyRot, shape.offset)

	fillColor := rl.Color{color.r, color.g, color.b, 55}

	switch shape.type {
	case .Circle:
		rl.DrawCircleV(worldCenter, shape.radius, fillColor)
		rl.DrawCircleLinesV(worldCenter, shape.radius, color)
		dir := b2.RotateVector(shapeRot, b2.Vec2{shape.radius, 0})
		rl.DrawLineV(worldCenter, worldCenter + dir, color)

	case .Capsule:
		halfLen := shape.size[1] * 0.5
		dir := b2.RotateVector(shapeRot, b2.Vec2{0, halfLen})
		p1 := worldCenter - dir
		p2 := worldCenter + dir
		rl.DrawCircleV(p1, shape.radius, fillColor)
		rl.DrawCircleV(p2, shape.radius, fillColor)
		rl.DrawCircleLinesV(p1, shape.radius, color)
		rl.DrawCircleLinesV(p2, shape.radius, color)
		rl.DrawLineEx(p1, p2, shape.radius * 2.0, fillColor)
		perp := b2.RotateVector(shapeRot, b2.Vec2{shape.radius, 0})
		rl.DrawLineV(p1 + perp, p2 + perp, color)
		rl.DrawLineV(p1 - perp, p2 - perp, color)

	case .Box, .RoundedBox:
		w := shape.size[0]
		h := shape.size[1]
		rect := rl.Rectangle{worldCenter.x, worldCenter.y, w, h}
		rl.DrawRectanglePro(rect, {w * 0.5, h * 0.5}, bodyRotDeg + shape.rotation, fillColor)
		hw := w * 0.5
		hh := h * 0.5
		c0 := worldCenter + b2.RotateVector(shapeRot, {-hw, -hh})
		c1 := worldCenter + b2.RotateVector(shapeRot, {hw, -hh})
		c2 := worldCenter + b2.RotateVector(shapeRot, {hw, hh})
		c3 := worldCenter + b2.RotateVector(shapeRot, {-hw, hh})
		rl.DrawLineV(c0, c1, color)
		rl.DrawLineV(c1, c2, color)
		rl.DrawLineV(c2, c3, color)
		rl.DrawLineV(c3, c0, color)

	case .Polygon:
		count := clamp(shape.vertexCount, 3, int(b2.MAX_POLYGON_VERTICES))
		for i in 0..<count {
			next := (i + 1) % count
			v0 := worldCenter + b2.RotateVector(shapeRot, shape.vertices[i])
			v1 := worldCenter + b2.RotateVector(shapeRot, shape.vertices[next])
			rl.DrawLineV(v0, v1, color)
		}

	case .Segment:
		p1 := worldCenter + b2.RotateVector(shapeRot, shape.point1)
		p2 := worldCenter + b2.RotateVector(shapeRot, shape.point2)
		rl.DrawLineEx(p1, p2, 2.0, color)

	case .Chain:
		n := len(shape.chainPoints)
		if n >= 2 {
			for i in 0..<(n - 1) {
				p1 := worldCenter + b2.RotateVector(shapeRot, shape.chainPoints[i])
				p2 := worldCenter + b2.RotateVector(shapeRot, shape.chainPoints[i + 1])
				rl.DrawLineEx(p1, p2, 2.0, color)
			}
			if shape.isLoop {
				p1 := worldCenter + b2.RotateVector(shapeRot, shape.chainPoints[n - 1])
				p2 := worldCenter + b2.RotateVector(shapeRot, shape.chainPoints[0])
				rl.DrawLineEx(p1, p2, 2.0, color)
			}
		}
	}
}

// Helper Constructors
MakeCirclePhysicsShape :: proc(radius: f32, offset: [2]f32 = {0, 0}) -> PhysicsShape {
	s: PhysicsShape
	PhysicsShape_InitDefault(&s, .Circle)
	s.radius = radius
	s.offset = offset
	return s
}

MakeBoxPhysicsShape :: proc(width, height: f32, offset: [2]f32 = {0, 0}, rotation: f32 = 0) -> PhysicsShape {
	s: PhysicsShape
	PhysicsShape_InitDefault(&s, .Box)
	s.size = {width, height}
	s.offset = offset
	s.rotation = rotation
	return s
}

MakeCapsulePhysicsShape :: proc(radius, height: f32, offset: [2]f32 = {0, 0}) -> PhysicsShape {
	s: PhysicsShape
	PhysicsShape_InitDefault(&s, .Capsule)
	s.radius = radius
	s.size = {radius * 2, height}
	s.offset = offset
	return s
}

MakeSegmentPhysicsShape :: proc(p1, p2: [2]f32) -> PhysicsShape {
	s: PhysicsShape
	PhysicsShape_InitDefault(&s, .Segment)
	s.point1 = p1
	s.point2 = p2
	return s
}
