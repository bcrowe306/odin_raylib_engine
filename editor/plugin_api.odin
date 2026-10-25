package editor

import "core:c"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:sync"
import "core:thread"
import e "../engine"
import lua "../engine/lua54"
import imgui "lib/imgui"

// ============================================================================
// The Editor API plugins call (plugins.odin; design: docs/plugins.md).
//
//   print(...), Editor.log / warn / error(...)  the plugin's log + the console
//   Editor.plugin                              {id, name, version, dir}
//   Editor.add_command{id, label, menu, shortcut, scope, run, enabled, checked}
//   Editor.selection() / select(nodes)         the selected nodes
//   Editor.scene() / project()                 {name, path, root} / {name, path}
//   Editor.edit(label, fn)                     changes in fn: one undo step
//   Editor.create_node(type, parent?, name?) / delete(node)
//   Editor.assets(folder?, ext?)               project files
//   Editor.fs.read / write / exists / list / mkdir   (project and plugin folders)
//   Editor.notify(text) / confirm(text, fn) / prompt(text, default, fn)
//   Editor.pick_file{title, exts, folders, multiple, fn}
//   Editor.run(cmd, args, fn)                  (permission "process")
//   Editor.http(url, fn)                       (permission "network")
// Lua callbacks (commands, dialogs, jobs) are kept as registry references;
// what a plugin registered goes when it stops (PluginAPI_Forget).
// ============================================================================

// PluginAPI_Register puts the Editor table in a plugin's Lua state.
PluginAPI_Register :: proc(L: ^lua.State, p: ^Plugin) {
	lua.pushcfunction(L, api_print)
	lua.setglobal(L, "print")
	lua.newtable(L)
	reg :: proc(L: ^lua.State, name: cstring, f: lua.CFunction) {
		lua.pushcfunction(L, f)
		lua.setfield(L, -2, name)
	}
	reg(L, "log", api_print)
	reg(L, "warn", api_warn)
	reg(L, "error", api_error)
	reg(L, "add_command", api_add_command)
	reg(L, "selection", api_selection)
	reg(L, "select", api_select)
	reg(L, "scene", api_scene)
	reg(L, "project", api_project)
	reg(L, "edit", api_edit)
	reg(L, "create_node", api_create_node)
	reg(L, "delete", api_delete)
	reg(L, "assets", api_assets)
	reg(L, "notify", api_notify)
	reg(L, "confirm", api_confirm)
	reg(L, "prompt", api_prompt)
	reg(L, "pick_file", api_pick_file)
	reg(L, "run", api_run)
	reg(L, "http", api_http)
	reg(L, "add_panel", api_add_panel)   // (plugin_panels.odin)
	reg(L, "show_panel", api_show_panel)
	reg(L, "on", api_on)                 // (plugin_events.odin)
	reg(L, "add_inspector", api_add_inspector) // (plugin_extend.odin)
	reg(L, "add_overlay", api_add_overlay)
	reg(L, "add_importer", api_add_importer)
	lua.newtable(L)
	reg(L, "read", api_fs_read)
	reg(L, "write", api_fs_write)
	reg(L, "exists", api_fs_exists)
	reg(L, "list", api_fs_list)
	reg(L, "mkdir", api_fs_mkdir)
	lua.setfield(L, -2, "fs")
	lua.newtable(L)
	set_str(L, "id", p.id)
	set_str(L, "name", p.name)
	set_str(L, "version", p.version)
	set_str(L, "dir", p.dir)
	lua.setfield(L, -2, "plugin")
	lua.setglobal(L, "Editor")
	PluginPanels_RegisterUI(L)
	PluginOverlays_RegisterG(L)
}

