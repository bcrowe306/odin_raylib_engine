package editor

import "core:fmt"
import os "core:os"
import "core:path/filepath"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Crash and bug reports (TODO E.1; engine/crash_report.odin writes them).
//
// A crash writes crash-<time>-<pid>.txt to the crash folder:
//   ~/.config/rayzr_editor/crashes  (--user-data <dir>: <dir>/crashes - drives;
//   RAYZR_CRASH_DIR overrides both)
// The next start offers it: Report on GitHub (a new issue with the report
// filled in - nothing is sent until the user submits it), Open Folder,
// Dismiss. Help > Report a Bug... does the same with the console's tail.
// ============================================================================

EDITOR_REPO :: "bcrowe306/rayzr"

@(private = "file")
crashUI: struct {
	reports:  []e.Crash_Report, // pending, oldest first (heap)
	asked:    bool,
	lastURL:  string,           // the last issue page opened (drives: not opened)
}

// CrashReports_Install: at startup, before the window.
CrashReports_Install :: proc() {
	dir := os.get_env("RAYZR_CRASH_DIR", context.temp_allocator)
	if dir == "" {
		for i := 0; i + 1 < len(os.args); i += 1 do if os.args[i] == "--user-data" {
			dir, _ = filepath.join({os.args[i + 1], "crashes"}, context.temp_allocator)
		}
	}
	if dir == "" {
		if home, err := os.user_home_dir(context.temp_allocator); err == nil {
			dir, _ = filepath.join({home, ".config", "rayzr_editor", "crashes"}, context.temp_allocator)
		}
	}
	// (Reports from earlier runs: read before this run's name is taken.)
	pending := e.Crash_Pending(dir, context.allocator)
	crashUI.reports = pending
	e.Crash_Install("Rayzr Editor", dir)
}

// CrashReports_Shutdown frees what Install read.
CrashReports_Shutdown :: proc() {
	crash_reports_free()
	delete(crashUI.lastURL)
	crashUI.lastURL = ""
}

@(private = "file")
crash_reports_free :: proc() {
	for r in crashUI.reports {
		delete(r.path)
		delete(r.text)
	}
	delete(crashUI.reports)
	crashUI.reports = nil
}

// CrashReports_Rescan reads the crash folder again (drives: crash-rescan).
CrashReports_Rescan :: proc() {
	crash_reports_free()
	all := e.Crash_Pending(e.Crash_Dir(), context.allocator)
	// (Not this run's own file - it has none until it crashes.)
	crashUI.reports = all
	crashUI.asked = false
}

// CrashReports_TestCrash: --crash-test panic | segv | abort (tests).
CrashReports_TestCrash :: proc() {
	for i := 0; i + 1 < len(os.args); i += 1 do if os.args[i] == "--crash-test" do e.Crash_TestCrash(os.args[i + 1])
}

// CrashReports_Prompt: "Rayzr Editor closed unexpectedly" (the first frames
// after a start that found reports).
CrashReports_Prompt :: proc(state: ^EditorState) {
	if len(crashUI.reports) == 0 do return
	if !crashUI.asked {
		crashUI.asked = true
		imgui.OpenPopup("Rayzr Editor Crashed###CrashReport")
	}
	center := imgui.GetMainViewport().WorkPos + imgui.GetMainViewport().WorkSize * 0.5
	imgui.SetNextWindowPos(center, .Appearing, {0.5, 0.5})
	imgui.SetNextWindowSize({640, 0}, .Appearing)
	if !imgui.BeginPopupModal("Rayzr Editor Crashed###CrashReport", nil, {}) do return
	last := crashUI.reports[len(crashUI.reports) - 1]
	imgui.TextWrapped("%s", fmt.ctprintf("Rayzr Editor closed unexpectedly%s. A report was saved:", "" if len(crashUI.reports) == 1 else fmt.tprintf(" (%d times)", len(crashUI.reports))))
	UI_DimText(last.path)
	imgui.InputTextMultiline("##crash.text", strings.clone_to_cstring(last.text, context.temp_allocator), uint(len(last.text) + 1), {-1, 260}, {.ReadOnly})
	Drive_Item("crash.text")
	UI_DimText("Reporting opens a new GitHub issue with this report filled in: nothing is sent until you submit it there.")
	if UI_PrimaryButton("Report on GitHub", "crash.report") {
		crash_open_issue(state, fmt.tprintf("Crash: %s", crash_reason(last.text)), crash_issue_body(last.text))
		crash_dismiss_all()
		imgui.CloseCurrentPopup()
	}
	UI_Tooltip("Open a prefilled issue in your browser (you can edit it before submitting)")
	imgui.SameLine()
	if UI_Button("Copy Report", "crash.copy") do imgui.SetClipboardText(strings.clone_to_cstring(last.text, context.temp_allocator))
	imgui.SameLine()
	if UI_Button("Open Folder", "crash.folder") do Editor_OpenExternally(state, filepath.dir(last.path, context.temp_allocator))
	imgui.SameLine()
	if UI_Button("Dismiss", "crash.dismiss") {
		crash_dismiss_all()
		imgui.CloseCurrentPopup()
	}
	UI_Tooltip("Don't offer these reports again (they stay in the folder)")
	imgui.EndPopup()
}

