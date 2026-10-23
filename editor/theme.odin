package editor

import "core:fmt"
import "core:strconv"
import "core:strings"
import imgui "lib/imgui"

// ============================================================================
// Editor themes: the palette the whole UI draws with (ui_style.odin's UI_*
// colours). Built-in presets - Default, Dark, Mid-day, Light - and any
// colour edited in Settings > General > Theme; saved in settings.ini's
// [theme] section (editor_settings.odin).
// ============================================================================

Theme_Color :: enum {
	BgApp,     // window background, gaps, tab bars
	BgPanel,   // panels
	BgRaised,  // inputs, buttons, cards, popups
	BgHover,
	BgActive,
	Text,
	TextDim,   // labels
	TextFaint, // hints
	Accent,    // what is selected / active
	Success,
	Warning,
	Danger,
	CodeBg,    // the code editor
}

THEME_COLOR_INFO := [Theme_Color]struct {key, label: string} {
	.BgApp     = {"bg_app", "App Background"},
	.BgPanel   = {"bg_panel", "Panels"},
	.BgRaised  = {"bg_raised", "Inputs & Cards"},
	.BgHover   = {"bg_hover", "Hover"},
	.BgActive  = {"bg_active", "Pressed"},
	.Text      = {"text", "Text"},
	.TextDim   = {"text_dim", "Labels"},
	.TextFaint = {"text_faint", "Hints"},
	.Accent    = {"accent", "Accent"},
	.Success   = {"success", "Success"},
	.Warning   = {"warning", "Warning"},
	.Danger    = {"danger", "Danger"},
	.CodeBg    = {"code_bg", "Code Background"},
}

Theme :: struct {
	name:   string, // a preset's name, or "Custom" once edited
	colors: [Theme_Color]imgui.Vec4,
}

Theme_Preset :: enum {
	Default,
	Dark,
	MidDay,
	Light,
}

THEME_PRESET_NAMES := [Theme_Preset]string {
	.Default = "Default",
	.Dark    = "Dark",
	.MidDay  = "Mid-day",
	.Light   = "Light",
}

@(private = "file")
hex :: proc(s: string) -> imgui.Vec4 {
	c, _ := theme_parse_color(s)
	return c
}

// Theme_PresetColors: a built-in theme.
Theme_PresetColors :: proc(p: Theme_Preset) -> (t: Theme) {
	t.name = THEME_PRESET_NAMES[p]
	switch p {
	case .Default:
		t.colors = {
			.BgApp = hex("#111317"), .BgPanel = hex("#171a1f"), .BgRaised = hex("#1e2229"), .BgHover = hex("#262b34"), .BgActive = hex("#2e343f"),
			.Text = hex("#dee2e8"), .TextDim = hex("#8d95a2"), .TextFaint = hex("#616874"),
			.Accent = hex("#5c8dff"), .Success = hex("#4cce8d"), .Warning = hex("#f5b84c"), .Danger = hex("#ef5f5f"), .CodeBg = hex("#121418"),
		}
	case .Dark:
		t.colors = {
			.BgApp = hex("#08090b"), .BgPanel = hex("#0e0f12"), .BgRaised = hex("#16181c"), .BgHover = hex("#1e2126"), .BgActive = hex("#272b31"),
			.Text = hex("#e6e8eb"), .TextDim = hex("#8b9099"), .TextFaint = hex("#5a5f68"),
			.Accent = hex("#7c6cff"), .Success = hex("#43c584"), .Warning = hex("#f0b04a"), .Danger = hex("#f05d63"), .CodeBg = hex("#0a0b0d"),
		}
	case .MidDay:
		t.colors = {
			.BgApp = hex("#2b3038"), .BgPanel = hex("#343a44"), .BgRaised = hex("#404754"), .BgHover = hex("#4a5262"), .BgActive = hex("#555e70"),
			.Text = hex("#eef1f5"), .TextDim = hex("#b1b8c4"), .TextFaint = hex("#868e9b"),
			.Accent = hex("#6fb3ff"), .Success = hex("#5fd39b"), .Warning = hex("#f7c15a"), .Danger = hex("#ff7474"), .CodeBg = hex("#2e333b"),
		}
	case .Light:
		t.colors = {
			.BgApp = hex("#d9dde3"), .BgPanel = hex("#eef0f3"), .BgRaised = hex("#ffffff"), .BgHover = hex("#e2e6ec"), .BgActive = hex("#d3d9e2"),
			.Text = hex("#1d2129"), .TextDim = hex("#59606c"), .TextFaint = hex("#8c939e"),
			.Accent = hex("#2f6bf2"), .Success = hex("#1e9e5f"), .Warning = hex("#c7860f"), .Danger = hex("#d23c3c"), .CodeBg = hex("#fbfbfc"),
		}
	}
	return
}

