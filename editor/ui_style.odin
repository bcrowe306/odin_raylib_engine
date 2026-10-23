package editor

import "core:fmt"
import "core:os"
import "core:strings"
import "core:unicode/utf8"
import imgui "lib/imgui"

// ============================================================================
// Editor look & feel: a flat, quiet dark theme.
//
// Principles: surfaces are separated by tone, not lines (no window/child
// borders, no separators between sections); one accent colour marks what is
// active; generous, consistent spacing (8px grid); labels are dim and values
// bright; section headers are small caps-style text instead of filled bars.
// Panels use the helpers below so spacing stays consistent everywhere.
// ============================================================================

// Palette (sRGB 0..1): set from the editor theme (theme.odin, Settings >
// General > Theme); these are the Default theme's colours until then.
UI_BG_APP      := imgui.Vec4{0.067, 0.075, 0.090, 1} // window background / gaps
UI_BG_PANEL    := imgui.Vec4{0.090, 0.102, 0.122, 1} // panels
UI_BG_RAISED   := imgui.Vec4{0.118, 0.133, 0.161, 1} // inputs, cards
UI_BG_HOVER    := imgui.Vec4{0.149, 0.169, 0.204, 1}
UI_BG_ACTIVE   := imgui.Vec4{0.180, 0.204, 0.247, 1}
UI_TEXT        := imgui.Vec4{0.871, 0.886, 0.910, 1}
UI_TEXT_DIM    := imgui.Vec4{0.553, 0.584, 0.635, 1}
UI_TEXT_FAINT  := imgui.Vec4{0.380, 0.408, 0.455, 1}
UI_ACCENT      := imgui.Vec4{0.361, 0.553, 1.000, 1}
UI_ACCENT_SOFT := imgui.Vec4{0.361, 0.553, 1.000, 0.18}
UI_SUCCESS     := imgui.Vec4{0.298, 0.808, 0.553, 1}
UI_WARNING     := imgui.Vec4{0.961, 0.722, 0.298, 1}
UI_DANGER      := imgui.Vec4{0.937, 0.373, 0.373, 1}
CODE_BG        := imgui.Vec4{0.071, 0.078, 0.094, 1}
UI_LINE_RGB    := [3]f32{1, 1, 1} // faint lines / borders: the text side of the theme
UI_THEME_LIGHT := false           // light backgrounds (darker syntax colours)

// ui_accent: the accent colour with alpha `a`.
ui_accent :: proc(a: f32) -> imgui.Vec4 {
	return {UI_ACCENT.x, UI_ACCENT.y, UI_ACCENT.z, a}
}

// ui_line: a faint line / border colour with alpha `a` (white on dark
// themes, dark on light ones).
ui_line :: proc(a: f32) -> imgui.Vec4 {
	return {UI_LINE_RGB.x, UI_LINE_RGB.y, UI_LINE_RGB.z, a * (1.6 if UI_THEME_LIGHT else 1)}
}

UI_SPACE :: 8.0 // base spacing unit

UI_Fonts :: struct {
	regular:  ^imgui.Font,
	semibold: ^imgui.Font,
	small:    ^imgui.Font,
	mono:     ^imgui.Font, // code editor (nil -> regular)
	ruler:    ^imgui.Font, // viewport ruler numbers: small, drawn at its own size
}

GlobalFonts: UI_Fonts

ui_fa_ranges: [3]imgui.Wchar = {0xE000, 0xF8FF, 0}
// Latin-1 plus punctuation (– — · … “ ”) and arrows.
ui_text_ranges: [7]imgui.Wchar = {0x0020, 0x00FF, 0x2000, 0x206F, 0x2190, 0x21FF, 0}

