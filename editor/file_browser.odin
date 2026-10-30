package editor

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"
import rl "vendor:raylib"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// File Browser (the bottom panel's Files tab; View > File Browser): browse the computer's folders and
// preview files before they come into the project - images, sounds, fonts,
// Aseprite files, SVGs, text - then Load the ones you want (the asset
// importer: by type or into a chosen folder, with a rule for taken names).
// The Assets panel shows what is already in the project; this shows what
// isn't yet. Previewing never writes to the project.
//
// Layout: a toolbar (back / forward / up / refresh, the path, bookmark),
// a sidebar (bookmarks, recent folders, places, and the folder tree -
// expanded lazily), the folder's files (search - optionally through every
// sub-folder, a few folders a frame - type filter, sort, multi-select) and
// the preview of the selected file with Load at the bottom. Rows drag onto
// the Assets panel or the viewport like files from the OS file manager.
//
// Bookmarks, recent folders and the last folder are the editor's
// (settings.ini [file_browser*]), the same in every project.
// ============================================================================

FB_Kind :: enum {
	Folder,
	Image,
	Audio,
	Video,
	Font,
	Aseprite,
	Vector,
	Text,
	Other,
}

FB_KIND_NAMES := [FB_Kind]string {
	.Folder   = "folder",
	.Image    = "image",
	.Audio    = "audio",
	.Video    = "video",
	.Font     = "font",
	.Aseprite = "aseprite",
	.Vector   = "vector",
	.Text     = "text",
	.Other    = "other",
}

FB_Filter :: enum {
	All,
	Images,
	Audio,
	Video,
	Fonts,
	Game_Assets, // what a game uses: images, sound, Aseprite, SVG, fonts, scripts, scenes, levels, shaders
}

FB_FILTER_NAMES := []string{"All files", "Images", "Audio", "Video", "Fonts", "Game assets"}

FB_Sort :: enum {
	Name,
	Size,
	Modified,
	Type,
}

FB_SORT_NAMES := []string{"Name", "Size", "Modified", "Type"}

FB_Entry :: struct {
	name:  string, // (search results: the path below the folder searched)
	full:  string,
	isDir: bool,
	size:  i64,
	mod:   time.Time,
	kind:  FB_Kind,
}

@(private = "file")
FB_Listing :: struct {
	entries: [dynamic]FB_Entry, // (heap strings)
	failed:  bool,              // couldn't be read
}

// An image decoded on a worker thread (the GPU upload stays on this one).
@(private = "file")
FB_Image_Job :: struct {
	path:   string,
	kind:   FB_Kind,
	image:  rl.Image,
	strip:  e.Anim_Strip, // an animation's frames (Aseprite, GIF; #203)
	animated: bool,
	done:   bool, // (atomic)
	thread: ^thread.Thread,
}

@(private = "file")
FB_Preview :: struct {
	path:      string, // heap ("" = nothing selected)
	kind:      FB_Kind,
	size:      i64,
	mod:       time.Time,
	error:     string, // heap: why it can't be shown
	// Images (also Aseprite's first frame and SVGs)
	job:       ^FB_Image_Job,
	tex:       rl.Texture2D,
	hasTex:    bool,
	zoom:      f32, // 0 = fit
	pan:       [2]f32,
	// Animations (Aseprite frames, GIF): tex is a strip of frames (#203)
	animated:    bool,
	frameSize:   [2]int,
	durations:   []f32, // heap
	animTime:    f32,
	animPlaying: bool,
	// Audio
	music:     rl.Music,
	hasMusic:  bool,
	playing:   bool,
	length:    f32,
	// Fonts: a sample rendered into a texture
	font:      rl.Font,
	fontTex:   rl.RenderTexture2D,
	hasFont:   bool,
	// Text (heap)
	text:      string,
	truncated: bool,
}

FB_TEXT_LIMIT :: 64 * 1024
FB_RECENT_MAX :: 12
FB_SEARCH_DIRS_PER_FRAME :: 24
FB_SEARCH_MAX_RESULTS :: 2000
FB_SEARCH_MAX_DEPTH :: 12

@(private = "file")
fb: struct {
	inited:     bool,
	dir:        string, // the folder shown (heap)
	back:       [dynamic]string,
	forward:    [dynamic]string,
	pathBuf:    [1024]u8,
	pathShown:  string, // what pathBuf was last filled with (heap)
	pathEditing: bool,  // the path field is being typed in
	searchBuf:  [256]u8,
	recursive:  bool,
	showHidden: bool,
	filter:     FB_Filter,
	sort:       FB_Sort,
	descending: bool,
	listings:   map[string]^FB_Listing, // folder -> its entries (heap)
	selection:  [dynamic]string,        // full paths (heap)
	anchor:     string,                 // shift-click range start (heap)
	revealDir:  string,                 // open the tree down to this folder once (heap)
	search: struct {
		query:   string, // heap
		root:    string, // heap
		queue:   [dynamic]FB_Search_Dir,
		results: [dynamic]FB_Entry,
		scanned: int,
		done:    bool,
	},
	rows:       struct {
		key:     FB_Rows_Key,
		entries: [dynamic]FB_Entry, // (strings borrowed from the listing / search)
		valid:   bool,
	},
	preview:    FB_Preview,
	jobs:       [dynamic]^FB_Image_Job, // decoding (incl. ones nobody wants now)
	dest:       string, // Load destination: project folder ("" = by type; heap)
	conflict:   Import_Conflict,
	dragFrame:  i32, // last frame rows were being dragged
	winMin:     [2]f32,
	winMax:     [2]f32,
	settingsDirty: bool,
	scrollTo:      int, // a row to scroll into view (arrow keys; -1: none)
	shownFrame:    i32, // the frame the Files tab last drew
	drives:     [dynamic]string, // Windows: the drives there were when it opened (heap)
}

// What the file list was made from (made again when any changes).
@(private = "file")
FB_Rows_Key :: struct {
	listing:    ^FB_Listing,
	query:      [256]u8,
	recursive:  bool,
	results:    int,
	filter:     FB_Filter,
	sort:       FB_Sort,
	descending: bool,
	showHidden: bool,
}

@(private = "file")
FB_Search_Dir :: struct {
	path:  string, // heap
	depth: int,
}

// --- opening -------------------------------------------------------------------------

// FileBrowser_IsOpen: the Files tab is the one shown (#193).
FileBrowser_IsOpen :: proc() -> bool {return GlobalEditor.bottomTab == .Files}

// FileBrowser_Toggle shows the Files tab (View > File Browser).
FileBrowser_Toggle :: proc() {bottomTabRequest = .Files}

// FileBrowser_Open shows the browser at a folder ("" = where it was).
FileBrowser_Open :: proc(dir := "") {
	bottomTabRequest = .Files
	fb_init()
	if dir != "" do fb_navigate(dir)
}

@(private = "file")
fb_init :: proc() {
	if fb.inited do return
	fb.inited = true
	fb.scrollTo = -1
	fb.listings = make(map[string]^FB_Listing)
	when ODIN_OS == .Windows {
		for letter in 'A' ..= 'Z' {
			drive := fmt.tprintf("%c:\\", letter)
			if os.is_dir(drive) do append(&fb.drives, strings.clone(drive))
		}
	}
	start := GlobalSettings.fileBrowserDir
	if start == "" || !os.is_dir(start) {
		start = ""
		if home, err := os.user_home_dir(context.temp_allocator); err == nil do start = home
		if start == "" || !os.is_dir(start) {
			if cwd, err := os.get_working_directory(context.temp_allocator); err == nil do start = cwd
		}
	}
	fb_set_dir(start)
}

// --- folders -------------------------------------------------------------------------

// FileBrowser_KindOf: what a file is, for the preview and the type filter.
FileBrowser_KindOf :: proc(name: string) -> FB_Kind {
	lower := strings.to_lower(name, context.temp_allocator)
	if e.Ase_IsPath(lower) do return .Aseprite
	switch filepath.ext(lower) {
	case ".png", ".jpg", ".jpeg", ".bmp", ".tga", ".gif", ".qoi", ".psd", ".hdr": return .Image
	case ".wav", ".ogg", ".mp3", ".flac", ".qoa", ".xm", ".mod": return .Audio
	case ".mp4", ".webm", ".mov", ".avi", ".mkv", ".m4v", ".mpg", ".mpeg", ".ogv", ".wmv": return .Video
	case ".ttf", ".otf", ".fnt": return .Font
	case ".svg": return .Vector
	case ".lua", ".json", ".ldtk", ".ldtkl", ".txt", ".md", ".csv", ".tsv", ".ini", ".cfg", ".toml", ".yaml", ".yml", ".xml", ".fs", ".vs", ".glsl", ".frag", ".vert", ".tmx", ".tsx", ".atlas", ".rhubarb":
		return .Text
	}
	return .Other
}

