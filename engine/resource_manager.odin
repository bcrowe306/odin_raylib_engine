package engine

import "core:path/filepath"
import "core:fmt"
import "core:log"
import "core:os"
import rl "vendor:raylib"

MAX_TEXTURES :: 1000
MAX_AUDIOSOUNDS :: 1000
MAX_AUDIOMUSIC :: 1000


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

AudioMusic :: struct {
	filePath: string,
	fileName: string,
	music: rl.Music,
	refCount: int,
}

ResourceManager :: struct {
	textures: [dynamic]Texture,
	audioSounds: [MAX_AUDIOSOUNDS]AudioSound,
	audioMusic: [MAX_AUDIOMUSIC]AudioMusic,
	textureCount: int,
	audioCount: int,
	musicCount: int,
	loadTexture: proc(resourceManager: ^ResourceManager, filePath: string) -> (texture: ^Texture, ok: bool),
	getTexture: proc(rm: ^ResourceManager, fileName: string) -> (texture: ^Texture, ok: bool),
	unloadTexture: proc(rm: ^ResourceManager, fileName: string),
	loadAudioSound: proc(rm: ^ResourceManager, filePath: string) -> (audioSound: ^AudioSound, ok: bool),
	getAudioSound: proc(rm: ^ResourceManager, fileName: string) -> (texture: ^AudioSound, ok: bool),
	unloadAudioSound: proc(rm: ^ResourceManager, fileName: string),
	loadAudioMusic: proc(rm: ^ResourceManager, filePath: string) -> (audioMusic: ^AudioMusic, ok: bool),
	getAudioMusic: proc(rm: ^ResourceManager, fileName: string) -> (audioMusic: ^AudioMusic, ok: bool),
	unloadAudioMusic: proc(rm: ^ResourceManager, fileName: string),
}

ResourceManager_Init :: proc(rm: ^ResourceManager) {
	rm.loadTexture = LoadTexture_FilePath
	rm.getTexture = GetTexture
	rm.unloadTexture = UnloadTexture
	rm.loadAudioSound = ResourceManager_LoadAudioSound
	rm.getAudioSound = GetAudioSound
	rm.unloadAudioSound = UnloadAudioSound
	rm.loadAudioMusic = ResourceManager_LoadAudioMusic
	rm.getAudioMusic = GetAudioMusic
	rm.unloadAudioMusic = UnloadAudioMusic
}

ResourceManager_Terminate :: proc(rm: ^ResourceManager) {
	if rm == nil do return
	for &tex in rm.textures {
		if tex.texture.id > 0 && rl.IsWindowReady() {
			rl.UnloadTexture(tex.texture)
			tex.texture.id = 0
		}
	}
	delete(rm.textures)
	rm.textures = nil

	for i in 0..<rm.audioCount {
		audio := &rm.audioSounds[i]
		if audio.sound.frameCount > 0 && rl.IsAudioDeviceReady() {
			rl.UnloadSound(audio.sound)
		}
	}
	rm.audioCount = 0

	for i in 0..<rm.musicCount {
		m := &rm.audioMusic[i]
		if rl.IsAudioDeviceReady() && rl.IsMusicValid(m.music) {
			rl.UnloadMusicStream(m.music)
		}
	}
	rm.musicCount = 0
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
			texture2d: rl.Texture2D
			if rl.IsWindowReady() {
				texture2d = rl.LoadTexture(fmt.ctprint(filePath))
			}
			texture := Texture {
				fileName = filepath.base(filePath),
				filePath = filePath,
				texture = texture2d,
				refCount = 1,
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
			log.errorf("Filepath: %s, is not a file", filePath)
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


ResourceManager_LoadAudioSound :: proc(rm: ^ResourceManager, filePath: string) -> (audioSound: ^AudioSound, ok: bool) {
	for &audio in rm.audioSounds {
		if audio.filePath == filePath {
			audio.refCount += 1
			log.warn("AudioSound already loaded. returning loaded audio")
			return &audio, true
		}
	}

	if os.exists(filePath) {
		if os.is_file(filePath) {
			if rm.audioCount < MAX_AUDIOSOUNDS {
				idx := rm.audioCount
				rm.audioCount += 1
				snd: rl.Sound
				if rl.IsAudioDeviceReady() {
					snd = rl.LoadSound(fmt.ctprint(filePath))
				}
				rm.audioSounds[idx] = AudioSound {
					fileName = filepath.base(filePath),
					filePath = filePath,
					sound = snd,
					refCount = 1,
				}
				return &rm.audioSounds[idx], true
			}

		}
		else {
			log.errorf("Filepath: %s, is not a file", filePath)
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


ResourceManager_LoadAudioMusic :: proc(rm: ^ResourceManager, filePath: string) -> (audioMusic: ^AudioMusic, ok: bool) {
	for &m in rm.audioMusic {
		if m.filePath == filePath {
			m.refCount += 1
			log.warn("AudioMusic already loaded. returning loaded music")
			return &m, true
		}
	}

	if os.exists(filePath) {
		if os.is_file(filePath) {
			if rm.musicCount < MAX_AUDIOMUSIC {
				idx := rm.musicCount
				rm.musicCount += 1
				mus: rl.Music
				if rl.IsAudioDeviceReady() {
					mus = rl.LoadMusicStream(fmt.ctprint(filePath))
				}
				rm.audioMusic[idx] = AudioMusic {
					fileName = filepath.base(filePath),
					filePath = filePath,
					music = mus,
					refCount = 1,
				}
				return &rm.audioMusic[idx], true
			}
		} else {
			log.errorf("Filepath: %s, is not a file", filePath)
			return nil, false
		}
	} else {
		log.errorf("Filepath: %s, does not exist", filePath)
		return nil, false
	}
	return nil, false
}

GetAudioMusic :: proc(rm: ^ResourceManager, fileName: string) -> (audioMusic: ^AudioMusic, ok: bool) {
	for &m in rm.audioMusic {
		if m.fileName == fileName {
			m.refCount += 1
			return &m, true
		}
	}
	return nil, false
}

UnloadAudioMusic :: proc(rm: ^ResourceManager, fileName: string) {
	for &m in rm.audioMusic {
		if m.fileName == fileName {
			m.refCount -= 1
		}
	}
}