// PluginAPI_Forget drops what a plugin registered (it stops / reloads).
PluginAPI_Forget :: proc(p: ^Plugin) {
	for i := len(GlobalActions) - 1; i >= 0; i -= 1 {
		if GlobalActions[i].plugin != p do continue
		delete(GlobalActions[i].id)
		delete(GlobalActions[i].label)
		delete(GlobalActions[i].category)
		delete(GlobalActions[i].menu)
		ordered_remove(&GlobalActions, i)
	}
	for i := len(api.dialogs) - 1; i >= 0; i -= 1 {
		if api.dialogs[i].plugin == p do dialog_free_at(i)
	}
	if api.pickPlugin == p do api.pickPlugin = nil
	PluginPanels_Forget(p)
	PluginEvents_Forget(p)
	PluginExtend_Forget(p)
	for j in api.jobs do if j.plugin == p do j.plugin = nil // (finished, then dropped)
}

// PluginAPI_Update: once a frame - finished jobs call back.
PluginAPI_Update :: proc(state: ^EditorState) {
	for i := len(api.jobs) - 1; i >= 0; i -= 1 {
		j := api.jobs[i]
		if !sync.atomic_load(&j.done) do continue
		ordered_remove(&api.jobs, i)
		thread.join(j.thread)
		thread.destroy(j.thread)
		if p := j.plugin; p != nil && p.state == .Running && p.mgr != nil {
			L := p.mgr.L
			lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(j.ref))
			lua.pushboolean(L, b32(j.ok))
			lua.pushstring(L, strings.clone_to_cstring(j.output, context.temp_allocator))
			lua.pushinteger(L, lua.Integer(j.exit))
			_ = Plugin_Call(state, p, 3, 0, "job callback")
			if p.mgr != nil do lua.L_unref(L, lua.REGISTRYINDEX, j.ref)
		}
		for a in j.command do delete(a)
		delete(j.command)
		delete(j.output)
		free(j)
	}
}

// --- commands (actions.odin's table) -------------------------------------------

// PluginAPI_ActionRun / Enabled / Checked: a plugin command's callbacks.
PluginAPI_ActionRun :: proc(state: ^EditorState, a: ^Editor_Action) {
	p := a.plugin
	if p.state != .Running || p.mgr == nil do return
	lua.rawgeti(p.mgr.L, lua.REGISTRYINDEX, lua.Integer(a.refRun))
	_ = Plugin_Call(state, p, 0, 0, a.label)
}

PluginAPI_ActionEnabled :: proc(state: ^EditorState, a: ^Editor_Action) -> bool {
	return action_bool(state, a, a.refEnabled, true)
}

PluginAPI_ActionChecked :: proc(state: ^EditorState, a: ^Editor_Action) -> bool {
	return action_bool(state, a, a.refChecked, false)
}

@(private = "file")
action_bool :: proc(state: ^EditorState, a: ^Editor_Action, ref: c.int, def: bool) -> bool {
	p := a.plugin
	if ref == lua.NOREF do return def
	if p.state != .Running || p.mgr == nil do return false
	L := p.mgr.L
	lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(ref))
	if !Plugin_Call(state, p, 0, 1, a.label) do return false
	defer lua.pop(L, 1)
	return bool(lua.toboolean(L, -1))
}

// PluginAPI_MenuItems: the plugin commands placed in the menu `top`
// ("Tools", "Edit", ...; "Tools/Align" makes a submenu Align).
PluginAPI_MenuItems :: proc(state: ^EditorState, top: string) {
	first := true
	for &a in GlobalActions {
		if a.plugin == nil || a.menu == "" do continue
		parts := strings.split(a.menu, "/", context.temp_allocator)
		if parts[0] != top do continue
		if first {
			imgui.Separator()
			first = false
		}
		menu_path_item(state, &a, parts[1:])
	}
}

@(private = "file")
menu_path_item :: proc(state: ^EditorState, a: ^Editor_Action, path: []string) {
	if len(path) == 0 {
		_ = Actions_MenuItem(state, a.id)
		return
	}
	open := imgui.BeginMenu(strings.clone_to_cstring(path[0], context.temp_allocator))
	Drive_Item(fmt.tprintf("menu:%s", a.menu))
	if open {
		menu_path_item(state, a, path[1:])
		imgui.EndMenu()
	}
}

