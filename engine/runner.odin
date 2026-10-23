package engine

import "core:fmt"
import "core:log"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:time"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

// ============================================================================
// Generic game runner: plays a data-only project (a project directory or a
// packaged .ore) - scenes, scripts, assets - with no game-specific code.
// Used by the demo binary (`--project`) and by the standalone runner/
// program that "Export Standalone Game" ships next to a game's .ore.
// ============================================================================

Run_Options :: struct {
	projectPath:    string, // project directory or .ore package
	screenshotPath: string, // save a screenshot after a few frames, then quit
	maxFrames:      int,
	hidden:         bool,
	startScene:     string, // project-relative scene file to start in
	dumpScenePath:  string, // write the running scene's JSON (tests)
	userDataDir:    string, // Save data folder instead of the platform's
	benchFrames:    int,    // --bench N: N uncapped frames, then print frame timings and quit
	noRenderCache:  bool,   // --no-render-cache: no tile chunk cache, no draw reordering (comparisons)
	editorLink:     bool,   // --editor-link: driven by the editor over stdin/stdout (editor_link.odin)
}

// Engine_ParseRunArgs reads --project/-p, --scene, --screenshot, --frames,
// --hidden, --dump-scene, --user-data, --bench and --no-render-cache. A bare argument is taken as the project.
Engine_ParseRunArgs :: proc(args: []string) -> (opts: Run_Options) {
	for i := 0; i < len(args); i += 1 {
		arg := args[i]
		next := args[i + 1] if i + 1 < len(args) else ""
		switch {
		case (arg == "--project" || arg == "-p") && next != "":
			opts.projectPath = next; i += 1
		case strings.has_prefix(arg, "--project="):
			opts.projectPath = arg[10:]
		case arg == "--screenshot" && next != "":
			opts.screenshotPath = next; i += 1
		case strings.has_prefix(arg, "--screenshot="):
			opts.screenshotPath = arg[13:]
		case arg == "--frames" && next != "":
			n, _ := strconv.parse_int(next); opts.maxFrames = n; i += 1
		case arg == "--hidden":
			opts.hidden = true
		case arg == "--scene" && next != "":
			opts.startScene = next; i += 1
		case arg == "--dump-scene" && next != "":
			opts.dumpScenePath = next; i += 1
		case arg == "--user-data" && next != "":
			opts.userDataDir = next; i += 1
		case arg == "--no-render-cache":
			opts.noRenderCache = true
		case arg == "--editor-link":
			opts.editorLink = true
		case arg == "--bench" && next != "":
			n, _ := strconv.parse_int(next); opts.benchFrames = n; i += 1
		case !strings.has_prefix(arg, "-") && opts.projectPath == "":
			opts.projectPath = arg
		}
	}
	return
}

// Engine_FindBundledProject looks for a game shipped next to the runner:
// game.ore, any other .ore, or a project/ directory (exe dir, then cwd).
Engine_FindBundledProject :: proc(exePath: string, allocator := context.allocator) -> string {
	dirs := make([dynamic]string, context.temp_allocator)
	exeDir := filepath.dir(exePath, context.temp_allocator)
	// macOS .app: Contents/MacOS/<exe> with the game in Contents/Resources.
	if res, _ := filepath.join({exeDir, "..", "Resources"}, context.temp_allocator); os.is_dir(res) do append(&dirs, res)
	append(&dirs, exeDir)
	if cwd, err := os.get_working_directory(context.temp_allocator); err == nil do append(&dirs, cwd)
	for dir in dirs {
		game, _ := filepath.join({dir, "game.ore"}, context.temp_allocator)
		if os.is_file(game) do return strings.clone(game, allocator)
		proj, _ := filepath.join({dir, "project", "project.json"}, context.temp_allocator)
		if os.is_file(proj) do return strings.clone(filepath.dir(proj, context.temp_allocator), allocator)
		h, err := os.open(dir)
		if err != nil do continue
		infos, _ := os.read_dir(h, -1, context.temp_allocator)
		os.close(h)
		for fi in infos {
			if fi.type != .Directory && strings.has_suffix(fi.name, ".ore") {
				p, _ := filepath.join({dir, fi.name}, context.temp_allocator)
				return strings.clone(p, allocator)
			}
		}
	}
	return ""
}

