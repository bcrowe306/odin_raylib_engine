package engine

import "core:path/filepath"
import "core:fmt"
import "core:log"
import "core:os"
import "core:strings"
import "core:time"
import rl "vendor:raylib"

MAX_TEXTURES :: 1000
MAX_AUDIOSOUNDS :: 1000
MAX_AUDIOMUSIC :: 1000


Texture :: struct {
	filePath: string,
	fileName: string,
	texture: rl.Texture2D,
	refCount: int,
	modTime: time.Time, // of the file when loaded (hot reload)
}

AudioSound :: struct {
	filePath: string,
	fileName: string,
	sound: rl.Sound,
	refCount: int,
	aliases: [dynamic]rl.Sound, // extra voices sharing the samples (audio.odin)
	nextVoice: int,
}

AudioMusic :: struct {
	filePath: string,
	fileName: string,
	music: rl.Music,
	refCount: int,
	streamData: []byte, // in-memory stream source (assets from a .ore package)
}

ResourceManager :: struct {
	textures: [dynamic]^Texture,
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

	// Exported games: resources missing on disk are read from the mounted
	// .ore package (paths relative to projectDir).
	package_: ^OrePackage,
	projectDir: string,
}

ResourceManager_Init :: proc(rm: ^ResourceManager) {
	rm.textures = make([dynamic]^Texture)
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
	for tex in rm.textures {
		if tex != nil {
			if tex.texture.id > 0 && rl.IsWindowReady() {
				rl.UnloadTexture(tex.texture)
				tex.texture.id = 0
			}
			delete(tex.filePath)
			free(tex)
		}
	}
	delete(rm.textures)
	rm.textures = nil

	for i in 0..<rm.audioCount {
		audio := &rm.audioSounds[i]
		Audio_ReleaseVoices(audio)
		if audio.sound.frameCount > 0 && rl.IsAudioDeviceReady() {
			rl.UnloadSound(audio.sound)
		}
		delete(audio.filePath)
		audio^ = {}
	}
	rm.audioCount = 0

	for i in 0..<rm.musicCount {
		m := &rm.audioMusic[i]
		if rl.IsAudioDeviceReady() && rl.IsMusicValid(m.music) {
			rl.UnloadMusicStream(m.music)
		}
		delete(m.filePath)
		delete(m.streamData)
		m^ = {}
	}
	rm.musicCount = 0
}

// resource_bytes reads a resource that isn't on disk from the mounted .ore
// package (exported games ship their assets inside it).
@(private = "file")
resource_bytes :: proc(rm: ^ResourceManager, filePath: string) -> ([]byte, bool) {
	if rm.package_ == nil do return nil, false
	rel := filePath
	if dir := rm.projectDir; dir != "" && len(rel) > len(dir) && rel[:len(dir)] == dir && rel[len(dir)] == '/' {
		rel = rel[len(dir) + 1:]
	}
	return OrePackage_ReadFile(rm.package_, rel, context.allocator)
}

@(private = "file")
file_ext_cstring :: proc(path: string) -> cstring {
	return fmt.ctprintf("%s", filepath.ext(path))
}

LoadTexture_FilePath :: proc(rm: ^ResourceManager, filePath: string) -> (texture: ^Texture, ok: bool) {
	for tex in rm.textures {
		if tex != nil && tex.filePath == filePath {
			tex.refCount += 1
			return tex, true
		}
	}

	texture2d: rl.Texture2D
	if os.is_file(filePath) {
		if rl.IsWindowReady() do texture2d = rl.LoadTexture(fmt.ctprint(filePath))
	} else if bytes, found := resource_bytes(rm, filePath); found {
		defer delete(bytes)
		if rl.IsWindowReady() {
			img := rl.LoadImageFromMemory(file_ext_cstring(filePath), raw_data(bytes), i32(len(bytes)))
			texture2d = rl.LoadTextureFromImage(img)
			rl.UnloadImage(img)
		}
	} else {
		log.errorf("Texture not found: %s", filePath)
		return nil, false
	}
	tex := new(Texture)
	// Owned copies: callers usually pass temporary strings.
	tex.filePath = strings.clone(filePath)
	tex.fileName = filepath.base(tex.filePath)
	tex.texture = texture2d
	tex.refCount = 1
	Texture_ApplyImport(&tex.texture, Texture_ImportFor(rm, filePath)) // project.json "texture_import"
	if info, serr := os.stat(filePath, context.temp_allocator); serr == nil do tex.modTime = info.modification_time
	append(&rm.textures, tex)
	return tex, true
}

