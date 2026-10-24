package engine

import "core:fmt"
import "core:mem"
import "core:strconv"
import "core:strings"
import "core:unicode/utf8"

// ============================================================================
// Order-preserving JSON tree with LDtk's own formatter
//
// The level editor saves .ldtk / .ldtkl files directly, so a load followed by
// a save must not lose or reorder anything (fields this engine does not know
// about included) and must write the bytes LDtk itself would write, which
// keeps version-control diffs small. LdtkJson keeps objects as ordered
// key / value lists and keeps the source text of numbers and strings; the
// writer is a port of deepnightLibs' dn.data.JsonPretty (the "Compact" and
// "Minified" levels LDtk uses), quirks included.
//
// Nodes are allocated with the allocator passed to the parser / builders
// (the document's arena), so the whole tree is freed at once.
// ============================================================================

LdtkJson_Kind :: enum u8 {
	Null,
	Bool,
	Number,
	String,
	Array,
	Object,
}

LdtkJson :: struct {
	kind:  LdtkJson_Kind,
	b:     bool,
	num:   f64,
	text:  string,           // String: decoded value
	raw:   string,           // Number: source text; String: source text between the quotes ("" = encode `text`)
	items: [dynamic]^LdtkJson, // Array elements / Object values
	keys:  [dynamic]string,    // Object keys, parallel to items
}

LdtkJson_Style :: enum u8 {
	Compact,  // LDtk's default (small arrays / objects on one line)
	Minified, // the project's "minifyJson" setting
	Full,     // every object / array expanded (the simplified export's data.json)
}

LDTK_JSON_HEADER_KEY :: "__header__"
@(private = "file") LDTK_JSON_MAX_LINE :: 85

// ----------------------------------------------------------------------------
// Building and reading
// ----------------------------------------------------------------------------

LdtkJson_New :: proc(kind: LdtkJson_Kind, a: mem.Allocator) -> ^LdtkJson {
	n := new(LdtkJson, a)
	n.kind = kind
	if kind == .Array || kind == .Object {
		n.items = make([dynamic]^LdtkJson, a)
		if kind == .Object do n.keys = make([dynamic]string, a)
	}
	return n
}

LdtkJson_NewInt :: proc(v: int, a: mem.Allocator) -> ^LdtkJson {
	n := LdtkJson_New(.Number, a)
	n.num = f64(v)
	return n
}

LdtkJson_NewFloat :: proc(v: f64, a: mem.Allocator) -> ^LdtkJson {
	n := LdtkJson_New(.Number, a)
	n.num = v
	return n
}

LdtkJson_NewBool :: proc(v: bool, a: mem.Allocator) -> ^LdtkJson {
	n := LdtkJson_New(.Bool, a)
	n.b = v
	return n
}

LdtkJson_NewString :: proc(s: string, a: mem.Allocator) -> ^LdtkJson {
	n := LdtkJson_New(.String, a)
	n.text = strings.clone(s, a)
	return n
}

// LdtkJson_Get returns the value of `key` (nil when absent or not an object).
LdtkJson_Get :: proc(o: ^LdtkJson, key: string) -> ^LdtkJson {
	if o == nil || o.kind != .Object do return nil
	for k, i in o.keys do if k == key do return o.items[i]
	return nil
}

LdtkJson_Index :: proc(o: ^LdtkJson, key: string) -> int {
	if o == nil || o.kind != .Object do return -1
	for k, i in o.keys do if k == key do return i
	return -1
}

// LdtkJson_Set replaces the value of `key`, or appends the key.
LdtkJson_Set :: proc(o: ^LdtkJson, key: string, v: ^LdtkJson, a: mem.Allocator) {
	if o == nil || o.kind != .Object do return
	if i := LdtkJson_Index(o, key); i >= 0 {
		o.items[i] = v
		return
	}
	append(&o.keys, strings.clone(key, a))
	append(&o.items, v)
}

LdtkJson_Remove :: proc(o: ^LdtkJson, key: string) {
	if i := LdtkJson_Index(o, key); i >= 0 {
		ordered_remove(&o.keys, i)
		ordered_remove(&o.items, i)
	}
}

LdtkJson_Int :: proc(o: ^LdtkJson, key: string, def := 0) -> int {
	v := LdtkJson_Get(o, key)
	if v == nil || v.kind != .Number do return def
	return int(v.num)
}

