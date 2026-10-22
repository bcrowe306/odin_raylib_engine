package engine

import "base:runtime"
import "core:c"
import "core:log"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:strings"
import rl "vendor:raylib"

// ============================================================================
// Asset Manager (loose project files and .ore archive packages)
// ============================================================================

// AssetManager is the file layer: it resolves project-relative paths
// through a mounted .ore package or the project directory and reads files.
// Loaded GPU/audio resources are cached in one place, the ResourceManager
// (resource_manager.odin), which reads through this layer.
AssetManager :: struct {
	allocator:     mem.Allocator,
	projectDir:    string,
	package_:      ^OrePackage,
}

AssetManager_Init :: proc(am: ^AssetManager, allocator := context.allocator) {
	am.allocator = allocator
	am.projectDir = ""
	am.package_ = nil
}

AssetManager_Destroy :: proc(am: ^AssetManager) {
	if am == nil do return
	if am.projectDir != "" {
		delete(am.projectDir, am.allocator)
		am.projectDir = ""
	}

	if am.package_ != nil {
		OrePackage_Close(am.package_)
		am.package_ = nil
	}
}

AssetManager_MountPackage :: proc(am: ^AssetManager, pkg: ^OrePackage) {
	if am.package_ != nil && am.package_ != pkg {
		OrePackage_Close(am.package_)
	}
	am.package_ = pkg
}

AssetManager_SetProjectDir :: proc(am: ^AssetManager, dir: string) {
	if am.projectDir != "" {
		delete(am.projectDir, am.allocator)
	}
	am.projectDir = strings.clone(dir, am.allocator)
}

// ----------------------------------------------------------------------------
// Low-level Data Access (Resolves Package first, then loose disk path)
// ----------------------------------------------------------------------------

AssetManager_ResolveDiskPath :: proc(am: ^AssetManager, relPath: string, allocator := context.temp_allocator) -> string {
	if am.projectDir == "" do return relPath
	res, _ := filepath.join({am.projectDir, relPath}, allocator)
	return res
}

AssetManager_ReadFileBytes :: proc(am: ^AssetManager, relPath: string, allocator := context.allocator) -> ([]byte, bool) {
	// 1. Try mounted package
	if am.package_ != nil {
		data, ok := OrePackage_ReadFile(am.package_, relPath, allocator)
		if ok do return data, true
	}

	// 2. Try disk relative to projectDir or cwd
	resolved := AssetManager_ResolveDiskPath(am, relPath, context.temp_allocator)
	data, err := os.read_entire_file(resolved, allocator)
	if err == nil do return data, true

	// 3. Fallback to direct relative path
	if resolved != relPath {
		dataDirect, errDirect := os.read_entire_file(relPath, allocator)
		if errDirect == nil do return dataDirect, true
	}

	return nil, false
}

AssetManager_ReadFileString :: proc(am: ^AssetManager, relPath: string, allocator := context.allocator) -> (string, bool) {
	bytes, ok := AssetManager_ReadFileBytes(am, relPath, allocator)
	if !ok do return "", false
	return string(bytes), true
}
