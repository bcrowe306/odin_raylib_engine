package editor

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Asset actions: the context menu every asset row shows (open / add / use on
// the selection, plus copy, paste, duplicate, rename, delete, copy path and
// reveal), folder menus, and LDtk levels in the scene.
// ============================================================================

@(private = "file")
assetClipboard: string // project-relative path of the copied asset

@(private = "file")
pendingDelete: string
@(private = "file")
pendingRename: string

// Asset_BeginRename / Asset_BeginDelete: ask for a new name / confirm
// (files and folders).
Asset_BeginRename :: proc(rel: string) {
	delete(pendingRename)
	pendingRename = strings.clone(rel)
	Prompt_Open(.RenameAsset, filepath.base(rel))
}

Asset_BeginDelete :: proc(rel: string) {
	delete(pendingDelete)
	pendingDelete = strings.clone(rel)
}

Asset_HasClipboard :: proc() -> bool {return assetClipboard != ""}

@(private = "file")
menu :: proc(icon, label: string, id: string, enabled := true, shortcut: cstring = nil) -> bool {
	clicked := imgui.MenuItem(fmt.ctprintf("%s  %s", icon, label), shortcut, false, enabled)
	Drive_Item(fmt.tprintf("ctx:%s", id))
	return clicked
}

// Editor_AddLevel adds an LdtkLevelNode for an LDtk project (first level).
Editor_AddLevel :: proc(state: ^EditorState, rel: string, worldPos: [2]f32) -> ^e.Node {
	if state.activeScene == nil do return nil
	saved := state.cameraPos
	state.cameraPos = worldPos
	node := Editor_CreateNode(state, "LdtkLevelNode", filepath.stem(rel))
	state.cameraPos = saved
	if node == nil do return nil
	ln := cast(^e.LdtkLevelNode)node
	e.LdtkLevelNode_SetProject(ln, e.Project_ResolveAssetPath(&state.game.gameContext, rel), "")
	Editor_Log(state, .Info, "Added LDtk level %s", rel)
	return node
}

@(private = "file")
attach_script :: proc(state: ^EditorState, n: ^e.Node, rel: string) {
	Editor_RecordUndo(state, "Attach script")
	n.gameContext = &state.game.gameContext
	if e.Script_AttachToNode(n, rel, nil, &state.game.scriptManager) != nil {
		Editor_Log(state, .Info, "Attached %s to %s", rel, n.name)
	}
}

@(private = "file")
set_audio :: proc(state: ^EditorState, n: ^e.Node, rel: string) {
	rm := &state.game.resourceManager
	resolved := e.Project_ResolveAssetPath(&state.game.gameContext, rel)
	Editor_RecordUndo(state, "Set audio")
	if n.typeId == e.SoundNode {
		sn := cast(^e.SoundNode)n
		if sn.audio != nil do e.ResourceManager_ReleaseSound(rm, sn.audio)
		sn.audio = nil
		if s, ok := rm.loadAudioSound(rm, resolved); ok do sn.audio = s
	} else if n.typeId == e.MusicNode {
		mn := cast(^e.MusicNode)n
		if mn.music != nil do e.ResourceManager_ReleaseMusic(rm, mn.music)
		mn.music = nil
		if m, ok := rm.loadAudioMusic(rm, resolved); ok do mn.music = m
	}
}

// Asset_ContextMenu draws the actions for one asset (inside a popup).
Asset_ContextMenu :: proc(state: ^EditorState, rel: string) {
	kind := Asset_KindOf(rel)
	full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
	sel := state.selectedNode
	hasScene := state.activeScene != nil
	UI_DimText(filepath.base(rel))
	imgui.Separator()
	switch kind {
	case .Scene:
		if menu(ICON_FA_FOLDER_OPEN, "Open", "open-scene") do Editor_OpenScene(state, rel)
		if menu(ICON_FA_PLAY, "Play This Scene", "play-scene", !state.gameProcessRunning) {
			if Editor_OpenScene(state, rel) do Editor_PlayGameProcess(state, .CurrentScene)
		}
		if menu(ICON_FA_FLAG, "Set as Startup Scene", "startup-scene", state.projectConfig.initialScene != rel) {
			delete(state.projectConfig.initialScene)
			state.projectConfig.initialScene = strings.clone(rel)
			if !slice.contains(state.projectConfig.scenes[:], rel) do append(&state.projectConfig.scenes, strings.clone(rel))
			e.Project_SaveConfigToFile(state.projectPath, &state.projectConfig)
			Editor_Log(state, .Info, "Startup scene: %s", rel)
		}
	case .Component:
		if menu(ICON_FA_CUBES, "Edit Component", "edit-component") do Editor_OpenComponent(state, rel)
		if menu(ICON_FA_PLUS, "Add to Scene", "add-component", hasScene) do Component_InstantiateFromFile(state, full, state.cameraPos)
		if menu(ICON_FA_PLUS, "Add as Child of Selected", "add-component-child", hasScene && sel != nil) {
			Editor_InstantiateComponentFile(state, rel, sel.globalPosition)
		}
	case .Shader:
		if menu(ICON_FA_CODE, "Edit Shader", "edit-shader") do Editor_OpenScript(state, rel)
		if menu(ICON_FA_WAND_MAGIC_SPARKLES, "Use on Selected Node", "use-shader", sel != nil) {
			Editor_RecordUndo(state, "Set shader")
			e.Material_SetShader(sel, rel)
		}
	case .Script:
		if menu(ICON_FA_CODE, "Edit Script", "edit-script") do Editor_OpenScript(state, rel)
		if menu(ICON_FA_PLUS, "Attach to Selected Node", "attach-script", sel != nil && sel != state.activeScene.rootNode) {
			for n in Editor_SelectionRoots(state) do attach_script(state, n, rel)
		}
	case .Texture:
		if menu(ICON_FA_PLUS, "Add Sprite to Scene", "add-sprite", hasScene) do Editor_DropAsset(state, rel, state.cameraPos)
		if menu(ICON_FA_IMAGE, "Use on Selected Sprite", "use-texture", sel != nil && sel.typeId == e.TextureNode) {
			Editor_RecordUndo(state, "Set texture")
			Editor_SetTexture(state, cast(^e.TextureNode)sel, rel)
		}
		if menu(ICON_FA_TABLE_CELLS, "Use as Tileset of Selected Tile Map", "use-tileset", sel != nil && sel.typeId == e.TileMapNode) {
			Editor_RecordUndo(state, "Set tileset")
			e.TileMapNode_SetTileset(cast(^e.TileMapNode)sel, rel, &state.game.gameContext)
		}
	case .Audio:
		if menu(ICON_FA_PLUS, "Add Sound to Scene", "add-sound", hasScene) do Editor_DropAsset(state, rel, state.cameraPos)
		if menu(ICON_FA_PLUS, "Add Music to Scene", "add-music", hasScene) {
			saved := state.cameraPos
			n := Editor_CreateNode(state, "MusicNode", filepath.stem(rel))
			state.cameraPos = saved
			if n != nil do set_audio(state, n, rel)
		}
		if menu(ICON_FA_MUSIC, "Use on Selected Sound/Music", "use-audio", sel != nil && (sel.typeId == e.SoundNode || sel.typeId == e.MusicNode)) do set_audio(state, sel, rel)
	case .Level:
		if menu(ICON_FA_PLUS, "Add Level to Scene", "add-level", hasScene) do Editor_AddLevel(state, rel, state.cameraPos)
		if menu(ICON_FA_TABLE_CELLS, "Open in LDtk", "open-ldtk") do Editor_OpenExternally(state, full)
		if menu(ICON_FA_TABLE_CELLS, "Use on Selected Level", "use-level", sel != nil && sel.typeId == e.LdtkLevelNode) {
			Editor_RecordUndo(state, "Set LDtk project")
			e.LdtkLevelNode_SetProject(cast(^e.LdtkLevelNode)sel, e.Project_ResolveAssetPath(&state.game.gameContext, rel), "")
		}
	case .Package, .Other:
		if menu(ICON_FA_FOLDER_OPEN, "Open With Default App", "open-external") do Editor_OpenExternally(state, full)
	}
	imgui.Separator()
	if menu(ICON_FA_COPY, "Copy", "copy-asset", shortcut = nil) {
		delete(assetClipboard)
		assetClipboard = strings.clone(rel)
		imgui.SetClipboardText(strings.clone_to_cstring(rel, context.temp_allocator))
	}
	if menu(ICON_FA_PASTE, "Paste Here", "paste-asset", assetClipboard != "") {
		Asset_Paste(state, filepath.dir(rel, context.temp_allocator))
	}
	if menu(ICON_FA_CLONE, "Duplicate", "duplicate-asset") do Asset_Duplicate(state, rel, filepath.dir(rel, context.temp_allocator))
	if menu(ICON_FA_PEN, "Rename...", "rename-asset") do Asset_BeginRename(rel)
	if menu(ICON_FA_MAGNIFYING_GLASS, "Find Usages", "find-usages") do Asset_ShowUsages(state, rel, false)
	if menu(ICON_FA_TRASH, "Delete...", "delete-asset") do Asset_BeginDelete(rel)
	imgui.Separator()
	if menu(ICON_FA_LINK, "Copy Path", "copy-path") do imgui.SetClipboardText(strings.clone_to_cstring(rel, context.temp_allocator))
	if menu(ICON_FA_FOLDER_OPEN, "Reveal in Finder" when ODIN_OS == .Darwin else "Show in Folder", "reveal") do Editor_OpenExternally(state, filepath.dir(full, context.temp_allocator))
}

// Asset_FolderContextMenu: actions for a folder header in the Assets panel.
Asset_FolderContextMenu :: proc(state: ^EditorState, title: string) {
	folder := strings.to_lower(title, context.temp_allocator)
	switch title {
	case "Scenes": if menu(ICON_FA_PLUS, "New Scene", "new-scene") do Toolbar_NewScene(state)
	case "Scripts": if menu(ICON_FA_PLUS, "New Script", "new-script") do Editor_NewScript(state)
	case "Levels": if menu(ICON_FA_FILE_IMPORT, "Import LDtk Project...", "import-level") do Asset_OpenImportDialog(state, {"ldtk"}, "Import LDtk Project")
	}
	// Import with this folder's file types in the dialog filter.
	switch title {
	case "Textures": if menu(ICON_FA_FILE_IMPORT, "Import Textures...", "import-here") do Asset_OpenImportDialog(state, {"png", "jpg", "jpeg", "bmp", "tga"}, "Import Textures")
	case "Audio": if menu(ICON_FA_FILE_IMPORT, "Import Audio...", "import-here") do Asset_OpenImportDialog(state, {"wav", "ogg", "mp3"}, "Import Audio")
	case "Scripts": if menu(ICON_FA_FILE_IMPORT, "Import Scripts...", "import-here") do Asset_OpenImportDialog(state, {"lua"}, "Import Scripts")
	case "Scenes", "Components": if menu(ICON_FA_FILE_IMPORT, fmt.tprintf("Import %s...", title), "import-here") do Asset_OpenImportDialog(state, {"json"}, fmt.tprintf("Import %s", title))
	}
	if menu(ICON_FA_PASTE, "Paste", "paste-folder", assetClipboard != "") do Asset_Paste(state, folder)
	full, _ := filepath.join({state.projectPath, folder}, context.temp_allocator)
	if menu(ICON_FA_FOLDER_OPEN, "Reveal in Finder" when ODIN_OS == .Darwin else "Show in Folder", "reveal-folder") {
		_ = os.make_directory_all(full)
		Editor_OpenExternally(state, full)
	}
}

// --- file operations ---------------------------------------------------------------

@(private = "file")
unique_copy_name :: proc(state: ^EditorState, dir, base: string) -> string {
	// "ship.png" -> "ship_copy.png", "ship_copy_2.png", ...
	ext := ""
	stem := base
	for suffix in ([]string{".scene.json", ".component.json"}) {
		if strings.has_suffix(base, suffix) {ext = suffix; stem = base[:len(base) - len(suffix)]}
	}
	if ext == "" {
		ext = filepath.ext(base)
		stem = base[:len(base) - len(ext)]
	}
	for i := 1; ; i += 1 {
		name := fmt.tprintf("%s_copy%s", stem, ext) if i == 1 else fmt.tprintf("%s_copy_%d%s", stem, i, ext)
		rel, _ := filepath.join({dir, name}, context.temp_allocator)
		full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
		if !os.exists(full) do return rel
	}
}

Asset_Duplicate :: proc(state: ^EditorState, rel, toDir: string) -> string {
	Lua_MarkProjectTypesDirty() // generated Lua types follow the project
	src, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
	data, err := os.read_entire_file(src, context.temp_allocator)
	if err != nil {
		Editor_Log(state, .Error, "Could not read %s", rel)
		return ""
	}
	dst := unique_copy_name(state, toDir, filepath.base(rel))
	full, _ := filepath.join({state.projectPath, dst}, context.temp_allocator)
	_ = os.make_directory_all(filepath.dir(full, context.temp_allocator))
	if os.write_entire_file(full, data) != nil {
		Editor_Log(state, .Error, "Could not write %s", dst)
		return ""
	}
	if Asset_KindOf(dst) == .Scene {
		append(&state.projectConfig.scenes, strings.clone(dst))
		e.Project_SaveConfigToFile(state.projectPath, &state.projectConfig)
	}
	Editor_Log(state, .Info, "Copied %s to %s", rel, dst)
	return dst
}

Asset_Paste :: proc(state: ^EditorState, toDir: string) {
	if assetClipboard == "" do return
	Asset_Duplicate(state, assetClipboard, toDir)
}

Asset_Rename :: proc(state: ^EditorState, rel, newName: string) -> bool {
	dst, _ := filepath.join({filepath.dir(rel, context.temp_allocator), newName}, context.temp_allocator)
	return Asset_Move(state, rel, dst) // references follow (asset_refs.odin)
}

Asset_Delete :: proc(state: ^EditorState, rel: string) -> bool {
	Lua_MarkProjectTypesDirty() // generated Lua types follow the project
	full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
	isDir := os.is_dir(full)
	if (os.remove_all(full) if isDir else os.remove(full)) != nil {
		Editor_Log(state, .Error, "Could not delete %s", rel)
		return false
	}
	Editor_InvalidateProjectFiles()
	// Deleted scenes leave the project's scene list.
	prefix := strings.concatenate({rel, "/"}, context.temp_allocator)
	removed := false
	for i := len(state.projectConfig.scenes) - 1; i >= 0; i -= 1 {
		s := state.projectConfig.scenes[i]
		if s == rel || (isDir && strings.has_prefix(s, prefix)) {
			delete(s)
			ordered_remove(&state.projectConfig.scenes, i)
			removed = true
		}
	}
	if removed do e.Project_SaveConfigToFile(state.projectPath, &state.projectConfig)
	Editor_Log(state, .Info, "Deleted %s", rel)
	return true
}

// Asset_PromptApply finishes a rename started from a menu.
Asset_PromptApply :: proc(state: ^EditorState, kind: Prompt_Kind, text: string) {
	#partial switch kind {
	case .RenameAsset:
		if pendingRename != "" do Asset_Rename(state, pendingRename, text)
	}
}

