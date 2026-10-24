package engine

import "core:math"
import "core:testing"
import lua "vendor:lua/5.4"

// Navigation regions and agents: a static body wall baked into a region,
// a path around it (and wider with a radius), a script-blocked gap making
// the target unreachable, an agent walking its parent there (events), two
// agents keeping apart, and the Lua methods.
@(test)
test_navigation_regions_and_agents :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("nav", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running

	// A 640 x 320 region; a wall from y 0 to 240 at x 300..340 (open below).
	region := cast(^NavigationRegionNode)Node_CreateByTypeName(scene, "NavigationRegionNode")
	region.name = "Nav"
	region.size = {640, 320}
	region.cellSize = 16
	wall := StaticBodyNode_Create(scene, "Wall")
	wall.position = {320, 120}
	StaticBodyNode_AddShape(wall, MakeBoxPhysicsShape(40, 240, {0, 0}, 0))
	ProcessNodeQueues(scene.manager, &game.gameContext)
	Node_SetGlobalPositions(scene.manager, scene.rootNode)
	NavRegion_Bake(region, &game.gameContext)
	testing.expect(t, len(scene.manager.navRegions) == 1 && region.cells == {40, 20}, "the region is listed and baked")
	g := Nav_GridFor(region)
	testing.expect(t, !Nav_Walkable(g, Nav_CellAt(g, {320, 100})) && Nav_Walkable(g, Nav_CellAt(g, {320, 300})), "the wall blocks, below it is open")

	// A path from the left to the right goes under the wall.
	path := Nav_FindPath(g, {100, 100}, {540, 100})
	testing.expect(t, path != nil, "a path")
	lowest: f32
	for p in path do lowest = max(lowest, p.y)
	testing.expectf(t, lowest > 240, "it goes under the wall (lowest %v)", lowest)
	// With a 20 px radius it keeps further from the wall's end.
	wide := Nav_FindPath(g, {100, 100}, {540, 100}, {diagonal = true, smooth = true, radius = 20})
	wl: f32
	for p in wide do wl = max(wl, p.y)
	testing.expectf(t, wide != nil && wl >= lowest, "the radius keeps it clear (%v vs %v)", wl, lowest)
	// Block the gap under the wall: unreachable.
	NavRegion_SetBlocked(region, {300, 240}, {340, 320}, true)
	testing.expect(t, Nav_FindPath(Nav_GridFor(region), {100, 100}, {540, 100}) == nil, "blocked: no way")
	NavRegion_Bake(region, &game.gameContext)
	testing.expect(t, Nav_FindPath(Nav_GridFor(region), {100, 100}, {540, 100}) == nil, "the script block survives a rebake")
	NavRegion_SetBlocked(region, {300, 240}, {340, 320}, false)
	testing.expect(t, Nav_FindPath(Nav_GridFor(region), {100, 100}, {540, 100}) != nil, "opened again")

	// An agent under a plain node walks there.
	walker := Node_CreateByTypeName(scene, "Node")
	walker.name = "Walker"
	walker.position = {100, 100}
	agent := cast(^NavigationAgentNode)Node_CreateByTypeName(scene, "NavigationAgentNode", walker)
	agent.speed = 400
	agent.radius = 8
	arrived := 0
	agent.onFinished->subscribe(proc(src: rawptr, v: EventValue, ctx: ^GameContext, ud: rawptr) {(cast(^int)ud)^ += 1}, &arrived)
	ProcessNodeQueues(scene.manager, &game.gameContext)
	NavAgent_SetTarget(agent, {540, 100})
	for _ in 0 ..< 240 do game->run(1.0 / 60)
	d := walker.globalPosition - [2]f32{540, 100}
	testing.expectf(t, math.sqrt(d.x * d.x + d.y * d.y) < 10 && arrived == 1, "arrived (%v), navigation_finished once", walker.globalPosition)

	// Two agents sent to the same spot keep apart.
	other := Node_CreateByTypeName(scene, "Node")
	other.position = {500, 280}
	agent2 := cast(^NavigationAgentNode)Node_CreateByTypeName(scene, "NavigationAgentNode", other)
	agent2.radius = 16
	agent.radius = 16
	ProcessNodeQueues(scene.manager, &game.gameContext)
	NavAgent_SetTarget(agent, {560, 280})
	NavAgent_SetTarget(agent2, {560, 280})
	for _ in 0 ..< 240 do game->run(1.0 / 60)
	gap := walker.globalPosition - other.globalPosition
	testing.expectf(t, math.sqrt(gap.x * gap.x + gap.y * gap.y) > 12, "they don't stack (%v)", math.sqrt(gap.x * gap.x + gap.y * gap.y))

	// Lua.
	L := game.scriptManager.L
	ok := lua.L_dostring(L, `
local nav = Scene.find_node("Nav")
local p = nav:nav_find_path(100, 100, 540, 100, {radius = 8})
n = p and #p or 0
open = nav:nav_is_walkable(100, 300)
nav:nav_set_blocked(0, 280, 64, 40, true)
closed = nav:nav_is_walkable(16, 300)
local a = Scene.find_node("Walker"):get_node("NavigationAgent")
a:nav_set_target(Vec2(100, 100))
waiting = a:nav_is_finished()
`)
	if ok != 0 do testing.fail_now(t, string(lua.tostring(L, -1)))
	geti :: proc(L: ^lua.State, n: cstring) -> int {lua.getglobal(L, n); defer lua.pop(L, 1); return int(lua.tointeger(L, -1))}
	getb :: proc(L: ^lua.State, n: cstring) -> bool {lua.getglobal(L, n); defer lua.pop(L, 1); return bool(lua.toboolean(L, -1))}
	testing.expect(t, geti(L, "n") >= 3, "nav_find_path on a region")
	testing.expect(t, getb(L, "open") && !getb(L, "closed") && !getb(L, "waiting"), "is_walkable / set_blocked / set_target")
	// Removing the region drops it from the list.
	RemoveNode(scene.manager, region)
	ProcessNodeQueues(scene.manager, &game.gameContext)
	testing.expect_value(t, len(scene.manager.navRegions), 0)
}
