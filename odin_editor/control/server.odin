// The control server: a non-blocking localhost TCP listener the host polls
// once per frame. Each connected client sends newline-terminated commands
// (see protocol.odin) and receives exactly one newline-terminated reply per
// command: `ok ...`, `err <reason>`, `timeout <condition>`, or (for
// `state`) one line of JSON.
//
// Host integration (see example/main.odin):
//
//     srv: control.Server
//     control.server_start(&srv, port, window, platform)
//     for running {
//         control.server_poll(&srv, &editor)          // before SDL_PollEvent
//         for sdl.PollEvent(&ev) { ... }              // injected events arrive here
//         editor_update(&editor)
//         editor_render(...)
//         control.server_after_render(&srv, &editor, renderer)  // before present
//         sdl.RenderPresent(renderer)
//     }
//
// Commands for one client run strictly in order. Any command that pushes
// SDL events holds back that client's next command until the following
// frame, so the events have been polled and handled before e.g. `state`
// or `wait` looks at the result.
package control

import ed "../editor"
import km "../keymap"
import "core:c/libc"
import "core:fmt"
import "core:net"
import "core:strings"
import "core:time"
import "core:unicode/utf8"
import sdl "vendor:sdl3"

@(private)
Conn :: struct {
	sock:        net.TCP_Socket,
	recv:        [dynamic]u8,
	queue:       [dynamic]string,
	peer_closed: bool,
	// Don't run the next queued command before this frame.
	resume_frame: int,
	// Command currently blocked on a wait/screenshot, if any.
	blocked:      bool,
	wait:         Cmd_Wait,
	wait_start:   time.Tick,
	wait_frame:   int,
	screenshot:   string,
}

Server :: struct {
	listener:  net.TCP_Socket,
	running:   bool,
	port:      int,
	window:    ^sdl.Window,
	platform:  km.Platform,
	conns:     [dynamic]^Conn,
	frame:     int,
	// TEXT_INPUT payloads pushed to SDL: SDL doesn't copy them, so they
	// must outlive the frame in which the host polls them.
	texts:     [dynamic]cstring,
	old_texts: [dynamic]cstring,
}

// server_start begins listening on 127.0.0.1:`port` (loopback only — the
// hook is never reachable from other machines). Returns false if the port
// can't be bound.
server_start :: proc(srv: ^Server, port: int, window: ^sdl.Window, platform: km.Platform) -> bool {
	// Writing a reply to a client that already hung up must not kill the
	// host with SIGPIPE.
	libc.signal(13 /* SIGPIPE */, auto_cast libc.SIG_IGN)

	ep := net.Endpoint{address = net.IP4_Loopback, port = port}
	sock, err := net.listen_tcp(ep)
	if err != nil {
		fmt.eprintfln("control: cannot listen on 127.0.0.1:%d: %v", port, err)
		return false
	}
	net.set_blocking(sock, false)
	srv.listener = sock
	srv.running = true
	srv.port = port
	srv.window = window
	srv.platform = platform
	srv.conns = make([dynamic]^Conn)
	srv.texts = make([dynamic]cstring)
	srv.old_texts = make([dynamic]cstring)
	return true
}

server_stop :: proc(srv: ^Server) {
	if !srv.running {
		return
	}
	for c in srv.conns {
		conn_destroy(c)
	}
	delete(srv.conns)
	net.close(srv.listener)
	free_texts(&srv.old_texts)
	free_texts(&srv.texts)
	delete(srv.texts)
	delete(srv.old_texts)
	srv.running = false
}

@(private)
free_texts :: proc(list: ^[dynamic]cstring) {
	for t in list {
		delete(t)
	}
	clear(list)
}

@(private)
conn_destroy :: proc(c: ^Conn) {
	net.close(c.sock)
	delete(c.recv)
	for line in c.queue {
		delete(line)
	}
	delete(c.queue)
	delete(c.screenshot)
	free(c)
}

// server_poll accepts connections, reads commands and runs every command
// that is ready. Call once per frame, before the host's SDL_PollEvent loop.
server_poll :: proc(srv: ^Server, e: ^ed.Editor) {
	if !srv.running {
		return
	}
	srv.frame += 1

	// Payloads pushed two polls ago have certainly been consumed.
	free_texts(&srv.old_texts)
	srv.old_texts, srv.texts = srv.texts, srv.old_texts

	for {
		client, _, err := net.accept_tcp(srv.listener)
		if err != nil {
			break
		}
		net.set_blocking(client, false)
		c := new(Conn)
		c.sock = client
		c.recv = make([dynamic]u8)
		c.queue = make([dynamic]string)
		append(&srv.conns, c)
	}

	for i := 0; i < len(srv.conns); {
		c := srv.conns[i]
		conn_read(c)
		conn_run(srv, c, e)
		if c.peer_closed && len(c.queue) == 0 && !c.blocked {
			conn_destroy(c)
			ordered_remove(&srv.conns, i)
			continue
		}
		i += 1
	}
}

