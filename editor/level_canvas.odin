package editor

import "core:fmt"
import "core:math"
import "core:math/rand"
import rl "vendor:raylib"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Level editor canvas: draws the active world's levels (the active one on
// top, the others dimmed) and runs the tools on the active layer.
//
//   IntGrid  Brush / Rectangle / Erase / Fill / Pick; right button erases
//   Tiles    the palette's stamp (with flips); same tools
//   Entities Brush places the picked entity, Select moves / resizes,
//            right click / Delete removes
//   Any      Move Levels drags levels in the world; a click in another level
//            makes it active; middle drag / Space+drag pans, wheel zooms
//
// Every stroke is one undo step (Ldtk_Doc_BeginCells / EndCells); auto
// tiles follow each painted cell (Ldtk_Doc_ApplyRules).
// ============================================================================

LevelCanvas_SetZoom :: proc(z: f32) {
	GlobalLevel.zoom = clamp(z, 0.1, 16)
}

@(private = "file")
to_screen :: proc(w: [2]f32) -> [2]f32 {
	L := &GlobalLevel
	return L.canvasMin + (w - L.cam) * L.zoom + L.canvasSize * 0.5
}

@(private = "file")
to_world :: proc(s: [2]f32) -> [2]f32 {
	L := &GlobalLevel
	return (s - L.canvasMin - L.canvasSize * 0.5) / L.zoom + L.cam
}

@(private = "file")
fit_level :: proc() {
	L := &GlobalLevel
	doc := L.doc
	if doc == nil || len(doc.levels) == 0 || L.canvasSize.x <= 0 do return
	p := e.Ldtk_Doc_LevelPos(doc, L.level)
	s := e.Ldtk_Doc_LevelSize(doc, L.level)
	L.cam = {f32(p.x) + f32(s.x) * 0.5, f32(p.y) + f32(s.y) * 0.5}
	z := min((L.canvasSize.x - 40) / f32(max(s.x, 1)), (L.canvasSize.y - 40) / f32(max(s.y, 1)))
	// whole steps keep pixel art crisp
	L.zoom = z >= 1 ? math.floor(z) : clamp(z, 0.1, 1)
}

col_rl :: proc(c: rl.Color, a: f32) -> rl.Color {
	return {c.r, c.g, c.b, u8(clamp(f32(c.a) * a, 0, 255))}
}

LevelCanvas_Render :: proc(state: ^EditorState) {
	L := &GlobalLevel
	imgui.PushStyleVarImVec2(.WindowPadding, {0, 0})
	defer imgui.PopStyleVar()
	defer imgui.End()
	if !imgui.Begin(LEVEL_CANVAS_WINDOW, nil, {.NoScrollbar, .NoScrollWithMouse}) do return
	driveNoScroll = true
	defer driveNoScroll = false
	LevelRef_Panel(LEVEL_TOOL_INFO[GlobalLevel.tool].topic) // F1 over the canvas: the current tool
	avail := imgui.GetContentRegionAvail()
	w := i32(max(avail.x, 64))
	h := i32(max(avail.y, 64))
	if L.rt.id == 0 || L.rt.texture.width != w || L.rt.texture.height != h {
		if L.rt.id != 0 do rl.UnloadRenderTexture(L.rt)
		L.rt = rl.LoadRenderTexture(w, h)
	}
	cursor := imgui.GetCursorScreenPos()
	L.canvasMin = {cursor.x, cursor.y}
	L.canvasSize = {f32(w), f32(h)}
	if L.fitRequest {
		L.fitRequest = false
		fit_level()
	}
	canvas_draw()
	imgui.Image(transmute(imgui.TextureID)&L.rt.texture, {f32(w), f32(h)}, {0, 1}, {1, 0})
	Drive_Item("level.canvas")
	L.hovered = imgui.IsItemHovered()
	doc := L.doc
	if doc != nil && len(doc.levels) > 0 {
		// drive anchor: the active level's top-left corner (+ the layer offset)
		lp := e.Ldtk_Doc_LevelPos(doc, L.level)
		o := [2]f32{f32(lp.x), f32(lp.y)}
		if ly, _ := level_active_layer(); ly != nil {
			off := e.Ldtk_Doc_LayerOffset(ly)
			o += {f32(off.x), f32(off.y)}
		}
		so := to_screen(o)
		Drive_ItemRect("level.origin", so, so + 1, true)
		canvas_input(state)
		canvas_overlay()
	}
}

// ----------------------------------------------------------------------------
// Drawing
// ----------------------------------------------------------------------------

@(private = "file")
canvas_draw :: proc() {
	L := &GlobalLevel
	doc := L.doc
	rl.BeginTextureMode(L.rt)
	defer rl.EndTextureMode()
	bg := doc != nil ? e.Ldtk_ParseHexColor(e.LdtkJson_Str(doc.root, "bgColor", "#40465B")) : rl.Color{23, 26, 33, 255}
	rl.ClearBackground(bg)
	if doc == nil || len(doc.levels) == 0 do return
	cam := rl.Camera2D{offset = L.canvasSize * 0.5, target = L.cam, zoom = L.zoom}
	rl.BeginMode2D(cam)
	// levels of the world, by depth (the active one last at its depth)
	order := make([dynamic]int, context.temp_allocator)
	for &lv, i in doc.levels do if lv.world == L.world do append(&order, i)
	for i in 1 ..< len(order) {
		for j := i; j > 0; j -= 1 {
			a, b := order[j - 1], order[j]
			da := e.LdtkJson_Int(doc.levels[a].obj, "worldDepth")
			db := e.LdtkJson_Int(doc.levels[b].obj, "worldDepth")
			if da > db || (da == db && a == L.level) {
				order[j - 1], order[j] = b, a
			} else do break
		}
	}
	for li in order do draw_level(li, li == L.level)
	draw_selection()
	draw_tool_preview()
	rl.EndMode2D()
}

