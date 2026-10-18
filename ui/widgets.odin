package ui

import "core:fmt"
import "core:math"
import "core:strings"
import rl "vendor:raylib"

// ============================================================================
// Standalone UI Enums & Types (Independent of Engine / GameContext)
// ============================================================================
WidgetType :: enum {
	None,
	Panel,
	VerticalContainer,
	HorizontalContainer,
	GridContainer,
	TabContainer,
	TabBar,
	Label,
	Button,
	Slider,
	Checkbox,
	ToggleSwitch,
	Knob,
	TextInput,
	Dropdown,
	RadioGroup,
	XYPlot,
	Separator,
	ProgressBar,
	ScrollPanel,
	ColorPicker,
	TreeView,
	ListView,
	VolumeFader,
	VolumeMeter,
	NotchedSlider,
	DockSpace,
	UnorderedList,
	OrderedList,
	Table,
}

SliderOrientation :: enum {
	Horizontal,
	Vertical,
}

MeterOrientation :: enum {
	Vertical,
	Horizontal,
}

VolumeMeterState :: struct {
	peakL: f32,
	peakR: f32,
	peakHoldTimerL: f32,
	peakHoldTimerR: f32,
	clipL: bool,
	clipR: bool,
	clipHoldTimerL: f32,
	clipHoldTimerR: f32,
}

TextAlign :: enum {
	Left,
	Center,
	Right,
}

LayoutDirection :: enum {
	Vertical,
	Horizontal,
	Grid,
}

Alignment :: enum {
	Start,
	Center,
	End,
	Stretch,
}

// ============================================================================
// 1. Label Rendering
// ============================================================================
RenderLabel :: proc(
	rect: rl.Rectangle,
	text: string,
	fontSize: f32,
	textColor: rl.Color,
	align: TextAlign = .Left,
	drawBackground: bool = false,
	backgroundColor: rl.Color = {30, 32, 38, 200},
) {
	if !rl.IsWindowReady() do return

	if drawBackground {
		rl.DrawRectangleRec(rect, backgroundColor)
	}

	if strings.contains_rune(text, '\n') {
		lines := strings.split(text, "\n", context.temp_allocator)
		lineH := fontSize + 3
		totalH := f32(len(lines)) * lineH - 3
		startY := rect.y + (rect.height - totalH) * 0.5
		for line, i in lines {
			lc := strings.clone_to_cstring(line, context.temp_allocator)
			lm := MeasureText(lc, fontSize)
			lx := rect.x + 2
			if align == .Center {
				lx = rect.x + (rect.width - lm.x) * 0.5
			} else if align == .Right {
				lx = rect.x + rect.width - lm.x - 2
			}
			ly := startY + f32(i) * lineH
			DrawText(lc, lx, ly, fontSize, textColor)
		}
	} else {
		cstr := fmt.ctprint(text)
		measured := MeasureText(cstr, fontSize)
		tx := rect.x
		switch align {
		case .Left:
			tx = rect.x + 2
		case .Center:
			tx = rect.x + (rect.width - measured.x) * 0.5
		case .Right:
			tx = rect.x + rect.width - measured.x - 2
		}
		ty := rect.y + (rect.height - measured.y) * 0.5
		DrawText(cstr, tx, ty, fontSize, textColor)
	}
}

// ============================================================================
// 2. Button Rendering (with Focus Indicator)
// ============================================================================
RenderButton :: proc(
	rect: rl.Rectangle,
	text: string,
	fontSize: f32,
	hovered: bool,
	isPressed: bool,
	normalColor: rl.Color = {35, 39, 49, 255},
	hoverColor: rl.Color = {50, 56, 72, 255},
	pressedColor: rl.Color = {37, 99, 235, 255},
	borderColor: rl.Color = {75, 83, 102, 255},
	textColor: rl.Color = {238, 240, 246, 255},
	align: TextAlign = .Center,
	focused: bool = false,
) {
	if !rl.IsWindowReady() do return

	bg := normalColor
	border := borderColor
	if isPressed {
		bg = pressedColor
		border = rl.Color{110, 168, 254, 255}
	} else if hovered {
		bg = hoverColor
		border = rl.Color{110, 168, 254, 255}
	} else if focused {
		border = rl.Color{110, 168, 254, 255}
	}

	rl.DrawRectangleRec(rect, bg)
	rl.DrawRectangleLinesEx(rect, 1, border)

	// Left subtle accent bar when hovered, pressed, or focused
	if hovered || isPressed || focused {
		rl.DrawRectangleRec({rect.x, rect.y, 3, rect.height}, rl.Color{110, 168, 254, 255})
	}

	if focused {
		RenderFocusRing(rect, true, 2.0)
	}

	if strings.contains_rune(text, '\n') {
		lines := strings.split(text, "\n", context.temp_allocator)
		lineH := fontSize + 4
		totalH := f32(len(lines)) * lineH - 4
		startY := rect.y + (rect.height - totalH) * 0.5
		for line, i in lines {
			lc := strings.clone_to_cstring(line, context.temp_allocator)
			lm := MeasureText(lc, fontSize)
			lx := rect.x + (rect.width - lm.x) * 0.5
			if align == .Left {
				lx = rect.x + 8
			} else if align == .Right {
				lx = rect.x + rect.width - lm.x - 8
			}
			ly := startY + f32(i) * lineH
			DrawText(lc, lx, ly, fontSize, textColor)
		}
	} else {
		cstr := fmt.ctprint(text)
		measured := MeasureText(cstr, fontSize)
		tx := rect.x + (rect.width - measured.x) * 0.5
		if align == .Left {
			tx = rect.x + 8
		} else if align == .Right {
			tx = rect.x + rect.width - measured.x - 8
		}
		ty := rect.y + (rect.height - measured.y) * 0.5
		DrawText(cstr, tx, ty, fontSize, textColor)
	}
}

// ============================================================================
// 3. Slider SubRects & Rendering (Editable Text, Shift Fine Mode, Reset [R])
// ============================================================================
GetSliderSubRects :: proc(
	rect: rl.Rectangle,
	hasLabel: bool,
	labelWidth: f32,
	showResetButton: bool,
	valBoxW: f32 = 64,
) -> (trackRect, valBoxRect, resetRect: rl.Rectangle) {
	lw := labelWidth if hasLabel else 0
	resetW: f32 = 22 if showResetButton else 0
	gap: f32 = 4

	trackX := rect.x + lw
	trackW := max(rect.width - lw - valBoxW - resetW - gap * (2 if showResetButton else 1), 36)
	trackRect = rl.Rectangle{trackX, rect.y + 1, trackW, max(rect.height - 2, 14)}
	valBoxRect = rl.Rectangle{trackX + trackW + gap, rect.y, valBoxW, max(rect.height, 16)}
	resetRect = rl.Rectangle{valBoxRect.x + valBoxW + gap, rect.y, resetW, max(rect.height, 16)}
	return
}