@(private)
conn_read :: proc(c: ^Conn) {
	if c.peer_closed {
		return
	}
	for {
		chunk: [4096]u8
		n, err := net.recv_tcp(c.sock, chunk[:])
		if err != nil {
			if err != .Would_Block {
				c.peer_closed = true
			}
			break
		}
		if n == 0 {
			c.peer_closed = true
			break
		}
		append(&c.recv, ..chunk[:n])
	}
	// Split complete lines into the command queue.
	for {
		nl := -1
		for b, j in c.recv {
			if b == '\n' {
				nl = j
				break
			}
		}
		if nl < 0 {
			break
		}
		line := strings.clone(string(c.recv[:nl]))
		remove_range(&c.recv, 0, nl + 1)
		trimmed := strings.trim_space(line)
		if len(trimmed) == 0 || trimmed[0] == '#' {
			delete(line)
			continue
		}
		append(&c.queue, line)
	}
	// A final unterminated line counts once the peer is done sending.
	if c.peer_closed && len(c.recv) > 0 {
		append(&c.queue, strings.clone(string(c.recv[:])))
		clear(&c.recv)
	}
}

@(private)
remove_range :: proc(b: ^[dynamic]u8, lo, hi: int) {
	copy(b[lo:], b[hi:])
	resize(b, len(b) - (hi - lo))
}

@(private)
reply :: proc(c: ^Conn, msg: string) {
	out := strings.concatenate({msg, "\n"}, context.temp_allocator)
	data := transmute([]u8)out
	// Replies are small; retry briefly if the socket buffer is full.
	for tries := 0; len(data) > 0 && tries < 1000; tries += 1 {
		n, err := net.send_tcp(c.sock, data)
		if err != nil && err != .Would_Block {
			return
		}
		data = data[n:]
	}
}

@(private)
conn_run :: proc(srv: ^Server, c: ^Conn, e: ^ed.Editor) {
	for {
		if c.blocked {
			if c.screenshot != "" {
				return // finished in server_after_render
			}
			if !wait_check(srv, c, e) {
				return
			}
		}
		if len(c.queue) == 0 || srv.frame < c.resume_frame {
			return
		}
		line := c.queue[0]
		ordered_remove(&c.queue, 0)
		run_command(srv, c, e, line)
		delete(line)
	}
}

@(private)
run_command :: proc(srv: ^Server, c: ^Conn, e: ^ed.Editor, line: string) {
	cmd, perr := parse_command(line, srv.platform)
	defer command_destroy(cmd)
	if cmd == nil {
		reply(c, strings.concatenate({"err ", perr}, context.temp_allocator))
		return
	}

	switch v in cmd {
	case Cmd_Key:
		for _ in 0 ..< v.count {
			push_key(srv, v.key, v.mod)
		}
		c.resume_frame = srv.frame + 1
		reply(c, "ok")
	case Cmd_Text:
		push_text(srv, v.text)
		c.resume_frame = srv.frame + 1
		reply(c, "ok")
	case Cmd_Type:
		for ch in v.text {
			bytes, n := utf8.encode_rune(ch)
			push_text(srv, string(bytes[:n]))
		}
		c.resume_frame = srv.frame + 1
		reply(c, "ok")
	case Cmd_Click:
		push_click(srv, v.x, v.y)
		c.resume_frame = srv.frame + 1
		reply(c, "ok")
	case Cmd_Wheel:
		push_wheel(srv, v.dy)
		c.resume_frame = srv.frame + 1
		reply(c, "ok")
	case Cmd_State:
		reply(c, state_json(e, srv.frame))
	case Cmd_Wait:
		c.blocked = true
		c.wait = v
		c.wait_start = time.tick_now()
		c.wait_frame = srv.frame
	case Cmd_Screenshot:
		c.blocked = true
		c.screenshot = strings.clone(v.path)
	case Cmd_Open:
		if ed.editor_load_file(e, v.path) {
			reply(c, "ok")
		} else {
			reply(c, strings.concatenate({"err cannot open ", v.path}, context.temp_allocator))
		}
	case Cmd_Cursor:
		resize(&e.buf.cursors, 1)
		cur := ed.editor_primary_cursor(e)
		cur.pos = ed.editor_clamp_to_buffer(e, v.line, v.col)
		cur.sel.active = false
		ed.editor_ensure_cursor_visible(e)
		reply(c, fmt.tprintf("ok %d %d", cur.pos.line, cur.pos.col))
	case Cmd_Quit:
		ev: sdl.Event
		ev.type = .QUIT
		_ = sdl.PushEvent(&ev)
		reply(c, "ok")
	case Cmd_Help:
		reply(c, strings.concatenate({"ok ", HELP_TEXT}, context.temp_allocator))
	case Cmd_Expect:
		reply(c, check_expect(e, v))
	}
}

