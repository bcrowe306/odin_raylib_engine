package engine

import "core:encoding/json"
import os "osx"
import "core:path/filepath"
import "core:testing"
import lua "lua54"

// Accessibility: settings JSON (only differences saved, clamped), the
// player's file over the project's defaults, the colour filter maths, UI
// scale (a corner button grows into its corner and is clicked where it is
// drawn), screen shake scaling, the subtitle track (kinds, limits, time),
// dialogue in Subtitles mode (by itself, events), and the Lua API.
@(test)
test_accessibility :: proc(t: ^testing.T) {
	dir, _ := filepath.join({Engine_TempDir(), "ore_access_test_zz"}, context.temp_allocator)
	_ = os.remove_all(dir)
	defer os.remove_all(dir)
	Save_SetDirectory(dir)
	defer Save_Reset()
	defer {access, accessDefaults = ACCESS_DEFAULTS, ACCESS_DEFAULTS}
	defer Subtitles_Clear()

	// JSON.
	s := ACCESS_DEFAULTS
	s.uiScale, s.colorblind, s.captions, s.screenShake = 1.5, .Deuteranopia, true, 9
	s = Access_Clamp(s)
	testing.expect_value(t, s.screenShake, f32(2))
	text := Access_ToJSON(s, context.temp_allocator, ACCESS_DEFAULTS)
	testing.expectf(t, text == `{"ui_scale": 1.50, "colorblind": "deuteranopia", "captions": true, "screen_shake": 2.00}`, "only the differences: %s", text)
	v, _ := json.parse_string(text, allocator = context.temp_allocator)
	testing.expect(t, Access_FromJSON(v.(json.Object), ACCESS_DEFAULTS) == s, "round trip")

	// The player's file over the project's defaults.
	cfg := ProjectConfig{}
	ProjectConfig_SetAccessibility(&cfg, {uiScale = 1.25, subtitles = false, colorblindStrength = 1, subtitleScale = 1, subtitleBackground = 0.6, screenShake = 1})
	defer delete(cfg.accessibility)
	Access_SetDefaults(ProjectConfig_Accessibility(&cfg))
	testing.expect(t, access.uiScale == 1.25 && !access.subtitles, "project defaults")
	access.screenShake = 0.5
	testing.expect(t, Access_Save(), "saved")
	access = ACCESS_DEFAULTS
	testing.expect(t, Access_Load() && access.screenShake == 0.5 && access.uiScale == 1.25, "loaded over the defaults")
	Access_Reset()
	testing.expect(t, access.screenShake == 1 && !access.subtitles, "reset to the project's defaults")
	access, accessDefaults = ACCESS_DEFAULTS, ACCESS_DEFAULTS

	// Colour filter.
	gray := [3]f32{0.5, 0.5, 0.5}
	for m in Colorblind_Mode {
		out := Colorblind_Apply(gray, m, 1, false)
		testing.expectf(t, abs(out.r - 0.5) < 0.02 && abs(out.g - 0.5) < 0.02 && abs(out.b - 0.5) < 0.02, "grey stays grey (%v: %v)", m, out)
	}
	red := [3]f32{1, 0, 0}
	sim := Colorblind_Apply(red, .Protanopia, 1, true)
	testing.expectf(t, sim.r < 0.3 && abs(sim.r - sim.g) < 0.15, "protanopia: red seen dark and yellowish (%v)", sim)
	fixed := Colorblind_Apply(red, .Protanopia, 1, false)
	testing.expectf(t, fixed.b > 0.5, "corrected: the lost red moved into blue (%v)", fixed)
	testing.expect_value(t, Colorblind_Apply(red, .Protanopia, 0, false), red)

	// UI scale and screen shake in a game.
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("access", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	game.virtualSize = {1280, 720}
	btn := cast(^UIButtonNode)Node_CreateByTypeName(scene, "UIButtonNode")
	btn.position = {1100, 600}
	btn.size = {100, 50}
	clicked := 0
	btn.onClick->subscribe(proc(src: rawptr, v: EventValue, ctx: ^GameContext, ud: rawptr) {(cast(^int)ud)^ += 1}, &clicked)
	ProcessNodeQueues(scene.manager, &game.gameContext)
	game->run(0.016)
	access.uiScale = 2
	pivot, sc := UI_ScaleTransform(btn)
	testing.expectf(t, pivot == {1200, 650} && sc == 2, "grows into its corner (pivot %v)", pivot)
	// (1010, 560): outside the unscaled button, inside where it is drawn.
	game.uiTestInputEnabled = true
	click :: proc(game: ^Game, p: [2]f32) {
		game.uiTestMousePos = p
		game.uiTestMousePressed, game.uiTestMouseDown = true, true
		game->run(0.016)
		game.uiTestMousePressed, game.uiTestMouseDown, game.uiTestMouseReleased = false, false, true
		game->run(0.016)
		game.uiTestMouseReleased = false
	}
	click(game, {1010, 560})
	testing.expect_value(t, clicked, 1)
	access.uiScale = 1
	click(game, {1010, 560})
	testing.expect_value(t, clicked, 1) // (at scale 1 that's beside it)
	cam := CameraNode_Create(scene, "Cam", true)
	cam.currentPosition, cam.currentZoom, cam.shakeOffset = {100, 100}, 1, {30, 0}
	access.screenShake = 0
	testing.expect_value(t, CameraNode_GetCamera2D(cam, 1280, 720).target, [2]f32{100, 100})
	access.screenShake = 1
	testing.expect_value(t, CameraNode_GetCamera2D(cam, 1280, 720).target, [2]f32{130, 100})

	// Subtitles.
	access.captions = false
	testing.expect(t, Subtitles_Show("[door creaks]", "", 2, .Caption) == 0, "captions off: not shown")
	access.captions = true
	testing.expect(t, Subtitles_Show("[door creaks]", "", 2, .Caption) != 0, "captions on")
	for i in 0 ..< 4 do Subtitles_Show("line", "Ada", 1)
	testing.expect_value(t, Subtitles_Count(), SUBTITLE_MAX)
	Subtitles_Update(1.1)
	testing.expect_value(t, Subtitles_Count(), 0) // (the caption gave way to the newer lines)

	// Dialogue in Subtitles mode: lines follow each other by themselves.
	d := cast(^DialogueNode)Node_CreateByTypeName(scene, "DialogueNode")
	d.mode = .Subtitles
	shown, finished := 0, 0
	d.onLineShown->subscribe(proc(src: rawptr, v: EventValue, ctx: ^GameContext, ud: rawptr) {(cast(^int)ud)^ += 1}, &shown)
	d.onFinished->subscribe(proc(src: rawptr, v: EventValue, ctx: ^GameContext, ud: rawptr) {(cast(^int)ud)^ += 1}, &finished)
	ProcessNodeQueues(scene.manager, &game.gameContext)
	DialogueNode_Show(d, {{"Guard", "Halt!", ""}, {"Guard", "Who goes there?", ""}})
	game->run(0.016)
	testing.expect(t, shown == 1 && Subtitles_Count() == 1 && Subtitles_Lines()[0].speaker == "Guard", "the first line on the track")
	for _ in 0 ..< 60 * 5 do game->run(1.0 / 60)
	testing.expect(t, shown == 2 && finished == 1 && !DialogueNode_IsOpen(d), "both lines, then finished")
	testing.expect_value(t, Subtitles_Count(), 0)
	access.subtitles = false
	DialogueNode_Show(d, {{"", "Unseen", ""}})
	for _ in 0 ..< 60 * 3 do game->run(1.0 / 60)
	testing.expect(t, finished == 2 && Subtitles_Count() == 0, "subtitles off: still plays out, unseen")
	access.subtitles = true

	// Lua.
	L := game.scriptManager.L
	ok := lua.L_dostring(L, `
Accessibility.set("ui_scale", 1.75)
Accessibility.set("colorblind", "tritanopia")
bad = Accessibility.set("nope", 1)
all = Accessibility.get_all()
id = Subtitles.show("Hello", {speaker = "Ada", duration = 2})
n = Subtitles.count()
`)
	if ok != 0 do testing.fail_now(t, string(lua.tostring(L, -1)))
	testing.expect(t, access.uiScale == 1.75 && access.colorblind == .Tritanopia, "set")
	lua.getglobal(L, "n")
	testing.expect_value(t, lua.tointeger(L, -1), 1)
	lua.pop(L, 1)
	lua.getglobal(L, "bad")
	testing.expect(t, !bool(lua.toboolean(L, -1)), "unknown key refused")
	lua.pop(L, 1)
	_ = lua.L_dostring(L, `cb = all.colorblind`)
	lua.getglobal(L, "cb")
	testing.expect_value(t, string(lua.tostring(L, -1)), "tritanopia")
	lua.pop(L, 1)
}