// CrashReports_ReportBug: Help > Report a Bug... (a new issue with the
// version, platform and the console's last lines).
CrashReports_ReportBug :: proc(state: ^EditorState) {
	sb := strings.builder_make(context.temp_allocator)
	strings.write_string(&sb, "**What happened?**\n\n\n**Steps to reproduce**\n\n1. \n\n**Expected**\n\n\n")
	fmt.sbprintf(&sb, "**Environment**\n\n- Rayzr Editor %s\n- %s %s\n\n", e.RAYZR_RELEASE, ODIN_OS_STRING, ODIN_ARCH_STRING)
	strings.write_string(&sb, "<details><summary>Console (last lines)</summary>\n\n```\n")
	start := max(0, len(state.logs) - 40)
	for l in state.logs[start:] do fmt.sbprintf(&sb, "%s [%v] %s\n", l.time, l.level, l.message)
	strings.write_string(&sb, "```\n</details>\n")
	crash_open_issue(state, "", strings.to_string(sb), label = "bug")
}

// CrashReports_OpenFolder: Help > Open Crash Reports Folder.
CrashReports_OpenFolder :: proc(state: ^EditorState) {
	dir := e.Crash_Dir()
	if dir == "" do return
	_ = os.make_directory_all(dir)
	Editor_OpenExternally(state, dir)
}

// CrashReports_DriveQuery: crash-dialog (pending reports shown), crash-url.
CrashReports_DriveQuery :: proc(q: string) -> (string, bool) {
	switch q {
	case "crash-pending": return fmt.tprint(len(crashUI.reports)), true
	case "crash-url": return crashUI.lastURL, true
	}
	return "", false
}

@(private = "file")
crash_dismiss_all :: proc() {
	for r in crashUI.reports do _ = e.Crash_MarkSeen(r.path)
	crash_reports_free()
}

@(private = "file")
crash_open_issue :: proc(state: ^EditorState, title, body: string, label := "crash") {
	url := e.Crash_IssueURL(EDITOR_REPO, title, body, label)
	delete(crashUI.lastURL)
	crashUI.lastURL = strings.clone(url)
	if GlobalDrive.enabled {
		Editor_Log(state, .Info, "Would open %d-byte issue page", len(url)) // (drives: no browser)
		return
	}
	Editor_OpenExternally(state, url)
}

// crash_reason: the report's "reason:" line.
@(private = "file")
crash_reason :: proc(text: string) -> string {
	for line in strings.split_lines(text, context.temp_allocator) {
		if strings.has_prefix(line, "reason:") {
			r := strings.trim_space(line[len("reason:"):])
			return r[:min(len(r), 90)]
		}
	}
	return "Rayzr Editor crashed"
}

@(private = "file")
crash_issue_body :: proc(report: string) -> string {
	return fmt.tprintf("**What were you doing when it crashed?**\n\n\n**Crash report**\n\n```\n%s\n```\n", strings.trim_space(report))
}
