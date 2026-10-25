package editor

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:thread"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Check for updates (TODO D.9): at startup (Settings > General, on by
// default) and from Help > Check for Updates, the latest GitHub Release is
// read (curl, on a thread) and compared with this editor's version
// (ORE_RELEASE). A newer one shows in the status bar (click: its page) and
// the console. Dev builds (0.1.0-dev.<n>, one per merge to main: release.yml)
// look at every release, so a newer dev build is offered too; releases only
// at releases. Not in local builds (0.0.0-dev) or test drives (ORE_UPDATE_URL
// points it elsewhere: tests).
// ============================================================================

UPDATE_RELEASES_URL :: "https://api.github.com/repos/bcrowe306/odin_raylib_engine/releases/latest"
// (Pre-releases too, newest first: what a dev build compares with.)
UPDATE_ALL_RELEASES_URL :: "https://api.github.com/repos/bcrowe306/odin_raylib_engine/releases?per_page=30"

@(private = "file")
Update_Job :: struct {
	url:    string,
	output: string,
	ok:     bool,
	done:   bool,
	thread: ^thread.Thread,
}

@(private = "file")
update: struct {
	job:      ^Update_Job,
	manual:   bool,   // asked from the Help menu: say "up to date" too
	version:  string, // a newer release ("" = none)
	page:     string, // its page
}

// UpdateCheck_Start reads the latest release in the background (manual:
// from the menu - also in development builds, and reports "up to date").
UpdateCheck_Start :: proc(manual := false) {
	if update.job != nil do return
	url := os.get_env("ORE_UPDATE_URL", context.temp_allocator)
	if url == "" {
		if !manual && (e.Version_IsDev(e.ORE_RELEASE) || GlobalDrive.enabled || !GlobalSettings.checkUpdates) do return
		url = UPDATE_ALL_RELEASES_URL if e.Version_IsPrerelease(e.ORE_RELEASE) else UPDATE_RELEASES_URL
	}
	update.manual = manual
	job := new(Update_Job)
	job.url = strings.clone(url)
	job.thread = thread.create_and_start_with_poly_data(job, proc(job: ^Update_Job) {
		cmd := []string{"curl", "-fsSL", "-m", "15", "-H", "Accept: application/vnd.github+json", job.url}
		st, out, errOut, err := os.process_exec({command = cmd}, context.allocator)
		delete(errOut)
		if err == nil && st.exit_code == 0 {
			job.output = string(out)
			job.ok = true
		} else {
			delete(out)
		}
		sync.atomic_store(&job.done, true)
	})
	update.job = job
}

// UpdateCheck_Poll takes a finished check (every frame).
UpdateCheck_Poll :: proc(state: ^EditorState) {
	job := update.job
	if job == nil || !sync.atomic_load(&job.done) do return
	update.job = nil
	defer {
		thread.join(job.thread)
		thread.destroy(job.thread)
		delete(job.url)
		delete(job.output)
		free(job)
	}
	tag, page, ok := update_parse(job.output)
	if !job.ok || !ok {
		if update.manual do Editor_Log(state, .Warn, "Could not check for updates (offline?)")
		return
	}
	if e.Version_Compare(tag, e.ORE_RELEASE) > 0 {
		delete(update.version)
		delete(update.page)
		update.version = strings.clone(strings.trim_prefix(tag, "v"))
		update.page = strings.clone(page)
		Editor_Log(state, .Info, "Ore Editor %s is available (this is %s): %s", update.version, e.ORE_RELEASE, page)
	} else if update.manual {
		Editor_Log(state, .Info, "Ore Editor %s is up to date", e.ORE_RELEASE)
	}
}

// UpdateCheck_Available: a newer release's version ("" = none) and page.
UpdateCheck_Available :: proc() -> (version, page: string) {
	return update.version, update.page
}

// update_parse reads a GitHub release (its tag and page) or a list of them
// (the newest version; drafts skipped).
@(private = "file")
update_parse :: proc(text: string) -> (tag, page: string, ok: bool) {
	v, err := json.parse_string(text, allocator = context.temp_allocator)
	if err != nil do return
	#partial switch r in v {
	case json.Object:
		tag = r["tag_name"].(json.String) or_return
		page = r["html_url"].(json.String) or_else ""
	case json.Array:
		for item in r {
			o := item.(json.Object) or_continue
			if o["draft"].(json.Boolean) or_else false do continue
			t := o["tag_name"].(json.String) or_continue
			if tag == "" || e.Version_Compare(t, tag) > 0 {
				tag = t
				page = o["html_url"].(json.String) or_else ""
			}
		}
	}
	return tag, page, tag != ""
}

// UpdateCheck_StatusBar draws the "update available" link (status bar).
UpdateCheck_StatusBar :: proc(state: ^EditorState) {
	if update.version == "" do return
	imgui.SameLine()
	imgui.PushStyleColorImVec4(.Text, UI_ACCENT)
	if imgui.SmallButton(fmt.ctprintf("%s  Update %s available", ICON_FA_ARROW_DOWN, update.version)) && update.page != "" {
		Editor_OpenExternally(state, update.page)
	}
	imgui.PopStyleColor()
	Drive_Item("status.update")
	UI_Tooltip("A newer Ore Editor is out: click for its download page")
}
