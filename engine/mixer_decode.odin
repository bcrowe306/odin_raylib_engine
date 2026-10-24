package engine

import "core:c"
import rl "vendor:raylib"

// ============================================================================
// Music decoding for the mixer (mixer.odin): raylib opens a music file and
// keeps its decoder (dr_wav, stb_vorbis, dr_mp3, qoa, jar_xm, jar_mod) in
// Music.ctxData; the mixer never plays that Music through raylib - it pulls
// decoded frames from the same decoder on the audio thread. raylib exports
// these decoders' functions (they're compiled into libraylib), so they're
// declared here without linking anything else (a second miniaudio / stb
// would collide with raylib's symbols).
// ============================================================================

when ODIN_OS == .Windows {
	foreign import raydec "system:kernel32.lib" // (any always-linked library: the symbols come from raylib)
} else when ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32 {
	foreign import raydec "env.o" // (web: resolved against the emcc-built raylib; a "system:" module would stay an import)
} else {
	foreign import raydec "system:c"
}

@(default_calling_convention = "c")
foreign raydec {
	drwav_read_pcm_frames_f32 :: proc(pWav: rawptr, framesToRead: u64, pBufferOut: [^]f32) -> u64 ---
	drwav_seek_to_pcm_frame :: proc(pWav: rawptr, targetFrameIndex: u64) -> b32 ---
	stb_vorbis_get_samples_float_interleaved :: proc(f: rawptr, channels: c.int, buffer: [^]f32, num_floats: c.int) -> c.int ---
	stb_vorbis_seek_start :: proc(f: rawptr) -> c.int ---
	stb_vorbis_seek :: proc(f: rawptr, sample_number: c.uint) -> c.int ---
	drmp3_read_pcm_frames_f32 :: proc(pMP3: rawptr, framesToRead: u64, pBufferOut: [^]f32) -> u64 ---
	drmp3_seek_to_pcm_frame :: proc(pMP3: rawptr, frameIndex: u64) -> b32 ---
	qoaplay_decode :: proc(qoa_ctx: rawptr, sample_data: [^]f32, num_samples: c.int) -> c.uint ---
	qoaplay_rewind :: proc(qoa_ctx: rawptr) ---
	jar_xm_generate_samples :: proc(ctx: rawptr, output: [^]f32, numsamples: c.size_t) ---
	jar_xm_reset :: proc(ctx: rawptr) ---
	jar_mod_fillbuffer :: proc(modctx: rawptr, outbuffer: [^]i16, nbsample: c.ulong, trkbuf: rawptr) ---
	jar_mod_seek_start :: proc(ctx: rawptr) ---
}

// raylib's MusicContextType (raudio.c).
Music_Ctx :: enum c.int {
	None = 0,
	Wav,
	Ogg,
	Flac,
	Mp3,
	Qoa,
	Xm,
	Mod,
}

// music_decode reads up to `frames` frames from a music decoder into `out`
// (interleaved, `channels` per frame - the stream's). Returns the frames
// read (0 at the end). `scratch` holds 16-bit samples for MOD.
music_decode :: proc(m: ^rl.Music, out: []f32, frames: int, channels: int, scratch: []i16) -> int {
	if m.ctxData == nil || frames <= 0 do return 0
	switch Music_Ctx(m.ctxType) {
	case .Wav: return int(drwav_read_pcm_frames_f32(m.ctxData, u64(frames), raw_data(out)))
	case .Ogg: return int(stb_vorbis_get_samples_float_interleaved(m.ctxData, c.int(channels), raw_data(out), c.int(frames * channels)))
	case .Mp3: return int(drmp3_read_pcm_frames_f32(m.ctxData, u64(frames), raw_data(out)))
	case .Qoa: return int(qoaplay_decode(m.ctxData, raw_data(out), c.int(frames)))
	case .Xm:
		jar_xm_generate_samples(m.ctxData, raw_data(out), c.size_t(frames))
		return frames // (a module plays forever; it loops by itself)
	case .Mod:
		n := min(frames, len(scratch) / 2)
		jar_mod_fillbuffer(m.ctxData, raw_data(scratch), c.ulong(n), nil)
		for i in 0 ..< n * 2 do out[i] = f32(scratch[i]) / 32768
		return n
	case .Flac, .None:
	}
	return 0
}

// music_rewind seeks a music decoder back to the start.
music_rewind :: proc(m: ^rl.Music) {
	if m.ctxData == nil do return
	switch Music_Ctx(m.ctxType) {
	case .Wav: drwav_seek_to_pcm_frame(m.ctxData, 0)
	case .Ogg: stb_vorbis_seek_start(m.ctxData)
	case .Mp3: drmp3_seek_to_pcm_frame(m.ctxData, 0)
	case .Qoa: qoaplay_rewind(m.ctxData)
	case .Xm: jar_xm_reset(m.ctxData)
	case .Mod: jar_mod_seek_start(m.ctxData)
	case .Flac, .None:
	}
}

// music_seek puts a decoder at a frame (the start for formats without seeking).
music_seek :: proc(m: ^rl.Music, frame: u64) {
	if m.ctxData == nil do return
	#partial switch Music_Ctx(m.ctxType) {
	case .Wav: drwav_seek_to_pcm_frame(m.ctxData, frame)
	case .Mp3: drmp3_seek_to_pcm_frame(m.ctxData, frame)
	case .Ogg: stb_vorbis_seek(m.ctxData, c.uint(frame))
	case: music_rewind(m) // (others: from the start)
	}
}