// runner_font_path: the UI font from the engine checkout, or fonts/ next
// to the executable / in a macOS .app's Resources (exported games).
@(private = "file")
runner_font_path :: proc() -> cstring {
	dev :: "engine/Open_Sans/static/OpenSans-Regular.ttf"
	if os.is_file(dev) do return dev
	exeDir := filepath.dir(os.args[0], context.temp_allocator)
	nextTo, _ := filepath.join({exeDir, "fonts", "OpenSans-Regular.ttf"}, context.temp_allocator)
	inApp, _ := filepath.join({exeDir, "..", "Resources", "fonts", "OpenSans-Regular.ttf"}, context.temp_allocator)
	for f in ([]string{nextTo, inApp}) do if os.is_file(f) do return strings.clone_to_cstring(f, context.temp_allocator)
	return dev
}

// Engine_RunProject opens a window and plays the project until it quits.
// Returns a process exit code.
Engine_RunProject :: proc(opts: Run_Options) -> int {
	projectPath := opts.projectPath
	screenshotPath := opts.screenshotPath
	maxFrames := opts.maxFrames
	isHidden := opts.hidden
	startScene := opts.startScene
	dumpScenePath := opts.dumpScenePath
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	if opts.userDataDir != "" do Save_SetDirectory(opts.userDataDir)
	if opts.noRenderCache {
		TileCache_SetEnabled(false)
		Render_SetBatching(false)
	}

	winW := i32(1280)
	winH := i32(720)
	winTitle := "Odin Raylib Game Engine"
	targetFPS := i32(60)
	video := ProjectConfig{vsync = true, resizable = true}

	// Attempt to read project.json to configure window size and title before window creation
	if strings.has_suffix(projectPath, ".ore") {
		pkg, ok := OrePackage_Open(projectPath, context.temp_allocator)
		if ok {
			if b, bOk := OrePackage_ReadFile(pkg, "project.json", context.temp_allocator); bOk {
				if cfg, pOk := Project_ParseConfig(b, context.temp_allocator); pOk {
					if cfg.windowWidth > 0 do winW = i32(cfg.windowWidth)
					if cfg.windowHeight > 0 do winH = i32(cfg.windowHeight)
					if cfg.windowTitle != "" do winTitle = cfg.windowTitle
					if cfg.targetFPS > 0 do targetFPS = i32(cfg.targetFPS)
					video = cfg
				}
			}
			OrePackage_Close(pkg)
		}
	} else {
		jsonPath, _ := filepath.join({projectPath, "project.json"}, context.temp_allocator)
		if b, bErr := os.read_entire_file(jsonPath, context.temp_allocator); bErr == nil {
			if cfg, pOk := Project_ParseConfig(b, context.temp_allocator); pOk {
				if cfg.windowWidth > 0 do winW = i32(cfg.windowWidth)
				if cfg.windowHeight > 0 do winH = i32(cfg.windowHeight)
				if cfg.windowTitle != "" do winTitle = cfg.windowTitle
				if cfg.targetFPS > 0 do targetFPS = i32(cfg.targetFPS)
				video = cfg
			}
		}
	}

	// Project Video settings.
	flags: rl.ConfigFlags = {}
	if video.resizable do flags += {.WINDOW_RESIZABLE}
	if video.vsync && opts.benchFrames <= 0 do flags += {.VSYNC_HINT}
	if video.msaa do flags += {.MSAA_4X_HINT}
	if video.highDPI do flags += {.WINDOW_HIGHDPI}
	if isHidden {
		flags += {.WINDOW_HIDDEN}
	}
	rl.SetConfigFlags(flags)
	rl.SetTraceLogLevel(.ERROR) // raylib warns once per oversized icon glyph (thousands of lines)
	titleC := strings.clone_to_cstring(winTitle, context.temp_allocator)
	rl.InitWindow(winW, winH, titleC)
	defer rl.CloseWindow()
	// Fullscreen (project Video, Engine.set_fullscreen): applied from the
	// first frames on (Runner_ApplyFullscreen); the frame scales to the window.
	if video.fullscreen && !isHidden do game.fullscreenRequest = true
	defer if runnerTarget.id != 0 {
		rl.UnloadRenderTexture(runnerTarget)
		runnerTarget = {}
	}
	if !opts.noRenderCache do Render_InitBatching()
	defer Render_ReleaseBatching()
	defer Post_Unload()

	rl.SetTargetFPS(0 if opts.benchFrames > 0 else targetFPS)
	rl.InitAudioDevice()
	defer rl.CloseAudioDevice()

	// Multi-size engine fonts
	InitEngineFonts(runner_font_path())
	defer UnloadEngineFonts()

	// Load Project (populates scenes, sets gravity, activates initial_scene)
	if !game->loadProject(projectPath) {
		log.errorf("Failed to load project: %s", projectPath)
		return 1
	}
	if video.icon != "" do Runner_SetWindowIcon(game, video.icon)

	// --scene <file>: start in that scene instead of the project's initial
	// scene (the editor's "Play Current Scene").
	if startScene != "" {
		scene := Game_FindSceneByFile(game, startScene)
		if scene == nil do scene = Game_RegisterSceneFile(game, startScene)
		if scene != nil {
			ChangeScene_ByPtr(&game.sceneManager, scene)
			ProcessSceneChange(&game.sceneManager, &game.gameContext)
			log.infof("Starting in scene: %s", startScene)
		} else {
			log.errorf("Scene not found: %s", startScene)
		}
	}

	game.viewportCanvasRect = {0, 0, f32(winW), f32(winH)}
	if cur := game.sceneManager.currentScene; cur != nil {
		log.infof("[Game] Playing scene '%s' (%s)", cur.name, cur.filePath)
	}

	if game.backgroundColor == rl.BLACK {
		game.backgroundColor = rl.Color{8, 10, 18, 255}
	}

	// The editor's Play: it drives the game over stdin/stdout. (Read from the
	// command line too: front ends pass on only the options they know.)
	if opts.editorLink || slice.contains(os.args, "--editor-link") do EditorLink_Enable(game)

	frameCount := 0
	targetCaptureFrame := max(25, maxFrames) if maxFrames > 0 else 30
	// --bench: the first 30 frames warm up (loading, caches), then N timed.
	benchWarmup :: 30
	benchRun, benchFrame: time.Duration

	// Game loop
	// Captures for tests step a fixed 1/60 s, so runs are comparable.
	fixedStep := screenshotPath != "" || dumpScenePath != ""
	for !rl.WindowShouldClose() && !game.shouldQuit {
		dt := 1.0 / 60 if fixedStep else rl.GetFrameTime()
		EditorLink_BeginFrame(game)
		if game.linkPaused && !game.frozen do dt = 1.0 / 60 // a step

		if on, asked := game.fullscreenRequest.?; asked && frameCount >= 2 {
			Runner_ApplyFullscreen(game, on)
			game.fullscreenRequest = nil
		}
		// The game draws at its virtual resolution into a texture, scaled to
		// the window (fullscreen, resized) - the mouse reads in game units.
		vw, vh := Runner_VirtualSize(game)
		dest := Runner_FitRect(vw, vh, f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight()))
		rl.SetMouseOffset(i32(-dest.x), i32(-dest.y))
		rl.SetMouseScale(vw / dest.width, vh / dest.height)
		game.viewportCanvasRect = {0, 0, vw, vh}
		target := Runner_FrameTarget(i32(vw), i32(vh), video.sharpScaling)

		frameStart := time.tick_now()
		Render_SetFrameTarget(target)
		rl.BeginTextureMode(target^)
		rl.ClearBackground(Game_ClearColor(game))
		game->run(dt)
		rl.EndTextureMode()
		Render_SetFrameTarget(nil)
		frame := target.texture
		if effects := Scene_PostEffects(game.sceneManager.currentScene); len(effects) > 0 {
			frame = Post_Process(effects, frame, &game.gameContext) // through each effect
		}
		runTime := time.tick_since(frameStart)

		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK) // the letterbox bars
		// Copied as is: blending would let the bars' black through where the
		// frame's alpha dropped (anti-aliased text, translucent sprites).
		rlgl.DrawRenderBatchActive()
		rlgl.DisableColorBlend()
		rl.DrawTexturePro(frame, {0, 0, f32(frame.width), -f32(frame.height)}, dest, {0, 0}, 0, rl.WHITE)
		rlgl.DrawRenderBatchActive()
		rlgl.EnableColorBlend()
		rl.EndDrawing()

		frameCount += 1
		if opts.benchFrames > 0 && frameCount > benchWarmup {
			benchRun += runTime
			benchFrame += time.tick_since(frameStart)
			if frameCount >= benchWarmup + opts.benchFrames {
				n := f64(opts.benchFrames)
				fmt.printfln("[bench] %d frames: update+draw %.3f ms | whole frame (incl. GPU sync) %.3f ms | %d drawn, %d culled | %d tile chunks (%d built)",
					opts.benchFrames, time.duration_milliseconds(benchRun) / n, time.duration_milliseconds(benchFrame) / n, renderStats.drawn, renderStats.culled, TileCache_Stats(), TileCache_Builds())
				break
			}
		}
		if (screenshotPath != "" || dumpScenePath != "") && frameCount >= targetCaptureFrame {
			// --dump-scene: what the game is actually running, for tests.
			if dumpScenePath != "" && game.sceneManager.currentScene != nil {
				dump := Scene_SerializeToJSON(game.sceneManager.currentScene, context.temp_allocator)
				_ = os.write_entire_file(dumpScenePath, transmute([]u8)dump)
			}
		}
		if screenshotPath == "" && dumpScenePath != "" && frameCount >= targetCaptureFrame do break
		if screenshotPath != "" && frameCount >= targetCaptureFrame {
			img := rl.LoadImageFromScreen()
			cPath := strings.clone_to_cstring(screenshotPath, context.temp_allocator)
			rl.ExportImage(img, cPath)
			rl.UnloadImage(img)
			log.infof("[Gameplay Screenshot] Saved gameplay capture to: %s", screenshotPath)
			break
		}
	}
	return 0
}

