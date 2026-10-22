package editor

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import "core:c/libc"
import imgui "lib/imgui"

// ============================================================================
// Play-in-editor link: the game started with Play runs with --editor-link
// (engine/editor_link.odin). The editor writes commands to its stdin and
// reads "@ore:" replies from its output. The bottom panel's Game tab shows
// the running game's scene tree (refreshed twice a second), the selected
// node's live properties (editable: Enter sends the value), and Pause /
// Resume / Step. Saving a scene while the game runs reloads it there;
// scripts and images reload by themselves.
// ============================================================================

Remote_Row :: struct {
	depth:    int,
	name:     string,
	type:     string,
	path:     string,
	enabled:  bool,
	visible:  bool,
	children: bool,
}

@(private = "file")
remote: struct {
	input:      ^os.File, // the game's stdin (write end)
	rows:       [dynamic]Remote_Row,
	scene:      string,
	frame:      int,
	frozen:     bool,
	paused:     bool,
	selected:   string,
	props:      [dynamic][2]string, // name, value
	edit:       map[string][128]u8,
	treeAt:     time.Tick,
	nodeAt:     time.Tick,
	steps:      int, // "@ore:stepped" replies (drives)
	reloads:    int, // "@ore:reloaded" replies
	connected:  bool,
	collapsed:  map[string]bool,
}

// RemoteGame_Attach: the game was launched; `input` is its stdin.
RemoteGame_Attach :: proc(input: ^os.File) {
	RemoteGame_Detach()
	remote.input = input
	// A write after the game quit must fail, not kill the editor (SIGPIPE).
	when ODIN_OS != .Windows {
		libc.signal(13 /* SIGPIPE */, auto_cast libc.SIG_IGN)
	}
}

RemoteGame_Detach :: proc() {
	if remote.input != nil do os.close(remote.input)
	remote.input = nil
	remote.connected = false
	remote.paused = false
	remote.frozen = false
	remote_clear_rows()
	for p in remote.props {delete(p[0]); delete(p[1])}
	clear(&remote.props)
}

RemoteGame_Connected :: proc() -> bool {return remote.input != nil && remote.connected}

// RemoteGame_Send writes one command line to the game.
RemoteGame_Send :: proc(line: string) -> bool {
	if remote.input == nil do return false
	data := strings.concatenate({line, "\n"}, context.temp_allocator)
	if _, err := os.write(remote.input, transmute([]u8)data); err != nil {
		RemoteGame_Detach()
		return false
	}
	return true
}

@(private = "file")
remote_clear_rows :: proc() {
	for r in remote.rows {
		delete(r.name)
		delete(r.type)
		delete(r.path)
	}
	clear(&remote.rows)
}

// RemoteGame_HandleLine takes a line of game output; true when it was a
// link reply (not shown in the console).
RemoteGame_HandleLine :: proc(state: ^EditorState, line: string) -> bool {
	if !strings.has_prefix(line, "@ore:") do return false
	msg := line[5:]
	kind, rest := msg, ""
	if i := strings.index_byte(msg, ' '); i >= 0 do kind, rest = msg[:i], msg[i + 1:]
	switch kind {
	case "hello": remote.connected = true
	case "paused": remote.paused = true
	case "resumed": remote.paused = false
	case "stepped": remote.steps += 1
	case "reloaded":
		remote.reloads += 1
		Editor_Log(state, .Info, "Reloaded in the running game: %s", rest)
	case "tree": remote_parse_tree(rest)
	case "node": remote_parse_node(rest)
	case "set":
	}
	return true
}

