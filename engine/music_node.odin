package engine

import "core:strings"
import "core:log"
import "core:math"
import rl "vendor:raylib"

MusicNode :: struct {
	using node: Node,
	music:      ^AudioMusic,
	volume:     f32 `gui:"true" min:"0" max:"1"`,
	pitch:      f32 `gui:"true" min:"0.1" max:"3"`,
	pan:        f32 `gui:"true" min:"0" max:"1"`,
	bus:        string `gui:"true"`, // the mixer bus it plays into ("" = Music)
	caption:    string `gui:"true"`, // shown on the subtitle track when it starts, for players with captions on ("[calm music]")
	looping:    bool `gui:"true"`,
	autoplay:   bool `gui:"true"`,
	isPlaying:  bool `gui:"true" save:"false"`,
	isPaused:   bool `gui:"true" save:"false"`,
	timeLength: f32,
	timePlayed: f32,
	// Fades (MusicNode_FadeTo, Audio.crossfade): a volume factor on top of
	// `volume`, moving to fadeTarget; fadeStop stops the track at 0.
	fadeVolume: f32,
	fadeStart:  f32,
	fadeTarget: f32,
	fadeTime:   f32,
	fadeElapsed: f32,
	fadeStop:   bool,
	onFinished: EventSubject, // "finished": a non-looping track ended
	voice:      Mixer_Voice_Handle, // its mixer voice (mixer.odin)
}

// MusicNode_BusIndex: the mixer bus it plays into (Music when "" / unknown).
MusicNode_BusIndex :: proc(m: ^MusicNode) -> int {
	if m.bus != "" do if i := Mixer_BusIndex(m.bus); i >= 0 do return i
	return Audio_BusFor(node_rm(m), m.music.filePath if m.music != nil else "", "Music") // (its import bus)
}

@(private = "file")
music_ok :: proc(m: ^MusicNode) -> bool {
	return m.music != nil && rl.IsAudioDeviceReady() && rl.IsMusicValid(m.music.music)
}

MusicNode_Init :: proc(musicNode: ^MusicNode) {
	InitializeNode(musicNode)
	musicNode.volume = 1.0
	musicNode.pitch = 1.0
	musicNode.pan = 0.5
	musicNode.looping = true
	musicNode.autoplay = false
	musicNode.isPlaying = false
	musicNode.isPaused = false
	musicNode.timeLength = 0
	musicNode.timePlayed = 0
	musicNode.fadeVolume = 1
	musicNode.fadeTarget = 1
	musicNode.ready = MusicNode_Ready
	musicNode.update = MusicNode_Update
	musicNode.onDestroy = MusicNode_Destroy
	InitializeSubject(&musicNode.onFinished, "finished", musicNode)
}

MusicNode_Create :: proc(
	scene: ^Scene,
	resourceManager: ^ResourceManager,
	filePath: string,
	name: string = "MusicNode",
	autoplay: bool = false,
	looping: bool = true,
	parent: ^Node = nil,
) -> ^MusicNode {
	musicNode := CreateNode(scene.manager, MusicNode)
	MusicNode_Init(musicNode)
	musicNode.name = strings.clone(name, musicNode.allocator) // owned: callers pass temp strings too
	musicNode.autoplay = autoplay
	musicNode.looping = looping

	if resourceManager != nil && filePath != "" {
		music, ok := resourceManager->loadAudioMusic(filePath)
		if ok && music != nil {
			log.info("Loaded background music: ", filePath)
			musicNode.music = music
			if rl.IsAudioDeviceReady() && rl.IsMusicValid(music.music) {
				music.music.looping = looping
				musicNode.timeLength = rl.GetMusicTimeLength(music.music)
			}
		} else {
			log.error("Failed to load background music: ", filePath)
		}
	}

	scene->addNode(musicNode, parent)
	return musicNode
}

MusicNode_Ready :: proc(node: ^Node, gameContext: ^GameContext) {
	musicNode := cast(^MusicNode)node
	if musicNode == nil do return

	if musicNode.autoplay {
		MusicNode_Play(musicNode)
	}
}

