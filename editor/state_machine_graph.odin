package editor

import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:strings"
import "core:time"
import e "../engine"
import buf "../odin_editor/buffer"
import imgui "lib/imgui"

// ============================================================================
// State machine tab (bottom panel "State Machine") for the selected
// StateMachineNode, in three pages: Graph (here), Parameters & Triggers and
// Settings (state_machine_tab_pages.odin).
//
// The graph: states as boxes (gameplay states or ones that play an
// animation, a child machine marked), transitions as arrows labelled with
// their conditions, the "Any state" box for transitions from anywhere.
// Manual arrows (only a script's sm_transition takes them) are dashed,
// Automatic ones solid; a pair both ways curves apart so each can be
// picked; an arrow from a state to itself (Allow Retrigger) loops over it.
//
//   drag a box             move it (saved with the scene)
//   drag a box's handle    (the dot on its right) onto another: a transition
//                          (dragged out and back onto its own box: to itself)
//   click / Delete         select a state or an arrow / remove it
//   right-click            add a state (gameplay, or for an animation) /
//                          the state's actions (initial, break on enter, ...)
//   wheel / middle drag    pan (Shift+wheel sideways); Cmd/Ctrl+wheel zooms;
//                          F frames everything
//
// The side panel edits the selection: a state's name, animation, child
// machine, initial, allow retrigger, break on enter, its guards (leave
// after, interruptible by Any state, can leave when / can enter when) and
// its script callbacks; a transition's mode, blend and conditions. While the
// scene runs (Simulate, or the game in Play) the current state is lit, the
// transition that fired flashes, the history lists the last changes, the
// parameters and pending triggers show live, and "Ways out" shows each
// arrow from the current state with every condition's result and the guard
// that blocks it (blocked arrows red).
// ============================================================================

SMG_BOX :: [2]f32{150, 54}

// stateGraphFocused: the graph tab has focus (its Delete isn't the scene's).
stateGraphFocused: bool

@(private = "file")
smg: struct {
	node:      ^e.StateMachineNode,
	pan:       [2]f32,
	zoom:      f32,
	selState:  int, // -1 none; -2 the Any box
	selTr:     int,
	dragging:  int, // state being moved (-1)
	dragGrab:  [2]f32,
	dragUndo:  bool,
	linkFrom:  int, // drag from a handle: -1 none, -2 = Any
	ctxState:  int,
	ctxWorld:  [2]f32,
	linkStart: [2]f32, // where the link drag started (screen)
	lastHist:  int,    // history length seen (flash on change)
	flashAt:   time.Tick,
	flashTr:   int,
	frame:     bool,
}

// SMG_Page: the State Machine tab's pages.
SMG_Page :: enum {
	Graph,
	Params, // Parameters & Triggers
	Settings,
}

// stateGraphPageRequest: show this page next frame.
stateGraphPageRequest: Maybe(SMG_Page)

SMG_LiveParam :: struct {
	name:  string,
	value: f32,
}

SMG_LiveTrigger :: struct {
	name:    string,
	pending: bool,
	held:    f32, // seconds it has waited since the first update that checked it
}

// SMG_View: what the graph shows as live - the editor's own machine
// (Simulate) or the running game's (Play, polled over the editor link).
SMG_View :: struct {
	running: bool,
	current: int, // state index (-1 none)
	time:    f32,
	fired:   int,
	history: []e.SM_Change,
	changes: int, // a counter that moves on every change (flash)
	remote:  bool,
	ways:    []e.SM_Way, // the ways out of the current state (explain)
	leave:   u32,        // the current state's leave conditions (bits)
	params:   []SMG_LiveParam,
	triggers: []SMG_LiveTrigger,
}

// The game's last answer for the machine shown (heap strings).
@(private = "file")
smgRemote: struct {
	path:    string,
	running: bool,
	current: string,
	secs:    f32,
	fired:   int,
	history: [dynamic]e.SM_Change,
	count:   int,
	asked:   time.Tick,
	got:     bool,
	ways:    [e.SM_WAYS_MAX]e.SM_Way,
	wayCount: int,
	leave:   u32,
	params:   [dynamic]SMG_LiveParam,
	triggers: [dynamic]SMG_LiveTrigger,
}

@(private = "file")
smg_remote_clear :: proc() {
	for h in smgRemote.history {
		delete(h.from)
		delete(h.to)
		delete(h.why)
	}
	clear(&smgRemote.history)
	for p in smgRemote.params do delete(p.name)
	clear(&smgRemote.params)
	for t in smgRemote.triggers do delete(t.name)
	clear(&smgRemote.triggers)
	delete(smgRemote.current)
	smgRemote.current = ""
	smgRemote.got = false
	smgRemote.wayCount = 0
	smgRemote.leave = 0
}

StateGraph_Shutdown :: proc() {
	for k in smgBreaks do delete(k)
	delete(smgBreaks)
	smg_remote_clear()
	delete(smgRemote.history)
	delete(smgRemote.params)
	delete(smgRemote.triggers)
	delete(smgRemote.path)
}

// smg_path: the machine's path from the scene root (the link's paths).
@(private = "file")
smg_path :: proc(state: ^EditorState, sm: ^e.StateMachineNode) -> string {
	return e.Node_RelativePath(state.activeScene.manager, state.activeScene.rootNode, sm)
}

@(private = "file")
smg_view :: proc(state: ^EditorState, sm: ^e.StateMachineNode) -> SMG_View {
	if RemoteGame_Connected() && state.gameProcessRunning {
		path := smg_path(state, sm)
		// Ask four times a second while shown.
		if time.duration_milliseconds(time.tick_since(smgRemote.asked)) > 250 {
			smgRemote.asked = time.tick_now()
			RemoteGame_Send(fmt.tprintf("sm %s", path))
		}
		if smgRemote.got && smgRemote.path == path {
			return {
				running = smgRemote.running, current = e.StateMachine_FindState(sm, smgRemote.current), time = smgRemote.secs,
				fired = smgRemote.fired, history = smgRemote.history[:], changes = smgRemote.count, remote = true,
				ways = smgRemote.ways[:smgRemote.wayCount], leave = smgRemote.leave,
				params = smgRemote.params[:], triggers = smgRemote.triggers[:],
			}
		}
		return {remote = true, current = -1, fired = -1}
	}
	params := make([]SMG_LiveParam, len(sm.params), context.temp_allocator)
	for p, i in sm.params do params[i] = {p.name, p.value}
	triggers := make([]SMG_LiveTrigger, len(sm.triggers), context.temp_allocator)
	for t, i in sm.triggers do triggers[i] = {t.name, t.pending, t.held}
	return {
		running = sm.running, current = sm.current, time = sm.timeInState, fired = sm.lastFired,
		history = e.StateMachine_History(sm), changes = sm.historyLen * 1000 + sm.historyNext,
		ways = sm.ways[:sm.wayCount], leave = sm.leaveMask, params = params, triggers = triggers,
	}
}

// StateGraph_View: what the tab shows as live for a machine (the editor's
// own in Simulate, the game's in Play).
StateGraph_View :: proc(state: ^EditorState, sm: ^e.StateMachineNode) -> SMG_View {return smg_view(state, sm)}

