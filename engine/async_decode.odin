package engine

import "base:runtime"
import "core:strings"
import "core:sync"
import "core:thread"
import rl "vendor:raylib"

// ============================================================================
// Background image decoding for scene preloads (scene_flow.odin).
//
// Decoding a PNG is the slow part of loading a texture; the GPU upload must
// stay on the main thread (OpenGL). A preload reads a file's bytes on the
// main thread (packed .ore archives aren't safe to read from two threads),
// hands them to a small thread pool that decodes them into an rl.Image, and
// uploads finished images a few per frame (Decode_Pump).
//
// Ownership: jobs live in `decoder.jobs` (heap) from submission until the
// main thread pops them done - a preload that is released meanwhile only
// marks its job abandoned, so a worker never writes into freed memory.
// ============================================================================

Decode_Job :: struct {
	path:      string,  // resolved path (the texture cache key; heap)
	ext:       cstring, // ".png" (heap)
	bytes:     []u8,    // the file (heap; freed by the worker once decoded)
	image:     rl.Image,
	size:      [2]i32,  // decoded size (worker)
	abandoned: bool,    // main thread only: nobody wants it any more
	texture:   ^Texture, // main thread: the uploaded texture (held for its preload)
	uploaded:  bool,
}

@(private = "file")
decoder: struct {
	pool:    thread.Pool,
	started: bool,
	jobs:    [dynamic]^Decode_Job, // in flight (heap)
}

DECODE_THREADS :: 2

// Decode_Submit queues a file's bytes (taken over) for decoding.
Decode_Submit :: proc(path: string, bytes: []u8) -> ^Decode_Job {
	a := runtime.heap_allocator()
	if !decoder.started {
		thread.pool_init(&decoder.pool, a, DECODE_THREADS)
		thread.pool_start(&decoder.pool)
		decoder.jobs = make([dynamic]^Decode_Job, a)
		decoder.started = true
	}
	j := new(Decode_Job, a)
	j.path = strings.clone(path, a)
	ext := path[strings.last_index_byte(path, '.'):] if strings.last_index_byte(path, '.') >= 0 else ".png"
	j.ext = strings.clone_to_cstring(ext, a)
	j.bytes = bytes
	append(&decoder.jobs, j)
	thread.pool_add_task(&decoder.pool, a, decode_task, j)
	return j
}

// decode_task (worker): bytes -> image. Touches only its job.
@(private = "file")
decode_task :: proc(t: thread.Task) {
	j := cast(^Decode_Job)t.data
	j.image = rl.LoadImageFromMemory(j.ext, raw_data(j.bytes), i32(len(j.bytes)))
	j.size = {j.image.width, j.image.height}
	delete(j.bytes, runtime.heap_allocator())
	j.bytes = nil
	sync.atomic_thread_fence(.Release)
}

// Decode_Pump (main thread, every frame): uploads decoded images (cached in
// the resource manager under their path), drops abandoned ones. A job
// stays listed until its preload collects it (Decode_Collect).
Decode_Pump :: proc(rm: ^ResourceManager, budget := 4) {
	if !decoder.started do return
	n := 0
	for n < budget {
		task, ok := thread.pool_pop_done(&decoder.pool)
		if !ok do break
		sync.atomic_thread_fence(.Acquire)
		j := cast(^Decode_Job)task.data
		if j.abandoned {
			decode_free(j)
			continue
		}
		if j.image.data != nil && rl.IsWindowReady() {
			j.texture = ResourceManager_TextureFromImage(rm, j.path, j.image)
			n += 1
		}
		rl.UnloadImage(j.image)
		j.image = {}
		j.uploaded = true
	}
}

// Decode_Collect: a finished job's texture (the reference moves to the
// caller); the job is freed.
Decode_Collect :: proc(j: ^Decode_Job) -> ^Texture {
	t := j.texture
	j.texture = nil
	decode_free(j)
	return t
}

// Decode_Abandon: the preload holding this job let go of it (frees it now
// if it's finished; else when the worker is done).
Decode_Abandon :: proc(rm: ^ResourceManager, j: ^Decode_Job) {
	if j == nil do return
	if j.uploaded {
		if j.texture != nil do ResourceManager_ReleaseTexture(rm, j.texture)
		decode_free(j)
		return
	}
	j.abandoned = true
}

@(private = "file")
decode_free :: proc(j: ^Decode_Job) {
	a := runtime.heap_allocator()
	for x, i in decoder.jobs do if x == j {
		unordered_remove(&decoder.jobs, i)
		break
	}
	if j.image.data != nil do rl.UnloadImage(j.image)
	if j.bytes != nil do delete(j.bytes, a)
	delete(j.path, a)
	delete(j.ext, a)
	free(j, a)
}

// Decode_Shutdown waits for the workers and frees every job (game end).
Decode_Shutdown :: proc() {
	if !decoder.started do return
	thread.pool_join(&decoder.pool)
	for {
		_, ok := thread.pool_pop_done(&decoder.pool)
		if !ok do break
	}
	for len(decoder.jobs) > 0 do decode_free(decoder.jobs[len(decoder.jobs) - 1])
	delete(decoder.jobs)
	thread.pool_destroy(&decoder.pool)
	decoder = {}
}
