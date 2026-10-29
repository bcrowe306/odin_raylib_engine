package editor

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:time"
import rl "vendor:raylib"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Asset import: copies files from outside the project into it.
//
// Sources: the Assets panel's + menu and folder menus (system file dialog,
// multi-select), or files / folders dropped onto the editor window from the
// OS file manager (dropped on the viewport, they are also added to the
// scene). Each file goes to the folder for its type (textures/, audio/,
// scripts/, scenes/, components/, levels/); a dropped folder keeps its
// layout below that. Contents are checked (images decode, audio has a known
// header, JSON parses) so a bad file fails on its own while the rest import.
// LDtk projects bring their external levels and the tileset images they
// reference (into textures/, with the paths in the level rewritten).
// Results go to the console; failures open the Import Results window.
// ============================================================================

TEXTURE_EXTS := []string{".png", ".jpg", ".jpeg", ".bmp", ".tga"}
AUDIO_EXTS := []string{".wav", ".ogg", ".mp3"}

// Extensions the importer accepts (for dialog filters), without dots.
IMPORT_EXTS := []string{"png", "jpg", "jpeg", "bmp", "tga", "aseprite", "ase", "wav", "ogg", "mp3", "lua", "json", "ldtk", "fs", "glsl", "frag"}

// Import_Options: where files go and what happens to a taken name (the
// File Browser's Load; everything else imports with the defaults).
Import_Options :: struct {
	dest:     string,          // project folder ("sprites/enemies"); "" = the folder for its type
	conflict: Import_Conflict, // a different file already has the name
}

Import_Conflict :: enum {
	Rename,    // import beside it ("ship_2.png")
	Overwrite, // replace it
	Skip,      // keep it, import nothing
}

Import_Status :: enum {
	Imported,
	Skipped, // already in the project
	Failed,
}

Import_Entry :: struct {
	source:  string,
	rel:     string, // project-relative destination ("" when failed)
	status:  Import_Status,
	message: string,
}

@(private = "file")
report: struct {
	entries: [dynamic]Import_Entry,
	open:    bool,
}

// Recently imported assets, highlighted in the Assets panel for a moment.
importHighlight: struct {
	rels:  [dynamic]string,
	until: time.Time,
	focus: bool, // scroll the first one into view
}

// Asset_ImportDir: the project folder an asset of this file name goes to.
Asset_ImportDir :: proc(name: string) -> (dir: string, ok: bool) {
	lower := strings.to_lower(name, context.temp_allocator)
	switch Asset_KindOf(lower) {
	case .Texture:   return "textures", true
	case .Audio:     return "audio", true
	case .Script:    return "scripts", true
	case .Scene:     return "scenes", true
	case .Component: return "components", true
	case .Level:     return "levels", true
	case .Shader:    return "shaders", true
	case .Aseprite:  return "sprites", true
	case .Vector:    return "vectors", true
	case .Resource:  return "resources", true
	case .CustomNode: return "nodes", true
	case .Generator: return "levels", true
	case .Package, .Other:
	}
	return "", false
}

// Asset_ImportFiles imports files and folders (absolute or cwd-relative
// paths); returns the project-relative paths now in the project, in order.
// With opts.dest, every file goes to that folder (any file type: copied as
// it is when the importer doesn't know it).
Asset_ImportFiles :: proc(state: ^EditorState, paths: []string, opts := Import_Options{}) -> []string {
	Lua_MarkProjectTypesDirty() // generated Lua types follow the project
	report_clear()
	out := make([dynamic]string, context.temp_allocator)
	for p in paths {
		abs, aerr := os.get_absolute_path(p, context.temp_allocator)
		if aerr != nil do abs = p
		abs = strings.trim_right(abs, "/\\")
		if os.is_dir(abs) {
			import_folder(state, abs, filepath.base(abs), &out, 0, opts)
		} else if rel, ok := import_file(state, abs, "", opts); ok {
			append(&out, rel)
		}
	}

	imported, skipped, failed := report_counts()
	if failed > 0 {
		Editor_Log(state, .Warn, "Imported %d asset(s), %d failed%s - see Import Results", imported, failed, fmt.tprintf(", %d already in the project", skipped) if skipped > 0 else "")
		report.open = true
	} else if imported > 0 {
		Editor_Log(state, .Info, "Imported %d asset(s)%s", imported, fmt.tprintf(", %d already in the project", skipped) if skipped > 0 else "")
	} else if skipped > 0 {
		Editor_Log(state, .Info, "Already in the project: %s", strings.join(out[:], ", ", context.temp_allocator))
	}

	// Show them: open their folders, select and highlight.
	for s in importHighlight.rels do delete(s)
	clear(&importHighlight.rels)
	for rel in out {
		append(&importHighlight.rels, strings.clone(rel))
		if dir, ok := Asset_ImportDir(rel); ok && opts.dest == "" {
			title := strings.to_upper(dir[:1], context.temp_allocator)
			title = strings.concatenate({title, dir[1:]}, context.temp_allocator)
			if title in assetFolderClosed do assetFolderClosed[title] = false
		}
	}
	if len(out) > 0 {
		importHighlight.until = time.time_add(time.now(), 2 * time.Second)
		importHighlight.focus = true
		full, _ := filepath.join({state.projectPath, out[len(out) - 1]}, context.temp_allocator)
		Editor_SelectAsset(state, full)
	}
	return out[:]
}

