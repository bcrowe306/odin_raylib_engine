package engine

import "core:fmt"
import "core:strings"
import "core:testing"
import lua "lua54"

// #128: emit(n) bursts, restart, the finished event, prewarm, seed,
// visibility (the view culling), and their Lua API.

@(private = "file")
control_game :: proc(name: string) -> (^Game, ^Scene, ^ParticleEmitterNode) {
	game := new(Game)
	InitializeGame(game)
	scene := game->createScene(name, true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	pen := ParticleEmitterNode_Create(scene, "Fx")
	pen.position = {100, 100}
	pen.gameContext = &game.gameContext
	ProcessNodeQueues(scene.manager, &game.gameContext)
	Node_SetGlobalPositions(scene.manager, scene.rootNode)
	return game, scene, pen
}

@(private = "file")
lua_text :: proc(L: ^lua.State, expr: string) -> string {
	_ = lua.L_dostring(L, strings.clone_to_cstring(fmt.tprintf("return tostring(%s)", expr), context.temp_allocator))
	defer lua.pop(L, 1)
	return strings.clone(string(lua.tostring(L, -1)), context.temp_allocator)
}

@(test)
test_particle_burst_finished_restart :: proc(t: ^testing.T) {
	ScriptVFS_RegisterEmbedded("particle_control.lua", `
local P = {}
function P:on_finished() finished = (finished or 0) + 1 end
return P
`)
	game, scene, pen := control_game("burst")
	defer game->terminate()
	Script_AttachToNode(pen, "particle_control.lua", nil, &game.scriptManager)
	ProcessNodeQueues(scene.manager, &game.gameContext)
	L := game.scriptManager.L
	ParticleEmitterNode_Stop(pen) // (not emitting: only the bursts)
	pen.emitter.lifetime = 0.5

	// emit(12) from Lua, then they live and die: finished once.
	_ = lua.L_dostring(L, `fx = Scene.find_node("Fx"); fx:particle_emit(12)`)
	game->run(1.0 / 60)
	testing.expect_value(t, lua_text(L, "fx:particle_get_alive_count()"), "12")
	for _ in 0 ..< 60 do game->run(1.0 / 60)
	testing.expect_value(t, lua_text(L, "fx:particle_get_alive_count()"), "0")
	testing.expect_value(t, lua_text(L, "finished"), "1")
	for _ in 0 ..< 30 do game->run(1.0 / 60)
	testing.expect_value(t, lua_text(L, "finished"), "1") // (once)

	// restart: emitting again from scratch.
	_ = lua.L_dostring(L, `fx:particle_restart()`)
	testing.expect(t, pen.emitter.emitting, "emitting again")
	game->run(1.0 / 60)
	testing.expect(t, pen.emitter.aliveCount > 0, "particles again")
}

@(test)
test_particle_prewarm :: proc(t: ^testing.T) {
	game, _, pen := control_game("prewarm")
	defer game->terminate()
	pen.emitter.prewarm, pen.emitter.lifetime = true, 2
	ParticleEmitterNode_Update(pen, &game.gameContext, 1.0 / 60)
	oldest: f32
	for p in pen.emitter.particles do if p.alive do oldest = max(oldest, p.age)
	testing.expectf(t, pen.emitter.aliveCount > 20 && oldest > 1, "already running on the first frame: %v alive, oldest %v s", pen.emitter.aliveCount, oldest)
}

@(test)
test_particle_seed :: proc(t: ^testing.T) {
	positions :: proc(seed: int) -> [8][2]f32 {
		e: ParticleEmitter
		ParticleEmitter_Init(&e)
		defer ParticleEmitter_Destroy(&e)
		e.seed, e.spread = seed, {100, 100}
		ParticleEmitter_Start(&e)
		out: [8][2]f32
		for i in 0 ..< 8 {
			ParticleEmitter_Emit(&e)
			out[i] = e.particles[i].position
		}
		return out
	}
	testing.expect(t, positions(42) == positions(42), "the same seed: the same pattern")
	testing.expect(t, positions(42) != positions(7), "another seed: another pattern")
	testing.expect(t, positions(0) != positions(0), "0: random each time")
}

@(test)
test_particle_visibility :: proc(t: ^testing.T) {
	game, _, pen := control_game("visibility")
	defer game->terminate()
	pen.emitter.velocity, pen.emitter.gravityVelocity = 0, 0
	ParticleEmitterNode_EmitBurst(pen, 5)
	// Auto: where the particles are (around 100, 100).
	r, ok := Node_RenderBounds(pen)
	testing.expect(t, ok, "has bounds")
	testing.expectf(t, r.x < 100 && r.x + r.width > 100 && r.y < 100 && r.y + r.height > 100, "around the particles: %v", r)
	Render_SetView({1000, 1000, 100, 100})
	testing.expect(t, !Render_IsVisible(r), "culled when the view is elsewhere")
	Render_SetView({50, 50, 100, 100})
	testing.expect(t, Render_IsVisible(r), "drawn when it's in view")
	Render_ClearView()
	// Manual: the rect around the emitter.
	pen.emitter.autoVisibility = false
	pen.emitter.visibilityRect = {-10, -20, 20, 40}
	r, _ = Node_RenderBounds(pen)
	testing.expect(t, r == {90, 80, 20, 40}, "the manual rect around the emitter")
}
