package editor

import "core:fmt"
import "core:math"
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
		w, h = L.tileSelW, L.tileSelH
		// ghost of the stamp
		ts := e.Ldtk_Doc_LayerTileset(L.doc, ly)
		if ts != nil {
			if tex, ok := level_texture(ts.uid); ok {
				gs := f32(ts.gridSize)
				for j in 0 ..< h {
					for i in 0 ..< w {
						tid := int(L.tileSel[i + j * w])
						src := e.Ldtk_Doc_TileSrc(ts, tid)
						x := (L.flips & 1) != 0 ? w - 1 - i : i
						y := (L.flips & 2) != 0 ? h - 1 - j : j
						sr := rl.Rectangle{f32(src.x), f32(src.y), gs, gs}
						if (L.flips & 1) != 0 do sr.width = -gs
						if (L.flips & 2) != 0 do sr.height = -gs
						rl.DrawTexturePro(tex, sr, {o.x + f32(c.x + x) * g, o.y + f32(c.y + y) * g, gs, gs}, {}, 0, {255, 255, 255, 150})
					}
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
	o := layer_origin()
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
	if ly == nil || d == nil do return
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
	// tiles: the stamp anchored at c
	if erase || len(L.tileSel) == 0 {
		if e.Ldtk_Doc_SetTile(doc, L.level, L.layer, c.x, c.y, -1) do e.Ldtk_Doc_ApplyRules(doc, L.level, L.layer, c.x, c.y, c.x, c.y)
		return
	}
	w, h := L.tileSelW, L.tileSelH
	for j in 0 ..< h {
		for i in 0 ..< w {
			x := (L.flips & 1) != 0 ? w - 1 - i : i
			y := (L.flips & 2) != 0 ? h - 1 - j : j
			e.Ldtk_Doc_SetTile(doc, L.level, L.layer, c.x + x, c.y + y, int(L.tileSel[i + j * w]), L.flips)
		}
	}
	e.Ldtk_Doc_ApplyRules(doc, L.level, L.layer, c.x, c.y, c.x + w - 1, c.y + h - 1)
}

// tile_for: the stamp's tile repeating over a rectangle / fill.
@(private = "file")
tile_for :: proc(c, anchor: [2]int) -> int {
	L := &GlobalLevel
	if len(L.tileSel) == 0 do return -1
	w, h := max(L.tileSelW, 1), max(L.tileSelH, 1)
	i := ((c.x - anchor.x) % w + w) % w
	j := ((c.y - anchor.y) % h + h) % h
	if (L.flips & 1) != 0 do i = w - 1 - i
	if (L.flips & 2) != 0 do j = h - 1 - j
	return int(L.tileSel[i + j * w])
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
		switch L.tool {
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
						e.Ldtk_Doc_SetTile(doc, L.level, L.layer, x, y, L.paintErase ? -1 : tile_for({x, y}, mn), L.flips)
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
	clear(&L.tileSel)
	append(&L.tileSel, t.t)
	L.tileSelW, L.tileSelH = 1, 1
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
				e.Ldtk_Doc_SetTile(doc, L.level, L.layer, x, y, erase ? -1 : tile_for({x, y}, start), L.flips)
			}
		}
	}
	e.Ldtk_Doc_ApplyRules(doc, L.level, L.layer, mn.x, mn.y, mx.x, mx.y)
}