RenderSlider :: proc(
	rect: rl.Rectangle,
	label: string,
	value: f32,
	minValue: f32,
	maxValue: f32,
	defaultValue: f32,
	isInteger: bool,
	showResetButton: bool,
	labelWidth: f32,
	hovered: bool,
	isDragging: bool,
	fineModeActive: bool,
	isEditingText: bool,
	editText: string,
	focused: bool = false,
) {
	if !rl.IsWindowReady() do return
	trackRect, valBoxRect, resetRect := GetSliderSubRects(rect, label != "", labelWidth, showResetButton)

	// 1. Label
	if label != "" {
		DrawText(fmt.ctprint(label), rect.x + 2, rect.y + (rect.height - 14) * 0.5, 14, rl.Color{215, 220, 230, 255})
	}

	// 2. Slider Track & Fill
	rl.DrawRectangleRec(trackRect, rl.Color{24, 27, 34, 255})
	range := max(maxValue - minValue, 0.0001)
	norm := clamp((value - minValue) / range, 0.0, 1.0)
	fillW := (trackRect.width - 4) * norm
	fillColor := rl.Color{245, 158, 11, 220} if fineModeActive else rl.Color{59, 130, 246, 210}
	if fillW > 0 {
		rl.DrawRectangleRec({trackRect.x + 2, trackRect.y + 2, fillW, trackRect.height - 4}, fillColor)
	}

	// Grab handle
	grabX := trackRect.x + 2 + clamp(fillW - 4, 0, max(trackRect.width - 10, 0))
	rl.DrawRectangleRec({grabX, trackRect.y + 1, 8, trackRect.height - 2}, rl.Color{230, 236, 248, 255})

	trackBorder := rl.Color{245, 158, 11, 255} if fineModeActive else (rl.Color{110, 168, 254, 255} if (hovered || isDragging || focused) else rl.Color{62, 68, 82, 255})
	rl.DrawRectangleLinesEx(trackRect, 1, trackBorder)

	if fineModeActive {
		DrawText("FINE", trackRect.x + 6, trackRect.y + (trackRect.height - 11) * 0.5, 11, rl.Color{255, 235, 180, 255})
	}

	// Focus Ring around active track or box
	if focused {
		RenderFocusRing(trackRect, true, 2.0)
	}

	// 3. Editable Value Box
	valBg := rl.Color{18, 20, 26, 255} if isEditingText else rl.Color{30, 33, 41, 255}
	valBorder := rl.Color{110, 168, 254, 255} if (isEditingText || (focused && isEditingText)) else rl.Color{68, 74, 88, 255}
	rl.DrawRectangleRec(valBoxRect, valBg)
	rl.DrawRectangleLinesEx(valBoxRect, 1, valBorder)

	valText: cstring
	if isEditingText {
		valText = fmt.ctprintf("%s|", editText)
	} else if isInteger {
		valText = fmt.ctprintf("%d", int(math.round(value)))
	} else {
		valText = fmt.ctprintf("%.2f", value)
	}
	measured := MeasureText(valText, 13)
	DrawText(valText, valBoxRect.x + (valBoxRect.width - measured.x) * 0.5, valBoxRect.y + (valBoxRect.height - 13) * 0.5, 13, rl.Color{235, 238, 245, 255})

	// 4. Reset Button [R]
	if showResetButton {
		isModified := abs(value - defaultValue) > 0.001
		rBg := rl.Color{46, 52, 66, 255} if isModified else rl.Color{28, 30, 36, 255}
		rBorder := rl.Color{110, 168, 254, 255} if isModified else rl.Color{55, 60, 70, 255}
		rTextCol := rl.Color{235, 240, 255, 255} if isModified else rl.Color{120, 125, 135, 255}
		rl.DrawRectangleRec(resetRect, rBg)
		rl.DrawRectangleLinesEx(resetRect, 1, rBorder)
		DrawText("R", resetRect.x + (resetRect.width - 8) * 0.5, resetRect.y + (resetRect.height - 13) * 0.5, 13, rTextCol)
	}
}

// ============================================================================
// 4. Checkbox Rendering (with Focus Indicator)
// ============================================================================
RenderCheckbox :: proc(
	rect: rl.Rectangle,
	label: string,
	checked: bool,
	hovered: bool,
	accentColor: rl.Color = {59, 130, 246, 255},
	boxSize: f32 = 18,
	focused: bool = false,
) {
	if !rl.IsWindowReady() do return

	boxRect := rl.Rectangle{rect.x + 2, rect.y + (rect.height - boxSize) * 0.5, boxSize, boxSize}

	bg := accentColor if checked else rl.Color{28, 31, 38, 255}
	border := rl.Color{110, 168, 254, 255} if (hovered || checked || focused) else rl.Color{72, 78, 92, 255}
	rl.DrawRectangleRec(boxRect, bg)
	rl.DrawRectangleLinesEx(boxRect, 1, border)

	if checked {
		// Draw crisp checkmark lines inside boxRect
		scale := boxSize / 18.0
		p1 := rl.Vector2{boxRect.x + 4 * scale, boxRect.y + 9 * scale}
		p2 := rl.Vector2{boxRect.x + 8 * scale, boxRect.y + 13 * scale}
		p3 := rl.Vector2{boxRect.x + 14 * scale, boxRect.y + 5 * scale}
		rl.DrawLineEx(p1, p2, 2.0, rl.WHITE)
		rl.DrawLineEx(p2, p3, 2.0, rl.WHITE)
	}

	if focused {
		RenderFocusRing(boxRect, true, 2.0)
	}

	if label != "" {
		DrawText(fmt.ctprint(label), boxRect.x + boxSize + 10, rect.y + (rect.height - 14) * 0.5, 14, rl.Color{225, 228, 236, 255})
	}
}

// ============================================================================
// 5. TextInput Rendering
// ============================================================================
RenderTextInput :: proc(
	rect: rl.Rectangle,
	label: string,
	text: string,
	placeholder: string,
	labelWidth: f32,
	hovered: bool,
	focused: bool,
	blinkTimer: f32,
) {
	if !rl.IsWindowReady() do return
	lw := labelWidth if label != "" else 0

	if label != "" {
		DrawText(fmt.ctprint(label), rect.x + 2, rect.y + (rect.height - 14) * 0.5, 14, rl.Color{215, 220, 230, 255})
	}

	boxRect := rl.Rectangle{rect.x + lw, rect.y + 2, max(rect.width - lw, 60), rect.height - 4}
	bg := rl.Color{18, 20, 26, 255} if focused else rl.Color{26, 29, 36, 255}
	border := rl.Color{110, 168, 254, 255} if (focused || hovered) else rl.Color{66, 72, 86, 255}

	rl.DrawRectangleRec(boxRect, bg)
	rl.DrawRectangleLinesEx(boxRect, 1, border)

	if focused {
		RenderFocusRing(boxRect, true, 2.0)
	}

	if len(text) > 0 {
		showCursor := focused && (int(blinkTimer * 2.0) % 2 == 0)
		displayStr := fmt.ctprintf("%s%s", text, "|" if showCursor else "")
		DrawText(displayStr, boxRect.x + 8, boxRect.y + (boxRect.height - 14) * 0.5, 14, rl.Color{235, 238, 245, 255})
	} else if focused {
		showCursor := (int(blinkTimer * 2.0) % 2 == 0)
		DrawText("|" if showCursor else "", boxRect.x + 8, boxRect.y + (boxRect.height - 14) * 0.5, 14, rl.Color{110, 168, 254, 255})
	} else {
		DrawText(fmt.ctprint(placeholder), boxRect.x + 8, boxRect.y + (boxRect.height - 14) * 0.5, 14, rl.Color{115, 120, 134, 255})
	}
}

// ============================================================================
// 6. Dropdown & Popup Overlay Rendering (with Focus Indicator)
// ============================================================================
RenderDropdownBox :: proc(
	rect: rl.Rectangle,
	label: string,
	boxRect: rl.Rectangle,
	selectedText: string,
	hovered: bool,
	isOpen: bool,
	focused: bool = false,
) {
	if !rl.IsWindowReady() do return

	if label != "" {
		DrawText(fmt.ctprint(label), rect.x + 2, rect.y + (rect.height - 14) * 0.5, 14, rl.Color{215, 220, 230, 255})
	}

	bg := rl.Color{36, 40, 50, 255} if (hovered || isOpen) else rl.Color{28, 31, 38, 255}
	border := rl.Color{110, 168, 254, 255} if (hovered || isOpen || focused) else rl.Color{66, 72, 86, 255}
	rl.DrawRectangleRec(boxRect, bg)
	rl.DrawRectangleLinesEx(boxRect, 1, border)

	if focused {
		RenderFocusRing(boxRect, true, 2.0)
	}

	DrawText(fmt.ctprint(selectedText), boxRect.x + 8, boxRect.y + (boxRect.height - 14) * 0.5, 14, rl.Color{235, 238, 245, 255})
	arrowStr: cstring = "^" if isOpen else "v"
	DrawText(arrowStr, boxRect.x + boxRect.width - 18, boxRect.y + (boxRect.height - 14) * 0.5, 14, rl.Color{150, 160, 180, 255})
}

