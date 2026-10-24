package engine

import "core:fmt"
import "core:math"
import "core:strings"
import "core:testing"

// The mixer without an audio device (Mixer_Render): voices into buses,
// faders and pan, mute / solo, routing a bus into another, ended voices,
// pitch, effects on a bus, meters, stopping by owner, and the project JSON.
@(test)
test_mixer :: proc(t: ^testing.T) {
	Mixer_Init()
	defer Mixer_Shutdown()
	// A 0.5 constant "sound" (stereo, 100 ms) and a 1 kHz sine.
	dc := make([]f32, 4800 * 2, context.temp_allocator)
	for &v in dc do v = 0.5
	sine := make([]f32, 9600 * 2, context.temp_allocator)
	for i in 0 ..< 9600 {
		x := math.sin(2 * math.PI * 1000 * f32(i) / MIXER_RATE)
		sine[i * 2], sine[i * 2 + 1] = x, x
	}
	out := make([]f32, 512 * 2, context.temp_allocator)
	sfx := Mixer_BusIndex("SFX")
	music := Mixer_BusIndex("Music")
	testing.expect(t, sfx > 0 && music > 0 && Mixer_BusCount() == 3, "Master, Music, SFX")

	// A voice on SFX at full volume: 0.5 out.
	h := Mixer_PlaySound(dc, sfx, loop = true, owner = &dc)
	Mixer_Render(out)
	testing.expectf(t, abs(out[400] - 0.5) < 0.001 && abs(out[401] - 0.5) < 0.001, "passes through: %v", out[400])
	// Fader and pan: SFX at 0.5, panned hard right.
	Mixer_SetBusVolume(sfx, 0.5)
	Mixer_SetBusPan(sfx, 1)
	Mixer_Render(out) // (ramps)
	Mixer_Render(out)
	testing.expectf(t, abs(out[401] - 0.25) < 0.001 && abs(out[400]) < 0.001, "fader 0.5, right only: %v %v", out[400], out[401])
	Mixer_SetBusPan(sfx, 0)
	// Mute; solo another bus silences SFX; solo SFX brings it back.
	Mixer_SetBusMute(sfx, true)
	Mixer_Render(out)
	Mixer_Render(out)
	testing.expect(t, abs(out[400]) < 0.001, "muted")
	Mixer_SetBusMute(sfx, false)
	Mixer_SetBusSolo(music, true)
	Mixer_Render(out)
	Mixer_Render(out)
	testing.expect(t, abs(out[400]) < 0.001, "another bus soloed")
	Mixer_SetBusSolo(sfx, true)
	Mixer_Render(out)
	Mixer_Render(out)
	testing.expectf(t, abs(out[400] - 0.25) < 0.001, "soloed: %v", out[400])
	Mixer_SetBusSolo(sfx, false)
	Mixer_SetBusSolo(music, false)

	// Routing: a Weapons bus into SFX (0.5) - its voice goes through both faders.
	weapons := Mixer_AddBus("Weapons", sfx)
	testing.expect(t, weapons > 0 && !Mixer_SetBusOutput(sfx, weapons), "a loop is refused")
	Mixer_SetVoiceBus(h, weapons)
	Mixer_SetBusVolume(weapons, 0.5)
	Mixer_Render(out)
	Mixer_Render(out)
	testing.expectf(t, abs(out[400] - 0.125) < 0.001, "two faders: %v", out[400])

	// A looping voice keeps going; a one-shot ends (100 ms) and is reaped;
	// pitch 2 ends twice as fast.
	testing.expect(t, Mixer_VoicePlaying(h), "looping")
	Mixer_StopVoice(h)
	h1 := Mixer_PlaySound(dc, sfx)
	for _ in 0 ..< 10 do Mixer_Render(out)
	testing.expect(t, !Mixer_VoicePlaying(h1), "ended")
	Mixer_Reap()
	testing.expect_value(t, Mixer_ActiveVoices(), 0)
	h2 := Mixer_PlaySound(dc, sfx, pitch = 2)
	for _ in 0 ..< 5 do Mixer_Render(out) // 2560 frames > 4800 / 2
	testing.expect(t, !Mixer_VoicePlaying(h2), "pitch 2: half the time")

	// A low-pass on SFX cuts the 1 kHz sine (cutoff 100 Hz).
	Mixer_SetBusVolume(sfx, 1)
	Mixer_SetBusVolume(0, 1)
	slot := Mixer_AddEffect(sfx, .Lowpass)
	Mixer_EffectRef(sfx, slot).params[0] = 100
	h3 := Mixer_PlaySound(sine, sfx, owner = &sine)
	for _ in 0 ..< 4 do Mixer_Render(out)
	peak: f32
	for v in out do peak = max(peak, abs(v))
	testing.expectf(t, peak < 0.2, "1 kHz under a 100 Hz low-pass: %v", peak)
	testing.expect(t, Mixer_Buses()[0].peak[0] > 0, "the meters move")
	Mixer_SetEffectEnabled(sfx, slot, false)
	for _ in 0 ..< 2 do Mixer_Render(out)
	peak = 0
	for v in out do peak = max(peak, abs(v))
	testing.expectf(t, peak > 0.9, "bypassed: %v", peak)
	// Stopping by owner (a sound resource being freed).
	Mixer_StopOwner(&sine)
	testing.expect(t, !Mixer_VoicePlaying(h3), "stopped with its owner")

	// The project's JSON: saved, loaded back.
	Mixer_SetBusMute(weapons, true)
	text := strings.clone(Mixer_ToJSON(), context.temp_allocator)
	testing.expect(t, strings.contains(text, `{"name": "Weapons", "output": "SFX", "volume": 0.5`) && strings.contains(text, `"mute": true`) && strings.contains(text, `{"type": "lowpass", "enabled": false, "cutoff": 100`), text)
	Mixer_ResetBuses()
	testing.expect_value(t, Mixer_BusIndex("Weapons"), -1)
	testing.expect(t, Mixer_LoadJSON(text), "loaded")
	w := Mixer_BusIndex("Weapons")
	testing.expect(t, w > 0, "Weapons is back")
	for b in Mixer_Buses() do if b.index == w {
		testing.expect(t, b.mute && b.volume == 0.5 && b.output == Mixer_BusIndex("SFX"), "with its settings")
	}
	for b in Mixer_Buses() do if b.index == Mixer_BusIndex("SFX") {
		testing.expect(t, len(b.effects) == 1 && b.effects[0].type == .Lowpass && !b.effects[0].enabled && b.effects[0].params[0] == 100, "and its effect")
	}
	// Every effect type runs (no NaNs, no allocation on the audio thread).
	for et in Mixer_Effect_Type do if et != .None do Mixer_AddEffect(0, et)
	h4 := Mixer_PlaySound(sine, sfx)
	for _ in 0 ..< 8 do Mixer_Render(out)
	for v in out do testing.expect(t, !math.is_nan(v) && abs(v) <= 1, "finite, in range")
	Mixer_StopVoice(h4)

	// The editor link (Play): the Mixer tab's live commands.
	game := new(Game)
	InitializeGame(game)
	defer game->terminate()
	music2 := Mixer_BusIndex("Music")
	EditorLink_Command(game, fmt.tprintf("mixer-set %d volume 0.25", music2))
	EditorLink_Command(game, fmt.tprintf("mixer-set %d mute 1", music2))
	for b in Mixer_Buses() do if b.index == music2 do testing.expect(t, b.volume == 0.25 && b.mute, "volume and mute over the link")
	EditorLink_Command(game, `mixer-load [{"name": "Master"}, {"name": "Voice", "output": "Master", "volume": 0.5}]`)
	testing.expect(t, Mixer_BusIndex("Voice") > 0 && Mixer_BusIndex("Music") < 0, "a new layout over the link")
	v := Mixer_BusIndex("Voice")
	dslot := Mixer_AddEffect(v, .Delay)
	EditorLink_Command(game, fmt.tprintf("mixer-fx %d %d 0 500", v, dslot))
	testing.expect_value(t, Mixer_EffectRef(v, dslot).params[0], 500)
	EditorLink_Command(game, fmt.tprintf("mixer-fx-enabled %d %d 0", v, dslot))
	testing.expect(t, !Mixer_EffectRef(v, dslot).enabled, "bypassed over the link")
}
