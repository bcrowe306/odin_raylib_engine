package editor

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Assets panel: scenes, components, scripts, textures, audio and exported
// packages of the open project. Double-click opens a scene / instantiates a
// component; drag textures, components, audio or scripts into the viewport.
// ============================================================================

assetFilterBuf: [64]u8

ASSET_PAYLOAD :: "ORE_ASSET"

// Asset_Payload is the drag & drop payload: a project-relative path.
Asset_Payload :: struct {
	path: [512]u8,
	len:  int,
}

Asset_Kind :: enum {
	Other,
	Scene,
	Component,
	Script,
	Texture,
	Audio,
	Level,   // LDtk project (.ldtk)
	Shader,  // fragment shader (.fs / .glsl / .frag)
	Package,
}

Asset_KindOf :: proc(path: string) -> Asset_Kind {
	lower := strings.to_lower(path, context.temp_allocator)
	switch {
	case strings.has_suffix(lower, ".scene.json"): return .Scene
	case strings.has_suffix(lower, ".component.json"): return .Component
	case strings.has_suffix(lower, ".lua"): return .Script
	case strings.has_suffix(lower, ".ldtk"): return .Level
	case strings.has_suffix(lower, ".ore"): return .Package
	case strings.has_suffix(lower, ".fs"), strings.has_suffix(lower, ".glsl"), strings.has_suffix(lower, ".frag"): return .Shader
	}
	ext := filepath.ext(lower)
	switch {
	case slice.contains(TEXTURE_EXTS, ext): return .Texture
	case slice.contains(AUDIO_EXTS, ext): return .Audio
	}
	return .Other
}

kind_icon :: proc(k: Asset_Kind) -> (string, imgui.Vec4) {
	switch k {
	case .Scene: return ICON_FA_CLAPPERBOARD, UI_ACCENT
	case .Component: return ICON_FA_CUBES, {0.70, 0.52, 1.0, 1}
	case .Script: return ICON_FA_FILE_CODE, {0.40, 0.75, 1.0, 1}
	case .Texture: return ICON_FA_FILE_IMAGE, {0.95, 0.68, 0.35, 1}
	case .Audio: return ICON_FA_FILE_AUDIO, UI_SUCCESS
	case .Level: return ICON_FA_TABLE_CELLS, {0.35, 0.82, 0.86, 1}
	case .Shader: return ICON_FA_WAND_MAGIC_SPARKLES, {0.92, 0.55, 0.95, 1}
	case .Package: return ICON_FA_BOX_ARCHIVE, UI_TEXT_DIM
	case .Other: return ICON_FA_FILE, UI_TEXT_DIM
	}
	return ICON_FA_FILE, UI_TEXT_DIM
}

AssetBrowser_Render :: proc(state: ^EditorState) {
	defer imgui.End()
	if !imgui.Begin("Assets###AssetBrowserWindow") do return
	UI_PanelTitle(ICON_FA_FOLDER_OPEN, "Assets")
	// "+" at the right: import (system file dialog) or create.
	imgui.SameLine(imgui.GetWindowContentRegionMax().x - 26)
	imgui.SetCursorPosY(imgui.GetCursorPosY() - 3)
	if UI_IconButton(ICON_FA_PLUS, "asset.add", "Import assets or create new", active = imgui.IsPopupOpen("##asset_add"), size = 26) do imgui.OpenPopup("##asset_add")
	if imgui.BeginPopup("##asset_add") {
		Asset_AddMenu(state)
		imgui.EndPopup()
	}
	assetPanelRect.min = imgui.GetWindowPos()
	assetPanelRect.max = assetPanelRect.min + imgui.GetWindowSize()
	assetPanelRect.frame = imgui.GetFrameCount()

	imgui.SetNextItemWidth(-1)
	imgui.InputTextWithHint("##AssetFilter", fmt.ctprintf("%s  Search assets", ICON_FA_MAGNIFYING_GLASS), cstring(raw_data(assetFilterBuf[:])), len(assetFilterBuf), {})
	Drive_Item("asset.search")
	filter := strings.to_lower(string(cstring(raw_data(assetFilterBuf[:]))), context.temp_allocator)

	imgui.PushStyleVarImVec2(.ItemSpacing, {6, 2})
	defer imgui.PopStyleVar()
	if imgui.BeginChild("##assets", {0, 0}, {}, {}) {
		section_files(state, "Scenes", Editor_ListProjectFiles(state, "scenes", {".scene.json"}), filter)
		section_components(state, filter)
		section_files(state, "Scripts", Editor_ListProjectFiles(state, "scripts", {".lua"}), filter)
		section_files(state, "Textures", Editor_ListProjectFiles(state, "textures", TEXTURE_EXTS), filter)
		section_files(state, "Audio", Editor_ListProjectFiles(state, "audio", AUDIO_EXTS), filter)
		section_files(state, "Levels", Editor_ListProjectFiles(state, "", {".ldtk"}), filter)
		section_files(state, "Shaders", Editor_ListProjectFiles(state, "", SHADER_EXTS), filter)
		section_packages(state, filter)
		imgui.Dummy({0, 8})
		UI_DimText(fmt.tprintf("%s  Drop files or folders here to import", ICON_FA_FILE_IMPORT))
	}
	imgui.EndChild()
}