// StateGraph_RemoteReply: the game's "@rayzr:sm" answer.
StateGraph_RemoteReply :: proc(text: string) {
	v, err := json.parse(transmute([]u8)text, allocator = context.temp_allocator)
	if err != .None do return
	o, ok := v.(json.Object)
	if !ok do return
	smg_remote_clear()
	delete(smgRemote.path)
	smgRemote.path = strings.clone(string(o["path"].(json.String) or_else ""))
	if _, missing := o["missing"]; missing do return
	smgRemote.running = bool(o["running"].(json.Boolean) or_else false)
	smgRemote.current = strings.clone(string(o["current"].(json.String) or_else ""))
	num :: proc(v: json.Value) -> f64 {
		#partial switch x in v {
		case json.Float: return f64(x)
		case json.Integer: return f64(x)
		}
		return 0
	}
	smgRemote.secs = f32(num(o["time"]))
	smgRemote.fired = int(num(o["fired"]))
	if arr, isArr := o["history"].(json.Array); isArr {
		for hv in arr {
			h, hok := hv.(json.Array)
			if !hok || len(h) < 4 do continue
			append(&smgRemote.history, e.SM_Change{strings.clone(string(h[0].(json.String) or_else "")), strings.clone(string(h[1].(json.String) or_else "")), f32(num(h[2])), strings.clone(string(h[3].(json.String) or_else ""))})
		}
	}
	smgRemote.leave = u32(num(o["leave"]))
	if arr, isArr := o["ways"].(json.Array); isArr {
		for wv in arr {
			wa, wok := wv.(json.Array)
			if !wok || len(wa) < 5 || smgRemote.wayCount >= e.SM_WAYS_MAX do continue
			smgRemote.ways[smgRemote.wayCount] = {i32(num(wa[0])), num(wa[1]) != 0, e.SM_Block(clamp(int(num(wa[2])), 0, len(e.SM_Block) - 1)), u32(num(wa[3])), u32(num(wa[4]))}
			smgRemote.wayCount += 1
		}
	}
	if arr, isArr := o["params"].(json.Array); isArr {
		for pv in arr {
			p, pok := pv.(json.Array)
			if !pok || len(p) < 2 do continue
			append(&smgRemote.params, SMG_LiveParam{strings.clone(string(p[0].(json.String) or_else "")), f32(num(p[1]))})
		}
	}
	if arr, isArr := o["triggers"].(json.Array); isArr {
		for tv in arr {
			tr, tok := tv.(json.Array)
			if !tok || len(tr) < 3 do continue
			append(&smgRemote.triggers, SMG_LiveTrigger{strings.clone(string(tr[0].(json.String) or_else "")), num(tr[1]) != 0, f32(num(tr[2]))})
		}
	}
	if n := len(smgRemote.history); n > 0 {
		last := smgRemote.history[n - 1]
		smgRemote.count = n * 100000 + int(last.time * 1000)
	}
	smgRemote.got = true
}

// --- break on enter --------------------------------------------------------------------
// Kept in the editor by "<machine path>|<state>" (not saved with the scene;
// survives Simulate's restore and is sent to games that connect).

@(private = "file")
smgBreaks: map[string]bool

@(private = "file")
smg_break_key :: proc(path, st: string) -> string {return strings.concatenate({path, "|", st}, context.temp_allocator)}

// smg_sync_breaks: the machine's states show the editor's breaks.
@(private = "file")
smg_sync_breaks :: proc(state: ^EditorState, sm: ^e.StateMachineNode) {
	path := smg_path(state, sm)
	for &s in sm.states do s.breakOnEnter = smgBreaks[smg_break_key(path, s.name)] or_else false
}

// StateGraph_SimulationStarted: break-on-enter for the editor's machines.
StateGraph_SimulationStarted :: proc(state: ^EditorState) {
	if state.activeScene == nil do return
	for n in state.activeScene.manager.nodes {
		if n == nil || n.typeId != e.StateMachineNode do continue
		smg_sync_breaks(state, cast(^e.StateMachineNode)n)
		(cast(^e.StateMachineNode)n).onEnterHook = proc(sm: ^e.StateMachineNode, name: string) {
			i := e.StateMachine_FindState(sm, name)
			if i < 0 || !sm.states[i].breakOnEnter do return
			GlobalEditor.isPaused = true
			Editor_Log(&GlobalEditor, .Info, "Paused: %s entered %s (break on enter)", sm.name, name)
		}
	}
}

// StateGraph_SendBreaks: the break-on-enter states to a game that connected.
StateGraph_SendBreaks :: proc(state: ^EditorState) {
	if state.activeScene == nil do return
	for key, on in smgBreaks {
		if !on do continue
		if bar := strings.last_index_byte(key, '|'); bar > 0 do RemoteGame_Send(fmt.tprintf("sm-break %s %s 1", key[:bar], key[bar + 1:]))
	}
}

// smg_set_break toggles a state's break on enter (and tells a running game).
@(private = "file")
smg_set_break :: proc(state: ^EditorState, sm: ^e.StateMachineNode, i: int, on: bool) {
	sm.states[i].breakOnEnter = on
	key := smg_break_key(smg_path(state, sm), sm.states[i].name)
	if on {
		if key not_in smgBreaks do smgBreaks[strings.clone(key)] = true
	} else if key in smgBreaks {
		k, _ := delete_key(&smgBreaks, key)
		delete(k)
	}
	if RemoteGame_Connected() do RemoteGame_Send(fmt.tprintf("sm-break %s %s %d", smg_path(state, sm), sm.states[i].name, 1 if on else 0))
}

@(private = "file")
smg_reset :: proc(sm: ^e.StateMachineNode) {
	smg.node = sm
	smg.zoom = 1
	smg.pan = {}
	smg.selState, smg.selTr, smg.dragging, smg.linkFrom = -1, -1, -1, -1
	smg.lastHist = -1
	smg.frame = true
}

// StateGraph_Render draws the tab.
StateGraph_Render :: proc(state: ^EditorState) {
	sel := state.selectedNode
	if sel == nil || sel.typeId != e.StateMachineNode {
		imgui.Dummy({0, 8})
		UI_DimText("   Select a State Machine node to edit its states and transitions as a graph.")
		return
	}
	sm := cast(^e.StateMachineNode)sel
	if smg.node != sm do smg_reset(sm)
	sm.explain = true // the live "ways out" (Simulate)
	stateGraphFocused = imgui.IsWindowFocused(imgui.FocusedFlags_RootAndChildWindows)
	smg_sync_breaks(state, sm) // the editor keeps them (scene rebuilds don't)
	if smg.zoom == 0 do smg.zoom = 1
	req, hasReq := stateGraphPageRequest.?
	stateGraphPageRequest = nil
	if !imgui.BeginTabBar("##smg_pages", {}) do return
	defer imgui.EndTabBar()
	page :: proc(label: cstring, id: string, p, req: SMG_Page, hasReq: bool) -> bool {
		open := imgui.BeginTabItem(label, nil, {.SetSelected} if hasReq && req == p else {})
		Drive_Item(id)
		return open
	}
	if page(fmt.ctprintf("%s  Graph###smg_graph", ICON_FA_DIAGRAM_PROJECT), "smg.page:graph", .Graph, req, hasReq) {
		avail := imgui.GetContentRegionAvail()
		panelW: f32 = 330
		if imgui.BeginChild("##smg_canvas", {max(avail.x - panelW - 8, 200), avail.y}, {.Borders}, {.NoScrollbar, .NoScrollWithMouse}) {
			smg_canvas(state, sm)
		}
		imgui.EndChild()
		imgui.SameLine()
		if imgui.BeginChild("##smg_side", {0, avail.y}, {}, {}) {
			smg_side_panel(state, sm)
		}
		imgui.EndChild()
		imgui.EndTabItem()
	}
	label := fmt.ctprintf("%s  Parameters & Triggers (%d / %d)###smg_params", ICON_FA_SLIDERS, len(sm.params), len(sm.triggers))
	if page(label, "smg.page:params", .Params, req, hasReq) {
		if imgui.BeginChild("##smg_params_page", {0, 0}, {}, {}) do StateGraph_ParamsPage(state, sm)
		imgui.EndChild()
		imgui.EndTabItem()
	}
	if page(fmt.ctprintf("%s  Settings###smg_settings", ICON_FA_GEAR), "smg.page:settings", .Settings, req, hasReq) {
		if imgui.BeginChild("##smg_settings_page", {0, 0}, {}, {}) do StateGraph_SettingsPage(state, sm)
		imgui.EndChild()
		imgui.EndTabItem()
	}
}

