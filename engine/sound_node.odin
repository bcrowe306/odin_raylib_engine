package engine

import "core:log"
import "core:math"
import "core:math/rand"
import "core:strings"
import rl "vendor:raylib"

// How a Sound Effect picks what to play (#204).
Sound_Play_Mode :: enum u8 {
	Single,              // the chosen sound (`single`)
	All,                 // every sound at once
	Sequential,          // the next one each play, then the first again
	Sequential_Reversed, // the same from the last one
	Random,              // one at random (by weight; never the one just played)
	Shuffle,             // each once in a random order, then a new order
}

// A sound in a Sound Effect's list.
Sound_Entry :: struct {
	path:   string, // the asset (node allocator) - kept when the sound can't load
	audio:  ^AudioSound,
	weight: f32, // Random: how likely (1: as likely as the others; 0: never)
}

// The variation one play gets (per voice): volume and pan offsets, a pitch
// multiplier.
Sound_Variation :: struct {
	volume, pan: f32,
	pitch:       f32,
}

@(private = "file")
Sound_Pending :: struct {
	delay:     f32, // seconds left
	sound:     int,
	variation: Sound_Variation,
}

SoundNode :: struct {
	using node: Node,
	sounds: [dynamic]Sound_Entry, // what it plays (#204; one sound before)
	playMode: Sound_Play_Mode `gui:"true"`,
	single: int `gui:"true" min:"1" max:"64"`, // Single: which sound (1: the first)
	volume: f32 `gui:"true" min:"0" max:"1"`,
	pitch: f32 `gui:"true" min:"0.1" max:"3"`,
	// Variation per play (each sound of All on its own): +/- around the
	// node's values - volume, pitch in semitones, pan (-1 left .. 1 right).
	volumeRandom: f32 `gui:"true" min:"0" max:"1"`,
	pitchRandom: f32 `gui:"true" min:"0" max:"12"`,
	panRandom: f32 `gui:"true" min:"0" max:"1"`,
	delayRandom: f32 `gui:"true" min:"0" max:"2"`, // a random 0..this seconds before each play
	cooldown: f32 `gui:"true" min:"0" max:"5"`, // plays within this many seconds of the last are skipped
	bus: string `gui:"true"`, // the mixer bus it plays into ("" = SFX)
	caption: string `gui:"true"`, // shown on the subtitle track when it plays, for players with captions on ("[door creaks]")
	autoplay: bool `gui:"true"`, // play once when the node becomes ready
	voices: int `gui:"true" min:"1" max:"8"`, // plays over itself up to this many times (1: restarts)
	// Positional: volume falls from minDistance to maxDistance from the
	// listener (the camera, or Audio.set_listener), pans with the side.
	positional: bool `gui:"true"`,
	minDistance: f32 `gui:"true" min:"0" max:"4000"`,
	maxDistance: f32 `gui:"true" min:"1" max:"8000"`,
	onFinished: EventSubject,    // "finished": everything it started has ended
	wasPlaying: bool,
	handles:    [AUDIO_MAX_VOICES]Mixer_Voice_Handle, // its playing voices (mixer.odin)
	variation:  [AUDIO_MAX_VOICES]Sound_Variation, // each voice's
	nextVoice:  int,
	soundPaused: bool, // SoundNode_Pause (not the node's subtree pause)
	// Picking (runtime)
	nextIndex:    int, // Sequential: plays so far
	lastIndex:    int, // the sound played last (-1: none)
	bag:          [dynamic]int, // Shuffle: this round's sounds left
	cooldownLeft: f32,
	pending:      [dynamic]Sound_Pending, // delayed plays
}

