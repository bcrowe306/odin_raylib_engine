package engine

import "core:fmt"
import "core:strings"
import "core:testing"
import lua "lua54"

// Scene transitions (scene_transition.odin). Headless: no frame to copy, so
// the snapshot kinds' phases are driven by hand where it matters.

@(private = "file")
Transition_Test_Log :: struct {
	entries: [dynamic]string,
}

@(private = "file")
transition_test_game :: proc() -> (^Game, ^Scene, ^Scene, ^Scene) {
	game := new(Game)
	InitializeGame(game)
	a := game->createScene("a", true)
	b := game->createScene("b", false)
	c := game->createScene("c", false)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	return game, a, b, c
}

@(private = "file")
transition_test_listen :: proc(game: ^Game, log: ^Transition_Test_Log) {
	for ev in ([]string{"transition_started", "transition_midpoint", "transition_finished"}) {
		EventBus_Subscribe(&game.events, ev, proc(source: rawptr, value: EventValue, ctx: ^GameContext, ud: rawptr) {
			l := cast(^Transition_Test_Log)ud
			append(&l.entries, fmt.tprintf("%v", value))
		}, log)
	}
}

@(test)
test_transition_names :: proc(t: ^testing.T) {
	game, _, _, _ := transition_test_game()
	defer game->terminate()
	check :: proc(t: ^testing.T, game: ^Game, name: string, kind: Transition_Kind, shader: string, ok: bool) {
		k, s, found := Transition_Parse(game, name)
		testing.expectf(t, k == kind && s == shader && found == ok, "%s -> %v %q %v", name, k, s, found)
	}
	check(t, game, "fade", .Fade, "", true)
	check(t, game, "wipe", .WipeLeft, "", true) // (older names)
	check(t, game, "iris", .Circle, "", true)
	check(t, game, "crossfade", .CrossFade, "", true)
	check(t, game, "slide_up", .SlideUp, "", true)
	check(t, game, "push_right", .PushRight, "", true)
	check(t, game, "shaders/swirl.fs", .Shader, "shaders/swirl.fs", true)
	check(t, game, "builtin:transition_dissolve", .Shader, "builtin:transition_dissolve", true)
	check(t, game, "nope", .Fade, "", false)
	Transition_Register(game, "swirl", "shaders/swirl.fs")
	Transition_Register(game, "swirl", "shaders/swirl2.fs") // (renamed shader: replaced)
	check(t, game, "swirl", .Shader, "shaders/swirl2.fs", true)
	testing.expect_value(t, Transition_KindParse("wipe_down"), Transition_Kind.WipeDown)
	testing.expect_value(t, Transition_KindParse("???"), Transition_Kind.Fade)
}

// A cover transition with its own uncover half; the events in order; the
// tree paused meanwhile.
@(test)
test_transition_cover_events_pause :: proc(t: ^testing.T) {
	game, a, b, _ := transition_test_game()
	defer game->terminate()
	log := Transition_Test_Log{entries = make([dynamic]string, context.temp_allocator)}
	transition_test_listen(game, &log)

	spec := TRANSITION_DEFAULT
	spec.kind, spec.duration, spec.ease = .WipeLeft, 0.2, .Linear
	spec.hasIn, spec.inKind, spec.inDuration, spec.inEase = true, .Circle, 0.4, .Linear
	spec.pause = true
	Game_ChangeSceneSpec(game, b, spec)
	testing.expect(t, game.transition.active && game.transition.phase == .Cover, "covering")
	testing.expect(t, game.treePaused, "paused while it runs")
	game->run(0.1)
	testing.expectf(t, abs(Scene_TransitionAmount(game) - 0.5) < 0.01, "linear: half covered (%v)", Scene_TransitionAmount(game))
	game->run(0.1)
	game->run(0.01)
	testing.expect(t, game.sceneManager.currentScene == b && game.transition.phase == .Reveal, "switched")
	// The uncover half is the circle over 0.4 s.
	game->run(0.2)
	testing.expectf(t, game.transition.active && abs(Scene_TransitionAmount(game) - 0.5) < 0.05, "uncovering for 0.4 s (%v)", Scene_TransitionAmount(game))
	game->run(0.25)
	testing.expect(t, !game.transition.active, "done")
	testing.expect(t, !game.treePaused, "unpaused after")
	testing.expectf(t, strings.join(log.entries[:], ",", context.temp_allocator) == "b,b,b", "started, midpoint, finished: %v", log.entries)
	_ = a
}

// A change asked for during a transition waits for it (the last one wins);
// the same target again is ignored.
@(test)
test_transition_queued_change :: proc(t: ^testing.T) {
	game, a, b, c := transition_test_game()
	defer game->terminate()
	Game_ChangeSceneWith(game, b, .Fade, 0.1)
	Game_ChangeSceneWith(game, b, .Fade, 0.1) // (already going there)
	testing.expect(t, game.transition.pending == nil, "same target: nothing queued")
	Game_ChangeSceneWith(game, a, .Fade, 0.1)
	Game_ChangeSceneWith(game, c, .Circle, 0.1)
	testing.expect(t, game.transition.pending == c, "the last change asked for waits")
	for _ in 0 ..< 30 do game->run(0.02)
	testing.expect(t, game.sceneManager.currentScene == c && !game.transition.active, "then it ran")
}

