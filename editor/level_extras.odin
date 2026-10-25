package editor

import "core:fmt"
import "core:math"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"
import rl "vendor:raylib"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Level editor conveniences (LDtk's CommandPalette, QuickSearch, file
// watcher, level navigation):
//
//   palette    Cmd+K / Cmd+F: levels, layers, entities (by name, iid or a
//              field value), definitions, rule groups - Enter goes there
//   filters    the lists' search boxes
//   watcher    tileset / background images reload when they change on
//              disk; the project file changed by another program asks
//              before reloading; external enum files are synced
//   navigation Alt+arrows: the neighbouring level; PageUp / PageDown: the
//              next world depth; Shift+PageUp / PageDown: move the level there
// ============================================================================

@(private = "file")
lx: struct {
	open:      bool,
	openReq:   bool,
	buf:       [128]u8,
	sel:       int,
	watchAt:   f64,
	projStamp: time.Time,
	projFor:   rawptr,
	stamps:    map[string]time.Time,
	reloadReq: bool,
	filters:   map[string]string, // list id -> filter text
}

LevelExtras_Shutdown :: proc() {
	for k in lx.stamps do delete(k)
	delete(lx.stamps)
	for k, v in lx.filters {
		delete(k)
		delete(v)
	}
	delete(lx.filters)
	lx = {}
}

// ----------------------------------------------------------------------------
// Command palette
// ----------------------------------------------------------------------------

LevelExtras_OpenPalette :: proc() {
	lx.openReq = true
	lx.buf = {}
	lx.sel = 0
}

@(private = "file")
Palette_Kind :: enum u8 {
	Level,
	Layer,
	Entity,
	Entity_Def,
	Enum,
	Tileset,
	Layer_Def,
	Rule_Group,
}

@(private = "file")
Palette_Item :: struct {
	kind:   Palette_Kind,
	label:  string,
	detail: string,
	li:     int,
	index:  int,
	uid:    int,
	iid:    string,
}

PALETTE_ICONS := [Palette_Kind]string {
	.Level      = ICON_FA_MAP,
	.Layer      = ICON_FA_LAYER_GROUP,
	.Entity     = ICON_FA_CUBE,
	.Entity_Def = ICON_FA_CUBE,
	.Enum       = ICON_FA_LIST,
	.Tileset    = ICON_FA_IMAGE,
	.Layer_Def  = ICON_FA_SLIDERS,
	.Rule_Group = ICON_FA_WAND_MAGIC_SPARKLES,
}

@(private = "file")
matches :: proc(q: string, texts: ..string) -> bool {
	if q == "" do return true
	for t in texts do if strings.contains(strings.to_lower(t, context.temp_allocator), q) do return true
	return false
}

@(private = "file")
palette_items :: proc(q: string) -> [dynamic]Palette_Item {
	L := &GlobalLevel
	doc := L.doc
	out := make([dynamic]Palette_Item, context.temp_allocator)
	add :: proc(out: ^[dynamic]Palette_Item, it: Palette_Item) {if len(out) < 60 do append(out, it)}
	for &lv, li in doc.levels {
		name := e.LdtkJson_Str(lv.obj, "identifier")
		if matches(q, name, e.LdtkJson_Str(lv.obj, "iid")) do add(&out, {kind = .Level, label = name, detail = doc.multiWorlds ? fmt.tprintf("level in %s", e.Ldtk_Doc_WorldName(doc, lv.world)) : "level", li = li})
	}
	if L.level < len(doc.levels) {
		for &ly, j in doc.levels[L.level].layers {
			d := e.Ldtk_Doc_LayerDef(doc, &ly)
			if d != nil && matches(q, d.identifier) do add(&out, {kind = .Layer, label = d.identifier, detail = fmt.tprintf("%s layer of this level", LAYER_TYPE_NAME[d.type]), index = j})
		}
	}
	for &lv, li in doc.levels {
		for &ly, j in lv.layers {
			for ent in e.LdtkJson_Arr(ly.obj, "entityInstances") {
				id := e.LdtkJson_Str(ent, "__identifier")
				iid := e.LdtkJson_Str(ent, "iid")
				hit := matches(q, id, iid)
				// field values (strings, enums)
				if !hit && q != "" {
					for fi in e.LdtkJson_Arr(ent, "fieldInstances") {
						v := e.LdtkJson_Get(fi, "__value")
						if v != nil && v.kind == .String && matches(q, v.text) {
							hit = true
							break
						}
					}
				}
				if hit do add(&out, {kind = .Entity, label = id, detail = fmt.tprintf("entity in %s", e.LdtkJson_Str(lv.obj, "identifier")), li = li, index = j, iid = iid})
			}
		}
	}
	for &ed in doc.entityDefs do if matches(q, ed.identifier) do add(&out, {kind = .Entity_Def, label = ed.identifier, detail = "entity definition", uid = ed.uid})
	defs := e.LdtkJson_Get(doc.root, "defs")
	for key in ([]string{"enums", "externalEnums"}) do for en in e.LdtkJson_Arr(defs, key) {
		name := e.LdtkJson_Str(en, "identifier")
		hit := matches(q, name)
		if !hit do for v in e.LdtkJson_Arr(en, "values") do if matches(q, e.LdtkJson_Str(v, "id")) do hit = true
		if hit do add(&out, {kind = .Enum, label = name, detail = "enum", uid = e.LdtkJson_Int(en, "uid")})
	}
	for &ts in doc.tilesets do if matches(q, ts.identifier, ts.relPath) do add(&out, {kind = .Tileset, label = ts.identifier, detail = "tileset", uid = ts.uid})
	for &d in doc.layerDefs {
		if matches(q, d.identifier) do add(&out, {kind = .Layer_Def, label = d.identifier, detail = "layer definition", uid = d.uid})
		for g in d.groups do if matches(q, g.name) do add(&out, {kind = .Rule_Group, label = g.name, detail = fmt.tprintf("rule group of %s", d.identifier), uid = d.uid})
	}
	return out
}

@(private = "file")
palette_go :: proc(state: ^EditorState, it: Palette_Item) {
	L := &GlobalLevel
	switch it.kind {
	case .Level:
		L.level = -1
		LevelEditor_SetLevel(it.li)
		L.fitRequest = true
	case .Layer:
		L.layer = it.index
		level_clear_selection()
		level_sync_palette()
	case .Entity: level_goto_entity(it.iid)
	case .Entity_Def:
		LevelDefs_SelectEntity(it.uid)
		LevelEditor_ShowTab(.Entities)
	case .Enum:
		LevelEnums_Select(it.uid)
		LevelEditor_ShowTab(.Enums)
	case .Tileset:
		LevelDefs_SelectTileset(it.uid)
		LevelEditor_ShowTab(.Tilesets)
	case .Layer_Def:
		LevelDefs_SelectLayer(it.uid)
		LevelEditor_ShowTab(.Layers)
	case .Rule_Group:
		LevelRules_SelectLayer(it.uid)
		LevelEditor_ShowTab(.Rules)
	}
}

LevelExtras_Palette :: proc(state: ^EditorState) {
	if lx.openReq {
		lx.openReq = false
		imgui.OpenPopup("##LevelPalette")
	}
	vp := imgui.GetMainViewport()
	imgui.SetNextWindowPos({vp.WorkPos.x + vp.WorkSize.x * 0.5, vp.WorkPos.y + 80}, .Always, {0.5, 0})
	imgui.SetNextWindowSize({520, 0})
	if !imgui.BeginPopup("##LevelPalette") do return
	defer imgui.EndPopup()
	if imgui.IsWindowAppearing() do imgui.SetKeyboardFocusHere()
	imgui.SetNextItemWidth(-1)
	imgui.InputTextWithHint("##q", fmt.ctprintf("%s  Search levels, layers, entities, definitions...", ICON_FA_MAGNIFYING_GLASS), cstring(raw_data(lx.buf[:])), len(lx.buf), {})
	Drive_Item("palette.query")
	level_tip("Part of a name, an iid or a field value; arrows pick, Enter goes there", "search")
	q := strings.to_lower(strings.trim_space(string(cstring(raw_data(lx.buf[:])))), context.temp_allocator)
	items := palette_items(q)
	if imgui.IsKeyPressed(.DownArrow, true) do lx.sel = min(lx.sel + 1, len(items) - 1)
	if imgui.IsKeyPressed(.UpArrow, true) do lx.sel = max(lx.sel - 1, 0)
	lx.sel = clamp(lx.sel, 0, max(len(items) - 1, 0))
	if imgui.IsKeyPressed(.Enter, false) && len(items) > 0 {
		palette_go(state, items[lx.sel])
		imgui.CloseCurrentPopup()
		return
	}
	if imgui.IsKeyPressed(.Escape, false) {
		imgui.CloseCurrentPopup()
		return
	}
	if len(items) == 0 do UI_DimText("Nothing matches.")
	if imgui.BeginChild("##palres", {0, min(f32(len(items)) * 26 + 4, 360)}, {}, {}) {
		for it, i in items {
			if imgui.Selectable(fmt.ctprintf("%s  %s##pal%d", PALETTE_ICONS[it.kind], it.label, i), i == lx.sel, {}, {0, 22}) {
				palette_go(state, it)
				imgui.CloseCurrentPopup()
			}
			Drive_Item(fmt.tprintf("palette:%d", i))
			level_tip(fmt.tprintf("%s - %s", it.label, it.detail), "search")
			if i == lx.sel && (imgui.IsKeyPressed(.DownArrow, true) || imgui.IsKeyPressed(.UpArrow, true)) do imgui.SetScrollHereY()
			// the detail, right-aligned on the row
			w := imgui.CalcTextSize(fmt.ctprintf("%s", it.detail)).x
			imgui.SameLine(imgui.GetWindowWidth() - w - imgui.GetStyle().WindowPadding.x - 6)
			UI_DimText(it.detail)
		}
	}
	imgui.EndChild()
}

// ----------------------------------------------------------------------------
// List filters (LDtk's QuickSearch)
// ----------------------------------------------------------------------------

// level_filter_box: a search box above a list; returns the lowercase filter.
level_filter_box :: proc(id: string, hint := "Filter") -> string {
	if lx.filters == nil do lx.filters = make(map[string]string)
	cur := lx.filters[id] or_else ""
	buf: [64]u8
	copy(buf[:63], cur)
	imgui.SetNextItemWidth(-1)
	if imgui.InputTextWithHint(fmt.ctprintf("##filter_%s", id), fmt.ctprintf("%s  %s", ICON_FA_MAGNIFYING_GLASS, hint), cstring(raw_data(buf[:])), len(buf), {}) {
		text := string(cstring(raw_data(buf[:])))
		if old, has := lx.filters[id]; has {
			delete(old)
			lx.filters[id] = strings.clone(text)
		} else do lx.filters[strings.clone(id)] = strings.clone(text)
	}
	Drive_Item(fmt.tprintf("filter:%s", id))
	level_tip("Show only the items whose name contains this", "panel.levels")
	return strings.to_lower(strings.trim_space(lx.filters[id] or_else ""), context.temp_allocator)
}

// level_filter_hit: does a name pass a list's filter?
level_filter_hit :: proc(filter, name: string) -> bool {
	return filter == "" || strings.contains(strings.to_lower(name, context.temp_allocator), filter)
}

// ----------------------------------------------------------------------------
// Navigation
// ----------------------------------------------------------------------------

// level_goto_neighbour: the closest level touching / overlapping the
// active one's side in a direction (same world).
level_goto_neighbour :: proc(state: ^EditorState, dir: [2]int) -> bool {
	L := &GlobalLevel
	doc := L.doc
	p := e.Ldtk_Doc_LevelPos(doc, L.level)
	s := e.Ldtk_Doc_LevelSize(doc, L.level)
	c := [2]f32{f32(p.x) + f32(s.x) * 0.5, f32(p.y) + f32(s.y) * 0.5}
	best, bestD := -1, f32(1e30)
	for &lv, i in doc.levels {
		if i == L.level || lv.world != L.world do continue
		q := e.Ldtk_Doc_LevelPos(doc, i)
		t := e.Ldtk_Doc_LevelSize(doc, i)
		oc := [2]f32{f32(q.x) + f32(t.x) * 0.5, f32(q.y) + f32(t.y) * 0.5}
		d := oc - c
		along := d.x * f32(dir.x) + d.y * f32(dir.y)
		if along <= 0 do continue
		across := abs(d.x * f32(dir.y)) + abs(d.y * f32(dir.x))
		score := along + across * 2
		if score < bestD {
			bestD = score
			best = i
		}
	}
	if best < 0 {
		Editor_Log(state, .Info, "No level that way")
		return true
	}
	LevelEditor_SetLevel(best)
	L.fitRequest = true
	return true
}

@(private = "file")
depths :: proc() -> [dynamic]int {
	L := &GlobalLevel
	out := make([dynamic]int, context.temp_allocator)
	for &lv in L.doc.levels {
		if lv.world != L.world do continue
		d := e.LdtkJson_Int(lv.obj, "worldDepth")
		known := false
		for x in out do if x == d do known = true
		if !known do append(&out, d)
	}
	return out
}

// level_goto_depth: Editor.C_GotoNext/PreviousWorldLayer - the nearest level
// of the next depth up / down.
level_goto_depth :: proc(state: ^EditorState, delta: int) {
	L := &GlobalLevel
	doc := L.doc
	cur := e.LdtkJson_Int(doc.levels[L.level].obj, "worldDepth")
	target := cur
	found := false
	for d in depths() {
		if delta > 0 && d > cur && (!found || d < target) {
			target, found = d, true
		}
		if delta < 0 && d < cur && (!found || d > target) {
			target, found = d, true
		}
	}
	if !found {
		Editor_Log(state, .Info, "No level %s (depth %d)", delta > 0 ? "above" : "below", cur)
		return
	}
	p := e.Ldtk_Doc_LevelPos(doc, L.level)
	best, bestD := -1, max(f32)
	for &lv, i in doc.levels {
		if lv.world != L.world || e.LdtkJson_Int(lv.obj, "worldDepth") != target do continue
		q := e.Ldtk_Doc_LevelPos(doc, i)
		dd := math.abs(f32(q.x - p.x)) + math.abs(f32(q.y - p.y))
		if dd < bestD {
			bestD, best = dd, i
		}
	}
	if best >= 0 {
		LevelEditor_SetLevel(best)
		Editor_Log(state, .Info, "World depth %d", target)
	}
}

// level_move_depth: the active level one depth up / down.
level_move_depth :: proc(state: ^EditorState, delta: int) {
	L := &GlobalLevel
	doc := L.doc
	d := e.LdtkJson_Int(doc.levels[L.level].obj, "worldDepth") + delta
	e.Ldtk_Doc_Checkpoint(doc, L.level, "Level Depth")
	e.Ldtk_Doc_SetLevelDepth(doc, L.level, d)
	Editor_Log(state, .Info, "%s: world depth %d", e.Ldtk_Doc_LevelName(doc, L.level), d)
}

// level_fit_world: every level of the world in the canvas.
level_fit_world :: proc() {
	L := &GlobalLevel
	doc := L.doc
	mn := [2]f32{1e9, 1e9}
	mx := [2]f32{-1e9, -1e9}
	for &lv, i in doc.levels {
		if lv.world != L.world do continue
		p := e.Ldtk_Doc_LevelPos(doc, i)
		s := e.Ldtk_Doc_LevelSize(doc, i)
		mn = {min(mn.x, f32(p.x)), min(mn.y, f32(p.y))}
		mx = {max(mx.x, f32(p.x + s.x)), max(mx.y, f32(p.y + s.y))}
	}
	if mx.x <= mn.x || L.canvasSize.x <= 0 do return
	L.cam = (mn + mx) * 0.5
	L.zoom = clamp(min((L.canvasSize.x - 40) / (mx.x - mn.x), (L.canvasSize.y - 40) / (mx.y - mn.y)), 0.1, 8)
}

// ----------------------------------------------------------------------------
// File watcher
// ----------------------------------------------------------------------------

@(private = "file")
mtime :: proc(path: string) -> (time.Time, bool) {
	fi, err := os.stat(path, context.temp_allocator)
	if err != nil do return {}, false
	return fi.modification_time, true
}

// LevelExtras_ProjectSaved: the project file's time after our own writes.
LevelExtras_ProjectSaved :: proc() {
	doc := GlobalLevel.doc
	if doc == nil do return
	if t, ok := mtime(doc.path); ok do lx.projStamp = t
	lx.projFor = rawptr(doc)
}

// LevelExtras_Watch checks the files the project uses about once a second.
LevelExtras_Watch :: proc(state: ^EditorState) {
	L := &GlobalLevel
	doc := L.doc
	if doc == nil do return
	if lx.projFor != rawptr(doc) do LevelExtras_ProjectSaved() // a newly opened project
	reload_prompt(state)
	now := rl.GetTime()
	if now - lx.watchAt < 1 do return
	lx.watchAt = now
	if lx.stamps == nil do lx.stamps = make(map[string]time.Time)
	// images: tilesets and level backgrounds
	check :: proc(rel: string) -> bool {
		doc := GlobalLevel.doc
		p, _ := filepath.join({doc.dir, rel}, context.temp_allocator)
		t, ok := mtime(p)
		if !ok do return false
		old, known := lx.stamps[rel]
		if !known {
			lx.stamps[strings.clone(rel)] = t
			return false
		}
		if time.diff(old, t) == 0 do return false
		lx.stamps[rel] = t
		return true
	}
	for &ts in doc.tilesets {
		if ts.relPath == "" || !check(ts.relPath) do continue
		p, _ := filepath.join({doc.dir, ts.relPath}, context.temp_allocator)
		img := rl.LoadImage(strings.clone_to_cstring(p, context.temp_allocator))
		if img.data == nil do continue
		e.Ldtk_Doc_ReloadTilesetImage(doc, ts.uid, &img)
		rl.UnloadImage(img)
		level_reload_texture(ts.uid)
		Editor_Log(state, .Info, "Reloaded the tileset image %s", ts.relPath)
		break // (the definitions were refreshed)
	}
	for &lv in doc.levels {
		rel := e.LdtkJson_Str(lv.obj, "bgRelPath")
		if rel == "" || !check(rel) do continue
		level_reload_bg_texture(rel)
		Editor_Log(state, .Info, "Reloaded the background image %s", rel)
	}
	// the project file written by another program
	if t, ok := mtime(doc.path); ok && time.diff(lx.projStamp, t) > 0 && !lx.reloadReq {
		lx.projStamp = t
		lx.reloadReq = true
	}
	// external enum files
	for src in e.Ldtk_Doc_ExternalEnumSources(doc) {
		if !src.missing && src.modified && check(src.relPath) do LevelEnums_Sync(state, src.relPath, true)
	}
}

@(private = "file")
reload_prompt :: proc(state: ^EditorState) {
	L := &GlobalLevel
	if lx.reloadReq {
		lx.reloadReq = false
		imgui.OpenPopup("Project Changed###LevelReload")
	}
	center := imgui.GetMainViewport().WorkPos + imgui.GetMainViewport().WorkSize * 0.5
	imgui.SetNextWindowPos(center, .Appearing, {0.5, 0.5})
	if !imgui.BeginPopupModal("Project Changed###LevelReload", nil, {.AlwaysAutoResize}) do return
	defer imgui.EndPopup()
	UI_DimText(fmt.tprintf("%s was changed by another program.", filepath.base(L.rel)))
	if L.doc.modified do UI_DimText("Reloading loses your unsaved changes.")
	if UI_PrimaryButton("Reload", "reload.ok") {
		rel := strings.clone(L.rel, context.temp_allocator)
		L.doc.modified = false // (no "save first?" prompt)
		LevelEditor_Open(state, rel)
		imgui.CloseCurrentPopup()
		return
	}
	imgui.SameLine()
	if UI_Button("Keep mine", "reload.keep") || imgui.IsKeyPressed(.Escape) do imgui.CloseCurrentPopup()
	level_tip("Keep editing; saving overwrites the other program's version", "saving")
}
