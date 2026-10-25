package engine

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

// (One test for the global crash state: tests run on several threads.)
@(test)
test_crash_notes_and_reports :: proc(t: ^testing.T) {
	saved := crash
	defer crash = saved
	crash_notes_keep_the_last_lines(t)
	crash_report_written_and_pending(t)
}

@(private = "file")
crash_notes_keep_the_last_lines :: proc(t: ^testing.T) {
	crash.noteNext = 0
	for i in 0 ..< CRASH_NOTES + 5 do Crash_Note(strings.repeat("x", i % 3 + 1, context.temp_allocator))
	Crash_Note("multi\nline")
	notes := Crash_Notes()
	testing.expect_value(t, len(notes), CRASH_NOTES)
	testing.expect_value(t, notes[len(notes) - 1], "multi line") // (one line each)
	long := strings.repeat("y", CRASH_NOTE_LEN + 50, context.temp_allocator)
	Crash_Note(long)
	notes = Crash_Notes()
	testing.expect_value(t, len(notes[len(notes) - 1]), CRASH_NOTE_LEN)
}

@(test)
test_crash_issue_url :: proc(t: ^testing.T) {
	url := Crash_IssueURL("me/repo", "Crash: SIGSEGV (bad)", "line 1\nline & 2", "crash")
	testing.expect(t, strings.has_prefix(url, "https://github.com/me/repo/issues/new?title=Crash%3A%20SIGSEGV%20%28bad%29"), url)
	testing.expect(t, strings.contains(url, "&labels=crash&body=line%201%0Aline%20%26%202"), url)
	// A long body is cut to fit a URL, never inside a %XX.
	big := strings.repeat("é", 5000, context.temp_allocator)
	url = Crash_IssueURL("me/repo", "t", big)
	testing.expect(t, len(url) < 7000, "cut")
	testing.expect(t, strings.contains(url, "cut%3A%20the%20full%20report"), "says it was cut")
	body := url[strings.index(url, "&body=") + 6:]
	for i := 0; i < len(body); i += 1 {
		if body[i] == '%' {
			testing.expect(t, i + 2 < len(body), "a whole escape")
			i += 2
		}
	}
}

@(private = "file")
crash_report_written_and_pending :: proc(t: ^testing.T) {
	tmp := os.get_env("TMPDIR", context.temp_allocator)
	dir, _ := filepath.join({tmp if tmp != "" else "/tmp", "ore_crash_unit"}, context.temp_allocator)
	os.remove_all(dir)
	defer os.remove_all(dir)
	crash.written = false
	crash.noteNext = 0
	Crash_Install("Unit Game", dir)
	Crash_Note("did a thing")
	crash_write_report("test reason")
	testing.expect(t, crash.written, "written once")
	reports := Crash_Pending(dir)
	testing.expect_value(t, len(reports), 1)
	if len(reports) == 1 {
		r := reports[0].text
		testing.expect(t, strings.has_prefix(r, "Unit Game crash report\nversion:  "), r)
		testing.expect(t, strings.contains(r, "reason:   test reason"), r)
		testing.expect(t, strings.contains(r, "\nstack:\n"), r)
		testing.expect(t, strings.contains(r, "\nrecent:\n  did a thing\n"), r)
		testing.expect(t, Crash_MarkSeen(reports[0].path), "marked seen")
		testing.expect_value(t, len(Crash_Pending(dir)), 0)
	}
	// A second report in the same process: none (one crash per process).
	crash_write_report("again")
	testing.expect_value(t, len(Crash_Pending(dir)), 0)
}

@(test)
test_crash_own_frames :: proc(t: ^testing.T) {
	testing.expect(t, crash_own_frame("engine::[crash_report.odin]::crash_write_report"))
	testing.expect(t, crash_own_frame("_sigtramp"))
	testing.expect(t, !crash_own_frame("engine::Crash_TestCrash"))
	testing.expect(t, !crash_own_frame("engine::Scene_Update"))
}