// check_expect evaluates an `expect` assertion against the live editor.
check_expect :: proc(e: ^ed.Editor, x: Cmd_Expect) -> string {
	s := snapshot_state(e, 0)
	actual: string
	pass: bool
	switch x.field {
	case .Line:
		actual = s.current_line
		pass = actual == x.want
	case .Cursor:
		actual = fmt.tprintf("%d %d", s.cursor[0], s.cursor[1])
		pass = actual == strings.trim_space(x.want)
	case .Text_Contains:
		actual = s.text
		pass = strings.contains(actual, x.want)
	case .Completion_Selected:
		actual = s.completion.selected_label
		pass = s.completion.visible && actual == x.want
	case .Completion_Has:
		// Search every listed item, not just the snapshot's first few.
		actual = fmt.tprintf("%d items starting %v", s.completion.count, s.completion.items)
		for idx in e.completion.filtered {
			pass ||= s.completion.visible && e.lsp.last_completion[idx].label == x.want
		}
	case .Signature:
		actual = s.signature.label
		pass = s.signature.visible && strings.contains(actual, x.want)
	case .Signature_Param:
		actual = s.signature.active_param
		pass = s.signature.visible && actual == x.want
	}
	if pass {
		return "ok"
	}
	return fmt.tprintf("fail expected %q got %q", x.want, actual)
}

// wait_check evaluates a blocked `wait`; replies and unblocks once the
// condition holds or the timeout expires. Conditions are only checked
// from the frame after the wait was issued, so events pushed by earlier
// commands have been handled first.
@(private)
wait_check :: proc(srv: ^Server, c: ^Conn, e: ^ed.Editor) -> bool {
	w := c.wait
	frames := srv.frame - c.wait_frame
	if w.cond == .Frames {
		if frames < w.amount {
			return false
		}
		c.blocked = false
		reply(c, fmt.tprintf("ok %d frames", frames))
		return true
	}

	met := false
	if frames >= 1 {
		switch w.cond {
		case .Completion: met = ed.editor_completion_visible(e)
		case .No_Completion: met = !ed.editor_completion_visible(e)
		case .Signature: met = ed.editor_signature_visible(e)
		case .No_Signature: met = !ed.editor_signature_visible(e)
		case .Lsp_Ready: met = e.lsp_enabled && e.lsp.initialized && e.lsp_doc_open
		case .Lsp_Idle: met = e.lsp_enabled && len(e.lsp.pending_kind) == 0
		case .Frames:
		}
	}
	elapsed := time.duration_milliseconds(time.tick_since(c.wait_start))
	name := wait_name(w.cond)
	if met {
		c.blocked = false
		reply(c, fmt.tprintf("ok %s after %.0fms", name, elapsed))
		return true
	}
	if elapsed >= f64(w.amount) {
		c.blocked = false
		reply(c, fmt.tprintf("timeout %s after %.0fms", name, elapsed))
		return true
	}
	return false
}

@(private)
wait_name :: proc(cond: Wait_Condition) -> string {
	switch cond {
	case .Completion: return "completion"
	case .No_Completion: return "no-completion"
	case .Signature: return "signature"
	case .No_Signature: return "no-signature"
	case .Lsp_Ready: return "lsp-ready"
	case .Lsp_Idle: return "lsp-idle"
	case .Frames: return "frames"
	}
	return "?"
}

// server_after_render services pending `screenshot` commands. Call after
// editor_render and before SDL_RenderPresent (the back buffer is only
// guaranteed to hold the frame until it's presented).
server_after_render :: proc(srv: ^Server, e: ^ed.Editor, renderer: ^sdl.Renderer) {
	if !srv.running {
		return
	}
	for c in srv.conns {
		if !c.blocked || c.screenshot == "" {
			continue
		}
		path := c.screenshot
		c.screenshot = ""
		c.blocked = false
		defer delete(path)

		surface := sdl.RenderReadPixels(renderer, nil)
		if surface == nil {
			reply(c, fmt.tprintf("err RenderReadPixels: %s", sdl.GetError()))
			continue
		}
		defer sdl.DestroySurface(surface)
		cpath := strings.clone_to_cstring(path, context.temp_allocator)
		if !sdl.SavePNG(surface, cpath) {
			reply(c, fmt.tprintf("err SavePNG: %s", sdl.GetError()))
			continue
		}
		reply(c, fmt.tprintf("ok %s %dx%d", path, surface.w, surface.h))
	}
}

