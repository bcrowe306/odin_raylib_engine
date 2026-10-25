package editor

import "core:c"
import "core:fmt"
import "core:math/linalg"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
import e "../engine"
import lua "../engine/lua54"
import imgui "lib/imgui"

// ============================================================================
// Plugin extension points (TODO 13.7; docs/plugins.md "D"):
//
//   Editor.add_inspector{id, title, type, draw = function(ui, node)}
//       a section in the Inspector for the selected node (of `type`, or any)
//   Editor.add_overlay{id, title, draw = function(g, view)}
//       world-space drawing over the viewport, with draggable handles
//       (a drag is one undo step)
//   Editor.add_importer{ext, import = function(name, data) -> files, err}
//       a new file type: `files` = {["project/relative/path"] = contents}
//
// Like panels, they go when their plugin stops; every call is protected.
// ============================================================================

@(private = "file")
Plugin_Inspector :: struct {
	plugin:   ^Plugin,
	id:       string, // plugin.<plugin id>.<id>
	title:    string,
	nodeType: string, // "" = every node
	ref:      c.int,
}

@(private = "file")
Plugin_Overlay :: struct {
	plugin: ^Plugin,
	id:     string,
	title:  string,
	ref:    c.int,
}

@(private = "file")
Plugin_Importer :: struct {
	plugin: ^Plugin,
	ext:    string, // ".tsx" (lower case)
	ref:    c.int,
}

@(private = "file")
ext: struct {
	inspectors: [dynamic]^Plugin_Inspector,
	overlays:   [dynamic]^Plugin_Overlay,
	importers:  [dynamic]^Plugin_Importer,
	// Overlay drawing (g.*), valid while an overlay's draw runs.
	drawList:   ^imgui.DrawList,
	overlay:    ^Plugin_Overlay,
	mouseWorld: [2]f32,
	owns:       bool, // a handle is hovered / dragged: the viewport leaves the mouse alone
	// The dragged handle ("<overlay id>:<handle id>").
	active:     string,
	grab:       [2]f32, // handle - mouse at the click (no jump)
	undone:     bool,   // the drag's undo step is recorded
}

// PluginExtend_Forget drops a plugin's inspectors, overlays and importers.
PluginExtend_Forget :: proc(p: ^Plugin) {
	for i := len(ext.inspectors) - 1; i >= 0; i -= 1 do if it := ext.inspectors[i]; it.plugin == p {
		ordered_remove(&ext.inspectors, i)
		delete(it.id); delete(it.title); delete(it.nodeType)
		free(it)
	}
	for i := len(ext.overlays) - 1; i >= 0; i -= 1 do if ov := ext.overlays[i]; ov.plugin == p {
		if strings.has_prefix(ext.active, ov.id) {
			delete(ext.active)
			ext.active = ""
		}
		ordered_remove(&ext.overlays, i)
		delete(ov.id); delete(ov.title)
		free(ov)
	}
	for i := len(ext.importers) - 1; i >= 0; i -= 1 do if im := ext.importers[i]; im.plugin == p {
		ordered_remove(&ext.importers, i)
		delete(im.ext)
		free(im)
	}
}

// spec_str: a string field of the spec table at 1 (cloned; "" if missing).
@(private = "file")
spec_str :: proc(L: ^lua.State, k: cstring) -> string {
	lua.getfield(L, 1, k)
	defer lua.pop(L, 1)
	return strings.clone(string(lua.tostring(L, -1))) if lua.type(L, -1) == .STRING else ""
}

// spec_fn: a registry ref to the function field k (NOREF if missing).
@(private = "file")
spec_fn :: proc(L: ^lua.State, k: cstring) -> c.int {
	lua.getfield(L, 1, k)
	if lua.type(L, -1) != .FUNCTION {
		lua.pop(L, 1)
		return lua.NOREF
	}
	return lua.L_ref(L, lua.REGISTRYINDEX)
}