RenderDropdownPopup :: proc(
	popupRect: rl.Rectangle,
	items: []string,
	selectedIndex: int,
	hoveredItemIndex: int,
	itemH: f32 = 24,
) {
	if !rl.IsWindowReady() do return

	rl.DrawRectangleRec(popupRect, rl.Color{22, 24, 30, 252})
	rl.DrawRectangleLinesEx(popupRect, 1, rl.Color{110, 168, 254, 255})

	for item, idx in items {
		iy := popupRect.y + 2 + f32(idx) * itemH
		itemRect := rl.Rectangle{popupRect.x + 2, iy, popupRect.width - 4, itemH}
		if idx == hoveredItemIndex {
			rl.DrawRectangleRec(itemRect, rl.Color{59, 130, 246, 200})
		} else if idx == selectedIndex {
			rl.DrawRectangleRec(itemRect, rl.Color{37, 99, 235, 90})
		}
		DrawText(fmt.ctprint(item), itemRect.x + 8, itemRect.y + (itemH - 14) * 0.5, 14, rl.Color{238, 240, 246, 255})
	}
}

// ============================================================================
// 7. RadioGroup Option Rect & Rendering (with Focus Indicator)
// ============================================================================
GetRadioGroupOptionRect :: proc(
	rect: rl.Rectangle,
	hasLabel: bool,
	labelWidth: f32,
	optionCount: int,
	horizontal: bool,
	index: int,
) -> rl.Rectangle {
	lw := labelWidth if hasLabel else 0
	availW := max(rect.width - lw, 60)
	count := max(optionCount, 1)

	if horizontal {
		optW := availW / f32(count)
		return rl.Rectangle{rect.x + lw + f32(index) * optW, rect.y + 2, optW - 4, rect.height - 4}
	} else {
		rowH: f32 = 24
		return rl.Rectangle{rect.x + lw, rect.y + f32(index) * rowH, availW, rowH - 2}
	}
}

RenderRadioGroup :: proc(
	rect: rl.Rectangle,
	label: string,
	labelWidth: f32,
	options: []string,
	selectedIndex: int,
	hoveredOption: int,
	horizontal: bool,
	focused: bool = false,
) {
	if !rl.IsWindowReady() do return

	if label != "" {
		DrawText(fmt.ctprint(label), rect.x + 2, rect.y + 6, 14, rl.Color{215, 220, 230, 255})
	}

	if focused {
		RenderFocusRing(rect, true, 2.0)
	}

	for opt, i in options {
		optRect := GetRadioGroupOptionRect(rect, label != "", labelWidth, len(options), horizontal, i)
		cx := optRect.x + 10
		cy := optRect.y + optRect.height * 0.5
		isSelected := (i == selectedIndex)
		isHovered := (i == hoveredOption)

		ringColor := rl.Color{110, 168, 254, 255} if (isSelected || isHovered) else rl.Color{90, 96, 112, 255}
		rl.DrawCircleV({cx, cy}, 8, rl.Color{26, 29, 36, 255})
		rl.DrawCircleLinesV({cx, cy}, 8, ringColor)
		if isSelected {
			rl.DrawCircleV({cx, cy}, 4.5, rl.Color{59, 130, 246, 255})
		}

		DrawText(fmt.ctprint(opt), cx + 14, optRect.y + (optRect.height - 13) * 0.5, 13, rl.Color{230, 234, 242, 255})
	}
}

// ============================================================================
// 8. XYPlot Helpers & Rendering
// ============================================================================
GetXYPlotCanvasRect :: proc(rect: rl.Rectangle, hasTitle: bool) -> rl.Rectangle {
	topPad: f32 = 24 if hasTitle else 6
	leftPad: f32 = 38
	rightPad: f32 = 10
	bottomPad: f32 = 20
	return rl.Rectangle{
		rect.x + leftPad,
		rect.y + topPad,
		max(rect.width - leftPad - rightPad, 40),
		max(rect.height - topPad - bottomPad, 30),
	}
}

DrawXYPlotSeries :: proc(
	pts: [][2]f32,
	canvas: rl.Rectangle,
	xmin, xmax, ymin, ymax: f32,
	color: rl.Color,
	showPoints: bool,
) {
	if len(pts) == 0 do return
	xRange := max(xmax - xmin, 0.0001)
	yRange := max(ymax - ymin, 0.0001)

	prevScreen: rl.Vector2
	for p, idx in pts {
		nx := clamp((p.x - xmin) / xRange, 0.0, 1.0)
		ny := clamp((p.y - ymin) / yRange, 0.0, 1.0)
		sx := canvas.x + nx * canvas.width
		sy := canvas.y + (1.0 - ny) * canvas.height
		curScreen := rl.Vector2{sx, sy}

		if idx > 0 {
			rl.DrawLineEx(prevScreen, curScreen, 2.0, color)
		}
		if showPoints {
			rl.DrawCircleV(curScreen, 3.0, color)
		}
		prevScreen = curScreen
	}
}

RenderXYPlot :: proc(
	rect: rl.Rectangle,
	title: string,
	xLabel: string,
	series1Name: string,
	series2Name: string,
	points: [][2]f32,
	secondaryPoints: [][2]f32,
	xmin, xmax, ymin, ymax: f32,
	showGrid: bool,
	showPoints: bool,
	showCrosshair: bool,
	hovered: bool,
	mousePos: [2]f32,
	hoveredDataPos: [2]f32,
	lineColor: rl.Color,
	secondaryLineColor: rl.Color,
	gridColor: rl.Color,
) {
	if !rl.IsWindowReady() do return
	canvas := GetXYPlotCanvasRect(rect, title != "")

	// Outer frame
	rl.DrawRectangleRec(rect, rl.Color{20, 22, 28, 255})
	rl.DrawRectangleLinesEx(rect, 1, rl.Color{58, 64, 78, 255})

	// Title & Legend
	if title != "" {
		DrawText(fmt.ctprint(title), rect.x + 8, rect.y + 4, 13, rl.Color{200, 210, 228, 255})
	}
	if len(points) > 0 && series1Name != "" {
		lx := rect.x + rect.width - 150
		rl.DrawRectangleRec({lx, rect.y + 7, 10, 8}, lineColor)
		DrawText(fmt.ctprint(series1Name), lx + 14, rect.y + 4, 12, lineColor)
	}
	if len(secondaryPoints) > 0 && series2Name != "" {
		lx := rect.x + rect.width - 75
		rl.DrawRectangleRec({lx, rect.y + 7, 10, 8}, secondaryLineColor)
		DrawText(fmt.ctprint(series2Name), lx + 14, rect.y + 4, 12, secondaryLineColor)
	}

	// Plot inner canvas
	rl.DrawRectangleRec(canvas, rl.Color{14, 16, 20, 255})

	// Grid lines (4x4 subdivisions)
	if showGrid {
		cols := 4
		rows := 4
		for c in 1..<cols {
			gx := canvas.x + (canvas.width / f32(cols)) * f32(c)
			rl.DrawLineEx({gx, canvas.y}, {gx, canvas.y + canvas.height}, 1, gridColor)
		}
		for r in 1..<rows {
			gy := canvas.y + (canvas.height / f32(rows)) * f32(r)
			rl.DrawLineEx({canvas.x, gy}, {canvas.x + canvas.width, gy}, 1, gridColor)
		}
		// Zero Y axis line if 0 is within [ymin, ymax]
		if ymin < 0 && ymax > 0 {
			zNorm := (0 - ymin) / (ymax - ymin)
			zy := canvas.y + (1.0 - zNorm) * canvas.height
			rl.DrawLineEx({canvas.x, zy}, {canvas.x + canvas.width, zy}, 1, rl.Color{75, 82, 98, 255})
		}
	}

	// Draw data series
	DrawXYPlotSeries(points, canvas, xmin, xmax, ymin, ymax, lineColor, showPoints)
	DrawXYPlotSeries(secondaryPoints, canvas, xmin, xmax, ymin, ymax, secondaryLineColor, showPoints)

	// Crosshair & Tooltip on Hover
	if hovered && showCrosshair {
		rl.DrawLineEx({mousePos.x, canvas.y}, {mousePos.x, canvas.y + canvas.height}, 1, rl.Color{250, 204, 21, 160})
		rl.DrawLineEx({canvas.x, mousePos.y}, {canvas.x + canvas.width, mousePos.y}, 1, rl.Color{250, 204, 21, 160})
		coordStr := fmt.ctprintf("(%.2f, %.2f)", hoveredDataPos.x, hoveredDataPos.y)
		DrawText(coordStr, canvas.x + 6, canvas.y + 4, 12, rl.Color{250, 204, 21, 255})
	}

	rl.DrawRectangleLinesEx(canvas, 1, rl.Color{68, 74, 88, 255})

	// Axis min/max labels
	DrawText(fmt.ctprintf("%.1f", ymax), rect.x + 4, canvas.y, 11, rl.Color{140, 146, 160, 255})
	DrawText(fmt.ctprintf("%.1f", ymin), rect.x + 4, canvas.y + canvas.height - 12, 11, rl.Color{140, 146, 160, 255})
	DrawText(fmt.ctprintf("%.1f", xmin), canvas.x, canvas.y + canvas.height + 3, 11, rl.Color{140, 146, 160, 255})
	xmaxStr := fmt.ctprintf("%.1f", xmax)
	xmaxW := MeasureText(xmaxStr, 11).x
	DrawText(xmaxStr, canvas.x + canvas.width - xmaxW, canvas.y + canvas.height + 3, 11, rl.Color{140, 146, 160, 255})
	if xLabel != "" {
		xl := fmt.ctprint(xLabel)
		xlW := MeasureText(xl, 11).x
		DrawText(xl, canvas.x + (canvas.width - xlW) * 0.5, canvas.y + canvas.height + 3, 11, rl.Color{165, 172, 188, 255})
	}
}

