// Per-frame update: drains injected/synthetic events and polls the LSP
// client (if attached) for responses/diagnostics.
package editor

import lspc "../lsp"

editor_update :: proc(ed: ^Editor) {
	editor_pump_injected_events(ed)
	if ed.lsp_enabled {
		lspc.client_poll(&ed.lsp)
	}
}

// editor_request_completion asks the attached LSP for completions at the
// primary cursor's position. No-op if no LSP client is attached.
editor_request_completion :: proc(ed: ^Editor) {
	if !ed.lsp_enabled || len(ed.document_uri) == 0 {
		return
	}
	c := editor_primary_cursor(ed)
	lspc.client_request_completion(&ed.lsp, ed.document_uri, c.pos.line, c.pos.col)
}

editor_request_signature_help :: proc(ed: ^Editor) {
	if !ed.lsp_enabled || len(ed.document_uri) == 0 {
		return
	}
	c := editor_primary_cursor(ed)
	lspc.client_request_signature_help(&ed.lsp, ed.document_uri, c.pos.line, c.pos.col)
}