@(private = "file")
draw_level :: proc(li: int, active: bool) {
	L := &GlobalLevel
	doc := L.doc
	lv := &doc.levels[li]
	p := e.Ldtk_Doc_LevelPos(doc, li)
	s := e.Ldtk_Doc_LevelSize(doc, li)
	origin := [2]f32{f32(p.x), f32(p.y)}
	bg := e.Ldtk_ParseHexColor(e.LdtkJson_Str(lv.obj, "__bgColor", e.LdtkJson_Str(doc.root, "defaultLevelBgColor", "#696A79")))
	rl.DrawRectangleV(origin, {f32(s.x), f32(s.y)}, bg)
	// layers: index 0 is the top one
	#reverse for &ly, i in lv.layers {
		if !e.LdtkJson_Bool(ly.obj, "visible", true) do continue
		draw_layer(li, i, &ly, origin, active && i == L.layer)
	}
	if !active {
		rl.DrawRectangleV(origin, {f32(s.x), f32(s.y)}, {0, 0, 0, 90})
	}
	thick := 1 / L.zoom
	rl.DrawRectangleLinesEx({origin.x, origin.y, f32(s.x), f32(s.y)}, (active ? 2 : 1) * thick, active ? rl.Color{255, 255, 255, 200} : rl.Color{0, 0, 0, 120})
}

@(private = "file")
draw_layer :: proc(li, layer: int, ly: ^e.Ldtk_DocLayer, origin: [2]f32, isActive: bool) {
	L := &GlobalLevel
	doc := L.doc
	d := e.Ldtk_Doc_LayerDef(doc, ly)
	if d == nil do return
	off := e.Ldtk_Doc_LayerOffset(ly)
	o := origin + {f32(off.x), f32(off.y)}
	opacity := d.opacity
	ts := e.Ldtk_Doc_LayerTileset(doc, ly)
	if ts != nil {
		if tex, ok := level_texture(ts.uid); ok {
			gs := f32(ts.gridSize)
			draw :: proc(tex: rl.Texture2D, ts: ^e.Ldtk_DocTileset, t: e.Ldtk_DocTile, o: [2]f32, gs: f32, opacity: f32) {
				src := rl.Rectangle{f32(t.src.x), f32(t.src.y), gs, gs}
				if anim, ok := ts.anims[t.t]; ok {
					p := e.Ldtk_Doc_TileSrc(ts, int(e.Ldtk_TileAnimFrame(anim, rl.GetTime())))
					src.x, src.y = f32(p.x), f32(p.y)
				}
				if (t.f & 1) != 0 do src.width = -gs
				if (t.f & 2) != 0 do src.height = -gs
				dst := rl.Rectangle{o.x + f32(t.px.x), o.y + f32(t.px.y), gs, gs}
				rl.DrawTexturePro(tex, src, dst, {}, 0, {255, 255, 255, u8(clamp(f32(t.a) * opacity * 255, 0, 255))})
			}
			for t in ly.autoTiles do draw(tex, ts, t, o, gs, opacity)
			for t in ly.gridTiles do draw(tex, ts, t, o, gs, opacity)
		}
	}
	if d.type == .IntGrid {
		// values: full colour without a tileset, faint over the active layer's auto tiles
		alpha: f32 = ts == nil ? opacity : (isActive && L.showIntGrid ? 0.35 : 0)
		if alpha > 0 {
			g := f32(d.gridSize)
			for cy in 0 ..< ly.cHei {
				for cx in 0 ..< ly.cWid {
					v := ly.intGrid[cx + cy * ly.cWid]
					if v == 0 do continue
					iv := e.Ldtk_Doc_IntValue(d, int(v))
					c := iv != nil ? iv.color : rl.MAGENTA
					rl.DrawRectangleV(o + {f32(cx) * g, f32(cy) * g}, {g, g}, col_rl(c, alpha))
				}
			}
		}
	}
	if d.type == .Entities {
		for ent in e.LdtkJson_Arr(ly.obj, "entityInstances") {
			r := e.Ldtk_Doc_EntityRect(ent)
			rect := rl.Rectangle{o.x + f32(r[0]), o.y + f32(r[1]), f32(r[2]), f32(r[3])}
			ed := e.Ldtk_Doc_EntityDef(doc, e.LdtkJson_Int(ent, "defUid", -1))
			c := ed != nil ? ed.color : rl.Color{148, 217, 179, 255}
			drewTile := false
			if ed != nil && ed.tileRect[2] > 0 {
				if tex, ok := level_texture(ed.tilesetUid); ok {
					src := rl.Rectangle{f32(ed.tileRect[0]), f32(ed.tileRect[1]), f32(ed.tileRect[2]), f32(ed.tileRect[3])}
					// fit inside, keeping the aspect
					sc := min(rect.width / src.width, rect.height / src.height)
					dw, dh := src.width * sc, src.height * sc
					rl.DrawTexturePro(tex, src, {rect.x + (rect.width - dw) * 0.5, rect.y + (rect.height - dh) * 0.5, dw, dh}, {}, 0, rl.WHITE)
					drewTile = true
				}
			}
			if !drewTile do rl.DrawRectangleRec(rect, col_rl(c, 0.35))
			rl.DrawRectangleLinesEx(rect, 1 / L.zoom, ent == L.selEntity ? rl.Color{255, 220, 80, 255} : c)
		}
	}
	if isActive && L.showGrid && d.type != .Entities {
		g := f32(d.gridSize)
		lc := rl.Color{255, 255, 255, 22}
		if L.zoom * g >= 6 {
			for cx in 0 ..= ly.cWid do rl.DrawLineV(o + {f32(cx) * g, 0}, o + {f32(cx) * g, f32(ly.cHei) * g}, lc)
			for cy in 0 ..= ly.cHei do rl.DrawLineV(o + {0, f32(cy) * g}, o + {f32(ly.cWid) * g, f32(cy) * g}, lc)
		}
	}
}

