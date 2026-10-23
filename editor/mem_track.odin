package editor

import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:slice"

// ============================================================================
// Memory diagnostics: build with -define:ORE_MEM_TRACK=true and the editor's
// heap goes through a tracking allocator. Every MEM_TRACK_EVERY frames it
// logs the live bytes, the allocation sites that grew since the last report
// (a leak shows up there run after run) and the temp arena's size; at exit,
// what is still allocated, by site.
// ============================================================================

ORE_MEM_TRACK :: #config(ORE_MEM_TRACK, false)
MEM_TRACK_EVERY :: 600

memTrack: ^mem.Tracking_Allocator

@(private = "file")
lastBySite: map[string]int

@(private = "file")
Site :: struct {
	where_: string,
	bytes:  int,
	count:  int,
}

@(private = "file")
sites_now :: proc() -> []Site {
	by := make(map[string]Site, allocator = context.temp_allocator)
	for _, entry in memTrack.allocation_map {
		key := fmt.tprintf("%s:%d %s", entry.location.file_path, entry.location.line, entry.location.procedure)
		s := by[key]
		s.where_ = key
		s.bytes += entry.size
		s.count += 1
		by[key] = s
	}
	out := make([dynamic]Site, context.temp_allocator)
	for _, s in by do append(&out, s)
	slice.sort_by(out[:], proc(a, b: Site) -> bool {return a.bytes > b.bytes})
	return out[:]
}

// MemTrack_Report logs the live heap and what grew since the last report.
MemTrack_Report :: proc(title: string, top := 12) {
	if memTrack == nil do return
	sites := sites_now()
	fmt.printfln("[MEM] %s: live %d KB in %d allocations (peak %d KB), bad frees %d", title, memTrack.current_memory_allocated / 1024, len(memTrack.allocation_map), memTrack.peak_memory_allocated / 1024, len(memTrack.bad_free_array))
	// The temp arena: frees only on free_all (once a frame, main.odin).
	if ta := (^runtime.Default_Temp_Allocator)(context.temp_allocator.data); ta != nil && context.temp_allocator.procedure == runtime.default_temp_allocator_proc {
		fmt.printfln("[MEM] temp arena: %d KB used, %d KB reserved", ta.arena.total_used / 1024, ta.arena.total_capacity / 1024)
	}
	growth := make([dynamic]Site, context.temp_allocator)
	for s in sites {
		if d := s.bytes - (lastBySite[s.where_] or_else 0); d > 0 do append(&growth, Site{s.where_, d, s.count})
	}
	slice.sort_by(growth[:], proc(a, b: Site) -> bool {return a.bytes > b.bytes})
	for g, i in growth {
		if i >= top do break
		fmt.printfln("[MEM]   +%d B (%d live) %s", g.bytes, g.count, g.where_)
	}
	for k in lastBySite do delete(k)
	clear(&lastBySite)
	for s in sites do lastBySite[fmt.aprint(s.where_)] = s.bytes
}

// MemTrack_ReportLeaks: what is still allocated (at exit), by site.
MemTrack_ReportLeaks :: proc(top := 25) {
	if memTrack == nil do return
	sites := sites_now()
	fmt.printfln("[MEM] at exit: %d KB still allocated in %d allocations", memTrack.current_memory_allocated / 1024, len(memTrack.allocation_map))
	for s, i in sites {
		if i >= top do break
		fmt.printfln("[MEM]   %d B in %d %s", s.bytes, s.count, s.where_)
	}
}