// UI_LoadFonts loads Open Sans (regular/semibold/small) with Font Awesome
// icons merged into each.
UI_LoadFonts :: proc() {
	io := imgui.GetIO()
	add :: proc(io: ^imgui.IO, path: cstring, size: f32) -> ^imgui.Font {
		font := imgui.FontAtlas_AddFontFromFileTTF(io.Fonts, path, size, nil, &ui_text_ranges[0])
		cfg: imgui.FontConfig
		cfg.FontDataOwnedByAtlas = true
		cfg.OversampleH = 2
		cfg.OversampleV = 1
		cfg.RasterizerMultiply = 1.0
		cfg.RasterizerDensity = 1.0
		cfg.EllipsisChar = max(u16)
		cfg.MergeMode = true
		cfg.GlyphMinAdvanceX = size
		cfg.GlyphOffset = {0, 0.5}
		imgui.FontAtlas_AddFontFromFileTTF(io.Fonts, "ui/fonts/fa-solid-900.ttf", size * 0.86, &cfg, &ui_fa_ranges[0])
		return font
	}
	GlobalFonts.regular = add(io, "engine/Open_Sans/static/OpenSans-Regular.ttf", 15)
	GlobalFonts.semibold = add(io, "engine/Open_Sans/static/OpenSans-SemiBold.ttf", 15)
	GlobalFonts.small = add(io, "engine/Open_Sans/static/OpenSans-Medium.ttf", 12.5)
	GlobalFonts.ruler = imgui.FontAtlas_AddFontFromFileTTF(io.Fonts, "engine/Open_Sans/static/OpenSans-SemiBold.ttf", 11, nil, &ui_text_ranges[0])
	for path in ([]cstring{"/System/Library/Fonts/SFNSMono.ttf", "/System/Library/Fonts/Menlo.ttc", "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", "C:/Windows/Fonts/consola.ttf"}) {
		if os.exists(string(path)) {
			GlobalFonts.mono = imgui.FontAtlas_AddFontFromFileTTF(io.Fonts, path, CODE_FONT_SIZE)
			break
		}
	}
}

// UI_ApplyTheme sets ImGui's style to the editor theme.
UI_ApplyTheme :: proc() {
	style := imgui.GetStyle()

	style.WindowRounding = 0
	style.ChildRounding = 6
	style.FrameRounding = 5
	style.PopupRounding = 8
	style.ScrollbarRounding = 8
	style.GrabRounding = 5
	style.TabRounding = 5

	style.WindowBorderSize = 0
	style.ChildBorderSize = 0
	style.FrameBorderSize = 0
	style.PopupBorderSize = 1
	style.TabBorderSize = 0
	style.TabBarBorderSize = 0
	style.SeparatorTextBorderSize = 1

	style.WindowPadding = {12, 10}
	style.FramePadding = {8, 5}
	style.CellPadding = {6, 4}
	style.ItemSpacing = {8, 6}
	style.ItemInnerSpacing = {6, 4}
	style.IndentSpacing = 14
	style.ScrollbarSize = 10
	style.GrabMinSize = 10
	style.WindowTitleAlign = {0, 0.5}
	style.WindowMenuButtonPosition = .None
	style.DockingSeparatorSize = 3
	style.SelectableTextAlign = {0, 0.5}

	c := &style.Colors
	c[imgui.Col.Text] = UI_TEXT
	c[imgui.Col.TextDisabled] = UI_TEXT_FAINT
	c[imgui.Col.WindowBg] = UI_BG_PANEL
	c[imgui.Col.ChildBg] = {0, 0, 0, 0}
	// Popups: one tone from the inputs on them (panel tone on light themes).
	popup := UI_BG_PANEL if UI_THEME_LIGHT else (UI_BG_PANEL + UI_BG_RAISED) * 0.5
	c[imgui.Col.PopupBg] = {popup.x, popup.y, popup.z, 0.99}
	c[imgui.Col.Border] = ui_line(0.06)
	c[imgui.Col.BorderShadow] = {0, 0, 0, 0}
	c[imgui.Col.FrameBg] = UI_BG_RAISED
	c[imgui.Col.FrameBgHovered] = UI_BG_HOVER
	c[imgui.Col.FrameBgActive] = UI_BG_ACTIVE
	c[imgui.Col.TitleBg] = UI_BG_APP
	c[imgui.Col.TitleBgActive] = UI_BG_APP
	c[imgui.Col.TitleBgCollapsed] = UI_BG_APP
	c[imgui.Col.MenuBarBg] = UI_BG_APP
	c[imgui.Col.ScrollbarBg] = {0, 0, 0, 0}
	c[imgui.Col.ScrollbarGrab] = ui_line(0.10)
	c[imgui.Col.ScrollbarGrabHovered] = ui_line(0.18)
	c[imgui.Col.ScrollbarGrabActive] = ui_line(0.26)
	c[imgui.Col.CheckMark] = UI_ACCENT
	c[imgui.Col.SliderGrab] = UI_ACCENT
	c[imgui.Col.SliderGrabActive] = ui_accent(1)
	c[imgui.Col.Button] = UI_BG_RAISED
	c[imgui.Col.ButtonHovered] = UI_BG_HOVER
	c[imgui.Col.ButtonActive] = UI_BG_ACTIVE
	c[imgui.Col.Header] = UI_ACCENT_SOFT
	c[imgui.Col.HeaderHovered] = ui_line(0.05)
	c[imgui.Col.HeaderActive] = ui_accent(0.26)
	c[imgui.Col.Separator] = ui_line(0.06)
	c[imgui.Col.SeparatorHovered] = UI_ACCENT_SOFT
	c[imgui.Col.SeparatorActive] = UI_ACCENT
	c[imgui.Col.ResizeGrip] = {0, 0, 0, 0}
	c[imgui.Col.ResizeGripHovered] = UI_ACCENT_SOFT
	c[imgui.Col.ResizeGripActive] = UI_ACCENT
	c[imgui.Col.Tab] = UI_BG_APP
	c[imgui.Col.TabHovered] = UI_BG_HOVER
	c[imgui.Col.TabSelected] = UI_BG_PANEL
	c[imgui.Col.TabSelectedOverline] = UI_ACCENT
	c[imgui.Col.TabDimmed] = UI_BG_APP
	c[imgui.Col.TabDimmedSelected] = UI_BG_PANEL
	c[imgui.Col.TabDimmedSelectedOverline] = {0, 0, 0, 0}
	c[imgui.Col.DockingPreview] = UI_ACCENT_SOFT
	c[imgui.Col.DockingEmptyBg] = UI_BG_APP
	c[imgui.Col.TableHeaderBg] = UI_BG_PANEL
	c[imgui.Col.TableBorderStrong] = {0, 0, 0, 0}
	c[imgui.Col.TableBorderLight] = {0, 0, 0, 0}
	c[imgui.Col.TableRowBg] = {0, 0, 0, 0}
	c[imgui.Col.TableRowBgAlt] = ui_line(0.02)
	c[imgui.Col.TextSelectedBg] = ui_accent(0.35)
	c[imgui.Col.NavHighlight] = UI_ACCENT
	c[imgui.Col.ModalWindowDimBg] = {0, 0, 0, 0.55}
}