// --- geometry -----------------------------------------------------------------------

@(private = "file")
smg_to_screen :: proc(origin: [2]f32, w: [2]f32) -> [2]f32 {return origin + smg.pan + w * smg.zoom}

@(private = "file")
smg_to_world :: proc(origin: [2]f32, s: [2]f32) -> [2]f32 {return (s - origin - smg.pan) / smg.zoom}

@(private = "file")
smg_box_pos :: proc(sm: ^e.StateMachineNode, i: int) -> [2]f32 {
	return sm.anyPos if i == -2 else sm.states[i].pos
}

// smg_edge: where the segment from a box's centre towards p leaves the box.
@(private = "file")
smg_edge :: proc(mn, mx, p: [2]f32) -> [2]f32 {
	c := (mn + mx) * 0.5
	d := p - c
	half := (mx - mn) * 0.5
	if d.x == 0 && d.y == 0 do return c
	sx := half.x / abs(d.x) if d.x != 0 else max(f32)
	sy := half.y / abs(d.y) if d.y != 0 else max(f32)
	return c + d * min(sx, sy)
}

@(private = "file")
seg_dist :: proc(p, a, b: [2]f32) -> f32 {
	ab := b - a
	t := clamp(linalg.dot(p - a, ab) / max(linalg.dot(ab, ab), 0.0001), 0, 1)
	return linalg.length(p - (a + ab * t))
}

SMG_ARROW_STEPS :: 24

// SMG_Arrow_Path: an arrow on screen as a polyline, its middle, and the side
// its label goes (the side it bows to).
SMG_Arrow_Path :: struct {
	pts:  [SMG_ARROW_STEPS + 1][2]f32,
	mid:  [2]f32,
	side: [2]f32,
}

// smg_arrow_path: the arrow from box a to box b - straight; curved (a
// quadratic Bezier bowing to its left) when the pair goes both ways, so the
// two arrows bow apart; a loop over the box when it goes to itself. Sizes
// follow the zoom.
smg_arrow_path :: proc(amn, amx, bmn, bmx: [2]f32, twoWay, self: bool) -> (p: SMG_Arrow_Path) {
	z := smg.zoom
	if self {
		cx, top := (amn.x + amx.x) * 0.5, amn.y
		p0, p3 := [2]f32{cx - 18 * z, top}, [2]f32{cx + 18 * z, top}
		c1, c2 := [2]f32{cx - 46 * z, top - 58 * z}, [2]f32{cx + 46 * z, top - 58 * z}
		for k in 0 ..= SMG_ARROW_STEPS {
			t := f32(k) / SMG_ARROW_STEPS
			u := 1 - t
			p.pts[k] = u * u * u * p0 + 3 * u * u * t * c1 + 3 * u * t * t * c2 + t * t * t * p3
		}
		p.mid = p.pts[SMG_ARROW_STEPS / 2]
		p.side = {0, -1}
		return
	}
	ca, cb := (amn + amx) * 0.5, (bmn + bmx) * 0.5
	dir := linalg.normalize0(cb - ca)
	p.side = {-dir.y, dir.x}
	if !twoWay {
		a, b := smg_edge(amn, amx, cb), smg_edge(bmn, bmx, ca)
		for k in 0 ..= SMG_ARROW_STEPS do p.pts[k] = linalg.lerp(a, b, f32(k) / SMG_ARROW_STEPS)
		p.mid = (a + b) * 0.5
		return
	}
	// The control point twice as far out as the curve's middle.
	ctrl := (ca + cb) * 0.5 + p.side * 30 * z * 2
	a, b := smg_edge(amn, amx, ctrl), smg_edge(bmn, bmx, ctrl)
	for k in 0 ..= SMG_ARROW_STEPS {
		t := f32(k) / SMG_ARROW_STEPS
		u := 1 - t
		p.pts[k] = u * u * a + 2 * u * t * ctrl + t * t * b
	}
	p.mid = p.pts[SMG_ARROW_STEPS / 2]
	return
}

// smg_path_dist: the distance from p to a polyline.
smg_path_dist :: proc(p: [2]f32, pts: [][2]f32) -> f32 {
	best := max(f32)
	for k in 1 ..< len(pts) do best = min(best, seg_dist(p, pts[k - 1], pts[k]))
	return best
}

// smg_draw_path: a polyline, solid or dashed (manual arrows).
@(private = "file")
smg_draw_path :: proc(dl: ^imgui.DrawList, pts: [][2]f32, col: u32, thick: f32, dashed: bool) {
	if !dashed {
		imgui.DrawList_AddPolyline(dl, raw_data(pts), i32(len(pts)), col, {}, thick)
		return
	}
	dash, gap := 7 * max(smg.zoom, 0.6), 5 * max(smg.zoom, 0.6)
	pos: f32 = 0 // along the dash pattern
	for k in 1 ..< len(pts) {
		a, b := pts[k - 1], pts[k]
		l := linalg.length(b - a)
		if l <= 0 do continue
		d: f32 = 0
		for d < l {
			inDash := pos < dash
			left := (dash - pos) if inDash else (dash + gap - pos)
			step := min(left, l - d)
			if inDash do imgui.DrawList_AddLine(dl, linalg.lerp(a, b, d / l), linalg.lerp(a, b, (d + step) / l), col, thick)
			d += step
			pos += step
			if pos >= dash + gap do pos = 0
		}
	}
}

// smg_arrow_label: an arrow's label - its conditions, "manual" first for a
// manual one.
@(private = "file")
smg_arrow_label :: proc(t: e.SM_Transition) -> string {
	if t.mode == .Automatic do return smg_condition_text(t.conditions[:])
	if len(t.conditions) == 0 do return "manual"
	return fmt.tprintf("manual: %s", smg_condition_text(t.conditions[:]))
}

// smg_condition_text: a short label for a transition's conditions.
smg_condition_text :: proc(conds: []e.SM_Condition) -> string {
	if len(conds) == 0 do return "always"
	sb := strings.builder_make(context.temp_allocator)
	sep := ""
	for c in conds {
		if c.op == .Or {
			strings.write_string(&sb, " | ")
			sep = ""
			continue
		}
		strings.write_string(&sb, sep)
		sep = ", "
		switch c.op {
		case .Is_True:   fmt.sbprintf(&sb, "%s", c.param)
		case .Is_False:  fmt.sbprintf(&sb, "!%s", c.param)
		case .Equal, .Not_Equal, .Greater, .Less: fmt.sbprintf(&sb, "%s %s %g", c.param, e.SM_OP_NAMES[c.op], c.value)
		case .Trigger:   fmt.sbprintf(&sb, "%s!", c.param)
		case .Finished:  strings.write_string(&sb, "anim done")
		case .After:     fmt.sbprintf(&sb, "after %gs", c.value)
		case .Call:      fmt.sbprintf(&sb, "%s()", c.param)
		case .Or:
		}
	}
	s := strings.to_string(sb)
	return s if len(s) <= 34 else fmt.tprintf("%s…", s[:32])
}

// --- canvas -------------------------------------------------------------------------

