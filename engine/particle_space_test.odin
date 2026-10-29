package engine

import "core:math"
import "core:strings"
import "core:testing"

// #124: emission follows the node's global rotation and scale; particles in
// Local space move, turn and scale with the node (the default, also for
// scenes saved before the option), World ones stay where they were emitted.

@(private = "file")
space_setup :: proc(name: string) -> (^Game, ^Scene, ^Node, ^ParticleEmitterNode) {
	game := new(Game)
	InitializeGame(game)
	scene := game->createScene(name, true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	parent := Node_CreateByTypeName(scene, "Node")
	parent.position = {100, 100}
	pen := ParticleEmitterNode_Create(scene, "Fx")
	AddChild(scene.manager, parent, pen)
	em := &pen.emitter
	em.amount, em.burst, em.continuous, em.lifetime = 4, 1, false, 5
	em.angle, em.velocity, em.gravityVelocity = 0, 100, 0
	em.size = {4, 4}
	ProcessNodeQueues(scene.manager, &game.gameContext)
	return game, scene, parent, pen
}

@(test)
test_particle_emission_follows_transform :: proc(t: ^testing.T) {
	game, scene, parent, pen := space_setup("transform")
	defer game->terminate()
	// A parent turned 90 degrees and scaled 2: "right" (angle 0) is down,
	// twice as fast, twice as big - in World space, where it's baked in.
	parent.rotation, parent.scale = 90, {2, 2}
	pen.emitter.localSpace = false
	pen.emitter.spread = {10, 0} // (an offset along the emitter's x: down in the world)
	Node_SetGlobalPositions(scene.manager, scene.rootNode)
	ParticleEmitterNode_Update(pen, &game.gameContext, 1.0 / 1000)
	for p in pen.emitter.particles do if p.alive {
		testing.expectf(t, abs(p.velocity.x) < 0.5 && abs(p.velocity.y - 200) < 1, "down at 200: %v", p.velocity)
		testing.expectf(t, abs(p.size.x - 8) < 0.01, "scaled size: %v", p.size)
		testing.expectf(t, abs(p.position.x - 100) < 0.5 && p.position.y >= 100 - 21 && p.position.y <= 100 + 21, "the spread turned (x stays 100): %v", p.position)
	}
}

@(test)
test_particle_local_and_world_space :: proc(t: ^testing.T) {
	for local in ([]bool{true, false}) {
		game, scene, parent, pen := space_setup("space")
		pen.emitter.localSpace = local
		Node_SetGlobalPositions(scene.manager, scene.rootNode)
		ParticleEmitterNode_Update(pen, &game.gameContext, 1.0 / 1000)
		before := particle_to_world(&pen.emitter, pen.emitter.particles[0].position) if local else pen.emitter.particles[0].position
		// The node moves 300 to the right.
		parent.position.x += 300
		Node_SetGlobalPositions(scene.manager, scene.rootNode)
		ParticleEmitterNode_Update(pen, &game.gameContext, 1.0 / 1000)
		after := particle_to_world(&pen.emitter, pen.emitter.particles[0].position) if local else pen.emitter.particles[0].position
		moved := after.x - before.x
		if local do testing.expectf(t, abs(moved - 300) < 1, "local: follows the node (moved %v)", moved)
		else do testing.expectf(t, abs(moved) < 1, "world: stays (moved %v)", moved)
		game->terminate()
	}
}

// Local particles under a rotated node still fall down the screen.
@(test)
test_particle_local_gravity_stays_down :: proc(t: ^testing.T) {
	game, scene, parent, pen := space_setup("gravity")
	defer game->terminate()
	parent.rotation = 90
	pen.emitter.velocity, pen.emitter.gravityVelocity = 0, 300
	Node_SetGlobalPositions(scene.manager, scene.rootNode)
	ParticleEmitterNode_Update(pen, &game.gameContext, 1.0 / 1000)
	start := particle_to_world(&pen.emitter, pen.emitter.particles[0].position)
	for _ in 0 ..< 30 do ParticleEmitterNode_Update(pen, &game.gameContext, 1.0 / 60)
	end := particle_to_world(&pen.emitter, pen.emitter.particles[0].position)
	d := end - start
	testing.expectf(t, d.y > 20 && abs(d.x) < 0.5, "fell down the screen: %v", d)
}

// Saved scenes: no setting = Local (#124's decision); World round-trips.
@(test)
test_particle_local_space_saving :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("saving", false)
	OLD :: `{"name": "s", "root": {"type": "Node", "name": "root", "children": [{"type": "ParticleEmitterNode", "name": "Old", "properties": {"emitter.amount": 5}}]}}`
	testing.expect(t, Scene_InstantiateFromJSON(scene, transmute([]u8)string(OLD), &game.gameContext), "loads")
	ProcessNodeQueues(scene.manager, &game.gameContext)
	old := cast(^ParticleEmitterNode)Scene_FindNodeByName(scene, "Old")
	testing.expect(t, old != nil && old.emitter.localSpace, "an old scene's emitter is Local")
	old.emitter.localSpace = false
	saved := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expect(t, strings.contains(saved, `"emitter.localSpace": false`), "saved")
	again := game->createScene("saving2", false)
	_ = Scene_InstantiateFromJSON(again, transmute([]u8)saved, &game.gameContext)
	ProcessNodeQueues(again.manager, &game.gameContext)
	re := cast(^ParticleEmitterNode)Scene_FindNodeByName(again, "Old")
	testing.expect(t, re != nil && !re.emitter.localSpace, "World round-trips")
	_ = math.PI
}
