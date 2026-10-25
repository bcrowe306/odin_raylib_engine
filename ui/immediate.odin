package ui

import "core:fmt"
import "core:math"
import "core:strconv"
import rl "vendor:raylib"

// ============================================================================
// Immediate-Mode Custom UI State (Zero Heap Allocations)
// ============================================================================
MAX_IMMEDIATE_SLIDERS :: 256
MAX_IMMEDIATE_COLOR_PICKERS :: 64
MAX_IMMEDIATE_SCROLL_PANELS :: 16
MAX_DROPDOWN_ITEMS :: 32

ImmediateSliderState :: struct {
	key: uintptr,
	used: bool,
	defaultValue: f32,
	isDragging: bool,
	isEditingText: bool,
	dragLastMouseX: f32,
	editBuffer: [64]u8,
	editLen: int,
}

ImmediateColorPickerState :: struct {
	key: uintptr,
	used: bool,
	hsv: [3]f32, // Hue [0..360], Saturation [0..1], Value [0..1]
	draggingSV: bool,
	draggingHue: bool,
	lastRGB: [3]u8,
}

ImmediateScrollState :: struct {
	key: uintptr,
	used: bool,
	draggingV: bool,
	dragOffsetY: f32,
}

ImmediateTextInputState :: struct {
	key: uintptr,
	used: bool,
	blinkTimer: f32,
}
MAX_IMMEDIATE_TEXT_INPUTS :: 64
immediateTextInputs: [MAX_IMMEDIATE_TEXT_INPUTS]ImmediateTextInputState

GetImmediateTextInputState :: proc(key: uintptr) -> ^ImmediateTextInputState {
	firstFree := -1
	for i in 0..<MAX_IMMEDIATE_TEXT_INPUTS {
		if immediateTextInputs[i].used && immediateTextInputs[i].key == key {
			return &immediateTextInputs[i]
		}
		if !immediateTextInputs[i].used && firstFree == -1 {
			firstFree = i
		}
	}
	idx := firstFree if firstFree != -1 else int(key % MAX_IMMEDIATE_TEXT_INPUTS)
	immediateTextInputs[idx] = ImmediateTextInputState{
		key = key,
		used = true,
		blinkTimer = 0.0,
	}
	return &immediateTextInputs[idx]
}

ImmediateDropdownOverlay :: struct {
	active: bool,
	key: uintptr,
	boxRect: rl.Rectangle,
	popupRect: rl.Rectangle,
	valuePtr: ^i32,
	items: [MAX_DROPDOWN_ITEMS]string,
	itemCount: int,
	justOpenedFrame: bool,
}

immediateSliders: [MAX_IMMEDIATE_SLIDERS]ImmediateSliderState
immediateColorPickers: [MAX_IMMEDIATE_COLOR_PICKERS]ImmediateColorPickerState
immediateScrolls: [MAX_IMMEDIATE_SCROLL_PANELS]ImmediateScrollState
immediateAlphaDraggingKey: uintptr
immediateDropdown: ImmediateDropdownOverlay

// Clipping rectangle for widgets inside a ScrollPanel so clicks outside the visible view are ignored
activeClipRect: rl.Rectangle
hasActiveClipRect: bool

BeginClipRect :: proc(view: rl.Rectangle) {
	activeClipRect = view
	hasActiveClipRect = true
	if !rl.IsWindowReady() do return
	rl.BeginScissorMode(i32(view.x), i32(view.y), i32(view.width), i32(view.height))
}

EndClipRect :: proc() {
	if !rl.IsWindowReady() {
		hasActiveClipRect = false
		return
	}
	if immediateDropdown.active {
		RenderImmediateDropdownOverlay()
	}
	hasActiveClipRect = false
	rl.EndScissorMode()
}

IsMouseInClipRect :: proc(mp: [2]f32) -> bool {
	if !hasActiveClipRect do return true
	return PointInRect(mp, activeClipRect)
}

IsBlockedByImmediateDropdown :: proc(key: uintptr, mp: [2]f32) -> bool {
	if !immediateDropdown.active do return false
	if immediateDropdown.key == key do return false
	return PointInRect(mp, immediateDropdown.popupRect)
}

GetImmediateSliderState :: proc(key: uintptr, currentVal: f32) -> ^ImmediateSliderState {
	firstFree := -1
	for i in 0..<MAX_IMMEDIATE_SLIDERS {
		if immediateSliders[i].used && immediateSliders[i].key == key {
			return &immediateSliders[i]
		}
		if !immediateSliders[i].used && firstFree == -1 {
			firstFree = i
		}
	}
	idx := firstFree if firstFree != -1 else int(key % MAX_IMMEDIATE_SLIDERS)
	immediateSliders[idx] = ImmediateSliderState{
		key = key,
		used = true,
		defaultValue = currentVal,
	}
	return &immediateSliders[idx]
}

GetImmediateColorPickerState :: proc(key: uintptr, col: rl.Color) -> ^ImmediateColorPickerState {
	firstFree := -1
	for i in 0..<MAX_IMMEDIATE_COLOR_PICKERS {
		if immediateColorPickers[i].used && immediateColorPickers[i].key == key {
			st := &immediateColorPickers[i]
			// Sync HSV if color was modified externally
			if !st.draggingSV && !st.draggingHue {
				if st.lastRGB[0] != col.r || st.lastRGB[1] != col.g || st.lastRGB[2] != col.b {
					hsv := rl.ColorToHSV(col)
					st.hsv = {hsv.x, hsv.y, hsv.z}
					st.lastRGB = {col.r, col.g, col.b}
				}
			}
			return st
		}
		if !immediateColorPickers[i].used && firstFree == -1 {
			firstFree = i
		}
	}
	idx := firstFree if firstFree != -1 else int(key % MAX_IMMEDIATE_COLOR_PICKERS)
	hsv := rl.ColorToHSV(col)
	immediateColorPickers[idx] = ImmediateColorPickerState{
		key = key,
		used = true,
		hsv = {hsv.x, hsv.y, hsv.z},
		lastRGB = {col.r, col.g, col.b},
	}
	return &immediateColorPickers[idx]
}

GetImmediateScrollState :: proc(key: uintptr) -> ^ImmediateScrollState {
	firstFree := -1
	for i in 0..<MAX_IMMEDIATE_SCROLL_PANELS {
		if immediateScrolls[i].used && immediateScrolls[i].key == key {
			return &immediateScrolls[i]
		}
		if !immediateScrolls[i].used && firstFree == -1 {
			firstFree = i
		}
	}
	idx := firstFree if firstFree != -1 else 0
	immediateScrolls[idx] = ImmediateScrollState{
		key = key,
		used = true,
	}
	return &immediateScrolls[idx]
}

// ============================================================================
// 1. Custom Immediate-Mode Button (Replaces rl.GuiButton)
// ============================================================================
GuiButton :: proc(
	rect: rl.Rectangle,
	text: cstring,
	align: TextAlign = .Center,
	isSelected: bool = false,
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
	if hovered {
		SetUICursor(.POINTING_HAND, .Hover)
		if IsUIMouseButtonPressed(.LEFT) {
			ImmediateNav_SetFocus(key)
		}
	}
	isDown := hovered && IsUIMouseButtonDown(.LEFT)
	keyTrigger := isFocused && (IsUIKeyPressed(.ENTER) || IsUIKeyPressed(.KP_ENTER) || IsUIKeyPressed(.SPACE))
	clicked := (hovered && IsUIMouseButtonPressed(.LEFT)) || keyTrigger

	normalBg := rl.Color{37, 99, 235, 95} if isSelected else rl.Color{34, 37, 45, 255}
	hoverBg := rl.Color{48, 112, 245, 130} if isSelected else rl.Color{48, 53, 66, 255}
	pressedBg := rl.Color{37, 99, 235, 255}
	borderCol := rl.Color{110, 168, 254, 255} if (isSelected || isFocused) else rl.Color{68, 73, 86, 255}
	textCol := rl.Color{240, 242, 248, 255}

	fontSize: f32 = DEFAULT_FONT_SIZE if rect.height >= 26 else DEFAULT_FONT_SIZE_SM
	RenderButton(
		rect,
		string(text),
		fontSize,
		hovered,
		isDown,
		normalBg,
		hoverBg,
		pressedBg,
		borderCol,
		textCol,
		align,
		focused = isFocused,
	)

	return clicked
}

