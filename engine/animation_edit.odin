package engine

import "core:fmt"
import "core:slice"
import "core:strings"

// ============================================================================
// Editing an animation's frames (the editor's timeline; tests).
//
// An animation plays a range (startFrame..endFrame) of its source frames:
// a FrameAnimation's images, or a sprite sheet's cells (its `cells` list, or
// every grid cell in reading order). Removing, pasting and moving frames
// keep the range on the same frames (it grows / shrinks with edits inside
// it); copied frames are image paths or cell numbers.
// ============================================================================

Frame_Clip :: struct {
	paths: [dynamic]string, // FrameAnimation: image files
	cells: [dynamic]int,    // sprite sheet: cell numbers
	sheet: string,          // the sheet the cells belong to
}

Frame_ClipClear :: proc(c: ^Frame_Clip) {
	for p in c.paths do delete(p)
	clear(&c.paths)
	clear(&c.cells)
	delete(c.sheet)
	c.sheet = ""
}

Frame_ClipEmpty :: proc(c: ^Frame_Clip) -> bool {return len(c.paths) == 0 && len(c.cells) == 0}

// Animation_SourceCount: how many source frames the animation has.
Animation_SourceCount :: proc(a: ^Animation) -> int {
	if a == nil do return 0
	if a.renderFrame == FA_RenderFrame do return len((cast(^FrameAnimation)a).frames)
	if a.renderFrame == SSA_RenderFrame {
		ssa := cast(^SpriteSheetAnimation)a
		if len(ssa.cells) > 0 do return len(ssa.cells)
		return max(ssa.grid.x, 1) * max(ssa.grid.y, 1)
	}
	return a.endFrame - a.startFrame + 1
}

// Animation_FrameSize: the pixel size a source frame is drawn at (before
// the node's scale; 0 when there is nothing to draw).
Animation_FrameSize :: proc(a: ^Animation, frame: int) -> [2]f32 {
	if a == nil do return {}
	if a.renderFrame == FA_RenderFrame {
		fa := cast(^FrameAnimation)a
		if len(fa.frames) == 0 do return {}
		t := fa.frames[clamp(frame, 0, len(fa.frames) - 1)]
		if t == nil do return {}
		return Texture_Size(t)
	}
	if a.renderFrame == SSA_RenderFrame {
		ssa := cast(^SpriteSheetAnimation)a
		if ssa.spriteSheet == nil do return {}
		tex := ssa.spriteSheet.texture
		r := SpriteSheet_CellRect({f32(tex.width), f32(tex.height)}, ssa.grid, ssa.margin, ssa.spacing, 0)
		return {r.width, r.height}
	}
	return {}
}

// Animation_SetRange plays source frames start..end (clamped).
Animation_SetRange :: proc(a: ^Animation, start, end: int) {
	n := Animation_SourceCount(a)
	if n <= 0 {
		a.startFrame, a.endFrame = 0, 0
		return
	}
	s := clamp(start, 0, n - 1)
	e := clamp(end, s, n - 1)
	a.startFrame, a.endFrame = s, e
}

// sheet_cells: a sheet animation's cell list (made from the grid if it has
// none, so cells can be removed / inserted).
@(private = "file")
sheet_cells :: proc(ssa: ^SpriteSheetAnimation, allocator := context.allocator) -> ^[dynamic]int {
	if len(ssa.cells) == 0 {
		if ssa.cells == nil do ssa.cells = make([dynamic]int, allocator)
		for i in 0 ..< max(ssa.grid.x, 1) * max(ssa.grid.y, 1) do append(&ssa.cells, i)
	}
	return &ssa.cells
}

// Animation_RemoveFrames removes source frames (any order); the range keeps
// to the frames left. Released images go back to `rm`.
Animation_RemoveFrames :: proc(apn: ^AnimationPlayerNode, a: ^Animation, indices: []int, rm: ^ResourceManager) -> int {
	if a == nil || len(indices) == 0 do return 0
	sorted := slice.clone(indices, context.temp_allocator)
	slice.sort(sorted)
	removed := 0
	start, end := a.startFrame, a.endFrame
	#reverse for idx, i in sorted {
		if i + 1 < len(sorted) && sorted[i + 1] == idx do continue // duplicates
		if idx < 0 || idx >= Animation_SourceCount(a) do continue
		if a.renderFrame == FA_RenderFrame {
			fa := cast(^FrameAnimation)a
			t := fa.frames[idx]
			ordered_remove(&fa.frames, idx)
			if rm != nil && t != nil do ResourceManager_ReleaseTexture(rm, t)
		} else if a.renderFrame == SSA_RenderFrame {
			cells := sheet_cells(cast(^SpriteSheetAnimation)a, apn.allocator if apn != nil else context.allocator)
			ordered_remove(cells, idx)
		} else do continue
		removed += 1
		if idx < start {start -= 1; end -= 1} else if idx <= end do end -= 1
	}
	Animation_SetRange(a, start, max(end, start))
	if apn != nil do apn.currentFrame = clamp(apn.currentFrame, a.startFrame, a.endFrame)
	return removed
}

