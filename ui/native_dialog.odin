package ui

import "core:c"
import "core:c/libc"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:sys/posix"

// ============================================================================
// Cross-Platform Native System Dialog Interoperability
// Supports Native File Open, File Save, Folder Pick, and Message Alerts.
// ============================================================================

DialogAlertType :: enum {
	Info,
	Warning,
	Error,
}

// Internal runner for command line dialog backends
@(private="file")
exec_dialog_cmd :: proc(cmd: string) -> (output: string, ok: bool) {
	cCmd := strings.clone_to_cstring(cmd, context.temp_allocator)
	pipe := posix.popen(cCmd, "r")
	if pipe == nil do return "", false
	defer posix.pclose(pipe)

	buf: [1024]u8
	sb: strings.Builder
	strings.builder_init(&sb, context.temp_allocator)

	for libc.fgets(raw_data(buf[:]), size_of(buf), (^libc.FILE)(pipe)) != nil {
		lenStr := libc.strlen(cstring(raw_data(buf[:])))
		if lenStr > 0 {
			strings.write_string(&sb, string(buf[:lenStr]))
		}
	}

	res := strings.trim_space(strings.to_string(sb))
	return res, len(res) > 0
}

// Native File Open Dialog
NativeDialog_OpenFile :: proc(
	title: string = "Open File",
	defaultPath: string = "",
	filterExts: []string = nil,
) -> (path: string, ok: bool) {
	if testHook.enabled do return "", false

	when ODIN_OS == .Darwin {
		sb: strings.Builder
		strings.builder_init(&sb, context.temp_allocator)
		strings.write_string(&sb, "osascript -e 'set f to choose file with prompt \"")
		strings.write_string(&sb, title)
		strings.write_string(&sb, "\"")

		if len(filterExts) > 0 {
			strings.write_string(&sb, " of type {")
			for ext, idx in filterExts {
				cleanExt := strings.trim_prefix(ext, ".")
				strings.write_string(&sb, "\"")
				strings.write_string(&sb, cleanExt)
				strings.write_string(&sb, "\"")
				if idx < len(filterExts) - 1 {
					strings.write_string(&sb, ", ")
				}
			}
			strings.write_string(&sb, "}")
		}

		if defaultPath != "" && os.exists(defaultPath) {
			strings.write_string(&sb, " default location POSIX file \"")
			strings.write_string(&sb, defaultPath)
			strings.write_string(&sb, "\"")
		}

		strings.write_string(&sb, "' -e 'POSIX path of f'")
		return exec_dialog_cmd(strings.to_string(sb))
	} else when ODIN_OS == .Linux {
		cmd := fmt.tprintf("zenity --file-selection --title=\"%s\"", title)
		return exec_dialog_cmd(cmd)
	} else {
		return "", false
	}
}

// Native File Save Dialog
NativeDialog_SaveFile :: proc(
	title: string = "Save File",
	defaultName: string = "untitled.txt",
	defaultPath: string = "",
	filterExts: []string = nil,
) -> (path: string, ok: bool) {
	if testHook.enabled do return "", false

	when ODIN_OS == .Darwin {
		sb: strings.Builder
		strings.builder_init(&sb, context.temp_allocator)
		strings.write_string(&sb, "osascript -e 'set f to choose file name with prompt \"")
		strings.write_string(&sb, title)
		strings.write_string(&sb, "\" default name \"")
		strings.write_string(&sb, defaultName)
		strings.write_string(&sb, "\"")

		if defaultPath != "" && os.exists(defaultPath) {
			strings.write_string(&sb, " default location POSIX file \"")
			strings.write_string(&sb, defaultPath)
			strings.write_string(&sb, "\"")
		}

		strings.write_string(&sb, "' -e 'POSIX path of f'")
		return exec_dialog_cmd(strings.to_string(sb))
	} else when ODIN_OS == .Linux {
		cmd := fmt.tprintf("zenity --file-selection --save --confirm-overwrite --title=\"%s\" --filename=\"%s\"", title, defaultName)
		return exec_dialog_cmd(cmd)
	} else {
		return "", false
	}
}

// Native Folder Pick Dialog
NativeDialog_OpenFolder :: proc(
	title: string = "Select Folder",
	defaultPath: string = "",
) -> (path: string, ok: bool) {
	if testHook.enabled do return "", false

	when ODIN_OS == .Darwin {
		sb: strings.Builder
		strings.builder_init(&sb, context.temp_allocator)
		strings.write_string(&sb, "osascript -e 'set f to choose folder with prompt \"")
		strings.write_string(&sb, title)
		strings.write_string(&sb, "\"")

		if defaultPath != "" && os.exists(defaultPath) {
			strings.write_string(&sb, " default location POSIX file \"")
			strings.write_string(&sb, defaultPath)
			strings.write_string(&sb, "\"")
		}

		strings.write_string(&sb, "' -e 'POSIX path of f'")
		return exec_dialog_cmd(strings.to_string(sb))
	} else when ODIN_OS == .Linux {
		cmd := fmt.tprintf("zenity --file-selection --directory --title=\"%s\"", title)
		return exec_dialog_cmd(cmd)
	} else {
		return "", false
	}
}

// Native Message Box Dialog
NativeDialog_MessageBox :: proc(
	title: string,
	message: string,
	alertType: DialogAlertType = .Info,
) -> bool {
	if testHook.enabled do return true

	when ODIN_OS == .Darwin {
		iconStr := "informational"
		#partial switch alertType {
		case .Warning:
			iconStr = "caution"
		case .Error:
			iconStr = "stop"
		}

		cmd := fmt.tprintf(
			"osascript -e 'display dialog \"%s\" with title \"%s\" with icon %s buttons {\"OK\"} default button \"OK\"'",
			message, title, iconStr,
		)
		_, ok := exec_dialog_cmd(cmd)
		return ok
	} else when ODIN_OS == .Linux {
		iconFlag := "--info"
		#partial switch alertType {
		case .Warning:
			iconFlag = "--warning"
		case .Error:
			iconFlag = "--error"
		}
		cmd := fmt.tprintf("zenity %s --title=\"%s\" --text=\"%s\"", iconFlag, title, message)
		_, ok := exec_dialog_cmd(cmd)
		return ok
	} else {
		return false
	}
}
