package editor

import "core:fmt"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Sound previews in the Inspector (#196): a Sound Effect or Music node's
// sound played from its Audio section - through the node's bus, at its
// volume and pitch (not positioned) - without touching the node (nothing
// saved, no `finished` event). Stops when the selection changes, the node
// goes, Simulate starts or the sound ends.
// ============================================================================

@(private = "file")
preview: struct {
	node:  ^e.Node,
	voice: e.Mixer_Voice_Handle,
}

AudioPreview_Playing :: proc(node: ^e.Node) -> bool {
	return preview.node == node && node != nil && e.Mixer_VoicePlaying(preview.voice)
}

AudioPreview_Stop :: proc() {
	if preview.node != nil do e.Mixer_StopVoice(preview.voice)
	preview = {}
}

// AudioPreview_Play plays a node's sound (a Sound Effect or Music node).
AudioPreview_Play :: proc(state: ^EditorState, node: ^e.Node) -> bool {
	AudioPreview_Stop()
	if node == nil || !e.Audio_Ready() do return false
	switch node.typeId {
	case e.SoundNode:
		sn := cast(^e.SoundNode)node
		if sn.audio == nil || len(sn.audio.pcm) == 0 do return false
		preview.voice = e.Mixer_PlaySound(sn.audio.pcm, e.SoundNode_BusIndex(sn), sn.volume, 0, sn.pitch, owner = sn.audio)
	case e.MusicNode:
		mn := cast(^e.MusicNode)node
		if mn.music == nil do return false
		preview.voice = e.Mixer_PlayMusic(mn.music.music, e.MusicNode_BusIndex(mn), e.MusicNode_EffectiveVolume(mn), false, owner = mn.music)
		e.Mixer_SetVoice(preview.voice, e.MusicNode_EffectiveVolume(mn), 0, mn.pitch)
	case:
		return false
	}
	preview.node = node
	return true
}

// AudioPreview_Update: every frame - the preview ends with its node's
// selection, the node, or Simulate.
AudioPreview_Update :: proc(state: ^EditorState) {
	if preview.node == nil do return
	if !e.Node_IsAlive(preview.node) || state.selectedNode != preview.node || state.isSimulating || !e.Mixer_VoicePlaying(preview.voice) {
		AudioPreview_Stop()
	}
}

// AudioPreview_Row: the Inspector's Preview row - Play / Stop and the length.
AudioPreview_Row :: proc(state: ^EditorState, node: ^e.Node) {
	hasAudio := false
	length: f32
	switch node.typeId {
	case e.SoundNode:
		sn := cast(^e.SoundNode)node
		if sn.audio != nil && len(sn.audio.pcm) > 0 {
			hasAudio = true
			length = f32(len(sn.audio.pcm) / 2) / f32(e.MIXER_RATE)
		}
	case e.MusicNode:
		mn := cast(^e.MusicNode)node
		hasAudio = mn.music != nil
	}
	UI_PropLabel("Preview")
	playing := AudioPreview_Playing(node)
	if !hasAudio do imgui.BeginDisabled(true)
	label := fmt.tprintf("%s  Stop", ICON_FA_STOP) if playing else fmt.tprintf("%s  Play", ICON_FA_PLAY)
	// (Room for the length after it in a narrow Inspector.)
	w := clamp(imgui.GetContentRegionAvail().x - (60 if length > 0 else 0), 60, 140)
	if UI_Button(label, "insp.audio-preview", {w, 0}) {
		if playing do AudioPreview_Stop()
		else do AudioPreview_Play(state, node)
	}
	if !hasAudio do imgui.EndDisabled()
	UI_Tooltip("Hear it here: through its bus, at its volume and pitch (not positioned). Stops when you select something else." if hasAudio else "Pick an audio file first")
	if length > 0 {
		imgui.SameLine()
		UI_DimText(fmt.tprintf("%.2f s", length))
	}
}
