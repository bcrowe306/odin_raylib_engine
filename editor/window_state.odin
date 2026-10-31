package editor

import rl "vendor:raylib"

// ============================================================================
// The editor window comes back as it was left (#265): size, position,
// maximized and the monitor it was on, saved in the user settings
// ([window]) on quit and before a project relaunch, restored at startup.
// Drives and --hidden keep their fixed window and touch none of it.
// ============================================================================

Window_State :: struct {
	saved:      bool, // a state was saved (else the default 1600 x 900)
	x, y, w, h: i32,  // the restored (not maximized) bounds, screen coordinates
	maximized:  bool,
	monitor:    i32,
}

@(private = "file")
win: struct {
	active:  bool,       // restoring / saving (not a drive, not hidden)
	normal:  [4]i32,     // the last bounds seen while not maximized
	pending: int,        // frames until the maximize (macOS applies it late)
}

WINDOW_MIN_SIZE :: [2]i32{640, 400}

// WindowState_Restore: call once after the settings are loaded.
WindowState_Restore :: proc(active: bool) {
	win.active = active
	win.normal = {i32(rl.GetWindowPosition().x), i32(rl.GetWindowPosition().y), rl.GetScreenWidth(), rl.GetScreenHeight()}
	if !active do return
	s := GlobalSettings.window
	if !s.saved do return
	r := WindowState_Clamp(s, window_monitors())
	rl.SetWindowSize(r.w, r.h)
	rl.SetWindowPosition(r.x, r.y)
	win.normal = {r.x, r.y, r.w, r.h}
	// (Maximizing in the same frame as InitWindow is lost on macOS.)
	if s.maximized do win.pending = 2
}

// WindowState_Frame: call every frame (keeps the restored bounds).
WindowState_Frame :: proc() {
	if !win.active do return
	if win.pending > 0 {
		win.pending -= 1
		if win.pending == 0 do rl.MaximizeWindow()
		return
	}
	if !rl.IsWindowMaximized() && !rl.IsWindowFullscreen() && !rl.IsWindowMinimized() {
		p := rl.GetWindowPosition()
		win.normal = {i32(p.x), i32(p.y), rl.GetScreenWidth(), rl.GetScreenHeight()}
	}
}

// WindowState_Save: the window's state into the settings (and saved).
// Call on quit and before relaunching on another project.
WindowState_Save :: proc() {
	if !win.active || !rl.IsWindowReady() do return
	s := &GlobalSettings.window
	s.saved = true
	s.x, s.y, s.w, s.h = win.normal[0], win.normal[1], win.normal[2], win.normal[3]
	s.maximized = rl.IsWindowMaximized()
	s.monitor = rl.GetCurrentMonitor()
	_ = Editor_SaveSettings()
}

// Monitor_Rect: a monitor's area in screen coordinates.
Monitor_Rect :: struct {x, y, w, h: i32}

@(private = "file")
window_monitors :: proc() -> []Monitor_Rect {
	n := rl.GetMonitorCount()
	out := make([]Monitor_Rect, max(n, 0), context.temp_allocator)
	for i in 0 ..< n {
		p := rl.GetMonitorPosition(i)
		out[i] = {i32(p.x), i32(p.y), rl.GetMonitorWidth(i), rl.GetMonitorHeight(i)}
	}
	return out
}

// WindowState_Clamp: saved bounds made to fit the monitors connected now -
// on the saved monitor if it's there (else the first), no bigger than it,
// and with its title bar on it (a window saved on an unplugged display
// isn't lost off-screen).
WindowState_Clamp :: proc(s: Window_State, monitors: []Monitor_Rect) -> Window_State {
	r := s
	r.w, r.h = max(r.w, WINDOW_MIN_SIZE.x), max(r.h, WINDOW_MIN_SIZE.y)
	if len(monitors) == 0 do return r
	// The monitor holding the window's top-left area, else the saved one, else the first.
	m := -1
	for mon, i in monitors {
		if r.x + 40 >= mon.x && r.x + 40 < mon.x + mon.w && r.y + 10 >= mon.y && r.y + 10 < mon.y + mon.h {
			m = i
			break
		}
	}
	if m < 0 do m = int(s.monitor) if s.monitor >= 0 && int(s.monitor) < len(monitors) else 0
	mon := monitors[m]
	r.monitor = i32(m)
	r.w, r.h = min(r.w, mon.w), min(r.h, mon.h)
	r.x = clamp(r.x, mon.x, mon.x + mon.w - r.w)
	r.y = clamp(r.y, mon.y, mon.y + mon.h - r.h)
	return r
}
