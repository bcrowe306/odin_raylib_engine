// Lua 5.4 line tokenizer: keywords, constants, numbers (incl. hex/exponents),
// quoted and long-bracket strings ([[ ]], [==[ ]==]), line and long
// comments (--, --[[ ]]), function names and calls, fields after . and :,
// operators. Multi-line long strings/comments carry their bracket level
// in the line state.
package syntax

import "core:mem"
import "core:strings"

LUA_STATE_NORMAL :: 0
// 100 + level: inside a long comment; 200 + level: inside a long string.
LUA_STATE_LONG_COMMENT :: 100
LUA_STATE_LONG_STRING :: 200

lua_language :: proc() -> Language {
	return Language{name = "lua", tokenize = tokenize_lua_line, line_comment = "--"}
}

// language_for_path picks a language by file extension (Odin otherwise).
language_for_path :: proc(path: string) -> Language {
	if strings.has_suffix(strings.to_lower(path, context.temp_allocator), ".lua") do return lua_language()
	return odin_language()
}

@(private = "file")
is_lua_keyword :: proc(w: string) -> bool {
	switch w {
	case "and", "break", "do", "else", "elseif", "end", "for", "function", "goto", "if",
	     "in", "local", "not", "or", "repeat", "return", "then", "until", "while":
		return true
	}
	return false
}

@(private = "file")
is_lua_builtin :: proc(w: string) -> bool {
	switch w {
	// Engine globals (see engine/definitions/engine_api.lua)
	case "Engine", "Input", "Audio", "Camera", "Physics", "Scene", "Log", "Project", "self",
	// Lua standard library
	     "print", "pairs", "ipairs", "next", "select", "type", "tostring", "tonumber",
	     "setmetatable", "getmetatable", "rawget", "rawset", "rawequal", "rawlen",
	     "require", "error", "assert", "pcall", "xpcall", "unpack",
	     "table", "string", "math", "os", "io", "coroutine", "utf8", "debug", "_G", "_ENV":
		return true
	}
	return false
}

@(private = "file")
is_ident_start :: proc(c: u8) -> bool {
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' || c >= 0x80
}

@(private = "file")
is_ident_char :: proc(c: u8) -> bool {
	return is_ident_start(c) || (c >= '0' && c <= '9')
}

// long_bracket_level: at line[i] == '[', returns the level of "[==[" (or -1).
@(private = "file")
long_bracket_level :: proc(line: string, i: int) -> int {
	if i >= len(line) || line[i] != '[' do return -1
	j := i + 1
	level := 0
	for j < len(line) && line[j] == '=' {
		level += 1
		j += 1
	}
	if j < len(line) && line[j] == '[' do return level
	return -1
}

// find_long_close finds the end (exclusive) of "]==]" of `level` from i.
@(private = "file")
find_long_close :: proc(line: string, i: int, level: int) -> int {
	for k := i; k < len(line); k += 1 {
		if line[k] != ']' do continue
		j := k + 1
		n := 0
		for j < len(line) && line[j] == '=' {
			n += 1
			j += 1
		}
		if n == level && j < len(line) && line[j] == ']' do return j + 1
	}
	return -1
}

