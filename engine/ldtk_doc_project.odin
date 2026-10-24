package engine

import "core:fmt"
import os "osx"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:time"

// ============================================================================
// Ldtk_Doc project options (LDtk's EditProject / ProjectSaver): external
// level files (on / off, file names), identifier styles applied everywhere,
// project flags and their side effects, backups on save.
// ============================================================================

// ----------------------------------------------------------------------------
// External level files
// ----------------------------------------------------------------------------

// Ldtk_Doc_LevelFileRel: Level.makeExternalRelPath - "<project name>/[0000-]
// <identifier>.ldtkl" (the index with the PrependIndexToLevelFileNames
// flag; levels are counted across worlds).
Ldtk_Doc_LevelFileRel :: proc(doc: ^Ldtk_Doc, li: int, allocator := context.temp_allocator) -> string {
	stem := strings.trim_suffix(filepath.base(doc.path), filepath.ext(doc.path))
	id := LdtkJson_Str(doc.levels[li].obj, "identifier")
	if Ldtk_Doc_HasFlag(doc, "PrependIndexToLevelFileNames") do return fmt.aprintf("%s/%04d-%s.ldtkl", stem, li, id, allocator = allocator)
	return fmt.aprintf("%s/%s.ldtkl", stem, id, allocator = allocator)
}

// Ldtk_Doc_FixLevelFiles gives every external level its expected file name
// (the old files are removed on save, like LDtk's saver).
Ldtk_Doc_FixLevelFiles :: proc(doc: ^Ldtk_Doc) {
	a := doc.allocator
	for &lv, li in doc.levels {
		if lv.extRoot == nil do continue
		want := Ldtk_Doc_LevelFileRel(doc, li)
		old := LdtkJson_Str(lv.obj, "externalRelPath")
		if old == want do continue
		if old != "" do append(&doc.removedFiles, strings.clone(old, doc.heap))
		LdtkJson_SetStr(lv.obj, "externalRelPath", want, a)
		lv.dirty = true
	}
}

// Ldtk_Doc_SetExternalLevels: the externalLevels option - levels move to
// their own .ldtkl files (the project keeps their headers) or back into the
// project file (the .ldtkl files are removed on save).
Ldtk_Doc_SetExternalLevels :: proc(doc: ^Ldtk_Doc, on: bool) {
	a := doc.allocator
	if on == doc.external do return
	LdtkJson_SetBool(doc.root, "externalLevels", on, a)
	doc.external = on
	for &lv, li in doc.levels {
		if on {
			if lv.extRoot != nil do continue
			// the layer instances move (the typed cells keep pointing at them)
			layers := LdtkJson_Get(lv.obj, "layerInstances")
			LdtkJson_SetNull(lv.obj, "layerInstances", a)
			ext := LdtkJson_Clone(lv.obj, a)
			LdtkJson_Set(ext, "layerInstances", layers != nil ? layers : LdtkJson_New(.Array, a), a)
			if hdr := LdtkJson_Get(doc.root, LDTK_JSON_HEADER_KEY); hdr != nil {
				inject_at(&ext.keys, 0, strings.clone(LDTK_JSON_HEADER_KEY, a))
				inject_at(&ext.items, 0, LdtkJson_Clone(hdr, a))
			}
			LdtkJson_SetNull(ext, "externalRelPath", a)
			LdtkJson_SetStr(lv.obj, "externalRelPath", Ldtk_Doc_LevelFileRel(doc, li), a)
			lv.extRoot, lv.data = ext, ext
		} else {
			if lv.extRoot == nil do continue
			if rel := LdtkJson_Str(lv.obj, "externalRelPath"); rel != "" do append(&doc.removedFiles, strings.clone(rel, doc.heap))
			layers := LdtkJson_Get(lv.extRoot, "layerInstances")
			LdtkJson_Set(lv.obj, "layerInstances", layers != nil ? layers : LdtkJson_New(.Array, a), a)
			LdtkJson_SetNull(lv.obj, "externalRelPath", a)
			// field values live in the project file again
			if f := LdtkJson_Get(lv.extRoot, "fieldInstances"); f != nil do LdtkJson_Set(lv.obj, "fieldInstances", f, a)
			lv.extRoot, lv.data = nil, lv.obj
		}
		lv.dirty = true
	}
	Ldtk_Doc_Touch(doc)
}

// ----------------------------------------------------------------------------
// Identifier style
// ----------------------------------------------------------------------------

