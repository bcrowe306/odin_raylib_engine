package editor

import "core:c"
import "core:fmt"
import "core:strings"
import rl "vendor:raylib"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Bottom panel: Console (editor, build and game output), Profiler, Game, tools.
// ============================================================================

consoleFilterBuf: [128]u8
animTabRequest := false // select the Animation tab next frame
bottomTabRequest: Maybe(BottomTab) // select this tab next frame

// Following the selection (Settings > General: Bottom Panel Follows
// Selection): an AnimationPlayer shows the Animation tab, a particle emitter
// Particles, an LDtk level LDtk; selecting something else returns to the tab
// shown before. Picking a tab by hand stops the return.
@(private = "file")
follow: struct {
	lastSel: ^e.Node,
	active:  bool,      // the shown tab was picked for the selection
	tab:     BottomTab, // that tab
	prev:    BottomTab, // the tab to go back to
}

// bottom_tab_for: the tool tab for a node (false: none).
bottom_tab_for :: proc(node: ^e.Node) -> (BottomTab, bool) {
	if node == nil do return {}, false
	switch node.typeId {
	case e.AnimationPlayerNode: return .Animation, true
	case e.ParticleEmitterNode: return .Particles, true
	case e.LdtkLevelNode:       return .Ldtk, true
	case e.StateMachineNode:    return .StateGraph, true
	}
	return {}, false
}

@(private = "file")
bottom_follow_selection :: proc(state: ^EditorState) {
	sel := state.selectedNode
	if sel == follow.lastSel do return
	follow.lastSel = sel
	if !GlobalSettings.autoBottomPanel do return
	if want, ok := bottom_tab_for(sel); ok {
		if state.bottomTab == want && !follow.active do return // already there by hand
		if !follow.active do follow.prev = state.bottomTab
		follow.active, follow.tab = true, want
		bottomTabRequest = want
	} else if follow.active {
		follow.active = false
		bottomTabRequest = follow.prev
	}
}

// BottomPanel_Tab: the tab shown (drives).
BottomPanel_Tab :: proc(state: ^EditorState) -> BottomTab {return state.bottomTab}
consoleShow: [LogLevel]bool = {.Info = true, .Warn = true, .Error = true}

BottomPanel_Render :: proc(state: ^EditorState) {
	animTimelineFocused = false // set again by the Animation tab when it has focus
	stateGraphFocused = false   // ... and the State Machine tab
	defer imgui.End()
	if !imgui.Begin("Console###BottomPanelWindow") do return
	bottom_follow_selection(state)
	// Tab requests (the old per-tab flags too).
	if animTabRequest {bottomTabRequest = .Animation; animTabRequest = false}
	if particleTabRequest {bottomTabRequest = .Particles; particleTabRequest = false}
	if ldtkTabRequest {bottomTabRequest = .Ldtk; ldtkTabRequest = false}
	req, hasReq := bottomTabRequest.?
	bottomTabRequest = nil
	flags :: proc(t: BottomTab, req: BottomTab, has: bool) -> imgui.TabItemFlags {return {.SetSelected} if has && req == t else {}}
	if imgui.BeginTabBar("##BottomPanelTabs", {}) {
		counts: [LogLevel]int
		for l in state.logs do counts[l.level] += 1
		label := fmt.ctprintf("%s  Console###ConsoleTab", ICON_FA_TERMINAL)
		if counts[.Error] > 0 do label = fmt.ctprintf("%s  Console  %s %d###ConsoleTab", ICON_FA_TERMINAL, ICON_FA_CIRCLE_XMARK, counts[.Error])
		if imgui.BeginTabItem(label, nil, flags(.Console, req, hasReq)) {
			state.bottomTab = .Console
			BottomPanel_RenderConsole(state, counts)
			imgui.EndTabItem()
		}
		Drive_Item("bottom:console")
		if imgui.BeginTabItem(fmt.ctprintf("%s  Profiler###ProfTab", ICON_FA_CHART_LINE), nil, flags(.Profiler, req, hasReq)) {
			state.bottomTab = .Profiler
			BottomPanel_RenderProfiler(state)
			imgui.EndTabItem()
		}
		Drive_Item("bottom:profiler")
		if imgui.BeginTabItem(fmt.ctprintf("%s  Game###GameTab", ICON_FA_GAMEPAD if RemoteGame_Connected() else ICON_FA_PLAY), nil, flags(.Game, req, hasReq)) {
			state.bottomTab = .Game
			GamePanel_Render(state)
			imgui.EndTabItem()
		}
		Drive_Item("bottom:game")
		if imgui.BeginTabItem(fmt.ctprintf("%s  Animation###AnimTab", ICON_FA_FILM), nil, flags(.Animation, req, hasReq)) {
			state.bottomTab = .Animation
			AnimationPanel_Render(state)
			imgui.EndTabItem()
		}
		Drive_Item("bottom:animation")
		if imgui.BeginTabItem(fmt.ctprintf("%s  Particles###ParticlesTab", ICON_FA_WAND_MAGIC_SPARKLES), nil, flags(.Particles, req, hasReq)) {
			state.bottomTab = .Particles
			ParticlePanel_Render(state)
			imgui.EndTabItem()
		}
		Drive_Item("bottom:particles")
		if imgui.BeginTabItem(fmt.ctprintf("%s  LDtk###LdtkTab", ICON_FA_TABLE_CELLS), nil, flags(.Ldtk, req, hasReq)) {
			state.bottomTab = .Ldtk
			LdtkPanel_Render(state)
			imgui.EndTabItem()
		}
		Drive_Item("bottom:ldtk")
		if imgui.BeginTabItem(fmt.ctprintf("%s  State Machine###StateGraphTab", ICON_FA_DIAGRAM_PROJECT), nil, flags(.StateGraph, req, hasReq)) {
			state.bottomTab = .StateGraph
			StateGraph_Render(state)
			imgui.EndTabItem()
		}
		Drive_Item("bottom:stategraph")
		if imgui.BeginTabItem(fmt.ctprintf("%s  Mixer###MixerTab", ICON_FA_SLIDERS), nil, flags(.Mixer, req, hasReq)) {
			state.bottomTab = .Mixer
			MixerPanel_Render(state)
			imgui.EndTabItem()
		}
		Drive_Item("bottom:mixer")
		if imgui.BeginTabItem(fmt.ctprintf("%s  Search###SearchTab", ICON_FA_MAGNIFYING_GLASS), nil, flags(.Search, req, hasReq)) {
			state.bottomTab = .Search
			Code_SearchPanel(state)
			imgui.EndTabItem()
		}
		Drive_Item("bottom:search")
		imgui.EndTabBar()
	}
	// A tab picked by hand: no going back when the selection changes.
	if follow.active && !hasReq && bottomTabRequest == nil && state.bottomTab != follow.tab do follow.active = false
}

