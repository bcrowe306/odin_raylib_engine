package editor

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// File operations behind the File menu: New / Open Project (recent list and
// a folder browser), Save, Save As (scene, script or component), Revert,
// and the component instance actions (Apply to Component, Save as New
// Component). Switching projects relaunches the editor on the other project
// after the usual unsaved-changes prompt.
// ============================================================================

// --- name prompt -------------------------------------------------------------------

Prompt_Kind :: enum {
	None,
	SaveSceneAs,
	SaveScriptAs,
	SaveComponentAs,  // a component document or instance -> new component file
	NewProject,
	RenameAsset,
}

@(private = "file")
Prompt_State :: struct {
	kind:   Prompt_Kind,
	open:   bool,
	text:   [256]u8,
	node:   ^e.Node, // SaveComponentAs from a scene node
}

@(private = "file")
prompt: Prompt_State

Prompt_Open :: proc(kind: Prompt_Kind, initial: string, node: ^e.Node = nil) {
	prompt.kind = kind
	prompt.open = true
	prompt.node = node
	prompt.text = {}
	copy(prompt.text[:len(prompt.text) - 1], initial)
}

@(private = "file")
prompt_title :: proc(kind: Prompt_Kind) -> (title, hint: string) {
	switch kind {
	case .SaveSceneAs:     return "Save Scene As", "scenes/<name>.scene.json"
	case .SaveScriptAs:    return "Save Script As", "scripts/<name>.lua"
	case .SaveComponentAs: return "Save as New Component", "Component name"
	case .NewProject:      return "New Project", "Folder for the new project"
	case .RenameAsset:     return "Rename Asset", "New file name"
	case .None:
	}
	return "", ""
}

Prompt_Render :: proc(state: ^EditorState) {
	if prompt.open {
		imgui.OpenPopup("##NamePrompt")
		prompt.open = false
	}
	center := imgui.GetMainViewport().WorkPos + imgui.GetMainViewport().WorkSize * 0.5
	imgui.SetNextWindowPos(center, .Appearing, {0.5, 0.5})
	if !imgui.BeginPopupModal("##NamePrompt", nil, {.NoTitleBar, .AlwaysAutoResize}) do return
	title, hint := prompt_title(prompt.kind)
	UI_PanelTitle(ICON_FA_FLOPPY_DISK, title)
	imgui.Dummy({0, 4})
	if imgui.IsWindowAppearing() do imgui.SetKeyboardFocusHere()
	imgui.SetNextItemWidth(420)
	enter := imgui.InputTextWithHint("##prompt", strings.clone_to_cstring(hint, context.temp_allocator), cstring(raw_data(prompt.text[:])), len(prompt.text), {.EnterReturnsTrue, .AutoSelectAll})
	Drive_Item("prompt.input")
	imgui.Dummy({0, 6})
	text := strings.trim_space(string(cstring(raw_data(prompt.text[:]))))
	if (enter || UI_PrimaryButton("OK", "prompt.ok", {96, 0})) && text != "" {
		prompt_apply(state, prompt.kind, strings.clone(text, context.temp_allocator))
		imgui.CloseCurrentPopup()
	}
	imgui.SameLine()
	if UI_Button("Cancel", "prompt.cancel", {96, 0}) || imgui.IsKeyPressed(.Escape, false) do imgui.CloseCurrentPopup()
	imgui.EndPopup()
}

@(private = "file")
with_suffix :: proc(text, dir, suffix: string) -> string {
	t := text
	if !strings.has_suffix(t, suffix) do t = strings.concatenate({t, suffix}, context.temp_allocator)
	if !strings.contains(t, "/") do t = strings.concatenate({dir, "/", t}, context.temp_allocator)
	return t
}

@(private = "file")
prompt_apply :: proc(state: ^EditorState, kind: Prompt_Kind, text: string) {
	switch kind {
	case .SaveSceneAs:     Editor_SaveSceneAs(state, with_suffix(text, "scenes", ".scene.json"))
	case .SaveScriptAs:    Editor_SaveScriptAs(state, with_suffix(text, "scripts", ".lua"))
	case .SaveComponentAs: Editor_SaveComponentAs(state, prompt.node, text)
	case .NewProject:      Editor_NewProject(state, text)
	case .RenameAsset: Asset_PromptApply(state, kind, text)
	case .None:
	}
}

// --- save / save as / revert -------------------------------------------------------