// ============================================================================
// 9. Separator, ProgressBar, & Container Panel Rendering
// ============================================================================
RenderSeparator :: proc(rect: rl.Rectangle, label: string, lineColor: rl.Color = {62, 68, 82, 255}) {
	if !rl.IsWindowReady() do return
	midY := rect.y + rect.height * 0.5

	if label != "" {
		cstr := fmt.ctprint(label)
		tw := MeasureText(cstr, 13).x
		DrawText(cstr, rect.x + 2, rect.y + (rect.height - 13) * 0.5, 13, rl.Color{110, 168, 254, 255})
		rl.DrawLineEx({rect.x + tw + 10, midY}, {rect.x + rect.width, midY}, 1, lineColor)
	} else {
		rl.DrawLineEx({rect.x, midY}, {rect.x + rect.width, midY}, 1, lineColor)
	}
}

RenderProgressBar :: proc(
	rect: rl.Rectangle,
	label: string,
	value: f32,
	minValue: f32,
	maxValue: f32,
	fillColor: rl.Color = {16, 185, 129, 255},
	direction: ProgressBarDirection = .Horizontal,
	showText: bool = true,
) {
	if !rl.IsWindowReady() do return

	rl.DrawRectangleRec(rect, rl.Color{24, 27, 34, 255})
	norm := clamp((value - minValue) / max(maxValue - minValue, 0.0001), 0.0, 1.0)
	if direction == .Horizontal {
		if norm > 0 {
			rl.DrawRectangleRec({rect.x + 2, rect.y + 2, (rect.width - 4) * norm, rect.height - 4}, fillColor)
		}
	} else {
		fillH := (rect.height - 4) * norm
		if norm > 0 {
			rl.DrawRectangleRec({rect.x + 2, rect.y + rect.height - 2 - fillH, rect.width - 4, fillH}, fillColor)
		}
	}
	rl.DrawRectangleLinesEx(rect, 1, rl.Color{62, 68, 82, 255})

	if showText {
		if direction == .Vertical {
			txt := fmt.ctprintf("%d%%", int(math.round(norm * 100.0)))
			fontSize: f32 = 11
			tw := MeasureText(txt, fontSize).x
			DrawText(txt, rect.x + (rect.width - tw) * 0.5, rect.y + (rect.height - fontSize) * 0.5, fontSize, rl.Color{240, 242, 248, 255})
			if label != "" {
				lw := MeasureText(fmt.ctprint(label), 11).x
				DrawText(fmt.ctprint(label), rect.x + (rect.width - lw) * 0.5, rect.y - 14, 11, rl.Color{170, 175, 190, 255})
			}
		} else {
			txt := fmt.ctprintf("%s: %d%%", label, int(math.round(norm * 100.0))) if label != "" else fmt.ctprintf("%d%%", int(math.round(norm * 100.0)))
			fontSize: f32 = 13
			tw := MeasureText(txt, fontSize).x
			DrawText(txt, rect.x + (rect.width - tw) * 0.5, rect.y + (rect.height - fontSize) * 0.5, fontSize, rl.Color{240, 242, 248, 255})
		}
	}
}

RenderContainerPanel :: proc(
	rect: rl.Rectangle,
	title: string,
	drawBackground: bool,
	drawBorder: bool,
	showHeader: bool,
	headerHeight: f32,
	backgroundColor: rl.Color,
	headerColor: rl.Color,
	borderColor: rl.Color,
	titleColor: rl.Color,
) {
	if !rl.IsWindowReady() do return

	if drawBackground {
		rl.DrawRectangleRec(rect, backgroundColor)
	}

	if showHeader {
		headerRect := rl.Rectangle{rect.x, rect.y, rect.width, headerHeight}
		rl.DrawRectangleRec(headerRect, headerColor)
		rl.DrawLineEx(
			{rect.x, rect.y + headerHeight},
			{rect.x + rect.width, rect.y + headerHeight},
			1,
			borderColor,
		)
		// Top accent stripe on panel header
		rl.DrawRectangleRec({rect.x, rect.y, rect.width, 2}, rl.Color{59, 130, 246, 255})

		if title != "" {
			cstr := fmt.ctprint(title)
			DrawText(cstr, rect.x + 14, rect.y + (headerHeight - 16) * 0.5, 16, titleColor)
		}
	}

	if drawBorder {
		rl.DrawRectangleLinesEx(rect, 1, borderColor)
	}
}

// ============================================================================
// Extended UI Types (ColorStop, TreeViewItem)
// ============================================================================

ColorStop :: struct {
	position: f32,
	color:    rl.Color,
}

TreeViewItem :: struct {
	id:          int,
	label:       string,
	icon:        string,
	depth:       int,
	hasChildren: bool,
	isCollapsed: bool,
	isSelected:  bool,
	isLastChild: bool,
	data:        rawptr,
}

