package editor

import "core:c"
import "core:fmt"
import "core:strings"
import "core:time"
import e "../engine"
import lua "../engine/lua54"
import imgui "lib/imgui"

// ============================================================================
// Plugin panels (TODO 13.4; docs/plugins.md): dockable windows a plugin
// draws each frame with the `ui` widgets (immediate mode over Dear ImGui).
//
//   Editor.add_panel{id, title, dock = "right" | "left" | "bottom" | "center" | "float",
//                    open = true, draw = function(ui) ... end}
//   Editor.show_panel(id, open?)
//
// A panel docks next to the editor window of its `dock` the first time it
// appears (the Inspector, Assets, the Console, the Viewport) - as a tab
// behind it; where it is moved is kept with the layout (imgui.ini).
// View > Plugins and Editor.show_panel show it (in front) / hide it. A `draw` slower than PANEL_SLOW_MS is flagged in its plugin's log.
//
// ui: text(s), dim(s), separator(label?), same_line(), spacing(), width(w),
//     button(label) -> clicked, selectable(label, selected?) -> clicked,
//     checkbox(label, v) -> changed, v, input(label, text) -> changed, text,
//     slider(label, v, min, max) -> changed, v, drag(label, v, speed?) -> changed, v,
//     combo(label, index, {items}) -> changed, index (1-based),
//     tree_node(label) -> open (then tree_pop()), tooltip(text),
//     begin_table(id, columns) -> visible, next_cell(), end_table()
// Labels are the widgets' ids (`label##id` hides the part after ##); drives
// address them as `@panel:<panel id>:<label>`.
// ============================================================================

Dock_Slot :: enum {
	Float,
	Right,
	Left,
	Bottom,
	Center,
}

// The dock nodes of the editor's own windows (Dock_Remember each frame).
@(private = "file")
dockIds: [Dock_Slot]imgui.ID

// Dock_Remember: the current window's dock node is where `slot` panels go.
Dock_Remember :: proc(slot: Dock_Slot) {
	dockIds[slot] = imgui.GetWindowDockID()
}

PANEL_SLOW_MS :: 4.0

@(private = "file")
Plugin_Panel :: struct {
	plugin:  ^Plugin,
	id:      string, // "plugin.<plugin>.<id>"
	short:   string, // the plugin's id for it
	title:   string,
	dock:    Dock_Slot,
	refDraw: c.int,
	open:    bool,
	focus:   bool, // bring it to the front next frame (show_panel, View > Plugins)
	slowLogged: bool,
}

@(private = "file")
panels: [dynamic]^Plugin_Panel

// The panel being drawn (ui widgets' drive ids).
@(private = "file")
drawing: ^Plugin_Panel

// PluginPanels_Forget drops a plugin's panels (it stops / reloads).
PluginPanels_Forget :: proc(p: ^Plugin) {
	for i := len(panels) - 1; i >= 0; i -= 1 {
		pn := panels[i]
		if pn.plugin != p do continue
		ordered_remove(&panels, i)
		delete(pn.id); delete(pn.short); delete(pn.title)
		free(pn)
	}
}

// PluginPanels_Render draws the open panels (every frame, with the windows).
PluginPanels_Render :: proc(state: ^EditorState) {
	for i := 0; i < len(panels); i += 1 {
		pn := panels[i]
		if !pn.open do continue
		p := pn.plugin
		if p.state != .Running || p.mgr == nil do continue
		if pn.dock != .Float && dockIds[pn.dock] != 0 do imgui.SetNextWindowDockID(dockIds[pn.dock], .FirstUseEver)
		imgui.SetNextWindowSize({320, 400}, .FirstUseEver)
		if pn.focus {
			pn.focus = false
			imgui.SetNextWindowFocus() // (a docked tab: selected)
		}
		visible := imgui.Begin(fmt.ctprintf("%s###%s", pn.title, pn.id), &pn.open)
		if visible {
			imgui.PushID(fmt.ctprintf("%s", pn.id))
			drawing = pn
			start := time.tick_now()
			L := p.mgr.L
			lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(pn.refDraw))
			lua.getglobal(L, "ui")
			ok := Plugin_Call(state, p, 1, 0, fmt.tprintf("panel %s", pn.short))
			ms := time.duration_milliseconds(time.tick_since(start))
			drawing = nil
			imgui.PopID()
			if ok && ms > PANEL_SLOW_MS && !pn.slowLogged {
				pn.slowLogged = true
				plugin_log(p, fmt.tprintf("panel %s took %.1f ms to draw (keep draw cheap: it runs every frame)", pn.short, ms))
			}
		}
		imgui.End()
		// (A failed plugin's panels are gone now: the list changed.)
		if i < len(panels) && panels[i] != pn do i -= 1
	}
}

