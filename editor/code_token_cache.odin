package editor

import "core:hash"
import "core:time"
import syn "../odin_editor/syntax"

// ============================================================================
// Per-line token cache for the Code tab. A line's tokens depend only on its
// text and the tokenizer state it starts in, so they are cached by
// (hash of the text, start state): after an edit, recomputing the line
// states only hashes the unchanged lines (and finds them again when lines
// above were inserted or deleted), and drawing reuses the tokens instead of
// tokenizing every visible line every frame. Measured on a 10k-line file:
// see GAPS.md (Performance).
// ============================================================================

Token_Line :: struct {
	tokens:   []syn.Token, // heap (freed with the entry)
	endState: int,
	used:     int, // buffer version the entry was last used at
}

Token_Cache :: struct {
	entries: map[u64]Token_Line,
	lastUpdateMs: f64, // the last line-state pass (drives, perf)
	tokenized:    int, // lines actually tokenized by it
}

@(private = "file")
line_key :: proc(text: string, state: int) -> u64 {
	return hash.fnv64a(transmute([]u8)text) ~ (u64(state) * 0x9E3779B97F4A7C15)
}

// Token_CacheGet: the tokens and end state of a line starting in `state`.
Token_CacheGet :: proc(c: ^Token_Cache, lang: syn.Language, text: string, state, version: int) -> ([]syn.Token, int) {
	key := line_key(text, state)
	if e, ok := &c.entries[key]; ok {
		e.used = version
		return e.tokens, e.endState
	}
	toks, endState := lang.tokenize(text, state, context.temp_allocator)
	c.entries[key] = {tokens = clone_tokens(toks), endState = endState, used = version}
	c.tokenized += 1
	return c.entries[key].tokens, endState
}

@(private = "file")
clone_tokens :: proc(t: []syn.Token) -> []syn.Token {
	if len(t) == 0 do return nil
	out := make([]syn.Token, len(t))
	copy(out, t)
	return out
}

// Token_CachePrune drops entries no line used since `version` (when the
// cache has grown well past the line count).
Token_CachePrune :: proc(c: ^Token_Cache, lines, version: int) {
	if len(c.entries) <= 2 * lines + 256 do return
	stale := make([dynamic]u64, context.temp_allocator)
	for k, e in c.entries do if e.used < version do append(&stale, k)
	for k in stale {
		delete(c.entries[k].tokens)
		delete_key(&c.entries, k)
	}
}

Token_CacheDestroy :: proc(c: ^Token_Cache) {
	for _, e in c.entries do delete(e.tokens)
	delete(c.entries)
	c.entries = nil
}

// Token_CacheTimeStart / End: measure a line-state pass.
Token_CacheTimeStart :: proc(c: ^Token_Cache) -> time.Tick {
	c.tokenized = 0
	return time.tick_now()
}

Token_CacheTimeEnd :: proc(c: ^Token_Cache, start: time.Tick) {
	c.lastUpdateMs = time.duration_milliseconds(time.tick_since(start))
}
