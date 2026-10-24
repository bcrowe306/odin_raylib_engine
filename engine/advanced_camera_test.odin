package engine

import "core:math"
import os "osx"
import "core:testing"
import lua "lua54"

// Advanced cameras: a host made when the scene has no camera, following
// (Simple with an offset, Framed's dead zone, Group's auto zoom), Rect
// limits, priorities and the blend between cameras (events), trauma
// stacking / decaying into a shake, the Lua API, and removal.
@(test)
test_advanced_camera_follow_blend_trauma :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("advcam", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running

	hero := Node_CreateByTypeName(scene, "Node")
	hero.name = "Hero"
	hero.position = {500, 300}
	a := cast(^AdvancedCameraNode)Node_CreateByTypeName(scene, "AdvancedCameraNode")
	a.name = "CamA"
	a.followTarget = "Hero"
	a.followOffset = {0, -40}
	a.damping = 0
	ProcessNodeQueues(scene.manager, &game.gameContext)
	game->run(1.0 / 60)
	game->run(1.0 / 60)
	testing.expect(t, len(scene.manager.advCameras) == 1, "listed")
	testing.expect(t, scene.camera != nil && scene.camera.transient, "a host camera was added (not saved)")
	testing.expectf(t, a.lookAt == {500, 260} && a.active, "Simple follow with offset (%v), active", a.lookAt)
	game->run(1.0 / 60)
	testing.expectf(t, scene.camera.currentPosition == {500, 260}, "the host shows it (%v)", scene.camera.currentPosition)

	// Framed: inside the dead zone it stays, outside it moves to the edge.
	a.followMode = .Framed
	a.followOffset = {}
	a.deadZone = {0.5, 0.5} // 640 x 360 at zoom 1
	hero.position = {500, 260}
	game->run(1.0 / 60)
	start := a.lookAt
	hero.position = start + {200, 0}
	game->run(1.0 / 60)
	testing.expectf(t, a.lookAt == start, "inside the dead zone it stays (%v)", a.lookAt)
	hero.position = start + {400, 0}
	game->run(1.0 / 60)
	testing.expectf(t, math.abs(a.lookAt.x - (start.x + 80)) < 0.5, "to the dead zone's edge (%v)", a.lookAt)

	// Rect limits: the view (1280 x 720 at zoom 1) stays inside.
	a.followMode = .Glued
	a.limitMode = .Rect
	a.limitRect = {0, 0, 2000, 1000}
	a.limitBlend = 0
	hero.position = {100, 900}
	game->run(1.0 / 60)
	testing.expectf(t, a.lookAt == {640, 640}, "clamped by the limits (%v)", a.lookAt)
	a.limitRect = {0, 0, 400, 300} // smaller than the view: centred
	game->run(1.0 / 60)
	testing.expectf(t, a.lookAt == {200, 150}, "smaller limits: centred (%v)", a.lookAt)
	a.limitMode = .None

	// Group: frames both, auto zoom fits them.
	b := Node_CreateByTypeName(scene, "Node")
	b.name = "Buddy"
	hero.position = {0, 0}
	b.position = {2000, 0}
	a.followMode = .Group
	a.followTargets = "Buddy"
	a.autoZoom, a.autoZoomMargin, a.autoZoomMin, a.autoZoomMax = true, 0, 0.1, 4
	ProcessNodeQueues(scene.manager, &game.gameContext)
	for _ in 0 ..< 120 do game->run(1.0 / 60)
	testing.expectf(t, a.lookAt == {1000, 0} && math.abs(a.curZoom - 0.64) < 0.01, "group centre %v, zoom %v (1280 / 2000)", a.lookAt, a.curZoom)

	// A second camera with a higher priority takes over, blending.
	a.followMode, a.autoZoom = .Glued, false
	c := cast(^AdvancedCameraNode)Node_CreateByTypeName(scene, "AdvancedCameraNode")
	c.name = "CamB"
	c.followMode = .None
	c.position = {3000, 0}
	c.priority = 5
	c.blendTime = 1
	c.blendEase = .Linear
	activated := 0
	c.onActive->subscribe(proc(src: rawptr, v: EventValue, ctx: ^GameContext, ud: rawptr) {(cast(^int)ud)^ += 1}, &activated)
	ProcessNodeQueues(scene.manager, &game.gameContext)
	Node_SetGlobalPositions(scene.manager, scene.rootNode)
	for _ in 0 ..< 30 do game->run(1.0 / 60)
	mid := scene.camera.currentPosition.x
	testing.expectf(t, c.active && !a.active && activated == 1, "B is active (events)")
	testing.expectf(t, mid > 1200 && mid < 2800, "half way through the blend (%v)", mid)
	for _ in 0 ..< 40 do game->run(1.0 / 60)
	testing.expectf(t, scene.camera.currentPosition == {3000, 0}, "blended to B (%v)", scene.camera.currentPosition)

	// Trauma stacks to 1, decays, and shakes the host.
	AdvCam_AddTrauma(c, 0.7)
	AdvCam_AddTrauma(c, 0.7)
	testing.expect_value(t, c.trauma, f32(1))
	game->run(0.1)
	off, _ := AdvCam_Shake(c)
	testing.expectf(t, c.trauma < 1 && c.trauma > 0.8 && off != {}, "decays (%v) and shakes (%v)", c.trauma, off)
	testing.expect(t, scene.camera.shakeOffset != {}, "the host shakes")
	for _ in 0 ..< 60 do game->run(1.0 / 60)
	testing.expect(t, c.trauma == 0 && scene.camera.shakeOffset == {}, "calm again")

	// Lua.
	L := game.scriptManager.L
	ok := lua.L_dostring(L, `
local a = Scene.find_node("CamA")
a:make_active()
Camera.add_trauma(0.25)
was = a:is_active()
`)
	if ok != 0 do testing.fail_now(t, string(lua.tostring(L, -1)))
	testing.expect(t, a.priority == 6, "make_active raises the priority above the others")
	game->run(1.0 / 60)
	ok = lua.L_dostring(L, `active = Camera.get_active():get_name(); now = Scene.find_node("CamA"):is_active()`)
	if ok != 0 do testing.fail_now(t, string(lua.tostring(L, -1)))
	lua.getglobal(L, "active")
	testing.expect_value(t, string(lua.tostring(L, -1)), "CamA")
	lua.pop(L, 1)
	lua.getglobal(L, "now")
	testing.expect(t, bool(lua.toboolean(L, -1)), "is_active after the switch")
	lua.pop(L, 1)

	// Removing cameras: the list empties, the host is itself again.
	RemoveNode(scene.manager, a)
	RemoveNode(scene.manager, c)
	ProcessNodeQueues(scene.manager, &game.gameContext)
	testing.expect_value(t, len(scene.manager.advCameras), 0)
	game->run(1.0 / 60)
	testing.expect(t, AdvCam_Active() == nil, "no active camera")
}