// FileBrowser_Matches: does an entry pass the type filter and the search?
FileBrowser_Matches :: proc(en: FB_Entry, filter: FB_Filter, query: string) -> bool {
	if query != "" {
		if !strings.contains(strings.to_lower(en.name, context.temp_allocator), strings.to_lower(query, context.temp_allocator)) do return false
	}
	if en.isDir do return true // (whatever the type filter: to browse into)
	switch filter {
	case .All: return true
	case .Images: return en.kind == .Image || en.kind == .Aseprite || en.kind == .Vector
	case .Audio: return en.kind == .Audio
	case .Video: return en.kind == .Video
	case .Fonts: return en.kind == .Font
	case .Game_Assets:
		#partial switch en.kind {
		case .Image, .Audio, .Font, .Aseprite, .Vector: return true
		case .Text: return Asset_KindOf(en.name) != .Other || strings.has_suffix(strings.to_lower(en.name, context.temp_allocator), ".ldtkl")
		}
		return false
	}
	return true
}

// FileBrowser_Sort: folders first, then by the column (names compare
// case-insensitively; ties by name).
FileBrowser_Sort :: proc(entries: []FB_Entry, by: FB_Sort, descending: bool) {
	Ctx :: struct {by: FB_Sort, desc: bool}
	@(static) ctx: Ctx
	ctx = {by, descending}
	slice.sort_by(entries, proc(a, b: FB_Entry) -> bool {
		if a.isDir != b.isDir do return a.isDir
		la := strings.to_lower(a.name, context.temp_allocator)
		lb := strings.to_lower(b.name, context.temp_allocator)
		less, equal: bool
		switch ctx.by {
		case .Name: less, equal = la < lb, la == lb
		case .Size: less, equal = a.size < b.size, a.size == b.size
		case .Modified:
			ta, tb := time.time_to_unix_nano(a.mod), time.time_to_unix_nano(b.mod)
			less, equal = ta < tb, ta == tb
		case .Type:
			ea, eb := filepath.ext(la), filepath.ext(lb)
			less, equal = ea < eb, ea == eb
		}
		if equal do return la < lb
		return !less if ctx.desc else less
	})
}

// fb_listing: a folder's entries (read once; fb_refresh reads again).
@(private = "file")
fb_listing :: proc(dir: string) -> ^FB_Listing {
	if l, ok := fb.listings[dir]; ok do return l
	if len(fb.listings) > 256 do fb_forget_listings() // (browsing far and wide)
	l := new(FB_Listing)
	l.entries = make([dynamic]FB_Entry)
	infos, err := os.read_all_directory_by_path(dir, context.temp_allocator)
	if err != nil do l.failed = true
	for fi in infos {
		isDir := fi.type == .Directory
		if fi.type == .Symlink do isDir = os.is_dir(fi.fullpath)
		full, _ := filepath.join({dir, fi.name}, context.temp_allocator)
		append(&l.entries, FB_Entry{
			name  = strings.clone(fi.name),
			full  = strings.clone(full),
			isDir = isDir,
			size  = fi.size if !isDir else 0,
			mod   = fi.modification_time,
			kind  = .Folder if isDir else FileBrowser_KindOf(fi.name),
		})
	}
	fb.listings[strings.clone(dir)] = l
	return l
}

@(private = "file")
fb_listing_free :: proc(l: ^FB_Listing) {
	for en in l.entries {
		delete(en.name)
		delete(en.full)
	}
	delete(l.entries)
	free(l)
}

@(private = "file")
fb_forget_listings :: proc() {
	fb.rows.valid = false
	for k, l in fb.listings {
		delete(k)
		fb_listing_free(l)
	}
	clear(&fb.listings)
}

@(private = "file")
fb_hidden :: proc(name: string) -> bool {return strings.has_prefix(name, ".")}

// fb_subdirs: a folder's sub-folders (sorted; hidden ones when shown).
@(private = "file")
fb_subdirs :: proc(dir: string) -> []FB_Entry {
	out := make([dynamic]FB_Entry, context.temp_allocator)
	for en in fb_listing(dir).entries do if en.isDir && (fb.showHidden || !fb_hidden(en.name)) do append(&out, en)
	FileBrowser_Sort(out[:], .Name, false)
	return out[:]
}

@(private = "file")
fb_set_dir :: proc(dir: string) {
	clean, _ := filepath.clean(dir, context.temp_allocator)
	delete(fb.dir)
	fb.dir = strings.clone(clean)
	fb_set_path_text(fb.dir)
	fb_select_clear()
	delete(fb.revealDir)
	fb.revealDir = strings.clone(fb.dir)
	fb_remember_recent(fb.dir)
	if GlobalSettings.fileBrowserDir != fb.dir {
		delete(GlobalSettings.fileBrowserDir)
		GlobalSettings.fileBrowserDir = strings.clone(fb.dir)
		fb.settingsDirty = true
	}
}

@(private = "file")
fb_set_path_text :: proc(text: string) {
	fb.pathBuf = {}
	copy(fb.pathBuf[:len(fb.pathBuf) - 1], text)
	delete(fb.pathShown)
	fb.pathShown = strings.clone(text)
}

// fb_navigate goes to a folder (history: back / forward). A file's path
// opens its folder with it selected; "~" is the home folder.
@(private = "file")
fb_navigate :: proc(target: string) -> bool {
	path := strings.trim_space(target)
	if strings.has_prefix(path, "~") {
		if home, err := os.user_home_dir(context.temp_allocator); err == nil do path = strings.concatenate({home, path[1:]}, context.temp_allocator)
	}
	if abs, err := os.get_absolute_path(path, context.temp_allocator); err == nil do path = abs
	file := ""
	if !os.is_dir(path) {
		if !os.exists(path) do return false
		file = strings.clone(path, context.temp_allocator)
		path = filepath.dir(path, context.temp_allocator)
	}
	clean, _ := filepath.clean(path, context.temp_allocator)
	if clean != fb.dir {
		if fb.dir != "" do append(&fb.back, strings.clone(fb.dir))
		for f in fb.forward do delete(f)
		clear(&fb.forward)
		fb_set_dir(clean)
	}
	if file != "" do fb_select_only(file)
	return true
}

@(private = "file")
fb_go_back :: proc() {
	if len(fb.back) == 0 do return
	prev := pop(&fb.back)
	append(&fb.forward, strings.clone(fb.dir))
	fb_set_dir(prev)
	delete(prev)
}

@(private = "file")
fb_go_forward :: proc() {
	if len(fb.forward) == 0 do return
	next := pop(&fb.forward)
	append(&fb.back, strings.clone(fb.dir))
	fb_set_dir(next)
	delete(next)
}

@(private = "file")
fb_go_up :: proc() {
	parent := filepath.dir(fb.dir, context.temp_allocator)
	if parent != fb.dir && parent != "" do fb_navigate(parent)
}

// fb_refresh reads the folders again (files changed outside the editor).
@(private = "file")
fb_refresh :: proc() {
	fb_forget_listings()
	fb_search_reset()
}

@(private = "file")
fb_remember_recent :: proc(dir: string) {
	r := &GlobalSettings.fileBrowserRecent
	for p, i in r {
		if p == dir {
			if i == 0 do return
			delete(p)
			ordered_remove(r, i)
			break
		}
	}
	inject_at(r, 0, strings.clone(dir))
	for len(r) > FB_RECENT_MAX do delete(pop(r))
	fb.settingsDirty = true
}

FileBrowser_IsBookmarked :: proc(dir: string) -> bool {return slice.contains(GlobalSettings.fileBrowserBookmarks[:], dir)}

// FileBrowser_ToggleBookmark adds a folder to the bookmarks, or removes it.
FileBrowser_ToggleBookmark :: proc(dir: string) {
	b := &GlobalSettings.fileBrowserBookmarks
	for p, i in b {
		if p == dir {
			delete(p)
			ordered_remove(b, i)
			_ = Editor_SaveSettings()
			return
		}
	}
	append(b, strings.clone(dir))
	_ = Editor_SaveSettings()
}

// --- selection -----------------------------------------------------------------------

