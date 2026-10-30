package editor

import "core:c"
import "core:fmt"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// A Sound Effect's sounds in the Inspector (#204): a row per sound - its
// file, its weight (Random), preview, remove; drag a row's number onto
// another to reorder; drop audio from Assets on the list to add; + adds.
// ============================================================================

SOUND_ROW_PAYLOAD :: "RAYZR_SOUND_ROW"

Inspector_SoundList :: proc(state: ^EditorState, sn: ^e.SoundNode) {
	rm := &state.game.resourceManager
	ctx := &state.game.gameContext
	files := Editor_ListProjectFiles(state, "audio", AUDIO_EXTS)
	weights := sn.playMode == .Random
	remove, moveFrom, moveTo := -1, -1, -1
	for &s, i in sn.sounds {
		imgui.PushIDInt(c.int(i))
		// The number: drag it onto another row to reorder.
		imgui.TableNextRow()
		imgui.TableNextColumn()
		imgui.PushStyleColorImVec4(.Text, UI_TEXT_DIM)
		imgui.Selectable(fmt.ctprintf("Sound %d##row", i + 1), false, {}, {0, imgui.GetFrameHeight()})
		imgui.PopStyleColor()
		if imgui.BeginDragDropSource({}) {
			idx := c.int(i)
			imgui.SetDragDropPayload(SOUND_ROW_PAYLOAD, &idx, size_of(c.int))
			imgui.TextUnformatted(fmt.ctprintf("Sound %d", i + 1))
			imgui.EndDragDropSource()
		}
		if imgui.BeginDragDropTarget() {
			if pl := imgui.AcceptDragDropPayload(SOUND_ROW_PAYLOAD); pl != nil do moveFrom, moveTo = int((cast(^c.int)pl.Data)^), i
			imgui.EndDragDropTarget()
		}
		Drive_Item(fmt.tprintf("insp.sound-row:%d", i + 1))
		UI_Tooltip("Drag onto another sound to reorder")
		imgui.TableNextColumn()
		// The file, then play / remove (fits a narrow Inspector).
		imgui.SetNextItemWidth(max(imgui.GetContentRegionAvail().x - 52, 40))
		current := asset_rel_editor(state, s.path)
		if path, ok := asset_picker(fmt.tprintf("insp.sound:%d", i + 1), current, files, allowNone = false); ok && path != current {
			Editor_RecordUndo(state, "Change sound")
			AudioPreview_Stop()
			w := s.weight
			e.SoundNode_RemoveSound(sn, rm, i)
			e.SoundNode_AddSound(sn, rm, e.Project_ResolveAssetPath(ctx, path), w)
			e.SoundNode_MoveSound(sn, len(sn.sounds) - 1, i)
			imgui.PopID()
			return // (the list changed)
		}
		imgui.SameLine(0, 2)
		playing := AudioPreview_PlayingSound(sn, i)
		if UI_IconButton(ICON_FA_STOP if playing else ICON_FA_PLAY, fmt.tprintf("insp.sound-play:%d", i + 1), "Stop" if playing else "Hear this one", size = 24) {
			if playing do AudioPreview_Stop()
			else do AudioPreview_PlaySound(state, sn, i)
		}
		imgui.SameLine(0, 2)
		if UI_IconButton(ICON_FA_XMARK, fmt.tprintf("insp.sound-remove:%d", i + 1), "Remove this sound", size = 24) do remove = i
		if weights {
			UI_PropLabel("    weight")
			imgui.DragFloat("##weight", &s.weight, 0.02, 0, 10, "%.2f")
			undo_on_activate(state, "Sound weight")
			Drive_Item(fmt.tprintf("insp.sound-weight:%d", i + 1))
			UI_Tooltip("How likely Random picks it (1: as likely as the others; 0: never)")
		}
		imgui.PopID()
	}
	if remove >= 0 {
		Editor_RecordUndo(state, "Remove sound")
		AudioPreview_Stop()
		e.SoundNode_RemoveSound(sn, rm, remove)
	}
	if moveFrom >= 0 && moveFrom != moveTo {
		Editor_RecordUndo(state, "Reorder sounds")
		e.SoundNode_MoveSound(sn, moveFrom, moveTo)
	}
	// Add: a picker (or drop audio from Assets here).
	UI_PropLabel("" if len(sn.sounds) > 0 else "Sounds")
	imgui.SetNextItemWidth(-1)
	if imgui.BeginCombo("##sound_add", fmt.ctprintf("%s  Add Sound%s", ICON_FA_PLUS, "" if len(sn.sounds) > 0 else " (or drop audio here)")) {
		for f in files {
			if imgui.Selectable(strings.clone_to_cstring(f, context.temp_allocator)) {
				Editor_RecordUndo(state, "Add sound")
				e.SoundNode_AddSound(sn, rm, e.Project_ResolveAssetPath(ctx, f))
			}
			Drive_Item(fmt.tprintf("pick:%s", f))
		}
		if len(files) == 0 do UI_DimText("No audio in the project yet: import some (Assets +).")
		imgui.EndCombo()
	}
	Drive_Item("insp.sound-add")
	if imgui.BeginDragDropTarget() {
		if pl := imgui.AcceptDragDropPayload(ASSET_PAYLOAD); pl != nil {
			p := (^Asset_Payload)(pl.Data)
			rel := strings.clone(string(p.path[:p.len]), context.temp_allocator)
			if Asset_KindOf(rel) == .Audio {
				Editor_RecordUndo(state, "Add sound")
				e.SoundNode_AddSound(sn, rm, e.Project_ResolveAssetPath(ctx, rel))
			}
		}
		imgui.EndDragDropTarget()
	}
	UI_Tooltip("Add a sound - or drop audio from Assets. Play Mode picks what plays: one, all, in turn, at random")
}
