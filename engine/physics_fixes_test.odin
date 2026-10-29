package engine

import "core:testing"
import lua "lua54"

@(test)
test_character_mover_shapes_and_multi_shape_collision :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("mover_shapes", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running

	// 1. Circle shape on CharacterMoverNode should have 0 segment length (center1 == center2),
	// not fall back to size.y (40px).
	cmCircle := CharacterMoverNode_Create(scene, "CircleMover")
	cmCircle.position = {100, 100}
	cmCircle.globalPosition = {100, 100}
	cmCircle.globalScale = {1, 1}
	cmCircle.shapes[0] = MakeCirclePhysicsShape(12)
	capCircle := CharacterMoverNode_GetWorldCapsule(cmCircle)
	testing.expectf(t, abs(capCircle.center2.y - capCircle.center1.y) < 0.01 && abs(capCircle.radius - 12) < 0.01,
		"Circle shape on CharacterMoverNode should produce zero-length capsule with radius 12, got center1=%v center2=%v r=%v",
		capCircle.center1, capCircle.center2, capCircle.radius)

	// 2. Box shape on CharacterMoverNode should reflect the box's size, not the default 14x28 capsule.
	cmBox := CharacterMoverNode_Create(scene, "BoxMover")
	cmBox.position = {100, 200}
	cmBox.globalPosition = {100, 200}
	cmBox.globalScale = {1, 1}
	cmBox.shapes[0] = MakeBoxPhysicsShape(20, 60)
	capBox := CharacterMoverNode_GetWorldCapsule(cmBox)
	totalHeight := (capBox.center2.y - capBox.center1.y) + capBox.radius * 2
	testing.expectf(t, abs(capBox.radius - 10) < 0.01 && abs(totalHeight - 60) < 0.01,
		"Box shape (20x60) on CharacterMoverNode should have radius 10 and total height 60, got r=%v totalHeight=%v",
		capBox.radius, totalHeight)

	// 3. Multi-shape CharacterMoverNode: second shape offset to the right (+50, 0) should collide with a wall.
	wall := StaticBodyNode_Create(scene, "Wall")
	wall.position = {200, 400}
	wall.gameContext = &game.gameContext
	StaticBodyNode_AddShape(wall, MakeBoxPhysicsShape(20, 200), &game.gameContext)

	cmMulti := CharacterMoverNode_Create(scene, "MultiMover")
	cmMulti.position = {100, 400}
	cmMulti.enableKeyboardInput = false
	cmMulti.controlMode = .Script
	cmMulti.gravityScale = 0
	cmMulti.gameContext = &game.gameContext
	cmMulti.shapes[0] = MakeCirclePhysicsShape(10, {0, 0})
	CharacterMoverNode_AddShape(cmMulti, MakeCirclePhysicsShape(10, {50, 0}), &game.gameContext)

	ProcessNodeQueues(scene.manager, &game.gameContext)
	game->run(1.0 / 60.0)

	// Move right toward the wall at x=200 (left face at x=190).
	// With second shape at offset +50 and radius 10, the mover's right extent is position.x + 60,
	// so position.x should stop at <= 132 (whereas ignoring shape[1] would let it reach ~180).
	cmMulti.velocity = {300, 0}
	for _ in 0 ..< 30 {
		CharacterMoverNode_MoveAndSlide(cmMulti, &game.gameContext, 1.0 / 60.0)
	}
	testing.expectf(t, cmMulti.position.x < 140,
		"Multi-shape CharacterMoverNode should collide using its second shape at +50 offset (got x=%v, expected < 140)",
		cmMulti.position.x)
}