@(private = "file")
spec_error :: proc(L: ^lua.State, msg: string) -> c.int {
	lua.pushstring(L, strings.clone_to_cstring(msg, context.temp_allocator))
	return c.int(lua.error(L))
}

// --- inspectors ---------------------------------------------------------------

// Editor.add_inspector{id, title, type, draw}
api_add_inspector :: proc "c" (L: ^lua.State) -> c.int {
	context = e.Script_Context(L)
	p := Plugin_Of(L)
	lua.L_checktype(L, 1, c.int(lua.Type.TABLE))
	short := spec_str(L, "id")
	defer delete(short)
	ref := spec_fn(L, "draw")
	if short == "" || ref == lua.NOREF do return spec_error(L, "add_inspector: id and a draw function are needed")
	id := fmt.aprintf("plugin.%s.%s", p.id, short)
	for old, i in ext.inspectors do if old.id == id {
		ordered_remove(&ext.inspectors, i)
		delete(old.id); delete(old.title); delete(old.nodeType)
		free(old)
		break
	}
	title := spec_str(L, "title")
	if title == "" {
		delete(title)
		title = strings.clone(short)
	}
	it := new(Plugin_Inspector)
	it^ = {plugin = p, id = id, title = title, nodeType = spec_str(L, "type"), ref = ref}
	append(&ext.inspectors, it)
	return 0
}

// PluginInspectors_Render: the plugins' sections for the selected node (after
// the built-in ones). Widgets' drive ids: panel:<inspector id>:<label>.
PluginInspectors_Render :: proc(state: ^EditorState, node: ^e.Node) {
	if len(ext.inspectors) == 0 do return
	typeName := e.Node_TypeName(node)
	for i := 0; i < len(ext.inspectors); i += 1 {
		it := ext.inspectors[i]
		p := it.plugin
		if p.state != .Running || p.mgr == nil do continue
		if it.nodeType != "" && it.nodeType != typeName do continue
		imgui.PushID(fmt.ctprintf("%s", it.id))
		if UI_SectionHeader(it.title) {
			PluginUI_Begin(it.id)
			L := p.mgr.L
			lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(it.ref))
			lua.getglobal(L, "ui")
			e.push_node_userdata(L, node)
			_ = Plugin_Call(state, p, 2, 0, fmt.tprintf("inspector %s", it.title))
			PluginUI_End()
		}
		imgui.PopID()
		// (A failed plugin's inspectors are gone now: the list changed.)
		if i < len(ext.inspectors) && ext.inspectors[i] != it do i -= 1
	}
}

// --- overlays -----------------------------------------------------------------

// Editor.add_overlay{id, title, draw}
api_add_overlay :: proc "c" (L: ^lua.State) -> c.int {
	context = e.Script_Context(L)
	p := Plugin_Of(L)
	lua.L_checktype(L, 1, c.int(lua.Type.TABLE))
	short := spec_str(L, "id")
	defer delete(short)
	ref := spec_fn(L, "draw")
	if short == "" || ref == lua.NOREF do return spec_error(L, "add_overlay: id and a draw function are needed")
	id := fmt.aprintf("plugin.%s.%s", p.id, short)
	for old, i in ext.overlays do if old.id == id {
		ordered_remove(&ext.overlays, i)
		delete(old.id); delete(old.title)
		free(old)
		break
	}
	title := spec_str(L, "title")
	if title == "" {
		delete(title)
		title = strings.clone(short)
	}
	ov := new(Plugin_Overlay)
	ov^ = {plugin = p, id = id, title = title, ref = ref}
	append(&ext.overlays, ov)
	return 0
}

