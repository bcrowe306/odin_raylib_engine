package engine

import "core:log"
import "core:math"
import "core:strings"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

// ============================================================================
// Scene transitions (Scene.change_scene's `transition`).
//
// Cover transitions (fade, wipe_*, circle) cover the screen with a colour,
// switch scenes underneath once the new one's assets are loaded, then
// uncover - each half with its own kind, duration and easing.
//
// Snapshot transitions (crossfade, dissolve, pixelate, slide_*, push_*, or
// a project's own shader) show both scenes at once: the old scene keeps
// running while the new one preloads, its last frame is copied (on the
// GPU) at the end of that frame, the scenes switch, and the old frame is
// drawn with the live new scene - faded, dissolved, slid or pushed - over
// `duration`. They need the frame the game draws into (the runner's frame
// target); without one (drawing straight to the screen, the smooth pixel
// camera) they fall back to a fade.
//
// A shader transition is a fragment shader (a project .fs file, or
// "builtin:..."): texture0 is the old scene's frame, `new_scene` the new
// one's, with `progress` (0 old .. 1 new), `resolution` and
// `transition_color`. Projects name their own with Transition_Register
// (Scene.register_transition).
//
// Events on the event bus (event_bus.odin), with the target scene's name:
// transition_started, transition_midpoint (the scenes switched),
// transition_finished. With `pause`, the scene tree is paused while it
// runs. A change asked for during a transition waits for it (the last
// one asked for wins).
// ============================================================================

Transition_Kind :: enum {
	// Cover the screen, switch, uncover.
	Fade,
	WipeLeft,  // the cover sweeps in from the right, leaving to the left
	WipeRight,
	WipeUp,
	WipeDown,
	Circle,    // an iris closing on the centre, then opening
	// The old scene's last frame with the new scene.
	CrossFade,
	Dissolve,  // the old frame burns away in noise
	Pixelate,  // the old frame breaks into blocks, the new one sharpens
	SlideLeft, // the new scene slides in over the old, towards the left
	SlideRight,
	SlideUp,
	SlideDown,
	PushLeft,  // the new scene pushes the old one out, towards the left
	PushRight,
	PushUp,
	PushDown,
	Shader,    // a fragment shader (Transition_Spec.shader)
}

TRANSITION_NAMES := [Transition_Kind]string {
	.Fade = "fade", .WipeLeft = "wipe_left", .WipeRight = "wipe_right", .WipeUp = "wipe_up", .WipeDown = "wipe_down", .Circle = "circle",
	.CrossFade = "crossfade", .Dissolve = "dissolve", .Pixelate = "pixelate",
	.SlideLeft = "slide_left", .SlideRight = "slide_right", .SlideUp = "slide_up", .SlideDown = "slide_down",
	.PushLeft = "push_left", .PushRight = "push_right", .PushUp = "push_up", .PushDown = "push_down",
	.Shader = "shader",
}

// Transition_Spec: how a scene change looks (Scene.change_scene's options).
Transition_Spec :: struct {
	kind:       Transition_Kind,
	duration:   f32,  // cover kinds: each half; the others: the whole
	ease:       Ease,
	color:      rl.Color,
	// The uncover half of a cover transition (else the same as covering).
	hasIn:      bool,
	inKind:     Transition_Kind,
	inDuration: f32,
	inEase:     Ease,
	shader:     string, // .Shader: the shader's path (heap when held by a transition)
	pause:      bool,   // the scene tree paused while it runs
}

TRANSITION_DEFAULT :: Transition_Spec{kind = .Fade, duration = 0.4, ease = .In_Out_Sine, color = {0, 0, 0, 255}}

Transition_Phase :: enum u8 {
	Cover,   // covering (cover kinds)
	Capture, // the old scene runs on until the new one is loaded; then its frame is copied
	Reveal,  // switched: uncovering, or the old frame over the new scene
}

