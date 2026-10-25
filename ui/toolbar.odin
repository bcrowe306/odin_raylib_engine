package ui

import "core:fmt"
import "core:math"
import rl "vendor:raylib"

// ============================================================================
// Toolbar Types & Layout
// ============================================================================

ToolbarItemType :: enum {
	Button,
	Toggle,
	Separator,
	Spacer,
}

ToolbarItem :: struct {
	id:         int,
	icon:       Icon,
	label:      string, // optional text next to icon
	tooltip:    string, // shown on hover
	itemType:   ToolbarItemType,
	isSelected: bool, // for toggle items
	disabled:   bool,
}

// Internal navigation state for toolbar keyboard navigation
ToolbarNavState :: struct {
	focusedIndex: int,
	key:          uintptr,
}

toolbarNavStates: [32]ToolbarNavState
toolbarNavCount: int

GetToolbarNavState :: proc(key: uintptr) -> ^ToolbarNavState {
	for i in 0..<toolbarNavCount {
		if toolbarNavStates[i].key == key {
			return &toolbarNavStates[i]
		}
	}
	if toolbarNavCount < len(toolbarNavStates) {
		idx := toolbarNavCount
		toolbarNavCount += 1
		toolbarNavStates[idx] = ToolbarNavState{
			key = key,
			focusedIndex = 0,
		}
		return &toolbarNavStates[idx]
	}
	return &toolbarNavStates[0]
}

// ============================================================================
// 1. Tooltip Rendering Helper
// ============================================================================
RenderTooltip :: proc(pos: [2]f32, text: string) {
	if text == "" || !rl.IsWindowReady() do return

	fontSize: f32 = DEFAULT_FONT_SIZE_SM
	tm := MeasureTextStr(text, fontSize)
	tipPadX: f32 = 8.0
	tipPadY: f32 = 5.0
	tipW := tm.x + tipPadX * 2.0
	tipH := tm.y + tipPadY * 2.0

	// Position tooltip above or below cursor, clamped within screen
	tipX := pos.x - tipW * 0.5
	tipY := pos.y + 18.0
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())

	if tipX + tipW > sw - 8.0 do tipX = sw - tipW - 8.0
	if tipX < 8.0 do tipX = 8.0
	if tipY + tipH > sh - 8.0 do tipY = pos.y - tipH - 8.0

	tipRect := rl.Rectangle{tipX, tipY, tipW, tipH}

	// Tooltip Shadow
	rl.DrawRectangleRec({tipRect.x + 2, tipRect.y + 2, tipRect.width, tipRect.height}, rl.Color{0, 0, 0, 140})
	// Tooltip Box
	rl.DrawRectangleRec(tipRect, rl.Color{18, 20, 26, 250})
	rl.DrawRectangleLinesEx(tipRect, 1, rl.Color{75, 83, 105, 255})

	DrawTextStr(text, tipRect.x + tipPadX, tipRect.y + tipPadY, fontSize, rl.Color{240, 244, 252, 255})
}

