// Per-frame update: drains injected/synthetic events, polls the LSP client
// (if attached) for responses/diagnostics, keeps the server's copy of the
// document in sync, and refreshes the completion/signature-help popups.
package editor

import buf "../buffer"
import lspc "../lsp"

editor_update :: proc(ed: ^Editor) {
	editor_pump_injected_events(ed)
	editor_update_mouse(ed)
	editor_update_diagnostics(ed)
	if ed.lsp_enabled {
		lspc.client_poll(&ed.lsp)
		editor_supervise_lsp(ed)
		editor_sync_lsp(ed)
		editor_update_lsp_ui(ed)
	}
}

// editor_lsp_ready reports whether requests about the current document can
// be sent: a server is attached and initialized and there's a document URI
// (requests call editor_sync_lsp first, which sends the deferred didOpen).
editor_lsp_ready :: proc(ed: ^Editor) -> bool {
	return ed.lsp_enabled && len(ed.document_uri) > 0 && ed.lsp.initialized
}

// editor_sync_lsp sends the deferred didOpen once the server is
// initialized, then a full-document didChange whenever the buffer has
// changed since the last sync. Called every update and before every
// request, so the server always sees the text the request refers to.
editor_sync_lsp :: proc(ed: ^Editor) {
	if !ed.lsp_enabled || len(ed.document_uri) == 0 || !ed.lsp.initialized {
		return
	}
	if !ed.lsp_doc_open {
		text := buf.buffer_to_string(&ed.buf, context.temp_allocator)
		lspc.client_did_open(&ed.lsp, ed.document_uri, "odin", text, ed.lsp_version)
		ed.lsp_doc_open = true
		ed.lsp_synced_version = ed.buf.version
		return
	}
	if ed.buf.version != ed.lsp_synced_version {
		editor_notify_lsp_changed(ed)
	}
}
