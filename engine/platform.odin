#+build !js
package engine

import "base:runtime"

// ============================================================================
// Platform allocators: the desktop's are the runtime's own (the C heap);
// the web build (platform_js.odin) uses emscripten's malloc, so wasm memory
// only ever grows through emscripten.
// ============================================================================

// Engine_HeapAllocator: process-lifetime allocations (decoded sounds,
// caches, pools...).
Engine_HeapAllocator :: proc() -> runtime.Allocator {return runtime.heap_allocator()}

// Engine_DefaultContext: a fresh context for callbacks the engine is
// called back on (audio, Lua, packaging).
Engine_DefaultContext :: proc "contextless" () -> runtime.Context {return runtime.default_context()}

// Shader_Port: shader source for this platform (desktop: as written).
Shader_Port :: proc(src: cstring) -> cstring {return src}
