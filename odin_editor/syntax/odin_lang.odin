// Odin-language line tokenizer: keywords, identifiers, builtins, numbers,
// strings (quoted + raw backtick), rune literals, line/block comments, and
// operators/punctuation.
package syntax

import "core:mem"

ODIN_STATE_NORMAL :: 0
ODIN_STATE_BLOCK_COMMENT :: 1

@(private)
is_odin_keyword :: proc(word: string) -> bool {
	switch word {
	case "package", "import", "foreign",
	     "proc", "struct", "enum", "union",
	     "bit_set", "bit_field", "map", "dynamic",
	     "distinct", "using", "defer",
	     "if", "else", "when", "for",
	     "switch", "case", "fallthrough",
	     "return", "break", "continue",
	     "in", "not_in", "do",
	     "cast", "transmute", "auto_cast",
	     "or_else", "or_return", "or_break", "or_continue",
	     "const", "context", "typeid",
	     "true", "false", "nil":
		return true
	}
	return false
}

@(private)
is_odin_builtin_type :: proc(word: string) -> bool {
	switch word {
	case "int", "uint", "i8", "i16", "i32", "i64", "i128",
	     "u8", "u16", "u32", "u64", "u128",
	     "f16", "f32", "f64",
	     "bool", "b8", "b16", "b32", "b64",
	     "string", "cstring", "rune", "byte",
	     "rawptr", "any", "uintptr",
	     "quaternion64", "quaternion128", "quaternion256",
	     "complex32", "complex64", "complex128":
		return true
	}
	return false
}

@(private)
is_ident_start :: proc(ch: u8) -> bool {
	return (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch == '_'
}

@(private)
is_ident_cont :: proc(ch: u8) -> bool {
	return is_ident_start(ch) || (ch >= '0' && ch <= '9')
}

@(private)
is_digit :: proc(ch: u8) -> bool {
	return ch >= '0' && ch <= '9'
}

// tokenize_odin_line implements the `LineTokenizer` signature for Odin
// source. `state_in`/returned `state_out` track whether the line starts (or
// ends) inside an unterminated `/* ... */` block comment.
tokenize_odin_line :: proc(line: string, state_in: int, allocator: mem.Allocator) -> (tokens: []Token, state_out: int) {
	out := make([dynamic]Token, 0, 16, allocator)
	i := 0
	n := len(line)
	state := state_in

	if state == ODIN_STATE_BLOCK_COMMENT {
		start := 0
		for i < n {
			if i + 1 < n && line[i] == '*' && line[i + 1] == '/' {
				i += 2
				append(&out, Token{.Comment, start, i})
				state = ODIN_STATE_NORMAL
				break
			}
			i += 1
		}
		if state == ODIN_STATE_BLOCK_COMMENT {
			append(&out, Token{.Comment, start, n})
			return out[:], state
		}
	}

	for i < n {
		ch := line[i]

		if ch == ' ' || ch == '\t' {
			i += 1
			continue
		}

		// Line comment.
		if ch == '/' && i + 1 < n && line[i + 1] == '/' {
			append(&out, Token{.Comment, i, n})
			i = n
			break
		}

		// Block comment start.
		if ch == '/' && i + 1 < n && line[i + 1] == '*' {
			start := i
			i += 2
			closed := false
			for i < n {
				if i + 1 < n && line[i] == '*' && line[i + 1] == '/' {
					i += 2
					closed = true
					break
				}
				i += 1
			}
			append(&out, Token{.Comment, start, i})
			if !closed {
				state = ODIN_STATE_BLOCK_COMMENT
			}
			continue
		}

		// Quoted string.
		if ch == '"' {
			start := i
			i += 1
			for i < n {
				if line[i] == '\\' && i + 1 < n {
					i += 2
					continue
				}
				if line[i] == '"' {
					i += 1
					break
				}
				i += 1
			}
			append(&out, Token{.String, start, i})
			continue
		}

		// Raw backtick string.
		if ch == '`' {
			start := i
			i += 1
			for i < n && line[i] != '`' {
				i += 1
			}
			if i < n {
				i += 1
			}
			append(&out, Token{.String, start, i})
			continue
		}

		// Rune literal.
		if ch == '\'' {
			start := i
			i += 1
			for i < n {
				if line[i] == '\\' && i + 1 < n {
					i += 2
					continue
				}
				if line[i] == '\'' {
					i += 1
					break
				}
				i += 1
			}
			append(&out, Token{.String, start, i})
			continue
		}

		// Number literal.
		if is_digit(ch) {
			start := i
			for i < n && (is_digit(line[i]) || line[i] == '.' || line[i] == '_' ||
				line[i] == 'x' || line[i] == 'b' || line[i] == 'o' ||
				(line[i] >= 'a' && line[i] <= 'f') || (line[i] >= 'A' && line[i] <= 'F')) {
				i += 1
			}
			append(&out, Token{.Number, start, i})
			continue
		}

		// Identifier / keyword / builtin type.
		if is_ident_start(ch) {
			start := i
			for i < n && is_ident_cont(line[i]) {
				i += 1
			}
			word := line[start:i]
			kind := TokenKind.Identifier
			if is_odin_keyword(word) {
				kind = .Keyword
			} else if is_odin_builtin_type(word) {
				kind = .Type
			}
			append(&out, Token{kind, start, i})
			continue
		}

		// Operators / punctuation: emit as single- or (for common 2-char
		// operators) double-byte tokens.
		two := i + 1 < n ? line[i:i + 2] : ""
		switch two {
		case "::", ":=", "->", "==", "!=", "<=", ">=", "&&", "||", "+=", "-=",
		     "*=", "/=", "%=", "..", "<<", ">>":
			append(&out, Token{.Operator, i, i + 2})
			i += 2
			continue
		}

		switch ch {
		case '(', ')', '[', ']', '{', '}', ',', ';':
			append(&out, Token{.Punctuation, i, i + 1})
		case:
			append(&out, Token{.Operator, i, i + 1})
		}
		i += 1
	}

	return out[:], state
}

odin_language :: proc() -> Language {
	return Language{name = "odin", tokenize = tokenize_odin_line}
}