@(private = "file")
remote_parse_tree :: proc(text: string) {
	v, err := json.parse(transmute([]u8)text, allocator = context.temp_allocator)
	if err != .None do return
	obj, ok := v.(json.Object)
	if !ok do return
	remote.connected = true
	#partial switch f in obj["frame"] {
	case json.Integer: remote.frame = int(f)
	case json.Float: remote.frame = int(f)
	}
	remote.frozen = bool(obj["frozen"].(json.Boolean) or_else false)
	remote.paused = bool(obj["paused"].(json.Boolean) or_else false)
	delete(remote.scene)
	remote.scene = strings.clone(string(obj["scene"].(json.String) or_else ""))
	remote_clear_rows()
	walk :: proc(v: json.Value, depth: int, parentPath: string) {
		o, isObj := v.(json.Object)
		if !isObj do return
		name := string(o["name"].(json.String) or_else "?")
		path := "" if depth == 0 else (name if parentPath == "" else strings.concatenate({parentPath, "/", name}, context.temp_allocator))
		kids, hasKids := o["children"].(json.Array)
		append(&remote.rows, Remote_Row{
			depth = depth, name = strings.clone(name), type = strings.clone(string(o["type"].(json.String) or_else "")),
			path = strings.clone(path), enabled = bool(o["enabled"].(json.Boolean) or_else true),
			visible = bool(o["visible"].(json.Boolean) or_else true), children = hasKids && len(kids) > 0,
		})
		if hasKids do for k in kids do walk(k, depth + 1, path)
	}
	walk(obj["root"], 0, "")
}

@(private = "file")
remote_parse_node :: proc(text: string) {
	v, err := json.parse(transmute([]u8)text, allocator = context.temp_allocator)
	if err != .None do return
	obj, _ := v.(json.Object)
	if string(obj["path"].(json.String) or_else "") != remote.selected do return
	for p in remote.props {delete(p[0]); delete(p[1])}
	clear(&remote.props)
	if props, ok := obj["props"].(json.Array); ok {
		for pv in props {
			pair, isArr := pv.(json.Array)
			if !isArr || len(pair) != 2 do continue
			append(&remote.props, [2]string{strings.clone(string(pair[0].(json.String) or_else "")), strings.clone(string(pair[1].(json.String) or_else ""))})
		}
	}
}

// RemoteGame_Update polls the game (call every frame).
RemoteGame_Update :: proc(state: ^EditorState) {
	if !state.gameProcessRunning {
		if remote.input != nil do RemoteGame_Detach()
		return
	}
	if remote.input == nil do return
	if time.tick_since(remote.treeAt) > 500 * time.Millisecond {
		remote.treeAt = time.tick_now()
		RemoteGame_Send("tree")
	}
	if remote.selected != "" && time.tick_since(remote.nodeAt) > 250 * time.Millisecond {
		remote.nodeAt = time.tick_now()
		RemoteGame_Send(fmt.tprintf("inspect %s", remote.selected))
	}
}

// RemoteGame_Query answers the drive queries remote-*.
RemoteGame_Query :: proc(q: string) -> (string, bool) {
	switch q {
	case "remote-connected": return "true" if RemoteGame_Connected() else "false", true
	case "remote-paused": return "true" if remote.paused else "false", true
	case "remote-frame": return fmt.tprint(remote.frame), true
	case "remote-steps": return fmt.tprint(remote.steps), true
	case "remote-reloads": return fmt.tprint(remote.reloads), true
	case "remote-nodes": return fmt.tprint(len(remote.rows)), true
	case "remote-names":
		names := make([dynamic]string, context.temp_allocator)
		for r in remote.rows do append(&names, r.name)
		return strings.join(names[:], ",", context.temp_allocator), true
	}
	if strings.has_prefix(q, "remote-prop:") {
		for p in remote.props do if p[0] == q[len("remote-prop:"):] do return p[1], true
		return "<none>", true
	}
	return "", false
}

