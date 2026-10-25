package engine

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:slice"
import "core:mem"
import "core:strconv"
import "core:sync"

// ============================================================================
// Profiling (build with -define:RAYZR_PROF=true; without it every call below
// compiles to nothing):
//
// - Zones: `Prof_Scope("name")` at the top of a block times it to the end of
//   the block; the trace (spall format) opens in https://gravitymoth.com/spall/.
//   Main thread only (other threads have no buffer and are skipped). The
//   trace writer is desktop only (profiling_trace.odin; on the web the zones
//   record nothing: profiling_trace_js.odin).
// - Allocations: the heap allocator is wrapped to count allocations, frees
//   and bytes per frame, and the temp arena's use is read before it's freed.
//   The editor's Profiler tab and the [bench] lines show them.
//
// The runner and the editor take `--prof <file.spall>` (the trace),
// `--prof-skip N` (frames before recording; default 30, the warm-up) and
// `--prof-frames N` (frames recorded; default 300, 0 = until exit). A
// build without RAYZR_PROF says so when --prof is given. `--prof-alloc-sites`
// also counts heap allocations by source line (from frame --prof-skip on)
// and prints the busiest at exit.
// ============================================================================

RAYZR_PROF :: #config(RAYZR_PROF, false)

Prof_Frame_Stats :: struct {
	allocs:    int, // heap allocations (and resizes) this frame
	frees:     int,
	bytes:     int, // bytes requested from the heap this frame
	tempBytes: int, // the temp arena's use at the end of the frame
}

Prof_Site :: struct {
	file: rawptr, // (the location's path: a constant string)
	line: i32,
	loc:  runtime.Source_Code_Location,
}

Prof_State :: struct {
	path:       string,
	skip:       int,  // frames before recording
	frames:     int,  // frames to record (0 = until shutdown)
	frame:      int,  // frames seen
	recording:  bool, // the trace is on (changed only between frames)
	opened:     bool,
	// The heap counter.
	backingAllocator: mem.Allocator,
	counting:   Prof_Frame_Stats, // this frame so far
	last:       Prof_Frame_Stats, // the last whole frame
	totalAllocs: int,             // since Prof_Init
	allocSites: bool,             // --prof-alloc-sites
	mainThread: int,
	sites:      map[Prof_Site]int,
}

prof: Prof_State

// Prof_ParseArgs reads --prof / --prof-skip / --prof-frames.
Prof_ParseArgs :: proc(args: []string) {
	prof.skip = 30
	prof.frames = 300
	for a in args do if a == "--prof-alloc-sites" do prof.allocSites = true
	for i := 0; i + 1 < len(args); i += 1 {
		n, _ := strconv.parse_int(args[i + 1])
		switch args[i] {
		case "--prof":        prof.path = args[i + 1]
		case "--prof-skip":   prof.skip = max(n, 0)
		case "--prof-frames": prof.frames = max(n, 0)
		}
	}
	when !RAYZR_PROF {
		if prof.path != "" do log.warnf("--prof %s: this build has no profiling (build with -define:RAYZR_PROF=true)", prof.path)
	}
}

// Prof_Init opens the trace (when --prof was given) and wraps the heap
// allocator for the counters: call at the top of main, before anything
// allocates, and use the returned allocator as context.allocator.
Prof_Init :: proc(heap: mem.Allocator) -> mem.Allocator {
	when RAYZR_PROF {
		prof.backingAllocator = heap
		prof.mainThread = sync.current_thread_id()
		if prof.allocSites do prof.sites = make(map[Prof_Site]int, 256, heap)
		if prof.path != "" {
			if prof_trace_open(prof.path, heap) {
				prof.opened = true
				log.infof("[prof] tracing frames %d..%d to %s", prof.skip, prof.skip + prof.frames if prof.frames > 0 else -1, prof.path)
			} else {
				log.errorf("[prof] cannot write %s", prof.path)
			}
		}
		return {procedure = prof_allocator_proc, data = nil}
	} else {
		return heap
	}
}