@(private = "file")
level_style :: proc(l: LogLevel) -> (string, imgui.Vec4) {
	switch l {
	case .Info: return ICON_FA_CIRCLE_INFO, UI_TEXT_FAINT
	case .Warn: return ICON_FA_TRIANGLE_EXCLAMATION, UI_WARNING
	case .Error: return ICON_FA_CIRCLE_XMARK, UI_DANGER
	}
	return "", UI_TEXT
}

BottomPanel_RenderConsole :: proc(state: ^EditorState, counts: [LogLevel]int) {
	// Toolbar: filter toggles with counts, search, auto-scroll, clear.
	for l in LogLevel {
		icon, col := level_style(l)
		on := consoleShow[l]
		imgui.PushStyleColorImVec4(.Button, UI_BG_ACTIVE if on else {0, 0, 0, 0})
		imgui.PushStyleColorImVec4(.Text, col if on else UI_TEXT_FAINT)
		if imgui.Button(fmt.ctprintf("%s %d##lvl%v", icon, counts[l], l)) do consoleShow[l] = !on
		imgui.PopStyleColor(2)
		Drive_Item(fmt.tprintf("console.filter:%v", l))
		imgui.SameLine(0, 4)
	}
	imgui.SameLine(0, UI_SPACE)
	imgui.SetNextItemWidth(220)
	imgui.InputTextWithHint("##consolefilter", fmt.ctprintf("%s  Filter", ICON_FA_MAGNIFYING_GLASS), cstring(raw_data(consoleFilterBuf[:])), len(consoleFilterBuf), {})
	Drive_Item("console.search")
	imgui.SameLine(imgui.GetWindowContentRegionMax().x - 150)
	imgui.Checkbox("Auto-scroll", &state.consoleAutoScroll)
	imgui.SameLine()
	@(static) clearRequested: bool
	if UI_IconButton(ICON_FA_TRASH, "console.clear", "Clear console", size = 26) || clearRequested {
		clearRequested = false
		for &log in state.logs {
			delete(log.time)
			delete(log.message)
		}
		clear(&state.logs)
	}

	filter := strings.to_lower(string(cstring(raw_data(consoleFilterBuf[:]))), context.temp_allocator)
	imgui.PushStyleColorImVec4(.ChildBg, UI_BG_APP)
	imgui.PushStyleVarImVec2(.ItemSpacing, {8, 3})
	if imgui.BeginChild("##ConsoleLogScroll", {0, -LUA_CONSOLE_H}, {}, {.HorizontalScrollbar}) {
		imgui.Dummy({0, 2})
		if len(state.logs) == 0 {
			imgui.Indent(6)
			UI_DimText("No messages. Editor, build and game output appear here.")
			imgui.Unindent(6)
		}
		for log in state.logs {
			if !consoleShow[log.level] do continue
			if filter != "" && !strings.contains(strings.to_lower(log.message, context.temp_allocator), filter) do continue
			icon, col := level_style(log.level)
			imgui.Indent(6)
			imgui.PushStyleColorImVec4(.Text, col)
			imgui.TextUnformatted(strings.clone_to_cstring(icon, context.temp_allocator))
			imgui.PopStyleColor()
			imgui.SameLine()
			imgui.PushStyleColorImVec4(.Text, UI_TEXT_FAINT)
			imgui.TextUnformatted(strings.clone_to_cstring(log.time, context.temp_allocator))
			imgui.PopStyleColor()
			imgui.SameLine()
			msgCol := UI_TEXT if log.level == .Info else col
			imgui.PushStyleColorImVec4(.Text, msgCol)
			imgui.TextUnformatted(strings.clone_to_cstring(log.message, context.temp_allocator))
			imgui.PopStyleColor()
			if imgui.BeginPopupContextItem(fmt.ctprintf("##logctx%p", raw_data(log.message))) {
				if imgui.MenuItem(fmt.ctprintf("%s  Copy Message", ICON_FA_COPY)) do imgui.SetClipboardText(strings.clone_to_cstring(log.message, context.temp_allocator))
				Drive_Item("ctx:copy-log")
				if imgui.MenuItem(fmt.ctprintf("%s  Copy All", ICON_FA_COPY)) {
					sb := strings.builder_make(context.temp_allocator)
					for l in state.logs do fmt.sbprintf(&sb, "%s %s\n", l.time, l.message)
					imgui.SetClipboardText(strings.clone_to_cstring(strings.to_string(sb), context.temp_allocator))
				}
				if path, line, ok := Code_ParseLocation(log.message); ok {
					if imgui.MenuItem(fmt.ctprintf("%s  Open %s:%d", ICON_FA_CODE, path, line)) do Editor_OpenScript(state, path, line - 1)
				}
				imgui.Separator()
				if imgui.MenuItem(fmt.ctprintf("%s  Clear Console", ICON_FA_TRASH)) do clearRequested = true
				imgui.EndPopup()
			}
			// "scripts/x.lua:12: ..." -> double-click opens the script there.
			if imgui.IsItemHovered() {
				if path, line, ok := Code_ParseLocation(log.message); ok {
					imgui.SetMouseCursor(.Hand)
					UI_Tooltip(fmt.tprintf("Double-click to open %s:%d", path, line))
					if imgui.IsMouseDoubleClicked(.Left) do Editor_OpenScript(state, path, line - 1)
				}
			}
			imgui.Unindent(6)
		}
		if state.consoleAutoScroll && imgui.GetScrollY() >= imgui.GetScrollMaxY() - 4 {
			imgui.SetScrollHereY(1.0)
		}
	}
	imgui.EndChild()
	imgui.PopStyleVar()
	imgui.PopStyleColor()
	LuaConsole_Render(state) // the Lua line (lua_console.odin)
}