LdtkJson_Float :: proc(o: ^LdtkJson, key: string, def := 0.0) -> f64 {
	v := LdtkJson_Get(o, key)
	if v == nil || v.kind != .Number do return def
	return v.num
}

LdtkJson_Bool :: proc(o: ^LdtkJson, key: string, def := false) -> bool {
	v := LdtkJson_Get(o, key)
	if v == nil || v.kind != .Bool do return def
	return v.b
}

LdtkJson_Str :: proc(o: ^LdtkJson, key: string, def := "") -> string {
	v := LdtkJson_Get(o, key)
	if v == nil || v.kind != .String do return def
	return v.text
}

// LdtkJson_IsNull: absent or null.
LdtkJson_IsNull :: proc(o: ^LdtkJson, key: string) -> bool {
	v := LdtkJson_Get(o, key)
	return v == nil || v.kind == .Null
}

LdtkJson_Arr :: proc(o: ^LdtkJson, key: string) -> []^LdtkJson {
	v := LdtkJson_Get(o, key)
	if v == nil || v.kind != .Array do return nil
	return v.items[:]
}

// Setters that keep the existing node when the value is unchanged (so the
// source text of untouched numbers survives).
LdtkJson_SetInt :: proc(o: ^LdtkJson, key: string, v: int, a: mem.Allocator) {
	if cur := LdtkJson_Get(o, key); cur != nil && cur.kind == .Number && cur.num == f64(v) do return
	LdtkJson_Set(o, key, LdtkJson_NewInt(v, a), a)
}

LdtkJson_SetFloat :: proc(o: ^LdtkJson, key: string, v: f64, a: mem.Allocator) {
	if cur := LdtkJson_Get(o, key); cur != nil && cur.kind == .Number && cur.num == v do return
	LdtkJson_Set(o, key, LdtkJson_NewFloat(v, a), a)
}

LdtkJson_SetBool :: proc(o: ^LdtkJson, key: string, v: bool, a: mem.Allocator) {
	if cur := LdtkJson_Get(o, key); cur != nil && cur.kind == .Bool && cur.b == v do return
	LdtkJson_Set(o, key, LdtkJson_NewBool(v, a), a)
}

LdtkJson_SetStr :: proc(o: ^LdtkJson, key: string, v: string, a: mem.Allocator) {
	if cur := LdtkJson_Get(o, key); cur != nil && cur.kind == .String && cur.text == v do return
	LdtkJson_Set(o, key, LdtkJson_NewString(v, a), a)
}

LdtkJson_SetNull :: proc(o: ^LdtkJson, key: string, a: mem.Allocator) {
	if cur := LdtkJson_Get(o, key); cur != nil && cur.kind == .Null do return
	LdtkJson_Set(o, key, LdtkJson_New(.Null, a), a)
}

// LdtkJson_Clone deep-copies a tree into `a`.
LdtkJson_Clone :: proc(n: ^LdtkJson, a: mem.Allocator) -> ^LdtkJson {
	if n == nil do return nil
	c := LdtkJson_New(n.kind, a)
	c.b, c.num = n.b, n.num
	c.text = strings.clone(n.text, a)
	c.raw = strings.clone(n.raw, a)
	for it in n.items do append(&c.items, LdtkJson_Clone(it, a))
	for k in n.keys do append(&c.keys, strings.clone(k, a))
	return c
}

// ----------------------------------------------------------------------------
// Parsing
// ----------------------------------------------------------------------------

@(private = "file")
Ljp :: struct {
	src: string,
	pos: int,
	a:   mem.Allocator,
	ok:  bool,
}

// LdtkJson_Parse parses `src` into a tree allocated with `a`. Strings and
// numbers point into copies made with `a`, so `src` may be freed afterwards.
LdtkJson_Parse :: proc(src: string, a: mem.Allocator) -> (^LdtkJson, bool) {
	p := Ljp{src = src, a = a, ok = true}
	if strings.has_prefix(p.src, "\xEF\xBB\xBF") do p.pos = 3
	v := ljp_value(&p, 0)
	ljp_ws(&p)
	if !p.ok || v == nil || p.pos != len(p.src) do return nil, false
	return v, true
}

