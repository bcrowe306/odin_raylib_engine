package editor

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import e "../engine"

// #265: the window's saved state fits the monitors connected now, and goes
// through settings.ini and back.
@(test)
test_window_state_clamp_and_settings :: proc(t: ^testing.T) {
	mons := []Monitor_Rect{{0, 0, 1920, 1080}, {1920, 0, 2560, 1440}}
	// On the second monitor: kept as is.
	r := WindowState_Clamp({saved = true, x = 2000, y = 100, w = 1600, h = 900, monitor = 1}, mons)
	testing.expect(t, r.x == 2000 && r.y == 100 && r.w == 1600 && r.h == 900 && r.monitor == 1, "kept")
	// Its monitor unplugged (only the first left): moved onto the first.
	r = WindowState_Clamp({saved = true, x = 2000, y = 100, w = 1600, h = 900, monitor = 1}, mons[:1])
	testing.expectf(t, r.monitor == 0 && r.x + r.w <= 1920 && r.x >= 0, "onto the first monitor: %v", r)
	// Bigger than the monitor: shrunk to it; tiny: the minimum size.
	r = WindowState_Clamp({saved = true, x = 0, y = 0, w = 5000, h = 3000}, mons[:1])
	testing.expect(t, r.w == 1920 && r.h == 1080, "shrunk to the monitor")
	r = WindowState_Clamp({saved = true, x = 10, y = 10, w = 10, h = 10}, mons[:1])
	testing.expect(t, r.w == WINDOW_MIN_SIZE.x && r.h == WINDOW_MIN_SIZE.y, "minimum size")
	// Off every monitor (negative): pulled back on.
	r = WindowState_Clamp({saved = true, x = -3000, y = -500, w = 800, h = 600}, mons)
	testing.expectf(t, r.x >= 0 && r.y >= 0, "back on screen: %v", r)

	// settings.ini [window], written and read back.
	dir, _ := filepath.join({e.Engine_TempDir(), "rayzr_window_state_test"}, context.temp_allocator)
	_ = os.make_directory_all(dir)
	defer os.remove_all(dir)
	oldPath := settingsPath
	defer settingsPath = oldPath
	path, _ := filepath.join({dir, "settings.ini"}, context.temp_allocator)
	settingsPath = path
	Editor_Settings_Destroy(&GlobalSettings)
	GlobalSettings = Editor_DefaultSettings()
	defer Editor_Settings_Destroy(&GlobalSettings)
	testing.expect(t, Editor_SaveSettings(), "saved")
	text, _ := os.read_entire_file(path, context.temp_allocator)
	testing.expect(t, !strings.contains(string(text), "[window]"), "no [window] until there's a state")
	GlobalSettings.window = {saved = true, x = 120, y = 80, w = 1440, h = 860, maximized = true, monitor = 1}
	testing.expect(t, Editor_SaveSettings(), "saved")
	text, _ = os.read_entire_file(path, context.temp_allocator)
	Editor_Settings_Destroy(&GlobalSettings)
	GlobalSettings = Editor_DefaultSettings()
	settings_from_ini(string(text))
	w := GlobalSettings.window
	testing.expectf(t, w.saved && w.x == 120 && w.y == 80 && w.w == 1440 && w.h == 860 && w.maximized && w.monitor == 1, "read back: %v", w)
	// A settings.ini with only some sections (hand-edited, older) reads fine
	// (a missing section used to crash the editor at startup).
	Editor_Settings_Destroy(&GlobalSettings)
	GlobalSettings = Editor_DefaultSettings()
	settings_from_ini("[general]\nshow_welcome = false\n\n[window]\nx = 220\ny = 140\nwidth = 1100\nheight = 720\n")
	testing.expect(t, GlobalSettings.window.w == 1100 && !GlobalSettings.showWelcome, "partial file read")
	free_all(context.temp_allocator)
}