BottomPanel_RenderProfiler :: proc(state: ^EditorState) {
	fps := rl.GetFPS()
	dt := rl.GetFrameTime() * 1000.0
	state.fpsHistory[state.fpsIdx] = dt
	state.fpsIdx = (state.fpsIdx + 1) % len(state.fpsHistory)

	if imgui.BeginTable("##prof", 2, imgui.TableFlags_SizingStretchProp) {
		imgui.TableSetupColumn("graph", {.WidthStretch}, 0.6)
		imgui.TableSetupColumn("stats", {.WidthStretch}, 0.4)
		imgui.TableNextColumn()
		UI_DimText(fmt.tprintf("Editor frame time  %.2f ms  (%d FPS)", dt, fps))
		imgui.PushStyleColorImVec4(.FrameBg, UI_BG_APP)
		imgui.PushStyleColorImVec4(.PlotLines, UI_ACCENT)
		imgui.PlotLines("##frametime", raw_data(state.fpsHistory[:]), c.int(len(state.fpsHistory)), c.int(state.fpsIdx), nil, 0, 33, {-1, 80})
		imgui.PopStyleColor(2)

		imgui.TableNextColumn()
		nodeCount := 0
		byType := make(map[string]int, context.temp_allocator)
		if state.activeScene != nil && state.activeScene.manager != nil {
			for n in state.activeScene.manager.nodes {
				if n == nil do continue
				nodeCount += 1
				byType[e.Node_TypeName(n)] += 1
			}
		}
		UI_DimText(fmt.tprintf("Scene nodes  %d", nodeCount))
		UI_DimText(fmt.tprintf("Viewport  %d drawn · %d culled (off screen)", e.renderStats.drawn, e.renderStats.culled))
		if state.activeScene != nil && len(state.activeScene.pools) > 0 {
			// Node pools (Pool.take): taken / parked / made.
			for p in state.activeScene.pools {
				name := p.component[strings.last_index_byte(p.component, '/') + 1:]
				imgui.TextColored(UI_ACCENT, "%s", fmt.ctprintf("Pool %s  %d taken · %d parked · %d made%s", name, p.active, len(p.free), p.created, fmt.tprintf(" (max %d)", p.max) if p.max > 0 else ""))
			}
			Drive_Item("prof.pools")
		}
		for name, count in byType {
			imgui.TextUnformatted(fmt.ctprintf("%s  %d", name, count))
		}
		imgui.EndTable()
	}
}
