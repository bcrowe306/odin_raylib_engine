package ui

import "core:math"
import rl "vendor:raylib"

// ============================================================================
// UI Container Types & Standalone Layout Calculations
// ============================================================================

Padding :: struct {
	left:   f32,
	top:    f32,
	right:  f32,
	bottom: f32,
}

TabDirection :: enum {
	Horizontal,
	Vertical,
}

ProgressBarDirection :: enum {
	Horizontal,
	Vertical,
}

LayoutItem :: struct {
	size:     [2]f32,
	position: [2]f32,
}

// Compute vertical layout for a sequence of child items.
// Mutates outPositions and outSizes (if stretch is requested).
// Returns the total computed content height.
ComputeVerticalLayout :: proc(
	boundsSize: [2]f32,
	itemSizes: []^[2]f32,
	outPositions: [][2]f32,
	alignment: Alignment,
	spacing: f32,
	padding: Padding,
	headerHeight: f32 = 0,
) -> f32 {
	count := len(itemSizes)
	if count == 0 do return padding.top + padding.bottom + headerHeight

	innerOffsetX := padding.left
	innerOffsetY := headerHeight + padding.top
	innerW := max(boundsSize.x - padding.left - padding.right, 20.0)

	curY := innerOffsetY
	for i := 0; i < count; i += 1 {
		sizePtr := itemSizes[i]
		childW := sizePtr.x
		childH := sizePtr.y

		childX := innerOffsetX
		switch alignment {
		case .Start:
			childX = innerOffsetX
		case .Center:
			childX = innerOffsetX + (innerW - childW) * 0.5
		case .End:
			childX = innerOffsetX + innerW - childW
		case .Stretch:
			childX = innerOffsetX
			sizePtr.x = innerW
		}

		if i < len(outPositions) {
			outPositions[i] = {math.round(childX), math.round(curY)}
		}

		curY += childH + spacing
	}

	return curY - spacing + padding.bottom
}

// Compute horizontal layout for a sequence of child items.
// Mutates outPositions and outSizes (if stretch is requested).
// Returns the total computed content width.
ComputeHorizontalLayout :: proc(
	boundsSize: [2]f32,
	itemSizes: []^[2]f32,
	outPositions: [][2]f32,
	alignment: Alignment,
	spacing: f32,
	padding: Padding,
	headerHeight: f32 = 0,
) -> f32 {
	count := len(itemSizes)
	if count == 0 do return padding.left + padding.right

	innerOffsetX := padding.left
	innerOffsetY := headerHeight + padding.top
	innerH := max(boundsSize.y - innerOffsetY - padding.bottom, 20.0)

	curX := innerOffsetX
	for i := 0; i < count; i += 1 {
		sizePtr := itemSizes[i]
		childW := sizePtr.x
		childH := sizePtr.y

		childY := innerOffsetY
		switch alignment {
		case .Start:
			childY = innerOffsetY
		case .Center:
			childY = innerOffsetY + (innerH - childH) * 0.5
		case .End:
			childY = innerOffsetY + innerH - childH
		case .Stretch:
			childY = innerOffsetY
			sizePtr.y = innerH
		}

		if i < len(outPositions) {
			outPositions[i] = {math.round(curX), math.round(childY)}
		}

		curX += childW + spacing
	}

	return curX - spacing + padding.right
}

// Compute grid layout for child items.
// Mutates outPositions and outSizes.
// Returns the total computed content height.
ComputeGridLayout :: proc(
	boundsSize: [2]f32,
	itemSizes: []^[2]f32,
	outPositions: [][2]f32,
	columns: int,
	spacing: f32,
	padding: Padding,
	headerHeight: f32 = 0,
) -> f32 {
	count := len(itemSizes)
	cols := max(columns, 1)
	if count == 0 do return padding.top + padding.bottom + headerHeight

	innerOffsetX := padding.left
	innerOffsetY := headerHeight + padding.top
	innerW := max(boundsSize.x - padding.left - padding.right, 20.0)

	cellW := (innerW - f32(cols - 1) * spacing) / f32(cols)

	curY := innerOffsetY
	maxRowH: f32 = 0

	for i := 0; i < count; i += 1 {
		c := i % cols

		if c == 0 && i > 0 {
			curY += maxRowH + spacing
			maxRowH = 0
		}

		sizePtr := itemSizes[i]
		sizePtr.x = cellW
		childH := sizePtr.y
		if childH > maxRowH do maxRowH = childH

		cellX := innerOffsetX + f32(c) * (cellW + spacing)

		if i < len(outPositions) {
			outPositions[i] = {math.round(cellX), math.round(curY)}
		}
	}

	return curY + maxRowH + padding.bottom
}

