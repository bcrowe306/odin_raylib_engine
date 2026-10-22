package editor

import "core:os"
import "core:path/filepath"
import "core:strings"
import e "../engine"

// ============================================================================
// Standalone export: for each target platform, a folder with a prebuilt
// runner (renamed to the game), game.ore and the UI font - no compiler
// needed. Runners come with the editor in runners/<platform>/ (next to the
// editor, or bin/runners/ in a source checkout; scripts/build_runners.sh
// builds the current platform's). Without one for this platform the editor
// builds it once (needs `odin`) into bin/runners/ and then exports.
//
//   <output>/<platform>/<Name>[.exe]        (+ the runner's libraries)
//   <output>/<platform>/game.ore
//   <output>/<platform>/fonts/OpenSans-Regular.ttf
//   <output>/macos/<Name>.app                (export_macos.odin)
// ============================================================================

RUNNER_FONT :: "OpenSans-Regular.ttf"

runner_file_name :: proc(t: e.Export_Target) -> string {
	return "runner.exe" if t == .Windows else "runner"
}

// Editor_RunnersDirs: where prebuilt runners are looked for, in order.
Editor_RunnersDirs :: proc() -> []string {
	out := make([dynamic]string, context.temp_allocator)
	exeDir := filepath.dir(os.args[0], context.temp_allocator)
	if !filepath.is_abs(exeDir) {
		if abs, err := os.get_absolute_path(exeDir, context.temp_allocator); err == nil do exeDir = abs
	}
	add :: proc(out: ^[dynamic]string, parts: ..string) {
		p, _ := filepath.join(parts, context.temp_allocator)
		for q in out do if q == p do return
		append(out, p)
	}
	add(&out, exeDir, "runners")                                        // shipped editor
	add(&out, filepath.dir(exeDir, context.temp_allocator), "runners") // macOS .app: Contents/MacOS/..
	add(&out, exeDir, "bin", "runners")                                 // editor binary at the repo root
	if cwd, err := os.get_working_directory(context.temp_allocator); err == nil do add(&out, cwd, "bin", "runners")
	return out[:]
}

// Editor_FindRunner: the prebuilt runner for a platform ("" = none).
Editor_FindRunner :: proc(t: e.Export_Target) -> string {
	for dir in Editor_RunnersDirs() {
		p, _ := filepath.join({dir, e.export_target_name(t), runner_file_name(t)}, context.temp_allocator)
		if os.is_file(p) do return p
	}
	return ""
}

// runner_libraries: the shared libraries shipped with a runner (every other
// file in its folder).
runner_libraries :: proc(runner: string) -> []string {
	out := make([dynamic]string, context.temp_allocator)
	infos, err := os.read_all_directory_by_path(filepath.dir(runner, context.temp_allocator), context.temp_allocator)
	if err != nil do return out[:]
	for f in infos {
		if f.type != .Regular || strings.has_prefix(f.name, ".") || f.fullpath == runner || f.name == filepath.base(runner) do continue
		append(&out, f.fullpath)
	}
	return out[:]
}

// runner_font: the UI font shipped with runners (or the engine's copy).
runner_font :: proc(runner: string) -> string {
	p, _ := filepath.join({filepath.dir(filepath.dir(runner, context.temp_allocator), context.temp_allocator), RUNNER_FONT}, context.temp_allocator)
	if os.is_file(p) do return p
	dev :: "engine/Open_Sans/static/OpenSans-Regular.ttf"
	if os.is_file(dev) do return dev
	return ""
}

