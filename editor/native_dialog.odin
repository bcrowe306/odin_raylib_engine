package editor

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sync"
import "core:thread"

// ============================================================================
// Native (system) file dialogs.
//
// The dialog runs in a helper process - osascript on macOS, zenity or
// kdialog on Linux, PowerShell on Windows - on a worker thread, so the
// editor keeps drawing while it is open. NativeDialog_Poll (once per frame)
// hands the chosen paths to the requester's callback on the main thread;
// Cancel delivers nothing. Test drives answer dialogs with the
// `dialog-files` command instead of opening one.
// ============================================================================

NativeDialog_Callback :: proc(state: ^EditorState, paths: []string)

NativeDialog_Options :: struct {
	title:    string,
	filter:   string,   // filter name, e.g. "Assets"
	exts:     []string, // without dots ("png"); empty = any file
	multiple: bool,
	folders:  bool,     // choose folders instead of files
	start:    string,   // folder the dialog opens in ("" = the system's choice)
}

// The folder the last dialog was asked to open in (drives).
nativeDialogLastStart: string

@(private = "file")
Dialog_Job :: struct {
	command: []string,
	output:  string,
	done:    bool, // set by the worker (atomic)
}

@(private = "file")
dlg: struct {
	thread:   ^thread.Thread,
	job:      ^Dialog_Job,
	callback: NativeDialog_Callback,
}

// Answers for the next dialogs in a test drive (FIFO). An empty answer is Cancel.
driveDialogAnswers: [dynamic][]string

NativeDialog_IsOpen :: proc() -> bool {
	return dlg.job != nil
}

// NativeDialog_Open shows a system open dialog; `callback` gets the chosen
// paths a few frames later (not at all on Cancel).
NativeDialog_Open :: proc(state: ^EditorState, opts: NativeDialog_Options, callback: NativeDialog_Callback) -> bool {
	if dlg.job != nil {
		Editor_Log(state, .Warn, "A file dialog is already open")
		return false
	}
	delete(nativeDialogLastStart)
	nativeDialogLastStart = strings.clone(opts.start)
	job := new(Dialog_Job)
	if GlobalDrive.enabled {
		// Scripted answer, delivered by the next poll like a real one.
		if len(driveDialogAnswers) > 0 {
			paths := pop_front(&driveDialogAnswers)
			job.output = strings.join(paths, "\n")
			for p in paths do delete(p)
			delete(paths)
		}
		job.done = true
	} else {
		cmd, ok := dialog_command(opts)
		if !ok {
			free(job)
			Editor_Log(state, .Error, "No system file dialog available (install zenity or kdialog)")
			return false
		}
		job.command = cmd
		dlg.thread = thread.create_and_start_with_poly_data(job, dialog_worker)
	}
	dlg.job = job
	dlg.callback = callback
	return true
}

// NativeDialog_Poll delivers a finished dialog's result; call once per frame.
NativeDialog_Poll :: proc(state: ^EditorState) {
	job := dlg.job
	if job == nil || !sync.atomic_load(&job.done) do return
	if dlg.thread != nil {
		thread.join(dlg.thread)
		thread.destroy(dlg.thread)
		dlg.thread = nil
	}
	paths := make([dynamic]string, context.temp_allocator)
	for line in strings.split_lines(job.output, context.temp_allocator) {
		p := strings.trim_right(line, "\r")
		if len(p) > 1 do p = strings.trim_right(p, "/\\")
		if p != "" do append(&paths, strings.clone(p, context.temp_allocator))
	}
	for c in job.command do delete(c)
	delete(job.command)
	delete(job.output)
	free(job)
	dlg.job = nil
	if len(paths) > 0 do dlg.callback(state, paths[:])
}

@(private = "file")
dialog_worker :: proc(job: ^Dialog_Job) {
	st, out, errOut, err := os.process_exec({command = job.command}, context.allocator)
	delete(errOut)
	// Cancel exits non-zero (osascript: -128, zenity: 1).
	if err == nil && st.exit_code == 0 {
		job.output = string(out)
	} else {
		delete(out)
	}
	sync.atomic_store(&job.done, true)
}

@(private = "file")
on_path :: proc(name: string) -> bool {
	path := os.get_env("PATH", context.temp_allocator)
	for dir in strings.split(path, ":" when ODIN_OS != .Windows else ";", context.temp_allocator) {
		full, _ := filepath.join({dir, name}, context.temp_allocator)
		if os.exists(full) do return true
	}
	return false
}

