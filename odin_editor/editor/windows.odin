// Editor windows: besides the text view, the editor can show full-area
// tool windows (keymap editor, theme editor, utilities), switched from the
// command palette. Escape (or the palette's "Editor" entry) returns to the
// text view.
package editor

Editor_Window :: enum {
	Text,
}

// window_label is the palette name of a window ("" = not listed).
window_label :: proc(w: Editor_Window) -> string {
	switch w {
	case .Text: return ""
	}
	return ""
}

window_detail :: proc(w: Editor_Window) -> string {
	return "window"
}

editor_show_window :: proc(ed: ^Editor, w: Editor_Window) {
	ed.window = w
}