// GamePanel_Render: the bottom panel's Game tab.
GamePanel_Render :: proc(state: ^EditorState) {
	if !state.gameProcessRunning {
		imgui.Dummy({0, 6})
		UI_DimText("Play the game (F5) to see its live scene tree here: inspect and change nodes while it runs, pause and step frames.")
		return
	}
	if !RemoteGame_Connected() {
		UI_DimText("Connecting to the game...")
		return
	}
	// Toolbar.
	if remote.paused {
		if UI_PrimaryButton(fmt.tprintf("%s  Resume", ICON_FA_PLAY), "remote.resume") do RemoteGame_Send("resume")
	} else {
		if UI_Button(fmt.tprintf("%s  Pause", ICON_FA_PAUSE), "remote.pause") do RemoteGame_Send("pause")
	}
	imgui.SameLine()
	if UI_Button(fmt.tprintf("%s  Step", ICON_FA_FORWARD_STEP), "remote.step") do RemoteGame_Send("step 1")
	UI_Tooltip("Run one frame (1/60 s) and pause")
	imgui.SameLine()
	UI_DimText(fmt.tprintf("frame %d  ·  %s%s", remote.frame, remote.scene, "  ·  paused" if remote.paused else ""))

	avail := imgui.GetContentRegionAvail()
	if imgui.BeginChild("##remote_tree", {avail.x * 0.45, 0}, {.Borders}, {}) {
		hideBelow := -1
		for r in remote.rows {
			if hideBelow >= 0 {
				if r.depth > hideBelow do continue
				hideBelow = -1
			}
			if r.depth == 0 do continue // the root
			imgui.Indent(f32(r.depth - 1) * 14)
			closed := remote.collapsed[r.path]
			arrow := (ICON_FA_CARET_RIGHT if closed else ICON_FA_CARET_DOWN) if r.children else " "
			col := UI_TEXT if r.enabled && r.visible else UI_TEXT_FAINT
			imgui.PushStyleColorImVec4(.Text, col)
			if imgui.Selectable(fmt.ctprintf("%s  %s  %s###r_%s", arrow, r.name, "", r.path), remote.selected == r.path) {
				if r.children && imgui.GetIO().MousePos.x < imgui.GetItemRectMin().x + 18 {
					remote.collapsed[strings.clone(r.path)] = !closed
				} else if remote.selected != r.path {
					delete(remote.selected)
					remote.selected = strings.clone(r.path)
					remote.nodeAt = {}
					clear(&remote.edit)
				}
			}
			imgui.PopStyleColor()
			Drive_Item(fmt.tprintf("remote.node:%s", r.path))
			imgui.SameLine()
			UI_DimText(r.type)
			imgui.Unindent(f32(r.depth - 1) * 14)
			if r.children && closed do hideBelow = r.depth
		}
	}
	imgui.EndChild()
	imgui.SameLine()
	if imgui.BeginChild("##remote_props", {0, 0}, {.Borders}, {}) {
		if remote.selected == "" {
			UI_DimText("Select a node to see its live properties.")
		} else if UI_BeginProps("##rprops") {
			for p in remote.props {
				UI_PropLabel(pretty_name(p[0]))
				key := p[0]
				buf, editing := remote.edit[key]
				if !editing do copy(buf[:len(buf) - 1], p[1])
				imgui.SetNextItemWidth(-1)
				readonly := key == "global"
				if readonly do imgui.BeginDisabled(true)
				if imgui.InputText(fmt.ctprintf("##rp_%s", key), cstring(raw_data(buf[:])), len(buf), {.EnterReturnsTrue}) {
					RemoteGame_Send(fmt.tprintf("set %s %s %s", remote.selected, key, string(cstring(raw_data(buf[:])))))
					delete_key(&remote.edit, key)
					remote.nodeAt = {}
				} else if imgui.IsItemActive() {
					remote.edit[key] = buf // typing: don't overwrite with live values
				} else if editing && !imgui.IsItemActive() {
					delete_key(&remote.edit, key)
				}
				if readonly do imgui.EndDisabled()
				Drive_Item(fmt.tprintf("remote.prop:%s", key))
			}
			UI_EndProps()
		}
	}
	imgui.EndChild()
}