// layer_origin: world position of the active layer's cell (0, 0).
@(private = "file")
layer_origin :: proc() -> [2]f32 {
	L := &GlobalLevel
	lp := e.Ldtk_Doc_LevelPos(L.doc, L.level)
	o := [2]f32{f32(lp.x), f32(lp.y)}
	if ly, _ := level_active_layer(); ly != nil {
		off := e.Ldtk_Doc_LayerOffset(ly)
		o += {f32(off.x), f32(off.y)}
	}
	return o
}

@(private = "file")
mouse_cell :: proc() -> ([2]int, bool) {
	L := &GlobalLevel
	ly, d := level_active_layer()
	if ly == nil || d == nil do return {}, false
	m := imgui.GetIO().MousePos
	local := to_world({m.x, m.y}) - layer_origin()
	g := f32(d.gridSize)
	c := [2]int{int(math.floor(local.x / g)), int(math.floor(local.y / g))}
	return c, c.x >= 0 && c.y >= 0 && c.x < ly.cWid && c.y < ly.cHei
}

@(private = "file")
draw_tool_preview :: proc() {
	L := &GlobalLevel
	if !L.hovered && !L.rectActive do return
	ly, d := level_active_layer()
	if ly == nil || d == nil || d.type == .Entities || d.type == .AutoLayer do return
	if L.tool == .Select || L.tool == .Move_Level do return
	g := f32(d.gridSize)
	o := layer_origin()
	c, _ := mouse_cell()
	thick := 1.5 / L.zoom
	col := L.tool == .Erase ? rl.Color{240, 90, 90, 230} : rl.Color{255, 220, 80, 230}
	if L.rectActive {
		a, b := L.rectStart, c
		mn := [2]int{min(a.x, b.x), min(a.y, b.y)}
		mx := [2]int{max(a.x, b.x), max(a.y, b.y)}
		if L.paintErase do col = {240, 90, 90, 230}
		rl.DrawRectangleLinesEx({o.x + f32(mn.x) * g, o.y + f32(mn.y) * g, f32(mx.x - mn.x + 1) * g, f32(mx.y - mn.y + 1) * g}, thick, col)
		return
	}
	w, h := 1, 1
	if d.type == .Tiles && L.tool == .Brush && len(L.tileSel) > 0 {
		// ghost of the stamp (random mode: the first tile)
		ts := e.Ldtk_Doc_LayerTileset(L.doc, ly)
		stamp, sw, sh := level_stamp(ts)
		if !L.tileRandom do w, h = sw, sh
		if ts != nil {
			if tex, ok := level_texture(ts.uid); ok {
				gs := f32(ts.gridSize)
				for st, k in stamp {
					if L.tileRandom && k > 0 do break
					src := e.Ldtk_Doc_TileSrc(ts, int(st.tid))
					p := L.tileRandom ? [2]int{} : st.d
					sr := rl.Rectangle{f32(src.x), f32(src.y), gs, gs}
					if (L.flips & 1) != 0 do sr.width = -gs
					if (L.flips & 2) != 0 do sr.height = -gs
					rl.DrawTexturePro(tex, sr, {o.x + f32(c.x + p.x) * g, o.y + f32(c.y + p.y) * g, gs, gs}, {}, 0, {255, 255, 255, 150})
				}
			}
		}
	}
	rl.DrawRectangleLinesEx({o.x + f32(c.x) * g, o.y + f32(c.y) * g, f32(w) * g, f32(h) * g}, thick, col)
}

// canvas_overlay: level names and the status line (screen space).
@(private = "file")
canvas_overlay :: proc() {
	L := &GlobalLevel
	doc := L.doc
	dl := imgui.GetWindowDrawList()
	for &lv, i in doc.levels {
		if lv.world != L.world do continue
		p := e.Ldtk_Doc_LevelPos(doc, i)
		sp := to_screen({f32(p.x), f32(p.y)})
		name := e.LdtkJson_Str(lv.obj, "identifier")
		imgui.DrawList_AddText(dl, {sp.x + 2, sp.y - 18}, col_u32(i == L.level ? UI_TEXT : UI_TEXT_DIM), fmt.ctprintf("%s", name))
	}
	if L.selEntity != nil {
		// resize handle
		if r, ok := selected_rect_screen(); ok && entity_resizable(L.selEntity) {
			imgui.DrawList_AddRectFilled(dl, {r[2] - 4, r[3] - 4}, {r[2] + 4, r[3] + 4}, col_u32(UI_WARNING), 1, {})
		}
	}
	ly, d := level_active_layer()
	status := fmt.tprintf("%s  %s", e.Ldtk_Doc_LevelName(doc, L.level), d != nil ? d.identifier : "")
	if c, inside := mouse_cell(); inside && L.hovered && ly != nil && d != nil {
		status = fmt.tprintf("%s   cell %d,%d", status, c.x, c.y)
		if d.type == .IntGrid {
			v := e.Ldtk_Doc_GetIntGrid(ly, c.x, c.y)
			iv := e.Ldtk_Doc_IntValue(d, v)
			status = fmt.tprintf("%s   value %d%s", status, v, iv != nil && iv.identifier != "" ? fmt.tprintf(" (%s)", iv.identifier) : "")
		}
	}
	if d != nil && d.type == .AutoLayer do status = fmt.tprintf("%s   (auto layer: paint its source IntGrid layer)", status)
	h := imgui.GetTextLineHeight()
	pos := [2]f32{L.canvasMin.x + 8, L.canvasMin.y + L.canvasSize.y - h - 8}
	tw := imgui.CalcTextSize(fmt.ctprintf("%s", status)).x
	imgui.DrawList_AddRectFilled(dl, {pos.x - 4, pos.y - 2}, {pos.x + tw + 4, pos.y + h + 2}, col_u32({0, 0, 0, 0.55}), 3, {})
	imgui.DrawList_AddText(dl, pos, col_u32(UI_TEXT), fmt.ctprintf("%s", status))
}

@(private = "file")
entity_resizable :: proc(ent: ^e.LdtkJson) -> bool {
	ed := e.Ldtk_Doc_EntityDef(GlobalLevel.doc, e.LdtkJson_Int(ent, "defUid", -1))
	return ed != nil && (e.LdtkJson_Bool(ed.obj, "resizableX") || e.LdtkJson_Bool(ed.obj, "resizableY"))
}