// Asset_IsHighlighted: freshly imported (the Assets panel tints the row).
Asset_IsHighlighted :: proc(rel: string) -> bool {
	if len(importHighlight.rels) == 0 || time.diff(time.now(), importHighlight.until) < 0 do return false
	return slice.contains(importHighlight.rels[:], rel)
}

// Asset_OpenImportDialog: system file dialog for assets (multi-select).
// `only` limits the filter to one kind's extensions (e.g. {"ldtk"}).
Asset_OpenImportDialog :: proc(state: ^EditorState, only: []string = nil, title := "Import Assets") {
	exts := only
	if len(exts) == 0 {
		all := make([dynamic]string, context.temp_allocator)
		append(&all, ..IMPORT_EXTS)
		append(&all, ..PluginImporters_Exts()) // (plugin_extend.odin)
		exts = all[:]
	}
	// Opens where the last import came from.
	NativeDialog_Open(state, {title = title, filter = "Assets", exts = exts, multiple = true, start = Editor_StartDir(.Import)}, proc(state: ^EditorState, paths: []string) {
		Editor_RememberDir(.Import, paths[0])
		Asset_ImportFiles(state, paths)
	})
}

// Asset_OpenImportFolderDialog imports a whole folder (keeps its layout).
Asset_OpenImportFolderDialog :: proc(state: ^EditorState) {
	NativeDialog_Open(state, {title = "Import Folder", folders = true, start = Editor_StartDir(.Import)}, proc(state: ^EditorState, paths: []string) {
		// The folder it is in: the next folder is likely next to it.
		Editor_RememberDir(.Import, filepath.dir(paths[0], context.temp_allocator), true)
		Asset_ImportFiles(state, paths)
	})
}

// --- OS drag & drop ----------------------------------------------------------------

// Dropped files injected by a test drive (`drop-files`) or queued by
// Editor_QueueFileDrop, at a position.
driveDrop: struct {
	paths: [dynamic]string,
	pos:   [2]f32,
}

// Editor_QueueFileDrop: files dropped at a screen position as if from the
// OS file manager (the File Browser's drags) - handled with the next
// Editor_HandleFileDrops.
Editor_QueueFileDrop :: proc(paths: []string, pos: [2]f32) {
	for p in paths do append(&driveDrop.paths, strings.clone(p))
	driveDrop.pos = pos
}

// Rect of the Assets panel when last drawn (screen space) and the frame.
assetPanelRect: struct {
	min, max: [2]f32,
	frame:    i32,
}