@(private = "file")
entities_input :: proc(state: ^EditorState, ly: ^e.Ldtk_DocLayer, d: ^e.Ldtk_DocLayerDef, pressL, pressR: bool, mw: [2]f32) {
	L := &GlobalLevel
	doc := L.doc
	o := layer_origin()
	local := mw - o
	lp := [2]int{int(math.floor(local.x)), int(math.floor(local.y))}
	g := d.gridSize
	alt := imgui.GetIO().KeyAlt
	if pressR {
		if ent := e.Ldtk_Doc_EntityAt(doc, L.level, L.layer, lp); ent != nil {
			e.Ldtk_Doc_Checkpoint(doc, L.level, "Delete Entity")
			e.Ldtk_Doc_RemoveEntity(doc, L.level, L.layer, ent)
			if ent == L.selEntity do L.selEntity = nil
		}
		return
	}
	if pressL {
		// the resize handle of the selection
		if r, ok := selected_rect_screen(); ok && entity_resizable(L.selEntity) {
			m := imgui.GetIO().MousePos
			if abs(m.x - r[2]) <= 6 && abs(m.y - r[3]) <= 6 {
				L.entResize, L.entMoved = true, false
				return
			}
		}
		if ent := e.Ldtk_Doc_EntityAt(doc, L.level, L.layer, lp); ent != nil {
			L.selEntity = ent
			px := e.LdtkJson_Arr(ent, "px")
			if len(px) >= 2 do L.entGrab = lp - {int(px[0].num), int(px[1].num)}
			L.entDrag, L.entMoved = true, false
			return
		}
		if L.tool == .Brush && L.entityDef >= 0 && lp.x >= 0 && lp.y >= 0 && lp.x < ly.cWid * g && lp.y < ly.cHei * g {
			ed := e.Ldtk_Doc_EntityDef(doc, L.entityDef)
			if ed != nil {
				cell := [2]int{lp.x / g, lp.y / g}
				px := [2]int{cell.x * g + int(ed.pivot.x * f64(g)), cell.y * g + int(ed.pivot.y * f64(g))}
				if alt do px = lp
				e.Ldtk_Doc_Checkpoint(doc, L.level, "Add Entity")
				L.selEntity = e.Ldtk_Doc_AddEntity(doc, L.level, L.layer, L.entityDef, px)
			}
			return
		}
		L.selEntity = nil
		return
	}
	if L.entDrag && L.selEntity != nil {
		ent := L.selEntity
		np := lp - L.entGrab
		if !alt {
			ed := e.Ldtk_Doc_EntityDef(doc, e.LdtkJson_Int(ent, "defUid", -1))
			pv := [2]int{}
			if ed != nil do pv = {int(ed.pivot.x * f64(g)), int(ed.pivot.y * f64(g))}
			np = {int(math.round(f32(np.x - pv.x) / f32(g))) * g + pv.x, int(math.round(f32(np.y - pv.y) / f32(g))) * g + pv.y}
		}
		px := e.LdtkJson_Arr(ent, "px")
		if len(px) >= 2 && (np.x != int(px[0].num) || np.y != int(px[1].num)) {
			if !L.entMoved do e.Ldtk_Doc_Checkpoint(doc, L.level, "Move Entity")
			L.entMoved = true
			e.Ldtk_Doc_MoveEntity(doc, L.level, L.layer, ent, np)
		}
		if !imgui.IsMouseDown(.Left) do L.entDrag = false
	}
	if L.entResize && L.selEntity != nil {
		ent := L.selEntity
		ed := e.Ldtk_Doc_EntityDef(doc, e.LdtkJson_Int(ent, "defUid", -1))
		r := e.Ldtk_Doc_EntityRect(ent)
		size := [2]int{lp.x - r[0], lp.y - r[1]}
		if !alt do size = {max(int(math.round(f32(size.x) / f32(g))), 1) * g, max(int(math.round(f32(size.y) / f32(g))), 1) * g}
		if ed != nil {
			if !e.LdtkJson_Bool(ed.obj, "resizableX") do size.x = r[2]
			if !e.LdtkJson_Bool(ed.obj, "resizableY") do size.y = r[3]
		}
		size = {max(size.x, 1), max(size.y, 1)}
		if size.x != r[2] || size.y != r[3] {
			if !L.entMoved do e.Ldtk_Doc_Checkpoint(doc, L.level, "Resize Entity")
			L.entMoved = true
			e.Ldtk_Doc_ResizeEntity(doc, L.level, L.layer, ent, size)
		}
		if !imgui.IsMouseDown(.Left) do L.entResize = false
	}
}