// selected_rect_screen: the selected entity's box on screen (x0, y0, x1, y1).
@(private = "file")
selected_rect_screen :: proc() -> ([4]f32, bool) {
	L := &GlobalLevel
	if L.selEntity == nil do return {}, false
	r := e.Ldtk_Doc_EntityRect(L.selEntity)
	o := layer_origin_of(L.selEntityLayer)
	a := to_screen(o + {f32(r[0]), f32(r[1])})
	b := to_screen(o + {f32(r[0] + r[2]), f32(r[1] + r[3])})
	return {a.x, a.y, b.x, b.y}, true
}

// ----------------------------------------------------------------------------
// Input
// ----------------------------------------------------------------------------

@(private = "file")
canvas_input :: proc(state: ^EditorState) {
	L := &GlobalLevel
	doc := L.doc
	io := imgui.GetIO()
	mouse := [2]f32{io.MousePos.x, io.MousePos.y}
	mw := to_world(mouse)
	// zoom around the mouse
	if L.hovered && io.MouseWheel != 0 {
		before := mw
		LevelCanvas_SetZoom(L.zoom * (1 + io.MouseWheel * 0.15))
		L.cam += before - to_world(mouse)
	}
	// pan: middle drag, or Space + left drag
	if L.hovered && (imgui.IsMouseClicked(.Middle) || (imgui.IsKeyDown(.Space) && imgui.IsMouseClicked(.Left))) do L.panning = true
	if L.panning {
		L.cam -= [2]f32{io.MouseDelta.x, io.MouseDelta.y} / L.zoom
		if !imgui.IsMouseDown(.Middle) && !imgui.IsMouseDown(.Left) do L.panning = false
		return
	}
	ly, d := level_active_layer()
	pressL := L.hovered && imgui.IsMouseClicked(.Left)
	pressR := L.hovered && imgui.IsMouseClicked(.Right)
	// move levels
	if L.tool == .Move_Level {
		if pressL {
			li := e.Ldtk_Doc_LevelAt(doc, L.world, {int(math.floor(mw.x)), int(math.floor(mw.y))})
			if li >= 0 {
				LevelEditor_SetLevel(li)
				p := e.Ldtk_Doc_LevelPos(doc, li)
				L.levelGrab = {int(mw.x) - p.x, int(mw.y) - p.y}
				L.levelDrag, L.levelMoved = true, false
			}
		}
		if L.levelDrag {
			snap := level_snap()
			np := [2]int{int(mw.x) - L.levelGrab.x, int(mw.y) - L.levelGrab.y}
			np = {int(math.round(f32(np.x) / f32(snap.x))) * snap.x, int(math.round(f32(np.y) / f32(snap.y))) * snap.y}
			if np != e.Ldtk_Doc_LevelPos(doc, L.level) {
				if !L.levelMoved do e.Ldtk_Doc_Checkpoint(doc, L.level, "Move Level")
				L.levelMoved = true
				e.Ldtk_Doc_MoveLevel(doc, L.level, np)
			}
			if !imgui.IsMouseDown(.Left) do L.levelDrag = false
		}
		return
	}
	// a click in another level makes it active
	if (pressL || pressR) && !L.painting {
		li := e.Ldtk_Doc_LevelAt(doc, L.world, {int(math.floor(mw.x)), int(math.floor(mw.y))})
		if li >= 0 && li != L.level {
			LevelEditor_SetLevel(li)
			return
		}
	}
	if !L.painting && selection_input(state, pressL, mw) do return
	if ly == nil || d == nil do return
	if L.tool == .Select do return
	switch d.type {
	case .IntGrid, .Tiles: cells_input(state, ly, d, pressL, pressR)
	case .Entities: entities_input(state, ly, d, pressL, pressR, mw)
	case .AutoLayer:
	}
}

// level_snap: the step levels move by (the world grid in GridVania).
@(private = "file")
level_snap :: proc() -> [2]int {
	doc := GlobalLevel.doc
	if LdtkJson_GridVania(doc) do return {max(e.LdtkJson_Int(doc.root, "worldGridWidth", 256), 1), max(e.LdtkJson_Int(doc.root, "worldGridHeight", 256), 1)}
	g := max(e.LdtkJson_Int(doc.root, "defaultGridSize", 16), 1)
	return {g, g}
}

// paint_cell applies the tool at one cell (inside a stroke).
@(private = "file")
paint_cell :: proc(ly: ^e.Ldtk_DocLayer, d: ^e.Ldtk_DocLayerDef, c: [2]int, erase: bool) {
	L := &GlobalLevel
	doc := L.doc
	if d.type == .IntGrid {
		v := erase ? 0 : L.intValue
		if e.Ldtk_Doc_SetIntGrid(doc, L.level, L.layer, c.x, c.y, v) do e.Ldtk_Doc_ApplyRules(doc, L.level, L.layer, c.x, c.y, c.x, c.y)
		return
	}
	// tiles: the stamp anchored at c, or one random tile of the selection
	if erase || len(L.tileSel) == 0 {
		if erase_tile(c) do e.Ldtk_Doc_ApplyRules(doc, L.level, L.layer, c.x, c.y, c.x, c.y)
		return
	}
	if L.tileRandom {
		if e.Ldtk_Doc_AddGridTile(doc, L.level, L.layer, c.x, c.y, random_tile(), L.flips, L.stacking) do e.Ldtk_Doc_ApplyRules(doc, L.level, L.layer, c.x, c.y, c.x, c.y)
		return
	}
	stamp, w, h := level_stamp(e.Ldtk_Doc_LayerTileset(doc, ly))
	for st in stamp do e.Ldtk_Doc_AddGridTile(doc, L.level, L.layer, c.x + st.d.x, c.y + st.d.y, int(st.tid), L.flips, L.stacking)
	e.Ldtk_Doc_ApplyRules(doc, L.level, L.layer, c.x, c.y, c.x + w - 1, c.y + h - 1)
}