Scene_Transition :: struct {
	active:       bool,
	kind:         Transition_Kind, // (spec.kind)
	color:        rl.Color,
	duration:     f32,
	t:            f32,
	target:       ^Scene,
	phase:        Transition_Phase,
	spec:         Transition_Spec,
	captured:     bool, // the old scene's frame was taken (the scenes can switch)
	hasSnapshot:  bool, // ... and copied into the snapshot
	pausedBefore: bool,
	warned:       bool, // (a shader that failed: said once)
	pending:      ^Scene,          // a change asked for meanwhile (the last one wins)
	pendingSpec:  Transition_Spec,
}

@(private = "file")
transitionTargets: struct {
	snapshot: rl.RenderTexture2D, // the old scene's last frame
	live:     rl.RenderTexture2D, // this frame's new scene (moved / shaded)
}

Transition_IsCover :: proc(k: Transition_Kind) -> bool {return k <= .Circle}

// Transition_Parse: a transition by name - built in, registered
// (Transition_Register), or a shader's path (.fs / .glsl / .frag, builtin:).
Transition_Parse :: proc(game: ^Game, name: string) -> (kind: Transition_Kind, shader: string, ok: bool) {
	switch name {
	case "wipe": return .WipeLeft, "", true
	case "iris": return .Circle, "", true
	case "cross_fade": return .CrossFade, "", true
	}
	for k in Transition_Kind do if k != .Shader && TRANSITION_NAMES[k] == name do return k, "", true
	if game != nil do if path, found := game.transitionShaders[name]; found do return .Shader, path, true
	lower := strings.to_lower(name, context.temp_allocator)
	if strings.has_prefix(lower, "builtin:") || strings.has_suffix(lower, ".fs") || strings.has_suffix(lower, ".glsl") || strings.has_suffix(lower, ".frag") {
		return .Shader, name, true
	}
	return .Fade, "", false
}

// Transition_KindParse: a built-in transition by name (fade when unknown).
Transition_KindParse :: proc(s: string) -> Transition_Kind {
	k, _, _ := Transition_Parse(nil, s)
	return k
}

// Transition_Register names a shader transition for Scene.change_scene.
Transition_Register :: proc(game: ^Game, name, shader: string) {
	a := Engine_HeapAllocator()
	if game.transitionShaders == nil do game.transitionShaders = make(map[string]string, allocator = a)
	if old, found := game.transitionShaders[name]; found {
		delete(old, a)
		game.transitionShaders[name] = strings.clone(shader, a)
		return
	}
	game.transitionShaders[strings.clone(name, a)] = strings.clone(shader, a)
}

// Transition_SetDefault: the project's transition for Scene.change_scene
// without one ("" or "none": a change is at once).
Transition_SetDefault :: proc(game: ^Game, name: string, duration: f32, ease: string) {
	Transition_SpecFree(&game.defaultTransition)
	game.hasDefaultTransition = false
	if name == "" || name == "none" do return
	spec := TRANSITION_DEFAULT
	spec.kind, spec.shader, _ = Transition_Parse(game, name)
	if duration > 0 do spec.duration = duration
	if e, ok := Ease_Parse(ease); ok do spec.ease = e
	game.defaultTransition = Transition_SpecClone(spec)
	game.hasDefaultTransition = true
}

Transition_SpecClone :: proc(s: Transition_Spec) -> Transition_Spec {
	c := s
	c.shader = strings.clone(s.shader, Engine_HeapAllocator()) if s.shader != "" else ""
	return c
}

Transition_SpecFree :: proc(s: ^Transition_Spec) {
	if s.shader != "" do delete(s.shader, Engine_HeapAllocator())
	s.shader = ""
}

// Game_ChangeSceneWith switches scenes behind a transition: the screen is
// covered over `duration`, the scene switches (once its assets are
// preloaded), then it's uncovered. duration <= 0: switch at once.
Game_ChangeSceneWith :: proc(game: ^Game, scene: ^Scene, kind: Transition_Kind = .Fade, duration: f32 = 0.4, color: rl.Color = rl.BLACK) {
	spec := TRANSITION_DEFAULT
	spec.kind, spec.duration, spec.color = kind, duration, color
	Game_ChangeSceneSpec(game, scene, spec)
}