tokenize_lua_line :: proc(line: string, state_in: int, allocator: mem.Allocator) -> (tokens: []Token, state_out: int) {
	out := make([dynamic]Token, allocator)
	i := 0
	state_out = LUA_STATE_NORMAL

	// Continue a long comment/string from the previous line.
	if state_in >= LUA_STATE_LONG_COMMENT {
		isComment := state_in < LUA_STATE_LONG_STRING
		level := state_in - (LUA_STATE_LONG_COMMENT if isComment else LUA_STATE_LONG_STRING)
		end := find_long_close(line, 0, level)
		kind := TokenKind.Comment if isComment else TokenKind.String
		if end < 0 {
			if len(line) > 0 do append(&out, Token{kind, 0, len(line)})
			return out[:], state_in
		}
		append(&out, Token{kind, 0, end})
		i = end
	}

	prevSignificant := ""
	for i < len(line) {
		c := line[i]
		switch {
		case c == ' ' || c == '\t' || c == '\r':
			i += 1
			continue // whitespace doesn't end "function name" / "a . b" context

		case c == '-' && i + 1 < len(line) && line[i + 1] == '-':
			// Comment: long (--[[ ]]) or to end of line.
			if level := long_bracket_level(line, i + 2); level >= 0 {
				end := find_long_close(line, i + 2 + level + 2, level)
				if end < 0 {
					append(&out, Token{.Comment, i, len(line)})
					return out[:], LUA_STATE_LONG_COMMENT + level
				}
				append(&out, Token{.Comment, i, end})
				i = end
			} else {
				append(&out, Token{.Comment, i, len(line)})
				i = len(line)
			}

		case c == '[' && long_bracket_level(line, i) >= 0:
			level := long_bracket_level(line, i)
			end := find_long_close(line, i + level + 2, level)
			if end < 0 {
				append(&out, Token{.String, i, len(line)})
				return out[:], LUA_STATE_LONG_STRING + level
			}
			append(&out, Token{.String, i, end})
			i = end

		case c == '"' || c == '\'':
			j := i + 1
			for j < len(line) && line[j] != c {
				if line[j] == '\\' do j += 1
				j += 1
			}
			end := min(j + 1, len(line))
			append(&out, Token{.String, i, end})
			i = end

		case (c >= '0' && c <= '9') || (c == '.' && i + 1 < len(line) && line[i + 1] >= '0' && line[i + 1] <= '9'):
			j := i
			if c == '0' && i + 1 < len(line) && (line[i + 1] == 'x' || line[i + 1] == 'X') {
				j += 2
				for j < len(line) && (is_ident_char(line[j]) || line[j] == '.') do j += 1
			} else {
				for j < len(line) {
					ch := line[j]
					if (ch >= '0' && ch <= '9') || ch == '.' || ch == 'e' || ch == 'E' {
						j += 1
					} else if (ch == '-' || ch == '+') && j > i && (line[j - 1] == 'e' || line[j - 1] == 'E') {
						j += 1
					} else {
						break
					}
				}
			}
			append(&out, Token{.Number, i, j})
			i = j

		case is_ident_start(c):
			j := i
			for j < len(line) && is_ident_char(line[j]) do j += 1
			word := line[i:j]
			// Next non-space character decides calls.
			k := j
			for k < len(line) && (line[k] == ' ' || line[k] == '\t') do k += 1
			isCall := k < len(line) && (line[k] == '(' || line[k] == '{' || line[k] == '"' || line[k] == '\'')
			kind := TokenKind.Identifier
			switch {
			case is_lua_keyword(word): kind = .Keyword
			case word == "true" || word == "false" || word == "nil": kind = .Constant
			case prevSignificant == "function": kind = .Function
			case prevSignificant == "." || prevSignificant == ":":
				kind = .Function if isCall else .Property
			case isCall: kind = .Function
			case is_lua_builtin(word): kind = .Builtin
			}
			append(&out, Token{kind, i, j})
			prevSignificant = word
			i = j
			continue

		case:
			// Operators / punctuation (longest first).
			ops := [?]string{"...", "..", "==", "~=", "<=", ">=", "<<", ">>", "//", "::"}
			matched := false
			for op in ops {
				if strings.has_prefix(line[i:], op) {
					append(&out, Token{.Operator, i, i + len(op)})
					prevSignificant = op
					i += len(op)
					matched = true
					break
				}
			}
			if matched do continue
			kind := TokenKind.Operator
			switch c {
			case '(', ')', '{', '}', '[', ']', ';', ',': kind = .Punctuation
			case '.', ':': kind = .Punctuation
			}
			append(&out, Token{kind, i, i + 1})
			prevSignificant = line[i:i + 1]
			i += 1
			continue
		}
		prevSignificant = "" // after a string, number or comment
	}
	return out[:], state_out
}
