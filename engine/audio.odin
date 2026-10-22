package engine

import "base:runtime"
import "core:math"
import rl "vendor:raylib"

// ============================================================================
// Audio mixing helpers.
//
// - Voices: a sound can play over itself (one-shots fired quickly) through
//   aliases that share its samples (Audio_PlayVoice; AUDIO_MAX_VOICES).
// - Positional sounds: volume falls from minDistance to maxDistance from
//   the listener (the current camera, or Audio_SetListener's node) and the
//   sound pans with its horizontal offset (Audio_Spatialize).
// - Buses: master, music and sound effects volumes (project Audio
//   settings, Audio.set_bus_volume); a low-pass filter and a reverb on the
//   master mix (Audio_SetLowpass / Audio_SetReverb). raylib's stream
//   processors carry no user data, so effects can't keep separate state per
//   bus: they process the whole mix.
// ============================================================================

AUDIO_MAX_VOICES :: 8
AUDIO_SAMPLE_RATE :: 48000 // the mixer's rate on macOS / most devices (filter coefficients)

// --- voices --------------------------------------------------------------------

// Audio_PlayVoice plays a sound on a free voice (up to `voices`, at most
// AUDIO_MAX_VOICES): a voice that isn't playing, else the oldest. Returns
// the rl.Sound used (volume / pan / pitch can be set on it).
Audio_PlayVoice :: proc(a: ^AudioSound, voices: int, volume, pitch: f32, pan: f32 = 0.5) -> (rl.Sound, bool) {
	if a == nil || !rl.IsAudioDeviceReady() || a.sound.frameCount == 0 do return {}, false
	n := clamp(voices, 1, AUDIO_MAX_VOICES)
	for len(a.aliases) < n - 1 {
		append(&a.aliases, rl.LoadSoundAlias(a.sound))
	}
	voice := -1
	for i in 0 ..< n {
		s := a.sound if i == 0 else a.aliases[i - 1]
		if !rl.IsSoundPlaying(s) {voice = i; break}
	}
	if voice < 0 {
		voice = a.nextVoice % n // all busy: restart the oldest
	}
	a.nextVoice = (voice + 1) % n
	s := a.sound if voice == 0 else a.aliases[voice - 1]
	rl.SetSoundVolume(s, volume)
	rl.SetSoundPitch(s, pitch)
	rl.SetSoundPan(s, pan)
	rl.PlaySound(s)
	return s, true
}

// Audio_VoicesPlaying: whether any of the sound's voices is playing.
Audio_VoicesPlaying :: proc(a: ^AudioSound) -> bool {
	if a == nil || !rl.IsAudioDeviceReady() || a.sound.frameCount == 0 do return false
	if rl.IsSoundPlaying(a.sound) do return true
	for s in a.aliases do if rl.IsSoundPlaying(s) do return true
	return false
}

// Audio_ReleaseVoices unloads the aliases (before the sound itself).
Audio_ReleaseVoices :: proc(a: ^AudioSound) {
	if rl.IsAudioDeviceReady() do for s in a.aliases do rl.UnloadSoundAlias(s)
	delete(a.aliases)
	a.aliases = nil
}

// --- positional ------------------------------------------------------------------

@(private = "file")
audioListener: ^Node

// Audio_SetListener: positional sounds are heard from this node (nil = the
// current camera).
Audio_SetListener :: proc(n: ^Node) {audioListener = n}

// Audio_ListenerPosition: where positional sounds are heard from.
Audio_ListenerPosition :: proc(ctx: ^GameContext) -> ([2]f32, bool) {
	if audioListener != nil && Node_IsAlive(audioListener) do return audioListener.globalPosition, true
	audioListener = nil
	if ctx != nil && ctx.scene != nil && ctx.scene.camera != nil do return ctx.scene.camera.currentPosition, true
	return {}, false
}

// Audio_Spatialize: volume factor (1 within minDist, 0 beyond maxDist,
// smooth between) and pan (raylib: 0.5 centre, 1 left, 0 right; full
// pan at panRange to the side).
Audio_Spatialize :: proc(source, listener: [2]f32, minDist, maxDist, panRange: f32) -> (volume, pan: f32) {
	d := source - listener
	dist := math.sqrt(d.x * d.x + d.y * d.y)
	volume = 1
	if dist > minDist {
		span := max(maxDist - minDist, 0.001)
		t := clamp((dist - minDist) / span, 0, 1)
		volume = (1 - t) * (1 - t) // eases out towards the edge
	}
	side := clamp(d.x / max(panRange, 0.001), -1, 1)
	pan = 0.5 - side * 0.5
	return
}

// --- bus effects (master mix) -------------------------------------------------------

Audio_Effects :: struct {
	lowpassHz:  f32, // 0 = off
	reverbMix:  f32, // 0..1 (0 = off)
	reverbSize: f32, // 0..1 room size (feedback)
}

