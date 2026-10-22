package editor

import "core:c"
import "core:fmt"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Tile map painting. Select a TileMapNode, pick a tileset and a tile in the
// Inspector's "Tile Map" section, choose a tool, then paint in the
// viewport: left button paints (Paint), erases (Erase) or flood-fills
// (Fill); the right button always erases. One stroke is one undo step.
// ============================================================================

Tile_Tool :: enum {
	None,
	Paint,
	Erase,
	Fill,
}

Tile_State :: struct {
	tool:   Tile_Tool,
	brush:  i32,
	stroke: bool, // a paint stroke is in progress (undo recorded)
}

GlobalTiles: Tile_State

selected_tilemap :: proc(state: ^EditorState) -> ^e.TileMapNode {
	n := state.selectedNode
	if n == nil || n.typeId != e.TileMapNode do return nil
	return cast(^e.TileMapNode)n
}

// Inspector_TileMap: tileset, sizes, tools and the tile palette.
Inspector_TileMap :: proc(state: ^EditorState, tm: ^e.TileMapNode) {
	if !UI_SectionHeader("Tile Map") do return
	ts := &GlobalTiles
	if UI_BeginProps("##tilemap") {
		UI_PropLabel("Tileset")
		textures := Editor_ListProjectFiles(state, "", TEXTURE_EXTS)
		current := asset_rel_editor(state, tm.tilesetPath)
		if path, ok := asset_picker("tile.tileset", current, textures, allowNone = true); ok && path != current {
			Editor_RecordUndo(state, "Set tileset")
			e.TileMapNode_SetTileset(tm, path, &state.game.gameContext)
		}
		UI_PropLabel("Tile Size")
		tsz := [2]c.int{c.int(tm.tileSize.x), c.int(tm.tileSize.y)}
		if imgui.DragInt2("##tilesize", &tsz, 0.2, 1, 512) do tm.tileSize = {int(max(tsz.x, 1)), int(max(tsz.y, 1))}
		undo_on_activate(state, "Tile size")
		Drive_Item("tile.size")
		UI_PropLabel("Map Size")
		msz := [2]c.int{c.int(tm.mapSize.x), c.int(tm.mapSize.y)}
		if imgui.DragInt2("##mapsize", &msz, 0.2, 1, 1024) {
			tm.mapSize = {int(max(msz.x, 1)), int(max(msz.y, 1))}
			e.TileMapNode_Layout(tm)
		}
		undo_on_activate(state, "Map size")
		Drive_Item("tile.map-size")
		UI_EndProps()
	}
	// Tools.
	tool :: proc(icon, id, tip: string, t: Tile_Tool) {
		if UI_IconButton(icon, id, tip, GlobalTiles.tool == t, 30) {
			GlobalTiles.tool = .None if GlobalTiles.tool == t else t
		}
	}
	tool(ICON_FA_PAINTBRUSH, "tile.paint", "Paint tiles (left button; right erases)", .Paint)
	imgui.SameLine(0, 2)
	tool(ICON_FA_ERASER, "tile.erase", "Erase tiles", .Erase)
	imgui.SameLine(0, 2)
	tool(ICON_FA_FILL_DRIP, "tile.fill", "Flood fill", .Fill)
	imgui.SameLine(0, UI_SPACE)
	imgui.AlignTextToFramePadding()
	UI_DimText(fmt.tprintf("Tile %d", ts.brush))

	// Palette.
	if tm.tileset == nil {
		UI_DimText("Pick a tileset image to paint with.")
		return
	}
	cols := e.TileMapNode_Columns(tm)
	count := e.TileMapNode_TileCount(tm)
	tex := &tm.tileset.texture
	cell := f32(32)
	perRow := max(int((imgui.GetContentRegionAvail().x + 2) / (cell + 2)), 1)
	imgui.PushStyleVarImVec2(.ItemSpacing, {2, 2})
	for i in 0 ..< count {
		if i % perRow != 0 do imgui.SameLine()
		u0 := [2]f32{f32((i % cols) * tm.tileSize.x) / f32(tex.width), f32((i / cols) * tm.tileSize.y) / f32(tex.height)}
		u1 := u0 + {f32(tm.tileSize.x) / f32(tex.width), f32(tm.tileSize.y) / f32(tex.height)}
		imgui.PushIDInt(c.int(i))
		selected := ts.brush == i32(i)
		if selected do imgui.PushStyleColorImVec4(.Button, UI_ACCENT)
		if imgui.ImageButton("##tile", transmute(imgui.TextureID)tex, {cell, cell}, u0, u1) {
			ts.brush = i32(i)
			if ts.tool == .None || ts.tool == .Erase do ts.tool = .Paint
		}
		if selected do imgui.PopStyleColor()
		Drive_Item(fmt.tprintf("tile.palette:%d", i))
		imgui.PopID()
	}
	imgui.PopStyleVar()
}

// Viewport_TilePaint handles painting; returns true when it owns the
// mouse this frame (no picking/gizmos).
Viewport_TilePaint :: proc(state: ^EditorState, drawList: ^imgui.DrawList, mouseScreen, mouseWorld: [2]f32) -> bool {
	tm := selected_tilemap(state)
	ts := &GlobalTiles
	if tm == nil || ts.tool == .None {
		ts.stroke = false
		return false
	}
	e.TileMapNode_Layout(tm)
	// Map outline and hovered cell.
	a := Viewport_WorldToScreen(state, e.TileMapNode_CellCorner(tm, {0, 0}))
	b := Viewport_WorldToScreen(state, e.TileMapNode_CellCorner(tm, tm.mapSize))
	imgui.DrawList_AddRect(drawList, {min(a.x, b.x), min(a.y, b.y)}, {max(a.x, b.x), max(a.y, b.y)}, col_u32({1, 1, 1, 0.35}))
	cell := e.TileMapNode_CellAt(tm, mouseWorld)
	inside := cell.x >= 0 && cell.y >= 0 && cell.x < tm.mapSize.x && cell.y < tm.mapSize.y
	if inside && state.viewportHovered {
		p := Viewport_WorldToScreen(state, e.TileMapNode_CellCorner(tm, cell))
		q := Viewport_WorldToScreen(state, e.TileMapNode_CellCorner(tm, cell + 1))
		col := UI_DANGER if ts.tool == .Erase || imgui.IsMouseDown(.Right) else UI_ACCENT
		imgui.DrawList_AddRect(drawList, {min(p.x, q.x), min(p.y, q.y)}, {max(p.x, q.x), max(p.y, q.y)}, col_u32(col), 0, {}, 2)
	}
	if !state.viewportHovered && !ts.stroke do return true
	left := imgui.IsMouseDown(.Left)
	right := imgui.IsMouseDown(.Right)
	if !left && !right {
		ts.stroke = false
		return true
	}
	if !inside do return true
	if !ts.stroke {
		Editor_RecordUndo(state, "Paint tiles")
		ts.stroke = true
		if left && ts.tool == .Fill {
			e.TileMapNode_Fill(tm, cell.x, cell.y, ts.brush)
			return true
		}
	}
	switch {
	case right || ts.tool == .Erase: e.TileMapNode_Set(tm, cell.x, cell.y, -1)
	case ts.tool == .Paint:          e.TileMapNode_Set(tm, cell.x, cell.y, ts.brush)
	case:
	}
	return true
}