@(private = "file")
matches :: proc(path, filter: string) -> bool {
	return filter == "" || strings.contains(strings.to_lower(path, context.temp_allocator), filter)
}

@(private = "file")
section_files :: proc(state: ^EditorState, title: string, files: []string, filter: string) {
	n := 0
	for f in files do if matches(f, filter) do n += 1
	if filter != "" && n == 0 do return
	open := asset_folder_header(title, n, add_scene = title == "Scenes", add_script = title == "Scripts", state = state)
	if !open do return
	for f in files {
		if !matches(f, filter) do continue
		asset_row(state, f)
	}
}

// asset_row draws one file row; returns true when double-clicked.
@(private = "file")
asset_row :: proc(state: ^EditorState, rel: string, label: string = "") -> bool {
	kind := Asset_KindOf(rel)
	icon, col := kind_icon(kind)
	full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
	selected := state.selectedAssetPath == full
	isActive := kind == .Scene && state.activeScenePath == rel

	name := label if label != "" else rel
	// Show paths below the category folder ("textures/exhaust/x.png" -> "exhaust/x.png").
	if label == "" {
		if i := strings.index_byte(rel, '/'); i >= 0 do name = rel[i + 1:]
	}
	suffix := ""
	if kind == .Scene {
		if s := e.Game_FindSceneByFile(state.game, rel); s != nil && Editor_SceneIsModifiedCached(state, s) do suffix = "  " + ICON_FA_CIRCLE
	}
	if kind == .Script && Code_IsDirty(state, rel) do suffix = "  " + ICON_FA_CIRCLE

	imgui.PushStyleColorImVec4(.Text, col)
	clicked := imgui.Selectable(fmt.ctprintf("%s##a_%s", icon, rel), selected || isActive, {.AllowDoubleClick}, {0, 24})
	imgui.PopStyleColor()
	Drive_Item(fmt.tprintf("asset:%s", rel))
	rowMin, rowMax := imgui.GetItemRectMin(), imgui.GetItemRectMax()
	dbl := imgui.IsItemHovered() && imgui.IsMouseDoubleClicked(.Left)
	if imgui.BeginPopupContextItem(fmt.ctprintf("ctx_%s", rel)) {
		Asset_ContextMenu(state, rel)
		imgui.EndPopup()
	}

	// Drag into the viewport.
	if kind != .Scene && kind != .Package && imgui.BeginDragDropSource({}) {
		p: Asset_Payload
		p.len = copy(p.path[:], rel)
		imgui.SetDragDropPayload(ASSET_PAYLOAD, &p, size_of(Asset_Payload))
		imgui.TextUnformatted(fmt.ctprintf("%s  %s", icon, name))
		imgui.EndDragDropSource()
	}
	imgui.SameLine(32)
	imgui.PushStyleColorImVec4(.Text, UI_ACCENT if isActive else UI_TEXT)
	imgui.TextUnformatted(fmt.ctprintf("%s%s", name, suffix))
	imgui.PopStyleColor()

	if clicked do Editor_SelectAsset(state, full)
	if Asset_IsHighlighted(rel) {
		imgui.DrawList_AddRectFilled(imgui.GetWindowDrawList(), rowMin, rowMax, col_u32(UI_ACCENT_SOFT), 4)
		if importHighlight.focus {
			imgui.SetScrollHereY(0.5)
			importHighlight.focus = false
		}
	}
	if dbl {
		#partial switch kind {
		case .Scene: Editor_OpenScene(state, rel)
		case .Component: Component_InstantiateFromFile(state, full, state.cameraPos)
		case .Script: Editor_OpenScript(state, rel)
		case .Level: Editor_AddLevel(state, rel, state.cameraPos)
		case .Shader: Editor_OpenScript(state, rel)
		}
	}
	UI_Tooltip(asset_tooltip(kind, rel))
	return dbl
}

