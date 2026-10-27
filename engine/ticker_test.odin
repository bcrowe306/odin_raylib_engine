package engine

import "core:testing"
import "core:time"

// Slow rates keep their real period (the f32 -> i64 conversion used to
// overflow past ~2.1 s: negative on x86-64, ticking every frame); 0 fps
// never ticks.
@(test)
test_ticker_slow_fps :: proc(t: ^testing.T) {
	tk: Ticker
	Ticker_Init(&tk, false)
	tk->setFPS(12)
	testing.expect(t, abs(time.duration_milliseconds(tk.secondsPerFrame) - 1000.0 / 12) < 0.01, "12 fps")
	tk->setFPS(0.1)
	testing.expectf(t, abs(time.duration_seconds(tk.secondsPerFrame) - 10) < 0.001, "0.1 fps: %v", tk.secondsPerFrame)
	tk->setFPS(0)
	testing.expect(t, tk.secondsPerFrame > 0, "0 fps: never")
	// A slow ticker doesn't tick on the next process.
	ticks := 0
	tk->setFPS(0.1)
	tk->setCallback(proc(tk: ^Ticker, n: int, data: rawptr) {(cast(^int)data)^ += 1}, &ticks)
	tk->start(true)
	for _ in 0 ..< 5 do tk->process()
	testing.expect_value(t, ticks, 0)
}