// Editor.add_command{id, label, menu, shortcut, scope, run, enabled, checked}
@(private = "file")
api_add_command :: proc "c" (L: ^lua.State) -> c.int {
	context = e.Script_Context(L)
	p := Plugin_Of(L)
	lua.L_checktype(L, 1, c.int(lua.Type.TABLE))
	id := field_str(L, 1, "id")
	label := field_str(L, 1, "label")
	if id == "" || label == "" do return api_fail(L, "add_command: id and label are needed")
	lua.getfield(L, 1, "run")
	if lua.type(L, -1) != .FUNCTION {
		lua.pop(L, 1)
		return api_fail(L, "add_command: run must be a function")
	}
	runRef := lua.L_ref(L, lua.REGISTRYINDEX)
	a := Editor_Action{
		id = fmt.aprintf("plugin.%s.%s", p.id, id),
		category = strings.clone(p.name),
		label = strings.clone(label),
		menu = strings.clone(field_str(L, 1, "menu")),
		scope = .Scene if field_str(L, 1, "scope") == "scene" else .Global,
		plugin = p,
		refRun = runRef,
		refEnabled = field_ref(L, 1, "enabled"),
		refChecked = field_ref(L, 1, "checked"),
	}
	if sc := field_str(L, 1, "shortcut"); sc != "" {
		if chord, ok := Chord_Parse(sc); ok do a.chords[0] = chord
		else do plugin_log(p, fmt.tprintf("add_command %s: unknown shortcut %q", id, sc))
	}
	// Replacing a command with the same id (a reload) keeps one.
	for &old, i in GlobalActions do if old.id == a.id {
		ordered_remove(&GlobalActions, i)
		break
	}
	if actionDefaults != nil do actionDefaults[strings.clone(a.id)] = a.chords
	if user, ok := GlobalSettings.keymap[a.id]; ok do a.chords = user // (rebound in the keymap)
	append(&GlobalActions, a)
	return 0
}

// --- selection, scene, edits ------------------------------------------------------

@(private = "file")
api_selection :: proc "c" (L: ^lua.State) -> c.int {
	context = e.Script_Context(L)
	state := &GlobalEditor
	lua.newtable(L)
	nodes := state.selection[:]
	if len(nodes) == 0 && state.selectedNode != nil do nodes = {state.selectedNode}
	for n, i in nodes {
		e.push_node_userdata(L, n)
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}
	return 1
}

// Editor.select(nil | node | {nodes})
@(private = "file")
api_select :: proc "c" (L: ^lua.State) -> c.int {
	context = e.Script_Context(L)
	state := &GlobalEditor
	Editor_ClearSelection(state)
	#partial switch lua.type(L, 1) {
	case .USERDATA:
		if n, ok := e.to_node_userdata(L, 1); ok do Editor_SelectNode(state, n)
	case .TABLE:
		count := int(lua.rawlen(L, 1))
		for i in 1 ..= count {
			lua.rawgeti(L, 1, lua.Integer(i))
			if n, ok := e.to_node_userdata(L, -1); ok do Editor_SelectNode(state, n, additive = true)
			lua.pop(L, 1)
		}
	}
	return 0
}

@(private = "file")
api_scene :: proc "c" (L: ^lua.State) -> c.int {
	context = e.Script_Context(L)
	state := &GlobalEditor
	if state.activeScene == nil {
		lua.pushnil(L)
		return 1
	}
	lua.newtable(L)
	set_str(L, "name", state.activeScene.name)
	set_str(L, "path", state.activeScenePath)
	e.push_node_userdata(L, state.activeScene.rootNode)
	lua.setfield(L, -2, "root")
	return 1
}

@(private = "file")
api_project :: proc "c" (L: ^lua.State) -> c.int {
	context = e.Script_Context(L)
	state := &GlobalEditor
	lua.newtable(L)
	set_str(L, "name", state.projectConfig.name)
	set_str(L, "path", project_dir())
	return 1
}

