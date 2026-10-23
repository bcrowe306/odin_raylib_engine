package editor

import "core:c"
import "core:fmt"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"
import rl "vendor:raylib"

// ============================================================================
// Sprite Sheet Slicer (Tools menu, a texture's context menu, an Animation
// Player's Inspector): cut a sheet into cells (columns x rows or a cell size,
// margin, spacing), pick cells (click, drag across, Shift = a range), turn
// them into named animations - or one per row - and add them to the selected
// AnimationPlayer or a new one. Animations play the picked cells in order
// (SpriteSheetAnimation.cells).
// ============================================================================

Slicer_Anim :: struct {
	name:  string,
	cells: [dynamic]int,
	loop:  bool,
}

@(private = "file")
slicer: struct {
	open:      bool,
	texRel:    string,
	tex:       rl.Texture2D,
	grid:      [2]c.int,
	margin:    [2]c.int,
	spacing:   [2]c.int,
	selection: [dynamic]int,
	lastCell:  int,
	dragAdd:   bool,
	nameBuf:   [64]u8,
	loop:      bool,
	fps:       f32,
	anims:     [dynamic]Slicer_Anim,
	preview:   f32,
	// Sheet view: zoom (pixels per texel; 0 = fit the view).
	zoom:      f32,
}

// Slicer_Open opens the slicer on a texture ("" = keep the current one).
Slicer_Open :: proc(state: ^EditorState, texRel: string) {
	slicer.open = true
	if slicer.grid == {} {
		slicer.grid = {4, 1}
		slicer.loop = true
		slicer.fps = 12
	}
	if texRel != "" do slicer_set_texture(state, texRel)
}

Slicer_IsOpen :: proc() -> bool {return slicer.open}

@(private = "file")
slicer_set_texture :: proc(state: ^EditorState, rel: string) {
	if slicer.tex.id != 0 do rl.UnloadTexture(slicer.tex)
	slicer.tex = {}
	delete(slicer.texRel)
	slicer.texRel = strings.clone(rel)
	full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
	slicer.tex = rl.LoadTexture(strings.clone_to_cstring(full, context.temp_allocator))
	clear(&slicer.selection)
	slicer_clear_anims()
}

@(private = "file")
slicer_clear_anims :: proc() {
	for &a in slicer.anims {
		delete(a.name)
		delete(a.cells)
	}
	clear(&slicer.anims)
}

@(private = "file")
cell_count :: proc() -> int {return int(max(slicer.grid.x, 1) * max(slicer.grid.y, 1))}

@(private = "file")
cell_rect :: proc(cell: int) -> rl.Rectangle {
	return e.SpriteSheet_CellRect({f32(slicer.tex.width), f32(slicer.tex.height)}, {int(slicer.grid.x), int(slicer.grid.y)}, {int(slicer.margin.x), int(slicer.margin.y)}, {int(slicer.spacing.x), int(slicer.spacing.y)}, cell)
}

@(private = "file")
add_anim :: proc(name: string, cells: []int) {
	a := Slicer_Anim{name = strings.clone(name), loop = slicer.loop}
	append(&a.cells, ..cells)
	append(&slicer.anims, a)
}

// Slicer_Apply adds the slicer's animations to `apn` (a new
// AnimationPlayerNode when nil). Returns the node.
Slicer_Apply :: proc(state: ^EditorState, apn: ^e.AnimationPlayerNode) -> ^e.AnimationPlayerNode {
	if len(slicer.anims) == 0 || slicer.texRel == "" || state.activeScene == nil do return nil
	target := apn
	if target == nil {
		n := Editor_CreateNode(state, "AnimationPlayerNode", filepath.stem(filepath.base(slicer.texRel)))
		if n == nil do return nil
		target = cast(^e.AnimationPlayerNode)n
	} else {
		Editor_RecordUndo(state, "Add sliced animations")
	}
	ctx := &state.game.gameContext
	for a in slicer.anims {
		ssa := e.AnimationPlayerNode_AddSheetAnimation(target, &state.game.resourceManager, a.name, e.Project_ResolveAssetPath(ctx, slicer.texRel), {int(slicer.grid.x), int(slicer.grid.y)}, 0, 0, a.loop)
		ssa.margin = {int(slicer.margin.x), int(slicer.margin.y)}
		ssa.spacing = {int(slicer.spacing.x), int(slicer.spacing.y)}
		e.SpriteSheetAnimation_SetCells(ssa, a.cells[:], target.allocator)
	}
	e.AnimationPlayerNode_SetFPS(target, slicer.fps)
	if apn == nil && len(target.animations) > 0 {
		// A new player starts on the first animation.
		target.animationIndex = 0
		target.currentFrame = target.animations[0].startFrame
	}
	Editor_Log(state, .Info, "Added %d animation(s) from %s to %s", len(slicer.anims), slicer.texRel, target.name)
	state.selectedNode = target
	return target
}