// ============================================================================
// Tab Container Rendering & Immediate-Mode TabBar (with Focus Indicator)
// ============================================================================

// Renders tab headers and container frame, returning the content area rectangle.
RenderTabContainer :: proc(
	bounds: rl.Rectangle,
	tabNames: []string,
	activeTab: int,
	direction: TabDirection = .Horizontal,
	tabSize: f32 = 30,
	bgColor: rl.Color = {24, 26, 32, 245},
	borderColor: rl.Color = {55, 60, 75, 255},
	activeTabColor: rl.Color = {42, 48, 64, 255},
	inactiveTabColor: rl.Color = {28, 30, 38, 255},
	accentColor: rl.Color = {80, 140, 245, 255},
	focused: bool = false,
) -> rl.Rectangle {
	// Background Panel
	rl.DrawRectangleRec(bounds, bgColor)
	borderCol := rl.Color{110, 168, 254, 255} if focused else borderColor
	rl.DrawRectangleLinesEx(bounds, 1, borderCol)

	if focused {
		RenderFocusRing(bounds, true, 2.0)
	}

	tabCount := len(tabNames)
	contentRect := bounds
	mousePos := GetUIMousePosition()

	if direction == .Horizontal {
		barRect := rl.Rectangle{bounds.x, bounds.y, bounds.width, tabSize}
		rl.DrawRectangleRec(barRect, inactiveTabColor)
		rl.DrawLineEx({barRect.x, barRect.y + barRect.height}, {barRect.x + barRect.width, barRect.y + barRect.height}, 1, borderColor)

		tabW := bounds.width / f32(max(tabCount, 1))
		for i := 0; i < tabCount; i += 1 {
			tabR := rl.Rectangle{bounds.x + f32(i) * tabW, bounds.y, tabW, tabSize}
			isActive := (i == activeTab)

			if isActive {
				rl.DrawRectangleRec(tabR, activeTabColor)
				// Top accent line
				rl.DrawRectangleRec({tabR.x, tabR.y, tabR.width, 3}, accentColor)
				if focused {
					RenderFocusRing(tabR, true, 1.0)
				}
			} else if PointInRect(mousePos, tabR) {
				rl.DrawRectangleRec(tabR, rl.Color{38, 44, 58, 255})
			}

			// Tab separator
			if i > 0 {
				rl.DrawLineEx({tabR.x, tabR.y + 4}, {tabR.x, tabR.y + tabSize - 4}, 1, borderColor)
			}

			// Tab Text
			tColor := rl.WHITE if isActive else rl.Color{170, 175, 190, 255}
			textW := MeasureTextStr(tabNames[i], 15).x
			DrawTextStr(tabNames[i], tabR.x + (tabR.width - textW) * 0.5, tabR.y + (tabSize - 15) * 0.5, 15, tColor)
		}

		contentRect.y += tabSize
		contentRect.height -= tabSize
	} else {
		// Vertical Tabs
		barRect := rl.Rectangle{bounds.x, bounds.y, tabSize, bounds.height}
		rl.DrawRectangleRec(barRect, inactiveTabColor)
		rl.DrawLineEx({barRect.x + barRect.width, barRect.y}, {barRect.x + barRect.width, barRect.y + barRect.height}, 1, borderColor)

		tabH := min(bounds.height / f32(max(tabCount, 1)), 44.0)
		for i := 0; i < tabCount; i += 1 {
			tabR := rl.Rectangle{bounds.x, bounds.y + f32(i) * tabH, tabSize, tabH}
			isActive := (i == activeTab)

			if isActive {
				rl.DrawRectangleRec(tabR, activeTabColor)
				// Left accent line
				rl.DrawRectangleRec({tabR.x, tabR.y, 3, tabR.height}, accentColor)
				if focused {
					RenderFocusRing(tabR, true, 1.0)
				}
			} else if PointInRect(mousePos, tabR) {
				rl.DrawRectangleRec(tabR, rl.Color{38, 44, 58, 255})
			}

			// Tab separator
			if i > 0 {
				rl.DrawLineEx({tabR.x + 4, tabR.y}, {tabR.x + tabSize - 4, tabR.y}, 1, borderColor)
			}

			// Tab Text
			tColor := rl.WHITE if isActive else rl.Color{170, 175, 190, 255}
			DrawTextStr(tabNames[i], tabR.x + 14, tabR.y + (tabH - 15) * 0.5, 15, tColor)
		}

		contentRect.x += tabSize
		contentRect.width -= tabSize
	}

	return contentRect
}

