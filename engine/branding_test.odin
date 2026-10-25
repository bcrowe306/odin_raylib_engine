package engine

import os "osx"
import "core:path/filepath"
import "core:testing"

// The rename from Ore (branding.odin): old packages, old project folders.
@(test)
test_branding_reads_what_ore_left :: proc(t: ^testing.T) {
	testing.expect(t, Is_PackagePath("game.rayzr") && Is_PackagePath("old/GAME.ORE"), "both extensions")
	testing.expect(t, !Is_PackagePath("scene.json") && !Is_PackagePath("store"), "not packages")

	// A package made before the rename ("ORE1") still opens.
	path, _ := filepath.join({Engine_TempDir(), "rayzr_brand_test.rayzr"}, context.temp_allocator)
	defer os.remove(path)
	if !testing.expect(t, RayzrPackage_CreateFromDirectory("tests/aseprite/project", path, true), "packaged") do return
	data, err := os.read_entire_file(path, context.temp_allocator)
	if !testing.expect(t, err == nil && len(data) > 4, "read") do return
	testing.expect(t, data[0] == 'R' && data[1] == 'Y' && data[2] == 'Z' && data[3] == '1', "new magic")
	data[0], data[1], data[2], data[3] = 'O', 'R', 'E', '1'
	pkg, ok := RayzrPackage_OpenFromMemory(data, context.temp_allocator)
	testing.expect(t, ok, "an ORE1 package opens")
	if ok {
		text, found := RayzrPackage_ReadString(pkg, "project.json", context.temp_allocator)
		testing.expect(t, found && len(text) > 0, "and reads")
		RayzrPackage_Close(pkg)
	}
	data[0] = 'X'
	logger := context.logger
	context.logger = {} // (the error it logs is expected)
	_, bad := RayzrPackage_OpenFromMemory(data, context.temp_allocator)
	context.logger = logger
	testing.expect(t, !bad, "other files don't")

	// A project's .ore/ becomes .rayzr/ - once.
	dir, _ := filepath.join({Engine_TempDir(), "rayzr_brand_project"}, context.temp_allocator)
	defer os.remove_all(dir)
	old, _ := filepath.join({dir, ".ore", "definitions"}, context.temp_allocator)
	_ = os.make_directory_all(old)
	marker, _ := filepath.join({old, "engine_api.lua"}, context.temp_allocator)
	_ = os.write_entire_file(marker, transmute([]u8)string("-- old"))
	testing.expect(t, Project_MigrateLegacyDir(dir), "moved")
	moved, _ := filepath.join({dir, ".rayzr", "definitions", "engine_api.lua"}, context.temp_allocator)
	testing.expect(t, os.is_file(moved), "its files came along")
	gone, _ := filepath.join({dir, ".ore"}, context.temp_allocator)
	testing.expect(t, !os.exists(gone), "no .ore/ left")
	_ = os.make_directory_all(gone)
	testing.expect(t, !Project_MigrateLegacyDir(dir), "a .rayzr/ already there: left alone")
}