// erase_tile: the whole cell, or with stacking its top tile.
@(private = "file")
erase_tile :: proc(c: [2]int) -> bool {
	L := &GlobalLevel
	if L.stacking do return e.Ldtk_Doc_RemoveTopTile(L.doc, L.level, L.layer, c.x, c.y)
	return e.Ldtk_Doc_SetTile(L.doc, L.level, L.layer, c.x, c.y, -1)
}

@(private = "file")
random_tile :: proc() -> int {
	L := &GlobalLevel
	if len(L.tileSel) == 0 do return -1
	return int(L.tileSel[rand.int_max(len(L.tileSel))])
}

// put_tile: one cell of a rectangle / fill (random mode: a random tile; a
// stamp's hole: nothing).
@(private = "file")
put_tile :: proc(x, y: int, anchor: [2]int, erase: bool) {
	L := &GlobalLevel
	if erase {
		erase_tile({x, y})
		return
	}
	tid := L.tileRandom ? random_tile() : tile_for({x, y}, anchor)
	if tid >= 0 do e.Ldtk_Doc_AddGridTile(L.doc, L.level, L.layer, x, y, tid, L.flips, L.stacking)
}

// tile_for: the stamp's tile repeating over a rectangle / fill.
@(private = "file")
tile_for :: proc(c, anchor: [2]int) -> int {
	L := &GlobalLevel
	if len(L.tileSel) == 0 do return -1
	ly, _ := level_active_layer()
	stamp, w, h := level_stamp(ly != nil ? e.Ldtk_Doc_LayerTileset(L.doc, ly) : nil)
	i := ((c.x - anchor.x) % w + w) % w
	j := ((c.y - anchor.y) % h + h) % h
	for st in stamp do if st.d == {i, j} do return int(st.tid)
	return -1
}

@(private = "file")
cells_input :: proc(state: ^EditorState, ly: ^e.Ldtk_DocLayer, d: ^e.Ldtk_DocLayerDef, pressL, pressR: bool) {
	L := &GlobalLevel
	doc := L.doc
	c, inside := mouse_cell()
	if (pressL || pressR) && L.tool == .Pick {
		if inside do pick_at(ly, d, c)
		return
	}
	if (pressL || pressR) && inside && !L.painting {
		L.paintErase = pressR || L.tool == .Erase
		tool := L.tool
		if (tool == .Brush || tool == .Erase) && imgui.GetIO().KeyShift do tool = .Rect // LDtk: Shift + drag = rectangle
		switch tool {
		case .Brush, .Erase:
			e.Ldtk_Doc_BeginCells(doc, L.level, L.layer, "Paint")
			L.painting = true
			L.lastCell = c
			paint_cell(ly, d, c, L.paintErase)
		case .Rect:
			e.Ldtk_Doc_BeginCells(doc, L.level, L.layer, "Rectangle")
			L.painting, L.rectActive = true, true
			L.rectStart = c
		case .Fill:
			e.Ldtk_Doc_BeginCells(doc, L.level, L.layer, "Fill")
			flood_fill(ly, d, c, L.paintErase)
			e.Ldtk_Doc_EndCells(doc)
		case .Pick, .Select, .Move_Level:
		}
		return
	}
	if !L.painting do return
	down := imgui.IsMouseDown(.Left) || imgui.IsMouseDown(.Right)
	if (L.tool == .Brush || L.tool == .Erase) && c != L.lastCell {
		// every cell on the line from the last one (fast strokes leave no gaps)
		a, b := L.lastCell, c
		dx, dy := abs(b.x - a.x), -abs(b.y - a.y)
		sx := a.x < b.x ? 1 : -1
		sy := a.y < b.y ? 1 : -1
		err := dx + dy
		p := a
		for {
			if p != a do paint_cell(ly, d, p, L.paintErase)
			if p == b do break
			e2 := 2 * err
			if e2 >= dy {
				err += dy
				p.x += sx
			}
			if e2 <= dx {
				err += dx
				p.y += sy
			}
		}
		L.lastCell = c
	}
	if !down {
		if L.rectActive {
			a := L.rectStart
			b := [2]int{clamp(c.x, 0, ly.cWid - 1), clamp(c.y, 0, ly.cHei - 1)}
			mn := [2]int{min(a.x, b.x), min(a.y, b.y)}
			mx := [2]int{max(a.x, b.x), max(a.y, b.y)}
			for y in mn.y ..= mx.y {
				for x in mn.x ..= mx.x {
					if d.type == .IntGrid {
						e.Ldtk_Doc_SetIntGrid(doc, L.level, L.layer, x, y, L.paintErase ? 0 : L.intValue)
					} else {
						put_tile(x, y, mn, L.paintErase)
					}
				}
			}
			e.Ldtk_Doc_ApplyRules(doc, L.level, L.layer, mn.x, mn.y, mx.x, mx.y)
			L.rectActive = false
		}
		e.Ldtk_Doc_EndCells(doc)
		L.painting = false
	}
}

@(private = "file")
pick_at :: proc(ly: ^e.Ldtk_DocLayer, d: ^e.Ldtk_DocLayerDef, c: [2]int) {
	L := &GlobalLevel
	if d.type == .IntGrid {
		if v := e.Ldtk_Doc_GetIntGrid(ly, c.x, c.y); v != 0 do L.intValue = v
		return
	}
	tiles := e.Ldtk_Doc_TilesAt(ly, c.x, c.y)
	if len(tiles) == 0 do return
	t := tiles[len(tiles) - 1]
	level_set_tile_sel({t.t})
	L.flips = t.f
	L.tool = .Brush
}