// ============================================================================
// 2. Custom Immediate-Mode Slider (Replaces rl.GuiSlider)
//    Features: Editable Value Box, Shift Fine Adjustment (0.1x), & [R] Reset!
// ============================================================================
GuiSlider :: proc(
	rect: rl.Rectangle,
	labelLeft: cstring,
	labelRight: cstring,
	value: ^f32,
	minValue: f32,
	maxValue: f32,
	isInteger: bool = false,
	idKey: uintptr = 0,
	labelWidth: f32 = 0,
) -> bool {
	if !rl.IsWindowReady() || value == nil do return false

	key := idKey if idKey != 0 else uintptr(value)
	ImmediateNav_RegisterFocusable(key, rect)
	isFocused := ImmediateNav_IsFocused(key)

	st := GetImmediateSliderState(key, value^)
	oldVal := value^

	mp := GetUIMousePosition()
	mousePt := [2]f32{mp.x, mp.y}
	inClip := IsMouseInClipRect(mousePt)
	blocked := IsBlockedByImmediateDropdown(key, mousePt)

	hasLabel := (labelLeft != nil && len(labelLeft) > 0)
	lw: f32 = 0
	if hasLabel {
		if labelWidth > 0 {
			lw = labelWidth
		} else if labelWidth == 0 {
			lw = MeasureText(labelLeft, DEFAULT_FONT_SIZE).x + 12
		}
	}

	valBoxW: f32 = 54 if rect.width >= 130 else 44
	showReset := rect.width >= 110
	trackRect, valBoxRect, resetRect := GetSliderSubRects(rect, lw > 0, lw, showReset, valBoxW)

	if hasLabel {
		if labelWidth < 0 {
			measured := MeasureText(labelLeft, DEFAULT_FONT_SIZE)
			labelX := rect.x - measured.x - 8
			DrawText(labelLeft, labelX, rect.y + (rect.height - DEFAULT_FONT_SIZE) * 0.5, DEFAULT_FONT_SIZE, rl.Color{205, 210, 222, 255})
		} else {
			DrawText(labelLeft, rect.x + 2, rect.y + (rect.height - DEFAULT_FONT_SIZE) * 0.5, DEFAULT_FONT_SIZE, rl.Color{205, 210, 222, 255})
		}
	}

	hovered := inClip && !blocked && PointInRect(mousePt, rect)
	if hovered && IsUIMouseButtonPressed(.LEFT) {
		ImmediateNav_SetFocus(key)
	}

	if st.isDragging {
		SetUICursor(.RESIZE_EW, .Dragging)
	} else if inClip && !blocked {
		if PointInRect(mousePt, valBoxRect) {
			SetUICursor(.IBEAM, .Hover)
		} else if PointInRect(mousePt, trackRect) || (showReset && PointInRect(mousePt, resetRect)) {
			SetUICursor(.POINTING_HAND, .Hover)
		}
	}

		shiftHeld := IsUIKeyDown(.LEFT_SHIFT) || IsUIKeyDown(.RIGHT_SHIFT)
	ctrlHeld := rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL)
	fineMode := shiftHeld && (st.isDragging || hovered)

	// Keyboard arrow navigation when slider is focused
	if isFocused && !st.isEditingText {
		step := (maxValue - minValue) * (0.01 if fineMode else 0.05)
		if isInteger do step = max(math.round(step), 1.0)
		if IsUIKeyPressed(.LEFT) || IsUIKeyPressed(.DOWN) {
			v := clamp(value^ - step, minValue, maxValue)
			if isInteger do v = math.round(v)
			value^ = v
		} else if IsUIKeyPressed(.RIGHT) || IsUIKeyPressed(.UP) {
			v := clamp(value^ + step, minValue, maxValue)
			if isInteger do v = math.round(v)
			value^ = v
		}
		if IsUIKeyPressed(.ENTER) || IsUIKeyPressed(.KP_ENTER) {
			st.isEditingText = true
			st.isDragging = false
			st.editLen = 0
			valStr := fmt.tprintf("%d", int(value^)) if isInteger else fmt.tprintf("%.2f", value^)
			copy(st.editBuffer[:], valStr)
			st.editLen = len(valStr)
		}
	}

	// 1. Reset Button [R] or Right-Click on Track
	if !blocked && inClip {
		if (showReset && PointInRect(mousePt, resetRect) && IsUIMouseButtonPressed(.LEFT)) ||
		   (PointInRect(mousePt, trackRect) && IsUIMouseButtonPressed(.RIGHT)) {
			st.isEditingText = false
			st.isDragging = false
			v := clamp(st.defaultValue, minValue, maxValue)
			if isInteger do v = math.round(v)
			value^ = v
		}
	}

	// 2. Editable Text Box Mode
	if st.isEditingText {
		if IsUIKeyPressed(.ESCAPE) {
			st.isEditingText = false
		} else if IsUIKeyPressed(.ENTER) || IsUIKeyPressed(.KP_ENTER) || (IsUIMouseButtonPressed(.LEFT) && !PointInRect(mousePt, valBoxRect)) {
			st.isEditingText = false
			str := string(st.editBuffer[:st.editLen])
			if parsed, ok := strconv.parse_f32(str); ok {
				v := clamp(parsed, minValue, maxValue)
				if isInteger do v = math.round(v)
				value^ = v
			}
		} else {
			if rl.IsKeyPressed(.BACKSPACE) && st.editLen > 0 {
				st.editLen -= 1
			}
			for {
				ch := rl.GetCharPressed()
				if ch == 0 do break
				if (ch >= '0' && ch <= '9') || ch == '.' || ch == '-' {
					if st.editLen < len(st.editBuffer) - 1 {
						st.editBuffer[st.editLen] = u8(ch)
						st.editLen += 1
					}
				}
			}
		}
	} else if inClip && !blocked && IsUIMouseButtonPressed(.LEFT) {
		if PointInRect(mousePt, valBoxRect) || (ctrlHeld && PointInRect(mousePt, trackRect)) {
			st.isEditingText = true
			st.isDragging = false
			formatted := fmt.tprintf("%d", int(math.round(value^))) if isInteger else fmt.tprintf("%.2f", value^)
			n := min(len(formatted), len(st.editBuffer) - 1)
			for i in 0..<n {
				st.editBuffer[i] = formatted[i]
			}
			st.editLen = n
		} else if PointInRect(mousePt, trackRect) {
			st.isDragging = true
			st.dragLastMouseX = mousePt.x
			usableWidth := max(trackRect.width - 4.0, 1.0)
			if !shiftHeld && usableWidth > 1 {
				t := clamp((mousePt.x - (trackRect.x + 2.0)) / usableWidth, 0.0, 1.0)
				v := minValue + t * (maxValue - minValue)
				if isInteger do v = math.round(v)
				value^ = clamp(v, minValue, maxValue)
			}
		}
	}

	// 3. Handle Dragging (with Shift fine adjustment!)
	if st.isDragging {
		if !IsUIMouseButtonDown(.LEFT) || IsUIMouseButtonReleased(.LEFT) {
			st.isDragging = false
		} else {
			usableWidth := max(trackRect.width - 4.0, 1.0)
			if usableWidth > 1 {
				dx := mousePt.x - st.dragLastMouseX
				st.dragLastMouseX = mousePt.x
				if abs(dx) > 0.0001 {
					range := maxValue - minValue
					v := value^
					if shiftHeld {
						v += (dx / usableWidth) * range * 0.1
					} else {
						t := clamp((mousePt.x - (trackRect.x + 2.0)) / usableWidth, 0.0, 1.0)
						v = minValue + t * range
					}
					if isInteger do v = math.round(v)
					value^ = clamp(v, minValue, maxValue)
				}
			}
		}
	}

	RenderSlider(
		rect,
		"",
		value^,
		minValue,
		maxValue,
		st.defaultValue,
		isInteger,
		showReset,
		0,
		hovered,
		st.isDragging,
		fineMode,
		st.isEditingText,
		string(st.editBuffer[:st.editLen]),
		focused = isFocused,
		customTrackRect = trackRect,
		customValBoxRect = valBoxRect,
		customResetRect = resetRect,
	)

	return abs(value^ - oldVal) > 0.00001
}

// ============================================================================
// 3. Custom Immediate-Mode Checkbox (Replaces rl.GuiCheckBox)
// ============================================================================
GuiCheckBox :: proc(rect: rl.Rectangle, text: cstring, checked: ^bool, idKey: uintptr = 0) -> bool {
	if !rl.IsWindowReady() || checked == nil do return false

	key := idKey if idKey != 0 else uintptr(checked)
	ImmediateNav_RegisterFocusable(key, rect)
	isFocused := ImmediateNav_IsFocused(key)

	mp := GetUIMousePosition()
	mousePt := [2]f32{mp.x, mp.y}
	inClip := IsMouseInClipRect(mousePt)
	blocked := IsBlockedByImmediateDropdown(key, mousePt)

	labelStr := string(text) if text != nil else ""
	labelW := MeasureText(text, DEFAULT_FONT_SIZE).x + 12 if (text != nil && len(text) > 0) else 0
	hitRect := rl.Rectangle{rect.x, rect.y, rect.width + labelW, max(rect.height, 18)}

	hovered := inClip && !blocked && PointInRect(mousePt, hitRect)
	if hovered do SetUICursor(.POINTING_HAND, .Hover)
	toggled := false
	if hovered && IsUIMouseButtonPressed(.LEFT) {
		ImmediateNav_SetFocus(key)
		checked^ = !checked^
		toggled = true
	} else if isFocused && (IsUIKeyPressed(.ENTER) || IsUIKeyPressed(.KP_ENTER) || IsUIKeyPressed(.SPACE)) {
		checked^ = !checked^
		toggled = true
	}

	t := GetTheme()
	RenderCheckbox(rect, labelStr, checked^, hovered, t.accent, 14, focused = isFocused)
	return toggled
}

