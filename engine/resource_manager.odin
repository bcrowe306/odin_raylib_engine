package engine

import "core:path/filepath"
import "core:fmt"
import "core:log"
import "core:os"
import rl "vendor:raylib"

MAX_TEXTURES :: 1000
MAX_AUDIOSOUNDS :: 1000


Texture :: struct {
	filePath: string,
	fileName: string,
	texture: rl.Texture2D,
	refCount: int,
}

AudioSound :: struct {
	filePath: string,
	fileName: string,
	sound: rl.Sound,
	refCount: int,
}

ResourceManager :: struct {
	textures: [dynamic]Texture,
	audioSounds: [MAX_AUDIOSOUNDS]AudioSound,
	textureCount: int,
	audioCount: int,
	loadTexture: proc(resourceManager: ^ResourceManager, filePath: string) -> (texture: ^Texture, ok: bool),
	getTexture: proc(rm: ^ResourceManager, fileName: string) -> (texture: ^Texture, ok: bool),
	unloadTexture: proc(rm: ^ResourceManager, fileName: string),
	loadAudioSound: proc(rm: ^ResourceManager, filePath: string) -> (audioSound: ^AudioSound, ok: bool),
	getAudioSound: proc(rm: ^ResourceManager, fileName: string) -> (texture: ^AudioSound, ok: bool),
	unloadAudioSound: proc(rm: ^ResourceManager, fileName: string),
}

ResourceManager_Init :: proc(rm: ^ResourceManager) {
	rm.loadTexture = LoadTexture_FilePath
	rm.getTexture = GetTexture
	rm.unloadTexture = UnloadTexture
	rm.loadAudioSound = ResourceManager_LoadAudioSound
	rm.getAudioSound = GetAudioSound
	rm.unloadAudioSound = UnloadAudioSound
}

LoadTexture_FilePath :: proc(rm: ^ResourceManager, filePath: string) -> (texture: ^Texture, ok: bool) {

	for &tex in rm.textures {
		if tex.filePath == filePath {
			tex.refCount += 1
			log.warn("Texture already loaded. returning loaded texture")
			return &tex, true
		}
	}

	if os.exists(filePath) {
		if os.is_file(filePath) {
			texture2d := rl.LoadTexture(fmt.ctprint(filePath))
			texture := Texture {
				fileName = filepath.base(filePath),
				filePath = filePath,
				texture = texture2d,
				refCount = 1
			}
			count, err := append(&rm.textures, texture)
			if count != 1 {
				log.error("Append not 1")
			}

			if err != nil {
				log.error(err)
			}
			return &rm.textures[len(rm.textures) - 1], true

		}
		else {
			log.errorf("Filepath: %s, is not a file")
			return nil, false
		}
	}
	else {
		log.errorf("Filepath: %s, does not exist", filePath)
		return nil, false
	}
	return nil, false
}

GetTexture :: proc(rm: ^ResourceManager, fileName: string) -> (texture: ^Texture, ok: bool) {
	for &tex in rm.textures {
		if tex.fileName == fileName {
			tex.refCount += 1
			return &tex, true
		}
	}
	return nil ,false
}

UnloadTexture :: proc(rm: ^ResourceManager, fileName: string) {
	for &tex in rm.textures {
		if tex.fileName == fileName {
			tex.refCount -= 1
		}
	}
}

ProcessTextures :: proc(rm: ^ResourceManager) {
	for &tex in rm.textures {
		if tex.refCount <= 0 {
			rl.UnloadTexture(tex.texture)
		}
	}
}


ResourceManager_LoadAudioSound :: proc(rm: ^ResourceManager, filePath: string) -> (audioSound: ^AudioSound, ok: bool) {
	for &audio in rm.audioSounds {
		if audio.filePath == filePath {
			audio.refCount += 1
			return &audio, true
		}
	}

	if os.exists(filePath) {
		if os.is_file(filePath) {
			if rm.audioCount < MAX_AUDIOSOUNDS {
				rm.audioSounds[rm.audioCount] = AudioSound {
					fileName = filepath.base(filePath),
					filePath = filePath,
					sound = rl.LoadSound(fmt.ctprint(filePath)),
					refCount = 1
				}
				rm.audioCount += 1
				return &rm.audioSounds[rm.audioCount], true
			}

		}
		else {
			log.errorf("Filepath: %s, is not a file")
			return nil, false
		}
	}
	else {
		log.errorf("Filepath: %s, does not exist", filePath)
		return nil, false
	}
	return nil, false
}


GetAudioSound :: proc(rm: ^ResourceManager, fileName: string) -> (texture: ^AudioSound, ok: bool) {
	for &audio in rm.audioSounds {
		if audio.fileName == fileName {
			audio.refCount += 1
			return &audio, true
		}
	}
	return nil ,false
}

UnloadAudioSound :: proc(rm: ^ResourceManager, fileName: string) {
	for &audio in rm.audioSounds {
		if audio.fileName == fileName {
			audio.refCount -= 1
		}
	}
}
