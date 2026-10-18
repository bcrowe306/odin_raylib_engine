package engine

import "core:c"
import "core:math"
import b2 "vendor:box2d"

PhysicsWorld :: struct {
	worldId: b2.WorldId,
	gravity: [2]f32 `gui:"true" min:"-2000" max:"2000"`,
	subStepCount: int `gui:"true" min:"1" max:"16"`,
	lengthUnitsPerMeter: f32 `gui:"true" min:"1" max:"200"`,
	restitutionThreshold: f32 `gui:"true" min:"0" max:"500"`,
	hitEventThreshold: f32 `gui:"true" min:"0" max:"500"`,
	contactHertz: f32 `gui:"true" min:"1" max:"240"`,
	contactDampingRatio: f32 `gui:"true" min:"0" max:"20"`,
	maxContactPushSpeed: f32 `gui:"true" min:"0" max:"1000"`,
	maximumLinearSpeed: f32 `gui:"true" min:"10" max:"10000"`,
	enableSleep: bool `gui:"true"`,
	enableContinuous: bool `gui:"true"`,
	enableWarmStarting: bool `gui:"true"`,
	drawPhysicsDebug: bool `gui:"true"`,
	paused: bool `gui:"true"`,
}

PhysicsWorld_Init :: proc(pw: ^PhysicsWorld) {
	pw.lengthUnitsPerMeter = 32.0
	b2.SetLengthUnitsPerMeter(pw.lengthUnitsPerMeter)

	def := b2.DefaultWorldDef()
	def.gravity = {0.0, 300.0}
	pw.gravity = def.gravity
	pw.subStepCount = 4
	pw.restitutionThreshold = def.restitutionThreshold
	pw.hitEventThreshold = def.hitEventThreshold
	pw.contactHertz = def.contactHertz
	pw.contactDampingRatio = def.contactDampingRatio
	pw.maxContactPushSpeed = def.maxContactPushSpeed
	pw.maximumLinearSpeed = def.maximumLinearSpeed
	pw.enableSleep = def.enableSleep
	pw.enableContinuous = def.enableContinuous
	pw.enableWarmStarting = true
	pw.drawPhysicsDebug = true
	pw.paused = false

	pw.worldId = b2.CreateWorld(def)
}

PhysicsWorld_SyncSettings :: proc(pw: ^PhysicsWorld) {
	if !b2.World_IsValid(pw.worldId) do return

	if pw.lengthUnitsPerMeter > 0.01 {
		b2.SetLengthUnitsPerMeter(pw.lengthUnitsPerMeter)
	}
	b2.World_SetGravity(pw.worldId, pw.gravity)
	b2.World_SetRestitutionThreshold(pw.worldId, pw.restitutionThreshold)
	b2.World_SetHitEventThreshold(pw.worldId, pw.hitEventThreshold)
	b2.World_SetContactTuning(pw.worldId, pw.contactHertz, pw.contactDampingRatio, pw.maxContactPushSpeed)
	b2.World_SetMaximumLinearSpeed(pw.worldId, pw.maximumLinearSpeed)
	b2.World_EnableSleeping(pw.worldId, pw.enableSleep)
	b2.World_EnableContinuous(pw.worldId, pw.enableContinuous)
	b2.World_EnableWarmStarting(pw.worldId, pw.enableWarmStarting)
}