// PluginPanels_ViewMenu: View > Plugins (show / hide each panel).
PluginPanels_ViewMenu :: proc(state: ^EditorState) {
	if len(panels) == 0 do return
	open := imgui.BeginMenu("Plugins")
	Drive_Item("menu:View/Plugins")
	if !open do return
	for pn in panels {
		if imgui.MenuItem(fmt.ctprintf("%s##%s", pn.title, pn.id), nil, pn.open) {
			pn.open = !pn.open
			pn.focus = pn.open
		}
		Drive_Item(fmt.tprintf("menu:View/Plugins/%s", pn.title))
	}
	imgui.EndMenu()
}

// PluginPanels_Show opens a panel in front (New Plugin).
PluginPanels_Show :: proc(id: string) {
	for pn in panels do if pn.id == id {
		pn.open = true
		pn.focus = true
	}
}

// PluginPanels_IsOpen: drives ("panel-open:<id>").
PluginPanels_IsOpen :: proc(id: string) -> bool {
	for pn in panels do if pn.id == id do return pn.open
	return false
}

// --- the Editor functions ---------------------------------------------------------

// Editor.add_panel{id, title, dock, open, draw}
api_add_panel :: proc "c" (L: ^lua.State) -> c.int {
	context = e.Script_Context(L)
	p := Plugin_Of(L)
	lua.L_checktype(L, 1, c.int(lua.Type.TABLE))
	lua.getfield(L, 1, "id")
	short := strings.clone(string(lua.tostring(L, -1))) if lua.type(L, -1) == .STRING else ""
	lua.pop(L, 1)
	lua.getfield(L, 1, "title")
	title := strings.clone(string(lua.tostring(L, -1))) if lua.type(L, -1) == .STRING else strings.clone(short)
	lua.pop(L, 1)
	lua.getfield(L, 1, "dock")
	dockName := string(lua.tostring(L, -1)) if lua.type(L, -1) == .STRING else "float"
	lua.pop(L, 1)
	lua.getfield(L, 1, "open")
	open := lua.type(L, -1) == .NIL || bool(lua.toboolean(L, -1))
	lua.pop(L, 1)
	lua.getfield(L, 1, "draw")
	if short == "" || lua.type(L, -1) != .FUNCTION {
		lua.pop(L, 1)
		delete(short); delete(title)
		lua.pushstring(L, "add_panel: id and a draw function are needed")
		return c.int(lua.error(L))
	}
	ref := lua.L_ref(L, lua.REGISTRYINDEX)
	dock := Dock_Slot.Float
	switch dockName {
	case "right": dock = .Right
	case "left": dock = .Left
	case "bottom": dock = .Bottom
	case "center": dock = .Center
	}
	id := fmt.aprintf("plugin.%s.%s", p.id, short)
	for old, i in panels do if old.id == id {
		open = old.open // (a reload keeps it open / closed)
		ordered_remove(&panels, i)
		delete(old.id); delete(old.short); delete(old.title)
		free(old)
		break
	}
	pn := new(Plugin_Panel)
	pn^ = {plugin = p, id = id, short = short, title = title, dock = dock, refDraw = ref, open = open}
	append(&panels, pn)
	return 0
}

// Editor.show_panel(id, open = true)
api_show_panel :: proc "c" (L: ^lua.State) -> c.int {
	context = e.Script_Context(L)
	p := Plugin_Of(L)
	id := fmt.tprintf("plugin.%s.%s", p.id, string(lua.L_checkstring(L, 1)))
	open := lua.type(L, 2) == .NONE || lua.type(L, 2) == .NIL || bool(lua.toboolean(L, 2))
	for pn in panels do if pn.id == id {
		pn.open = open
		pn.focus = open
	}
	return 0
}

// --- the ui table -----------------------------------------------------------------