// ============================================================================
// 4. Custom Immediate-Mode DropdownBox (Replaces rl.GuiDropdownBox)
// ============================================================================
SplitDropdownItems :: proc(itemsJoined: string, outItems: ^[MAX_DROPDOWN_ITEMS]string) -> int {
	if len(itemsJoined) == 0 do return 0
	count := 0
	start := 0
	for i := 0; i <= len(itemsJoined); i += 1 {
		if i == len(itemsJoined) || itemsJoined[i] == ';' {
			if count < MAX_DROPDOWN_ITEMS {
				outItems^[count] = itemsJoined[start:i]
				count += 1
			}
			start = i + 1
		}
	}
	return count
}

GuiDropdownBox :: proc(
	rect: rl.Rectangle,
	itemsJoined: cstring,
	active: ^i32,
	editMode: bool = false,
	idKey: uintptr = 0,
) -> bool {
	if !rl.IsWindowReady() || active == nil do return false

	key := idKey if idKey != 0 else uintptr(active)
	ImmediateNav_RegisterFocusable(key, rect)
	isFocused := ImmediateNav_IsFocused(key)

	mp := GetUIMousePosition()
	mousePt := [2]f32{mp.x, mp.y}
	inClip := IsMouseInClipRect(mousePt)
	blocked := IsBlockedByImmediateDropdown(key, mousePt)

	items: [MAX_DROPDOWN_ITEMS]string
	count := SplitDropdownItems(string(itemsJoined), &items)

	selIdx := clamp(int(active^), 0, max(count - 1, 0))
	selText := items[selIdx] if count > 0 else ""

	isOpen := immediateDropdown.active && immediateDropdown.key == key
	hovered := inClip && !blocked && PointInRect(mousePt, rect)
	if hovered || isOpen do SetUICursor(.POINTING_HAND, .Hover)
	clickedBox := false

	if isFocused {
		if IsUIKeyPressed(.UP) {
			active^ = max(active^ - 1, 0)
			clickedBox = true
		} else if IsUIKeyPressed(.DOWN) {
			active^ = min(active^ + 1, i32(count - 1))
			clickedBox = true
		}
		if IsUIKeyPressed(.ENTER) || IsUIKeyPressed(.KP_ENTER) || IsUIKeyPressed(.SPACE) {
			isOpen = !isOpen
			immediateDropdown.active = isOpen
		}
	}

	if hovered && IsUIMouseButtonPressed(.LEFT) {
		ImmediateNav_SetFocus(key)
		clickedBox = true
		if isOpen {
			immediateDropdown.active = false
		} else {
			itemH: f32 = 22
			immediateDropdown = ImmediateDropdownOverlay{
				active = true,
				key = key,
				boxRect = rect,
				popupRect = rl.Rectangle{rect.x, rect.y + rect.height + 2, rect.width, f32(count) * itemH + 4},
				valuePtr = active,
				items = items,
				itemCount = count,
				justOpenedFrame = true,
			}
			isOpen = true
		}
	} else if isOpen {
		// Keep box/popup position synced as scroll panel moves
		itemH: f32 = 22
		immediateDropdown.boxRect = rect
		immediateDropdown.popupRect = rl.Rectangle{rect.x, rect.y + rect.height + 2, rect.width, f32(count) * itemH + 4}
		immediateDropdown.items = items
		immediateDropdown.itemCount = count
	}

	RenderDropdownBox(rect, "", rect, selText, hovered, isOpen, focused = isFocused)
	return clickedBox
}

RenderImmediateDropdownOverlay :: proc() {
	if !immediateDropdown.active || immediateDropdown.valuePtr == nil do return

	mp := GetUIMousePosition()
	mousePt := [2]f32{mp.x, mp.y}
	popupRect := immediateDropdown.popupRect
	boxRect := immediateDropdown.boxRect
	itemH: f32 = 22
	hoveredIdx := -1

	// Arrow keys navigation in open dropdown
	if IsUIKeyPressed(.UP) {
		immediateDropdown.valuePtr^ = max(immediateDropdown.valuePtr^ - 1, 0)
	} else if IsUIKeyPressed(.DOWN) {
		immediateDropdown.valuePtr^ = min(immediateDropdown.valuePtr^ + 1, i32(immediateDropdown.itemCount - 1))
	}
	if IsUIKeyPressed(.ENTER) || IsUIKeyPressed(.KP_ENTER) || IsUIKeyPressed(.SPACE) || IsUIKeyPressed(.ESCAPE) {
		immediateDropdown.active = false
		return
	}

	if PointInRect(mousePt, popupRect) {
		idx := int((mousePt.y - (popupRect.y + 2)) / itemH)
		if idx >= 0 && idx < immediateDropdown.itemCount {
			hoveredIdx = idx
			if IsUIMouseButtonPressed(.LEFT) && !immediateDropdown.justOpenedFrame {
				immediateDropdown.valuePtr^ = i32(idx)
				immediateDropdown.active = false
				return
			}
		}
	} else if IsUIMouseButtonPressed(.LEFT) && !immediateDropdown.justOpenedFrame && !PointInRect(mousePt, boxRect) {
		immediateDropdown.active = false
		return
	}

	immediateDropdown.justOpenedFrame = false
	RenderDropdownPopup(
		popupRect,
		immediateDropdown.items[:immediateDropdown.itemCount],
		int(immediateDropdown.valuePtr^),
		hoveredIdx,
		itemH,
	)
}

// ============================================================================
// 5. Custom Immediate-Mode ScrollPanel (Replaces rl.GuiScrollPanel)
// ============================================================================
GuiScrollPanel :: proc(
	bounds: rl.Rectangle,
	text: cstring,
	content: rl.Rectangle,
	scroll: ^rl.Vector2,
	view: ^rl.Rectangle,
) -> (changed: bool) {
	if scroll == nil || view == nil do return false

	scrollbarW: f32 = 12
	hasVScroll := content.height > bounds.height

	view.x = bounds.x
	view.y = bounds.y
	view.width = bounds.width - (scrollbarW if hasVScroll else 0)
	view.height = bounds.height

	if !rl.IsWindowReady() {
		return
	}

	st := GetImmediateScrollState(uintptr(scroll))
	mp := GetUIMousePosition()
	mousePt := [2]f32{mp.x, mp.y}
	maxScrollY := max(content.height - bounds.height, 0)

	// 1. Mouse wheel scrolling when cursor is inside the scroll panel bounds
	if PointInRect(mousePt, bounds) {
		wheel := rl.GetMouseWheelMove()
		if abs(wheel) > 0.001 {
			scroll.y += wheel * 28.0
		}
	}

	// 2. Vertical Scrollbar interaction & rendering
	rl.DrawRectangleRec(bounds, rl.Color{24, 25, 28, 255})

	if hasVScroll && maxScrollY > 0 {
		trackRect := rl.Rectangle{bounds.x + bounds.width - scrollbarW, bounds.y + 2, scrollbarW - 2, bounds.height - 4}
		visibleRatio := clamp(bounds.height / content.height, 0.08, 1.0)
		thumbH := max(trackRect.height * visibleRatio, 24.0)
		usableTrackH := max(trackRect.height - thumbH, 1.0)

		scrollNorm := clamp(-scroll.y / maxScrollY, 0.0, 1.0)
		thumbY := trackRect.y + scrollNorm * usableTrackH
		thumbRect := rl.Rectangle{trackRect.x + 1, thumbY, trackRect.width - 2, thumbH}

		hoveredThumb := PointInRect(mousePt, thumbRect)
		hoveredTrack := PointInRect(mousePt, trackRect)

		if IsUIMouseButtonPressed(.LEFT) {
			if hoveredThumb {
				st.draggingV = true
				st.dragOffsetY = mousePt.y - thumbY
			} else if hoveredTrack {
				targetNorm := clamp((mousePt.y - trackRect.y - thumbH * 0.5) / usableTrackH, 0.0, 1.0)
				scroll.y = -targetNorm * maxScrollY
				st.draggingV = true
				st.dragOffsetY = thumbH * 0.5
			}
		}

		if st.draggingV {
			if !IsUIMouseButtonDown(.LEFT) {
				st.draggingV = false
			} else {
				newNorm := clamp((mousePt.y - trackRect.y - st.dragOffsetY) / usableTrackH, 0.0, 1.0)
				scroll.y = -newNorm * maxScrollY
			}
		}

		scroll.y = clamp(scroll.y, -maxScrollY, 0.0)
		scrollNorm = clamp(-scroll.y / maxScrollY, 0.0, 1.0)
		thumbRect.y = trackRect.y + scrollNorm * usableTrackH

		rl.DrawRectangleRec(trackRect, rl.Color{18, 19, 22, 255})
		thumbCol := rl.Color{110, 168, 254, 230} if st.draggingV else (rl.Color{105, 112, 128, 220} if hoveredThumb else rl.Color{68, 72, 84, 200})
		rl.DrawRectangleRec(thumbRect, thumbCol)
	} else {
		scroll.y = 0
		st.draggingV = false
	}

	scroll.x = 0
	return false
}