// Theme_Apply makes a theme the editor's palette (and ImGui's style).
Theme_Apply :: proc(t: Theme) {
	c := t.colors
	UI_BG_APP = c[.BgApp]
	UI_BG_PANEL = c[.BgPanel]
	UI_BG_RAISED = c[.BgRaised]
	UI_BG_HOVER = c[.BgHover]
	UI_BG_ACTIVE = c[.BgActive]
	UI_TEXT = c[.Text]
	UI_TEXT_DIM = c[.TextDim]
	UI_TEXT_FAINT = c[.TextFaint]
	UI_ACCENT = c[.Accent]
	UI_ACCENT_SOFT = {c[.Accent].x, c[.Accent].y, c[.Accent].z, 0.18}
	UI_SUCCESS = c[.Success]
	UI_WARNING = c[.Warning]
	UI_DANGER = c[.Danger]
	CODE_BG = c[.CodeBg]
	// Light theme: the panels are brighter than the text.
	lum :: proc(v: imgui.Vec4) -> f32 {return v.x * 0.299 + v.y * 0.587 + v.z * 0.114}
	UI_THEME_LIGHT = lum(c[.BgPanel]) > lum(c[.Text])
	UI_LINE_RGB = {0, 0, 0} if UI_THEME_LIGHT else {1, 1, 1}
	UI_ApplyTheme()
}

theme_color_text :: proc(c: imgui.Vec4) -> string {
	b :: proc(f: f32) -> u8 {return u8(clamp(f, 0, 1) * 255 + 0.5)}
	return fmt.tprintf("#%02x%02x%02x%02x", b(c.x), b(c.y), b(c.z), b(c.w))
}

// theme_parse_color: "#rrggbb" or "#rrggbbaa".
theme_parse_color :: proc(s: string) -> (imgui.Vec4, bool) {
	h := strings.trim_prefix(strings.trim_space(s), "#")
	if len(h) != 6 && len(h) != 8 do return {}, false
	v, ok := strconv.parse_u64(h, 16)
	if !ok do return {}, false
	if len(h) == 6 do v = v << 8 | 0xff
	return {f32((v >> 24) & 0xff) / 255, f32((v >> 16) & 0xff) / 255, f32((v >> 8) & 0xff) / 255, f32(v & 0xff) / 255}, true
}

// Theme_Editor: the Theme page of Settings > General (edits `t`, applying
// it live; Cancel puts the saved theme back).
Theme_Editor :: proc(t: ^Theme) {
	UI_DimText("Presets")
	for p in Theme_Preset {
		name := THEME_PRESET_NAMES[p]
		if p != .Default do imgui.SameLine()
		if UI_Button(name, fmt.tprintf("theme.preset:%s", name)) {
			old := t.name
			t^ = Theme_PresetColors(p)
			t.name = strings.clone(t.name)
			delete(old)
			Theme_Apply(t^)
		}
	}
	imgui.Dummy({0, 4})
	UI_DimText(fmt.tprintf("Current: %s", t.name))
	Drive_Item("theme.current")
	imgui.Dummy({0, 4})
	if UI_BeginProps("##theme_colors") {
		for k in Theme_Color {
			info := THEME_COLOR_INFO[k]
			UI_PropLabel(info.label)
			f := [4]f32{t.colors[k].x, t.colors[k].y, t.colors[k].z, t.colors[k].w}
			if imgui.ColorEdit4(fmt.ctprintf("##theme_%s", info.key), &f, {.AlphaBar, .DisplayHex}) {
				t.colors[k] = {f[0], f[1], f[2], f[3]}
				if !strings.has_prefix(t.name, "Custom") {
					delete(t.name)
					t.name = strings.clone("Custom")
				}
				Theme_Apply(t^)
			}
			Drive_Item(fmt.tprintf("theme.color:%s", info.key))
		}
		UI_EndProps()
	}
}