// Immediate-mode TabBar widget.
// Returns changed=true if a tab was clicked, plus the tab bounds and content area bounds.
GuiTabBar :: proc(
	bounds: rl.Rectangle,
	tabNames: []string,
	activeTab: ^int,
	direction: TabDirection = .Horizontal,
	tabSize: f32 = 30,
	idKey: uintptr = 0,
) -> (changed: bool, tabBounds: rl.Rectangle, contentBounds: rl.Rectangle) {
	tabCount := len(tabNames)
	mousePos := GetUIMousePosition()
	isClick := IsUIMouseButtonPressed(.LEFT)

	key := idKey if idKey != 0 else uintptr(uint(u32(bounds.x * 1000)) ~ uint(u32(bounds.y * 1000)))
	ImmediateNav_RegisterFocusable(key, bounds)
	isFocused := ImmediateNav_IsFocused(key)

	contentBounds = bounds
	changed = false

	if direction == .Horizontal {
		tabBounds = rl.Rectangle{bounds.x, bounds.y, bounds.width, tabSize}
		contentBounds.y += tabSize
		contentBounds.height -= tabSize

		tabW := bounds.width / f32(max(tabCount, 1))
		for i := 0; i < tabCount; i += 1 {
			tabR := rl.Rectangle{bounds.x + f32(i) * tabW, bounds.y, tabW, tabSize}
			if PointInRect(mousePos, tabR) {
				SetUICursor(.POINTING_HAND, .Hover)
				if isClick {
					ImmediateNav_SetFocus(key)
					if activeTab^ != i {
						activeTab^ = i
						changed = true
					}
				}
			}
		}
	} else {
		tabBounds = rl.Rectangle{bounds.x, bounds.y, tabSize, bounds.height}
		contentBounds.x += tabSize
		contentBounds.width -= tabSize

		tabH := min(bounds.height / f32(max(tabCount, 1)), 44.0)
		for i := 0; i < tabCount; i += 1 {
			tabR := rl.Rectangle{bounds.x, bounds.y + f32(i) * tabH, tabSize, tabH}
			if PointInRect(mousePos, tabR) {
				SetUICursor(.POINTING_HAND, .Hover)
				if isClick {
					ImmediateNav_SetFocus(key)
					if activeTab^ != i {
						activeTab^ = i
						changed = true
					}
				}
			}
		}
	}

	// Keyboard navigation when focused
	if isFocused && tabCount > 0 && rl.IsWindowReady() {
		if IsUIKeyPressed(.LEFT) || IsUIKeyPressed(.UP) {
			newTab := (activeTab^ - 1 + tabCount) % tabCount
			if newTab != activeTab^ {
				activeTab^ = newTab
				changed = true
			}
		} else if IsUIKeyPressed(.RIGHT) || IsUIKeyPressed(.DOWN) {
			newTab := (activeTab^ + 1) % tabCount
			if newTab != activeTab^ {
				activeTab^ = newTab
				changed = true
			}
		}
	}

	RenderTabContainer(bounds, tabNames, activeTab^, direction, tabSize, focused = isFocused)
	return changed, tabBounds, contentBounds
}
