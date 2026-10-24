package vmemx

// ============================================================================
// vmemx: the core:mem/virtual growing arena API the engine uses, over
// malloc - for the web build, where there is no virtual memory to reserve
// (scripts/web_prepare.py points the copied sources' vmem imports here).
// Blocks are malloc'd as needed (at least minimum_block_size); free_all
// keeps the first block, like a growing virtual arena.
// ============================================================================

import "base:runtime"
import "core:c"
import "core:mem"

@(private = "file")
@(default_calling_convention = "c")
foreign {
	malloc :: proc(size: c.size_t) -> rawptr ---
	free :: proc(p: rawptr) ---
}

Arena_Kind :: enum uint {
	Growing,
	Static,
	Buffer,
}

Memory_Block :: struct {
	prev: ^Memory_Block,
	base: [^]byte,
	used: uint,
	size: uint,
}

Arena :: struct {
	kind:               Arena_Kind,
	curr_block:         ^Memory_Block,
	total_used:         uint,
	total_reserved:     uint,
	minimum_block_size: uint,
}

DEFAULT_ARENA_GROWING_MINIMUM_BLOCK_SIZE :: 1 * mem.Megabyte

arena_init_growing :: proc(arena: ^Arena, reserved: uint = DEFAULT_ARENA_GROWING_MINIMUM_BLOCK_SIZE) -> runtime.Allocator_Error {
	arena^ = {kind = .Growing, minimum_block_size = max(reserved, 4 * mem.Kilobyte)}
	return block_push(arena, 0)
}

@(private = "file")
block_push :: proc(arena: ^Arena, need: uint) -> runtime.Allocator_Error {
	size := max(arena.minimum_block_size, need)
	raw := malloc(c.size_t(size_of(Memory_Block) + int(size) + 16))
	if raw == nil do return .Out_Of_Memory
	b := (^Memory_Block)(raw)
	base := uintptr(raw) + size_of(Memory_Block)
	base = (base + 15) &~ 15
	b^ = {prev = arena.curr_block, base = ([^]byte)(rawptr(base)), size = size}
	arena.curr_block = b
	arena.total_reserved += size
	return nil
}

arena_alloc :: proc(arena: ^Arena, size, alignment: uint) -> ([]byte, runtime.Allocator_Error) {
	if arena.curr_block == nil {
		if err := block_push(arena, size + alignment); err != nil do return nil, err
	}
	b := arena.curr_block
	start := (uintptr(b.base) + uintptr(b.used) + uintptr(alignment) - 1) &~ (uintptr(alignment) - 1)
	off := uint(start - uintptr(b.base))
	if off + size > b.size {
		if err := block_push(arena, size + alignment); err != nil do return nil, err
		return arena_alloc(arena, size, alignment)
	}
	b.used = off + size
	arena.total_used += size
	return ([^]byte)(rawptr(start))[:size], nil
}

arena_free_all :: proc(arena: ^Arena) {
	for arena.curr_block != nil && arena.curr_block.prev != nil {
		b := arena.curr_block
		arena.curr_block = b.prev
		arena.total_reserved -= b.size
		free(b)
	}
	if arena.curr_block != nil do arena.curr_block.used = 0
	arena.total_used = 0
}

arena_destroy :: proc(arena: ^Arena) {
	for arena.curr_block != nil {
		b := arena.curr_block
		arena.curr_block = b.prev
		free(b)
	}
	arena^ = {}
}

arena_allocator :: proc(arena: ^Arena) -> runtime.Allocator {
	return {procedure = arena_allocator_proc, data = arena}
}

arena_allocator_proc :: proc(data: rawptr, mode: runtime.Allocator_Mode, size, alignment: int, old_memory: rawptr, old_size: int, loc := #caller_location) -> ([]byte, runtime.Allocator_Error) {
	arena := (^Arena)(data)
	align := uint(max(alignment, 1))
	switch mode {
	case .Alloc, .Alloc_Non_Zeroed:
		res, err := arena_alloc(arena, uint(size), align)
		if err == nil && mode == .Alloc do mem.zero_slice(res)
		return res, err
	case .Free:
		return nil, nil // (an arena frees all at once)
	case .Free_All:
		arena_free_all(arena)
		return nil, nil
	case .Resize, .Resize_Non_Zeroed:
		if old_memory == nil do return arena_allocator_proc(data, .Alloc, size, alignment, nil, 0, loc)
		if size <= old_size do return ([^]byte)(old_memory)[:size], nil
		// The last allocation of the block grows in place when it fits.
		b := arena.curr_block
		if b != nil && uintptr(old_memory) + uintptr(old_size) == uintptr(b.base) + uintptr(b.used) && uintptr(old_memory) + uintptr(size) <= uintptr(b.base) + uintptr(b.size) {
			b.used += uint(size - old_size)
			arena.total_used += uint(size - old_size)
			res := ([^]byte)(old_memory)[:size]
			if mode == .Resize do mem.zero_slice(res[old_size:])
			return res, nil
		}
		res, err := arena_alloc(arena, uint(size), align)
		if err != nil do return nil, err
		mem.copy(raw_data(res), old_memory, old_size)
		if mode == .Resize do mem.zero_slice(res[old_size:])
		return res, nil
	case .Query_Features:
		set := (^runtime.Allocator_Mode_Set)(old_memory)
		if set != nil do set^ = {.Alloc, .Alloc_Non_Zeroed, .Free, .Free_All, .Resize, .Resize_Non_Zeroed, .Query_Features}
		return nil, nil
	case .Query_Info:
		return nil, .Mode_Not_Implemented
	}
	return nil, nil
}