// Editor_SaveActive saves what has focus: the script being edited, else the scene.
Editor_SaveActive :: proc(state: ^EditorState) {
	if Code_WindowFocused() {
		Code_CmdSave(state)
		return
	}
	Toolbar_SaveScene(state)
}

// Editor_SaveAsActive asks for a new name for the focused document.
Editor_SaveAsActive :: proc(state: ^EditorState) {
	if Code_WindowFocused() {
		if doc := code_active_doc(); doc != nil do Prompt_Open(.SaveScriptAs, doc.rel)
		return
	}
	scene := state.activeScene
	if scene == nil do return
	if Editor_IsComponentDoc(state, scene) {
		Prompt_Open(.SaveComponentAs, fmt.tprintf("%s_copy", filepath.stem(filepath.stem(scene.filePath))))
		return
	}
	stem := filepath.stem(filepath.stem(scene.filePath)) if scene.filePath != "" else "scene"
	Prompt_Open(.SaveSceneAs, fmt.tprintf("scenes/%s_copy.scene.json", stem))
}

// Editor_SaveSceneAs writes the active scene to a new file, adds it to the
// project and opens it (the original file stays as it was saved).
Editor_SaveSceneAs :: proc(state: ^EditorState, rel: string) -> bool {
	scene := state.activeScene
	if scene == nil do return false
	disk, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
	if os.exists(disk) {
		Editor_Log(state, .Error, "%s already exists", rel)
		return false
	}
	json := e.Scene_SerializeToJSON(scene, context.temp_allocator)
	_ = os.make_directory_all(filepath.dir(disk, context.temp_allocator))
	if os.write_entire_file(disk, transmute([]u8)json) != nil {
		Editor_Log(state, .Error, "Could not write %s", disk)
		return false
	}
	if !slice.contains(state.projectConfig.scenes[:], rel) {
		append(&state.projectConfig.scenes, strings.clone(rel))
		e.Project_SaveConfigToFile(state.projectPath, &state.projectConfig)
	}
	Editor_Log(state, .Info, "Saved scene as %s", rel)
	return Editor_OpenScene(state, rel)
}

Editor_SaveScriptAs :: proc(state: ^EditorState, rel: string) -> bool {
	doc := code_active_doc()
	if doc == nil do return false
	disk, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
	if os.exists(disk) {
		Editor_Log(state, .Error, "%s already exists", rel)
		return false
	}
	_ = os.make_directory_all(filepath.dir(disk, context.temp_allocator))
	text := Code_DocText(doc)
	if os.write_entire_file(disk, transmute([]u8)text) != nil {
		Editor_Log(state, .Error, "Could not write %s", disk)
		return false
	}
	Editor_Log(state, .Info, "Saved script as %s", rel)
	return Editor_OpenScript(state, rel)
}

// Editor_SaveComponentAs saves a component document, or a scene node
// (instance or not), as a new component file.
Editor_SaveComponentAs :: proc(state: ^EditorState, node: ^e.Node, name: string) -> bool {
	scene := state.activeScene
	if scene == nil do return false
	target := node
	if target == nil && Editor_IsComponentDoc(state, scene) {
		kids := e.GetChildrenView(scene.manager, scene.rootNode)
		if len(kids) > 0 do target = kids[0]
	}
	if target == nil do return false
	if Editor_IsComponentDoc(state, scene) && node == nil {
		// A component document: write a new file and open it.
		json := e.Component_InstanceJSON(target, scene.manager, context.temp_allocator)
		rel := fmt.tprintf("components/%s.component.json", name)
		disk, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
		_ = os.make_directory_all(filepath.dir(disk, context.temp_allocator))
		if os.write_entire_file(disk, transmute([]u8)json) != nil do return false
		Editor_Log(state, .Info, "Saved component as %s", rel)
		return Editor_OpenComponent(state, rel)
	}
	_, ok := Editor_SaveComponent(state, target, name)
	return ok
}

