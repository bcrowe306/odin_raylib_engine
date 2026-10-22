package editor

import "core:c"
import "core:fmt"
import "core:strings"
import "core:time"
import rl "vendor:raylib"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Animation timeline (bottom panel "Animation" tab) for AnimationPlayerNode.
//
//   toolbar   animation picker, new, play/stop preview, FPS, loop, frame
//   frames    one cell per frame (thumbnail); click scrubs; drag to reorder;
//             drop textures from Assets to append; right-click removes
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
}

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
draw_frame_thumb :: proc(dl: ^imgui.DrawList, anim: ^e.Animation, frame: int, mn, mx: [2]f32) {
	tex: ^rl.Texture2D
	uv0, uv1 := [2]f32{0, 0}, [2]f32{1, 1}
	if anim.renderFrame == e.SSA_RenderFrame {
		ssa := cast(^e.SpriteSheetAnimation)anim
		if ssa.spriteSheet == nil || ssa.grid.x <= 0 || ssa.grid.y <= 0 do return
		tex = &ssa.spriteSheet.texture
		idx := anim.startFrame + frame
		cw, ch := 1 / f32(ssa.grid.x), 1 / f32(ssa.grid.y)
		uv0 = {f32(idx % ssa.grid.x) * cw, f32(idx / ssa.grid.x) * ch}
		uv1 = uv0 + {cw, ch}
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
	imgui.SetNextItemWidth(80)
	fps := apn.ticker.framesPerSecond
	if imgui.DragFloat("##anim_fps", &fps, 0.2, 1, 120, "%.0f fps") do apn.ticker->setFPS(fps)
	undo_on_activate(state, "Edit FPS")
	Drive_Item("anim.fps")
	imgui.SameLine(0, UI_SPACE)
	imgui.Checkbox("Loop##anim_loop", &anim.loop)
	undo_on_activate(state, "Toggle loop")
	Drive_Item("anim.loop")
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
		}
		imgui.EndPopup()
	}

	// Preview playback (the editor doesn't run node updates outside Simulate).
	if panel.playing {
		dt := f32(time.duration_seconds(time.tick_since(panel.lastTick)))
		panel.lastTick = time.tick_now()
		panel.accum += dt * max(apn.ticker.framesPerSecond, 1)
		if int(panel.accum) >= length {
			if anim.loop do panel.accum -= f32(length)
			else {panel.accum = f32(length - 1); panel.playing = false}
		}
		f := int(panel.accum)
		apn.currentFrame = anim.startFrame + min(f, max(anim->frameCount() - 1, 0))
		e.AnimationPlayerNode_ApplyTracks(apn, panel.accum)
		rel = f
	}

	// --- timeline ---
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
	totalH := 20 + THUMB_H + 4 + f32(nTracks) * ROW_H
	imgui.Dummy({LABEL_W + f32(length + 4) * CELL_W, totalH})

	// Header: frame numbers; click/drag scrubs.
	headMn := [2]f32{x0, origin.y}
	headMx := [2]f32{x0 + f32(length) * CELL_W, origin.y + 18}
	imgui.DrawList_AddRectFilled(dl, headMn, headMx, col_u32(UI_BG_RAISED), 4)
	for f in 0 ..< length {
		x := x0 + f32(f) * CELL_W
		if f % 5 == 0 || length <= 20 {
			imgui.DrawList_AddText(dl, {x + 4, origin.y + 3}, col_u32(UI_TEXT_DIM), fmt.ctprintf("%d", f + 1))
		}
		imgui.DrawList_AddLine(dl, {x, origin.y + 14}, {x, origin.y + 20}, col_u32({1, 1, 1, 0.12}))
	}
	imgui.SetCursorScreenPos(headMn)
	imgui.InvisibleButton("##anim_head", {max(headMx.x - headMn.x, 1), 20})
	Drive_Item("anim.header")
	if imgui.IsItemActive() {
		f := int((mouse.x - x0) / CELL_W)
		scrub(state, apn, anim, f)
		panel.playing = false
		rel = clamp(f, 0, length - 1)
	}

	// Frames row.
	fy := origin.y + 20
	label :: proc(dl: ^imgui.DrawList, x, y: f32, text: string, col: imgui.Vec4) {
		imgui.DrawList_AddText(dl, {x + 8, y}, col_u32(col), strings.clone_to_cstring(text, context.temp_allocator))
	}
	label(dl, origin.x + scrollX, fy + THUMB_H * 0.5 - 8, fmt.tprintf("%s  Frames", ICON_FA_IMAGE), UI_TEXT)
	isFrames := anim.renderFrame == e.FA_RenderFrame
	frameCount := anim->frameCount() if anim.frameCount != nil else 0
	if isFrames && len((cast(^e.FrameAnimation)anim).frames) == 0 do frameCount = 0
	removeFrame := -1
	for f in 0 ..< max(frameCount, 0) {
		mn := [2]f32{x0 + f32(f) * CELL_W + 1, fy}
		mx := [2]f32{mn.x + CELL_W - 2, fy + THUMB_H}
		imgui.DrawList_AddRectFilled(dl, mn, mx, col_u32(UI_ACCENT_SOFT if f == rel else UI_BG_RAISED), 4)
		draw_frame_thumb(dl, anim, f, mn, mx)
		imgui.SetCursorScreenPos(mn)
		imgui.PushIDInt(c.int(f))
		if imgui.InvisibleButton("##frame", mx - mn) {
			scrub(state, apn, anim, f)
			panel.playing = false
		}
		Drive_Item(fmt.tprintf("anim.frame:%d", f + 1))
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
					fa := cast(^e.FrameAnimation)anim
					if from != f && from >= 0 && from < len(fa.frames) {
						Editor_RecordUndo(state, "Move frame")
						t := fa.frames[from]
						ordered_remove(&fa.frames, from)
						inject_at(&fa.frames, f, t)
					}
				}
				imgui.EndDragDropTarget()
			}
			if imgui.BeginPopupContextItem("##frame_ctx") {
				if imgui.MenuItem(fmt.ctprintf("%s  Remove frame", ICON_FA_TRASH)) do removeFrame = f
				imgui.EndPopup()
			}
		}
		imgui.PopID()
	}
	// Drop textures to append frames.
	if isFrames {
		dropMn := [2]f32{x0 + f32(frameCount) * CELL_W + 1, fy}
		dropMx := [2]f32{dropMn.x + CELL_W * 2, fy + THUMB_H}
		imgui.DrawList_AddRect(dl, dropMn, dropMx, col_u32({1, 1, 1, 0.15}), 4)
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
	if removeFrame >= 0 {
		Editor_RecordUndo(state, "Remove frame")
		fa := cast(^e.FrameAnimation)anim
		t := fa.frames[removeFrame]
		ordered_remove(&fa.frames, removeFrame)
		e.ResourceManager_ReleaseTexture(&state.game.resourceManager, t)
		fa.endFrame = max(len(fa.frames) - 1, 0)
		apn.currentFrame = clamp(apn.currentFrame, anim.startFrame, anim.startFrame + max(len(fa.frames) - 1, 0))
	}

	// Track rows.
	ty := fy + THUMB_H + 4
	removeTrack := -1
	for &tr, ti in anim.tracks {
		y := ty + f32(ti) * ROW_H
		imgui.DrawList_AddRectFilled(dl, {origin.x + scrollX, y}, {x0 + f32(length) * CELL_W, y + ROW_H - 2}, col_u32({1, 1, 1, 0.025}), 3)
		target: ^e.Node = apn
		if tr.target != "." && tr.target != "" do target = e.Node_ResolvePath(mgr, apn, tr.target)
		name := tr.property if tr.target == "." else fmt.tprintf("%s.%s", tr.target, tr.property)
		label(dl, origin.x + scrollX, y + 6, name, UI_TEXT if target != nil else UI_DANGER)
		imgui.PushIDInt(c.int(ti) + 1000)
		// Row buttons (fixed at the left).
		imgui.SetCursorScreenPos({origin.x + scrollX + LABEL_W - 56, y + 2})
		if UI_IconButton(ICON_FA_CIRCLE, fmt.tprintf("anim.key:%s", tr.property), "Key the current value at the playhead", size = 24, tint = UI_WARNING) && target != nil {
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
			cx := x0 + k.frame * CELL_W + CELL_W * 0.5
			cy := y + ROW_H * 0.5 - 1
			r := f32(6)
			pts := [4][2]f32{{cx, cy - r}, {cx + r, cy}, {cx, cy + r}, {cx - r, cy}}
			hot := point_in_rect(mouse, {cx - r, cy - r}, {cx + r, cy + r})
			col := col_u32(UI_WARNING if !hot else {1, 0.85, 0.5, 1})
			imgui.DrawList_AddQuadFilled(dl, pts[0], pts[1], pts[2], pts[3], col)
			if k.ease != .Linear do imgui.DrawList_AddCircleFilled(dl, {cx, cy + r + 4}, 2, col_u32(UI_ACCENT))
			Drive_ItemRect(fmt.tprintf("anim.keyframe:%s:%d", tr.property, int(k.frame) + 1), {cx - r, cy - r}, {cx + r, cy + r})
			if hot {
				imgui.SetTooltip("%s", fmt.ctprintf("Frame %d: %.2f %.2f %.2f %.2f\nEasing to the next key: %s  (right-click: easing, delete)", int(k.frame) + 1, k.value[0], k.value[1], k.value[2], k.value[3], e.Ease_Name(k.ease)))
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
				if imgui.BeginMenu(fmt.ctprintf("%s  Easing: %s", ICON_FA_WAVE_SQUARE, e.Ease_Name(key.ease))) {
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
	px := x0 + (f32(rel) + 0.5) * CELL_W
	imgui.DrawList_AddLine(dl, {px, origin.y}, {px, ty + f32(nTracks) * ROW_H}, col_u32(UI_ACCENT), 2)
	imgui.EndChild()
}
