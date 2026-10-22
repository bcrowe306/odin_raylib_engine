package engine

import "core:fmt"
import "core:testing"
import "core:time"

// Rough timings of the hot paths (printed, not asserted): node creation,
// the per-frame global transform pass and a full scene update.
@(test)
bench_scene_hot_paths :: proc(t: ^testing.T) {
	fmt.printfln("[bench] size_of: Node %d B, TextureNode %d B, DynamicBodyNode %d B", size_of(Node), size_of(TextureNode), size_of(DynamicBodyNode))
	for count in ([]int{500, 2000, 5000}) {
		game := new(Game)
		InitializeGame(game)
		scene := game->createScene("bench", true)

		start := time.tick_now()
		for i in 0 ..< count {
			n := CreateNode(scene.manager, Node)
			n.position = {f32(i), 0}
			SceneAddNode(scene, n)
		}
		ProcessNodeQueues(scene.manager, &game.gameContext)
		create := time.tick_since(start)

		start = time.tick_now()
		for _ in 0 ..< 10 do Node_SetGlobalPositions(scene.manager, scene.rootNode)
		globals := time.tick_since(start) / 10

		ProcessSceneChange(&game.sceneManager, &game.gameContext)
		start = time.tick_now()
		for _ in 0 ..< 10 do RunScene(scene, &game.gameContext, 1.0 / 60)
		frame := time.tick_since(start) / 10

		// Respawn: destroy every node and create as many again (recycled arenas).
		start = time.tick_now()
		for n in scene.manager.nodes do if n != nil && n != scene.rootNode do RemoveNode(scene.manager, n)
		ProcessNodeQueues(scene.manager, &game.gameContext)
		destroy := time.tick_since(start)
		start = time.tick_now()
		for i in 0 ..< count {
			n := CreateNode(scene.manager, Node)
			n.position = {f32(i), 0}
			SceneAddNode(scene, n)
		}
		ProcessNodeQueues(scene.manager, &game.gameContext)
		respawn := time.tick_since(start)

		// Typed nodes through the registry (what scenes and the editor do).
		start = time.tick_now()
		for _ in 0 ..< count do Node_CreateByTypeName(scene, "TextureNode")
		ProcessNodeQueues(scene.manager, &game.gameContext)
		typed := time.tick_since(start)

		fmt.printfln("[bench] %5d nodes: create %8.2f ms | destroy all %8.2f ms | respawn %8.2f ms | create TextureNodes %8.2f ms | global transforms %8.3f ms | RunScene frame %8.3f ms",
			count, time.duration_milliseconds(create), time.duration_milliseconds(destroy), time.duration_milliseconds(respawn), time.duration_milliseconds(typed), time.duration_milliseconds(globals), time.duration_milliseconds(frame))
		game->terminate()
	}
}

// Particle simulation (emit + update, no drawing): 5000 live particles.
@(test)
bench_particles :: proc(t: ^testing.T) {
	emitter: ParticleEmitter
	ParticleEmitter_Init(&emitter)
	defer ParticleEmitter_Destroy(&emitter)
	emitter.amount = 5000
	emitter.lifetime = 1
	emitter.continuous = true
	emitter.velocity = 100
	emitter.velocitySpread = 50
	emitter.velocityVariance = 1
	emitter.colorVariance = 0.2
	emitter.spread = {100, 100}
	ParticleEmitter_Start(&emitter)
	for _ in 0 ..< 60 do ParticleEmitter_Update(&emitter, 1.0 / 60) // warm up: steady state
	frames :: 300
	start := time.tick_now()
	for _ in 0 ..< frames do ParticleEmitter_Update(&emitter, 1.0 / 60)
	per := time.tick_since(start) / frames
	alive := 0
	for i in 0 ..< len(emitter.particles) do if emitter.particles[i].alive do alive += 1
	fmt.printfln("[bench] particles: %d alive, %d emitted/frame: update %.3f ms/frame", alive, 5000 / 60, time.duration_milliseconds(per))
}