@(private = "file")
ljp_ws :: proc(p: ^Ljp) {
	for p.pos < len(p.src) {
		switch p.src[p.pos] {
		case ' ', '\t', '\n', '\r': p.pos += 1
		case: return
		}
	}
}

@(private = "file")
ljp_value :: proc(p: ^Ljp, depth: int) -> ^LdtkJson {
	ljp_ws(p)
	if p.pos >= len(p.src) || depth > 512 {
		p.ok = false
		return nil
	}
	c := p.src[p.pos]
	switch {
	case c == '{':
		p.pos += 1
		o := LdtkJson_New(.Object, p.a)
		ljp_ws(p)
		if p.pos < len(p.src) && p.src[p.pos] == '}' {
			p.pos += 1
			return o
		}
		for p.ok {
			ljp_ws(p)
			if p.pos >= len(p.src) || p.src[p.pos] != '"' {
				p.ok = false
				return nil
			}
			k, _, kok := ljp_string(p)
			if !kok {
				p.ok = false
				return nil
			}
			ljp_ws(p)
			if p.pos >= len(p.src) || p.src[p.pos] != ':' {
				p.ok = false
				return nil
			}
			p.pos += 1
			v := ljp_value(p, depth + 1)
			if !p.ok do return nil
			append(&o.keys, k)
			append(&o.items, v)
			ljp_ws(p)
			if p.pos >= len(p.src) {
				p.ok = false
				return nil
			}
			if p.src[p.pos] == ',' {
				p.pos += 1
				continue
			}
			if p.src[p.pos] == '}' {
				p.pos += 1
				return o
			}
			p.ok = false
		}
		return nil
	case c == '[':
		p.pos += 1
		arr := LdtkJson_New(.Array, p.a)
		ljp_ws(p)
		if p.pos < len(p.src) && p.src[p.pos] == ']' {
			p.pos += 1
			return arr
		}
		for p.ok {
			v := ljp_value(p, depth + 1)
			if !p.ok do return nil
			append(&arr.items, v)
			ljp_ws(p)
			if p.pos >= len(p.src) {
				p.ok = false
				return nil
			}
			if p.src[p.pos] == ',' {
				p.pos += 1
				continue
			}
			if p.src[p.pos] == ']' {
				p.pos += 1
				return arr
			}
			p.ok = false
		}
		return nil
	case c == '"':
		s, raw, sok := ljp_string(p)
		if !sok {
			p.ok = false
			return nil
		}
		n := LdtkJson_New(.String, p.a)
		n.text, n.raw = s, raw
		return n
	case c == 't' && strings.has_prefix(p.src[p.pos:], "true"):
		p.pos += 4
		return LdtkJson_NewBool(true, p.a)
	case c == 'f' && strings.has_prefix(p.src[p.pos:], "false"):
		p.pos += 5
		return LdtkJson_NewBool(false, p.a)
	case c == 'n' && strings.has_prefix(p.src[p.pos:], "null"):
		p.pos += 4
		return LdtkJson_New(.Null, p.a)
	case c == '-' || (c >= '0' && c <= '9'):
		start := p.pos
		p.pos += 1
		for p.pos < len(p.src) {
			d := p.src[p.pos]
			if (d >= '0' && d <= '9') || d == '.' || d == 'e' || d == 'E' || d == '+' || d == '-' {
				p.pos += 1
			} else do break
		}
		text := p.src[start:p.pos]
		v, vok := strconv.parse_f64(text)
		if !vok {
			p.ok = false
			return nil
		}
		n := LdtkJson_New(.Number, p.a)
		n.num = v
		n.raw = strings.clone(text, p.a)
		return n
	}
	p.ok = false
	return nil
}