Slicer_Render :: proc(state: ^EditorState) {
	if !slicer.open do return
	imgui.SetNextWindowSize({760, 520}, .FirstUseEver)
	center := imgui.GetMainViewport().WorkPos + imgui.GetMainViewport().WorkSize * 0.5
	imgui.SetNextWindowPos(center, .FirstUseEver, {0.5, 0.5})
	defer imgui.End()
	if !imgui.Begin(fmt.ctprintf("%s  Sprite Sheet Slicer###SpriteSlicer", ICON_FA_TABLE_CELLS), &slicer.open, {.NoCollapse}) do return

	// --- settings column ---
	if imgui.BeginChild("##slicer_side", {250, 0}, {}, {}) {
		imgui.SetNextItemWidth(-1)
		if imgui.BeginCombo("##slicer_tex", fmt.ctprintf("%s  %s", ICON_FA_IMAGE, slicer.texRel if slicer.texRel != "" else "Pick a texture")) {
			for f in Editor_ListProjectFiles(state, "", TEXTURE_EXTS) {
				if imgui.Selectable(strings.clone_to_cstring(f, context.temp_allocator), f == slicer.texRel) do slicer_set_texture(state, f)
				Drive_Item(fmt.tprintf("pick:%s", f))
			}
			imgui.EndCombo()
		}
		Drive_Item("slicer.texture")
		if slicer.tex.id != 0 {
			UI_DimText(fmt.tprintf("%d x %d px", slicer.tex.width, slicer.tex.height))
			if UI_BeginProps("##slicer_props") {
				int_field :: proc(label, id: string, v: ^c.int, lo, hi: c.int) -> bool {
					UI_PropLabel(label)
					changed := imgui.DragInt(fmt.ctprintf("##%s", id), v, 0.1, lo, hi)
					Drive_Item(id)
					return changed
				}
				changed := false
				changed |= int_field("Columns", "slicer.cols", &slicer.grid.x, 1, 256)
				changed |= int_field("Rows", "slicer.rows", &slicer.grid.y, 1, 256)
				// Cell size: sets columns / rows to fit.
				r := cell_rect(0)
				cell := [2]c.int{c.int(r.width), c.int(r.height)}
				UI_PropLabel("Cell Size")
				if imgui.DragInt2("##cellsize", &cell, 0.2, 1, 4096) {
					for a in 0 ..< 2 {
						size := slicer.tex.width if a == 0 else slicer.tex.height
						slicer.grid[a] = max(1, (size - 2 * slicer.margin[a] + slicer.spacing[a]) / max(cell[a] + slicer.spacing[a], 1))
					}
					changed = true
				}
				Drive_Item("slicer.cell-size")
				UI_PropLabel("Margin")
				changed |= imgui.DragInt2("##margin", &slicer.margin, 0.1, 0, 512)
				Drive_Item("slicer.margin")
				UI_PropLabel("Spacing")
				changed |= imgui.DragInt2("##spacing", &slicer.spacing, 0.1, 0, 512)
				Drive_Item("slicer.spacing")
				if changed do clear(&slicer.selection)
				UI_EndProps()
			}
			imgui.Separator()
			UI_DimText(fmt.tprintf("Selected: %d cell(s)", len(slicer.selection)))
			imgui.SetNextItemWidth(-1)
			imgui.InputTextWithHint("##slicer_name", "Animation name", cstring(raw_data(slicer.nameBuf[:])), len(slicer.nameBuf))
			Drive_Item("slicer.name")
			imgui.Checkbox("Loop##slicer", &slicer.loop)
			imgui.SameLine()
			if UI_Button(fmt.tprintf("%s  Add Animation", ICON_FA_PLUS), "slicer.add", {-1, 0}) && len(slicer.selection) > 0 {
				name := strings.trim_space(string(cstring(raw_data(slicer.nameBuf[:]))))
				if name == "" do name = fmt.tprintf("anim%d", len(slicer.anims) + 1)
				add_anim(name, slicer.selection[:])
				clear(&slicer.selection)
				slicer.nameBuf = {}
			}
			if UI_Button(fmt.tprintf("%s  One Animation per Row", ICON_FA_BARS), "slicer.per-row", {-1, 0}) {
				cols := int(max(slicer.grid.x, 1))
				for row in 0 ..< int(max(slicer.grid.y, 1)) {
					cells := make([dynamic]int, context.temp_allocator)
					for col in 0 ..< cols do append(&cells, row * cols + col)
					add_anim(fmt.tprintf("row%d", row + 1), cells[:])
				}
			}
			imgui.Separator()
			remove := -1
			for a, i in slicer.anims {
				imgui.PushIDInt(c.int(i))
				if UI_IconButton(ICON_FA_XMARK, fmt.tprintf("slicer.anim%d.remove", i), "Remove", size = 22) do remove = i
				imgui.SameLine()
				imgui.AlignTextToFramePadding()
				imgui.TextUnformatted(fmt.ctprintf("%s  ", a.name))
				imgui.SameLine()
				UI_DimText(fmt.tprintf("%d frames%s", len(a.cells), ", loop" if a.loop else ""))
				imgui.PopID()
			}
			if remove >= 0 {
				delete(slicer.anims[remove].name)
				delete(slicer.anims[remove].cells)
				ordered_remove(&slicer.anims, remove)
			}
			if len(slicer.anims) > 0 {
				imgui.SetNextItemWidth(90)
				imgui.DragFloat("FPS##slicer", &slicer.fps, 0.2, 1, 60, "%.0f")
				Drive_Item("slicer.fps")
				sel := state.selectedNode
				into := sel != nil && sel.typeId == e.AnimationPlayerNode
				label := fmt.tprintf("%s  Add to %s", ICON_FA_FILM, sel.name) if into else fmt.tprintf("%s  Create Animation Player", ICON_FA_FILM)
				if UI_PrimaryButton(label, "slicer.create", {-1, 0}) {
					if Slicer_Apply(state, cast(^e.AnimationPlayerNode)sel if into else nil) != nil do slicer_clear_anims()
				}
			}
		}
	}
	imgui.EndChild()
	imgui.SameLine()

	// --- the sheet, cells and the preview ---
	if imgui.BeginChild("##slicer_sheet", {0, 0}, {.Borders}, {.HorizontalScrollbar}) {
		if slicer.tex.id == 0 {
			UI_DimText("Pick a texture to slice.")
		} else {
			slicer_sheet(state)
			slicer_preview(90)
		}
	}
	imgui.EndChild()
}