// ============================================================================
// Toggle Switch Rendering (with Focus Indicator)
// ============================================================================
RenderToggleSwitch :: proc(
	rect: rl.Rectangle,
	label: string,
	active: bool,
	hovered: bool = false,
	disabled: bool = false,
	activeColor: rl.Color = {59, 130, 246, 255},
	inactiveColor: rl.Color = {50, 55, 68, 255},
	thumbColor: rl.Color = rl.WHITE,
	focused: bool = false,
) {
	if !rl.IsWindowReady() do return

	trackH := min(rect.height, 22.0)
	trackW := trackH * 1.8
	trackRect := rl.Rectangle{rect.x, rect.y + (rect.height - trackH) * 0.5, trackW, trackH}

	trackCol := activeColor if active else inactiveColor
	if disabled {
		trackCol = rl.Color{40, 42, 50, 200}
	} else if hovered {
		trackCol = activeColor if active else rl.Color{65, 72, 88, 255}
	}

	rl.DrawRectangleRounded(trackRect, 0.9, 8, trackCol)
	borderCol := rl.Color{110, 168, 254, 255} if focused else rl.Color{75, 85, 105, 255}
	rl.DrawRectangleRoundedLinesEx(trackRect, 0.9, 8, 1, borderCol)

	if focused {
		RenderFocusRing(trackRect, true, 2.0)
	}

	thumbPadding: f32 = 2.0
	thumbRadius := (trackH - thumbPadding * 2.0) * 0.5
	thumbX := trackRect.x + thumbPadding + thumbRadius if !active else trackRect.x + trackW - thumbPadding - thumbRadius
	thumbY := trackRect.y + trackH * 0.5

	rl.DrawCircle(i32(math.round(thumbX)), i32(math.round(thumbY)), thumbRadius, thumbColor)

	if label != "" {
		labelX := trackRect.x + trackW + 8
		labelY := rect.y + (rect.height - 14) * 0.5
		lblColor := rl.Color{220, 225, 235, 255} if !disabled else rl.Color{120, 125, 135, 255}
		cstr := fmt.ctprint(label)
		DrawText(cstr, labelX, labelY, 14, lblColor)
	}
}

// ============================================================================
// Rotary Knob Rendering (with Focus Indicator)
// ============================================================================
RenderKnob :: proc(
	rect: rl.Rectangle,
	label: string,
	value: f32,
	minValue: f32,
	maxValue: f32,
	format: string = "%.2f",
	hovered: bool = false,
	active: bool = false,
	primaryColor: rl.Color = {59, 130, 246, 255},
	dialColor: rl.Color = {32, 36, 46, 255},
	trackColor: rl.Color = {48, 54, 68, 255},
	labelColor: rl.Color = {210, 215, 228, 255},
	focused: bool = false,
	fineMode: bool = false,
) {
	if !rl.IsWindowReady() do return

	norm := clamp((value - minValue) / max(maxValue - minValue, 0.0001), 0.0, 1.0)

	labelH: f32 = 16.0 if label != "" else 0.0
	valueH: f32 = 14.0
	availableH := max(rect.height - labelH - valueH - 4, 16.0)

	dialSize := min(rect.width, availableH)
	radius := dialSize * 0.5
	center := rl.Vector2{rect.x + rect.width * 0.5, rect.y + radius}

	startAngle: f32 = 135.0
	endAngle: f32 = 405.0
	valueAngle := startAngle + norm * (endAngle - startAngle)

	// Outer value track arc
	trackThickness: f32 = max(radius * 0.10, 3.0)
	trackOuter: f32 = radius
	trackInner: f32 = radius - trackThickness

	rl.DrawRing(center, trackInner, trackOuter, startAngle, endAngle, 36, trackColor)

	activeArcCol := primaryColor
	if fineMode {
		activeArcCol = rl.Color{245, 158, 11, 255}
	} else if active {
		activeArcCol = rl.Color{96, 165, 250, 255}
	} else if hovered || focused {
		activeArcCol = rl.Color{80, 150, 250, 255}
	}
	if norm > 0.005 {
		rl.DrawRing(center, trackInner - 0.5, trackOuter + 0.5, startAngle, valueAngle, 36, activeArcCol)
	}

	// Distinct gap separating the outer value arc from the inner rotating knob body
	arcToKnobGap: f32 = max(radius * 0.20, 6.0)
	knobRadius: f32 = max(trackInner - arcToKnobGap, 8.0)

	// Inner rotating knob body
	rl.DrawCircleV(center, knobRadius, dialColor)
	borderCol := rl.Color{245, 158, 11, 255} if fineMode else (rl.Color{110, 168, 254, 255} if focused else rl.Color{60, 66, 82, 255})
	rl.DrawCircleLines(i32(math.round(center.x)), i32(math.round(center.y)), knobRadius, borderCol)

	if focused {
		focusRect := rl.Rectangle{center.x - radius - 2, center.y - radius - 2, (radius + 2) * 2, (radius + 2) * 2}
		RenderFocusRing(focusRect, true, 2.0)
	}

	if fineMode {
		DrawText("FINE", center.x - 11, center.y - 5, 10, rl.Color{255, 235, 180, 255})
	}

	rad := valueAngle * (math.PI / 180.0)
	needleLen := knobRadius - 3.0
	needleEnd := rl.Vector2{
		center.x + math.cos(rad) * needleLen,
		center.y + math.sin(rad) * needleLen,
	}
	needleStart := rl.Vector2{
		center.x + math.cos(rad) * (needleLen * 0.25),
		center.y + math.sin(rad) * (needleLen * 0.25),
	}
	needleCol := rl.Color{255, 235, 180, 255} if fineMode else rl.WHITE
	rl.DrawLineEx(needleStart, needleEnd, 2.5, needleCol)

	valStr := fmt.tprintf(format, value)
	valCStr := fmt.ctprint(valStr)
	valW := MeasureText(valCStr, 12).x
	valY := center.y + radius + 4
	DrawText(valCStr, center.x - valW * 0.5, valY, 12, rl.Color{230, 235, 245, 255})

	if label != "" {
		lblCStr := fmt.ctprint(label)
		lblW := MeasureText(lblCStr, 12).x
		lblY := valY + 14
		DrawText(lblCStr, center.x - lblW * 0.5, lblY, 12, labelColor)
	}
}

// ============================================================================
// List View Rendering (with Focus Indicator)
// ============================================================================
RenderListView :: proc(
	rect: rl.Rectangle,
	items: []string,
	selectedIndex: int,
	hoveredIndex: int,
	scrollOffset: f32,
	itemHeight: f32 = 24,
	bgColor: rl.Color = {24, 26, 32, 240},
	borderColor: rl.Color = {55, 60, 75, 255},
	selectedColor: rl.Color = {45, 90, 180, 255},
	hoverColor: rl.Color = {40, 45, 58, 255},
	focused: bool = false,
) {
	if !rl.IsWindowReady() do return

	rl.DrawRectangleRec(rect, bgColor)
	borderCol := rl.Color{110, 168, 254, 255} if focused else borderColor
	rl.DrawRectangleLinesEx(rect, 1, borderCol)

	if focused {
		RenderFocusRing(rect, true, 2.0)
	}

	itemCount := len(items)
	for i := 0; i < itemCount; i += 1 {
		itemY := rect.y + f32(i) * itemHeight - scrollOffset
		if itemY + itemHeight < rect.y || itemY > rect.y + rect.height do continue

		itemRect := rl.Rectangle{rect.x + 1, itemY, rect.width - 2, itemHeight}

		if i == selectedIndex {
			rl.DrawRectangleRec(itemRect, selectedColor)
		} else if i == hoveredIndex {
			rl.DrawRectangleRec(itemRect, hoverColor)
		}

		txtCol := rl.WHITE if i == selectedIndex else rl.Color{215, 220, 230, 255}
		cstr := fmt.ctprint(items[i])
		DrawText(cstr, itemRect.x + 8, itemRect.y + (itemHeight - 13) * 0.5, 13, txtCol)
	}
}