// ============================================================================
// 6. Custom Immediate-Mode Color Picker & Alpha Bar
//    (Replaces rl.GuiColorPicker and rl.GuiColorBarAlpha)
// ============================================================================
GuiColorPicker :: proc(rect: rl.Rectangle, label: cstring, color: ^rl.Color) -> bool {
	if !rl.IsWindowReady() || color == nil do return false

	key := uintptr(color)
	st := GetImmediateColorPickerState(key, color^)
	oldCol := color^

	mp := GetUIMousePosition()
	mousePt := [2]f32{mp.x, mp.y}
	inClip := IsMouseInClipRect(mousePt)
	blocked := IsBlockedByImmediateDropdown(key, mousePt)

	hueBarW: f32 = 18
	gap: f32 = 8
	svWidth := max(rect.width - hueBarW - gap, 40)
	svHeight := rect.height
	svRect := rl.Rectangle{rect.x, rect.y, svWidth, svHeight}
	hueRect := rl.Rectangle{rect.x + svWidth + gap, rect.y, hueBarW, svHeight}

	// 1. Hue Bar interaction
	if inClip && !blocked && !st.draggingSV {
		if PointInRect(mousePt, hueRect) && IsUIMouseButtonPressed(.LEFT) {
			st.draggingHue = true
		}
	}
	if st.draggingHue {
		if !IsUIMouseButtonDown(.LEFT) {
			st.draggingHue = false
		} else {
			normY := clamp((mousePt.y - hueRect.y) / max(hueRect.height, 1.0), 0.0, 1.0)
			st.hsv[0] = normY * 360.0
		}
	}

	// 2. Saturation/Value Box interaction
	if inClip && !blocked && !st.draggingHue {
		if PointInRect(mousePt, svRect) && IsUIMouseButtonPressed(.LEFT) {
			st.draggingSV = true
		}
	}
	if st.draggingSV {
		if !IsUIMouseButtonDown(.LEFT) {
			st.draggingSV = false
		} else {
			st.hsv[1] = clamp((mousePt.x - svRect.x) / max(svRect.width, 1.0), 0.0, 1.0)
			st.hsv[2] = clamp(1.0 - (mousePt.y - svRect.y) / max(svRect.height, 1.0), 0.0, 1.0)
		}
	}

	pureCol := rl.ColorFromHSV(st.hsv[0], 1.0, 1.0)
	newRGB := rl.ColorFromHSV(st.hsv[0], st.hsv[1], st.hsv[2])
	newRGB.a = color.a
	color^ = newRGB
	st.lastRGB = {newRGB.r, newRGB.g, newRGB.b}

	// Render Hue Strip
	hueSteps := 32
	stepH := hueRect.height / f32(hueSteps)
	for i in 0..<hueSteps {
		h0 := f32(i) / f32(hueSteps) * 360.0
		h1 := f32(i + 1) / f32(hueSteps) * 360.0
		c0 := rl.ColorFromHSV(h0, 1.0, 1.0)
		c1 := rl.ColorFromHSV(h1, 1.0, 1.0)
		rl.DrawRectangleGradientV(
			i32(hueRect.x),
			i32(hueRect.y + f32(i) * stepH),
			i32(hueRect.width),
			i32(stepH + 1),
			c0,
			c1,
		)
	}
	rl.DrawRectangleLinesEx(hueRect, 1, rl.Color{65, 70, 84, 255})

	// Hue Indicator
	indicatorY := hueRect.y + (st.hsv[0] / 360.0) * hueRect.height
	rl.DrawRectangleRec({hueRect.x - 2, indicatorY - 2, hueRect.width + 4, 4}, rl.WHITE)
	rl.DrawRectangleLinesEx({hueRect.x - 2, indicatorY - 2, hueRect.width + 4, 4}, 1, rl.BLACK)

	// Render S/V Canvas
	rl.DrawRectangleGradientH(i32(svRect.x), i32(svRect.y), i32(svRect.width), i32(svRect.height), rl.WHITE, pureCol)
	rl.DrawRectangleGradientV(i32(svRect.x), i32(svRect.y), i32(svRect.width), i32(svRect.height), rl.BLANK, rl.BLACK)
	rl.DrawRectangleLinesEx(svRect, 1, rl.Color{65, 70, 84, 255})

	// S/V Cursor
	cursorX := svRect.x + st.hsv[1] * svRect.width
	cursorY := svRect.y + (1.0 - st.hsv[2]) * svRect.height
	rl.DrawCircleLines(i32(cursorX), i32(cursorY), 5, rl.BLACK)
	rl.DrawCircleLines(i32(cursorX), i32(cursorY), 4, rl.WHITE)

	return color.r != oldCol.r || color.g != oldCol.g || color.b != oldCol.b
}

GuiColorBarAlpha :: proc(rect: rl.Rectangle, label: cstring, alpha: ^f32, idKey: uintptr = 0) -> bool {
	if !rl.IsWindowReady() || alpha == nil do return false

	key := idKey if idKey != 0 else uintptr(alpha)
	oldA := alpha^

	mp := GetUIMousePosition()
	mousePt := [2]f32{mp.x, mp.y}
	inClip := IsMouseInClipRect(mousePt)
	blocked := IsBlockedByImmediateDropdown(key, mousePt)

	// Checkerboard background
	checkSize: f32 = 6
	for y := rect.y; y < rect.y + rect.height; y += checkSize {
		for x := rect.x; x < rect.x + rect.width; x += checkSize {
			isWhite := (i32((x - rect.x) / checkSize) + i32((y - rect.y) / checkSize)) % 2 == 0
			checkCol := rl.Color{180, 180, 180, 255} if isWhite else rl.Color{130, 130, 130, 255}
			rl.DrawRectangleRec({x, y, min(checkSize, rect.x + rect.width - x), min(checkSize, rect.y + rect.height - y)}, checkCol)
		}
	}

	// Gradient white -> transparent
	rl.DrawRectangleGradientH(i32(rect.x), i32(rect.y), i32(rect.width), i32(rect.height), rl.BLANK, rl.WHITE)
	rl.DrawRectangleLinesEx(rect, 1, rl.Color{68, 73, 86, 255})

	// Handle Dragging
	if inClip && !blocked {
		if PointInRect(mousePt, rect) && IsUIMouseButtonPressed(.LEFT) {
			immediateAlphaDraggingKey = key
		}
	}
	if immediateAlphaDraggingKey == key {
		if !IsUIMouseButtonDown(.LEFT) {
			immediateAlphaDraggingKey = 0
		} else {
			normX := clamp((mousePt.x - rect.x) / max(rect.width, 1.0), 0.0, 1.0)
			alpha^ = normX
		}
	}

	// Indicator
	indX := rect.x + clamp(alpha^, 0.0, 1.0) * rect.width
	rl.DrawRectangleRec({indX - 2, rect.y - 1, 4, rect.height + 2}, rl.Color{110, 168, 254, 255})
	rl.DrawRectangleLinesEx({indX - 2, rect.y - 1, 4, rect.height + 2}, 1, rl.WHITE)

	return abs(alpha^ - oldA) > 0.0001
}

// ============================================================================
// 7. Custom Immediate-Mode Toggle Switch
// ============================================================================
GuiToggleSwitch :: proc(bounds: rl.Rectangle, text: cstring, active: ^bool, idKey: uintptr = 0) -> bool {
	if !rl.IsWindowReady() do return false

	key := idKey if idKey != 0 else (uintptr(active) if active != nil else uintptr(uint(u32(bounds.x * 1000)) ~ uint(u32(bounds.y * 1000))))
	ImmediateNav_RegisterFocusable(key, bounds)
	isFocused := ImmediateNav_IsFocused(key)

	mousePos := GetUIMousePosition()
	trackW: f32 = 28.0
	labelW := MeasureText(text, DEFAULT_FONT_SIZE).x + 12 if (text != nil && len(text) > 0) else 0
	clickableRect := rl.Rectangle{
		bounds.x,
		bounds.y,
		max(bounds.width, trackW + labelW + 8),
		bounds.height,
	}
	hovered := PointInRect(mousePos, clickableRect)
	if hovered do SetUICursor(.POINTING_HAND, .Hover)

	clicked := false
	if hovered && IsUIMouseButtonPressed(.LEFT) {
		ImmediateNav_SetFocus(key)
		if active != nil do active^ = !active^
		clicked = true
	} else if isFocused && (IsUIKeyPressed(.ENTER) || IsUIKeyPressed(.KP_ENTER) || IsUIKeyPressed(.SPACE)) {
		if active != nil do active^ = !active^
		clicked = true
	}

	labelStr := string(text) if text != nil else ""
	curActive := active^ if active != nil else false
	RenderToggleSwitch(bounds, labelStr, curActive, hovered, focused = isFocused)
	return clicked
}

