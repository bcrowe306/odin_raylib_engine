package lsp

import "core:fmt"
import "core:mem"
import "core:strings"
import "core:testing"

run_leak_free :: proc(t: ^testing.T, body: proc(t: ^testing.T)) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)

	old := context.allocator
	context.allocator = mem.tracking_allocator(&track)
	body(t)
	context.allocator = old

	for _, entry in track.allocation_map {
		testing.expectf(t, false, "Memory leak: %v bytes at %v", entry.size, entry.location)
	}
	for bf in track.bad_free_array {
		testing.expectf(t, false, "Bad free: %p at %v", bf.memory, bf.location)
	}
}

@(test)
test_frame_message_adds_content_length_header :: proc(t: ^testing.T) {
	run_leak_free(t, proc(t: ^testing.T) {
		framed := frame_message(`{"a":1}`, context.allocator)
		defer delete(framed)
		testing.expect(t, strings.has_prefix(framed, "Content-Length: 7\r\n\r\n"), "expected header with correct length")
		testing.expect(t, strings.has_suffix(framed, `{"a":1}`), "expected body to follow header")
	})
}

@(test)
test_try_extract_message_waits_for_full_body :: proc(t: ^testing.T) {
	run_leak_free(t, proc(t: ^testing.T) {
		partial := transmute([]u8)string("Content-Length: 10\r\n\r\n{\"a\":1}")
		_, _, ok := try_extract_message(partial)
		testing.expect(t, !ok, "expected no message until full body is present")

		full := transmute([]u8)string(`Content-Length: 7` + "\r\n\r\n" + `{"a":1}`)
		body, consumed, ok2 := try_extract_message(full)
		testing.expect(t, ok2, "expected message to be extracted")
		testing.expect_value(t, string(body), `{"a":1}`)
		testing.expect_value(t, consumed, len(full))
	})
}

@(test)
test_try_extract_message_handles_trailing_data :: proc(t: ^testing.T) {
	run_leak_free(t, proc(t: ^testing.T) {
		msg1 := `Content-Length: 7` + "\r\n\r\n" + `{"a":1}`
		msg2 := `Content-Length: 7` + "\r\n\r\n" + `{"b":2}`
		combined := transmute([]u8)strings.concatenate({msg1, msg2}, context.temp_allocator)

		body, consumed, ok := try_extract_message(combined)
		testing.expect(t, ok, "expected first message to extract")
		testing.expect_value(t, string(body), `{"a":1}`)

		remaining := combined[consumed:]
		body2, _, ok2 := try_extract_message(remaining)
		testing.expect(t, ok2, "expected second message to extract")
		testing.expect_value(t, string(body2), `{"b":2}`)
	})
}

@(test)
test_encode_request_shape :: proc(t: ^testing.T) {
	run_leak_free(t, proc(t: ^testing.T) {
		Params :: struct {
			foo: string `json:"foo"`,
		}
		framed := encode_request(1, "textDocument/completion", Params{foo = "bar"}, context.allocator)
		defer delete(framed)
		testing.expect(t, strings.contains(framed, `"id":1`), "expected id field")
		testing.expect(t, strings.contains(framed, `"method":"textDocument/completion"`), "expected method field")
		testing.expect(t, strings.contains(framed, `"foo":"bar"`), "expected params to be marshaled")
	})
}

@(test)
test_feed_bytes_dispatches_diagnostics :: proc(t: ^testing.T) {
	run_leak_free(t, proc(t: ^testing.T) {
		c := client_init()
		defer client_destroy(&c)

		body := `{"jsonrpc":"2.0","method":"textDocument/publishDiagnostics","params":{"uri":"file:///x.odin","diagnostics":[{"range":{"start":{"line":1,"character":2},"end":{"line":1,"character":5}},"severity":1,"message":"undeclared identifier"}]}}`
		framed := frame_message(body, context.temp_allocator)
		client_feed_bytes(&c, transmute([]u8)framed)

		diags := client_diagnostics_for(&c, "file:///x.odin")
		testing.expect_value(t, len(diags), 1)
		testing.expect_value(t, diags[0].message, "undeclared identifier")
		testing.expect_value(t, diags[0].severity, 1)
		testing.expect_value(t, diags[0].range.start, Position{line = 1, character = 2})
	})
}

