// Client spawns and drives the Odin Language Server (OLS) subprocess over
// stdio. `client_poll` is non-blocking (uses os.pipe_has_data) so it can be
// called once per editor frame/update without stalling the host's render
// loop. `client_feed_bytes` contains all the message-dispatch logic and is
// exposed separately so it can be unit tested with synthetic byte streams,
// without ever spawning a real `ols` process.
package lsp

import "core:mem"
import "core:os"

RequestKind :: enum {
	Initialize,
	Completion,
	SignatureHelp,
	Hover,
	Other,
}

Client :: struct {
	process:    os.Process,
	has_process: bool,
	stdin:      ^os.File,
	stdout:     ^os.File,
	allocator:  mem.Allocator,

	next_id:      int,
	recv_buf:     [dynamic]u8,
	pending_kind: map[int]RequestKind,

	diagnostics:     map[string][dynamic]Diagnostic,
	last_completion: [dynamic]CompletionItem,
	last_signatures: [dynamic]SignatureInformation,
	initialized:     bool,
}

client_init :: proc(allocator := context.allocator) -> Client {
	return Client{
		allocator        = allocator,
		recv_buf         = make([dynamic]u8, allocator),
		pending_kind     = make(map[int]RequestKind, allocator),
		diagnostics      = make(map[string][dynamic]Diagnostic, allocator),
		last_completion  = make([dynamic]CompletionItem, allocator),
		last_signatures  = make([dynamic]SignatureInformation, allocator),
	}
}

client_destroy :: proc(c: ^Client) {
	if c.has_process {
		client_stop(c)
	}
	delete(c.recv_buf)
	delete(c.pending_kind)
	for uri, &list in c.diagnostics {
		for d in list {
			delete(d.message, c.allocator)
		}
		delete(list)
		delete(uri, c.allocator)
	}
	delete(c.diagnostics)
	for item in c.last_completion {
		delete(item.label, c.allocator)
		delete(item.detail, c.allocator)
	}
	delete(c.last_completion)
	for sig in c.last_signatures {
		delete(sig.label, c.allocator)
		for p in sig.parameters {
			delete(p.label, c.allocator)
		}
		delete(sig.parameters)
	}
	delete(c.last_signatures)
}

// client_start launches `command` (e.g. `{"ols"}`) as a child process and
// wires up its stdin/stdout as pipes. Returns false if the process could
// not be spawned (e.g. `ols` is not installed/built yet).
client_start :: proc(c: ^Client, command: []string, working_dir := "") -> bool {
	in_r, in_w, err1 := os.pipe()
	if err1 != nil {
		return false
	}
	out_r, out_w, err2 := os.pipe()
	if err2 != nil {
		os.close(in_r)
		os.close(in_w)
		return false
	}

	desc := os.Process_Desc{
		command     = command,
		working_dir = working_dir,
		stdin       = in_r,
		stdout      = out_w,
	}
	process, perr := os.process_start(desc)
	// The child end of each pipe is only needed by the child; close our
	// copies once the process has (or hasn't) started.
	os.close(in_r)
	os.close(out_w)
	if perr != nil {
		os.close(in_w)
		os.close(out_r)
		return false
	}

	c.process = process
	c.has_process = true
	c.stdin = in_w
	c.stdout = out_r
	return true
}

client_stop :: proc(c: ^Client) {
	if !c.has_process {
		return
	}
	if c.stdin != nil {
		os.close(c.stdin)
		c.stdin = nil
	}
	_ = os.process_kill(c.process)
	_, _ = os.process_wait(c.process)
	if c.stdout != nil {
		os.close(c.stdout)
		c.stdout = nil
	}
	c.has_process = false
}

client_next_id :: proc(c: ^Client) -> int {
	c.next_id += 1
	return c.next_id
}

client_send_raw :: proc(c: ^Client, framed: string) -> bool {
	if !c.has_process || c.stdin == nil {
		return false
	}
	_, err := os.write(c.stdin, transmute([]u8)framed)
	return err == nil
}

// client_poll drains any currently-available bytes from the subprocess's
// stdout (non-blocking) and dispatches any complete messages found. Safe to
// call every frame even if the process has no output ready.
client_poll :: proc(c: ^Client) {
	if !c.has_process || c.stdout == nil {
		return
	}
	for {
		has_data, err := os.pipe_has_data(c.stdout)
		if err != nil || !has_data {
			return
		}
		chunk: [4096]u8
		n, rerr := os.read(c.stdout, chunk[:])
		if n <= 0 {
			return
		}
		client_feed_bytes(c, chunk[:n])
		if rerr != nil {
			return
		}
	}
}
