package engine

import os "osx"
import "core:strings"
import "core:testing"
import rl "vendor:raylib"

// Per-asset import settings: the file's text round-trips (only non-defaults
// written, defaults delete the file), textures take it over project.json,
// audio gain is applied when decoded, the import bus is the default bus,
// export stores "compress": "qoi" textures as QOI that loads back, and the
// cache is freed on reset (leak tracker).
@(test)
test_asset_import_settings :: proc(t: ^testing.T) {
	dir :: "test_asset_import_zz"
	_ = os.make_directory_all(dir + "/textures")
	_ = os.make_directory_all(dir + "/audio")
	defer os.remove_all(dir)
	defer Asset_ImportsReset()

	// Text.
	a := Asset_Import{filter = .Bilinear, wrap = .Clamp, slice = {grid = {4, 2}, spacing = {1, 1}}, compress = .QOI, gainDb = -6, bus = "UI"}
	text := Asset_ImportToJSON(a, context.temp_allocator)
	b: Asset_Import
	Asset_ImportParse(text, &b, context.temp_allocator)
	testing.expectf(t, b.found && b.filter == .Bilinear && b.wrap == .Clamp && b.slice == a.slice && b.compress == .QOI && b.gainDb == -6 && b.bus == "UI", "round trip: %s", text)
	testing.expect(t, !strings.contains(text, "mipmaps") && !strings.contains(text, "atlas"), "only what differs from the defaults")
	broken: Asset_Import
	Asset_ImportParse("{not json", &broken)
	testing.expect(t, !broken.found && Asset_ImportIsDefault(broken), "a broken file gives the defaults")

	// Textures: the file wins over project.json; defaults delete it.
	img := rl.GenImageColor(8, 4, rl.RED)
	rl.ExportImage(img, "test_asset_import_zz/textures/a.png")
	rl.UnloadImage(img)
	rm := ResourceManager{projectDir = dir}
	Texture_ImportsSet({{path = "textures/a.png", filter = .Trilinear}})
	defer Texture_ImportsSet(nil)
	testing.expect_value(t, Texture_ImportFor(&rm, "test_asset_import_zz/textures/a.png").filter, Texture_Filter.Trilinear)
	testing.expect(t, Asset_ImportSave(&rm, "test_asset_import_zz/textures/a.png", {filter = .Bilinear, slice = {grid = {2, 1}}}), "saved")
	testing.expect(t, os.is_file("test_asset_import_zz/textures/a.png.import.json"), "next to the asset")
	testing.expect_value(t, Texture_ImportFor(&rm, "test_asset_import_zz/textures/a.png").filter, Texture_Filter.Bilinear)
	testing.expect_value(t, Asset_ImportGet(&rm, "textures/a.png").slice.grid, [2]int{2, 1}) // (same entry by relative path)
	testing.expect(t, Asset_ImportSave(&rm, "test_asset_import_zz/textures/a.png", {}) && !os.is_file("test_asset_import_zz/textures/a.png.import.json"), "the defaults delete the file")
	testing.expect_value(t, Texture_ImportFor(&rm, "test_asset_import_zz/textures/a.png").filter, Texture_Filter.Trilinear)

	// Audio: a 0.25 constant wave; +6 dB doubles it when decoded.
	samples := make([]f32, 4800, context.temp_allocator)
	for &s in samples do s = 0.25
	wave := rl.Wave{frameCount = 4800, sampleRate = MIXER_RATE, sampleSize = 32, channels = 1, data = raw_data(samples)}
	rl.ExportWave(wave, "test_asset_import_zz/audio/hit.wav")
	_ = os.write_entire_file("test_asset_import_zz/audio/hit.wav.import.json", transmute([]u8)string(`{"gain_db": 6.0206, "bus": "UI"}`))
	snd, ok := ResourceManager_LoadAudioSound(&rm, "test_asset_import_zz/audio/hit.wav")
	testing.expect(t, ok && snd != nil && len(snd.pcm) > 100, "loaded")
	if ok do testing.expectf(t, abs(snd.pcm[100] - 0.5) < 0.01, "gain applied once when decoded (%v)", snd.pcm[100])
	Mixer_Init()
	defer Mixer_Shutdown()
	ui := Mixer_AddBus("UI")
	testing.expect_value(t, Audio_BusFor(&rm, "test_asset_import_zz/audio/hit.wav", "SFX"), ui)
	testing.expect_value(t, Audio_BusFor(&rm, "test_asset_import_zz/audio/none.wav", "SFX"), Mixer_BusIndex("SFX"))
	if ok do ResourceManager_ReleaseSound(&rm, snd)

	// Export: "compress": "qoi" -> QOI bytes under the same name, loading back.
	_ = os.write_entire_file("test_asset_import_zz/textures/a.png.import.json", transmute([]u8)string(`{"compress": "qoi"}`))
	overrides := make(map[string][]u8, context.temp_allocator)
	n := Asset_ExportOverrides(dir, &overrides, allocator = context.temp_allocator)
	q, has := overrides["textures/a.png"]
	testing.expect(t, n == 1 && has && len(q) > 4 && string(q[:4]) == "qoif", "QOI under the original name")
	if has {
		back := rl.LoadImageFromMemory(strings.clone_to_cstring(Image_ExtFor(q, "textures/a.png"), context.temp_allocator), raw_data(q), i32(len(q)))
		testing.expect(t, back.width == 8 && back.height == 4, "the loaders decode it")
		rl.UnloadImage(back)
	}
	// A preset that leaves the file out: not converted.
	skip :: proc(path: string, data: rawptr) -> bool {return false}
	clear(&overrides)
	testing.expect_value(t, Asset_ExportOverrides(dir, &overrides, skip, nil, context.temp_allocator), 0)
}
