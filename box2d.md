package vendor_box2d
	Bindings for [[ Box2D ; https://box2d.org ]].

	constants
		EPSILON :: math.F32_EPSILON
		HASH_INIT :: 5381
		MAX_POLYGON_VERTICES :: 8
			The maximum number of vertices on a convex polygon. Changing this affects performance even if you
				don't use more vertices.

		Mat22_zero :: Mat22{0, 0, 0, 0}
		PI :: math.PI
		Rot_identity :: Rot{1, 0}
		Transform_identity :: Transform{{0, 0}, {1, 0}}
		Vec2_zero :: Vec2{0, 0}
		bodyTypeCount :: len(BodyType)
			number of body types

		emptySimplexCache :: SimplexCache{}
		nullBodyId :: BodyId{}
		nullChainId :: ChainId{}
		nullJointId :: JointId{}
		nullShapeId :: ShapeId{}
		nullWorldId :: WorldId{}
			/ Use these to make your identifiers null.
			/ You may also use zero initialization to get null.

		shapeTypeCount :: len(ShapeType)
			The number of shape types


	procedures
		AABB_Center :: proc(a: AABB) -> Vec2 {...}
			Get the center of the AABB.

		AABB_Contains :: proc(a, b: AABB) -> bool {...}
			Does a fully contain b

		AABB_Extents :: proc(a: AABB) -> Vec2 {...}
			Get the extents of the AABB (half-widths).

		AABB_Overlaps :: proc(a, b: AABB) -> bool {...}
			Do a and b overlap

		AABB_Union :: proc(a, b: AABB) -> (c: AABB) {...}
			Union of two AABBs

		Abs :: proc(a: Vec2) -> (b: Vec2) {...}
			Component-wise absolute vector

		AbsFloat :: proc(a: f32) -> f32 {...}
			@return the absolute value of a float

		AbsInt :: proc(a: c.int) -> c.int {...}
			@return the absolute value of an integer

		Add :: proc(a, b: Vec2) -> Vec2 {...}
			Vector addition

		Atan2 :: proc(y, x: f32) -> f32 {...}
		Body_ApplyAngularImpulse :: proc(bodyId: BodyId, impulse: f32, wake: bool) ---
			Apply an angular impulse. The impulse is ignored if the body is not awake.
			This optionally wakes the body.
				@param bodyId The body id
			@param impulse the angular impulse, usually in units of kg*m*m/s
			@param wake also wake up the body
				@warning This should be used for one-shot impulses. If you need a steady force,
			use a force instead, which will work better with the sub-stepping solver.

		Body_ApplyForce :: proc(bodyId: BodyId, force: Vec2, point: Vec2, wake: bool) ---
			Apply a force at a world point. If the force is not applied at the center of mass,
			it will generate a torque and affect the angular velocity. This optionally wakes up the body.
				The force is ignored if the body is not awake.
				@param bodyId The body id
			@param force The world force vector, usually in newtons (N)
			@param point The world position of the point of application
			@param wake Option to wake up the body

		Body_ApplyForceToCenter :: proc(bodyId: BodyId, force: Vec2, wake: bool) ---
			Apply a force to the center of mass. This optionally wakes up the body.
				The force is ignored if the body is not awake.
				@param bodyId The body id
			@param force the world force vector, usually in newtons (N).
			@param wake also wake up the body

		Body_ApplyLinearImpulse :: proc(bodyId: BodyId, impulse: Vec2, point: Vec2, wake: bool) ---
			Apply an impulse at a point. This immediately modifies the velocity.
			It also modifies the angular velocity if the point of application
			is not at the center of mass. This optionally wakes the body.
			The impulse is ignored if the body is not awake.
				@param bodyId The body id
			@param impulse the world impulse vector, usually in N*s or kg*m/s.
			@param point the world position of the point of application.
			@param wake also wake up the body
				@warning This should be used for one-shot impulses. If you need a steady force,
			use a force instead, which will work better with the sub-stepping solver.

		Body_ApplyLinearImpulseToCenter :: proc(bodyId: BodyId, impulse: Vec2, wake: bool) ---
			Apply an impulse to the center of mass. This immediately modifies the velocity.
			The impulse is ignored if the body is not awake. This optionally wakes the body.
				@param bodyId The body id
			@param impulse the world impulse vector, usually in N*s or kg*m/s.
			@param wake also wake up the body
				@warning This should be used for one-shot impulses. If you need a steady force,
			use a force instead, which will work better with the sub-stepping solver.

		Body_ApplyMassFromShapes :: proc(bodyId: BodyId) ---
			This update the mass properties to the sum of the mass properties of the shapes.
			This normally does not need to be called unless you called SetMassData to override
			the mass and you later want to reset the mass.
				You may also use this when automatic mass computation has been disabled.
				You should call this regardless of body type.

		Body_ApplyTorque :: proc(bodyId: BodyId, torque: f32, wake: bool) ---
			Apply a torque. This affects the angular velocity without affecting the linear velocity.
				This optionally wakes the body. The torque is ignored if the body is not awake.
				@param bodyId The body id
			@param torque about the z-axis (out of the screen), usually in N*m.
			@param wake also wake up the body

		Body_ComputeAABB :: proc(bodyId: BodyId) -> AABB ---
			Get the current world AABB that contains all the attached shapes. Note that this may not encompass the body origin.
				If there are no shapes attached then the returned AABB is empty and centered on the body origin.

		Body_Disable :: proc(bodyId: BodyId) ---
			Disable a body by removing it completely from the simulation. This is expensive.

		Body_Enable :: proc(bodyId: BodyId) ---
			Enable a body by adding it to the simulation. This is expensive.

		Body_EnableContactEvents :: proc(bodyId: BodyId, flag: bool) ---
			Enable/disable contact events on all shapes.
			@see b2ShapeDef::enableContactEvents
			@warning changing this at runtime may cause mismatched begin/end touch events

		Body_EnableHitEvents :: proc(bodyId: BodyId, flag: bool) ---
			Enable/disable hit events on all shapes
				@see b2ShapeDef::enableHitEvents

		Body_EnableSleep :: proc(bodyId: BodyId, enableSleep: bool) ---
			Enable or disable sleeping for this body. If sleeping is disabled the body will wake.

		Body_GetAngularDamping :: proc(bodyId: BodyId) -> f32 ---
			Get the current angular damping.

		Body_GetAngularVelocity :: proc(bodyId: BodyId) -> f32 ---
			Get the angular velocity of a body in radians per second

		Body_GetContactCapacity :: proc(bodyId: BodyId) -> c.int ---
			Get the maximum capacity required for retrieving all the touching contacts on a body

		Body_GetContactData :: proc(bodyId: BodyId, contactData: []ContactData) -> []ContactData {...}
			Get the touching contact data for a body

		Body_GetGravityScale :: proc(bodyId: BodyId) -> f32 ---
			Get the current gravity scale

		Body_GetJointCount :: proc(bodyId: BodyId) -> c.int ---
			Get the number of joints on this body

		Body_GetJoints :: proc(bodyId: BodyId, jointArray: []JointId) -> []JointId {...}
			Get the joint ids for all joints on this body, up to the provided capacity
				@returns the joint ids stored in the user array

		Body_GetLinearDamping :: proc(bodyId: BodyId) -> f32 ---
			Get the current linear damping.

		Body_GetLinearVelocity :: proc(bodyId: BodyId) -> Vec2 ---
			Get the linear velocity of a body's center of mass. Usually in meters per second.

		Body_GetLocalCenterOfMass :: proc(bodyId: BodyId) -> Vec2 ---
			Get the center of mass position of the body in local space

		Body_GetLocalPoint :: proc(bodyId: BodyId, worldPoint: Vec2) -> Vec2 ---
			Get a local point on a body given a world point

		Body_GetLocalPointVelocity :: proc(bodyId: BodyId, localPoint: Vec2) -> Vec2 ---
			Get the linear velocity of a local point attached to a body. Usually in meters per second.

		Body_GetLocalVector :: proc(bodyId: BodyId, worldVector: Vec2) -> Vec2 ---
			Get a local vector on a body given a world vector

		Body_GetMass :: proc(bodyId: BodyId) -> f32 ---
			Get the mass of the body, usually in kilograms

		Body_GetMassData :: proc(bodyId: BodyId) -> MassData ---
			Get the mass data for a body

		Body_GetName :: proc(bodyId: BodyId) -> cstring ---
			Get the body name. May be nil.

		Body_GetPosition :: proc(bodyId: BodyId) -> Vec2 ---
			Get the world position of a body. This is the location of the body origin.

		Body_GetRotation :: proc(bodyId: BodyId) -> Rot ---
			Get the world rotation of a body as a cosine/sine pair (complex number)

		Body_GetRotationalInertia :: proc(bodyId: BodyId) -> f32 ---
			Get the rotational inertia of the body, usually in kg*m^2

		Body_GetShapeCount :: proc(bodyId: BodyId) -> c.int ---
			Get the number of shapes on this body

		Body_GetShapes :: proc(bodyId: BodyId, shapeArray: []ShapeId) -> []ShapeId {...}
			Get the shape ids for all shapes on this body, up to the provided capacity.
				@returns the shape ids stored in the user array

		Body_GetSleepThreshold :: proc(bodyId: BodyId) -> f32 ---
			Get the sleep threshold, usually in meters per second.

		Body_GetTransform :: proc(bodyId: BodyId) -> Transform ---
			Get the world transform of a body.

		Body_GetType :: proc(bodyId: BodyId) -> BodyType ---
			Get the body type: static, kinematic, or dynamic

		Body_GetUserData :: proc(bodyId: BodyId) -> rawptr ---
			Get the user data stored in a body

		Body_GetWorld :: proc(bodyId: BodyId) -> WorldId ---
			Get the world that owns this body

		Body_GetWorldCenterOfMass :: proc(bodyId: BodyId) -> Vec2 ---
			Get the center of mass position of the body in world space

		Body_GetWorldPoint :: proc(bodyId: BodyId, localPoint: Vec2) -> Vec2 ---
			Get a world point on a body given a local point

		Body_GetWorldPointVelocity :: proc(bodyId: BodyId, worldPoint: Vec2) -> Vec2 ---
			Get the linear velocity of a world point attached to a body. Usually in meters per second.

		Body_GetWorldVector :: proc(bodyId: BodyId, localVector: Vec2) -> Vec2 ---
			Get a world vector on a body given a local vector

		Body_IsAwake :: proc(bodyId: BodyId) -> bool ---
			@return true if this body is awake

		Body_IsBullet :: proc(bodyId: BodyId) -> bool ---
			Is this body a bullet?

		Body_IsEnabled :: proc(bodyId: BodyId) -> bool ---
			Returns true if this body is enabled

		Body_IsFixedRotation :: proc(bodyId: BodyId) -> bool ---
			Does this body have fixed rotation?

		Body_IsSleepEnabled :: proc(bodyId: BodyId) -> bool ---
			Returns true if sleeping is enabled for this body

		Body_IsValid :: proc(id: BodyId) -> bool ---
			Body identifier validation. Can be used to detect orphaned ids. Provides validation for up to 64K allocations.

		Body_SetAngularDamping :: proc(bodyId: BodyId, angularDamping: f32) ---
			Adjust the angular damping. Normally this is set in BodyDef before creation.

		Body_SetAngularVelocity :: proc(bodyId: BodyId, angularVelocity: f32) ---
			Set the angular velocity of a body in radians per second

		Body_SetAwake :: proc(bodyId: BodyId, awake: bool) ---
			Wake a body from sleep. This wakes the entire island the body is touching.
				@warning Putting a body to sleep will put the entire island of bodies touching this body to sleep,
				which can be expensive and possibly unintuitive.

		Body_SetBullet :: proc(bodyId: BodyId, flag: bool) ---
			Set this body to be a bullet. A bullet does continuous collision detection
			against dynamic bodies (but not other bullets).

		Body_SetFixedRotation :: proc(bodyId: BodyId, flag: bool) ---
			Set this body to have fixed rotation. This causes the mass to be reset in all cases.

		Body_SetGravityScale :: proc(bodyId: BodyId, gravityScale: f32) ---
			Adjust the gravity scale. Normally this is set in BodyDef before creation.
				@see BodyDef::gravityScale

		Body_SetLinearDamping :: proc(bodyId: BodyId, linearDamping: f32) ---
			Adjust the linear damping. Normally this is set in BodyDef before creation.

		Body_SetLinearVelocity :: proc(bodyId: BodyId, linearVelocity: Vec2) ---
			Set the linear velocity of a body. Usually in meters per second.

		Body_SetMassData :: proc(bodyId: BodyId, massData: MassData) ---
			Override the body's mass properties. Normally this is computed automatically using the
				shape geometry and density. This information is lost if a shape is added or removed or if the
				body type changes.

		Body_SetName :: proc(bodyId: BodyId, name: cstring) ---
			Set the body name. Up to 32 characters excluding 0 termination.

		Body_SetSleepThreshold :: proc(bodyId: BodyId, sleepThreshold: f32) ---
			Set the sleep threshold, usually in meters per second

		Body_SetTargetTransform :: proc(bodyId: BodyId, target: Transform, timeStep: f32) ---
			Set the velocity to reach the given transform after a given time step.
			The result will be close but maybe not exact. This is meant for kinematic bodies.
			The target is not applied if the velocity would be below the sleep threshold.
			This will automatically wake the body if asleep.

		Body_SetTransform :: proc(bodyId: BodyId, position: Vec2, rotation: Rot) ---
			Set the world transform of a body. This acts as a teleport and is fairly expensive.
			@note Generally you should create a body with then intended transform.
				@see BodyDef::position and BodyDef::angle

		Body_SetType :: proc(bodyId: BodyId, type: BodyType) ---
			Change the body type. This is an expensive operation. This automatically updates the mass
				properties regardless of the automatic mass setting.

		Body_SetUserData :: proc(bodyId: BodyId, userData: rawptr) ---
			Set the user data for a body

		Chain_GetFriction :: proc(chainId: ChainId) -> f32 ---
			Get the chain friction

		Chain_GetMaterial :: proc(chainId: ChainId) -> c.int ---
			Get the chain material

		Chain_GetRestitution :: proc(chainId: ChainId) -> f32 ---
			Get the chain restitution

		Chain_GetSegmentCount :: proc(chainId: ChainId) -> c.int ---
			Get the number of segments on this chain

		Chain_GetSegments :: proc(chainId: ChainId, segmentArray: [^]ShapeId, capacity: c.int) -> c.int ---
			Fill a user array with chain segment shape ids up to the specified capacity. Returns
			the actual number of segments returned.

		Chain_GetWorld :: proc(chainId: ChainId) -> WorldId ---
			Get the world that owns this chain shape

		Chain_IsValid :: proc(id: ChainId) -> bool ---
			Chain identifier validation. Provides validation for up to 64K allocations.

		Chain_SetFriction :: proc(chainId: ChainId, friction: f32) ---
			Set the chain friction
			@see b2ChainDef::friction

		Chain_SetMaterial :: proc(chainId: ChainId, material: c.int) ---
			Set the chain material
			@see b2ChainDef::material

		Chain_SetRestitution :: proc(chainId: ChainId, restitution: f32) ---
			Set the chain restitution (bounciness)
			@see b2ChainDef::restitution

		Clamp :: proc(v: Vec2, a, b: Vec2) -> (c: Vec2) {...}
			Component-wise clamp vector v into the range [a, b]

		ClampFloat :: proc(a, lower, upper: f32) -> f32 {...}
			@return a f32 clamped between a lower and upper bound

		ClampInt :: proc(a, lower, upper: c.int) -> c.int {...}
			@return an integer clamped between a lower and upper bound

		ClipVector :: proc(vector: Vec2, planes: []CollisionPlane) -> Vec2 {...}
		CollideCapsuleAndCircle :: proc(capsuleA: Capsule, xfA: Transform, circleB: Circle, xfB: Transform) -> Manifold ---
			Compute the contact manifold between a capsule and circle

		CollideCapsules :: proc(capsuleA: Capsule, xfA: Transform, capsuleB: Capsule, xfB: Transform) -> Manifold ---
			Compute the contact manifold between a capsule and circle

		CollideChainSegmentAndCapsule :: proc(segmentA: ChainSegment, xfA: Transform, capsuleB: Capsule, xfB: Transform, cache: ^SimplexCache) -> Manifold ---
			Compute the contact manifold between an segment and a capsule

		CollideChainSegmentAndCircle :: proc(segmentA: ChainSegment, xfA: Transform, circleB: Circle, xfB: Transform) -> Manifold ---
			Compute the contact manifold between a chain segment and a circle

		CollideChainSegmentAndPolygon :: proc(segmentA: ChainSegment, xfA: Transform, polygonB: Polygon, xfB: Transform, cache: ^SimplexCache) -> Manifold ---
			Compute the contact manifold between a chain segment and a rounded polygon

		CollideCircles :: proc(circleA: Circle, xfA: Transform, circleB: Circle, xfB: Transform) -> Manifold ---
			Compute the contact manifold between two circles

		CollidePolygonAndCapsule :: proc(polygonA: Polygon, xfA: Transform, capsuleB: Capsule, xfB: Transform) -> Manifold ---
			Compute the contact manifold between a polygon and capsule

		CollidePolygonAndCircle :: proc(polygonA: Polygon, xfA: Transform, circleB: Circle, xfB: Transform) -> Manifold ---
			Compute the contact manifold between a polygon and a circle

		CollidePolygons :: proc(polygonA: Polygon, xfA: Transform, polygonB: Polygon, xfB: Transform) -> Manifold ---
			Compute the contact manifold between two polygons

		CollideSegmentAndCapsule :: proc(segmentA: Segment, xfA: Transform, capsuleB: Capsule, xfB: Transform) -> Manifold ---
			Compute the contact manifold between an segment and a capsule

		CollideSegmentAndCircle :: proc(segmentA: Segment, xfA: Transform, circleB: Circle, xfB: Transform) -> Manifold ---
			Compute the contact manifold between an segment and a circle

		CollideSegmentAndPolygon :: proc(segmentA: Segment, xfA: Transform, polygonB: Polygon, xfB: Transform) -> Manifold ---
			Compute the contact manifold between an segment and a polygon

		ComputeAngularVelocity :: proc(q1: Rot, q2: Rot, inv_h: f32) -> f32 {...}
			Compute the angular velocity necessary to rotate between two rotations over a give time
				@param q1 initial rotation
				@param q2 final rotation
				@param inv_h inverse time step

		ComputeCapsuleAABB :: proc(shape: Capsule, transform: Transform) -> AABB ---
			Compute the bounding box of a transformed capsule

		ComputeCapsuleMass :: proc(shape: Capsule, density: f32) -> MassData ---
			Compute mass properties of a capsule

		ComputeCircleAABB :: proc(shape: Circle, transform: Transform) -> AABB ---
			Compute the bounding box of a transformed circle

		ComputeCircleMass :: proc(shape: Circle, density: f32) -> MassData ---
			Compute mass properties of a circle

		ComputeCosSin :: proc(radians: f32) -> (res: CosSin) {...}
		ComputeHull :: proc(points: []Vec2) -> Hull {...}
			Compute the convex hull of a set of points. Returns an empty hull if it fails.
			Some failure cases:
			- all points very close together
			- all points on a line
			- less than 3 points
			- more than MAX_POLYGON_VERTICES points
			This welds close points and removes collinear points.
				@warning Do not modify a hull once it has been computed

		ComputePolygonAABB :: proc(shape: Polygon, transform: Transform) -> AABB ---
			Compute the bounding box of a transformed polygon

		ComputePolygonMass :: proc(shape: Polygon, density: f32) -> MassData ---
			Compute mass properties of a polygon

		ComputeRotationBetweenUnitVectors :: proc(v1, v2: Vec2) -> Rot {...}
			Compute the rotation between two unit vectors

		ComputeSegmentAABB :: proc(shape: Segment, transform: Transform) -> AABB ---
			Compute the bounding box of a transformed line segment

		CreateBody :: proc(worldId: WorldId, def: BodyDef) -> BodyId ---
			Create a rigid body given a definition. No reference to the definition is retained. So you can create the definition
				on the stack and pass it as a pointer.
				@code{.odin}
				body_def := b2.DefaultBodyDef()
				my_body_id =: b2.CreateBody(my_world_id, body_def)
				@endcode
			@warning This function is locked during callbacks.

		CreateCapsuleShape :: proc(bodyId: BodyId, def: ShapeDef, capsule: Capsule) -> ShapeId ---
			Create a capsule shape and attach it to a body. The shape definition and geometry are fully cloned.
			Contacts are not created until the next time step.
				@return the shape id for accessing the shape

		CreateChain :: proc(bodyId: BodyId, def: ChainDef) -> ChainId ---
			Create a chain shape
				@see b2ChainDef for details

		CreateCircleShape :: proc(bodyId: BodyId, def: ShapeDef, circle: Circle) -> ShapeId ---
			Create a circle shape and attach it to a body. The shape definition and geometry are fully cloned.
			Contacts are not created until the next time step.
				@return the shape id for accessing the shape

		CreateDistanceJoint :: proc(worldId: WorldId, def: DistanceJointDef) -> JointId ---
			Create a distance joint
				@see b2DistanceJointDef for details

		CreateFilterJoint :: proc(worldId: WorldId, def: FilterJointDef) -> JointId ---
			Create a filter joint.
			@see b2FilterJointDef for details

		CreateMotorJoint :: proc(worldId: WorldId, def: MotorJointDef) -> JointId ---
			Create a motor joint
				@see b2MotorJointDef for details

		CreateMouseJoint :: proc(worldId: WorldId, def: MouseJointDef) -> JointId ---
			Create a mouse joint
				@see b2MouseJointDef for details

		CreatePolygonShape :: proc(bodyId: BodyId, def: ShapeDef, polygon: Polygon) -> ShapeId ---
			Create a polygon shape and attach it to a body. The shape definition and geometry are fully cloned.
			Contacts are not created until the next time step.
				@return the shape id for accessing the shape

		CreatePrismaticJoint :: proc(worldId: WorldId, def: PrismaticJointDef) -> JointId ---
			Create a prismatic (slider) joint.
				@see b2PrismaticJointDef for details

		CreateRevoluteJoint :: proc(worldId: WorldId, def: RevoluteJointDef) -> JointId ---
			Create a revolute joint
				@see b2RevoluteJointDef for details

		CreateSegmentShape :: proc(bodyId: BodyId, def: ShapeDef, segment: Segment) -> ShapeId ---
			Create a line segment shape and attach it to a body. The shape definition and geometry are fully cloned.
			Contacts are not created until the next time step.
				@return the shape id for accessing the shape

		CreateWeldJoint :: proc(worldId: WorldId, def: WeldJointDef) -> JointId ---
			Create a weld joint
				@see b2WeldJointDef for details

		CreateWheelJoint :: proc(worldId: WorldId, def: WheelJointDef) -> JointId ---
			Create a wheel joint
				@see b2WheelJointDef for details

		CreateWorld :: proc(def: WorldDef) -> WorldId ---
			Create a world for rigid body simulation. A world contains bodies, shapes, and constraints. You make create
				up to 128 worlds. Each world is completely independent and may be simulated in parallel.
				@return the world id.

		Cross :: proc(a, b: Vec2) -> f32 {...}
			Vector cross product. In 2D this yields a scalar.

		CrossSV :: proc(s: f32, v: Vec2) -> Vec2 {...}
			Perform the cross product on a scalar and a vector. In 2D this produces a vector.

		CrossVS :: proc(v: Vec2, s: f32) -> Vec2 {...}
			Perform the cross product on a vector and a scalar. In 2D this produces a vector.

		DefaultBodyDef :: proc() -> BodyDef ---
			Use this to initialize your body definition
			@ingroup body

		DefaultChainDef :: proc() -> ChainDef ---
			Use this to initialize your chain definition
			@ingroup shape

		DefaultDebugDraw :: proc() -> DebugDraw ---
			Use this to initialize your drawing interface. This allows you to implement a sub-set
			of the drawing functions.

		DefaultDistanceJointDef :: proc() -> DistanceJointDef ---
			Use this to initialize your joint definition
			@ingroup distance_joint

		DefaultExplosionDef :: proc() -> ExplosionDef ---
			Use this to initialize your explosion definition
			@ingroup world

		DefaultFilter :: proc() -> Filter ---
			Use this to initialize your filter
			@ingroup shape

		DefaultFilterJointDef :: proc() -> FilterJointDef ---
			Use this to initialize your joint definition
			@ingroup filter_joint

		DefaultMotorJointDef :: proc() -> MotorJointDef ---
			Use this to initialize your joint definition
			@ingroup motor_joint

		DefaultMouseJointDef :: proc() -> MouseJointDef ---
			Use this to initialize your joint definition
			@ingroup mouse_joint

		DefaultPrismaticJointDef :: proc() -> PrismaticJointDef ---
			Use this to initialize your joint definition
			@ingroupd prismatic_joint

		DefaultQueryFilter :: proc() -> QueryFilter ---
			Use this to initialize your query filter
			@ingroup shape

		DefaultRevoluteJointDef :: proc() -> RevoluteJointDef ---
			Use this to initialize your joint definition.
			@ingroup revolute_joint

		DefaultShapeDef :: proc() -> ShapeDef ---
			Use this to initialize your shape definition
			@ingroup shape

		DefaultSurfaceMaterial :: proc() -> SurfaceMaterial ---
			Use this to initialize your surface material
			@ingroup shape

		DefaultWeldJointDef :: proc() -> WeldJointDef ---
			Use this to initialize your joint definition
			@ingroup weld_joint

		DefaultWheelJointDef :: proc() -> WheelJointDef ---
			Use this to initialize your joint definition
			@ingroup wheel_joint

		DefaultWorldDef :: proc() -> WorldDef ---
			Use this to initialize your world definition
			@ingroup world

		DestroyBody :: proc(bodyId: BodyId) ---
			Destroy a rigid body given an id. This destroys all shapes and joints attached to the body.
				Do not keep references to the associated shapes and joints.

		DestroyChain :: proc(chainId: ChainId) ---
			Destroy a chain shape

		DestroyJoint :: proc(jointId: JointId) ---
			Destroy a joint

		DestroyShape :: proc(shapeId: ShapeId, updateBodyMass: bool) ---
			Destroy a shape. You may defer the body mass update which can improve performance if several shapes on a
				body are destroyed at once.
				@see b2Body_ApplyMassFromShapes

		DestroyWorld :: proc(worldId: WorldId) ---
			Destroy a world

		Distance :: proc(a, b: Vec2) -> f32 {...}
			Get the distance between two points

		DistanceJoint_EnableLimit :: proc(jointId: JointId, enableLimit: bool) ---
			Enable joint limit. The limit only works if the joint spring is enabled. Otherwise the joint is rigid
				and the limit has no effect.

		DistanceJoint_EnableMotor :: proc(jointId: JointId, enableMotor: bool) ---
			Enable/disable the distance joint motor

		DistanceJoint_EnableSpring :: proc(jointId: JointId, enableSpring: bool) ---
			Enable/disable the distance joint spring. When disabled the distance joint is rigid.

		DistanceJoint_GetCurrentLength :: proc(jointId: JointId) -> f32 ---
			Get the current length of a distance joint

		DistanceJoint_GetLength :: proc(jointId: JointId) -> f32 ---
			Get the rest length of a distance joint

		DistanceJoint_GetMaxLength :: proc(jointId: JointId) -> f32 ---
			Get the distance joint maximum length

		DistanceJoint_GetMaxMotorForce :: proc(jointId: JointId) -> f32 ---
			Get the distance joint maximum motor force, usually in newtons

		DistanceJoint_GetMinLength :: proc(jointId: JointId) -> f32 ---
			Get the distance joint minimum length

		DistanceJoint_GetMotorForce :: proc(jointId: JointId) -> f32 ---
			Get the distance joint current motor force, usually in newtons

		DistanceJoint_GetMotorSpeed :: proc(jointId: JointId) -> f32 ---
			Get the distance joint motor speed, usually in meters per second

		DistanceJoint_GetSpringDampingRatio :: proc(jointId: JointId) -> f32 ---
			Get the spring damping ratio

		DistanceJoint_GetSpringHertz :: proc(jointId: JointId) -> f32 ---
			Get the spring Hertz

		DistanceJoint_IsLimitEnabled :: proc(jointId: JointId) -> bool ---
			Is the distance joint limit enabled?

		DistanceJoint_IsMotorEnabled :: proc(jointId: JointId) -> bool ---
			Is the distance joint motor enabled?

		DistanceJoint_IsSpringEnabled :: proc(jointId: JointId) -> bool ---
			Is the distance joint spring enabled?

		DistanceJoint_SetLength :: proc(jointId: JointId, length: f32) ---
			Set the rest length of a distance joint
			@param jointId The id for a distance joint
			@param length The new distance joint length

		DistanceJoint_SetLengthRange :: proc(jointId: JointId, minLength, maxLength: f32) ---
			Set the minimum and maximum length parameters of a distance joint

		DistanceJoint_SetMaxMotorForce :: proc(jointId: JointId, force: f32) ---
			Set the distance joint maximum motor force, usually in newtons

		DistanceJoint_SetMotorSpeed :: proc(jointId: JointId, motorSpeed: f32) ---
			Set the distance joint motor speed, usually in meters per second

		DistanceJoint_SetSpringDampingRatio :: proc(jointId: JointId, dampingRatio: f32) ---
			Set the spring damping ratio, non-dimensional

		DistanceJoint_SetSpringHertz :: proc(jointId: JointId, hertz: f32) ---
			Set the spring stiffness in Hertz

		DistanceSquared :: proc(a, b: Vec2) -> f32 {...}
			Get the distance squared between points

		Dot :: proc(a, b: Vec2) -> f32 {...}
			Vector dot product

		DynamicTree_Create :: proc() -> DynamicTree ---
			Constructing the tree initializes the node pool.

		DynamicTree_CreateProxy :: proc(tree: ^DynamicTree, aabb: AABB, categoryBits: u64, userData: u64) -> i32 ---
			Create a proxy. Provide an AABB and a userData value.

		DynamicTree_Destroy :: proc(tree: ^DynamicTree) ---
			Destroy the tree, freeing the node pool.

		DynamicTree_DestroyProxy :: proc(tree: ^DynamicTree, proxyId: i32) ---
			Destroy a proxy. This asserts if the id is invalid.

		DynamicTree_EnlargeProxy :: proc(tree: ^DynamicTree, proxyId: i32, aabb: AABB) ---
			Enlarge a proxy and enlarge ancestors as necessary.

		DynamicTree_GetAABB :: proc(tree: DynamicTree, proxyId: c.int) -> AABB ---
			Get the AABB of a proxy

		DynamicTree_GetAreaRatio :: proc(tree: DynamicTree) -> f32 ---
			Get the ratio of the sum of the node areas to the root area.

		DynamicTree_GetByteCount :: proc(tree: DynamicTree) -> c.int ---
			Get the number of bytes used by this tree

		DynamicTree_GetCategoryBits :: proc(tree: ^DynamicTree, proxyId: i32) ---
			Get the category bits on a proxy.

		DynamicTree_GetHeight :: proc(tree: DynamicTree) -> c.int ---
			Get the height of the binary tree.

		DynamicTree_GetProxyCount :: proc(tree: DynamicTree) -> c.int ---
			Get the number of proxies created

		DynamicTree_GetRootBounds :: proc(tree: DynamicTree) -> AABB ---
			Get the bounding box that contains the entire tree

		DynamicTree_GetUserData :: proc(tree: DynamicTree, proxyId: c.int) -> u64 ---
			Get proxy user data

		DynamicTree_MoveProxy :: proc(tree: ^DynamicTree, proxyId: i32, aabb: AABB) ---
			Move a proxy to a new AABB by removing and reinserting into the tree.

		DynamicTree_Query :: proc(tree: DynamicTree, aabb: AABB, maskBits: u64, callback: TreeQueryCallbackFcn, ctx: rawptr) -> TreeStats ---
			Query an AABB for overlapping proxies. The callback class is called for each proxy that overlaps the supplied AABB.
				@return performance data

		DynamicTree_RayCast :: proc(tree: DynamicTree, input: RayCastInput, maskBits: u64, callback: TreeRayCastCallbackFcn, ctx: rawptr) -> TreeStats ---
			Ray cast against the proxies in the tree. This relies on the callback
			to perform a exact ray cast in the case were the proxy contains a shape.
			The callback also performs the any collision filtering. This has performance
			roughly equal to k * log(n), where k is the number of collisions and n is the
			number of proxies in the tree.
			Bit-wise filtering using mask bits can greatly improve performance in some scenarios.
				However, this filtering may be approximate, so the user should still apply filtering to results.
			@param tree the dynamic tree to ray cast
			@param input the ray cast input data. The ray extends from p1 to p1 + maxFraction * (p2 - p1)
			@param maskBits mask bit hint: `bool accept = (maskBits & node->categoryBits) != 0;`
			@param callback a callback class that is called for each proxy that is hit by the ray
			@param context user context that is passed to the callback
				@return performance data

		DynamicTree_Rebuild :: proc(tree: ^DynamicTree, fullBuild: bool) -> c.int ---
			Rebuild the tree while retaining subtrees that haven't changed. Returns the number of boxes sorted.

		DynamicTree_SetCategoryBits :: proc(tree: ^DynamicTree, proxyId: i32, categoryBits: u64) ---
			Modify the category bits on a proxy. This is an expensive operation.

		DynamicTree_ShapeCast :: proc(tree: DynamicTree, input: ShapeCastInput, maskBits: u32, callback: TreeShapeCastCallbackFcn, ctx: rawptr) -> TreeStats ---
			Ray cast against the proxies in the tree. This relies on the callback
			to perform a exact ray cast in the case were the proxy contains a shape.
			The callback also performs the any collision filtering. This has performance
			roughly equal to k * log(n), where k is the number of collisions and n is the
			number of proxies in the tree.
				@param tree the dynamic tree to ray cast
			@param input the ray cast input data. The ray extends from p1 to p1 + maxFraction * (p2 - p1).
				@param maskBits filter bits: `bool accept = (maskBits & node->categoryBits) != 0 ---`
			@param callback a callback class that is called for each proxy that is hit by the shape
				@param context user context that is passed to the callback
				@return performance data

		DynamicTree_Validate :: proc(tree: DynamicTree) ---
			Validate this tree. For testing.

		DynamicTree_ValidateNoEnlarged :: proc(tree: DynamicTree) ---
			Validate this tree has no enlarged AABBs. For testing.

		GetByteCount :: proc() -> c.int ---
			@return the total bytes allocated by Box2D

		GetInverse22 :: proc(A: Mat22) -> Mat22 {...}
			Get the inverse of a 2-by-2 matrix

		GetLengthAndNormalize :: proc(v: Vec2) -> (length: f32, vn: Vec2) {...}
		GetLengthUnitsPerMeter :: proc() -> f32 ---
			Get the current length units per meter.

		GetMilliseconds :: proc(ticks: u64) -> f32 ---
			Get the milliseconds passed from an initial tick value.

		GetMillisecondsAndReset :: proc(ticks: ^u64) -> f32 ---
			Get the milliseconds passed from an initial tick value. Resets the passed in
			value to the current tick value.

		GetSweepTransform :: proc(sweep: Sweep, time: f32) -> Transform ---
			Evaluate the transform sweep at a specific time.

		GetTicks :: proc() -> u64 ---
			Get the absolute number of system ticks. The value is platform specific.

		Hash :: proc(hash: u32, data: [^]byte, count: c.int) -> u32 ---
			Simple djb2 hash function for determinism testing.

		ID_EQUALS :: proc(id1, id2: $T) -> bool {...}
			/ Compare two ids for equality. Doesn't work for b2WorldId.

		IS_NON_NULL :: proc(id: $T) -> bool {...}
			/ Macro to determine if any id is non-null.

		IS_NULL :: proc(id: $T) -> bool {...}
			/ Macro to determine if any id is null.

		IntegrateRotation :: proc(q1: Rot, deltaAngle: f32) -> Rot {...}
			Integration rotation from angular velocity
				@param q1 initial rotation
				@param deltaAngle the angular displacement in radians

		InvMulRot :: proc(q, r: Rot) -> (qr: Rot) {...}
			Transpose multiply two rotations: qT * r

		InvMulTransforms :: proc(A, B: Transform) -> (C: Transform) {...}
			Creates a transform that converts a local point in frame B to a local point in frame A.
			v2 = A.q' * (B.q * v1 + B.p - A.p)
			   = A.q' * B.q * v1 + A.q' * (B.p - A.p)

		InvRotateVector :: proc(q: Rot, v: Vec2) -> Vec2 {...}
			Inverse rotate a vector

		InvTransformPoint :: proc(t: Transform, p: Vec2) -> Vec2 {...}
			Inverse transform a point (e.g. world space to local space)

		IsNormalized :: proc(v: Vec2) -> bool {...}
		IsNormalizedRot :: proc(q: Rot) -> bool {...}
			Is this rotation normalized?

		IsValidAABB :: proc(aabb: AABB) -> bool {...}
			Is this a valid bounding box? Not Nan or infinity. Upper bound greater than or equal to lower bound.

		IsValidFloat :: proc(a: f32) -> bool {...}
		IsValidPlane :: proc(plane: Plane) -> bool {...}
			Is this a valid plane? Normal is a unit vector. Not Nan or infinity.

		IsValidRay :: proc(input: RayCastInput) -> bool ---
			Validate ray cast input data (NaN, etc)

		IsValidRotation :: proc(q: Rot) -> bool {...}
		IsValidVec2 :: proc(v: Vec2) -> bool {...}
		Joint_GetAngularSeparation :: proc(jointId: JointId) -> f32 ---
			Get the current angular separation error for this joint. Does not consider admissible movement. Usually in meters.

		Joint_GetBodyA :: proc(jointId: JointId) -> BodyId ---
			Get body A id on a joint

		Joint_GetBodyB :: proc(jointId: JointId) -> BodyId ---
			Get body B id on a joint

		Joint_GetCollideConnected :: proc(jointId: JointId) -> bool ---
			Is collision allowed between connected bodies?

		Joint_GetConstraintForce :: proc(jointId: JointId) -> Vec2 ---
			Get the current constraint force for this joint. Usually in Newtons.

		Joint_GetConstraintTorque :: proc(jointId: JointId) -> f32 ---
			Get the current constraint torque for this joint. Usually in Newton * meters.

		Joint_GetConstraintTuning :: proc(jointId: JointId, hertz: ^f32, dampingRatio: ^f32) ---
			Get the joint constraint tuning. Advanced feature.

		Joint_GetLinearSeparation :: proc(jointId: JointId) -> f32 ---
			Get the current linear separation error for this joint. Does not consider admissible movement. Usually in meters.

		Joint_GetLocalAnchorA :: proc(jointId: JointId) -> Vec2 ---
			Get the local anchor on bodyA

		Joint_GetLocalAnchorB :: proc(jointId: JointId) -> Vec2 ---
			Get the local anchor on bodyB

		Joint_GetLocalAxisA :: proc(jointId: JointId) -> Vec2 ---
			Get the local axis on bodyA (prismatic and wheel)

		Joint_GetReferenceAngle :: proc(jointId: JointId) -> f32 ---
			Get the joint reference angle in radians (revolute, prismatic, and weld)

		Joint_GetType :: proc(jointId: JointId) -> JointType ---
			Get the joint type

		Joint_GetUserData :: proc(jointId: JointId) -> rawptr ---
			Get the user data on a joint

		Joint_GetWorld :: proc(jointId: JointId) -> WorldId ---
			Get the world that owns this joint

		Joint_IsValid :: proc(id: JointId) -> bool ---
			Joint identifier validation. Provides validation for up to 64K allocations.

		Joint_SetCollideConnected :: proc(jointId: JointId, shouldCollide: bool) ---
			Toggle collision between connected bodies

		Joint_SetConstraintTuning :: proc(jointId: JointId, hertz: f32, dampingRatio: f32) ---
			Set the joint constraint tuning. Advanced feature.
			@param jointId the joint
			@param hertz the stiffness in Hertz (cycles per second)
			@param dampingRatio the non-dimensional damping ratio (one for critical damping)

		Joint_SetLocalAnchorA :: proc(jointId: JointId, localAnchor: Vec2) ---
			Set the local anchor on bodyA

		Joint_SetLocalAnchorB :: proc(jointId: JointId, localAnchor: Vec2) ---
			Set the local anchor on bodyB

		Joint_SetLocalAxisA :: proc(jointId: JointId, localAxis: Vec2) ---
			Set the local axis on bodyA (prismatic and wheel)

		Joint_SetReferenceAngle :: proc(jointId: JointId, angleInRadians: f32) ---
			Set the joint reference angle in radians, must be in [-pi,pi]. (revolute, prismatic, and weld)

		Joint_SetUserData :: proc(jointId: JointId, userData: rawptr) ---
			Set the user data on a joint

		Joint_WakeBodies :: proc(jointId: JointId) ---
			Wake the bodies connect to this joint

		LeftPerp :: proc(v: Vec2) -> Vec2 {...}
			Get a left pointing perpendicular vector. Equivalent to b2CrossSV(1, v)

		Length :: proc(v: Vec2) -> f32 {...}
			Get the length of this vector (the norm)

		LengthSquared :: proc(v: Vec2) -> f32 {...}
			Get the length squared of this vector

		Lerp :: proc(a, b: Vec2, t: f32) -> Vec2 {...}
			Vector linear interpolation
			https://fgiesen.wordpress.com/2012/08/15/linear-interpolation-past-present-and-future/

		LoadWorldId :: proc(x: u32) -> WorldId {...}
			Load a u32 into a world id.

		MakeAABB :: proc(points: []Vec2, radius: f32) -> AABB {...}
			Compute the bounding box of an array of circles

		MakeBox :: proc(halfWidth, halfHeight: f32) -> Polygon ---
			Make a box (rectangle) polygon, bypassing the need for a convex hull.

		MakeOffsetBox :: proc(halfWidth, halfHeight: f32, center: Vec2, rotation: Rot) -> Polygon ---
			Make an offset box, bypassing the need for a convex hull.

		MakeOffsetPolygon :: proc(hull: Hull, position: Vec2, rotation: Rot) -> Polygon ---
			Make an offset convex polygon from a convex hull. This will assert if the hull is not valid.
			@warning Do not manually fill in the hull data, it must come directly from b2ComputeHull

		MakeOffsetProxy :: proc(points: []Vec2, radius: f32, position: Vec2, rotation: Rot) -> ShapeProxy {...}
			Make a proxy with a transform. This is a deep copy of the points.

		MakeOffsetRoundedBox :: proc(halfWidth, halfHeight: f32, center: Vec2, rotation: Rot, radius: f32) -> Polygon ---
			Make an offset rounded box, bypassing the need for a convex hull.

		MakeOffsetRoundedPolygon :: proc(hull: Hull, position: Vec2, rotation: Rot, radius: f32) -> Polygon ---
			Make an offset convex polygon from a convex hull. This will assert if the hull is not valid.
			@warning Do not manually fill in the hull data, it must come directly from b2ComputeHull

		MakePolygon :: proc(hull: Hull, radius: f32) -> Polygon ---
			Make a convex polygon from a convex hull. This will assert if the hull is not valid.
			@warning Do not manually fill in the hull data, it must come directly from b2ComputeHull

		MakeProxy :: proc(points: []Vec2, radius: f32) -> ShapeProxy {...}
			Make a proxy for use in overlap, shape cast, and related functions. This is a deep copy of the points.

		MakeRot :: proc(angle: f32) -> Rot {...}
			Make a rotation using an angle in radians

		MakeRoundedBox :: proc(halfWidth, halfHeight: f32, radius: f32) -> Polygon ---
			Make a rounded box, bypassing the need for a convex hull.

		MakeSquare :: proc(halfWidth: f32) -> Polygon ---
			Make a square polygon, bypassing the need for a convex hull.

		Max :: proc(a, b: Vec2) -> (c: Vec2) {...}
			Component-wise maximum vector

		MaxFloat :: proc(a, b: f32) -> f32 {...}
			@return the maximum of two floats

		MaxInt :: proc(a, b: c.int) -> c.int {...}
			@return the maximum of two integers

		Min :: proc(a, b: Vec2) -> (c: Vec2) {...}
			Component-wise minimum vector

		MinFloat :: proc(a, b: f32) -> f32 {...}
			@return the minimum of two floats

		MinInt :: proc(a, b: c.int) -> c.int {...}
			@return the minimum of two integers

		MotorJoint_GetAngularOffset :: proc(jointId: JointId) -> f32 ---
			Get the motor joint angular offset target in radians

		MotorJoint_GetCorrectionFactor :: proc(jointId: JointId) -> f32 ---
			Get the motor joint correction factor, usually in [0, 1]

		MotorJoint_GetLinearOffset :: proc(jointId: JointId) -> Vec2 ---
			Get the motor joint linear offset target

		MotorJoint_GetMaxForce :: proc(jointId: JointId) -> f32 ---
			Get the motor joint maximum force, usually in newtons

		MotorJoint_GetMaxTorque :: proc(jointId: JointId) -> f32 ---
			Get the motor joint maximum torque, usually in newton-meters

		MotorJoint_SetAngularOffset :: proc(jointId: JointId, angularOffset: f32) ---
			Set the motor joint angular offset target in radians. This angle will be unwound
			so the motor will drive along the shortest arc.

		MotorJoint_SetCorrectionFactor :: proc(jointId: JointId, correctionFactor: f32) ---
			Set the motor joint correction factor, usually in [0, 1]

		MotorJoint_SetLinearOffset :: proc(jointId: JointId, linearOffset: Vec2) ---
			Set the motor joint linear offset target

		MotorJoint_SetMaxForce :: proc(jointId: JointId, maxForce: f32) ---
			Set the motor joint maximum force, usually in newtons

		MotorJoint_SetMaxTorque :: proc(jointId: JointId, maxTorque: f32) ---
			Set the motor joint maximum torque, usually in newton-meters

		MouseJoint_GetMaxForce :: proc(jointId: JointId) -> f32 ---
			Get the mouse joint maximum force, usually in newtons

		MouseJoint_GetSpringDampingRatio :: proc(jointId: JointId) -> f32 ---
			Get the mouse joint damping ratio, non-dimensional

		MouseJoint_GetSpringHertz :: proc(jointId: JointId) -> f32 ---
			Get the mouse joint spring stiffness in Hertz

		MouseJoint_GetTarget :: proc(jointId: JointId) -> Vec2 ---
			Get the mouse joint target

		MouseJoint_SetMaxForce :: proc(jointId: JointId, maxForce: f32) ---
			Set the mouse joint maximum force, usually in newtons

		MouseJoint_SetSpringDampingRatio :: proc(jointId: JointId, dampingRatio: f32) ---
			Set the mouse joint spring damping ratio, non-dimensional

		MouseJoint_SetSpringHertz :: proc(jointId: JointId, hertz: f32) ---
			Set the mouse joint spring stiffness in Hertz

		MouseJoint_SetTarget :: proc(jointId: JointId, target: Vec2) ---
			Set the mouse joint target

		Mul :: proc(a, b: Vec2) -> Vec2 {...}
			Component-wise multiplication

		MulAdd :: proc(a: Vec2, s: f32, b: Vec2) -> Vec2 {...}
			a + s * b

		MulMV :: proc(A: Mat22, v: Vec2) -> Vec2 {...}
			Multiply a 2-by-2 matrix times a 2D vector

		MulRot :: proc(q, r: Rot) -> (qr: Rot) {...}
			Multiply two rotations: q * r

		MulSV :: proc(s: f32, v: Vec2) -> Vec2 {...}
			Multiply a scalar and vector

		MulSub :: proc(a: Vec2, s: f32, b: Vec2) -> Vec2 {...}
			a - s * b

		MulTransforms :: proc(A, B: Transform) -> (C: Transform) {...}
			Multiply two transforms. If the result is applied to a point p local to frame B,
			the transform would first convert p to a point local to frame A, then into a point
			in the world frame.
			v2 = A.q.Rot(B.q.Rot(v1) + B.p) + A.p
			   = (A.q * B.q).Rot(v1) + A.q.Rot(B.p) + A.p

		NLerp :: proc(q1: Rot, q2: Rot, t: f32) -> Rot {...}
			Normalized linear interpolation
			https://fgiesen.wordpress.com/2012/08/15/linear-interpolation-past-present-and-future/
			https://web.archive.org/web/20170825184056/http://number-none.com/product/Understanding%20Slerp,%20Then%20Not%20Using%20It/

		Neg :: proc(a: Vec2) -> Vec2 {...}
			Vector negation

		Normalize :: proc(v: Vec2) -> Vec2 {...}
		NormalizeChecked :: proc(v: Vec2) -> Vec2 {...}
		NormalizeRot :: proc(q: Rot) -> Rot {...}
			Normalize rotation

		PlaneSeparation :: proc(plane: Plane, point: Vec2) -> f32 {...}
			Signed separation of a point from a plane

		PointInCapsule :: proc(point: Vec2, shape: Capsule) -> bool ---
			Test a point for overlap with a capsule in local space

		PointInCircle :: proc(point: Vec2, shape: Circle) -> bool ---
			Test a point for overlap with a circle in local space

		PointInPolygon :: proc(point: Vec2, shape: Polygon) -> bool ---
			Test a point for overlap with a convex polygon in local space

		PrismaticJoint_EnableLimit :: proc(jointId: JointId, enableLimit: bool) ---
			Enable/disable a prismatic joint limit

		PrismaticJoint_EnableMotor :: proc(jointId: JointId, enableMotor: bool) ---
			Enable/disable a prismatic joint motor

		PrismaticJoint_EnableSpring :: proc(jointId: JointId, enableSpring: bool) ---
			Enable/disable the joint spring.

		PrismaticJoint_GetLowerLimit :: proc(jointId: JointId) -> f32 ---
			Get the prismatic joint lower limit

		PrismaticJoint_GetMaxMotorForce :: proc(jointId: JointId) -> f32 ---
			Get the prismatic joint maximum motor force, usually in newtons

		PrismaticJoint_GetMotorForce :: proc(jointId: JointId) -> f32 ---
			Get the prismatic joint current motor force, usually in newtons

		PrismaticJoint_GetMotorSpeed :: proc(jointId: JointId) -> f32 ---
			Get the prismatic joint motor speed, usually in meters per second

		PrismaticJoint_GetSpeed :: proc(jointId: JointId) -> f32 ---
			Get the current joint translation speed, usually in meters per second.

		PrismaticJoint_GetSpringDampingRatio :: proc(jointId: JointId) -> f32 ---
			Get the prismatic spring damping ratio (non-dimensional)

		PrismaticJoint_GetSpringHertz :: proc(jointId: JointId) -> f32 ---
			Get the prismatic joint stiffness in Hertz

		PrismaticJoint_GetTargetTranslation :: proc(jointId: JointId) -> f32 ---
			Get the prismatic joint sprint target translation, usually in meters

		PrismaticJoint_GetTranslation :: proc(jointId: JointId) -> f32 ---
			Get the current joint translation, usually in meters.

		PrismaticJoint_GetUpperLimit :: proc(jointId: JointId) -> f32 ---
			Get the prismatic joint upper limit

		PrismaticJoint_IsLimitEnabled :: proc(jointId: JointId) -> bool ---
			Is the prismatic joint limit enabled?

		PrismaticJoint_IsMotorEnabled :: proc(jointId: JointId) -> bool ---
			Is the prismatic joint motor enabled?

		PrismaticJoint_IsSpringEnabled :: proc(jointId: JointId) -> bool ---
			Is the prismatic joint spring enabled or not?

		PrismaticJoint_SetLimits :: proc(jointId: JointId, lower, upper: f32) ---
			Set the prismatic joint limits

		PrismaticJoint_SetMaxMotorForce :: proc(jointId: JointId, force: f32) ---
			Set the prismatic joint maximum motor force, usually in newtons

		PrismaticJoint_SetMotorSpeed :: proc(jointId: JointId, motorSpeed: f32) ---
			Set the prismatic joint motor speed, usually in meters per second

		PrismaticJoint_SetSpringDampingRatio :: proc(jointId: JointId, dampingRatio: f32) ---
			Set the prismatic joint damping ratio (non-dimensional)

		PrismaticJoint_SetSpringHertz :: proc(jointId: JointId, hertz: f32) ---
			Set the prismatic joint stiffness in Hertz.
			This should usually be less than a quarter of the simulation rate. For example, if the simulation
			runs at 60Hz then the joint stiffness should be 15Hz or less.

		PrismaticJoint_SetTargetTranslation :: proc(jointId: JointId, translation: f32) ---
			Set the prismatic joint sprint target angle, usually in meters

		RayCastCapsule :: proc(input: RayCastInput, shape: Capsule) -> CastOutput ---
			Ray cast versus capsule in shape local space. Initial overlap is treated as a miss.

		RayCastCircle :: proc(input: RayCastInput, shape: Circle) -> CastOutput ---
			Ray cast versus circle in shape local space. Initial overlap is treated as a miss.

		RayCastPolygon :: proc(input: RayCastInput, shape: Polygon) -> CastOutput ---
			Ray cast versus polygon in shape local space. Initial overlap is treated as a miss.

		RayCastSegment :: proc(input: RayCastInput, shape: Segment, oneSided: bool) -> CastOutput ---
			Ray cast versus segment in shape local space. Optionally treat the segment as one-sided with hits from
			the left side being treated as a miss.

		RelativeAngle :: proc(b, a: Rot) -> f32 {...}
			relative angle between b and a (rot_b * inv(rot_a))

		RevoluteJoint_EnableLimit :: proc(jointId: JointId, enableLimit: bool) ---
			Enable/disable the revolute joint limit

		RevoluteJoint_EnableMotor :: proc(jointId: JointId, enableMotor: bool) ---
			Enable/disable a revolute joint motor

		RevoluteJoint_EnableSpring :: proc(jointId: JointId, enableSpring: bool) ---
			Enable/disable the revolute joint spring

		RevoluteJoint_GetAngle :: proc(jointId: JointId) -> f32 ---
			Get the revolute joint current angle in radians relative to the reference angle
				@see b2RevoluteJointDef::referenceAngle

		RevoluteJoint_GetLowerLimit :: proc(jointId: JointId) -> f32 ---
			Get the revolute joint lower limit in radians

		RevoluteJoint_GetMaxMotorTorque :: proc(jointId: JointId) -> f32 ---
			Get the revolute joint maximum motor torque, usually in newton-meters

		RevoluteJoint_GetMotorSpeed :: proc(jointId: JointId) -> f32 ---
			Get the revolute joint motor speed in radians per second

		RevoluteJoint_GetMotorTorque :: proc(jointId: JointId) -> f32 ---
			Get the revolute joint current motor torque, usually in newton-meters

		RevoluteJoint_GetSpringDampingRatio :: proc(jointId: JointId) -> f32 ---
			Get the revolute joint spring damping ratio, non-dimensional

		RevoluteJoint_GetSpringHertz :: proc(jointId: JointId) -> f32 ---
			Get the revolute joint spring stiffness in Hertz

		RevoluteJoint_GetTargetAngle :: proc(jointId: JointId) -> f32 ---
			Get the revolute joint spring target angle, radians

		RevoluteJoint_GetUpperLimit :: proc(jointId: JointId) -> f32 ---
			Get the revolute joint upper limit in radians

		RevoluteJoint_IsLimitEnabled :: proc(jointId: JointId) -> bool ---
			Is the revolute joint limit enabled?

		RevoluteJoint_IsMotorEnabled :: proc(jointId: JointId) -> bool ---
			Is the revolute joint motor enabled?

		RevoluteJoint_IsSpringEnabled :: proc(jointId: JointId) -> bool ---
			Is the revolute spring enabled?

		RevoluteJoint_SetLimits :: proc(jointId: JointId, lower, upper: f32) ---
			Set the revolute joint limits in radians. It is expected that lower <= upper
			and that -0.99 * B2_PI <= lower && upper <= -0.99 * B2_PI.

		RevoluteJoint_SetMaxMotorTorque :: proc(jointId: JointId, torque: f32) ---
			Set the revolute joint maximum motor torque, usually in newton-meters

		RevoluteJoint_SetMotorSpeed :: proc(jointId: JointId, motorSpeed: f32) ---
			Set the revolute joint motor speed in radians per second

		RevoluteJoint_SetSpringDampingRatio :: proc(jointId: JointId, dampingRatio: f32) ---
			Set the revolute joint spring damping ratio, non-dimensional

		RevoluteJoint_SetSpringHertz :: proc(jointId: JointId, hertz: f32) ---
			Set the revolute joint spring stiffness in Hertz

		RevoluteJoint_SetTargetAngle :: proc(jointId: JointId, angle: f32) ---
			Set the revolute joint spring target angle, radians

		RightPerp :: proc(v: Vec2) -> Vec2 {...}
			Get a right pointing perpendicular vector. Equivalent to b2CrossVS(v, 1)

		Rot_GetAngle :: proc(q: Rot) -> f32 {...}
			Get the angle in radians in the range [-pi, pi]

		Rot_GetXAxis :: proc(q: Rot) -> Vec2 {...}
			Get the x-axis

		Rot_GetYAxis :: proc(q: Rot) -> Vec2 {...}
			Get the y-axis

		RotateVector :: proc(q: Rot, v: Vec2) -> Vec2 {...}
			Rotate a vector

		SegmentDistance :: proc(p1, q1: Vec2, p2, q2: Vec2) -> SegmentDistanceResult ---
			Compute the distance between two line segments, clamping at the end points if needed.

		SetAllocator :: proc(allocFcn: AllocFcn, freefcn: FreeFcn) ---
			This allows the user to override the allocation functions. These should be
				set during application startup.

		SetAssertFcn :: proc(assertfcn: AssertFcn) ---
			Override the default assert callback
				@param assertFcn a non-null assert callback

		SetLengthUnitsPerMeter :: proc(lengthUnits: f32) ---
			Box2D bases all length units on meters, but you may need different units for your game.
			You can set this value to use different units. This should be done at application startup
			and only modified once. Default value is 1.
			For example, if your game uses pixels for units you can use pixels for all length values
			sent to Box2D. There should be no extra cost. However, Box2D has some internal tolerances
			and thresholds that have been tuned for meters. By calling this function, Box2D is able
			to adjust those tolerances and thresholds to improve accuracy.
			A good rule of thumb is to pass the height of your player character to this function. So
			if your player character is 32 pixels high, then pass 32 to this function. Then you may
			confidently use pixels for all the length values sent to Box2D. All length values returned
			from Box2D will also be pixels because Box2D does not do any scaling internally.
			However, you are now on the hook for coming up with good values for gravity, density, and
			forces.
			@warning This must be modified before any calls to Box2D

		ShapeCast :: proc(input: ShapeCastPairInput) -> CastOutput ---
			Perform a linear shape cast of shape B moving and shape A fixed. Determines the hit point, normal, and translation fraction.
			Initially touching shapes are treated as a miss.

		ShapeCastCapsule :: proc(input: ShapeCastInput, shape: Capsule) -> CastOutput ---
			Shape cast versus a capsule. Initial overlap is treated as a miss.

		ShapeCastCircle :: proc(input: ShapeCastInput, shape: Circle) -> CastOutput ---
			Shape cast versus a circle. Initial overlap is treated as a miss.

		ShapeCastPolygon :: proc(input: ShapeCastInput, shape: Polygon) -> CastOutput ---
			Shape cast versus a convex polygon. Initial overlap is treated as a miss.

		ShapeCastSegment :: proc(input: ShapeCastInput, shape: Segment) -> CastOutput ---
			Shape cast versus a line segment. Initial overlap is treated as a miss.

		ShapeDistance :: proc(input: DistanceInput, cache: ^SimplexCache, simplexes: []Simplex) -> DistanceOutput {...}
			Compute the closest points between two shapes represented as point clouds.
			SimplexCache cache is input/output. On the first call set SimplexCache.count to zero.
				The underlying GJK algorithm may be debugged by passing in debug simplexes and capacity. You may pass in NULL and 0 for these.

		Shape_AreContactEventsEnabled :: proc(shapeId: ShapeId) -> bool ---
			Returns true if contact events are enabled

		Shape_AreHitEventsEnabled :: proc(shapeId: ShapeId) -> bool ---
			Returns true if hit events are enabled

		Shape_ArePreSolveEventsEnabled :: proc(shapeId: ShapeId) -> bool ---
			Returns true if pre-solve events are enabled

		Shape_AreSensorEventsEnabled :: proc(shapeId: ShapeId) -> bool ---
			Returns true if sensor events are enabled

		Shape_EnableContactEvents :: proc(shapeId: ShapeId, flag: bool) ---
			Enable contact events for this shape. Only applies to kinematic and dynamic bodies. Ignored for sensors.
				@see b2ShapeDef::enableContactEvents
			@warning changing this at run-time may lead to lost begin/end events

		Shape_EnableHitEvents :: proc(shapeId: ShapeId, flag: bool) ---
			Enable contact hit events for this shape. Ignored for sensors.
				@see WorldDef.hitEventThreshold

		Shape_EnablePreSolveEvents :: proc(shapeId: ShapeId, flag: bool) ---
			Enable pre-solve contact events for this shape. Only applies to dynamic bodies. These are expensive
				and must be carefully handled due to multithreading. Ignored for sensors.
				@see b2PreSolveFcn

		Shape_EnableSensorEvents :: proc(shapeId: ShapeId, flag: bool) ---
			Enable sensor events for this shape.
				@see b2ShapeDef::enableSensorEvents

		Shape_GetAABB :: proc(shapeId: ShapeId) -> AABB ---
			Get the current world AABB

		Shape_GetBody :: proc(shapeId: ShapeId) -> BodyId ---
			Get the id of the body that a shape is attached to

		Shape_GetCapsule :: proc(shapeId: ShapeId) -> Capsule ---
			Get a copy of the shape's capsule. Asserts the type is correct.

		Shape_GetChainSegment :: proc(shapeId: ShapeId) -> ChainSegment ---
			Get a copy of the shape's chain segment. These come from chain shapes.
			Asserts the type is correct.

		Shape_GetCircle :: proc(shapeId: ShapeId) -> Circle ---
			Get a copy of the shape's circle. Asserts the type is correct.

		Shape_GetClosestPoint :: proc(shapeId: ShapeId, target: Vec2) -> Vec2 ---
			Get the closest point on a shape to a target point. Target and result are in world space.

		Shape_GetContactCapacity :: proc(shapeId: ShapeId) -> c.int ---
			Get the maximum capacity required for retrieving all the touching contacts on a shape

		Shape_GetContactData :: proc(shapeId: ShapeId, contactData: []ContactData) -> []ContactData {...}
			Get the touching contact data for a shape. The provided shapeId will be either shapeIdA or shapeIdB on the contact data.

		Shape_GetDensity :: proc(shapeId: ShapeId) -> f32 ---
			Get the density of a shape, usually in kg/m^2

		Shape_GetFilter :: proc(shapeId: ShapeId) -> Filter ---
			Get the shape filter

		Shape_GetFriction :: proc(shapeId: ShapeId) -> f32 ---
			Get the friction of a shape

		Shape_GetMassData :: proc(shapeId: ShapeId) -> MassData ---
			Get the mass data of a shape

		Shape_GetMaterial :: proc(shapeId: ShapeId) -> c.int ---
			Get the shape material identifier

		Shape_GetParentChain :: proc(shapeId: ShapeId) -> ChainId ---
			Get the parent chain id if the shape type is a chain segment, otherwise
			returns b2_nullChainId.

		Shape_GetPolygon :: proc(shapeId: ShapeId) -> Polygon ---
			Get a copy of the shape's convex polygon. Asserts the type is correct.

		Shape_GetRestitution :: proc(shapeId: ShapeId) -> f32 ---
			Get the shape restitution

		Shape_GetSegment :: proc(shapeId: ShapeId) -> Segment ---
			Get a copy of the shape's line segment. Asserts the type is correct.

		Shape_GetSensorCapacity :: proc(shapeId: ShapeId) -> c.int ---
			Get the maximum capacity required for retrieving all the overlapped shapes on a sensor shape.
			This returns 0 if the provided shape is not a sensor.
			@param shapeId the id of a sensor shape
			@returns the required capacity to get all the overlaps in b2Shape_GetSensorOverlaps

		Shape_GetSensorOverlaps :: proc(shapeId: ShapeId, overlaps: [^]ShapeId, capacity: c.int) -> c.int ---
			Get the overlapped shapes for a sensor shape.
			@param shapeId the id of a sensor shape
			@param overlaps a user allocated array that is filled with the overlapping shapes
			@param capacity the capacity of overlappedShapes
			@returns the number of elements filled in the provided array
			@warning do not ignore the return value, it specifies the valid number of elements
			@warning overlaps may contain destroyed shapes so use b2Shape_IsValid to confirm each overlap

		Shape_GetSurfaceMaterial :: proc(shapeId: ShapeId) -> SurfaceMaterial ---
			Get the shape surface material

		Shape_GetType :: proc(shapeId: ShapeId) -> ShapeType ---
			Get the type of a shape

		Shape_GetUserData :: proc(shapeId: ShapeId) -> rawptr ---
			Get the user data for a shape. This is useful when you get a shape id
				from an event or query.

		Shape_GetWorld :: proc(shapeId: ShapeId) -> WorldId ---
			Get the world that owns this shape.

		Shape_IsSensor :: proc(shapeId: ShapeId) -> bool ---
			Returns true if the shape is a sensor. It is not possible to change a shape
			from sensor to solid dynamically because this breaks the contract for
			sensor events.

		Shape_IsValid :: proc(id: ShapeId) -> bool ---
			Shape identifier validation. Provides validation for up to 64K allocations.

		Shape_RayCast :: proc(shapeId: ShapeId, input: RayCastInput) -> CastOutput ---
			Ray cast a shape directly

		Shape_SetCapsule :: proc(shapeId: ShapeId, capsule: Capsule) ---
			Allows you to change a shape to be a capsule or update the current capsule.
			This does not modify the mass properties.
				@see b2Body_ApplyMassFromShapes

		Shape_SetCircle :: proc(shapeId: ShapeId, circle: Circle) ---
			Allows you to change a shape to be a circle or update the current circle.
			This does not modify the mass properties.
				@see b2Body_ApplyMassFromShapes

		Shape_SetDensity :: proc(shapeId: ShapeId, density: f32, updateBodyMass: bool) ---
			Set the mass density of a shape, usually in kg/m^2.
				This will optionally update the mass properties on the parent body.
				@see b2ShapeDef::density, b2Body_ApplyMassFromShapes

		Shape_SetFilter :: proc(shapeId: ShapeId, filter: Filter) ---
			Set the current filter. This is almost as expensive as recreating the shape. This may cause
			contacts to be immediately destroyed. However contacts are not created until the next world step.
			Sensor overlap state is also not updated until the next world step.
			@see b2ShapeDef::filter

		Shape_SetFriction :: proc(shapeId: ShapeId, friction: f32) ---
			Set the friction on a shape
				@see b2ShapeDef::friction

		Shape_SetMaterial :: proc(shapeId: ShapeId, material: c.int) ---
			Set the shape material identifier
			@see b2ShapeDef::material

		Shape_SetPolygon :: proc(shapeId: ShapeId, polygon: Polygon) ---
			Allows you to change a shape to be a polygon or update the current polygon.
			This does not modify the mass properties.
				@see b2Body_ApplyMassFromShapes

		Shape_SetRestitution :: proc(shapeId: ShapeId, restitution: f32) ---
			Set the shape restitution (bounciness)
				@see b2ShapeDef::restitution

		Shape_SetSegment :: proc(shapeId: ShapeId, segment: Segment) ---
			Allows you to change a shape to be a segment or update the current segment.

		Shape_SetSurfaceMaterial :: proc(shapeId: ShapeId, surfaceMaterial: SurfaceMaterial) ---
			Set the shape surface material

		Shape_SetUserData :: proc(shapeId: ShapeId, userData: rawptr) ---
			Set the user data for a shape

		Shape_TestPoint :: proc(shapeId: ShapeId, point: Vec2) -> bool ---
			Test a point for overlap with a shape

		Solve22 :: proc(A: Mat22, b: Vec2) -> Vec2 {...}
			Solve A * x = b, where b is a column vector. This is more efficient
			than computing the inverse in one-shot cases.

		SolvePlanes :: proc(targetDelta: Vec2, planes: []CollisionPlane) -> PlaneSolverResult {...}
		StoreWorldId :: proc(id: WorldId) -> u32 {...}
			Store a world id into a u32.

		Sub :: proc(a, b: Vec2) -> Vec2 {...}
			Vector subtraction

		TimeOfImpact :: proc(input: TOIInput) -> TOIOutput ---
			Compute the upper bound on time before two shapes penetrate. Time is represented as
			a fraction between [0,tMax]. This uses a swept separating axis and may miss some intermediate,
			non-tunneling collisions. If you change the time interval, you should call this function
			again.

		TransformPoint :: proc(t: Transform, p: Vec2) -> Vec2 {...}
			Transform a point (e.g. local space to world space)

		TransformPolygon :: proc(transform: Transform, polygon: Polygon) -> Polygon ---
			Transform a polygon. This is useful for transferring a shape from one body to another.

		UnwindAngle :: proc(radians: f32) -> f32 {...}
			Convert any angle into the range [-pi, pi]

		ValidateHull :: proc(hull: Hull) -> bool ---
			This determines if a hull is valid. Checks for:
			- convexity
			- collinear points
			This is expensive and should not be called at runtime.

		WeldJoint_GetAngularDampingRatio :: proc(jointId: JointId) -> f32 ---
			Get the weld joint angular damping ratio, non-dimensional

		WeldJoint_GetAngularHertz :: proc(jointId: JointId) -> f32 ---
			Get the weld joint angular stiffness in Hertz

		WeldJoint_GetLinearDampingRatio :: proc(jointId: JointId) -> f32 ---
			Get the weld joint linear damping ratio (non-dimensional)

		WeldJoint_GetLinearHertz :: proc(jointId: JointId) -> f32 ---
			Get the weld joint linear stiffness in Hertz

		WeldJoint_SetAngularDampingRatio :: proc(jointId: JointId, dampingRatio: f32) ---
			Set weld joint angular damping ratio, non-dimensional

		WeldJoint_SetAngularHertz :: proc(jointId: JointId, hertz: f32) ---
			Set the weld joint angular stiffness in Hertz. 0 is rigid.

		WeldJoint_SetLinearDampingRatio :: proc(jointId: JointId, dampingRatio: f32) ---
			Set the weld joint linear damping ratio (non-dimensional)

		WeldJoint_SetLinearHertz :: proc(jointId: JointId, hertz: f32) ---
			Set the weld joint linear stiffness in Hertz. 0 is rigid.

		WheelJoint_EnableLimit :: proc(jointId: JointId, enableLimit: bool) ---
			Enable/disable the wheel joint limit

		WheelJoint_EnableMotor :: proc(jointId: JointId, enableMotor: bool) ---
			Enable/disable the wheel joint motor

		WheelJoint_EnableSpring :: proc(jointId: JointId, enableSpring: bool) ---
			Enable/disable the wheel joint spring

		WheelJoint_GetLowerLimit :: proc(jointId: JointId) -> f32 ---
			Get the wheel joint lower limit

		WheelJoint_GetMaxMotorTorque :: proc(jointId: JointId) -> f32 ---
			Get the wheel joint maximum motor torque, usually in newton-meters

		WheelJoint_GetMotorSpeed :: proc(jointId: JointId) -> f32 ---
			Get the wheel joint motor speed in radians per second

		WheelJoint_GetMotorTorque :: proc(jointId: JointId) -> f32 ---
			Get the wheel joint current motor torque, usually in newton-meters

		WheelJoint_GetSpringDampingRatio :: proc(jointId: JointId) -> f32 ---
			Get the wheel joint damping ratio, non-dimensional

		WheelJoint_GetSpringHertz :: proc(jointId: JointId) -> f32 ---
			Get the wheel joint stiffness in Hertz

		WheelJoint_GetUpperLimit :: proc(jointId: JointId) -> f32 ---
			Get the wheel joint upper limit

		WheelJoint_IsLimitEnabled :: proc(jointId: JointId) -> bool ---
			Is the wheel joint limit enabled?

		WheelJoint_IsMotorEnabled :: proc(jointId: JointId) -> bool ---
			Is the wheel joint motor enabled?

		WheelJoint_IsSpringEnabled :: proc(jointId: JointId) -> bool ---
			Is the wheel joint spring enabled?

		WheelJoint_SetLimits :: proc(jointId: JointId, lower, upper: f32) ---
			Set the wheel joint limits

		WheelJoint_SetMaxMotorTorque :: proc(jointId: JointId, torque: f32) ---
			Set the wheel joint maximum motor torque, usually in newton-meters

		WheelJoint_SetMotorSpeed :: proc(jointId: JointId, motorSpeed: f32) ---
			Set the wheel joint motor speed in radians per second

		WheelJoint_SetSpringDampingRatio :: proc(jointId: JointId, dampingRatio: f32) ---
			Set the wheel joint damping ratio, non-dimensional

		WheelJoint_SetSpringHertz :: proc(jointId: JointId, hertz: f32) ---
			Set the wheel joint stiffness in Hertz

		World_CastMover :: proc(worldId: WorldId, mover: Capsule, translation: Vec2, filter: QueryFilter) -> f32 ---
			Cast a capsule mover through the world. This is a special shape cast that handles sliding along other shapes while reducing
			clipping.

		World_CastRay :: proc(worldId: WorldId, origin: Vec2, translation: Vec2, filter: QueryFilter, fcn: CastResultFcn, ctx: rawptr) -> TreeStats ---
			Cast a ray into the world to collect shapes in the path of the ray.
			Your callback function controls whether you get the closest point, any point, or n-points.
				@note The callback function may receive shapes in any order
				@param worldId The world to cast the ray against
				@param origin The start point of the ray
				@param translation The translation of the ray from the start point to the end point
				@param filter Contains bit flags to filter unwanted shapes from the results
				@param fcn A user implemented callback function
				@param context A user context that is passed along to the callback function
				@return traversal performance counters

		World_CastRayClosest :: proc(worldId: WorldId, origin: Vec2, translation: Vec2, filter: QueryFilter) -> RayResult ---
			Cast a ray into the world to collect the closest hit. This is a convenience function. Ignores initial overlap.
			This is less general than b2World_CastRay() and does not allow for custom filtering.

		World_CastShape :: proc(worldId: WorldId, shape: ShapeProxy, translation: Vec2, filter: QueryFilter, fcn: CastResultFcn, ctx: rawptr) -> TreeStats ---
			Cast a shape through the world. Similar to a cast ray except that a shape is cast instead of a point.
			@see World_CastRay

		World_CollideMover :: proc(worldId: WorldId, mover: Capsule, filter: QueryFilter, fcn: PlaneResultFcn, ctx: rawptr) ---
			Collide a capsule mover with the world, gathering collision planes that can be fed to b2SolvePlanes. Useful for
			kinematic character movement.

		World_Draw :: proc(worldId: WorldId, draw: ^DebugDraw) ---
			Call this to draw shapes and other debug draw data

		World_DumpMemoryStats :: proc(worldId: WorldId) ---
			Dump memory stats to box2d_memory.txt

		World_EnableContinuous :: proc(worldId: WorldId, flag: bool) ---
			Enable/disable continuous collision between dynamic and static bodies. Generally you should keep continuous
			collision enabled to prevent fast moving objects from going through static objects. The performance gain from
				disabling continuous collision is minor.
				@see WorldDef

		World_EnableSleeping :: proc(worldId: WorldId, flag: bool) ---
			Enable/disable sleep. If your application does not need sleeping, you can gain some performance
				by disabling sleep completely at the world level.
				@see WorldDef

		World_EnableSpeculative :: proc(worldId: WorldId, flag: bool) ---
			This is for internal testing

		World_EnableWarmStarting :: proc(worldId: WorldId, flag: bool) ---
			Enable/disable constraint warm starting. Advanced feature for testing. Disabling
				warm starting greatly reduces stability and provides no performance gain.

		World_Explode :: proc(worldId: WorldId, explosionDef: ExplosionDef) ---
			Apply a radial explosion
				@param worldId The world id
				@param explosionDef The explosion definition

		World_GetAwakeBodyCount :: proc(worldId: WorldId) -> c.int ---
			Get the number of awake bodies.

		World_GetBodyEvents :: proc(worldId: WorldId) -> BodyEvents ---
			Get the body events for the current time step. The event data is transient. Do not store a reference to this data.

		World_GetContactEvents :: proc(worldId: WorldId) -> ContactEvents ---
			Get contact events for this current time step. The event data is transient. Do not store a reference to this data.

		World_GetCounters :: proc(worldId: WorldId) -> Counters ---
			Get world counters and sizes

		World_GetGravity :: proc(worldId: WorldId) -> Vec2 ---
			Get the gravity vector

		World_GetHitEventThreshold :: proc(worldId: WorldId) -> f32 ---
			Get the hit event speed threshold. Usually in meters per second.

		World_GetMaximumLinearSpeed :: proc(worldId: WorldId) -> f32 ---
			Get the maximum linear speed. Usually in m/s.

		World_GetProfile :: proc(worldId: WorldId) -> Profile ---
			Get the current world performance profile

		World_GetRestitutionThreshold :: proc(worldId: WorldId) -> f32 ---
			Get the restitution speed threshold. Usually in meters per second.

		World_GetSensorEvents :: proc(worldId: WorldId) -> SensorEvents ---
			Get sensor events for the current time step. The event data is transient. Do not store a reference to this data.

		World_GetUserData :: proc(worldId: WorldId) -> rawptr ---
			Get the user data pointer.

		World_IsContinuousEnabled :: proc(worldId: WorldId) -> bool ---
			Is continuous collision enabled?

		World_IsSleepingEnabled :: proc(worldId: WorldId) -> bool ---
			Is body sleeping enabled?

		World_IsValid :: proc(id: WorldId) -> bool ---
			World id validation. Provides validation for up to 64K allocations.

		World_IsWarmStartingEnabled :: proc(worldId: WorldId) -> bool ---
			Is constraint warm starting enabled?

		World_OverlapAABB :: proc(worldId: WorldId, aabb: AABB, filter: QueryFilter, fcn: OverlapResultFcn, ctx: rawptr) -> TreeStats ---
			Overlap test for all shapes that *potentially* overlap the provided AABB

		World_OverlapShape :: proc(worldId: WorldId, proxy: ShapeProxy, filter: QueryFilter, fcn: OverlapResultFcn, ctx: rawptr) -> TreeStats ---
			Overlap test for all shapes that overlap the provided shape proxy.

		World_RebuildStaticTree :: proc(worldId: WorldId) ---
			This is for internal testing

		World_SetContactTuning :: proc(worldId: WorldId, hertz: f32, dampingRatio: f32, pushSpeed: f32) ---
			Adjust contact tuning parameters
				@param worldId The world id
			@param hertz The contact stiffness (cycles per second)
			@param dampingRatio The contact bounciness with 1 being critical damping (non-dimensional)
			@param pushSpeed The maximum contact constraint push out speed (meters per second)
				@note Advanced feature

		World_SetCustomFilterCallback :: proc(worldId: WorldId, fcn: CustomFilterFcn, ctx: rawptr) ---
			Register the custom filter callback. This is optional.

		World_SetFrictionCallback :: proc(worldId: WorldId, callback: FrictionCallback) ---
			Set the friction callback. Passing nil resets to default.

		World_SetGravity :: proc(worldId: WorldId, gravity: Vec2) ---
			Set the gravity vector for the entire world. Box2D has no concept of an up direction and this
			is left as a decision for the application. Usually in m/s^2.
				@see WorldDef

		World_SetHitEventThreshold :: proc(worldId: WorldId, value: f32) ---
			Adjust the hit event threshold. This controls the collision velocity needed to generate a b2ContactHitEvent.
			Usually in meters per second.
				@see WorldDef::hitEventThreshold

		World_SetMaximumLinearSpeed :: proc(worldId: WorldId, maximumLinearSpeed: f32) ---
			Set the maximum linear speed. Usually in m/s.

		World_SetPreSolveCallback :: proc(worldId: WorldId, fcn: PreSolveFcn, ctx: rawptr) ---
			Register the pre-solve callback. This is optional.

		World_SetRestitutionCallback :: proc(worldId: WorldId, callback: RestitutionCallback) ---
			Set the restitution callback. Passing nil resets to default.

		World_SetRestitutionThreshold :: proc(worldId: WorldId, value: f32) ---
			Adjust the restitution threshold. It is recommended not to make this value very small
				because it will prevent bodies from sleeping. Usually in meters per second.
				@see WorldDef

		World_SetUserData :: proc(worldId: WorldId, userData: rawptr) ---
			Set the user data pointer.

		World_Step :: proc(worldId: WorldId, timeStep: f32, subStepCount: c.int) ---
			Simulate a world for one time step. This performs collision detection, integration, and constraint solution.
			@param worldId The world to simulate
			@param timeStep The amount of time to simulate, this should be a fixed number. Usually 1/60.
			@param subStepCount The number of sub-steps, increasing the sub-step count can increase accuracy. Usually 4.

		Yield :: proc() ---
			Yield to be used in a busy loop.

		b2SpringDamper :: proc(hertz, dampingRatio, position, velocity, timeStep: f32) -> f32 {...}
			One-dimensional mass-spring-damper simulation. Returns the new velocity given the position and time step.
			You can then compute the new position using:
			position += timeStep * newVelocity
			This drives towards a zero position. By using implicit integration we get a stable solution
			that doesn't require transcendental functions.


	proc_group
		IsValid :: proc{IsValidFloat, IsValidVec2, IsValidRotation, IsValidAABB, IsValidPlane, World_IsValid, Body_IsValid, Shape_IsValid, Chain_IsValid, Joint_IsValid, IsValidRay}

	types
		AABB :: struct {lowerBound: Vec2, upperBound: Vec2}
		AllocFcn :: #type proc(size: u32, alignment: i32) -> rawptr
			Prototype for user allocation function
				@param size the allocation size in bytes
				@param alignment the required alignment, guaranteed to be a power of 2

		AssertFcn :: #type proc(condition, file_name: cstring, line_number: i32) -> i32
			Prototype for the user assert callback. Return 0 to skip the debugger break.

		BodyDef :: struct {type: BodyType, position: Vec2, rotation: Rot, linearVelocity: Vec2, angularVelocity: f32, linearDamping: f32, angularDamping: f32, gravityScale: f32, sleepThreshold: f32, name: cstring, userData: rawptr, enableSleep: bool, isAwake: bool, fixedRotation: bool, isBullet: bool, isEnabled: bool, allowFastRotation: bool, internalValue: i32}
			A body definition holds all the data needed to construct a rigid body.
			You can safely re-use body definitions. Shapes are added to a body after construction.
				Body definitions are temporary objects used to bundle creation parameters.
			Must be initialized using b2DefaultBodyDef().
			@ingroup body

		BodyEvents :: struct {moveEvents: [^]BodyMoveEvent, moveCount: i32}
			Body events are buffered in the Box2D world and are available
				as event arrays after the time step is complete.
				Note: this date becomes invalid if bodies are destroyed

		BodyId :: struct {index1: i32, world0: u16, generation: u16}
			/ Body id references a body instance. This should be treated as an opaque handle.

		BodyMoveEvent :: struct {transform: Transform, bodyId: BodyId, userData: rawptr, fellAsleep: bool}
			Body move events triggered when a body moves.
			Triggered when a body moves due to simulation. Not reported for bodies moved by the user.
			This also has a flag to indicate that the body went to sleep so the application can also
			sleep that actor/entity/object associated with the body.
			On the other hand if the flag does not indicate the body went to sleep then the application
			can treat the actor/entity/object associated with the body as awake.
				This is an efficient way for an application to update game object transforms rather than
				calling functions such as b2Body_GetTransform() because this data is delivered as a contiguous array
				and it is only populated with bodies that have moved.
				@note If sleeping is disabled all dynamic and kinematic bodies will trigger move events.

		BodyType :: enum c.int {staticBody = 0, kinematicBody = 1, dynamicBody = 2}
			The body simulation type.
			Each body is one of these three types. The type determines how the body behaves in the simulation.
			@ingroup body

		Capsule :: struct {center1: Vec2, center2: Vec2, radius: f32}
			A solid capsule can be viewed as two semicircles connected
				by a rectangle.

		CastOutput :: struct {normal: Vec2, point: Vec2, fraction: f32, iterations: c.int, hit: bool}
			Low level ray cast or shape-cast output data. Returns a zero fraction and normal in the case of initial overlap.

		CastResultFcn :: #type proc(shapeId: ShapeId, point: Vec2, normal: Vec2, fraction: f32, ctx: rawptr) -> f32
			Prototype callback for ray and shape casts.
			Called for each shape found in the query. You control how the ray cast
			proceeds by returning a f32:
			return -1: ignore this shape and continue
			return 0: terminate the ray cast
			return fraction: clip the ray to this point
			return 1: don't clip the ray and continue
			A cast with initial overlap will return a zero fraction and a zero normal.
			@param shapeId the shape hit by the ray
			@param point the point of initial intersection
			@param normal the normal vector at the point of intersection, zero for a shape cast with initial overlap
			@param fraction the fraction along the ray at the point of intersection, zero for a shape cast with initial overlap
				@param context the user context
			@return -1 to filter, 0 to terminate, fraction to clip the ray for closest hit, 1 to continue
			@see b2World_CastRay
				@ingroup world

		ChainDef :: struct {userData: rawptr, points: [^]Vec2, count: i32, materials: [^]SurfaceMaterial, materialCount: i32, filter: Filter, isLoop: bool, enableSensorEvents: bool, internalValue: i32}
			Used to create a chain of line segments. This is designed to eliminate ghost collisions with some limitations.
				- chains are one-sided
				- chains have no mass and should be used on static bodies
				- chains have a counter-clockwise winding order (normal points right of segment direction)
				- chains are either a loop or open
			- a chain must have at least 4 points
				- the distance between any two points must be greater than B2_LINEAR_SLOP
				- a chain shape should not self intersect (this is not validated)
				- an open chain shape has NO COLLISION on the first and final edge
				- you may overlap two open chains on their first three and/or last three points to get smooth collision
				- a chain shape creates multiple line segment shapes on the body
			https://en.wikipedia.org/wiki/Polygonal_chain
			Must be initialized using b2DefaultChainDef().
				@warning Do not use chain shapes unless you understand the limitations. This is an advanced feature.
			@ingroup shape

		ChainId :: struct {index1: i32, world0: u16, generation: u16}
			/ Chain id references a chain instances. This should be treated as an opaque handle.

		ChainSegment :: struct {ghost1: Vec2, segment: Segment, ghost2: Vec2, chainId: c.int}
			A line segment with one-sided collision. Only collides on the right side.
			Several of these are generated for a chain shape.
			ghost1 -> point1 -> point2 -> ghost2

		Circle :: struct {center: Vec2, radius: f32}
			A solid circle

		CollisionPlane :: struct {plane: Plane, pushLimit: f32, push: f32, clipVelocity: bool}
			These are collision planes that can be fed to b2SolvePlanes. Normally
			this is assembled by the user from plane results in b2PlaneResult

		ContactBeginTouchEvent :: struct {shapeIdA: ShapeId, shapeIdB: ShapeId, manifold: Manifold}
			A begin touch event is generated when two shapes begin touching.

		ContactData :: struct {shapeIdA: ShapeId, shapeIdB: ShapeId, manifold: Manifold}
			The contact data for two shapes. By convention the manifold normal points
				from shape A to shape B.
				@see b2Shape_GetContactData() and b2Body_GetContactData()

		ContactEndTouchEvent :: struct {shapeIdA: ShapeId, shapeIdB: ShapeId}
			An end touch event is generated when two shapes stop touching.
			You will get an end event if you do anything that destroys contacts previous to the last
			world step. These include things like setting the transform, destroying a body
			or shape, or changing a filter or body type.

		ContactEvents :: struct {beginEvents: [^]ContactBeginTouchEvent, endEvents: [^]ContactEndTouchEvent, hitEvents: [^]ContactHitEvent, beginCount: i32, endCount: i32, hitCount: i32}
			Contact events are buffered in the Box2D world and are available
				as event arrays after the time step is complete.
				Note: these may become invalid if bodies and/or shapes are destroyed

		ContactHitEvent :: struct {shapeIdA: ShapeId, shapeIdB: ShapeId, point: Vec2, normal: Vec2, approachSpeed: f32}
			A hit touch event is generated when two shapes collide with a speed faster than the hit speed threshold.
			This may be reported for speculative contacts that have a confirmed impulse.

		CosSin :: struct {cosine: f32, sine: f32}
			Cosine and sine pair
			This uses a custom implementation designed for cross-platform determinism

		Counters :: struct {bodyCount: i32, shapeCount: i32, contactCount: i32, jointCount: i32, islandCount: i32, stackUsed: i32, staticTreeHeight: i32, treeHeight: i32, byteCount: i32, taskCount: i32, colorCounts: [12]i32}
			Counters that give details of the simulation size.

		CustomFilterFcn :: #type proc(shapeIdA, shapeIdB: ShapeId, ctx: rawptr) -> bool
			Prototype for a contact filter callback.
			This is called when a contact pair is considered for collision. This allows you to
				perform custom logic to prevent collision between shapes. This is only called if
				one of the two shapes has custom filtering enabled. @see b2ShapeDef.
			Notes:
				- this function must be thread-safe
				- this is only called if one of the two shapes has enabled custom filtering
			- this is called only for awake dynamic bodies
				Return false if you want to disable the collision
				@warning Do not attempt to modify the world inside this callback
				@ingroup world

		DebugDraw :: struct {DrawPolygonFcn: proc(vertices: [^]Vec2, vertexCount: c.int, color: HexColor, ctx: rawptr), DrawSolidPolygonFcn: proc(transform: Transform, vertices: [^]Vec2, vertexCount: c.int, radius: f32, colr: HexColor, ctx: rawptr), DrawCircleFcn: proc(center: Vec2, radius: f32, color: HexColor, ctx: rawptr), DrawSolidCircleFcn: proc(transform: Transform, radius: f32, color: HexColor, ctx: rawptr), DrawSolidCapsuleFcn: proc(p1, p2: Vec2, radius: f32, color: HexColor, ctx: rawptr), DrawSegmentFcn: proc(p1, p2: Vec2, color: HexColor, ctx: rawptr), DrawTransformFcn: proc(transform: Transform, ctx: rawptr), DrawPointFcn: proc(p: Vec2, size: f32, color: HexColor, ctx: rawptr), DrawStringFcn: proc(p: Vec2, s: cstring, color: HexColor, ctx: rawptr), drawingBounds: AABB, useDrawingBounds: bool, drawShapes: bool, drawJoints: bool, drawJointExtras: bool, drawBounds: bool, drawMass: bool, drawBodyNames: bool, drawContacts: bool, drawGraphColors: bool, drawContactNormals: bool, drawContactImpulses: bool, drawContactFeatures: bool, drawFrictionImpulses: bool, drawIslands: bool, userContext: rawptr}
			This struct holds callbacks you can implement to draw a Box2D world.
				@ingroup world

		DistanceInput :: struct {proxyA: ShapeProxy, proxyB: ShapeProxy, transformA: Transform, transformB: Transform, useRadii: bool}
			Input for b2ShapeDistance

		DistanceJointDef :: struct {bodyIdA: BodyId, bodyIdB: BodyId, localAnchorA: Vec2, localAnchorB: Vec2, length: f32, enableSpring: bool, hertz: f32, dampingRatio: f32, enableLimit: bool, minLength: f32, maxLength: f32, enableMotor: bool, maxMotorForce: f32, motorSpeed: f32, collideConnected: bool, userData: rawptr, internalValue: i32}
			Distance joint definition
			
			This requires defining an anchor point on both
			bodies and the non-zero distance of the distance joint. The definition uses
			local anchor points so that the initial configuration can violate the
			constraint slightly. This helps when saving and loading a game.
			@ingroup distance_joint

		DistanceOutput :: struct {pointA: Vec2, pointB: Vec2, normal: Vec2, distance: f32, iterations: i32, simplexCount: i32}
			Output for b2ShapeDistance

		DynamicTree :: struct {nodes: rawptr, root: i32, nodeCount: i32, nodeCapacity: i32, freeList: i32, proxyCount: i32, leafIndices: [^]i32, leafBoxes: [^]AABB, leafCenters: [^]Vec2, binIndices: [^]i32, rebuildCapacity: i32}
			The dynamic tree structure. This should be considered private data.
			It is placed here for performance reasons.

		EnqueueTaskCallback :: #type proc(task: TaskCallback, itemCount: i32, minRange: i32, taskContext: rawptr, userContext: rawptr) -> rawptr
			These functions can be provided to Box2D to invoke a task system. These are designed to work well with enkiTS.
			Returns a pointer to the user's task object. May be nullptr. A nullptr indicates to Box2D that the work was executed
				serially within the callback and there is no need to call b2FinishTaskCallback.
				The itemCount is the number of Box2D work items that are to be partitioned among workers by the user's task system.
				This is essentially a parallel-for. The minRange parameter is a suggestion of the minimum number of items to assign
				per worker to reduce overhead. For example, suppose the task is small and that itemCount is 16. A minRange of 8 suggests
				that your task system should split the work items among just two workers, even if you have more available.
				In general the range [startIndex, endIndex) send to TaskCallback should obey:
				endIndex - startIndex >= minRange
				The exception of course is when itemCount < minRange.
				@ingroup world

		ExplosionDef :: struct {maskBits: u64, position: Vec2, radius: f32, falloff: f32, impulsePerLength: f32}
			The explosion definition is used to configure options for explosions. Explosions
			consider shape geometry when computing the impulse.
			@ingroup world

		Filter :: struct {categoryBits: u64, maskBits: u64, groupIndex: i32}
			This is used to filter collision on shapes. It affects shape-vs-shape collision
				and shape-versus-query collision (such as b2World_CastRay).
			@ingroup shape

		FilterJointDef :: struct {bodyIdA: BodyId, bodyIdB: BodyId, userData: rawptr, internalValue: i32}
			A filter joint is used to disable collision between two specific bodies.
			
			@ingroup filter_joint

		FinishTaskCallback :: #type proc(userTask: rawptr, userContext: rawptr)
			Finishes a user task object that wraps a Box2D task.
				@ingroup world

		FreeFcn :: #type proc(mem: rawptr)
			Prototype for user free function
				@param mem the memory previously allocated through `b2AllocFcn`

		FrictionCallback :: #type proc(frictionA: f32, userMaterialIdA: i32, frictionB: f32, userMaterialIdB: i32) -> f32
			Optional friction mixing callback. This intentionally provides no context objects because this is called
			from a worker thread.
			@warning This function should not attempt to modify Box2D state or user application state.
			@ingroup world

		HexColor :: enum c.int {AliceBlue = 0xF0F8FF, AntiqueWhite = 0xFAEBD7, Aqua = 0x00FFFF, Aquamarine = 0x7FFFD4, Azure = 0xF0FFFF, Beige = 0xF5F5DC, Bisque = 0xFFE4C4, Black = 0x000000, BlanchedAlmond = 0xFFEBCD, Blue = 0x0000FF, BlueViolet = 0x8A2BE2, Brown = 0xA52A2A, Burlywood = 0xDEB887, CadetBlue = 0x5F9EA0, Chartreuse = 0x7FFF00, Chocolate = 0xD2691E, Coral = 0xFF7F50, CornflowerBlue = 0x6495ED, Cornsilk = 0xFFF8DC, Crimson = 0xDC143C, Cyan = 0x00FFFF, DarkBlue = 0x00008B, DarkCyan = 0x008B8B, DarkGoldenRod = 0xB8860B, DarkGray = 0xA9A9A9, DarkGreen = 0x006400, DarkKhaki = 0xBDB76B, DarkMagenta = 0x8B008B, DarkOliveGreen = 0x556B2F, DarkOrange = 0xFF8C00, DarkOrchid = 0x9932CC, DarkRed = 0x8B0000, DarkSalmon = 0xE9967A, DarkSeaGreen = 0x8FBC8F, DarkSlateBlue = 0x483D8B, DarkSlateGray = 0x2F4F4F, DarkTurquoise = 0x00CED1, DarkViolet = 0x9400D3, DeepPink = 0xFF1493, DeepSkyBlue = 0x00BFFF, DimGray = 0x696969, DodgerBlue = 0x1E90FF, FireBrick = 0xB22222, FloralWhite = 0xFFFAF0, ForestGreen = 0x228B22, Fuchsia = 0xFF00FF, Gainsboro = 0xDCDCDC, GhostWhite = 0xF8F8FF, Gold = 0xFFD700, GoldenRod = 0xDAA520, Gray = 0x808080, Green = 0x008000, GreenYellow = 0xADFF2F, HoneyDew = 0xF0FFF0, HotPink = 0xFF69B4, IndianRed = 0xCD5C5C, Indigo = 0x4B0082, Ivory = 0xFFFFF0, Khaki = 0xF0E68C, Lavender = 0xE6E6FA, LavenderBlush = 0xFFF0F5, LawnGreen = 0x7CFC00, LemonChiffon = 0xFFFACD, LightBlue = 0xADD8E6, LightCoral = 0xF08080, LightCyan = 0xE0FFFF, LightGoldenRodYellow = 0xFAFAD2, LightGray = 0xD3D3D3, LightGreen = 0x90EE90, LightPink = 0xFFB6C1, LightSalmon = 0xFFA07A, LightSeaGreen = 0x20B2AA, LightSkyBlue = 0x87CEFA, LightSlateGray = 0x778899, LightSteelBlue = 0xB0C4DE, LightYellow = 0xFFFFE0, Lime = 0x00FF00, LimeGreen = 0x32CD32, Linen = 0xFAF0E6, Magenta = 0xFF00FF, Maroon = 0x800000, MediumAquaMarine = 0x66CDAA, MediumBlue = 0x0000CD, MediumOrchid = 0xBA55D3, MediumPurple = 0x9370DB, MediumSeaGreen = 0x3CB371, MediumSlateBlue = 0x7B68EE, MediumSpringGreen = 0x00FA9A, MediumTurquoise = 0x48D1CC, MediumVioletRed = 0xC71585, MidnightBlue = 0x191970, MintCream = 0xF5FFFA, MistyRose = 0xFFE4E1, Moccasin = 0xFFE4B5, NavajoWhite = 0xFFDEAD, Navy = 0x000080, OldLace = 0xFDF5E6, Olive = 0x808000, OliveDrab = 0x6B8E23, Orange = 0xFFA500, OrangeRed = 0xFF4500, Orchid = 0xDA70D6, PaleGoldenRod = 0xEEE8AA, PaleGreen = 0x98FB98, PaleTurquoise = 0xAFEEEE, PaleVioletRed = 0xDB7093, PapayaWhip = 0xFFEFD5, PeachPuff = 0xFFDAB9, Peru = 0xCD853F, Pink = 0xFFC0CB, Plum = 0xDDA0DD, PowderBlue = 0xB0E0E6, Purple = 0x800080, RebeccaPurple = 0x663399, Red = 0xFF0000, RosyBrown = 0xBC8F8F, RoyalBlue = 0x4169E1, SaddleBrown = 0x8B4513, Salmon = 0xFA8072, SandyBrown = 0xF4A460, SeaGreen = 0x2E8B57, SeaShell = 0xFFF5EE, Sienna = 0xA0522D, Silver = 0xC0C0C0, SkyBlue = 0x87CEEB, SlateBlue = 0x6A5ACD, SlateGray = 0x708090, Snow = 0xFFFAFA, SpringGreen = 0x00FF7F, SteelBlue = 0x4682B4, Tan = 0xD2B48C, Teal = 0x008080, Thistle = 0xD8BFD8, Tomato = 0xFF6347, Turquoise = 0x40E0D0, Violet = 0xEE82EE, Wheat = 0xF5DEB3, White = 0xFFFFFF, WhiteSmoke = 0xF5F5F5, Yellow = 0xFFFF00, YellowGreen = 0x9ACD32, Box2DRed = 0xDC3132, Box2DBlue = 0x30AEBF, Box2DGreen = 0x8CC924, Box2DYellow = 0xFFEE8C}
			These colors are used for debug draw and mostly match the named SVG colors.
			See https://www.rapidtables.com/web/color/index.html
			https://johndecember.com/html/spec/colorsvg.html
			https://upload.wikimedia.org/wikipedia/commons/2/2b/SVG_Recognized_color_keyword_names.svg

		Hull :: struct {points: [MAX_POLYGON_VERTICES]Vec2, count: c.int}
			A convex hull. Used to create convex polygons.
				@warning Do not modify these values directly, instead use b2ComputeHull()

		JointId :: struct {index1: i32, world0: u16, generation: u16}
			/ Joint id references a joint instance. This should be treated as an opaque handle.

		JointType :: enum c.int {distanceJoint, filterJoint, motorJoint, mouseJoint, prismaticJoint, revoluteJoint, weldJoint, wheelJoint}
			Joint type enumeration
			
			This is useful because all joint types use b2JointId and sometimes you
			want to get the type of a joint.
			@ingroup joint

		Manifold :: struct {normal: Vec2, rollingImpulse: f32, points: [2]ManifoldPoint, pointCount: c.int}
			A contact manifold describes the contact points between colliding shapes.
			@note Box2D uses speculative collision so some contact points may be separated.

		ManifoldPoint :: struct {point: Vec2, anchorA: Vec2, anchorB: Vec2, separation: f32, totalNormalImpulse: f32, tangentImpulse: f32, maxNormalImpulse: f32, normalVelocity: f32, id: u16, persisted: bool}
			A manifold point is a contact point belonging to a contact manifold.
			It holds details related to the geometry and dynamics of the contact points.
			Box2D uses speculative collision so some contact points may be separated.
			You may use the totalNormalImpulse to determine if there was an interaction during
			the time step.

		MassData :: struct {mass: f32, center: Vec2, rotationalInertia: f32}
			This holds the mass data computed for a shape.

		Mat22 :: matrix[2, 2]f32
		MotorJointDef :: struct {bodyIdA: BodyId, bodyIdB: BodyId, linearOffset: Vec2, angularOffset: f32, maxForce: f32, maxTorque: f32, correctionFactor: f32, collideConnected: bool, userData: rawptr, internalValue: i32}
			A motor joint is used to control the relative motion between two bodies
			
			A typical usage is to control the movement of a dynamic body with respect to the ground.
			@ingroup motor_joint

		MouseJointDef :: struct {bodyIdA: BodyId, bodyIdB: BodyId, target: Vec2, hertz: f32, dampingRatio: f32, maxForce: f32, collideConnected: bool, userData: rawptr, internalValue: i32}
			A mouse joint is used to make a point on a body track a specified world point.
			
			This a soft constraint and allows the constraint to stretch without
			applying huge forces. This also applies rotation constraint heuristic to improve control.
			@ingroup mouse_joint

		OverlapResultFcn :: #type proc(shapeId: ShapeId, ctx: rawptr) -> bool
			Prototype callback for overlap queries.
			Called for each shape found in the query.
			@see b2World_QueryAABB
			@return false to terminate the query.
				@ingroup world

		Plane :: struct {normal: Vec2, offset: f32}
			separation = dot(normal, point) - offset

		PlaneResult :: struct {plane: Plane, point: Vec2, hit: bool}
			/ These are the collision planes returned from b2World_CollideMover

		PlaneResultFcn :: #type proc(shapeId: ShapeId, plane: ^PlaneResult, ctx: rawptr) -> bool
			Used to collect collision planes for character movers.
			Return true to continue gathering planes.

		PlaneSolverResult :: struct {translation: Vec2, iterationCount: i32}
			Result returned by b2SolvePlanes

		Polygon :: struct {vertices: [MAX_POLYGON_VERTICES]Vec2, normals: [MAX_POLYGON_VERTICES]Vec2, centroid: Vec2, radius: f32, count: c.int}
			A solid convex polygon. It is assumed that the interior of the polygon is to
			the left of each edge.
			Polygons have a maximum number of vertices equal to MAX_POLYGON_VERTICES.
			In most cases you should not need many vertices for a convex polygon.
			@warning DO NOT fill this out manually, instead use a helper function like
			b2MakePolygon or b2MakeBox.

		PreSolveFcn :: #type proc(shapeIdA, shapeIdB: ShapeId, manifold: ^Manifold, ctx: rawptr) -> bool
			Prototype for a pre-solve callback.
			This is called after a contact is updated. This allows you to inspect a
			contact before it goes to the solver. If you are careful, you can modify the
			contact manifold (e.g. modify the normal).
			Notes:
				- this function must be thread-safe
				- this is only called if the shape has enabled pre-solve events
			- this is called only for awake dynamic bodies
			- this is not called for sensors
			- the supplied manifold has impulse values from the previous step
				Return false if you want to disable the contact this step
				@warning Do not attempt to modify the world inside this callback
				@ingroup world

		PrismaticJointDef :: struct {bodyIdA: BodyId, bodyIdB: BodyId, localAnchorA: Vec2, localAnchorB: Vec2, localAxisA: Vec2, referenceAngle: f32, targetTranslation: f32, enableSpring: bool, hertz: f32, dampingRatio: f32, enableLimit: bool, lowerTranslation: f32, upperTranslation: f32, enableMotor: bool, maxMotorForce: f32, motorSpeed: f32, collideConnected: bool, userData: rawptr, internalValue: i32}
			Prismatic joint definition
			
			This requires defining a line of motion using an axis and an anchor point.
			The definition uses local anchor points and a local axis so that the initial
			configuration can violate the constraint slightly. The joint translation is zero
			when the local anchor points coincide in world space.
			@ingroup prismatic_joint

		Profile :: struct {step: f32, pairs: f32, collide: f32, solve: f32, mergeIslands: f32, prepareStages: f32, solveConstraints: f32, prepareConstraints: f32, integrateVelocities: f32, warmStart: f32, solveImpulses: f32, integratePositions: f32, relaxImpulses: f32, applyRestitution: f32, storeImpulses: f32, splitIslands: f32, transforms: f32, hitEvents: f32, refit: f32, bullets: f32, sleepIslands: f32, sensors: f32}
			! @cond
			Profiling data. Times are in milliseconds.

		QueryFilter :: struct {categoryBits: u64, maskBits: u64}
			The query filter is used to filter collisions between queries and shapes. For example,
				you may want a ray-cast representing a projectile to hit players and the static environment
				but not debris.
			@ingroup shape

		RayCastInput :: struct {origin: Vec2, translation: Vec2, maxFraction: f32}
			Low level ray cast input data

		RayResult :: struct {shapeId: ShapeId, point: Vec2, normal: Vec2, fraction: f32, nodeVisits: i32, leafVisits: i32, hit: bool}
			Result from b2World_RayCastClosest
			If there is initial overlap the fraction and normal will be zero while the point is an arbitrary point in the overlap region.
			@ingroup world

		RestitutionCallback :: #type proc(restitutionA: f32, userMaterialIdA: i32, restitutionB: f32, userMaterialIdB: i32) -> f32
			Optional restitution mixing callback. This intentionally provides no context objects because this is called
			from a worker thread.
			@warning This function should not attempt to modify Box2D state or user application state.
			@ingroup world

		RevoluteJointDef :: struct {bodyIdA: BodyId, bodyIdB: BodyId, localAnchorA: Vec2, localAnchorB: Vec2, referenceAngle: f32, targetAngle: f32, enableSpring: bool, hertz: f32, dampingRatio: f32, enableLimit: bool, lowerAngle: f32, upperAngle: f32, enableMotor: bool, maxMotorTorque: f32, motorSpeed: f32, drawSize: f32, collideConnected: bool, userData: rawptr, internalValue: i32}
			Revolute joint definition
			
			This requires defining an anchor point where the bodies are joined.
			The definition uses local anchor points so that the
			initial configuration can violate the constraint slightly. You also need to
			specify the initial relative angle for joint limits. This helps when saving
			and loading a game.
			The local anchor points are measured from the body's origin
			rather than the center of mass because:
			1. you might not know where the center of mass will be
			2. if you add/remove shapes from a body and recompute the mass, the joints will be broken
			@ingroup revolute_joint

		Rot :: struct {c, s: f32}
		Segment :: struct {point1: Vec2, point2: Vec2}
			A line segment with two-sided collision.

		SegmentDistanceResult :: struct {closest1: Vec2, closest2: Vec2, fraction1: f32, fraction2: f32, distanceSquared: f32}
			Result of computing the distance between two line segments

		SensorBeginTouchEvent :: struct {sensorShapeId: ShapeId, visitorShapeId: ShapeId}
			A begin touch event is generated when a shape starts to overlap a sensor shape.

		SensorEndTouchEvent :: struct {sensorShapeId: ShapeId, visitorShapeId: ShapeId}
			An end touch event is generated when a shape stops overlapping a sensor shape.
			These include things like setting the transform, destroying a body or shape, or changing
			a filter. You will also get an end event if the sensor or visitor are destroyed.
			Therefore you should always confirm the shape id is valid using b2Shape_IsValid.

		SensorEvents :: struct {beginEvents: [^]SensorBeginTouchEvent, endEvents: [^]SensorEndTouchEvent, beginCount: i32, endCount: i32}
			Sensor events are buffered in the Box2D world and are available
				as begin/end overlap event arrays after the time step is complete.
				Note: these may become invalid if bodies and/or shapes are destroyed

		ShapeCastInput :: struct {proxy: ShapeProxy, translation: Vec2, maxFraction: f32, canEncroach: bool}
			Low level shape cast input in generic form. This allows casting an arbitrary point
			cloud wrap with a radius. For example, a circle is a single point with a non-zero radius.
			A capsule is two points with a non-zero radius. A box is four points with a zero radius.

		ShapeCastPairInput :: struct {proxyA: ShapeProxy, proxyB: ShapeProxy, transformA: Transform, transformB: Transform, translationB: Vec2, maxFraction: f32, canEncroach: bool}
			Input parameters for b2ShapeCast

		ShapeDef :: struct {userData: rawptr, material: SurfaceMaterial, density: f32, filter: Filter, isSensor: bool, enableSensorEvents: bool, enableContactEvents: bool, enableHitEvents: bool, enablePreSolveEvents: bool, invokeContactCreation: bool, updateBodyMass: bool, internalValue: i32}
			Used to create a shape.
			This is a temporary object used to bundle shape creation parameters. You may use
				the same shape definition to create multiple shapes.
			Must be initialized using b2DefaultShapeDef().
			@ingroup shape

		ShapeId :: struct {index1: i32, world0: u16, generation: u16}
			/ Shape id references a shape instance. This should be treated as an opaque handle.

		ShapeProxy :: struct {points: [MAX_POLYGON_VERTICES]Vec2, count: c.int, radius: f32}
			A distance proxy is used by the GJK algorithm. It encapsulates any shape.
			You can provide between 1 and MAX_POLYGON_VERTICES and a radius.

		ShapeType :: enum c.int {circleShape, capsuleShape, segmentShape, polygonShape, chainSegmentShape}
			Shape type
			@ingroup shape

		Simplex :: struct {v1, v2, v3: SimplexVertex, count: c.int}
			Simplex from the GJK algorithm

		SimplexCache :: struct {count: u16, indexA: [3]u8, indexB: [3]u8}
			Used to warm start the GJK simplex. If you call this function multiple times with nearby
			transforms this might improve performance. Otherwise you can zero initialize this.
			The distance cache must be initialized to zero on the first call.
			Users should generally just zero initialize this structure for each call.

		SimplexVertex :: struct {wA: Vec2, wB: Vec2, w: Vec2, a: f32, indexA: c.int, indexB: c.int}
			Simplex vertex for debugging the GJK algorithm

		SurfaceMaterial :: struct {friction: f32, restitution: f32, rollingResistance: f32, tangentSpeed: f32, userMaterialId: i32, customColor: u32}
			Surface materials allow chain shapes to have per segment surface properties.
			@ingroup shape

		Sweep :: struct {localCenter: Vec2, c1: Vec2, c2: Vec2, q1: Rot, q2: Rot}
			This describes the motion of a body/shape for TOI computation. Shapes are defined with respect to the body origin,
			which may not coincide with the center of mass. However, to support dynamics we must interpolate the center of mass
			position.

		TOIInput :: struct {proxyA: ShapeProxy, proxyB: ShapeProxy, sweepA: Sweep, sweepB: Sweep, maxFraction: f32}
			Input parameters for b2TimeOfImpact

		TOIOutput :: struct {state: TOIState, fraction: f32}
			Output parameters for b2TimeOfImpact.

		TOIState :: enum c.int {Unknown, Failed, Overlapped, Hit, Separated}
			Describes the TOI output

		TaskCallback :: #type proc(startIndex, endIndex: i32, workerIndex: u32, taskContext: rawptr)
			Task interface
			This is prototype for a Box2D task. Your task system is expected to invoke the Box2D task with these arguments.
			The task spans a range of the parallel-for: [startIndex, endIndex)
			The worker index must correctly identify each worker in the user thread pool, expected in [0, workerCount).
				A worker must only exist on only one thread at a time and is analogous to the thread index.
			The task context is the context pointer sent from Box2D when it is enqueued.
				The startIndex and endIndex are expected in the range [0, itemCount) where itemCount is the argument to b2EnqueueTaskCallback
			below. Box2D expects startIndex < endIndex and will execute a loop like this:
			
				@code{.odin}
				for i in startIndex ..< endIndex {
					DoWork()
				}
				@endcode
				@ingroup world

		Transform :: struct {p: Vec2, q: Rot}
		TreeQueryCallbackFcn :: #type proc(proxyId: i32, userData: u64, ctx: rawptr) -> bool
			This function receives proxies found in the AABB query.
			@return true if the query should continue

		TreeRayCastCallbackFcn :: #type proc(input: RayCastInput, proxyId: i32, userData: u64, ctx: rawptr) -> f32
			This function receives clipped raycast input for a proxy. The function
			returns the new ray fraction.
			- return a value of 0 to terminate the ray cast
			- return a value less than input->maxFraction to clip the ray
			- return a value of input->maxFraction to continue the ray cast without clipping

		TreeShapeCastCallbackFcn :: #type proc(input: ShapeCastInput, proxyId: i32, userData: u64, ctx: rawptr) -> f32
			This function receives clipped ray cast input for a proxy. The function
			returns the new ray fraction.
			- return a value of 0 to terminate the ray cast
			- return a value less than input->maxFraction to clip the ray
			- return a value of input->maxFraction to continue the ray cast without clipping

		TreeStats :: struct {nodeVisits: c.int, leafVisits: c.int}
			These are performance results returned by dynamic tree queries.

		Vec2 :: [2]f32
		Version :: struct {major: i32, minor: i32, revision: i32}
			Version numbering scheme.
			
			See https://semver.org/

		WeldJointDef :: struct {bodyIdA: BodyId, bodyIdB: BodyId, localAnchorA: Vec2, localAnchorB: Vec2, referenceAngle: f32, linearHertz: f32, angularHertz: f32, linearDampingRatio: f32, angularDampingRatio: f32, collideConnected: bool, userData: rawptr, internalValue: i32}
			Weld joint definition
			
			A weld joint connect to bodies together rigidly. This constraint provides springs to mimic
				soft-body simulation.
			@note The approximate solver in Box2D cannot hold many bodies together rigidly
			@ingroup weld_joint

		WheelJointDef :: struct {bodyIdA: BodyId, bodyIdB: BodyId, localAnchorA: Vec2, localAnchorB: Vec2, localAxisA: Vec2, enableSpring: bool, hertz: f32, dampingRatio: f32, enableLimit: bool, lowerTranslation: f32, upperTranslation: f32, enableMotor: bool, maxMotorTorque: f32, motorSpeed: f32, collideConnected: bool, userData: rawptr, internalValue: i32}
			Wheel joint definition
			
			This requires defining a line of motion using an axis and an anchor point.
			The definition uses local  anchor points and a local axis so that the initial
			configuration can violate the constraint slightly. The joint translation is zero
			when the local anchor points coincide in world space.
			@ingroup wheel_joint

		WorldDef :: struct {gravity: Vec2, restitutionThreshold: f32, hitEventThreshold: f32, contactHertz: f32, contactDampingRatio: f32, maxContactPushSpeed: f32, maximumLinearSpeed: f32, frictionCallback: FrictionCallback, restitutionCallback: RestitutionCallback, enableSleep: bool, enableContinuous: bool, workerCount: i32, enqueueTask: EnqueueTaskCallback, finishTask: FinishTaskCallback, userTaskContext: rawptr, userData: rawptr, internalValue: i32}
			World definition used to create a simulation world.
			Must be initialized using b2DefaultWorldDef().
			@ingroup world

		WorldId :: struct {index1: u16, generation: u16}
			/ World id references a world instance. This should be treated as an opaque handle.



	fullpath:
		/opt/homebrew/Cellar/odin/2026-03/libexec/vendor/box2d
	files:
		box2d.odin
		collision.odin
		id.odin
		math_functions.odin
		types.odin