SoundNode_Init :: proc(soundNode: ^SoundNode) {
	InitializeNode(soundNode)
	soundNode.typeId = SoundNode
	soundNode.volume = 1.0
	soundNode.pitch = 1.0
	soundNode.voices = 1
	soundNode.single = 1
	soundNode.lastIndex = -1
	soundNode.minDistance = 100
	soundNode.maxDistance = 900
	soundNode.ready = SoundNode_Ready
	soundNode.update = SoundNode_Update
	soundNode.onDestroy = SoundNode_Destroy
	InitializeSubject(&soundNode.onFinished, "finished", soundNode)
}

// --- the list -------------------------------------------------------------------------

// SoundNode_FirstSound: the first loaded sound (its import bus, previews).
SoundNode_FirstSound :: proc(sn: ^SoundNode) -> ^AudioSound {
	for s in sn.sounds do if s.audio != nil do return s.audio
	return nil
}

// SoundNode_AddSound adds a sound (an asset path; loaded when audio is up).
SoundNode_AddSound :: proc(sn: ^SoundNode, rm: ^ResourceManager, path: string, weight: f32 = 1) {
	entry := Sound_Entry{path = strings.clone(path, sn.allocator), weight = weight}
	if rm != nil && path != "" && rl.IsAudioDeviceReady() {
		if s, ok := rm.loadAudioSound(rm, path); ok do entry.audio = s
		else do log.error("Failed to load sound: ", path)
	}
	if sn.sounds == nil do sn.sounds = make([dynamic]Sound_Entry, sn.allocator)
	append(&sn.sounds, entry)
	clear(&sn.bag)
}

// SoundNode_RemoveSound takes a sound out of the list.
SoundNode_RemoveSound :: proc(sn: ^SoundNode, rm: ^ResourceManager, i: int) {
	if i < 0 || i >= len(sn.sounds) do return
	SoundNode_Stop(sn)
	e := sn.sounds[i]
	if e.audio != nil && rm != nil do ResourceManager_ReleaseSound(rm, e.audio)
	delete(e.path, sn.allocator)
	ordered_remove(&sn.sounds, i)
	clear(&sn.bag)
}

// SoundNode_MoveSound reorders the list.
SoundNode_MoveSound :: proc(sn: ^SoundNode, from, to: int) {
	if from < 0 || from >= len(sn.sounds) || to < 0 || to >= len(sn.sounds) || from == to do return
	e := sn.sounds[from]
	ordered_remove(&sn.sounds, from)
	inject_at(&sn.sounds, to, e)
	clear(&sn.bag)
}

// SoundNode_ClearSounds empties the list.
SoundNode_ClearSounds :: proc(sn: ^SoundNode, rm: ^ResourceManager) {
	for len(sn.sounds) > 0 do SoundNode_RemoveSound(sn, rm, len(sn.sounds) - 1)
}

// SoundNode_SetSound: just this one sound ("" = none).
SoundNode_SetSound :: proc(sn: ^SoundNode, rm: ^ResourceManager, path: string) {
	SoundNode_ClearSounds(sn, rm)
	if path != "" do SoundNode_AddSound(sn, rm, path)
}

// --- picking --------------------------------------------------------------------------