@(private = "file")
asset_tooltip :: proc(k: Asset_Kind, rel: string) -> string {
	#partial switch k {
	case .Scene: return fmt.tprintf("%s - double-click to open", rel)
	case .Component: return fmt.tprintf("%s - double-click or drag into the viewport to add", rel)
	case .Texture: return fmt.tprintf("%s - drag into the viewport to add a sprite", rel)
	case .Audio: return fmt.tprintf("%s - drag into the viewport to add a sound", rel)
	case .Script: return fmt.tprintf("%s - drag onto a node in the viewport to attach", rel)
	case .Level: return fmt.tprintf("%s - LDtk project: double-click or drag into the viewport to add a level", rel)
	}
	return rel
}

@(private = "file")
section_components :: proc(state: ^EditorState, filter: string) {
	files := Editor_ListProjectFiles(state, "components", {".component.json"})
	n := 0
	for f in files do if matches(f, filter) do n += 1
	for comp in state.components do if matches(comp.name, filter) do n += 1
	if filter != "" && n == 0 do return
	if !asset_folder_header("Components", n, state = state) do return
	for f in files {
		if matches(f, filter) do asset_row(state, f)
	}
	// Built-in templates.
	for &comp, idx in state.components {
		if !matches(comp.name, filter) do continue
		icon, col := kind_icon(.Component)
		imgui.PushStyleColorImVec4(.Text, col)
		clicked := imgui.Selectable(fmt.ctprintf("%s##tpl%d", icon, idx), state.selectedCompIdx == idx, {.AllowDoubleClick}, {0, 24})
		imgui.PopStyleColor()
		Drive_Item(fmt.tprintf("asset:component:%s", comp.name))
		if clicked do state.selectedCompIdx = idx
		if imgui.IsItemHovered() && imgui.IsMouseDoubleClicked(.Left) do Component_Instantiate(state, &comp, state.cameraPos)
		if imgui.BeginPopupContextItem(fmt.ctprintf("ctx_tpl%d", idx)) {
			if imgui.MenuItem(fmt.ctprintf("%s  Add to Scene", ICON_FA_PLUS), nil, false, state.activeScene != nil) do Component_Instantiate(state, &comp, state.cameraPos)
			Drive_Item("ctx:add-template")
			if imgui.MenuItem(fmt.ctprintf("%s  Add as Child of Selected", ICON_FA_PLUS), nil, false, state.selectedNode != nil) do Component_Instantiate(state, &comp, state.selectedNode.globalPosition)
			imgui.EndPopup()
		}
		UI_Tooltip(fmt.tprintf("%s - built-in template. Double-click to add.", comp.description))
		imgui.SameLine(32)
		imgui.TextUnformatted(strings.clone_to_cstring(comp.name, context.temp_allocator))
		imgui.SameLine(0, 6)
		UI_DimText(comp.category)
	}
}

