package engine

import "core:strings"
import "core:testing"
import b2 "vendor:box2d"
import lua "lua54"

@(test)
test_collision_layer_names :: proc(t: ^testing.T) {
	cfg, ok := Project_ParseConfig(transmute([]u8)string(`{"name": "P", "physics": {"gravity": [0, 900], "layers": ["Player", "Enemies", "", "Pickups"]}}`))
	defer ProjectConfig_Destroy(&cfg)
	testing.expect(t, ok && cfg.collisionLayers[1] == "Enemies" && cfg.collisionLayers[3] == "Pickups", "parsed")
	text := Project_SerializeToJSON(&cfg, context.temp_allocator)
	testing.expect(t, strings.contains(text, `"layers": ["Player", "Enemies", "", "Pickups"]`), text)

	Physics_SetLayerNames(cfg.collisionLayers[:])
	defer Physics_SetLayerNames({})
	l, found := CollisionLayer_Parse("enemies")
	testing.expect(t, found && l == .Layer2, "by name")
	l, found = CollisionLayer_Parse("3")
	testing.expect(t, found && l == .Layer3, "by number")
	l, found = CollisionLayer_Parse("Layer16")
	testing.expect(t, found && l == .Layer16, "by enum name")
	_, found = CollisionLayer_Parse("Nope")
	testing.expect(t, !found, "unknown")
	testing.expect_value(t, CollisionLayer_DisplayName(.Layer4), "Pickups (4)")
	testing.expect_value(t, CollisionLayer_DisplayName(.Layer5), "Layer 5")
}

@(private = "file")
throw_ball_up :: proc(t: ^testing.T, oneWay: bool) -> (finalY: f32) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("oneway", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running

	platform := StaticBodyNode_Create(scene, "Platform")
	platform.position = {0, 400}
	platform.oneWay = oneWay
	box: PhysicsShape
	PhysicsShape_InitDefault(&box, .Box)
	box.size = {300, 20}
	StaticBodyNode_AddShape(platform, box)

	ball := DynamicBodyNode_Create(scene, "Ball")
	ball.position = {0, 470}
	circle: PhysicsShape
	PhysicsShape_InitDefault(&circle, .Circle)
	circle.radius = 10
	circle.restitution = 0
	DynamicBodyNode_AddShape(ball, circle)
	game->run(1.0 / 60)
	b2.Body_SetLinearVelocity(ball.bodyId, {0, -420})
	for _ in 0 ..< 240 do game->run(1.0 / 60)
	return ball.globalPosition.y
}

@(test)
test_one_way_platform :: proc(t: ^testing.T) {
	// Thrown up from below: through a one-way platform, then lands on it.
	y := throw_ball_up(t, true)
	testing.expectf(t, y < 400 && y > 360, "landed on top of the one-way platform: y = %v", y)
	// A solid platform stops it from below: it falls back down.
	y = throw_ball_up(t, false)
	testing.expectf(t, y > 420, "blocked by a solid platform: y = %v", y)
}