// ============================================================================
// 2. Icon Button Rendering (with Focus Indicator & Icon)
// ============================================================================
RenderIconButton :: proc(
	rect: rl.Rectangle,
	icon: Icon,
	label: string = "",
	iconSize: f32 = 0,
	hovered: bool = false,
	isPressed: bool = false,
	focused: bool = false,
	isSelected: bool = false,
	normalColor: rl.Color = {35, 39, 49, 255},
	hoverColor: rl.Color = {50, 56, 72, 255},
	pressedColor: rl.Color = {37, 99, 235, 255},
	borderColor: rl.Color = {75, 83, 102, 255},
	textColor: rl.Color = {238, 240, 246, 255},
	align: TextAlign = .Center,
) {
	if !rl.IsWindowReady() do return

	bg := normalColor
	border := borderColor
	if isPressed {
		bg = pressedColor
		border = rl.Color{110, 168, 254, 255}
	} else if isSelected {
		bg = rl.Color{37, 99, 235, 180}
		border = rl.Color{110, 168, 254, 255}
	} else if hovered {
		bg = hoverColor
		border = rl.Color{110, 168, 254, 255}
	} else if focused {
		border = rl.Color{110, 168, 254, 255}
	}

	t := GetTheme()
	DrawThemeRect(rect, bg, border, radius = t.borderRadius)

	// Accent bar when selected or hovered
	if isSelected {
		accentRec := rl.Rectangle{rect.x, rect.y + rect.height - 3, rect.width, 3}
		DrawThemeRect(accentRec, t.accent, rl.Color{0, 0, 0, 0}, radius = t.borderRadiusSmall)
	} else if hovered || focused {
		accentRec := rl.Rectangle{rect.x, rect.y, 3, rect.height}
		DrawThemeRect(accentRec, t.borderFocused, rl.Color{0, 0, 0, 0}, radius = t.borderRadiusSmall)
	}

	if focused {
		RenderFocusRing(rect, true, 2.0)
	}

	// Calculate content sizing
	actualIconSize := iconSize if iconSize > 0 else clamp(rect.height - 14, 14, 22)
	iconMeas := MeasureIcon(icon, actualIconSize) if icon != .None else [2]f32{0, 0}
	labelMeas := MeasureTextStr(label, DEFAULT_FONT_SIZE) if label != "" else [2]f32{0, 0}

	gap: f32 = 8.0 if (icon != .None && label != "") else 0.0
	totalW := iconMeas.x + gap + labelMeas.x

	startX := rect.x + (rect.width - totalW) * 0.5
	switch align {
	case .Left:
		startX = rect.x + 8.0
	case .Right:
		startX = rect.x + rect.width - totalW - 8.0
	case .Center:
		startX = rect.x + (rect.width - totalW) * 0.5
	}

	// Render Icon
	if icon != .None {
		iconY := rect.y + (rect.height - actualIconSize) * 0.5
		iconCol := textColor
		if isSelected {
			iconCol = rl.WHITE
		} else if hovered {
			iconCol = rl.Color{255, 255, 255, 255}
		}
		DrawIcon(icon, startX, iconY, actualIconSize, iconCol)
	}

	// Render Label text
	if label != "" {
		textX := startX + (iconMeas.x + gap if icon != .None else 0.0)
		textY := rect.y + (rect.height - DEFAULT_FONT_SIZE) * 0.5
		DrawTextStr(label, textX, textY, DEFAULT_FONT_SIZE, textColor)
	}
}

// Immediate-mode GuiIconButton
GuiIconButton :: proc(
	rect: rl.Rectangle,
	icon: Icon,
	label: string = "",
	iconSize: f32 = 0,
	isSelected: bool = false,
	align: TextAlign = .Center,
	idKey: uintptr = 0,
) -> bool {
	if !rl.IsWindowReady() do return false

	key := idKey if idKey != 0 else uintptr(uint(u32(rect.x * 1000)) ~ uint(u32(rect.y * 1000)))
	ImmediateNav_RegisterFocusable(key, rect)
	isFocused := ImmediateNav_IsFocused(key)

	mp := GetUIMousePosition()
	mousePt := [2]f32{mp.x, mp.y}
	inClip := IsMouseInClipRect(mousePt)
	blocked := IsBlockedByImmediateDropdown(0, mousePt)
	hovered := inClip && !blocked && PointInRect(mousePt, rect)
	if hovered do SetUICursor(.POINTING_HAND, .Hover)
	if hovered && IsUIMouseButtonPressed(.LEFT) {
		ImmediateNav_SetFocus(key)
	}
	isDown := hovered && IsUIMouseButtonDown(.LEFT)
	keyTrigger := isFocused && (IsUIKeyPressed(.ENTER) || IsUIKeyPressed(.KP_ENTER) || IsUIKeyPressed(.SPACE))
	clicked := (hovered && IsUIMouseButtonPressed(.LEFT)) || keyTrigger

	normalBg := rl.Color{37, 99, 235, 95} if isSelected else rl.Color{34, 37, 45, 255}
	hoverBg := rl.Color{48, 112, 245, 130} if isSelected else rl.Color{48, 53, 66, 255}
	pressedBg := rl.Color{37, 99, 235, 255}
	borderCol := rl.Color{110, 168, 254, 255} if (isSelected || isFocused) else rl.Color{68, 73, 86, 255}
	textCol := rl.Color{240, 242, 248, 255}

	RenderIconButton(
		rect,
		icon,
		label,
		iconSize,
		hovered,
		isDown,
		isFocused,
		isSelected,
		normalBg,
		hoverBg,
		pressedBg,
		borderCol,
		textCol,
		align,
	)

	return clicked
}

// ============================================================================
// 3. Retained & Immediate-Mode Toolbar Widget
// ============================================================================

