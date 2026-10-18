// JSON snapshot of editor + LSP popup state, returned by the `state`
// command. Lets an external driver assert on exactly what the user would
// see: buffer text, cursor, and whether/where the completion list and
// signature-help tooltip are shown and what they contain.
package control

import buf "../buffer"
import ed "../editor"
import lspc "../lsp"
import "core:encoding/json"
import sdl "vendor:sdl3"

STATE_MAX_ITEMS :: 25

State_Lsp :: struct {
	enabled:          bool `json:"enabled"`,
	initialized:      bool `json:"initialized"`,
	doc_open:         bool `json:"doc_open"`,
	synced:           bool `json:"synced"`,
	pending_requests: int  `json:"pending_requests"`,
	diagnostics:      int  `json:"diagnostics"`,
}

State_Completion :: struct {
	active:         bool     `json:"active"`,
	waiting:        bool     `json:"waiting"`,
	visible:        bool     `json:"visible"`,
	anchor:         [2]int   `json:"anchor"`,
	prefix:         string   `json:"prefix"`,
	selected:       int      `json:"selected"`,
	selected_label: string   `json:"selected_label"`,
	count:          int      `json:"count"`,
	items:          []string `json:"items"`,
	rect:           [4]f32   `json:"rect"`,
}

State_Signature :: struct {
	active:       bool   `json:"active"`,
	waiting:      bool   `json:"waiting"`,
	visible:      bool   `json:"visible"`,
	label:        string `json:"label"`,
	active_param: string `json:"active_param"`,
	rect:         [4]f32 `json:"rect"`,
}

State :: struct {
	frame:        int              `json:"frame"`,
	file:         string           `json:"file"`,
	line_count:   int              `json:"line_count"`,
	cursor:       [2]int           `json:"cursor"`,
	cursors:      int              `json:"cursors"`,
	selection:    bool             `json:"selection"`,
	current_line: string           `json:"current_line"`,
	scroll:       [2]int           `json:"scroll"`,
	lsp:          State_Lsp        `json:"lsp"`,
	completion:   State_Completion `json:"completion"`,
	signature:    State_Signature  `json:"signature"`,
	text:         string           `json:"text"`,
}

// snapshot_state gathers the current state; strings are borrowed from the
// editor or allocated in the temp allocator, so the result is only valid
// until the next edit / temp-allocator reset.
snapshot_state :: proc(e: ^ed.Editor, frame: int) -> State {
	c := ed.editor_primary_cursor(e)
	_, _, has_sel := buf.selection_range(c^)
	s := State{
		frame        = frame,
		file         = e.buf.file_path,
		line_count   = buf.buffer_line_count(&e.buf),
		cursor       = {c.pos.line, c.pos.col},
		cursors      = len(e.buf.cursors),
		selection    = has_sel,
		current_line = buf.buffer_line_str(&e.buf, c.pos.line),
		scroll       = {e.scroll_line, e.scroll_col},
		text         = ed.editor_to_string(e, context.temp_allocator),
	}

	if e.lsp_enabled {
		s.lsp = State_Lsp{
			enabled          = true,
			initialized      = e.lsp.initialized,
			doc_open         = e.lsp_doc_open,
			synced           = e.lsp_synced_version == e.buf.version,
			pending_requests = len(e.lsp.pending_kind),
			diagnostics      = len(lspc.client_diagnostics_for(&e.lsp, e.document_uri)),
		}
	}

	layout := ed.editor_popup_layout(e)

	cs := &e.completion
	prefix, _ := ed.editor_completion_prefix(e)
	s.completion = State_Completion{
		active   = cs.active,
		waiting  = cs.waiting,
		visible  = ed.editor_completion_visible(e),
		anchor   = {cs.anchor.line, cs.anchor.col},
		prefix   = prefix if cs.active else "",
		selected = cs.selected,
		count    = len(cs.filtered),
		rect     = rect_array(layout.completion),
	}
	if item, ok := ed.editor_completion_selected_item(e); ok {
		s.completion.selected_label = item.label
	}
	n := min(len(cs.filtered), STATE_MAX_ITEMS)
	items := make([]string, n, context.temp_allocator)
	for i in 0 ..< n {
		items[i] = e.lsp.last_completion[cs.filtered[i]].label
	}
	s.completion.items = items

	s.signature = State_Signature{
		active  = e.signature.active,
		waiting = e.signature.waiting,
		visible = ed.editor_signature_visible(e),
		rect    = rect_array(layout.signature),
	}
	if s.signature.visible {
		s.signature.label, _, s.signature.active_param, _ = ed.editor_signature_active_parts(e)
	}
	return s
}

@(private)
rect_array :: proc(r: sdl.FRect) -> [4]f32 {
	return {r.x, r.y, r.w, r.h}
}

// state_json renders the snapshot as a single line of JSON (temp
// allocated).
state_json :: proc(e: ^ed.Editor, frame: int) -> string {
	s := snapshot_state(e, frame)
	data, err := json.marshal(s, allocator = context.temp_allocator)
	if err != nil {
		return `{"error":"marshal failed"}`
	}
	return string(data)
}
