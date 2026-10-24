package engine

import "base:runtime"
import "core:c"
import "core:fmt"
import os "osx"
import "core:strings"
import "core:sync"
import lua "lua54"

// ============================================================================
// Virtual File System (VFS) & Embedded Asset Packaging for Lua Scripts
// Supports transparent loading from disk in development & embedded memory in release.
// ============================================================================

ScriptVFS :: struct {
	embedded:    map[string]string,
	searchPaths: [dynamic]string,
	initialized: bool,
	mutex:       sync.Mutex,
}

vfsGlobal: ScriptVFS

ScriptVFS_Init :: proc() {
	sync.mutex_lock(&vfsGlobal.mutex)
	defer sync.mutex_unlock(&vfsGlobal.mutex)

	if vfsGlobal.initialized do return

	alloc := Engine_HeapAllocator()
	vfsGlobal.embedded = make(map[string]string, allocator = alloc)
	vfsGlobal.searchPaths = make([dynamic]string, allocator = alloc)
	append(&vfsGlobal.searchPaths, "assets/scripts/")
	append(&vfsGlobal.searchPaths, "scripts/")
	append(&vfsGlobal.searchPaths, "./")
	vfsGlobal.initialized = true
}

ScriptVFS_Destroy :: proc() {
	sync.mutex_lock(&vfsGlobal.mutex)
	defer sync.mutex_unlock(&vfsGlobal.mutex)

	if !vfsGlobal.initialized do return

	alloc := Engine_HeapAllocator()
	for k, v in vfsGlobal.embedded {
		delete(k, alloc)
		delete(v, alloc)
	}
	delete(vfsGlobal.embedded)
	delete(vfsGlobal.searchPaths)
	vfsGlobal.initialized = false
}

ScriptVFS_RegisterEmbedded :: proc(path: string, code: string) {
	ScriptVFS_Init()
	sync.mutex_lock(&vfsGlobal.mutex)
	defer sync.mutex_unlock(&vfsGlobal.mutex)

	alloc := Engine_HeapAllocator()
	norm := ScriptVFS_NormalizePath(path)
	for k, v in vfsGlobal.embedded {
		if k == norm {
			delete(k, alloc)
			delete(v, alloc)
			delete_key(&vfsGlobal.embedded, k)
			break
		}
	}
	vfsGlobal.embedded[strings.clone(norm, alloc)] = strings.clone(code, alloc)
}

ScriptVFS_NormalizePath :: proc(path: string) -> string {
	res := strings.trim_space(path)
	if strings.has_prefix(res, "./") {
		res = res[2:]
	}
	return res
}

// Loads a script either from embedded VFS or from the filesystem
ScriptVFS_Load :: proc(path: string, allocator := context.allocator) -> (code: string, ok: bool) {
	ScriptVFS_Init()
	norm := ScriptVFS_NormalizePath(path)

	// 1. Check embedded VFS first (both as-is and with .lua extension)
	sync.mutex_lock(&vfsGlobal.mutex)
	embeddedCandidates := make([dynamic]string, context.temp_allocator)
	append(&embeddedCandidates, norm)
	if !strings.has_suffix(norm, ".lua") {
		append(&embeddedCandidates, strings.concatenate({norm, ".lua"}, context.temp_allocator))
	} else if len(norm) > 4 {
		append(&embeddedCandidates, norm[:len(norm)-4])
	}

	for cand in embeddedCandidates {
		if embeddedCode, exists := vfsGlobal.embedded[cand]; exists {
			res := strings.clone(embeddedCode, allocator)
			sync.mutex_unlock(&vfsGlobal.mutex)
			return res, true
		}
	}

	baseName := norm
	if idx := strings.last_index_byte(norm, '/'); idx >= 0 {
		baseName = norm[idx+1:]
		baseCandidates := make([dynamic]string, context.temp_allocator)
		append(&baseCandidates, baseName)
		if !strings.has_suffix(baseName, ".lua") {
			append(&baseCandidates, strings.concatenate({baseName, ".lua"}, context.temp_allocator))
		}
		for cand in baseCandidates {
			if embeddedCode, exists := vfsGlobal.embedded[cand]; exists {
				res := strings.clone(embeddedCode, allocator)
				sync.mutex_unlock(&vfsGlobal.mutex)
				return res, true
			}
		}
	}

	searchPathsCopy := make([]string, len(vfsGlobal.searchPaths), context.temp_allocator)
	copy(searchPathsCopy, vfsGlobal.searchPaths[:])
	sync.mutex_unlock(&vfsGlobal.mutex)

	// 2. Check disk search paths
	candidates := make([dynamic]string, context.temp_allocator)
	append(&candidates, norm)
	if !strings.has_suffix(norm, ".lua") {
		append(&candidates, strings.concatenate({norm, ".lua"}, context.temp_allocator))
	}

	for sp in searchPathsCopy {
		append(&candidates, strings.concatenate({sp, norm}, context.temp_allocator))
		if !strings.has_suffix(norm, ".lua") {
			append(&candidates, strings.concatenate({sp, norm, ".lua"}, context.temp_allocator))
		}
	}

	for cand in candidates {
		if os.exists(cand) {
			data, err := os.read_entire_file(cand, allocator)
			if err == nil {
				return string(data), true
			}
		}
	}

	return "", false
}

// Custom Lua 5.4 searcher function for package.searchers that looks up in ScriptVFS
@(private="file")
lua_vfs_searcher :: proc "c" (L: ^lua.State) -> c.int {
	context = Script_Context(L)
	modNameC := lua.tostring(L, 1)
	if modNameC == nil {
		lua.pushstring(L, "\n\t[ScriptVFS] module name is nil")
		return 1
	}

	modName := string(modNameC)
	// Replace '.' with '/' in Lua module paths (e.g. "player.controller" -> "player/controller.lua")
	relPath, was_alloc := strings.replace_all(modName, ".", "/", context.temp_allocator)
	_ = was_alloc

	code, ok := ScriptVFS_Load(relPath, context.temp_allocator)
	if !ok {
		msg := fmt.tprintf("\n\t[ScriptVFS] no embedded or disk script matching '%s'", relPath)
		msgC := strings.clone_to_cstring(msg, context.temp_allocator)
		lua.pushstring(L, msgC)
		return 1
	}

	chunkName := fmt.tprintf("@%s.lua", relPath)
	chunkNameC := strings.clone_to_cstring(chunkName, context.temp_allocator)
	codeC := raw_data(transmute([]u8)code)

	loadStatus := lua.L_loadbuffer(L, cast([^]u8)codeC, c.size_t(len(code)), chunkNameC)
	if loadStatus != .OK {
		// lua.L_loadbuffer pushed error string onto stack
		return 1
	}

	// Return loader function to Lua
	return 1
}

// Inserts our ScriptVFS searcher into Lua's package.searchers array
ScriptVFS_RegisterLuaSearcher :: proc(L: ^lua.State) {
	if L == nil do return

	lua.getglobal(L, "package")
	if lua.type(L, -1) != .TABLE {
		lua.pop(L, 1)
		return
	}

	lua.getfield(L, -1, "searchers")
	if lua.type(L, -1) != .TABLE {
		lua.pop(L, 2)
		return
	}

	// Insert lua_vfs_searcher at index 2 (just after preload searcher)
	// Length of searchers table
	numSearchers := lua.rawlen(L, -1)
	for i := numSearchers; i >= 2; i -= 1 {
		lua.rawgeti(L, -1, lua.Integer(i))
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}

	lua.pushcfunction(L, lua_vfs_searcher)
	lua.rawseti(L, -2, 2)

	lua.pop(L, 2) // pop searchers and package
}