// Asset_AddMenu: the Assets panel's "+" menu.
Asset_AddMenu :: proc(state: ^EditorState) {
	busy := NativeDialog_IsOpen()
	if menu(ICON_FA_FILE_IMPORT, "Import Assets...", "add-import", !busy) do Asset_OpenImportDialog(state)
	UI_Tooltip("Pick one or more files (images, audio, Lua, scenes, components, LDtk)")
	if menu(ICON_FA_FOLDER_PLUS, "Import Folder...", "add-import-folder", !busy) do Asset_OpenImportFolderDialog(state)
	UI_Tooltip("Imports every supported file in a folder, keeping its layout")
	imgui.Separator()
	if menu(ICON_FA_CLAPPERBOARD, "New Scene", "add-new-scene") do Toolbar_NewScene(state)
	if menu(ICON_FA_FILE_CODE, "New Script", "add-new-script") do Editor_NewScript(state)
	if menu(ICON_FA_WAND_MAGIC_SPARKLES, "New Shader", "add-new-shader") do Editor_NewShader(state)
}

// AssetDelete_Render: the delete confirmation.
AssetDelete_Render :: proc(state: ^EditorState) {
	if pendingDelete != "" && !imgui.IsPopupOpen("Delete Asset###DeleteAsset") do imgui.OpenPopup("Delete Asset###DeleteAsset")
	center := imgui.GetMainViewport().WorkPos + imgui.GetMainViewport().WorkSize * 0.5
	imgui.SetNextWindowPos(center, .Appearing, {0.5, 0.5})
	if !imgui.BeginPopupModal("Delete Asset###DeleteAsset", nil, {.NoTitleBar, .AlwaysAutoResize}) do return
	UI_PanelTitle(ICON_FA_TRASH, "Delete asset?")
	imgui.Dummy({0, 4})
	full, _ := filepath.join({state.projectPath, pendingDelete}, context.temp_allocator)
	if os.is_dir(full) {
		n := 0
		for f in Editor_ProjectFiles(state) do if strings.has_prefix(f, strings.concatenate({pendingDelete, "/"}, context.temp_allocator)) do n += 1
		imgui.TextUnformatted(fmt.ctprintf("The folder %s and the %d file(s) in it will be deleted.", pendingDelete, n))
	} else {
		imgui.TextUnformatted(fmt.ctprintf("%s will be deleted from the project folder.", pendingDelete))
	}
	UI_DimText("Scenes, scripts or components that use it will show it as missing.")
	imgui.Dummy({0, 6})
	if UI_PrimaryButton("Delete", "delete.ok", {96, 0}) {
		Asset_Delete(state, pendingDelete)
		delete(pendingDelete)
		pendingDelete = ""
		imgui.CloseCurrentPopup()
	}
	imgui.SameLine()
	if UI_Button("Cancel", "delete.cancel", {96, 0}) || imgui.IsKeyPressed(.Escape, false) {
		delete(pendingDelete)
		pendingDelete = ""
		imgui.CloseCurrentPopup()
	}
	imgui.EndPopup()
}
