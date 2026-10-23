package editor

import "core:strings"
import buf "../odin_editor/buffer"

// ============================================================================
// Inlay hints: parameter names before the arguments of calls -
// `Audio.play_sound(path: "x.wav", volume: 0.5)` - for the engine API (from
// engine_api.lua, compiled in) and the functions the file defines. Hints
// are inline (text after them moves right): code_row_x / code_row_col add
// their widths. Computed per line on demand, cached per buffer version.
// ============================================================================

EDITOR_ENGINE_API :: #load("../engine/definitions/engine_api.lua", string)

Code_Inlay :: struct {
	col:   int,    // byte column the hint sits before
	label: string, // "name:" (static / doc-cache owned)
}

@(private = "file")
api: struct {
	built:   bool,
	sigs:    map[string][]string, // "AudioModule.play_sound", ":set_position" (methods by name)
	modules: map[string]string,   // "Audio" -> "AudioModule"
}

// api_build parses engine_api.lua's function lines once (process lifetime).
@(private = "file")
api_build :: proc() {
	if api.built do return
	api.built = true
	for line in strings.split_lines(EDITOR_ENGINE_API, context.temp_allocator) {
		if strings.has_prefix(line, "function ") {
			sig := line[len("function "):]
			p := strings.index_byte(sig, '(')
			q := strings.index_byte(sig, ')')
			if p < 0 || q < p do continue
			head := sig[:p]
			params := parse_params(sig[p + 1:q])
			if dot := strings.last_index_any(head, ".:"); dot >= 0 {
				api.sigs[strings.clone(head)] = params
				method := strings.concatenate({":", head[dot + 1:]})
				if method not_in api.sigs do api.sigs[method] = params
				else do delete(method)
			}
		} else if eq := strings.index(line, " = "); eq > 0 && strings.has_suffix(line, "Module") && !strings.has_prefix(line, "local") {
			name, mod := strings.trim_space(line[:eq]), strings.trim_space(line[eq + 3:])
			if !strings.contains(name, " ") && !strings.contains(mod, " ") do api.modules[strings.clone(name)] = strings.clone(mod)
		}
	}
}

@(private = "file")
parse_params :: proc(s: string) -> []string {
	out := make([dynamic]string)
	for part in strings.split(s, ",", context.temp_allocator) {
		p := strings.trim_space(part)
		if p == "" || p == "..." do continue
		append(&out, strings.clone(p))
	}
	return out[:]
}

// code_inlays: a line's hints (empty when off / none).
code_inlays :: proc(doc: ^Code_Doc, ln: int) -> []Code_Inlay {
	if !GlobalSettings.inlayHints || !doc.isLua do return nil
	c := &doc.inlayCache
	b := &doc.buffer
	if c.version != b.version {
		code_inlay_cache_clear(c)
		c.version = b.version
		code_inlay_file_sigs(doc)
	}
	if hints, ok := c.lines[ln]; ok do return hints
	hints := code_inlay_line(doc, ln)
	c.lines[ln] = hints
	return hints
}

Code_Inlay_Cache :: struct {
	version:  int,
	lines:    map[int][]Code_Inlay,
	fileSigs: map[string][]string, // functions defined in the file: "name" / ":name"
	strings:  [dynamic]string,     // labels owned by the cache
}

code_inlay_cache_clear :: proc(c: ^Code_Inlay_Cache) {
	for _, h in c.lines do delete(h)
	clear(&c.lines)
	for k, v in c.fileSigs {
		delete(k)
		for p in v do delete(p)
		delete(v)
	}
	clear(&c.fileSigs)
	for s in c.strings do delete(s)
	clear(&c.strings)
}

code_inlay_cache_destroy :: proc(c: ^Code_Inlay_Cache) {
	code_inlay_cache_clear(c)
	delete(c.lines)
	delete(c.fileSigs)
	delete(c.strings)
}

// code_inlay_file_sigs: the parameters of the functions this file defines.
@(private = "file")
code_inlay_file_sigs :: proc(doc: ^Code_Doc) {
	c := &doc.inlayCache
	b := &doc.buffer
	for ln in 0 ..< buf.buffer_line_count(b) {
		l := strings.trim_space(buf.buffer_line_str(b, ln))
		i := strings.index(l, "function ")
		if i < 0 || (i > 0 && !strings.has_prefix(l, "local ")) do continue
		rest := l[i + len("function "):]
		p := strings.index_byte(rest, '(')
		q := strings.index_byte(rest, ')')
		if p <= 0 || q < p do continue
		head := rest[:p]
		key := head
		if dot := strings.last_index_any(head, ".:"); dot >= 0 do key = strings.concatenate({":", head[dot + 1:]}, context.temp_allocator)
		if key in c.fileSigs do continue
		c.fileSigs[strings.clone(key)] = parse_params(rest[p + 1:q])
	}
}

