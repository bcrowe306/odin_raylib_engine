package clipper

import "core:c"

// ============================================================================
// Clipper2 (polygon clipping and offsetting; Angus Johnson, Boost Software
// License 1.0) through the engine's C interface (rayzr_clipper.cpp, built
// by scripts/build_clipper.sh). The vector renderer normalizes fills with
// it (fill rules, self-intersections); boolean path operations and
// outlines use it too.
//
// Every call returns a Paths result (free it with free_paths): contours as
// x, y pairs; parents[i] is the outer ring a hole belongs to (-1: an outer).
// ============================================================================

when ODIN_OS == .Windows {
	foreign import lib "lib/clipper_windows_x64.lib"
} else when ODIN_OS == .Darwin {
	foreign import lib {"lib/libclipper_darwin.a", "system:c++"}
} else when ODIN_OS == .Linux {
	foreign import lib {"lib/libclipper_linux_x64.a", "system:stdc++"}
} else when ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32 {
	foreign import lib "env.o" // (libclipper.a is linked by emcc: scripts/build_web_runner.sh)
} else {
	foreign import lib "system:clipper"
}

Paths :: struct {
	xy:       [^]f64,
	counts:   [^]c.int,
	parents:  [^]c.int,
	contours: c.int,
	points:   c.int,
}

Fill_Rule :: enum c.int {
	EvenOdd  = 0,
	NonZero  = 1,
	Positive = 2,
	Negative = 3,
}

Op :: enum c.int {
	Intersection = 1,
	Union        = 2,
	Difference   = 3,
	Xor          = 4,
}

Join :: enum c.int {
	Square = 0,
	Bevel  = 1,
	Round  = 2,
	Miter  = 3,
}

End :: enum c.int {
	Butt   = 2,
	Square = 3,
	Round  = 4,
}

@(default_calling_convention = "c")
foreign lib {
	@(link_name = "rz_normalize")
	normalize :: proc(xy: [^]f64, counts: [^]c.int, n: c.int, rule: Fill_Rule, precision: c.int, out: ^Paths) -> c.int ---
	@(link_name = "rz_boolean")
	boolean :: proc(op: Op, sxy: [^]f64, scounts: [^]c.int, sn: c.int, cxy: [^]f64, ccounts: [^]c.int, cn: c.int, rule: Fill_Rule, precision: c.int, out: ^Paths) -> c.int ---
	@(link_name = "rz_offset")
	offset :: proc(xy: [^]f64, counts: [^]c.int, n: c.int, closed: c.int, delta: f64, join: Join, end: End, miter_limit, arc_tolerance: f64, precision: c.int, out: ^Paths) -> c.int ---
	@(link_name = "rz_free")
	free_paths :: proc(p: ^Paths) ---
}