// Editor_HandleFileDrops imports files dropped onto the window. Dropped on
// the viewport, the imported assets are also added to the scene there.
Editor_HandleFileDrops :: proc(state: ^EditorState) {
	paths := make([dynamic]string, context.temp_allocator)
	pos: [2]f32
	if rl.IsFileDropped() {
		list := rl.LoadDroppedFiles()
		for i in 0 ..< int(list.count) do append(&paths, strings.clone(string(list.paths[i]), context.temp_allocator))
		rl.UnloadDroppedFiles(list)
		pos = rl.GetMousePosition()
	}
	if len(driveDrop.paths) > 0 {
		for p in driveDrop.paths {
			append(&paths, strings.clone(p, context.temp_allocator))
			delete(p)
		}
		clear(&driveDrop.paths)
		pos = driveDrop.pos
	}
	if len(paths) == 0 do return
	if state.projectPath == "" {
		Editor_Log(state, .Error, "Open a project before importing assets")
		return
	}

	imported := Asset_ImportFiles(state, paths[:])

	// Onto the viewport: place what can be placed, fanned out a little.
	frame := imgui.GetFrameCount()
	overViewport := viewportShownFrame >= frame - 1 && point_in_rect(pos, state.viewportPos, state.viewportPos + state.viewportSize)
	overAssets := assetPanelRect.frame >= frame - 1 && point_in_rect(pos, assetPanelRect.min, assetPanelRect.max)
	if overViewport && !overAssets && state.activeScene != nil {
		world := Viewport_ScreenToWorld(state, pos)
		placed := 0
		for rel in imported {
			#partial switch Asset_KindOf(rel) {
			case .Texture, .Audio, .Component, .Level, .Aseprite, .Vector:
				Editor_DropAsset(state, rel, world + {f32(placed) * 24, f32(placed) * 24})
				placed += 1
			}
		}
	}
}

// --- import ------------------------------------------------------------------------

@(private = "file")
report_clear :: proc() {
	for &en in report.entries {
		delete(en.source)
		delete(en.rel)
		delete(en.message)
	}
	clear(&report.entries)
}

@(private = "file")
report_add :: proc(source, rel: string, status: Import_Status, message: string) {
	append(&report.entries, Import_Entry{strings.clone(source), strings.clone(rel), status, strings.clone(message)})
}

@(private = "file")
report_counts :: proc() -> (imported, skipped, failed: int) {
	for en in report.entries {
		switch en.status {
		case .Imported: imported += 1
		case .Skipped:  skipped += 1
		case .Failed:   failed += 1
		}
	}
	return
}

@(private = "file")
fail :: proc(state: ^EditorState, src, why: string) -> (string, bool) {
	report_add(src, "", .Failed, why)
	Editor_Log(state, .Error, "Import %s: %s", filepath.base(src), why)
	return "", false
}

// import_folder walks a dropped/picked folder; `sub` is the folder's
// layout below the type folder ("Space Pack/Box").
@(private = "file")
import_folder :: proc(state: ^EditorState, dir, sub: string, out: ^[dynamic]string, depth: int, opts: Import_Options) {
	if depth > 8 do return
	infos, err := os.read_all_directory_by_path(dir, context.temp_allocator)
	if err != nil {
		fail(state, dir, "could not read the folder")
		return
	}
	slice.sort_by(infos, proc(a, b: os.File_Info) -> bool {return a.name < b.name})
	for fi in infos {
		if strings.has_prefix(fi.name, ".") do continue
		full, _ := filepath.join({dir, fi.name}, context.temp_allocator)
		if fi.type == .Directory {
			// "<name>/" next to "<name>.ldtk" holds its external levels:
			// imported with the .ldtk.
			ldtk, _ := filepath.join({dir, fmt.tprintf("%s.ldtk", fi.name)}, context.temp_allocator)
			if os.exists(ldtk) do continue
			child, _ := filepath.join({sub, fi.name}, context.temp_allocator)
			import_folder(state, full, child, out, depth + 1, opts)
			continue
		}
		if rel, ok := import_file(state, full, sub, opts); ok do append(out, rel)
	}
}