// Editor.edit(label, fn): fn's changes to the scene are one undo step.
@(private = "file")
api_edit :: proc "c" (L: ^lua.State) -> c.int {
	context = e.Script_Context(L)
	state := &GlobalEditor
	label := string(lua.L_checkstring(L, 1))
	lua.L_checktype(L, 2, c.int(lua.Type.FUNCTION))
	if state.activeScene == nil do return api_fail(L, "edit: no scene is open")
	if state.isSimulating do return api_fail(L, "edit: the scene can't be edited while simulating")
	// A widget being dragged (an inspector's ui.drag / slider) edits every
	// frame: one undo step for the drag.
	frame := imgui.GetFrameCount()
	if !(imgui.IsAnyItemActive() && label == api.lastEdit && frame - api.lastEditFrame <= 1) do Editor_RecordUndo(state, label)
	if label != api.lastEdit {
		delete(api.lastEdit)
		api.lastEdit = strings.clone(label)
	}
	api.lastEditFrame = frame
	lua.pushvalue(L, 2)
	lua.call(L, 0, 0) // (an error propagates to whoever called the plugin)
	e.ProcessNodeQueues(state.activeScene.manager, &state.game.gameContext)
	e.Node_SetGlobalPositions(state.activeScene.manager, state.activeScene.rootNode)
	return 0
}

// Editor.create_node(type, parent?, name?) -> node
@(private = "file")
api_create_node :: proc "c" (L: ^lua.State) -> c.int {
	context = e.Script_Context(L)
	state := &GlobalEditor
	typeName := string(lua.L_checkstring(L, 1))
	if state.activeScene == nil do return api_fail(L, "create_node: no scene is open")
	parent := state.activeScene.rootNode
	if n, ok := e.to_node_userdata(L, 2); ok do parent = n
	node := e.Node_CreateByTypeName(state.activeScene, typeName, parent)
	if node == nil do return api_fail(L, fmt.tprintf("create_node: unknown node type %q", typeName))
	node.gameContext = &state.game.gameContext
	base := string(lua.tostring(L, 3)) if lua.type(L, 3) == .STRING else typeName
	node.name = strings.clone(Editor_UniqueChildName(state, parent, base, node), node.allocator)
	e.ProcessNodeQueues(state.activeScene.manager, &state.game.gameContext)
	e.push_node_userdata(L, node)
	return 1
}

// Editor.delete(node)
@(private = "file")
api_delete :: proc "c" (L: ^lua.State) -> c.int {
	context = e.Script_Context(L)
	state := &GlobalEditor
	n, ok := e.to_node_userdata(L, 1)
	if !ok || state.activeScene == nil do return 0
	if n == state.activeScene.rootNode do return api_fail(L, "delete: the scene's root can't be deleted")
	if idx, found := slice.linear_search(state.selection[:], n); found do ordered_remove(&state.selection, idx)
	if state.selectedNode == n do state.selectedNode = nil
	e.RemoveNode(state.activeScene.manager, n)
	e.ProcessNodeQueues(state.activeScene.manager, &state.game.gameContext)
	return 0
}

// --- files ----------------------------------------------------------------------

// Editor.assets(folder?, ext?) -> project-relative paths
@(private = "file")
api_assets :: proc "c" (L: ^lua.State) -> c.int {
	context = e.Script_Context(L)
	root := project_dir()
	folder := string(lua.tostring(L, 1)) if lua.type(L, 1) == .STRING else ""
	ext := string(lua.tostring(L, 2)) if lua.type(L, 2) == .STRING else ""
	start, _ := filepath.join({root, folder}, context.temp_allocator)
	out := make([dynamic]string, context.temp_allocator)
	walk :: proc(dir, root, ext: string, out: ^[dynamic]string) {
		infos, err := os.read_all_directory_by_path(dir, context.temp_allocator)
		if err != nil do return
		for f in infos {
			if strings.has_prefix(f.name, ".") do continue
			if f.type == .Directory {
				walk(f.fullpath, root, ext, out)
				continue
			}
			if ext != "" && !strings.has_suffix(f.name, ext) do continue
			rel, _ := filepath.rel(root, f.fullpath, context.temp_allocator)
			rel, _ = strings.replace_all(rel, "\\", "/", context.temp_allocator)
			append(out, rel)
		}
	}
	walk(start, root, ext, &out)
	slice.sort(out[:])
	lua.newtable(L)
	for s, i in out {
		lua.pushstring(L, strings.clone_to_cstring(s, context.temp_allocator))
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}
	return 1
}

