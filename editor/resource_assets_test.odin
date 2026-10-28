package editor

import "core:testing"

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
