package engine

import "core:math"
import "core:strings"
import "core:testing"
import lua "lua54"

// Paths: the bake (length, sampling by distance, closest point), Bézier
// handles bending it, followers stopping / looping / ping-ponging with
// their events, rotation, saving, the Lua methods, and a character riding a
// floor carried by a follower (moving platform).
@(test)
test_path_and_follow :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("path", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	game.physicsWorld.gravity = {0, 980}

	path := cast(^PathNode)Node_CreateByTypeName(scene, "PathNode")
	path.name = "Route"
	path.position = {100, 100}
	clear(&path.points)
	append(&path.points, Path_Point{pos = {0, 0}}, Path_Point{pos = {300, 0}}, Path_Point{pos = {300, 100}})
	ProcessNodeQueues(scene.manager, &game.gameContext)
	Node_SetGlobalPositions(scene.manager, scene.rootNode)
	near :: proc(a, b: f32, eps: f32 = 0.6) -> bool {return abs(a - b) <= eps}
	testing.expect(t, near(PathNode_Length(path), 400), "straight segments: 300 + 100")
	p, d := PathNode_SampleLocal(path, 150)
	testing.expect(t, near(p.x, 150) && near(p.y, 0) && d == {1, 0}, "halfway along the first segment")
	p, d = PathNode_SampleLocal(path, 350)
	testing.expect(t, near(p.x, 300) && near(p.y, 50) && near(d.y, 1, 0.01), "down the second")
	testing.expect(t, near(PathNode_ClosestOffset(path, {250 + 100, -40 + 100}), 250), "closest: above x=250")
	// A handle bends it: longer than the straight line, still ends at the point.
	path.points[0].out = {0, -150}
	testing.expect(t, PathNode_Length(path) > 420, "re-baked after the edit, curved")
	end, _ := PathNode_SampleLocal(path, 99999)
	testing.expect(t, near(end.x, 300) && near(end.y, 100), "clamped to the end")
	path.points[0].out = {}

	// A follower: stop at the end (event), loop, ping-pong.
	f := cast(^PathFollowNode)Node_CreateByTypeName(scene, "PathFollowNode", path)
	{
		pp, pok := Node_FindProperty(f, "progress")
		testing.expect(t, pok && pp.kind == .Float, "progress is a property")
	}
	f.speed = 200
	f.loop = .Stop
	finished := 0
	f.onFinished->subscribe(proc(src: rawptr, v: EventValue, ctx: ^GameContext, ud: rawptr) {(cast(^int)ud)^ += 1}, &finished)
	ProcessNodeQueues(scene.manager, &game.gameContext)
	for _ in 0 ..< 60 do game->run(1.0 / 60) // 200 px
	testing.expect(t, near(f.progress, 200, 4) && near(f.position.x, 200, 4) && near(f.rotation, 0, 0.01), "travelled 200 px facing right")
	for _ in 0 ..< 120 do game->run(1.0 / 60)
	testing.expect(t, f.finished && near(f.progress, 400) && finished == 1, "stopped at the end, path_finished once")
	testing.expect(t, near(f.rotation, 90, 0.5), "facing down the last segment")
	f.loop, f.finished, f.progress = .Loop, false, 398
	game->run(1.0 / 60)
	testing.expect(t, f.progress < 20, "looped round")
	f.loop, f.progress, f.direction = .PingPong, 399, 1
	game->run(1.0 / 60)
	testing.expect(t, f.direction == -1 && f.progress < 400, "turned back")
	testing.expect(t, near(f.rotation, -90, 0.5), "facing back up")

	// Saved with its handles; read back.
	path.points[1].in_ = {-20, 5}
	json := Scene_SerializeToJSON(scene)
	defer delete(json)
	testing.expect(t, strings.contains(json, `"points": [[0, 0, 0, 0, 0, 0], [300, 0, -20, 5, 0, 0]`) && strings.contains(json, `"loop": "PingPong"`), json)
	one := Node_SerializeToJSON(path, scene.manager, context.temp_allocator)
	back := cast(^PathNode)Scene_InstantiateNodeFromJSON(scene, transmute([]u8)one, nil, &game.gameContext)
	testing.expect(t, back != nil && len(back.points) == 3 && back.points[1].in_ == {-20, 5}, "read back with its handles")
	if back != nil do RemoveNode(scene.manager, back)
	path.points[1].in_ = {}

	// Lua.
	L := game.scriptManager.L
	r := lua.L_dostring(L, `
local route = Scene.find_node("Route")
len = route:path_length()
local pos, dir = route:path_point_at(150)
px, py = pos.x, pos.y
route:path_add_point(Vec2(400, 100))
count = route:path_point_count()
`)
	if r != 0 do testing.fail_now(t, string(lua.tostring(L, -1)))
	getn :: proc(L: ^lua.State, n: cstring) -> f64 {lua.getglobal(L, n); defer lua.pop(L, 1); return f64(lua.tonumber(L, -1))}
	testing.expect(t, math.abs(getn(L, "len") - 400) < 1 && math.abs(getn(L, "px") - 250) < 1 && math.abs(getn(L, "py") - 100) < 1, "path_length / path_point_at (world)")
	testing.expect_value(t, getn(L, "count"), 4)

	// Moving platform: a floor under a follower carries a character on it.
	rail := cast(^PathNode)Node_CreateByTypeName(scene, "PathNode")
	rail.position = {1000, 500}
	clear(&rail.points)
	append(&rail.points, Path_Point{pos = {0, 0}}, Path_Point{pos = {600, 0}})
	carrier := cast(^PathFollowNode)Node_CreateByTypeName(scene, "PathFollowNode", rail)
	carrier.rotate = false
	floor := StaticBodyNode_Create(scene, "Platform", carrier)
	floor.position = {} // on the carrier
	floor.gameContext = &game.gameContext
	StaticBodyNode_AddShape(floor, MakeBoxPhysicsShape(200, 20, {0, 0}, 0), &game.gameContext)
	mover := CharacterMoverNode_Create(scene, "Rider")
	mover.position = {1000, 440}
	mover.enableKeyboardInput = false
	mover.gameContext = &game.gameContext
	ProcessNodeQueues(scene.manager, &game.gameContext)
	for _ in 0 ..< 60 do game->run(1.0 / 60) // lands on the platform
	testing.expectf(t, mover.isOnFloor && mover.floorNode == floor, "standing on the platform (y=%v)", mover.position.y)
	x0 := mover.position.x
	carrier.speed = 120
	for _ in 0 ..< 60 do game->run(1.0 / 60) // the platform moves ~120 px
	testing.expectf(t, mover.position.x - x0 > 90, "carried with the platform (%v -> %v)", x0, mover.position.x)
	testing.expect(t, mover.isOnFloor, "still on it")
}
