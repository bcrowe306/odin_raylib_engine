// SDL3 event handling: translates keyboard/text-input events into keymap
// chords/actions and buffer mutations. This is the thin glue layer that
// depends on SDL; the pure logic it calls into (editor_apply_action,
// buffer ops) is unit tested independently.
package editor

import km "../keymap"
import sdl "vendor:sdl3"

// editor_handle_event processes one SDL event. Returns true if the editor
// consumed it (host can use this to decide whether to also forward the
// event elsewhere, e.g. UI focus chrome around the editor widget).
editor_handle_event :: proc(ed: ^Editor, ev: sdl.Event) -> bool {
	#partial switch ev.type {
	case .KEY_DOWN:
		return editor_handle_key_down(ed, ev.key)
	case .TEXT_INPUT:
		text := string(ev.text.text)
		if len(text) > 0 {
			editor_insert_text(ed, text)
			return true
		}
	case .MOUSE_WHEEL:
		editor_handle_mouse_wheel(ed, ev.wheel)
		return true
	case .MOUSE_BUTTON_DOWN:
		editor_handle_mouse_down(ed, ev.button)
		return true
	}
	return false
}

@(private)
editor_handle_key_down :: proc(ed: ^Editor, key: sdl.KeyboardEvent) -> bool {
	chord := sdl_event_to_chord(key)
	action, bound := km.keymap_resolve(&ed.keymap, chord)
	if !bound {
		return false
	}

	if action == .Copy || action == .Cut || action == .Paste {
		editor_handle_clipboard_action(ed, action)
		return true
	}
	if action == .TriggerCompletion {
		editor_request_completion(ed)
		return true
	}
	if action == .TriggerSignatureHelp {
		editor_request_signature_help(ed)
		return true
	}

	handled := editor_apply_action(ed, action)
	if handled {
		editor_ensure_cursor_visible(ed)
	}
	return handled
}

@(private)
editor_handle_mouse_wheel :: proc(ed: ^Editor, wheel: sdl.MouseWheelEvent) {
	SCROLL_LINES :: 3
	delta := int(wheel.y)
	ed.scroll_line -= delta * SCROLL_LINES
	editor_clamp_scroll(ed)
}

@(private)
editor_handle_mouse_down :: proc(ed: ^Editor, button: sdl.MouseButtonEvent) {
	if ed.char_w <= 0 || ed.char_h <= 0 {
		return
	}
	line := ed.scroll_line + int(button.y / ed.char_h)
	col := ed.scroll_col + int(button.x / ed.char_w)
	pos := editor_clamp_to_buffer(ed, line, col)
	resize(&ed.buf.cursors, 1)
	ed.buf.cursors[0].pos = pos
	ed.buf.cursors[0].sel.active = false
}