// PluginOverlays_Render draws the overlays over the viewport (screen space,
// after the scene) and runs their handles. True: a handle has the mouse (no
// picking / gizmo this frame).
PluginOverlays_Render :: proc(state: ^EditorState, drawList: ^imgui.DrawList, mouseWorld: [2]f32) -> bool {
	if ext.active != "" && !imgui.IsMouseDown(.Left) {
		delete(ext.active)
		ext.active = ""
	}
	if len(ext.overlays) == 0 || state.activeScene == nil || state.isSimulating do return false
	ext.drawList = drawList
	ext.mouseWorld = mouseWorld
	ext.owns = ext.active != ""
	moved := false
	for i := 0; i < len(ext.overlays); i += 1 {
		ov := ext.overlays[i]
		p := ov.plugin
		if p.state != .Running || p.mgr == nil do continue
		ext.overlay = ov
		L := p.mgr.L
		lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(ov.ref))
		lua.getglobal(L, "__Rayzr_Overlay_G")
		lua.createtable(L, 0, 2)
		lua.pushnumber(L, lua.Number(state.cameraZoom))
		lua.setfield(L, -2, "zoom")
		e.Lua_PushVec2(L, mouseWorld)
		lua.setfield(L, -2, "mouse")
		_ = Plugin_Call(state, p, 2, 0, fmt.tprintf("overlay %s", ov.title))
		ext.overlay = nil
		moved = moved || ext.undone
		if i < len(ext.overlays) && ext.overlays[i] != ov do i -= 1
	}
	ext.drawList = nil
	// A handle moved nodes: their global positions follow now.
	if moved && ext.active != "" do e.Node_SetGlobalPositions(state.activeScene.manager, state.activeScene.rootNode)
	return ext.owns
}

// PluginOverlays_RegisterG puts the overlay drawing table (the draw
// function's `g`) in a plugin's state.
PluginOverlays_RegisterG :: proc(L: ^lua.State) {
	lua.newtable(L)
	reg :: proc(L: ^lua.State, name: cstring, f: lua.CFunction) {
		lua.pushcfunction(L, f)
		lua.setfield(L, -2, name)
	}
	reg(L, "line", g_line)
	reg(L, "circle", g_circle)
	reg(L, "rect", g_rect)
	reg(L, "text", g_text)
	reg(L, "handle", g_handle)
	lua.setglobal(L, "__Rayzr_Overlay_G")
}

@(private = "file")
g_ok :: proc(L: ^lua.State) -> bool {
	if ext.drawList != nil do return true
	lua.pushstring(L, "g: drawing only works inside an overlay's draw function")
	lua.error(L)
	return false
}

// g_color: "#rrggbb" / "#rrggbbaa" at idx (else `def`).
@(private = "file")
g_color :: proc(L: ^lua.State, idx: c.int, def: imgui.Vec4) -> u32 {
	if lua.type(L, idx) != .STRING do return col_u32(def)
	s := strings.trim_prefix(string(lua.tostring(L, idx)), "#")
	v, ok := strconv.parse_u64_of_base(s, 16)
	if !ok || (len(s) != 6 && len(s) != 8) do return col_u32(def)
	if len(s) == 6 do v = v << 8 | 0xff
	return col_u32({f32(v >> 24 & 0xff) / 255, f32(v >> 16 & 0xff) / 255, f32(v >> 8 & 0xff) / 255, f32(v & 0xff) / 255})
}

@(private = "file")
g_point :: proc(L: ^lua.State, idx: c.int) -> [2]f32 {
	x, y := e.arg_xy(L, idx)
	return Viewport_WorldToScreen(&GlobalEditor, {x, y})
}

// g.line(a, b, color?, thickness?) - a, b: Vec2 (world)
@(private = "file")
g_line :: proc "c" (L: ^lua.State) -> c.int {
	context = e.Script_Context(L)
	if !g_ok(L) do return 0
	a, b := g_point(L, 1), g_point(L, 2)
	w := f32(lua.tonumber(L, 4)) if lua.type(L, 4) == .NUMBER else 1.5
	imgui.DrawList_AddLine(ext.drawList, a, b, g_color(L, 3, UI_ACCENT), w)
	return 0
}

