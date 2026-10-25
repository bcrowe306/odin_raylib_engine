package engine

import "core:strconv"
import "core:strings"

// The release version of the engine, the editor and the runners (the git
// tag in CI: -define:ORE_RELEASE=1.2.3; scripts/package_editor.sh). The .ore
// package format has its own number (ORE_VERSION, ore_package.odin).
ORE_RELEASE :: #config(ORE_RELEASE, "0.0.0-dev")


// Version_IsDev: a development build's version (no release: 0.0.0-...).
Version_IsDev :: proc(v: string) -> bool {
	return v == "" || strings.has_prefix(v, "0.0.0-")
}

// Version_Compare orders release versions ("1.2.3", "1.2.3-beta.1"): -1, 0
// or 1. A pre-release sorts before its release; pre-releases of the same
// release compare part by part as semver does ("dev.9" < "dev.10": numbers
// as numbers, before words; fewer parts first).
Version_Compare :: proc(a, b: string) -> int {
	split :: proc(v: string) -> (nums: [3]int, pre: string) {
		core := strings.trim_prefix(v, "v")
		if i := strings.index_byte(core, '-'); i >= 0 {
			pre = core[i + 1:]
			core = core[:i]
		}
		parts := strings.split(core, ".", context.temp_allocator)
		for p, k in parts {
			if k >= 3 do break
			nums[k], _ = strconv.parse_int(p)
		}
		return
	}
	an, ap := split(a)
	bn, bp := split(b)
	for k in 0 ..< 3 {
		if an[k] != bn[k] do return -1 if an[k] < bn[k] else 1
	}
	switch {
	case ap == bp: return 0
	case ap == "": return 1
	case bp == "": return -1
	}
	as := strings.split(ap, ".", context.temp_allocator)
	bs := strings.split(bp, ".", context.temp_allocator)
	for k in 0 ..< min(len(as), len(bs)) {
		x, xnum := strconv.parse_int(as[k], 10)
		y, ynum := strconv.parse_int(bs[k], 10)
		switch {
		case xnum && ynum: if x != y do return -1 if x < y else 1
		case xnum: return -1
		case ynum: return 1
		case as[k] != bs[k]: return -1 if as[k] < bs[k] else 1
		}
	}
	if len(as) != len(bs) do return -1 if len(as) < len(bs) else 1
	return 0
}

// Version_IsPrerelease: "1.2.0-dev.14", "1.0.0-beta.1" (a suffix).
Version_IsPrerelease :: proc(v: string) -> bool {
	return strings.index_byte(v, '-') >= 0
}
