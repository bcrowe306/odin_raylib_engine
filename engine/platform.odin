#+build !js
package engine

import "base:runtime"
import "core:os"

// ============================================================================
// Platform allocators: the desktop's are the runtime's own (the C heap);
// the web build (platform_js.odin) uses emscripten's malloc, so wasm memory
// only ever grows through emscripten.
// ============================================================================

// Engine_HeapAllocator: process-lifetime allocations (decoded sounds,
// caches, pools...).
Engine_HeapAllocator :: proc() -> runtime.Allocator {return runtime.heap_allocator()}

// Engine_CoreCount: the processor's cores (1 on the web).
Engine_CoreCount :: proc() -> int {return os.get_processor_core_count()}

// Engine_TempDir: the OS's temporary folder (temp-allocated; TMPDIR, /tmp,
// %TEMP%) - TMPDIR alone isn't set on Linux or Windows.
Engine_TempDir :: proc() -> string {
	if d, err := os.temp_directory(context.temp_allocator); err == nil && d != "" do return d
	return "/tmp"
}

// Engine_DefaultContext: a fresh context for callbacks the engine is
// called back on (audio, Lua, packaging).
Engine_DefaultContext :: proc "contextless" () -> runtime.Context {return runtime.default_context()}

// Shader_Port: shader source for this platform (desktop: as written).
Shader_Port :: proc(src: cstring) -> cstring {return src}