@(private = "file")
smg_canvas :: proc(state: ^EditorState, sm: ^e.StateMachineNode) {
	dl := imgui.GetWindowDrawList()
	origin := imgui.GetCursorScreenPos()
	size := imgui.GetContentRegionAvail()
	io := imgui.GetIO()
	mouse := [2]f32{io.MousePos.x, io.MousePos.y}
	hovered := imgui.IsWindowHovered()
	imgui.DrawList_AddRectFilled(dl, origin, origin + size, col_u32(CODE_BG))
	Drive_ItemRect("smg.canvas", origin, origin + size, inWindow = true)
	// Grid.
	step := 40 * smg.zoom
	if step > 8 {
		gx := math.mod(smg.pan.x, step)
		for x := origin.x + gx; x < origin.x + size.x; x += step do imgui.DrawList_AddLine(dl, {x, origin.y}, {x, origin.y + size.y}, col_u32(ui_line(0.03)))
		gy := math.mod(smg.pan.y, step)
		for y := origin.y + gy; y < origin.y + size.y; y += step do imgui.DrawList_AddLine(dl, {origin.x, y}, {origin.x + size.x, y}, col_u32(ui_line(0.03)))
	}
	// Frame everything (first show, F).
	if (smg.frame && size.x > 120 && size.y > 80) || (hovered && imgui.IsKeyPressed(.F) && !io.WantTextInput) { // (laid out first)
		smg.frame = false
		mn, mx := sm.anyPos, sm.anyPos + SMG_BOX
		for s in sm.states {
			mn = {min(mn.x, s.pos.x), min(mn.y, s.pos.y)}
			mx = {max(mx.x, s.pos.x + SMG_BOX.x), max(mx.y, s.pos.y + SMG_BOX.y)}
		}
		ext := mx - mn + {80, 80}
		smg.zoom = clamp(min(size.x / ext.x, size.y / ext.y), 0.3, 1.0)
		smg.pan = (size - (mx - mn) * smg.zoom) * 0.5 - mn * smg.zoom
	}
	// Cmd/Ctrl+wheel zooms at the mouse; the wheel pans (Shift: sideways).
	if hovered && (io.MouseWheel != 0 || io.MouseWheelH != 0) {
		if io.KeyCtrl || io.KeySuper {
			before := smg_to_world(origin, mouse)
			smg.zoom = clamp(smg.zoom * (1 + io.MouseWheel * 0.1), 0.3, 2.5)
			smg.pan += mouse - smg_to_screen(origin, before)
		} else if io.KeyShift {
			smg.pan.x += io.MouseWheel * 30
		} else {
			smg.pan += {io.MouseWheelH * 30, io.MouseWheel * 30}
		}
	}
	if hovered && imgui.IsMouseDragging(.Middle) do smg.pan += {io.MouseDelta.x, io.MouseDelta.y}

	// A change: flash the transition that fired.
	view := smg_view(state, sm)
	if view.changes != smg.lastHist {
		if smg.lastHist != -1 {
			smg.flashAt = time.tick_now()
			smg.flashTr = view.fired
		}
		smg.lastHist = view.changes
	}
	flash := f32(1) - clamp(f32(time.duration_seconds(time.tick_since(smg.flashAt))) / 0.8, 0, 1)

	box :: proc(origin: [2]f32, sm: ^e.StateMachineNode, i: int) -> (mn, mx: [2]f32) {
		mn = smg_to_screen(origin, smg_box_pos(sm, i))
		mx = mn + SMG_BOX * smg.zoom
		return
	}
	// Transitions. Hover picks the arrow nearest the mouse (two-way pairs
	// curve apart, so each has its own hit area).
	hoverTr := -1
	hoverDist: f32 = 6
	for t, ti in sm.transitions {
		fi := -2 if t.from == e.SM_ANY else e.StateMachine_FindState(sm, t.from)
		toI := e.StateMachine_FindState(sm, t.to)
		if fi == -1 || toI < 0 do continue
		amn, amx := box(origin, sm, fi)
		bmn, bmx := box(origin, sm, toI)
		twoWay := false
		for o in sm.transitions do if o.from == t.to && o.to == t.from && t.from != t.to do twoWay = true
		path := smg_arrow_path(amn, amx, bmn, bmx, twoWay, fi == toI)
		if hovered {
			if d := smg_path_dist(mouse, path.pts[:]); d < hoverDist do hoverTr, hoverDist = ti, d
		}
	}
	for t, ti in sm.transitions {
		fi := -2 if t.from == e.SM_ANY else e.StateMachine_FindState(sm, t.from)
		toI := e.StateMachine_FindState(sm, t.to)
		if fi == -1 || toI < 0 do continue
		amn, amx := box(origin, sm, fi)
		bmn, bmx := box(origin, sm, toI)
		twoWay := false
		for o in sm.transitions do if o.from == t.to && o.to == t.from && t.from != t.to do twoWay = true
		path := smg_arrow_path(amn, amx, bmn, bmx, twoWay, fi == toI)
		col := ui_line(0.45)
		thick: f32 = 1.5
		if ti == smg.selTr {col = UI_ACCENT; thick = 2.5}
		else if ti == hoverTr do col = ui_line(0.7)
		if view.running do for w in view.ways do if int(w.transition) == ti && w.arrow && w.block != .None && w.block != .Manual {
			col = UI_DANGER // it would fire, a guard says no
			thick = max(thick, 2)
		}
		if ti == smg.flashTr && flash > 0 {col = {0.96, 0.72, 0.30, 0.4 + 0.6 * flash}; thick = 2 + 2 * flash}
		smg_draw_path(dl, path.pts[:], col_u32(col), thick, dashed = t.mode == .Manual)
		// Arrowhead, along the end of the path.
		n := len(path.pts)
		b := path.pts[n - 1]
		dir := linalg.normalize0(b - path.pts[n - 3])
		perp := [2]f32{-dir.y, dir.x}
		ah := 9 * max(smg.zoom, 0.6)
		imgui.DrawList_AddTriangleFilled(dl, b, b - dir * ah + perp * ah * 0.5, b - dir * ah - perp * ah * 0.5, col_u32(col))
		// The mode and conditions at the middle, on the side it bows to.
		if smg.zoom > 0.55 {
			label := strings.clone_to_cstring(smg_arrow_label(t), context.temp_allocator)
			w := imgui.CalcTextSize(label).x * 0.85
			mid := path.mid + path.side * 10
			imgui.DrawList_AddRectFilled(dl, {mid.x - w * 0.5 - 4, mid.y - 8}, {mid.x + w * 0.5 + 4, mid.y + 8}, col_u32(CODE_BG), 3)
			imgui.DrawList_AddTextImFontPtr(dl, GlobalFonts.small, 12, {mid.x - w * 0.5, mid.y - 7}, col_u32(UI_TEXT_DIM if ti != smg.selTr else UI_ACCENT), label)
		}
		Drive_ItemRect(fmt.tprintf("smg.tr:%d", ti), path.mid - {5, 5}, path.mid + {5, 5}, inWindow = true)
	}

	// Boxes: Any, then the states.
	hoverState := -1
	hoverHandle := -1
	for i := -2; i < len(sm.states); i += 1 {
		if i == -1 do continue
		mn, mx := box(origin, sm, i)
		inside := hovered && point_in_rect(mouse, mn, mx)
		handle := [2]f32{mx.x, (mn.y + mx.y) * 0.5}
		onHandle := hovered && linalg.length(mouse - handle) < 8
		if inside do hoverState = i
		if onHandle do hoverHandle = i
		isAny := i == -2
		current := !isAny && view.running && view.current == i
		fill := UI_BG_RAISED
		if current do fill = ui_accent(0.35)
		if isAny do fill = UI_BG_PANEL
		imgui.DrawList_AddRectFilled(dl, mn, mx, col_u32(fill), 8)
		border := ui_line(0.18)
		if (isAny && smg.selState == -2) || (!isAny && smg.selState == i) do border = UI_ACCENT
		else if current do border = UI_ACCENT
		imgui.DrawList_AddRect(dl, mn, mx, col_u32(border), 8, {}, 2 if border == UI_ACCENT else 1)
		pad := [2]f32{10, 7} * smg.zoom
		if isAny {
			imgui.DrawList_AddText(dl, mn + pad, col_u32(UI_TEXT_DIM), "Any state")
		} else {
			s := sm.states[i]
			title := strings.clone_to_cstring(s.name, context.temp_allocator)
			if s.name == sm.initial do imgui.DrawList_AddText(dl, mn + pad, col_u32(UI_WARNING), ICON_FA_FLAG)
			tx := mn.x + pad.x + (16 if s.name == sm.initial else 0)
			imgui.DrawList_AddTextImFontPtr(dl, GlobalFonts.semibold, imgui.GetFontSize(), {tx, mn.y + pad.y}, col_u32(UI_TEXT), title)
			sub := fmt.tprintf("%s %s", ICON_FA_FILM, s.animation) if s.animation != "" else "gameplay"
			if s.child != "" do sub = fmt.tprintf("%s  %s %s", sub, ICON_FA_SITEMAP, s.child)
			if smg.zoom > 0.6 do imgui.DrawList_AddTextImFontPtr(dl, GlobalFonts.small, 12, {mn.x + pad.x, mx.y - pad.y - 13}, col_u32(UI_TEXT_DIM), strings.clone_to_cstring(sub, context.temp_allocator))
			if s.breakOnEnter do imgui.DrawList_AddCircleFilled(dl, {mx.x - 10, mn.y + 10}, 4.5, col_u32({0.92, 0.30, 0.29, 1}))
			badgeX := mx.x - (34 if s.breakOnEnter else 22)
			if s.allowRetrigger {
				rp := [2]f32{badgeX, mn.y + 4}
				imgui.DrawList_AddTextImFontPtr(dl, GlobalFonts.small, 12, rp, col_u32(UI_TEXT_DIM), ICON_FA_ROTATE_RIGHT)
				if hovered && point_in_rect(mouse, rp - {3, 3}, rp + {15, 17}) do imgui.SetTooltip("Allow Retrigger: it can go to itself (re-entered)")
				badgeX -= 16
			}
			if e.StateMachine_HasGuards(s) {
				// Guarded: a lock (what it refuses in the tooltip).
				lp := [2]f32{badgeX, mn.y + 4}
				imgui.DrawList_AddTextImFontPtr(dl, GlobalFonts.small, 12, lp, col_u32(UI_WARNING), ICON_FA_LOCK)
				if hovered && point_in_rect(mouse, lp - {3, 3}, lp + {15, 17}) do imgui.SetTooltip("%s", strings.clone_to_cstring(smg_guard_summary(s), context.temp_allocator))
				Drive_ItemRect(fmt.tprintf("smg.lock:%s", s.name), lp, lp + {12, 14}, inWindow = true)
			}
			if current {
				// Time in the state, a thin bar along the bottom.
				f := clamp(view.time / 3, 0, 1)
				imgui.DrawList_AddRectFilled(dl, {mn.x + 6, mx.y - 3}, {mn.x + 6 + (mx.x - mn.x - 12) * f, mx.y - 1}, col_u32(UI_ACCENT))
			}
		}
		// The link handle.
		imgui.DrawList_AddCircleFilled(dl, handle, 4.5 if !onHandle else 6, col_u32(UI_ACCENT if onHandle else ui_line(0.35)))
		Drive_ItemRect(fmt.tprintf("smg.state:%s", "Any" if isAny else sm.states[i].name), mn, {mx.x - 12, mx.y}, inWindow = true)
		Drive_ItemRect(fmt.tprintf("smg.handle:%s", "Any" if isAny else sm.states[i].name), handle - {6, 6}, handle + {6, 6}, inWindow = true)
	}

	// Mouse.
	if hovered && (imgui.IsMouseClicked(.Left) || imgui.IsMouseClicked(.Right)) do imgui.SetWindowFocus() // keys go to the graph
	if hovered && imgui.IsMouseClicked(.Left) {
		switch {
		case hoverHandle != -1:
			smg.linkFrom = hoverHandle
			smg.linkStart = mouse
		case hoverState != -1:
			smg.selState, smg.selTr = hoverState, -1
			smg.dragging = hoverState // the Any box (-2) moves too
			smg.dragGrab = smg_to_world(origin, mouse) - smg_box_pos(sm, hoverState)
			smg.dragUndo = false
		case hoverTr != -1:
			smg.selTr, smg.selState = hoverTr, -1
		case:
			smg.selState, smg.selTr = -1, -1
		}
	}
	if smg.dragging == -2 || (smg.dragging >= 0 && smg.dragging < len(sm.states)) {
		if imgui.IsMouseDragging(.Left, 2) {
			if !smg.dragUndo {
				Editor_RecordUndo(state, "Move state")
				smg.dragUndo = true
			}
			p := smg_to_world(origin, mouse) - smg.dragGrab
			snapped := [2]f32{math.round(p.x / 10) * 10, math.round(p.y / 10) * 10}
			if smg.dragging == -2 do sm.anyPos = snapped
			else do sm.states[smg.dragging].pos = snapped
		}
		if !imgui.IsMouseDown(.Left) do smg.dragging = -1
	}
	if smg.linkFrom != -1 {
		// Dragging a new transition: an arrow to the mouse.
		amn, amx := box(origin, sm, smg.linkFrom)
		start := [2]f32{amx.x, (amn.y + amx.y) * 0.5}
		imgui.DrawList_AddLine(dl, start, mouse, col_u32(UI_ACCENT), 2)
		if !imgui.IsMouseDown(.Left) {
			// Back onto its own box: an arrow to itself, only when dragged out
			// and back (not a click on the handle).
			self := hoverState >= 0 && hoverState == smg.linkFrom
			if hoverState >= 0 && (!self || linalg.length(mouse - smg.linkStart) > 40) {
				Editor_RecordUndo(state, "Add transition")
				from := e.SM_ANY if smg.linkFrom == -2 else sm.states[smg.linkFrom].name
				e.StateMachine_AddTransition(sm, from, sm.states[hoverState].name)
				smg.selTr, smg.selState = len(sm.transitions) - 1, -1
				if self && !sm.states[hoverState].allowRetrigger {
					sm.states[hoverState].allowRetrigger = true
					Editor_Log(state, .Info, "%s: Allow Retrigger turned on (an arrow to itself)", sm.states[hoverState].name)
				}
			}
			smg.linkFrom = -1
		}
	}
	// Delete the selection.
	if (imgui.IsWindowFocused() || hovered) && !io.WantTextInput && (imgui.IsKeyPressed(.Delete) || imgui.IsKeyPressed(.Backspace)) {
		smg_delete_selection(state, sm)
	}
	// Right-click: on a state its actions, elsewhere add a state.
	if hovered && imgui.IsMouseClicked(.Right) {
		smg.ctxState = hoverState
		smg.ctxWorld = smg_to_world(origin, mouse)
		if hoverState != -1 do smg.selState, smg.selTr = hoverState, -1
		imgui.OpenPopup("##smg_ctx")
	}
	if imgui.BeginPopup("##smg_ctx") {
		smg_context_menu(state, sm)
		imgui.EndPopup()
	}
	if len(sm.states) == 0 {
		imgui.SetCursorScreenPos(origin + {20, size.y * 0.5})
		UI_DimText("Right-click to add a state. Drag a state's dot onto another to connect them.")
	}
}