// SoundNode_Pick: the sounds the next play starts (by the play mode).
SoundNode_Pick :: proc(sn: ^SoundNode, allocator := context.temp_allocator) -> []int {
	n := len(sn.sounds)
	out := make([dynamic]int, allocator)
	if n == 0 do return out[:]
	switch sn.playMode {
	case .Single:
		append(&out, clamp(sn.single - 1, 0, n - 1))
	case .All:
		for i in 0 ..< n do append(&out, i)
	case .Sequential:
		append(&out, sn.nextIndex % n)
		sn.nextIndex += 1
	case .Sequential_Reversed:
		append(&out, n - 1 - sn.nextIndex % n)
		sn.nextIndex += 1
	case .Random:
		// By weight, never the one just played (with others to choose).
		total: f32
		for s, i in sn.sounds do if i != sn.lastIndex || n == 1 do total += max(s.weight, 0)
		pick := -1
		if total > 0 {
			r := rand.float32() * total
			for s, i in sn.sounds {
				if i == sn.lastIndex && n > 1 do continue
				w := max(s.weight, 0)
				if w <= 0 do continue
				pick = i
				if r < w do break
				r -= w
			}
		}
		if pick < 0 do pick = (sn.lastIndex + 1) % n // (all weights 0)
		append(&out, pick)
	case .Shuffle:
		// Each once a round; a new round doesn't start with the last one.
		if len(sn.bag) == 0 || len(sn.bag) > n {
			if sn.bag == nil do sn.bag = make([dynamic]int, sn.allocator)
			clear(&sn.bag)
			for i in 0 ..< n do append(&sn.bag, i)
			rand.shuffle(sn.bag[:])
			// (drawn from the end: keep the last one played off the end)
			if n > 1 && sn.bag[len(sn.bag) - 1] == sn.lastIndex do sn.bag[0], sn.bag[len(sn.bag) - 1] = sn.bag[len(sn.bag) - 1], sn.bag[0]
		}
		append(&out, pop(&sn.bag))
	}
	if len(out) > 0 do sn.lastIndex = out[len(out) - 1]
	return out[:]
}

// SoundNode_RollVariation: one play's variation (volume and pan +/-; pitch
// +/- semitones as a multiplier).
SoundNode_RollVariation :: proc(sn: ^SoundNode) -> Sound_Variation {
	v := Sound_Variation{pitch = 1}
	if sn.volumeRandom > 0 do v.volume = rand.float32_range(-sn.volumeRandom, sn.volumeRandom)
	if sn.panRandom > 0 do v.pan = rand.float32_range(-sn.panRandom, sn.panRandom)
	if sn.pitchRandom > 0 do v.pitch = math.pow(2, rand.float32_range(-sn.pitchRandom, sn.pitchRandom) / 12)
	return v
}

// --- mixing ---------------------------------------------------------------------------

// SoundNode_BusIndex: the mixer bus it plays into (SFX when "" or unknown).
SoundNode_BusIndex :: proc(sn: ^SoundNode) -> int {
	if sn.bus != "" do if i := Mixer_BusIndex(sn.bus); i >= 0 do return i
	first := SoundNode_FirstSound(sn)
	return Audio_BusFor(node_rm(sn), first.filePath if first != nil else "", "SFX") // (its import bus)
}

// SoundNode_Playing: any of its voices still playing.
SoundNode_Playing :: proc(sn: ^SoundNode) -> bool {
	for h in sn.handles do if Mixer_VoicePlaying(h) do return true
	return false
}

SoundNode_Update :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	soundNode := cast(^SoundNode)node
	if soundNode.cooldownLeft > 0 do soundNode.cooldownLeft -= deltaTime
	// Delayed plays whose time has come.
	for i := len(soundNode.pending) - 1; i >= 0; i -= 1 {
		p := &soundNode.pending[i]
		p.delay -= deltaTime
		if p.delay > 0 do continue
		sound_start(soundNode, p.sound, p.variation)
		ordered_remove(&soundNode.pending, i)
	}
	if len(soundNode.sounds) == 0 do return
	playing := SoundNode_Playing(soundNode)
	if playing do SoundNode_ApplyMix(soundNode) // follows the source / listener, volume, bus
	if soundNode.wasPlaying && !playing && len(soundNode.pending) == 0 && !soundNode.soundPaused do soundNode.onFinished->notify(soundNode, nil, gameContext)
	soundNode.wasPlaying = playing || len(soundNode.pending) > 0
}

// SoundNode_Mix: the volume (node x distance) and pan (raylib's 0.5 centre)
// to play at; the bus fader applies in the mixer.
SoundNode_Mix :: proc(sn: ^SoundNode, ctx: ^GameContext) -> (volume, pan: f32) {
	gc := ctx if ctx != nil else sn.gameContext
	volume, pan = sn.volume, 0.5
	if sn.positional {
		if listener, ok := Audio_ListenerPosition(gc); ok {
			v, p := Audio_Spatialize(sn.globalPosition, listener, sn.minDistance, sn.maxDistance, max(sn.maxDistance * 0.5, 1))
			volume *= v
			pan = p
		}
	}
	return
}