// g.circle(center, radius, color?, filled?) - radius in world units
@(private = "file")
g_circle :: proc "c" (L: ^lua.State) -> c.int {
	context = e.Script_Context(L)
	if !g_ok(L) do return 0
	center := g_point(L, 1)
	r := f32(lua.tonumber(L, 2)) * GlobalEditor.cameraZoom
	col := g_color(L, 3, UI_ACCENT)
	if lua.toboolean(L, 4) do imgui.DrawList_AddCircleFilled(ext.drawList, center, r, col)
	else do imgui.DrawList_AddCircle(ext.drawList, center, r, col, 0, 1.5)
	return 0
}

// g.rect(min, max, color?, filled?)
@(private = "file")
g_rect :: proc "c" (L: ^lua.State) -> c.int {
	context = e.Script_Context(L)
	if !g_ok(L) do return 0
	a, b := g_point(L, 1), g_point(L, 2)
	mn, mx := linalg.min(a, b), linalg.max(a, b)
	col := g_color(L, 3, UI_ACCENT)
	if lua.toboolean(L, 4) do imgui.DrawList_AddRectFilled(ext.drawList, mn, mx, col)
	else do imgui.DrawList_AddRect(ext.drawList, mn, mx, col, 0, {}, 1.5)
	return 0
}

// g.text(pos, text, color?)
@(private = "file")
g_text :: proc "c" (L: ^lua.State) -> c.int {
	context = e.Script_Context(L)
	if !g_ok(L) do return 0
	pos := g_point(L, 1)
	imgui.DrawList_AddText(ext.drawList, pos, g_color(L, 3, UI_TEXT), lua.L_tostring(L, 2))
	lua.pop(L, 1)
	return 0
}

OVERLAY_HANDLE_PX :: 6

// g.handle(id, pos, color?) -> moved, new_pos: a draggable point. While it's
// dragged, `moved` is true with where it is now; the drag is one undo step
// (taken as it starts: change the scene right away, no Editor.edit needed).
@(private = "file")
g_handle :: proc "c" (L: ^lua.State) -> c.int {
	context = e.Script_Context(L)
	if !g_ok(L) do return 0
	state := &GlobalEditor
	hid := string(lua.L_checkstring(L, 1))
	x, y := e.arg_xy(L, 2)
	world := [2]f32{x, y}
	key := fmt.tprintf("%s:%s", ext.overlay.id, hid)
	at := Viewport_WorldToScreen(state, world)
	mouse := Viewport_WorldToScreen(state, ext.mouseWorld)
	hovered := ext.active == "" && state.viewportHovered && state.toolMode != .Pan && linalg.length(mouse - at) <= OVERLAY_HANDLE_PX + 2
	if hovered {
		ext.owns = true
		imgui.SetMouseCursor(.Hand)
		if imgui.IsMouseClicked(.Left) {
			ext.active = strings.clone(key)
			ext.grab = world - ext.mouseWorld
			ext.undone = false
		}
	}
	dragging := ext.active == key
	col := g_color(L, 3, UI_ACCENT)
	r: f32 = OVERLAY_HANDLE_PX + 1 if hovered || dragging else OVERLAY_HANDLE_PX
	imgui.DrawList_AddCircleFilled(ext.drawList, at, r, col)
	imgui.DrawList_AddCircle(ext.drawList, at, r, col_u32({0, 0, 0, 0.8}), 0, 1)
	Drive_ItemRect(fmt.tprintf("overlay:%s", key), at - OVERLAY_HANDLE_PX, at + OVERLAY_HANDLE_PX, inWindow = true)
	if dragging && imgui.IsMouseDragging(.Left, 1) {
		if !ext.undone {
			Editor_RecordUndo(state, ext.overlay.title)
			ext.undone = true
		}
		lua.pushboolean(L, true)
		e.Lua_PushVec2(L, ext.mouseWorld + ext.grab)
		return 2
	}
	lua.pushboolean(L, false)
	e.Lua_PushVec2(L, world)
	return 2
}

