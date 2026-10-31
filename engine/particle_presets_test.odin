package engine

import "core:testing"
import lua "lua54"

// #130: presets give an emitter a whole look, replacing the last one's.

@(test)
test_particle_presets :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("presets", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	pen := ParticleEmitterNode_Create(scene, "Fx")
	pen.gameContext = &game.gameContext
	ProcessNodeQueues(scene.manager, &game.gameContext)
	em := &pen.emitter

	// Every preset emits.
	for p in ParticlePreset {
		ParticleEmitter_ApplyPreset(em, p)
		for _ in 0 ..< 30 do game->run(1.0 / 60)
		testing.expectf(t, em.aliveCount > 0, "%v emits", p)
	}

	// Explosion is one burst; Fire after it is continuous again and keeps no
	// explosion damping (presets don't pile up).
	ParticleEmitter_ApplyPreset(em, .Explosion)
	testing.expect(t, !em.continuous && em.burst == 1, "explosion bursts once")
	ParticleEmitter_ApplyPreset(em, .Fire)
	testing.expect(t, em.continuous && em.burst == 0, "fire is continuous")
	testing.expect_value(t, em.damping, f32(0))
	testing.expect_value(t, em.blendMode, ParticleBlend.Additive)

	// A texture stays.
	em.shape = .Texture
	ParticleEmitter_ApplyPreset(em, .Smoke)
	testing.expect_value(t, em.shape, ParticleShape.Texture)

	// Lua, any case; unknown names are refused.
	L := game.scriptManager.L
	_ = lua.L_dostring(L, `fx = Scene.find_node("Fx"); ok1 = fx:particle_apply_preset("Snow"); ok2 = fx:particle_apply_preset("lava")`)
	lua.getglobal(L, "ok1")
	testing.expect(t, bool(lua.toboolean(L, -1)), "snow applied")
	lua.getglobal(L, "ok2")
	testing.expect(t, !bool(lua.toboolean(L, -1)), "lava refused")
	lua.pop(L, 2)
	testing.expect_value(t, em.wind, [2]f32{15, 0})

	_, known := ParticlePreset_Parse("EXPLOSION")
	testing.expect(t, known, "names parse in any case")
}
