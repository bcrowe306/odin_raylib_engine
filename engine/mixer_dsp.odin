package engine

import "base:runtime"
import "core:math"

// ============================================================================
// Mixer bus effects (mixer.odin). Each effect processes a bus's stereo block
// in place on the audio thread; buffers (delay lines, reverb) are allocated
// on the game thread when the effect is added, so the audio thread never
// allocates. Parameters are plain floats the game thread writes; filter
// coefficients are recomputed on the audio thread when they change.
// ============================================================================

Mixer_Effect_Type :: enum u8 {
	None,
	EQ,          // low shelf, mid peak, high shelf
	Lowpass,
	Highpass,
	Compressor,
	Limiter,
	Delay,
	Reverb,
	Distortion,
}

MIXER_EFFECT_NAMES := [Mixer_Effect_Type]string {
	.None       = "none",
	.EQ         = "eq",
	.Lowpass    = "lowpass",
	.Highpass   = "highpass",
	.Compressor = "compressor",
	.Limiter    = "limiter",
	.Delay      = "delay",
	.Reverb     = "reverb",
	.Distortion = "distortion",
}

MIXER_EFFECT_LABELS := [Mixer_Effect_Type]string {
	.None       = "None",
	.EQ         = "EQ",
	.Lowpass    = "Low-pass",
	.Highpass   = "High-pass",
	.Compressor = "Compressor",
	.Limiter    = "Limiter",
	.Delay      = "Delay",
	.Reverb     = "Reverb",
	.Distortion = "Distortion",
}

Effect_Param_Def :: struct {
	name:  string, // saved / Lua key
	label: string,
	min, max, def: f32,
	unit:  string,
	log:   bool,   // shown on a logarithmic scale (frequencies, times)
}

MIXER_MAX_PARAMS :: 6

// The parameters of each effect, in order (Mixer_Effect.params).
MIXER_EFFECT_PARAMS := [Mixer_Effect_Type][]Effect_Param_Def {
	.None = {},
	.EQ = {
		{"low_gain", "Low", -24, 24, 0, "dB", false},
		{"low_freq", "Low Freq", 40, 1000, 200, "Hz", true},
		{"mid_gain", "Mid", -24, 24, 0, "dB", false},
		{"mid_freq", "Mid Freq", 200, 8000, 1000, "Hz", true},
		{"high_gain", "High", -24, 24, 0, "dB", false},
		{"high_freq", "High Freq", 1000, 16000, 5000, "Hz", true},
	},
	.Lowpass = {
		{"cutoff", "Cutoff", 40, 20000, 2000, "Hz", true},
		{"resonance", "Resonance", 0.3, 10, 0.707, "Q", false},
	},
	.Highpass = {
		{"cutoff", "Cutoff", 20, 10000, 200, "Hz", true},
		{"resonance", "Resonance", 0.3, 10, 0.707, "Q", false},
	},
	.Compressor = {
		{"threshold", "Threshold", -60, 0, -18, "dB", false},
		{"ratio", "Ratio", 1, 20, 4, ":1", false},
		{"attack", "Attack", 0.1, 200, 10, "ms", true},
		{"release", "Release", 5, 2000, 150, "ms", true},
		{"makeup", "Makeup", 0, 24, 0, "dB", false},
	},
	.Limiter = {
		{"ceiling", "Ceiling", -24, 0, -0.3, "dB", false},
		{"release", "Release", 5, 1000, 80, "ms", true},
	},
	.Delay = {
		{"time", "Time", 10, 2000, 300, "ms", true},
		{"feedback", "Feedback", 0, 0.95, 0.35, "", false},
		{"mix", "Mix", 0, 1, 0.3, "", false},
	},
	.Reverb = {
		{"size", "Room Size", 0, 1, 0.6, "", false},
		{"damping", "Damping", 0, 1, 0.3, "", false},
		{"mix", "Mix", 0, 1, 0.25, "", false},
	},
	.Distortion = {
		{"drive", "Drive", 1, 50, 4, "x", true},
		{"mix", "Mix", 0, 1, 1, "", false},
		{"output", "Output", -24, 6, -6, "dB", false},
	},
}

Effect_ParseType :: proc(s: string) -> (Mixer_Effect_Type, bool) {
	for name, t in MIXER_EFFECT_NAMES do if name == s && t != .None do return t, true
	return .None, false
}

// --- state ----------------------------------------------------------------------------

Biquad :: struct {
	b0, b1, b2, a1, a2: f32,
	z:                  [2][2]f32, // per channel: two state values (transposed direct form II)
}

DELAY_MAX_MS :: 2000
REVERB_COMB := [4]int{1557, 1617, 1491, 1422}
REVERB_AP := [2]int{556, 441}

Mixer_Effect :: struct {
	type:     Mixer_Effect_Type,
	enabled:  bool,
	params:   [MIXER_MAX_PARAMS]f32,
	// Audio thread.
	applied:  [MIXER_MAX_PARAMS]f32, // the params the coefficients were made for
	fresh:    bool,                  // coefficients valid
	bq:       [3]Biquad,
	env:      f32,                   // compressor / limiter envelope (linear)
	gr:       f32,                   // gain reduction now (dB, for the meter)
	// Buffers (heap; game thread).
	buf:      []f32,
	delayPos: int,
	comb:     [2][4][]f32,
	combPos:  [2][4]int,
	combLp:   [2][4]f32,
	ap:       [2][2][]f32,
	apPos:    [2][2]int,
}

