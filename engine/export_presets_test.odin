package engine

import os "osx"
import "core:path/filepath"
import "core:strings"
import "core:testing"

@(test)
test_export_presets :: proc(t: ^testing.T) {
	src := `{"name": "Space Game", "version": "1.0.0", "window": {"title": "Space", "width": 1280, "height": 720},
		"export": {"targets": ["macos"], "presets": [
			{"name": "Mac Release", "target": "macos", "exclude": ["*.psd", "raw/"]},
			{"name": "Win Demo", "target": "windows", "executable": "SpaceDemo", "version": "0.9.1", "window_title": "Space (Demo)",
			 "window_width": 800, "window_height": 600, "fullscreen": true, "include": ["scenes", "textures/*.png"], "debug": true}]}}`
	cfg, ok := Project_ParseConfig(transmute([]u8)string(src))
	defer ProjectConfig_Destroy(&cfg)
	testing.expect(t, ok, "parsed")
	testing.expect_value(t, len(cfg.export.presets), 2)
	if len(cfg.export.presets) != 2 do return
	win := &cfg.export.presets[1]
	testing.expect_value(t, win.target, Export_Target.Windows)
	testing.expect_value(t, win.executableName, "SpaceDemo")
	testing.expect_value(t, win.fullscreen, Export_Toggle.On)
	testing.expect(t, win.debug && len(win.include) == 2, "debug + include")

	// Saved and read back the same.
	text := Project_SerializeToJSON(&cfg, context.temp_allocator)
	cfg2, ok2 := Project_ParseConfig(transmute([]u8)text)
	defer ProjectConfig_Destroy(&cfg2)
	testing.expect(t, ok2 && len(cfg2.export.presets) == 2, text)
	if len(cfg2.export.presets) == 2 {
		w2 := &cfg2.export.presets[1]
		testing.expect(t, w2.name == "Win Demo" && w2.version == "0.9.1" && w2.windowWidth == 800 && w2.fullscreen == .On && w2.debug, "preset round trip")
		testing.expect_value(t, cfg2.export.presets[0].exclude[1], "raw/")
	}
	clone := ProjectConfig_Clone(&cfg)
	testing.expect_value(t, clone.export.presets[1].include[1], "textures/*.png")
	ProjectConfig_Destroy(&clone)

	// Without presets: one per target.
	plain := Export_Settings{targets = {.MacOS, .Linux}}
	eff := Export_EffectivePresets(&plain)
	testing.expect(t, len(eff) == 2 && eff[0].target == .MacOS && eff[1].target == .Linux, "presets from targets")

	// Overrides for the packaged project.json.
	pc := Export_PresetConfig(&cfg, win)
	testing.expect(t, pc.version == "0.9.1" && pc.windowTitle == "Space (Demo)" && pc.windowWidth == 800 && pc.fullscreen, "preset overrides")
	testing.expect_value(t, Export_PresetConfig(&cfg, &cfg.export.presets[0]).windowTitle, "Space")

	// Patterns.
	testing.expect(t, Export_PatternMatch("*.psd", "art/hero.psd"), "file name anywhere")
	testing.expect(t, Export_PatternMatch("raw/", "raw/a/b.png") && !Export_PatternMatch("raw/", "rawfile.png"), "folder")
	testing.expect(t, Export_PatternMatch("scenes", "scenes/main.scene.json"), "folder without slash")
	testing.expect(t, Export_PatternMatch("textures/*.png", "textures/a.png") && !Export_PatternMatch("textures/*.png", "textures/sub/a.png"), "path pattern")
	mac := &cfg.export.presets[0]
	testing.expect(t, !Export_PresetIncludes(mac, "art/hero.psd") && Export_PresetIncludes(mac, "scenes/main.scene.json"), "exclude")
	testing.expect(t, Export_PresetIncludes(win, "project.json") && Export_PresetIncludes(win, "textures/a.png") && !Export_PresetIncludes(win, "audio/x.wav"), "include")

	// A package with the filter and a replaced project.json.
	dir, _ := filepath.join({Engine_TempDir(), "ore_preset_pkg"}, context.temp_allocator)
	_ = os.remove_all(dir)
	defer os.remove_all(dir)
	for f in ([]string{"project.json", "scenes/main.scene.json", "textures/a.png", "audio/x.wav"}) {
		p, _ := filepath.join({dir, "proj", f}, context.temp_allocator)
		_ = os.make_directory_all(filepath.dir(p, context.temp_allocator))
		_ = os.write_entire_file(p, transmute([]u8)string("{}"))
	}
	projDir, _ := filepath.join({dir, "proj"}, context.temp_allocator)
	out, _ := filepath.join({dir, "game.ore"}, context.temp_allocator)
	overrides := make(map[string][]u8, context.temp_allocator)
	overrides["project.json"] = transmute([]u8)string(`{"name": "patched"}`)
	filter :: proc(path: string, data: rawptr) -> bool {return Export_PresetIncludes(cast(^Export_Preset)data, path)}
	testing.expect(t, OrePackage_CreateFromDirectory(projDir, out, false, filter, win, overrides), "package written")
	pkg, pok := OrePackage_Open(out, context.temp_allocator)
	testing.expect(t, pok, "package opens")
	if !pok do return
	defer OrePackage_Close(pkg)
	_, hasWav := OrePackage_ReadFile(pkg, "audio/x.wav", context.temp_allocator)
	_, hasPng := OrePackage_ReadFile(pkg, "textures/a.png", context.temp_allocator)
	proj, _ := OrePackage_ReadFile(pkg, "project.json", context.temp_allocator)
	testing.expect(t, !hasWav && hasPng, "filtered")
	testing.expect_value(t, string(proj), `{"name": "patched"}`)
	testing.expect(t, strings.contains(text, `"name": "Win Demo"`), "written")
}
