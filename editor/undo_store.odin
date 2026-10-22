package editor

import "core:strings"

// ============================================================================
// Undo snapshot storage. A snapshot is the whole scene's JSON (restoring
// rebuilds the scene from it), but consecutive snapshots are nearly the
// same text - an edit changes a node or two. Snapshots are split into
// content-defined chunks (boundaries where a rolling hash of the bytes
// matches, so an edit only changes the chunks around it) and identical
// chunks are stored once, shared and refcounted: 100 snapshots of a 2.4 MB
// scene take a few MB instead of 240.
// ============================================================================

@(private = "file")
Undo_Chunk :: struct {
	data: string, // heap; also the store's key
	refs: int,
}

Undo_Snapshot :: []^Undo_Chunk

@(private = "file")
undoChunks: map[string]^Undo_Chunk

@(private = "file")
CHUNK_MIN :: 512
@(private = "file")
CHUNK_MAX :: 16 * 1024
@(private = "file")
CHUNK_MASK :: 0x7FF // ~2 KB average

// gear table for the rolling hash (any fixed pseudo-random values).
@(private = "file")
gear: [256]u64

@(private = "file", init)
make_gear :: proc "contextless" () {
	x: u64 = 0x9E3779B97F4A7C15
	for i in 0 ..< 256 {
		x ~= x << 13
		x ~= x >> 7
		x ~= x << 17
		gear[i] = x
	}
}

// Undo_Pack splits text into shared chunks (the snapshot owns references).
Undo_Pack :: proc(text: string) -> Undo_Snapshot {
	out := make([dynamic]^Undo_Chunk)
	start := 0
	h: u64
	for i in 0 ..< len(text) {
		h = (h << 1) + gear[text[i]]
		size := i - start + 1
		if (size >= CHUNK_MIN && h & CHUNK_MASK == 0) || size >= CHUNK_MAX || i == len(text) - 1 {
			append(&out, intern(text[start:i + 1]))
			start = i + 1
			h = 0
		}
	}
	return out[:]
}

@(private = "file")
intern :: proc(piece: string) -> ^Undo_Chunk {
	if c, ok := undoChunks[piece]; ok {
		c.refs += 1
		return c
	}
	c := new(Undo_Chunk)
	c.data = strings.clone(piece)
	c.refs = 1
	undoChunks[c.data] = c
	return c
}

// Undo_Same: two snapshots of the same text (shared chunks compare by pointer).
Undo_Same :: proc(a, b: Undo_Snapshot) -> bool {
	if len(a) != len(b) do return false
	for c, i in a do if c != b[i] do return false
	return true
}

// Undo_Unpack joins a snapshot back into its text (temp-allocated).
Undo_Unpack :: proc(s: Undo_Snapshot) -> string {
	n := 0
	for c in s do n += len(c.data)
	sb := strings.builder_make(0, n, context.temp_allocator)
	for c in s do strings.write_string(&sb, c.data)
	return strings.to_string(sb)
}

// Undo_Release drops a snapshot's references (and chunks no one uses).
Undo_Release :: proc(s: Undo_Snapshot) {
	for c in s {
		c.refs -= 1
		if c.refs <= 0 {
			delete_key(&undoChunks, c.data)
			delete(c.data)
			free(c)
		}
	}
	delete(s)
}

// Undo_StoreBytes: memory the snapshots hold (tests, profiler).
Undo_StoreBytes :: proc() -> int {
	n := 0
	for _, c in undoChunks do n += len(c.data)
	return n
}