// Animation_CopyFrames puts source frames (in order) on a clip.
Animation_CopyFrames :: proc(a: ^Animation, indices: []int, clip: ^Frame_Clip) -> int {
	Frame_ClipClear(clip)
	sorted := slice.clone(indices, context.temp_allocator)
	slice.sort(sorted)
	for idx, i in sorted {
		if i > 0 && sorted[i - 1] == idx do continue
		if idx < 0 || idx >= Animation_SourceCount(a) do continue
		if a.renderFrame == FA_RenderFrame {
			fa := cast(^FrameAnimation)a
			if t := fa.frames[idx]; t != nil do append(&clip.paths, strings.clone(t.filePath))
		} else if a.renderFrame == SSA_RenderFrame {
			ssa := cast(^SpriteSheetAnimation)a
			append(&clip.cells, ssa.cells[idx] if len(ssa.cells) > 0 else idx)
			if clip.sheet == "" && ssa.spriteSheet != nil do clip.sheet = strings.clone(ssa.spriteSheet.filePath)
		}
	}
	return len(clip.paths) + len(clip.cells)
}

// Animation_PasteFrames inserts a clip's frames before source frame `at`
// (images into frame animations; cells into sheet animations of the same
// sheet). Returns how many were added.
Animation_PasteFrames :: proc(apn: ^AnimationPlayerNode, a: ^Animation, at: int, clip: ^Frame_Clip, rm: ^ResourceManager) -> int {
	if a == nil do return 0
	n := Animation_SourceCount(a)
	pos := clamp(at, 0, n)
	added := 0
	if a.renderFrame == FA_RenderFrame && len(clip.paths) > 0 && rm != nil {
		fa := cast(^FrameAnimation)a
		for p in clip.paths {
			t, ok := rm->loadTexture(p)
			if !ok || t == nil do continue
			inject_at(&fa.frames, pos + added, t)
			added += 1
		}
	} else if a.renderFrame == SSA_RenderFrame && len(clip.cells) > 0 {
		ssa := cast(^SpriteSheetAnimation)a
		if clip.sheet != "" && ssa.spriteSheet != nil && ssa.spriteSheet.filePath != clip.sheet do return 0
		cells := sheet_cells(ssa, apn.allocator if apn != nil else context.allocator)
		for c, i in clip.cells do inject_at(cells, pos + i, c)
		added = len(clip.cells)
	}
	if added == 0 do return 0
	start, end := a.startFrame, a.endFrame
	if n == 0 {
		start, end = 0, added - 1
	} else if pos < start {
		start += added; end += added // before the range: it moves along
	} else if pos <= end + 1 {
		end += added // at its start, inside or right after it: it grows
	}
	Animation_SetRange(a, start, end)
	return added
}

// Animation_MoveFrame moves a frame-animation image to another position.
Animation_MoveFrame :: proc(a: ^Animation, from, to: int) {
	if a == nil || a.renderFrame != FA_RenderFrame do return
	fa := cast(^FrameAnimation)a
	if from < 0 || from >= len(fa.frames) || to < 0 || to >= len(fa.frames) || from == to do return
	t := fa.frames[from]
	ordered_remove(&fa.frames, from)
	inject_at(&fa.frames, to, t)
}

// ============================================================================
// Managing a player's animations: rename, delete, duplicate.
// ============================================================================

// AnimationPlayerNode_FindAnimation: the index of the animation named `name`
// (-1 when there is none).
AnimationPlayerNode_FindAnimation :: proc(apn: ^AnimationPlayerNode, name: string) -> int {
	for a, i in apn.animations do if a.name == name do return i
	return -1
}

// AnimationPlayerNode_UniqueAnimationName: `base`, or `base_2`, `base_3`, ...
// when it is taken (temp allocated).
AnimationPlayerNode_UniqueAnimationName :: proc(apn: ^AnimationPlayerNode, base: string) -> string {
	if AnimationPlayerNode_FindAnimation(apn, base) < 0 do return base
	for i := 2; ; i += 1 {
		n := fmt.tprintf("%s_%d", base, i)
		if AnimationPlayerNode_FindAnimation(apn, n) < 0 do return n
	}
}