@(private = "file")
smg_delete_selection :: proc(state: ^EditorState, sm: ^e.StateMachineNode) {
	if smg.selTr >= 0 && smg.selTr < len(sm.transitions) {
		Editor_RecordUndo(state, "Remove transition")
		ordered_remove(&sm.transitions, smg.selTr)
		smg.selTr = -1
	} else if smg.selState >= 0 && smg.selState < len(sm.states) {
		Editor_RecordUndo(state, "Remove state")
		e.StateMachine_RemoveState(sm, smg.selState)
		smg.selState = -1
	}
}

@(private = "file")
smg_add_state :: proc(state: ^EditorState, sm: ^e.StateMachineNode, base, animation: string, at: [2]f32) {
	Editor_RecordUndo(state, "Add state")
	name := base
	for k := 2; e.StateMachine_FindState(sm, name) >= 0; k += 1 do name = fmt.tprintf("%s_%d", base, k)
	i := e.StateMachine_AddState(sm, name, animation)
	p := [2]f32{math.round(at.x / 10) * 10, math.round(at.y / 10) * 10}
	// Not on top of another box: step down until it's clear.
	overlaps :: proc(sm: ^e.StateMachineNode, i: int, p: [2]f32) -> bool {
		hit :: proc(a, b: [2]f32) -> bool {return abs(a.x - b.x) < SMG_BOX.x + 10 && abs(a.y - b.y) < SMG_BOX.y + 10}
		if hit(p, sm.anyPos) do return true
		for s, k in sm.states do if k != i && hit(p, s.pos) do return true
		return false
	}
	for tries := 0; overlaps(sm, i, p) && tries < 40; tries += 1 do p.y += 70
	sm.states[i].pos = p
	smg.selState, smg.selTr = i, -1
}