// import_file copies one file into the project; returns its project path.
@(private = "file")
import_file :: proc(state: ^EditorState, src, sub: string, opts: Import_Options) -> (string, bool) {
	name := filepath.base(src)
	dir, supported := Asset_ImportDir(name)
	known := supported
	if opts.dest != "" {
		dir = opts.dest
		supported = true // (any file goes to a chosen folder)
	} else if raw, ok := import_raw_dir(name); ok {
		dir = raw
		supported = true
	}
	if !known && os.exists(src) {
		// A plugin's importer (plugin_extend.odin)?
		data, rerr := os.read_entire_file(src, context.temp_allocator)
		if rerr != nil do return fail(state, src, fmt.tprintf("could not read (%v)", rerr))
		if files, why, found := PluginImporters_Run(state, name, data); found {
			if why != "" do return fail(state, src, why)
			for f in files {
				full, _ := filepath.join({state.projectPath, f.rel}, context.temp_allocator)
				_ = os.make_directory_all(filepath.dir(full, context.temp_allocator))
				if werr := os.write_entire_file(full, f.data); werr != nil do return fail(state, src, fmt.tprintf("could not write %s (%v)", f.rel, werr))
				report_add(src, f.rel, .Imported, "")
				Editor_Log(state, .Info, "Imported %s -> %s", name, f.rel)
				_, _ = PluginEvents_Emit(state, "asset_imported", f.rel)
			}
			return files[0].rel, true
		}
	}
	if !supported {
		ext := filepath.ext(name)
		return fail(state, src, fmt.tprintf("unsupported file type (%s)", ext if ext != "" else "no extension"))
	}
	if !os.exists(src) do return fail(state, src, "file not found")

	// Already part of the project: nothing to copy.
	project, _ := filepath.clean(state.projectPath, context.temp_allocator)
	if inside, rel := path_inside(project, src); inside {
		report_add(src, rel, .Skipped, "already in the project")
		return strings.clone(rel, context.temp_allocator), true
	}

	data, rerr := os.read_entire_file(src, context.temp_allocator)
	if rerr != nil do return fail(state, src, fmt.tprintf("could not read (%v)", rerr))
	if known do if why, ok := validate(name, data); !ok do return fail(state, src, why)

	rel, _ := filepath.join({dir, sub, name}, context.temp_allocator)
	full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
	replaced := false
	if os.exists(full) {
		if existing, err := os.read_entire_file(full, context.temp_allocator); err == nil && slice.equal(existing, data) {
			report_add(src, rel, .Skipped, "already in the project")
			return rel, true
		}
		switch opts.conflict {
		case .Rename:
			rel = free_name(state, rel) // keep the existing file, import beside it
			full, _ = filepath.join({state.projectPath, rel}, context.temp_allocator)
		case .Overwrite:
			replaced = true
		case .Skip:
			report_add(src, rel, .Skipped, "a different file has the name (kept)")
			Editor_Log(state, .Info, "Skipped %s: %s exists", name, rel)
			return "", false
		}
	}

	if Asset_KindOf(name) == .Level do data = import_ldtk_deps(state, src, rel, data)

	_ = os.make_directory_all(filepath.dir(full, context.temp_allocator))
	if werr := os.write_entire_file(full, data); werr != nil do return fail(state, src, fmt.tprintf("could not write %s (%v)", rel, werr))

	if Asset_KindOf(rel) == .Scene && !slice.contains(state.projectConfig.scenes[:], rel) {
		append(&state.projectConfig.scenes, strings.clone(rel))
		e.Project_SaveConfigToFile(state.projectPath, &state.projectConfig)
	}
	renamed := filepath.base(rel) != name
	report_add(src, rel, .Imported, fmt.tprintf("renamed to %s (a different %s exists)", filepath.base(rel), name) if renamed else "replaced the file there" if replaced else "")
	Editor_Log(state, .Info, "%s %s -> %s", "Replaced" if replaced else "Imported", name, rel)
	_, _ = PluginEvents_Emit(state, "asset_imported", rel) // (plugin_events.odin)
	return rel, true
}

// import_raw_dir: the folder for files copied as they are, with no asset
// type of their own (fonts: UI and text nodes name them by path).
@(private = "file")
import_raw_dir :: proc(name: string) -> (string, bool) {
	switch strings.to_lower(filepath.ext(name), context.temp_allocator) {
	case ".ttf", ".otf", ".fnt": return "fonts", true
	}
	return "", false
}

// path_inside: is `path` inside `root`? (and the relative path)
@(private = "file")
path_inside :: proc(root, path: string) -> (bool, string) {
	clean, _ := filepath.clean(path, context.temp_allocator)
	rel, err := filepath.rel(root, clean, context.temp_allocator)
	if err != nil || rel == ".." || strings.has_prefix(rel, "../") || filepath.is_abs(rel) do return false, ""
	return true, rel
}