// ============================================================================
// 8. Custom Immediate-Mode Rotary Knob
// ============================================================================
KnobDragState :: struct {
	activeKey:  uintptr,
	startMouse: rl.Vector2,
	startVal:   f32,
}
activeKnobDrag: KnobDragState

GuiKnob :: proc(
	bounds: rl.Rectangle,
	label: cstring,
	value: ^f32,
	minValue, maxValue: f32,
	defaultValue: f32 = 0,
	format: cstring = "%.2f",
	idKey: uintptr = 0,
) -> bool {
	if !rl.IsWindowReady() do return false

	key := idKey if idKey != 0 else uintptr(value)
	ImmediateNav_RegisterFocusable(key, bounds)
	isFocused := ImmediateNav_IsFocused(key)

	mousePos := GetUIMousePosition()
	hovered := PointInRect(mousePos, bounds)
	changed := false

	if hovered && IsUIMouseButtonPressed(.LEFT) {
		ImmediateNav_SetFocus(key)
	}

	if activeKnobDrag.activeKey == key && IsUIMouseButtonReleased(.LEFT) {
		activeKnobDrag.activeKey = 0
	}

	isDragging := activeKnobDrag.activeKey == key
	shiftDown := IsUIKeyDown(.LEFT_SHIFT) || IsUIKeyDown(.RIGHT_SHIFT)
	// Fine adjustment mode applies strictly to the focused knob (or the knob currently being dragged)
	fineAdjust := shiftDown && (isFocused || isDragging)

	if isFocused && !isDragging {
		step := (maxValue - minValue) * (0.01 if fineAdjust else 0.05)
		if IsUIKeyPressed(.LEFT) || IsUIKeyPressed(.DOWN) {
			newVal := clamp(value^ - step, minValue, maxValue)
			if newVal != value^ {
				value^ = newVal
				changed = true
			}
		} else if IsUIKeyPressed(.RIGHT) || IsUIKeyPressed(.UP) {
			newVal := clamp(value^ + step, minValue, maxValue)
			if newVal != value^ {
				value^ = newVal
				changed = true
			}
		}
	}

	if hovered {
		wheel := rl.GetMouseWheelMove()
		if wheel != 0 {
			wheelFine := shiftDown && (isFocused || hovered)
			step := (maxValue - minValue) * (0.005 if wheelFine else 0.02) * wheel
			newVal := clamp(value^ + step, minValue, maxValue)
			if newVal != value^ {
				value^ = newVal
				changed = true
			}
		}
	}

	if hovered && (IsUIMouseButtonPressed(.RIGHT) || (IsUIMouseButtonPressed(.LEFT) && rl.GetGestureDetected() == {.DOUBLETAP})) {
		if value^ != defaultValue {
			value^ = defaultValue
			changed = true
		}
	} else if hovered && IsUIMouseButtonPressed(.LEFT) {
		activeKnobDrag.activeKey = key
		activeKnobDrag.startMouse = mousePos
		activeKnobDrag.startVal = value^
	}

	if isDragging && IsUIMouseButtonDown(.LEFT) {
		dy := activeKnobDrag.startMouse.y - mousePos.y
		speed: f32 = 0.005 if fineAdjust else 0.02
		valRange := maxValue - minValue
		newVal := clamp(activeKnobDrag.startVal + dy * speed * valRange, minValue, maxValue)
		if newVal != value^ {
			value^ = newVal
			changed = true
		}
	}

	labelStr := string(label) if label != nil else ""
	formatStr := string(format) if format != nil else "%.2f"
	if fineAdjust && formatStr == "%.0f%%" {
		formatStr = "%.1f%%"
	}
	RenderKnob(bounds, labelStr, value^, minValue, maxValue, formatStr, hovered, isDragging, focused = isFocused, fineMode = fineAdjust)
	return changed
}

// ============================================================================
// 9. Custom Immediate-Mode Progress Bar
// ============================================================================
GuiProgressBar :: proc(
	bounds: rl.Rectangle,
	label: cstring,
	value: f32,
	minValue, maxValue: f32,
	direction: ProgressBarDirection = .Horizontal,
	showText: bool = true,
) -> bool {
	labelStr := string(label) if label != nil else ""
	RenderProgressBar(bounds, labelStr, value, minValue, maxValue, {16, 185, 129, 255}, direction, showText)
	return false
}

// ============================================================================
// 10. Custom Immediate-Mode List View
// ============================================================================
GuiListView :: proc(
	bounds: rl.Rectangle,
	items: []string,
	selectedIndex: ^int,
	scroll: ^rl.Vector2,
	itemHeight: f32 = 24,
	idKey: uintptr = 0,
) -> (changed: bool, clickedIndex: int) {
	changed = false
	clickedIndex = -1
	if !rl.IsWindowReady() do return

	key := idKey if idKey != 0 else (uintptr(selectedIndex) if selectedIndex != nil else uintptr(uint(u32(bounds.x * 1000)) ~ uint(u32(bounds.y * 1000))))
	ImmediateNav_RegisterFocusable(key, bounds)
	isFocused := ImmediateNav_IsFocused(key)

	itemCount := len(items)
	contentHeight := f32(itemCount) * itemHeight
	contentRect := rl.Rectangle{0, 0, bounds.width - 16, contentHeight}
	viewRect := rl.Rectangle{}

	GuiScrollPanel(bounds, nil, contentRect, scroll, &viewRect)
	BeginClipRect(viewRect)
	defer EndClipRect()

	mousePos := GetUIMousePosition()
	inView := PointInRect(mousePos, viewRect)

	if isFocused && itemCount > 0 && selectedIndex != nil {
		if IsUIKeyPressed(.UP) {
			newIdx := max(selectedIndex^ - 1, 0)
			if newIdx != selectedIndex^ {
				selectedIndex^ = newIdx
				changed = true
			}
		} else if IsUIKeyPressed(.DOWN) {
			newIdx := min(selectedIndex^ + 1, itemCount - 1)
			if newIdx != selectedIndex^ {
				selectedIndex^ = newIdx
				changed = true
			}
		}
	}

	hoveredIdx := -1
	for i := 0; i < itemCount; i += 1 {
		itemY := viewRect.y + scroll.y + f32(i) * itemHeight
		itemRect := rl.Rectangle{viewRect.x, itemY, viewRect.width, itemHeight}

		if inView && PointInRect(mousePos, itemRect) {
			hoveredIdx = i
			if IsUIMouseButtonPressed(.LEFT) {
				ImmediateNav_SetFocus(key)
				clickedIndex = i
				if selectedIndex != nil && selectedIndex^ != i {
					selectedIndex^ = i
					changed = true
				}
			}
		}

		isSelected := (selectedIndex != nil && i == selectedIndex^)
		isHovered := (i == hoveredIdx)
		if isSelected {
			rl.DrawRectangleRec(itemRect, rl.Color{45, 90, 180, 255})
		} else if isHovered {
			rl.DrawRectangleRec(itemRect, rl.Color{40, 45, 58, 255})
		}

		txtCol := rl.WHITE if isSelected else rl.Color{215, 220, 230, 255}
		cstr := fmt.ctprint(items[i])
		DrawText(cstr, itemRect.x + 8, itemRect.y + (itemHeight - 15) * 0.5, 15, txtCol)
	}

	if isFocused {
		RenderFocusRing(bounds, true, 2.0)
	}

	return changed, clickedIndex
}

// ============================================================================
// 11. Custom Immediate-Mode Tree View & Node
// ============================================================================
GuiTreeNode :: proc(
	bounds: rl.Rectangle,
	label: string,
	icon: string = "",
	depth: int = 0,
	hasChildren: bool = false,
	isCollapsed: ^bool = nil,
	isSelected: bool = false,
	isLastChild: bool = false,
) -> (clicked: bool, toggled: bool) {
	if !rl.IsWindowReady() do return false, false

	mousePos := GetUIMousePosition()
	indent: f32 = f32(depth) * 16.0
	rowX := bounds.x + indent
	rowW := max(bounds.width - indent, 40.0)
	rowRect := rl.Rectangle{rowX, bounds.y, rowW, bounds.height}

	hovered := PointInRect(mousePos, rowRect)

	if hasChildren {
		boxRect := rl.Rectangle{rowX + 2, bounds.y + (bounds.height - 14) * 0.5, 14, 14}
		if PointInRect(mousePos, boxRect) && IsUIMouseButtonPressed(.LEFT) {
			if isCollapsed != nil {
				isCollapsed^ = !isCollapsed^
			}
			toggled = true
			return false, toggled
		}
	}

	if hovered && IsUIMouseButtonPressed(.LEFT) {
		clicked = true
	}

	collapsedVal := isCollapsed^ if isCollapsed != nil else false
	item := TreeViewItem{
		id = 0,
		label = label,
		icon = icon,
		depth = depth,
		hasChildren = hasChildren,
		isCollapsed = collapsedVal,
		isSelected = isSelected,
		isLastChild = isLastChild,
	}
	RenderTreeNode(bounds, item, hovered)

	return clicked, toggled
}

