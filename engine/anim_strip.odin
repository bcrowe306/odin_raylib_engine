package engine

import os "osx" // (core:os doesn't build for the web)
import "core:strings"
import rl "vendor:raylib"

// Anim_Strip: an animated file's frames, top to bottom in one image, with
// each frame's time (seconds) - previews of Aseprite files and animated
// GIFs (#203). Safe to load on a worker thread (no GL).
Anim_Strip :: struct {
	image:     rl.Image, // frameSize.x wide, frameSize.y * frames tall
	frameSize: [2]int,
	durations: []f32, // (heap)
}

// GIF frame times aren't exposed by raylib: a common 10 fps.
ANIM_GIF_FRAME_TIME :: f32(0.1)

// Anim_LoadFileStrip loads an Aseprite file or a GIF with 2+ frames.
Anim_LoadFileStrip :: proc(path: string) -> (strip: Anim_Strip, ok: bool) {
	lower := strings.to_lower(path, context.temp_allocator)
	if Ase_IsPath(lower) {
		data, err := os.read_entire_file(path, context.temp_allocator)
		if err != nil do return {}, false
		doc, _ := Ase_Load(data)
		if doc == nil do return {}, false
		defer Ase_Destroy(doc)
		n := len(doc.frames)
		if n < 2 do return {}, false
		w, h := doc.width, doc.height
		strip.image = rl.GenImageColor(i32(w), i32(h * n), {0, 0, 0, 0})
		px := ([^]u8)(strip.image.data)
		strip.durations = make([]f32, n)
		for f in 0 ..< n {
			Ase_RenderFrame(doc, f, px[f * w * h * 4:][:w * h * 4])
			strip.durations[f] = f32(max(doc.frames[f].duration, 1)) / 1000
		}
		strip.frameSize = {w, h}
		return strip, true
	}
	if strings.has_suffix(lower, ".gif") {
		frames: i32
		img := rl.LoadImageAnim(strings.clone_to_cstring(path, context.temp_allocator), &frames)
		if img.data == nil do return {}, false
		if frames < 2 {
			rl.UnloadImage(img)
			return {}, false
		}
		// (raylib stacks GIF frames top to bottom: height is one frame's.)
		strip.frameSize = {int(img.width), int(img.height)}
		full := rl.GenImageColor(img.width, img.height * frames, {0, 0, 0, 0})
		rl.ImageFormat(&img, .UNCOMPRESSED_R8G8B8A8)
		size := int(img.width * img.height * 4)
		copy(([^]u8)(full.data)[:size * int(frames)], ([^]u8)(img.data)[:size * int(frames)])
		rl.UnloadImage(img)
		strip.image = full
		strip.durations = make([]f32, int(frames))
		for &d in strip.durations do d = ANIM_GIF_FRAME_TIME
		return strip, true
	}
	return {}, false
}

Anim_StripDestroy :: proc(strip: ^Anim_Strip) {
	if strip.image.data != nil do rl.UnloadImage(strip.image)
	delete(strip.durations)
	strip^ = {}
}

// Anim_StripFrameRect: frame i's rect in the strip.
Anim_StripFrameRect :: proc(strip: Anim_Strip, i: int) -> rl.Rectangle {
	w, h := f32(strip.frameSize.x), f32(strip.frameSize.y)
	return {0, f32(i) * h, w, h}
}

// Anim_StripFrameAt: the frame shown `t` seconds in (looping or held on the
// last frame).
Anim_StripFrameAt :: proc(durations: []f32, t: f32, loop: bool) -> int {
	total: f32
	for d in durations do total += d
	if len(durations) == 0 || total <= 0 do return 0
	x := t
	if loop {
		for x >= total do x -= total
	} else if x >= total {
		return len(durations) - 1
	}
	for d, i in durations {
		if x < d do return i
		x -= d
	}
	return len(durations) - 1
}
