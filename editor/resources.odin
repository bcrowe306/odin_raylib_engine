package editor

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

// ============================================================================
// Where the editor's own files are (not the project's):
//
// - A source checkout (the editor built from this repo): the repo root - the
//   working directory, or above the executable (bin/editor) - recognised by
//   editor/main.odin and engine/. Engine developers' paths: bin/runners,
//   lua-language-server/, assets/demo_project, and Play may rebuild the game.
// - An installed editor: next to the executable (Windows, Linux) or the
//   .app's Contents/Resources (macOS), laid out as
//       runners/<platform>/      the prebuilt runners (export, Play)
//       lua-language-server/     the Code tab's language server
//       fonts/                   the engine's font (OpenSans-Regular.ttf)
//       templates/demo_project/  copied to Documents on the first start
//       docs/images/             the Node Reference's screenshots
//   RAYZR_EDITOR_RESOURCES overrides the folder.
//
// The editor's UI fonts are embedded (ui_style.odin): no file needed.
// ============================================================================

Editor_Resources :: struct {
	root:     string, // absolute
	checkout: bool,   // a source checkout (else an installed editor)
}

editorResources: Editor_Resources

// Resources_Init finds the editor's files; call first thing in main.
Resources_Init :: proc() {
	r := &editorResources
	if r.root != "" do delete(r.root)
	r^ = {}
	if v := os.get_env("RAYZR_EDITOR_RESOURCES", context.temp_allocator); v != "" {
		r.root = strings.clone(resources_abs(v))
		r.checkout = resources_is_checkout(r.root)
		return
	}
	exeDir := resources_abs(filepath.dir(os.args[0], context.temp_allocator) if len(os.args) > 0 else ".")
	candidates := make([dynamic]string, context.temp_allocator)
	if cwd, err := os.get_working_directory(context.temp_allocator); err == nil do append(&candidates, cwd)
	append(&candidates, exeDir, filepath.dir(exeDir, context.temp_allocator), filepath.dir(filepath.dir(exeDir, context.temp_allocator), context.temp_allocator))
	for c in candidates {
		if resources_is_checkout(c) {
			r.root = strings.clone(c)
			r.checkout = true
			return
		}
	}
	// Installed: the .app's Resources, else next to the executable.
	app, _ := filepath.join({exeDir, "..", "Resources"}, context.temp_allocator)
	app, _ = filepath.clean(app, context.temp_allocator)
	r.root = strings.clone(app if os.is_dir(app) else exeDir)
}

// Resource_Path joins a path under the editor's resource folder (temp).
Resource_Path :: proc(parts: ..string) -> string {
	all := make([dynamic]string, 0, len(parts) + 1, context.temp_allocator)
	append(&all, editorResources.root)
	append(&all, ..parts)
	p, _ := filepath.join(all[:], context.temp_allocator)
	return p
}

// Resources_InCheckout: the editor runs from a source checkout (engine
// development: Play may rebuild the game; the repo's demo project).
Resources_InCheckout :: proc() -> bool {
	return editorResources.checkout
}

// Resources_EngineFont: the engine's UI font (in-game UI text in the
// viewport, the exported runners' font).
Resources_EngineFont :: proc() -> string {
	if editorResources.checkout do return Resource_Path("engine", "Open_Sans", "static", "OpenSans-Regular.ttf")
	return Resource_Path("fonts", "OpenSans-Regular.ttf")
}

// Resources_RunnersDir: where this editor's prebuilt runners are.
Resources_RunnersDir :: proc() -> string {
	if editorResources.checkout do return Resource_Path("bin", "runners")
	return Resource_Path("runners")
}

// Resources_DefaultProject: the project opened when none is given - the
// repo's demo in a checkout; else the most recent project, else (the first
// start) a copy of the bundled demo in Documents/Rayzr Projects.
Resources_DefaultProject :: proc() -> string {
	if editorResources.checkout do return "assets/demo_project"
	for p in Editor_RecentProjectsAtStartup() {
		if os.is_file(fmt.tprintf("%s/project.json", p)) do return p
	}
	home, err := os.user_home_dir(context.temp_allocator)
	if err != nil do return ""
	dst, _ := filepath.join({home, "Documents", "Rayzr Projects", "Demo Project"}, context.temp_allocator)
	if os.is_file(fmt.tprintf("%s/project.json", dst)) do return dst
	src := Resource_Path("templates", "demo_project")
	if !os.is_dir(src) do return ""
	if !resources_copy_tree(src, dst) do return ""
	return dst
}

@(private = "file")
resources_is_checkout :: proc(dir: string) -> bool {
	main_, _ := filepath.join({dir, "editor", "main.odin"}, context.temp_allocator)
	engine, _ := filepath.join({dir, "engine"}, context.temp_allocator)
	return os.is_file(main_) && os.is_dir(engine)
}

@(private = "file")
resources_abs :: proc(p: string) -> string {
	if abs, err := os.get_absolute_path(p, context.temp_allocator); err == nil do return abs
	return p
}

// resources_copy_tree copies a folder (the demo project on the first start).
@(private = "file")
resources_copy_tree :: proc(src, dst: string) -> bool {
	if os.make_directory_all(dst) != nil do return false
	infos, err := os.read_all_directory_by_path(src, context.temp_allocator)
	if err != nil do return false
	for f in infos {
		to, _ := filepath.join({dst, f.name}, context.temp_allocator)
		if f.type == .Directory {
			if !resources_copy_tree(f.fullpath, to) do return false
			continue
		}
		data, rerr := os.read_entire_file(f.fullpath, context.temp_allocator)
		if rerr != nil do return false
		if os.write_entire_file(to, data) != nil do return false
	}
	return true
}