// fs_path: a path the plugin may touch (relative = in the project; absolute
// inside the project or the plugin's folder) - "" when it may not.
@(private = "file")
fs_path :: proc(L: ^lua.State, idx: c.int) -> string {
	p := Plugin_Of(L)
	raw := string(lua.L_checkstring(L, idx))
	full := raw
	if !filepath.is_abs(raw) do full, _ = filepath.join({project_dir(), raw}, context.temp_allocator)
	full, _ = filepath.clean(full, context.temp_allocator)
	inside :: proc(path, dir: string) -> bool {
		d, _ := filepath.clean(dir, context.temp_allocator)
		return path == d || strings.has_prefix(path, strings.concatenate({d, filepath.SEPARATOR_STRING}, context.temp_allocator))
	}
	if inside(full, project_dir()) || inside(full, p.dir) do return full
	return ""
}

@(private = "file")
api_fs_read :: proc "c" (L: ^lua.State) -> c.int {
	context = e.Script_Context(L)
	path := fs_path(L, 1)
	if path == "" do return api_fail(L, "fs.read: only files in the project or the plugin's folder")
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil {
		lua.pushnil(L)
		lua.pushstring(L, strings.clone_to_cstring(fmt.tprint(err), context.temp_allocator))
		return 2
	}
	lua.pushlstring(L, cstring(raw_data(data)), c.size_t(len(data)))
	return 1
}

@(private = "file")
api_fs_write :: proc "c" (L: ^lua.State) -> c.int {
	context = e.Script_Context(L)
	path := fs_path(L, 1)
	if path == "" do return api_fail(L, "fs.write: only files in the project or the plugin's folder")
	n: c.size_t
	text := lua.L_checkstring(L, 2, &n)
	_ = os.make_directory_all(filepath.dir(path, context.temp_allocator))
	err := os.write_entire_file(path, (cast([^]u8)text)[:n])
	lua.pushboolean(L, b32(err == nil))
	return 1
}

@(private = "file")
api_fs_exists :: proc "c" (L: ^lua.State) -> c.int {
	context = e.Script_Context(L)
	path := fs_path(L, 1)
	lua.pushboolean(L, b32(path != "" && os.exists(path)))
	return 1
}

@(private = "file")
api_fs_list :: proc "c" (L: ^lua.State) -> c.int {
	context = e.Script_Context(L)
	path := fs_path(L, 1)
	if path == "" do return api_fail(L, "fs.list: only folders in the project or the plugin's folder")
	lua.newtable(L)
	infos, err := os.read_all_directory_by_path(path, context.temp_allocator)
	if err != nil do return 1
	slice.sort_by(infos, proc(a, b: os.File_Info) -> bool {return a.name < b.name})
	for f, i in infos {
		name := f.name if f.type != .Directory else strings.concatenate({f.name, "/"}, context.temp_allocator)
		lua.pushstring(L, strings.clone_to_cstring(name, context.temp_allocator))
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}
	return 1
}

@(private = "file")
api_fs_mkdir :: proc "c" (L: ^lua.State) -> c.int {
	context = e.Script_Context(L)
	path := fs_path(L, 1)
	if path == "" do return api_fail(L, "fs.mkdir: only folders in the project or the plugin's folder")
	lua.pushboolean(L, b32(os.make_directory_all(path) == nil))
	return 1
}

// --- dialogs ----------------------------------------------------------------------

@(private = "file")
Dialog_Kind :: enum {
	Confirm,
	Prompt,
}

@(private = "file")
Plugin_Dialog :: struct {
	plugin: ^Plugin,
	kind:   Dialog_Kind,
	text:   string,
	buf:    [256]u8,
	ref:    c.int,
	opened: bool,
}

@(private = "file")
Plugin_Job :: struct {
	plugin:  ^Plugin,
	ref:     c.int,
	command: []string,
	output:  string,
	exit:    int,
	ok:      bool,
	done:    bool,
	thread:  ^thread.Thread,
}