col_u32 :: proc(c: imgui.Vec4) -> u32 {
	return imgui.ColorConvertFloat4ToU32(c)
}

// --- widgets ---------------------------------------------------------------------

// UI_Tooltip shows a tooltip after the normal hover delay.
UI_Tooltip :: proc(text: string) {
	if imgui.IsItemHovered(imgui.HoveredFlags_DelayNormal | imgui.HoveredFlags_Stationary) {
		imgui.SetTooltip("%s", strings.clone_to_cstring(text, context.temp_allocator))
	}
}

// UI_SectionHeader is a flat collapsing section: small dim caption, no bar.
UI_SectionHeader :: proc(label: string, default_open := true) -> bool {
	imgui.Dummy({0, 2})
	imgui.PushStyleColorImVec4(.Header, {0, 0, 0, 0})
	imgui.PushStyleColorImVec4(.HeaderHovered, {0, 0, 0, 0})
	imgui.PushStyleColorImVec4(.HeaderActive, {0, 0, 0, 0})
	imgui.PushStyleColorImVec4(.Text, UI_TEXT_DIM)
	imgui.PushFont(GlobalFonts.semibold)
	flags: imgui.TreeNodeFlags = {.SpanAvailWidth, .NoTreePushOnOpen}
	if default_open do flags += {.DefaultOpen}
	open := imgui.CollapsingHeader(strings.clone_to_cstring(strings.to_upper(label, context.temp_allocator), context.temp_allocator), flags)
	imgui.PopFont()
	imgui.PopStyleColor(4)
	Drive_Item(fmt.tprintf("section:%s", label))
	return open
}

// UI_BeginProps starts a two-column property grid (dim label | widget).
UI_BeginProps :: proc(id: string) -> bool {
	if !imgui.BeginTable(strings.clone_to_cstring(id, context.temp_allocator), 2, imgui.TableFlags_SizingStretchProp) do return false
	imgui.TableSetupColumn("label", {.WidthStretch}, 0.36)
	imgui.TableSetupColumn("value", {.WidthStretch}, 0.64)
	return true
}