// Effect_Init: a new effect with default parameters and its buffers.
Effect_Init :: proc(e: ^Mixer_Effect, t: Mixer_Effect_Type, rate: f32) {
	Effect_Free(e)
	e^ = {type = t, enabled = true}
	for d, i in MIXER_EFFECT_PARAMS[t] do e.params[i] = d.def
	a := runtime.heap_allocator()
	#partial switch t {
	case .Delay:
		e.buf = make([]f32, int(rate * DELAY_MAX_MS / 1000 + 4) * 2, a)
	case .Reverb:
		total := 0
		for ch in 0 ..< 2 {
			for l in REVERB_COMB do total += l + ch * 23
			for l in REVERB_AP do total += l + ch * 23
		}
		e.buf = make([]f32, total, a)
		at := 0
		for ch in 0 ..< 2 {
			for l, i in REVERB_COMB {
				n := l + ch * 23
				e.comb[ch][i] = e.buf[at:at + n]
				at += n
			}
			for l, i in REVERB_AP {
				n := l + ch * 23
				e.ap[ch][i] = e.buf[at:at + n]
				at += n
			}
		}
	}
}

Effect_Free :: proc(e: ^Mixer_Effect) {
	if e.buf != nil do delete(e.buf, runtime.heap_allocator())
	e.buf = nil
}

// Effect_Clear silences an effect's memory (tails) without reallocating.
Effect_Clear :: proc(e: ^Mixer_Effect) {
	for &v in e.buf do v = 0
	e.bq = {}
	for &b in e.bq do b.z = {}
	e.env, e.gr = 0, 0
	e.combLp = {}
	e.fresh = false
}

// --- biquads (RBJ cookbook) -----------------------------------------------------------

@(private = "file")
Biquad_Kind :: enum {Lowpass, Highpass, Peak, LowShelf, HighShelf}

@(private = "file")
biquad_set :: proc(b: ^Biquad, kind: Biquad_Kind, freq, q, gainDb, rate: f32) {
	f := clamp(freq, 10, rate * 0.49)
	w := 2 * math.PI * f / rate
	cw, sw := math.cos(w), math.sin(w)
	A := math.pow(10, gainDb / 40)
	alpha := sw / (2 * max(q, 0.05))
	b0, b1, b2, a0, a1, a2: f32
	switch kind {
	case .Lowpass:
		b0, b1, b2 = (1 - cw) / 2, 1 - cw, (1 - cw) / 2
		a0, a1, a2 = 1 + alpha, -2 * cw, 1 - alpha
	case .Highpass:
		b0, b1, b2 = (1 + cw) / 2, -(1 + cw), (1 + cw) / 2
		a0, a1, a2 = 1 + alpha, -2 * cw, 1 - alpha
	case .Peak:
		b0, b1, b2 = 1 + alpha * A, -2 * cw, 1 - alpha * A
		a0, a1, a2 = 1 + alpha / A, -2 * cw, 1 - alpha / A
	case .LowShelf:
		sa := 2 * math.sqrt(A) * alpha
		b0 = A * ((A + 1) - (A - 1) * cw + sa)
		b1 = 2 * A * ((A - 1) - (A + 1) * cw)
		b2 = A * ((A + 1) - (A - 1) * cw - sa)
		a0 = (A + 1) + (A - 1) * cw + sa
		a1 = -2 * ((A - 1) + (A + 1) * cw)
		a2 = (A + 1) + (A - 1) * cw - sa
	case .HighShelf:
		sa := 2 * math.sqrt(A) * alpha
		b0 = A * ((A + 1) + (A - 1) * cw + sa)
		b1 = -2 * A * ((A - 1) + (A + 1) * cw)
		b2 = A * ((A + 1) + (A - 1) * cw - sa)
		a0 = (A + 1) - (A - 1) * cw + sa
		a1 = 2 * ((A - 1) - (A + 1) * cw)
		a2 = (A + 1) - (A - 1) * cw - sa
	}
	b.b0, b.b1, b.b2, b.a1, b.a2 = b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0
}

@(private = "file")
biquad_run :: #force_inline proc(b: ^Biquad, x: f32, ch: int) -> f32 {
	y := b.b0 * x + b.z[ch][0]
	b.z[ch][0] = b.b1 * x - b.a1 * y + b.z[ch][1]
	b.z[ch][1] = b.b2 * x - b.a2 * y
	return y
}

db_to_lin :: #force_inline proc(db: f32) -> f32 {return math.pow(10, db / 20)}
lin_to_db :: #force_inline proc(v: f32) -> f32 {return 20 * math.log10(max(v, 1e-6))}

