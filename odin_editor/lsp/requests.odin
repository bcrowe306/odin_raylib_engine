// High-level LSP requests/notifications built on top of the jsonrpc +
// protocol layers. Each proc sends the framed message to the subprocess
// stdin and (for requests) records the pending request id so the response
// can be routed back to the right storage slot when it arrives.
package lsp

file_uri :: proc(path: string, allocator := context.allocator) -> string {
	sb_len := len("file://") + len(path)
	buf := make([]u8, sb_len, allocator)
	copy(buf, "file://")
	copy(buf[len("file://"):], path)
	return string(buf)
}

client_initialize :: proc(c: ^Client, root_uri: string) -> int {
	id := client_next_id(c)
	params := InitializeParams{
		processId    = nil,
		rootUri      = root_uri,
		capabilities = ClientCapabilities{},
	}
	msg := encode_request(id, "initialize", params, context.temp_allocator)
	c.pending_kind[id] = .Initialize
	client_send_raw(c, msg)
	return id
}

client_notify_initialized :: proc(c: ^Client) {
	msg := encode_notification("initialized", struct{}{}, context.temp_allocator)
	client_send_raw(c, msg)
}

client_did_open :: proc(c: ^Client, uri: string, language_id: string, text: string, version := 1) {
	params := DidOpenTextDocumentParams{
		textDocument = TextDocumentItem{
			uri        = uri,
			languageId = language_id,
			version    = version,
			text       = text,
		},
	}
	msg := encode_notification("textDocument/didOpen", params, context.temp_allocator)
	client_send_raw(c, msg)
}

// client_did_change sends a full-document-sync update (simplest correct
// strategy; incremental sync can be added later without changing the
// public API).
client_did_change :: proc(c: ^Client, uri: string, full_text: string, version: int) {
	params := DidChangeTextDocumentParams{
		textDocument = VersionedTextDocumentIdentifier{uri = uri, version = version},
		contentChanges = []TextDocumentContentChangeEvent{{text = full_text}},
	}
	msg := encode_notification("textDocument/didChange", params, context.temp_allocator)
	client_send_raw(c, msg)
}

client_did_close :: proc(c: ^Client, uri: string) {
	params := DidCloseTextDocumentParams{textDocument = TextDocumentIdentifier{uri = uri}}
	msg := encode_notification("textDocument/didClose", params, context.temp_allocator)
	client_send_raw(c, msg)
}

client_did_save :: proc(c: ^Client, uri: string) {
	params := DidSaveTextDocumentParams{textDocument = TextDocumentIdentifier{uri = uri}}
	msg := encode_notification("textDocument/didSave", params, context.temp_allocator)
	client_send_raw(c, msg)
}

client_request_completion :: proc(c: ^Client, uri: string, line, character: int) -> int {
	id := client_next_id(c)
	params := CompletionParams{
		textDocument = TextDocumentIdentifier{uri = uri},
		position     = Position{line = line, character = character},
	}
	msg := encode_request(id, "textDocument/completion", params, context.temp_allocator)
	c.pending_kind[id] = .Completion
	c.latest_completion_id = id
	client_send_raw(c, msg)
	return id
}

client_request_signature_help :: proc(c: ^Client, uri: string, line, character: int) -> int {
	id := client_next_id(c)
	params := SignatureHelpParams{
		textDocument = TextDocumentIdentifier{uri = uri},
		position     = Position{line = line, character = character},
	}
	msg := encode_request(id, "textDocument/signatureHelp", params, context.temp_allocator)
	c.pending_kind[id] = .SignatureHelp
	c.latest_signature_id = id
	client_send_raw(c, msg)
	return id
}
