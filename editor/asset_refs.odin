package editor

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import e "../engine"

// ============================================================================
// Moving / renaming assets and folders with their references, and Find
// Usages. References are quoted project-relative paths (e.AssetPath_Rewrite)
// in the project's JSON (scenes, components, ...) and Lua files, in
// project.json (startup scene, scene list, icon, texture import settings),
// in scenes loaded in the editor (unsaved edits kept) and in their undo
// history. Open scripts that move are reopened at the new path.
// ============================================================================

Asset_Usage :: struct {
	file:  string, // project-relative
	count: int,
}

@(private = "file")
reference_files :: proc(state: ^EditorState) -> []string {
	out := make([dynamic]string, context.temp_allocator)
	for f in Editor_ListProjectFiles(state, "", {".json", ".lua"}) do if f != "project.json" do append(&out, f)
	return out[:]
}

// loaded_scenes: scenes (and component documents) loaded in the editor.
@(private = "file")
loaded_scenes :: proc(state: ^EditorState) -> []^e.Scene {
	out := make([dynamic]^e.Scene, context.temp_allocator)
	for _, s in state.game.sceneManager.scenes do if s != nil && s.isLoaded do append(&out, s)
	return out[:]
}

// Undo_ResourceMoved: resource undo entries follow their file when it (or
// its folder) moves.
Undo_ResourceMoved :: proc(state: ^EditorState, oldRel, newRel: string, isFolder: bool) {
	for stack in ([]^[dynamic]Undo_Entry{&state.undoStack, &state.redoStack}) {
		for &entry in stack {
			if entry.kind != .Resource do continue
			if entry.resource != oldRel && !(isFolder && strings.has_prefix(entry.resource, strings.concatenate({oldRel, "/"}, context.temp_allocator))) do continue
			moved := strings.concatenate({newRel, entry.resource[len(oldRel):]})
			delete(entry.resource)
			entry.resource = moved
		}
	}
}

// Asset_FindUsages: the files that reference an asset (or anything in a
// folder). A scene with unsaved edits is checked as it is in the editor.
Asset_FindUsages :: proc(state: ^EditorState, rel: string, isFolder: bool) -> []Asset_Usage {
	out := make([dynamic]Asset_Usage, context.temp_allocator)
	inMemory := make(map[string]bool, allocator = context.temp_allocator)
	for s in loaded_scenes(state) {
		if s.filePath == "" || !Editor_SceneIsModified(state, s) do continue
		inMemory[s.filePath] = true
		if n := e.AssetPath_Count(e.Scene_SerializeToJSON(s, context.temp_allocator), rel, isFolder); n > 0 {
			append(&out, Asset_Usage{s.filePath, n})
		}
	}
	for f in reference_files(state) {
		if inMemory[f] do continue
		full, _ := filepath.join({state.projectPath, f}, context.temp_allocator)
		data, err := os.read_entire_file(full, context.temp_allocator)
		if err != nil do continue
		if n := e.AssetPath_Count(string(data), rel, isFolder); n > 0 do append(&out, Asset_Usage{f, n})
	}
	if n := e.AssetPath_Count(e.Project_SerializeToJSON(&state.projectConfig, context.temp_allocator), rel, isFolder); n > 0 {
		append(&out, Asset_Usage{"project.json", n})
	}
	slice.sort_by(out[:], proc(a, b: Asset_Usage) -> bool {return a.file < b.file})
	return out[:]
}

