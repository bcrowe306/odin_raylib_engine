package engine

import "base:runtime"
import "core:testing"
import "core:time"
import lua "lua54"
import rl "vendor:raylib"

// Loading screens: change_scene with loading = "<scene>" goes through the
// screen (shown for min_time at least), reports progress, then to the
// target; and the background decoder turns PNG bytes into an image on a
// worker thread.
@(test)
test_loading_screen_and_async_decode :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	menu := game->createScene("menu", true)
	_ = game->createScene("loading", false)
	level := game->createScene("level", false)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	L := game.scriptManager.L

	ok := lua.L_dostring(L, `Scene.change_scene("level", {transition = "fade", duration = 0.1, loading = "loading", min_time = 0.3})`)
	testing.expect_value(t, ok, i32(0))
	testing.expect(t, game.loading.active && game.loading.target == level, "loading the level")
	steps := 0
	sawLoading := false
	progress := f64(-1)
	for game.sceneManager.currentScene != level && steps < 200 {
		game->run(1.0 / 60)
		steps += 1
		if game.sceneManager.currentScene.name == "loading" && !game.transition.active {
			sawLoading = true
			lua.L_dostring(L, `p = Scene.loading_progress(); tgt = Scene.loading_target()`)
			lua.getglobal(L, "p")
			progress = f64(lua.tonumber(L, -1))
			lua.pop(L, 1)
		}
	}
	testing.expect(t, sawLoading, "the loading screen was shown")
	testing.expect(t, game.sceneManager.currentScene == level, "then the level")
	testing.expect(t, progress == 1, "its progress (headless: loaded at once)")
	// 0.1 s cover + 0.1 uncover + 0.3 shown + 0.1 cover: at least ~36 frames.
	testing.expectf(t, steps >= 34, "the screen stayed min_time (%d frames)", steps)
	testing.expect(t, !game.loading.active, "done")
	_ = menu

	// The decoder: PNG bytes -> an image on a worker.
	img := rl.GenImageColor(37, 21, rl.RED)
	size: i32
	png := rl.ExportImageToMemory(img, ".png", &size)
	rl.UnloadImage(img)
	bytes := make([]u8, int(size), context.allocator)
	copy(bytes, (cast([^]u8)png)[:size])
	rl.MemFree(png)
	heap := make([]u8, len(bytes), runtime.heap_allocator())
	copy(heap, bytes)
	heap2 := make([]u8, len(bytes), runtime.heap_allocator())
	copy(heap2, bytes)
	delete(bytes)
	job := Decode_Submit("virtual/test.png", heap)
	deadline := time.tick_now()
	for !job.uploaded && time.duration_seconds(time.tick_since(deadline)) < 5 {
		Decode_Pump(&game.resourceManager)
		time.sleep(time.Millisecond)
	}
	testing.expect(t, job.uploaded, "decoded")
	testing.expect_value(t, job.size, [2]i32{37, 21})
	testing.expect(t, Decode_Collect(job) == nil, "headless: no texture (nothing to upload to)")
	// An abandoned job is freed when its worker is done.
	Decode_Abandon(&game.resourceManager, Decode_Submit("virtual/b.png", heap2))
	Decode_Shutdown() // waits, frees everything
}
