// Message dispatch: turns raw accumulated bytes into complete JSON-RPC
// bodies and routes them (diagnostics notifications vs. request
// responses). Exposed as its own entry point (`client_feed_bytes`) so unit
// tests can exercise the full parsing/dispatch pipeline with synthetic
// byte streams instead of a real `ols` subprocess.
package lsp

import "core:encoding/json"
import "core:strings"

// client_feed_bytes appends `data` to the client's receive buffer and
// extracts+dispatches every complete message currently available.
client_feed_bytes :: proc(c: ^Client, data: []u8) {
	append(&c.recv_buf, ..data)
	for {
		body, consumed, ok := try_extract_message(c.recv_buf[:])
		if !ok {
			return
		}
		body_copy := make([]u8, len(body), context.temp_allocator)
		copy(body_copy, body)
		remove_range(&c.recv_buf, 0, consumed)
		client_handle_message_body(c, body_copy)
	}
}

@(private)
remove_range :: proc(buf: ^[dynamic]u8, lo, hi: int) {
	n := hi - lo
	if n <= 0 {
		return
	}
	copy(buf[lo:], buf[hi:])
	resize(buf, len(buf) - n)
}

client_handle_message_body :: proc(c: ^Client, body: []u8) {
	value, err := decode_message(body, context.temp_allocator)
	if err != nil {
		return
	}
	defer json.destroy_value(value, context.temp_allocator)

	if method_val, has_method := json_object_get(value, "method"); has_method {
		method, _ := json_as_string(method_val)
		params, _ := json_object_get(value, "params")
		client_handle_server_message(c, method, params)
		return
	}

	id_val, has_id := json_object_get(value, "id")
	if !has_id {
		return
	}
	id, _ := json_as_int(id_val)
	kind, found := c.pending_kind[id]
	if !found {
		return
	}
	delete_key(&c.pending_kind, id)

	if kind == .Initialize {
		c.initialized = true
		return
	}

	result, has_result := json_object_get(value, "result")
	if !has_result {
		return
	}

	switch kind {
	case .Completion:
		client_store_completion(c, result)
	case .SignatureHelp:
		client_store_signature_help(c, result)
	case .Initialize, .Hover, .Other:
		// No persistent storage needed for these yet.
	}
}

@(private)
client_handle_server_message :: proc(c: ^Client, method: string, params: json.Value) {
	if method == "textDocument/publishDiagnostics" {
		client_store_diagnostics(c, params)
	}
}

@(private)
client_store_diagnostics :: proc(c: ^Client, params: json.Value) {
	uri_val, has_uri := json_object_get(params, "uri")
	if !has_uri {
		return
	}
	uri, _ := json_as_string(uri_val)
	diags_val, has_diags := json_object_get(params, "diagnostics")
	if !has_diags {
		return
	}
	arr, is_arr := diags_val.(json.Array)
	if !is_arr {
		return
	}

	list := make([dynamic]Diagnostic, c.allocator)
	for item in arr {
		d: Diagnostic
		if msg_val, ok := json_object_get(item, "message"); ok {
			msg, _ := json_as_string(msg_val)
			d.message = strings.clone(msg, c.allocator)
		}
		if sev_val, ok := json_object_get(item, "severity"); ok {
			sev, _ := json_as_int(sev_val)
			d.severity = sev
		}
		if range_val, ok := json_object_get(item, "range"); ok {
			if start_val, ok2 := json_object_get(range_val, "start"); ok2 {
				d.range.start = parse_position(start_val)
			}
			if end_val, ok2 := json_object_get(range_val, "end"); ok2 {
				d.range.end = parse_position(end_val)
			}
		}
		append(&list, d)
	}

	if old, existed := c.diagnostics[uri]; existed {
		for d in old {
			delete(d.message, c.allocator)
		}
		delete(old)
	}
	c.diagnostics[strings.clone(uri, c.allocator)] = list
}

@(private)
parse_position :: proc(v: json.Value) -> Position {
	p: Position
	if line_val, ok := json_object_get(v, "line"); ok {
		p.line, _ = json_as_int(line_val)
	}
	if char_val, ok := json_object_get(v, "character"); ok {
		p.character, _ = json_as_int(char_val)
	}
	return p
}

@(private)
client_store_completion :: proc(c: ^Client, result: json.Value) {
	for item in c.last_completion {
		delete(item.label, c.allocator)
		delete(item.detail, c.allocator)
	}
	clear(&c.last_completion)

	items: json.Array
	#partial switch v in result {
	case json.Array:
		items = v
	case json.Object:
		// CompletionList shape: { isIncomplete, items: [...] }
		if list_val, ok := json_object_get(result, "items"); ok {
			items, _ = list_val.(json.Array)
		}
	}

	for item in items {
		ci: CompletionItem
		if label_val, ok := json_object_get(item, "label"); ok {
			label, _ := json_as_string(label_val)
			ci.label = strings.clone(label, c.allocator)
		}
		if kind_val, ok := json_object_get(item, "kind"); ok {
			ci.kind, _ = json_as_int(kind_val)
		}
		if detail_val, ok := json_object_get(item, "detail"); ok {
			detail, _ := json_as_string(detail_val)
			ci.detail = strings.clone(detail, c.allocator)
		}
		append(&c.last_completion, ci)
	}
}

@(private)
client_store_signature_help :: proc(c: ^Client, result: json.Value) {
	for sig in c.last_signatures {
		delete(sig.label, c.allocator)
		for p in sig.parameters {
			delete(p.label, c.allocator)
		}
		delete(sig.parameters)
	}
	clear(&c.last_signatures)

	sigs_val, has_sigs := json_object_get(result, "signatures")
	if !has_sigs {
		return
	}
	sigs, is_arr := sigs_val.(json.Array)
	if !is_arr {
		return
	}

	for sig_v in sigs {
		si: SignatureInformation
		if label_val, ok := json_object_get(sig_v, "label"); ok {
			label, _ := json_as_string(label_val)
			si.label = strings.clone(label, c.allocator)
		}
		if params_val, ok := json_object_get(sig_v, "parameters"); ok {
			if params_arr, is_parr := params_val.(json.Array); is_parr {
				params_list := make([]ParameterInformation, len(params_arr), c.allocator)
				for p_v, i in params_arr {
					if plabel_val, ok2 := json_object_get(p_v, "label"); ok2 {
						plabel, _ := json_as_string(plabel_val)
						params_list[i] = ParameterInformation{label = strings.clone(plabel, c.allocator)}
					}
				}
				si.parameters = params_list
			}
		}
		append(&c.last_signatures, si)
	}
}

// client_diagnostics_for returns the last-known diagnostics for a file URI
// (empty slice if none/unknown).
client_diagnostics_for :: proc(c: ^Client, uri: string) -> []Diagnostic {
	list, ok := c.diagnostics[uri]
	if !ok {
		return nil
	}
	return list[:]
}