@(private = "file")
section_packages :: proc(state: ^EditorState, filter: string) {
	dir := filepath.dir(strings.trim_suffix(state.projectPath, "/"), context.temp_allocator)
	h, err := os.open(dir)
	if err != nil do return
	infos, _ := os.read_dir(h, -1, context.temp_allocator)
	os.close(h)
	pkgs := make([dynamic]string, context.temp_allocator)
	for fi in infos {
		if fi.type != .Directory && strings.has_suffix(fi.name, ".ore") && matches(fi.name, filter) do append(&pkgs, fi.name)
	}
	if len(pkgs) == 0 do return
	if !asset_folder_header("Packages", len(pkgs), default_open = false) do return
	for p in pkgs {
		icon, col := kind_icon(.Package)
		imgui.PushStyleColorImVec4(.Text, col)
		imgui.Selectable(fmt.ctprintf("%s##pkg_%s", icon, p), false, {}, {0, 24})
		imgui.PopStyleColor()
		Drive_Item(fmt.tprintf("asset:package:%s", p))
		if imgui.BeginPopupContextItem(fmt.ctprintf("ctx_pkg_%s", p)) {
			pkgPath, _ := filepath.join({dir, p}, context.temp_allocator)
			if imgui.MenuItem(fmt.ctprintf("%s  Run Game From Package", ICON_FA_PLAY), nil, false, !state.gameProcessRunning) do Editor_RunPackage(state, pkgPath)
			Drive_Item("ctx:run-package")
			if imgui.MenuItem(fmt.ctprintf("%s  Reveal in Finder", ICON_FA_FOLDER_OPEN)) do Editor_OpenExternally(state, dir)
			if imgui.MenuItem(fmt.ctprintf("%s  Copy Path", ICON_FA_LINK)) do imgui.SetClipboardText(strings.clone_to_cstring(pkgPath, context.temp_allocator))
			imgui.Separator()
			if imgui.MenuItem(fmt.ctprintf("%s  Delete Package", ICON_FA_TRASH)) {
				if os.remove(pkgPath) == nil do Editor_Log(state, .Info, "Deleted %s", p)
			}
			imgui.EndPopup()
		}
		UI_Tooltip("Exported game package. Run it with: odin_raylib_engine --project <file>.ore")
		imgui.SameLine(32)
		imgui.TextUnformatted(strings.clone_to_cstring(p, context.temp_allocator))
	}
}

// AssetBrowser_HandleViewportDrop accepts an asset dropped on the viewport
// (call right after the viewport image item).
AssetBrowser_HandleViewportDrop :: proc(state: ^EditorState, worldPos: [2]f32) {
	if !imgui.BeginDragDropTarget() do return
	defer imgui.EndDragDropTarget()
	payload := imgui.AcceptDragDropPayload(ASSET_PAYLOAD)
	if payload == nil do return
	p := (^Asset_Payload)(payload.Data)
	rel := strings.clone(string(p.path[:p.len]), context.temp_allocator)
	Editor_DropAsset(state, rel, worldPos)
}

// Editor_DropAsset adds an asset to the scene at a world position.
Editor_DropAsset :: proc(state: ^EditorState, rel: string, worldPos: [2]f32) {
	switch Asset_KindOf(rel) {
	case .Texture:
		saved := state.cameraPos
		state.cameraPos = worldPos
		state.selectedNode = nil
		node := Editor_CreateNode(state, "TextureNode", filepath.stem(rel))
		state.cameraPos = saved
		if node != nil do Editor_SetTexture(state, cast(^e.TextureNode)node, rel)
	case .Audio:
		saved := state.cameraPos
		state.cameraPos = worldPos
		state.selectedNode = nil
		node := Editor_CreateNode(state, "SoundNode", filepath.stem(rel))
		state.cameraPos = saved
		if node != nil {
			sn := cast(^e.SoundNode)node
			rm := &state.game.resourceManager
			if s, ok := rm.loadAudioSound(rm, e.Project_ResolveAssetPath(&state.game.gameContext, rel)); ok do sn.audio = s
		}
	case .Component:
		full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
		state.selectedNode = nil
		Component_InstantiateFromFile(state, full, worldPos)
	case .Script:
		target := Viewport_PickNode(state, worldPos)
		if target == nil do target = state.selectedNode
		if target == nil {
			Editor_Log(state, .Warn, "Drop the script onto a node to attach it")
			return
		}
		Editor_RecordUndo(state, "Attach script")
		target.gameContext = &state.game.gameContext
		if e.Script_AttachToNode(target, rel, nil, &state.game.scriptManager) != nil {
			state.selectedNode = target
			Editor_Log(state, .Info, "Attached %s to %s", rel, target.name)
		}
	case .Level:
		Editor_AddLevel(state, rel, worldPos)
	case .Shader:
		// Onto a node: it gets this shader.
		target := Viewport_PickNode(state, worldPos)
		if target == nil do target = state.selectedNode
		if target == nil {
			Editor_Log(state, .Warn, "Drop the shader onto a node to apply it")
			return
		}
		Editor_RecordUndo(state, "Set shader")
		e.Material_SetShader(target, rel)
		state.selectedNode = target
		Editor_Log(state, .Info, "%s uses %s", target.name, rel)
	case .Scene, .Package, .Other:
	}
}