// Editor_RevertScene discards unsaved changes of the active scene.
Editor_RevertScene :: proc(state: ^EditorState) {
	scene := state.activeScene
	if scene == nil || scene.filePath == "" do return
	disk, _ := filepath.join({state.projectPath, scene.filePath}, context.temp_allocator)
	data, err := os.read_entire_file(disk, context.temp_allocator)
	if err != nil {
		Editor_Log(state, .Error, "Could not read %s", disk)
		return
	}
	Editor_RecordUndo(state, "Revert")
	if Editor_IsComponentDoc(state, scene) {
		e.Scene_Unload(scene, &state.game.gameContext)
		node := e.Scene_InstantiateNodeFromJSON(scene, data, scene.rootNode, &state.game.gameContext)
		if node != nil do node.position = {0, 0}
		e.ProcessNodeQueues(scene.manager, &state.game.gameContext)
		scene.isLoaded = true
	} else {
		Editor_RestoreSceneJSON(state, scene, string(data))
	}
	Editor_SetSceneBaseline(state, scene)
	state.selectedNode = nil
	Editor_Log(state, .Info, "Reverted %s", scene.filePath)
}

// --- projects ----------------------------------------------------------------------

@(private = "file")
Project_Browser :: struct {
	open:    bool,
	dir:     string,
	pathBuf: [512]u8,
}

@(private = "file")
browser: Project_Browser

Editor_OpenProjectDialog :: proc(state: ^EditorState) {
	browser.open = true
	if browser.dir != "" do delete(browser.dir)
	start := filepath.dir(strings.trim_suffix(GlobalSettings.recentProjects[0] if len(GlobalSettings.recentProjects) > 0 else state.projectPath, "/"), context.temp_allocator)
	if !filepath.is_abs(start) {
		cwd, _ := os.get_working_directory(context.temp_allocator)
		start, _ = filepath.join({cwd, start}, context.temp_allocator)
	}
	browser.dir = strings.clone(start)
	browser.pathBuf = {}
}

@(private = "file")
is_project_dir :: proc(dir: string) -> bool {
	p, _ := filepath.join({dir, "project.json"}, context.temp_allocator)
	return os.is_file(p)
}

// Editor_SwitchProject relaunches the editor on another project (after the
// unsaved-changes prompt).
Editor_SwitchProject :: proc(state: ^EditorState, path: string) {
	if !is_project_dir(path) && !strings.has_suffix(path, ".ore") {
		Editor_Log(state, .Error, "%s is not a project (no project.json)", path)
		return
	}
	if state.pendingProject != "" do delete(state.pendingProject)
	state.pendingProject = strings.clone(path)
	Editor_RequestQuit(state)
}

// Editor_LaunchPendingProject runs after the editor decided to quit.
Editor_LaunchPendingProject :: proc(state: ^EditorState) {
	if state.pendingProject == "" do return
	if GlobalDrive.enabled {
		Editor_Log(state, .Info, "Would open project %s", state.pendingProject)
		return
	}
	Editor_AddRecentProject(state.pendingProject)
	_ = Editor_SaveSettings()
	exe := os.args[0]
	desc := os.Process_Desc{command = []string{exe, "--project", state.pendingProject}}
	if _, err := os.process_start(desc); err != nil {
		fmt.eprintln("Could not relaunch the editor:", err)
	}
}

// Editor_NewProject creates a project folder (project.json, a main scene,
// the usual folders) and opens it.
Editor_NewProject :: proc(state: ^EditorState, path: string) {
	dir := path
	if !filepath.is_abs(dir) {
		dir, _ = filepath.join({filepath.dir(strings.trim_suffix(state.projectPath, "/"), context.temp_allocator), path}, context.temp_allocator)
	}
	if is_project_dir(dir) {
		Editor_Log(state, .Error, "%s already has a project", dir)
		return
	}
	for sub in ([]string{"scenes", "scripts", "textures", "audio", "components", "levels"}) {
		p, _ := filepath.join({dir, sub}, context.temp_allocator)
		_ = os.make_directory_all(p)
	}
	cfg, _ := e.Project_ParseConfig(transmute([]u8)string("{}"), context.temp_allocator)
	cfg.name = filepath.base(dir)
	cfg.windowTitle = cfg.name
	cfg.initialScene = "scenes/main.scene.json"
	cfg.gravity = {0, 980}
	append(&cfg.scenes, "scenes/main.scene.json")
	if !e.Project_SaveConfigToFile(dir, &cfg) {
		Editor_Log(state, .Error, "Could not create %s", dir)
		return
	}
	main, _ := filepath.join({dir, "scenes", "main.scene.json"}, context.temp_allocator)
	_ = os.write_entire_file(main, transmute([]u8)string(`{"name": "main", "root": {"type": "Node", "name": "root", "children": [{"type": "CameraNode", "name": "Camera", "position": [640, 360], "properties": {"isCurrent": true}}]}}`))
	Editor_Log(state, .Info, "Created project %s", dir)
	Editor_SwitchProject(state, dir)
}