// flood_fill fills the 4-connected area of equal cells (IntGrid value, or
// top tile) from c.
@(private = "file")
flood_fill :: proc(ly: ^e.Ldtk_DocLayer, d: ^e.Ldtk_DocLayerDef, start: [2]int, erase: bool) {
	L := &GlobalLevel
	doc := L.doc
	key :: proc(ly: ^e.Ldtk_DocLayer, d: ^e.Ldtk_DocLayerDef, c: [2]int) -> int {
		if d.type == .IntGrid do return e.Ldtk_Doc_GetIntGrid(ly, c.x, c.y)
		tiles := e.Ldtk_Doc_TilesAt(ly, c.x, c.y)
		return len(tiles) > 0 ? int(tiles[len(tiles) - 1].t) : -1
	}
	target := key(ly, d, start)
	if d.type == .IntGrid && target == (erase ? 0 : L.intValue) do return
	seen := make([]bool, ly.cWid * ly.cHei, context.temp_allocator)
	stack := make([dynamic][2]int, context.temp_allocator)
	append(&stack, start)
	mn, mx := start, start
	for len(stack) > 0 {
		c := pop(&stack)
		if c.x < 0 || c.y < 0 || c.x >= ly.cWid || c.y >= ly.cHei do continue
		i := c.x + c.y * ly.cWid
		if seen[i] || key(ly, d, c) != target do continue
		seen[i] = true
		mn = {min(mn.x, c.x), min(mn.y, c.y)}
		mx = {max(mx.x, c.x), max(mx.y, c.y)}
		append(&stack, [2]int{c.x + 1, c.y}, [2]int{c.x - 1, c.y}, [2]int{c.x, c.y + 1}, [2]int{c.x, c.y - 1})
	}
	for y in mn.y ..= mx.y {
		for x in mn.x ..= mx.x {
			if !seen[x + y * ly.cWid] do continue
			if d.type == .IntGrid {
				e.Ldtk_Doc_SetIntGrid(doc, L.level, L.layer, x, y, erase ? 0 : L.intValue)
			} else {
				put_tile(x, y, start, erase)
			}
		}
	}
	e.Ldtk_Doc_ApplyRules(doc, L.level, L.layer, mn.x, mn.y, mx.x, mx.y)
}

// entities_input: the Brush places the picked entity (Shift: off the grid);
// the right button deletes the entity under the mouse. Selecting, moving and
// resizing are selection_input's.
@(private = "file")
entities_input :: proc(state: ^EditorState, ly: ^e.Ldtk_DocLayer, d: ^e.Ldtk_DocLayerDef, pressL, pressR: bool, mw: [2]f32) {
	L := &GlobalLevel
	doc := L.doc
	o := layer_origin()
	local := mw - o
	lp := [2]int{int(math.floor(local.x)), int(math.floor(local.y))}
	g := d.gridSize
	if pressR {
		if ent := e.Ldtk_Doc_EntityAt(doc, L.level, L.layer, lp); ent != nil {
			e.Ldtk_Doc_Checkpoint(doc, L.level, "Delete Entity")
			e.Ldtk_Doc_RemoveEntity(doc, L.level, L.layer, ent)
			level_sync_selection()
		}
		return
	}
	if pressL && L.tool == .Brush && L.entityDef >= 0 && lp.x >= 0 && lp.y >= 0 && lp.x < ly.cWid * g && lp.y < ly.cHei * g {
		ed := e.Ldtk_Doc_EntityDef(doc, L.entityDef)
		if ed == nil do return
		cell := [2]int{lp.x / g, lp.y / g}
		px := [2]int{cell.x * g + int(ed.pivot.x * f64(g)), cell.y * g + int(ed.pivot.y * f64(g))}
		if imgui.GetIO().KeyShift do px = lp
		e.Ldtk_Doc_Checkpoint(doc, L.level, "Add Entity")
		level_select_entity(L.layer, e.Ldtk_Doc_AddEntity(doc, L.level, L.layer, L.entityDef, px))
	}
}

// ----------------------------------------------------------------------------
// Selection (LDtk's Selection tool: the Select tool, or Alt with any tool)
// ----------------------------------------------------------------------------

// layer_origin_of: world position of a layer's cell (0, 0) in the level.
@(private = "file")
layer_origin_of :: proc(layer: int) -> [2]f32 {
	L := &GlobalLevel
	lp := e.Ldtk_Doc_LevelPos(L.doc, L.level)
	o := [2]f32{f32(lp.x), f32(lp.y)}
	lv := &L.doc.levels[L.level]
	if layer >= 0 && layer < len(lv.layers) {
		off := e.Ldtk_Doc_LayerOffset(&lv.layers[layer])
		o += {f32(off.x), f32(off.y)}
	}
	return o
}

// element_at: the entity or the cell with a value under a world position -
// the active layer first, then the others from the top (visible ones).
@(private = "file")
element_at :: proc(mw: [2]f32) -> (cell: e.Ldtk_SelCell, ent: e.Ldtk_SelEntity, found: bool) {
	L := &GlobalLevel
	doc := L.doc
	lv := &doc.levels[L.level]
	try :: proc(doc: ^e.Ldtk_Doc, li, j: int, mw: [2]f32) -> (e.Ldtk_SelCell, e.Ldtk_SelEntity, bool) {
		ly := &doc.levels[li].layers[j]
		if !e.LdtkJson_Bool(ly.obj, "visible", true) do return {}, {}, false
		d := e.Ldtk_Doc_LayerDef(doc, ly)
		if d == nil do return {}, {}, false
		o := layer_origin_of(j)
		lp := [2]int{int(math.floor(mw.x - o.x)), int(math.floor(mw.y - o.y))}
		#partial switch d.type {
		case .Entities:
			if ent := e.Ldtk_Doc_EntityAt(doc, li, j, lp); ent != nil do return {}, {j, ent}, true
		case .IntGrid:
			c := [2]int{ldtk_floor(lp.x, d.gridSize), ldtk_floor(lp.y, d.gridSize)}
			if e.Ldtk_Doc_GetIntGrid(ly, c.x, c.y) != 0 do return {j, c.x, c.y}, {}, true
		case .Tiles:
			c := [2]int{ldtk_floor(lp.x, d.gridSize), ldtk_floor(lp.y, d.gridSize)}
			if len(e.Ldtk_Doc_TilesAt(ly, c.x, c.y)) > 0 do return {j, c.x, c.y}, {}, true
		}
		return {}, {}, false
	}
	if L.layer < len(lv.layers) {
		if c, en, ok := try(doc, L.level, L.layer, mw); ok do return c, en, true
	}
	for _, j in lv.layers {
		if j == L.layer do continue
		if c, en, ok := try(doc, L.level, j, mw); ok do return c, en, true
	}
	return {}, {}, false
}

