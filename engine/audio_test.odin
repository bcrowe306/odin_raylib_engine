package engine

import "core:math"
import "core:testing"
import lua "vendor:lua/5.4"

@(private = "file")
rms :: proc(s: []f32, from: int) -> f32 {
	sum: f32
	n := 0
	for i := from; i < len(s); i += 1 {
		sum += s[i] * s[i]
		n += 1
	}
	return math.sqrt(sum / f32(max(n, 1)))
}

@(private = "file")
sine :: proc(hz: f32, frames: int) -> []f32 {
	out := make([]f32, frames * 2, context.temp_allocator)
	for i in 0 ..< frames {
		v := math.sin(2 * math.PI * hz * f32(i) / AUDIO_SAMPLE_RATE)
		out[i * 2], out[i * 2 + 1] = v, v
	}
	return out
}

@(test)
test_audio_mixing :: proc(t: ^testing.T) {
	// Positional: full at the listener, silent past maxDistance, panned by side
	// (raylib: 1 = left, 0 = right).
	v, p := Audio_Spatialize({0, 0}, {0, 0}, 100, 900, 450)
	testing.expect(t, v == 1 && p == 0.5, "at the listener")
	v, p = Audio_Spatialize({1000, 0}, {0, 0}, 100, 900, 450)
	testing.expect(t, v == 0 && p == 0, "far right")
	v, p = Audio_Spatialize({-300, 0}, {0, 0}, 100, 900, 450)
	testing.expectf(t, v > 0.4 && v < 0.8 && p > 0.8, "left, part volume: %v %v", v, p)

	// Low-pass at 2 kHz: 200 Hz passes, 12 kHz is cut.
	Audio_ResetEffects()
	low := sine(200, 4800)
	Audio_ProcessEffects(low, {lowpassHz = 2000})
	Audio_ResetEffects()
	high := sine(12000, 4800)
	Audio_ProcessEffects(high, {lowpassHz = 2000})
	testing.expectf(t, rms(low, 2000) > 0.6, "200 Hz kept: %v", rms(low, 2000))
	testing.expectf(t, rms(high, 2000) < 0.2, "12 kHz cut: %v", rms(high, 2000))

	// Reverb: an impulse leaves a tail; mix 0 changes nothing.
	Audio_ResetEffects()
	Audio_SetReverb(0, 0) // buffers allocated on the main thread before use
	imp := make([]f32, 16000, context.temp_allocator)
	imp[0], imp[1] = 1, 1
	dry := make([]f32, len(imp), context.temp_allocator)
	copy(dry, imp)
	Audio_ProcessEffects(dry, {})
	testing.expect(t, dry[0] == 1 && rms(dry, 2) == 0, "no effects: passthrough")
	Audio_SetReverb(0.5, 0.6)
	Audio_ProcessEffects(imp, Audio_GetEffects())
	testing.expectf(t, rms(imp, 4000) > 0.0005, "reverb tail: %v", rms(imp, 4000))
	Audio_ResetEffects()
}

@(test)
test_music_fades_and_buses :: proc(t: ^testing.T) {
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("audio", true)
	ProcessSceneChange(&game.sceneManager, &game.gameContext)
	game.state = .Running
	a := cast(^MusicNode)Node_CreateByTypeName(scene, "MusicNode")
	a.name = "A"
	b := cast(^MusicNode)Node_CreateByTypeName(scene, "MusicNode")
	b.name = "B"
	game->run(0.016)

	// Fade in from silence (starts the track).
	MusicNode_FadeTo(a, 1, 1)
	testing.expect(t, a.isPlaying && a.fadeVolume == 0, "fade-in starts at 0")
	game->run(0.5)
	testing.expectf(t, abs(a.fadeVolume - 0.5) < 0.05, "half-way: %v", a.fadeVolume)
	game->run(0.6)
	testing.expect_value(t, a.fadeVolume, 1)

	// Crossfade A -> B: A stops when silent, B ends at full volume.
	MusicNode_Crossfade(a, b, 0.4)
	game->run(0.2)
	testing.expect(t, a.isPlaying && b.isPlaying && a.fadeVolume < 0.6 && b.fadeVolume > 0.4, "both playing mid-fade")
	game->run(0.3)
	testing.expect(t, !a.isPlaying && b.isPlaying && b.fadeVolume == 1, "A stopped, B full")

	// Buses, also from Lua.
	Game_SetBusVolume(game, .Music, 0.25)
	testing.expect_value(t, game.musicVolume, 0.25)
	testing.expectf(t, abs(MusicNode_EffectiveVolume(b) - 0.25) < 0.001, "bus applies: %v", MusicNode_EffectiveVolume(b))
	L := game.scriptManager.L
	ok := lua.L_dostring(L, `
Audio.set_bus_volume("sfx", 0.5)
sfx = Audio.get_bus_volume("sfx")
Audio.set_lowpass(0)
Audio.set_reverb(0)
local m = Scene.find_node("A")
m:music_fade(0.8, 0.1)
`)
	testing.expect(t, ok == 0, "lua ran")
	lua.getglobal(L, "sfx")
	testing.expect_value(t, f32(lua.tonumber(L, -1)), 0.5)
	lua.pop(L, 1)
	testing.expect(t, a.isPlaying && a.fadeTarget == 0.8, "music_fade from Lua")
}