// Ldtk_Doc_SetIdentifierStyle: Project.applyIdentifierStyleEverywhere -
// enums (internal) and their values, layers, entities, tilesets, worlds and
// levels get the new style.
Ldtk_Doc_SetIdentifierStyle :: proc(doc: ^Ldtk_Doc, style: Ldtk_IdentifierStyle) {
	a := doc.allocator
	if style == Ldtk_Doc_IdentifierStyle(doc) do return
	LdtkJson_SetStr(doc.root, "identifierStyle", LDTK_IDENTIFIER_STYLES[style], a)
	defs := LdtkJson_Get(doc.root, "defs")
	for en in LdtkJson_Arr(defs, "enums") {
		uid := LdtkJson_Int(en, "uid")
		Ldtk_Doc_RenameEnum(doc, uid, LdtkJson_Str(en, "identifier"))
		ids := make([dynamic]string, context.temp_allocator)
		for v in LdtkJson_Arr(en, "values") do append(&ids, LdtkJson_Str(v, "id"))
		for id in ids do Ldtk_Doc_RenameEnumValue(doc, uid, id, id)
	}
	for d in LdtkJson_Arr(defs, "layers") {
		uid := LdtkJson_Int(d, "uid")
		Ldtk_Doc_RenameLayerDef(doc, uid, LdtkJson_Str(d, "identifier"))
	}
	for ed in LdtkJson_Arr(defs, "entities") {
		LdtkJson_SetStr(ed, "identifier", Ldtk_Doc_CleanIdentifier(doc, LdtkJson_Str(ed, "identifier")), a)
		Ldtk_Doc_EntityDefChanged(doc, LdtkJson_Int(ed, "uid"))
	}
	for ts in LdtkJson_Arr(defs, "tilesets") do LdtkJson_SetStr(ts, "identifier", Ldtk_Doc_CleanIdentifier(doc, LdtkJson_Str(ts, "identifier")), a)
	if doc.multiWorlds do for w in doc.worlds do LdtkJson_SetStr(w.obj, "identifier", Ldtk_Doc_CleanIdentifier(doc, LdtkJson_Str(w.obj, "identifier")), a)
	for &lv, li in doc.levels {
		name := Ldtk_Doc_CleanIdentifier(doc, LdtkJson_Str(lv.obj, "identifier"))
		auto := LdtkJson_Bool(lv.obj, "useAutoIdentifier", true)
		if name != LdtkJson_Str(lv.obj, "identifier") && Ldtk_Doc_RenameLevel(doc, li, name) {
			LdtkJson_SetBool(lv.obj, "useAutoIdentifier", auto, a)
			if lv.extRoot != nil do LdtkJson_SetBool(lv.extRoot, "useAutoIdentifier", auto, a)
		}
	}
	Ldtk_Doc_RefreshDefs(doc)
	Ldtk_Doc_UpdateToc(doc)
	for &lv in doc.levels do lv.dirty = true
	Ldtk_Doc_Touch(doc)
}

// ----------------------------------------------------------------------------
// Flags
// ----------------------------------------------------------------------------

// LDtk's advanced project flags (EditProject) and what they do.
LDTK_PROJECT_FLAGS := [?]struct {
	name, label, desc: string,
} {
	{"MultiWorlds", "Multi-worlds", "Several worlds in one project (the World tab)."},
	{"PrependIndexToLevelFileNames", "Prefix level file names with their index", "External level files are named 0000-Level_0.ldtkl, ... so they sort in level order."},
	{"ExportPreCsvIntGridFormat", "Export the old IntGrid format", "Also writes each IntGrid layer as \"intGrid\": [{coordId, v}] (LDtk before 0.8), for old importers."},
	{"UseMultilinesType", "Use the \"Multilines\" type name", "Multi-line text fields are typed \"Multilines\" instead of \"String\" in the file."},
	{"ExportOldTableOfContentData", "Export the old table of contents", "The table of contents also lists entity instances' data in the old format."},
}

