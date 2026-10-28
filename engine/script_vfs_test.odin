package engine

import "core:fmt"
import "core:testing"

// Registering an embedded script again replaces it: one entry per path, the
// last code wins. (It used to free the key before removing it from the map -
// a use-after-free that sometimes left the entry behind to be freed twice,
// aborting the test run on macOS CI.)
@(test)
test_script_vfs_reregister_replaces :: proc(t: ^testing.T) {
	PATHS :: 8
	ScriptVFS_Init()
	before := len(vfsGlobal.embedded)
	for round in 0 ..< 200 {
		for p in 0 ..< PATHS {
			ScriptVFS_RegisterEmbedded(fmt.tprintf("vfs_test/file_%d.lua", p), fmt.tprintf("return %d", round))
		}
		// (other heap churn between rounds, as between tests)
		junk := make([]u8, 64 + round, Engine_HeapAllocator())
		delete(junk, Engine_HeapAllocator())
	}
	testing.expect_value(t, len(vfsGlobal.embedded), before + PATHS)
	code, ok := ScriptVFS_Load("vfs_test/file_3.lua", context.temp_allocator)
	testing.expect(t, ok && code == "return 199", "the last registration wins")
}