// --- importers ----------------------------------------------------------------

// Editor.add_importer{ext, import}
api_add_importer :: proc "c" (L: ^lua.State) -> c.int {
	context = e.Script_Context(L)
	p := Plugin_Of(L)
	lua.L_checktype(L, 1, c.int(lua.Type.TABLE))
	x := spec_str(L, "ext")
	defer delete(x)
	ref := spec_fn(L, "import")
	if x == "" || ref == lua.NOREF do return spec_error(L, "add_importer: ext and an import function are needed")
	lower := strings.to_lower(x)
	if !strings.has_prefix(lower, ".") {
		dotted := strings.concatenate({".", lower})
		delete(lower)
		lower = dotted
	}
	for old, i in ext.importers do if old.ext == lower && old.plugin == p {
		ordered_remove(&ext.importers, i)
		delete(old.ext)
		free(old)
		break
	}
	im := new(Plugin_Importer)
	im^ = {plugin = p, ext = lower, ref = ref}
	append(&ext.importers, im)
	return 0
}

// PluginImporters_Exts: the extensions plugins import (no dots: the import
// dialog's filter).
PluginImporters_Exts :: proc(allocator := context.temp_allocator) -> []string {
	out := make([dynamic]string, allocator)
	for im in ext.importers do if im.plugin.state == .Running do append(&out, im.ext[1:])
	return out[:]
}

Plugin_Imported_File :: struct {
	rel:  string,
	data: []u8,
}

// PluginImporters_Run: a plugin importer for `name`'s extension turns its
// contents into project files (temp memory). found = false: no importer.
PluginImporters_Run :: proc(state: ^EditorState, name: string, data: []u8) -> (files: []Plugin_Imported_File, err: string, found: bool) {
	lowerName := strings.to_lower(name, context.temp_allocator)
	for im in ext.importers {
		p := im.plugin
		if p.state != .Running || p.mgr == nil || !strings.has_suffix(lowerName, im.ext) do continue
		found = true
		L := p.mgr.L
		lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(im.ref))
		lua.pushstring(L, strings.clone_to_cstring(name, context.temp_allocator))
		lua.pushlstring(L, cstring(raw_data(data)) if len(data) > 0 else "", c.size_t(len(data)))
		if !Plugin_Call(state, p, 2, 2, fmt.tprintf("importer %s", im.ext)) {
			return nil, fmt.tprintf("%s failed (Settings > Plugins)", p.name), true
		}
		defer lua.pop(L, 2)
		if lua.type(L, -2) != .TABLE {
			why := string(lua.tostring(L, -1)) if lua.type(L, -1) == .STRING else "it returned no files"
			return nil, fmt.tprintf("%s: %s", p.name, why), true
		}
		out := make([dynamic]Plugin_Imported_File, context.temp_allocator)
		lua.pushnil(L)
		for lua.next(L, -3) != 0 {
			if lua.type(L, -2) == .STRING && lua.type(L, -1) == .STRING {
				rel, _ := filepath.clean(string(lua.tostring(L, -2)), context.temp_allocator)
				n: c.size_t
				s := lua.tolstring(L, -1, &n)
				if filepath.is_abs(rel) || rel == ".." || strings.has_prefix(rel, "../") || strings.has_prefix(rel, ".rayzr") || strings.has_prefix(rel, ".ore") {
					lua.pop(L, 2) // (key, value: the results go with the defer)
					return nil, fmt.tprintf("%s: %q is outside the project", p.name, rel), true
				}
				append(&out, Plugin_Imported_File{rel, transmute([]u8)strings.clone(strings.string_from_ptr((^u8)(s), int(n)), context.temp_allocator)})
			}
			lua.pop(L, 1)
		}
		if len(out) == 0 do return nil, fmt.tprintf("%s: it returned no files", p.name), true
		return out[:], "", true
	}
	return nil, "", false
}