// code_inlay_line finds the calls on a line and hints their arguments.
@(private = "file")
code_inlay_line :: proc(doc: ^Code_Doc, ln: int) -> []Code_Inlay {
	api_build()
	c := &doc.inlayCache
	b := &doc.buffer
	text := buf.buffer_line_str(b, ln)
	code_update_line_states(doc)
	tokens, _ := Token_CacheGet(&doc.tokens, doc.lang, text, doc.lineStates[ln] if ln < len(doc.lineStates) else 0, b.version)
	skip := make([]bool, len(text) + 1, context.temp_allocator) // strings / comments
	for t in tokens {
		if t.kind == .String || t.kind == .Comment do for k in t.start ..< t.end do skip[k] = true
	}
	out := make([dynamic]Code_Inlay)
	for i := 0; i < len(text); i += 1 {
		if text[i] != '(' || skip[i] do continue
		// The callee: an identifier chain right before '('.
		e := i
		s := e
		for s > 0 && (code_is_ident_byte(text[s - 1]) || text[s - 1] == '.' || text[s - 1] == ':') do s -= 1
		callee := text[s:e]
		if callee == "" || strings.has_suffix(strings.trim_space(text[:s]), "function") do continue
		params := code_inlay_params(c, callee)
		if len(params) == 0 do continue
		// Arguments: split at top-level commas up to the matching ')' on this line.
		depth := 0
		argStart := i + 1
		argIdx := 0
		for k := i + 1; k <= len(text); k += 1 {
			ch: u8 = 0 if k == len(text) else text[k]
			if k < len(text) && skip[k] do continue
			if ch == '(' || ch == '{' || ch == '[' do depth += 1
			if (ch == ')' || ch == '}' || ch == ']') && depth > 0 {depth -= 1; continue}
			end := k == len(text) || ((ch == ',' || ch == ')') && depth == 0)
			if !end do continue
			arg := strings.trim_space(text[argStart:k])
			if arg != "" && argIdx < len(params) {
				name := params[argIdx]
				// Not when the argument already says it (x for x, self.speed for speed).
				if arg != name && !strings.has_suffix(arg, strings.concatenate({".", name}, context.temp_allocator)) {
					col := argStart + (len(text[argStart:k]) - len(strings.trim_left(text[argStart:k], " \t")))
					label := strings.concatenate({name, ":"})
					append(&c.strings, label)
					append(&out, Code_Inlay{col, label})
				}
			}
			argIdx += 1
			argStart = k + 1
			if ch == ')' || k == len(text) do break
		}
	}
	return out[:]
}

// code_inlay_params: the parameter names of a callee ("Audio.play_sound",
// "self.node:set_position", "helper").
@(private = "file")
code_inlay_params :: proc(c: ^Code_Inlay_Cache, callee: string) -> []string {
	sep := strings.last_index_any(callee, ".:")
	if sep < 0 {
		return c.fileSigs[callee] or_else nil
	}
	name := callee[sep + 1:]
	qual := callee[:sep]
	if callee[sep] == '.' {
		if mod, ok := api.modules[qual]; ok {
			if p, has := api.sigs[strings.concatenate({mod, ".", name}, context.temp_allocator)]; has do return p
		}
		if p, has := api.sigs[callee]; has do return p
	}
	key := strings.concatenate({":", name}, context.temp_allocator)
	if p, has := c.fileSigs[key]; has do return p
	if callee[sep] == ':' do return api.sigs[key] or_else nil
	return nil
}

// code_inlay_width: columns a hint takes (its label and a space).
code_inlay_width :: proc(h: Code_Inlay) -> int {return len(h.label) + 1}

// code_inlay_before: columns of hints at or before col on a row.
code_inlay_before :: proc(hints: []Code_Inlay, from, col: int) -> int {
	w := 0
	for h in hints do if h.col >= from && h.col <= col do w += code_inlay_width(h)
	return w
}