// ============================================================================
// Tree View Node Item Rendering (with Focus Indicator)
// ============================================================================
RenderTreeNode :: proc(
	rect: rl.Rectangle,
	item: TreeViewItem,
	hovered: bool = false,
	lineColor: rl.Color = {75, 80, 92, 255},
	selectedColor: rl.Color = {45, 80, 160, 255},
	hoverColor: rl.Color = {38, 42, 54, 255},
	focused: bool = false,
) {
	if !rl.IsWindowReady() do return

	indent: f32 = f32(item.depth) * 16.0
	rowX := rect.x + indent
	rowW := max(rect.width - indent, 40.0)

	if item.depth > 0 {
		branchX := rowX - 10
		midY := rect.y + rect.height * 0.5
		topY := rect.y - 4
		bottomY := midY if item.isLastChild else rect.y + rect.height + 4
		rl.DrawLineEx({branchX, topY}, {branchX, bottomY}, 1, lineColor)
		rl.DrawLineEx({branchX, midY}, {rowX - 2, midY}, 1, lineColor)
	}

	rowRect := rl.Rectangle{rowX, rect.y, rowW, rect.height}
	if item.isSelected {
		rl.DrawRectangleRec(rowRect, selectedColor)
	} else if hovered {
		rl.DrawRectangleRec(rowRect, hoverColor)
	}

	if focused {
		RenderFocusRing(rowRect, true, 1.0)
	}

	btnOffsetX: f32 = 0
	if item.hasChildren {
		boxRect := rl.Rectangle{rowX + 2, rect.y + (rect.height - 14) * 0.5, 14, 14}
		rl.DrawRectangleRec(boxRect, rl.Color{30, 34, 44, 255})
		rl.DrawRectangleLinesEx(boxRect, 1, rl.Color{75, 82, 98, 255})
		sym := "+" if item.isCollapsed else "-"
		DrawText(fmt.ctprint(sym), boxRect.x + 3, boxRect.y + 1, 11, rl.Color{200, 210, 230, 255})
		btnOffsetX = 18
	}

	txtX := rowX + btnOffsetX + 4
	txtY := rect.y + (rect.height - 13) * 0.5
	txtCol := rl.WHITE if item.isSelected else rl.Color{215, 220, 232, 255}

	fullTxt := fmt.ctprint(item.icon, item.label) if item.icon != "" else fmt.ctprint(item.label)
	DrawText(fullTxt, txtX, txtY, 13, txtCol)
}


// ============================================================================
// 12. Volume Fader Helpers & Rendering (Studio Console Audio Fader)
// ============================================================================
FaderDbToNorm :: proc(db: f32, minDb: f32 = -60.0, maxDb: f32 = 6.0) -> f32 {
	if db <= minDb do return 0.0
	if db >= maxDb do return 1.0
	// 0 dB (Unity Gain) is placed at 75% travel (0.75 norm)
	if db >= 0.0 {
		return 0.75 + (db / maxDb) * 0.25
	} else {
		// db in [minDb, 0.0] -> norm in [0.0, 0.75]
		return 0.75 * (1.0 - (db / minDb))
	}
}

FaderNormToDb :: proc(norm: f32, minDb: f32 = -60.0, maxDb: f32 = 6.0) -> f32 {
	n := clamp(norm, 0.0, 1.0)
	if n >= 0.75 {
		return ((n - 0.75) / 0.25) * maxDb
	} else {
		return (1.0 - (n / 0.75)) * minDb
	}
}

RenderVolumeFader :: proc(
	rect: rl.Rectangle,
	label: string,
	valueDb: f32,
	minDb: f32 = -60.0,
	maxDb: f32 = 6.0,
	defaultDb: f32 = 0.0,
	hovered: bool = false,
	isDragging: bool = false,
	focused: bool = false,
	fineMode: bool = false,
) {
	if !rl.IsWindowReady() do return

	// Background backing panel
	rl.DrawRectangleRec(rect, rl.Color{24, 27, 34, 240})
	borderCol := rl.Color{110, 168, 254, 255} if focused else rl.Color{55, 62, 78, 255}
	rl.DrawRectangleLinesEx(rect, 1, borderCol)

	if focused {
		RenderFocusRing(rect, true, 2.0)
	}

	// 1. Channel Title Header
	if label != "" {
		DrawText(fmt.ctprint(label), rect.x + 8, rect.y + 6, 12, rl.Color{210, 218, 235, 255})
	}

	slotTop := rect.y + 26
	slotBottom := rect.y + rect.height - 30
	slotH := max(slotBottom - slotTop, 40.0)
	slotX := rect.x + rect.width * 0.5

	// 2. Ticks and dB Graduations
	dBLevels := []f32{+6.0, 0.0, -6.0, -12.0, -24.0, -36.0, -48.0, -60.0}
	for db in dBLevels {
		norm := FaderDbToNorm(db, minDb, maxDb)
		ty := slotBottom - norm * slotH
		isUnity := abs(db - 0.0) < 0.1

		tickLen: f32 = 8.0 if isUnity else 5.0
		tickCol := rl.Color{96, 165, 250, 255} if isUnity else rl.Color{90, 98, 115, 255}

		// Left and right graduation lines
		rl.DrawLineEx({slotX - 12 - tickLen, ty}, {slotX - 12, ty}, 1, tickCol)
		rl.DrawLineEx({slotX + 12, ty}, {slotX + 12 + tickLen, ty}, 1, tickCol)

		// Graduation labels on left side
		lblStr: string
		if isUnity {
			lblStr = "0"
		} else if db == minDb {
			lblStr = "-INF"
		} else if db > 0 {
			lblStr = fmt.tprintf("+%.0f", db)
		} else {
			lblStr = fmt.tprintf("%.0f", db)
		}
		lblCStr := fmt.ctprint(lblStr)
		meas := MeasureText(lblCStr, 9)
		DrawText(lblCStr, slotX - 15 - tickLen - meas.x, ty - meas.y * 0.5, 9, tickCol)
	}

	// 3. Center Slot / Trough
	troughW: f32 = 6.0
	troughRect := rl.Rectangle{slotX - troughW * 0.5, slotTop, troughW, slotH}
	rl.DrawRectangleRec(troughRect, rl.Color{16, 18, 24, 255})
	rl.DrawRectangleLinesEx(troughRect, 1, rl.Color{45, 50, 64, 255})
	// Center reference hair-line
	rl.DrawLineEx({slotX, slotTop}, {slotX, slotBottom}, 1, rl.Color{32, 36, 48, 255})

	// 4. Physical Fader Cap / Thumb
	curNorm := FaderDbToNorm(valueDb, minDb, maxDb)
	capCenterY := slotBottom - curNorm * slotH
	capW: f32 = min(rect.width * 0.65, 42.0)
	capH: f32 = 22.0
	capRect := rl.Rectangle{slotX - capW * 0.5, capCenterY - capH * 0.5, capW, capH}

	// Cap metallic body
	capBg := rl.Color{45, 52, 68, 255} if isDragging else (rl.Color{38, 44, 58, 255} if hovered else rl.Color{32, 37, 48, 255})
	rl.DrawRectangleRec(capRect, capBg)
	// Bevel highlights
	rl.DrawLineEx({capRect.x, capRect.y}, {capRect.x + capRect.width, capRect.y}, 1, rl.Color{90, 100, 125, 255})
	rl.DrawLineEx({capRect.x, capRect.y + capRect.height}, {capRect.x + capRect.width, capRect.y + capRect.height}, 1, rl.Color{18, 20, 26, 255})
	rl.DrawRectangleLinesEx(capRect, 1, rl.Color{75, 84, 105, 255})

	// Grip texture ridges on cap
	rl.DrawLineEx({capRect.x + 4, capRect.y + 4}, {capRect.x + capRect.width - 4, capRect.y + 4}, 1, rl.Color{55, 62, 78, 255})
	rl.DrawLineEx({capRect.x + 4, capRect.y + capRect.height - 4}, {capRect.x + capRect.width - 4, capRect.y + capRect.height - 4}, 1, rl.Color{55, 62, 78, 255})

	// Center indicator notch line on fader cap
	lineCol := rl.Color{245, 158, 11, 255} if fineMode else (rl.Color{96, 165, 250, 255} if abs(valueDb - defaultDb) < 0.1 else rl.Color{240, 245, 255, 255})
	rl.DrawRectangleRec({capRect.x + 2, capCenterY - 1, capW - 4, 2}, lineCol)

	// 5. Digital Value Readout Box at bottom
	valBoxRect := rl.Rectangle{rect.x + 6, rect.y + rect.height - 24, rect.width - 12, 18}
	rl.DrawRectangleRec(valBoxRect, rl.Color{18, 20, 26, 255})
	rl.DrawRectangleLinesEx(valBoxRect, 1, rl.Color{45, 52, 68, 255})

	valText: string
	if fineMode {
		valText = "FINE"
	} else if valueDb <= minDb + 0.1 {
		valText = "-INF dB"
	} else if valueDb > 0.0 {
		valText = fmt.tprintf("+%.1f dB", valueDb)
	} else {
		valText = fmt.tprintf("%.1f dB", valueDb)
	}
	valCStr := fmt.ctprint(valText)
	valMeas := MeasureText(valCStr, 11)
	textCol := rl.Color{245, 158, 11, 255} if fineMode else rl.Color{230, 235, 245, 255}
	DrawText(valCStr, valBoxRect.x + (valBoxRect.width - valMeas.x) * 0.5, valBoxRect.y + (valBoxRect.height - valMeas.y) * 0.5, 11, textCol)
}

