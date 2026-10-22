package engine

import "core:log"
import "core:math"
import rl "vendor:raylib"

MusicNode :: struct {
	using node: Node,
	music:      ^AudioMusic,
	volume:     f32 `gui:"true" min:"0" max:"1"`,
	pitch:      f32 `gui:"true" min:"0.1" max:"3"`,
	pan:        f32 `gui:"true" min:"0" max:"1"`,
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
	musicNode.name = name
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

	// When music is actively streaming, we must feed Raylib's audio stream buffer every frame!
	if musicNode.isPlaying && !musicNode.isPaused {
		if rl.IsAudioDeviceReady() && rl.IsMusicValid(musicNode.music.music) {
			rl.UpdateMusicStream(musicNode.music.music)
			musicNode.timePlayed = rl.GetMusicTimePlayed(musicNode.music.music)
			musicNode.timeLength = rl.GetMusicTimeLength(musicNode.music.music)

			// If music stopped playing and looping is disabled, transition isPlaying to false
			if !musicNode.looping && !rl.IsMusicStreamPlaying(musicNode.music.music) {
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

	if rl.IsAudioDeviceReady() && rl.IsMusicValid(musicNode.music.music) {
		musicNode.music.music.looping = musicNode.looping
		rl.SetMusicVolume(musicNode.music.music, MusicNode_EffectiveVolume(musicNode))
		rl.SetMusicPitch(musicNode.music.music, musicNode.pitch)
		rl.SetMusicPan(musicNode.music.music, musicNode.pan)

		if musicNode.isPaused {
			rl.ResumeMusicStream(musicNode.music.music)
		} else {
			rl.PlayMusicStream(musicNode.music.music)
		}
	}

	musicNode.isPlaying = true
	musicNode.isPaused = false
}

MusicNode_Stop :: proc(musicNode: ^MusicNode) {
	if musicNode == nil do return

	if musicNode.music != nil && rl.IsAudioDeviceReady() && rl.IsMusicValid(musicNode.music.music) {
		if rl.IsMusicStreamPlaying(musicNode.music.music) || musicNode.isPaused {
			rl.StopMusicStream(musicNode.music.music)
		}
	}

	musicNode.isPlaying = false
	musicNode.isPaused = false
	musicNode.timePlayed = 0
}

MusicNode_Pause :: proc(musicNode: ^MusicNode) {
	if musicNode == nil do return

	if musicNode.isPlaying && !musicNode.isPaused {
		if musicNode.music != nil && rl.IsAudioDeviceReady() && rl.IsMusicValid(musicNode.music.music) {
			if rl.IsMusicStreamPlaying(musicNode.music.music) {
				rl.PauseMusicStream(musicNode.music.music)
			}
		}
		musicNode.isPaused = true
	}
}

MusicNode_Resume :: proc(musicNode: ^MusicNode) {
	if musicNode == nil do return

	if musicNode.isPaused {
		if musicNode.music != nil && rl.IsAudioDeviceReady() && rl.IsMusicValid(musicNode.music.music) {
			rl.ResumeMusicStream(musicNode.music.music)
		}
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

	if musicNode.music != nil && rl.IsAudioDeviceReady() && rl.IsMusicValid(musicNode.music.music) {
		rl.SeekMusicStream(musicNode.music.music, targetPos)
	}
	musicNode.timePlayed = targetPos
}

MusicNode_SetVolume :: proc(musicNode: ^MusicNode, volume: f32) {
	if musicNode == nil do return
	musicNode.volume = math.clamp(volume, 0.0, 1.0)
	if musicNode.music != nil && rl.IsAudioDeviceReady() && rl.IsMusicValid(musicNode.music.music) {
		rl.SetMusicVolume(musicNode.music.music, musicNode.volume * Game_BusVolume(musicNode.gameContext, music = true))
	}
}

MusicNode_SetPitch :: proc(musicNode: ^MusicNode, pitch: f32) {
	if musicNode == nil do return
	musicNode.pitch = max(pitch, 0.01)
	if musicNode.music != nil && rl.IsAudioDeviceReady() && rl.IsMusicValid(musicNode.music.music) {
		rl.SetMusicPitch(musicNode.music.music, musicNode.pitch)
	}
}

MusicNode_SetPan :: proc(musicNode: ^MusicNode, pan: f32) {
	if musicNode == nil do return
	musicNode.pan = math.clamp(pan, 0.0, 1.0)
	if musicNode.music != nil && rl.IsAudioDeviceReady() && rl.IsMusicValid(musicNode.music.music) {
		rl.SetMusicPan(musicNode.music.music, musicNode.pan)
	}
}

MusicNode_SetLooping :: proc(musicNode: ^MusicNode, looping: bool) {
	if musicNode == nil do return
	musicNode.looping = looping
	if musicNode.music != nil {
		musicNode.music.music.looping = looping
	}
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

// MusicNode_EffectiveVolume: volume x fade x the music bus.
MusicNode_EffectiveVolume :: proc(m: ^MusicNode) -> f32 {
	return m.volume * m.fadeVolume * Game_BusVolume(m.gameContext, music = true)
}

// MusicNode_ApplyVolume pushes the effective volume to the stream.
MusicNode_ApplyVolume :: proc(m: ^MusicNode) {
	if m.music != nil && rl.IsAudioDeviceReady() && rl.IsMusicValid(m.music.music) {
		rl.SetMusicVolume(m.music.music, MusicNode_EffectiveVolume(m))
	}
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
