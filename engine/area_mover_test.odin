package engine

import "core:testing"

// #173: an Area is a trigger - a CharacterMover walks through it (and it
// reports the mover), while a wall still stops the mover.
@(test)
test_character_mover_walks_through_area :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("mover_area", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	ctx := &game.gameContext

	cm := CharacterMoverNode_Create(scene, "Mover")
	cm.enableKeyboardInput = false
	cm.gravityScale = 0
	cm.position = {0, 0}
	cm.gameContext = ctx
	area := AreaNode_Create(scene, "Area")
	area.position = {100, 0}
	area.gameContext = ctx
	AreaNode_AddShape(area, MakeBoxPhysicsShape(40, 200), ctx)
	wall := StaticBodyNode_Create(scene, "Wall")
	wall.position = {300, 0}
	wall.gameContext = ctx
	StaticBodyNode_AddShape(wall, MakeBoxPhysicsShape(20, 200), ctx)
	ProcessNodeQueues(scene.manager, ctx)

	entered := false
	for _ in 0 ..< 120 {
		cm.velocity = {200, 0}
		game->run(1.0 / 60)
		if area.overlapCount > 0 do entered = true
	}
	testing.expect(t, entered, "the area reported the mover")
	testing.expectf(t, cm.position.x > 200, "walked through the area (x %v)", cm.position.x)
	testing.expectf(t, cm.position.x < 290, "stopped at the wall (its left side at 290): x %v", cm.position.x)
}

// (The cast still keeps a fast mover from tunnelling through a thin wall.)
@(test)
test_character_mover_fast_into_thin_wall :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("mover_fast", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	ctx := &game.gameContext
	cm := CharacterMoverNode_Create(scene, "Mover")
	cm.enableKeyboardInput = false
	cm.gravityScale = 0
	cm.position = {0, 0}
	cm.gameContext = ctx
	wall := StaticBodyNode_Create(scene, "Wall")
	wall.position = {150, 0}
	wall.gameContext = ctx
	StaticBodyNode_AddShape(wall, MakeBoxPhysicsShape(10, 200), ctx)
	ProcessNodeQueues(scene.manager, ctx)
	for _ in 0 ..< 30 {
		cm.velocity = {6000, 0} // 100 px a frame: more than the wall is thick
		game->run(1.0 / 60)
	}
	testing.expectf(t, cm.position.x < 145, "stopped before the wall (its left side at 145): x %v", cm.position.x)
}