// ljp_string reads a quoted string at p.pos: (decoded, raw source between
// the quotes, ok).
@(private = "file")
ljp_string :: proc(p: ^Ljp) -> (string, string, bool) {
	p.pos += 1 // opening quote
	start := p.pos
	escaped := false
	for p.pos < len(p.src) {
		c := p.src[p.pos]
		if c == '\\' {
			escaped = true
			p.pos += 2
			continue
		}
		if c == '"' do break
		p.pos += 1
	}
	if p.pos >= len(p.src) do return "", "", false
	raw := p.src[start:p.pos]
	p.pos += 1 // closing quote
	rawCopy := strings.clone(raw, p.a)
	if !escaped do return rawCopy, rawCopy, true
	b := strings.builder_make(0, len(raw), p.a)
	i := 0
	for i < len(raw) {
		c := raw[i]
		if c != '\\' || i + 1 >= len(raw) {
			strings.write_byte(&b, c)
			i += 1
			continue
		}
		e := raw[i + 1]
		i += 2
		switch e {
		case 'n': strings.write_byte(&b, '\n')
		case 't': strings.write_byte(&b, '\t')
		case 'r': strings.write_byte(&b, '\r')
		case 'b': strings.write_byte(&b, '\b')
		case 'f': strings.write_byte(&b, '\f')
		case 'u':
			if i + 4 > len(raw) do return "", "", false
			cp, ok := strconv.parse_u64(raw[i:i + 4], 16)
			if !ok do return "", "", false
			i += 4
			r := rune(cp)
			// surrogate pair
			if r >= 0xD800 && r < 0xDC00 && i + 6 <= len(raw) && raw[i] == '\\' && raw[i + 1] == 'u' {
				lo, lok := strconv.parse_u64(raw[i + 2:i + 6], 16)
				if lok && lo >= 0xDC00 && lo < 0xE000 {
					r = 0x10000 + ((r - 0xD800) << 10) + (rune(lo) - 0xDC00)
					i += 6
				}
			}
			strings.write_rune(&b, r)
		case: strings.write_byte(&b, e) // \" \\ \/
		}
	}
	return strings.to_string(b), rawCopy, true
}

// ----------------------------------------------------------------------------
// Writing (port of dn.data.JsonPretty, Compact and Minified levels)
// ----------------------------------------------------------------------------

@(private = "file")
Ljw :: struct {
	b:      ^strings.Builder,
	style:  LdtkJson_Style,
	indent: int,
}

// LdtkJson_Write appends the formatted tree to `b`.
LdtkJson_Write :: proc(b: ^strings.Builder, root: ^LdtkJson, style := LdtkJson_Style.Compact) {
	w := Ljw{b = b, style = style}
	// JsonPretty writes the header object first and forces the root onto
	// several lines while it is pending.
	ljw_value(&w, "", false, root, false, LdtkJson_Index(root, LDTK_JSON_HEADER_KEY) >= 0)
}

LdtkJson_ToString :: proc(root: ^LdtkJson, style := LdtkJson_Style.Compact, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	LdtkJson_Write(&b, root, style)
	return strings.to_string(b)
}

// JS's Type.typeof: integral values inside the 32-bit range are TInt.
@(private = "file")
ljw_is_int :: proc(n: ^LdtkJson) -> bool {
	return n.num == f64(i64(n.num)) && n.num >= -2147483648 && n.num <= 2147483647
}

@(private = "file")
ljw_utf16_len :: proc(s: string) -> int {
	n := 0
	for r in s do n += r > 0xFFFF ? 2 : 1
	return n
}

@(private = "file")
ljw_eval_len :: proc(n: ^LdtkJson, depth: int) -> int {
	switch n.kind {
	case .Null: return 4
	case .Bool: return n.b ? 4 : 5
	case .Number: return ljw_is_int(n) ? 4 : 5
	case .String: return ljw_utf16_len(n.text) + 2
	case .Object:
		if depth <= 0 && len(n.keys) <= 5 {
			l := 0
			for it in n.items do l += ljw_eval_len(it, depth + 1)
			return l
		}
		return len(n.keys) * 10
	case .Array:
		if len(n.items) == 0 do return 2
		if len(n.items) < 50 && n.items[0].kind == .Number do return len(n.items)
		if len(n.items) > 5 || depth > 0 do return 99
		l := 0
		for it in n.items do l += ljw_eval_len(it, depth + 1)
		return l
	}
	return 1
}

@(private = "file")
ljw_tab :: proc(w: ^Ljw) {
	if w.style == .Minified do return
	for _ in 0 ..< w.indent do strings.write_byte(w.b, '\t')
}

@(private = "file")
ljw_nl :: proc(w: ^Ljw) {
	if w.style != .Minified do strings.write_byte(w.b, '\n')
}

