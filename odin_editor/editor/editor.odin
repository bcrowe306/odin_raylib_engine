// Package editor glues together `buffer`, `keymap`, `syntax`, and `lsp`
// into a complete, embeddable code editor widget, plus SDL3-based rendering
// and input handling. The host owns an `Editor` value and drives it
// explicitly via `editor_handle_event` / `editor_update` / `editor_render` —
// there is no global/singleton state, so multiple independent editors can
// coexist in one process.
package editor

import buf "../buffer"
import km "../keymap"
import lspc "../lsp"
import syn "../syntax"
import sdl "vendor:sdl3"

Editor :: struct {
	buf:       buf.Buffer,
	keymap:    km.Keymap,
	language:  syn.Language,

	lsp:          lspc.Client,
	lsp_enabled:  bool,
	document_uri: string,
	lsp_version:  int,

	// Viewport / scrolling (in cells, not pixels).
	scroll_line: int,
	scroll_col:  int,
	visible_rows: int,
	visible_cols: int,

	// Font metrics used both for rendering and for mouse-position hit
	// testing; set by the host once a font is loaded.
	char_w: f32,
	char_h: f32,

	injected_events: [dynamic]sdl.Event,
}

editor_init :: proc(
	platform: km.Platform,
	language: syn.Language = {},
	allocator := context.allocator,
) -> Editor {
	ed := Editor{
		buf      = buf.buffer_init(allocator),
		keymap   = km.keymap_default(platform, allocator),
		language = language,
		char_w   = 8,
		char_h   = 16,
		visible_rows = 32,
		visible_cols = 80,
	}
	if ed.language.tokenize == nil {
		ed.language = syn.odin_language()
	}
	ed.injected_events = make([dynamic]sdl.Event, allocator)
	return ed
}

editor_destroy :: proc(ed: ^Editor) {
	buf.buffer_destroy(&ed.buf)
	km.keymap_destroy(&ed.keymap)
	if ed.lsp_enabled {
		lspc.client_destroy(&ed.lsp)
	}
	if len(ed.document_uri) > 0 {
		delete(ed.document_uri)
	}
	delete(ed.injected_events)
}

// editor_primary_cursor returns a pointer to the first (primary) cursor.
editor_primary_cursor :: proc(ed: ^Editor) -> ^buf.Cursor {
	return &ed.buf.cursors[0]
}
