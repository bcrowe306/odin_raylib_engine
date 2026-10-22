package engine

import "core:testing"

// Every property the Inspector shows has a help line (property_docs.odin).
@(test)
test_property_docs :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("docs", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)

	missing := 0
	check :: proc(t: ^testing.T, props: []Node_Property, missing: ^int) {
		for p in props {
			if Property_Doc(p) == "" {
				testing.expectf(t, false, "no doc for %s.%s", p.owner, p.name)
				missing^ += 1
			}
		}
	}
	for info in NODE_TYPES {
		node := Node_CreateByTypeName(scene, info.name)
		testing.expectf(t, node != nil, "created %s", info.name)
		if node != nil do check(t, Node_CollectProperties(node), &missing)
	}
	shape: PhysicsShape
	check(t, Struct_CollectProperties(PhysicsShape, &shape), &missing)
	world: PhysicsWorld
	check(t, Struct_CollectProperties(PhysicsWorld, &world), &missing)
	testing.expect_value(t, missing, 0)

	// Owner-specific beats shared; nested paths use the last segment.
	cam := Node_CreateByTypeName(scene, "CameraNode")
	p, _ := Node_FindProperty(cam, "dampingRatio")
	testing.expect_value(t, p.owner, "CameraNode")
	testing.expect(t, Property_Doc(p) != Property_Doc({name = "dampingRatio"}), "camera's own damping doc")
	j := Node_CreateByTypeName(scene, "JointNode")
	jp, ok := Node_FindProperty(j, "joint.distance.length")
	testing.expect(t, ok && jp.owner == "DistanceJoint" && Property_Doc(jp) == "Rest distance between the anchors (px).", "nested joint doc")
}