// free_name: "textures/ship.png" -> "textures/ship_2.png" (first unused).
@(private = "file")
free_name :: proc(state: ^EditorState, rel: string) -> string {
	dir := filepath.dir(rel, context.temp_allocator)
	base := filepath.base(rel)
	ext := filepath.ext(base)
	for suffix in ([]string{".scene.json", ".component.json"}) do if strings.has_suffix(base, suffix) do ext = suffix
	stem := base[:len(base) - len(ext)]
	for i := 2; ; i += 1 {
		cand, _ := filepath.join({dir, fmt.tprintf("%s_%d%s", stem, i, ext)}, context.temp_allocator)
		full, _ := filepath.join({state.projectPath, cand}, context.temp_allocator)
		if !os.exists(full) do return cand
	}
}

// validate checks a file's contents match its type.
@(private = "file")
validate :: proc(name: string, data: []byte) -> (why: string, ok: bool) {
	if len(data) == 0 do return "the file is empty", false
	lower := strings.to_lower(name, context.temp_allocator)
	switch Asset_KindOf(lower) {
	case .Aseprite:
		// The header's magic number (0xA5E0 at byte 4), then a full read.
		if len(data) < 128 || data[4] != 0xE0 || data[5] != 0xA5 do return "not an Aseprite file", false
		doc, why := e.Ase_Load(data)
		if doc == nil do return fmt.tprintf("can't be read: %s", why), false
		e.Ase_Destroy(doc)
	case .Vector:
		doc: e.Vector_Doc
		defer e.Vector_Doc_Destroy(&doc)
		if !e.Vector_LoadSVG(string(data), &doc) do return fmt.tprintf("not a readable SVG: %s", strings.join(doc.warnings[:], "; ", context.temp_allocator)), false
	case .Texture:
		img := rl.LoadImageFromMemory(strings.clone_to_cstring(filepath.ext(lower), context.temp_allocator), raw_data(data), i32(len(data)))
		if img.data == nil do return "not a readable image (corrupt, or a format the engine can't load)", false
		rl.UnloadImage(img)
	case .Audio:
		s := string(data)
		switch filepath.ext(lower) {
		case ".wav": if len(s) < 12 || s[:4] != "RIFF" || s[8:12] != "WAVE" do return "not a WAV file", false
		case ".ogg": if !strings.has_prefix(s, "OggS") do return "not an Ogg Vorbis file", false
		case ".mp3":
			mpeg := len(data) > 1 && data[0] == 0xFF && data[1] & 0xE0 == 0xE0
			if !strings.has_prefix(s, "ID3") && !mpeg do return "not an MP3 file", false
		}
	case .Generator:
		g, why := e.Gen_GraphParse(data, context.temp_allocator)
		if why != "" do return fmt.tprintf("not a level generator: %s", why), false
		_ = g
	case .Scene, .Component, .Level, .Resource, .CustomNode:
		val, err := json.parse(data, parse_integers = false, allocator = context.temp_allocator)
		if err != .None do return fmt.tprintf("invalid JSON (%v)", err), false
		obj, isObj := val.(json.Object)
		if !isObj do return "invalid JSON (not an object)", false
		#partial switch Asset_KindOf(lower) {
		case .Scene: if "root" not_in obj do return "not a scene file (no \"root\")", false
		case .Level: if "defs" not_in obj do return "not an LDtk project (no \"defs\")", false
		case .Component: if "type" not_in obj do return "not a component file (no \"type\")", false
		case .Resource: if _, ok := obj["script"].(json.String); !ok do return "not a resource file (no \"script\": its class)", false
		case .CustomNode: if _, ok := obj["name"].(json.String); !ok do return "not a custom node type (no \"name\")", false
		}
	case .Script, .Shader:
		if !utf8_valid(data) do return "not a text file", false
	case .Package, .Other:
		return "unsupported file type", false
	}
	return "", true
}

@(private = "file")
utf8_valid :: proc(data: []byte) -> bool {
	for b in data do if b == 0 do return false
	return true
}