GuiTreeView :: proc(
	bounds: rl.Rectangle,
	items: []TreeViewItem,
	selectedId: ^int,
	scroll: ^rl.Vector2,
	itemHeight: f32 = 22,
) -> (clickedIndex: int, toggledIndex: int) {
	clickedIndex = -1
	toggledIndex = -1
	if !rl.IsWindowReady() do return

	totalItems := len(items)

	// First pass: compute visible items count respecting collapsed ancestors
	visibleCount := 0
	skipUntilDepth := -1
	for i in 0..<totalItems {
		if skipUntilDepth != -1 {
			if items[i].depth > skipUntilDepth {
				continue
			} else {
				skipUntilDepth = -1
			}
		}
		visibleCount += 1
		if items[i].hasChildren && items[i].isCollapsed {
			skipUntilDepth = items[i].depth
		}
	}

	contentHeight := f32(visibleCount) * itemHeight
	contentRect := rl.Rectangle{0, 0, bounds.width - 16, contentHeight}
	viewRect := rl.Rectangle{}

	GuiScrollPanel(bounds, nil, contentRect, scroll, &viewRect)
	BeginClipRect(viewRect)
	defer EndClipRect()

	mousePos := GetUIMousePosition()
	inView := PointInRect(mousePos, viewRect)

	visibleIdx := 0
	skipUntilDepth = -1
	for i in 0..<totalItems {
		item := &items[i]
		if skipUntilDepth != -1 {
			if item.depth > skipUntilDepth {
				continue
			} else {
				skipUntilDepth = -1
			}
		}

		itemY := viewRect.y + scroll.y + f32(visibleIdx) * itemHeight
		visibleIdx += 1
		itemRect := rl.Rectangle{viewRect.x, itemY, viewRect.width, itemHeight}

		if itemY + itemHeight >= viewRect.y && itemY <= viewRect.y + viewRect.height {
			indent := f32(item.depth) * 16.0
			rowX := viewRect.x + indent
			rowW := max(viewRect.width - indent, 40.0)

			isHovered := inView && PointInRect(mousePos, rl.Rectangle{rowX, itemY, rowW, itemHeight})

			if item.hasChildren {
				boxRect := rl.Rectangle{rowX + 2, itemY + (itemHeight - 14) * 0.5, 14, 14}
				if inView && PointInRect(mousePos, boxRect) && IsUIMouseButtonPressed(.LEFT) {
					item.isCollapsed = !item.isCollapsed
					toggledIndex = i
				}
			}

			if isHovered && IsUIMouseButtonPressed(.LEFT) {
				clickedIndex = i
				if selectedId != nil {
					selectedId^ = item.id
				}
			}

			RenderTreeNode(itemRect, item^, isHovered)
		}

		if item.hasChildren && item.isCollapsed {
			skipUntilDepth = item.depth
		}
	}

	return clickedIndex, toggledIndex
}

// ============================================================================
// 11. Custom Immediate-Mode Text Input (Replaces rl.GuiTextBox)
// ============================================================================
GuiTextInput :: proc(
	rect: rl.Rectangle,
	label: string,
	buffer: ^[dynamic]u8,
	placeholder: string = "Enter text...",
	labelWidth: f32 = 120,
	idKey: uintptr = 0,
) -> (changed: bool, submitted: bool) {
	if !rl.IsWindowReady() || buffer == nil do return false, false

	key := idKey if idKey != 0 else uintptr(buffer)
	ImmediateNav_RegisterFocusable(key, rect)
	isFocused := ImmediateNav_IsFocused(key)

	st := GetImmediateTextInputState(key)
	st.blinkTimer += rl.GetFrameTime()

	mp := GetUIMousePosition()
	mousePt := [2]f32{mp.x, mp.y}
	inClip := IsMouseInClipRect(mousePt)
	blocked := IsBlockedByImmediateDropdown(key, mousePt)
	hovered := inClip && !blocked && PointInRect(mousePt, rect)
	if hovered || isFocused do SetUICursor(.IBEAM, .Interact)

	if hovered && IsUIMouseButtonPressed(.LEFT) {
		ImmediateNav_SetFocus(key)
		isFocused = true
	}

	changed = false
	submitted = false

	if isFocused {
		keyChar := rl.GetCharPressed()
		for keyChar > 0 {
			if keyChar >= 32 && keyChar <= 126 {
				append(buffer, u8(keyChar))
				changed = true
			}
			keyChar = rl.GetCharPressed()
		}

		if IsUIKeyPressed(.BACKSPACE) && len(buffer^) > 0 {
			pop(buffer)
			changed = true
		}

		if IsUIKeyPressed(.ENTER) || IsUIKeyPressed(.KP_ENTER) {
			submitted = true
		}
	}

	textStr := string(buffer^[:])
	RenderTextInput(rect, label, textStr, placeholder, labelWidth, hovered, isFocused, st.blinkTimer)
	return changed, submitted
}

// ============================================================================
// 12. Custom Immediate-Mode Gradient / Color Ramp Editor & Line Plot
// ============================================================================
EvaluateGradient :: proc(stops: []ColorStop, t: f32) -> rl.Color {
	n := len(stops)
	if n == 0 do return rl.WHITE
	if n == 1 do return stops[0].color

	ct := clamp(t, 0.0, 1.0)
	if ct <= stops[0].position do return stops[0].color
	if ct >= stops[n - 1].position do return stops[n - 1].color

	for i in 0..<(n - 1) {
		p0 := stops[i].position
		p1 := stops[i + 1].position
		if ct >= p0 && ct <= p1 {
			span := p1 - p0
			frac := (ct - p0) / span if span > 0.0001 else 0.0
			c0 := stops[i].color
			c1 := stops[i + 1].color
			return rl.Color{
				u8(f32(c0.r) + frac * f32(i32(c1.r) - i32(c0.r))),
				u8(f32(c0.g) + frac * f32(i32(c1.g) - i32(c0.g))),
				u8(f32(c0.b) + frac * f32(i32(c1.b) - i32(c0.b))),
				u8(f32(c0.a) + frac * f32(i32(c1.a) - i32(c0.a))),
			}
		}
	}
	return stops[n - 1].color
}

