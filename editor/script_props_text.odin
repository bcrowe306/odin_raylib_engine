package editor

import "core:fmt"
import "core:strings"

// ============================================================================
// A script's `properties` table as text (#208): an entry written from a
// definition (the Properties tab's dialog), added before the table's
// closing brace, replaced where it is (multi-line entries too), removed; the
// table made after `local Cls = {}` when there's none; the lines using
// `self.<name>`.
// ============================================================================

// Prop_Def: a property as the dialog edits it. `default` is a Lua literal
// ("" = none).
Prop_Def :: struct {
	name:     string,
	kind:     string, // the `type`: float, int, range, bool, string, vector2, color, enum, texture ... node, resource, array, curve, gradient
	default:  string,
	min, max: f32,
	hasRange: bool,
	slider:   bool,
	values:   []string, // enum
	elem:     string, // array: `of`
	class:    string, // resource (or an array of them): the class script
	local:    int, // resource: 0 the class's, 1 shared (local_copy = false), 2 per instance (true)
	label:    string,
	tooltip:  string,
	group:    string,
}

// Prop_EntryLua: the table entry, one line (no indent).
Prop_EntryLua :: proc(d: Prop_Def) -> string {
	sb := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&sb, "%s = {{ type = %q", d.name, d.kind)
	if d.kind == "enum" && len(d.values) > 0 {
		strings.write_string(&sb, ", values = {")
		for v, i in d.values {
			if i > 0 do strings.write_string(&sb, ", ")
			fmt.sbprintf(&sb, "%q", v)
		}
		strings.write_string(&sb, "}")
	}
	if d.kind == "array" && d.elem != "" do fmt.sbprintf(&sb, ", of = %q", d.elem)
	if d.class != "" do fmt.sbprintf(&sb, ", class = %q", d.class)
	if d.local == 1 do strings.write_string(&sb, ", local_copy = false")
	if d.local == 2 do strings.write_string(&sb, ", local_copy = true")
	if d.default != "" do fmt.sbprintf(&sb, ", default = %s", d.default)
	if d.hasRange do fmt.sbprintf(&sb, ", min = %v, max = %v", d.min, d.max)
	if d.slider && d.kind != "range" do strings.write_string(&sb, ", slider = true")
	if d.label != "" do fmt.sbprintf(&sb, ", label = %q", d.label)
	if d.tooltip != "" do fmt.sbprintf(&sb, ", tooltip = %q", d.tooltip)
	if d.group != "" do fmt.sbprintf(&sb, ", group = %q", d.group)
	strings.write_string(&sb, " },")
	return strings.to_string(sb)
}

// brace_delta: { minus } on a line, outside strings and -- comments.
@(private = "file")
brace_delta :: proc(line: string) -> int {
	d := 0
	quote: u8 = 0
	for i := 0; i < len(line); i += 1 {
		ch := line[i]
		if quote != 0 {
			if ch == '\\' do i += 1
			else if ch == quote do quote = 0
			continue
		}
		switch ch {
		case '"', '\'': quote = ch
		case '-': if i + 1 < len(line) && line[i + 1] == '-' do return d
		case '{': d += 1
		case '}': d -= 1
		}
	}
	return d
}

// props_table: the lines of `Cls.properties = {` and its closing brace.
@(private = "file")
props_table :: proc(lines: []string, cls: string) -> (open, close: int, ok: bool) {
	header := fmt.tprintf("%s.properties", cls)
	for l, i in lines {
		t := strings.trim_space(l)
		if !strings.has_prefix(t, header) || !strings.contains(t, "{") do continue
		depth := 0
		for j in i ..< len(lines) {
			depth += brace_delta(lines[j])
			if depth <= 0 do return i, j, true
		}
		return
	}
	return
}

// props_entry: an entry's first and last lines in the table.
@(private = "file")
props_entry :: proc(lines: []string, open, close: int, name: string) -> (first, last: int, ok: bool) {
	depth := 1
	for i in open + 1 ..< close {
		t := strings.trim_space(lines[i])
		if depth == 1 && (strings.has_prefix(t, fmt.tprintf("%s =", name)) || strings.has_prefix(t, fmt.tprintf("%s=", name))) {
			d := 0
			for j in i ..< close {
				d += brace_delta(lines[j])
				if d <= 0 do return i, j, true
			}
			return i, i, true
		}
		depth += brace_delta(lines[i])
	}
	return
}

@(private = "file")
indent_unit :: proc(lines: []string, open, close: int) -> string {
	for i in open + 1 ..< close {
		l := lines[i]
		t := strings.trim_left_space(l)
		if t != "" && len(t) < len(l) do return l[:len(l) - len(t)]
	}
	return "\t"
}

@(private = "file")
join :: proc(lines: []string) -> string {
	return strings.join(lines, "\n", context.temp_allocator)
}

// Prop_Upsert writes a property's entry: in place when it's there, else
// last in the table (made after `local Cls = {}` when missing).
Prop_Upsert :: proc(text, cls: string, d: Prop_Def) -> (string, bool) {
	lines := strings.split(text, "\n", context.temp_allocator)
	out := make([dynamic]string, context.temp_allocator)
	open, close, ok := props_table(lines, cls)
	if !ok {
		for l, i in lines {
			if strings.trim_space(l) != fmt.tprintf("local %s = {{}}", cls) do continue
			append(&out, ..lines[:i + 1])
			append(&out, "", fmt.tprintf("%s.properties = {{", cls), fmt.tprintf("\t%s", Prop_EntryLua(d)), "}")
			append(&out, ..lines[i + 1:])
			return join(out[:]), true
		}
		return text, false
	}
	entry := strings.concatenate({indent_unit(lines, open, close), Prop_EntryLua(d)}, context.temp_allocator)
	if first, last, has := props_entry(lines, open, close, d.name); has {
		append(&out, ..lines[:first])
		append(&out, entry)
		append(&out, ..lines[last + 1:])
		return join(out[:]), true
	}
	append(&out, ..lines[:close])
	append(&out, entry)
	append(&out, ..lines[close:])
	return join(out[:]), true
}

// Prop_Remove takes a property's entry out of the table.
Prop_Remove :: proc(text, cls, name: string) -> (string, bool) {
	lines := strings.split(text, "\n", context.temp_allocator)
	open, close, ok := props_table(lines, cls)
	if !ok do return text, false
	first, last, has := props_entry(lines, open, close, name)
	if !has do return text, false
	out := make([dynamic]string, context.temp_allocator)
	append(&out, ..lines[:first])
	append(&out, ..lines[last + 1:])
	return join(out[:]), true
}

// Prop_Uses: the lines (1-based) that use self.<name>.
Prop_Uses :: proc(text, name: string) -> []int {
	out := make([dynamic]int, context.temp_allocator)
	needle := fmt.tprintf("self.%s", name)
	for l, i in strings.split(text, "\n", context.temp_allocator) {
		rest := l
		for {
			k := strings.index(rest, needle)
			if k < 0 do break
			after := k + len(needle)
			if after >= len(rest) || !is_ident_char(rest[after]) {
				append(&out, i + 1)
				break
			}
			rest = rest[after:]
		}
	}
	return out[:]
}

@(private = "file")
is_ident_char :: proc(c: u8) -> bool {
	return c == '_' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
}

// Prop_Declared: the script's own table has the entry (else it's inherited
// from the script it extends).
Prop_Declared :: proc(text, cls, name: string) -> bool {
	lines := strings.split(text, "\n", context.temp_allocator)
	open, close, ok := props_table(lines, cls)
	if !ok do return false
	_, _, has := props_entry(lines, open, close, name)
	return has
}