// ============================================================================
// 13. Volume Meter Rendering (Stereo / Mono Segmented VU Peak Meter)
// ============================================================================
RenderVolumeMeter :: proc(
	rect: rl.Rectangle,
	label: string,
	levelL: f32, // in dB (-60 to +3)
	levelR: f32 = -120.0, // in dB (-60 to +3); if < -100, mono meter
	state: ^VolumeMeterState = nil,
	orientation: MeterOrientation = .Vertical,
	minDb: f32 = -60.0,
	maxDb: f32 = 3.0,
) {
	if !rl.IsWindowReady() do return

	isStereo := levelR >= -100.0

	// Outer chassis
	rl.DrawRectangleRec(rect, rl.Color{20, 22, 28, 255})
	rl.DrawRectangleLinesEx(rect, 1, rl.Color{50, 56, 70, 255})

	if orientation == .Vertical {
		headerH: f32 = 18.0 if label != "" else 4.0
		if label != "" {
			DrawText(fmt.ctprint(label), rect.x + 6, rect.y + 4, 11, rl.Color{200, 205, 220, 255})
		}

		meterTop := rect.y + headerH
		meterH := max(rect.height - headerH - 8, 30.0)
		scaleW: f32 = 22.0
		barsW := max(rect.width - scaleW - 12, 16.0)

		clipH: f32 = 7.0
		ladderTop := meterTop + clipH + 3
		ladderH := meterH - clipH - 3

		numSegments := 24
		segGap: f32 = 1.0
		totalGap := f32(numSegments - 1) * segGap
		segH := (ladderH - totalGap) / f32(numSegments)

		// Dynamic peak decay & clip holding
		normL := clamp((levelL - minDb) / (maxDb - minDb), 0.0, 1.0)
		normR := clamp((levelR - minDb) / (maxDb - minDb), 0.0, 1.0)

		if state != nil {
			if normL >= 0.98 do state.clipL = true
			if normR >= 0.98 do state.clipR = true
			if normL > state.peakL {
				state.peakL = normL
				state.peakHoldTimerL = 1.2
			}
			if normR > state.peakR {
				state.peakR = normR
				state.peakHoldTimerR = 1.2
			}
		}

		barW: f32 = (barsW - 4) * 0.5 if isStereo else barsW
		startX := rect.x + 6

		channels := 2 if isStereo else 1
		for ch in 0..<channels {
			bx := startX + f32(ch) * (barW + 4)
			curNorm := normL if ch == 0 else normR
			peakNorm := (state.peakL if ch == 0 else state.peakR) if state != nil else curNorm
			isClip := (state.clipL if ch == 0 else state.clipR) if state != nil else (curNorm >= 0.98)

			// 1. Clip LED Box at top of channel
			clipRect := rl.Rectangle{bx, meterTop, barW, clipH}
			clipCol := rl.Color{239, 68, 68, 255} if isClip else rl.Color{70, 20, 20, 255}
			rl.DrawRectangleRec(clipRect, clipCol)
			rl.DrawRectangleLinesEx(clipRect, 1, rl.Color{100, 30, 30, 255})

			// 2. LED Segments Ladder
			for s in 0..<numSegments {
				segNorm := 1.0 - (f32(s) + 0.5) / f32(numSegments)
				sy := ladderTop + f32(s) * (segH + segGap)
				sRect := rl.Rectangle{bx, sy, barW, segH}

				isLit := curNorm >= segNorm

				litCol: rl.Color
				unlitCol: rl.Color
				if segNorm >= 0.90 {
					// Hot / Overload Zone (Red)
					litCol = rl.Color{239, 68, 68, 255}
					unlitCol = rl.Color{55, 20, 20, 255}
				} else if segNorm >= 0.70 {
					// Caution Zone (Yellow/Amber)
					litCol = rl.Color{245, 158, 11, 255}
					unlitCol = rl.Color{55, 40, 15, 255}
				} else {
					// Safe Signal Zone (Green)
					litCol = rl.Color{16, 185, 129, 255}
					unlitCol = rl.Color{16, 45, 32, 255}
				}

				rl.DrawRectangleRec(sRect, litCol if isLit else unlitCol)
			}

			// 3. Peak Hold Line
			if peakNorm > 0.02 {
				peakY := ladderTop + (1.0 - peakNorm) * ladderH
				rl.DrawRectangleRec({bx, peakY - 1, barW, 2}, rl.Color{240, 248, 255, 255})
			}
		}

		// 4. dB Scale Legend on the right
		scaleX := rect.x + rect.width - scaleW
		dBGrads := []f32{+3.0, 0.0, -6.0, -12.0, -24.0, -48.0}
		for db in dBGrads {
			norm := clamp((db - minDb) / (maxDb - minDb), 0.0, 1.0)
			gy := ladderTop + (1.0 - norm) * ladderH
			isZero := abs(db - 0.0) < 0.1
			lbl := fmt.ctprint("0" if isZero else fmt.tprintf("%.0f", db))
			col := rl.Color{239, 68, 68, 255} if db > 0 else (rl.Color{245, 158, 11, 255} if isZero else rl.Color{120, 130, 150, 255})
			DrawText(lbl, scaleX, gy - 5, 9, col)
		}
	} else {
		// Horizontal Meter Orientation
		meterX := rect.x + 8
		meterW := max(rect.width - 16, 40.0)
		meterY := rect.y + 6
		meterH := max(rect.height - 12, 12.0)

		normL := clamp((levelL - minDb) / (maxDb - minDb), 0.0, 1.0)
		numSegments := 32
		segGap: f32 = 1.0
		totalGap := f32(numSegments - 1) * segGap
		segW := (meterW - totalGap) / f32(numSegments)

		for s in 0..<numSegments {
			segNorm := (f32(s) + 0.5) / f32(numSegments)
			sx := meterX + f32(s) * (segW + segGap)
			sRect := rl.Rectangle{sx, meterY, segW, meterH}

			isLit := normL >= segNorm
			litCol: rl.Color
			unlitCol: rl.Color
			if segNorm >= 0.90 {
				litCol = rl.Color{239, 68, 68, 255}
				unlitCol = rl.Color{55, 20, 20, 255}
			} else if segNorm >= 0.70 {
				litCol = rl.Color{245, 158, 11, 255}
				unlitCol = rl.Color{55, 40, 15, 255}
			} else {
				litCol = rl.Color{16, 185, 129, 255}
				unlitCol = rl.Color{16, 45, 32, 255}
			}
			rl.DrawRectangleRec(sRect, litCol if isLit else unlitCol)
		}
	}
}

