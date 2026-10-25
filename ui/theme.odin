package ui

import "core:math"
import rl "vendor:raylib"

// ============================================================================
// UI Theme System
// ============================================================================

Theme :: struct {
	// Spacing & Geometry Metrics
	paddingSm:         f32,
	paddingMd:         f32,
	paddingLg:         f32,
	marginSm:          f32,
	marginMd:          f32,
	itemSpacing:       f32,
	borderRadius:      f32, // default 5.0px for buttons, inputs, panels
	borderRadiusSmall: f32, // default 3.0px for tags, badges, chips
	borderWidth:       f32, // default 1.0px

	// Colors - Backgrounds & Surfaces
	bgApp:            rl.Color,
	bgPanel:          rl.Color,
	bgHeader:         rl.Color,
	bgWidget:         rl.Color,
	bgWidgetHover:    rl.Color,
	bgWidgetPressed:  rl.Color,
	bgWidgetSelected: rl.Color,
	bgInput:          rl.Color,

	// Colors - Borders
	borderNormal:  rl.Color,
	borderHover:   rl.Color,
	borderFocused: rl.Color,

	// Colors - Typography
	textPrimary:   rl.Color,
	textSecondary: rl.Color,
	textDisabled:  rl.Color,

	// Colors - Accents & Semantic States
	accent:      rl.Color,
	accentHover: rl.Color,
	success:     rl.Color,
	warning:     rl.Color,
	danger:      rl.Color,
	info:        rl.Color,
}

// Global active theme and stack
activeTheme: Theme
themeStack: [16]Theme
themeStackCount: int = 0
themeInitialized: bool = false

// ============================================================================
// Built-In Theme Presets
// ============================================================================

// 1. Dark Modern (Default)
Theme_Dark :: proc() -> Theme {
	return Theme{
		paddingSm         = 4.0,
		paddingMd         = 8.0,
		paddingLg         = 16.0,
		marginSm          = 4.0,
		marginMd          = 8.0,
		itemSpacing       = 6.0,
		borderRadius      = 5.0,
		borderRadiusSmall = 3.0,
		borderWidth       = 1.0,

		bgApp             = {16, 18, 23, 255},
		bgPanel           = {22, 25, 33, 240},
		bgHeader          = {28, 33, 44, 255},
		bgWidget          = {34, 38, 48, 255},
		bgWidgetHover     = {48, 54, 68, 255},
		bgWidgetPressed   = {37, 99, 235, 255},
		bgWidgetSelected  = {37, 99, 235, 180},
		bgInput           = {20, 23, 30, 255},

		borderNormal      = {55, 62, 80, 255},
		borderHover       = {90, 102, 130, 255},
		borderFocused     = {110, 168, 254, 255},

		textPrimary       = {240, 243, 250, 255},
		textSecondary     = {140, 148, 168, 255},
		textDisabled      = {85, 92, 110, 255},

		accent            = {59, 130, 246, 255},
		accentHover       = {96, 165, 250, 255},
		success           = {52, 211, 153, 255},
		warning           = {251, 191, 36, 255},
		danger            = {239, 68, 68, 255},
		info              = {56, 189, 248, 255},
	}
}

// 2. Clean Light
Theme_Light :: proc() -> Theme {
	return Theme{
		paddingSm         = 4.0,
		paddingMd         = 8.0,
		paddingLg         = 16.0,
		marginSm          = 4.0,
		marginMd          = 8.0,
		itemSpacing       = 6.0,
		borderRadius      = 5.0,
		borderRadiusSmall = 3.0,
		borderWidth       = 1.0,

		bgApp             = {243, 244, 246, 255},
		bgPanel           = {255, 255, 255, 250},
		bgHeader          = {240, 242, 245, 255},
		bgWidget          = {243, 244, 248, 255},
		bgWidgetHover     = {228, 231, 238, 255},
		bgWidgetPressed   = {37, 99, 235, 255},
		bgWidgetSelected  = {219, 234, 254, 255},
		bgInput           = {255, 255, 255, 255},

		borderNormal      = {209, 213, 219, 255},
		borderHover       = {156, 163, 175, 255},
		borderFocused     = {37, 99, 235, 255},

		textPrimary       = {17, 24, 39, 255},
		textSecondary     = {75, 85, 99, 255},
		textDisabled      = {156, 163, 175, 255},

		accent            = {37, 99, 235, 255},
		accentHover       = {29, 78, 216, 255},
		success           = {16, 185, 129, 255},
		warning           = {245, 158, 11, 255},
		danger            = {220, 38, 38, 255},
		info              = {2, 132, 199, 255},
	}
}

