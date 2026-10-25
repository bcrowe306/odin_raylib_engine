package engine

import "core:log"
import os "osx"
import "core:path/filepath"
import "core:strings"

// ============================================================================
// The engine's name (Rayzr; formerly Ore) and what the old name left on
// disk: projects' hidden ".ore/" folders, ".ore" packages (magic "ORE1") and
// the editor's ~/.config/ore_editor. New files use the new names; old ones
// are moved over when first seen (folders) or still read (packages).
// ============================================================================

BRAND_NAME :: "Rayzr"
PACKAGE_EXT :: ".rayzr" // packages (game.rayzr) and each project's hidden folder
LEGACY_PACKAGE_EXT :: ".ore"

// Is_PackagePath: a package file's path (.rayzr, or an old .ore).
Is_PackagePath :: proc(path: string) -> bool {
	lower := strings.to_lower(path, context.temp_allocator)
	return strings.has_suffix(lower, PACKAGE_EXT) || strings.has_suffix(lower, LEGACY_PACKAGE_EXT)
}

// Project_MigrateLegacyDir renames a project's old ".ore/" folder (editor
// state: open scenes, Lua definitions, history) to ".rayzr/" - once, when
// there is no ".rayzr/" yet. Returns whether it moved one.
Project_MigrateLegacyDir :: proc(projectDir: string) -> bool {
	if projectDir == "" || !os.is_dir(projectDir) do return false
	old, _ := filepath.join({projectDir, LEGACY_PACKAGE_EXT}, context.temp_allocator)
	new_, _ := filepath.join({projectDir, PACKAGE_EXT}, context.temp_allocator)
	if !os.is_dir(old) || os.exists(new_) do return false
	if err := os.rename(old, new_); err != nil {
		log.warnf("Couldn't rename %s to %s: %v", old, new_, err)
		return false
	}
	log.infof("Moved %s to %s (the engine's new name)", old, new_)
	return true
}

// Legacy_MigrateDir moves an old folder to its new name when only the old
// one exists (the editor's ~/.config/ore_editor). Returns whether it moved.
Legacy_MigrateDir :: proc(old, new_: string) -> bool {
	if !os.is_dir(old) || os.exists(new_) do return false
	if err := os.rename(old, new_); err != nil {
		log.warnf("Couldn't rename %s to %s: %v", old, new_, err)
		return false
	}
	log.infof("Moved %s to %s (the engine's new name)", old, new_)
	return true
}
