package engine

import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:strings"
import "core:time"
import rl "vendor:raylib"

// ============================================================================
// Scene flow: pausing, transitions between scenes and loading a scene's
// assets in the background (on the main thread, a little each frame).
// ============================================================================

// --- pausing ------------------------------------------------------------------------

Pause_Mode :: enum u8 {
	Inherit,  // as the parent (the root: Pausable)
	Pausable, // stops when the parent (or the game) is paused
	Always,   // keeps running (pause menus, music players)
}

Pause_ModeName :: proc(m: Pause_Mode) -> string {
	switch m {
	case .Inherit:  return "inherit"
	case .Pausable: return "pausable"
	case .Always:   return "always"
	}
	return "inherit"
}

Pause_ModeParse :: proc(s: string) -> Pause_Mode {
	switch s {
	case "pausable": return .Pausable
	case "always":   return .Always
	}
	return .Inherit
}

// Game_SetPaused pauses the game: Pausable nodes stop updating and physics
// stops; Always nodes keep running.
Game_SetPaused :: proc(game: ^Game, paused: bool) {
	game.treePaused = paused
}

// --- loading screens ----------------------------------------------------------------

Scene_Loading :: struct {
	active:   bool,
	target:   ^Scene,  // the scene loading in the background
	screen:   ^Scene,  // the loading screen shown meanwhile
	spec:     Transition_Spec, // into the screen, then into the target (its shader owned)
	minTime:  f32,     // seconds the screen stays at least (no flash on fast loads)
	shown:    f32,     // seconds it has been fully shown
}

// Game_ChangeSceneVia switches to `target` through a loading screen: a
// transition into `screen` (a light scene with, say, a progress bar), the
// target's assets loading in the background meanwhile (textures decoded on
// worker threads), then - once loaded and shown for at least minTime - a
// transition into the target. Scripts on the screen read the progress with
// Scene.loading_progress().
Game_ChangeSceneVia :: proc(game: ^Game, target, screen: ^Scene, kind: Transition_Kind = .Fade, duration: f32 = 0.4, color: rl.Color = rl.BLACK, minTime: f32 = 0.5) {
	spec := TRANSITION_DEFAULT
	spec.kind, spec.duration, spec.color = kind, duration, color
	Game_ChangeSceneViaSpec(game, target, screen, spec, minTime)
}

// Game_ChangeSceneViaSpec: Game_ChangeSceneVia with every transition option.
Game_ChangeSceneViaSpec :: proc(game: ^Game, target, screen: ^Scene, spec: Transition_Spec, minTime: f32 = 0.5) {
	if target == nil do return
	if screen == nil || screen == target {
		Game_ChangeSceneSpec(game, target, spec)
		return
	}
	Scene_PreloadBegin(game, target)
	Transition_SpecFree(&game.loading.spec)
	game.loading = {active = true, target = target, screen = screen, spec = Transition_SpecClone(spec), minTime = minTime}
	Game_ChangeSceneSpec(game, screen, spec)
}

// Scene_LoadingProgress: how far the scene behind the loading screen has
// loaded (0..1; 1 when nothing is loading).
Scene_LoadingProgress :: proc(game: ^Game) -> f32 {
	if !game.loading.active do return 1
	return Scene_PreloadProgress(game, game.loading.target)
}

@(private = "file")
loading_update :: proc(game: ^Game, dt: f32) {
	ld := &game.loading
	if !ld.active do return
	if game.sceneManager.currentScene != ld.screen || game.transition.active do return
	ld.shown += dt
	if ld.shown < ld.minTime || Scene_PreloadProgress(game, ld.target) < 1 do return
	target := ld.target
	spec := ld.spec
	ld.active = false
	ld.spec = {}
	Game_ChangeSceneSpec(game, target, spec)
	Transition_SpecFree(&spec)
}

// --- background loading -------------------------------------------------------------

@(private = "file")
Preload_Kind :: enum {
	Texture,
	Sound,
	Music,
	Font,
}

@(private = "file")
Preload_Item :: struct {
	kind:     Preload_Kind,
	path:     string, // project-relative (heap)
	size:     f32,    // fonts
	held:     rawptr, // what was loaded (released once the scene is loaded)
	job:      ^Decode_Job, // a texture being decoded on a worker (async_decode.odin)
	finished: bool,
}