@(private = "file")
ljw_name :: proc(w: ^Ljw, name: string) {
	strings.write_byte(w.b, '"')
	strings.write_string(w.b, name)
	strings.write_string(w.b, w.style == .Minified ? "\":" : "\": ")
}

// ljw_number: JS Number.toString for values we created; source text kept
// for parsed ones.
@(private = "file")
ljw_number :: proc(w: ^Ljw, n: ^LdtkJson) {
	if n.raw != "" {
		strings.write_string(w.b, n.raw)
		return
	}
	if n.num == f64(i64(n.num)) && abs(n.num) < 1e21 {
		strings.write_i64(w.b, i64(n.num))
		return
	}
	ldtk_js_number(w.b, n.num)
}

// ldtk_js_number writes `v` like JavaScript's Number.toString: the shortest
// digits that read back as `v`, in decimal notation for 1e-7 <= |v| < 1e21.
ldtk_js_number :: proc(b: ^strings.Builder, v: f64) {
	if v != v {
		strings.write_string(b, "NaN")
		return
	}
	if v == 0 {
		strings.write_byte(b, '0')
		return
	}
	buf: [64]u8
	digits: [32]u8
	nd, exp := 0, 0
	for prec in 1 ..= 17 {
		s := strconv.write_float(buf[:], v, 'e', prec - 1, 64) // [+-]d.ddde[+-]xx
		back, _ := strconv.parse_f64(s)
		if back != v && prec < 17 do continue
		nd = 0
		i := 0
		if s[0] == '+' || s[0] == '-' do i = 1
		for ; i < len(s) && s[i] != 'e' && s[i] != 'E'; i += 1 {
			if s[i] != '.' {
				digits[nd] = s[i]
				nd += 1
			}
		}
		e, _ := strconv.parse_int(s[i + 1:])
		exp = e
		break
	}
	for nd > 1 && digits[nd - 1] == '0' do nd -= 1
	if v < 0 do strings.write_byte(b, '-')
	// value = 0.d1d2... * 10^(exp+1)
	k := exp + 1
	if k > 21 || k < -5 {
		strings.write_byte(b, digits[0])
		if nd > 1 {
			strings.write_byte(b, '.')
			strings.write_bytes(b, digits[1:nd])
		}
		strings.write_string(b, exp >= 0 ? "e+" : "e-")
		strings.write_int(b, abs(exp))
		return
	}
	if k <= 0 {
		strings.write_string(b, "0.")
		for _ in 0 ..< -k do strings.write_byte(b, '0')
		strings.write_bytes(b, digits[:nd])
	} else if k >= nd {
		strings.write_bytes(b, digits[:nd])
		for _ in 0 ..< k - nd do strings.write_byte(b, '0')
	} else {
		strings.write_bytes(b, digits[:k])
		strings.write_byte(b, '.')
		strings.write_bytes(b, digits[k:nd])
	}
}

@(private = "file")
ljw_string :: proc(w: ^Ljw, n: ^LdtkJson) {
	strings.write_byte(w.b, '"')
	if n.raw != "" || n.text == "" {
		strings.write_string(w.b, n.raw)
	} else {
		// JsonPretty: line breaks and tabs become spaces, \r is dropped,
		// quotes are escaped. Backslashes and other control characters are
		// escaped too (JsonPretty leaves them raw, which is not valid JSON).
		for r in n.text {
			switch r {
			case '\n', '\t': strings.write_byte(w.b, ' ')
			case '\r':
			case '"': strings.write_string(w.b, "\\\"")
			case '\\': strings.write_string(w.b, "\\\\")
			case 0 ..< 0x20: fmt.sbprintf(w.b, "\\u%04x", int(r))
			case:
				bytes, cnt := utf8.encode_rune(r)
				strings.write_bytes(w.b, bytes[:cnt])
			}
		}
	}
	strings.write_byte(w.b, '"')
}

@(private = "file")
ljw_value :: proc(w: ^Ljw, name: string, named: bool, n: ^LdtkJson, force: bool, header := false) {
	force := force || (named && name == LDTK_JSON_HEADER_KEY)
	switch n.kind {
	case .Null, .Bool, .Number, .String:
		if named do ljw_name(w, name)
		switch n.kind {
		case .Null: strings.write_string(w.b, "null")
		case .Bool: strings.write_string(w.b, n.b ? "true" : "false")
		case .Number: ljw_number(w, n)
		case .String: ljw_string(w, n)
		case .Array, .Object:
		}
	case .Object: ljw_object(w, name, named, n, force, header)
	case .Array: ljw_array(w, name, named, n, force)
	}
}