// LDtk level limits: the camera stays in the level the target is in and
// changes to the linked neighbour when it walks over.
@(test)
test_advanced_camera_ldtk_level_limits :: proc(t: ^testing.T) {
	_ = os.make_directory_all("test_advcam_ldtk")
	defer os.remove_all("test_advcam_ldtk")
	_ = os.write_entire_file("test_advcam_ldtk/game.ldtk", transmute([]u8)string(LDTK_WORLDS_PROJECT))
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	AssetManager_SetProjectDir(&game.assetManager, "test_advcam_ldtk")
	scene := game->createScene("advcam_ldtk", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running

	ln := cast(^LdtkLevelNode)Node_CreateByTypeName(scene, "LdtkLevelNode")
	ln.gameContext = &game.gameContext
	ln.worldIdentifier = "Overworld"
	ln.worldMode = true
	LdtkLevelNode_SetProject(ln, "test_advcam_ldtk/game.ldtk", "A")
	testing.expect_value(t, len(ln.activeLevels), 2) // A (0..64) and B (64..128), 32 high

	hero := Node_CreateByTypeName(scene, "Node")
	hero.name = "HeroZz"
	hero.position = {10, 10}
	cam := cast(^AdvancedCameraNode)Node_CreateByTypeName(scene, "AdvancedCameraNode")
	cam.followTarget = "HeroZz"
	cam.followMode = .Glued
	cam.zoom = 40 // a 32 x 18 view
	cam.limitMode = .LdtkLevel
	cam.limitBlend = 0
	ProcessNodeQueues(scene.manager, &game.gameContext)
	game->run(1.0 / 60)
	game->run(1.0 / 60)
	testing.expectf(t, cam.lookAt == {16, 10} && cam.limitCur == {0, 0, 64, 32}, "in level A (%v, %v)", cam.lookAt, cam.limitCur)
	hero.position = {120, 30}
	game->run(1.0 / 60)
	testing.expectf(t, cam.lookAt == {112, 23} && cam.limitCur == {64, 0, 128, 32}, "in level B (%v, %v)", cam.lookAt, cam.limitCur)
	// Gliding (Limit Blend) moves the limits over a few frames.
	cam.limitBlend = 0.5
	hero.position = {10, 10}
	game->run(1.0 / 60)
	testing.expectf(t, cam.limitCur[0] > 0 && cam.limitCur[0] < 64, "gliding back (%v)", cam.limitCur)
	for _ in 0 ..< 120 do game->run(1.0 / 60)
	testing.expectf(t, math.abs(cam.limitCur[0]) < 0.5, "arrived in A (%v)", cam.limitCur)
	// The editor preview doesn't touch the camera.
	before := cam^
	center, _, lim, has := AdvCam_Preview(cam, &game.gameContext)
	testing.expect(t, has && lim == {0, 0, 64, 32} && center == {16, 10}, "preview")
	testing.expect(t, cam.lookAt == before.lookAt && cam.limitCur == before.limitCur, "preview leaves the camera alone")
}
