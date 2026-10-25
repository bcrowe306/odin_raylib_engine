#+build darwin, linux
package engine

import "core:c"
import "core:sys/posix"

// Crash reports on macOS / Linux (crash_report.odin): signal handlers on
// their own stack (a stack overflow still reports), backtrace() frames.

// Frames: the unwinder (the unwind tables - Odin code has no frame
// pointers, so backtrace() stops at the first frame), names from dladdr.
when ODIN_OS == .Darwin {
	foreign import libc_bt "system:System"
	foreign import libunwind_bt "system:System"
} else {
	foreign import libc_bt "system:c"
	foreign import libunwind_bt "system:gcc_s"
}

@(private = "file")
Dl_info :: struct {
	dli_fname: cstring,
	dli_fbase: rawptr,
	dli_sname: cstring,
	dli_saddr: rawptr,
}

@(default_calling_convention = "c")
foreign libc_bt {
	dladdr :: proc(addr: rawptr, info: ^Dl_info) -> c.int ---
}

@(default_calling_convention = "c")
foreign libunwind_bt {
	_Unwind_Backtrace :: proc(cb: proc "c" (ctx: rawptr, arg: rawptr) -> c.int, arg: rawptr) -> c.int ---
	_Unwind_GetIP :: proc(ctx: rawptr) -> uintptr ---
}

@(private = "file")
CRASH_SIGNALS := [?]posix.Signal{.SIGSEGV, .SIGBUS, .SIGILL, .SIGFPE, .SIGABRT, .SIGTRAP}

@(private = "file")
altStack: [64 * 1024]u8

when ODIN_OS == .Darwin {
	foreign import libc_mach "system:System"

	@(default_calling_convention = "c")
	foreign libc_mach {
		mach_task_self_: u32
		task_set_exception_ports :: proc(task: u32, mask: u32, port: u32, behavior: i32, flavor: i32) -> i32 ---
	}
}

@(private)
crash_install_platform :: proc() {
	when ODIN_OS == .Darwin {
		// A Mach exception port inherited from the parent (a launcher, an
		// IDE, a tool's process tree) can take hardware faults before they
		// become signals - the faulting thread then hangs. Faults go to the
		// signal handlers below instead.
		EXC_MASK_BAD_ACCESS :: 1 << 1
		EXC_MASK_BAD_INSTRUCTION :: 1 << 2
		EXC_MASK_ARITHMETIC :: 1 << 3
		EXC_MASK_BREAKPOINT :: 1 << 6
		EXCEPTION_DEFAULT :: 1
		THREAD_STATE_NONE :: 5 when ODIN_ARCH == .arm64 else 13
		_ = task_set_exception_ports(mach_task_self_, EXC_MASK_BAD_ACCESS | EXC_MASK_BAD_INSTRUCTION | EXC_MASK_ARITHMETIC | EXC_MASK_BREAKPOINT, 0, EXCEPTION_DEFAULT, THREAD_STATE_NONE)
	}
	ss := posix.stack_t{ss_sp = raw_data(altStack[:]), ss_size = len(altStack)}
	_ = posix.sigaltstack(&ss, nil)
	act: posix.sigaction_t
	act.sa_handler = crash_signal
	act.sa_flags = {.ONSTACK, .SA_NODEFER} // (a fault inside the handler comes back here: crash_stack_failed)
	posix.sigemptyset(&act.sa_mask)
	for s in CRASH_SIGNALS do posix.sigaction(s, &act, nil)
}