@(private = "file")
api: struct {
	dialogs:    [dynamic]^Plugin_Dialog,
	jobs:       [dynamic]^Plugin_Job,
	pickPlugin: ^Plugin, // the plugin a file dialog answers
	pickRef:    c.int,
	lastEdit:      string, // Editor.edit's last label and frame (a drag: one undo step)
	lastEditFrame: i32,
}

@(private = "file")
api_notify :: proc "c" (L: ^lua.State) -> c.int {
	context = e.Script_Context(L)
	p := Plugin_Of(L)
	text := string(lua.L_checkstring(L, 1))
	Editor_Log(&GlobalEditor, .Info, "[%s] %s", p.name, text)
	return 0
}

@(private = "file")
api_confirm :: proc "c" (L: ^lua.State) -> c.int {
	context = e.Script_Context(L)
	return dialog_open(L, .Confirm, 2)
}

@(private = "file")
api_prompt :: proc "c" (L: ^lua.State) -> c.int {
	context = e.Script_Context(L)
	return dialog_open(L, .Prompt, 3)
}

@(private = "file")
dialog_open :: proc(L: ^lua.State, kind: Dialog_Kind, fnArg: c.int) -> c.int {
	d := new(Plugin_Dialog)
	d.plugin = Plugin_Of(L)
	d.kind = kind
	d.text = strings.clone(string(lua.L_checkstring(L, 1)))
	if kind == .Prompt && lua.type(L, 2) == .STRING do copy(d.buf[:len(d.buf) - 1], string(lua.tostring(L, 2)))
	lua.L_checktype(L, fnArg, c.int(lua.Type.FUNCTION))
	lua.pushvalue(L, fnArg)
	d.ref = lua.L_ref(L, lua.REGISTRYINDEX)
	append(&api.dialogs, d)
	return 0
}

@(private = "file")
dialog_free_at :: proc(i: int) {
	d := api.dialogs[i]
	ordered_remove(&api.dialogs, i)
	delete(d.text)
	free(d)
}

// PluginAPI_Dialogs draws the first open confirm / prompt (every frame).
PluginAPI_Dialogs :: proc(state: ^EditorState) {
	if len(api.dialogs) == 0 do return
	d := api.dialogs[0]
	title := fmt.ctprintf("%s###PluginDialog", d.plugin.name)
	if !d.opened {
		d.opened = true
		imgui.OpenPopup(title)
	}
	center := imgui.GetMainViewport().WorkPos + imgui.GetMainViewport().WorkSize * 0.5
	imgui.SetNextWindowPos(center, .Appearing, {0.5, 0.5})
	if !imgui.BeginPopupModal(title, nil, {.AlwaysAutoResize}) do return
	imgui.TextUnformatted(strings.clone_to_cstring(d.text, context.temp_allocator))
	answer: Maybe(bool)
	if d.kind == .Prompt {
		if imgui.IsWindowAppearing() do imgui.SetKeyboardFocusHere()
		imgui.SetNextItemWidth(360)
		if imgui.InputText("##plugin_prompt", cstring(raw_data(d.buf[:])), len(d.buf), {.EnterReturnsTrue}) do answer = true
		Drive_Item("plugin.dialog.input")
	}
	if UI_PrimaryButton("OK", "plugin.dialog.ok") do answer = true
	imgui.SameLine()
	if UI_Button("Cancel", "plugin.dialog.cancel") || imgui.IsKeyPressed(.Escape) do answer = false
	if yes, done := answer.?; done {
		imgui.CloseCurrentPopup()
		p, ref, kind := d.plugin, d.ref, d.kind
		text := strings.clone_from_cstring(cstring(raw_data(d.buf[:])), context.temp_allocator)
		dialog_free_at(0) // (d is gone from here on)
		if p.state == .Running && p.mgr != nil {
			L := p.mgr.L
			lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(ref))
			if kind == .Confirm do lua.pushboolean(L, b32(yes))
			else if yes do lua.pushstring(L, strings.clone_to_cstring(text, context.temp_allocator))
			else do lua.pushnil(L)
			_ = Plugin_Call(state, p, 1, 0, "dialog callback")
			if p.mgr != nil do lua.L_unref(L, lua.REGISTRYINDEX, ref)
		}
	}
	imgui.EndPopup()
}