GuiGradientEditor :: proc(
	bounds: rl.Rectangle,
	stops: ^[dynamic]ColorStop,
	selectedStop: ^int,
	draggingStop: ^bool,
	showPlot: bool = true,
) -> bool {
	if !rl.IsWindowReady() || stops == nil || len(stops^) == 0 do return false

	mousePos := GetUIMousePosition()
	changed := false

	plotH: f32 = 70.0 if showPlot else 0.0
	barH: f32 = 22.0
	y := bounds.y

	if showPlot {
		plotRect := rl.Rectangle{bounds.x, y, bounds.width, plotH}
		rl.DrawRectangleRec(plotRect, rl.Color{20, 22, 28, 255})
		rl.DrawRectangleLinesEx(plotRect, 1, rl.Color{55, 60, 75, 255})

		for step in 1..<4 {
			gy := plotRect.y + f32(step) * (plotH / 4)
			rl.DrawLineEx({plotRect.x, gy}, {plotRect.x + plotRect.width, gy}, 1, rl.Color{35, 38, 48, 255})
			gx := plotRect.x + f32(step) * (bounds.width / 4)
			rl.DrawLineEx({gx, plotRect.y}, {gx, plotRect.y + plotH}, 1, rl.Color{35, 38, 48, 255})
		}
		DrawText("Alpha 1.0", plotRect.x + 4, plotRect.y + 4, 10, rl.GRAY)
		DrawText("0.0", plotRect.x + 4, plotRect.y + plotH - 12, 10, rl.GRAY)

		prevPt := rl.Vector2{plotRect.x, plotRect.y + plotH - (f32(EvaluateGradient(stops^[:], 0.0).a) / 255.0) * plotH}
		for px in 1..=i32(bounds.width) {
			t := f32(px) / bounds.width
			col := EvaluateGradient(stops^[:], t)
			currY := plotRect.y + plotH - (f32(col.a) / 255.0) * plotH
			currPt := rl.Vector2{plotRect.x + f32(px), currY}
			rl.DrawLineEx(prevPt, currPt, 2, col)
			prevPt = currPt
		}

		for i in 0..<len(stops^) {
			st := stops^[i]
			sx := bounds.x + st.position * bounds.width
			sy := plotRect.y + plotH - (f32(st.color.a) / 255.0) * plotH
			rl.DrawCircle(i32(sx), i32(sy), 4, st.color)
			if selectedStop != nil && i == selectedStop^ {
				rl.DrawCircleLines(i32(sx), i32(sy), 6, rl.GOLD)
			}
		}

		y += plotH + 8
	}

	barRect := rl.Rectangle{bounds.x, y, bounds.width, barH}
	checkSize: f32 = 6
	for cy := barRect.y; cy < barRect.y + barH; cy += checkSize {
		for cx := barRect.x; cx < barRect.x + bounds.width; cx += checkSize {
			isWhite := (i32((cx - barRect.x) / checkSize) + i32((cy - barRect.y) / checkSize)) % 2 == 0
			checkCol := rl.Color{180, 180, 180, 255} if isWhite else rl.Color{130, 130, 130, 255}
			rl.DrawRectangleRec({cx, cy, min(checkSize, barRect.x + bounds.width - cx), min(checkSize, barRect.y + barH - cy)}, checkCol)
		}
	}

	for px in 0..<i32(bounds.width) {
		t := f32(px) / bounds.width
		col := EvaluateGradient(stops^[:], t)
		rl.DrawLineV({bounds.x + f32(px), barRect.y}, {bounds.x + f32(px), barRect.y + barH}, col)
	}
	rl.DrawRectangleLinesEx(barRect, 1, rl.LIGHTGRAY)

	markerH: f32 = 14
	markerW: f32 = 10
	markerY := barRect.y + barH + 2

	clickedStop := false
	if IsUIMouseButtonPressed(.LEFT) {
		for i in 0..<len(stops^) {
			sx := bounds.x + stops^[i].position * bounds.width
			if PointInRect(mousePos, {sx - markerW * 0.5 - 2, markerY - 2, markerW + 4, markerH + 4}) {
				if selectedStop != nil do selectedStop^ = i
				if draggingStop != nil do draggingStop^ = true
				clickedStop = true
				break
			}
		}
	}

	if !clickedStop && IsUIMouseButtonPressed(.LEFT) && PointInRect(mousePos, barRect) {
		newT := clamp((mousePos.x - bounds.x) / bounds.width, 0.0, 1.0)
		newCol := EvaluateGradient(stops^[:], newT)
		append(stops, ColorStop{position = newT, color = newCol})
		if selectedStop != nil do selectedStop^ = len(stops^) - 1
		changed = true
	}

	if draggingStop != nil && draggingStop^ {
		if IsUIMouseButtonReleased(.LEFT) {
			draggingStop^ = false
		} else if selectedStop != nil && selectedStop^ >= 0 && selectedStop^ < len(stops^) {
			newPos := clamp((mousePos.x - bounds.x) / bounds.width, 0.0, 1.0)
			if stops^[selectedStop^].position != newPos {
				stops^[selectedStop^].position = newPos
				changed = true
			}
		}
	}

	for i in 0..<len(stops^) {
		st := stops^[i]
		sx := bounds.x + st.position * bounds.width
		isSelected := (selectedStop != nil && i == selectedStop^)
		mRect := rl.Rectangle{sx - markerW * 0.5, markerY, markerW, markerH}

		rl.DrawRectangleRec(mRect, st.color)
		bCol := rl.GOLD if isSelected else rl.WHITE
		rl.DrawRectangleLinesEx(mRect, 1.5 if isSelected else 1.0, bCol)
	}

	return changed
}

// Immediate-mode Line Plot
GuiXYPlot :: proc(
	bounds: rl.Rectangle,
	title: cstring,
	points: [][2]f32,
	secondaryPoints: [][2]f32 = nil,
	minVal: [2]f32 = {0, 0},
	maxVal: [2]f32 = {1, 1},
	showGrid: bool = true,
) -> bool {
	titleStr := string(title) if title != nil else ""
	mousePos := GetUIMousePosition()
	hovered := PointInRect(mousePos, bounds)
	RenderXYPlot(
		bounds,
		titleStr,
		"Time",
		"Series 1",
		"Series 2",
		points,
		secondaryPoints,
		minVal[0], maxVal[0], minVal[1], maxVal[1],
		showGrid,
		true,
		hovered,
		hovered,
		mousePos,
		{0, 0},
		{59, 130, 246, 255},
		{239, 68, 68, 255},
		{45, 50, 62, 255},
	)
	return false
}


// ============================================================================
// 15. Custom Immediate-Mode Volume Fader
// ============================================================================
FaderDragState :: struct {
	activeKey:   uintptr,
	startMouseY: f32,
	startValDb:  f32,
}
activeFaderDrag: FaderDragState

GuiVolumeFader :: proc(
	rect: rl.Rectangle,
	label: cstring,
	valueDb: ^f32,
	minDb: f32 = -60.0,
	maxDb: f32 = 6.0,
	defaultDb: f32 = 0.0,
	idKey: uintptr = 0,
) -> bool {
	if !rl.IsWindowReady() || valueDb == nil do return false

	key := idKey if idKey != 0 else uintptr(valueDb)
	ImmediateNav_RegisterFocusable(key, rect)
	isFocused := ImmediateNav_IsFocused(key)

	mousePos := GetUIMousePosition()
	hovered := PointInRect(mousePos, rect)
	changed := false

	if hovered && IsUIMouseButtonPressed(.LEFT) {
		ImmediateNav_SetFocus(key)
	}

	if activeFaderDrag.activeKey == key && IsUIMouseButtonReleased(.LEFT) {
		activeFaderDrag.activeKey = 0
	}

	isDragging := activeFaderDrag.activeKey == key
	shiftDown := IsUIKeyDown(.LEFT_SHIFT) || IsUIKeyDown(.RIGHT_SHIFT)
	fineAdjust := shiftDown && (isFocused || isDragging)

	slotTop := rect.y + 26
	slotBottom := rect.y + rect.height - 30
	slotH := max(slotBottom - slotTop, 40.0)

	// Keyboard arrow navigation when focused
	if isFocused && !isDragging {
		step: f32 = 0.1 if fineAdjust else 0.5
		if IsUIKeyPressed(.UP) {
			newVal := clamp(valueDb^ + step, minDb, maxDb)
			if newVal != valueDb^ {
				valueDb^ = newVal
				changed = true
			}
		} else if IsUIKeyPressed(.DOWN) {
			newVal := clamp(valueDb^ - step, minDb, maxDb)
			if newVal != valueDb^ {
				valueDb^ = newVal
				changed = true
			}
		} else if IsUIKeyPressed(.PAGE_UP) {
			newVal := clamp(valueDb^ + 3.0, minDb, maxDb)
			if newVal != valueDb^ {
				valueDb^ = newVal
				changed = true
			}
		} else if IsUIKeyPressed(.PAGE_DOWN) {
			newVal := clamp(valueDb^ - 3.0, minDb, maxDb)
			if newVal != valueDb^ {
				valueDb^ = newVal
				changed = true
			}
		} else if IsUIKeyPressed(.HOME) {
			if valueDb^ != maxDb {
				valueDb^ = maxDb
				changed = true
			}
		} else if IsUIKeyPressed(.END) {
			if valueDb^ != minDb {
				valueDb^ = minDb
				changed = true
			}
		}
	}

	// Mouse Wheel navigation
	if hovered {
		wheel := rl.GetMouseWheelMove()
		if wheel != 0 {
			step: f32 = 0.1 if (shiftDown && (isFocused || hovered)) else 0.5
			newVal := clamp(valueDb^ + step * wheel, minDb, maxDb)
			if newVal != valueDb^ {
				valueDb^ = newVal
				changed = true
			}
		}
	}

	// Reset on Right Click or Double Click
	if hovered && (IsUIMouseButtonPressed(.RIGHT) || (IsUIMouseButtonPressed(.LEFT) && rl.GetGestureDetected() == {.DOUBLETAP})) {
		if valueDb^ != defaultDb {
			valueDb^ = defaultDb
			changed = true
		}
	} else if hovered && IsUIMouseButtonPressed(.LEFT) {
		activeFaderDrag.activeKey = key
		activeFaderDrag.startMouseY = mousePos.y
		activeFaderDrag.startValDb = valueDb^

		// Jump fader on click if not fine mode
		if !fineAdjust {
			norm := clamp((slotBottom - mousePos.y) / slotH, 0.0, 1.0)
			newDb := FaderNormToDb(norm, minDb, maxDb)
			if newDb != valueDb^ {
				valueDb^ = newDb
				changed = true
			}
		}
	}

	// Dragging
	if isDragging && IsUIMouseButtonDown(.LEFT) {
		if fineAdjust {
			dy := activeFaderDrag.startMouseY - mousePos.y
			dbDelta := (dy / slotH) * (maxDb - minDb) * 0.15
			newDb := clamp(activeFaderDrag.startValDb + dbDelta, minDb, maxDb)
			if newDb != valueDb^ {
				valueDb^ = newDb
				changed = true
			}
		} else {
			norm := clamp((slotBottom - mousePos.y) / slotH, 0.0, 1.0)
			newDb := FaderNormToDb(norm, minDb, maxDb)
			if newDb != valueDb^ {
				valueDb^ = newDb
				changed = true
			}
		}
	}

	labelStr := string(label) if label != nil else ""
	RenderVolumeFader(rect, labelStr, valueDb^, minDb, maxDb, defaultDb, hovered, isDragging, focused = isFocused, fineMode = fineAdjust)
	return changed
}