RenderToolbar :: proc(
	rect: rl.Rectangle,
	items: []ToolbarItem,
	hoveredId: int = -1,
	selectedId: int = -1,
	focusedId: int = -1,
	buttonSize: [2]f32 = {34, 32},
	spacing: f32 = 4.0,
	bgColor: rl.Color = {22, 25, 33, 255},
	borderColor: rl.Color = {48, 54, 70, 255},
) -> (hoveredTooltip: string, tooltipPos: [2]f32) {
	if !rl.IsWindowReady() do return "", {0, 0}

	// Toolbar Background Bar
	t := GetTheme()
	DrawThemeRect(rect, bgColor, borderColor, radius = t.borderRadius)
	// Top subtle highlight stripe
	stripeRec := rl.Rectangle{rect.x, rect.y, rect.width, 2}
	DrawThemeRect(stripeRec, t.borderNormal, rl.Color{0, 0, 0, 0}, radius = t.borderRadius)

	curX := rect.x + 8.0
	centerY := rect.y + rect.height * 0.5
	mp := GetUIMousePosition()

	for item in items {
		#partial switch item.itemType {
		case .Separator:
			sepX := math.round(curX + 3.0)
			rl.DrawLineEx({sepX, rect.y + 6.0}, {sepX, rect.y + rect.height - 6.0}, 1.0, rl.Color{55, 62, 80, 255})
			curX += 8.0

		case .Spacer:
			curX += 16.0

		case .Button, .Toggle:
			btnW := buttonSize.x
			if item.label != "" {
				labelW := MeasureTextStr(item.label, DEFAULT_FONT_SIZE_SM).x
				iconW: f32 = 18.0 if item.icon != .None else 0.0
				gap: f32 = 6.0 if (item.icon != .None && item.label != "") else 0.0
				btnW = max(btnW, iconW + gap + labelW + 16.0)
			}
			btnH := buttonSize.y
			btnY := math.round(centerY - btnH * 0.5)
			btnRect := rl.Rectangle{curX, btnY, btnW, btnH}

			isHovered := (item.id == hoveredId)
			isSelected := item.isSelected || (item.id == selectedId)
			isFocused := (item.id == focusedId)

			// Button Background
			bg := rl.Color{0, 0, 0, 0}
			borderCol := rl.Color{0, 0, 0, 0}
			if item.disabled {
				bg = rl.Color{24, 27, 34, 160}
			} else if isSelected {
				bg = rl.Color{37, 99, 235, 180}
				borderCol = rl.Color{110, 168, 254, 255}
			} else if isHovered {
				bg = rl.Color{45, 52, 70, 255}
				borderCol = rl.Color{90, 102, 130, 255}
			} else if isFocused {
				borderCol = rl.Color{110, 168, 254, 255}
			}

			if bg.a > 0 || borderCol.a > 0 {
				DrawThemeRect(btnRect, bg, borderCol, radius = t.borderRadiusSmall)
			}

			// Selected accent indicator
			if isSelected {
				rl.DrawRectangleRec({btnRect.x + 2, btnRect.y + btnRect.height - 2, btnRect.width - 4, 2}, rl.Color{96, 165, 250, 255})
			}

			if isFocused {
				RenderFocusRing(btnRect, true, 2.0)
			}

			// Render Icon & Label
			actualIconSize: f32 = 17.0
			iconCol := rl.Color{210, 218, 235, 255}
			if item.disabled {
				iconCol = rl.Color{90, 96, 112, 255}
			} else if isSelected {
				iconCol = rl.WHITE
			} else if isHovered {
				iconCol = rl.Color{255, 255, 255, 255}
			}

			if item.label == "" {
				// Centered icon-only button
				if item.icon != .None {
					m := MeasureIcon(item.icon, actualIconSize)
					ix := btnRect.x + (btnRect.width - m.x) * 0.5
					iy := btnRect.y + (btnRect.height - actualIconSize) * 0.5
					DrawIcon(item.icon, ix, iy, actualIconSize, iconCol)
				}
			} else {
				// Icon + Label
				iconMeas := MeasureIcon(item.icon, actualIconSize) if item.icon != .None else [2]f32{0, 0}
				labelMeas := MeasureTextStr(item.label, DEFAULT_FONT_SIZE_SM)
				gap: f32 = 6.0 if item.icon != .None else 0.0
				totalContentW := iconMeas.x + gap + labelMeas.x
				startX := btnRect.x + (btnRect.width - totalContentW) * 0.5

				if item.icon != .None {
					iy := btnRect.y + (btnRect.height - actualIconSize) * 0.5
					DrawIcon(item.icon, startX, iy, actualIconSize, iconCol)
				}
				lx := startX + (iconMeas.x + gap if item.icon != .None else 0.0)
				ly := btnRect.y + (btnRect.height - DEFAULT_FONT_SIZE_SM) * 0.5
				DrawTextStr(item.label, lx, ly, DEFAULT_FONT_SIZE_SM, iconCol)
			}

			if isHovered && item.tooltip != "" {
				hoveredTooltip = item.tooltip
				tooltipPos = {mp.x, btnRect.y + btnRect.height}
			}

			curX += btnW + spacing
		}
	}

	return hoveredTooltip, tooltipPos
}