// sound_voice_mix: a voice's volume, mixer pan and pitch - the node's mix
// with the voice's variation.
@(private = "file")
sound_voice_mix :: proc(sn: ^SoundNode, v: Sound_Variation) -> (volume, pan, pitch: f32) {
	vol, rpan := SoundNode_Mix(sn, sn.gameContext)
	dist := vol / sn.volume if sn.volume > 0 else 1
	volume = max(sn.volume + v.volume, 0) * dist
	pan = clamp(Audio_RaylibPanToMixer(rpan) + v.pan, -1, 1)
	pitch = max(sn.pitch * (v.pitch if v.pitch > 0 else 1), 0.01)
	return
}

// SoundNode_ApplyMix pushes volume / pan / pitch / bus to its voices.
SoundNode_ApplyMix :: proc(sn: ^SoundNode) {
	bus := SoundNode_BusIndex(sn)
	for h, i in sn.handles {
		if !Mixer_VoicePlaying(h) do continue
		vol, pan, pitch := sound_voice_mix(sn, sn.variation[i])
		Mixer_SetVoice(h, vol, pan, pitch)
		Mixer_SetVoiceBus(h, bus)
	}
}

SoundNode_Destroy :: proc(node: ^Node, gameContext: ^GameContext) {
	soundNode := cast(^SoundNode)node
	DestroySubject(&soundNode.onFinished)
	SoundNode_Stop(soundNode)
	SoundNode_ClearSounds(soundNode, Node_ResourceManager(soundNode))
	delete(soundNode.sounds)
	delete(soundNode.bag)
	delete(soundNode.pending)
}

SoundNode_Ready :: proc(node: ^Node, gameContext: ^GameContext) {
	soundNode := cast(^SoundNode)node
	if len(soundNode.sounds) == 0 do return
	if soundNode.autoplay do SoundNode_Play(soundNode)
}

SoundNode_Create :: proc(scene: ^Scene, resource_manager: ^ResourceManager, filePath: string, name: string) -> ^SoundNode {
	soundNode := CreateNode(scene.manager, SoundNode)
	SoundNode_Init(soundNode)
	soundNode.name = strings.clone(name, soundNode.allocator) // owned: callers pass temp strings too
	if filePath != "" do SoundNode_AddSound(soundNode, resource_manager, filePath)
	return soundNode
}

// --- playing --------------------------------------------------------------------------

// SoundNode_Play plays by its mode (#204): skipped within the cooldown;
// each sound gets its own variation, and a random delay when set.
SoundNode_Play :: proc(soundNode: ^SoundNode) {
	if soundNode == nil || len(soundNode.sounds) == 0 do return
	if soundNode.cooldownLeft > 0 do return
	soundNode.cooldownLeft = soundNode.cooldown
	for i in SoundNode_Pick(soundNode) do sound_schedule(soundNode, i)
}

// SoundNode_PlayIndex plays one sound of the list (0-based), whatever the
// mode (variation and delay apply; the cooldown doesn't).
SoundNode_PlayIndex :: proc(soundNode: ^SoundNode, i: int) {
	if soundNode == nil || i < 0 || i >= len(soundNode.sounds) do return
	soundNode.lastIndex = i
	sound_schedule(soundNode, i)
}

// SoundNode_PlayAudio plays a sound that isn't in its list through it
// (its bus, volume, variation) - animation sound keys routed to it.
SoundNode_PlayAudio :: proc(soundNode: ^SoundNode, audio: ^AudioSound) {
	if soundNode == nil || audio == nil do return
	sound_start_audio(soundNode, audio, SoundNode_RollVariation(soundNode))
}