UI_EndProps :: proc() {
	imgui.EndTable()
}

// UI_PropLabel starts a row: draws the label and leaves the cursor in the
// value column with a full-width next item.
UI_PropLabel :: proc(label: string) {
	imgui.TableNextRow()
	imgui.TableNextColumn()
	imgui.AlignTextToFramePadding()
	imgui.PushStyleColorImVec4(.Text, UI_TEXT_DIM)
	imgui.TextUnformatted(strings.clone_to_cstring(label, context.temp_allocator))
	imgui.PopStyleColor()
	imgui.TableNextColumn()
	imgui.SetNextItemWidth(-1)
}

// UI_IconButton is a square, borderless icon button; `active` tints it
// with the accent.
UI_IconButton :: proc(icon: string, id: string, tooltip: string, active := false, size: f32 = 30, tint: imgui.Vec4 = {}) -> bool {
	if active {
		imgui.PushStyleColorImVec4(.Button, UI_ACCENT_SOFT)
		imgui.PushStyleColorImVec4(.ButtonHovered, ui_accent(0.28))
		imgui.PushStyleColorImVec4(.Text, UI_ACCENT)
	} else {
		imgui.PushStyleColorImVec4(.Button, {0, 0, 0, 0})
		imgui.PushStyleColorImVec4(.ButtonHovered, UI_BG_HOVER)
		imgui.PushStyleColorImVec4(.Text, tint if tint.w > 0 else UI_TEXT_DIM)
	}
	pressed := imgui.Button(fmt.ctprintf("%s##%s", icon, id), {size, size})
	imgui.PopStyleColor(3)
	Drive_Item(id)
	if tooltip != "" do UI_Tooltip(tooltip)
	return pressed
}

// UI_PrimaryButton is a filled accent button for the main action.
UI_PrimaryButton :: proc(label: string, id: string, size: imgui.Vec2 = {0, 0}) -> bool {
	imgui.PushStyleColorImVec4(.Button, UI_ACCENT)
	imgui.PushStyleColorImVec4(.ButtonHovered, {0.45, 0.62, 1, 1})
	imgui.PushStyleColorImVec4(.ButtonActive, {0.30, 0.48, 0.92, 1})
	imgui.PushStyleColorImVec4(.Text, {1, 1, 1, 1})
	pressed := imgui.Button(fmt.ctprintf("%s##%s", label, id), size)
	imgui.PopStyleColor(4)
	Drive_Item(id)
	return pressed
}

// UI_Button is a quiet secondary button.
UI_Button :: proc(label: string, id: string, size: imgui.Vec2 = {0, 0}) -> bool {
	pressed := imgui.Button(fmt.ctprintf("%s##%s", label, id), size)
	Drive_Item(id)
	return pressed
}

// UI_DimText draws secondary text.
UI_DimText :: proc(text: string) {
	imgui.PushStyleColorImVec4(.Text, UI_TEXT_DIM)
	imgui.TextUnformatted(strings.clone_to_cstring(text, context.temp_allocator))
	imgui.PopStyleColor()
}

// UI_VerticalDivider draws a short, faint divider in a horizontal toolbar.
UI_VerticalDivider :: proc(height: f32 = 20) {
	imgui.SameLine(0, UI_SPACE)
	pos := imgui.GetCursorScreenPos()
	dl := imgui.GetWindowDrawList()
	y := pos.y + (30 - height) * 0.5
	imgui.DrawList_AddLine(dl, {pos.x, y}, {pos.x, y + height}, col_u32(ui_line(0.08)), 1)
	imgui.Dummy({1, 30})
	imgui.SameLine(0, UI_SPACE)
}

// UI_PanelTitle draws a panel's heading row (icon + title + dim detail).
// Panel headers: a title and icon buttons on one row of PANEL_BUTTON
// height - UI_PanelTitle starts the row (text centred on it), then
// UI_HeaderButtons(n) moves to the right edge and UI_HeaderButton draws
// each button at the row's top, all the same size.
PANEL_BUTTON :: 26

@(private = "file")
headerRow: struct {
	y:     f32,
	first: bool,
}

