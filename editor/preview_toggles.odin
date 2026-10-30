package editor

import "core:fmt"
import imgui "lib/imgui"

// Preview_Toggles: Autoplay, Loop and the volume for previews while
// browsing - the File Browser and the Assets' Preview panel share them
// (settings.ini [preview]; #203). True when the volume changed.
Preview_Toggles :: proc(id: string) -> (volumeChanged: bool) {
	s := &GlobalSettings
	if UI_IconButton(ICON_FA_CIRCLE_PLAY, fmt.tprintf("%s.autoplay", id), "Autoplay on: a selected sound or animation plays (click: off)" if s.previewAutoplay else "Autoplay: play a sound or animation when it's selected", s.previewAutoplay, 26) {
		s.previewAutoplay = !s.previewAutoplay
		_ = Editor_SaveSettings()
	}
	imgui.SameLine(0, 2)
	if UI_IconButton(ICON_FA_REPEAT, fmt.tprintf("%s.loop", id), "Loop on (click: play once)" if s.previewLoop else "Loop: play again from the start", s.previewLoop, 26) {
		s.previewLoop = !s.previewLoop
		_ = Editor_SaveSettings()
	}
	imgui.SameLine(0, 6)
	imgui.AlignTextToFramePadding()
	imgui.TextUnformatted(ICON_FA_VOLUME_HIGH)
	imgui.SameLine(0, 4)
	imgui.SetNextItemWidth(80)
	volumeChanged = imgui.SliderFloat(fmt.ctprintf("##%s_volume", id), &s.previewVolume, 0, 1, "%.2f")
	if imgui.IsItemDeactivatedAfterEdit() do _ = Editor_SaveSettings()
	Drive_Item(fmt.tprintf("%s.volume", id))
	UI_Tooltip("Preview volume (sounds while browsing)")
	return
}
