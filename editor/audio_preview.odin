package editor

import "core:fmt"
import "core:math/rand"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Sound previews in the Inspector (#196): a Sound Effect or Music node's
// sound played from its Audio section - through the node's bus, at its
// volume and pitch (not positioned) - without touching the node (nothing
// saved, no `finished` event). A Sound Effect plays by its play mode, each
// sound with its variation and Delay Random (#204); its list's rows play one.
// Sequential / Shuffle step through the list on the preview's own position,
// not the node's (#217); the Cooldown doesn't apply (one play at a time).
// Stops when the selection changes, the node goes, Simulate starts or the
// sound ends.
// ============================================================================

@(private = "file")
preview: struct {
	node:   ^e.Node,
	voices: [e.AUDIO_MAX_VOICES]e.Mixer_Voice_Handle,
	sound:   int, // a list row's sound (-1: the node's play)
	pending: [dynamic]Preview_Pending, // sounds waiting out their Delay Random
}

@(private = "file")
Preview_Pending :: struct {
	left: f32,
	i, k: int,
}

// The preview's place in a Sound Effect's Sequential / Shuffle order.
@(private = "file")
previewSeq: struct {
	node:                 ^e.Node,
	count:                int,
	nextIndex, lastIndex: int,
	bag:                  [dynamic]int,
}

// preview_pick: SoundNode_Pick on the preview's own order (the node's stays).
@(private = "file")
preview_pick :: proc(sn: ^e.SoundNode) -> []int {
	if previewSeq.node != sn || previewSeq.count != len(sn.sounds) {
		delete(previewSeq.bag)
		previewSeq = {node = sn, count = len(sn.sounds), lastIndex = -1}
	}
	tmp := sn^
	tmp.nextIndex, tmp.lastIndex, tmp.bag, tmp.allocator = previewSeq.nextIndex, previewSeq.lastIndex, previewSeq.bag, context.allocator
	out := e.SoundNode_Pick(&tmp)
	previewSeq.nextIndex, previewSeq.lastIndex, previewSeq.bag = tmp.nextIndex, tmp.lastIndex, tmp.bag
	return out
}

@(private = "file")
any_playing :: proc() -> bool {
	for v in preview.voices do if e.Mixer_VoicePlaying(v) do return true
	return len(preview.pending) > 0
}

AudioPreview_Playing :: proc(node: ^e.Node) -> bool {
	return preview.node == node && node != nil && any_playing()
}

// AudioPreview_PlayingSound: one of a Sound Effect's rows is playing.
AudioPreview_PlayingSound :: proc(sn: ^e.SoundNode, i: int) -> bool {
	return AudioPreview_Playing(sn) && preview.sound == i
}

AudioPreview_Stop :: proc() {
	if preview.node != nil do for v in preview.voices do e.Mixer_StopVoice(v)
	delete(preview.pending)
	preview = {}
}

// play_entry: sound i of a Sound Effect with a variation, in voice slot k.
@(private = "file")
play_entry :: proc(sn: ^e.SoundNode, i, k: int) {
	if i < 0 || i >= len(sn.sounds) do return
	audio := sn.sounds[i].audio
	if audio == nil || len(audio.pcm) == 0 || k >= len(preview.voices) do return
	v := e.SoundNode_RollVariation(sn)
	preview.voices[k] = e.Mixer_PlaySound(audio.pcm, e.SoundNode_BusIndex(sn), max(sn.volume + v.volume, 0), clamp(v.pan, -1, 1), max(sn.pitch * v.pitch, 0.01), owner = audio)
}

// AudioPreview_Play plays a node's sound: a Sound Effect by its play mode
// (All: every sound; each with its variation), a Music node's music.
AudioPreview_Play :: proc(state: ^EditorState, node: ^e.Node) -> bool {
	AudioPreview_Stop()
	if node == nil || !e.Audio_Ready() do return false
	switch node.typeId {
	case e.SoundNode:
		sn := cast(^e.SoundNode)node
		if len(sn.sounds) == 0 do return false
		for i, k in preview_pick(sn) {
			if sn.delayRandom > 0 {
				if d := rand.float32_range(0, sn.delayRandom); d > 0.001 {
					append(&preview.pending, Preview_Pending{d, i, k})
					continue
				}
			}
			play_entry(sn, i, k)
		}
	case e.MusicNode:
		mn := cast(^e.MusicNode)node
		if mn.music == nil do return false
		preview.voices[0] = e.Mixer_PlayMusic(mn.music.music, e.MusicNode_BusIndex(mn), e.MusicNode_EffectiveVolume(mn), false, owner = mn.music)
		e.Mixer_SetVoice(preview.voices[0], e.MusicNode_EffectiveVolume(mn), 0, mn.pitch)
	case:
		return false
	}
	preview.node = node
	preview.sound = -1
	return true
}

// AudioPreview_PlaySound plays one sound of a Sound Effect's list.
AudioPreview_PlaySound :: proc(state: ^EditorState, sn: ^e.SoundNode, i: int) {
	AudioPreview_Stop()
	if sn == nil || i < 0 || i >= len(sn.sounds) || !e.Audio_Ready() do return
	play_entry(sn, i, 0)
	preview.node = sn
	preview.sound = i
}

// AudioPreview_Update: every frame - the preview ends with its node's
// selection, the node, or Simulate.
AudioPreview_Update :: proc(state: ^EditorState) {
	if preview.node == nil do return
	// Sounds whose Delay Random is up.
	if len(preview.pending) > 0 && e.Node_IsAlive(preview.node) {
		sn := cast(^e.SoundNode)preview.node
		dt := imgui.GetIO().DeltaTime
		for j := len(preview.pending) - 1; j >= 0; j -= 1 {
			p := &preview.pending[j]
			p.left -= dt
			if p.left > 0 do continue
			play_entry(sn, p.i, p.k)
			ordered_remove(&preview.pending, j)
		}
	}
	if !e.Node_IsAlive(preview.node) || state.selectedNode != preview.node || state.isSimulating || !any_playing() {
		AudioPreview_Stop()
	}
}

// AudioPreview_Row: the Inspector's Preview row - Play / Stop (and the
// sound's length when there's one).
AudioPreview_Row :: proc(state: ^EditorState, node: ^e.Node) {
	hasAudio := false
	length: f32
	switch node.typeId {
	case e.SoundNode:
		sn := cast(^e.SoundNode)node
		if first := e.SoundNode_FirstSound(sn); first != nil && len(first.pcm) > 0 {
			hasAudio = true
			if len(sn.sounds) == 1 do length = f32(len(first.pcm) / 2) / f32(e.MIXER_RATE)
		}
	case e.MusicNode:
		mn := cast(^e.MusicNode)node
		hasAudio = mn.music != nil
	}
	UI_PropLabel("Preview")
	playing := AudioPreview_Playing(node) && preview.sound < 0
	if !hasAudio do imgui.BeginDisabled(true)
	label := fmt.tprintf("%s  Stop", ICON_FA_STOP) if playing else fmt.tprintf("%s  Play", ICON_FA_PLAY)
	// (Room for the length after it in a narrow Inspector.)
	w := clamp(imgui.GetContentRegionAvail().x - (60 if length > 0 else 0), 60, 140)
	if UI_Button(label, "insp.audio-preview", {w, 0}) {
		if playing do AudioPreview_Stop()
		else do AudioPreview_Play(state, node)
	}
	if !hasAudio do imgui.EndDisabled()
	tip := "Hear it here: through its bus, at its volume and pitch (not positioned). Stops when you select something else."
	if node.typeId == e.SoundNode do tip = "Hear a play: by its Play Mode, with its variation and Delay Random, through its bus (not positioned; no Cooldown). Stops when you select something else."
	UI_Tooltip(tip if hasAudio else "Pick an audio file first")
	if length > 0 {
		imgui.SameLine()
		UI_DimText(fmt.tprintf("%.2f s", length))
	}
}