// Runner_ApplyFullscreen switches the window to cover the monitor (a
// borderless window at its resolution - the display mode doesn't change) or
// back. Called at the start of a frame, once the window is up: on macOS the
// switch made right after InitWindow doesn't take.
Runner_ApplyFullscreen :: proc(game: ^Game, on: bool) {
	if rl.IsWindowState({.BORDERLESS_WINDOWED_MODE}) != on do rl.ToggleBorderlessWindowed()
	game.fullscreen = on
}

// Runner_VirtualSize: the resolution the game draws at (project Video >
// virtual resolution, else the window's).
Runner_VirtualSize :: proc(game: ^Game) -> (f32, f32) {
	if game.virtualSize.x > 0 && game.virtualSize.y > 0 do return game.virtualSize.x, game.virtualSize.y
	return f32(max(rl.GetScreenWidth(), 1)), f32(max(rl.GetScreenHeight(), 1))
}

// Runner_FitRect: a w x h frame scaled to fit a screen, centred (bars on the
// sides that don't fill).
Runner_FitRect :: proc(w, h, screenW, screenH: f32) -> rl.Rectangle {
	if w <= 0 || h <= 0 || screenW <= 0 || screenH <= 0 do return {0, 0, max(w, 1), max(h, 1)}
	s := min(screenW / w, screenH / h)
	dw, dh := w * s, h * s
	return {f32(int((screenW - dw) * 0.5)), f32(int((screenH - dh) * 0.5)), dw, dh}
}