@(private = "file")
fb_select_clear :: proc() {
	for s in fb.selection do delete(s)
	clear(&fb.selection)
	delete(fb.anchor)
	fb.anchor = ""
}

@(private = "file")
fb_select_only :: proc(path: string) {
	fb_select_clear()
	append(&fb.selection, strings.clone(path))
	fb.anchor = strings.clone(path)
}

@(private = "file")
fb_is_selected :: proc(path: string) -> bool {return slice.contains(fb.selection[:], path)}

// fb_click: a click on a row (ctrl / cmd toggles, shift selects a range).
@(private = "file")
fb_click :: proc(rows: []FB_Entry, index: int) {
	io := imgui.GetIO()
	path := rows[index].full
	if io.KeyShift && fb.anchor != "" {
		a := -1
		for r, i in rows do if r.full == fb.anchor do a = i
		if a >= 0 {
			for s in fb.selection do delete(s)
			clear(&fb.selection)
			for i in min(a, index) ..= max(a, index) do append(&fb.selection, strings.clone(rows[i].full))
			return
		}
	}
	if io.KeyCtrl || io.KeySuper {
		for s, i in fb.selection {
			if s == path {
				delete(s)
				ordered_remove(&fb.selection, i)
				return
			}
		}
		append(&fb.selection, strings.clone(path))
		delete(fb.anchor)
		fb.anchor = strings.clone(path)
		return
	}
	fb_select_only(path)
}

// --- recursive search ----------------------------------------------------------------

@(private = "file")
fb_search_reset :: proc() {
	fb.rows.valid = false
	s := &fb.search
	delete(s.query)
	delete(s.root)
	s.query, s.root = "", ""
	for d in s.queue do delete(d.path)
	clear(&s.queue)
	for en in s.results {
		delete(en.name)
		delete(en.full)
	}
	clear(&s.results)
	s.scanned = 0
	s.done = false
}

// fb_search_step looks through a few more folders below the current one
// (the search runs over frames: big trees don't stall the editor).
@(private = "file")
fb_search_step :: proc(query: string) {
	s := &fb.search
	if s.query != query || s.root != fb.dir {
		fb_search_reset()
		s.query = strings.clone(query)
		s.root = strings.clone(fb.dir)
		append(&s.queue, FB_Search_Dir{strings.clone(fb.dir), 0})
	}
	lowerQ := strings.to_lower(query, context.temp_allocator)
	for n := 0; n < FB_SEARCH_DIRS_PER_FRAME && len(s.queue) > 0 && len(s.results) < FB_SEARCH_MAX_RESULTS; n += 1 {
		d := pop_front(&s.queue)
		defer delete(d.path)
		s.scanned += 1
		infos, err := os.read_all_directory_by_path(d.path, context.temp_allocator)
		if err != nil do continue
		for fi in infos {
			if !fb.showHidden && fb_hidden(fi.name) do continue
			full, _ := filepath.join({d.path, fi.name}, context.temp_allocator)
			if fi.type == .Directory {
				if d.depth < FB_SEARCH_MAX_DEPTH do append(&s.queue, FB_Search_Dir{strings.clone(full), d.depth + 1})
				continue
			}
			if !strings.contains(strings.to_lower(fi.name, context.temp_allocator), lowerQ) do continue
			rel, _ := filepath.rel(s.root, full, context.temp_allocator)
			append(&s.results, FB_Entry{
				name = strings.clone(rel), full = strings.clone(full),
				size = fi.size, mod = fi.modification_time, kind = FileBrowser_KindOf(fi.name),
			})
			if len(s.results) >= FB_SEARCH_MAX_RESULTS do break
		}
	}
	s.done = len(s.queue) == 0 || len(s.results) >= FB_SEARCH_MAX_RESULTS
}

// --- preview -------------------------------------------------------------------------

@(private = "file")
fb_preview_clear :: proc() {
	p := &fb.preview
	if p.job != nil do p.job = nil // (fb_jobs_poll frees it when it finishes)
	if p.hasTex do rl.UnloadTexture(p.tex)
	if p.hasMusic {
		rl.StopMusicStream(p.music)
		rl.UnloadMusicStream(p.music)
	}
	if p.hasFont {
		rl.UnloadRenderTexture(p.fontTex)
		rl.UnloadFont(p.font)
	}
	delete(p.path)
	delete(p.error)
	delete(p.text)
	delete(p.durations)
	p^ = {}
}

// fb_preview_load shows a file (images decode in the background).
@(private = "file")
fb_preview_load :: proc(path: string) {
	if fb.preview.path == path do return
	fb_preview_clear()
	p := &fb.preview
	p.path = strings.clone(path)
	p.kind = FileBrowser_KindOf(filepath.base(path))
	if fi, err := os.stat(path, context.temp_allocator); err == nil {
		p.size = fi.size
		p.mod = fi.modification_time
		if fi.type == .Directory do p.kind = .Folder
	}
	switch p.kind {
	case .Image, .Aseprite:
		job := new(FB_Image_Job)
		job.path = strings.clone(path)
		job.kind = p.kind
		job.thread = thread.create_and_start_with_poly_data(job, proc(job: ^FB_Image_Job) {
			// Animated (Aseprite frames, a GIF): every frame, with its time.
			if job.kind == .Aseprite || strings.has_suffix(strings.to_lower(job.path, context.temp_allocator), ".gif") {
				job.strip, job.animated = e.Anim_LoadFileStrip(job.path)
			}
			if job.animated {
				job.image = job.strip.image
				job.strip.image = {}
			} else if job.kind == .Aseprite {
				job.image = e.Ase_LoadFileImage(job.path)
			} else {
				job.image = rl.LoadImage(strings.clone_to_cstring(job.path, context.temp_allocator))
			}
			free_all(context.temp_allocator)
			sync.atomic_store(&job.done, true)
		})
		append(&fb.jobs, job)
		p.job = job
	case .Vector:
		img := e.Vector_FileImage(path, 512) // (needs the GL context: here)
		if img.data != nil {
			p.tex = rl.LoadTextureFromImage(img)
			p.hasTex = p.tex.id > 0
			rl.SetTextureFilter(p.tex, .BILINEAR)
			rl.UnloadImage(img)
		} else {
			p.error = strings.clone("Not a readable SVG")
		}
	case .Audio:
		if !rl.IsAudioDeviceReady() do rl.InitAudioDevice()
		m := rl.LoadMusicStream(strings.clone_to_cstring(path, context.temp_allocator))
		if rl.IsMusicValid(m) {
			m.looping = GlobalSettings.previewLoop
			p.music = m
			p.hasMusic = true
			p.length = rl.GetMusicTimeLength(m)
			rl.SetMusicVolume(m, GlobalSettings.previewVolume)
			if GlobalSettings.previewAutoplay do fb_audio_play() // (browsing: hear it straight away)
		} else {
			p.error = strings.clone("Not a readable sound (WAV, OGG, MP3, FLAC, QOA, XM, MOD)")
		}
	case .Font:
		fb_preview_font(path)
	case .Text:
		if data, err := os.read_entire_file(path, context.temp_allocator); err == nil {
			p.truncated = len(data) > FB_TEXT_LIMIT
			p.text = strings.clone(string(data[:min(len(data), FB_TEXT_LIMIT)]))
		} else {
			p.error = strings.clone("Could not read the file")
		}
	case .Video, .Folder, .Other:
	}
}

// fb_preview_font renders a sample of a font into a texture.
@(private = "file")
fb_preview_font :: proc(path: string) {
	p := &fb.preview
	cpath := strings.clone_to_cstring(path, context.temp_allocator)
	f := rl.LoadFont(cpath) if strings.has_suffix(strings.to_lower(path, context.temp_allocator), ".fnt") else rl.LoadFontEx(cpath, 40, nil, 0)
	// (raylib hands back its own font when it can't read one)
	if !rl.IsFontValid(f) || f.glyphCount == 0 || f.texture.id == rl.GetFontDefault().texture.id {
		rl.UnloadFont(f) // (never the default one: raylib checks)
		p.error = strings.clone("Not a readable font")
		return
	}
	lines := []cstring{"AaBbCcDdEeFfGgHhIiJj", "The quick brown fox jumps", "over the lazy dog.", "0123456789 !?&@#%()"}
	sizes := []f32{40, 28, 28, 22}
	w, h: f32 = 0, 8
	for l, i in lines {
		sz := rl.MeasureTextEx(f, l, sizes[i], 1)
		w = max(w, sz.x)
		h += sz.y + 6
	}
	rt := rl.LoadRenderTexture(i32(w) + 16, i32(h) + 8)
	rl.BeginTextureMode(rt)
	rl.ClearBackground({0, 0, 0, 0})
	y: f32 = 8
	for l, i in lines {
		rl.DrawTextEx(f, l, {8, y}, sizes[i], 1, rl.WHITE)
		y += rl.MeasureTextEx(f, l, sizes[i], 1).y + 6
	}
	rl.EndTextureMode()
	p.font = f
	p.fontTex = rt
	p.hasFont = true
}