// Snapshot kinds: with no frame to copy (headless) a fade over the same
// time; their phases (old scene running until the copy, then the reveal)
// driven by hand.
@(test)
test_transition_snapshot_phases :: proc(t: ^testing.T) {
	game, _, b, _ := transition_test_game()
	defer game->terminate()
	spec := TRANSITION_DEFAULT
	spec.kind, spec.duration = .PushLeft, 0.6
	Game_ChangeSceneSpec(game, b, spec)
	testing.expect(t, game.transition.kind == .Fade && abs(game.transition.duration - 0.3) < 0.001, "headless: a fade, half each way")
	for _ in 0 ..< 40 do game->run(0.02)
	testing.expect(t, !game.transition.active && game.sceneManager.currentScene == b, "faded")

	// The phases (as with a frame target): the old scene runs until its frame
	// is copied, then the switch, then the reveal over `duration`.
	a := game.sceneManager.scenes["a"]
	game.transition = {active = true, kind = .CrossFade, duration = 0.4, target = a, phase = .Capture, spec = {kind = .CrossFade, duration = 0.4, ease = .Linear}}
	game->run(0.02)
	testing.expect(t, game.sceneManager.currentScene == b && game.transition.phase == .Capture, "waits for the copy")
	testing.expect_value(t, Scene_TransitionAmount(game), 1) // (all old)
	game.transition.captured = true
	game->run(0.02)
	testing.expect(t, game.sceneManager.currentScene == a && game.transition.phase == .Reveal, "switched after the copy")
	game->run(0.2)
	testing.expectf(t, abs(Scene_TransitionAmount(game) - 0.5) < 0.06, "half the old frame left (%v)", Scene_TransitionAmount(game))
	game->run(0.25)
	testing.expect(t, !game.transition.active, "done")
}

@(test)
test_transition_lua_and_project_default :: proc(t: ^testing.T) {
	game, a, b, _ := transition_test_game()
	defer game->terminate()
	L := game.scriptManager.L

	ok := lua.L_dostring(L, `Scene.change_scene("b", {transition = "wipe_up", duration = 0.3, easing = "out_quad", transition_in = "circle", duration_in = 0.5, color = "#ff8000", pause = true})`)
	testing.expect_value(t, ok, i32(0))
	tr := &game.transition
	testing.expect(t, tr.active && tr.spec.kind == .WipeUp && tr.spec.duration == 0.3 && tr.spec.ease == .Out_Quad, "the cover half")
	testing.expect(t, tr.spec.hasIn && tr.spec.inKind == .Circle && tr.spec.inDuration == 0.5 && tr.spec.inEase == .Out_Quad, "the uncover half (its easing from the cover's)")
	testing.expect(t, tr.spec.color == {255, 128, 0, 255} && tr.spec.pause && game.treePaused, "colour and pause")
	for _ in 0 ..< 60 do game->run(0.02)
	testing.expect(t, game.sceneManager.currentScene == b && !tr.active && !game.treePaused, "arrived, unpaused")

	// A registered shader transition (headless: a fade).
	ok = lua.L_dostring(L, `Scene.register_transition("swirl", "shaders/swirl.fs"); Scene.change_scene("a", {transition = "swirl", duration = 0.2})`)
	testing.expect_value(t, ok, i32(0))
	testing.expect(t, tr.active && tr.kind == .Fade, "shader transition headless: a fade")
	for _ in 0 ..< 30 do game->run(0.02)
	testing.expect(t, game.sceneManager.currentScene == a, "there")

	// No options: at once - unless the project has a default transition.
	ok = lua.L_dostring(L, `Scene.change_scene("b")`)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	testing.expect(t, game.sceneManager.currentScene == b && !tr.active, "at once")
	Transition_SetDefault(game, "circle", 0.25, "linear")
	ok = lua.L_dostring(L, `Scene.change_scene("a")`)
	testing.expect(t, tr.active && tr.spec.kind == .Circle && tr.spec.duration == 0.25 && tr.spec.ease == .Linear, "the project's default")
	for _ in 0 ..< 40 do game->run(0.02)
	// Options a script leaves out come from the default.
	ok = lua.L_dostring(L, `Scene.change_scene("b", {duration = 0.1})`)
	testing.expect(t, tr.active && tr.spec.kind == .Circle && tr.spec.duration == 0.1, "default kind, given duration")
	for _ in 0 ..< 20 do game->run(0.02)
	Transition_SetDefault(game, "none", 0, "")
	testing.expect(t, !game.hasDefaultTransition, "none: no default")
}

@(test)
test_transition_project_config :: proc(t: ^testing.T) {
	cfg: ProjectConfig
	cfg.name = "T"
	cfg.transition = "slide_left"
	cfg.transitionDuration = 0.6
	cfg.transitionEasing = "out_cubic"
	text := Project_SerializeToJSON(&cfg, context.temp_allocator)
	testing.expectf(t, strings.contains(text, `"scene_flow": {"transition": "slide_left", "duration": 0.60, "easing": "out_cubic"}`), "saved: %s", text)
	back, ok := Project_ParseConfig(transmute([]u8)text)
	defer ProjectConfig_Destroy(&back)
	testing.expect(t, ok && back.transition == "slide_left" && back.transitionDuration == 0.6 && back.transitionEasing == "out_cubic", "read back")
}
