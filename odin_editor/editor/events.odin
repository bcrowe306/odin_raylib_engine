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
			editor_ensure_cursor_visible(ed)
			editor_after_text_input(ed, text)
			return true
		}
	case .KEY_UP:
		editor_track_modifier_key(ed, ev.key)
	case .MOUSE_WHEEL:
		return editor_handle_mouse_wheel(ed, ev.wheel)
	case .MOUSE_BUTTON_DOWN:
		return editor_handle_mouse_down(ed, ev.button)
	case .MOUSE_BUTTON_UP:
		return editor_handle_mouse_up(ed, ev.button)
	case .MOUSE_MOTION:
		return editor_handle_mouse_motion(ed, ev.motion)
	case .WINDOW_MOUSE_LEAVE:
		ed.mouse.zone = .Outside
	case .WINDOW_FOCUS_LOST:
		// Key-ups for held modifiers go to whichever window has focus now.
		ed.key_mods = {}
		ed.mouse.drag = .None
	}
	return false
}

@(private)
editor_handle_key_down :: proc(ed: ^Editor, key: sdl.KeyboardEvent) -> bool {
	editor_track_modifier_key(ed, key)
	chord := sdl_event_to_chord(key)
	if editor_handle_popup_key(ed, chord) {
		return true
	}
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

// editor_handle_popup_key gives open popups first claim on navigation
// keys: Up/Down/PageUp/PageDown move the completion selection, Enter/Tab
// accept it, and Escape dismisses the topmost popup.
@(private)
editor_handle_popup_key :: proc(ed: ^Editor, chord: km.Chord) -> bool {
	if chord.mods != {} {
		return false
	}
	if ed.actions.active {
		#partial switch chord.key {
		case .Up:
			editor_code_actions_move(ed, -1)
			return true
		case .Down:
			editor_code_actions_move(ed, 1)
			return true
		case .Enter, .Tab:
			if editor_code_actions_visible(ed) {
				editor_apply_code_action(ed, ed.actions.selected)
			}
			return true
		case .Escape:
			editor_close_code_actions(ed)
			return true
		}
	}
	if editor_completion_visible(ed) {
		#partial switch chord.key {
		case .Up:
			editor_completion_move(ed, -1)
			return true
		case .Down:
			editor_completion_move(ed, 1)
			return true
		case .PageUp:
			editor_completion_move(ed, -COMPLETION_MAX_VISIBLE)
			return true
		case .PageDown:
			editor_completion_move(ed, COMPLETION_MAX_VISIBLE)
			return true
		case .Enter, .Tab:
			return editor_accept_completion(ed)
		case .Escape:
			editor_close_completion(ed)
			return true
		}
	}
	if chord.key == .Escape && (ed.completion.active || ed.signature.active || ed.diag_tip.source != .None) {
		editor_close_completion(ed)
		editor_close_signature_help(ed)
		ed.diag_tip.source = .None
		ed.diag_tip.hover_valid = false
		return true
	}
	return false
}