// Editor.pick_file{title, exts = {"png"}, folders, multiple, fn = function(paths)}
@(private = "file")
api_pick_file :: proc "c" (L: ^lua.State) -> c.int {
	context = e.Script_Context(L)
	lua.L_checktype(L, 1, c.int(lua.Type.TABLE))
	if api.pickPlugin != nil || NativeDialog_IsOpen() do return api_fail(L, "pick_file: a file dialog is already open")
	exts := make([dynamic]string, context.temp_allocator)
	lua.getfield(L, 1, "exts")
	if lua.type(L, -1) == .TABLE {
		for i in 1 ..= int(lua.rawlen(L, -1)) {
			lua.rawgeti(L, -1, lua.Integer(i))
			append(&exts, strings.clone(string(lua.tostring(L, -1)), context.temp_allocator))
			lua.pop(L, 1)
		}
	}
	lua.pop(L, 1)
	opts := NativeDialog_Options{
		title = field_str(L, 1, "title"),
		exts = exts[:],
		folders = field_bool(L, 1, "folders"),
		multiple = field_bool(L, 1, "multiple"),
		start = project_dir(),
	}
	ref := field_ref(L, 1, "fn")
	if ref == lua.NOREF do return api_fail(L, "pick_file: fn must be a function")
	api.pickPlugin, api.pickRef = Plugin_Of(L), ref
	if !NativeDialog_Open(&GlobalEditor, opts, pick_done) {
		api.pickPlugin = nil
		return api_fail(L, "pick_file: no file dialog on this system")
	}
	return 0
}

@(private = "file")
pick_done :: proc(state: ^EditorState, paths: []string) {
	p := api.pickPlugin
	api.pickPlugin = nil
	if p == nil || p.state != .Running || p.mgr == nil do return
	L := p.mgr.L
	lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(api.pickRef))
	lua.newtable(L)
	for s, i in paths {
		lua.pushstring(L, strings.clone_to_cstring(s, context.temp_allocator))
		lua.rawseti(L, -2, lua.Integer(i + 1))
	}
	_ = Plugin_Call(state, p, 1, 0, "pick_file callback")
	if p.mgr != nil do lua.L_unref(L, lua.REGISTRYINDEX, api.pickRef)
}

// --- processes and the network (permissions) ----------------------------------------

// Editor.run(cmd, {args}, fn(ok, output, exit_code)) - permission "process"
@(private = "file")
api_run :: proc "c" (L: ^lua.State) -> c.int {
	context = e.Script_Context(L)
	p := Plugin_Of(L)
	if .Process not_in p.permissions do return api_fail(L, "run: the plugin needs the \"process\" permission (plugin.json)")
	cmd := make([dynamic]string)
	append(&cmd, strings.clone(string(lua.L_checkstring(L, 1))))
	if lua.type(L, 2) == .TABLE {
		for i in 1 ..= int(lua.rawlen(L, 2)) {
			lua.rawgeti(L, 2, lua.Integer(i))
			append(&cmd, strings.clone(string(lua.L_tostring(L, -1))))
			lua.pop(L, 2)
		}
	}
	return job_start(L, cmd[:], 3)
}

// Editor.http(url, fn(ok, body)) - permission "network" (a GET, by curl)
@(private = "file")
api_http :: proc "c" (L: ^lua.State) -> c.int {
	context = e.Script_Context(L)
	p := Plugin_Of(L)
	if .Network not_in p.permissions do return api_fail(L, "http: the plugin needs the \"network\" permission (plugin.json)")
	url := string(lua.L_checkstring(L, 1))
	cmd := make([]string, 5)
	cmd[0], cmd[1], cmd[2], cmd[3], cmd[4] = strings.clone("curl"), strings.clone("-fsSL"), strings.clone("-m"), strings.clone("30"), strings.clone(url)
	return job_start(L, cmd, 2)
}

