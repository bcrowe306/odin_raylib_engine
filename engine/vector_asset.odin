package engine

import "core:log"
import os "osx"
import "core:strings"
import "core:time"
import rl "vendor:raylib"

// ============================================================================
// Vector assets (Phase 14 V.4 / V.5): an SVG file loaded once per path
// (counted) and reloaded when it changes (ResourceManager_CheckForChanges:
// saving in Inkscape / Illustrator / Affinity shows up in the editor and in
// a running game). Its tessellations are shared by every node drawing it -
// one cached mesh per scale bucket, the most recent few kept - so a hundred
// copies of a character cost one tessellation and a hundred draw calls of
// the same GPU mesh.
// ============================================================================

VECTOR_BUCKETS_KEPT :: 3

Vector_Resource :: struct {
	path:    string,
	doc:     Vector_Doc,
	refs:    int,
	version: int, // +1 per reload
	modTime: time.Time,
	caches:  [VECTOR_BUCKETS_KEPT]Vector_Resource_Cache,
	frame:   u64, // a draw counter (which bucket was used last)
	owner:   ^ResourceManager,
	pending: int, // background tessellations running (vector_jobs.odin)
	waiting: [VECTOR_BUCKETS_KEPT]f32, // buckets queued (0: none)
}

Vector_Resource_Cache :: struct {
	cache:    Vector_Cache,
	used:     u64, // r.frame when last drawn (0: free)
	version:  int,
}

// Vector_IsPath: a vector asset's path (.svg).
Vector_IsPath :: proc(path: string) -> bool {
	lower := strings.to_lower(path, context.temp_allocator)
	return strings.has_suffix(lower, ".svg")
}

// ResourceManager_LoadVector: the file's resource (a reference taken); nil
// when it can't be read or isn't an SVG (the reasons are logged).
ResourceManager_LoadVector :: proc(rm: ^ResourceManager, path: string) -> ^Vector_Resource {
	if rm.vectors != nil {
		if r, ok := rm.vectors[path]; ok {
			r.refs += 1
			return r
		}
	}
	data, found := vector_bytes(rm, path)
	if !found {
		log.errorf("Vector file not found: %s", path)
		return nil
	}
	defer delete(data, Engine_HeapAllocator())
	r := new(Vector_Resource, Engine_HeapAllocator())
	if !Vector_LoadSVG(string(data), &r.doc) {
		log.errorf("Can't read the SVG %s: %s", path, strings.join(r.doc.warnings[:], "; ", context.temp_allocator))
		Vector_Doc_Destroy(&r.doc)
		free(r, Engine_HeapAllocator())
		return nil
	}
	for w in r.doc.warnings do log.warnf("%s: %s", path, w)
	if imp := Asset_ImportGet(rm, path); imp.vectorScale > 0 do Vector_DocScale(&r.doc, imp.vectorScale)
	r.path = strings.clone(path, Engine_HeapAllocator())
	r.refs = 1
	r.owner = rm
	if info, err := os.stat(path, context.temp_allocator); err == nil do r.modTime = info.modification_time
	if rm.vectors == nil do rm.vectors = make(map[string]^Vector_Resource, allocator = Engine_HeapAllocator())
	rm.vectors[r.path] = r
	return r
}

// ResourceManager_ReleaseVector drops a reference (the last frees it).
ResourceManager_ReleaseVector :: proc(r: ^Vector_Resource) {
	if r == nil do return
	r.refs -= 1
	if r.refs > 0 do return
	if r.owner != nil && r.owner.vectors != nil do delete_key(&r.owner.vectors, r.path)
	vector_resource_free(r)
}

@(private = "file")
vector_resource_free :: proc(r: ^Vector_Resource) {
	context.allocator = Engine_HeapAllocator()
	for &c in r.caches do Vector_Cache_Destroy(&c.cache)
	Vector_Doc_Destroy(&r.doc)
	delete(r.path)
	free(r)
}

// Vector_ReleaseAll frees a resource manager's vector files (its shutdown).
Vector_ReleaseAll :: proc(rm: ^ResourceManager) {
	for _, r in rm.vectors do vector_resource_free(r)
	delete(rm.vectors)
	rm.vectors = nil
}

// Vector_ResourceCount: files loaded now (tests).
Vector_ResourceCount :: proc(rm: ^ResourceManager) -> int {return len(rm.vectors)}

@(private = "file")
vector_bytes :: proc(rm: ^ResourceManager, path: string) -> ([]u8, bool) {
	if os.is_file(path) {
		data, err := os.read_entire_file(path, Engine_HeapAllocator())
		return data, err == nil
	}
	if rm != nil {
		if b, ok := resource_bytes(rm, path); ok {
			defer delete(b)
			c := make([]u8, len(b), Engine_HeapAllocator())
			copy(c, b)
			return c, true
		}
	}
	return nil, false
}

// Vector_CheckForChanges reloads the files changed on disk; the number reloaded.
Vector_CheckForChanges :: proc(rm: ^ResourceManager) -> int {
	n := 0
	for _, r in rm.vectors {
		if r.modTime == {} || r.pending > 0 do continue // (jobs read the document: next check)
		info, err := os.stat(r.path, context.temp_allocator)
		if err != nil || time.diff(r.modTime, info.modification_time) <= 0 do continue
		data, rerr := os.read_entire_file(r.path, context.temp_allocator)
		if rerr != nil do continue
		doc: Vector_Doc
		if !Vector_LoadSVG(string(data), &doc) {
			Vector_Doc_Destroy(&doc) // (half-written: next time)
			continue
		}
		if imp := Asset_ImportGet(rm, r.path); imp.vectorScale > 0 do Vector_DocScale(&doc, imp.vectorScale)
		Vector_Doc_Destroy(&r.doc)
		r.doc = doc
		r.modTime = info.modification_time
		r.version += 1
		for &c in r.caches do c.cache.dirty = true
		log.infof("Reloaded %s", r.path)
		n += 1
	}
	return n
}

