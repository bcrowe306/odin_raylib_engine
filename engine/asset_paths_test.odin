package engine

import "core:strings"
import "core:testing"

@(test)
test_asset_path_rewrite :: proc(t: ^testing.T) {
	scene := `{"texture": "textures/ship.png", "other": "textures/ship.png.bak", "x": "textures/ship_2.png", "s": "scripts/a.lua"}`
	out, n := AssetPath_Rewrite(scene, "textures/ship.png", "textures/player/ship.png", false, context.temp_allocator)
	testing.expect_value(t, n, 1)
	testing.expect_value(t, out, `{"texture": "textures/player/ship.png", "other": "textures/ship.png.bak", "x": "textures/ship_2.png", "s": "scripts/a.lua"}`)

	// Lua single quotes too; a folder rewrites everything inside it, not
	// a folder that only starts with the same name.
	lua := `local a = 'textures/ship.png' local b = "textures/fx/boom.png" local c = "texturesX/y.png"`
	out, n = AssetPath_Rewrite(lua, "textures", "art", true, context.temp_allocator)
	testing.expect_value(t, n, 2)
	testing.expect_value(t, out, `local a = 'art/ship.png' local b = "art/fx/boom.png" local c = "texturesX/y.png"`)
	testing.expect_value(t, AssetPath_Count(scene, "scripts/a.lua", false), 1)
	testing.expect_value(t, AssetPath_Count(scene, "textures", true), 3)

	// Texture import settings: saved in project.json, found by relative path.
	cfg, ok := Project_ParseConfig(transmute([]u8)string(`{"name": "T"}`), context.temp_allocator)
	testing.expect(t, ok, "parsed")
	ProjectConfig_SetTextureImport(&cfg, {path = "textures/bg.png", filter = .Bilinear, wrap = .Clamp, mipmaps = true})
	ProjectConfig_SetTextureImport(&cfg, {path = "textures/pixel.png"}) // the defaults: not stored
	testing.expect_value(t, len(cfg.textureImport), 1)
	text := Project_SerializeToJSON(&cfg, context.temp_allocator)
	testing.expect(t, strings.contains(text, `"textures/bg.png": {"filter": "bilinear", "wrap": "clamp", "mipmaps": true}`), "saved")
	moved, _ := AssetPath_Rewrite(text, "textures/bg.png", "textures/sky/bg.png", false, context.temp_allocator)
	cfg2, ok2 := Project_ParseConfig(transmute([]u8)moved, context.temp_allocator)
	testing.expect(t, ok2 && len(cfg2.textureImport) == 1 && cfg2.textureImport[0].path == "textures/sky/bg.png", "the setting follows a move")
	Texture_ImportsSet(cfg2.textureImport[:])
	defer Texture_ImportsSet(nil)
	rm := ResourceManager{projectDir = "/proj"}
	imp := Texture_ImportFor(&rm, "/proj/textures/sky/bg.png")
	testing.expect(t, imp.filter == .Bilinear && imp.wrap == .Clamp && imp.mipmaps, "found by full path")
	testing.expect(t, Texture_ImportIsDefault(Texture_ImportFor(&rm, "/proj/textures/other.png")), "others: defaults")
	ProjectConfig_SetTextureImport(&cfg, {path = "textures/bg.png"})
	testing.expect_value(t, len(cfg.textureImport), 0)
}