@(test)
test_multi_shape_area_and_body_single_events :: proc(t: ^testing.T) {
	ScriptVFS_RegisterEmbedded("multi_shape_area.lua", `
local A = {}
function A:on_body_entered(other)
	area_enters = (area_enters or 0) + 1
end
function A:on_body_exited(other)
	area_exits = (area_exits or 0) + 1
end
return A
`)
	ScriptVFS_RegisterEmbedded("multi_shape_body.lua", `
local B = {}
function B:on_collision_started(other)
	body_collisions_started = (body_collisions_started or 0) + 1
end
function B:on_collision_ended(other)
	body_collisions_ended = (body_collisions_ended or 0) + 1
end
return B
`)
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("multi_events", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running

	// Area with 2 overlapping shapes
	area := AreaNode_Create(scene, "DualArea")
	area.position = {300, 300}
	area.gameContext = &game.gameContext
	AreaNode_AddShape(area, MakeBoxPhysicsShape(80, 80, {-20, 0}, 0), &game.gameContext)
	AreaNode_AddShape(area, MakeBoxPhysicsShape(80, 80, {20, 0}, 0), &game.gameContext)
	Script_AttachToNode(area, "multi_shape_area.lua", nil, &game.scriptManager)

	// Visitor body with 2 shapes inside DualArea
	visitor := DynamicBodyNode_Create(scene, "DualVisitor")
	visitor.position = {300, 300}
	visitor.gravityScale = 0
	visitor.gameContext = &game.gameContext
	DynamicBodyNode_AddShape(visitor, MakeCirclePhysicsShape(10, {-5, 0}), &game.gameContext)
	DynamicBodyNode_AddShape(visitor, MakeCirclePhysicsShape(10, {5, 0}), &game.gameContext)

	// Static floor with 2 shapes and a multi-shape dynamic body landing on both simultaneously
	floor := StaticBodyNode_Create(scene, "DualFloor")
	floor.position = {700, 500}
	floor.gameContext = &game.gameContext
	StaticBodyNode_AddShape(floor, MakeBoxPhysicsShape(100, 20, {-40, 0}, 0), &game.gameContext)
	StaticBodyNode_AddShape(floor, MakeBoxPhysicsShape(100, 20, {40, 0}, 0), &game.gameContext)

	crate := DynamicBodyNode_Create(scene, "DualCrate")
	crate.position = {700, 475}
	crate.fixedRotation = true
	crate.gameContext = &game.gameContext
	DynamicBodyNode_AddShape(crate, MakeBoxPhysicsShape(20, 20, {-30, 0}, 0), &game.gameContext)
	DynamicBodyNode_AddShape(crate, MakeBoxPhysicsShape(20, 20, {30, 0}, 0), &game.gameContext)
	Script_AttachToNode(crate, "multi_shape_body.lua", nil, &game.scriptManager)

	ProcessNodeQueues(scene.manager, &game.gameContext)
	for _ in 0 ..< 20 do game->run(1.0 / 60.0)

	L := game.scriptManager.L
	get_int :: proc(L: ^lua.State, name: cstring) -> int {
		lua.getglobal(L, name)
		defer lua.pop(L, 1)
		return int(lua.tointeger(L, -1))
	}
	testing.expect_value(t, get_int(L, "area_enters"), 1)
	testing.expect_value(t, get_int(L, "area_exits"), 0)
	testing.expect_value(t, get_int(L, "body_collisions_started"), 1)
}

@(test)
test_kinematic_body_and_monitoring :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("kinematic_and_monitoring", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running

	// 1. Velocity-driven KinematicBodyNode carries a CharacterMoverNode standing on it
	platform := KinematicBodyNode_Create(scene, "MovingPlatform")
	platform.position = {100, 400}
	platform.linearVelocity = {120, 0} // 120 px/s right
	platform.gameContext = &game.gameContext
	KinematicBodyNode_AddShape(platform, MakeBoxPhysicsShape(120, 20), &game.gameContext)

	mover := CharacterMoverNode_Create(scene, "Passenger")
	mover.position = {100, 360} // standing above platform top at y=390
	mover.enableKeyboardInput = false
	mover.gameContext = &game.gameContext

	// 2. Transform-driven KinematicBodyNode (e.g. animated or scripted position)
	elevator := KinematicBodyNode_Create(scene, "Elevator")
	elevator.position = {400, 400}
	elevator.gameContext = &game.gameContext
	KinematicBodyNode_AddShape(elevator, MakeBoxPhysicsShape(80, 20), &game.gameContext)

	// 3. AreaNode and RaycastNode monitoring toggle
	area := AreaNode_Create(scene, "ToggleArea")
	area.position = {700, 300}
	area.monitoring = false
	area.gameContext = &game.gameContext
	AreaNode_AddShape(area, MakeBoxPhysicsShape(60, 60), &game.gameContext)

	probe := DynamicBodyNode_Create(scene, "Probe")
	probe.position = {700, 300}
	probe.gravityScale = 0
	probe.gameContext = &game.gameContext
	DynamicBodyNode_AddShape(probe, MakeCirclePhysicsShape(10), &game.gameContext)

	ray := RaycastNode_Create(scene, "ToggleRay")
	ray.position = {650, 300}
	ray.direction = {1, 0}
	ray.length = 150
	ray.monitoring = false
	ray.gameContext = &game.gameContext

	ProcessNodeQueues(scene.manager, &game.gameContext)

	// Step 30 frames (0.5s): platform moves right by ~60px, elevator moves up via external position edits
	for _ in 0 ..< 30 {
		elevator.position.y -= 2.0
		game->run(1.0 / 60.0)
	}

	testing.expectf(t, platform.position.x > 150,
		"Velocity-driven KinematicBodyNode should have moved right past x=150, got %v", platform.position.x)
	testing.expectf(t, mover.isOnFloor && mover.position.x > 130,
		"CharacterMoverNode standing on KinematicBodyNode should be on floor and carried right, got isOnFloor=%v x=%v",
		mover.isOnFloor, mover.position.x)
	testing.expectf(t, abs(elevator.position.y - 340) < 2.0,
		"Transform-driven KinematicBodyNode should remain at target y=340, got %v", elevator.position.y)

	// While monitoring == false, neither area nor raycast should detect Probe
	testing.expect_value(t, len(area.overlappingNodes), 0)
	testing.expect_value(t, ray.isColliding, false)

	// Enable monitoring on both and step a few frames
	AreaNode_SetMonitoring(area, true)
	RaycastNode_SetMonitoring(ray, true)
	for _ in 0 ..< 5 do game->run(1.0 / 60.0)

	testing.expect_value(t, AreaNode_IsMonitoring(area), true)
	testing.expect_value(t, RaycastNode_IsMonitoring(ray), true)
	testing.expectf(t, len(area.overlappingNodes) == 1,
		"AreaNode should detect Probe after monitoring enabled, got %d overlapping bodies", len(area.overlappingNodes))
	testing.expect_value(t, ray.isColliding, true)
	testing.expect_value(t, ray.hitNode, cast(^Node)probe)

	// Disable monitoring again -> overlappingNodes and hit state should clear
	AreaNode_SetMonitoring(area, false)
	RaycastNode_SetMonitoring(ray, false)
	testing.expect_value(t, len(area.overlappingNodes), 0)
	testing.expect_value(t, ray.isColliding, false)
	testing.expect_value(t, ray.hitNode, nil)

	// An area that doesn't monitor (a quiet hitbox) is still a shape:
	// a raycast that collides with sensors finds it.
	seer := RaycastNode_Create(scene, "SensorSeer")
	seer.position = {700, 230}
	seer.direction = {0, 1}
	seer.length = 60
	seer.collideWithSensors = true
	seer.gameContext = &game.gameContext
	ProcessNodeQueues(scene.manager, &game.gameContext)
	for _ in 0 ..< 3 do game->run(1.0 / 60.0)
	testing.expect_value(t, len(area.overlappingNodes), 0)
	testing.expect_value(t, seer.hitNode, cast(^Node)area)
}
