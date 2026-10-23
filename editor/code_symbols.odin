package editor

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import buf "../odin_editor/buffer"

// ============================================================================
// Outline (Cmd+Shift+O): the active script's functions, script properties
// and top-level locals; workspace symbols (Cmd+T): the functions of every
// project script (open ones from their buffers). Both open the palette:
// type to filter (fuzzy), Enter goes there.
// ============================================================================

// code_file_symbols lists a script's symbols (lines of text).
@(private = "file")
code_file_symbols :: proc(out: ^[dynamic]Palette_Location, path, display: string, lines: []string, functionsOnly: bool) {
	inProps := false
	for raw, ln in lines {
		l := strings.trim_space(raw)
		indent := len(raw) - len(strings.trim_left(raw, " \t"))
		if strings.has_prefix(l, "--") || l == "" do continue
		// Functions: "function A:b(x)", "local function f(x)", "M.f = function(x)".
		name, kind := "", ""
		if i := strings.index(l, "function"); i >= 0 && (i == 0 || strings.has_prefix(l, "local function") || strings.contains(l[:i], "=")) {
			rest := strings.trim_space(l[i + len("function"):])
			if p := strings.index_byte(rest, '('); p > 0 {
				name, kind = rest[:p], "function"
			} else if eq := strings.index_byte(l, '='); eq > 0 && eq < i {
				name, kind = strings.trim_space(strings.trim_prefix(l[:eq], "local ")), "function"
			}
			if name != "" {
				args := ""
				if p := strings.index_byte(l, '('); p >= 0 {
					if q := strings.index_byte(l[p:], ')'); q >= 0 do args = l[p:p + q + 1]
				}
				append(out, Palette_Location{path, ln, indent, fmt.tprintf("%s%s", name, args), fmt.tprintf("%s · %s:%d", kind, display, ln + 1)})
			}
			continue
		}
		if functionsOnly do continue
		// Script properties: entries of "X.properties = {".
		if strings.has_suffix(l, ".properties = {") {
			inProps = true
			continue
		}
		if inProps {
			if strings.has_prefix(l, "}") {
				inProps = false
				continue
			}
			if eq := strings.index_byte(l, '='); eq > 0 {
				append(out, Palette_Location{path, ln, indent, strings.trim_space(l[:eq]), fmt.tprintf("property · line %d", ln + 1)})
			}
			continue
		}
		// Top-level locals.
		if indent == 0 && strings.has_prefix(l, "local ") {
			decl := l[len("local "):]
			if eq := strings.index_byte(decl, '='); eq > 0 do decl = decl[:eq]
			append(out, Palette_Location{path, ln, 0, strings.trim_space(decl), fmt.tprintf("local · line %d", ln + 1)})
		}
	}
}

// Code_CmdOutline (Cmd+Shift+O).
Code_CmdOutline :: proc(state: ^EditorState) {
	doc := code_active_doc()
	if doc == nil do return
	lines := make([dynamic]string, context.temp_allocator)
	for ln in 0 ..< buf.buffer_line_count(&doc.buffer) do append(&lines, strings.clone(buf.buffer_line_str(&doc.buffer, ln), context.temp_allocator))
	out := make([dynamic]Palette_Location, context.temp_allocator)
	code_file_symbols(&out, doc.path, doc.rel, lines[:], false)
	if len(out) == 0 {
		Editor_Log(state, .Info, "No symbols in %s", doc.rel)
		return
	}
	Palette_ShowList(fmt.tprintf("Go to symbol in %s", filepath.base(doc.rel)), out[:])
}

// Code_CmdWorkspaceSymbols (Cmd+T): functions across the project's scripts.
Code_CmdWorkspaceSymbols :: proc(state: ^EditorState) {
	out := make([dynamic]Palette_Location, context.temp_allocator)
	for rel in Editor_ListProjectFiles(state, "", {".lua"}) {
		if strings.has_prefix(rel, ".") do continue
		full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
		lines: []string
		if doc := code_doc_for_path(full); doc != nil {
			l := make([dynamic]string, context.temp_allocator)
			for ln in 0 ..< buf.buffer_line_count(&doc.buffer) do append(&l, strings.clone(buf.buffer_line_str(&doc.buffer, ln), context.temp_allocator))
			lines = l[:]
		} else if data, err := os.read_entire_file(full, context.temp_allocator); err == nil {
			lines = strings.split_lines(string(data), context.temp_allocator)
		}
		code_file_symbols(&out, full, rel, lines, true)
	}
	if len(out) == 0 {
		Editor_Log(state, .Info, "No functions in the project's scripts")
		return
	}
	Palette_ShowList("Go to symbol in the project", out[:])
}

// code_doc_for_path: the open doc of an absolute path.
code_doc_for_path :: proc(path: string) -> ^Code_Doc {
	for d in GlobalCode.docs do if d.path == path do return d
	return nil
}