PhysicsWorld_Step :: proc(pw: ^PhysicsWorld, deltaTime: f32, gameContext: ^GameContext) {
	if !b2.World_IsValid(pw.worldId) do return

	PhysicsWorld_SyncSettings(pw)

	if pw.paused || deltaTime <= 0.00001 {
		return
	}

	subSteps := c.int(max(pw.subStepCount, 1))
	b2.World_Step(pw.worldId, deltaTime, subSteps)

	// Dispatch Sensor Events (for AreaNode and sensor shapes)
	sensorEvents := b2.World_GetSensorEvents(pw.worldId)
	for i in 0..<sensorEvents.beginCount {
		ev := sensorEvents.beginEvents[i]
		if b2.Shape_IsValid(ev.sensorShapeId) && b2.Shape_IsValid(ev.visitorShapeId) {
			sensorBody := b2.Shape_GetBody(ev.sensorShapeId)
			visitorBody := b2.Shape_GetBody(ev.visitorShapeId)
			if b2.Body_IsValid(sensorBody) {
				sensorNode := cast(^Node)b2.Body_GetUserData(sensorBody)
				visitorNode := cast(^Node)b2.Body_GetUserData(visitorBody) if b2.Body_IsValid(visitorBody) else nil
				if sensorNode != nil {
					AreaNode_HandleEnter(sensorNode, visitorNode, gameContext)
				}
			}
		}
	}

	for i in 0..<sensorEvents.endCount {
		ev := sensorEvents.endEvents[i]
		if b2.Shape_IsValid(ev.sensorShapeId) {
			sensorBody := b2.Shape_GetBody(ev.sensorShapeId)
			visitorNode: ^Node = nil
			if b2.Shape_IsValid(ev.visitorShapeId) {
				visitorBody := b2.Shape_GetBody(ev.visitorShapeId)
				if b2.Body_IsValid(visitorBody) {
					visitorNode = cast(^Node)b2.Body_GetUserData(visitorBody)
				}
			}
			if b2.Body_IsValid(sensorBody) {
				sensorNode := cast(^Node)b2.Body_GetUserData(sensorBody)
				if sensorNode != nil {
					AreaNode_HandleExit(sensorNode, visitorNode, gameContext)
				}
			}
		}
	}

	// Dispatch Contact Begin/End Events to Node onEnter / onExit subjects
	contactEvents := b2.World_GetContactEvents(pw.worldId)
	for i in 0..<contactEvents.beginCount {
		ev := contactEvents.beginEvents[i]
		if b2.Shape_IsValid(ev.shapeIdA) && b2.Shape_IsValid(ev.shapeIdB) {
			bodyA := b2.Shape_GetBody(ev.shapeIdA)
			bodyB := b2.Shape_GetBody(ev.shapeIdB)
			nodeA := cast(^Node)b2.Body_GetUserData(bodyA) if b2.Body_IsValid(bodyA) else nil
			nodeB := cast(^Node)b2.Body_GetUserData(bodyB) if b2.Body_IsValid(bodyB) else nil
			if nodeA != nil {
				nodeA.onEnter->notify(nodeB, true, gameContext)
			}
			if nodeB != nil {
				nodeB.onEnter->notify(nodeA, true, gameContext)
			}
		}
	}

	for i in 0..<contactEvents.endCount {
		ev := contactEvents.endEvents[i]
		if b2.Shape_IsValid(ev.shapeIdA) && b2.Shape_IsValid(ev.shapeIdB) {
			bodyA := b2.Shape_GetBody(ev.shapeIdA)
			bodyB := b2.Shape_GetBody(ev.shapeIdB)
			nodeA := cast(^Node)b2.Body_GetUserData(bodyA) if b2.Body_IsValid(bodyA) else nil
			nodeB := cast(^Node)b2.Body_GetUserData(bodyB) if b2.Body_IsValid(bodyB) else nil
			if nodeA != nil {
				nodeA.onExit->notify(nodeB, false, gameContext)
			}
			if nodeB != nil {
				nodeB.onExit->notify(nodeA, false, gameContext)
			}
		}
	}
}

PhysicsWorld_Destroy :: proc(pw: ^PhysicsWorld) {
	if b2.World_IsValid(pw.worldId) {
		b2.DestroyWorld(pw.worldId)
		pw.worldId = b2.nullWorldId
	}
}

DegreesToRot :: proc(deg: f32) -> b2.Rot {
	return b2.MakeRot(math.to_radians(deg))
}

RotToDegrees :: proc(rot: b2.Rot) -> f32 {
	deg := math.to_degrees(b2.Rot_GetAngle(rot))
	for deg < 0 {
		deg += 360.0
	}
	for deg >= 360.0 {
		deg -= 360.0
	}
	return deg
}