Scene_Preload :: struct {
	items: [dynamic]Preload_Item,
	next:  int, // the next item to start
	done:  int, // items finished (loaded, or missing)
}

// Scene_PreloadBegin queues a scene's assets (textures, sounds, music,
// fonts - also those of the components it uses) to load a few at a time
// (Scene_PreloadStep). Loading the scene afterwards finds them cached.
Scene_PreloadBegin :: proc(game: ^Game, scene: ^Scene) {
	if scene == nil || scene.isLoaded || scene in game.preloads do return
	p := new(Scene_Preload, Engine_HeapAllocator())
	p.items = make([dynamic]Preload_Item, Engine_HeapAllocator())
	if game.preloads == nil do game.preloads = make(map[^Scene]^Scene_Preload, allocator = Engine_HeapAllocator())
	game.preloads[scene] = p
	if scene.sourceJson == "" do return
	seen := make(map[string]bool, allocator = context.temp_allocator)
	add :: proc(p: ^Scene_Preload, seen: ^map[string]bool, kind: Preload_Kind, path: string, size: f32 = 0) {
		if path == "" do return
		key := fmt.tprintf("%v|%s|%v", kind, path, size)
		if key in seen do return
		seen[key] = true
		append(&p.items, Preload_Item{kind = kind, path = strings.clone(path, Engine_HeapAllocator()), size = size})
	}
	walk :: proc(game: ^Game, p: ^Scene_Preload, seen: ^map[string]bool, v: json.Value, depth: int) {
		if depth > 64 do return
		#partial switch x in v {
		case json.Array:
			for e in x do walk(game, p, seen, e, depth + 1)
		case json.Object:
			type, _ := x["type"].(json.String)
			if s, ok := x["texture_path"].(json.String); ok do add(p, seen, .Texture, s) // (legacy)
			#partial switch tv in x["texture"] {
			case json.String: add(p, seen, .Texture, tv)
			case json.Object: if s, ok := tv["path"].(json.String); ok do add(p, seen, .Texture, s)
			}
			if s, ok := x["sheet"].(json.String); ok do add(p, seen, .Texture, s)
			if fr, ok := x["frames"].(json.Array); ok do for f in fr do if s, sok := f.(json.String); sok do add(p, seen, .Texture, s)
			if tm, ok := x["tilemap"].(json.Object); ok do if s, sok := tm["tileset"].(json.String); sok do add(p, seen, .Texture, s)
			if s, ok := x["audio"].(json.String); ok do add(p, seen, .Music if type == "MusicNode" else .Sound, s)
			if props, ok := x["properties"].(json.Object); ok {
				// Image files named by properties (nine-slices, particles, ...).
				for _, pv in props {
					if ps, sok := pv.(json.String); sok && preload_is_image(ps) do add(p, seen, .Texture, ps)
				}
				if s, sok := props["font"].(json.String); sok && s != "" {
					size: f32 = 24
					if f, fok := json_number(props["fontSize"]); fok do size = f
					add(p, seen, .Font, s, size)
				}
			}
			// A component instance: its file's assets too.
			if comp, ok := x["component"].(json.String); ok && !(comp in seen^) {
				seen[strings.clone(comp, context.temp_allocator)] = true
				if data, rok := AssetManager_ReadFileBytes(&game.assetManager, comp, context.temp_allocator); rok {
					if cv, err := json.parse(data, allocator = context.temp_allocator); err == nil do walk(game, p, seen, cv, depth + 1)
				}
			}
			for _, e in x do walk(game, p, seen, e, depth + 1)
		}
	}
	if v, err := json.parse(transmute([]u8)scene.sourceJson, allocator = context.temp_allocator); err == nil {
		walk(game, p, &seen, v, 0)
	}
}

@(private = "file")
preload_is_image :: proc(path: string) -> bool {
	lower := strings.to_lower(path, context.temp_allocator)
	for ext in ([]string{".png", ".jpg", ".jpeg", ".bmp", ".qoi", ".tga"}) do if strings.has_suffix(lower, ext) do return true
	return false
}

