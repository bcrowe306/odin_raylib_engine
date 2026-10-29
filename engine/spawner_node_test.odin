package engine

import "core:fmt"
import "core:math"
import os "osx"
import "core:strings"
import "core:testing"
import lua "lua54"

// SpawnerNode (spawner_node.odin): modes, where spawned nodes go (the
// spawner's world transform through a rotated / flipped parent), limits,
// cooldown, events, auto spawn, saving, Lua and signal connections.

@(private = "file")
SPAWNER_DIR :: "test_spawner_project"

@(private = "file")
spawner_test_game :: proc() -> (^Game, ^Scene) {
	_ = os.make_directory_all(SPAWNER_DIR + "/components")
	for name in ([]string{"a", "b", "c"}) {
		path := fmt.tprintf("%s/components/%s.component.json", SPAWNER_DIR, name)
		_ = os.write_entire_file(path, transmute([]u8)fmt.tprintf(`{{"type": "Node", "name": "%s"}}`, strings.to_upper(name, context.temp_allocator)))
	}
	_ = os.write_entire_file(SPAWNER_DIR + "/components/ball.component.json", transmute([]u8)string(`{"type": "DynamicBodyNode", "name": "Ball"}`))
	game := new(Game)
	InitializeGame(game)
	AssetManager_SetProjectDir(&game.assetManager, SPAWNER_DIR)
	scene := game->createScene("spawn", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	return game, scene
}

// The names of the spawned roots under `parent`, in order (A, B, ...).
@(private = "file")
spawned_names :: proc(scene: ^Scene, parent: ^Node) -> string {
	ProcessNodeQueues(scene.manager, scene.rootNode.gameContext)
	names := make([dynamic]string, context.temp_allocator)
	for c in GetChildrenView(scene.manager, parent) do if c != nil && !c.removing && len(c.name) == 1 do append(&names, c.name)
	return strings.join(names[:], "", context.temp_allocator)
}

@(private = "file")
clear_spawned :: proc(scene: ^Scene, parent: ^Node) {
	for c in GetChildrenTemp(scene.manager, parent) do if c != nil && len(c.name) == 1 do RemoveNode(scene.manager, c)
	ProcessNodeQueues(scene.manager, scene.rootNode.gameContext)
}

@(private = "file")
spawner_with_abc :: proc(scene: ^Scene, ctx: ^GameContext, parent: ^Node = nil) -> ^SpawnerNode {
	s := cast(^SpawnerNode)Node_CreateByTypeName(scene, "SpawnerNode", parent)
	s.gameContext = ctx
	for name in ([]string{"a", "b", "c"}) do SpawnerNode_AddEntry(s, fmt.tprintf("components/%s.component.json", name))
	ProcessNodeQueues(scene.manager, ctx)
	return s
}

@(test)
test_spawner_modes :: proc(t: ^testing.T) {
	game, scene := spawner_test_game()
	defer os.remove_all(SPAWNER_DIR)
	defer game->terminate()
	ctx := &game.gameContext
	root := scene.rootNode
	s := spawner_with_abc(scene, ctx)

	// Single: the first entry; index: that one.
	SpawnerNode_Spawn(s, ctx)
	SpawnerNode_Spawn(s, ctx, 2)
	testing.expect_value(t, spawned_names(scene, root), "AC")
	clear_spawned(scene, root)

	// All, with a burst count of 2.
	s.mode, s.count = .All, 2
	testing.expect_value(t, len(SpawnerNode_Spawn(s, ctx)), 6)
	testing.expect_value(t, spawned_names(scene, root), "ABCABC")
	clear_spawned(scene, root)
	s.count = 1

	// Sequential: loop, ping-pong, stop (list_finished, then nothing).
	s.mode = .Sequential
	for _ in 0 ..< 4 do SpawnerNode_Spawn(s, ctx)
	testing.expect_value(t, spawned_names(scene, root), "ABCA")
	clear_spawned(scene, root)
	SpawnerNode_Reset(s)
	s.sequenceEnd = .Ping_Pong
	for _ in 0 ..< 6 do SpawnerNode_Spawn(s, ctx)
	testing.expect_value(t, spawned_names(scene, root), "ABCBAB")
	clear_spawned(scene, root)
	SpawnerNode_Reset(s)
	s.sequenceEnd = .Stop
	finished := 0
	Subscribe(&s.onFinished, proc(source: rawptr, value: EventValue, ctx: ^GameContext, ud: rawptr) {(cast(^int)ud)^ += 1}, &finished)
	for _ in 0 ..< 5 do SpawnerNode_Spawn(s, ctx)
	testing.expect_value(t, spawned_names(scene, root), "ABC")
	testing.expect_value(t, finished, 1)
	SpawnerNode_Reset(s)
	testing.expect_value(t, len(SpawnerNode_Spawn(s, ctx)), 1) // (started over)
	clear_spawned(scene, root)

	// Shuffle: each entry once before any repeats.
	s.mode = .Shuffle
	for _ in 0 ..< 3 do SpawnerNode_Spawn(s, ctx)
	got := spawned_names(scene, root)
	testing.expectf(t, len(got) == 3 && strings.contains(got, "A") && strings.contains(got, "B") && strings.contains(got, "C"), "one round: %s", got)
	clear_spawned(scene, root)

	// Random by weight: only C can come up.
	s.mode = .Random
	s.entries[0].weight, s.entries[1].weight, s.entries[2].weight = 0, 0, 1
	for _ in 0 ..< 5 do SpawnerNode_Spawn(s, ctx)
	testing.expect_value(t, spawned_names(scene, root), "CCCCC")
	clear_spawned(scene, root)

	// Chance 0: never.
	s.chance = 0
	testing.expect_value(t, len(SpawnerNode_Spawn(s, ctx)), 0)
}

@(test)
test_spawner_limits_and_events :: proc(t: ^testing.T) {
	game, scene := spawner_test_game()
	defer os.remove_all(SPAWNER_DIR)
	defer game->terminate()
	ctx := &game.gameContext
	root := scene.rootNode
	s := spawner_with_abc(scene, ctx)

	// Max alive: waits until one is gone.
	s.maxAlive = 2
	for _ in 0 ..< 3 do SpawnerNode_Spawn(s, ctx)
	testing.expect_value(t, spawned_names(scene, root), "AA")
	testing.expect_value(t, SpawnerNode_AliveCount(s), 2)
	for c in GetChildrenTemp(scene.manager, root) do if c.name == "A" {RemoveNode(scene.manager, c); break}
	ProcessNodeQueues(scene.manager, ctx)
	testing.expect_value(t, SpawnerNode_AliveCount(s), 1)
	testing.expect_value(t, len(SpawnerNode_Spawn(s, ctx)), 1)
	clear_spawned(scene, root)
	s.maxAlive = 0

	// Total limit: limit_reached once it's hit, then nothing.
	SpawnerNode_Reset(s)
	s.totalLimit = 2
	limits := 0
	Subscribe(&s.onLimit, proc(source: rawptr, value: EventValue, ctx: ^GameContext, ud: rawptr) {(cast(^int)ud)^ += 1}, &limits)
	spawnedNames := make([dynamic]string, context.temp_allocator)
	Subscribe(&s.onSpawned, proc(source: rawptr, value: EventValue, ctx: ^GameContext, ud: rawptr) {
		if n, ok := value.(^Node); ok do append(cast(^[dynamic]string)ud, strings.clone(n.name, context.temp_allocator))
	}, &spawnedNames)
	for _ in 0 ..< 4 do SpawnerNode_Spawn(s, ctx)
	testing.expect_value(t, spawned_names(scene, root), "AA")
	testing.expect(t, limits >= 1, "limit_reached")
	testing.expect_value(t, s.spawnedTotal, 2)
	testing.expectf(t, strings.join(spawnedNames[:], ",", context.temp_allocator) == "A,A", "spawned events: %v", spawnedNames)
	clear_spawned(scene, root)
	s.totalLimit = 0

	// Cooldown: held back until it passes (the update counts it down).
	s.cooldown = 0.5
	testing.expect_value(t, len(SpawnerNode_Spawn(s, ctx)), 1)
	testing.expect_value(t, len(SpawnerNode_Spawn(s, ctx)), 0)
	SpawnerNode_Update(s, ctx, 0.6)
	testing.expect_value(t, len(SpawnerNode_Spawn(s, ctx)), 1)
	clear_spawned(scene, root)
	s.cooldown = 0

	// Auto spawn: after the start delay, every interval.
	SpawnerNode_Reset(s) // (the cooldown left from above)
	s.autoSpawn, s.startDelay, s.interval = true, 0.2, 0.5
	SpawnerNode_Update(s, ctx, 0.1)
	testing.expect_value(t, spawned_names(scene, root), "")
	SpawnerNode_Update(s, ctx, 0.15) // 0.25: the first
	SpawnerNode_Update(s, ctx, 0.3)  // 0.55
	SpawnerNode_Update(s, ctx, 0.2)  // 0.75: the second
	testing.expect_value(t, spawned_names(scene, root), "AA")
}

@(test)
test_spawner_placement :: proc(t: ^testing.T) {
	game, scene := spawner_test_game()
	defer os.remove_all(SPAWNER_DIR)
	defer game->terminate()
	ctx := &game.gameContext
	root := scene.rootNode
	near :: proc(a, b: [2]f32) -> bool {return math.abs(a.x - b.x) < 0.01 && math.abs(a.y - b.y) < 0.01}

	// A player at (100, 50) turned 90°; the spawner 20 px ahead of it with a
	// 10 px offset: the spawn point is (100, 80), facing down.
	player := Node_CreateByTypeName(scene, "Node")
	player.name = "Player"
	player.position, player.rotation = {100, 50}, 90
	s := spawner_with_abc(scene, ctx, player)
	s.position, s.offset = {20, 0}, {10, 0}
	n := SpawnerNode_Spawn(s, ctx)[0]
	testing.expect(t, GetParent(scene.manager, n) == root, "spawned under the scene's root")
	testing.expectf(t, near(n.position, {100, 80}) && math.abs(n.rotation - 90) < 0.01, "at the spawn point, turned: %v %v", n.position, n.rotation)
	s.inheritRotation = false
	n = SpawnerNode_Spawn(s, ctx)[0]
	testing.expect_value(t, n.rotation, 0)
	s.inheritRotation = true

	// Under the spawner's parent: the same world place, in its space.
	s.parentMode = .Spawner_Parent
	n = SpawnerNode_Spawn(s, ctx)[0]
	testing.expect(t, GetParent(scene.manager, n) == player, "under the player")
	testing.expectf(t, near(n.position, {30, 0}) && math.abs(n.rotation) < 0.01, "local to the player: %v %v", n.position, n.rotation)
	s.parentMode = .Scene_Root

	// Flipped (the player faces left): a body flies left at `speed`, flipped
	// too with inheritScale.
	player.rotation = 0
	player.scale = {-1, 1}
	SpawnerNode_RemoveEntry(s, 0)
	SpawnerNode_RemoveEntry(s, 0)
	SpawnerNode_RemoveEntry(s, 0)
	SpawnerNode_AddEntry(s, "components/ball.component.json")
	s.speed, s.inheritScale = 300, true
	ball := SpawnerNode_Spawn(s, ctx)[0]
	testing.expect(t, ball.typeId == DynamicBodyNode, "a body")
	testing.expectf(t, near(ball.position, {70, 50}) && ball.scale.x < 0, "flipped: %v %v", ball.position, ball.scale)
	testing.expectf(t, near((cast(^DynamicBodyNode)ball).linearVelocity, {-300, 0}), "flies left: %v", (cast(^DynamicBodyNode)ball).linearVelocity)
}

@(test)
test_spawner_save_lua_signals :: proc(t: ^testing.T) {
	game, scene := spawner_test_game()
	defer os.remove_all(SPAWNER_DIR)
	defer game->terminate()
	ctx := &game.gameContext
	root := scene.rootNode
	s := spawner_with_abc(scene, ctx)
	s.name = "Gun"
	s.mode = .Sequential
	s.entries[1].weight, s.entries[1].count, s.entries[1].offset = 2.5, 3, {4, -5}

	// Saved and read back.
	text := Scene_SerializeToJSON(scene, context.temp_allocator)
	testing.expectf(t, strings.contains(text, `"spawner": {"entries": [{"component": "components/a.component.json"`), "saved: %s", text)
	s2 := game->createScene("spawn2", false)
	Scene_InstantiateFromJSON(s2, transmute([]u8)text, ctx)
	ProcessNodeQueues(s2.manager, ctx)
	back := cast(^SpawnerNode)Scene_FindNodeByName(s2, "Gun")
	testing.expect(t, back != nil && back.mode == .Sequential && len(back.entries) == 3, "read back")
	if back != nil && len(back.entries) == 3 {
		en := back.entries[1]
		testing.expect(t, en.component == "components/b.component.json" && en.weight == 2.5 && en.count == 3 && en.offset == {4, -5}, "the entry")
	}

	// Lua.
	L := game.scriptManager.L
	ok := lua.L_dostring(L, `
local gun = Scene.find_node("Gun")
local made = gun:spawn()
first = made[1]:get_name()
gun:spawn(3)
alive = gun:spawn_alive_count()
entries = #gun:spawn_entries()
gun:spawn_add("components/a.component.json", 1, 1)
entries2 = #gun:spawn_entries()
gun:spawn_remove(4)
gun:spawn_reset()
`)
	testing.expectf(t, ok == 0, "lua: %s", lua.tostring(L, -1) if ok != 0 else "")
	gets :: proc(L: ^lua.State, name: cstring) -> string {
		lua.getglobal(L, name)
		defer lua.pop(L, 1)
		return strings.clone(string(lua.tostring(L, -1)), context.temp_allocator)
	}
	testing.expect_value(t, gets(L, "first"), "A")
	testing.expect_value(t, gets(L, "alive"), "2")
	testing.expect_value(t, gets(L, "entries"), "3")
	testing.expect_value(t, gets(L, "entries2"), "4")
	testing.expect_value(t, len(s.entries), 3)
	testing.expect_value(t, s.spawnedTotal, 0) // (reset)
	clear_spawned(scene, root)

	// A signal connected to the spawner's spawn (no script): a timer fires it.
	timer := cast(^TimerNode)Node_CreateByTypeName(scene, "TimerNode")
	timer.name = "Clock"
	timer.gameContext = ctx
	ProcessNodeQueues(scene.manager, ctx)
	testing.expect(t, Node_AddConnection(timer, "timeout", Node_RelativePath(scene.manager, timer, s), "spawn"), "connected")
	timer->setDuration(0.05)
	timer.running = true
	game->run(0.016)
	game->run(0.06)
	testing.expectf(t, spawned_names(scene, root) == "A", "the timer spawned: %s", spawned_names(scene, root))
}