// fb_jobs_poll uploads finished images (or drops ones nobody wants).
@(private = "file")
fb_jobs_poll :: proc() {
	for i := len(fb.jobs) - 1; i >= 0; i -= 1 {
		job := fb.jobs[i]
		if !sync.atomic_load(&job.done) do continue
		thread.join(job.thread)
		thread.destroy(job.thread)
		unordered_remove(&fb.jobs, i)
		p := &fb.preview
		if p.job == job {
			p.job = nil
			if job.image.data != nil {
				p.tex = rl.LoadTextureFromImage(job.image)
				p.hasTex = p.tex.id > 0
				if !p.hasTex do p.error = strings.clone(fmt.tprintf("Too large to show (%d × %d px)", job.image.width, job.image.height))
				if p.hasTex && job.animated {
					p.animated = true
					p.frameSize = job.strip.frameSize
					p.durations = job.strip.durations
					job.strip.durations = nil
					p.animTime = 0
					p.animPlaying = GlobalSettings.previewAutoplay
				}
			} else {
				p.error = strings.clone("Not a readable image")
			}
		}
		if job.image.data != nil do rl.UnloadImage(job.image)
		e.Anim_StripDestroy(&job.strip)
		delete(job.path)
		free(job)
	}
}

@(private = "file")
fb_audio_play :: proc() {
	p := &fb.preview
	if !p.hasMusic do return
	if p.playing {
		rl.PauseMusicStream(p.music)
		p.playing = false
		return
	}
	if rl.IsMusicStreamPlaying(p.music) || rl.GetMusicTimePlayed(p.music) > 0 {
		rl.ResumeMusicStream(p.music)
	} else {
		rl.PlayMusicStream(p.music)
	}
	p.playing = true
}

@(private = "file")
fb_audio_stop :: proc() {
	p := &fb.preview
	if !p.hasMusic do return
	rl.StopMusicStream(p.music)
	p.playing = false
}

// --- the window ----------------------------------------------------------------------

// FileBrowser_Update: every frame - background jobs, the playing sound
// (stopped when the tab isn't shown), rows dragged out and let go.
FileBrowser_Update :: proc(state: ^EditorState) {
	fb_jobs_poll()
	if fb.preview.hasMusic && fb.preview.playing {
		rl.UpdateMusicStream(fb.preview.music)
		if !rl.IsMusicStreamPlaying(fb.preview.music) {
			rl.StopMusicStream(fb.preview.music) // reached the end: the next Play starts over
			fb.preview.playing = false
		}
	}
	if fb.settingsDirty {
		fb.settingsDirty = false
		_ = Editor_SaveSettings()
	}
	if fb.preview.playing && imgui.GetFrameCount() - fb.shownFrame > 1 do fb_audio_stop() // (a hidden tab doesn't keep playing)
	if p := &fb.preview; p.animated && p.animPlaying {
		p.animTime += rl.GetFrameTime()
		total: f32
		for d in p.durations do total += d
		if !GlobalSettings.previewLoop && p.animTime >= total do p.animPlaying = false
	}
	if p := &fb.preview; p.hasMusic do p.music.looping = GlobalSettings.previewLoop

	// Rows dragged out of the browser and let go elsewhere: dropped like
	// files from the OS file manager (Assets panel: import; viewport: import
	// and place).
	frame := imgui.GetFrameCount()
	if fb.dragFrame == frame - 1 && !imgui.IsMouseDown(.Left) {
		m := imgui.GetMousePos()
		if !point_in_rect({m.x, m.y}, fb.winMin, fb.winMax) && len(fb.selection) > 0 {
			if state.projectPath == "" do Editor_Log(state, .Error, "Open a project before importing assets")
			else do Editor_QueueFileDrop(fb.selection[:], {m.x, m.y})
		}
	}

}

// FileBrowser_RenderTab draws the browser in the bottom panel's Files tab.
FileBrowser_RenderTab :: proc(state: ^EditorState) {
	fb_init()
	fb.shownFrame = imgui.GetFrameCount()
	Drive_Window("filebrowser")
	wp := imgui.GetWindowPos()
	ws := imgui.GetWindowSize()
	fb.winMin, fb.winMax = {wp.x, wp.y}, {wp.x + ws.x, wp.y + ws.y}

	fb_keys()
	fb_toolbar(state)
	imgui.Separator()

	avail := imgui.GetContentRegionAvail()
	if imgui.BeginChild("##fb_side", {220, avail.y}, {.ResizeX}, {}) do fb_sidebar(state)
	imgui.EndChild()
	imgui.SameLine(0, 6)
	listW := max((avail.x - imgui.GetCursorPosX()) * 0.55, 220)
	if imgui.BeginChild("##fb_files", {listW, avail.y}, {.ResizeX}, {}) do fb_files(state)
	imgui.EndChild()
	imgui.SameLine(0, 6)
	if imgui.BeginChild("##fb_preview", {0, avail.y}, {}, {}) do fb_preview_pane(state)
	imgui.EndChild()
}

// fb_keys: Alt+Left / Alt+Right / Alt+Up (or Backspace) while the browser
// has focus and nothing is being typed.
@(private = "file")
fb_keys :: proc() {
	if !imgui.IsWindowFocused({.RootWindow, .ChildWindows}) || imgui.GetIO().WantTextInput do return
	io := imgui.GetIO()
	oneDir := len(fb.selection) == 1 && os.is_dir(fb.selection[0])
	if io.KeyAlt && imgui.IsKeyPressed(.LeftArrow) do fb_go_back()
	else if io.KeyAlt && imgui.IsKeyPressed(.RightArrow) do fb_go_forward()
	else if (io.KeyAlt && imgui.IsKeyPressed(.UpArrow)) || imgui.IsKeyPressed(.Backspace) || imgui.IsKeyPressed(.LeftArrow) do fb_go_up()
	else if (imgui.IsKeyPressed(.Enter) || imgui.IsKeyPressed(.RightArrow)) && oneDir do fb_navigate(strings.clone(fb.selection[0], context.temp_allocator))
	else if imgui.IsKeyPressed(.DownArrow) do fb_step(1)
	else if imgui.IsKeyPressed(.UpArrow) do fb_step(-1)
}

// fb_step: the arrow keys - the next / previous row (Shift: extends the
// selection), scrolled into view; its preview (autoplay) follows (#203).
@(private = "file")
fb_step :: proc(d: int) {
	rows := fb_rows()
	if len(rows) == 0 do return
	cur := -1
	if len(fb.selection) > 0 {
		last := fb.selection[len(fb.selection) - 1]
		for r, i in rows do if r.full == last do cur = i
	}
	next := clamp(cur + d, 0, len(rows) - 1) if cur >= 0 else (0 if d > 0 else len(rows) - 1)
	fb_click(rows, next)
	fb.scrollTo = next
}