// Prof_Shutdown writes out and closes the trace.
Prof_Shutdown :: proc() {
	when RAYZR_PROF {
		if prof.allocSites {
			Row :: struct {site: Prof_Site, n: int}
			rows := make([dynamic]Row, 0, len(prof.sites), prof.backingAllocator)
			for k, n in prof.sites do append(&rows, Row{k, n})
			slice.sort_by(rows[:], proc(a, b: Row) -> bool {return a.n > b.n})
			frames := max(prof.frame - prof.skip, 1)
			fmt.printfln("[prof] heap allocations by site, per frame (%d frames):", frames)
			for r in rows[:min(len(rows), 25)] do fmt.printfln("  %9.1f  %s:%d %s", f64(r.n) / f64(frames), r.site.loc.file_path, r.site.loc.line, r.site.loc.procedure)
			delete(rows)
			delete(prof.sites)
		}
		if !prof.opened do return
		prof_trace_close(prof.backingAllocator)
		prof.opened = false
		prof.recording = false
		log.infof("[prof] wrote %s (%d heap allocations counted over %d frames)", prof.path, prof.totalAllocs, prof.frame)
	}
}

// Prof_FrameEnd closes a frame: the counters roll over and the trace
// starts / stops on its frame window. Call once per frame, outside every
// zone (before freeing the temp arena).
@(disabled = !RAYZR_PROF)
Prof_FrameEnd :: proc() {
	when RAYZR_PROF {
		if context.temp_allocator.procedure == runtime.default_temp_allocator_proc && context.temp_allocator.data != nil {
			ta := cast(^runtime.Default_Temp_Allocator)context.temp_allocator.data
			prof.counting.tempBytes = int(ta.arena.total_used)
		}
		prof.last = prof.counting
		prof.totalAllocs += prof.counting.allocs
		prof.counting = {}
		prof.frame += 1
		if prof.opened {
			start := prof.skip
			stop := prof.skip + prof.frames
			prof.recording = prof.frame >= start && (prof.frames == 0 || prof.frame < stop)
			if prof.frames > 0 && prof.frame == stop do prof_trace_flush()
		}
	}
}

// Prof_Last: the counters of the last whole frame (zeros without RAYZR_PROF).
Prof_Last :: proc() -> Prof_Frame_Stats {
	return prof.last
}

// Prof_Scope times the rest of the enclosing block as a zone named `name`
// (a constant string: zones must not allocate).
@(disabled = !RAYZR_PROF, deferred_none = prof_scope_end)
Prof_Scope :: proc(name: string, loc := #caller_location) {
	when RAYZR_PROF {
		if prof.recording do prof_trace_begin(name, loc)
	}
}

// Prof_Begin / Prof_End: a zone that doesn't follow a block (must be paired).
@(disabled = !RAYZR_PROF)
Prof_Begin :: proc(name: string, loc := #caller_location) {
	when RAYZR_PROF {
		if prof.recording do prof_trace_begin(name, loc)
	}
}

@(disabled = !RAYZR_PROF)
Prof_End :: proc() {
	prof_scope_end()
}

@(private = "file", disabled = !RAYZR_PROF)
prof_scope_end :: proc() {
	when RAYZR_PROF {
		if prof.recording do prof_trace_end()
	}
}

when RAYZR_PROF {
	@(private = "file")
	prof_allocator_proc :: proc(data: rawptr, mode: mem.Allocator_Mode, size, alignment: int, old_memory: rawptr, old_size: int, loc := #caller_location) -> ([]byte, mem.Allocator_Error) {
		// (Atomic: worker threads, e.g. async_decode, allocate too.)
		#partial switch mode {
		case .Alloc, .Alloc_Non_Zeroed, .Resize, .Resize_Non_Zeroed:
			sync.atomic_add(&prof.counting.allocs, 1)
			sync.atomic_add(&prof.counting.bytes, size)
			if prof.allocSites && prof.frame >= prof.skip && sync.current_thread_id() == prof.mainThread {
				context.allocator = prof.backingAllocator
				prof.sites[Prof_Site{raw_data(loc.file_path), loc.line, loc}] += 1
			}
		case .Free:
			if old_memory != nil do sync.atomic_add(&prof.counting.frees, 1)
		}
		b := prof.backingAllocator
		return b.procedure(b.data, mode, size, alignment, old_memory, old_size, loc)
	}
}
