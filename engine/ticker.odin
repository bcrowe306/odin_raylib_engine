package engine

import "core:time"

TickerCallBack :: proc(ticker: ^Ticker, currentTick: int, user_data: rawptr)

Ticker :: struct {
	framesPerSecond: f32,
	secondsPerFrame: time.Duration,
	elapsedTime: time.Duration,
	lastTick: time.Tick,
	currentTick: int,
	user_data: rawptr,
	running: bool,
	setFPS: proc(ticker: ^Ticker, framesPerSecond: f32),
	setCallback: proc(ticker: ^Ticker, callback: TickerCallBack, user_data: rawptr = nil),
	start: proc(ticker: ^Ticker, resetCounter: bool),
	stop: proc(ticker: ^Ticker),
	pause: proc(ticker: ^Ticker),
	resume: proc(ticker: ^Ticker),
	togglePause: proc(ticker: ^Ticker),
	reset: proc(ticker: ^Ticker),
	process: proc(ticker: ^Ticker),
	callback: proc(ticker: ^Ticker, currentTick: int, user_data: rawptr),
}

Ticker_Process :: proc(ticker: ^Ticker) {
	if !ticker.running do return
	tick := time.tick_now()
	ticker.elapsedTime += time.tick_diff(ticker.lastTick, tick)
	ticker.lastTick = tick
	if ticker.elapsedTime >= ticker.secondsPerFrame {
		ticker.elapsedTime = 0
		ticker.currentTick += 1
		if ticker.callback != nil do ticker.callback(ticker, ticker.currentTick, ticker.user_data)
	}
}

Ticker_Init :: proc(ticker: ^Ticker, auto_start: bool = true) {
	ticker.process = Ticker_Process
	ticker.setFPS = Ticker_SetFPS
	ticker.setCallback = Ticker_SetCallback
	ticker.reset = Ticker_Reset
	ticker.start = Ticker_Start
	ticker.stop = Ticker_Stop
	ticker.pause = Ticker_Pause
	ticker.resume = Ticker_Resume
	ticker.togglePause = Ticker_TogglePause
	ticker->setFPS(1)
	if auto_start {
		ticker->start(true)
	}
}

Ticker_Start :: proc(ticker: ^Ticker, resetCounter: bool = true){
	ticker.running = true
	ticker.elapsedTime = 0
	ticker.lastTick = time.tick_now()
	if resetCounter do ticker.currentTick = 0
}
Ticker_Stop :: proc(ticker: ^Ticker) {
	ticker.running = false
}

Ticker_TogglePause :: proc(ticker: ^Ticker) {
	ticker.running = !ticker.running
}

Ticker_Pause :: proc(ticker: ^Ticker) {
	ticker.running = false
}
Ticker_Resume :: proc(ticker: ^Ticker) {
	ticker.running = true
}

Ticker_SetFPS :: proc(ticker: ^Ticker, framesPerSecond: f32) {
	framesPerSecond := clamp(framesPerSecond, 0, 120)
	ticker.framesPerSecond = framesPerSecond
	// In f64: periods over ~2.1 s (fps < ~0.47) overflow an f32 -> i64
	// conversion, which wraps negative on x86-64 (a tick every frame). 0 fps:
	// never ticks.
	if framesPerSecond <= 0 do ticker.secondsPerFrame = max(time.Duration)
	else do ticker.secondsPerFrame = time.Duration(f64(time.Second) / f64(framesPerSecond))
}

Ticker_Reset :: proc(ticker: ^Ticker) {
	ticker.elapsedTime = 0
	ticker.currentTick = 0
}

Ticker_SetCallback :: proc(ticker: ^Ticker, callback: TickerCallBack, user_data: rawptr = nil) {
	ticker.callback = callback
	ticker.user_data = user_data
}
