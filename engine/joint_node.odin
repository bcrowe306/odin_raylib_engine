package engine

import "core:strings"
import b2 "vendor:box2d"
import rl "vendor:raylib"

// ============================================================================
// JointNode: a Box2D joint between two body nodes (static, dynamic or
// character mover) placed in the scene. Body A / Body B are paths from the
// joint ("" for Body A = the joint's parent). The joint is created once
// both bodies exist and follows its parameters (`joint.<type>.*`, edited in
// the Inspector, saved as properties, settable from Lua with
// node:set_property). Destroying either body destroys the joint; it's made
// again if the bodies come back.
// ============================================================================

JointNode :: struct {
	using node: Node,
	joint:    PhysicsJoint `gui:"true"`,
	bodyA:    string, // path from this node ("" = parent)
	bodyB:    string,
	debugColor: rl.Color `gui:"true"`,
	synced:   PhysicsJoint, // the parameters last given to Box2D
}

JointNode_Create :: proc(scene: ^Scene, name: string = "Joint", parent: ^Node = nil) -> ^JointNode {
	j := CreateNode(scene.manager, JointNode)
	j.name = strings.clone(name, j.allocator) // owned: callers pass temp strings too
	PhysicsJoint_Init(&j.joint, .Revolute)
	// Motors strong enough for pixel-scale bodies (a 40 px box weighs 1600).
	j.joint.revolute.maxMotorTorque = 5e6
	j.joint.wheel.maxMotorTorque = 5e6
	j.joint.prismatic.maxMotorForce = 1e5
	j.joint.distance.maxMotorForce = 1e5
	j.joint.motor.maxForce = 1e5
	j.joint.motor.maxTorque = 5e6
	j.debugColor = {250, 204, 21, 255}
	j.update = JointNode_Update
	j.render = JointNode_Render
	j.onDestroy = JointNode_Destroy
	scene->addNode(j, parent)
	return j
}

JointNode_SetBodies :: proc(j: ^JointNode, a, b: string) {
	j.bodyA = strings.clone(a, j.allocator)
	j.bodyB = strings.clone(b, j.allocator)
	PhysicsJoint_Destroy(&j.joint) // made again with the new bodies
}

@(private = "file")
joint_manager :: proc(j: ^JointNode, ctx: ^GameContext) -> ^NodeManager {
	gc := ctx if ctx != nil else j.gameContext
	if gc == nil || gc.scene == nil do return nil
	return gc.scene.manager
}

// JointNode_Bodies: the nodes the joint connects (nil when missing).
JointNode_Bodies :: proc(j: ^JointNode, mgr: ^NodeManager) -> (a, b: ^Node) {
	if mgr == nil do return nil, nil
	a = GetParent(mgr, j) if j.bodyA == "" else Node_ResolvePath(mgr, j, j.bodyA)
	if j.bodyB != "" do b = Node_ResolvePath(mgr, j, j.bodyB)
	return
}

// JointNode_IsActive: the Box2D joint exists.
JointNode_IsActive :: proc(j: ^JointNode) -> bool {
	return b2.Joint_IsValid(PhysicsJoint_GetId(&j.joint))
}

JointNode_Update :: proc(node: ^Node, ctx: ^GameContext, dt: f32) {
	j := cast(^JointNode)node
	// A new type: the old type's joint goes (made again below) (#219).
	if j.joint.type != j.synced.type {
		PhysicsJoint_Destroy(&j.joint)
		j.synced.type = j.joint.type
	}
	if JointNode_IsActive(j) {
		// Parameters edited live (Inspector, scripts): apply and wake the
		// bodies (a resting body sleeps and wouldn't react).
		if j.joint != j.synced {
			PhysicsJoint_Sync(&j.joint)
			id := PhysicsJoint_GetId(&j.joint)
			b2.Body_SetAwake(b2.Joint_GetBodyA(id), true)
			b2.Body_SetAwake(b2.Joint_GetBodyB(id), true)
			j.synced = j.joint
		}
		return
	}
	gc := ctx if ctx != nil else j.gameContext
	if gc == nil || gc.game == nil do return
	a, b := JointNode_Bodies(j, joint_manager(j, ctx))
	ba, bb := Physics_BodyOf(a), Physics_BodyOf(b)
	if a == b || !b2.Body_IsValid(ba) || !b2.Body_IsValid(bb) do return
	PhysicsJoint_Create(&j.joint, gc.game.physicsWorld.worldId, ba, bb)
	j.synced = j.joint
}

JointNode_Render :: proc(node: ^Node, ctx: ^GameContext, dt: f32) {
	j := cast(^JointNode)node
	if !rl.IsWindowReady() do return
	if ctx != nil && ctx.game != nil && !ctx.game.physicsWorld.drawPhysicsDebug do return
	if JointNode_IsActive(j) {
		PhysicsJoint_DrawDebug(&j.joint, j.debugColor)
		return
	}
	// Not running (the editor): a line between the bodies' anchors.
	a, b := JointNode_Bodies(j, joint_manager(j, ctx))
	if a == nil || b == nil do return
	pa := a.globalPosition + rotate_vec(joint_anchor(&j.joint, true), a.globalRotation)
	pb := b.globalPosition + rotate_vec(joint_anchor(&j.joint, false), b.globalRotation)
	rl.DrawLineEx(pa, pb, 2, j.debugColor)
	rl.DrawCircleV(pa, 4, j.debugColor)
	rl.DrawCircleV(pb, 4, j.debugColor)
}

// joint_anchor: the local anchor on body A or B for the joint's type.
@(private = "file")
joint_anchor :: proc(pj: ^PhysicsJoint, a: bool) -> [2]f32 {
	switch pj.type {
	case .Distance:  return pj.distance.localAnchorA if a else pj.distance.localAnchorB
	case .Prismatic: return pj.prismatic.localAnchorA if a else pj.prismatic.localAnchorB
	case .Revolute:  return pj.revolute.localAnchorA if a else pj.revolute.localAnchorB
	case .Weld:      return pj.weld.localAnchorA if a else pj.weld.localAnchorB
	case .Wheel:     return pj.wheel.localAnchorA if a else pj.wheel.localAnchorB
	case .Filter, .Motor, .Mouse:
	}
	return {}
}

JointNode_Destroy :: proc(node: ^Node, ctx: ^GameContext) {
	j := cast(^JointNode)node
	PhysicsJoint_Destroy(&j.joint)
}

// JointType_FieldName: the `joint.<name>.` prefix of a type's parameters.
JointType_FieldName :: proc(t: PhysicsJointType) -> string {
	switch t {
	case .Distance:  return "distance"
	case .Filter:    return "filter"
	case .Motor:     return "motor"
	case .Mouse:     return "mouse"
	case .Prismatic: return "prismatic"
	case .Revolute:  return "revolute"
	case .Weld:      return "weld"
	case .Wheel:     return "wheel"
	}
	return ""
}
