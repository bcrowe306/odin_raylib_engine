// JSON snapshot of editor + LSP popup state, returned by the `state`
// command. Lets an external driver assert on exactly what the user would
// see: buffer text, cursor, and whether/where the completion list and
// signature-help tooltip are shown and what they contain.
package control

import buf "../buffer"
import ed "../editor"
import lspc "../lsp"
import "core:encoding/json"
import "core:fmt"
import "core:strings"
import "core:time"
import sdl "vendor:sdl3"

STATE_MAX_ITEMS :: 25

State_Lsp :: struct {
	enabled:          bool `json:"enabled"`,
	initialized:      bool `json:"initialized"`,
	doc_open:         bool `json:"doc_open"`,
	synced:           bool `json:"synced"`,
	pending_requests: int  `json:"pending_requests"`,
	diagnostics:      int  `json:"diagnostics"`,
	status:           string `json:"status"`,
	crashes:          int    `json:"crashes"`,
	restarts:         int    `json:"restarts"`,
}

State_Mouse :: struct {
	x:      f32    `json:"x"`,
	y:      f32    `json:"y"`,
	zone:   string `json:"zone"`,
	cursor: string `json:"cursor"`,
	drag:   string `json:"drag"`,
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

State_Diagnostic :: struct {
	range:    [4]int `json:"range"` /* start line, col, end line, col (bytes) */,
	severity: string `json:"severity"`,
	message:  string `json:"message"`,
	source:   string `json:"source"`,
}

State_Diag_Counts :: struct {
	errors:   int `json:"errors"`,
	warnings: int `json:"warnings"`,
	infos:    int `json:"infos"`,
	hints:    int `json:"hints"`,
}

State_Tooltip :: struct {
	// Pending hover (what the pointer rests on, and for how long).
	hover_armed: bool   `json:"hover_armed"`,
	hover_cell:  [2]int `json:"hover_cell"`,
	hover_ms:    f64    `json:"hover_ms"`,
	visible: bool   `json:"visible"`,
	source:  string `json:"source"`,
	text:    string `json:"text"`,
	rect:    [4]f32 `json:"rect"`,
}

State :: struct {
	frame:        int              `json:"frame"`,
	file:         string           `json:"file"`,
	line_count:   int              `json:"line_count"`,
	cursor:       [2]int           `json:"cursor"`,
	cursors:      int              `json:"cursors"`,
	selection:    bool             `json:"selection"`,
	// Every cursor as [anchor_line, anchor_col, line, col] (anchor ==
	// position when there's no selection); index 0 is the primary.
	selections:    [][4]int        `json:"selections"`,
	selected_text: string          `json:"selected_text"`,
	tab_width:     int             `json:"tab_width"`,
	mouse:         State_Mouse     `json:"mouse"`,
	current_line: string           `json:"current_line"`,
	scroll:       [2]int           `json:"scroll"`,
	lsp:          State_Lsp        `json:"lsp"`,
	completion:   State_Completion `json:"completion"`,
	signature:    State_Signature  `json:"signature"`,
	diagnostics:       []State_Diagnostic `json:"diagnostics"`,
	diagnostic_counts: State_Diag_Counts  `json:"diagnostic_counts"`,
	tooltip:           State_Tooltip      `json:"tooltip"`,
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

	sels := make([][4]int, len(e.buf.cursors), context.temp_allocator)
	for cur, i in e.buf.cursors {
		anchor := cur.sel.anchor if cur.sel.active else cur.pos
		sels[i] = {anchor.line, anchor.col, cur.pos.line, cur.pos.col}
	}
	s.selections = sels
	if lo, hi, ok := buf.selection_range(c^); ok {
		s.selected_text = selection_text(e, lo, hi)
	}
	s.tab_width = e.tab_width
	s.mouse = State_Mouse{
		x      = e.mouse.x,
		y      = e.mouse.y,
		zone   = fmt.tprint(e.mouse.zone),
		cursor = "text" if ed.editor_mouse_cursor(e) == .Text else "default",
		drag   = fmt.tprint(e.mouse.drag),
	}

	s.lsp.status = strings.to_lower(fmt.tprint(ed.editor_lsp_status(e)), context.temp_allocator)
	s.lsp.crashes = e.lsp_supervisor.total_crashes
	s.lsp.restarts = e.lsp_supervisor.restarts
	if e.lsp_enabled {
		s.lsp = State_Lsp{
			status           = s.lsp.status,
			crashes          = s.lsp.crashes,
			restarts         = s.lsp.restarts,
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

	diags := ed.editor_diagnostics(e)
	sd := make([]State_Diagnostic, len(diags), context.temp_allocator)
	for d, i in diags {
		sd[i] = {{d.start.line, d.start.col, d.end.line, d.end.col}, ed.severity_label(d.severity), d.message, d.source}
		switch d.severity {
		case .Error: s.diagnostic_counts.errors += 1
		case .Warning: s.diagnostic_counts.warnings += 1
		case .Information: s.diagnostic_counts.infos += 1
		case .Hint: s.diagnostic_counts.hints += 1
		}
	}
	s.diagnostics = sd
	s.tooltip.hover_armed = e.diag_tip.hover_valid
	s.tooltip.hover_cell = {e.diag_tip.hover_pos.line, e.diag_tip.hover_pos.col}
	if e.diag_tip.hover_valid {
		s.tooltip.hover_ms = time.duration_milliseconds(time.tick_since(e.diag_tip.hover_since))
	}
	if tip, ok := ed.editor_diag_tooltip_layout(e); ok {
		lines := make([dynamic]string, context.temp_allocator)
		for l in tip.lines {
			append(&lines, l.text)
		}
		s.tooltip = State_Tooltip{
			hover_armed = s.tooltip.hover_armed,
			hover_cell  = s.tooltip.hover_cell,
			hover_ms    = s.tooltip.hover_ms,
			visible = true,
			source  = strings.to_lower(fmt.tprint(e.diag_tip.source), context.temp_allocator),
			text    = strings.join(lines[:], "\n", context.temp_allocator),
			rect    = rect_array(tip.rect),
		}
	}

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

// selection_text extracts the buffer text in [lo, hi).
@(private)
selection_text :: proc(e: ^ed.Editor, lo, hi: buf.Position) -> string {
	sb := strings.builder_make(context.temp_allocator)
	for ln in lo.line ..= hi.line {
		line := buf.buffer_line_str(&e.buf, ln)
		a := lo.col if ln == lo.line else 0
		b := hi.col if ln == hi.line else len(line)
		strings.write_string(&sb, line[min(a, len(line)):min(b, len(line))])
		if ln != hi.line {
			strings.write_byte(&sb, '\n')
		}
	}
	return strings.to_string(sb)
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
