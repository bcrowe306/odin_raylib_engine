#+build !js
package engine

import "base:runtime"
import "core:mem"
import "core:prof/spall"
import "core:sync"

// The trace writer of profiling.odin (desktop): spall, one buffer on the
// main thread (zones on other threads, which have none, are skipped).

@(private = "file")
trace: struct {
	ctx:     spall.Context,
	backing: []u8,
}

@(private = "file", thread_local)
traceBuffer: spall.Buffer

prof_trace_open :: proc(path: string, allocator: mem.Allocator) -> bool {
	ctx, ok := spall.context_create(path)
	if !ok do return false
	trace.ctx = ctx
	trace.backing = make([]u8, spall.BUFFER_DEFAULT_SIZE, allocator)
	traceBuffer = spall.buffer_create(trace.backing, u32(sync.current_thread_id()))
	return true
}

prof_trace_close :: proc(allocator: mem.Allocator) {
	spall.buffer_destroy(&trace.ctx, &traceBuffer)
	spall.context_destroy(&trace.ctx)
	delete(trace.backing, allocator)
	trace = {}
}

prof_trace_flush :: proc() {
	spall.buffer_flush(&trace.ctx, &traceBuffer)
}

prof_trace_begin :: #force_inline proc(name: string, loc: runtime.Source_Code_Location) {
	if len(traceBuffer.data) > 0 do spall._buffer_begin(&trace.ctx, &traceBuffer, name, "", loc)
}

prof_trace_end :: #force_inline proc() {
	if len(traceBuffer.data) > 0 do spall._buffer_end(&trace.ctx, &traceBuffer)
}