// Game_ChangeSceneSpec: Game_ChangeSceneWith with every option.
Game_ChangeSceneSpec :: proc(game: ^Game, scene: ^Scene, spec: Transition_Spec) {
	if scene == nil do return
	tr := &game.transition
	if tr.active {
		// After this one (the last change asked for wins).
		if scene == tr.target && tr.pending == nil do return
		Transition_SpecFree(&tr.pendingSpec)
		tr.pending = scene
		tr.pendingSpec = Transition_SpecClone(spec)
		return
	}
	if spec.duration <= 0 {
		ChangeScene_ByPtr(&game.sceneManager, scene)
		return
	}
	s := Transition_SpecClone(spec)
	if !Transition_IsCover(s.kind) && !transition_can_capture() {
		// No frame to copy: a fade over the same time.
		Transition_SpecFree(&s)
		s.kind, s.duration, s.hasIn = .Fade, spec.duration * 0.5, false
	}
	Scene_PreloadBegin(game, scene)
	tr^ = {
		active = true, kind = s.kind, color = s.color, duration = s.duration, target = scene, spec = s,
		phase = .Cover if Transition_IsCover(s.kind) else .Capture,
	}
	if s.pause {
		tr.pausedBefore = game.treePaused
		game.treePaused = true
	}
	EventBus_Publish(&game.events, "transition_started", scene.name)
}

Scene_TransitionActive :: proc(game: ^Game) -> bool {return game.transition.active}

// transition_can_capture: is there a frame to copy the old scene from?
@(private = "file")
transition_can_capture :: proc() -> bool {
	return rl.IsWindowReady() && Render_FrameTarget() != nil && !renderPixel.smooth
}

@(private = "file")
transition_reveal :: proc(tr: ^Scene_Transition) -> (duration: f32, ease: Ease) {
	if Transition_IsCover(tr.spec.kind) && tr.spec.hasIn do return tr.spec.inDuration, tr.spec.inEase
	return tr.spec.duration, tr.spec.ease
}

// Scene_TransitionUpdate advances the transition (call before the scene
// change is processed).
Scene_TransitionUpdate :: proc(game: ^Game, dt: f32) {
	tr := &game.transition
	if !tr.active do return
	tr.t += dt
	switch tr.phase {
	case .Cover:
		// Covered and loaded: switch.
		if tr.t >= tr.duration && Scene_PreloadProgress(game, tr.target) >= 1 do transition_switch(game)
	case .Capture:
		if tr.captured do transition_switch(game) // (the old frame was copied at the end of the last frame)
	case .Reveal:
		if d, _ := transition_reveal(tr); tr.t >= d do transition_finish(game)
	}
}

@(private = "file")
transition_switch :: proc(game: ^Game) {
	tr := &game.transition
	ChangeScene_ByPtr(&game.sceneManager, tr.target)
	tr.phase = .Reveal
	tr.t = 0
	EventBus_Publish(&game.events, "transition_midpoint", tr.target.name)
}

@(private = "file")
transition_finish :: proc(game: ^Game) {
	tr := &game.transition
	target := tr.target
	if tr.spec.pause do game.treePaused = tr.pausedBefore
	pending, pendingSpec := tr.pending, tr.pendingSpec
	Transition_SpecFree(&tr.spec)
	tr^ = {}
	EventBus_Publish(&game.events, "transition_finished", target.name)
	if pending != nil {
		Game_ChangeSceneSpec(game, pending, pendingSpec)
		Transition_SpecFree(&pendingSpec)
	}
}

// Scene_TransitionAmount: cover kinds - how much of the screen is covered
// (0..1); the others - how much of the old scene is left.
Scene_TransitionAmount :: proc(game: ^Game) -> f32 {
	tr := &game.transition
	if !tr.active do return 0
	switch tr.phase {
	case .Cover: return Ease_Apply(tr.spec.ease, tr.t / max(tr.duration, 0.0001))
	case .Capture: return 1 if !Transition_IsCover(tr.spec.kind) else 0
	case .Reveal:
		d, e := transition_reveal(tr)
		return 1 - Ease_Apply(e, tr.t / max(d, 0.0001))
	}
	return 0
}

