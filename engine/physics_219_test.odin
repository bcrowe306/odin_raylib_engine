package engine

import "core:testing"
import lua "lua54"
import b2 "vendor:box2d"

// #219: a Character Mover jumps up through a One Way platform and lands on
// it; it can't drop through from above.
@(test)
test_character_mover_one_way_platform :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("mover_one_way", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	ctx := &game.gameContext
	cm := CharacterMoverNode_Create(scene, "Mover")
	cm.enableKeyboardInput = false
	cm.gravityScale = 0
	cm.position = {0, 300}
	cm.gameContext = ctx
	plat := StaticBodyNode_Create(scene, "Platform")
	plat.position = {0, 200}
	plat.oneWay = true
	plat.gameContext = ctx
	StaticBodyNode_AddShape(plat, MakeBoxPhysicsShape(400, 16), ctx)
	ProcessNodeQueues(scene.manager, ctx)

	// Up from below: through it.
	for _ in 0 ..< 40 {
		cm.velocity = {0, -400}
		game->run(1.0 / 60)
	}
	testing.expectf(t, cm.position.y < 150, "jumped up through the platform (y %v)", cm.position.y)
	// Down onto it: it lands on top and stays.
	landed := false
	for _ in 0 ..< 90 {
		cm.velocity = {0, 400}
		game->run(1.0 / 60)
		if cm.isOnFloor do landed = true
	}
	testing.expect(t, landed, "landed on the platform")
	testing.expectf(t, cm.position.y < 192, "stays on top (its top is at 192): y %v", cm.position.y)
}

// #219: changing a running Joint's type replaces its joint; a disabled Joint
// (and body) stops; Lua get_mass; a Raycast ignores the body it's under.
@(test)
test_physics_joint_type_disable_mass_raycast :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("phys219", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	ctx := &game.gameContext
	a := DynamicBodyNode_Create(scene, "A")
	a.position = {0, 0}
	a.gameContext = ctx
	DynamicBodyNode_AddShape(a, MakeBoxPhysicsShape(64, 64), ctx)
	b := DynamicBodyNode_Create(scene, "B")
	b.position = {100, 0}
	b.gameContext = ctx
	DynamicBodyNode_AddShape(b, MakeBoxPhysicsShape(64, 64), ctx)
	j := JointNode_Create(scene, "Joint", a)
	JointNode_SetBodies(j, "", "../../B")
	wall := StaticBodyNode_Create(scene, "Wall")
	wall.position = {0, 300}
	wall.gameContext = ctx
	StaticBodyNode_AddShape(wall, MakeBoxPhysicsShape(400, 20), ctx)
	ray := RaycastNode_Create(scene, "Ray", a)
	ray.position, ray.direction, ray.length = {0, 0}, {0, 1}, 400
	ProcessNodeQueues(scene.manager, ctx)
	game->run(1.0 / 60)
	game->run(1.0 / 60)
	testing.expect(t, JointNode_IsActive(j), "the joint is made")
	testing.expect_value(t, b2.Body_GetJointCount(a.bodyId), 1)

	// A new type: one joint, of the new type.
	j.joint.type = .Weld
	game->run(1.0 / 60)
	testing.expect_value(t, b2.Body_GetJointCount(a.bodyId), 1)
	testing.expect(t, b2.Joint_GetType(PhysicsJoint_GetId(&j.joint)) == .weldJoint, "a weld joint")

	// Disabled: the joint goes, and a disabled body stops; back again on enable.
	j.enabled, wall.enabled = false, false
	game->run(1.0 / 60)
	testing.expect_value(t, b2.Body_GetJointCount(a.bodyId), 0)
	testing.expect(t, !b2.Body_IsEnabled(wall.bodyId), "the disabled wall's body is off")
	j.enabled, wall.enabled = true, true
	game->run(1.0 / 60)
	testing.expect_value(t, b2.Body_GetJointCount(a.bodyId), 1)
	testing.expect(t, b2.Body_IsEnabled(wall.bodyId), "the wall's body is on again")

	// The ray from inside A doesn't hit A (with Exclude Parent off, it does).
	game->run(1.0 / 60)
	testing.expectf(t, ray.isColliding && ray.hitNode != a, "the ray hits past A (hit %v)", ray.hitNode.name if ray.hitNode != nil else "nothing")
	ray.excludeParent = false
	game->run(1.0 / 60)
	testing.expect(t, ray.hitNode == a, "without Exclude Parent it hits A")

	// get_mass: density x area in px^2.
	L := game.scriptManager.L
	ok := lua.L_dostring(L, `mass = Scene.find_node("A"):get_mass()`) == 0
	testing.expect(t, ok, "Lua ran")
	lua.getglobal(L, "mass")
	testing.expectf(t, abs(lua.tonumber(L, -1) - 4096) < 1, "a 64x64 box at density 1 weighs 4096: %v", lua.tonumber(L, -1))
	lua.pop(L, 1)
}
