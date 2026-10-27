package editor

import "core:fmt"
import "core:path/filepath"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"
import rl "vendor:raylib"

// ============================================================================
// Assets panel, Folders view: the project's real folders as a tree (the
// project folder at the top), files under each. Drag an asset or a folder
// onto a folder to move it there - references in scenes, components, scripts
// and project.json follow (asset_refs.odin). Folder menu: New Folder,
// Rename, Find Usages, Delete, Paste, Reveal. Also: image thumbnails for the
// grid, and the Find Usages window.
// ============================================================================

assetFolderOpen: map[string]bool

@(private = "file")
dir_of :: proc(rel: string) -> string {
	i := strings.last_index_byte(rel, '/')
	return rel[:i] if i >= 0 else ""
}

Asset_FoldersView :: proc(state: ^EditorState, filter: string) {
	if filter != "" {
		// Searching: the matching files, flat.
		shown := make([dynamic]string, context.temp_allocator)
		for f in Editor_ProjectFiles(state) do if strings.contains(strings.to_lower(f, context.temp_allocator), filter) do append(&shown, f)
		Asset_Items(state, shown[:])
		return
	}
	name := state.projectConfig.name if state.projectConfig.name != "" else "Project"
	if folder_row(state, "", name) do folder_contents(state, "")
}

@(private = "file")
folder_contents :: proc(state: ^EditorState, dir: string) {
	imgui.Indent(12)
	defer imgui.Unindent(12)
	for d in Editor_ProjectDirs(state) {
		if dir_of(d) != dir do continue
		if folder_row(state, d, filepath.base(d)) do folder_contents(state, d)
	}
	files := make([dynamic]string, context.temp_allocator)
	for f in Editor_ProjectFiles(state) do if dir_of(f) == dir do append(&files, f)
	Asset_Items(state, files[:], labelBase = true)
}

// folder_row: a folder (dir "" = the project folder); true when open.
@(private = "file")
folder_row :: proc(state: ^EditorState, dir, label: string) -> bool {
	if dir not_in assetFolderOpen do assetFolderOpen[strings.clone(dir)] = dir == ""
	open := assetFolderOpen[dir]
	if imgui.Selectable(fmt.ctprintf("##dir_%s", dir), false, {}, {0, 24}) {
		assetFolderOpen[dir] = !open
		open = !open
	}
	Drive_Item(fmt.tprintf("folder:%s", dir))
	mn := imgui.GetItemRectMin()
	if dir != "" && imgui.BeginDragDropSource({}) {
		p: Asset_Payload
		p.len = copy(p.path[:], dir)
		imgui.SetDragDropPayload(ASSET_PAYLOAD, &p, size_of(Asset_Payload))
		imgui.TextUnformatted(fmt.ctprintf("%s  %s", ICON_FA_FOLDER, label))
		imgui.EndDragDropSource()
	}
	// Drop an asset or folder here: move it into this folder.
	if imgui.BeginDragDropTarget() {
		if payload := imgui.AcceptDragDropPayload(ASSET_PAYLOAD); payload != nil {
			p := (^Asset_Payload)(payload.Data)
			src := strings.clone(string(p.path[:p.len]), context.temp_allocator)
			srcFull, _ := filepath.join({state.projectPath, src}, context.temp_allocator)
			if Editor_AssetIsSelected(state, srcFull) && len(state.selectedAssetPaths) > 1 {
				movedAny := false
				for f in state.selectedAssetPaths {
					r := strings.trim_prefix(strings.trim_prefix(f, state.projectPath), "/")
					dst, _ := filepath.join({dir, filepath.base(r)}, context.temp_allocator)
					if dir_of(r) != dir && Asset_Move(state, r, dst) {
						movedAny = true
					}
				}
				if movedAny {
					assetFolderOpen[strings.clone(dir)] = true
					Editor_ClearAssetSelection(state)
				}
			} else {
				dst, _ := filepath.join({dir, filepath.base(src)}, context.temp_allocator)
				if dir_of(src) != dir && Asset_Move(state, src, dst) do assetFolderOpen[strings.clone(dir)] = true
			}
		}
		imgui.EndDragDropTarget()
	}
	if imgui.BeginPopupContextItem(fmt.ctprintf("ctx_dir_%s", dir)) {
		folder_menu(state, dir)
		imgui.EndPopup()
	}
	imgui.SetCursorScreenPos({mn.x + 2, mn.y + 4})
	imgui.PushStyleColorImVec4(.Text, UI_WARNING)
	imgui.TextUnformatted(ICON_FA_FOLDER_OPEN if open else ICON_FA_FOLDER)
	imgui.PopStyleColor()
	imgui.SameLine(0, 8)
	imgui.TextUnformatted(strings.clone_to_cstring(label, context.temp_allocator))
	return open
}

@(private = "file")
folder_menu :: proc(state: ^EditorState, dir: string) {
	item :: proc(icon, label, id: string, enabled := true) -> bool {
		clicked := imgui.MenuItem(fmt.ctprintf("%s  %s", icon, label), nil, false, enabled)
		Drive_Item(fmt.tprintf("ctx:%s", id))
		return clicked
	}
	UI_DimText(dir if dir != "" else "Project folder")
	imgui.Separator()
	if item(ICON_FA_FOLDER_PLUS, "New Folder", "new-folder") {
		if rel := Asset_NewFolder(state, dir); rel != "" {
			assetFolderOpen[strings.clone(dir)] = true
			Asset_BeginRename(rel)
		}
	}
	if item(ICON_FA_PASTE, "Paste Here", "paste-into-folder", Asset_HasClipboard()) do Asset_Paste(state, dir)
	if dir != "" {
		imgui.Separator()
		if item(ICON_FA_PEN, "Rename...", "rename-folder") do Asset_BeginRename(dir)
		if item(ICON_FA_MAGNIFYING_GLASS, "Find Usages", "folder-usages") do Asset_ShowUsages(state, dir, true)
		if item(ICON_FA_TRASH, "Delete...", "delete-folder") do Asset_BeginDelete(dir)
	}
	imgui.Separator()
	full, _ := filepath.join({state.projectPath, dir}, context.temp_allocator)
	if item(ICON_FA_FOLDER_OPEN, "Reveal in Finder" when ODIN_OS == .Darwin else "Show in Folder", "reveal-dir") do Editor_OpenExternally(state, full)
}