@(private = "file")
fb_toolbar :: proc(state: ^EditorState) {
	imgui.BeginDisabled(len(fb.back) == 0)
	if UI_IconButton(ICON_FA_ARROW_LEFT, "fb.back", "Back (Alt+Left)", size = 26) do fb_go_back()
	imgui.EndDisabled()
	imgui.SameLine(0, 2)
	imgui.BeginDisabled(len(fb.forward) == 0)
	if UI_IconButton(ICON_FA_ARROW_RIGHT, "fb.forward", "Forward (Alt+Right)", size = 26) do fb_go_forward()
	imgui.EndDisabled()
	imgui.SameLine(0, 2)
	if UI_IconButton(ICON_FA_ARROW_UP, "fb.up", "Up one folder (Alt+Up, Backspace)", size = 26) do fb_go_up()
	imgui.SameLine(0, 2)
	if UI_IconButton(ICON_FA_ROTATE_RIGHT, "fb.refresh", "Read the folders again", size = 26) do fb_refresh()
	imgui.SameLine(0, 6)

	// The path: edit it and press Enter to go there (a file's path selects it).
	if !fb.pathEditing && (fb.pathShown != fb.dir || string(cstring(raw_data(fb.pathBuf[:]))) != fb.dir) do fb_set_path_text(fb.dir)
	imgui.SetNextItemWidth(max(imgui.GetContentRegionAvail().x - 34 - 176, 120))
	if imgui.InputText("##fb_path", cstring(raw_data(fb.pathBuf[:])), len(fb.pathBuf), {.EnterReturnsTrue, .AutoSelectAll}) {
		typed := strings.clone(string(cstring(raw_data(fb.pathBuf[:]))), context.temp_allocator)
		if !fb_navigate(typed) {
			Editor_Log(state, .Warn, "File Browser: no such folder or file: %s", typed)
			fb_set_path_text(fb.dir)
		}
	}
	fb.pathEditing = imgui.IsItemActive()
	Drive_Item("fb.path")
	imgui.SameLine(0, 4)
	marked := FileBrowser_IsBookmarked(fb.dir)
	if UI_IconButton(ICON_FA_STAR if marked else ICON_FA_BOOKMARK, "fb.bookmark", "Remove the bookmark" if marked else "Bookmark this folder", marked, 26) do FileBrowser_ToggleBookmark(fb.dir)
	imgui.SameLine(0, 8)
	if Preview_Toggles("fb") && fb.preview.hasMusic do rl.SetMusicVolume(fb.preview.music, GlobalSettings.previewVolume)
}

@(private = "file")
fb_sidebar :: proc(state: ^EditorState) {
	if len(GlobalSettings.fileBrowserBookmarks) > 0 && UI_SectionHeader(fmt.tprintf("%s  Bookmarks", ICON_FA_STAR)) {
		remove := ""
		for b in GlobalSettings.fileBrowserBookmarks {
			label := filepath.base(b)
			if imgui.Selectable(fmt.ctprintf("%s  %s##mark_%s", ICON_FA_FOLDER, label, b), b == fb.dir) do fb_navigate(strings.clone(b, context.temp_allocator))
			Drive_Item(fmt.tprintf("fb.mark:%s", label))
			Editor_Tooltip(b)
			if imgui.BeginPopupContextItem(fmt.ctprintf("##markctx_%s", b)) {
				if imgui.MenuItem("Remove Bookmark") do remove = b
				imgui.EndPopup()
			}
		}
		if remove != "" do FileBrowser_ToggleBookmark(strings.clone(remove, context.temp_allocator))
	}
	if len(GlobalSettings.fileBrowserRecent) > 1 && UI_SectionHeader(fmt.tprintf("%s  Recent", ICON_FA_CLOCK), false) {
		for r in GlobalSettings.fileBrowserRecent[1:] {
			if imgui.Selectable(fmt.ctprintf("%s  %s##recent_%s", ICON_FA_FOLDER, filepath.base(r), r)) do fb_navigate(strings.clone(r, context.temp_allocator))
			Editor_Tooltip(r)
		}
	}
	if UI_SectionHeader(fmt.tprintf("%s  Folders", ICON_FA_FOLDER_TREE)) {
		roots := make([dynamic][2]string, context.temp_allocator) // {label, path}
		if state.projectPath != "" do append(&roots, [2]string{"Project", state.projectPath})
		if home, err := os.user_home_dir(context.temp_allocator); err == nil do append(&roots, [2]string{"Home", home})
		when ODIN_OS == .Windows {
			for d in fb.drives do append(&roots, [2]string{d, d})
		} else {
			append(&roots, [2]string{"Computer", "/"})
		}
		revealed := false // (the folder opens in the first root it is in)
		for r in roots {
			reveal := !revealed && fb.revealDir != "" && fb_path_within(fb.revealDir, r[1])
			revealed ||= reveal
			fb_tree(r[1], r[0], 0, reveal)
		}
	}
	if fb.revealDir != "" {
		delete(fb.revealDir) // (opened down to it this frame)
		fb.revealDir = ""
	}
}

// fb_tree draws a folder and, when open, its sub-folders (read only then).
@(private = "file")
fb_tree :: proc(dir, label: string, depth: int, reveal: bool) {
	if depth > 48 do return
	flags: imgui.TreeNodeFlags = {.OpenOnArrow, .OpenOnDoubleClick, .SpanAvailWidth}
	if dir == fb.dir do flags += {.Selected}
	if reveal && dir != fb.revealDir do imgui.SetNextItemOpen(true)
	opened := imgui.TreeNodeEx(fmt.ctprintf("%s  %s##tree_%s", ICON_FA_FOLDER, label, dir), flags)
	Drive_Item(fmt.tprintf("fb.tree:%s", label))
	if imgui.IsItemClicked() && !imgui.IsItemToggledOpen() do fb_navigate(strings.clone(dir, context.temp_allocator))
	if reveal && dir == fb.revealDir do imgui.SetScrollHereY()
	if imgui.BeginPopupContextItem(fmt.ctprintf("##treectx_%s", dir)) {
		if imgui.MenuItem("Remove Bookmark" if FileBrowser_IsBookmarked(dir) else "Bookmark") do FileBrowser_ToggleBookmark(strings.clone(dir, context.temp_allocator))
		if imgui.MenuItem("Copy Path") do imgui.SetClipboardText(fmt.ctprintf("%s", dir))
		imgui.EndPopup()
	}
	if !opened do return
	defer imgui.TreePop()
	for sub in fb_subdirs(dir) do fb_tree(sub.full, sub.name, depth + 1, reveal && fb_path_within(fb.revealDir, sub.full))
}

// fb_path_within: is `path` inside `dir` (or `dir` itself)?
@(private = "file")
fb_path_within :: proc(path, dir: string) -> bool {
	if path == dir do return true
	rel, err := filepath.rel(dir, path, context.temp_allocator)
	return err == nil && rel != ".." && !strings.has_prefix(rel, "..") && !filepath.is_abs(rel)
}

// fb_rows: what the file list shows - the folder's entries, or the
// search's results through its sub-folders - filtered and sorted.
@(private = "file")
fb_rows :: proc() -> []FB_Entry {
	query := strings.trim_space(string(cstring(raw_data(fb.searchBuf[:]))))
	searching := query != "" && fb.recursive
	if searching do fb_search_step(query)
	key := FB_Rows_Key{
		listing = fb_listing(fb.dir), query = fb.searchBuf, recursive = fb.recursive,
		results = len(fb.search.results) if searching else -1,
		filter = fb.filter, sort = fb.sort, descending = fb.descending, showHidden = fb.showHidden,
	}
	if fb.rows.valid && fb.rows.key == key do return fb.rows.entries[:]
	clear(&fb.rows.entries)
	if searching {
		for en in fb.search.results do if FileBrowser_Matches(en, fb.filter, "") do append(&fb.rows.entries, en)
	} else {
		for en in key.listing.entries {
			if !fb.showHidden && fb_hidden(en.name) do continue
			if FileBrowser_Matches(en, fb.filter, query) do append(&fb.rows.entries, en)
		}
	}
	FileBrowser_Sort(fb.rows.entries[:], fb.sort, fb.descending)
	fb.rows.key = key
	fb.rows.valid = true
	return fb.rows.entries[:]
}

