package engine

import "core:log"
import rl "vendor:raylib"

SoundNode :: struct {
	using node: Node,
	audio: ^AudioSound,
	volume: f32 `gui:"true" min:"0" max:"1"`,
	pitch: f32 `gui:"true" min:"0.1" max:"3"`,
	autoplay: bool `gui:"true"`, // play once when the node becomes ready
	voices: int `gui:"true" min:"1" max:"8"`, // plays over itself up to this many times (1: restarts)
	// Positional: volume falls from minDistance to maxDistance from the
	// listener (the camera, or Audio.set_listener), pans with the side.
	positional: bool `gui:"true"`,
	minDistance: f32 `gui:"true" min:"0" max:"4000"`,
	maxDistance: f32 `gui:"true" min:"1" max:"8000"`,
	onFinished: EventSubject,    // "finished": playback reached the end
	wasPlaying: bool,
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

SoundNode_Update :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	soundNode := cast(^SoundNode)node
	if soundNode.audio == nil || !rl.IsAudioDeviceReady() do return
	playing := Audio_VoicesPlaying(soundNode.audio)
	if playing && soundNode.positional {
		// Follow the source and the listener while it plays.
		vol, pan := SoundNode_Mix(soundNode, gameContext)
		a := soundNode.audio
		rl.SetSoundVolume(a.sound, vol)
		rl.SetSoundPan(a.sound, pan)
		for s in a.aliases {
			rl.SetSoundVolume(s, vol)
			rl.SetSoundPan(s, pan)
		}
	}
	if soundNode.wasPlaying && !playing do soundNode.onFinished->notify(soundNode, nil, gameContext)
	soundNode.wasPlaying = playing
}

// SoundNode_Mix: the volume (node x bus x distance) and pan to play at.
SoundNode_Mix :: proc(sn: ^SoundNode, ctx: ^GameContext) -> (volume, pan: f32) {
	gc := ctx if ctx != nil else sn.gameContext
	volume, pan = sn.volume * Game_BusVolume(gc, music = false), 0.5
	if sn.positional {
		if listener, ok := Audio_ListenerPosition(gc); ok {
			v, p := Audio_Spatialize(sn.globalPosition, listener, sn.minDistance, sn.maxDistance, max(sn.maxDistance * 0.5, 1))
			volume *= v
			pan = p
		}
	}
	return
}

SoundNode_Destroy :: proc(node: ^Node, gameContext: ^GameContext) {
	soundNode := cast(^SoundNode)node
	DestroySubject(&soundNode.onFinished)
	if soundNode.audio != nil {
		if rl.IsAudioDeviceReady() do rl.StopSound(soundNode.audio.sound)
		ResourceManager_ReleaseSound(Node_ResourceManager(soundNode), soundNode.audio)
		soundNode.audio = nil
	}
}

SoundNode_Ready :: proc(node: ^Node, gameContext: ^GameContext) {
	soundNode := cast(^SoundNode)node
	if soundNode.audio == nil || !rl.IsAudioDeviceReady() do return
	rl.SetSoundVolume(soundNode.audio.sound, soundNode.volume * Game_BusVolume(gameContext, music = false))
	rl.SetSoundPitch(soundNode.audio.sound, soundNode.pitch)
	if soundNode.autoplay do SoundNode_Play(soundNode)
}

SoundNode_Create :: proc(scene: ^Scene, resource_manager: ^ResourceManager, filePath: string, name: string) -> ^SoundNode {
	soundNode := CreateNode(scene.manager, SoundNode)
	SoundNode_Init(soundNode)
	soundNode.name = name
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


SoundNode_Play :: proc(soundNode: ^SoundNode) {
	if soundNode != nil {
		if soundNode.audio != nil {
			if rl.IsSoundReady(soundNode.audio.sound) {
				vol, pan := SoundNode_Mix(soundNode, soundNode.gameContext)
				Audio_PlayVoice(soundNode.audio, soundNode.voices, vol, soundNode.pitch, pan)
				soundNode.wasPlaying = true
			}
			else {
				log.warn("Cannot play. SoundNode not ready")
			}
		}
		else do log.error("SoundNode.audio is nil")
	}
	else do log.error("SoundNode is nil")
}

SoundNode_Stop :: proc(soundNode: ^SoundNode) {
	if soundNode != nil {
		if soundNode.audio != nil {
			if rl.IsSoundPlaying(soundNode.audio.sound) {
				rl.StopSound(soundNode.audio.sound)
			}
		}
		else do log.error("SoundNode.audio is nil")
	}
	else do log.error("SoundNode is nil")
}

SoundNode_Pause :: proc(soundNode: ^SoundNode) {
	if soundNode != nil {
		if soundNode.audio != nil {
			if rl.IsSoundPlaying(soundNode.audio.sound) {
				rl.PauseSound(soundNode.audio.sound)
			}
		}
		else do log.error("SoundNode.audio is nil")
	}
	else do log.error("SoundNode is nil")
}

SoundNode_Resume :: proc(soundNode: ^SoundNode) {
	if soundNode != nil {
		if soundNode.audio != nil {
			if rl.IsSoundReady(soundNode.audio.sound) {
				rl.ResumeSound(soundNode.audio.sound)
			}
		}
		else do log.error("SoundNode.audio is nil")
	}
	else do log.error("SoundNode is nil")
}

SoundNode_SetVolume :: proc(soundNode: ^SoundNode, volume: f32) {
	if soundNode != nil {
		if soundNode.audio != nil {
			rl.SetSoundVolume(soundNode.audio.sound, volume * Game_BusVolume(soundNode.gameContext, music = false))
		}
		else do log.error("SoundNode.audio is nil")
	}
	else do log.error("SoundNode is nil")
}

SoundNode_SetPitch :: proc(soundNode: ^SoundNode, pitch: f32) {
	if soundNode != nil {
		if soundNode.audio != nil {
			rl.SetSoundPitch(soundNode.audio.sound, pitch)
		}
		else do log.error("SoundNode.audio is nil")
	}
	else do log.error("SoundNode is nil")
}

SoundNode_SetPan :: proc(soundNode: ^SoundNode, pan: f32) {
	if soundNode != nil {
		if soundNode.audio != nil {
			rl.SetSoundPan(soundNode.audio.sound, pan)
		}
		else do log.error("SoundNode.audio is nil")
	}
	else do log.error("SoundNode is nil")
}