@(private = "file")
SLICER_ZOOM_MIN :: f32(0.05)
@(private = "file")
SLICER_ZOOM_MAX :: f32(32)

// slicer_fit_scale: the zoom that fits the whole sheet in `avail`.
@(private = "file")
slicer_fit_scale :: proc(avail: [2]f32) -> f32 {
	s := min((avail.x - 8) / f32(slicer.tex.width), (avail.y - 8) / f32(slicer.tex.height))
	return clamp(s, SLICER_ZOOM_MIN, 8)
}

// Slicer_Selection: the picked cells, "0,1,2" (drives).
Slicer_Selection :: proc() -> string {
	sb := strings.builder_make(context.temp_allocator)
	for c, i in slicer.selection {
		if i > 0 do strings.write_string(&sb, ",")
		fmt.sbprint(&sb, c)
	}
	return strings.to_string(sb)
}

// Slicer_Zoom: the sheet's zoom (0 = fit) - drives.
Slicer_Zoom :: proc() -> f32 {return slicer.zoom}

@(private = "file")
slicer_sheet :: proc(state: ^EditorState) {
	previewH: f32 = 90
	io := imgui.GetIO()

	// --- zoom bar: - / % / + / Fit / 1:1 ---
	fitScale := slicer_fit_scale(imgui.GetContentRegionAvail() - {0, previewH + 34})
	scale := slicer.zoom if slicer.zoom > 0 else fitScale
	zoomTo := f32(-1)
	if UI_IconButton(ICON_FA_MINUS, "slicer.zoom-out", "Zoom out (Cmd+wheel)", size = 24) do zoomTo = scale / 1.25
	imgui.SameLine(0, 2)
	imgui.SetNextItemWidth(64)
	pct := scale * 100
	if imgui.DragFloat("##slicer_zoom", &pct, 1, SLICER_ZOOM_MIN * 100, SLICER_ZOOM_MAX * 100, "%.0f%%") do zoomTo = pct / 100
	Drive_Item("slicer.zoom")
	imgui.SameLine(0, 2)
	if UI_IconButton(ICON_FA_PLUS, "slicer.zoom-in", "Zoom in (Cmd+wheel)", size = 24) do zoomTo = scale * 1.25
	imgui.SameLine(0, UI_SPACE)
	if UI_Button("Fit", "slicer.zoom-fit") do slicer.zoom = 0
	UI_Tooltip("Fit the whole sheet in the view")
	imgui.SameLine(0, 2)
	if UI_Button("1:1", "slicer.zoom-1") do zoomTo = 1
	UI_Tooltip("One screen pixel per texture pixel")
	imgui.SameLine(0, UI_SPACE)
	imgui.AlignTextToFramePadding()
	UI_DimText("Cmd+wheel zooms · middle-drag pans")

	// --- the sheet: scrolls when zoomed in ---
	avail := imgui.GetContentRegionAvail()
	canvasOpen := imgui.BeginChild("##slicer_canvas", {avail.x, max(avail.y - previewH - 6, 60)}, {}, {.HorizontalScrollbar, .NoScrollWithMouse})
	defer imgui.EndChild()
	if !canvasOpen do return
	canvasMn := imgui.GetWindowPos()
	mouse := [2]f32{io.MousePos.x, io.MousePos.y}
	canvasHovered := imgui.IsWindowHovered({})
	if canvasHovered {
		// Cmd / Ctrl + wheel zooms around the mouse; the wheel scrolls (Shift: across).
		if io.MouseWheel != 0 && (io.KeySuper || io.KeyCtrl) {
			zoomTo = scale * (1.15 if io.MouseWheel > 0 else 1 / 1.15)
		} else if io.MouseWheel != 0 || io.MouseWheelH != 0 {
			dx, dy := io.MouseWheelH, io.MouseWheel
			if io.KeyShift && dx == 0 do dx, dy = dy, 0
			imgui.SetScrollX(imgui.GetScrollX() - dx * 40)
			imgui.SetScrollY(imgui.GetScrollY() - dy * 40)
		}
	}
	if canvasHovered && imgui.IsMouseDragging(.Middle) {
		d := io.MouseDelta
		imgui.SetScrollX(imgui.GetScrollX() - d.x)
		imgui.SetScrollY(imgui.GetScrollY() - d.y)
	}
	if zoomTo > 0 {
		zoomTo = clamp(zoomTo, SLICER_ZOOM_MIN, SLICER_ZOOM_MAX)
		// Keep the point under the mouse (else the view's centre) in place.
		anchor := mouse - canvasMn if canvasHovered else imgui.GetWindowSize() * 0.5
		content := ([2]f32{imgui.GetScrollX(), imgui.GetScrollY()} + anchor) / scale
		slicer.zoom = zoomTo
		scale = zoomTo
		imgui.SetScrollX(max(content.x * scale - anchor.x, 0))
		imgui.SetScrollY(max(content.y * scale - anchor.y, 0))
	}
	if slicer.zoom == 0 do scale = fitScale

	size := [2]f32{f32(slicer.tex.width), f32(slicer.tex.height)} * scale
	p0 := imgui.GetCursorScreenPos()
	dl := imgui.GetWindowDrawList()
	imgui.DrawList_AddRectFilled(dl, p0, p0 + size, col32(30, 34, 44, 255))
	imgui.Image(transmute(imgui.TextureID)&slicer.tex, size, {0, 0}, {1, 1}, {1, 1, 1, 1}, {0, 0, 0, 0})
	hovered := imgui.IsItemHovered()
	if !imgui.IsMouseDown(.Left) do slicer.dragAdd = false
	for cell in 0 ..< cell_count() {
		r := cell_rect(cell)
		mn := p0 + [2]f32{r.x, r.y} * scale
		mx := mn + [2]f32{r.width, r.height} * scale
		Drive_ItemRect(fmt.tprintf("slicer.cell:%d", cell), mn, mx, inWindow = true)
		idx := -1
		for s, i in slicer.selection do if s == cell do idx = i
		if idx >= 0 {
			imgui.DrawList_AddRectFilled(dl, mn, mx, col_u32(ui_accent(0.30)))
			imgui.DrawList_AddText(dl, mn + {3, 2}, col_u32(UI_ACCENT), fmt.ctprintf("%d", idx + 1))
		}
		imgui.DrawList_AddRect(dl, mn, mx, col32(0, 206, 201, 160))
		if !hovered || !point_in_rect(mouse, mn, mx) do continue
		imgui.DrawList_AddRect(dl, mn, mx, col32(255, 255, 255, 230), 0, {}, 2)
		if imgui.IsMouseClicked(.Left) {
			if io.KeyShift && slicer.lastCell >= 0 {
				// A range from the last clicked cell.
				step := 1 if cell >= slicer.lastCell else -1
				for k := slicer.lastCell + step; ; k += step {
					if !slice.contains(slicer.selection[:], k) do append(&slicer.selection, k)
					if k == cell do break
				}
			} else if idx >= 0 {
				ordered_remove(&slicer.selection, idx)
			} else {
				append(&slicer.selection, cell)
				slicer.dragAdd = true
			}
			slicer.lastCell = cell
		} else if slicer.dragAdd && imgui.IsMouseDown(.Left) && idx < 0 {
			append(&slicer.selection, cell) // dragging across adds cells
			slicer.lastCell = cell
		}
	}
}

