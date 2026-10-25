#+build js
package engine

import "base:runtime"
import "core:mem"

// The web has no trace writer (core:prof/spall writes files): the zones of
// profiling.odin record nothing there; the heap counters still work.

prof_trace_open :: proc(path: string, allocator: mem.Allocator) -> bool {return false}
prof_trace_close :: proc(allocator: mem.Allocator) {}
prof_trace_flush :: proc() {}
prof_trace_begin :: proc(name: string, loc: runtime.Source_Code_Location) {}
prof_trace_end :: proc() {}