GetTexture :: proc(rm: ^ResourceManager, fileName: string) -> (texture: ^Texture, ok: bool) {
	for tex in rm.textures {
		if tex != nil && tex.fileName == fileName {
			tex.refCount += 1
			return tex, true
		}
	}
	return nil ,false
}

UnloadTexture :: proc(rm: ^ResourceManager, fileName: string) {
	for tex in rm.textures {
		if tex != nil && (tex.filePath == fileName || tex.fileName == fileName) {
			ResourceManager_ReleaseTexture(rm, tex)
			return
		}
	}
}

// ResourceManager_ReleaseTexture drops one reference; the GPU texture is
// freed when nothing uses it any more.
ResourceManager_ReleaseTexture :: proc(rm: ^ResourceManager, tex: ^Texture) {
	if rm == nil || tex == nil do return
	for t, i in rm.textures {
		if t != tex do continue
		tex.refCount -= 1
		if tex.refCount > 0 do return
		if tex.texture.id > 0 && rl.IsWindowReady() do rl.UnloadTexture(tex.texture)
		delete(tex.filePath)
		free(tex)
		ordered_remove(&rm.textures, i)
		return
	}
}


ResourceManager_LoadAudioSound :: proc(rm: ^ResourceManager, filePath: string) -> (audioSound: ^AudioSound, ok: bool) {
	for i in 0 ..< rm.audioCount {
		if rm.audioSounds[i].filePath == filePath {
			rm.audioSounds[i].refCount += 1
			return &rm.audioSounds[i], true
		}
	}
	slot := -1
	for i in 0 ..< rm.audioCount {
		if rm.audioSounds[i].filePath == "" {slot = i; break}
	}
	if slot < 0 && rm.audioCount >= MAX_AUDIOSOUNDS {
		log.error("Max audios reached")
		return nil, false
	}
	sound: rl.Sound
	if os.is_file(filePath) {
		if rl.IsAudioDeviceReady() do sound = rl.LoadSound(fmt.ctprint(filePath))
	} else if bytes, found := resource_bytes(rm, filePath); found {
		defer delete(bytes)
		if rl.IsAudioDeviceReady() {
			wave := rl.LoadWaveFromMemory(file_ext_cstring(filePath), raw_data(bytes), i32(len(bytes)))
			sound = rl.LoadSoundFromWave(wave)
			rl.UnloadWave(wave)
		}
	} else {
		log.errorf("Sound not found: %s", filePath)
		return nil, false
	}
	owned := strings.clone(filePath)
	if slot < 0 {
		slot = rm.audioCount
		rm.audioCount += 1
	}
	rm.audioSounds[slot] = AudioSound{fileName = filepath.base(owned), filePath = owned, sound = sound, refCount = 1}
	return &rm.audioSounds[slot], true
}

GetAudioSound :: proc(rm: ^ResourceManager, fileName: string) -> (audioSound: ^AudioSound, ok: bool) {
	for &audio in rm.audioSounds {
		if audio.fileName == fileName {
			audio.refCount += 1
			return &audio, true
		}
	}
	return nil, false
}

UnloadAudioSound :: proc(rm: ^ResourceManager, fileName: string) {
	for i in 0 ..< rm.audioCount {
		if rm.audioSounds[i].filePath == fileName || rm.audioSounds[i].fileName == fileName {
			ResourceManager_ReleaseSound(rm, &rm.audioSounds[i])
			return
		}
	}
}

// ResourceManager_ReleaseSound drops one reference; at zero the sound is
// unloaded and its slot reused (slots never move, so other pointers stay valid).
ResourceManager_ReleaseSound :: proc(rm: ^ResourceManager, audio: ^AudioSound) {
	if rm == nil || audio == nil || audio.filePath == "" do return
	audio.refCount -= 1
	if audio.refCount > 0 do return
	Audio_ReleaseVoices(audio)
	if audio.sound.frameCount > 0 && rl.IsAudioDeviceReady() do rl.UnloadSound(audio.sound)
	delete(audio.filePath)
	audio^ = {}
}

