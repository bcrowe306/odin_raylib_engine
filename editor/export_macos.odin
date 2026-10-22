package editor

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import e "../engine"

// ============================================================================
// macOS export: <preset folder>/<Name>.app
//
//   Contents/Info.plist
//   Contents/MacOS/<Name>              the runner
//   Contents/Frameworks/*.dylib        the runner's libraries (liblua.dylib)
//   Contents/Resources/game.ore
//   Contents/Resources/fonts/OpenSans-Regular.ttf
//   Contents/Resources/AppIcon.icns    from the project icon (PNG)
//
// Signed with codesign when it's available (ad-hoc unless an identity is
// set in Export settings); with a notarytool keychain profile the app is
// then zipped, notarized and stapled in the background.
// ============================================================================

// Export_BundleId: the app's CFBundleIdentifier.
Export_BundleId :: proc(cfg: ^e.ProjectConfig, exeName: string) -> string {
	if cfg.export.bundleId != "" do return cfg.export.bundleId
	sb := strings.builder_make(context.temp_allocator)
	for r in strings.to_lower(exeName, context.temp_allocator) {
		if (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') || r == '-' do strings.write_rune(&sb, r)
	}
	id := strings.to_string(sb)
	return fmt.tprintf("com.ore.%s", id if id != "" else "game")
}

@(private = "file")
xml_escape :: proc(s: string) -> string {
	out, _ := strings.replace_all(s, "&", "&amp;", context.temp_allocator)
	out, _ = strings.replace_all(out, "<", "&lt;", context.temp_allocator)
	out, _ = strings.replace_all(out, ">", "&gt;", context.temp_allocator)
	return out
}

Export_InfoPlist :: proc(cfg: ^e.ProjectConfig, exeName: string, hasIcon: bool) -> string {
	version := cfg.version if cfg.version != "" else "1.0.0"
	display := cfg.windowTitle if cfg.windowTitle != "" else cfg.name
	sb := strings.builder_make(context.temp_allocator)
	strings.write_string(&sb, `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
`)
	kv :: proc(sb: ^strings.Builder, k, v: string) {fmt.sbprintf(sb, "\t<key>%s</key>\n\t<string>%s</string>\n", k, xml_escape(v))}
	kv(&sb, "CFBundleName", cfg.name if cfg.name != "" else exeName)
	kv(&sb, "CFBundleDisplayName", display if display != "" else exeName)
	kv(&sb, "CFBundleIdentifier", Export_BundleId(cfg, exeName))
	kv(&sb, "CFBundleExecutable", exeName)
	kv(&sb, "CFBundleVersion", version)
	kv(&sb, "CFBundleShortVersionString", version)
	kv(&sb, "CFBundlePackageType", "APPL")
	kv(&sb, "CFBundleInfoDictionaryVersion", "6.0")
	kv(&sb, "LSMinimumSystemVersion", "11.0")
	kv(&sb, "LSApplicationCategoryType", "public.app-category.games")
	if hasIcon do kv(&sb, "CFBundleIconFile", "AppIcon")
	strings.write_string(&sb, "\t<key>NSHighResolutionCapable</key>\n\t<true/>\n</dict>\n</plist>\n")
	return strings.to_string(sb)
}

// Export_WriteIcns writes an .icns from a PNG (PNG-encoded entries,
// 16..1024 px; macOS 10.7+).
Export_WriteIcns :: proc(pngPath, dst: string) -> bool {
	types := []string{"icp4", "icp5", "icp6", "ic07", "ic08", "ic09", "ic10", "ic11", "ic12", "ic13", "ic14"}
	sizes := []int{16, 32, 64, 128, 256, 512, 1024, 32, 64, 256, 512}
	images := e.Icon_Images(pngPath, sizes, context.temp_allocator)
	if len(images) != len(sizes) do return false
	be32 :: proc(buf: ^[dynamic]u8, v: int) {append(buf, u8(v >> 24), u8(v >> 16), u8(v >> 8), u8(v))}
	body := make([dynamic]u8, context.temp_allocator)
	for im, i in images {
		append(&body, ..transmute([]u8)types[i])
		be32(&body, len(im.png) + 8)
		append(&body, ..im.png)
	}
	out := make([dynamic]u8, context.temp_allocator)
	append(&out, 'i', 'c', 'n', 's')
	be32(&out, len(body) + 8)
	append(&out, ..body[:])
	return os.write_entire_file(dst, out[:]) == nil
}

// run_tool runs a command to completion; false (logged) when it fails.
run_tool :: proc(state: ^EditorState, cmd: []string) -> bool {
	st, _, stderr, err := os.process_exec({command = cmd}, context.temp_allocator)
	if err != nil {
		Editor_Log(state, .Warn, "%s: %v", cmd[0], err)
		return false
	}
	if st.exit_code != 0 {
		Editor_Log(state, .Error, "%s failed: %s", cmd[0], strings.trim_space(string(stderr)))
		return false
	}
	return true
}

// Export_MacApp builds <dir>/<name>.app from a runner (cfg: the project
// settings with the preset's overrides).
Export_MacApp :: proc(state: ^EditorState, cfg: ^e.ProjectConfig, runner, ore, dir, name: string) -> (string, bool) {
	app, _ := filepath.join({dir, strings.concatenate({name, ".app"}, context.temp_allocator)}, context.temp_allocator)
	_ = os.remove_all(app) // a fresh bundle (it's ours: <preset folder>/<name>.app)
	contents, _ := filepath.join({app, "Contents"}, context.temp_allocator)
	macos, _ := filepath.join({contents, "MacOS"}, context.temp_allocator)
	frameworks, _ := filepath.join({contents, "Frameworks"}, context.temp_allocator)
	res, _ := filepath.join({contents, "Resources"}, context.temp_allocator)
	for d in ([]string{macos, res}) do _ = os.make_directory_all(d)

	exe, _ := filepath.join({macos, name}, context.temp_allocator)
	if err := os.copy_file(exe, runner); err != nil {
		Editor_Log(state, .Error, "Could not copy the runner to %s: %v", exe, err)
		return "", false
	}
	// The runner's libraries (everything else in its folder).
	for lib in runner_libraries(runner) {
		_ = os.make_directory_all(frameworks)
		dst, _ := filepath.join({frameworks, filepath.base(lib)}, context.temp_allocator)
		_ = os.copy_file(dst, lib)
	}
	dstOre, _ := filepath.join({res, "game.ore"}, context.temp_allocator)
	if err := os.copy_file(dstOre, ore); err != nil {
		Editor_Log(state, .Error, "Could not write %s: %v", dstOre, err)
		return "", false
	}
	if cfg.export.includeFont {
		if font := runner_font(runner); font != "" {
			fonts, _ := filepath.join({res, "fonts"}, context.temp_allocator)
			_ = os.make_directory_all(fonts)
			dst, _ := filepath.join({fonts, RUNNER_FONT}, context.temp_allocator)
			_ = os.copy_file(dst, font)
		}
	}
	hasIcon := false
	if cfg.icon != "" {
		iconSrc, _ := filepath.join({state.projectPath, cfg.icon}, context.temp_allocator)
		icns, _ := filepath.join({res, "AppIcon.icns"}, context.temp_allocator)
		hasIcon = Export_WriteIcns(iconSrc, icns)
		if !hasIcon do Editor_Log(state, .Warn, "Could not make the app icon from %s", cfg.icon)
	}
	plist, _ := filepath.join({contents, "Info.plist"}, context.temp_allocator)
	if os.write_entire_file(plist, transmute([]u8)Export_InfoPlist(cfg, name, hasIcon)) != nil {
		Editor_Log(state, .Error, "Could not write %s", plist)
		return "", false
	}

	// Signing (macOS only; the bundle changed, so the runner's own
	// signature no longer covers it).
	when ODIN_OS == .Darwin {
		identity := cfg.export.macSign if cfg.export.macSign != "" else "-"
		if identity != "none" {
			cmd := make([dynamic]string, context.temp_allocator)
			append(&cmd, "codesign", "--force", "--deep", "-s", identity)
			// Developer ID signing for notarization: hardened runtime + timestamp.
			if identity != "-" do append(&cmd, "--options", "runtime", "--timestamp")
			append(&cmd, app)
			if run_tool(state, cmd[:]) do Editor_Log(state, .Info, "Signed %s (%s)", filepath.base(app), "ad-hoc" if identity == "-" else identity)
			if cfg.export.macNotaryProfile != "" {
				if identity == "-" {
					Editor_Log(state, .Warn, "Notarization needs a Developer ID signing identity (Export > Signing Identity)")
				} else {
					Export_Notarize(state, app, cfg.export.macNotaryProfile)
				}
			}
		}
	}
	return strings.clone(app, context.temp_allocator), true
}

// Export_Notarize zips the app, submits it with notarytool (waiting for the
// result) and staples the ticket - in the background, output in the console.
Export_Notarize :: proc(state: ^EditorState, app, profile: string) {
	zip := strings.concatenate({strings.trim_suffix(app, ".app"), ".zip"}, context.temp_allocator)
	script := fmt.tprintf(`ditto -c -k --keepParent "%s" "%s" && xcrun notarytool submit "%s" --keychain-profile "%s" --wait && xcrun stapler staple "%s"`, app, zip, zip, profile, app)
	if Editor_StartBuild(state, {"sh", "-c", script}, .Notarize) {
		Editor_Log(state, .Info, "Notarizing %s (this takes a few minutes)...", filepath.base(app))
	} else {
		Editor_Log(state, .Error, "Could not start notarization")
	}
}
