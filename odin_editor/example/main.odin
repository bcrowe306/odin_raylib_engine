// Standalone demo/test application for the odin_editor package. Opens an
// SDL3 window, hosts a single Editor, and demonstrates:
//   - normal interactive editing (type, navigate, select, undo/redo, etc.)
//   - file load/save via Ctrl/Cmd+S
//   - an optional scripted "self test" mode that drives the editor purely
//     through the event-injection hook (no real input required), proving
//     requirement #8 (SDL event injection for automated testing/demo).
//
// Usage:
//   example                 launch interactively, loading assets/sample.odin.txt
//   example --script        run the injected-event script, then continue interactively
//   example --script-only   run the injected-event script, print the result, and exit
//   example --e2e           run the full automated end-to-end test suite and exit
//                           (exit code 0 on success, 1 if any check failed)
package main

import ed "../editor"
import km "../keymap"
import "core:fmt"
import "core:os"
import "core:strings"
import sdl "vendor:sdl3"
import ttf "vendor:sdl3/ttf"

WINDOW_W :: 1100
WINDOW_H :: 720
FONT_SIZE :: 16

find_font_path :: proc() -> string {
	candidates := []string{
		"/System/Library/Fonts/SFNSMono.ttf",
		"/System/Library/Fonts/Menlo.ttc",
		"/System/Library/Fonts/Supplemental/Andale Mono.ttf",
		"/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
		"/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf",
	}
	for c in candidates {
		if os.exists(c) {
			return c
		}
	}
	return ""
}

// run_demo_script exercises the injection hook end-to-end: it types text,
// moves the cursor, selects, and deletes -- entirely via
// editor_inject_key/editor_inject_text, never touching real SDL input.
// This is requirement #8's "hook to inject SDL events to test the editor".
run_demo_script :: proc(e: ^ed.Editor, primary_mod: sdl.Keymod) {
	ed.editor_set_text(e, "")
	ed.editor_inject_text(e, "// injected by demo script\n")
	ed.editor_inject_text(e, "hello := \"world\"")
	ed.editor_pump_injected_events(e)

	ed.editor_inject_key(e, sdl.K_HOME)
	ed.editor_pump_injected_events(e)

	ed.editor_inject_key(e, sdl.K_END, sdl.KMOD_SHIFT)
	ed.editor_pump_injected_events(e)

	ed.editor_inject_key(e, sdl.K_C, primary_mod)
	ed.editor_pump_injected_events(e)

	ed.editor_inject_key(e, sdl.K_RIGHT)
	ed.editor_inject_text(e, "\n")
	ed.editor_inject_key(e, sdl.K_V, primary_mod)
	ed.editor_pump_injected_events(e)

	fmt.println("--- demo script result ---")
	text := ed.editor_to_string(e, context.temp_allocator)
	fmt.println(text)
	fmt.println("--- end demo script result ---")
}

main :: proc() {
	run_script := false
	script_only := false
	run_e2e := false
	for arg in os.args[1:] {
		switch arg {
		case "--script":
			run_script = true
		case "--script-only":
			run_script = true
			script_only = true
		case "--e2e":
			run_e2e = true
		}
	}

	platform := km.Platform.Other
	primary_mod := sdl.KMOD_CTRL
	word_mod := sdl.KMOD_CTRL
	when ODIN_OS == .Darwin {
		platform = km.Platform.MacOS
		primary_mod = sdl.KMOD_GUI
		word_mod = sdl.KMOD_ALT
	}

	editor := ed.editor_init(platform)
	defer ed.editor_destroy(&editor)

	sample_path := "odin_editor/example/assets/sample.odin.txt"
	if os.exists(sample_path) {
		_ = ed.editor_load_file(&editor, sample_path)
	} else if os.exists("assets/sample.odin.txt") {
		_ = ed.editor_load_file(&editor, "assets/sample.odin.txt")
	}

	// SDL must be initialized before the demo script runs: clipboard
	// copy/paste (exercised by run_demo_script) requires the video
	// subsystem to be up even when no window is shown.
	if !sdl.Init(sdl.INIT_VIDEO) {
		fmt.eprintln("sdl.Init failed:", sdl.GetError())
		os.exit(1)
	}
	defer sdl.Quit()

	if run_script {
		run_demo_script(&editor, primary_mod)
		if script_only {
			return
		}
	}

	if !ttf.Init() {
		fmt.eprintln("ttf.Init failed:", sdl.GetError())
		os.exit(1)
	}
	defer ttf.Quit()

	window: ^sdl.Window
	renderer: ^sdl.Renderer
	if !sdl.CreateWindowAndRenderer("odin_editor demo", WINDOW_W, WINDOW_H, sdl.WINDOW_RESIZABLE, &window, &renderer) {
		fmt.eprintln("CreateWindowAndRenderer failed:", sdl.GetError())
		os.exit(1)
	}
	defer sdl.DestroyWindow(window)
	defer sdl.DestroyRenderer(renderer)

	font_path := find_font_path()
	font: ^ttf.Font
	if font_path != "" {
		cpath := strings.clone_to_cstring(font_path, context.temp_allocator)
		font = ttf.OpenFont(cpath, FONT_SIZE)
	}
	if font == nil {
		fmt.eprintln("warning: could not open a monospace font; text will not render")
	}
	defer if font != nil {
		ttf.CloseFont(font)
	}

	char_w, char_h: f32 = 9, 18
	if font != nil {
		w, h: i32
		if ttf.GetStringSize(font, "M", 1, &w, &h) {
			char_w, char_h = f32(w), f32(h)
		}
	}
	editor.char_w = char_w
	editor.char_h = char_h
	editor.visible_cols = int(WINDOW_W / char_w)
	editor.visible_rows = int(WINDOW_H / char_h)

	_ = sdl.StartTextInput(window)
	defer _ = sdl.StopTextInput(window)

	theme := ed.default_theme()

	if run_e2e {
		all_pass := run_e2e_suite(&editor, renderer, font, theme, primary_mod, word_mod)
		os.exit(all_pass ? 0 : 1)
	}

	running := true
	for running {
		event: sdl.Event
		for sdl.PollEvent(&event) {
			#partial switch event.type {
			case .QUIT:
				running = false
			case .WINDOW_RESIZED:
				w, h: i32
				sdl.GetWindowSize(window, &w, &h)
				editor.visible_cols = int(f32(w) / char_w)
				editor.visible_rows = int(f32(h) / char_h)
			}
			handled := ed.editor_handle_event(&editor, event)
			if !handled && event.type == .KEY_DOWN {
				handle_host_level_shortcuts(&editor, event.key)
			}
		}

		ed.editor_update(&editor)

		sdl.SetRenderDrawColor(renderer, 30, 30, 30, 255)
		sdl.RenderClear(renderer)
		ed.editor_render(&editor, renderer, font, theme, 0, 0)
		sdl.RenderPresent(renderer)

		sdl.Delay(8)
	}
}

// handle_host_level_shortcuts deals with actions the Editor package
// intentionally reports as "not handled" because they require host/OS
// integration (file dialogs, real clipboard already handled inside the
// editor though). Here we just wire Save to the currently open file.
handle_host_level_shortcuts :: proc(e: ^ed.Editor, key: sdl.KeyboardEvent) {
	ctrl_or_cmd := .LCTRL in key.mod || .RCTRL in key.mod || .LGUI in key.mod || .RGUI in key.mod
	if ctrl_or_cmd && key.key == sdl.K_S {
		if ed.editor_save(e) {
			fmt.println("saved", e.document_uri)
		}
	}
}
