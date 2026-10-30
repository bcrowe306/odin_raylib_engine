package engine

import "core:strings"
import "core:testing"
import lua "lua54"

@(test)
test_camera_follow_target_saved_and_multi_target_lua :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	src := game->createScene("cam_src", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)

	// Editor side: the follow target is saved as a path relative to the camera.
	cam := CameraNode_Create(src, "Cam", true)
	player := Node_CreateByTypeName(src, "Node")
	player.name = "Player"
	player.position = {500, 300}
	ProcessNodeQueues(src.manager, &game.gameContext)
	CameraNode_SetFollowTarget(cam, src.manager, player)
	testing.expect_value(t, cam.followTarget, "../Player")
	text := Scene_SerializeToJSON(src, context.temp_allocator)
	testing.expect(t, strings.contains(text, `"follow": "../Player"`), "follow target saved")

	// Game side: loaded, the camera follows the player.
	scene := game->createScene("cam_run", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	Scene_InstantiateFromJSON(scene, transmute([]u8)text, &game.gameContext)
	ProcessNodeQueues(scene.manager, &game.gameContext)
	game.state = .Running
	game->run(0.016)
	c := scene.camera
	p := Scene_FindNodeByName(scene, "Player")
	testing.expectf(t, c != nil && p != nil && c.target == p && c.followMode == .SingleTarget, "follow target resolved: cam %v follow %q resolved %v target %p player %p mode %v", c.name if c != nil else "", c.followTarget if c != nil else "", c.followResolved if c != nil else false, c.target if c != nil else nil, p, c.followMode if c != nil else CameraFollowMode.Static)
	if c == nil || p == nil do return
	testing.expectf(t, abs(c.currentPosition.x - 500) < 1 && abs(c.currentPosition.y - 300) < 1, "starts on the target: %v", c.currentPosition)
	p.position = {900, 300}
	for _ in 0 ..< 120 do game->run(0.016)
	testing.expectf(t, c.currentPosition.x > 850, "follows the moving target: %v", c.currentPosition)

	// Destroyed target: dropped, no crash.
	RemoveNode(scene.manager, p)
	game->run(0.016)
	game->run(0.016)
	testing.expect(t, c.target == nil, "destroyed target dropped")

	// A saved target that appears later (spawned) is picked up.
	c.followTarget = "../Late"
	c.followResolved = false
	game->run(0.016)
	late := Node_CreateByTypeName(scene, "Node")
	late.name = "Late"
	late.position = {100, 100}
	game->run(0.016)
	game->run(0.016)
	testing.expect(t, c.target == late, "late target resolved")

	// Multi-target from Lua.
	a := Node_CreateByTypeName(scene, "Node")
	a.name = "A"
	a.position = {0, 0}
	b := Node_CreateByTypeName(scene, "Node")
	b.name = "B"
	b.position = {400, 200}
	game->run(0.016)
	L := game.scriptManager.L
	ok := lua.L_dostring(L, `
local a, b, late = Scene.find_node("A"), Scene.find_node("B"), Scene.find_node("Late")
Camera.set_target(nil)
Camera.add_target(a)
Camera.add_target(b, { weight = 1, radius = 80 })
n_two = #Camera.get_targets()
Camera.remove_target(a)
n_one = #Camera.get_targets()
Camera.add_target(a)
`) == 0
	testing.expect(t, ok, "Lua ran")
	lua.getglobal(L, "n_two")
	testing.expect_value(t, int(lua.tointeger(L, -1)), 2)
	lua.getglobal(L, "n_one")
	testing.expect_value(t, int(lua.tointeger(L, -1)), 1)
	lua.pop(L, 2)
	game->run(0.016)
	testing.expect(t, c.followMode == .MultiTarget && len(c.targets) == 2, "multi-target group")
	testing.expectf(t, abs(c.targetPosition.x - 200) < 1 && abs(c.targetPosition.y - 100) < 1, "frames the group's centre: %v", c.targetPosition)
	_ = lua.L_dostring(L, `Camera.clear_targets()`)
	testing.expect(t, len(c.targets) == 0 && c.target == nil && c.followMode == .Static, "cleared")
}

// #215: shake strength is pixels and plays the Shake Preset without
// overwriting the settings; Screen Offset, Max Distance and Zoom work.
@(test)
test_camera_shake_offset_distance_zoom :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("cam_215", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	cam := CameraNode_Create(scene, "Cam", true)
	ProcessNodeQueues(scene.manager, &game.gameContext)
	game.state = .Running
	game->run(0.016)

	// Custom: the node's settings, untouched by the shake.
	cam.shakeTypes, cam.shakeSpeed, cam.shakeIntensity = {.Horizontal}, 7, 3
	L := game.scriptManager.L
	testing.expect(t, lua.L_dostring(L, `Camera.shake(20, 1)`) == 0, "Lua ran")
	testing.expect_value(t, cam.activeShakeIntensity, 20)
	testing.expect_value(t, cam.activeShakeTypes, bit_set[CameraShakeType]{.Horizontal})
	testing.expect_value(t, cam.activeShakeSpeed, 7)
	testing.expect_value(t, cam.shakeIntensity, 3)
	maxOff: f32
	for _ in 0 ..< 30 {
		game->run(0.016)
		maxOff = max(maxOff, abs(cam.shakeOffset.x))
	}
	testing.expectf(t, maxOff > 5 && maxOff <= 20, "moves up to 20 px: %v", maxOff)
	testing.expect_value(t, cam.shakeOffset.y, 0)

	// No arguments: the preset.
	CameraNode_StopShake(cam)
	cam.shakePreset = .Explosion
	testing.expect(t, lua.L_dostring(L, `local c = Scene.find_node("Cam"); c:camera_shake()`) == 0, "Lua ran")
	testing.expect_value(t, cam.activeShakeIntensity, 25)
	testing.expect(t, .Zoom in cam.activeShakeTypes, "the preset's motions")
	testing.expect_value(t, cam.shakeTypes, bit_set[CameraShakeType]{.Horizontal})
	CameraNode_StopShake(cam)

	// Screen Offset applies when custom.
	cam.customScreenOffset, cam.screenOffset = true, {100, 50}
	testing.expect_value(t, CameraNode_GetCamera2D(cam).offset, [2]f32{100, 50})
	cam.customScreenOffset = false
	testing.expect_value(t, CameraNode_GetCamera2D(cam, 1280, 720).offset, [2]f32{640, 360})

	// Max Distance: never trails the target by more.
	cam.dragType, cam.smoothDrag, cam.smoothDragSpeed, cam.maxDistance = .SmoothDamp, true, {2, 2}, {40, 40}
	CameraNode_SetTargetPosition(cam, cam.currentPosition + {500, 0})
	game->run(0.016)
	testing.expectf(t, abs(cam.targetPosition.x - cam.currentPosition.x) <= 40.01, "within 40 px: %v vs %v", cam.currentPosition, cam.targetPosition)

	// Zoom isn't saved; Target Zoom is.
	cam.targetZoom, cam.zoom = 2, 5
	text := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expect(t, !strings.contains(text, `"zoom"`), "zoom not saved")
	testing.expect(t, strings.contains(text, `"targetZoom"`), "target zoom saved")
}