// ============================================================================
// 14. Notched Slider Rendering (Horizontal & Vertical with Detent Snapping)
// ============================================================================
RenderNotchedSlider :: proc(
	rect: rl.Rectangle,
	label: string,
	value: f32,
	minValue: f32,
	maxValue: f32,
	numNotches: int,
	notchLabels: []string = nil,
	orientation: SliderOrientation = .Horizontal,
	hovered: bool = false,
	isDragging: bool = false,
	focused: bool = false,
	fineMode: bool = false,
	snappedNotch: int = -1,
) {
	if !rl.IsWindowReady() do return

	norm := clamp((value - minValue) / max(maxValue - minValue, 0.0001), 0.0, 1.0)
	notches := max(numNotches, 2)

	if orientation == .Horizontal {
		// Header Label & Value Display
		labelH: f32 = 16.0 if label != "" else 0.0
		if label != "" {
			DrawText(fmt.ctprint(label), rect.x + 2, rect.y + 2, 12, rl.Color{215, 222, 238, 255})
		}

		// Readout on top right
		valStr: string
		if fineMode {
			valStr = fmt.tprintf("FINE: %.2f", value)
		} else if notchLabels != nil && snappedNotch >= 0 && snappedNotch < len(notchLabels) {
			valStr = notchLabels[snappedNotch]
		} else {
			valStr = fmt.tprintf("%.1f", value)
		}
		valCStr := fmt.ctprint(valStr)
		valW := MeasureText(valCStr, 11).x
		valCol := rl.Color{245, 158, 11, 255} if fineMode else rl.Color{96, 165, 250, 255}
		DrawText(valCStr, rect.x + rect.width - valW - 2, rect.y + 2, 11, valCol)

		trackPadX: f32 = 12.0
		trackY := rect.y + labelH + 10
		trackW := max(rect.width - trackPadX * 2.0, 30.0)
		trackX := rect.x + trackPadX
		trackH: f32 = 6.0

		// Track Groove
		trackRect := rl.Rectangle{trackX, trackY, trackW, trackH}
		rl.DrawRectangleRec(trackRect, rl.Color{22, 25, 33, 255})
		rl.DrawRectangleLinesEx(trackRect, 1, rl.Color{55, 62, 78, 255})

		// Fill active portion
		fillW := trackW * norm
		if fillW > 0 {
			fillCol := rl.Color{245, 158, 11, 220} if fineMode else rl.Color{59, 130, 246, 200}
			rl.DrawRectangleRec({trackX + 1, trackY + 1, fillW, trackH - 2}, fillCol)
		}

		// Draw Notches & Ticks below track
		for i in 0..<notches {
			t := f32(i) / f32(notches - 1)
			nx := trackX + t * trackW
			isCur := i == snappedNotch

			tickH: f32 = 9.0 if isCur else 6.0
			tickCol := rl.Color{96, 165, 250, 255} if isCur else rl.Color{80, 88, 105, 255}
			rl.DrawLineEx({nx, trackY + trackH + 2}, {nx, trackY + trackH + 2 + tickH}, 1.5 if isCur else 1.0, tickCol)

			if notchLabels != nil && i < len(notchLabels) {
				nlCStr := fmt.ctprint(notchLabels[i])
				nlMeas := MeasureText(nlCStr, 9)
				DrawText(nlCStr, nx - nlMeas.x * 0.5, trackY + trackH + 12, 9, tickCol)
			}
		}

		// Thumb Handle
		thumbX := trackX + norm * trackW
		thumbW: f32 = 18.0
		thumbH: f32 = 18.0
		thumbRect := rl.Rectangle{thumbX - thumbW * 0.5, trackY + trackH * 0.5 - thumbH * 0.5, thumbW, thumbH}

		thumbBg := rl.Color{45, 52, 68, 255} if isDragging else (rl.Color{38, 44, 58, 255} if hovered else rl.Color{32, 37, 48, 255})
		rl.DrawRectangleRec(thumbRect, thumbBg)
		borderCol := rl.Color{245, 158, 11, 255} if fineMode else (rl.Color{110, 168, 254, 255} if (hovered || isDragging || focused) else rl.Color{75, 84, 105, 255})
		rl.DrawRectangleLinesEx(thumbRect, 1, borderCol)

		// Notch pointer mark on thumb
		pCol := rl.Color{245, 158, 11, 255} if fineMode else rl.Color{96, 165, 250, 255}
		rl.DrawLineEx({thumbX, thumbRect.y + 3}, {thumbX, thumbRect.y + thumbH - 3}, 2, pCol)

		if focused {
			RenderFocusRing(rect, true, 2.0)
		}
	} else {
		// Vertical Orientation
		labelH: f32 = 16.0 if label != "" else 0.0
		if label != "" {
			DrawText(fmt.ctprint(label), rect.x + 2, rect.y + 2, 11, rl.Color{215, 222, 238, 255})
		}

		trackPadY: f32 = 14.0
		trackY := rect.y + labelH + trackPadY
		trackH := max(rect.height - labelH - trackPadY * 2.0 - 18, 30.0)
		trackX := rect.x + rect.width * 0.4
		trackW: f32 = 6.0

		trackRect := rl.Rectangle{trackX, trackY, trackW, trackH}
		rl.DrawRectangleRec(trackRect, rl.Color{22, 25, 33, 255})
		rl.DrawRectangleLinesEx(trackRect, 1, rl.Color{55, 62, 78, 255})

		// Fill active portion (bottom to top)
		fillH := trackH * norm
		if fillH > 0 {
			fillCol := rl.Color{245, 158, 11, 220} if fineMode else rl.Color{59, 130, 246, 200}
			rl.DrawRectangleRec({trackX + 1, trackY + trackH - fillH, trackW - 2, fillH}, fillCol)
		}

		// Draw Notches & Ticks on right side of track
		for i in 0..<notches {
			t := f32(i) / f32(notches - 1)
			ny := trackY + trackH - t * trackH
			isCur := i == snappedNotch

			tickW: f32 = 9.0 if isCur else 6.0
			tickCol := rl.Color{96, 165, 250, 255} if isCur else rl.Color{80, 88, 105, 255}
			rl.DrawLineEx({trackX + trackW + 2, ny}, {trackX + trackW + 2 + tickW, ny}, 1.5 if isCur else 1.0, tickCol)

			if notchLabels != nil && i < len(notchLabels) {
				nlCStr := fmt.ctprint(notchLabels[i])
				DrawText(nlCStr, trackX + trackW + 14, ny - 5, 9, tickCol)
			}
		}

		// Thumb Handle
		thumbY := trackY + trackH - norm * trackH
		thumbW: f32 = 18.0
		thumbH: f32 = 18.0
		thumbRect := rl.Rectangle{trackX + trackW * 0.5 - thumbW * 0.5, thumbY - thumbH * 0.5, thumbW, thumbH}

		thumbBg := rl.Color{45, 52, 68, 255} if isDragging else (rl.Color{38, 44, 58, 255} if hovered else rl.Color{32, 37, 48, 255})
		rl.DrawRectangleRec(thumbRect, thumbBg)
		borderCol := rl.Color{245, 158, 11, 255} if fineMode else (rl.Color{110, 168, 254, 255} if (hovered || isDragging || focused) else rl.Color{75, 84, 105, 255})
		rl.DrawRectangleLinesEx(thumbRect, 1, borderCol)

		// Notch pointer mark on thumb
		pCol := rl.Color{245, 158, 11, 255} if fineMode else rl.Color{96, 165, 250, 255}
		rl.DrawLineEx({thumbRect.x + 3, thumbY}, {thumbRect.x + thumbW - 3, thumbY}, 2, pCol)

		// Readout at bottom
		valStr: string
		if fineMode {
			valStr = fmt.tprintf("FINE: %.1f", value)
		} else if notchLabels != nil && snappedNotch >= 0 && snappedNotch < len(notchLabels) {
			valStr = notchLabels[snappedNotch]
		} else {
			valStr = fmt.tprintf("%.0f", value)
		}
		valCStr := fmt.ctprint(valStr)
		valMeas := MeasureText(valCStr, 10)
		DrawText(valCStr, rect.x + (rect.width - valMeas.x) * 0.5, rect.y + rect.height - 14, 10, rl.Color{215, 222, 238, 255})

		if focused {
			RenderFocusRing(rect, true, 2.0)
		}
	}
}
