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
	// uri_key of document_uri (decoded + symlink-resolved), used to look up
	// diagnostics the server may publish under a different spelling.
	document_key: string,
	lsp_version:  int,
	// didOpen has been sent for document_uri (deferred until the server
	// has answered `initialize`, as the spec requires).
	lsp_doc_open: bool,
	// buf.version last pushed to the server via didOpen/didChange.
	lsp_synced_version: int,
	lsp_supervisor: Lsp_Supervisor,

	completion: Completion_State,
	signature:  Signature_State,
	diag_tip:   Diagnostic_Tooltip,

	// Viewport / scrolling (in cells, not pixels). scroll_col is a visual
	// column (tabs expanded), not a byte offset.
	scroll_line: int,
	scroll_col:  int,
	tab_width:   int,
	visible_rows: int,
	visible_cols: int,

	// Font metrics used both for rendering and for mouse-position hit
	// testing; set by the host once a font is loaded.
	char_w: f32,
	char_h: f32,

	// Top-left of the editor in window pixels as of the last
	// editor_render, so mouse hit-testing works for hosts that draw the
	// editor at an offset.
	origin_x: f32,
	origin_y: f32,

	mouse: Mouse_State,
	// Modifier keys currently held, tracked from the KEY_DOWN/KEY_UP
	// events the editor receives (so injected modifier presses work for
	// mouse gestures like Shift+click, which SDL mouse events don't carry).
	key_mods: km.Modifiers,

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
		tab_width    = DEFAULT_TAB_WIDTH,
	}
	if ed.language.tokenize == nil {
		ed.language = syn.odin_language()
	}
	ed.injected_events = make([dynamic]sdl.Event, allocator)
	ed.completion.filtered = make([dynamic]int, allocator)
	return ed
}

editor_destroy :: proc(ed: ^Editor) {
	buf.buffer_destroy(&ed.buf)
	km.keymap_destroy(&ed.keymap)
	if ed.lsp_enabled {
		lspc.client_destroy(&ed.lsp)
	}
	lsp_supervisor_end(&ed.lsp_supervisor)
	if len(ed.document_uri) > 0 {
		delete(ed.document_uri)
	}
	delete(ed.document_key)
	delete(ed.injected_events)
	delete(ed.completion.filtered)
}

// editor_primary_cursor returns a pointer to the first (primary) cursor.
editor_primary_cursor :: proc(ed: ^Editor) -> ^buf.Cursor {
	return &ed.buf.cursors[0]
}