@(private = "file")
sound_schedule :: proc(sn: ^SoundNode, i: int) {
	v := SoundNode_RollVariation(sn)
	if sn.delayRandom > 0 {
		if d := rand.float32_range(0, sn.delayRandom); d > 0.001 {
			if sn.pending == nil do sn.pending = make([dynamic]Sound_Pending, sn.allocator)
			append(&sn.pending, Sound_Pending{d, i, v})
			sn.wasPlaying = true
			return
		}
	}
	sound_start(sn, i, v)
}

// sound_start starts a voice for sound i: up to `voices` overlap (All: at
// least one per sound); the oldest is cut when all are busy.
@(private = "file")
sound_start :: proc(sn: ^SoundNode, i: int, v: Sound_Variation) {
	if i < 0 || i >= len(sn.sounds) do return
	sound_start_audio(sn, sn.sounds[i].audio, v)
}

@(private = "file")
sound_start_audio :: proc(sn: ^SoundNode, audio: ^AudioSound, v: Sound_Variation) {
	if audio == nil || !Audio_Ready() || len(audio.pcm) == 0 do return
	n := sn.voices
	if sn.playMode == .All do n = max(n, len(sn.sounds))
	n = clamp(n, 1, AUDIO_MAX_VOICES)
	slot := -1
	for k in 0 ..< n do if !Mixer_VoicePlaying(sn.handles[k]) {slot = k; break}
	if slot < 0 {
		slot = sn.nextVoice % n
		Mixer_StopVoice(sn.handles[slot])
	}
	sn.nextVoice = (slot + 1) % n
	sn.variation[slot] = v
	vol, pan, pitch := sound_voice_mix(sn, v)
	sn.handles[slot] = Mixer_PlaySound(audio.pcm, SoundNode_BusIndex(sn), vol, pan, pitch, owner = audio)
	if sn.caption != "" do Subtitles_Show(sn.caption, "", clamp(f32(len(audio.pcm) / 2) / MIXER_RATE, 1.5, 5), .Caption)
	sn.wasPlaying = true
	sn.soundPaused = false
}

SoundNode_Stop :: proc(soundNode: ^SoundNode) {
	if soundNode == nil do return
	for &h in soundNode.handles {
		Mixer_StopVoice(h)
		h = {}
	}
	clear(&soundNode.pending)
	soundNode.soundPaused = false
	soundNode.wasPlaying = false
}

SoundNode_Pause :: proc(soundNode: ^SoundNode) {
	if soundNode == nil do return
	for h in soundNode.handles do Mixer_SetVoicePaused(h, true)
	soundNode.soundPaused = true
}

SoundNode_Resume :: proc(soundNode: ^SoundNode) {
	if soundNode == nil do return
	for h in soundNode.handles do Mixer_SetVoicePaused(h, false)
	soundNode.soundPaused = false
}

SoundNode_SetVolume :: proc(soundNode: ^SoundNode, volume: f32) {
	if soundNode == nil do return
	soundNode.volume = max(volume, 0)
	SoundNode_ApplyMix(soundNode)
}

SoundNode_SetPitch :: proc(soundNode: ^SoundNode, pitch: f32) {
	if soundNode == nil do return
	soundNode.pitch = max(pitch, 0.01)
	SoundNode_ApplyMix(soundNode)
}

// SoundNode_SetPan: raylib-style pan (0.5 centre, 1 left, 0 right) for its
// playing voices (positional sounds pan by themselves).
SoundNode_SetPan :: proc(soundNode: ^SoundNode, pan: f32) {
	if soundNode == nil do return
	vol, _ := SoundNode_Mix(soundNode, soundNode.gameContext)
	for h in soundNode.handles do Mixer_SetVoice(h, vol, Audio_RaylibPanToMixer(pan), soundNode.pitch)
}