@(test)
test_joint_node :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("joints", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	anchor := cast(^StaticBodyNode)Node_CreateByTypeName(scene, "StaticBodyNode")
	anchor.name = "Anchor"
	anchor.position = {0, 0}
	wheel := cast(^DynamicBodyNode)Node_CreateByTypeName(scene, "DynamicBodyNode")
	wheel.name = "Wheel"
	wheel.position = {0, 0}
	disc: PhysicsShape
	PhysicsShape_InitDefault(&disc, .Circle) // a body needs a shape to have rotational inertia
	DynamicBodyNode_AddShape(wheel, disc)
	j := cast(^JointNode)Node_CreateByTypeName(scene, "JointNode")
	j.name = "Hinge"
	JointNode_SetBodies(j, "../Anchor", "../Wheel")
	testing.expect_value(t, j.joint.type, PhysicsJointType.Revolute)
	game->run(1.0 / 60)
	game->run(1.0 / 60)
	testing.expect(t, JointNode_IsActive(j), "joint created once both bodies exist")

	// Parameters from Lua, applied to the live joint.
	L := game.scriptManager.L
	ok := lua.L_dostring(L, `
local h = Scene.find_node("Hinge")
h:set_property("joint.revolute.enableMotor", true)
h:set_property("joint.revolute.motorSpeed", 3)
speed = h:get_property("joint.revolute.motorSpeed")
kind = h:get_property("joint.type")
`)
	testing.expect(t, ok == 0, "lua ran")
	lua.getglobal(L, "speed")
	testing.expect_value(t, f32(lua.tonumber(L, -1)), 3)
	lua.pop(L, 1)
	lua.getglobal(L, "kind")
	testing.expect_value(t, string(lua.tostring(L, -1)), "Revolute")
	lua.pop(L, 1)
	for _ in 0 ..< 30 do game->run(1.0 / 60)
	testing.expectf(t, abs(b2.Body_GetAngularVelocity(wheel.bodyId) - 3) < 0.5, "motor turns the wheel: %v", b2.Body_GetAngularVelocity(wheel.bodyId))

	// Saved and loaded.
	text := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expect(t, strings.contains(text, `"joint": {"a": "../Anchor", "b": "../Wheel"}`), "bodies saved")
	s2 := game->createScene("joints2", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	Scene_InstantiateFromJSON(s2, transmute([]u8)text, &game.gameContext)
	ProcessNodeQueues(s2.manager, &game.gameContext)
	j2 := cast(^JointNode)Scene_FindNodeByName(s2, "Hinge")
	testing.expect(t, j2 != nil && j2.bodyB == "../Wheel" && j2.joint.revolute.motorSpeed == 3 && j2.joint.revolute.enableMotor, "joint loaded")
}

@(test)
test_raycast_parent_transform :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("raycast_parent", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running

	parent := CreateNodeScene(scene, Node, true)
	parent.name = "Parent"
	parent.position = {500, 300}

	rc := RaycastNode_Create(scene, "ChildRaycast", parent)
	rc.position = {20, 10}
	rc.direction = {0, 1}
	rc.length = 150.0

	// Static obstacle placed below the parent + raycast position: (520, 390)
	obstacle := StaticBodyNode_Create(scene, "Obstacle")
	obstacle.position = {520, 390}
	box: PhysicsShape
	PhysicsShape_InitDefault(&box, .Box)
	box.size = {100, 20} // Extends from y = 380 to 400, x = 470 to 570
	StaticBodyNode_AddShape(obstacle, box)

	// Step 2 frames to initialize transforms and physics bodies
	game->run(1.0 / 60)
	game->run(1.0 / 60)

	// Origin should be parent.globalPosition + local position: (520, 310)
	origin := RaycastNode_GetOrigin(rc)
	testing.expectf(t, abs(origin.x - 520) < 0.1 && abs(origin.y - 310) < 0.1, "origin should transform with parent position: got %v, want (520, 310)", origin)

	// Raycast should hit the top surface of the obstacle at y = 380
	testing.expect(t, rc.isColliding, "raycast should hit obstacle below parent")
	testing.expectf(t, abs(rc.hitPoint.x - 520) < 0.5 && abs(rc.hitPoint.y - 380) < 0.5, "hitPoint should be at obstacle top (520, 380), got %v", rc.hitPoint)
	testing.expect(t, rc.hitNode == cast(^Node)obstacle, "hitNode should be obstacle")

	// Now move parent to a new position where there is no obstacle
	parent.position = {700, 300}
	game->run(1.0 / 60)

	origin = RaycastNode_GetOrigin(rc)
	testing.expectf(t, abs(origin.x - 720) < 0.1 && abs(origin.y - 310) < 0.1, "origin should move with parent: got %v, want (720, 310)", origin)
	testing.expect(t, !rc.isColliding, "raycast should no longer collide when parent moves away")
	testing.expectf(t, abs(rc.hitPoint.x - 720) < 0.5 && abs(rc.hitPoint.y - 460) < 0.5, "hitPoint should be at ray tip when not colliding: got %v", rc.hitPoint)

	// Test parent rotation
	parent.position = {520, 380}
	parent.rotation = 90 // Rotated 90 degrees clockwise
	rc.position = {0, 0}
	rc.direction = {1, 0} // Local right, rotated 90 deg clockwise becomes world down (0, 1)
	rc.length = 100.0
	// Obstacle is at (520, 430) (box height 20 -> top surface at y = 420)
	obstacle.position = {520, 430}
	// Re-sync obstacle body transform
	b2.Body_SetTransform(obstacle.bodyId, obstacle.position, DegreesToRot(obstacle.rotation))

	game->run(1.0 / 60)
	trans := RaycastNode_GetTranslation(rc)
	testing.expectf(t, abs(trans.x) < 0.1 && abs(trans.y - 100) < 0.1, "translation should rotate with parent: got %v, want (0, 100)", trans)
	testing.expect(t, rc.isColliding, "rotated raycast should hit obstacle below")
	testing.expectf(t, abs(rc.hitPoint.y - 420) < 0.5, "rotated raycast hitPoint.y should be 420: got %v", rc.hitPoint.y)

	// Test parent scale flip (e.g. character facing left)
	parent.rotation = 0
	parent.scale = {-1, 1}
	parent.position = {500, 300}
	rc.position = {0, 0}
	rc.direction = {1, 0} // Local right, with scale.x = -1 points world left (-1, 0)
	rc.length = 100.0
	// Place obstacle to the left at (440, 300)
	obstacle.position = {440, 300}
	b2.Body_SetTransform(obstacle.bodyId, obstacle.position, DegreesToRot(obstacle.rotation))

	game->run(1.0 / 60)
	trans = RaycastNode_GetTranslation(rc)
	testing.expectf(t, abs(trans.x - (-100)) < 0.1 && abs(trans.y) < 0.1, "translation should flip with parent scale.x: got %v, want (-100, 0)", trans)
	testing.expect(t, rc.isColliding, "flipped raycast should hit obstacle to the left")
}