// --- SDL event construction -------------------------------------------------

// Device id stamped on injected keyboard/mouse events so hosts can tell
// them apart from real input (see event_is_injected).
INJECTED_DEVICE_ID :: 0x0EDC7

// event_is_user_input reports whether `ev` is keyboard/text/mouse input.
event_is_user_input :: proc(ev: sdl.Event) -> bool {
	#partial switch ev.type {
	case .KEY_DOWN, .KEY_UP, .TEXT_INPUT, .TEXT_EDITING,
	     .MOUSE_BUTTON_DOWN, .MOUSE_BUTTON_UP, .MOUSE_WHEEL, .MOUSE_MOTION:
		return true
	}
	return false
}

// event_is_injected reports whether an input event was pushed by this
// server rather than coming from a real device. Hosts running scripted
// tests can drop real input (`--control-only` in the demo) so a person
// typing elsewhere can't leak keystrokes into the run.
event_is_injected :: proc(srv: ^Server, ev: sdl.Event) -> bool {
	#partial switch ev.type {
	case .KEY_DOWN, .KEY_UP:
		return ev.key.which == INJECTED_DEVICE_ID
	case .MOUSE_BUTTON_DOWN, .MOUSE_BUTTON_UP:
		return ev.button.which == INJECTED_DEVICE_ID
	case .MOUSE_WHEEL:
		return ev.wheel.which == INJECTED_DEVICE_ID
	case .TEXT_INPUT:
		// Text events carry no device id; match the payload pointer
		// against the strings this server pushed.
		for t in srv.texts {
			if t == ev.text.text {
				return true
			}
		}
		for t in srv.old_texts {
			if t == ev.text.text {
				return true
			}
		}
	}
	return false
}

@(private)
window_id :: proc(srv: ^Server) -> sdl.WindowID {
	return sdl.GetWindowID(srv.window) if srv.window != nil else 0
}

// push_key pushes a KEY_DOWN followed by a KEY_UP, as a real key press
// produces.
push_key :: proc(srv: ^Server, key: sdl.Keycode, mod: sdl.Keymod) {
	ev: sdl.Event
	ev.type = .KEY_DOWN
	ev.key.windowID = window_id(srv)
	ev.key.which = INJECTED_DEVICE_ID
	ev.key.key = key
	ev.key.mod = mod
	ev.key.scancode = sdl.GetScancodeFromKey(key, nil)
	ev.key.down = true
	ev.key.timestamp = sdl.GetTicksNS()
	_ = sdl.PushEvent(&ev)

	ev.type = .KEY_UP
	ev.key.down = false
	_ = sdl.PushEvent(&ev)
}

push_text :: proc(srv: ^Server, text: string) {
	ctext := strings.clone_to_cstring(text)
	append(&srv.texts, ctext)
	ev: sdl.Event
	ev.type = .TEXT_INPUT
	ev.text.windowID = window_id(srv)
	ev.text.text = ctext
	ev.text.timestamp = sdl.GetTicksNS()
	_ = sdl.PushEvent(&ev)
}

push_click :: proc(srv: ^Server, x, y: f32) {
	ev: sdl.Event
	ev.type = .MOUSE_BUTTON_DOWN
	ev.button.windowID = window_id(srv)
	ev.button.which = INJECTED_DEVICE_ID
	ev.button.button = 1 // SDL_BUTTON_LEFT
	ev.button.down = true
	ev.button.clicks = 1
	ev.button.x = x
	ev.button.y = y
	ev.button.timestamp = sdl.GetTicksNS()
	_ = sdl.PushEvent(&ev)

	ev.type = .MOUSE_BUTTON_UP
	ev.button.down = false
	_ = sdl.PushEvent(&ev)
}

push_wheel :: proc(srv: ^Server, dy: f32) {
	ev: sdl.Event
	ev.type = .MOUSE_WHEEL
	ev.wheel.windowID = window_id(srv)
	ev.wheel.which = INJECTED_DEVICE_ID
	ev.wheel.y = dy
	ev.wheel.integer_y = i32(dy)
	ev.wheel.timestamp = sdl.GetTicksNS()
	_ = sdl.PushEvent(&ev)
}