@(private = "file")
fb_files :: proc(state: ^EditorState) {
	// Search, filter, sort.
	imgui.SetNextItemWidth(max(imgui.GetContentRegionAvail().x - 300, 100))
	imgui.InputTextWithHint("##fb_search", fmt.ctprintf("%s  Search", ICON_FA_MAGNIFYING_GLASS), cstring(raw_data(fb.searchBuf[:])), len(fb.searchBuf), {})
	Drive_Item("fb.search")
	imgui.SameLine(0, 4)
	imgui.Checkbox("Sub-folders", &fb.recursive)
	Drive_Item("fb.recursive")
	Editor_Tooltip("Search every folder below this one too")
	imgui.SameLine(0, 4)
	imgui.SetNextItemWidth(110)
	if v, changed := UI_Combo("fb_filter", int(fb.filter), FB_FILTER_NAMES); changed do fb.filter = FB_Filter(v)
	Drive_Item("fb.filter")
	imgui.SameLine(0, 4)
	if imgui.Button(fmt.ctprintf("%s##fb_more", ICON_FA_FILTER)) do imgui.OpenPopup("##fb_view")
	Drive_Item("fb.view")
	Editor_Tooltip("Sort, hidden files")
	if imgui.BeginPopup("##fb_view") {
		for name, i in FB_SORT_NAMES {
			if imgui.MenuItem(fmt.ctprintf("Sort by %s", name), nil, int(fb.sort) == i) do fb.sort = FB_Sort(i)
			Drive_Item(fmt.tprintf("fb.sort:%s", name))
		}
		imgui.Separator()
		if imgui.MenuItem("Descending", nil, fb.descending) do fb.descending = !fb.descending
		if imgui.MenuItem("Show Hidden Files", nil, fb.showHidden) do fb.showHidden = !fb.showHidden
		Drive_Item("fb.hidden")
		imgui.EndPopup()
	}

	rows := fb_rows()
	query := strings.trim_space(string(cstring(raw_data(fb.searchBuf[:]))))
	if query != "" && fb.recursive {
		UI_DimText(fmt.tprintf("%d found in %d folders%s", len(rows), fb.search.scanned, "" if fb.search.done else "  (searching…)"))
	} else if fb_listing(fb.dir).failed {
		imgui.TextColored(UI_WARNING, "This folder can't be read")
	}

	tflags := imgui.TableFlags_RowBg | imgui.TableFlags_ScrollY | imgui.TableFlags_SizingStretchProp | imgui.TableFlags_BordersInnerV | imgui.TableFlags_Resizable
	if imgui.BeginTable("##fb_table", 3, tflags, imgui.GetContentRegionAvail()) {
		imgui.TableSetupColumn("Name", {.WidthStretch}, 4)
		imgui.TableSetupColumn("Size", {.WidthStretch}, 1)
		imgui.TableSetupColumn("Modified", {.WidthStretch}, 1.6)
		imgui.TableSetupScrollFreeze(0, 1)
		imgui.TableHeadersRow()
		enter := ""
		clipper: imgui.ListClipper
		imgui.ListClipper_Begin(&clipper, i32(len(rows)))
		if fb.scrollTo >= 0 && fb.scrollTo < len(rows) do imgui.ListClipper_IncludeItemByIndex(&clipper, i32(fb.scrollTo)) // (the arrow keys' row)
		// (Drives: rows the clipper skips get estimated rects, from a drawn
		// one, so a click scrolls to them like to any other item.)
		shown := make([]bool, len(rows), context.temp_allocator)
		known, knownMin, knownMax := -1, [2]f32{}, [2]f32{}
		for imgui.ListClipper_Step(&clipper) do for i in int(clipper.DisplayStart) ..< int(clipper.DisplayEnd) {
			en := rows[i]
			shown[i] = true
			imgui.TableNextRow()
			imgui.TableNextColumn()
			icon, tint := fb_icon(en)
			imgui.PushStyleColorImVec4(.Text, tint)
			imgui.TextUnformatted(strings.clone_to_cstring(icon, context.temp_allocator))
			imgui.PopStyleColor()
			imgui.SameLine(0, 6)
			sel := fb_is_selected(en.full)
			if imgui.Selectable(fmt.ctprintf("%s##row_%s", en.name, en.full), sel, {.SpanAllColumns, .AllowDoubleClick}) {
				if imgui.IsMouseDoubleClicked(.Left) {
					if en.isDir do enter = en.full
					else if en.kind == .Audio do fb_audio_play()
				} else {
					fb_click(rows, i)
				}
			}
			Drive_Item(fmt.tprintf("fb.row:%s", en.name))
			if i == fb.scrollTo {
				if !imgui.IsItemVisible() do imgui.SetScrollHereY(0.5)
				fb.scrollTo = -1
			}
			if known < 0 do known, knownMin, knownMax = i, imgui.GetItemRectMin(), imgui.GetItemRectMax()
			if imgui.BeginPopupContextItem(fmt.ctprintf("##rowctx_%s", en.full)) {
				if !fb_is_selected(en.full) do fb_select_only(en.full)
				fb_row_menu(state, en)
				imgui.EndPopup()
			}
			if imgui.BeginDragDropSource({}) {
				if !fb_is_selected(en.full) do fb_select_only(en.full)
				imgui.SetDragDropPayload("FILE_BROWSER", nil, 0)
				n := len(fb.selection)
				imgui.TextUnformatted(fmt.ctprintf("%s  %s", ICON_FA_FILE_IMPORT, filepath.base(fb.selection[0]) if n == 1 else fmt.tprintf("%d files", n)))
				UI_DimText("Drop on the Assets panel or the viewport to import")
				imgui.EndDragDropSource()
				fb.dragFrame = imgui.GetFrameCount()
			}
			imgui.TableNextColumn()
			if !en.isDir do UI_DimText(fb_size_text(en.size))
			imgui.TableNextColumn()
			UI_DimText(fb_time_text(en.mod))
		}
		if GlobalDrive.enabled && known >= 0 && clipper.ItemsHeight > 0 {
			h := clipper.ItemsHeight
			for en, i in rows {
				if shown[i] do continue
				dy := f32(i - known) * h
				Drive_ItemRect(fmt.tprintf("fb.row:%s", en.name), knownMin + {0, dy}, knownMax + {0, dy}, inWindow = true)
			}
		}
		imgui.EndTable()
		if enter != "" do fb_navigate(enter)
	}
	// The preview follows the selection (the last one clicked).
	if len(fb.selection) > 0 do fb_preview_load(fb.selection[len(fb.selection) - 1])
	else if fb.preview.path != "" do fb_preview_clear()
}

@(private = "file")
fb_row_menu :: proc(state: ^EditorState, en: FB_Entry) {
	hasProject := state.projectPath != ""
	n := len(fb.selection)
	what := filepath.base(en.full) if n <= 1 else fmt.tprintf("%d items", n)
	if imgui.MenuItem(fmt.ctprintf("%s  Load into Project (%s)", ICON_FA_FILE_IMPORT, what), nil, false, hasProject) do fb_load(state, "")
	Drive_Item("ctx:fb-load")
	if imgui.BeginMenu("Load into Folder", hasProject) {
		for f in fb_project_folders(state) {
			if imgui.MenuItem(fmt.ctprintf("%s  %s", ICON_FA_FOLDER, f)) do fb_load(state, f)
			Drive_Item(fmt.tprintf("ctx:fb-load-to:%s", f))
		}
		imgui.EndMenu()
	}
	imgui.Separator()
	if en.isDir {
		if imgui.MenuItem("Open") do fb_navigate(strings.clone(en.full, context.temp_allocator))
		if imgui.MenuItem("Remove Bookmark" if FileBrowser_IsBookmarked(en.full) else "Bookmark") do FileBrowser_ToggleBookmark(strings.clone(en.full, context.temp_allocator))
	} else if fb.search.root != "" && filepath.dir(en.full, context.temp_allocator) != fb.dir {
		if imgui.MenuItem("Show in Folder") do fb_navigate(strings.clone(en.full, context.temp_allocator))
	}
	if imgui.MenuItem("Copy Path") do imgui.SetClipboardText(fmt.ctprintf("%s", en.full))
}

// fb_project_folders: the project's folders (where Load can put files).
@(private = "file")
fb_project_folders :: proc(state: ^EditorState) -> []string {
	out := make([dynamic]string, context.temp_allocator)
	walk :: proc(root, rel: string, out: ^[dynamic]string, depth: int) {
		if depth > 6 || len(out) > 400 do return
		dir, _ := filepath.join({root, rel}, context.temp_allocator)
		infos, err := os.read_all_directory_by_path(dir, context.temp_allocator)
		if err != nil do return
		slice.sort_by(infos, proc(a, b: os.File_Info) -> bool {return a.name < b.name})
		for fi in infos {
			if fi.type != .Directory || fb_hidden(fi.name) do continue
			sub, _ := filepath.join({rel, fi.name}, context.temp_allocator)
			sub, _ = strings.replace_all(sub, "\\", "/", context.temp_allocator)
			append(out, sub)
			walk(root, sub, out, depth + 1)
		}
	}
	if state.projectPath != "" do walk(state.projectPath, "", &out, 0)
	return out[:]
}

// fb_load imports the selection (files and folders) into the project:
// `dest` = a project folder, or "" for the Load bar's choice.
@(private = "file")
fb_load :: proc(state: ^EditorState, dest: string) {
	if state.projectPath == "" || len(fb.selection) == 0 do return
	paths := make([dynamic]string, context.temp_allocator)
	for s in fb.selection do append(&paths, strings.clone(s, context.temp_allocator))
	Asset_ImportFiles(state, paths[:], {dest = dest if dest != "" else fb.dest, conflict = fb.conflict})
}