// Editor_SelectAsset selects a file in the Assets panel and previews it.
Editor_SelectAsset :: proc(state: ^EditorState, full: string) {
	if state.selectedAssetPath != full {
		delete(state.selectedAssetPath)
		state.selectedAssetPath = strings.clone(full)
	}
	PreviewPanel_OnAssetSelected(state, full)
}

// Kept for callers of the previous API.
AssetBrowser_LoadSceneFile :: proc(state: ^EditorState, fullPath, relPath: string) {
	Editor_OpenScene(state, relPath)
}

// Open/closed state of the asset folders (default: open).
assetFolderClosed: map[string]bool

// asset_folder_header draws a folder row: open-folder icon when expanded,
// closed folder when collapsed (no tree arrow). Click toggles. The Scenes
// folder gets a "+" (new scene) button at its right edge.
@(private = "file")
asset_folder_header :: proc(title: string, count: int, default_open := true, add_scene := false, add_script := false, state: ^EditorState = nil) -> bool {
	if title not_in assetFolderClosed do assetFolderClosed[strings.clone(title)] = !default_open
	open := !assetFolderClosed[title]

	imgui.Dummy({0, 2})
	imgui.SetNextItemAllowOverlap() // the + button sits on the row
	if imgui.Selectable(fmt.ctprintf("##folder_%s", title), false, {}, {0, 26}) {
		assetFolderClosed[title] = open
		open = !open
	}
	Drive_Item(fmt.tprintf("section:%s", title))
	if state != nil && imgui.BeginPopupContextItem(fmt.ctprintf("ctx_folder_%s", title)) {
		Asset_FolderContextMenu(state, title)
		imgui.EndPopup()
	}
	rowMin := imgui.GetItemRectMin()
	rowMax := imgui.GetItemRectMax()

	// Icon + caption drawn over the selectable.
	imgui.SetCursorScreenPos({rowMin.x + 2, rowMin.y + 4})
	imgui.PushStyleColorImVec4(.Text, UI_WARNING)
	imgui.TextUnformatted(ICON_FA_FOLDER_OPEN if open else ICON_FA_FOLDER)
	imgui.PopStyleColor()
	imgui.SameLine(0, 8)
	imgui.PushFont(GlobalFonts.semibold)
	imgui.PushStyleColorImVec4(.Text, UI_TEXT_DIM)
	imgui.TextUnformatted(strings.clone_to_cstring(strings.to_upper(title, context.temp_allocator), context.temp_allocator))
	imgui.PopStyleColor()
	imgui.PopFont()
	imgui.SameLine(0, 6)
	UI_DimText(fmt.tprint(count))

	if add_scene && state != nil {
		imgui.SetCursorScreenPos({rowMax.x - 26, rowMin.y})
		if UI_IconButton(ICON_FA_PLUS, "asset.new-scene", "New scene (Ctrl+N)", size = 26) do Toolbar_NewScene(state)
	}
	if add_script && state != nil {
		imgui.SetCursorScreenPos({rowMax.x - 26, rowMin.y})
		if UI_IconButton(ICON_FA_PLUS, "asset.new-script", "New Lua script", size = 26) do Editor_NewScript(state)
	}
	imgui.SetCursorScreenPos({rowMin.x, rowMax.y + 2})
	imgui.Dummy({0, 0})
	return open
}