// PluginPanels_RegisterUI puts the `ui` table in a plugin's Lua state.
PluginPanels_RegisterUI :: proc(L: ^lua.State) {
	lua.newtable(L)
	reg :: proc(L: ^lua.State, name: cstring, f: lua.CFunction) {
		lua.pushcfunction(L, f)
		lua.setfield(L, -2, name)
	}
	reg(L, "text", ui_text)
	reg(L, "dim", ui_dim)
	reg(L, "separator", ui_separator)
	reg(L, "same_line", ui_same_line)
	reg(L, "spacing", ui_spacing)
	reg(L, "width", ui_width)
	reg(L, "button", ui_button)
	reg(L, "selectable", ui_selectable)
	reg(L, "checkbox", ui_checkbox)
	reg(L, "input", ui_input)
	reg(L, "slider", ui_slider)
	reg(L, "drag", ui_drag)
	reg(L, "combo", ui_combo)
	reg(L, "tree_node", ui_tree_node)
	reg(L, "tree_pop", ui_tree_pop)
	reg(L, "tooltip", ui_tooltip)
	reg(L, "begin_table", ui_begin_table)
	reg(L, "next_cell", ui_next_cell)
	reg(L, "end_table", ui_end_table)
	lua.setglobal(L, "ui")
}

// ui_ok: widgets only draw inside a panel's draw (else they'd land in
// whatever window is current).
@(private = "file")
ui_ok :: proc(L: ^lua.State) -> bool {
	if drawing != nil do return true
	lua.pushstring(L, "ui: widgets only work inside a panel's draw function")
	lua.error(L)
	return false
}

@(private = "file")
ui_item :: proc(label: string) {
	if drawing == nil do return
	name := label
	if i := strings.index(label, "##"); i >= 0 do name = label[:i] if i > 0 else label[i + 2:]
	Drive_Item(fmt.tprintf("panel:%s:%s", drawing.id, name))
}

@(private = "file")
arg_str :: proc(L: ^lua.State, i: c.int) -> cstring {
	return lua.L_tostring(L, i) // (a copy on the stack; fine within this call)
}

@(private = "file")
ui_text :: proc "c" (L: ^lua.State) -> c.int {
	context = e.Script_Context(L)
	if !ui_ok(L) do return 0
	imgui.TextWrapped("%s", arg_str(L, 1))
	return 0
}

@(private = "file")
ui_dim :: proc "c" (L: ^lua.State) -> c.int {
	context = e.Script_Context(L)
	if !ui_ok(L) do return 0
	UI_DimText(string(arg_str(L, 1)))
	return 0
}

@(private = "file")
ui_separator :: proc "c" (L: ^lua.State) -> c.int {
	context = e.Script_Context(L)
	if !ui_ok(L) do return 0
	if lua.type(L, 1) == .STRING do imgui.SeparatorText(lua.tostring(L, 1))
	else do imgui.Separator()
	return 0
}

@(private = "file")
ui_same_line :: proc "c" (L: ^lua.State) -> c.int {
	context = e.Script_Context(L)
	if !ui_ok(L) do return 0
	imgui.SameLine()
	return 0
}

@(private = "file")
ui_spacing :: proc "c" (L: ^lua.State) -> c.int {
	context = e.Script_Context(L)
	if !ui_ok(L) do return 0
	imgui.Spacing()
	return 0
}

@(private = "file")
ui_width :: proc "c" (L: ^lua.State) -> c.int {
	context = e.Script_Context(L)
	if !ui_ok(L) do return 0
	imgui.SetNextItemWidth(f32(lua.L_checknumber(L, 1)))
	return 0
}

@(private = "file")
ui_button :: proc "c" (L: ^lua.State) -> c.int {
	context = e.Script_Context(L)
	if !ui_ok(L) do return 0
	label := lua.L_checkstring(L, 1)
	clicked := imgui.Button(label)
	ui_item(string(label))
	lua.pushboolean(L, b32(clicked))
	return 1
}

@(private = "file")
ui_selectable :: proc "c" (L: ^lua.State) -> c.int {
	context = e.Script_Context(L)
	if !ui_ok(L) do return 0
	label := lua.L_checkstring(L, 1)
	clicked := imgui.Selectable(label, bool(lua.toboolean(L, 2)))
	ui_item(string(label))
	lua.pushboolean(L, b32(clicked))
	return 1
}

@(private = "file")
ui_checkbox :: proc "c" (L: ^lua.State) -> c.int {
	context = e.Script_Context(L)
	if !ui_ok(L) do return 0
	label := lua.L_checkstring(L, 1)
	v := bool(lua.toboolean(L, 2))
	changed := imgui.Checkbox(label, &v)
	ui_item(string(label))
	lua.pushboolean(L, b32(changed))
	lua.pushboolean(L, b32(v))
	return 2
}