// import_ldtk_deps copies an LDtk project's external levels and the images
// it references; returns the project JSON with image paths rewritten.
@(private = "file")
import_ldtk_deps :: proc(state: ^EditorState, src, rel: string, data: []byte) -> []byte {
	srcDir := filepath.dir(src, context.temp_allocator)
	dstDir := filepath.dir(rel, context.temp_allocator) // project-relative
	val, err := json.parse(data, parse_integers = false, allocator = context.temp_allocator)
	if err != .None do return data
	root := val.(json.Object) or_else nil

	refs := make([dynamic]string, context.temp_allocator)
	add_ref :: proc(refs: ^[dynamic]string, v: json.Value) {
		if s, ok := v.(json.String); ok && s != "" && !slice.contains(refs[:], s) do append(refs, s)
	}
	if defs, ok := root["defs"].(json.Object); ok {
		if tilesets, tok := defs["tilesets"].(json.Array); tok {
			for t in tilesets do if obj, isObj := t.(json.Object); isObj do add_ref(&refs, obj["relPath"])
		}
	}
	if levels, ok := root["levels"].(json.Array); ok {
		for l in levels do if obj, isObj := l.(json.Object); isObj do add_ref(&refs, obj["bgRelPath"])
	}

	// Each image goes to textures/ (reused when identical); the level then
	// points at it relative to its new folder.
	swaps := make([dynamic][2]string, context.temp_allocator) // quoted old -> quoted new
	for ref in refs {
		srcImg, _ := filepath.join({srcDir, ref}, context.temp_allocator)
		imgData, rerr := os.read_entire_file(srcImg, context.temp_allocator)
		if rerr != nil {
			report_add(srcImg, "", .Failed, fmt.tprintf("image referenced by %s not found", filepath.base(src)))
			Editor_Log(state, .Warn, "Import %s: referenced image %s not found", filepath.base(src), ref)
			continue
		}
		imgRel, _ := filepath.join({"textures", filepath.base(ref)}, context.temp_allocator)
		imgFull, _ := filepath.join({state.projectPath, imgRel}, context.temp_allocator)
		reuse := false
		if existing, eerr := os.read_entire_file(imgFull, context.temp_allocator); eerr == nil {
			reuse = slice.equal(existing, imgData)
			if !reuse {
				imgRel = free_name(state, imgRel)
				imgFull, _ = filepath.join({state.projectPath, imgRel}, context.temp_allocator)
			}
		}
		if !reuse {
			_ = os.make_directory_all(filepath.dir(imgFull, context.temp_allocator))
			if os.write_entire_file(imgFull, imgData) != nil {
				report_add(srcImg, "", .Failed, "could not write the tileset image")
				continue
			}
			report_add(srcImg, imgRel, .Imported, fmt.tprintf("used by %s", filepath.base(src)))
		}
		newRef, _ := filepath.rel(dstDir, imgRel, context.temp_allocator)
		newRef, _ = strings.replace_all(newRef, "\\", "/", context.temp_allocator)
		if newRef != ref do append(&swaps, [2]string{fmt.tprintf("%q", ref), fmt.tprintf("%q", newRef)})
	}
	rewrite :: proc(text: string, swaps: [][2]string) -> string {
		out := text
		for s in swaps do out, _ = strings.replace_all(out, s[0], s[1], context.temp_allocator)
		return out
	}

	// "Save levels separately": <name>/*.ldtkl next to the project (their
	// layer data carries the same image paths).
	extSrc := strings.trim_suffix(src, filepath.ext(src))
	if os.is_dir(extSrc) {
		extDst, _ := filepath.join({state.projectPath, dstDir, filepath.stem(rel)}, context.temp_allocator)
		_ = os.make_directory_all(extDst)
		infos, _ := os.read_all_directory_by_path(extSrc, context.temp_allocator)
		for fi in infos {
			if fi.type == .Directory || !strings.has_suffix(fi.name, ".ldtkl") do continue
			p, _ := filepath.join({extSrc, fi.name}, context.temp_allocator)
			lvl, lerr := os.read_entire_file(p, context.temp_allocator)
			if lerr != nil {
				report_add(p, "", .Failed, "could not read the external level")
				continue
			}
			out, _ := filepath.join({extDst, fi.name}, context.temp_allocator)
			_ = os.write_entire_file(out, transmute([]byte)rewrite(string(lvl), swaps[:]))
		}
	}
	return transmute([]byte)rewrite(string(data), swaps[:])
}