@(private = "file")
smg_context_menu :: proc(state: ^EditorState, sm: ^e.StateMachineNode) {
	i := smg.ctxState
	if i >= 0 && i < len(sm.states) {
		s := &sm.states[i]
		UI_DimText(s.name)
		if imgui.MenuItem(fmt.ctprintf("%s  Set as Initial State", ICON_FA_FLAG), nil, false, sm.initial != s.name) {
			Editor_RecordUndo(state, "Initial state")
			sm.initial = s.name
		}
		Drive_Item("ctx:smg-initial")
		if imgui.MenuItem(fmt.ctprintf("%s  Break on Enter", ICON_FA_CIRCLE), nil, s.breakOnEnter) do smg_set_break(state, sm, i, !s.breakOnEnter)
		Drive_Item("ctx:smg-break")
		if imgui.MenuItem(fmt.ctprintf("%s  Add Script Callbacks", ICON_FA_CODE)) do smg_add_callbacks(state, sm, s.name)
		Drive_Item("ctx:smg-callbacks")
		if imgui.MenuItem(fmt.ctprintf("%s  Add Guard Callbacks", ICON_FA_LOCK)) do smg_add_callbacks(state, sm, s.name, guards = true)
		Drive_Item("ctx:smg-guard-callbacks")
		UI_Tooltip("can_exit_ / can_enter_: return false to refuse the change")
		imgui.Separator()
		if imgui.MenuItem(fmt.ctprintf("%s  Delete State", ICON_FA_TRASH)) {
			smg.selState = i
			smg_delete_selection(state, sm)
		}
		Drive_Item("ctx:smg-delete")
		return
	}
	if imgui.MenuItem(fmt.ctprintf("%s  Add State", ICON_FA_PLUS)) do smg_add_state(state, sm, "state", "", smg.ctxWorld)
	Drive_Item("ctx:smg-add-state")
	if player := e.StateMachine_Player(sm, state.activeScene.manager); player != nil && len(player.animations) > 0 {
		if imgui.BeginMenu(fmt.ctprintf("%s  Add State for Animation", ICON_FA_FILM)) {
			for a in player.animations {
				if a == nil do continue
				if imgui.MenuItem(strings.clone_to_cstring(a.name, context.temp_allocator)) do smg_add_state(state, sm, a.name, a.name, smg.ctxWorld)
				Drive_Item(fmt.tprintf("ctx:smg-add-anim:%s", a.name))
			}
			imgui.EndMenu()
		}
	}
	if imgui.MenuItem(fmt.ctprintf("%s  Frame All", ICON_FA_EXPAND), "F") do smg.frame = true
}

// smg_script_rel: the script that gets the machine's callbacks (the
// machine's own, else its parent's).
@(private = "file")
smg_script_rel :: proc(state: ^EditorState, sm: ^e.StateMachineNode) -> (string, ^e.Node) {
	if rel := node_script_rel(state, sm); rel != "" do return rel, sm
	if p := e.GetParent(state.activeScene.manager, sm); p != nil {
		if rel := node_script_rel(state, p); rel != "" do return rel, p
	}
	return "", nil
}

// smg_add_callbacks writes on_enter_ / on_update_ / on_exit_<state> (or
// with guards can_exit_ / can_enter_<state>) into the script (those
// missing), before its final `return`.
@(private = "file")
smg_add_callbacks :: proc(state: ^EditorState, sm: ^e.StateMachineNode, name: string, guards := false) {
	rel, _ := smg_script_rel(state, sm)
	if rel == "" {
		Editor_Log(state, .Warn, "Attach a script to %s or its parent first: the callbacks go there", sm.name)
		return
	}
	if !Editor_OpenScript(state, rel) do return
	doc := code_active_doc()
	b := &doc.buffer
	cls := Script_ClassName(buf.buffer_to_string(b, context.temp_allocator))
	if cls == "" do return
	sb := strings.builder_make(context.temp_allocator)
	CALLBACKS :: [?][4]string{{"on_enter_", "previous", "Entered (from the previous state)", ""}, {"on_update_", "dt", "Every frame while in the state", ""}, {"on_exit_", "next", "Left (for the next state)", ""}}
	GUARDS :: [?][4]string{{"can_exit_", "next", "Can it leave for next? false keeps it here", "    return true\n"}, {"can_enter_", "previous", "Can it come in from previous? false keeps it out", "    return true\n"}}
	cbs, gs := CALLBACKS, GUARDS
	methods := gs[:] if guards else cbs[:]
	for m in methods {
		method := strings.concatenate({m[0], name}, context.temp_allocator)
		if _, _, _, found := Script_FindMethod(b, cls, method); found do continue
		fmt.sbprintf(&sb, "\n---State %s: %s\nfunction %s:%s(%s)\n%send\n", name, m[2], cls, method, m[1], m[3])
	}
	if strings.builder_len(sb) == 0 {
		Editor_Log(state, .Info, "%s already has the %s of %s", rel, "guard callbacks" if guards else "callbacks", name)
		return
	}
	insertLine := buf.buffer_line_count(b)
	for ln := buf.buffer_line_count(b) - 1; ln >= 0; ln -= 1 {
		if strings.trim_space(buf.buffer_line_str(b, ln)) == fmt.tprintf("return %s", cls) {insertLine = ln; break}
	}
	group := buf.buffer_next_group(b)
	buf.buffer_insert_text(b, {insertLine, 0}, strings.to_string(sb), group)
	code_set_single_cursor(b, {insertLine + 3, 0}, false)
	doc.scrollToCursor = true
	Editor_Log(state, .Info, "Added %s's %s to %s", name, "guard callbacks" if guards else "callbacks", rel)
}

// --- side panel ---------------------------------------------------------------------

