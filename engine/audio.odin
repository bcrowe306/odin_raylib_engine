package engine

import "core:math"
import rl "vendor:raylib"

// ============================================================================
// Audio helpers on top of the mixer (mixer.odin).
//
// - Positional sounds: volume falls from minDistance to maxDistance from
//   the listener (the current camera, or Audio_SetListener's node) and the
//   sound pans with its horizontal offset (Audio_Spatialize).
// - The project's master / music / sound-effects volumes are the Master,
//   Music and SFX buses' faders; the old master low-pass and reverb
//   (Audio.set_lowpass / set_reverb) are effects on the Master bus.
// ============================================================================

AUDIO_MAX_VOICES :: 8

// Audio_RaylibPanToMixer: raylib's pan (0.5 centre, 1 left, 0 right) as the
// mixer's (-1 left .. 1 right).
Audio_RaylibPanToMixer :: #force_inline proc(p: f32) -> f32 {return clamp((0.5 - p) * 2, -1, 1)}

// Audio_Ready: the mixer can play (an audio device, the mixer started).
Audio_Ready :: proc() -> bool {
	if !rl.IsAudioDeviceReady() do return false
	Mixer_Init()
	return true
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

// --- master effects (Audio.set_lowpass / set_reverb) ------------------------------------

// audio_master_effect: the Master bus's first effect of a type (added when
// `create`); its slot or -1.
@(private = "file")
audio_master_effect :: proc(t: Mixer_Effect_Type, create: bool) -> int {
	Mixer_Init()
	for b in Mixer_Buses() do if b.index == 0 {
		for e, k in b.effects do if e.type == t do return k
	}
	return Mixer_AddEffect(0, t) if create else -1
}

// Audio_SetLowpass: a low-pass on the Master bus (hz <= 0: bypassed).
Audio_SetLowpass :: proc(hz: f32) {
	slot := audio_master_effect(.Lowpass, hz > 0)
	if slot < 0 do return
	if hz > 0 do Mixer_EffectRef(0, slot).params[0] = hz
	Mixer_SetEffectEnabled(0, slot, hz > 0)
}

// Audio_SetReverb: reverb on the Master bus (mix 0..1, 0 = bypassed; size 0..1).
Audio_SetReverb :: proc(mix, size: f32) {
	slot := audio_master_effect(.Reverb, mix > 0)
	if slot < 0 do return
	e := Mixer_EffectRef(0, slot)
	e.params[0] = clamp(size, 0, 1)
	e.params[2] = clamp(mix, 0, 1)
	Mixer_SetEffectEnabled(0, slot, mix > 0)
}