@(private = "file")
fb_icon :: proc(en: FB_Entry) -> (string, imgui.Vec4) {
	switch en.kind {
	case .Folder: return ICON_FA_FOLDER, {0.95, 0.78, 0.38, 1}
	case .Image: return kind_icon(.Texture)
	case .Audio: return kind_icon(.Audio)
	case .Video: return ICON_FA_FILM, {0.85, 0.55, 0.95, 1}
	case .Font: return ICON_FA_FONT, UI_TEXT
	case .Aseprite: return kind_icon(.Aseprite)
	case .Vector: return kind_icon(.Vector)
	case .Text:
		if k := Asset_KindOf(en.name); k != .Other do return kind_icon(k)
		return ICON_FA_FILE_CODE, UI_TEXT_DIM
	case .Other:
	}
	return ICON_FA_FILE, UI_TEXT_DIM
}

FileBrowser_SizeText :: proc(size: i64) -> string {return fb_size_text(size)}

@(private = "file")
fb_size_text :: proc(size: i64) -> string {
	switch {
	case size < 1024: return fmt.tprintf("%d B", size)
	case size < 1024 * 1024: return fmt.tprintf("%.1f KB", f64(size) / 1024)
	case size < 1024 * 1024 * 1024: return fmt.tprintf("%.1f MB", f64(size) / (1024 * 1024))
	}
	return fmt.tprintf("%.2f GB", f64(size) / (1024 * 1024 * 1024))
}

@(private = "file")
fb_time_text :: proc(t: time.Time) -> string {
	if time.time_to_unix(t) <= 0 do return ""
	y, mo, d := time.date(t)
	h, mi, _ := time.clock(t)
	return fmt.tprintf("%04d-%02d-%02d %02d:%02d", y, int(mo), d, h, mi)
}

@(private = "file")
fb_duration_text :: proc(seconds: f32) -> string {
	s := int(max(seconds, 0))
	return fmt.tprintf("%d:%02d", s / 60, s % 60)
}

@(private = "file")
fb_preview_pane :: proc(state: ^EditorState) {
	p := &fb.preview
	loadH: f32 = 74
	if imgui.BeginChild("##fb_preview_body", {0, max(imgui.GetContentRegionAvail().y - loadH, 60)}, {}, {}) {
		if p.path == "" {
			UI_DimTextWrapped("Select a file to preview it. Load brings the selected files and folders into the project.")
		} else {
			fb_preview_body(p)
		}
	}
	imgui.EndChild()
	imgui.Separator()
	fb_load_bar(state)
}

@(private = "file")
fb_preview_body :: proc(p: ^FB_Preview) {
	icon, tint := fb_icon({name = filepath.base(p.path), kind = p.kind, isDir = p.kind == .Folder})
	imgui.PushStyleColorImVec4(.Text, tint)
	imgui.TextUnformatted(strings.clone_to_cstring(icon, context.temp_allocator))
	imgui.PopStyleColor()
	imgui.SameLine(0, 6)
	imgui.PushFont(GlobalFonts.semibold)
	imgui.TextUnformatted(strings.clone_to_cstring(filepath.base(p.path), context.temp_allocator))
	imgui.PopFont()
	details := make([dynamic]string, context.temp_allocator)
	if p.kind != .Folder do append(&details, fb_size_text(p.size))
	if p.hasTex && p.animated do append(&details, fmt.tprintf("%d × %d px, %d frames", p.frameSize.x, p.frameSize.y, len(p.durations)))
	else if p.hasTex do append(&details, fmt.tprintf("%d × %d px", p.tex.width, p.tex.height))
	if p.hasMusic {
		append(&details, fb_duration_text(p.length))
		append(&details, fmt.tprintf("%d Hz, %s", p.music.stream.sampleRate, "stereo" if p.music.stream.channels == 2 else fmt.tprintf("%d ch", p.music.stream.channels)))
	}
	if p.hasFont do append(&details, fmt.tprintf("%d glyphs", p.font.glyphCount))
	if t := fb_time_text(p.mod); t != "" do append(&details, t)
	UI_DimText(strings.join(details[:], "  ·  ", context.temp_allocator))
	imgui.Spacing()

	if p.error != "" {
		imgui.TextColored(UI_WARNING, fmt.ctprintf("%s  %s", ICON_FA_TRIANGLE_EXCLAMATION, p.error))
		return
	}
	switch p.kind {
	case .Image, .Aseprite, .Vector:
		if p.job != nil {
			UI_DimText("Loading…")
		} else if p.hasTex {
			if p.animated {
				// An animation: play / pause, the frame.
				if UI_IconButton(ICON_FA_PAUSE if p.animPlaying else ICON_FA_PLAY, "fb.anim-play", "Pause" if p.animPlaying else "Play", p.animPlaying, 24) {
					total: f32
					for d in p.durations do total += d
					if !p.animPlaying && p.animTime >= total do p.animTime = 0 // (ended: from the start)
					p.animPlaying = !p.animPlaying
				}
				imgui.SameLine(0, 6)
				imgui.AlignTextToFramePadding()
				UI_DimText(fmt.tprintf("frame %d / %d", e.Anim_StripFrameAt(p.durations, p.animTime, GlobalSettings.previewLoop) + 1, len(p.durations)))
				Drive_Item("fb.anim-frame")
			}
			fb_image_view(p)
		}
	case .Audio:
		fb_audio_view(p)
	case .Font:
		if p.hasFont {
			w, h := f32(p.fontTex.texture.width), f32(p.fontTex.texture.height)
			scale := min(imgui.GetContentRegionAvail().x / max(w, 1), 1)
			imgui.Image(transmute(imgui.TextureID)&p.fontTex.texture, {w * scale, h * scale}, {0, 1}, {1, 0}) // (render textures are upside down)
		}
	case .Text:
		if GlobalFonts.mono != nil do imgui.PushFont(GlobalFonts.mono)
		if imgui.BeginChild("##fb_text", {0, 0}, {.Borders}, {.HorizontalScrollbar}) {
			imgui.TextUnformatted(strings.clone_to_cstring(p.text, context.temp_allocator))
			if p.truncated do UI_DimText(fmt.tprintf("… (the first %d KB)", FB_TEXT_LIMIT / 1024))
		}
		imgui.EndChild()
		if GlobalFonts.mono != nil do imgui.PopFont()
	case .Video:
		UI_DimTextWrapped("Video files can't be played in the editor yet (the engine has no video decoder); their details are above. To load one, pick a project folder under To: (it is copied as it is).")
	case .Folder:
		UI_DimTextWrapped("A folder: Load brings it and everything in it into the project (keeping its layout).")
	case .Other:
		UI_DimTextWrapped("No preview for this kind of file. Files the importer doesn't know are loaded into the folder picked under To:.")
	}
}

// fb_image_view: the image, fitted (zoom with the wheel or the buttons,
// drag to pan) over a checkerboard for transparency.
@(private = "file")
fb_image_view :: proc(p: ^FB_Preview) {
	if UI_IconButton(ICON_FA_EXPAND, "fb.fit", "Fit", p.zoom == 0, 24) {p.zoom = 0; p.pan = {}}
	imgui.SameLine(0, 2)
	if imgui.Button("1:1##fb_actual") {p.zoom = 1; p.pan = {}}
	Drive_Item("fb.actual")
	imgui.SameLine(0, 8)
	avail := imgui.GetContentRegionAvail()
	w, h := f32(p.tex.width), f32(p.tex.height)
	// An animation: its current frame (a band of the strip).
	uv0, uv1 := imgui.Vec2{0, 0}, imgui.Vec2{1, 1}
	if p.animated && p.frameSize.y > 0 {
		i := e.Anim_StripFrameAt(p.durations, p.animTime, GlobalSettings.previewLoop)
		h = f32(p.frameSize.y)
		uv0 = {0, f32(i) * h / f32(p.tex.height)}
		uv1 = {1, f32(i + 1) * h / f32(p.tex.height)}
	}
	fit := min(avail.x / max(w, 1), (avail.y - 4) / max(h, 1))
	zoom := p.zoom if p.zoom > 0 else fit
	UI_DimText(fmt.tprintf("%.0f%%", zoom * 100))
	if !imgui.BeginChild("##fb_image", {0, 0}, {}, {.NoScrollbar, .NoScrollWithMouse}) {
		imgui.EndChild()
		return
	}
	defer imgui.EndChild()
	area := imgui.GetContentRegionAvail()
	origin := imgui.GetCursorScreenPos()
	imgui.InvisibleButton("##fb_image_area", {max(area.x, 1), max(area.y, 1)})
	if imgui.IsItemHovered() {
		wheel := imgui.GetIO().MouseWheel
		if wheel != 0 do p.zoom = clamp(zoom * (1.15 if wheel > 0 else 1 / 1.15), 0.05, 32)
	}
	if imgui.IsItemActive() && imgui.IsMouseDragging(.Left) {
		d := imgui.GetIO().MouseDelta
		p.pan += {d.x, d.y}
	}
	dw, dh := w * zoom, h * zoom
	pos := imgui.Vec2{origin.x + (area.x - dw) * 0.5 + p.pan.x, origin.y + (area.y - dh) * 0.5 + p.pan.y}
	dl := imgui.GetWindowDrawList()
	imgui.DrawList_PushClipRect(dl, origin, {origin.x + area.x, origin.y + area.y}, true)
	// Checkerboard under the image's rect.
	cell: f32 = 10
	a, b := col_u32({0.30, 0.30, 0.33, 1}), col_u32({0.22, 0.22, 0.25, 1})
	x0, y0 := max(pos.x, origin.x), max(pos.y, origin.y)
	x1, y1 := min(pos.x + dw, origin.x + area.x), min(pos.y + dh, origin.y + area.y)
	for y := y0; y < y1; y += cell {
		for x := x0; x < x1; x += cell {
			c := a if (int((x - x0) / cell) + int((y - y0) / cell)) % 2 == 0 else b
			imgui.DrawList_AddRectFilled(dl, {x, y}, {min(x + cell, x1), min(y + cell, y1)}, c)
		}
	}
	imgui.DrawList_AddImage(dl, transmute(imgui.TextureID)&p.tex, pos, {pos.x + dw, pos.y + dh}, uv0, uv1)
	imgui.DrawList_PopClipRect(dl)
}