ResourceManager_LoadAudioMusic :: proc(rm: ^ResourceManager, filePath: string) -> (audioMusic: ^AudioMusic, ok: bool) {
	for i in 0 ..< rm.musicCount {
		if rm.audioMusic[i].filePath == filePath {
			rm.audioMusic[i].refCount += 1
			return &rm.audioMusic[i], true
		}
	}
	mslot := -1
	for i in 0 ..< rm.musicCount {
		if rm.audioMusic[i].filePath == "" {mslot = i; break}
	}
	if mslot < 0 && rm.musicCount >= MAX_AUDIOMUSIC {
		log.error("Max music streams reached")
		return nil, false
	}
	music: rl.Music
	streamData: []byte
	if os.is_file(filePath) {
		if rl.IsAudioDeviceReady() do music = rl.LoadMusicStream(fmt.ctprint(filePath))
	} else if bytes, found := resource_bytes(rm, filePath); found {
		// Streams read their data lazily: keep the bytes alive with the music.
		streamData = bytes
		if rl.IsAudioDeviceReady() {
			music = rl.LoadMusicStreamFromMemory(file_ext_cstring(filePath), raw_data(bytes), i32(len(bytes)))
		}
	} else {
		log.errorf("Music not found: %s", filePath)
		return nil, false
	}
	owned := strings.clone(filePath)
	if mslot < 0 {
		mslot = rm.musicCount
		rm.musicCount += 1
	}
	rm.audioMusic[mslot] = AudioMusic{fileName = filepath.base(owned), filePath = owned, music = music, refCount = 1, streamData = streamData}
	return &rm.audioMusic[mslot], true
}

GetAudioMusic :: proc(rm: ^ResourceManager, fileName: string) -> (audioMusic: ^AudioMusic, ok: bool) {
	for &audio in rm.audioMusic {
		if audio.fileName == fileName {
			audio.refCount += 1
			return &audio, true
		}
	}
	return nil, false
}

UnloadAudioMusic :: proc(rm: ^ResourceManager, fileName: string) {
	for i in 0 ..< rm.musicCount {
		if rm.audioMusic[i].filePath == fileName || rm.audioMusic[i].fileName == fileName {
			ResourceManager_ReleaseMusic(rm, &rm.audioMusic[i])
			return
		}
	}
}

ResourceManager_ReleaseMusic :: proc(rm: ^ResourceManager, m: ^AudioMusic) {
	if rm == nil || m == nil || m.filePath == "" do return
	m.refCount -= 1
	if m.refCount > 0 do return
	if rl.IsAudioDeviceReady() && rl.IsMusicValid(m.music) {
		rl.StopMusicStream(m.music)
		rl.UnloadMusicStream(m.music)
	}
	delete(m.filePath)
	delete(m.streamData)
	m^ = {}
}

// Node_ResourceManager is the resource manager of the node's game (or nil).
Node_ResourceManager :: proc(node: ^Node) -> ^ResourceManager {
	if node != nil && node.gameContext != nil && node.gameContext.game != nil do return &node.gameContext.game.resourceManager
	return nil
}

@(private = "file")
textureCheck: time.Tick

// ResourceManager_CheckForChanges reloads textures whose files changed
// (an image edited while the game or editor runs); every user of the
// texture sees the new pixels. Stats files at most twice a second.
ResourceManager_CheckForChanges :: proc(rm: ^ResourceManager) -> int {
	if rm == nil || !rl.IsWindowReady() || time.tick_since(textureCheck) < 500 * time.Millisecond do return 0
	textureCheck = time.tick_now()
	n := 0
	for t in rm.textures {
		if t == nil || t.modTime == {} do continue
		info, err := os.stat(t.filePath, context.temp_allocator)
		if err != nil || time.diff(t.modTime, info.modification_time) <= 0 do continue
		fresh := rl.LoadTexture(strings.clone_to_cstring(t.filePath, context.temp_allocator))
		if fresh.id == 0 do continue // half-written: try again later
		t.modTime = info.modification_time
		rl.UnloadTexture(t.texture)
		t.texture = fresh
		Texture_ApplyImport(&t.texture, Texture_ImportFor(rm, t.filePath))
		log.infof("Reloaded %s", t.fileName)
		n += 1
	}
	return n
}
