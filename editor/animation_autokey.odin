package editor

import "core:fmt"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Keys from the Inspector (#179): a diamond by each animatable property keys
// it at the playhead of the animation being edited (right-click: previous /
// next key, remove); auto-key records each change made while it's on.
// ============================================================================

// The animation the Animation tab edits (set as it draws; the Inspector's
// diamonds key into it).
animKeyTarget: struct {
	state: ^EditorState,
	apn:   ^e.AnimationPlayerNode,
	anim:  ^e.Animation,
	frame: i32,
}

AnimKeyTarget_Set :: proc(state: ^EditorState, apn: ^e.AnimationPlayerNode, anim: ^e.Animation) {
	animKeyTarget = {state, apn, anim, imgui.GetFrameCount()}
}

// key_target: the player and animation to key into (the tab drew them this
// frame or the last).
@(private = "file")
key_target :: proc() -> (^EditorState, ^e.AnimationPlayerNode, ^e.Animation, bool) {
	t := animKeyTarget
	if t.apn == nil || t.anim == nil || imgui.GetFrameCount() - t.frame > 1 || !e.Node_IsAlive(t.apn) do return nil, nil, nil, false
	if e.AnimationPlayerNode_GetAnimation(t.apn) != t.anim do return nil, nil, nil, false
	return t.state, t.apn, t.anim, true
}

// AnimKeys_KeyProperty keys a node's property at `at` (seconds) with its
// current value, adding the track when there's none.
AnimKeys_KeyProperty :: proc(state: ^EditorState, apn: ^e.AnimationPlayerNode, anim: ^e.Animation, node: ^e.Node, property: string, at: f32) -> bool {
	p, ok := e.Track_FindProperty(node, property)
	if !ok || !e.Track_IsAnimatable(p) || state.activeScene == nil do return false
	target := e.Node_RelativePath(state.activeScene.manager, apn, node)
	if p.kind == .String {
		text, tok := e.Property_GetTrackText(p)
		if !tok do return false
		e.Track_SetEventKey(e.Animation_AddTrack(apn, anim, target, property), at, text, apn.allocator)
		return true
	}
	v, vok := e.Property_GetTrackValue(p)
	if !vok do return false
	e.Track_SetKey(e.Animation_AddTrack(apn, anim, target, property), at, v)
	return true
}

@(private = "file")
find_track :: proc(state: ^EditorState, apn: ^e.AnimationPlayerNode, anim: ^e.Animation, node: ^e.Node, property: string) -> ^e.Property_Track {
	target := e.Node_RelativePath(state.activeScene.manager, apn, node)
	for &tr in anim.tracks {
		t := "." if tr.target == "" else tr.target
		if tr.kind == .Property && t == target && tr.property == property do return &tr
	}
	return nil
}

// Inspector_KeyButton: the diamond at the end of a property's label - empty
// (no track), outlined (a track, no key here), filled (a key at the
// playhead). Click: key the value; right-click: previous / next key, remove.
Inspector_KeyButton :: proc(node: ^e.Node, path: string) {
	// ("origin": the Inspector's Origin edits the pivot, not a sprite's origin field.)
	if node == nil || path == "" || path == "origin" do return
	state, apn, anim, ok := key_target()
	if !ok || state.activeScene == nil || state.isSimulating do return
	p, pok := e.Track_FindProperty(node, path)
	if !pok || !e.Track_IsAnimatable(p) || p.runtime do return
	at := AnimationPanel_PlayheadTime(apn, anim)
	tr := find_track(state, apn, anim, node, path)
	keyed := tr != nil && e.Track_KeyAt(tr, at) >= 0

	S :: f32(14)
	imgui.SameLine(0, 0)
	x := imgui.GetCursorPosX() + max(imgui.GetContentRegionAvail().x - S - 2, 0)
	imgui.SetCursorPosX(x)
	pos := imgui.GetCursorScreenPos()
	id := fmt.tprintf("insp.key:%s", path)
	imgui.InvisibleButton(fmt.ctprintf("##%s", id), {S, imgui.GetFrameHeight()})
	Drive_Item(id)
	hot := imgui.IsItemHovered()
	c := pos + {S * 0.5, imgui.GetFrameHeight() * 0.5}
	r := f32(5)
	dl := imgui.GetWindowDrawList()
	pts := [4][2]f32{{c.x, c.y - r}, {c.x + r, c.y}, {c.x, c.y + r}, {c.x - r, c.y}}
	col := UI_WARNING if keyed else (UI_ACCENT if tr != nil else UI_TEXT_FAINT)
	if hot do col = UI_TEXT
	if keyed do imgui.DrawList_AddQuadFilled(dl, pts[0], pts[1], pts[2], pts[3], col_u32(col))
	else do imgui.DrawList_AddQuad(dl, pts[0], pts[1], pts[2], pts[3], col_u32(col), 1.5)
	if hot {
		what := "Update the key" if keyed else "Key this value"
		imgui.SetTooltip("%s", fmt.ctprintf("%s at %.2fs in %s (right-click: previous / next key, remove)", what, at, anim.name))
	}
	if imgui.IsItemClicked(.Left) {
		Editor_RecordUndo(state, "Key property")
		if AnimKeys_KeyProperty(state, apn, anim, node, path, at) do Editor_Log(state, .Info, "Keyed %s at %.2fs", path, at)
	}
	if imgui.IsItemClicked(.Right) do imgui.OpenPopup(fmt.ctprintf("##keymenu_%s", path))
	if imgui.BeginPopup(fmt.ctprintf("##keymenu_%s", path)) {
		defer imgui.EndPopup()
		UI_DimText(fmt.tprintf("%s in %s", path, anim.name))
		imgui.Separator()
		prev, next := f32(-1), f32(-1)
		if tr != nil {
			for k in tr.keys {
				if k.time < at - e.TRACK_KEY_EPS do prev = k.time
				if k.time > at + e.TRACK_KEY_EPS && next < 0 do next = k.time
			}
		}
		if imgui.MenuItem(fmt.ctprintf("%s  Previous Key", ICON_FA_CHEVRON_LEFT), nil, false, prev >= 0) do AnimationPanel_ScrubTo(state, apn, anim, prev)
		Drive_Item("insp.key-prev")
		if imgui.MenuItem(fmt.ctprintf("%s  Next Key", ICON_FA_CHEVRON_RIGHT), nil, false, next >= 0) do AnimationPanel_ScrubTo(state, apn, anim, next)
		Drive_Item("insp.key-next")
		if imgui.MenuItem(fmt.ctprintf("%s  Remove Key Here", ICON_FA_TRASH), nil, false, keyed) {
			Editor_RecordUndo(state, "Remove key")
			e.Track_RemoveKey(tr, at)
		}
		Drive_Item("insp.key-remove")
	}
}

// --- auto-key ------------------------------------------------------------------------

@(private = "file")
Auto_Value :: struct {
	node:     ^e.Node,
	property: string, // (the property's path; lives with the node)
	value:    [4]f32,
	text:     string, // String properties (owned)
}

animAutoKey: struct {
	on:      bool,
	values:  [dynamic]Auto_Value,
	valid:   bool,
	apn:     ^e.AnimationPlayerNode,
	anim:    ^e.Animation,
	undoGen: int,
}

AutoKey_Shutdown :: proc() {
	autokey_clear()
	delete(animAutoKey.values)
}

@(private = "file")
autokey_clear :: proc() {
	for v in animAutoKey.values {
		delete(v.text)
		delete(v.property)
	}
	clear(&animAutoKey.values)
	animAutoKey.valid = false
}

// AutoKey_Record: before the tab draws - each selected node's animatable
// property that changed since the last frame (an Inspector edit, a viewport
// drag) gets a key at the playhead. Undo / redo and playback don't count.
AutoKey_Record :: proc(state: ^EditorState, apn: ^e.AnimationPlayerNode, anim: ^e.Animation, at: f32) {
	a := &animAutoKey
	if !a.on || !a.valid || a.apn != apn || a.anim != anim || a.undoGen != state.undoGeneration || state.isSimulating do return
	for v in a.values {
		if !e.Node_IsAlive(v.node) do continue
		p, ok := e.Track_FindProperty(v.node, v.property)
		if !ok do continue
		changed := false
		if p.kind == .String {
			text, _ := e.Property_GetTrackText(p)
			changed = text != v.text
		} else {
			cur, _ := e.Property_GetTrackValue(p)
			for i in 0 ..< 4 do if abs(cur[i] - v.value[i]) > 0.0001 do changed = true
		}
		if changed do AnimKeys_KeyProperty(state, apn, anim, v.node, v.property, at)
	}
}

// AutoKey_Snapshot: after the tab draws - the selected nodes' values (what
// the next frame's changes are measured from).
AutoKey_Snapshot :: proc(state: ^EditorState, apn: ^e.AnimationPlayerNode, anim: ^e.Animation) {
	a := &animAutoKey
	autokey_clear()
	if !a.on || apn == nil || anim == nil || state.isSimulating do return
	a.apn, a.anim, a.undoGen = apn, anim, state.undoGeneration
	add :: proc(n: ^e.Node, name: string) {
		p, ok := e.Track_FindProperty(n, name)
		if !ok || !e.Track_IsAnimatable(p) || p.runtime do return
		v := Auto_Value{node = n, property = strings.clone(name)}
		if p.kind == .String {
			text, _ := e.Property_GetTrackText(p)
			v.text = strings.clone(text)
		} else {
			v.value, _ = e.Property_GetTrackValue(p)
		}
		append(&animAutoKey.values, v)
	}
	for n in state.selection {
		if n == nil || !e.Node_IsAlive(n) do continue
		for name in ([]string{"position", "rotation", "scale"}) do add(n, name)
		if n.typeId == e.TextureNode do add(n, "texture")
		for p in e.Node_CollectProperties(n) do add(n, p.name)
	}
	a.valid = true
}
