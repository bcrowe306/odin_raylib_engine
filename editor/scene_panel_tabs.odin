package editor

import "core:c"
import "core:fmt"
import "core:os"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// The Scene panel's tabs (#195): Tree (the node tree), Signals (every saved
// connection in the scene: source . event -> target : method; click selects
// the source, double-click opens the method), Settings (the scene's own
// settings, out of the Inspector).
// ============================================================================

Scene_Panel_Tab :: enum {
	Tree,
	Signals,
	Settings,
}

scenePanelTab: Scene_Panel_Tab
scenePanelTabRequest: Maybe(Scene_Panel_Tab) // select this tab next frame

// ScenePanel_Signals: the scene's connections, one row each.
ScenePanel_Signals :: proc(state: ^EditorState) {
	mgr := state.activeScene.manager
	Row :: struct {
		source: ^e.Node,
		index:  int,
	}
	rows := make([dynamic]Row, context.temp_allocator)
	collect :: proc(mgr: ^e.NodeManager, n: ^e.Node, rows: ^[dynamic]Row) {
		for c, i in n.signalConnections do if c.node == nil do append(rows, Row{n, i}) // (runtime-only links aren't the scene's)
		for k in e.GetChildrenView(mgr, n) do if k != nil do collect(mgr, k, rows)
	}
	collect(mgr, state.activeScene.rootNode, &rows)
	if len(rows) == 0 {
		imgui.Dummy({0, 6})
		imgui.PushTextWrapPos(0)
		imgui.PushStyleColorImVec4(.Text, UI_TEXT_FAINT)
		imgui.TextWrapped("No signal connections in this scene. Select a node and connect one of its events in the Inspector's Signals section.")
		imgui.PopStyleColor()
		imgui.PopTextWrapPos()
		Drive_Item("scene.signals-empty")
		return
	}
	imgui.PushTextWrapPos(0)
	imgui.PushStyleColorImVec4(.Text, UI_TEXT_DIM)
	imgui.TextWrapped("%s", fmt.ctprintf("%d connection(s) - click: select the node, double-click: open the method", len(rows)))
	imgui.PopStyleColor()
	imgui.PopTextWrapPos()
	// The scripts' text (for "is the method there"), read once per frame.
	scripts := make(map[string]string, 8, context.temp_allocator)
	has_method :: proc(state: ^EditorState, scripts: ^map[string]string, target: ^e.Node, method: string) -> bool {
		rel := node_script_rel(state, target)
		if rel == "" do return false
		text, ok := scripts[rel]
		if !ok {
			data, err := os.read_entire_file(fmt.tprintf("%s/%s", state.projectPath, rel), context.temp_allocator)
			text = string(data) if err == nil else ""
			scripts[rel] = text
		}
		return strings.contains(text, fmt.tprintf(":%s(", method)) || strings.contains(text, fmt.tprintf(".%s(", method))
	}
	if !imgui.BeginChild("##scene_signals", {0, 0}, {}, {}) {
		imgui.EndChild()
		return
	}
	defer imgui.EndChild()
	lineH := imgui.GetTextLineHeight()
	dl := imgui.GetWindowDrawList()
	disconnect: struct {node: ^e.Node, signal, target, method: string}
	for r, ri in rows {
		cn := r.source.signalConnections[r.index]
		target := e.Node_ResolvePath(mgr, r.source, cn.target)
		problem := ""
		if target == nil do problem = fmt.tprintf("%s isn't in the scene", cn.target)
		else if node_script_rel(state, target) == "" do problem = fmt.tprintf("%s has no script", target.name)
		else if !has_method(state, &scripts, target, cn.method) do problem = fmt.tprintf("%s's script has no %s()", target.name, cn.method)
		imgui.PushIDInt(c.int(ri))
		// A row: "node . event" over "-> target : method()", buttons right.
		sel := state.selectedNode == r.source
		if imgui.Selectable("##signal_row", sel, {.AllowDoubleClick, .AllowOverlap}, {0, lineH * 2 + 8}) {
			Editor_SelectNode(state, r.source, false)
			if imgui.IsMouseDoubleClicked(.Left) && !Signals_OpenHandler(state, target, cn.method) do Editor_Log(state, .Warn, "Can't open %s: %s", cn.method, problem if problem != "" else "no script")
		}
		Drive_Item(fmt.tprintf("scene.signal:%s:%s:%s", r.source.name, cn.signal, cn.method))
		UI_Tooltip(fmt.tprintf("%s.%s -> %s:%s(value, source)%s", r.source.name, cn.signal, cn.target, cn.method, fmt.tprintf("\n%s", problem) if problem != "" else ""))
		mn, mx := imgui.GetItemRectMin(), imgui.GetItemRectMax()
		textR := mx.x - 54
		imgui.DrawList_PushClipRect(dl, mn, {textR, mx.y}, true)
		imgui.DrawList_AddText(dl, {mn.x + 4, mn.y + 3}, col_u32(UI_TEXT), fmt.ctprintf("%s  %s", Editor_NodeIcon(r.source), r.source.name))
		nameW := imgui.CalcTextSize(fmt.ctprintf("%s  %s", Editor_NodeIcon(r.source), r.source.name)).x
		imgui.DrawList_AddText(dl, {mn.x + 10 + nameW, mn.y + 3}, col_u32(UI_WARNING), fmt.ctprintf("%s %s", ICON_FA_BOLT, cn.signal))
		col := UI_DANGER if target == nil else (UI_WARNING if problem != "" else UI_ACCENT)
		imgui.DrawList_AddText(dl, {mn.x + 16, mn.y + lineH + 5}, col_u32(col), fmt.ctprintf("%s  %s : %s()", ICON_FA_LINK, target.name if target != nil else cn.target, cn.method))
		imgui.DrawList_PopClipRect(dl)
		if problem != "" do Drive_ItemRect(fmt.tprintf("scene.signal-problem:%s:%s", r.source.name, cn.method), {mn.x, mn.y + lineH}, mx, inWindow = true)
		after := imgui.GetCursorScreenPos()
		imgui.SetCursorScreenPos({mx.x - 50, mn.y + (mx.y - mn.y - 22) * 0.5})
		if UI_IconButton(ICON_FA_CODE, fmt.tprintf("scene.signal-open:%s:%s", r.source.name, cn.method), "Open the method", size = 22) {
			if !Signals_OpenHandler(state, target, cn.method) do Editor_Log(state, .Warn, "Can't open %s: %s", cn.method, problem if problem != "" else "no script")
		}
		imgui.SameLine(0, 2)
		if UI_IconButton(ICON_FA_LINK_SLASH, fmt.tprintf("scene.signal-disconnect:%s:%s", r.source.name, cn.method), "Disconnect (removes the generated handler)", size = 22) {
			disconnect = {r.source, cn.signal, cn.target, cn.method}
		}
		imgui.SetCursorScreenPos(after)
		imgui.PopID()
	}
	if disconnect.node != nil do Signals_Disconnect(state, disconnect.node, disconnect.signal, disconnect.target, disconnect.method)
}

// ScenePanel_Settings: the scene's own settings (once the Inspector's, with
// the root selected).
ScenePanel_Settings :: proc(state: ^EditorState) {
	if imgui.BeginChild("##scene_settings", {0, 0}, {}, {}) do inspector_scene_settings(state, state.activeScene)
	imgui.EndChild()
}
