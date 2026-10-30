package editor

import "core:fmt"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Sound previews in the Inspector (#196): a Sound Effect or Music node's
// sound played from its Audio section - through the node's bus, at its
// volume and pitch (not positioned) - without touching the node (nothing
// saved, no `finished` event). A Sound Effect plays by its play mode, each
// sound with its variation (#204); its list's rows play one. Stops when the
// selection changes, the node goes, Simulate starts or the sound ends.
// ============================================================================

@(private = "file")
preview: struct {
	node:   ^e.Node,
	voices: [e.AUDIO_MAX_VOICES]e.Mixer_Voice_Handle,
	sound:  int, // a list row's sound (-1: the node's play)
}

@(private = "file")
any_playing :: proc() -> bool {
	for v in preview.voices do if e.Mixer_VoicePlaying(v) do return true
	return false
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
	preview = {}
}

// play_entry: sound i of a Sound Effect with a variation, in voice slot k.
@(private = "file")
play_entry :: proc(sn: ^e.SoundNode, i, k: int) {
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
		for i, k in e.SoundNode_Pick(sn) do play_entry(sn, i, k)
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
	if node.typeId == e.SoundNode do tip = "Hear a play: by its Play Mode, with its variation, through its bus (not positioned). Stops when you select something else."
	UI_Tooltip(tip if hasAudio else "Pick an audio file first")
	if length > 0 {
		imgui.SameLine()
		UI_DimText(fmt.tprintf("%.2f s", length))
	}
}
