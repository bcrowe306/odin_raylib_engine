package editor

import "core:fmt"
import imgui "lib/imgui"

// ============================================================================
// Tooltip Utility for Editor Widgets
// Exposes rich hover tooltips with GitKraken-styled dark frames
// ============================================================================

Editor_Tooltip :: proc(text: string) {
	if imgui.IsItemHovered() {
		if imgui.BeginTooltip() {
			imgui.PushStyleVarImVec2(imgui.StyleVar.WindowPadding, imgui.Vec2{8, 6})
			imgui.Text(fmt.ctprintf("%s", text))
			imgui.PopStyleVar()
			imgui.EndTooltip()
		}
	}
}

Editor_Tooltip_Formatted :: proc(format: string, args: ..any) {
	if imgui.IsItemHovered() {
		if imgui.BeginTooltip() {
			imgui.PushStyleVarImVec2(imgui.StyleVar.WindowPadding, imgui.Vec2{8, 6})
			msg := fmt.tprintf(format, ..args)
			imgui.Text(fmt.ctprintf("%s", msg))
			imgui.PopStyleVar()
			imgui.EndTooltip()
		}
	}
}
