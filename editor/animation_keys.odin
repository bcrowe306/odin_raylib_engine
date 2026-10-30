package editor

import "core:fmt"
import "core:math"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Animation timeline keys (#177): the selected keys (click, Shift / Cmd, a
// box), dragging them in time (snapping to frames; Shift: free), and copy /
// paste / duplicate / delete. Keys are named by track and time.
// ============================================================================

Key_Ref :: struct {
	track: int,
	time:  f32,
}

@(private = "file")
Key_Clip_Entry :: struct {
	target, property: string,
	kind:             e.Track_Kind,
	key:              e.Track_Key, // time: from the first copied key
}

Anim_Keys :: struct {
	anim:     ^e.Animation, // the animation the selection is in
	sel:      [dynamic]Key_Ref,
	// A press on a key: a drag once the mouse moves.
	pressed:  bool,
	dragging: bool,
	pressX:   f32,
	grab:     Key_Ref,
	delta:    f32, // seconds the selection is dragged by
	// A box from an empty spot.
	boxing:   bool,
	boxFrom:  [2]f32,
	boxHits:  [dynamic]Key_Ref, // keys in the box this frame
	clip:     [dynamic]Key_Clip_Entry,
}

animKeys: Anim_Keys

// AnimKeys_Follow forgets the selection when the animation changes.
AnimKeys_Follow :: proc(anim: ^e.Animation) {
	if animKeys.anim == anim do return
	clear(&animKeys.sel)
	animKeys.anim = anim
	animKeys.pressed, animKeys.dragging, animKeys.boxing = false, false, false
}

AnimKeys_Shutdown :: proc() {
	delete(animKeys.sel)
	delete(animKeys.boxHits)
	clip_clear()
	delete(animKeys.clip)
}

AnimKeys_IsSelected :: proc(track: int, time: f32) -> bool {
	for r in animKeys.sel do if r.track == track && abs(r.time - time) < e.TRACK_KEY_EPS do return true
	return false
}

// AnimKeys_Click: a click on a key (Shift / Cmd adds or removes it; else it
// becomes the selection unless it's in it - then the drag moves them all).
AnimKeys_Click :: proc(track: int, time: f32, mouseX: f32) {
	io := imgui.GetIO()
	in_sel := AnimKeys_IsSelected(track, time)
	if io.KeyShift || io.KeySuper || io.KeyCtrl {
		if in_sel {
			for r, i in animKeys.sel do if r.track == track && abs(r.time - time) < e.TRACK_KEY_EPS {
				ordered_remove(&animKeys.sel, i)
				break
			}
		} else {
			append(&animKeys.sel, Key_Ref{track, time})
		}
	} else if !in_sel {
		clear(&animKeys.sel)
		append(&animKeys.sel, Key_Ref{track, time})
	}
	animKeys.pressed = AnimKeys_IsSelected(track, time)
	animKeys.dragging = false
	animKeys.pressX = mouseX
	animKeys.grab = {track, time}
	animKeys.delta = 0
}

// AnimKeys_DragUpdate: the drag's time offset - the grabbed key snaps to a
// frame (Shift: anywhere); the selection stays at or after 0.
AnimKeys_DragUpdate :: proc(apn: ^e.AnimationPlayerNode, anim: ^e.Animation, mouseX, cellW: f32) {
	if !animKeys.pressed do return
	if !animKeys.dragging && abs(mouseX - animKeys.pressX) > 3 do animKeys.dragging = true
	if !animKeys.dragging do return
	col := e.Animation_TimeFrame(apn, anim, animKeys.grab.time) + (mouseX - animKeys.pressX) / cellW
	if !imgui.GetIO().KeyShift do col = math.round(col)
	d := e.Animation_FrameTime(apn, anim, max(col, 0)) - animKeys.grab.time
	earliest := animKeys.grab.time
	for r in animKeys.sel do earliest = min(earliest, r.time)
	animKeys.delta = max(d, -earliest)
}

// AnimKeys_DragEnd: on release, moves the selection by the drag (one undo).
AnimKeys_DragEnd :: proc(state: ^EditorState, anim: ^e.Animation) {
	defer {animKeys.pressed, animKeys.dragging, animKeys.delta = false, false, 0}
	if !animKeys.dragging || abs(animKeys.delta) < e.TRACK_KEY_EPS do return
	Editor_RecordUndo(state, "Move keys")
	d := animKeys.delta
	for ti in 0 ..< len(anim.tracks) {
		times := make([dynamic]f32, context.temp_allocator)
		for r in animKeys.sel do if r.track == ti do append(&times, r.time)
		if len(times) > 0 do e.Track_MoveKeys(&anim.tracks[ti], times[:], d)
	}
	// (Track_MoveKeys stops the group at 0 the same way.)
	for &r in animKeys.sel do r.time += d
}

// AnimKeys_BoxEnd: the keys in the box become the selection (Shift / Cmd:
// added to it).
AnimKeys_BoxEnd :: proc() {
	io := imgui.GetIO()
	if !(io.KeyShift || io.KeySuper || io.KeyCtrl) do clear(&animKeys.sel)
	for h in animKeys.boxHits do if !AnimKeys_IsSelected(h.track, h.time) do append(&animKeys.sel, h)
	animKeys.boxing = false
}

AnimKeys_Delete :: proc(state: ^EditorState, anim: ^e.Animation) {
	if len(animKeys.sel) == 0 do return
	Editor_RecordUndo(state, "Delete keys")
	n := 0
	for r in animKeys.sel do if r.track < len(anim.tracks) && e.Track_RemoveKey(&anim.tracks[r.track], r.time) do n += 1
	clear(&animKeys.sel)
	Editor_Log(state, .Info, "Deleted %d key(s)", n)
}

@(private = "file")
clip_clear :: proc() {
	for c in animKeys.clip {
		delete(c.target)
		delete(c.property)
		delete(c.key.text)
		delete(c.key.arg)
	}
	clear(&animKeys.clip)
}

AnimKeys_CanPaste :: proc() -> bool {return len(animKeys.clip) > 0}

// AnimKeys_Copy: the selected keys, timed from the first.
AnimKeys_Copy :: proc(state: ^EditorState, anim: ^e.Animation) {
	if len(animKeys.sel) == 0 do return
	clip_clear()
	first := max(f32)
	for r in animKeys.sel do first = min(first, r.time)
	for r in animKeys.sel {
		if r.track >= len(anim.tracks) do continue
		tr := &anim.tracks[r.track]
		i := e.Track_KeyAt(tr, r.time)
		if i < 0 do continue
		k := tr.keys[i]
		k.time -= first
		k.text = strings.clone(k.text)
		k.arg = strings.clone(k.arg)
		append(&animKeys.clip, Key_Clip_Entry{strings.clone(tr.target), strings.clone(tr.property), tr.kind, k})
	}
	Editor_Log(state, .Info, "Copied %d key(s)", len(animKeys.clip))
}

// AnimKeys_Paste puts the copied keys at `at` (seconds) on their tracks (the
// same node and property); keys copied from one track go onto the selected
// track instead when it's the same kind. The pasted keys are selected.
AnimKeys_Paste :: proc(state: ^EditorState, apn: ^e.AnimationPlayerNode, anim: ^e.Animation, at: f32, selectedTrack: int, label := "Paste keys") {
	if len(animKeys.clip) == 0 do return
	oneTrack := true
	for c in animKeys.clip do if c.target != animKeys.clip[0].target || c.property != animKeys.clip[0].property do oneTrack = false
	Editor_RecordUndo(state, label)
	clear(&animKeys.sel)
	missed := 0
	for c in animKeys.clip {
		ti := -1
		if oneTrack && selectedTrack >= 0 && selectedTrack < len(anim.tracks) && anim.tracks[selectedTrack].kind == c.kind {
			ti = selectedTrack
		} else {
			for tr, i in anim.tracks do if tr.target == c.target && tr.property == c.property && tr.kind == c.kind do ti = i
		}
		if ti < 0 {
			missed += 1
			continue
		}
		k := c.key
		k.time += at
		k.text = strings.clone(k.text, apn.allocator)
		k.arg = strings.clone(k.arg, apn.allocator)
		e.Track_PutKey(&anim.tracks[ti], k)
		append(&animKeys.sel, Key_Ref{ti, k.time})
	}
	if missed > 0 do Editor_Log(state, .Warn, "%d key(s) had no track here (add the track, or select a track of the same kind)", missed)
	else do Editor_Log(state, .Info, "%s: %d key(s)", label, len(animKeys.clip))
}

// AnimKeys_Duplicate: copies of the selected keys one frame after the last.
AnimKeys_Duplicate :: proc(state: ^EditorState, apn: ^e.AnimationPlayerNode, anim: ^e.Animation) {
	if len(animKeys.sel) == 0 do return
	last := f32(0)
	for r in animKeys.sel do last = max(last, r.time)
	AnimKeys_Copy(state, anim)
	after := e.Animation_FrameTime(apn, anim, math.round(e.Animation_TimeFrame(apn, anim, last)) + 1)
	AnimKeys_Paste(state, apn, anim, after, -1, "Duplicate keys")
}

// AnimKeys_Summary: "<n> key(s)" for drives and the header.
AnimKeys_Summary :: proc() -> string {
	return fmt.tprintf("%d", len(animKeys.sel))
}