// Immediate-Mode GuiToolbar Widget
GuiToolbar :: proc(
	rect: rl.Rectangle,
	items: []ToolbarItem,
	activeToggleId: ^int = nil,
	buttonSize: [2]f32 = {34, 32},
	spacing: f32 = 4.0,
	idKey: uintptr = 0,
) -> (clickedId: int, clicked: bool) {
	if !rl.IsWindowReady() do return -1, false

	key := idKey if idKey != 0 else uintptr(uint(u32(rect.x * 1000)) ~ uint(u32(rect.y * 1000)))
	ImmediateNav_RegisterFocusable(key, rect)
	isFocused := ImmediateNav_IsFocused(key)

	navState := GetToolbarNavState(key)

	mp := GetUIMousePosition()
	mousePt := [2]f32{mp.x, mp.y}
	inClip := IsMouseInClipRect(mousePt)
	blocked := IsBlockedByImmediateDropdown(0, mousePt)

	// Collect interactive buttons for navigation
	actionableCount := 0
	actionableIndices: [64]int
	for i in 0..<len(items) {
		if items[i].itemType == .Button || items[i].itemType == .Toggle {
			if actionableCount < len(actionableIndices) {
				actionableIndices[actionableCount] = i
				actionableCount += 1
			}
		}
	}

	// Keyboard Left / Right arrow navigation when toolbar has focus
	if isFocused && actionableCount > 0 {
		if IsUIKeyPressed(.LEFT) {
			navState.focusedIndex = (navState.focusedIndex - 1 + actionableCount) % actionableCount
		} else if IsUIKeyPressed(.RIGHT) {
			navState.focusedIndex = (navState.focusedIndex + 1) % actionableCount
		}
	}

	hoveredId := -1
	focusedItemId := -1
	if isFocused && actionableCount > 0 && navState.focusedIndex < actionableCount {
		focusedItemId = items[actionableIndices[navState.focusedIndex]].id
	}

	// Mouse hit testing
	curX := rect.x + 8.0
	centerY := rect.y + rect.height * 0.5
	clickedId = -1
	clicked = false

	for i in 0..<len(items) {
		item := &items[i]
		#partial switch item.itemType {
		case .Separator:
			curX += 8.0
		case .Spacer:
			curX += 16.0
		case .Button, .Toggle:
			btnW := buttonSize.x
			if item.label != "" {
				labelW := MeasureTextStr(item.label, DEFAULT_FONT_SIZE_SM).x
				iconW: f32 = 18.0 if item.icon != .None else 0.0
				gap: f32 = 6.0 if (item.icon != .None && item.label != "") else 0.0
				btnW = max(btnW, iconW + gap + labelW + 16.0)
			}
			btnH := buttonSize.y
			btnY := math.round(centerY - btnH * 0.5)
			btnRect := rl.Rectangle{curX, btnY, btnW, btnH}

			isHover := inClip && !blocked && PointInRect(mousePt, btnRect)
			if isHover && !item.disabled do SetUICursor(.POINTING_HAND, .Hover)
			if isHover {
				hoveredId = item.id
				if IsUIMouseButtonPressed(.LEFT) {
					ImmediateNav_SetFocus(key)
					// update nav state focused index
					for a := 0; a < actionableCount; a += 1 {
						if actionableIndices[a] == i {
							navState.focusedIndex = a
							break
						}
					}
					if !item.disabled {
						clickedId = item.id
						clicked = true
						if item.itemType == .Toggle {
							item.isSelected = !item.isSelected
							if activeToggleId != nil {
								activeToggleId^ = item.id if item.isSelected else -1
							}
						}
					}
				}
			}

			// Key trigger for focused button
			if isFocused && item.id == focusedItemId && (IsUIKeyPressed(.ENTER) || IsUIKeyPressed(.KP_ENTER) || IsUIKeyPressed(.SPACE)) {
				if !item.disabled {
					clickedId = item.id
					clicked = true
					if item.itemType == .Toggle {
						item.isSelected = !item.isSelected
						if activeToggleId != nil {
							activeToggleId^ = item.id if item.isSelected else -1
						}
					}
				}
			}

			curX += btnW + spacing
		}
	}

	selectedId := activeToggleId^ if activeToggleId != nil else -1
	tooltipText, tooltipPos := RenderToolbar(rect, items, hoveredId, selectedId, focusedItemId, buttonSize, spacing)

	if tooltipText != "" {
		RenderTooltip(tooltipPos, tooltipText)
	}

	return clickedId, clicked
}