// --- Import Results window ---------------------------------------------------------

AssetImport_Render :: proc(state: ^EditorState) {
	if !report.open do return
	center := imgui.GetMainViewport().WorkPos + imgui.GetMainViewport().WorkSize * 0.5
	imgui.SetNextWindowPos(center, .Appearing, {0.5, 0.5})
	imgui.SetNextWindowSize({620, 0}, .Appearing)
	if imgui.Begin("Import Results###ImportResults", &report.open, {.NoTitleBar, .NoCollapse, .NoDocking, .AlwaysAutoResize}) {
		imported, skipped, failed := report_counts()
		UI_PanelTitle(ICON_FA_FILE_IMPORT, "Import Results", fmt.tprintf("%d imported, %d failed%s", imported, failed, fmt.tprintf(", %d already in the project", skipped) if skipped > 0 else ""))
		imgui.Dummy({0, 4})
		if imgui.BeginTable("##import_results", 2, imgui.TableFlags_RowBg | imgui.TableFlags_BordersInnerH | imgui.TableFlags_ScrollY | imgui.TableFlags_SizingStretchProp, {600, min(f32(len(report.entries)) * 26 + 8, 360)}) {
			imgui.TableSetupColumn("file", {.WidthStretch}, 0.45)
			imgui.TableSetupColumn("result", {.WidthStretch}, 0.55)
			// Failures first.
			for pass in 0 ..< 2 {
				for en in report.entries {
					if (en.status == .Failed) != (pass == 0) do continue
					imgui.TableNextRow()
					imgui.TableNextColumn()
					icon, col := ICON_FA_CIRCLE_CHECK, UI_SUCCESS
					if en.status == .Skipped do icon, col = ICON_FA_CIRCLE_INFO, UI_TEXT_FAINT
					if en.status == .Failed do icon, col = ICON_FA_CIRCLE_XMARK, UI_DANGER
					imgui.PushStyleColorImVec4(.Text, col)
					imgui.TextUnformatted(strings.clone_to_cstring(icon, context.temp_allocator))
					imgui.PopStyleColor()
					imgui.SameLine()
					imgui.TextUnformatted(strings.clone_to_cstring(filepath.base(en.source), context.temp_allocator))
					UI_Tooltip(en.source)
					imgui.TableNextColumn()
					switch en.status {
					case .Imported:
						imgui.TextUnformatted(strings.clone_to_cstring(en.rel, context.temp_allocator))
						if en.message != "" {
							imgui.SameLine()
							UI_DimText(en.message)
						}
					case .Skipped:
						UI_DimText(fmt.tprintf("%s - %s", en.rel, en.message))
					case .Failed:
						imgui.PushStyleColorImVec4(.Text, UI_DANGER)
						imgui.TextWrapped(strings.clone_to_cstring(en.message, context.temp_allocator))
						imgui.PopStyleColor()
					}
				}
			}
			imgui.EndTable()
		}
		imgui.Dummy({0, 4})
		UI_DimText(fmt.tprintf("Supported: %s", strings.join(IMPORT_EXTS, ", ", context.temp_allocator)))
		imgui.SameLine(imgui.GetWindowContentRegionMax().x - 96)
		if UI_PrimaryButton("Close", "import.close", {96, 0}) do report.open = false
	}
	imgui.End()
}

// AssetImport_DriveQuery: import.imported / import.skipped / import.failed
// (counts of the last import), import.report (window open), import.dialog.
AssetImport_DriveQuery :: proc(q: string) -> (string, bool) {
	imported, skipped, failed := report_counts()
	switch q {
	case "import.imported": return fmt.tprint(imported), true
	case "import.skipped":  return fmt.tprint(skipped), true
	case "import.failed":   return fmt.tprint(failed), true
	case "import.report":   return "true" if report.open else "false", true
	case "import.dialog":   return "true" if NativeDialog_IsOpen() else "false", true
	case "import.messages":
		sb := strings.builder_make(context.temp_allocator)
		for en in report.entries do fmt.sbprintf(&sb, "%s: %v %s %s\n", filepath.base(en.source), en.status, en.rel, en.message)
		return strings.to_string(sb), true
	}
	return "", false
}