@(private = "file")
smg_side_panel :: proc(state: ^EditorState, sm: ^e.StateMachineNode) {
	avail := imgui.GetContentRegionAvail().x
	switch {
	case smg.selTr >= 0 && smg.selTr < len(sm.transitions):
		UI_PanelTitle(ICON_FA_ARROW_RIGHT, "Transition")
		// Live: its conditions' results while it's a way out of the current state.
		view := smg_view(state, sm)
		live, hasLive := u32(0), false
		block := e.SM_Block.None
		if view.running do for w in view.ways do if int(w.transition) == smg.selTr do live, hasLive, block = w.mask, true, w.block
		if SM_TransitionEditor(state, sm, &sm.transitions[smg.selTr], smg.selTr, avail, live, hasLive) do smg_delete_selection(state, sm)
		t := sm.transitions[smg.selTr]
		if hasLive && block != .None {
			color := UI_TEXT_DIM if block == .Manual else UI_DANGER
			imgui.TextColored(color, "%s", fmt.ctprintf("%s  %s%s", ICON_FA_LOCK, "" if block == .Manual else "blocked: ", e.StateMachine_BlockText(sm, block, smg_current_name(sm, view), t.to, view.time)))
		}
		if ti := e.StateMachine_FindState(sm, t.to); ti >= 0 && (t.from == t.to || t.from == e.SM_ANY) && !sm.states[ti].allowRetrigger {
			if t.from == t.to do imgui.TextColored(UI_WARNING, "%s", fmt.ctprintf("%s  %s doesn't allow retriggering: this arrow is never taken", ICON_FA_TRIANGLE_EXCLAMATION, t.to))
			else do UI_DimTextWrapped(fmt.tprintf("Not taken while already in %s (Allow Retrigger is off).", t.to))
		}
		imgui.Dummy({0, 4})
		if t.mode == .Manual {
			UI_DimTextWrapped(fmt.tprintf("Manual: the machine never takes it by itself. A script does: sm_transition(\"%s\") - the guards and these conditions (if any) must hold then; {force = true} skips both.", t.to))
		} else {
			UI_DimTextWrapped("Automatic: taken by itself when its conditions hold (ANDed; Or starts another group; none: at once). Arrows are checked in order, one change per frame. The states' guards can still refuse it; a script's sm_transition can take it too.")
		}
	case smg.selState >= 0 && smg.selState < len(sm.states):
		smg_state_panel(state, sm, smg.selState, avail)
	case:
		UI_PanelTitle(ICON_FA_DIAGRAM_PROJECT, sm.name)
		UI_DimText(fmt.tprintf("%d states, %d transitions, %d parameters", len(sm.states), len(sm.transitions), len(sm.params)))
		view := smg_view(state, sm)
		if view.running && view.current >= 0 {
			imgui.TextColored(UI_ACCENT, "%s", fmt.ctprintf("%s  %s  (%.1fs)%s", ICON_FA_PLAY, sm.states[view.current].name, view.time, "  - in the running game" if view.remote else ""))
		}
		Drive_Item("smg.live")
		smg_ways_panel(state, sm, view)
		if len(view.params) > 0 || len(view.triggers) > 0 {
			imgui.SeparatorText("Parameters & Triggers")
			for p in view.params do imgui.TextUnformatted(fmt.ctprintf("%s = %s", p.name, SM_ParamText(sm, p.name, p.value)))
			for t in view.triggers do if t.pending {
				imgui.TextColored(UI_WARNING, "%s", fmt.ctprintf("%s  %s  %s", ICON_FA_BOLT, t.name, SM_TriggerLeft(sm, t)))
			}
			Drive_Item("smg.live-values")
			if UI_Button("Edit Parameters & Triggers", "smg.goto-params") do stateGraphPageRequest = .Params
		}
		UI_DimText("Select a state or an arrow to edit it.")
	}
	// The history (while running / after a run).
	hist := smg_view(state, sm).history
	if len(hist) > 0 {
		imgui.SeparatorText("History")
		#reverse for h, k in hist {
			if k < len(hist) - 12 do break
			from := h.from if h.from != "" else "-"
			imgui.TextColored(UI_TEXT_FAINT, "%s", fmt.ctprintf("%6.2fs", h.time))
			imgui.SameLine()
			imgui.TextUnformatted(fmt.ctprintf("%s %s %s", from, ICON_FA_ARROW_RIGHT, h.to))
			imgui.SameLine()
			UI_DimText(h.why)
		}
		Drive_Item("smg.history")
	}
}

@(private = "file")
smg_state_panel :: proc(state: ^EditorState, sm: ^e.StateMachineNode, i: int, avail: f32) {
	s := &sm.states[i]
	UI_PanelTitle(ICON_FA_CIRCLE, "State")
	@(static) nameBuf: [64]u8
	@(static) nameFor: int = -1
	if nameFor != i || !imgui.IsAnyItemActive() {
		if nameFor != i || string(cstring(raw_data(nameBuf[:]))) != s.name {
			nameBuf = {}
			copy(nameBuf[:len(nameBuf) - 1], s.name)
		}
		nameFor = i
	}
	if UI_BeginProps("##smgstate") {
		UI_PropLabel("Name")
		imgui.SetNextItemWidth(-1)
		if imgui.InputText("##smg_name", cstring(raw_data(nameBuf[:])), len(nameBuf), {.EnterReturnsTrue, .CharsNoBlank}) || imgui.IsItemDeactivatedAfterEdit() {
			v := strings.trim_space(string(cstring(raw_data(nameBuf[:]))))
			if v != "" && v != s.name {
				if e.StateMachine_FindState(sm, v) >= 0 {
					Editor_Log(state, .Warn, "A state named %s already exists", v)
				} else {
					Editor_RecordUndo(state, "Rename state")
					e.StateMachine_RenameState(sm, i, v)
				}
			}
		}
		Drive_Item("smg.state-name")
		UI_PropLabel("Animation")
		player := e.StateMachine_Player(sm, state.activeScene.manager)
		names := make([dynamic]string, context.temp_allocator)
		append(&names, "(none: gameplay)")
		if player != nil do for a in player.animations do if a != nil do append(&names, a.name)
		cur := 0
		for n, k in names do if k > 0 && n == s.animation do cur = k
		if k, changed := UI_Combo("smg.state-anim", cur, names[:]); changed {
			Editor_RecordUndo(state, "State animation")
			s.animation = strings.clone(names[k], sm.allocator) if k > 0 else ""
		}
		UI_Tooltip("Played on entering the state (none: a gameplay state - use its script callbacks)")
		UI_PropLabel("Child Machine")
		machines := make([dynamic]string, context.temp_allocator)
		append(&machines, "(none)")
		mgr := state.activeScene.manager
		for n in mgr.nodes do if n != nil && n != sm && n.typeId == e.StateMachineNode && !n.removing do append(&machines, e.Node_RelativePath(mgr, sm, n))
		cc := 0
		for n, k in machines do if k > 0 && n == s.child do cc = k
		if k, changed := UI_Combo("smg.state-child", cc, machines[:]); changed {
			Editor_RecordUndo(state, "Child machine")
			s.child = strings.clone(machines[k], sm.allocator) if k > 0 else ""
		}
		UI_Tooltip("Another state machine that runs only while this state is current (sub-states)")
		UI_PropLabel("Initial")
		isInit := sm.initial == s.name
		if imgui.Checkbox("##smg_init", &isInit) && isInit {
			Editor_RecordUndo(state, "Initial state")
			sm.initial = s.name
		}
		Drive_Item("smg.state-initial")
		UI_PropLabel("Break on Enter")
		brk := s.breakOnEnter
		if imgui.Checkbox("##smg_break", &brk) do smg_set_break(state, sm, i, brk)
		Drive_Item("smg.state-break")
		UI_Tooltip("Pause when the machine enters this state (Simulate and Play)")
		UI_PropLabel("Allow Retrigger")
		if imgui.Checkbox("##smg_retrigger", &s.allowRetrigger) do Editor_RecordUndo(state, "Allow retrigger")
		Drive_Item("smg.state-retrigger")
		UI_Tooltip("It may go to itself (an arrow from it to it, or from Any state): on_exit, on_enter and the animation run again. Off: such arrows are skipped while it's current.")
		UI_EndProps()
	}
	view := smg_view(state, sm)
	isCurrent := view.running && view.current == i
	if isCurrent do smg_ways_panel(state, sm, view)
	smg_guards_section(state, sm, i, avail, view, isCurrent)
	imgui.SeparatorText("Script callbacks")
	rel, owner := smg_script_rel(state, sm)
	if rel != "" {
		UI_DimText(fmt.tprintf("on %s's script (%s):", owner.name, rel))
		for m in ([3]string{"on_enter_", "on_update_", "on_exit_"}) do imgui.TextUnformatted(fmt.ctprintf("  %s%s", m, s.name))
		if UI_Button(fmt.tprintf("%s  Add Missing Callbacks", ICON_FA_CODE), "smg.add-callbacks") do smg_add_callbacks(state, sm, s.name)
		imgui.SameLine()
		if UI_Button(fmt.tprintf("%s  Add Guard Callbacks", ICON_FA_LOCK), "smg.add-guard-callbacks") do smg_add_callbacks(state, sm, s.name, guards = true)
		UI_Tooltip(fmt.tprintf("can_exit_%s(next) / can_enter_%s(previous): return false to refuse the change", s.name, s.name))
	} else {
		UI_DimTextWrapped("Attach a script to the machine or its parent for on_enter_ / on_update_ / on_exit_ callbacks (and can_exit_ / can_enter_ guards).")
	}
	imgui.SeparatorText("Transitions out")
	for t, ti in sm.transitions {
		if t.from != s.name do continue
		if imgui.Selectable(fmt.ctprintf("%s %s   %s##smgout%d", ICON_FA_ARROW_RIGHT, t.to, smg_arrow_label(t), ti)) do smg.selTr, smg.selState = ti, -1
	}
}

