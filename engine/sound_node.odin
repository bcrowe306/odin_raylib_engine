package engine

import "core:log"
import rl "vendor:raylib"

SoundNode :: struct {
	using node: Node,
	audio: ^AudioSound,

}

SoundNode_Init :: proc(soundNode: ^SoundNode) {
	InitializeNode(soundNode)
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
				rl.PlaySound(soundNode.audio.sound)
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

SoundNode_SetVolume :: proc(soundNode: ^SoundNode, volume: f32) {
	if soundNode != nil {
		if soundNode.audio != nil {
			rl.SetSoundVolume(soundNode.audio.sound, volume)
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