// Asset_Move moves (or renames) an asset or folder to `newRel` and updates
// every reference to it.
Asset_Move :: proc(state: ^EditorState, oldRel, newRel: string) -> bool {
	oldRel := strings.trim_suffix(oldRel, "/")
	newRel := strings.trim_suffix(newRel, "/")
	if oldRel == "" || newRel == "" || oldRel == newRel do return false
	src, _ := filepath.join({state.projectPath, oldRel}, context.temp_allocator)
	dst, _ := filepath.join({state.projectPath, newRel}, context.temp_allocator)
	isFolder := os.is_dir(src)
	if !os.exists(src) {
		Editor_Log(state, .Error, "%s doesn't exist", oldRel)
		return false
	}
	if os.exists(dst) {
		Editor_Log(state, .Error, "%s already exists", newRel)
		return false
	}
	if isFolder && strings.has_prefix(newRel, strings.concatenate({oldRel, "/"}, context.temp_allocator)) {
		Editor_Log(state, .Error, "Can't move %s into itself", oldRel)
		return false
	}
	inside :: proc(path, old: string, isFolder: bool) -> bool {
		return path == old || (isFolder && strings.has_prefix(path, old) && len(path) > len(old) && path[len(old)] == '/')
	}
	moved :: proc(path, old, new: string) -> string {
		return strings.concatenate({new, path[len(old):]}, context.temp_allocator)
	}
	// Open scripts: unsaved ones block the move; the others reopen.
	reopen := make([dynamic]string, context.temp_allocator)
	for d in GlobalCode.docs {
		if !inside(d.rel, oldRel, isFolder) do continue
		if code_doc_dirty(d) {
			Editor_Log(state, .Error, "Save %s before moving it", d.rel)
			return false
		}
		append(&reopen, moved(d.rel, oldRel, newRel))
	}
	_ = os.make_directory_all(filepath.dir(dst, context.temp_allocator))
	if os.rename(src, dst) != nil {
		Editor_Log(state, .Error, "Could not move %s", oldRel)
		return false
	}
	// Its import settings file goes with it (folders take theirs along).
	if !isFolder && os.is_file(strings.concatenate({src, e.IMPORT_SUFFIX}, context.temp_allocator)) {
		_ = os.rename(strings.concatenate({src, e.IMPORT_SUFFIX}, context.temp_allocator), strings.concatenate({dst, e.IMPORT_SUFFIX}, context.temp_allocator))
	}
	e.Asset_ImportsReset()
	Slicer_AssetMoved(oldRel, newRel, isFolder)
	Editor_InvalidateProjectFiles()
	Lua_MarkProjectTypesDirty()
	for i := len(GlobalCode.docs) - 1; i >= 0; i -= 1 {
		if inside(GlobalCode.docs[i].rel, oldRel, isFolder) do code_close_doc(i)
	}

	// Scenes loaded in the editor (and their history), then files on disk.
	refs, files := 0, 0
	selPath := Editor_NodePath(state, state.selectedNode)
	for _, s in state.game.sceneManager.scenes {
		if s == nil do continue
		if inside(s.filePath, oldRel, isFolder) do s.filePath = strings.clone(moved(s.filePath, oldRel, newRel), state.game.sceneManager.allocator)
	}
	for s in loaded_scenes(state) {
		text, n := e.AssetPath_Rewrite(e.Scene_SerializeToJSON(s, context.temp_allocator), oldRel, newRel, isFolder, context.temp_allocator)
		if n > 0 {
			Editor_RestoreSceneJSON(state, s, text)
			if s == state.activeScene do state.selectedNode = Editor_NodeAtPath(state, selPath)
		}
		if s.sourceJson != "" {
			if src2, n2 := e.AssetPath_Rewrite(s.sourceJson, oldRel, newRel, isFolder, state.game.sceneManager.allocator); n2 > 0 {
				s.sourceJson = src2
			}
		}
	}
	Undo_ResourceMoved(state, oldRel, newRel, isFolder)
	for stack in ([]^[dynamic]Undo_Entry{&state.undoStack, &state.redoStack}) {
		for &entry in stack {
			text, n := e.AssetPath_Rewrite(Undo_Unpack(entry.json), oldRel, newRel, isFolder, context.temp_allocator)
			if n == 0 do continue
			Undo_Release(entry.json)
			entry.json = Undo_Pack(text)
		}
	}
	for f in reference_files(state) {
		full, _ := filepath.join({state.projectPath, f}, context.temp_allocator)
		data, err := os.read_entire_file(full, context.temp_allocator)
		if err != nil do continue
		text, n := e.AssetPath_Rewrite(string(data), oldRel, newRel, isFolder, context.temp_allocator)
		if n == 0 do continue
		if os.write_entire_file(full, transmute([]u8)text) == nil {
			refs += n
			files += 1
		}
	}
	// project.json, through the config the editor holds.
	cfgText, n := e.AssetPath_Rewrite(e.Project_SerializeToJSON(&state.projectConfig, context.temp_allocator), oldRel, newRel, isFolder, context.temp_allocator)
	if n > 0 {
		if cfg, ok := e.Project_ParseConfig(transmute([]u8)cfgText); ok {
			e.ProjectConfig_Destroy(&state.projectConfig)
			state.projectConfig = cfg
			e.Project_SaveConfigToFile(state.projectPath, &state.projectConfig)
			e.Texture_ImportsSet(state.projectConfig.textureImport[:])
			refs += n
			files += 1
		}
	}
	if inside(state.activeScenePath, oldRel, isFolder) {
		p := strings.clone(moved(state.activeScenePath, oldRel, newRel))
		delete(state.activeScenePath)
		state.activeScenePath = p
	}
	if state.selectedAssetPath != "" {
		selRel := strings.trim_prefix(strings.trim_prefix(state.selectedAssetPath, state.projectPath), "/")
		if inside(selRel, oldRel, isFolder) {
			full, _ := filepath.join({state.projectPath, moved(selRel, oldRel, newRel)}, context.temp_allocator)
			Editor_SelectAsset(state, full)
		}
	}
	for r in reopen do Editor_OpenScript(state, r)
	if isFolder && assetFolderOpen[oldRel] do assetFolderOpen[strings.clone(newRel)] = true
	Editor_Log(state, .Info, "Moved %s to %s (%d reference(s) in %d file(s) updated)", oldRel, newRel, refs, files)
	return true
}

// Asset_NewFolder creates a folder (a unique "New Folder" name) in `parent`.
Asset_NewFolder :: proc(state: ^EditorState, parent: string) -> string {
	for i := 1; ; i += 1 {
		name := "New Folder" if i == 1 else fmt.tprintf("New Folder %d", i)
		rel, _ := filepath.join({parent, name}, context.temp_allocator)
		full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
		if os.exists(full) do continue
		if os.make_directory_all(full) != nil {
			Editor_Log(state, .Error, "Could not create %s", rel)
			return ""
		}
		Editor_InvalidateProjectFiles()
		Editor_Log(state, .Info, "Created %s", rel)
		return strings.clone(rel, context.temp_allocator)
	}
}