OpenProject_Render :: proc(state: ^EditorState) {
	if browser.open {
		imgui.OpenPopup("Open Project###OpenProject")
		browser.open = false
	}
	center := imgui.GetMainViewport().WorkPos + imgui.GetMainViewport().WorkSize * 0.5
	imgui.SetNextWindowPos(center, .Appearing, {0.5, 0.5})
	imgui.SetNextWindowSize({640, 520}, .Appearing)
	if !imgui.BeginPopupModal("Open Project###OpenProject", nil, {.NoTitleBar}) do return
	defer imgui.EndPopup()
	UI_PanelTitle(ICON_FA_FOLDER_OPEN, "Open Project")
	imgui.Dummy({0, 4})
	if len(GlobalSettings.recentProjects) > 0 && UI_SectionHeader("Recent") {
		for r in GlobalSettings.recentProjects {
			if imgui.Selectable(fmt.ctprintf("%s  %s##recent_%s", ICON_FA_FOLDER, filepath.base(r), r), false, {}, {0, 24}) {
				Editor_SwitchProject(state, r)
				imgui.CloseCurrentPopup()
			}
			Drive_Item(fmt.tprintf("open.recent:%s", filepath.base(r)))
			imgui.SameLine(200)
			UI_DimText(r)
		}
	}
	if UI_SectionHeader("Browse") {
		UI_DimText(browser.dir)
		h := imgui.GetContentRegionAvail().y - 46
		if imgui.BeginChild("##browse", {0, max(h, 80)}, {.Borders}, {}) {
			if imgui.Selectable(fmt.ctprintf("%s  ..", ICON_FA_FOLDER), false) {
				parent := filepath.dir(browser.dir, context.temp_allocator)
				delete(browser.dir)
				browser.dir = strings.clone(parent)
			}
			Drive_Item("open.up")
			if handle, err := os.open(browser.dir); err == nil {
				infos, _ := os.read_dir(handle, -1, context.temp_allocator)
				os.close(handle)
				slice.sort_by(infos[:], proc(a, b: os.File_Info) -> bool {return a.name < b.name})
				for fi in infos {
					if fi.type != .Directory || strings.has_prefix(fi.name, ".") do continue
					full, _ := filepath.join({browser.dir, fi.name}, context.temp_allocator)
					proj := is_project_dir(full)
					imgui.PushStyleColorImVec4(.Text, UI_ACCENT if proj else UI_TEXT)
					clicked := imgui.Selectable(fmt.ctprintf("%s  %s%s##dir_%s", ICON_FA_FOLDER_OPEN if proj else ICON_FA_FOLDER, fi.name, "   (project)" if proj else "", fi.name), false, {.AllowDoubleClick})
					imgui.PopStyleColor()
					Drive_Item(fmt.tprintf("open.dir:%s", fi.name))
					if clicked {
						if proj && imgui.IsMouseDoubleClicked(.Left) {
							Editor_SwitchProject(state, full)
							imgui.CloseCurrentPopup()
						} else if !proj || imgui.IsMouseDoubleClicked(.Left) {
							delete(browser.dir)
							browser.dir = strings.clone(full)
						} else {
							browser.pathBuf = {}
							copy(browser.pathBuf[:len(browser.pathBuf) - 1], full)
						}
					}
				}
			}
		}
		imgui.EndChild()
	}
	imgui.SetNextItemWidth(imgui.GetContentRegionAvail().x - 220)
	imgui.InputTextWithHint("##openpath", "Project folder or .ore", cstring(raw_data(browser.pathBuf[:])), len(browser.pathBuf), {})
	Drive_Item("open.path")
	imgui.SameLine()
	path := strings.trim_space(string(cstring(raw_data(browser.pathBuf[:]))))
	if path == "" && is_project_dir(browser.dir) do path = browser.dir
	if UI_PrimaryButton("Open", "open.ok", {96, 0}) && path != "" {
		Editor_SwitchProject(state, strings.clone(path, context.temp_allocator))
		imgui.CloseCurrentPopup()
	}
	imgui.SameLine()
	if UI_Button("Cancel", "open.cancel", {96, 0}) || imgui.IsKeyPressed(.Escape, false) do imgui.CloseCurrentPopup()
}
