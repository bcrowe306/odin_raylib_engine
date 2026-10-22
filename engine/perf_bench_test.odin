package engine

import "core:fmt"
import "core:testing"
import "core:time"

// Rough timings of the hot paths (printed, not asserted): node creation,
// the per-frame global transform pass and a full scene update.
@(test)
bench_scene_hot_paths :: proc(t: ^testing.T) {
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
		for n in scene.manager.nodes do if n != nil && n != scene.rootNode do RemoveNode(scene.manager, n)
		ProcessNodeQueues(scene.manager, &game.gameContext)
		start = time.tick_now()
		for i in 0 ..< count {
			n := CreateNode(scene.manager, Node)
			n.position = {f32(i), 0}
			SceneAddNode(scene, n)
		}
		ProcessNodeQueues(scene.manager, &game.gameContext)
		respawn := time.tick_since(start)

		fmt.printfln("[bench] %5d nodes: create %8.2f ms | respawn %8.2f ms | global transforms %8.3f ms | RunScene frame %8.3f ms",
			count, time.duration_milliseconds(create), time.duration_milliseconds(respawn), time.duration_milliseconds(globals), time.duration_milliseconds(frame))
		game->terminate()
	}
}