@(private = "file")
fx: struct {
	params:   Audio_Effects,
	attached: bool,
	// Low-pass state per channel.
	lp:       [2]f32,
	// Reverb: four combs and two all-passes per channel (Freeverb-like).
	comb:     [2][4][]f32,
	combPos:  [2][4]int,
	combLp:   [2][4]f32,
	ap:       [2][2][]f32,
	apPos:    [2][2]int,
	storage:  []f32,
}

@(private = "file")
COMB_LEN := [4]int{1557, 1617, 1491, 1422}
@(private = "file")
AP_LEN := [2]int{556, 441}

@(private = "file")
fx_init_buffers :: proc() {
	if fx.storage != nil do return
	total := 0
	for ch in 0 ..< 2 {
		for l in COMB_LEN do total += l + ch * 23 // a little stereo spread
		for l in AP_LEN do total += l + ch * 23
	}
	fx.storage = make([]f32, total, runtime.heap_allocator())
	at := 0
	for ch in 0 ..< 2 {
		for l, i in COMB_LEN {
			n := l + ch * 23
			fx.comb[ch][i] = fx.storage[at:at + n]
			at += n
		}
		for l, i in AP_LEN {
			n := l + ch * 23
			fx.ap[ch][i] = fx.storage[at:at + n]
			at += n
		}
	}
}

// Audio_ProcessEffects applies the master effects to interleaved stereo
// samples in place (the mixer callback; also used by tests).
Audio_ProcessEffects :: proc(samples: []f32, p: Audio_Effects) {
	if p.lowpassHz > 0 {
		a := 1 - math.exp(-2 * math.PI * min(p.lowpassHz, AUDIO_SAMPLE_RATE / 2) / AUDIO_SAMPLE_RATE)
		for i := 0; i + 1 < len(samples); i += 2 {
			for ch in 0 ..< 2 {
				fx.lp[ch] += a * (samples[i + ch] - fx.lp[ch])
				samples[i + ch] = fx.lp[ch]
			}
		}
	}
	if p.reverbMix > 0.0001 {
		fx_init_buffers()
		feedback := 0.7 + 0.28 * clamp(p.reverbSize, 0, 1)
		damp: f32 = 0.2
		mix := clamp(p.reverbMix, 0, 1)
		for i := 0; i + 1 < len(samples); i += 2 {
			for ch in 0 ..< 2 {
				x := samples[i + ch]
				wet: f32
				for k in 0 ..< 4 {
					buf := fx.comb[ch][k]
					pos := fx.combPos[ch][k]
					y := buf[pos]
					fx.combLp[ch][k] = y * (1 - damp) + fx.combLp[ch][k] * damp
					buf[pos] = x * 0.015 + fx.combLp[ch][k] * feedback
					fx.combPos[ch][k] = (pos + 1) % len(buf)
					wet += y
				}
				for k in 0 ..< 2 {
					buf := fx.ap[ch][k]
					pos := fx.apPos[ch][k]
					b := buf[pos]
					buf[pos] = wet + b * 0.5
					wet = b - wet
					fx.apPos[ch][k] = (pos + 1) % len(buf)
				}
				samples[i + ch] = x * (1 - mix * 0.5) + wet * mix * 3
			}
		}
	}
}

@(private = "file")
fx_callback :: proc "c" (buffer: rawptr, frames: u32) {
	context = runtime.default_context()
	samples := ([^]f32)(buffer)[:frames * 2]
	Audio_ProcessEffects(samples, fx.params)
}

@(private = "file")
fx_update :: proc() {
	if !rl.IsAudioDeviceReady() do return
	want := fx.params.lowpassHz > 0 || fx.params.reverbMix > 0.0001
	if want && !fx.attached {
		fx.lp = {}
		rl.AttachAudioMixedProcessor(fx_callback)
		fx.attached = true
	} else if !want && fx.attached {
		rl.DetachAudioMixedProcessor(fx_callback)
		fx.attached = false
	}
}

// Audio_SetLowpass: a low-pass on the master mix (hz <= 0: off).
Audio_SetLowpass :: proc(hz: f32) {
	fx.params.lowpassHz = max(hz, 0)
	fx_update()
}

// Audio_SetReverb: reverb on the master mix (mix 0..1, 0 = off; size 0..1).
Audio_SetReverb :: proc(mix, size: f32) {
	if mix > 0 do fx_init_buffers() // here, not on the audio thread
	fx.params.reverbMix = clamp(mix, 0, 1)
	fx.params.reverbSize = clamp(size, 0, 1)
	fx_update()
}

Audio_GetEffects :: proc() -> Audio_Effects {return fx.params}

// Audio_ResetEffects detaches the effects and clears their state (game end).
Audio_ResetEffects :: proc() {
	fx.params = {}
	fx_update()
	fx.lp = {}
	fx.combPos = {}
	fx.combLp = {}
	fx.apPos = {}
	for &v in fx.storage do v = 0
}