@(private = "file")
ljw_object :: proc(w: ^Ljw, name: string, named: bool, n: ^LdtkJson, force: bool, header: bool) {
	if len(n.keys) == 0 {
		if named {
			strings.write_byte(w.b, '"')
			strings.write_string(w.b, name)
			strings.write_string(w.b, "\" : {}")
		} else do strings.write_string(w.b, "{}")
		return
	}
	l := w.style == .Compact ? ljw_eval_len(n, 0) : w.style == .Full ? max(int) : 0
	if named do ljw_name(w, name)
	space := w.style == .Minified ? "" : " "
	if l <= LDTK_JSON_MAX_LINE && !header && !force {
		strings.write_byte(w.b, '{')
		strings.write_string(w.b, space)
		for k, i in n.keys {
			ljw_value(w, k, true, n.items[i], false)
			if i < len(n.keys) - 1 {
				strings.write_byte(w.b, ',')
				strings.write_string(w.b, space)
			}
		}
		strings.write_string(w.b, space)
		strings.write_byte(w.b, '}')
		return
	}
	strings.write_byte(w.b, '{')
	ljw_nl(w)
	w.indent += 1
	for k, i in n.keys {
		ljw_tab(w)
		ljw_value(w, k, true, n.items[i], false)
		if i < len(n.keys) - 1 {
			strings.write_byte(w.b, ',')
			ljw_nl(w)
		}
	}
	w.indent -= 1
	ljw_nl(w)
	ljw_tab(w)
	strings.write_byte(w.b, '}')
}

@(private = "file")
ljw_array :: proc(w: ^Ljw, name: string, named: bool, n: ^LdtkJson, force: bool) {
	if len(n.items) == 0 {
		if named do ljw_name(w, name)
		strings.write_string(w.b, "[]")
		return
	}
	l := w.style == .Compact ? ljw_eval_len(n, 0) : w.style == .Full ? max(int) : 0
	if named do ljw_name(w, name)
	first := n.items[0].kind
	if w.style != .Minified && first == .Number && !force && len(n.items) > LDTK_JSON_MAX_LINE {
		// Number grid, 35 per line (CSV data)
		strings.write_byte(w.b, '[')
		ljw_nl(w)
		w.indent += 1
		ljw_tab(w)
		lineLimit := 0
		for it, i in n.items {
			ljw_value(w, "", false, it, false)
			if i < len(n.items) - 1 do strings.write_byte(w.b, ',')
			lineLimit += 1
			if lineLimit >= 35 {
				ljw_nl(w)
				ljw_tab(w)
				lineLimit = 0
			}
		}
		w.indent -= 1
		ljw_nl(w)
		ljw_tab(w)
		strings.write_byte(w.b, ']')
		return
	}
	if l <= LDTK_JSON_MAX_LINE && !force {
		space := w.style == .Minified ? "" : " "
		arraySpace: string
		#partial switch first {
		case .Number: arraySpace = ""
		case .Bool: arraySpace = len(n.items) > 5 ? "" : space
		case: arraySpace = len(n.items) == 1 ? "" : space
		}
		strings.write_byte(w.b, '[')
		strings.write_string(w.b, arraySpace)
		for it, i in n.items {
			ljw_value(w, "", false, it, false)
			if i < len(n.items) - 1 {
				strings.write_byte(w.b, ',')
				strings.write_string(w.b, arraySpace)
			}
		}
		strings.write_string(w.b, arraySpace)
		strings.write_byte(w.b, ']')
		return
	}
	strings.write_byte(w.b, '[')
	ljw_nl(w)
	w.indent += 1
	for it, i in n.items {
		ljw_tab(w)
		ljw_value(w, "", false, it, false)
		if i < len(n.items) - 1 {
			strings.write_byte(w.b, ',')
			ljw_nl(w)
		}
	}
	w.indent -= 1
	ljw_nl(w)
	ljw_tab(w)
	strings.write_byte(w.b, ']')
}
