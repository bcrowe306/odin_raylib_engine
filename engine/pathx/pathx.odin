package pathx

// ============================================================================
// pathx: the core:path/filepath procedures the engine uses, with the same
// signatures, over forward-slash paths and without core:os - for the web
// build, where core:path/filepath doesn't build (scripts/web_prepare.py
// points the copied sources' filepath imports here). Paths are emscripten
// file system paths ("/game.ore", "/save/...").
// ============================================================================

import "base:runtime"
import "core:path/slashpath"
import "core:strings"

Relative_Error :: enum {
	None,
	Cannot_Relate,
}

join :: proc(elems: []string, allocator := context.allocator) -> (string, runtime.Allocator_Error) {
	return slashpath.join(elems, allocator), nil
}

base :: proc(path: string) -> string {
	if path == "" do return "."
	p := strings.trim_right(path, "/")
	if p == "" do return "/"
	i := strings.last_index_byte(p, '/')
	return p[i + 1:]
}

dir :: proc(path: string, allocator := context.allocator) -> string {
	return slashpath.dir(path, allocator)
}

ext :: proc(path: string) -> string {
	b := base(path)
	i := strings.last_index_byte(b, '.')
	return b[i:] if i >= 0 else ""
}

stem :: proc(path: string) -> string {
	b := base(path)
	i := strings.last_index_byte(b, '.')
	return b[:i] if i > 0 else b
}

is_abs :: proc(path: string) -> bool {return strings.has_prefix(path, "/")}

clean :: proc(path: string, allocator := context.allocator) -> (string, runtime.Allocator_Error) {
	return slashpath.clean(path, allocator), nil
}

abs :: proc(path: string, allocator := context.allocator) -> (string, runtime.Allocator_Error) {
	if is_abs(path) do return slashpath.clean(path, allocator), nil
	return slashpath.clean(strings.concatenate({"/", path}, context.temp_allocator), allocator), nil
}

rel :: proc(base_path, target_path: string, allocator := context.allocator) -> (string, Relative_Error) {
	b := slashpath.clean(base_path, context.temp_allocator)
	t := slashpath.clean(target_path, context.temp_allocator)
	if t == b do return strings.clone(".", allocator), .None
	prefix := b if strings.has_suffix(b, "/") else strings.concatenate({b, "/"}, context.temp_allocator)
	if strings.has_prefix(t, prefix) do return strings.clone(t[len(prefix):], allocator), .None
	return "", .Cannot_Relate
}

match :: proc(pattern, name: string) -> (bool, slashpath.Match_Error) {
	return slashpath.match(pattern, name)
}