MusicNode_Update :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	musicNode := cast(^MusicNode)node
	if musicNode == nil do return
	if musicNode.isPlaying && musicNode.fadeTime > 0 do music_fade_step(musicNode, deltaTime)
	if musicNode.music == nil do return

	// The mixer streams it (its voice); here: time, the end, the bus.
	if musicNode.isPlaying && !musicNode.isPaused {
		if music_ok(musicNode) {
			musicNode.timeLength = rl.GetMusicTimeLength(musicNode.music.music)
			if Mixer_VoicePlaying(musicNode.voice) {
				t := Mixer_VoiceTime(musicNode.voice)
				musicNode.timePlayed = math.mod(t, musicNode.timeLength) if musicNode.timeLength > 0 else t
				Mixer_SetVoiceBus(musicNode.voice, MusicNode_BusIndex(musicNode))
			} else if !musicNode.looping {
				musicNode.isPlaying = false
				musicNode.timePlayed = musicNode.timeLength
				musicNode.onFinished->notify(musicNode, nil, gameContext)
			}
		} else {
			// Headless / simulated advance for testing
			musicNode.timePlayed += deltaTime
			if musicNode.timeLength > 0 && musicNode.timePlayed >= musicNode.timeLength {
				if musicNode.looping {
					musicNode.timePlayed = math.mod(musicNode.timePlayed, musicNode.timeLength)
				} else {
					musicNode.timePlayed = musicNode.timeLength
					musicNode.isPlaying = false
					musicNode.onFinished->notify(musicNode, nil, gameContext)
				}
			}
		}
	}
}

MusicNode_Destroy :: proc(node: ^Node, gameContext: ^GameContext) {
	musicNode := cast(^MusicNode)node
	if musicNode == nil do return
	DestroySubject(&musicNode.onFinished)
	if musicNode.isPlaying {
		MusicNode_Stop(musicNode)
	}
	if musicNode.music != nil {
		ResourceManager_ReleaseMusic(Node_ResourceManager(musicNode), musicNode.music)
		musicNode.music = nil
	}
}

MusicNode_Play :: proc(musicNode: ^MusicNode) {
	if musicNode == nil {
		log.error("MusicNode is nil")
		return
	}
	if musicNode.music == nil {
		log.warn("MusicNode.music is nil")
		musicNode.isPlaying = true
		musicNode.isPaused = false
		return
	}

	if music_ok(musicNode) && Audio_Ready() {
		if musicNode.isPaused && Mixer_VoicePlaying(musicNode.voice) {
			Mixer_SetVoicePaused(musicNode.voice, false)
		} else {
			Mixer_StopVoice(musicNode.voice)
			musicNode.voice = Mixer_PlayMusic(musicNode.music.music, MusicNode_BusIndex(musicNode), MusicNode_EffectiveVolume(musicNode), musicNode.looping, owner = musicNode.music)
			Mixer_SetVoice(musicNode.voice, MusicNode_EffectiveVolume(musicNode), music_mixer_pan(musicNode.pan), musicNode.pitch)
			if musicNode.caption != "" do Subtitles_Show(musicNode.caption, "", 4, .Caption)
		}
	}

	musicNode.isPlaying = true
	musicNode.isPaused = false
}

MusicNode_Stop :: proc(musicNode: ^MusicNode) {
	if musicNode == nil do return

	Mixer_StopVoice(musicNode.voice)
	musicNode.voice = {}

	musicNode.isPlaying = false
	musicNode.isPaused = false
	musicNode.timePlayed = 0
}

MusicNode_Pause :: proc(musicNode: ^MusicNode) {
	if musicNode == nil do return

	if musicNode.isPlaying && !musicNode.isPaused {
		Mixer_SetVoicePaused(musicNode.voice, true)
		musicNode.isPaused = true
	}
}

MusicNode_Resume :: proc(musicNode: ^MusicNode) {
	if musicNode == nil do return

	if musicNode.isPaused {
		Mixer_SetVoicePaused(musicNode.voice, false)
		musicNode.isPaused = false
		musicNode.isPlaying = true
	}
}

MusicNode_Seek :: proc(musicNode: ^MusicNode, positionInSeconds: f32) {
	if musicNode == nil do return

	targetPos := max(positionInSeconds, 0)
	if musicNode.timeLength > 0 {
		targetPos = min(targetPos, musicNode.timeLength)
	}

	// A new voice from there (the decoder seeks).
	if music_ok(musicNode) && Mixer_VoicePlaying(musicNode.voice) && Audio_Ready() {
		paused := musicNode.isPaused
		Mixer_StopVoice(musicNode.voice)
		musicNode.voice = Mixer_PlayMusic(musicNode.music.music, MusicNode_BusIndex(musicNode), MusicNode_EffectiveVolume(musicNode), musicNode.looping, owner = musicNode.music, startSeconds = targetPos)
		Mixer_SetVoice(musicNode.voice, MusicNode_EffectiveVolume(musicNode), music_mixer_pan(musicNode.pan), musicNode.pitch)
		Mixer_SetVoicePaused(musicNode.voice, paused)
	}
	musicNode.timePlayed = targetPos
}