// ============================================================================
// 16. Custom Immediate-Mode Volume Meter
// ============================================================================
GuiVolumeMeter :: proc(
	rect: rl.Rectangle,
	label: cstring,
	levelL: f32, // in dB (-60 to +3)
	levelR: f32 = -120.0, // in dB (-60 to +3); if < -100, mono meter
	state: ^VolumeMeterState = nil,
	orientation: MeterOrientation = .Vertical,
	minDb: f32 = -60.0,
	maxDb: f32 = 3.0,
) -> bool {
	if !rl.IsWindowReady() do return false

	dt := rl.GetFrameTime()
	if dt <= 0.0 || dt > 0.1 do dt = 0.016

	if state != nil {
		if state.peakHoldTimerL > 0 {
			state.peakHoldTimerL -= dt
		} else {
			state.peakL = max(state.peakL - dt * 0.45, 0.0)
		}
		if state.peakHoldTimerR > 0 {
			state.peakHoldTimerR -= dt
		} else {
			state.peakR = max(state.peakR - dt * 0.45, 0.0)
		}
		if state.clipL {
			state.clipHoldTimerL -= dt
			if state.clipHoldTimerL <= 0 do state.clipL = false
		}
		if state.clipR {
			state.clipHoldTimerR -= dt
			if state.clipHoldTimerR <= 0 do state.clipR = false
		}
	}

	labelStr := string(label) if label != nil else ""
	RenderVolumeMeter(rect, labelStr, levelL, levelR, state, orientation, minDb, maxDb)
	return false
}

// ============================================================================
// 17. Custom Immediate-Mode Notched Slider (Horizontal & Vertical)
// ============================================================================
NotchedSliderDragState :: struct {
	activeKey:  uintptr,
	startMouse: rl.Vector2,
	startVal:   f32,
}
activeNotchedDrag: NotchedSliderDragState

GuiNotchedSlider :: proc(
	rect: rl.Rectangle,
	label: cstring,
	value: ^f32,
	minValue, maxValue: f32,
	numNotches: int,
	notchLabels: []string = nil,
	snapToNotches: bool = true,
	orientation: SliderOrientation = .Horizontal,
	idKey: uintptr = 0,
) -> bool {
	if !rl.IsWindowReady() || value == nil do return false

	key := idKey if idKey != 0 else uintptr(value)
	ImmediateNav_RegisterFocusable(key, rect)
	isFocused := ImmediateNav_IsFocused(key)

	mousePos := GetUIMousePosition()
	hovered := PointInRect(mousePos, rect)
	changed := false

	if hovered && IsUIMouseButtonPressed(.LEFT) {
		ImmediateNav_SetFocus(key)
	}

	if activeNotchedDrag.activeKey == key && IsUIMouseButtonReleased(.LEFT) {
		activeNotchedDrag.activeKey = 0
	}

	isDragging := activeNotchedDrag.activeKey == key
	shiftDown := IsUIKeyDown(.LEFT_SHIFT) || IsUIKeyDown(.RIGHT_SHIFT)
	fineAdjust := shiftDown && (isFocused || isDragging)

	notches := max(numNotches, 2)
	stepSize := (maxValue - minValue) / f32(notches - 1)

	// Keyboard arrow navigation when focused
	if isFocused && !isDragging {
		if snapToNotches && !fineAdjust {
			curNorm := clamp((value^ - minValue) / max(maxValue - minValue, 0.0001), 0.0, 1.0)
			curNotch := int(math.round(curNorm * f32(notches - 1)))
			if (orientation == .Horizontal && IsUIKeyPressed(.LEFT)) || (orientation == .Vertical && IsUIKeyPressed(.DOWN)) {
				curNotch = max(curNotch - 1, 0)
				newVal := minValue + f32(curNotch) * stepSize
				if newVal != value^ {
					value^ = newVal
					changed = true
				}
			} else if (orientation == .Horizontal && IsUIKeyPressed(.RIGHT)) || (orientation == .Vertical && IsUIKeyPressed(.UP)) {
				curNotch = min(curNotch + 1, notches - 1)
				newVal := minValue + f32(curNotch) * stepSize
				if newVal != value^ {
					value^ = newVal
					changed = true
				}
			}
		} else {
			fineStep := stepSize * (0.05 if fineAdjust else 0.20)
			if (orientation == .Horizontal && IsUIKeyPressed(.LEFT)) || (orientation == .Vertical && IsUIKeyPressed(.DOWN)) {
				newVal := clamp(value^ - fineStep, minValue, maxValue)
				if newVal != value^ {
					value^ = newVal
					changed = true
				}
			} else if (orientation == .Horizontal && IsUIKeyPressed(.RIGHT)) || (orientation == .Vertical && IsUIKeyPressed(.UP)) {
				newVal := clamp(value^ + fineStep, minValue, maxValue)
				if newVal != value^ {
					value^ = newVal
					changed = true
				}
			}
		}
	}

	// Mouse Dragging
	if hovered && IsUIMouseButtonPressed(.LEFT) {
		activeNotchedDrag.activeKey = key
		activeNotchedDrag.startMouse = mousePos
		activeNotchedDrag.startVal = value^
	}

	if isDragging && IsUIMouseButtonDown(.LEFT) {
		norm: f32
		if orientation == .Horizontal {
			trackPadX: f32 = 12.0
			norm = clamp((mousePos.x - (rect.x + trackPadX)) / max(rect.width - trackPadX * 2.0, 1.0), 0.0, 1.0)
		} else {
			labelH: f32 = 16.0 if label != nil && len(label) > 0 else 0.0
			trackPadY: f32 = 14.0
			trackY := rect.y + labelH + trackPadY
			trackH := max(rect.height - labelH - trackPadY * 2.0 - 18, 30.0)
			norm = clamp(((trackY + trackH) - mousePos.y) / trackH, 0.0, 1.0)
		}

		rawVal := minValue + norm * (maxValue - minValue)
		if snapToNotches && !fineAdjust {
			notchIdx := int(math.round(norm * f32(notches - 1)))
			snappedVal := minValue + f32(notchIdx) * stepSize
			if snappedVal != value^ {
				value^ = snappedVal
				changed = true
			}
		} else {
			if rawVal != value^ {
				value^ = rawVal
				changed = true
			}
		}
	}

	// Find current snapped notch index (for visual highlight)
	curNorm := clamp((value^ - minValue) / max(maxValue - minValue, 0.0001), 0.0, 1.0)
	nearestNotch := int(math.round(curNorm * f32(notches - 1)))
	notchNorm := f32(nearestNotch) / f32(notches - 1)
	isAtNotch := abs(curNorm - notchNorm) < (0.5 / f32(notches - 1))
	snappedNotch := nearestNotch if isAtNotch else -1

	labelStr := string(label) if label != nil else ""
	RenderNotchedSlider(rect, labelStr, value^, minValue, maxValue, numNotches, notchLabels, orientation, hovered, isDragging, focused = isFocused, fineMode = fineAdjust, snappedNotch = snappedNotch)
	return changed
}


// ============================================================================
// 12. Custom Immediate-Mode Radio Group
// ============================================================================
GuiRadioGroup :: proc(
	rect: rl.Rectangle,
	label: string,
	options: []string,
	selectedIndex: ^int,
	horizontal: bool = false,
	idKey: uintptr = 0,
) -> bool {
	if !rl.IsWindowReady() || selectedIndex == nil do return false
	key := idKey if idKey != 0 else uintptr(selectedIndex)
	ImmediateNav_RegisterFocusable(key, rect)
	isFocused := ImmediateNav_IsFocused(key)

	changed := false
	count := len(options)
	mousePos := GetUIMousePosition()
	mp := [2]f32{mousePos.x, mousePos.y}

	hoveredOpt := -1
	for i in 0..<count {
		optRect := GetRadioGroupOptionRect(rect, label != "", 110, count, horizontal, i)
		if PointInRect(mp, optRect) {
			hoveredOpt = i
			if IsUIMouseButtonPressed(.LEFT) {
				ImmediateNav_SetFocus(key)
				if selectedIndex^ != i {
					selectedIndex^ = i
					changed = true
				}
			}
		}
	}

	if hoveredOpt != -1 do SetUICursor(.POINTING_HAND, .Hover)

	if isFocused && count > 0 {
		if horizontal {
			if IsUIKeyPressed(.LEFT) {
				selectedIndex^ = (selectedIndex^ - 1 + count) % count
				changed = true
			} else if IsUIKeyPressed(.RIGHT) {
				selectedIndex^ = (selectedIndex^ + 1) % count
				changed = true
			}
		} else {
			if IsUIKeyPressed(.UP) {
				selectedIndex^ = (selectedIndex^ - 1 + count) % count
				changed = true
			} else if IsUIKeyPressed(.DOWN) {
				selectedIndex^ = (selectedIndex^ + 1) % count
				changed = true
			}
		}
	}

	RenderRadioGroup(rect, label, 110, options, selectedIndex^, hoveredOpt, horizontal, isFocused)
	return changed
}