// Vector_ResourceMesh: the cached mesh for drawing at a screen-pixel size.
// A bucket not cached yet: with `background`, the nearest cached bucket is
// drawn meanwhile and a worker tessellates the new one (vector_jobs.odin);
// otherwise (or when nothing is cached) it is tessellated now. The least
// recently used bucket is replaced.
Vector_ResourceMesh :: proc(r: ^Vector_Resource, t: ^Vector_Tess, pixel: f32, background := false) -> ^Vector_Cache {
	context.allocator = Engine_HeapAllocator()
	// (Finished background meshes, once a frame - also where the game loop
	// doesn't run: the editor's viewport.)
	@(static) lastPump: f64 = -1
	if now := rl.GetTime(); now != lastPump {
		lastPump = now
		Vector_JobPump()
	}
	r.frame += 1
	b := Vector_PixelBucket(pixel)
	slot := -1
	for &c, i in r.caches do if c.used != 0 && c.cache.bucket == b && c.version == r.version {slot = i; break}
	if slot < 0 && background {
		// The nearest bucket that is ready (current version, a mesh).
		near := -1
		best := max(f32)
		for c, i in r.caches {
			if c.used == 0 || c.version != r.version || c.cache.dirty || len(c.cache.mesh.idx) == 0 do continue
			d := abs(c.cache.bucket / b - 1) if c.cache.bucket > b else abs(b / c.cache.bucket - 1)
			if d < best {best = d; near = i}
		}
		if near >= 0 {
			queued := false
			for w in r.waiting do if w == b do queued = true
			if !queued {
				for &w in r.waiting do if w == 0 {
					w = b
					vector_job_submit(r, b)
					break
				}
			}
			c := &r.caches[near]
			c.used = r.frame
			Vector_Cache_Ensure(&c.cache, t, r.doc.shapes[:], c.cache.bucket) // (uploads it if needed)
			return &c.cache
		}
	}
	if slot < 0 {
		// The free or least recently used slot.
		oldest := max(u64)
		for c, i in r.caches do if c.used < oldest {oldest = c.used; slot = i}
		Vector_Cache_Destroy(&r.caches[slot].cache)
		r.caches[slot] = {}
	}
	c := &r.caches[slot]
	if c.version != r.version {c.cache.dirty = true; c.version = r.version}
	c.used = r.frame
	Vector_Cache_Ensure(&c.cache, t, r.doc.shapes[:], b)
	return &c.cache
}

// Vector_ResourceBounds: the document's box (its origin rectangle).
Vector_ResourceBounds :: proc(r: ^Vector_Resource) -> (min, size: [2]f32) {return r.doc.min, r.doc.size}

// Vector_FileImage: an SVG file rendered into an image fitting max x max px
// (asset thumbnails and previews; needs a window; the caller unloads it; no
// data when the file can't be read).
Vector_FileImage :: proc(path: string, maxSize: i32) -> rl.Image {
	if !rl.IsWindowReady() do return {}
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil do return {}
	doc: Vector_Doc
	defer Vector_Doc_Destroy(&doc)
	if !Vector_LoadSVG(string(data), &doc) do return {}
	return Vector_DocImage(&doc, maxSize)
}

// Vector_DocImage: a document rendered into an image fitting max x max px
// (transparent around it).
Vector_DocImage :: proc(doc: ^Vector_Doc, maxSize: i32) -> rl.Image {
	if !rl.IsWindowReady() || doc.size.x <= 0 || doc.size.y <= 0 do return {}
	s := f32(maxSize) / max(doc.size.x, doc.size.y)
	w, h := max(i32(doc.size.x * s + 0.5), 1), max(i32(doc.size.y * s + 0.5), 1)
	rt := rl.LoadRenderTexture(w, h)
	defer rl.UnloadRenderTexture(rt)
	tess: Vector_Tess
	defer Vector_Tess_Destroy(&tess)
	cache: Vector_Cache
	defer Vector_Cache_Destroy(&cache)
	{
		context.allocator = Engine_HeapAllocator()
		Vector_Cache_Ensure(&cache, &tess, doc.shapes[:], 1 / s)
	}
	rl.BeginTextureMode(rt)
	rl.ClearBackground({0, 0, 0, 0})
	Vector_Cache_Draw(&cache, {0, 0}, 0, {s, s}, rl.WHITE, -doc.min)
	rl.EndTextureMode()
	img := rl.LoadImageFromTexture(rt.texture)
	rl.ImageFlipVertical(&img) // (render textures are upside down)
	return img
}

// vector_resource_install: a finished background mesh into the bucket's
// cache slot (main thread; vector_jobs.odin).
vector_resource_install :: proc(r: ^Vector_Resource, bucket: f32, mesh: ^Vector_Mesh) {
	for &w in r.waiting do if w == bucket do w = 0
	slot := -1
	for c, i in r.caches do if c.used != 0 && c.cache.bucket == bucket {slot = i; break}
	if slot < 0 {
		oldest := max(u64)
		for c, i in r.caches do if c.used < oldest {oldest = c.used; slot = i}
	}
	c := &r.caches[slot]
	Vector_Cache_Destroy(&c.cache)
	c.cache = {}
	c.cache.mesh = mesh^
	mesh^ = {}
	c.cache.bucket = bucket
	c.cache.stats.tessellations = 1
	c.version = r.version
	c.used = r.frame
}
