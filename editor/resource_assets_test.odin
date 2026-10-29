package editor

import "core:os"
import "core:path/filepath"
import "core:testing"
import e "../engine"

// Resources in the Assets panel: their kind, name, import folder, and how
// class scripts are recognised (the explicit `resource` marker).
@(test)
test_resource_asset_kind :: proc(t: ^testing.T) {
	testing.expect_value(t, Asset_KindOf("resources/boss.resource.json"), Asset_Kind.Resource)
	testing.expect_value(t, Asset_KindOf("resources/Boss.Resource.JSON"), Asset_Kind.Resource)
	testing.expect_value(t, Asset_KindOf("scenes/main.scene.json"), Asset_Kind.Scene)
	testing.expect_value(t, Asset_DisplayName("resources/boss.resource.json"), "boss")
	testing.expect_value(t, Asset_DisplayName("resources/weapons/sword.resource.json", true), "resources/weapons/sword")
	dir, ok := Asset_ImportDir("sword.resource.json")
	testing.expect(t, ok && dir == "resources", "imported into resources/")
	testing.expect_value(t, Script_AssetKind("resources/sword.resource.json"), "resource")
}

@(test)
test_resource_class_marker_detection :: proc(t: ^testing.T) {
	testing.expect(t, Resource_HasClassMarker("local H = {}\nH.resource = { local_copy = true }\nreturn H"), "marker")
	testing.expect(t, Resource_HasClassMarker("local Item = {}\n  Item.resource={}\nreturn Item"), "no spaces, indented")
	testing.expect(t, !Resource_HasClassMarker("local S = {}\n-- S.resource = {}\nreturn S"), "commented out")
	testing.expect(t, !Resource_HasClassMarker("local S = {}\nS.resource = true\nreturn S"), "not a table")
	testing.expect(t, !Resource_HasClassMarker("local S = {}\nS.resources = {}\nS.properties = {}\nreturn S"), "another field")
	testing.expect(t, !Resource_HasClassMarker("x = self.resource\n"), "a read, not the marker")
}

// Regression test for issue #70: renaming a scene (or other asset) without its
// compound suffix or extension must auto-append the appropriate suffix and
// extension so the scene/asset is not lost.
@(test)
test_asset_rename_preserves_suffix :: proc(t: ^testing.T) {
	tmpDir, _ := filepath.join({os.get_env("TMPDIR", context.temp_allocator), "rayzr_rename_test_70"}, context.temp_allocator)
	_ = os.remove_all(tmpDir)
	scenesDir, _ := filepath.join({tmpDir, "scenes"}, context.temp_allocator)
	_ = os.make_directory_all(scenesDir)
	defer _ = os.remove_all(tmpDir)

	scenePath, _ := filepath.join({scenesDir, "main.scene.json"}, context.temp_allocator)
	_ = os.write_entire_file(scenePath, transmute([]u8)string("{}"))

	game: e.Game
	state: EditorState
	state.game = &game
	state.projectPath = tmpDir

	// User renames "scenes/main.scene.json" to "level1" (forgetting ".scene.json").
	ok1 := Asset_Rename(&state, "scenes/main.scene.json", "level1")
	testing.expect(t, ok1, "Asset_Rename should succeed")
	dst1, _ := filepath.join({scenesDir, "level1.scene.json"}, context.temp_allocator)
	testing.expect(t, os.exists(dst1), "renaming scene to 'level1' should produce 'scenes/level1.scene.json'")

	// User renames "scenes/level1.scene.json" to "level2.scene" (forgetting ".json").
	if os.exists(dst1) {
		ok2 := Asset_Rename(&state, "scenes/level1.scene.json", "level2.scene")
		testing.expect(t, ok2, "Asset_Rename with partial .scene suffix should succeed")
		dst2, _ := filepath.join({scenesDir, "level2.scene.json"}, context.temp_allocator)
		testing.expect(t, os.exists(dst2), "renaming scene to 'level2.scene' should produce 'scenes/level2.scene.json'")

		// User renames "scenes/level2.scene.json" to "level3.json" (forgetting ".scene").
		if os.exists(dst2) {
			ok3 := Asset_Rename(&state, "scenes/level2.scene.json", "level3.json")
			testing.expect(t, ok3, "Asset_Rename with partial .json suffix should succeed")
			dst3, _ := filepath.join({scenesDir, "level3.scene.json"}, context.temp_allocator)
			testing.expect(t, os.exists(dst3), "renaming scene to 'level3.json' should produce 'scenes/level3.scene.json'")
		}
	}

	// Verify Asset_NormalizedRename across all asset types and folders.
	testing.expect_value(t, Asset_NormalizedRename("scenes/main.scene.json", "arena"), "arena.scene.json")
	testing.expect_value(t, Asset_NormalizedRename("scenes/main.scene.json", "arena.scene"), "arena.scene.json")
	testing.expect_value(t, Asset_NormalizedRename("scenes/main.scene.json", "arena.json"), "arena.scene.json")
	testing.expect_value(t, Asset_NormalizedRename("scenes/main.scene.json", "arena.scene.json"), "arena.scene.json")
	testing.expect_value(t, Asset_NormalizedRename("components/Ship.component.json", "Drone"), "Drone.component.json")
	testing.expect_value(t, Asset_NormalizedRename("components/Ship.component.json", "Drone.component"), "Drone.component.json")
	testing.expect_value(t, Asset_NormalizedRename("components/Ship.component.json", "Drone.json"), "Drone.component.json")
	testing.expect_value(t, Asset_NormalizedRename("resources/boss.resource.json", "miniboss"), "miniboss.resource.json")
	testing.expect_value(t, Asset_NormalizedRename("resources/boss.resource.json", "miniboss.resource"), "miniboss.resource.json")
	testing.expect_value(t, Asset_NormalizedRename("resources/boss.resource.json", "miniboss.json"), "miniboss.resource.json")
	testing.expect_value(t, Asset_NormalizedRename("scripts/player.lua", "hero"), "hero.lua")
	testing.expect_value(t, Asset_NormalizedRename("scripts/player.lua", "hero.lua"), "hero.lua")
	testing.expect_value(t, Asset_NormalizedRename("textures/ship.png", "boat"), "boat.png")
	testing.expect_value(t, Asset_NormalizedRename("textures/ship.png", "boat.png"), "boat.png")
	testing.expect_value(t, Asset_NormalizedRename("levels/world.ldtk", "dungeon"), "dungeon.ldtk")
	testing.expect_value(t, Asset_NormalizedRename("textures/enemies", "bosses", isFolder = true), "bosses")

	ProjectFiles_Shutdown()
	for entry in state.logs {
		delete(entry.time)
		delete(entry.message)
	}
	delete(state.logs)
}

