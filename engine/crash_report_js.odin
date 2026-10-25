#+build js
package engine

// Crash reports on the web (crash_report.odin): none - the browser's console
// has the error.

@(private) crash_install_platform :: proc() {}
@(private) crash_set_path_platform :: proc() {}
@(private) crash_open_platform :: proc "contextless" () -> Crash_File {return CRASH_STDERR}
@(private) crash_write_platform :: proc "contextless" (f: Crash_File, s: string) {}
@(private) crash_close_platform :: proc "contextless" (f: Crash_File) {}
@(private) crash_stack_platform :: proc "contextless" (f: Crash_File) {}
@(private) crash_unix_time_platform :: proc "contextless" () -> i64 {return 0}
@(private) crash_pid_platform :: proc() -> int {return 0}
@(private) crash_abort_platform :: proc() {}