@(private = "file")
dialog_command :: proc(opts: NativeDialog_Options) -> (cmd: []string, ok: bool) {
	args := make([dynamic]string)
	title := opts.title if opts.title != "" else ("Choose Folder" if opts.folders else "Choose Files")
	when ODIN_OS == .Darwin {
		// No `of type` filter: AppleScript wants UTIs, and project files
		// (.ldtk, .lua) have none; unsupported picks are reported instead.
		q, _ := strings.replace_all(title, "\"", "\\\"", context.temp_allocator)
		what := "choose folder" if opts.folders else "choose file"
		multi := " with multiple selections allowed" if opts.multiple else ""
		location := ""
		if opts.start != "" && os.is_dir(opts.start) {
			sq, _ := strings.replace_all(opts.start, "\"", "\\\"", context.temp_allocator)
			location = fmt.tprintf(" default location (POSIX file \"%s\")", sq)
		}
		script := []string{
			"activate",
			fmt.tprintf("set picked to (%s with prompt \"%s\"%s%s)", what, q, location, multi),
			"if class of picked is not list then set picked to {picked}",
			"set out to \"\"",
			"repeat with f in picked",
			"set out to out & POSIX path of f & linefeed",
			"end repeat",
			"return out",
		}
		append(&args, "osascript")
		for line in script do append(&args, "-e", line)
	} else when ODIN_OS == .Windows {
		q, _ := strings.replace_all(title, "'", "''", context.temp_allocator)
		start, _ := strings.replace_all(opts.start, "'", "''", context.temp_allocator)
		ps: string
		if opts.folders {
			ps = fmt.tprintf("Add-Type -AssemblyName System.Windows.Forms; $d = New-Object System.Windows.Forms.FolderBrowserDialog; $d.Description = '%s'; $d.SelectedPath = '%s'; if ($d.ShowDialog() -eq 'OK') {{ $d.SelectedPath }} else {{ exit 1 }}", q, start)
		} else {
			filter := "All files|*.*"
			if len(opts.exts) > 0 {
				sb := strings.builder_make(context.temp_allocator)
				for e, i in opts.exts do fmt.sbprintf(&sb, "%s*.%s", ";" if i > 0 else "", e)
				filter = fmt.tprintf("%s|%s|All files|*.*", opts.filter if opts.filter != "" else "Supported", strings.to_string(sb))
			}
			ps = fmt.tprintf("Add-Type -AssemblyName System.Windows.Forms; $d = New-Object System.Windows.Forms.OpenFileDialog; $d.Title = '%s'; $d.Filter = '%s'; $d.Multiselect = $%v; $d.InitialDirectory = '%s'; if ($d.ShowDialog() -eq 'OK') {{ $d.FileNames }} else {{ exit 1 }}", q, filter, opts.multiple, start)
		}
		append(&args, "powershell", "-NoProfile", "-STA", "-Command", ps)
	} else {
		patterns := strings.builder_make(context.temp_allocator)
		for e, i in opts.exts do fmt.sbprintf(&patterns, "%s*.%s", " " if i > 0 else "", e)
		if on_path("zenity") {
			append(&args, "zenity", "--file-selection", fmt.tprintf("--title=%s", title), "--separator=\n")
			if opts.multiple do append(&args, "--multiple")
			if opts.folders do append(&args, "--directory")
			if opts.start != "" do append(&args, fmt.tprintf("--filename=%s/", strings.trim_suffix(opts.start, "/")))
			if !opts.folders && len(opts.exts) > 0 {
				append(&args, fmt.tprintf("--file-filter=%s | %s", opts.filter if opts.filter != "" else "Supported", strings.to_string(patterns)), "--file-filter=All files | *")
			}
		} else if on_path("kdialog") {
			append(&args, "kdialog", "--title", title)
			startDir := opts.start if opts.start != "" else "."
			if opts.folders {
				append(&args, "--getexistingdirectory", startDir)
			} else {
				filter := strings.to_string(patterns) if len(opts.exts) > 0 else "*"
				append(&args, "--getopenfilename", startDir, filter)
				if opts.multiple do append(&args, "--multiple", "--separate-output")
			}
		} else {
			delete(args)
			return nil, false
		}
	}
	for &a in args do a = strings.clone(a)
	return args[:], true
}