UI_PanelTitle :: proc(icon, title: string, detail: string = "", maxWidth: f32 = 0) {
	headerRow = {imgui.GetCursorPosY(), true}
	imgui.SetCursorPosY(headerRow.y + max((PANEL_BUTTON - imgui.GetTextLineHeight()) * 0.5, 0))
	imgui.PushFont(GlobalFonts.semibold)
	imgui.PushStyleColorImVec4(.Text, UI_TEXT)
	text := fmt.tprintf("%s  %s", icon, title) if icon != "" else title
	if maxWidth > 0 && imgui.CalcTextSize(strings.clone_to_cstring(text, context.temp_allocator)).x > maxWidth {
		// Too long for the room left by the buttons: cut with an ellipsis.
		runes := utf8.string_to_runes(text, context.temp_allocator)
		for n := len(runes) - 1; n > 0; n -= 1 {
			t := fmt.tprintf("%s…", utf8.runes_to_string(runes[:n], context.temp_allocator))
			if imgui.CalcTextSize(strings.clone_to_cstring(t, context.temp_allocator)).x <= maxWidth {
				text = t
				break
			}
		}
	}
	imgui.TextUnformatted(strings.clone_to_cstring(text, context.temp_allocator))
	imgui.PopStyleColor()
	imgui.PopFont()
	if detail != "" {
		imgui.SameLine(0, UI_SPACE)
		UI_DimText(detail)
	}
}

// UI_HeaderButtons: the next `count` header buttons sit at the right edge.
UI_HeaderButtons :: proc(count: int) {
	w := f32(count) * PANEL_BUTTON + f32(max(count - 1, 0)) * 2
	imgui.SameLine(imgui.GetWindowContentRegionMax().x - w)
	headerRow.first = true
}

UI_HeaderButton :: proc(icon, id, tooltip: string, active := false) -> bool {
	if !headerRow.first do imgui.SameLine(0, 2)
	headerRow.first = false
	imgui.SetCursorPosY(headerRow.y)
	return UI_IconButton(icon, id, tooltip, active, PANEL_BUTTON)
}

// UI_Combo: a combo over `names`; returns the new index when changed.
UI_Combo :: proc(id: string, current: int, names: []string, mixed := false) -> (int, bool) {
	preview := MIXED_TEXT if mixed else names[current] if current >= 0 && current < len(names) else ""
	result, changed := current, false
	if imgui.BeginCombo(fmt.ctprintf("##%s", id), strings.clone_to_cstring(preview, context.temp_allocator)) {
		for n, i in names {
			if imgui.Selectable(strings.clone_to_cstring(n, context.temp_allocator), i == current) {
				result, changed = i, i != current || mixed
			}
			Drive_Item(fmt.tprintf("pick:%s", n))
		}
		imgui.EndCombo()
	}
	Drive_Item(id)
	return result, changed
}

// UI_BeginBanner / UI_EndBanner: a tinted, full-width block around the items
// between them. A group, not a child window, so its items exist (for
// keyboard focus and drives) even when scrolled out of view.
@(private = "file")
banner: struct {
	left, right: f32,
}

UI_BeginBanner :: proc() {
	PAD :: 6
	pos := imgui.GetCursorScreenPos()
	banner = {pos.x, pos.x + imgui.GetContentRegionAvail().x}
	dl := imgui.GetWindowDrawList()
	imgui.DrawList_ChannelsSplit(dl, 2)
	imgui.DrawList_ChannelsSetCurrent(dl, 1)
	imgui.BeginGroup()
	imgui.Dummy({0, PAD - imgui.GetStyle().ItemSpacing.y})
	imgui.Indent(PAD)
	imgui.PushTextWrapPos(banner.right - PAD - imgui.GetWindowPos().x)
}

UI_EndBanner :: proc(color: imgui.Vec4) {
	PAD :: 6
	imgui.PopTextWrapPos()
	imgui.Unindent(PAD)
	imgui.EndGroup()
	mn, mx := imgui.GetItemRectMin(), imgui.GetItemRectMax()
	dl := imgui.GetWindowDrawList()
	imgui.DrawList_ChannelsSetCurrent(dl, 0)
	imgui.DrawList_AddRectFilled(dl, {banner.left, mn.y}, {banner.right, mx.y + PAD}, col_u32(color), 4, {})
	imgui.DrawList_ChannelsMerge(dl)
	imgui.Dummy({0, PAD - imgui.GetStyle().ItemSpacing.y})
}