@(private = "file")
crash_signal :: proc "c" (sig: posix.Signal) {
	name := "signal"
	#partial switch sig {
	case .SIGSEGV: name = "SIGSEGV (invalid memory access)"
	case .SIGBUS:  name = "SIGBUS (invalid memory access)"
	case .SIGILL:  name = "SIGILL (illegal instruction: an Odin runtime check - bounds, type assertion - or a trap)"
	case .SIGFPE:  name = "SIGFPE (arithmetic error: division by zero?)"
	case .SIGABRT: name = "SIGABRT (aborted)"
	case .SIGTRAP: name = "SIGTRAP (trap: an Odin runtime check - bounds, type assertion - or a panic)"
	}
	if !crash_stack_failed() do crash_write_report(name)
	// The default action now, unblocked: the OS reports / dumps as usual.
	dfl: posix.sigaction_t
	dfl.sa_handler = auto_cast posix.SIG_DFL
	posix.sigemptyset(&dfl.sa_mask)
	posix.sigaction(sig, &dfl, nil)
	set: posix.sigset_t
	posix.sigemptyset(&set)
	posix.sigaddset(&set, sig)
	posix.pthread_sigmask(.UNBLOCK, &set, nil)
	posix.raise(sig)
	posix._exit(128 + c.int(sig)) // (if it's still running)
}

@(private)
crash_set_path_platform :: proc() {}

@(private)
crash_open_platform :: proc "contextless" () -> Crash_File {
	if crash.pathLen == 0 do return CRASH_STDERR
	fd := posix.open(cstring(raw_data(crash.path[:])), {.WRONLY, .CREAT, .TRUNC}, {.IRUSR, .IWUSR, .IRGRP, .IROTH})
	return CRASH_STDERR if fd < 0 else Crash_File(uintptr(fd))
}

@(private)
crash_fd :: proc "contextless" (f: Crash_File) -> posix.FD {
	return posix.STDERR_FILENO if f == CRASH_STDERR else posix.FD(f)
}

@(private)
crash_write_platform :: proc "contextless" (f: Crash_File, s: string) {
	if len(s) == 0 do return
	_ = posix.write(crash_fd(f), raw_data(s), uint(len(s)))
}

@(private)
crash_close_platform :: proc "contextless" (f: Crash_File) {
	if f != CRASH_STDERR do posix.close(crash_fd(f))
}

@(private = "file")
Stack_Walk :: struct {
	f:    Crash_File,
	n:    int,
}

@(private)
crash_stack_platform :: proc "contextless" (f: Crash_File) {
	walk := Stack_Walk{f = f}
	_Unwind_Backtrace(proc "c" (ctx: rawptr, arg: rawptr) -> c.int {
		walk := (^Stack_Walk)(arg)
		ip := _Unwind_GetIP(ctx)
		if ip == 0 || walk.n >= 64 do return 5 // (_URC_END_OF_STACK)
		buf: [24]u8
		w := walk.f
		info: Dl_info
		named := dladdr(rawptr(ip), &info) != 0
		// (The report's own frames at the top: the stack starts at the crash.)
		if walk.n == 0 && named && info.dli_sname != nil && crash_own_frame(string(info.dli_sname)) do return 0
		crash_write_platform(w, "  ")
		crash_write_platform(w, crash_itoa(buf[:], i64(walk.n)))
		crash_write_platform(w, "  ")
		crash_write_platform(w, crash_hex(buf[:], ip))
		if named {
			if info.dli_sname != nil {
				crash_write_platform(w, "  ")
				crash_write_platform(w, string(info.dli_sname))
				crash_write_platform(w, " + ")
				crash_write_platform(w, crash_itoa(buf[:], i64(ip - uintptr(info.dli_saddr))))
			}
			if info.dli_fname != nil {
				// (The module and the offset in it: addr2line / atos with the debug build.)
				name := string(info.dli_fname)
				for i := len(name) - 1; i >= 0; i -= 1 do if name[i] == '/' {
					name = name[i + 1:]
					break
				}
				crash_write_platform(w, "  (")
				crash_write_platform(w, name)
				crash_write_platform(w, "+")
				crash_write_platform(w, crash_hex(buf[:], ip - uintptr(info.dli_fbase)))
				crash_write_platform(w, ")")
			}
		}
		crash_write_platform(w, "\n")
		walk.n += 1
		return 0
	}, &walk)
}

@(private)
crash_unix_time_platform :: proc "contextless" () -> i64 {
	return i64(posix.time(nil))
}

@(private)
crash_pid_platform :: proc() -> int {
	return int(posix.getpid())
}

@(private)
crash_abort_platform :: proc() {
	posix.abort()
}
