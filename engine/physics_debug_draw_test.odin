package engine

import "core:strings"
import "core:testing"
import lua "lua54"

// The project's Show Colliders setting (physics.debug_draw): on by default,
// read, saved; scripts switch it with Physics.set_debug_draw.
@(test)
test_physics_debug_draw_setting :: proc(t: ^testing.T) {
	cfg, ok := Project_ParseConfig(transmute([]u8)string(`{"name": "x", "initial_scene": "a.scene.json"}`))
	testing.expect(t, ok && cfg.debugDraw, "on by default")
	ProjectConfig_Destroy(&cfg)

	cfg, ok = Project_ParseConfig(transmute([]u8)string(`{"name": "x", "initial_scene": "a.scene.json", "physics": {"gravity": [0, 10], "debug_draw": false}}`))
	testing.expect(t, ok && !cfg.debugDraw, "read")
	text := Project_SerializeToJSON(&cfg, context.temp_allocator)
	testing.expect(t, strings.contains(text, `"debug_draw": false`), "saved")
	cfg2, ok2 := Project_ParseConfig(transmute([]u8)text)
	testing.expect(t, ok2 && !cfg2.debugDraw && cfg2.gravity == {0, 10}, "round trip")
	ProjectConfig_Destroy(&cfg2)
	ProjectConfig_Destroy(&cfg)

	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	L := game.scriptManager.L
	testing.expect_value(t, lua.L_dostring(L, `Physics.set_debug_draw(false); dd = Physics.get_debug_draw()`), i32(0))
	testing.expect(t, !game.physicsWorld.drawPhysicsDebug, "off from Lua")
	lua.getglobal(L, "dd")
	testing.expect(t, !bool(lua.toboolean(L, -1)), "get")
	lua.pop(L, 1)
}