// 3. High-Contrast / Cyberpunk
Theme_Cyberpunk :: proc() -> Theme {
	return Theme{
		paddingSm         = 4.0,
		paddingMd         = 8.0,
		paddingLg         = 16.0,
		marginSm          = 4.0,
		marginMd          = 8.0,
		itemSpacing       = 6.0,
		borderRadius      = 2.0, // sharper tech aesthetic
		borderRadiusSmall = 1.0,
		borderWidth       = 1.5,

		bgApp             = {10, 10, 16, 255},
		bgPanel           = {16, 16, 26, 245},
		bgHeader          = {24, 20, 38, 255},
		bgWidget          = {26, 22, 42, 255},
		bgWidgetHover     = {42, 34, 68, 255},
		bgWidgetPressed   = {255, 0, 128, 255},
		bgWidgetSelected  = {0, 229, 255, 120},
		bgInput           = {12, 10, 20, 255},

		borderNormal      = {65, 45, 105, 255},
		borderHover       = {0, 229, 255, 255},
		borderFocused     = {255, 234, 0, 255},

		textPrimary       = {255, 255, 255, 255},
		textSecondary     = {0, 229, 255, 255},
		textDisabled      = {100, 80, 140, 255},

		accent            = {0, 229, 255, 255},
		accentHover       = {255, 0, 128, 255},
		success           = {0, 255, 157, 255},
		warning           = {255, 234, 0, 255},
		danger            = {255, 0, 85, 255},
		info              = {170, 0, 255, 255},
	}
}

// ============================================================================
// Theme Management API
// ============================================================================

GetTheme :: proc() -> ^Theme {
	if !themeInitialized {
		activeTheme = Theme_Dark()
		themeInitialized = true
	}
	return &activeTheme
}

SetTheme :: proc(t: Theme) {
	activeTheme = t
	themeInitialized = true
}

PushTheme :: proc(t: Theme) {
	if !themeInitialized {
		activeTheme = Theme_Dark()
		themeInitialized = true
	}
	if themeStackCount < len(themeStack) {
		themeStack[themeStackCount] = activeTheme
		themeStackCount += 1
	}
	activeTheme = t
}

PopTheme :: proc() {
	if themeStackCount > 0 {
		themeStackCount -= 1
		activeTheme = themeStack[themeStackCount]
	}
}

// ============================================================================
// Theme-Aware Drawing Helpers
// ============================================================================

DrawThemeRect :: proc(
	rect: rl.Rectangle,
	bgColor: rl.Color,
	borderColor: rl.Color,
	radius: f32 = -1,
	borderWidth: f32 = -1,
) {
	if !rl.IsWindowReady() || rect.width <= 0 || rect.height <= 0 do return

	t := GetTheme()
	rad := radius if radius >= 0 else t.borderRadius
	bw := borderWidth if borderWidth >= 0 else t.borderWidth

	minDim := min(rect.width, rect.height)
	if rad <= 0.5 || minDim <= 2.0 {
		// Sharp rectangle
		if bgColor.a > 0 {
			rl.DrawRectangleRec(rect, bgColor)
		}
		if borderColor.a > 0 && bw > 0 {
			rl.DrawRectangleLinesEx(rect, bw, borderColor)
		}
		return
	}

	// Rounded rectangle via Raylib normalized roundness [0.0..1.0]
	// roundness * minDim / 2 = radius => roundness = (radius * 2.0) / minDim
	roundness := clamp((rad * 2.0) / minDim, 0.0, 1.0)
	segments: i32 = 6

	if bgColor.a > 0 {
		rl.DrawRectangleRounded(rect, roundness, segments, bgColor)
	}
	if borderColor.a > 0 && bw > 0 {
		rl.DrawRectangleRoundedLinesEx(rect, roundness, segments, bw, borderColor)
	}
}