// Scene_DrawTransition draws the transition over the frame (after the scene).
Scene_DrawTransition :: proc(game: ^Game) {
	tr := &game.transition
	if !tr.active || !rl.IsWindowReady() do return
	target := Render_FrameTarget()
	w, h := f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())
	if target != nil do w, h = f32(target.texture.width), f32(target.texture.height) // (the game's canvas, not the window)
	a := Scene_TransitionAmount(game)
	switch tr.phase {
	case .Cover:
		draw_cover(tr.spec.kind, a, true, w, h, tr.spec.color)
	case .Capture:
		if tr.captured || Scene_PreloadProgress(game, tr.target) < 1 do return
		if target != nil {
			transition_copy(target, &transitionTargets.snapshot)
			tr.hasSnapshot = true
		}
		tr.captured = true
	case .Reveal:
		if Transition_IsCover(tr.spec.kind) {
			draw_cover(tr.spec.inKind if tr.spec.hasIn else tr.spec.kind, a, false, w, h, tr.spec.color)
		} else if target != nil && tr.hasSnapshot {
			draw_snapshot(game, tr, target, 1 - a, w, h)
		}
	}
}

@(private = "file")
draw_cover :: proc(kind: Transition_Kind, a: f32, covering: bool, w, h: f32, c: rl.Color) {
	#partial switch kind {
	case .Fade:
		rl.DrawRectangleRec({0, 0, w, h}, {c.r, c.g, c.b, u8(f32(c.a) * a)})
	case .WipeLeft:
		x := w * (1 - a) if covering else 0
		rl.DrawRectangleRec({x, 0, w * a, h}, c)
	case .WipeRight:
		x := 0 if covering else w * (1 - a)
		rl.DrawRectangleRec({x, 0, w * a, h}, c)
	case .WipeUp:
		y := h * (1 - a) if covering else 0
		rl.DrawRectangleRec({0, y, w, h * a}, c)
	case .WipeDown:
		y := 0 if covering else h * (1 - a)
		rl.DrawRectangleRec({0, y, w, h * a}, c)
	case .Circle:
		diag := math.sqrt(w * w + h * h) * 0.5 + 2
		inner := diag * (1 - a)
		rl.DrawRing({w * 0.5, h * 0.5}, inner, diag, 0, 360, 96, c)
	case:
		rl.DrawRectangleRec({0, 0, w, h}, {c.r, c.g, c.b, u8(f32(c.a) * a)})
	}
}

// transition_copy copies the frame being drawn into `dst` (sized to it),
// then goes back to drawing the frame.
@(private = "file")
transition_copy :: proc(src: ^rl.RenderTexture2D, dst: ^rl.RenderTexture2D) {
	w, h := src.texture.width, src.texture.height
	if dst.id == 0 || dst.texture.width != w || dst.texture.height != h {
		if dst.id != 0 do rl.UnloadRenderTexture(dst^)
		dst^ = rl.LoadRenderTexture(w, h)
	}
	rl.EndTextureMode()
	rl.BeginTextureMode(dst^)
	rlgl.DrawRenderBatchActive()
	rlgl.DisableColorBlend() // (a copy: alpha as it is)
	rl.DrawTexturePro(src.texture, {0, 0, f32(w), -f32(h)}, {0, 0, f32(w), f32(h)}, {}, 0, rl.WHITE)
	rlgl.DrawRenderBatchActive()
	rlgl.EnableColorBlend()
	rl.EndTextureMode()
	rl.BeginTextureMode(src^)
}