// Effect_Process runs one effect over interleaved stereo samples in place.
Effect_Process :: proc(e: ^Mixer_Effect, s: []f32, rate: f32) {
	if !e.enabled || e.type == .None do return
	frames := len(s) / 2
	p := &e.params
	if !e.fresh || e.applied != p^ {
		e.applied = p^
		e.fresh = true
		#partial switch e.type {
		case .EQ:
			biquad_set(&e.bq[0], .LowShelf, p[1], 0.707, p[0], rate)
			biquad_set(&e.bq[1], .Peak, p[3], 1.0, p[2], rate)
			biquad_set(&e.bq[2], .HighShelf, p[5], 0.707, p[4], rate)
		case .Lowpass:  biquad_set(&e.bq[0], .Lowpass, p[0], p[1], 0, rate)
		case .Highpass: biquad_set(&e.bq[0], .Highpass, p[0], p[1], 0, rate)
		}
	}
	switch e.type {
	case .None:
	case .EQ:
		for i in 0 ..< frames do for ch in 0 ..< 2 {
			x := s[i * 2 + ch]
			if p[0] != 0 do x = biquad_run(&e.bq[0], x, ch)
			if p[2] != 0 do x = biquad_run(&e.bq[1], x, ch)
			if p[4] != 0 do x = biquad_run(&e.bq[2], x, ch)
			s[i * 2 + ch] = x
		}
	case .Lowpass, .Highpass:
		for i in 0 ..< frames do for ch in 0 ..< 2 do s[i * 2 + ch] = biquad_run(&e.bq[0], s[i * 2 + ch], ch)
	case .Compressor:
		thr, ratio := p[0], max(p[1], 1)
		att := math.exp(-1 / (max(p[2], 0.01) * 0.001 * rate))
		rel := math.exp(-1 / (max(p[3], 1) * 0.001 * rate))
		makeup := db_to_lin(p[4])
		maxGr: f32 = 0
		for i in 0 ..< frames {
			peak := max(abs(s[i * 2]), abs(s[i * 2 + 1]))
			c := att if peak > e.env else rel
			e.env = c * e.env + (1 - c) * peak
			over := lin_to_db(e.env) - thr
			gr: f32 = over * (1 - 1 / ratio) if over > 0 else 0
			maxGr = max(maxGr, gr)
			g := db_to_lin(-gr) * makeup
			s[i * 2] *= g
			s[i * 2 + 1] *= g
		}
		e.gr = maxGr
	case .Limiter:
		ceil := db_to_lin(p[0])
		rel := math.exp(-1 / (max(p[1], 1) * 0.001 * rate))
		maxGr: f32 = 0
		for i in 0 ..< frames {
			peak := max(abs(s[i * 2]), abs(s[i * 2 + 1]))
			// e.env: the gain (1 = none); drops at once, recovers with release.
			if e.env <= 0 do e.env = 1
			want: f32 = ceil / peak if peak > ceil else 1
			e.env = want if want < e.env else rel * e.env + (1 - rel) * want
			s[i * 2] *= e.env
			s[i * 2 + 1] *= e.env
			maxGr = max(maxGr, -lin_to_db(e.env))
		}
		e.gr = maxGr
	case .Delay:
		if e.buf == nil do return
		n := len(e.buf) / 2
		d := clamp(int(p[0] * 0.001 * rate), 1, n - 1)
		fb, mix := p[1], p[2]
		for i in 0 ..< frames {
			r := (e.delayPos - d + n) % n
			for ch in 0 ..< 2 {
				x := s[i * 2 + ch]
				y := e.buf[r * 2 + ch]
				e.buf[e.delayPos * 2 + ch] = x + y * fb
				s[i * 2 + ch] = x * (1 - mix) + y * mix
			}
			e.delayPos = (e.delayPos + 1) % n
		}
	case .Reverb:
		if e.buf == nil do return
		feedback := 0.7 + 0.28 * clamp(p[0], 0, 1)
		damp := clamp(p[1], 0, 1)
		mix := clamp(p[2], 0, 1)
		for i in 0 ..< frames do for ch in 0 ..< 2 {
			x := s[i * 2 + ch]
			wet: f32
			for k in 0 ..< 4 {
				b := e.comb[ch][k]
				pos := e.combPos[ch][k]
				y := b[pos]
				e.combLp[ch][k] = y * (1 - damp) + e.combLp[ch][k] * damp
				b[pos] = x * 0.015 + e.combLp[ch][k] * feedback
				e.combPos[ch][k] = (pos + 1) % len(b)
				wet += y
			}
			for k in 0 ..< 2 {
				b := e.ap[ch][k]
				pos := e.apPos[ch][k]
				bv := b[pos]
				b[pos] = wet + bv * 0.5
				wet = bv - wet
				e.apPos[ch][k] = (pos + 1) % len(b)
			}
			s[i * 2 + ch] = x * (1 - mix * 0.5) + wet * mix * 3
		}
	case .Distortion:
		drive, mix, out := p[0], p[1], db_to_lin(p[2])
		norm := 1 / math.tanh(drive)
		for i in 0 ..< frames * 2 {
			x := s[i]
			y := math.tanh(x * drive) * norm
			s[i] = (x * (1 - mix) + y * mix) * out
		}
	}
}