@(test)
test_feed_bytes_dispatches_completion_response :: proc(t: ^testing.T) {
	run_leak_free(t, proc(t: ^testing.T) {
		c := client_init()
		defer client_destroy(&c)

		id := client_next_id(&c)
		c.pending_kind[id] = .Completion

		body := fmt.tprintf(
			`{{"jsonrpc":"2.0","id":%d,"result":[{{"label":"foo","kind":3,"detail":"proc()"}},{{"label":"bar","kind":6,"detail":""}}]}}`,
			id,
		)
		framed := frame_message(body, context.temp_allocator)
		client_feed_bytes(&c, transmute([]u8)framed)

		testing.expect_value(t, len(c.last_completion), 2)
		testing.expect_value(t, c.last_completion[0].label, "foo")
		testing.expect_value(t, c.last_completion[0].kind, 3)
		testing.expect_value(t, c.last_completion[1].label, "bar")
		_, still_pending := c.pending_kind[id]
		testing.expect(t, !still_pending, "expected pending request to be cleared")
	})
}

@(test)
test_feed_bytes_dispatches_signature_help_response :: proc(t: ^testing.T) {
	run_leak_free(t, proc(t: ^testing.T) {
		c := client_init()
		defer client_destroy(&c)

		id := client_next_id(&c)
		c.pending_kind[id] = .SignatureHelp

		body := fmt.tprintf(
			`{{"jsonrpc":"2.0","id":%d,"result":{{"signatures":[{{"label":"foo(a: int) -> int","parameters":[{{"label":"a: int"}}]}}]}}}}`,
			id,
		)
		framed := frame_message(body, context.temp_allocator)
		client_feed_bytes(&c, transmute([]u8)framed)

		testing.expect_value(t, len(c.last_signatures), 1)
		testing.expect_value(t, c.last_signatures[0].label, "foo(a: int) -> int")
		testing.expect_value(t, len(c.last_signatures[0].parameters), 1)
		testing.expect_value(t, c.last_signatures[0].parameters[0].label, "a: int")
	})
}

@(test)
test_feed_bytes_handles_split_across_two_calls :: proc(t: ^testing.T) {
	run_leak_free(t, proc(t: ^testing.T) {
		c := client_init()
		defer client_destroy(&c)

		id := client_next_id(&c)
		c.pending_kind[id] = .Completion
		body := fmt.tprintf(`{{"jsonrpc":"2.0","id":%d,"result":[{{"label":"x","kind":1,"detail":""}}]}}`, id)
		framed := frame_message(body, context.temp_allocator)

		split := len(framed) / 2
		client_feed_bytes(&c, transmute([]u8)framed[:split])
		testing.expect_value(t, len(c.last_completion), 0)
		client_feed_bytes(&c, transmute([]u8)framed[split:])
		testing.expect_value(t, len(c.last_completion), 1)
		testing.expect_value(t, c.last_completion[0].label, "x")
	})
}

@(test)
test_initialize_marks_client_initialized :: proc(t: ^testing.T) {
	run_leak_free(t, proc(t: ^testing.T) {
		c := client_init()
		defer client_destroy(&c)

		id := client_next_id(&c)
		c.pending_kind[id] = .Initialize
		body := fmt.tprintf(`{{"jsonrpc":"2.0","id":%d,"result":{{"capabilities":{{}}}}}}`, id)
		framed := frame_message(body, context.temp_allocator)
		client_feed_bytes(&c, transmute([]u8)framed)

		testing.expect(t, c.initialized, "expected client to be marked initialized")
	})
}

@(test)
test_file_uri_formats_path :: proc(t: ^testing.T) {
	run_leak_free(t, proc(t: ^testing.T) {
		uri := file_uri("/tmp/foo.odin", context.allocator)
		defer delete(uri)
		testing.expect_value(t, uri, "file:///tmp/foo.odin")
	})
}