MusicNode_SetVolume :: proc(musicNode: ^MusicNode, volume: f32) {
	if musicNode == nil do return
	musicNode.volume = math.clamp(volume, 0.0, 1.0)
	MusicNode_ApplyVolume(musicNode)
}

MusicNode_SetPitch :: proc(musicNode: ^MusicNode, pitch: f32) {
	if musicNode == nil do return
	musicNode.pitch = max(pitch, 0.01)
	MusicNode_ApplyVolume(musicNode)
}

// music_mixer_pan: Pan (0 left, 0.5 centre, 1 right) as the mixer's
// (-1 left .. 1 right). Not raylib's pan, which is the other way (#216).
music_mixer_pan :: #force_inline proc(p: f32) -> f32 {return clamp((p - 0.5) * 2, -1, 1)}

MusicNode_SetPan :: proc(musicNode: ^MusicNode, pan: f32) {
	if musicNode == nil do return
	musicNode.pan = math.clamp(pan, 0.0, 1.0)
	MusicNode_ApplyVolume(musicNode)
}

MusicNode_SetLooping :: proc(musicNode: ^MusicNode, looping: bool) {
	if musicNode == nil do return
	musicNode.looping = looping
	Mixer_SetVoiceLoop(musicNode.voice, looping)
}

MusicNode_IsPlaying :: proc(musicNode: ^MusicNode) -> bool {
	if musicNode == nil do return false
	return musicNode.isPlaying && !musicNode.isPaused
}

MusicNode_GetTimeLength :: proc(musicNode: ^MusicNode) -> f32 {
	if musicNode == nil do return 0
	return musicNode.timeLength
}

MusicNode_GetTimePlayed :: proc(musicNode: ^MusicNode) -> f32 {
	if musicNode == nil do return 0
	return musicNode.timePlayed
}

MusicNode_GetProgress :: proc(musicNode: ^MusicNode) -> f32 {
	if musicNode == nil || musicNode.timeLength <= 0 do return 0
	return math.clamp(musicNode.timePlayed / musicNode.timeLength, 0.0, 1.0)
}

// MusicNode_EffectiveVolume: volume x fade (its bus fader applies in the mixer).
MusicNode_EffectiveVolume :: proc(m: ^MusicNode) -> f32 {
	return m.volume * m.fadeVolume * (m.music.gain if m.music != nil && m.music.gain > 0 else 1)
}

// MusicNode_ApplyVolume pushes volume, pan and pitch to its voice.
MusicNode_ApplyVolume :: proc(m: ^MusicNode) {
	Mixer_SetVoice(m.voice, MusicNode_EffectiveVolume(m), music_mixer_pan(m.pan), m.pitch)
}

// MusicNode_FadeTo fades the track's volume factor to `target` (0..1) over
// `seconds` (starting it if needed); stopAtEnd stops it when the fade ends.
MusicNode_FadeTo :: proc(m: ^MusicNode, target, seconds: f32, stopAtEnd := false) {
	if m == nil do return
	if !m.isPlaying || m.isPaused {
		if target <= 0 do return
		m.fadeVolume = 0
		MusicNode_Play(m)
	}
	m.fadeStart = m.fadeVolume
	m.fadeTarget = clamp(target, 0, 1)
	m.fadeTime = max(seconds, 0.0001)
	m.fadeElapsed = 0
	m.fadeStop = stopAtEnd
	MusicNode_ApplyVolume(m)
}

// MusicNode_Crossfade fades `from` out (and stops it) while `to` fades in.
MusicNode_Crossfade :: proc(from, to: ^MusicNode, seconds: f32) {
	if from != nil && from != to do MusicNode_FadeTo(from, 0, seconds, stopAtEnd = true)
	if to != nil do MusicNode_FadeTo(to, 1, seconds)
}

@(private = "file")
music_fade_step :: proc(m: ^MusicNode, dt: f32) {
	m.fadeElapsed += dt
	t := clamp(m.fadeElapsed / m.fadeTime, 0, 1)
	m.fadeVolume = m.fadeStart + (m.fadeTarget - m.fadeStart) * t
	MusicNode_ApplyVolume(m)
	if t >= 1 {
		m.fadeTime = 0
		if m.fadeStop && m.fadeTarget <= 0 {
			MusicNode_Stop(m)
			m.fadeVolume = 1 // a later play starts at full volume
			m.fadeTarget = 1
		}
	}
}