@(private = "file")
fb_audio_view :: proc(p: ^FB_Preview) {
	if !p.hasMusic do return
	if UI_IconButton(ICON_FA_PAUSE if p.playing else ICON_FA_PLAY, "fb.play", "Pause" if p.playing else "Play", p.playing, 30) do fb_audio_play()
	imgui.SameLine(0, 2)
	if UI_IconButton(ICON_FA_STOP, "fb.stop", "Stop", false, 30) do fb_audio_stop()
	imgui.SameLine(0, 8)
	played := rl.GetMusicTimePlayed(p.music)
	t := played
	imgui.SetNextItemWidth(max(imgui.GetContentRegionAvail().x - 70, 80))
	if imgui.SliderFloat("##fb_seek", &t, 0, max(p.length, 0.01), strings.clone_to_cstring(fb_duration_text(played), context.temp_allocator)) {
		if !p.playing && !rl.IsMusicStreamPlaying(p.music) {
			rl.PlayMusicStream(p.music)
			rl.PauseMusicStream(p.music)
		}
		rl.SeekMusicStream(p.music, clamp(t, 0, max(p.length - 0.01, 0)))
	}
	Drive_Item("fb.seek")
	imgui.SameLine(0, 4)
	UI_DimText(fb_duration_text(p.length))
}

@(private = "file")
fb_load_bar :: proc(state: ^EditorState) {
	hasProject := state.projectPath != ""
	n := len(fb.selection)
	imgui.AlignTextToFramePadding()
	UI_DimText("To")
	imgui.SameLine(0, 6)
	imgui.SetNextItemWidth(max(imgui.GetContentRegionAvail().x * 0.5, 120))
	destLabel := fb.dest if fb.dest != "" else "Folder for its type (textures/, audio/…)"
	if imgui.BeginCombo("##fb_dest", strings.clone_to_cstring(destLabel, context.temp_allocator)) {
		if imgui.Selectable("Folder for its type (textures/, audio/…)", fb.dest == "") {
			delete(fb.dest)
			fb.dest = ""
		}
		Drive_Item("pick:by-type")
		for f in fb_project_folders(state) {
			if imgui.Selectable(fmt.ctprintf("%s  %s", ICON_FA_FOLDER, f), fb.dest == f) {
				delete(fb.dest)
				fb.dest = strings.clone(f)
			}
			Drive_Item(fmt.tprintf("pick:%s", f))
		}
		imgui.EndCombo()
	}
	Drive_Item("fb.dest")
	Editor_Tooltip("Where Load puts the files: the folder for each file's type, or one project folder (any file type)")
	imgui.SameLine(0, 6)
	imgui.SetNextItemWidth(-1)
	names := []string{"Name taken: import beside it", "Name taken: replace it", "Name taken: skip it"}
	if v, changed := UI_Combo("fb_conflict", int(fb.conflict), names); changed do fb.conflict = Import_Conflict(v)
	Drive_Item("fb.conflict")
	Editor_Tooltip("When a different file already has the name (the same file is never copied twice)")

	imgui.BeginDisabled(!hasProject || n == 0)
	label := "Load into Project" if n <= 1 else fmt.tprintf("Load %d Items into Project", n)
	if imgui.Button(fmt.ctprintf("%s  %s", ICON_FA_FILE_IMPORT, label), {-1, 0}) do fb_load(state, "")
	imgui.EndDisabled()
	Drive_Item("fb.load")
	if !hasProject do Editor_Tooltip("Open a project first")
}

// FileBrowser_Shutdown releases the preview and waits for decoding images.
FileBrowser_Shutdown :: proc() {
	fb_preview_clear()
	for job in fb.jobs {
		thread.join(job.thread)
		thread.destroy(job.thread)
		if job.image.data != nil do rl.UnloadImage(job.image)
		e.Anim_StripDestroy(&job.strip)
		delete(job.path)
		free(job)
	}
	delete(fb.jobs)
	fb_search_reset()
	delete(fb.search.queue)
	delete(fb.search.results)
	fb_forget_listings()
	delete(fb.listings)
	delete(fb.rows.entries)
	fb_select_clear()
	delete(fb.selection)
	for b in fb.back do delete(b)
	delete(fb.back)
	for f in fb.forward do delete(f)
	delete(fb.forward)
	delete(fb.dir)
	delete(fb.pathShown)
	delete(fb.revealDir)
	delete(fb.dest)
	for d in fb.drives do delete(d)
	delete(fb.drives)
	if fb.settingsDirty do _ = Editor_SaveSettings()
	fb = {}
}

// FileBrowser_DriveQuery answers test-drive queries ("fb.*").
FileBrowser_DriveQuery :: proc(q: string) -> (string, bool) {
	switch q {
	case "fb.open": return "true" if FileBrowser_IsOpen() else "false", true
	case "fb.dir": return fb.dir, true
	case "fb.dir-name": return filepath.base(fb.dir), true
	case "fb.back": return fmt.tprint(len(fb.back)), true
	case "fb.forward": return fmt.tprint(len(fb.forward)), true
	case "fb.selected":
		names := make([dynamic]string, context.temp_allocator)
		for s in fb.selection do append(&names, filepath.base(s))
		return strings.join(names[:], ",", context.temp_allocator), true
	case "fb.rows":
		names := make([dynamic]string, context.temp_allocator)
		for en in fb_rows() do append(&names, en.name)
		return strings.join(names[:], ",", context.temp_allocator), true
	case "fb.search-done": return "true" if fb.search.done else "false", true
	case "fb.preview": return FB_KIND_NAMES[fb.preview.kind] if fb.preview.path != "" else "", true
	case "fb.preview-name": return filepath.base(fb.preview.path), true
	case "fb.anim":
		// An animation's preview: playing / paused, its frame count (#203).
		if !fb.preview.animated do return "none", true
		return fmt.tprintf("%s %d", "playing" if fb.preview.animPlaying else "paused", len(fb.preview.durations)), true
	case "fb.preview-error": return fb.preview.error, true
	case "fb.image-size": return fmt.tprintf("%dx%d", fb.preview.tex.width, fb.preview.tex.height) if fb.preview.hasTex else "", true
	case "fb.audio":
		if !fb.preview.hasMusic do return "none", true
		return "playing" if fb.preview.playing else "stopped", true
	case "fb.audio-length": return fmt.tprintf("%.1f", fb.preview.length), true
	case "fb.text": return fb.preview.text, true
	case "fb.bookmarks":
		names := make([dynamic]string, context.temp_allocator)
		for b in GlobalSettings.fileBrowserBookmarks do append(&names, filepath.base(b))
		return strings.join(names[:], ",", context.temp_allocator), true
	case "fb.recent": return fmt.tprint(len(GlobalSettings.fileBrowserRecent)), true
	case "fb.dest": return fb.dest, true
	case "fb.conflict": return fmt.tprint(fb.conflict), true
	}
	return "", false
}