// smg_current_name: the live current state's name ("" none).
@(private = "file")
smg_current_name :: proc(sm: ^e.StateMachineNode, view: SMG_View) -> string {
	return sm.states[view.current].name if view.current >= 0 && view.current < len(sm.states) else ""
}

// smg_guard_summary: one line per guard of a state (the lock's tooltip).
@(private = "file")
smg_guard_summary :: proc(s: e.SM_State) -> string {
	sb := strings.builder_make(context.temp_allocator)
	if s.minTime > 0 do fmt.sbprintf(&sb, "Leave after %.2gs\n", s.minTime)
	if s.noInterrupt do strings.write_string(&sb, "Any state can't interrupt it\n")
	if len(s.leaveWhen) > 0 do fmt.sbprintf(&sb, "Can leave when %s\n", smg_condition_text(s.leaveWhen[:]))
	if len(s.enterWhen) > 0 do fmt.sbprintf(&sb, "Can enter when %s\n", smg_condition_text(s.enterWhen[:]))
	return strings.trim_right(strings.to_string(sb), "\n")
}

// smg_guards_section: a state's guards in the side panel.
@(private = "file")
smg_guards_section :: proc(state: ^EditorState, sm: ^e.StateMachineNode, i: int, avail: f32, view: SMG_View, isCurrent: bool) {
	s := &sm.states[i]
	imgui.SeparatorText("Guards")
	UI_Tooltip("An arrow says the machine may go there; guards let a state refuse: they apply to every arrow (Automatic or Manual), Any state and sm_transition (not with force = true)")
	if UI_BeginProps("##smgguards") {
		UI_PropLabel("Leave After")
		imgui.SetNextItemWidth(-1)
		imgui.DragFloat("##smg_min", &s.minTime, 0.01, 0, 60, "%.2f s" if s.minTime > 0 else "any time")
		undo_on_activate(state, "Leave after")
		if s.minTime < 0 do s.minTime = 0
		Drive_Item("smg.state-min-time")
		UI_Tooltip("No arrow leaves this state before it has been in it this long (e.g. an attack that can't be cancelled)")
		UI_PropLabel("Any State Interrupts")
		interrupt := !s.noInterrupt
		if imgui.Checkbox("##smg_interrupt", &interrupt) {
			Editor_RecordUndo(state, "Interruptible")
			s.noInterrupt = !interrupt
		}
		Drive_Item("smg.state-interruptible")
		UI_Tooltip("Off: arrows from Any state don't fire while in this state (e.g. dead, a cutscene)")
		UI_EndProps()
	}
	imgui.TextUnformatted("Can leave when")
	imgui.SameLine()
	UI_DimText("(empty: any time)" if len(s.leaveWhen) == 0 else "(else it stays)")
	SM_ConditionList(state, sm, &s.leaveWhen, "smg.leave", i, avail, live = view.leave, hasLive = isCurrent)
	imgui.TextUnformatted("Can enter when")
	imgui.SameLine()
	UI_DimText("(empty: any time)" if len(s.enterWhen) == 0 else "(else nothing comes in)")
	// Live: when the current state has a way here, that way's enter results.
	enterLive, enterHas := u32(0), false
	if view.running do for w in view.ways do if int(w.transition) < len(sm.transitions) && sm.transitions[w.transition].to == s.name do enterLive, enterHas = w.enterMask, true
	SM_ConditionList(state, sm, &s.enterWhen, "smg.enter", i, avail, live = enterLive, hasLive = enterHas)
}

// smg_ways_panel: live, each arrow out of the current state - its
// conditions' results and what blocks it.
@(private = "file")
smg_ways_panel :: proc(state: ^EditorState, sm: ^e.StateMachineNode, view: SMG_View) {
	if !view.running || view.current < 0 || view.current >= len(sm.states) do return
	imgui.SeparatorText("Ways out (live)")
	if len(view.ways) == 0 {
		UI_DimText("No arrows out of this state.")
		return
	}
	cur := sm.states[view.current].name
	for w, k in view.ways {
		if int(w.transition) >= len(sm.transitions) do continue
		t := sm.transitions[w.transition]
		from := "Any " if t.from == e.SM_ANY else ""
		if imgui.Selectable(fmt.ctprintf("%s%s %s   %s##smgway%d", from, ICON_FA_ARROW_RIGHT, t.to, smg_arrow_label(t), k)) do smg.selTr, smg.selState = int(w.transition), -1
		Drive_Item(fmt.tprintf("smg.way:%s", t.to))
		imgui.Indent()
		switch {
		case w.block == .Manual:
			UI_DimText(fmt.tprintf("%s  %s", ICON_FA_HAND_POINTER, e.StateMachine_BlockText(sm, w.block, cur, t.to, view.time)))
		case w.block != .None:
			imgui.TextColored(UI_DANGER if w.arrow else UI_TEXT_DIM, "%s", fmt.ctprintf("%s  %s%s", ICON_FA_LOCK, "blocked: " if w.arrow else "", e.StateMachine_BlockText(sm, w.block, cur, t.to, view.time)))
		case w.arrow:
			imgui.TextColored(UI_SUCCESS, "%s", fmt.ctprintf("%s  fires", ICON_FA_CIRCLE_CHECK))
		case:
			// Which conditions are still missing.
			missing := strings.builder_make(context.temp_allocator)
			for c, j in t.conditions {
				if c.op == .Or || (j < e.SM_CONDITIONS_MAX && w.mask & (1 << u32(j)) != 0) do continue
				if strings.builder_len(missing) > 0 do strings.write_string(&missing, ", ")
				strings.write_string(&missing, smg_condition_text(t.conditions[j:j + 1]))
			}
			UI_DimText(fmt.tprintf("waiting for %s", strings.to_string(missing)))
		}
		imgui.Unindent()
	}
}

// StateGraph_Query: drive queries smg-*.
StateGraph_Query :: proc(q: string) -> (string, bool) {
	switch q {
	case "smg-selected":
		sm := smg.node
		if sm == nil do return "", true
		if smg.selTr >= 0 && smg.selTr < len(sm.transitions) do return fmt.tprintf("transition %d", smg.selTr), true
		if smg.selState == -2 do return "Any", true
		if smg.selState >= 0 && smg.selState < len(sm.states) do return sm.states[smg.selState].name, true
		return "", true
	case "smg-ways":
		// "to:fires|waiting|<block>, ..." for the machine shown (live).
		sm := smg.node
		if sm == nil do return "", true
		view := smg_view(&GlobalEditor, sm)
		sb := strings.builder_make(context.temp_allocator)
		for w, k in view.ways {
			if int(w.transition) >= len(sm.transitions) do continue
			if k > 0 do strings.write_string(&sb, ", ")
			status := "waiting"
			if w.block != .None do status = fmt.tprintf("%v", w.block)
			else if w.arrow do status = "fires"
			fmt.sbprintf(&sb, "%s:%s", sm.transitions[w.transition].to, status)
		}
		return strings.to_string(sb), true
	case "smg-zoom": return fmt.tprintf("%.2f", smg.zoom), true
	case "smg-pan": return fmt.tprintf("%.0f,%.0f", smg.pan.x, smg.pan.y), true
	}
	return "", false
}
