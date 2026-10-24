package engine

import "core:math"
import "core:testing"
import lua "lua54"

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
sine :: proc(buf: []f32, hz: f32) {
	for i in 0 ..< len(buf) / 2 {
		v := math.sin(2 * math.PI * hz * f32(i) / f32(MIXER_RATE))
		buf[i * 2] = v
		buf[i * 2 + 1] = v
	}
}

// The sound mixing pieces that need no audio device: spatialization, the
// mixer's effects (a low-pass cuts highs, reverb leaves a tail) and the
// master low-pass / reverb Lua calls (effects on the Master bus).
@(test)
test_audio_mixing :: proc(t: ^testing.T) {
	defer Mixer_Shutdown()
	v, p := Audio_Spatialize({0, 0}, {0, 0}, 100, 900, 450)
	testing.expect(t, v == 1 && p == 0.5, "at the listener")
	v, p = Audio_Spatialize({1000, 0}, {0, 0}, 100, 900, 450)
	testing.expect(t, v == 0 && p == 0, "far right")
	v, p = Audio_Spatialize({-300, 0}, {0, 0}, 100, 900, 450)
	testing.expectf(t, v > 0.4 && v < 0.8 && p > 0.8, "left, part volume: %v %v", v, p)

	// A low-pass at 2 kHz: 200 Hz passes, 12 kHz is cut.
	low := make([]f32, 9600, context.temp_allocator)
	high := make([]f32, 9600, context.temp_allocator)
	sine(low, 200)
	sine(high, 12000)
	lp: Mixer_Effect
	Effect_Init(&lp, .Lowpass, MIXER_RATE)
	lp.params[0] = 2000
	Effect_Process(&lp, low, MIXER_RATE)
	Effect_Clear(&lp)
	Effect_Process(&lp, high, MIXER_RATE)
	Effect_Free(&lp)
	testing.expectf(t, rms(low, 2000) > 0.6, "200 Hz kept: %v", rms(low, 2000))
	testing.expectf(t, rms(high, 2000) < 0.2, "12 kHz cut: %v", rms(high, 2000))

	// Reverb: an impulse leaves a tail.
	imp := make([]f32, 16000, context.temp_allocator)
	imp[0], imp[1] = 1, 1
	rv: Mixer_Effect
	Effect_Init(&rv, .Reverb, MIXER_RATE)
	Effect_Process(&rv, imp, MIXER_RATE)
	Effect_Free(&rv)
	testing.expectf(t, rms(imp, 4000) > 0.0005, "reverb tail: %v", rms(imp, 4000))

	// The Lua master effects are Master bus effects.
	Mixer_Init()
	Audio_SetLowpass(800)
	Audio_SetReverb(0.4, 0.7)
	master := Mixer_Buses()[0]
	testing.expect(t, len(master.effects) == 2 && master.effects[0].type == .Lowpass && master.effects[0].params[0] == 800 && master.effects[1].type == .Reverb && master.effects[1].params[2] == 0.4, "on Master")
	Audio_SetLowpass(0)
	testing.expect(t, !Mixer_Buses()[0].effects[0].enabled, "0 Hz: bypassed")
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
	// The Music bus fader (applied in the mixer, not to the node's volume).
	testing.expectf(t, abs(Mixer_Buses()[Mixer_BusIndex("Music")].volume - 0.25) < 0.001 && MusicNode_EffectiveVolume(b) == 1, "the Music fader: %v", Mixer_Buses()[Mixer_BusIndex("Music")].volume)
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