@(private = "file")
ldtk_floor :: proc(a, b: int) -> int {
	if b == 0 do return 0
	q := a / b
	if a % b != 0 && (a < 0) != (b < 0) do q -= 1
	return q
}

// over_selection: is a world position on a selected cell or entity?
@(private = "file")
over_selection :: proc(mw: [2]f32) -> bool {
	L := &GlobalLevel
	doc := L.doc
	lv := &doc.levels[L.level]
	for c in L.sel.cells {
		d := e.Ldtk_Doc_LayerDef(doc, &lv.layers[c.layer])
		if d == nil do continue
		o := layer_origin_of(c.layer)
		g := f32(d.gridSize)
		x, y := o.x + f32(c.cx) * g, o.y + f32(c.cy) * g
		if mw.x >= x && mw.y >= y && mw.x < x + g && mw.y < y + g do return true
	}
	for se in L.sel.entities {
		o := layer_origin_of(se.layer)
		r := e.Ldtk_Doc_EntityRect(se.obj)
		if mw.x >= o.x + f32(r[0]) && mw.y >= o.y + f32(r[1]) && mw.x < o.x + f32(r[0] + r[2]) && mw.y < o.y + f32(r[1] + r[3]) do return true
	}
	return false
}

// sel_delta: the drag's offset, snapped (entities alone with Shift: free).
@(private = "file")
sel_delta :: proc(mw: [2]f32) -> [2]int {
	L := &GlobalLevel
	raw := mw - L.selGrab
	g := 16
	if _, d := level_active_layer(); d != nil do g = d.gridSize
	// the cells' coarsest grid decides the step
	for c in L.sel.cells {
		if d := e.Ldtk_Doc_LayerDef(L.doc, &L.doc.levels[L.level].layers[c.layer]); d != nil do g = max(g, d.gridSize)
	}
	if len(L.sel.cells) == 0 && imgui.GetIO().KeyShift do return {int(math.round(raw.x)), int(math.round(raw.y))}
	return {int(math.round(raw.x / f32(g))) * g, int(math.round(raw.y / f32(g))) * g}
}

// LevelCanvas_PasteAt: where Cmd+V puts the clipboard's top-left - the cell
// under the mouse (the clip's place when the mouse is off the canvas).
LevelCanvas_PasteAt :: proc() -> [2]int {
	L := &GlobalLevel
	if !L.hovered do return L.clip.origin
	m := imgui.GetIO().MousePos
	lp := e.Ldtk_Doc_LevelPos(L.doc, L.level)
	w := to_world({m.x, m.y}) - {f32(lp.x), f32(lp.y)}
	g := 16
	if _, d := level_active_layer(); d != nil do g = d.gridSize
	return {ldtk_floor(int(w.x), g) * g, ldtk_floor(int(w.y), g) * g}
}