@(private = "file")
job_start :: proc(L: ^lua.State, cmd: []string, fnArg: c.int) -> c.int {
	lua.L_checktype(L, fnArg, c.int(lua.Type.FUNCTION))
	lua.pushvalue(L, fnArg)
	j := new(Plugin_Job)
	j.plugin = Plugin_Of(L)
	j.ref = lua.L_ref(L, lua.REGISTRYINDEX)
	j.command = cmd
	j.thread = thread.create_and_start_with_poly_data(j, proc(j: ^Plugin_Job) {
		st, out, errOut, err := os.process_exec({command = j.command}, context.allocator)
		if err == nil {
			j.ok = st.exit_code == 0
			j.exit = st.exit_code
			j.output = strings.concatenate({string(out), string(errOut)})
		} else {
			j.output = fmt.aprint(err)
			j.exit = -1
		}
		delete(out)
		delete(errOut)
		sync.atomic_store(&j.done, true)
	})
	append(&api.jobs, j)
	return 0
}

// --- log ------------------------------------------------------------------------

@(private = "file")
plugin_text :: proc(L: ^lua.State) -> string {
	sb := strings.builder_make(context.temp_allocator)
	n := lua.gettop(L)
	for i in 1 ..= n {
		if i > 1 do strings.write_byte(&sb, '\t')
		strings.write_string(&sb, string(lua.L_tostring(L, i)))
		lua.pop(L, 1)
	}
	return strings.to_string(sb)
}

@(private = "file")
plugin_say :: proc(L: ^lua.State, level: LogLevel) {
	p := Plugin_Of(L)
	if p == nil do return
	text := plugin_text(L)
	plugin_log(p, text)
	Editor_Log(&GlobalEditor, level, "[%s] %s", p.name, text)
}

@(private = "file")
api_print :: proc "c" (L: ^lua.State) -> c.int {
	context = e.Script_Context(L)
	plugin_say(L, .Info)
	return 0
}

@(private = "file")
api_warn :: proc "c" (L: ^lua.State) -> c.int {
	context = e.Script_Context(L)
	plugin_say(L, .Warn)
	return 0
}

@(private = "file")
api_error :: proc "c" (L: ^lua.State) -> c.int {
	context = e.Script_Context(L)
	plugin_say(L, .Error)
	return 0
}

// --- helpers --------------------------------------------------------------------

// api_fail raises a Lua error (the plugin's call stops; Plugin_Call reports it).
@(private = "file")
api_fail :: proc(L: ^lua.State, msg: string) -> c.int {
	lua.pushstring(L, strings.clone_to_cstring(msg, context.temp_allocator))
	return c.int(lua.error(L))
}

@(private = "file")
project_dir :: proc() -> string {
	p := GlobalEditor.projectPath
	if abs, err := os.get_absolute_path(p, context.temp_allocator); err == nil do p = abs
	p, _ = filepath.clean(p, context.temp_allocator)
	return p
}

@(private = "file")
set_str :: proc(L: ^lua.State, k, v: string) {
	lua.pushstring(L, strings.clone_to_cstring(v, context.temp_allocator))
	lua.setfield(L, -2, strings.clone_to_cstring(k, context.temp_allocator))
}

@(private = "file")
field_str :: proc(L: ^lua.State, idx: c.int, k: cstring) -> string {
	lua.getfield(L, idx, k)
	defer lua.pop(L, 1)
	if lua.type(L, -1) != .STRING do return ""
	return strings.clone(string(lua.tostring(L, -1)), context.temp_allocator)
}

@(private = "file")
field_bool :: proc(L: ^lua.State, idx: c.int, k: cstring) -> bool {
	lua.getfield(L, idx, k)
	defer lua.pop(L, 1)
	return bool(lua.toboolean(L, -1))
}

// field_ref: a registry reference to the function in field k (NOREF if none).
@(private = "file")
field_ref :: proc(L: ^lua.State, idx: c.int, k: cstring) -> c.int {
	lua.getfield(L, idx, k)
	if lua.type(L, -1) != .FUNCTION {
		lua.pop(L, 1)
		return lua.NOREF
	}
	return lua.L_ref(L, lua.REGISTRYINDEX)
}
