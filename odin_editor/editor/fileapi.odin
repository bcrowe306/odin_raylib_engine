// Host-facing file load/save API. Wraps `buffer` file IO and (when an LSP
// client is attached) keeps the language server's view of the document in
// sync via didOpen/didChange/didSave notifications.
package editor

import buf "../buffer"
import lspc "../lsp"

editor_attach_lsp :: proc(ed: ^Editor, command: []string, working_dir := "") -> bool {
	ed.lsp = lspc.client_init()
	if !lspc.client_start(&ed.lsp, command, working_dir) {
		lspc.client_destroy(&ed.lsp)
		return false
	}
	ed.lsp_enabled = true
	root_uri := lspc.file_uri(working_dir, context.temp_allocator)
	lspc.client_initialize(&ed.lsp, root_uri)
	return true
}

editor_detach_lsp :: proc(ed: ^Editor) {
	if !ed.lsp_enabled {
		return
	}
	lspc.client_destroy(&ed.lsp)
	ed.lsp_enabled = false
}

// editor_load_file loads `path` into the buffer and (re)associates the LSP
// document URI, sending `didOpen` if an LSP client is attached.
editor_load_file :: proc(ed: ^Editor, path: string) -> bool {
	if !buf.buffer_load_file(&ed.buf, path) {
		return false
	}
	if len(ed.document_uri) > 0 {
		delete(ed.document_uri)
	}
	ed.document_uri = lspc.file_uri(path)
	ed.lsp_version = 1
	if ed.lsp_enabled {
		text := buf.buffer_to_string(&ed.buf, context.temp_allocator)
		lspc.client_did_open(&ed.lsp, ed.document_uri, "odin", text, ed.lsp_version)
	}
	return true
}

editor_save_file :: proc(ed: ^Editor, path: string) -> bool {
	ok := buf.buffer_save_file(&ed.buf, path)
	if ok && ed.lsp_enabled && len(ed.document_uri) > 0 {
		lspc.client_did_save(&ed.lsp, ed.document_uri)
	}
	return ok
}

editor_save_file_as :: proc(ed: ^Editor, path: string) -> bool {
	return editor_save_file(ed, path)
}

editor_save :: proc(ed: ^Editor) -> bool {
	ok := buf.buffer_save(&ed.buf)
	if ok && ed.lsp_enabled && len(ed.document_uri) > 0 {
		lspc.client_did_save(&ed.lsp, ed.document_uri)
	}
	return ok
}

// editor_set_text loads `text` directly into the buffer (for hosts that
// don't go through disk files, e.g. embedded script buffers), resetting
// undo history.
editor_set_text :: proc(ed: ^Editor, text: string) {
	buf.buffer_set_text(&ed.buf, text)
}

// editor_to_string returns the current buffer contents as a string owned
// by the caller.
editor_to_string :: proc(ed: ^Editor, allocator := context.allocator) -> string {
	return buf.buffer_to_string(&ed.buf, allocator)
}

// editor_notify_lsp_changed should be called by the host after any edit
// that should be reflected to the language server (full-document sync).
editor_notify_lsp_changed :: proc(ed: ^Editor) {
	if !ed.lsp_enabled || len(ed.document_uri) == 0 {
		return
	}
	ed.lsp_version += 1
	text := buf.buffer_to_string(&ed.buf, context.temp_allocator)
	lspc.client_did_change(&ed.lsp, ed.document_uri, text, ed.lsp_version)
}
