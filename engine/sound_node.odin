package engine

import "core:strings"
import "core:log"
import rl "vendor:raylib"

SoundNode :: struct {
	using node: Node,
	audio: ^AudioSound,
	volume: f32 `gui:"true" min:"0" max:"1"`,
	pitch: f32 `gui:"true" min:"0.1" max:"3"`,
	bus: string `gui:"true"`, // the mixer bus it plays into ("" = SFX)
	autoplay: bool `gui:"true"`, // play once when the node becomes ready
	voices: int `gui:"true" min:"1" max:"8"`, // plays over itself up to this many times (1: restarts)
	// Positional: volume falls from minDistance to maxDistance from the
	// listener (the camera, or Audio.set_listener), pans with the side.
	positional: bool `gui:"true"`,
	minDistance: f32 `gui:"true" min:"0" max:"4000"`,
	maxDistance: f32 `gui:"true" min:"1" max:"8000"`,
	onFinished: EventSubject,    // "finished": playback reached the end
	wasPlaying: bool,
	handles:    [AUDIO_MAX_VOICES]Mixer_Voice_Handle, // its playing voices (mixer.odin)
	nextVoice:  int,
	soundPaused: bool, // SoundNode_Pause (not the node's subtree pause)
}

SoundNode_Init :: proc(soundNode: ^SoundNode) {
	InitializeNode(soundNode)
	soundNode.typeId = SoundNode
	soundNode.volume = 1.0
	soundNode.pitch = 1.0
	soundNode.voices = 1
	soundNode.minDistance = 100
	soundNode.maxDistance = 900
	soundNode.renderable = false
	soundNode.ready = SoundNode_Ready
	soundNode.update = SoundNode_Update
	soundNode.onDestroy = SoundNode_Destroy
	InitializeSubject(&soundNode.onFinished, "finished", soundNode)
}

// SoundNode_BusIndex: the mixer bus it plays into (SFX when "" or unknown).
SoundNode_BusIndex :: proc(sn: ^SoundNode) -> int {
	if sn.bus != "" do if i := Mixer_BusIndex(sn.bus); i >= 0 do return i
	if i := Mixer_BusIndex("SFX"); i >= 0 do return i
	return 0
}

// SoundNode_Playing: any of its voices still playing.
SoundNode_Playing :: proc(sn: ^SoundNode) -> bool {
	for h in sn.handles do if Mixer_VoicePlaying(h) do return true
	return false
}

SoundNode_Update :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	soundNode := cast(^SoundNode)node
	if soundNode.audio == nil do return
	playing := SoundNode_Playing(soundNode)
	if playing do SoundNode_ApplyMix(soundNode) // follows the source / listener, volume, bus
	if soundNode.wasPlaying && !playing && !soundNode.soundPaused do soundNode.onFinished->notify(soundNode, nil, gameContext)
	soundNode.wasPlaying = playing
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

// SoundNode_ApplyMix pushes volume / pan / pitch / bus to its voices.
SoundNode_ApplyMix :: proc(sn: ^SoundNode) {
	vol, pan := SoundNode_Mix(sn, sn.gameContext)
	bus := SoundNode_BusIndex(sn)
	for h in sn.handles {
		Mixer_SetVoice(h, vol, Audio_RaylibPanToMixer(pan), sn.pitch)
		Mixer_SetVoiceBus(h, bus)
	}
}

SoundNode_Destroy :: proc(node: ^Node, gameContext: ^GameContext) {
	soundNode := cast(^SoundNode)node
	DestroySubject(&soundNode.onFinished)
	SoundNode_Stop(soundNode)
	if soundNode.audio != nil {
		ResourceManager_ReleaseSound(Node_ResourceManager(soundNode), soundNode.audio)
		soundNode.audio = nil
	}
}

SoundNode_Ready :: proc(node: ^Node, gameContext: ^GameContext) {
	soundNode := cast(^SoundNode)node
	if soundNode.audio == nil do return
	if soundNode.autoplay do SoundNode_Play(soundNode)
}

SoundNode_Create :: proc(scene: ^Scene, resource_manager: ^ResourceManager, filePath: string, name: string) -> ^SoundNode {
	soundNode := CreateNode(scene.manager, SoundNode)
	SoundNode_Init(soundNode)
	soundNode.name = strings.clone(name, soundNode.allocator) // owned: callers pass temp strings too
	sound, ok := resource_manager->loadAudioSound(filePath)
	if ok {
		log.info("Loaded sound: ", filePath)
		soundNode.audio = sound
	}
	else {
		log.error("Failed to load sound: ", filePath)
	}
	return soundNode
}

// SoundNode_Play starts a voice: up to `voices` overlap (the oldest is cut
// when all are busy; 1 restarts it).
SoundNode_Play :: proc(soundNode: ^SoundNode) {
	if soundNode == nil || soundNode.audio == nil do return
	if !Audio_Ready() || len(soundNode.audio.pcm) == 0 do return
	n := clamp(soundNode.voices, 1, AUDIO_MAX_VOICES)
	slot := -1
	for i in 0 ..< n do if !Mixer_VoicePlaying(soundNode.handles[i]) {slot = i; break}
	if slot < 0 {
		slot = soundNode.nextVoice % n
		Mixer_StopVoice(soundNode.handles[slot])
	}
	soundNode.nextVoice = (slot + 1) % n
	vol, pan := SoundNode_Mix(soundNode, soundNode.gameContext)
	soundNode.handles[slot] = Mixer_PlaySound(soundNode.audio.pcm, SoundNode_BusIndex(soundNode), vol, Audio_RaylibPanToMixer(pan), soundNode.pitch, owner = soundNode.audio)
	soundNode.wasPlaying = true
	soundNode.soundPaused = false
}

SoundNode_Stop :: proc(soundNode: ^SoundNode) {
	if soundNode == nil do return
	for &h in soundNode.handles {
		Mixer_StopVoice(h)
		h = {}
	}
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
