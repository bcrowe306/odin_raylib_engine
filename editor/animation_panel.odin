package editor

import "core:c"
import "core:fmt"
import "core:math"
import "core:slice"
import "core:strings"
import "core:time"
import rl "vendor:raylib"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Animation timeline (bottom panel "Animation" tab) for AnimationPlayerNode.
//
//   toolbar   animation picker, new, play/stop preview, loop, reverse, the
//             animation's FPS, default-on-load, frame; range (start / end),
//             copy / paste / delete the selected frames
//   frames    every source frame (frames outside the range dimmed; the range
//             handles in the header drag); click selects (Shift: a run,
//             Cmd: toggle) and scrubs; drag to reorder; drop textures from
//             Assets to append; right-click: copy, paste, delete, set range;
//             Delete / Cmd+C / Cmd+V while the panel has focus
//   tracks    keyframed properties (engine/animation_tracks.odin): a row per
//             target.property with diamonds on keyed frames. "Key" records
//             the property's current value at the playhead; right-click a
//             diamond to delete it; "Add Track" picks node + property.
//
// Scrubbing and previewing apply the tracks to the scene; Stop (or leaving
// the node) puts the animated properties back, so previews never end up
// saved into the scene.
// ============================================================================

CELL_W :: f32(34)
LABEL_W :: f32(190)
ROW_H :: f32(30)
THUMB_H :: f32(40)

@(private = "file")
Preview_Value :: struct {
	node:     ^e.Node,
	property: string,
	value:    [4]f32,
}

@(private = "file")
Anim_Panel :: struct {
	node:       ^e.AnimationPlayerNode, // node the saved values belong to
	saved:      [dynamic]Preview_Value,
	playing:    bool,
	lastTick:   time.Tick,
	accum:      f32,
	trackNode:  ^e.Node, // Add Track dialog
	trackOpen:  bool,
	newName:    [64]u8,
	// Selected source frames (of selAnim) and the last one clicked.
	sel:        [dynamic]int,
	selAnim:    ^e.Animation,
	anchor:     int,
	rangeDrag:  int, // 1: dragging the range start handle, 2: the end
}

// The copied frames (Copy / Paste in the timeline).
frameClip: e.Frame_Clip

// animTimelineFocused: the Animation tab has focus (its keys aren't the
// scene's: Delete, Cmd+C / V act on frames).
animTimelineFocused: bool

@(private = "file")
panel: Anim_Panel

// preview_capture remembers the animated properties' values (once per
// preview session) so they can be restored.
@(private = "file")
preview_capture :: proc(state: ^EditorState, apn: ^e.AnimationPlayerNode) {
	if panel.node == apn && len(panel.saved) > 0 do return
	preview_restore(state)
	panel.node = apn
	anim := e.AnimationPlayerNode_GetAnimation(apn)
	if anim == nil do return
	mgr := state.activeScene.manager
	for tr in anim.tracks {
		target: ^e.Node = apn
		if tr.target != "." && tr.target != "" do target = e.Node_ResolvePath(mgr, apn, tr.target)
		if target == nil do continue
		p, ok := e.Track_FindProperty(target, tr.property)
		if !ok do continue
		v, vok := e.Property_GetTrackValue(p)
		if !vok do continue
		append(&panel.saved, Preview_Value{target, strings.clone(tr.property), v})
	}
}

// preview_restore puts animated properties back to their pre-preview values.
@(private = "file")
preview_restore :: proc(state: ^EditorState) {
	for pv in panel.saved {
		if e.Node_IsAlive(pv.node) {
			if p, ok := e.Track_FindProperty(pv.node, pv.property); ok do e.Property_SetTrackValue(p, pv.value)
		}
		delete(pv.property)
	}
	clear(&panel.saved)
	if panel.node != nil && e.Node_IsAlive(panel.node) {
		if a := e.AnimationPlayerNode_GetAnimation(panel.node); a != nil do panel.node.currentFrame = a.startFrame
	}
	panel.playing = false
	panel.node = nil
}

// AnimationPanel_Shutdown frees the panel's preview state.
AnimationPanel_Shutdown :: proc() {
	for pv in panel.saved do delete(pv.property)
	delete(panel.saved)
}

@(private = "file")
scrub :: proc(state: ^EditorState, apn: ^e.AnimationPlayerNode, anim: ^e.Animation, frame: int) {
	preview_capture(state, apn)
	length := e.Animation_Length(anim)
	f := clamp(frame, 0, length - 1)
	apn.currentFrame = anim.startFrame + min(f, max(anim->frameCount() - 1, 0))
	e.AnimationPlayerNode_ApplyTracks(apn, f32(f))
	panel.accum = f32(f)
}

@(private = "file")
selected :: proc(f: int) -> bool {
	for s in panel.sel do if s == f do return true
	return false
}