// --- thumbnails -----------------------------------------------------------------------------

@(private = "file")
Thumb :: struct {
	tex: rl.Texture2D,
	ok:  bool,
}

@(private = "file")
thumbs: map[string]^Thumb

@(private = "file")
thumbFrame: i32
@(private = "file")
thumbBudget: int

// assetThumbsStale: files changed (Editor_InvalidateProjectFiles); reload.
assetThumbsStale: bool

THUMB_MAX :: 128

// Asset_Thumbnail: a small copy of an image file for the grid (a few are
// loaded per frame; nil until then or when it can't be read).
Asset_Thumbnail :: proc(full: string) -> ^rl.Texture2D {
	if assetThumbsStale {
		for k, t in thumbs {
			if t.ok do rl.UnloadTexture(t.tex)
			free(t)
			delete(k)
		}
		clear(&thumbs)
		assetThumbsStale = false
	}
	if t, ok := thumbs[full]; ok do return &t.tex if t.ok else nil
	if f := imgui.GetFrameCount(); f != thumbFrame {
		thumbFrame = f
		thumbBudget = 3
	}
	if thumbBudget <= 0 do return nil
	thumbBudget -= 1
	t := new(Thumb)
	thumbs[strings.clone(full)] = t
	img: rl.Image
	switch {
	case e.Ase_IsPath(full): img = e.Ase_LoadFileImage(full)
	case e.Vector_IsPath(full): img = e.Vector_FileImage(full, THUMB_MAX) // (rendered offscreen)
	case: img = rl.LoadImage(strings.clone_to_cstring(full, context.temp_allocator))
	}
	if img.data == nil do return nil
	if img.width > THUMB_MAX || img.height > THUMB_MAX {
		s := f32(THUMB_MAX) / f32(max(img.width, img.height))
		rl.ImageResize(&img, max(1, i32(f32(img.width) * s)), max(1, i32(f32(img.height) * s)))
	}
	t.tex = rl.LoadTextureFromImage(img)
	rl.UnloadImage(img)
	t.ok = t.tex.id != 0
	if t.ok do rl.SetTextureFilter(t.tex, .BILINEAR)
	return &t.tex if t.ok else nil
}

// --- Find Usages ----------------------------------------------------------------------------

@(private = "file")
usages: struct {
	open:     bool,
	path:     string,
	isFolder: bool,
	list:     [dynamic]Asset_Usage,
}

Asset_ShowUsages :: proc(state: ^EditorState, rel: string, isFolder: bool) {
	delete(usages.path)
	for u in usages.list do delete(u.file)
	clear(&usages.list)
	usages.path = strings.clone(rel)
	usages.isFolder = isFolder
	for u in Asset_FindUsages(state, rel, isFolder) do append(&usages.list, Asset_Usage{strings.clone(u.file), u.count})
	usages.open = true
	Editor_Log(state, .Info, "%s is used in %d file(s)", rel, len(usages.list))
}

// AssetUsages_Count: files in the open Find Usages window (drives).
AssetUsages_Count :: proc() -> int {
	return len(usages.list) if usages.open else -1
}

AssetUsages_Render :: proc(state: ^EditorState) {
	if !usages.open do return
	imgui.SetNextWindowSize({420, 300}, .Appearing)
	center := imgui.GetMainViewport().WorkPos + imgui.GetMainViewport().WorkSize * 0.5
	imgui.SetNextWindowPos(center, .Appearing, {0.5, 0.5})
	defer imgui.End()
	if !imgui.Begin(fmt.ctprintf("%s  Usages of %s###AssetUsages", ICON_FA_MAGNIFYING_GLASS, filepath.base(usages.path)), &usages.open, {.NoCollapse}) do return
	UI_DimText(fmt.tprintf("%s%s", usages.path, "/ (anything inside)" if usages.isFolder else ""))
	imgui.Separator()
	if len(usages.list) == 0 do UI_DimText("Not referenced by any scene, component, script or project setting.")
	for u in usages.list {
		kind := Asset_KindOf(u.file)
		icon, col := kind_icon(kind)
		imgui.PushStyleColorImVec4(.Text, col)
		clicked := imgui.Selectable(fmt.ctprintf("%s##u_%s", icon, u.file), false, {.AllowDoubleClick})
		imgui.PopStyleColor()
		Drive_Item(fmt.tprintf("usage:%s", u.file))
		if clicked && imgui.IsMouseDoubleClicked(.Left) {
			#partial switch kind {
			case .Scene: Editor_OpenScene(state, u.file)
			case .Component: Editor_OpenComponent(state, u.file)
			case .Script, .Other: Editor_OpenScript(state, u.file)
			}
		}
		UI_Tooltip("Double-click to open")
		imgui.SameLine(28)
		imgui.TextUnformatted(fmt.ctprintf("%s  ", u.file))
		imgui.SameLine()
		UI_DimText(fmt.tprintf("%d reference(s)", u.count))
	}
}