// draw_snapshot draws the old scene's frame with the new scene (p: 0 the
// old one .. 1 the new one).
@(private = "file")
draw_snapshot :: proc(game: ^Game, tr: ^Scene_Transition, target: ^rl.RenderTexture2D, p: f32, w, h: f32) {
	snap := transitionTargets.snapshot.texture
	src := rl.Rectangle{0, 0, f32(snap.width), -f32(snap.height)}
	full := rl.Rectangle{0, 0, w, h}
	kind := tr.spec.kind
	shader := ""
	#partial switch kind {
	case .CrossFade:
		rl.DrawTexturePro(snap, src, full, {}, 0, rl.Fade(rl.WHITE, 1 - p))
		return
	case .SlideLeft, .SlideRight, .SlideUp, .SlideDown, .PushLeft, .PushRight, .PushUp, .PushDown:
		dir: [2]f32
		#partial switch kind {
		case .SlideLeft, .PushLeft: dir = {-1, 0}
		case .SlideRight, .PushRight: dir = {1, 0}
		case .SlideUp, .PushUp: dir = {0, -1}
		case .SlideDown, .PushDown: dir = {0, 1}
		}
		transition_copy(target, &transitionTargets.live)
		live := transitionTargets.live.texture
		rl.ClearBackground({0, 0, 0, 0})
		push := kind >= .PushLeft && kind <= .PushDown
		old := dir * p * {w, h} if push else {0, 0}
		new := -dir * (1 - p) * {w, h}
		rl.DrawTexturePro(snap, src, {old.x, old.y, w, h}, {}, 0, rl.WHITE)
		rl.DrawTexturePro(live, src, {new.x, new.y, w, h}, {}, 0, rl.WHITE)
		return
	case .Dissolve: shader = "builtin:transition_dissolve"
	case .Pixelate: shader = "builtin:transition_pixelate"
	case .Shader: shader = tr.spec.shader
	}
	sh, ok := Shader_Get(shader, &game.gameContext)
	if !ok {
		if !tr.warned {
			log.warnf("Scene transition: the shader %s can't be used (missing or doesn't compile); crossfading", shader)
			tr.warned = true
		}
		rl.DrawTexturePro(snap, src, full, {}, 0, rl.Fade(rl.WHITE, 1 - p))
		return
	}
	newScene := rl.GetShaderLocation(sh, "new_scene")
	if newScene >= 0 do transition_copy(target, &transitionTargets.live) // (only shaders that read it)
	rl.BeginShaderMode(sh)
	progress := p
	res := [2]f32{w, h}
	col := [4]f32{f32(tr.spec.color.r) / 255, f32(tr.spec.color.g) / 255, f32(tr.spec.color.b) / 255, f32(tr.spec.color.a) / 255}
	if loc := rl.GetShaderLocation(sh, "progress"); loc >= 0 do rl.SetShaderValue(sh, loc, &progress, .FLOAT)
	if loc := rl.GetShaderLocation(sh, "resolution"); loc >= 0 do rl.SetShaderValue(sh, loc, &res, .VEC2)
	if loc := rl.GetShaderLocation(sh, "transition_color"); loc >= 0 do rl.SetShaderValue(sh, loc, &col, .VEC4)
	if newScene >= 0 do rl.SetShaderValueTexture(sh, newScene, transitionTargets.live.texture)
	rl.DrawTexturePro(snap, src, full, {}, 0, rl.WHITE)
	rl.EndShaderMode()
}

// Transition_Shutdown frees the transition's textures and names (game end).
Transition_Shutdown :: proc(game: ^Game) {
	tr := &game.transition
	if tr.active && tr.spec.pause do game.treePaused = tr.pausedBefore
	Transition_SpecFree(&tr.spec)
	Transition_SpecFree(&tr.pendingSpec)
	tr^ = {}
	Transition_SpecFree(&game.loading.spec)
	Transition_SpecFree(&game.defaultTransition)
	game.hasDefaultTransition = false
	a := Engine_HeapAllocator()
	for k, v in game.transitionShaders {
		delete(k, a)
		delete(v, a)
	}
	delete(game.transitionShaders)
	game.transitionShaders = nil
	if rl.IsWindowReady() {
		if transitionTargets.snapshot.id != 0 do rl.UnloadRenderTexture(transitionTargets.snapshot)
		if transitionTargets.live.id != 0 do rl.UnloadRenderTexture(transitionTargets.live)
	}
	transitionTargets = {}
}
