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

		// Scene JSON (the editor's undo snapshots and saves) and loading it.
		start = time.tick_now()
		text := Scene_SerializeToJSON(scene, context.temp_allocator)
		serialize := time.tick_since(start)
		copyScene := game->createScene("bench_copy", false)
		start = time.tick_now()
		Scene_InstantiateFromJSON(copyScene, transmute([]u8)text, &game.gameContext)
		ProcessNodeQueues(copyScene.manager, &game.gameContext)
		instantiate := time.tick_since(start)
		fmt.printfln("[bench] %5d nodes: scene JSON %d KB, serialize %8.2f ms, load %8.2f ms", count * 2, len(text) / 1024, time.duration_milliseconds(serialize), time.duration_milliseconds(instantiate))

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

// Lua scripts: 1000 nodes whose script moves them every frame (update(dt)
// calls, property access, a node method), and emitting an event each
// frame to a Lua connection.
@(test)
bench_scripts :: proc(t: ^testing.T) {
	ScriptVFS_RegisterEmbedded("bench_mover.lua", `
local M = {}
M.properties = { speed = { type = "float", default = 40 } }
function M:ready() self.t = 0 end
function M:update(dt)
	self.t = self.t + dt
	local x, y = self.node:get_position()
	self.node:set_position(x + self.speed * dt, y + math.sin(self.t) * dt)
end
return M
`)
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("bench_scripts", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	count :: 1000
	for i in 0 ..< count {
		n := Node_CreateByTypeName(scene, "Node")
		n.gameContext = &game.gameContext
		Script_AttachToNode(n, "bench_mover.lua", nil, &game.scriptManager)
	}
	for _ in 0 ..< 10 do game->run(1.0 / 60) // ready() and warm-up
	frames :: 120
	start := time.tick_now()
	for _ in 0 ..< frames do game->run(1.0 / 60)
	per := time.tick_since(start) / frames
	fmt.printfln("[bench] scripts: %d nodes with update(dt): %.3f ms/frame (%.2f us per script)", count, time.duration_milliseconds(per), time.duration_microseconds(per) / count)
}

// A* on a 256x256 grid with ~20% random walls, corner to corner.
@(test)
bench_navigation :: proc(t: ^testing.T) {
	g := Nav_Grid{w = 256, h = 256, cell = {16, 16}}
	g.blocked = make([]bool, g.w * g.h, context.temp_allocator)
	seed: u32 = 12345
	for &b in g.blocked {
		seed = seed * 1664525 + 1013904223
		b = (seed >> 24) % 5 == 0
	}
	// Open 4x4 corners so the ends aren't walled in.
	for y in 0 ..< 4 do for x in 0 ..< 4 {
		g.blocked[y * g.w + x] = false
		g.blocked[(g.h - 1 - y) * g.w + (g.w - 1 - x)] = false
	}
	start := time.tick_now()
	runs :: 20
	found := 0
	for _ in 0 ..< runs do if Nav_FindPath(&g, {8, 8}, {256 * 16 - 8, 256 * 16 - 8}) != nil do found += 1
	per := time.tick_since(start) / runs
	fmt.printfln("[bench] navigation: 256x256 grid, 20%% walls, corner to corner: %.3f ms per path (%d/%d found)", time.duration_milliseconds(per), found, runs)
}