@(private = "file")
ui_input :: proc "c" (L: ^lua.State) -> c.int {
	context = e.Script_Context(L)
	if !ui_ok(L) do return 0
	label := lua.L_checkstring(L, 1)
	buf: [1024]u8
	if lua.type(L, 2) == .STRING do copy(buf[:len(buf) - 1], string(lua.tostring(L, 2)))
	changed := imgui.InputText(label, cstring(raw_data(buf[:])), len(buf))
	ui_item(string(label))
	lua.pushboolean(L, b32(changed))
	lua.pushstring(L, cstring(raw_data(buf[:])))
	return 2
}

@(private = "file")
ui_slider :: proc "c" (L: ^lua.State) -> c.int {
	context = e.Script_Context(L)
	if !ui_ok(L) do return 0
	label := lua.L_checkstring(L, 1)
	v := f32(lua.L_checknumber(L, 2))
	changed := imgui.SliderFloat(label, &v, f32(lua.L_checknumber(L, 3)), f32(lua.L_checknumber(L, 4)))
	ui_item(string(label))
	lua.pushboolean(L, b32(changed))
	lua.pushnumber(L, lua.Number(v))
	return 2
}

@(private = "file")
ui_drag :: proc "c" (L: ^lua.State) -> c.int {
	context = e.Script_Context(L)
	if !ui_ok(L) do return 0
	label := lua.L_checkstring(L, 1)
	v := f32(lua.L_checknumber(L, 2))
	speed: f32 = 0.1
	if lua.type(L, 3) == .NUMBER do speed = f32(lua.tonumber(L, 3))
	changed := imgui.DragFloat(label, &v, speed)
	ui_item(string(label))
	lua.pushboolean(L, b32(changed))
	lua.pushnumber(L, lua.Number(v))
	return 2
}

// ui.combo(label, index, {items}) -> changed, index (1-based)
@(private = "file")
ui_combo :: proc "c" (L: ^lua.State) -> c.int {
	context = e.Script_Context(L)
	if !ui_ok(L) do return 0
	label := lua.L_checkstring(L, 1)
	index := int(lua.L_checkinteger(L, 2))
	lua.L_checktype(L, 3, c.int(lua.Type.TABLE))
	items := make([dynamic]string, context.temp_allocator)
	for i in 1 ..= int(lua.rawlen(L, 3)) {
		lua.rawgeti(L, 3, lua.Integer(i))
		append(&items, strings.clone(string(lua.L_tostring(L, -1)), context.temp_allocator))
		lua.pop(L, 2)
	}
	preview := items[index - 1] if index >= 1 && index <= len(items) else ""
	changed := false
	if imgui.BeginCombo(label, strings.clone_to_cstring(preview, context.temp_allocator)) {
		for it, i in items {
			if imgui.Selectable(strings.clone_to_cstring(it, context.temp_allocator), i + 1 == index) {
				index = i + 1
				changed = true
			}
		}
		imgui.EndCombo()
	}
	ui_item(string(label))
	lua.pushboolean(L, b32(changed))
	lua.pushinteger(L, lua.Integer(index))
	return 2
}

@(private = "file")
ui_tree_node :: proc "c" (L: ^lua.State) -> c.int {
	context = e.Script_Context(L)
	if !ui_ok(L) do return 0
	label := lua.L_checkstring(L, 1)
	open := imgui.TreeNode(label)
	ui_item(string(label))
	lua.pushboolean(L, b32(open))
	return 1
}

@(private = "file")
ui_tree_pop :: proc "c" (L: ^lua.State) -> c.int {
	context = e.Script_Context(L)
	if !ui_ok(L) do return 0
	imgui.TreePop()
	return 0
}

@(private = "file")
ui_tooltip :: proc "c" (L: ^lua.State) -> c.int {
	context = e.Script_Context(L)
	if !ui_ok(L) do return 0
	UI_Tooltip(string(arg_str(L, 1)))
	return 0
}

@(private = "file")
ui_begin_table :: proc "c" (L: ^lua.State) -> c.int {
	context = e.Script_Context(L)
	if !ui_ok(L) do return 0
	id := lua.L_checkstring(L, 1)
	cols := c.int(lua.L_checkinteger(L, 2))
	visible := imgui.BeginTable(id, cols, imgui.TableFlags_RowBg | imgui.TableFlags_Borders)
	lua.pushboolean(L, b32(visible))
	return 1
}

@(private = "file")
ui_next_cell :: proc "c" (L: ^lua.State) -> c.int {
	context = e.Script_Context(L)
	if !ui_ok(L) do return 0
	imgui.TableNextColumn()
	return 0
}

@(private = "file")
ui_end_table :: proc "c" (L: ^lua.State) -> c.int {
	context = e.Script_Context(L)
	if !ui_ok(L) do return 0
	imgui.EndTable()
	return 0
}
