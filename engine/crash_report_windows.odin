#+build windows
package engine

import "core:c/libc"
import win "core:sys/windows"

// Crash reports on Windows (crash_report.odin): an unhandled-exception
// filter; frames as <exe>+offset (resolve with the matching .pdb).

@(private = "file")
widePath: win.wstring

foreign import kernel32_crash "system:Kernel32.lib"

@(default_calling_convention = "system")
foreign kernel32_crash {
	SetThreadStackGuarantee :: proc(StackSizeInBytes: ^win.ULONG) -> win.BOOL ---
}

@(private)
crash_install_platform :: proc() {
	// (Room for the filter when the stack overflowed.)
	guarantee: win.ULONG = 64 * 1024
	_ = SetThreadStackGuarantee(&guarantee)
	win.SetUnhandledExceptionFilter(crash_filter)
}

@(private = "file")
crash_filter :: proc "system" (info: ^win.EXCEPTION_POINTERS) -> win.LONG {
	name := "exception"
	code: win.DWORD = info.ExceptionRecord.ExceptionCode if info != nil && info.ExceptionRecord != nil else 0
	switch code {
	case win.EXCEPTION_ACCESS_VIOLATION, win.EXCEPTION_IN_PAGE_ERROR: name = "EXCEPTION_ACCESS_VIOLATION (invalid memory access)"
	case win.EXCEPTION_STACK_OVERFLOW: name = "EXCEPTION_STACK_OVERFLOW (stack overflow: deep recursion?)"
	case win.EXCEPTION_ILLEGAL_INSTRUCTION, win.EXCEPTION_PRIV_INSTRUCTION: name = "EXCEPTION_ILLEGAL_INSTRUCTION (an Odin runtime check - bounds, type assertion - or a trap)"
	case win.EXCEPTION_BREAKPOINT: name = "EXCEPTION_BREAKPOINT (a trap: an Odin runtime check or a panic)"
	case win.EXCEPTION_INT_DIVIDE_BY_ZERO, win.EXCEPTION_FLT_DIVIDE_BY_ZERO: name = "EXCEPTION_DIVIDE_BY_ZERO"
	case win.EXCEPTION_ARRAY_BOUNDS_EXCEEDED: name = "EXCEPTION_ARRAY_BOUNDS_EXCEEDED"
	}
	crash_write_report(name)
	return win.EXCEPTION_CONTINUE_SEARCH // (then Windows ends the process as usual)
}

@(private)
crash_set_path_platform :: proc() {
	widePath = win.utf8_to_wstring(string(crash.path[:crash.pathLen]), Engine_HeapAllocator())
}

@(private)
crash_open_platform :: proc "contextless" () -> Crash_File {
	if crash.pathLen == 0 || widePath == nil do return CRASH_STDERR
	h := win.CreateFileW(widePath, win.GENERIC_WRITE, 0, nil, win.CREATE_ALWAYS, win.FILE_ATTRIBUTE_NORMAL, nil)
	return CRASH_STDERR if h == win.INVALID_HANDLE_VALUE else Crash_File(uintptr(h))
}

@(private)
crash_write_platform :: proc "contextless" (f: Crash_File, s: string) {
	if len(s) == 0 do return
	h := win.GetStdHandle(win.STD_ERROR_HANDLE) if f == CRASH_STDERR else win.HANDLE(uintptr(f))
	written: win.DWORD
	_ = win.WriteFile(h, raw_data(s), win.DWORD(len(s)), &written, nil)
}

@(private)
crash_close_platform :: proc "contextless" (f: Crash_File) {
	if f != CRASH_STDERR do win.CloseHandle(win.HANDLE(uintptr(f)))
}

@(private)
crash_stack_platform :: proc "contextless" (f: Crash_File) {
	frames: [64]rawptr
	n := win.RtlCaptureStackBackTrace(3, len(frames), raw_data(frames[:]), nil) // (not this, crash_write_report, crash_filter)
	base := uintptr(rawptr(win.GetModuleHandleW(nil)))
	buf: [24]u8
	for i in 0 ..< int(n) {
		a := uintptr(frames[i])
		crash_write_platform(f, "  ")
		if a >= base && a - base < 0x8000_0000 {
			crash_write_platform(f, "exe+")
			crash_write_platform(f, crash_hex(buf[:], a - base))
		} else {
			crash_write_platform(f, crash_hex(buf[:], a))
		}
		crash_write_platform(f, "\n")
	}
}

@(private)
crash_unix_time_platform :: proc "contextless" () -> i64 {
	ft: win.FILETIME
	win.GetSystemTimeAsFileTime(&ft)
	t := i64(ft.dwHighDateTime) << 32 | i64(ft.dwLowDateTime)
	return t / 10_000_000 - 11_644_473_600
}

@(private)
crash_pid_platform :: proc() -> int {
	return int(win.GetCurrentProcessId())
}

@(private)
crash_abort_platform :: proc() {
	libc.abort()
}