// Ldtk_Doc_SetProjectFlag turns a flag on / off with its side effects.
Ldtk_Doc_SetProjectFlag :: proc(doc: ^Ldtk_Doc, flag: string, on: bool) -> bool {
	a := doc.allocator
	switch flag {
	case "MultiWorlds": return Ldtk_Doc_SetMultiWorlds(doc, on)
	case "UseMultilinesType":
		Ldtk_Doc_SetFlag(doc, flag, on)
		label := on ? "Multilines" : "String"
		defs := LdtkJson_Get(doc.root, "defs")
		fix :: proc(doc: ^Ldtk_Doc, fd: ^LdtkJson, label: string) {
			if LdtkJson_Str(fd, "type") != "F_Text" do return
			t := LdtkJson_Bool(fd, "isArray") ? fmt.tprintf("Array<%s>", label) : label
			LdtkJson_SetStr(fd, "__type", t, doc.allocator)
			uid := LdtkJson_Int(fd, "uid")
			for &lv in doc.levels {
				for fi in LdtkJson_Arr(lv.obj, "fieldInstances") do if LdtkJson_Int(fi, "defUid", -1) == uid do LdtkJson_SetStr(fi, "__type", t, doc.allocator)
				if lv.extRoot != nil do for fi in LdtkJson_Arr(lv.extRoot, "fieldInstances") do if LdtkJson_Int(fi, "defUid", -1) == uid do LdtkJson_SetStr(fi, "__type", t, doc.allocator)
				for &ly in lv.layers do for ent in LdtkJson_Arr(ly.obj, "entityInstances") {
					for fi in LdtkJson_Arr(ent, "fieldInstances") do if LdtkJson_Int(fi, "defUid", -1) == uid do LdtkJson_SetStr(fi, "__type", t, doc.allocator)
				}
				lv.dirty = true
			}
		}
		for fd in LdtkJson_Arr(defs, "levelFields") do fix(doc, fd, label)
		for ed in LdtkJson_Arr(defs, "entities") do for fd in LdtkJson_Arr(ed, "fieldDefs") do fix(doc, fd, label)
	case "ExportPreCsvIntGridFormat":
		Ldtk_Doc_SetFlag(doc, flag, on)
		for &lv in doc.levels {
			for &ly in lv.layers {
				if on do ly.cellsDirty = true
				else do LdtkJson_Remove(ly.obj, "intGrid")
			}
			lv.dirty = true
		}
	case "ExportOldTableOfContentData":
		Ldtk_Doc_SetFlag(doc, flag, on)
		Ldtk_Doc_UpdateToc(doc)
	case:
		Ldtk_Doc_SetFlag(doc, flag, on)
	}
	_ = a
	Ldtk_Doc_Touch(doc)
	return true
}

// ----------------------------------------------------------------------------
// Backups
// ----------------------------------------------------------------------------

// Ldtk_Doc_BackupDir: Project.getAbsBackupDir.
Ldtk_Doc_BackupDir :: proc(doc: ^Ldtk_Doc, allocator := context.temp_allocator) -> string {
	if rel := LdtkJson_Str(doc.root, "backupRelPath"); rel != "" {
		p, _ := filepath.join({doc.dir, rel}, allocator)
		return p
	}
	stem := strings.trim_suffix(filepath.base(doc.path), filepath.ext(doc.path))
	p, _ := filepath.join({doc.dir, stem, "backups"}, allocator)
	return p
}

// Ldtk_Doc_Backup: ProjectSaver.backupProjectFiles - copies the project file
// (as it is on disk, before saving) and its .ldtkl files to
// "<backups>/<iid>_<date>_<time>/", then keeps the newest backupLimit
// backups. Returns the backup's folder ("" = nothing to back up / failed).
Ldtk_Doc_Backup :: proc(doc: ^Ldtk_Doc, now: time.Time = {}) -> string {
	if !os.is_file(doc.path) do return ""
	now := now
	if now == {} do now = time.now()
	y, mo, d := time.date(now)
	h, mi, s := time.clock_from_time(now)
	iid := LdtkJson_Str(doc.root, "iid", "backup")
	root := Ldtk_Doc_BackupDir(doc)
	dir, _ := filepath.join({root, fmt.tprintf("%s_%04d-%02d-%02d_%02d-%02d-%02d", iid, y, int(mo), d, h, mi, s)}, context.temp_allocator)
	stem := strings.trim_suffix(filepath.base(doc.path), filepath.ext(doc.path))
	files := make([dynamic]string, context.temp_allocator)
	append(&files, filepath.base(doc.path))
	levelDir, _ := filepath.join({doc.dir, stem}, context.temp_allocator)
	if list, err := os.read_all_directory_by_path(levelDir, context.temp_allocator); err == nil {
		for fi in list do if strings.has_suffix(fi.name, ".ldtkl") do append(&files, fmt.tprintf("%s/%s", stem, fi.name))
	}
	for f in files {
		from, _ := filepath.join({doc.dir, f}, context.temp_allocator)
		to, _ := filepath.join({dir, f}, context.temp_allocator)
		bytes, err := os.read_entire_file(from, context.temp_allocator)
		if err != nil do continue
		_ = os.make_directory_all(filepath.dir(to, context.temp_allocator))
		if os.write_entire_file(to, bytes) != nil do return ""
	}
	// the newest backupLimit backups stay
	limit := LdtkJson_Int(doc.root, "backupLimit", 10)
	if list, err := os.read_all_directory_by_path(root, context.temp_allocator); err == nil {
		mine := make([dynamic]string, context.temp_allocator)
		for fi in list do if fi.type == .Directory && strings.has_prefix(fi.name, fmt.tprintf("%s_", iid)) do append(&mine, fi.name)
		slice.sort(mine[:])
		for len(mine) > max(limit, 1) {
			old, _ := filepath.join({root, mine[0]}, context.temp_allocator)
			_ = os.remove_all(old)
			ordered_remove(&mine, 0)
		}
	}
	return strings.clone(dir, context.temp_allocator)
}