// AnimationPlayerNode_RenameAnimation renames an animation (and the default
// animation with it). Fails for an empty name or one another animation has.
AnimationPlayerNode_RenameAnimation :: proc(apn: ^AnimationPlayerNode, index: int, name: string) -> bool {
	if index < 0 || index >= len(apn.animations) do return false
	name := strings.trim_space(name)
	a := apn.animations[index]
	if name == "" do return false
	if name == a.name do return true
	if AnimationPlayerNode_FindAnimation(apn, name) >= 0 do return false
	if apn.defaultAnimation == a.name do apn.defaultAnimation = strings.clone(name, apn.allocator)
	a.name = strings.clone(name, apn.allocator)
	return true
}

// AnimationPlayerNode_DeleteAnimation removes an animation (freed when the
// player owns it; its images go back to `rm`). The default animation is
// cleared with it; the next animation (or the previous) becomes current.
AnimationPlayerNode_DeleteAnimation :: proc(apn: ^AnimationPlayerNode, index: int, rm: ^ResourceManager) -> bool {
	if index < 0 || index >= len(apn.animations) do return false
	a := apn.animations[index]
	if apn.defaultAnimation == a.name do apn.defaultAnimation = ""
	if apn.blendFrom == a do apn.blendFrom = nil
	ordered_remove(&apn.animations, index)
	for o, i in apn.owned do if o == a {
		ordered_remove(&apn.owned, i)
		if a.renderFrame == FA_RenderFrame {
			fa := cast(^FrameAnimation)a
			if rm != nil do for t in fa.frames do if t != nil do ResourceManager_ReleaseTexture(rm, t)
			FrameAnimation_Destroy(fa)
		} else if a.renderFrame == SSA_RenderFrame {
			ssa := cast(^SpriteSheetAnimation)a
			if rm != nil && ssa.spriteSheet != nil do ResourceManager_ReleaseTexture(rm, ssa.spriteSheet)
		}
		break
	}
	if len(apn.animations) == 0 {
		apn.animationIndex, apn.currentFrame = 0, 0
	} else {
		AnimationPlayerNode_SetAnimationIndex(apn, min(index, len(apn.animations) - 1))
		if cur := AnimationPlayerNode_GetAnimation(apn); cur != nil do apn.currentFrame = cur.startFrame
	}
	return true
}

// AnimationPlayerNode_DuplicateAnimation copies an animation (frames,
// cells, range, settings and tracks) right after it as `<name>_copy` and
// makes the copy current.
AnimationPlayerNode_DuplicateAnimation :: proc(apn: ^AnimationPlayerNode, index: int, rm: ^ResourceManager) -> ^Animation {
	if index < 0 || index >= len(apn.animations) do return nil
	src := apn.animations[index]
	name := AnimationPlayerNode_UniqueAnimationName(apn, fmt.tprintf("%s_copy", src.name))
	dup: ^Animation
	if src.renderFrame == FA_RenderFrame {
		sfa := cast(^FrameAnimation)src
		fa := new(FrameAnimation, apn.allocator)
		fa^ = sfa^
		fa.frames = make([dynamic]^Texture, apn.allocator)
		for t in sfa.frames {
			if t == nil do continue
			if rm != nil {
				if nt, ok := rm->loadTexture(t.filePath); ok && nt != nil do append(&fa.frames, nt) // one more reference
			} else do append(&fa.frames, t)
		}
		dup = fa
	} else if src.renderFrame == SSA_RenderFrame {
		sssa := cast(^SpriteSheetAnimation)src
		ssa := new(SpriteSheetAnimation, apn.allocator)
		ssa^ = sssa^
		ssa.cells = nil
		if len(sssa.cells) > 0 do SpriteSheetAnimation_SetCells(ssa, sssa.cells[:], apn.allocator)
		ssa.startFrame, ssa.endFrame = sssa.startFrame, sssa.endFrame
		ssa.spriteSheet = nil
		if sssa.spriteSheet != nil {
			if rm != nil {
				if t, ok := rm->loadTexture(sssa.spriteSheet.filePath); ok do ssa.spriteSheet = t
			} else do ssa.spriteSheet = sssa.spriteSheet
		}
		dup = ssa
	} else do return nil
	dup.name = strings.clone(name, apn.allocator)
	dup.tracks = nil
	for tr in src.tracks {
		nt := Animation_AddTrack(apn, dup, tr.target, tr.property)
		nt.kind = tr.kind
		for k in tr.keys {
			nk := k
			if k.text != "" do nk.text = strings.clone(k.text, apn.allocator)
			append(&nt.keys, nk)
		}
	}
	append(&apn.owned, dup)
	inject_at(&apn.animations, index + 1, dup)
	AnimationPlayerNode_SetAnimationIndex(apn, index + 1)
	apn.currentFrame = dup.startFrame
	return dup
}