// frame_select: a click on source frame f (Shift extends, Cmd toggles).
@(private = "file")
frame_select :: proc(f: int) {
	io := imgui.GetIO()
	if io.KeyShift && len(panel.sel) > 0 {
		clear(&panel.sel)
		for i in min(panel.anchor, f) ..= max(panel.anchor, f) do append(&panel.sel, i)
		return
	}
	if io.KeySuper || io.KeyCtrl {
		for s, i in panel.sel do if s == f {ordered_remove(&panel.sel, i); return}
		append(&panel.sel, f)
	} else {
		clear(&panel.sel)
		append(&panel.sel, f)
	}
	panel.anchor = f
}

@(private = "file")
frames_delete :: proc(state: ^EditorState, apn: ^e.AnimationPlayerNode, anim: ^e.Animation, frames: []int) {
	if len(frames) == 0 do return
	Editor_RecordUndo(state, "Delete frames")
	n := e.Animation_RemoveFrames(apn, anim, frames, &state.game.resourceManager)
	clear(&panel.sel)
	Editor_Log(state, .Info, "Deleted %d frame(s)", n)
}

@(private = "file")
frames_copy :: proc(state: ^EditorState, anim: ^e.Animation, frames: []int) {
	if len(frames) == 0 do return
	n := e.Animation_CopyFrames(anim, frames, &frameClip)
	Editor_Log(state, .Info, "Copied %d frame(s)", n)
}

// frames_paste: after the last selected frame (else at the end).
@(private = "file")
frames_paste :: proc(state: ^EditorState, apn: ^e.AnimationPlayerNode, anim: ^e.Animation) {
	if e.Frame_ClipEmpty(&frameClip) do return
	at := e.Animation_SourceCount(anim)
	if len(panel.sel) > 0 {
		at = 0
		for s in panel.sel do at = max(at, s + 1)
	}
	Editor_RecordUndo(state, "Paste frames")
	n := e.Animation_PasteFrames(apn, anim, at, &frameClip, &state.game.resourceManager)
	if n == 0 {
		Editor_Log(state, .Warn, "Those frames don't fit this animation (images go into frame animations, cells into the same sprite sheet)")
		return
	}
	clear(&panel.sel)
	for i in at ..< at + n do append(&panel.sel, i)
	Editor_Log(state, .Info, "Pasted %d frame(s)", n)
}

@(private = "file")
draw_frame_thumb :: proc(dl: ^imgui.DrawList, anim: ^e.Animation, frame: int, mn, mx: [2]f32) {
	tex: ^rl.Texture2D
	uv0, uv1 := [2]f32{0, 0}, [2]f32{1, 1}
	if anim.renderFrame == e.SSA_RenderFrame {
		// `frame` is a source frame: a cell of the sheet.
		ssa := cast(^e.SpriteSheetAnimation)anim
		if ssa.spriteSheet == nil || ssa.grid.x <= 0 || ssa.grid.y <= 0 do return
		tex = &ssa.spriteSheet.texture
		cell := ssa.cells[frame] if frame >= 0 && frame < len(ssa.cells) else frame
		size := [2]f32{f32(tex.width), f32(tex.height)}
		r := e.SpriteSheet_CellRect(size, ssa.grid, ssa.margin, ssa.spacing, cell)
		uv0 = {r.x / max(size.x, 1), r.y / max(size.y, 1)}
		uv1 = uv0 + {r.width / max(size.x, 1), r.height / max(size.y, 1)}
	} else {
		fa := cast(^e.FrameAnimation)anim
		if frame < 0 || frame >= len(fa.frames) || fa.frames[frame] == nil do return
		tex = &fa.frames[frame].texture
	}
	if tex == nil || tex.id == 0 do return
	// Fit, keeping the aspect ratio.
	w := f32(tex.width) * (uv1.x - uv0.x)
	h := f32(tex.height) * (uv1.y - uv0.y)
	boxW, boxH := mx.x - mn.x - 4, mx.y - mn.y - 4
	s := min(boxW / max(w, 1), boxH / max(h, 1))
	dw, dh := w * s, h * s
	p := [2]f32{mn.x + (mx.x - mn.x - dw) * 0.5, mn.y + (mx.y - mn.y - dh) * 0.5}
	imgui.DrawList_AddImage(dl, transmute(imgui.TextureID)tex, p, {p.x + dw, p.y + dh}, uv0, uv1)
}

// The key whose context menu is open.
@(private = "file")
keyMenu: struct {
	track: int,
	frame: f32,
} = {track = -1}

// ease_preview: a tooltip with the curve's shape.
@(private = "file")
ease_preview :: proc(ease: e.Ease) {
	if !imgui.BeginTooltip() do return
	defer imgui.EndTooltip()
	size := imgui.Vec2{120, 70}
	o := imgui.GetCursorScreenPos()
	imgui.Dummy(size)
	dl := imgui.GetWindowDrawList()
	imgui.DrawList_AddRectFilled(dl, o, o + size, col_u32(UI_BG_APP), 3)
	prev: imgui.Vec2
	for i in 0 ..= 40 {
		t := f32(i) / 40
		v := e.Ease_Apply(ease, t)
		p := imgui.Vec2{o.x + 6 + t * (size.x - 12), o.y + size.y - 10 - v * (size.y - 20)}
		if i > 0 do imgui.DrawList_AddLine(dl, prev, p, col_u32(UI_ACCENT), 2)
		prev = p
	}
}