// Editor_ExportStandalone exports every selected target that has a runner
// (afterBuild: called back once this platform's runner was built).
Editor_ExportStandalone :: proc(state: ^EditorState, afterBuild := false) {
	if state.buildRunning {
		Editor_Log(state, .Warn, "A build is already running")
		return
	}
	Editor_SaveAllScenes(state)
	Code_SaveAll(state)
	cfg := &state.projectConfig
	x := &cfg.export
	clean := strings.trim_suffix(state.projectPath, "/")
	name := x.executableName if x.executableName != "" else export_default_name(cfg)
	outDir := x.outputDir if x.outputDir != "" else strings.concatenate({clean, "_standalone"}, context.temp_allocator)
	targets := x.targets if x.targets != {} else {e.native_export_target()}

	// This platform's runner is built once when it isn't there yet.
	native := e.native_export_target()
	if native in targets && Editor_FindRunner(native) == "" {
		if afterBuild {
			Editor_Log(state, .Error, "The runner was built but isn't in any of: %s", strings.join(Editor_RunnersDirs(), ", ", context.temp_allocator))
			return
		}
		dst, _ := filepath.join({"bin", "runners", e.export_target_name(native), runner_file_name(native)}, context.temp_allocator)
		_ = os.make_directory_all(filepath.dir(dst, context.temp_allocator))
		// The script also ships the runner's libraries (Lua on macOS / Windows).
		cmd := []string{"bash", "scripts/build_runners.sh"} if os.is_file("scripts/build_runners.sh") else []string{"odin", "build", "runner", "-o:speed", strings.concatenate({"-out:", dst}, context.temp_allocator)}
		if !Editor_StartBuild(state, cmd, .Standalone) {
			Editor_Log(state, .Error, "No prebuilt %s runner, and it couldn't be built (is `odin` on PATH?)", e.export_target_name(native))
			return
		}
		Editor_Log(state, .Info, "No prebuilt %s runner: building it once (later exports reuse it)...", e.export_target_name(native))
		return // Editor_UpdatePlaytest calls back when the build succeeds
	}

	_ = os.make_directory_all(outDir)
	ore, _ := filepath.join({outDir, "game.ore"}, context.temp_allocator)
	if !e.OrePackage_CreateFromDirectory(state.projectPath, ore, x.compress) {
		Editor_Log(state, .Error, "Failed to package the project into %s", ore)
		return
	}
	exported := 0
	for t in e.Export_Target {
		if t not_in targets do continue
		runner := Editor_FindRunner(t)
		if runner == "" {
			Editor_Log(state, .Warn, "No %s runner: build one on %s (scripts/build_runners.sh) and put it in runners/%s/ next to the editor", e.export_target_name(t), e.export_target_name(t), e.export_target_name(t))
			continue
		}
		dir: string
		ok: bool
		if t == .MacOS do dir, ok = Export_MacApp(state, runner, ore, outDir, name)
		else do dir, ok = export_target(state, t, runner, ore, outDir, name)
		if ok {
			Editor_Log(state, .Info, "Exported %s: %s", e.export_target_name(t), dir)
			exported += 1
		}
	}
	_ = os.remove(ore) // copied into each target's folder
	if state.exportDir != "" do delete(state.exportDir)
	state.exportDir = strings.clone(outDir)
	if exported > 0 do Editor_Log(state, .Info, "Standalone game ready: %s (%d platform(s))", outDir, exported)
}

@(private = "file")
export_target :: proc(state: ^EditorState, t: e.Export_Target, runner, ore, outDir, name: string) -> (string, bool) {
	dir, _ := filepath.join({outDir, e.export_target_name(t)}, context.temp_allocator)
	_ = os.make_directory_all(dir)
	exeName := strings.concatenate({name, ".exe"}, context.temp_allocator) if t == .Windows else name
	exe, _ := filepath.join({dir, exeName}, context.temp_allocator)
	if err := os.copy_file(exe, runner); err != nil {
		Editor_Log(state, .Error, "Could not copy the runner to %s: %v", exe, err)
		return "", false
	}
	for lib in runner_libraries(runner) {
		dst, _ := filepath.join({dir, filepath.base(lib)}, context.temp_allocator)
		_ = os.copy_file(dst, lib)
	}
	dstOre, _ := filepath.join({dir, "game.ore"}, context.temp_allocator)
	if err := os.copy_file(dstOre, ore); err != nil {
		Editor_Log(state, .Error, "Could not write %s: %v", dstOre, err)
		return "", false
	}
	if state.projectConfig.export.includeFont {
		if font := runner_font(runner); font != "" {
			fonts, _ := filepath.join({dir, "fonts"}, context.temp_allocator)
			_ = os.make_directory_all(fonts)
			dst, _ := filepath.join({fonts, RUNNER_FONT}, context.temp_allocator)
			_ = os.copy_file(dst, font)
		}
	}
	return strings.clone(dir, context.temp_allocator), true
}
