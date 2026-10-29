package editor

import "core:fmt"
import "core:path/filepath"
import "core:strings"
import rl "vendor:raylib"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Level editor: the Tilesets tab (LDtk's EditTilesetDefs / TileTagger)
//
//   tilesets (by tag) | the picked tileset: identifier, image (change /
//   reload; tiles remapped when its size changes), tile size (remapped),
//   spacing, padding, tags, tag enum; its tiles: custom data, animation,
//   enum tags (painted over the tiles with a picked tag)
// ============================================================================

@(private = "file")
lt: struct {
	uid:        int,
	tileId:     int,
	clip:       string,
	paintTag:   string, // enum value painted by clicking tiles ("" = pick tiles)
	deleteReq:  bool,
	deleteUid:  int,
	tagEnumReq: bool,
	tagEnumTo:  int,
}

TILESET_TOPIC :: "tab.tilesets"

LevelTilesets_Shutdown :: proc() {
	delete(lt.clip)
	delete(lt.paintTag)
	lt = {}
}

LevelTilesets_Select :: proc(uid: int) {lt.uid = uid}
LevelTilesets_Selected :: proc() -> int {return lt.uid}

LevelTilesets_Page :: proc(state: ^EditorState) {
	L := &GlobalLevel
	doc := L.doc
	avail := imgui.GetContentRegionAvail()
	if imgui.BeginChild("##tileset_list", {230, avail.y}, {.Borders}, {}) {
		images := Editor_ListProjectFiles(state, "", {".png", ".jpg", ".jpeg", ".bmp"})
		imgui.SetNextItemWidth(-1)
		if imgui.BeginCombo("##add_tileset", fmt.ctprintf("%s  Add from an image...", ICON_FA_PLUS)) {
			for rel in images {
				if imgui.Selectable(fmt.ctprintf("%s", rel)) do add_tileset(state, rel)
				Drive_Item(fmt.tprintf("pick:%s", rel))
			}
			if len(images) == 0 do UI_DimText("No image in the project")
			imgui.EndCombo()
		}
		Drive_Item("defs.tileset.add")
		level_tip("A new tileset from an image of the project (its grid: the project's default)", TILESET_TOPIC)
		filter := level_filter_box("tilesets", "Filter tilesets")
		imgui.Separator()
		tags := make([dynamic]string, context.temp_allocator)
		append(&tags, "")
		for &ts in doc.tilesets do for t in e.LdtkJson_Arr(ts.obj, "tags") {
			known := false
			for x in tags do if x == t.text do known = true
			if !known do append(&tags, t.text)
		}
		for tag in tags {
			if len(tags) > 1 do UI_DimText(tag == "" ? "UNTAGGED" : strings.to_upper(tag, context.temp_allocator))
			for &ts in doc.tilesets {
				tt := e.LdtkJson_Arr(ts.obj, "tags")
				if (len(tt) > 0 ? tt[0].text : "") != tag || !level_filter_hit(filter, ts.identifier) do continue
				embedded := ts.relPath == ""
				if imgui.Selectable(fmt.ctprintf("%s%s##tsl%d", embedded ? "[embedded] " : "", ts.identifier, ts.uid), lt.uid == ts.uid, {}, {0, 22}) {
					lt.uid = ts.uid
					delete(lt.paintTag)
					lt.paintTag = ""
				}
				Drive_Item(fmt.tprintf("defs.tileset:%s", ts.identifier))
				level_tip(fmt.tprintf("%s: %dx%d px, %d px tiles%s. Right-click for more.", ts.identifier, ts.pxSize.x, ts.pxSize.y, ts.gridSize, embedded ? " (LDtk's embedded atlas: no image file here)" : ""), TILESET_TOPIC)
				if tileset_menu(state, ts.uid) {
					imgui.EndChild()
					tileset_dialogs(state)
					return
				}
			}
		}
		imgui.Dummy({imgui.GetContentRegionAvail().x, max(imgui.GetContentRegionAvail().y, 20)})
		if imgui.BeginPopupContextItem("##tslistctx") {
			if ctx_item(ICON_FA_PASTE, "Paste tileset", "Paste the copied tileset at the end", lt.clip != "") {
				defs_checkpoint("Paste Tileset")
				if nu := e.Ldtk_Doc_PasteTileset(doc, lt.clip); nu > 0 do lt.uid = nu
			}
			imgui.EndPopup()
		}
	}
	imgui.EndChild()
	imgui.SameLine(0, 8)
	if imgui.BeginChild("##tileset_props", {0, avail.y}, {}, {}) {
		if e.Ldtk_Doc_Tileset(doc, lt.uid) == nil do UI_DimText("Pick a tileset, or add one from an image.")
		else do tileset_form(state, lt.uid)
	}
	imgui.EndChild()
	tileset_dialogs(state)
}

// add_tileset adds a project image (path made relative to the .ldtk).
@(private = "file")
add_tileset :: proc(state: ^EditorState, rel: string) {
	L := &GlobalLevel
	doc := L.doc
	img := rl.LoadImage(strings.clone_to_cstring(level_abs(state, rel), context.temp_allocator))
	if img.data == nil {
		Editor_Log(state, .Error, "Could not read %s", rel)
		return
	}
	defer rl.UnloadImage(img)
	defs_checkpoint("Add Tileset")
	lt.uid = e.Ldtk_Doc_AddTileset(doc, level_doc_rel(state, rel), {int(img.width), int(img.height)}, e.LdtkJson_Int(doc.root, "defaultGridSize", 16), &img)
}

@(private = "file")
tileset_used :: proc(doc: ^e.Ldtk_Doc, uid: int) -> bool {
	for &d in doc.layerDefs do if d.tilesetUid == uid do return true
	for &ed in doc.entityDefs do if ed.tilesetUid == uid do return true
	defs := e.LdtkJson_Get(doc.root, "defs")
	for en in e.LdtkJson_Arr(defs, "enums") do if e.LdtkJson_Int(en, "iconTilesetUid", -1) == uid do return true
	return false
}

@(private = "file")
delete_tileset :: proc(uid: int) {
	doc := GlobalLevel.doc
	if tileset_used(doc, uid) {
		lt.deleteReq = true
		lt.deleteUid = uid
		return
	}
	defs_checkpoint("Delete Tileset")
	e.Ldtk_Doc_RemoveTileset(doc, uid)
	level_after_defs()
}

// tileset_menu: a tileset's right-click menu (true: the tilesets changed).
@(private = "file")
tileset_menu :: proc(state: ^EditorState, uid: int) -> bool {
	doc := GlobalLevel.doc
	if !imgui.BeginPopupContextItem(fmt.ctprintf("##tsctx%d", uid)) do return false
	defer imgui.EndPopup()
	ts := e.Ldtk_Doc_Tileset(doc, uid)
	if ts == nil do return false
	embedded := ts.relPath == ""
	if ctx_item(ICON_FA_COPY, "Copy", "Copy the tileset definition", !embedded) {
		delete(lt.clip)
		lt.clip = e.Ldtk_Doc_TilesetText(doc, uid)
	}
	if ctx_item(ICON_FA_SCISSORS, "Cut", "Copy it, then delete it", !embedded) {
		delete(lt.clip)
		lt.clip = e.Ldtk_Doc_TilesetText(doc, uid)
		delete_tileset(uid)
		return true
	}
	if ctx_item(ICON_FA_PASTE, "Paste after", "Paste the copied tileset after this one", lt.clip != "") {
		defs_checkpoint("Paste Tileset")
		if nu := e.Ldtk_Doc_PasteTileset(doc, lt.clip, uid); nu > 0 do lt.uid = nu
		return true
	}
	if ctx_item(ICON_FA_CLONE, "Duplicate", "A copy (tags, custom data, saved selections) after it") {
		defs_checkpoint("Duplicate Tileset")
		if nu := e.Ldtk_Doc_DuplicateTileset(doc, uid); nu > 0 do lt.uid = nu
		return true
	}
	imgui.Separator()
	if ctx_item(ICON_FA_ARROW_UP, "Move up", "Earlier in the list") {
		defs_checkpoint("Move Tileset")
		e.Ldtk_Doc_MoveTileset(doc, uid, -1)
		return true
	}
	if ctx_item(ICON_FA_ARROW_DOWN, "Move down", "Later in the list") {
		defs_checkpoint("Move Tileset")
		e.Ldtk_Doc_MoveTileset(doc, uid, 1)
		return true
	}
	if !embedded && ctx_item(ICON_FA_ROTATE, "Reload image", "Read the image file again (tiles are remapped if its size changed)") do reload_image(state, uid, "")
	imgui.Separator()
	if ctx_item(ICON_FA_TRASH, "Delete", "Delete the tileset (layers, entities, fields and icons using it lose it; asks first)") {
		delete_tileset(uid)
		return true
	}
	imgui.Separator()
	if ctx_item(ICON_FA_CIRCLE_QUESTION, "Help", "Tilesets in the reference") do LevelRef_Open(TILESET_TOPIC)
	return false
}

// reload_image: a new image (rel != "") or the same one read again.
@(private = "file")
reload_image :: proc(state: ^EditorState, uid: int, projectRel: string) {
	L := &GlobalLevel
	doc := L.doc
	ts := e.Ldtk_Doc_Tileset(doc, uid)
	if ts == nil do return
	docRel := projectRel != "" ? level_doc_rel(state, projectRel) : ts.relPath
	p, _ := filepath.join({doc.dir, docRel}, context.temp_allocator)
	img := rl.LoadImage(strings.clone_to_cstring(p, context.temp_allocator))
	if img.data == nil {
		Editor_Log(state, .Error, "Could not read %s", docRel)
		return
	}
	defer rl.UnloadImage(img)
	defs_checkpoint(projectRel != "" ? "Tileset Image" : "Reload Tileset Image")
	switch e.Ldtk_Doc_SetTilesetImage(doc, uid, projectRel != "" ? docRel : "", &img) {
	case .Ok: Editor_Log(state, .Info, "Image loaded")
	case .Remapped: Editor_Log(state, .Info, "The image's size changed: tiles were remapped to keep their place")
	case .Remap_Loss: Editor_Log(state, .Warn, "The image is smaller: some tiles were lost in the remapping")
	case .Trimmed_Padding: Editor_Log(state, .Info, "The image is smaller by its padding: the padding was reduced")
	}
	level_reload_texture(uid)
	level_after_defs()
}

@(private = "file")
tileset_form :: proc(state: ^EditorState, uid: int) {
	L := &GlobalLevel
	doc := L.doc
	ts := e.Ldtk_Doc_Tileset(doc, uid)
	embedded := ts.relPath == ""
	UI_PanelTitle(ICON_FA_TABLE_CELLS, ts.identifier, embedded ? "embedded atlas" : ts.relPath)
	UI_HeaderButtons(3)
	if UI_HeaderButton(ICON_FA_CLONE, "defs.tileset.duplicate", "") {
		defs_checkpoint("Duplicate Tileset")
		if nu := e.Ldtk_Doc_DuplicateTileset(doc, uid); nu > 0 do lt.uid = nu
		return
	}
	level_tip("Duplicate the tileset", TILESET_TOPIC)
	if UI_HeaderButton(ICON_FA_TRASH, "defs.tileset.remove", "") {
		delete_tileset(uid)
		return
	}
	level_tip("Delete the tileset (asks when it is used)", TILESET_TOPIC)
	if UI_HeaderButton(ICON_FA_CIRCLE_QUESTION, "defs.tileset.help", "") do LevelRef_Open(TILESET_TOPIC)
	level_tip("Tilesets in the reference", TILESET_TOPIC)
	img_for :: proc(ts: ^e.Ldtk_DocTileset) -> rl.Image {
		if ts.relPath == "" do return {}
		p, _ := filepath.join({GlobalLevel.doc.dir, ts.relPath}, context.temp_allocator)
		return rl.LoadImage(strings.clone_to_cstring(p, context.temp_allocator))
	}
	if !UI_BeginProps("##ts_t") do return
	UI_PropLabel("Identifier")
	if name, ok := defs_text_edit("defs.tileset.name", ts.obj, "identifier"); ok && name != "" {
		defs_checkpoint("Rename Tileset")
		e.Ldtk_Doc_RenameTileset(doc, uid, name)
		UI_EndProps()
		return
	}
	level_tip("Its name (unique; Enter applies)", TILESET_TOPIC)
	if !embedded {
		UI_PropLabel("Image")
		images := Editor_ListProjectFiles(state, "", {".png", ".jpg", ".jpeg", ".bmp"})
		if imgui.BeginCombo("##tsimage", fmt.ctprintf("%s", ts.relPath)) {
			for rel in images {
				if imgui.Selectable(fmt.ctprintf("%s", rel), level_doc_rel(state, rel) == ts.relPath) {
					imgui.EndCombo()
					UI_EndProps()
					reload_image(state, uid, rel)
					return
				}
				Drive_Item(fmt.tprintf("pick:%s", rel))
			}
			imgui.EndCombo()
		}
		Drive_Item("defs.tileset.image")
		level_tip("Another image for the tileset (tiles keep their place when the size changes)", "tileset.image")
		imgui.SameLine()
		if UI_IconButton(ICON_FA_ROTATE, "defs.tileset.reload", "", false, 26) {
			UI_EndProps()
			reload_image(state, uid, "")
			return
		}
		level_tip("Read the image file again (it is also reloaded when it changes on disk)", "tileset.image")
		if level_texture_ptr(uid) == nil {
			UI_PropLabel("")
			imgui.TextColored(UI_DANGER, "The image file is missing")
		}
	}
	UI_PropLabel("Tile size")
	grid, gridSet := level_input_int("##tsgrid", i32(ts.gridSize), 1, 8)
	if gridSet && grid >= 2 && int(grid) != ts.gridSize {
		img := img_for(ts)
		defer if img.data != nil do rl.UnloadImage(img)
		defs_checkpoint("Tileset Grid")
		if !e.Ldtk_Doc_SetTilesetGrid(doc, uid, int(grid), &img) do Editor_Log(state, .Warn, "The bigger grid lost some tiles in the remapping (undo brings them back)")
		else do Editor_Log(state, .Info, "Tiles were remapped to the new grid")
		UI_EndProps()
		level_after_defs()
		return
	}
	Drive_Item("defs.tileset.tileGridSize")
	level_tip("Tile size in pixels; painted tiles, rules, tags and custom data keep their place in the image", "tileset.image")
	UI_PropLabel("Spacing, padding")
	sp := [2]i32{i32(ts.spacing), i32(ts.padding)}
	w := (imgui.GetContentRegionAvail().x - 4) * 0.5
	imgui.SetNextItemWidth(w)
	ch1, ch2: bool
	sp.x, ch1 = level_input_int("##tsspacing", sp.x)
	Drive_Item("defs.tileset.spacing")
	level_tip("Pixels between tiles", "tileset.image")
	imgui.SameLine(0, 4)
	imgui.SetNextItemWidth(w)
	sp.y, ch2 = level_input_int("##tspadding", sp.y)
	Drive_Item("defs.tileset.padding")
	level_tip("Pixels around the whole image", "tileset.image")
	if (ch1 || ch2) && sp.x >= 0 && sp.y >= 0 {
		img := img_for(ts)
		defer if img.data != nil do rl.UnloadImage(img)
		defs_checkpoint("Tileset Spacing")
		e.Ldtk_Doc_SetTilesetSpacing(doc, uid, int(sp.x), int(sp.y), &img)
		UI_EndProps()
		level_after_defs()
		return
	}
	UI_PropLabel("Tags")
	{
		cur := strings.builder_make(context.temp_allocator)
		for t, i in e.LdtkJson_Arr(ts.obj, "tags") {
			if i > 0 do strings.write_string(&cur, ", ")
			strings.write_string(&cur, t.text)
		}
		buf: [256]u8
		copy(buf[:255], strings.to_string(cur))
		if imgui.InputTextWithHint("##tstags", "none", cstring(raw_data(buf[:])), len(buf), {.EnterReturnsTrue}) || imgui.IsItemDeactivatedAfterEdit() {
			defs_checkpoint("Tileset Tags")
			e.Ldtk_Doc_SetTilesetTags(doc, uid, strings.split(string(cstring(raw_data(buf[:]))), ",", context.temp_allocator))
		}
		Drive_Item("defs.tileset.tags")
		level_tip("Comma-separated: the list groups tilesets by their first tag", TILESET_TOPIC)
	}
	UI_PropLabel("Tag enum")
	{
		enums := e.LdtkJson_Arr(e.LdtkJson_Get(doc.root, "defs"), "enums")
		names := make([]string, len(enums) + 1, context.temp_allocator)
		names[0] = "(none)"
		cur := 0
		src := e.LdtkJson_Int(ts.obj, "tagsSourceEnumUid", -1)
		for en, i in enums {
			names[i + 1] = e.LdtkJson_Str(en, "identifier")
			if e.LdtkJson_Int(en, "uid") == src do cur = i + 1
		}
		if pick, changed := UI_Combo("defs.tileset.tagenum", cur, names); changed {
			to := pick == 0 ? -1 : e.LdtkJson_Int(enums[pick - 1], "uid")
			if e.Ldtk_Doc_TilesetHasTags(doc, uid) {
				lt.tagEnumReq = true
				lt.tagEnumTo = to
			} else {
				defs_checkpoint("Tag Enum")
				e.Ldtk_Doc_SetTilesetTagEnum(doc, uid, to)
			}
		}
		level_tip("An enum whose values tag tiles (games read them; tiles can carry several). Changing it forgets the tags.", "tileset.tags")
	}
	UI_EndProps()
	UI_DimText(fmt.tprintf("%dx%d px, %dx%d tiles", ts.pxSize.x, ts.pxSize.y, ts.cWid, ts.cHei))
	tile_data_editor(state, uid)
}

// tile_data_editor: the tileset's tiles; the picked tile's custom data,
// animation and enum tags; tags painted over tiles.
@(private = "file")
tile_data_editor :: proc(state: ^EditorState, uid: int) {
	L := &GlobalLevel
	doc := L.doc
	ts := e.Ldtk_Doc_Tileset(doc, uid)
	tagEnum := e.Ldtk_Doc_EnumDef(doc, e.LdtkJson_Int(ts.obj, "tagsSourceEnumUid", -1))
	UI_SectionHeader("Tiles")
	if tagEnum != nil {
		// the tag painted by clicking tiles (LDtk's TileTagger)
		if UI_IconButton(ICON_FA_HAND_POINTER, "defs.tile.painttag:none", "", lt.paintTag == "", 24) {
			delete(lt.paintTag)
			lt.paintTag = ""
		}
		level_tip("Click tiles to pick them (their data below)", "tileset.tags")
		for v in e.LdtkJson_Arr(tagEnum, "values") {
			id := e.LdtkJson_Str(v, "id")
			imgui.SameLine()
			rgb := e.LdtkJson_Int(v, "color")
			col := imgui.Vec4{f32((rgb >> 16) & 255) / 255, f32((rgb >> 8) & 255) / 255, f32(rgb & 255) / 255, 1}
			on := lt.paintTag == id
			imgui.PushStyleColorImVec4(.Button, on ? col : imgui.Vec4{col.x * 0.4, col.y * 0.4, col.z * 0.4, 1})
			if imgui.Button(fmt.ctprintf("%s##pt", id)) {
				delete(lt.paintTag)
				lt.paintTag = on ? "" : strings.clone(id)
			}
			imgui.PopStyleColor()
			Drive_Item(fmt.tprintf("defs.tile.painttag:%s", id))
			level_tip(fmt.tprintf("Paint \"%s\": click tiles to tag / untag them", id), "tileset.tags")
		}
	}
	ptr := level_texture_ptr(uid)
	if ptr == nil {
		UI_DimText(ts.relPath == "" ? "LDtk's embedded atlas isn't drawn here." : "Image not found.")
		return
	}
	tex := ptr^
	avail := imgui.GetContentRegionAvail()
	z := clamp(min(avail.x / f32(max(tex.width, 1)), 320 / f32(max(tex.height, 1))), 0.25, 3)
	w, h := f32(tex.width) * z, f32(tex.height) * z
	{ // (drawn inline: a scrolling child here would take the page's wheel)
		p := imgui.GetCursorScreenPos()
		dl := imgui.GetWindowDrawList()
		imgui.InvisibleButton("##tiles", {w, h})
		Drive_ItemRect("defs.tiles", {p.x, p.y}, {p.x + 1, p.y + 1}, true)
		level_tip(lt.paintTag != "" ? fmt.tprintf("Click tiles to tag / untag them \"%s\"", lt.paintTag) : "Click a tile to edit its data", TILESET_TOPIC)
		imgui.DrawList_AddImage(dl, transmute(imgui.TextureID)ptr, p, {p.x + w, p.y + h})
		step := f32(ts.gridSize + ts.spacing) * z
		pad := f32(ts.padding) * z
		gs := f32(ts.gridSize) * z
		tile_rect :: proc(p: [2]f32, pad, step, gs: f32, tid, cw: int) -> ([2]f32, [2]f32) {
			x, y := tid % max(cw, 1), tid / max(cw, 1)
			mn := [2]f32{p.x + pad + f32(x) * step, p.y + pad + f32(y) * step}
			return mn, mn + gs
		}
		for cd in e.LdtkJson_Arr(ts.obj, "customData") {
			tid := e.LdtkJson_Int(cd, "tileId")
			mn, mx := tile_rect(p, pad, step, gs, tid, ts.cWid)
			isAnim := i32(tid) in ts.anims
			imgui.DrawList_AddCircleFilled(dl, {mx.x - 5, mn.y + 5}, 3, col_u32(isAnim ? UI_SUCCESS : UI_WARNING))
		}
		// enum tags: a coloured bar per tag (the painted one brighter)
		if tagEnum != nil {
			for t in e.LdtkJson_Arr(ts.obj, "enumTags") {
				id := e.LdtkJson_Str(t, "enumValueId")
				rgb := 0xffffff
				for v in e.LdtkJson_Arr(tagEnum, "values") do if e.LdtkJson_Str(v, "id") == id do rgb = e.LdtkJson_Int(v, "color")
				a: f32 = lt.paintTag == "" || lt.paintTag == id ? 0.9 : 0.3
				col := imgui.Vec4{f32((rgb >> 16) & 255) / 255, f32((rgb >> 8) & 255) / 255, f32(rgb & 255) / 255, a}
				for v in e.LdtkJson_Arr(t, "tileIds") {
					mn, mx := tile_rect(p, pad, step, gs, int(v.num), ts.cWid)
					if lt.paintTag == id do imgui.DrawList_AddRectFilled(dl, mn, mx, col_u32({col.x, col.y, col.z, 0.35}), 0, {})
					imgui.DrawList_AddRectFilled(dl, {mn.x, mx.y - 3}, {mx.x, mx.y}, col_u32(col), 0, {})
				}
			}
		}
		if imgui.IsItemActivated() {
			m := imgui.GetIO().MousePos
			cx := int((m.x - p.x - pad) / step)
			cy := int((m.y - p.y - pad) / step)
			if cx >= 0 && cy >= 0 && cx < ts.cWid && cy < ts.cHei {
				tid := cx + cy * ts.cWid
				if lt.paintTag != "" {
					defs_checkpoint("Tile Tag")
					e.Ldtk_Doc_SetTileTag(doc, uid, tid, lt.paintTag, !e.Ldtk_Doc_TileHasTag(doc, uid, tid, lt.paintTag))
				}
				lt.tileId = tid
			}
		}
		mn, mx := tile_rect(p, pad, step, gs, lt.tileId, ts.cWid)
		imgui.DrawList_AddRect(dl, mn, mx, col_u32(UI_ACCENT), 0, {}, 2)
	}
	UI_DimText("Dots: tiles with custom data (green: animated); bars: enum tags.")
	tid := lt.tileId
	UI_SectionHeader(fmt.tprintf("Tile %d", tid))
	// custom data (live; one undo step per edit)
	cur := e.Ldtk_Doc_TileCustomData(doc, uid, tid)
	buf: [1024]u8
	copy(buf[:len(buf) - 1], cur)
	if imgui.InputTextMultiline("##tile_custom", cstring(raw_data(buf[:])), len(buf), {-1, 70}, {}) {
		e.Ldtk_Doc_CheckpointOnce(doc, -1, "Tile Data", rawptr(uintptr(uid * 100003 + tid + 1)))
		e.Ldtk_Doc_SetTileCustomData(doc, uid, tid, string(cstring(raw_data(buf[:]))))
	}
	if imgui.IsItemDeactivated() do e.Ldtk_Doc_EndCoalesce(doc)
	Drive_Item("defs.tile.custom")
	level_tip("Free text for your scripts (node:ldtk_get_tile(layer, x, y).custom_data); \"anim=\" / \"fps=\" lines animate the tile", "tile.animation")
	// animation
	anim, animated := e.Ldtk_Doc_TileAnimation(doc, uid, tid)
	if animated {
		b := strings.builder_make(context.temp_allocator)
		for f, i in anim.frames {
			if i > 0 do strings.write_string(&b, ", ")
			fmt.sbprintf(&b, "%d", f)
		}
		UI_DimText(fmt.tprintf("Animated: %s at %v fps", strings.to_string(b), anim.fps))
	}
	if UI_Button(fmt.tprintf("%s  Animate with picked tiles", ICON_FA_PLAY), "defs.tile.animate") {
		if len(L.tileSel) >= 2 {
			defs_checkpoint("Tile Animation")
			e.Ldtk_Doc_SetTileAnimation(doc, uid, tid, L.tileSel[:], animated ? anim.fps : e.LDTK_TILE_ANIM_DEFAULT_FPS)
		} else do Editor_Log(state, .Info, "Pick two or more tiles (the frames, in order) in the Layers panel's tileset first")
	}
	level_tip("The frames: tiles picked in the Layers panel's tileset, left to right, top to bottom", "tile.animation")
	if animated {
		imgui.SameLine()
		imgui.SetNextItemWidth(80)
		fps := anim.fps
		if (imgui.InputFloat("fps##tile_fps", &fps, 0, 0, "%.1f") || imgui.IsItemDeactivatedAfterEdit()) && fps > 0 {
			defs_checkpoint("Tile Animation")
			e.Ldtk_Doc_SetTileAnimation(doc, uid, tid, anim.frames, fps)
		}
		Drive_Item("defs.tile.fps")
		level_tip("Frames per second (Enter applies)", "tile.animation")
		imgui.SameLine()
		if UI_Button("Stop", "defs.tile.animate.stop") {
			defs_checkpoint("Tile Animation")
			e.Ldtk_Doc_SetTileAnimation(doc, uid, tid, nil, 0)
		}
		level_tip("No animation for this tile", "tile.animation")
	}
	// enum tags of the picked tile
	if tagEnum != nil {
		UI_DimText("Tags:")
		for v in e.LdtkJson_Arr(tagEnum, "values") {
			id := e.LdtkJson_Str(v, "id")
			on := e.Ldtk_Doc_TileHasTag(doc, uid, tid, id)
			imgui.SameLine()
			if imgui.Checkbox(fmt.ctprintf("%s##tag", id), &on) {
				defs_checkpoint("Tile Tag")
				e.Ldtk_Doc_SetTileTag(doc, uid, tid, id, on)
			}
			Drive_Item(fmt.tprintf("defs.tile.tag:%s", id))
			level_tip(fmt.tprintf("Tag this tile \"%s\"", id), "tileset.tags")
		}
	}
}

@(private = "file")
tileset_dialogs :: proc(state: ^EditorState) {
	doc := GlobalLevel.doc
	center := imgui.GetMainViewport().WorkPos + imgui.GetMainViewport().WorkSize * 0.5
	if lt.deleteReq {
		lt.deleteReq = false
		imgui.OpenPopup("Delete Tileset###LevelDeleteTileset")
	}
	imgui.SetNextWindowPos(center, .Appearing, {0.5, 0.5})
	if imgui.BeginPopupModal("Delete Tileset###LevelDeleteTileset", nil, {.AlwaysAutoResize}) {
		UI_DimText("Layers, entities, fields or enum icons use this tileset:")
		UI_DimText("they lose it (undo brings it back). Delete it?")
		if UI_PrimaryButton("Delete", "deletetileset.ok") {
			defs_checkpoint("Delete Tileset")
			e.Ldtk_Doc_RemoveTileset(doc, lt.deleteUid)
			level_after_defs()
			imgui.CloseCurrentPopup()
		}
		level_tip("Delete it anyway", TILESET_TOPIC)
		imgui.SameLine()
		if UI_Button("Cancel", "deletetileset.cancel") || imgui.IsKeyPressed(.Escape) do imgui.CloseCurrentPopup()
		level_tip("Keep the tileset", TILESET_TOPIC)
		imgui.EndPopup()
	}
	if lt.tagEnumReq {
		lt.tagEnumReq = false
		imgui.OpenPopup("Tag Enum###LevelTagEnum")
	}
	imgui.SetNextWindowPos(center, .Appearing, {0.5, 0.5})
	if imgui.BeginPopupModal("Tag Enum###LevelTagEnum", nil, {.AlwaysAutoResize}) {
		UI_DimText("Tiles of this tileset have tags: changing the enum")
		UI_DimText("forgets them (undo brings them back).")
		if UI_PrimaryButton("Change", "tagenum.ok") {
			defs_checkpoint("Tag Enum")
			e.Ldtk_Doc_SetTilesetTagEnum(doc, lt.uid, lt.tagEnumTo)
			imgui.CloseCurrentPopup()
		}
		level_tip("Use the other enum; the tags go", "tileset.tags")
		imgui.SameLine()
		if UI_Button("Cancel", "tagenum.cancel") || imgui.IsKeyPressed(.Escape) do imgui.CloseCurrentPopup()
		level_tip("Keep the tags", "tileset.tags")
		imgui.EndPopup()
	}
}