AnimationPanel_Render :: proc(state: ^EditorState) {
	animTimelineFocused = false
	node := state.selectedNode
	apn: ^e.AnimationPlayerNode
	if node != nil && node.typeId == e.AnimationPlayerNode do apn = cast(^e.AnimationPlayerNode)node
	if panel.node != nil && panel.node != apn do preview_restore(state)
	if apn == nil {
		imgui.Dummy({0, 8})
		UI_DimText("   Select an AnimationPlayer node to edit its animations and keyframes.")
		return
	}
	ctx := &state.game.gameContext
	_ = ctx

	// --- toolbar ---
	imgui.Dummy({0, 2})
	names := make([dynamic]string, context.temp_allocator)
	for a in apn.animations do append(&names, a.name)
	imgui.SetNextItemWidth(170)
	if idx, changed := UI_Combo("anim.select", apn.animationIndex, names[:]); changed {
		preview_restore(state)
		Editor_RecordUndo(state, "Set animation")
		e.AnimationPlayerNode_SetAnimationIndex(apn, idx)
		if a := e.AnimationPlayerNode_GetAnimation(apn); a != nil do apn.currentFrame = a.startFrame
	}
	imgui.SameLine(0, 4)
	if UI_IconButton(ICON_FA_PLUS, "anim.new", "New animation", size = 26) {
		Editor_RecordUndo(state, "New animation")
		name := fmt.tprintf("anim_%d", len(apn.animations) + 1)
		e.AnimationPlayerNode_AddFrameAnimation(apn, &state.game.resourceManager, name, nil)
		e.AnimationPlayerNode_SetAnimationIndex(apn, len(apn.animations) - 1)
	}
	anim := e.AnimationPlayerNode_GetAnimation(apn)
	if anim == nil {
		imgui.SameLine()
		UI_DimText("No animations yet: add one with +")
		return
	}
	length := e.Animation_Length(anim)
	rel := apn.currentFrame - anim.startFrame
	imgui.SameLine(0, UI_SPACE)
	UI_VerticalDivider(20)
	if UI_IconButton(ICON_FA_PAUSE if panel.playing else ICON_FA_PLAY, "anim.play", "Pause preview" if panel.playing else "Play preview", panel.playing, 26) {
		if panel.playing {
			panel.playing = false
		} else {
			preview_capture(state, apn)
			panel.playing = true
			panel.lastTick = time.tick_now()
			panel.accum = f32(rel)
		}
	}
	imgui.SameLine(0, 2)
	if UI_IconButton(ICON_FA_STOP, "anim.stop", "Stop (restore the scene)", size = 26) do preview_restore(state)
	imgui.SameLine(0, UI_SPACE)
	imgui.Checkbox("Loop##anim_loop", &anim.loop)
	undo_on_activate(state, "Toggle loop")
	Drive_Item("anim.loop")
	imgui.SameLine(0, UI_SPACE)
	imgui.Checkbox("Reverse##anim_rev", &anim.reverse)
	undo_on_activate(state, "Toggle reverse")
	Drive_Item("anim.reverse")
	UI_Tooltip("Play this animation from its last frame to its first")
	// This animation's frame rate (0 = the player's).
	imgui.SameLine(0, UI_SPACE)
	imgui.SetNextItemWidth(96)
	fpsFmt := fmt.ctprintf("player %.0f", apn.fps) if anim.fps <= 0 else "%.0f fps"
	if imgui.DragFloat("##anim_fps", &anim.fps, 0.2, 0, 120, fpsFmt) do e.AnimationPlayerNode_SetAnimationIndex(apn, apn.animationIndex)
	undo_on_activate(state, "Edit FPS")
	Drive_Item("anim.fps")
	UI_Tooltip("This animation's frames per second (0: the player's FPS, set in the Inspector)")
	imgui.SameLine(0, 2)
	isDefault := apn.defaultAnimation == anim.name
	if UI_IconButton(ICON_FA_STAR, "anim.default", "Played first when the scene loads (click to clear)" if isDefault else "Make this the animation played when the scene loads", isDefault, 26) {
		Editor_RecordUndo(state, "Default animation")
		apn.defaultAnimation = "" if isDefault else strings.clone(anim.name, apn.allocator)
	}
	imgui.SameLine(0, UI_SPACE)
	imgui.AlignTextToFramePadding()
	UI_DimText(fmt.tprintf("Frame %d / %d", rel + 1, length))
	imgui.SameLine(0, UI_SPACE)
	if UI_Button(fmt.tprintf("%s  Add Track", ICON_FA_PLUS), "anim.add-track") {
		panel.trackNode = apn
		imgui.OpenPopup("##anim_add_track")
	}
	UI_Tooltip("Scrub the header · drag frames to reorder · drop textures on + · right-click a key to delete")
	mgr := state.activeScene.manager
	if imgui.BeginPopup("##anim_add_track") {
		UI_DimText("Animate a property of:")
		// The player and its descendants.
		draw :: proc(state: ^EditorState, mgr: ^e.NodeManager, n: ^e.Node, depth: int) {
			if n.transient do return
			if imgui.Selectable(fmt.ctprintf("%*s%s  %s###tn%p", depth * 3, "", Editor_NodeIcon(n), n.name, n), panel.trackNode == n, {.NoAutoClosePopups}) do panel.trackNode = n
			Drive_Item(fmt.tprintf("anim.track-node:%s", n.name))
			for c in e.GetChildrenView(mgr, n) do if c != nil do draw(state, mgr, c, depth + 1)
		}
		draw(state, mgr, apn, 0)
		imgui.Separator()
		if panel.trackNode != nil && e.Node_IsAlive(panel.trackNode) {
			props := make([dynamic]string, context.temp_allocator)
			append(&props, "position", "rotation", "scale")
			for p in e.Node_CollectProperties(panel.trackNode) do if e.Track_IsAnimatable(p) && !p.runtime do append(&props, p.name)
			for pname in props {
				if imgui.MenuItem(strings.clone_to_cstring(pname, context.temp_allocator)) {
					Editor_RecordUndo(state, "Add track")
					target := e.Node_RelativePath(mgr, apn, panel.trackNode)
					tr := e.Animation_AddTrack(apn, anim, target, pname)
					// First key: the current value at the playhead.
					if p, ok := e.Track_FindProperty(panel.trackNode, pname); ok {
						if v, vok := e.Property_GetTrackValue(p); vok do e.Track_SetKey(tr, f32(apn.currentFrame - anim.startFrame), v)
					}
				}
				Drive_Item(fmt.tprintf("anim.track-prop:%s", pname))
			}
			imgui.SeparatorText("Events")
			target := e.Node_RelativePath(mgr, apn, panel.trackNode)
			if imgui.MenuItem(fmt.ctprintf("%s  Call Script Methods", ICON_FA_CODE)) {
				Editor_RecordUndo(state, "Add track")
				e.Animation_AddEventTrack(apn, anim, target, .Method)
			}
			Drive_Item("anim.track-methods")
			UI_Tooltip("Keys call a method on this node's script when playback reaches them")
			if imgui.MenuItem(fmt.ctprintf("%s  Play Sounds", ICON_FA_MUSIC)) {
				Editor_RecordUndo(state, "Add track")
				e.Animation_AddEventTrack(apn, anim, target, .Audio)
			}
			Drive_Item("anim.track-sounds")
		}
		imgui.EndPopup()
	}

	// Selection follows the animation.
	if panel.selAnim != anim {
		clear(&panel.sel)
		panel.selAnim = anim
	}
	srcCount := e.Animation_SourceCount(anim)

	hasSel := len(panel.sel) > 0
	canPaste := !e.Frame_ClipEmpty(&frameClip)
	// Keys while the panel has focus (not while typing in a field).
	animTimelineFocused = imgui.IsWindowFocused(imgui.FocusedFlags_RootAndChildWindows)
	if animTimelineFocused && !imgui.GetIO().WantTextInput {
		primary := imgui.GetIO().KeySuper || imgui.GetIO().KeyCtrl
		if hasSel && (imgui.IsKeyPressed(.Delete) || imgui.IsKeyPressed(.Backspace)) do frames_delete(state, apn, anim, slice.clone(panel.sel[:], context.temp_allocator))
		if hasSel && primary && imgui.IsKeyPressed(.C) do frames_copy(state, anim, panel.sel[:])
		if canPaste && primary && imgui.IsKeyPressed(.V) do frames_paste(state, apn, anim)
	}
	srcCount = e.Animation_SourceCount(anim)
	length = e.Animation_Length(anim)
	rel = clamp(apn.currentFrame - anim.startFrame, 0, max(length - 1, 0))

	// Preview playback (the editor doesn't run node updates outside Simulate).
	reversed := e.AnimationPlayerNode_IsReversed(apn, anim)
	if panel.playing {
		dt := f32(time.duration_seconds(time.tick_since(panel.lastTick)))
		panel.lastTick = time.tick_now()
		panel.accum += dt * max(e.AnimationPlayerNode_FPS(apn), 1)
		if int(panel.accum) >= length {
			if anim.loop do panel.accum -= f32(length)
			else {panel.accum = f32(length - 1); panel.playing = false}
		}
		f := int(panel.accum)
		if reversed do f = length - 1 - f
		apn.currentFrame = anim.startFrame + min(f, max(anim->frameCount() - 1, 0))
		e.AnimationPlayerNode_ApplyTracks(apn, f32(f))
		rel = f
	}

	// --- timeline: one column per source frame; the range starts at `base` ---
	avail := imgui.GetContentRegionAvail()
	if !imgui.BeginChild("##anim_timeline", {avail.x, max(avail.y, 40)}, {}, {.HorizontalScrollbar}) {
		imgui.EndChild()
		return
	}
	dl := imgui.GetWindowDrawList()
	origin := imgui.GetCursorScreenPos()
	scrollX := imgui.GetScrollX()
	x0 := origin.x + LABEL_W
	io := imgui.GetIO()
	mouse := [2]f32{io.MousePos.x, io.MousePos.y}
	nTracks := len(anim.tracks)
	base := anim.startFrame
	cols := max(srcCount, base + length)
	totalH := 20 + THUMB_H + 4 + f32(nTracks) * ROW_H
	imgui.Dummy({LABEL_W + f32(cols + 4) * CELL_W, totalH})
	colX :: proc(x0: f32, col: int) -> f32 {return x0 + f32(col) * CELL_W}

	// Header: frame numbers and the range band with its handles; click /
	// drag inside the range scrubs.
	headMn := [2]f32{x0, origin.y}
	headMx := [2]f32{colX(x0, cols), origin.y + 18}
	imgui.DrawList_AddRectFilled(dl, headMn, headMx, col_u32(UI_BG_RAISED), 4)
	rangeMn := [2]f32{colX(x0, base), origin.y}
	rangeMx := [2]f32{colX(x0, base + length), origin.y + 18}
	imgui.DrawList_AddRectFilled(dl, rangeMn, rangeMx, col_u32(UI_ACCENT_SOFT), 4)
	for f in 0 ..< cols {
		x := colX(x0, f)
		if f % 5 == 0 || cols <= 20 {
			inRange := f >= base && f < base + length
			imgui.DrawList_AddText(dl, {x + 4, origin.y + 3}, col_u32(UI_TEXT_DIM if inRange else UI_TEXT_FAINT), fmt.ctprintf("%d", f + 1))
		}
		imgui.DrawList_AddLine(dl, {x, origin.y + 14}, {x, origin.y + 20}, col_u32(ui_line(0.12)))
	}
	// Left of the header: copy / paste / delete the selected frames.
	{
		imgui.PushStyleVarImVec2(.FramePadding, {3, 1})
		bx := origin.x + scrollX + 6
		imgui.SetCursorScreenPos({bx, origin.y})
		if !hasSel do imgui.BeginDisabled(true)
		if UI_IconButton(ICON_FA_COPY, "anim.copy", "Copy the selected frames (Cmd+C)", size = 20) do frames_copy(state, anim, panel.sel[:])
		if !hasSel do imgui.EndDisabled()
		imgui.SameLine(0, 2)
		if !canPaste do imgui.BeginDisabled(true)
		if UI_IconButton(ICON_FA_PASTE, "anim.paste", "Paste frames after the selection, else at the end (Cmd+V)", size = 20) do frames_paste(state, apn, anim)
		if !canPaste do imgui.EndDisabled()
		imgui.SameLine(0, 2)
		if !hasSel do imgui.BeginDisabled(true)
		if UI_IconButton(ICON_FA_TRASH, "anim.delete", "Delete the selected frames (Delete)", size = 20, tint = UI_DANGER) do frames_delete(state, apn, anim, slice.clone(panel.sel[:], context.temp_allocator))
		if !hasSel do imgui.EndDisabled()
		imgui.SameLine(0, 6)
		imgui.SetCursorPosY(imgui.GetCursorPosY() + 2)
		UI_DimText(fmt.tprintf("%d selected", len(panel.sel)) if hasSel else "")
		imgui.PopStyleVar()
	}
	imgui.SetCursorScreenPos(rangeMn)
	imgui.InvisibleButton("##anim_head", {max(rangeMx.x - rangeMn.x, 1), 20})
	Drive_Item("anim.header")
	if imgui.IsItemActive() && panel.rangeDrag == 0 {
		f := int((mouse.x - rangeMn.x) / CELL_W)
		scrub(state, apn, anim, f)
		panel.playing = false
		rel = clamp(f, 0, length - 1)
	}
	// Range handles: drag to the first / last frame played.
	handle :: proc(id: string, x, y: f32) -> bool {
		imgui.SetCursorScreenPos({x - 4, y})
		imgui.InvisibleButton(strings.clone_to_cstring(id, context.temp_allocator), {8, 20})
		Drive_Item(id)
		hot := imgui.IsItemHovered() || imgui.IsItemActive()
		imgui.DrawList_AddRectFilled(imgui.GetWindowDrawList(), {x - 2, y}, {x + 2, y + 20}, col_u32(UI_ACCENT if hot else ui_accent(0.7)), 2)
		if hot do imgui.SetMouseCursor(.ResizeEW)
		return imgui.IsItemActive()
	}
	if handle("anim.range-start", rangeMn.x, origin.y) {
		if panel.rangeDrag == 0 do Editor_RecordUndo(state, "Edit range")
		panel.rangeDrag = 1
		e.Animation_SetRange(anim, int(math.round((mouse.x - x0) / CELL_W)), anim.endFrame)
	} else if handle("anim.range-end", rangeMx.x, origin.y) {
		if panel.rangeDrag == 0 do Editor_RecordUndo(state, "Edit range")
		panel.rangeDrag = 2
		e.Animation_SetRange(anim, anim.startFrame, int(math.round((mouse.x - x0) / CELL_W)) - 1)
	} else if !imgui.IsMouseDown(.Left) {
		panel.rangeDrag = 0
	}

	// Frames row: every source frame.
	fy := origin.y + 20
	label :: proc(dl: ^imgui.DrawList, x, y: f32, text: string, col: imgui.Vec4) {
		imgui.DrawList_AddText(dl, {x + 8, y}, col_u32(col), strings.clone_to_cstring(text, context.temp_allocator))
	}
	label(dl, origin.x + scrollX, fy + 1, fmt.tprintf("%s  Frames", ICON_FA_IMAGE), UI_TEXT)
	// Under the label: the range played (first / last frame).
	{
		imgui.PushStyleVarImVec2(.FramePadding, {4, 1})
		imgui.SetCursorScreenPos({origin.x + scrollX + 8, fy + 19})
		imgui.SetNextItemWidth(56)
		first := c.int(anim.startFrame + 1)
		if imgui.DragInt("##anim_start", &first, 0.1, 1, c.int(max(srcCount, 1)), "from %d") do e.Animation_SetRange(anim, int(first) - 1, max(anim.endFrame, int(first) - 1))
		undo_on_activate(state, "Edit range")
		Drive_Item("anim.start")
		UI_Tooltip("First frame played (or drag the range handles in the header)")
		imgui.SameLine(0, 3)
		imgui.SetNextItemWidth(56)
		last := c.int(anim.endFrame + 1)
		if imgui.DragInt("##anim_end", &last, 0.1, 1, c.int(max(srcCount, 1)), "to %d") do e.Animation_SetRange(anim, anim.startFrame, int(last) - 1)
		undo_on_activate(state, "Edit range")
		Drive_Item("anim.end")
		UI_Tooltip("Last frame played")
		imgui.SameLine(0, 4)
		imgui.SetCursorPosY(imgui.GetCursorPosY() + 1)
		UI_DimText(fmt.tprintf("/ %d", srcCount))
		imgui.PopStyleVar()
	}
	isFrames := anim.renderFrame == e.FA_RenderFrame
	ctxFrame := -1
	for f in 0 ..< srcCount {
		mn := [2]f32{colX(x0, f) + 1, fy}
		mx := [2]f32{mn.x + CELL_W - 2, fy + THUMB_H}
		inRange := f >= base && f <= anim.endFrame
		imgui.DrawList_AddRectFilled(dl, mn, mx, col_u32(UI_ACCENT_SOFT if f == apn.currentFrame else UI_BG_RAISED), 4)
		draw_frame_thumb(dl, anim, f, mn, mx)
		if !inRange do imgui.DrawList_AddRectFilled(dl, mn, mx, col_u32({UI_BG_PANEL.x, UI_BG_PANEL.y, UI_BG_PANEL.z, 0.65}), 4)
		if selected(f) do imgui.DrawList_AddRect(dl, mn, mx, col_u32(UI_ACCENT), 4, {}, 2)
		imgui.SetCursorScreenPos(mn)
		imgui.PushIDInt(c.int(f))
		if imgui.InvisibleButton("##frame", mx - mn) {
			frame_select(f)
			panel.playing = false
			if inRange do scrub(state, apn, anim, f - base)
			else do apn.currentFrame = f // just show it
		}
		Drive_Item(fmt.tprintf("anim.frame:%d", f + 1))
		if imgui.IsItemHovered() && imgui.IsMouseClicked(.Right) {
			if !selected(f) {
				clear(&panel.sel)
				append(&panel.sel, f)
			}
			panel.anchor = f
			ctxFrame = f
		}
		if isFrames {
			// Drag to reorder.
			if imgui.BeginDragDropSource({}) {
				idx := c.int(f)
				imgui.SetDragDropPayload("ORE_ANIM_FRAME", &idx, size_of(c.int))
				imgui.TextUnformatted(fmt.ctprintf("Frame %d", f + 1))
				imgui.EndDragDropSource()
			}
			if imgui.BeginDragDropTarget() {
				if pl := imgui.AcceptDragDropPayload("ORE_ANIM_FRAME"); pl != nil {
					from := int((cast(^c.int)pl.Data)^)
					if from != f {
						Editor_RecordUndo(state, "Move frame")
						e.Animation_MoveFrame(anim, from, f)
						clear(&panel.sel)
						append(&panel.sel, f)
					}
				}
				imgui.EndDragDropTarget()
			}
		}
		imgui.PopID()
	}
	if ctxFrame >= 0 do imgui.OpenPopup("##frame_ctx")
	if imgui.BeginPopup("##frame_ctx") {
		f := panel.anchor
		UI_DimText(fmt.tprintf("%d frame(s) selected", len(panel.sel)))
		imgui.Separator()
		if imgui.MenuItem(fmt.ctprintf("%s  Copy", ICON_FA_COPY), "Cmd+C") do frames_copy(state, anim, panel.sel[:])
		Drive_Item("anim.ctx-copy")
		if imgui.MenuItem(fmt.ctprintf("%s  Paste After", ICON_FA_PASTE), "Cmd+V", false, !e.Frame_ClipEmpty(&frameClip)) do frames_paste(state, apn, anim)
		Drive_Item("anim.ctx-paste")
		if imgui.MenuItem(fmt.ctprintf("%s  Delete", ICON_FA_TRASH), "Del") do frames_delete(state, apn, anim, slice.clone(panel.sel[:], context.temp_allocator))
		Drive_Item("anim.ctx-delete")
		imgui.Separator()
		if imgui.MenuItem(fmt.ctprintf("Start the Range Here (frame %d)", f + 1)) {
			Editor_RecordUndo(state, "Edit range")
			e.Animation_SetRange(anim, f, max(anim.endFrame, f))
		}
		Drive_Item("anim.ctx-range-start")
		if imgui.MenuItem(fmt.ctprintf("End the Range Here (frame %d)", f + 1)) {
			Editor_RecordUndo(state, "Edit range")
			e.Animation_SetRange(anim, min(anim.startFrame, f), f)
		}
		Drive_Item("anim.ctx-range-end")
		imgui.EndPopup()
	}
	// Drop textures to append frames.
	if isFrames {
		dropMn := [2]f32{colX(x0, srcCount) + 1, fy}
		dropMx := [2]f32{dropMn.x + CELL_W * 2, fy + THUMB_H}
		imgui.DrawList_AddRect(dl, dropMn, dropMx, col_u32(ui_line(0.15)), 4)
		imgui.DrawList_AddText(dl, {dropMn.x + CELL_W - 6, fy + THUMB_H * 0.5 - 8}, col_u32(UI_TEXT_FAINT), ICON_FA_PLUS)
		imgui.SetCursorScreenPos(dropMn)
		imgui.InvisibleButton("##frame_drop", dropMx - dropMn)
		Drive_Item("anim.frame-drop")
		UI_Tooltip("Drop textures from Assets here to add frames")
		if imgui.BeginDragDropTarget() {
			if pl := imgui.AcceptDragDropPayload(ASSET_PAYLOAD); pl != nil {
				p := (^Asset_Payload)(pl.Data)
				rel := strings.clone(string(p.path[:p.len]), context.temp_allocator)
				if Asset_KindOf(rel) == .Texture {
					Editor_Log(state, .Info, "Added frame %s", rel)
					Editor_RecordUndo(state, "Add frame")
					fa := cast(^e.FrameAnimation)anim
					e.FrameAnimation_AddFrame(fa, &state.game.resourceManager, e.Project_ResolveAssetPath(&state.game.gameContext, rel))
				}
			}
			imgui.EndDragDropTarget()
		}
	}

	// Track rows.
	ty := fy + THUMB_H + 4
	removeTrack := -1
	for &tr, ti in anim.tracks {
		y := ty + f32(ti) * ROW_H
		imgui.DrawList_AddRectFilled(dl, {origin.x + scrollX, y}, {colX(x0, cols), y + ROW_H - 2}, col_u32(ui_line(0.025)), 3)
		target: ^e.Node = apn
		if tr.target != "." && tr.target != "" do target = e.Node_ResolvePath(mgr, apn, tr.target)
		prop := tr.property
		if tr.kind == .Method do prop = "calls()"
		if tr.kind == .Audio do prop = "sounds"
		name := prop if tr.target == "." else fmt.tprintf("%s.%s", tr.target, prop)
		label(dl, origin.x + scrollX, y + 6, name, UI_TEXT if target != nil else UI_DANGER)
		imgui.PushIDInt(c.int(ti) + 1000)
		// Row buttons (fixed at the left).
		imgui.SetCursorScreenPos({origin.x + scrollX + LABEL_W - 56, y + 2})
		keyTip := "Key the current value at the playhead"
		if tr.kind == .Method do keyTip = "Call a method at the playhead (right-click the key to name it)"
		if tr.kind == .Audio do keyTip = "Play a sound at the playhead (right-click the key to pick it)"
		keyClicked := UI_IconButton(ICON_FA_CIRCLE, fmt.tprintf("anim.key:%s", tr.property), keyTip, size = 24, tint = UI_WARNING)
		if keyClicked && tr.kind != .Property {
			Editor_RecordUndo(state, "Add event key")
			text := "on_animation_event"
			if tr.kind == .Audio {
				audio := Editor_ListProjectFiles(state, "", AUDIO_EXTS)
				text = audio[0] if len(audio) > 0 else ""
			}
			// The previous key's text is the likely next one.
			for k in tr.keys do if k.frame < f32(rel) && k.text != "" do text = k.text
			e.Track_SetEventKey(&tr, f32(rel), text, apn.allocator)
		} else if keyClicked && target != nil {
			if p, ok := e.Track_FindProperty(target, tr.property); ok {
				if v, vok := e.Property_GetTrackValue(p); vok {
					Editor_RecordUndo(state, "Set key")
					e.Track_SetKey(&tr, f32(rel), v)
					// The value the user just set is the one to come back to.
					for &pv in panel.saved do if pv.node == target && pv.property == tr.property do pv.value = v
				}
			}
		}
		imgui.SameLine(0, 2)
		if UI_IconButton(ICON_FA_XMARK, fmt.tprintf("anim.remove-track:%s", tr.property), "Remove track", size = 24) do removeTrack = ti
		// Keys (right-click: easing to the next key, delete).
		for k in tr.keys {
			cx := x0 + (f32(base) + k.frame) * CELL_W + CELL_W * 0.5
			cy := y + ROW_H * 0.5 - 1
			r := f32(6)
			pts := [4][2]f32{{cx, cy - r}, {cx + r, cy}, {cx, cy + r}, {cx - r, cy}}
			hot := point_in_rect(mouse, {cx - r, cy - r}, {cx + r, cy + r})
			col := col_u32(UI_WARNING if !hot else {1, 0.85, 0.5, 1})
			if tr.kind == .Property {
				imgui.DrawList_AddQuadFilled(dl, pts[0], pts[1], pts[2], pts[3], col)
			} else {
				// Event keys: a square (method) or a circle (sound).
				ec := col_u32({0.55, 0.75, 1, 1} if !hot else {0.75, 0.88, 1, 1})
				if tr.kind == .Method do imgui.DrawList_AddRectFilled(dl, {cx - r + 1, cy - r + 1}, {cx + r - 1, cy + r - 1}, ec, 2)
				else do imgui.DrawList_AddCircleFilled(dl, {cx, cy}, r - 1, ec)
			}
			if k.ease != .Linear do imgui.DrawList_AddCircleFilled(dl, {cx, cy + r + 4}, 2, col_u32(UI_ACCENT))
			Drive_ItemRect(fmt.tprintf("anim.keyframe:%s:%d", tr.property, int(k.frame) + 1), {cx - r, cy - r}, {cx + r, cy + r})
			if hot {
				switch tr.kind {
				case .Property: imgui.SetTooltip("%s", fmt.ctprintf("Frame %d: %.2f %.2f %.2f %.2f\nEasing to the next key: %s  (right-click: easing, delete)", int(k.frame) + 1, k.value[0], k.value[1], k.value[2], k.value[3], e.Ease_Name(k.ease)))
				case .Method:   imgui.SetTooltip("%s", fmt.ctprintf("Frame %d: calls %s:%s(frame)  (right-click: edit, delete)", int(k.frame) + 1, tr.target, k.text))
				case .Audio:    imgui.SetTooltip("%s", fmt.ctprintf("Frame %d: plays %s  (right-click: edit, delete)", int(k.frame) + 1, k.text))
				}
				if imgui.IsMouseClicked(.Left) do scrub(state, apn, anim, int(k.frame))
				if imgui.IsMouseClicked(.Right) {
					keyMenu = {ti, k.frame}
					imgui.OpenPopup("##key_ctx")
				}
			}
		}
		if keyMenu.track == ti && imgui.BeginPopup("##key_ctx") {
			key: ^e.Track_Key
			for &k in tr.keys do if abs(k.frame - keyMenu.frame) < 0.001 do key = &k
			if key != nil {
				UI_DimText(fmt.tprintf("Key at frame %d", int(key.frame) + 1))
				imgui.Separator()
				if tr.kind == .Method {
					buf: [128]u8
					copy(buf[:len(buf) - 1], key.text)
					imgui.SetNextItemWidth(220)
					if imgui.InputTextWithHint("##method", "method name", cstring(raw_data(buf[:])), len(buf), {.AutoSelectAll}) {
						key.text = strings.clone(string(cstring(raw_data(buf[:]))), apn.allocator)
					}
					if imgui.IsItemActivated() do Editor_RecordUndo(state, "Event key")
					Drive_Item("anim.event-method")
					UI_DimText("Called on the target's script: method(frame)")
				} else if tr.kind == .Audio {
					if path, ok := asset_picker("anim.event-sound", key.text, Editor_ListProjectFiles(state, "", AUDIO_EXTS), allowNone = false); ok {
						Editor_RecordUndo(state, "Event key")
						key.text = strings.clone(path, apn.allocator)
					}
				}
				if tr.kind == .Property && imgui.BeginMenu(fmt.ctprintf("%s  Easing: %s", ICON_FA_WAVE_SQUARE, e.Ease_Name(key.ease))) {
					for ease in e.Ease {
						if imgui.MenuItem(strings.clone_to_cstring(e.Ease_Name(ease), context.temp_allocator), nil, ease == key.ease) {
							Editor_RecordUndo(state, "Key easing")
							key.ease = ease
						}
						Drive_Item(fmt.tprintf("anim.ease:%s", e.Ease_Name(ease)))
						if imgui.IsItemHovered() do ease_preview(ease)
					}
					imgui.EndMenu()
				}
				Drive_Item("anim.key-easing")
				if imgui.MenuItem(fmt.ctprintf("%s  Delete Key", ICON_FA_TRASH)) {
					Editor_RecordUndo(state, "Delete key")
					e.Track_RemoveKey(&tr, keyMenu.frame)
				}
				Drive_Item("anim.key-delete")
			}
			imgui.EndPopup()
		}
		imgui.PopID()
	}
	if removeTrack >= 0 {
		Editor_RecordUndo(state, "Remove track")
		preview_restore(state)
		e.Animation_RemoveTrack(anim, removeTrack)
	}

	// Playhead.
	px := x0 + (f32(base + rel) + 0.5) * CELL_W
	imgui.DrawList_AddLine(dl, {px, origin.y}, {px, ty + f32(nTracks) * ROW_H}, col_u32(UI_ACCENT), 2)
	imgui.EndChild()
}