// slicer_preview: the selection (else the last animation) playing.
@(private = "file")
slicer_preview :: proc(previewH: f32) {
	dl := imgui.GetWindowDrawList()
	frames := slicer.selection[:]
	if len(frames) == 0 && len(slicer.anims) > 0 do frames = slicer.anims[len(slicer.anims) - 1].cells[:]
	imgui.Dummy({0, 6})
	if len(frames) > 0 {
		slicer.preview += rl.GetFrameTime() * max(slicer.fps, 1)
		cell := frames[int(slicer.preview) % len(frames)]
		r := cell_rect(cell)
		s := min(previewH / max(r.height, 1), 3)
		q := imgui.GetCursorScreenPos()
		w, h := r.width * s, r.height * s
		imgui.DrawList_AddRectFilled(dl, q, q + {w, h}, col32(30, 34, 44, 255))
		uv0 := [2]f32{r.x / f32(slicer.tex.width), r.y / f32(slicer.tex.height)}
		uv1 := uv0 + [2]f32{r.width / f32(slicer.tex.width), r.height / f32(slicer.tex.height)}
		imgui.DrawList_AddImage(dl, transmute(imgui.TextureID)&slicer.tex, q, q + {w, h}, uv0, uv1)
		imgui.Dummy({w, h})
	}
}