@(private = "file")
runnerTarget: rl.RenderTexture2D

// Runner_FrameTarget: the virtual-resolution render texture (remade when
// the size changes). `sharp`: nearest-neighbour scaling (pixel art).
Runner_FrameTarget :: proc(w, h: i32, sharp: bool) -> ^rl.RenderTexture2D {
	if runnerTarget.id == 0 || runnerTarget.texture.width != w || runnerTarget.texture.height != h {
		if runnerTarget.id != 0 do rl.UnloadRenderTexture(runnerTarget)
		runnerTarget = rl.LoadRenderTexture(w, h)
	}
	rl.SetTextureFilter(runnerTarget.texture, .POINT if sharp else .BILINEAR)
	return &runnerTarget
}

// Runner_SetWindowIcon uses a project PNG (project.json "icon") as the
// window's icon.
Runner_SetWindowIcon :: proc(game: ^Game, path: string) -> bool {
	data, ok := AssetManager_ReadFileBytes(&game.assetManager, path, context.temp_allocator)
	if !ok || len(data) == 0 {
		log.warnf("[Game] Icon not found: %s", path)
		return false
	}
	ext := strings.clone_to_cstring(strings.to_lower(filepath.ext(path), context.temp_allocator), context.temp_allocator)
	img := rl.LoadImageFromMemory(ext, raw_data(data), i32(len(data)))
	if img.data == nil {
		log.warnf("[Game] Icon is not a readable image: %s", path)
		return false
	}
	defer rl.UnloadImage(img)
	rl.ImageFormat(&img, .UNCOMPRESSED_R8G8B8A8) // what SetWindowIcon expects
	rl.SetWindowIcon(img)
	return true
}