// Scene_PreloadStep starts queued assets until `budget` is spent this frame:
// textures are read here and decoded on worker threads (uploaded by
// Decode_Pump); sounds, music and fonts load here.
Scene_PreloadStep :: proc(game: ^Game, budget: time.Duration = 4 * time.Millisecond) {
	rm := &game.resourceManager
	Decode_Pump(rm) // finished decodes -> textures (also for abandoned preloads)
	Vector_JobPump() // finished vector tessellations -> their assets (vector_jobs.odin)
	if len(game.preloads) == 0 do return
	start := time.tick_now()
	ctx := &game.gameContext
	for _, p in game.preloads {
		// Collect the textures decoded since last frame.
		for &it in p.items[:p.next] {
			if it.job == nil || !it.job.uploaded do continue
			it.held = Decode_Collect(it.job)
			it.job = nil
			it.finished = true
			p.done += 1
		}
		for p.next < len(p.items) {
			if time.tick_since(start) > budget do break
			it := &p.items[p.next]
			p.next += 1
			if !rl.IsWindowReady() {
				// Headless: nothing to load.
				it.finished = true
				p.done += 1
				continue
			}
			resolved := Project_ResolveAssetPath(ctx, it.path)
			if it.kind == .Texture {
				if ResourceManager_HasTexture(rm, resolved) || Atlas_Has(rm, resolved) { // (atlased: its page loads now)
					if t, ok := rm.loadTexture(rm, resolved); ok do it.held = t // cached: a reference
				} else if bytes, ok := Decode_ReadBytes(rm, resolved); ok {
					it.job = Decode_Submit(resolved, bytes)
					continue // finished when collected
				}
				it.finished = true
				p.done += 1
				continue
			}
			switch it.kind {
			case .Texture:
			case .Sound:
				if rl.IsAudioDeviceReady() do if s, ok := rm.loadAudioSound(rm, resolved); ok do it.held = s
			case .Music:
				if rl.IsAudioDeviceReady() do if m, ok := rm.loadAudioMusic(rm, resolved); ok do it.held = m
			case .Font:
				Text_GetFont(it.path, it.size, false, ctx) // cached for the run
			}
			it.finished = true
			p.done += 1
		}
	}
}

// Scene_PreloadProgress: 0..1 (1 when nothing is left to load, or loaded).
Scene_PreloadProgress :: proc(game: ^Game, scene: ^Scene) -> f32 {
	if scene == nil do return 0
	if scene.isLoaded do return 1
	p, ok := game.preloads[scene]
	if !ok do return 0
	if len(p.items) == 0 do return 1
	return f32(p.done) / f32(len(p.items))
}

// Scene_PreloadRelease drops what a preload holds (its scene has its own
// references once loaded; or the preload is abandoned).
Scene_PreloadRelease :: proc(game: ^Game, scene: ^Scene) {
	p, ok := game.preloads[scene]
	if !ok do return
	rm := &game.resourceManager
	for it in p.items {
		if it.job != nil do Decode_Abandon(rm, it.job) // still decoding (or not collected)
		if it.held != nil {
			switch it.kind {
			case .Texture: ResourceManager_ReleaseTexture(rm, cast(^Texture)it.held)
			case .Sound:   ResourceManager_ReleaseSound(rm, cast(^AudioSound)it.held)
			case .Music:   ResourceManager_ReleaseMusic(rm, cast(^AudioMusic)it.held)
			case .Font:
			}
		}
		delete(it.path, Engine_HeapAllocator())
	}
	delete(p.items)
	free(p, Engine_HeapAllocator())
	delete_key(&game.preloads, scene)
}

// Scene_FlowUpdate runs once a frame before the scene change is processed:
// transition, preloading, and releasing preloads whose scene got loaded.
Scene_FlowUpdate :: proc(game: ^Game, dt: f32) {
	Scene_TransitionUpdate(game, dt)
	Scene_PreloadStep(game)
	loading_update(game, dt)
}

// Scene_FlowAfterChange: preloads of scenes now loaded let go.
Scene_FlowAfterChange :: proc(game: ^Game) {
	if len(game.preloads) == 0 do return
	done := make([dynamic]^Scene, context.temp_allocator)
	for s in game.preloads do if s.isLoaded do append(&done, s)
	for s in done do Scene_PreloadRelease(game, s)
}

// Scene_FlowShutdown releases every preload (game end).
Scene_FlowShutdown :: proc(game: ^Game) {
	for len(game.preloads) > 0 {
		for s in game.preloads {
			Scene_PreloadRelease(game, s)
			break
		}
	}
	delete(game.preloads)
	game.preloads = nil
	Transition_Shutdown(game)
	Decode_Shutdown()
	Vector_JobsShutdown()
}
