package engine

import "core:fmt"
import cos "core:os"
import os "osx"
import "core:testing"
import "core:time"

// #80: what component instances cost - instantiate, save (an editor undo
// snapshot is the same serialization), load - with 10 / 100 / 1000
// instances of a 12-node component that nests another. Printed, not
// asserted (scripts/bench.sh runs it with -o:speed).

@(private = "file")
BENCH_DIR :: "test_component_bench"
@(private = "file")
BENCH_INNER :: `{"type": "Node", "name": "Turret", "uid": "turret00", "children": [{"type": "Node", "name": "Barrel", "uid": "barrel00"}, {"type": "Node", "name": "Muzzle", "uid": "muzzle00"}]}`
@(private = "file")
BENCH_SHIP :: `{"type": "Node", "name": "Ship", "uid": "ship0000", "children": [
	{"type": "Node", "name": "Hull", "uid": "hull0000", "children": [{"type": "Node", "name": "Plate1", "uid": "plate100"}, {"type": "Node", "name": "Plate2", "uid": "plate200"}]},
	{"type": "Node", "name": "Engine", "uid": "engine00", "children": [{"type": "Node", "name": "Flame", "uid": "flame000"}]},
	{"type": "Node", "name": "Shield", "uid": "shield00"},
	{"type": "Node", "name": "Gun", "uid": "gun00000", "component": "components/turret.component.json", "overrides": {"barrel00": {"rotation": 15}}}]}`

@(test)
bench_components :: proc(t: ^testing.T) {
	_ = os.make_directory_all(BENCH_DIR + "/components")
	defer os.remove_all(BENCH_DIR)
	_ = os.write_entire_file(BENCH_DIR + "/components/turret.component.json", transmute([]u8)string(BENCH_INNER))
	_ = os.write_entire_file(BENCH_DIR + "/components/ship.component.json", transmute([]u8)string(BENCH_SHIP))
	// (Files modified just now aren't cached yet: written a minute ago.)
	old := time.time_add(time.now(), -time.Minute)
	for f in ([]string{"turret", "ship"}) {
		path := fmt.tprintf("%s/components/%s.component.json", BENCH_DIR, f)
		_ = cos.change_times(path, old, old)
	}
	for count in ([]int{10, 100, 1000, -1000}) {
		// (-1000: as a game runs them, without component bases.)
		gameMode := count < 0
		count := abs(count)
		Component_KeepBases = !gameMode
		defer Component_KeepBases = true
		game := new(Game)
		InitializeGame(game)
		AssetManager_SetProjectDir(&game.assetManager, BENCH_DIR)
		ctx := &game.gameContext
		scene := game->createScene("bench_comp", false)

		start := time.tick_now()
		for i in 0 ..< count {
			n := Scene_InstantiateComponent(scene, "components/ship.component.json", nil, ctx)
			if n != nil do n.position = {f32(i), 0}
		}
		ProcessNodeQueues(scene.manager, ctx)
		instantiate := time.tick_since(start)

		start = time.tick_now()
		text := Scene_SerializeToJSON(scene, context.temp_allocator)
		save := time.tick_since(start)

		loaded := game->createScene("bench_comp_load", false)
		start = time.tick_now()
		Scene_InstantiateFromJSON(loaded, transmute([]u8)text, ctx)
		ProcessNodeQueues(loaded.manager, ctx)
		load := time.tick_since(start)

		baseBytes := 0
		for n in loaded.manager.nodes do if n != nil do baseBytes += len(n.componentBase)
		fmt.printfln("[bench] %4d component instances%s (%d nodes): instantiate %8.2f ms | save / undo snapshot %8.2f ms | load %8.2f ms | componentBase %d KB",
			count, " (game)" if gameMode else "", len(loaded.manager.nodes), time.duration_milliseconds(instantiate), time.duration_milliseconds(save), time.duration_milliseconds(load), baseBytes / 1024)
		game->terminate()
		Component_ClearCaches()
		free_all(context.temp_allocator)
	}
}