// selection_input runs the selection gestures; returns true when it took
// the mouse this frame (painting tools then don't).
@(private = "file")
selection_input :: proc(state: ^EditorState, pressL: bool, mw: [2]f32) -> bool {
	L := &GlobalLevel
	doc := L.doc
	io := imgui.GetIO()
	selectMode := L.tool == .Select || io.KeyAlt
	// resizing the single selected entity (its corner handle)
	if L.entResize {
		ent := L.selEntity
		if ent == nil {
			L.entResize = false
			return true
		}
		ed := e.Ldtk_Doc_EntityDef(doc, e.LdtkJson_Int(ent, "defUid", -1))
		ld := e.Ldtk_Doc_LayerDef(doc, &doc.levels[L.level].layers[L.selEntityLayer])
		g := ld != nil ? ld.gridSize : 16
		o := layer_origin_of(L.selEntityLayer)
		lp := [2]int{int(math.floor(mw.x - o.x)), int(math.floor(mw.y - o.y))}
		r := e.Ldtk_Doc_EntityRect(ent)
		size := [2]int{lp.x - r[0], lp.y - r[1]}
		if !io.KeyShift do size = {max(int(math.round(f32(size.x) / f32(g))), 1) * g, max(int(math.round(f32(size.y) / f32(g))), 1) * g}
		if ed != nil {
			if !e.LdtkJson_Bool(ed.obj, "resizableX") do size.x = r[2]
			if !e.LdtkJson_Bool(ed.obj, "resizableY") do size.y = r[3]
		}
		size = {max(size.x, 1), max(size.y, 1)}
		if size.x != r[2] || size.y != r[3] {
			if !L.entMoved do e.Ldtk_Doc_Checkpoint(doc, L.level, "Resize Entity")
			L.entMoved = true
			e.Ldtk_Doc_ResizeEntity(doc, L.level, L.selEntityLayer, ent, size)
		}
		if !imgui.IsMouseDown(.Left) do L.entResize = false
		return true
	}
	// dragging the selection: a ghost follows, the move happens on release
	if L.selMoving {
		if !L.selMoved && linalg_len(mw - L.selGrab) * L.zoom >= 4 do L.selMoved = true
		if !imgui.IsMouseDown(.Left) {
			L.selMoving = false
			if L.selMoved {
				delta := sel_delta(mw)
				if delta != {} || L.selCopy {
					if e.Ldtk_Doc_SelectionCanMove(doc, L.level, &L.sel, delta) {
						e.Ldtk_Doc_Checkpoint(doc, L.level, L.selCopy ? "Copy Selection" : "Move Selection")
						e.Ldtk_Doc_MoveSelection(doc, L.level, &L.sel, delta, L.selCopy)
						level_sync_selection()
					} else do Editor_Log(state, .Warn, "The selection can't move by %d,%d px: its layers' grids don't line up", delta.x, delta.y)
				}
			}
		}
		return true
	}
	// rectangle selection
	if L.selRect {
		if !imgui.IsMouseDown(.Left) {
			L.selRect = false
			lp := e.Ldtk_Doc_LevelPos(doc, L.level)
			a := L.selRectStart - {f32(lp.x), f32(lp.y)}
			b := mw - {f32(lp.x), f32(lp.y)}
			mn := [2]f32{min(a.x, b.x), min(a.y, b.y)}
			mx := [2]f32{max(a.x, b.x), max(a.y, b.y)}
			r := [4]int{int(math.floor(mn.x)), int(math.floor(mn.y)), max(int(mx.x - mn.x), 1), max(int(mx.y - mn.y), 1)}
			e.Ldtk_Doc_SelectRect(doc, L.level, &L.sel, r)
			level_sync_selection()
		}
		return true
	}
	if !pressL do return false
	// the corner handle of a single resizable entity
	if r, ok := selected_rect_screen(); ok && entity_resizable(L.selEntity) {
		m := io.MousePos
		if abs(m.x - r[2]) <= 6 && abs(m.y - r[3]) <= 6 {
			L.entResize, L.entMoved = true, false
			return true
		}
	}
	startMove :: proc(mw: [2]f32) {
		L := &GlobalLevel
		io := imgui.GetIO()
		L.selMoving, L.selMoved = true, false
		L.selGrab = mw
		L.selCopy = (io.KeySuper || io.KeyCtrl) && io.KeyAlt
	}
	// on the selection (any tool): move it
	if !e.Ldtk_Selection_Empty(&L.sel) && over_selection(mw) && !io.KeyShift {
		startMove(mw)
		return true
	}
	cell, ent, found := element_at(mw)
	if !selectMode {
		// with the painting tools, a click on an entity of the active Entities layer selects it
		if _, d := level_active_layer(); d != nil && d.type == .Entities && found && ent.obj != nil && ent.layer == L.layer {
			level_select_entity(ent.layer, ent.obj)
			startMove(mw)
			return true
		}
		return false
	}
	if io.KeyShift {
		// add / remove, or a rectangle from empty space
		if found {
			if ent.obj != nil do e.Ldtk_Selection_ToggleEntity(&L.sel, ent)
			else do e.Ldtk_Selection_ToggleCell(&L.sel, cell)
			level_sync_selection()
		} else {
			L.selRect = true
			L.selRectStart = mw
		}
		return true
	}
	if !found {
		level_clear_selection()
		L.selRect = true // a drag from empty space selects a rectangle
		L.selRectStart = mw
		return true
	}
	// select it; its layer becomes active and the palette picks its value
	level_clear_selection()
	layer := ent.obj != nil ? ent.layer : cell.layer
	if layer != L.layer {
		L.layer = layer
		level_sync_palette()
	}
	if ent.obj != nil {
		level_select_entity(ent.layer, ent.obj)
		if ed := e.Ldtk_Doc_EntityDef(doc, e.LdtkJson_Int(ent.obj, "defUid", -1)); ed != nil do L.entityDef = ed.uid
	} else {
		append(&L.sel.cells, cell)
		ly := &doc.levels[L.level].layers[cell.layer]
		if v := e.Ldtk_Doc_GetIntGrid(ly, cell.cx, cell.cy); v != 0 do L.intValue = v
		if tiles := e.Ldtk_Doc_TilesAt(ly, cell.cx, cell.cy); len(tiles) > 0 {
			level_set_tile_sel({tiles[len(tiles) - 1].t})
			L.flips = tiles[len(tiles) - 1].f
		}
		level_sync_selection()
	}
	startMove(mw)
	return true
}

@(private = "file")
linalg_len :: proc(v: [2]f32) -> f32 {return math.sqrt(v.x * v.x + v.y * v.y)}

// draw_selection: outlines of the selection, the drag ghost, the rectangle.
@(private = "file")
draw_selection :: proc() {
	L := &GlobalLevel
	doc := L.doc
	if doc == nil || len(doc.levels) == 0 do return
	lv := &doc.levels[L.level]
	thick := 1.5 / L.zoom
	col := rl.Color{255, 220, 80, 255}
	off := [2]f32{}
	if L.selMoving && L.selMoved {
		m := imgui.GetIO().MousePos
		dd := sel_delta(to_world({m.x, m.y}))
		off = {f32(dd.x), f32(dd.y)}
	}
	for c in L.sel.cells {
		if c.layer >= len(lv.layers) do continue
		d := e.Ldtk_Doc_LayerDef(doc, &lv.layers[c.layer])
		if d == nil do continue
		o := layer_origin_of(c.layer) + off
		g := f32(d.gridSize)
		r := rl.Rectangle{o.x + f32(c.cx) * g, o.y + f32(c.cy) * g, g, g}
		if off != {} do rl.DrawRectangleRec(r, {255, 220, 80, 70})
		rl.DrawRectangleLinesEx(r, thick, col)
	}
	for se in L.sel.entities {
		o := layer_origin_of(se.layer) + off
		r := e.Ldtk_Doc_EntityRect(se.obj)
		rect := rl.Rectangle{o.x + f32(r[0]), o.y + f32(r[1]), f32(r[2]), f32(r[3])}
		if off != {} do rl.DrawRectangleRec(rect, {255, 220, 80, 70})
		rl.DrawRectangleLinesEx(rect, thick * 1.3, col)
	}
	if L.selRect {
		m := imgui.GetIO().MousePos
		b := to_world({m.x, m.y})
		a := L.selRectStart
		rl.DrawRectangleRec({min(a.x, b.x), min(a.y, b.y), abs(b.x - a.x), abs(b.y - a.y)}, {120, 170, 255, 40})
		rl.DrawRectangleLinesEx({min(a.x, b.x), min(a.y, b.y), abs(b.x - a.x), abs(b.y - a.y)}, thick, {120, 170, 255, 230})
	}
}
