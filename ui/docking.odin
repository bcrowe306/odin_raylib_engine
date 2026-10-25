package ui

import "core:fmt"
import "core:math"
import "core:strings"
import rl "vendor:raylib"

// ============================================================================
// Professional Docking Interface System (Window-Resize Invariant & Non-Overlapping)
// ============================================================================

DockSlot :: enum {
	None,
	Hidden,
	Left,
	Right,
	Top,
	Bottom,
	Center,
	Floating,
}

DockPanel :: struct {
	id:             string,
	title:          string,
	slot:           DockSlot,
	prevSlot:       DockSlot,
	isVisible:      bool,
	isCollapsed:    bool,
	canClose:       bool,
	canUndock:      bool,

	// Runtime computed bounding rectangles
	panelRect:      rl.Rectangle,
	contentRect:    rl.Rectangle,
	headerRect:     rl.Rectangle,

	// Floating window state
	floatPos:       rl.Vector2,
	floatSize:      rl.Vector2,

	// Proportional normalized position (survives window resizing)
	floatRelPos:    rl.Vector2,
	floatRelSize:   rl.Vector2,
}

SplitterType :: enum {
	None,
	LeftSplitter,
	RightSplitter,
	BottomSplitter,
}

DockSpace :: struct {
	hostBounds:          rl.Rectangle,

	// Normalized proportional split ratios (survive host window resizing)
	leftRatio:           f32,
	rightRatio:          f32,
	bottomRatio:         f32,

	// Min/max pixel constraints
	minLeftWidth:        f32,
	maxLeftWidth:        f32,
	minRightWidth:       f32,
	maxRightWidth:       f32,
	minBottomHeight:     f32,
	maxBottomHeight:     f32,

	// Computed dock zones for the current frame
	leftRect:            rl.Rectangle,
	rightRect:           rl.Rectangle,
	bottomRect:          rl.Rectangle,
	centerRect:          rl.Rectangle,

	// Splitter hit rectangles
	leftSplitterRect:    rl.Rectangle,
	rightSplitterRect:   rl.Rectangle,
	bottomSplitterRect:  rl.Rectangle,

	// Splitter drag state
	draggingSplitter:    SplitterType,

	// Panel drag and drop state
	draggingPanelId:     string,
	dragOffset:          rl.Vector2,
	dragHoverSlot:       DockSlot,
	dragPreviewRect:     rl.Rectangle,

	// Active tab indices when multiple panels are docked in the same slot
	activeLeftTab:       int,
	activeRightTab:      int,
	activeBottomTab:     int,
	activeCenterTab:     int,

	// Panels registered in this dockspace
	panels:              [dynamic]DockPanel,

	// Styling parameters
	headerHeight:        f32,
	splitterWidth:       f32,
	panelBgColor:        rl.Color,
	headerBgColor:       rl.Color,
	headerActiveBg:      rl.Color,
	borderColor:         rl.Color,
	accentColor:         rl.Color,
	dropZoneColor:       rl.Color,
}

DockSpace_Init :: proc(space: ^DockSpace, initialBounds: rl.Rectangle) {
	space.hostBounds = initialBounds
	space.leftRatio = 0.24
	space.rightRatio = 0.26
	space.bottomRatio = 0.28

	space.minLeftWidth = 160.0
	space.maxLeftWidth = 500.0
	space.minRightWidth = 180.0
	space.maxRightWidth = 550.0
	space.minBottomHeight = 110.0
	space.maxBottomHeight = 450.0

	space.headerHeight = 28.0
	space.splitterWidth = 6.0

	space.panelBgColor = rl.Color{20, 24, 32, 245}
	space.headerBgColor = rl.Color{28, 33, 44, 255}
	space.headerActiveBg = rl.Color{38, 46, 62, 255}
	space.borderColor = rl.Color{48, 56, 75, 255}
	space.accentColor = rl.Color{59, 130, 246, 255}
	space.dropZoneColor = rl.Color{59, 130, 246, 75}

	space.panels = make([dynamic]DockPanel)
}

DockSpace_Destroy :: proc(space: ^DockSpace) {
	delete(space.panels)
}

DockSpace_AddPanel :: proc(
	space: ^DockSpace,
	id: string,
	title: string,
	initialSlot: DockSlot,
	floatPos: rl.Vector2 = {100, 100},
	floatSize: rl.Vector2 = {320, 240},
	canClose: bool = true,
	canUndock: bool = true,
) {
	relPos := rl.Vector2{
		floatPos.x / max(space.hostBounds.width, 1.0),
		floatPos.y / max(space.hostBounds.height, 1.0),
	}
	relSize := rl.Vector2{
		floatSize.x / max(space.hostBounds.width, 1.0),
		floatSize.y / max(space.hostBounds.height, 1.0),
	}

	panel := DockPanel{
		id = id,
		title = title,
		slot = initialSlot,
		prevSlot = initialSlot if initialSlot != .Floating else .Left,
		isVisible = true,
		isCollapsed = false,
		canClose = canClose,
		canUndock = canUndock,
		floatPos = floatPos,
		floatSize = floatSize,
		floatRelPos = relPos,
		floatRelSize = relSize,
	}
	append(&space.panels, panel)
}

DockSpace_FindPanel :: proc(space: ^DockSpace, id: string) -> ^DockPanel {
	for i in 0..<len(space.panels) {
		if space.panels[i].id == id {
			return &space.panels[i]
		}
	}
	return nil
}

// Find another panel that is currently occupying a dock slot
DockSpace_FindOccupant :: proc(space: ^DockSpace, slot: DockSlot, excludeId: string) -> ^DockPanel {
	if slot == .None || slot == .Floating || slot == .Hidden do return nil
	for i in 0..<len(space.panels) {
		p := &space.panels[i]
		if p.id != excludeId && p.isVisible && p.slot == slot {
			return p
		}
	}
	return nil
}

// Find an unoccupied standard dock slot
DockSpace_FindUnoccupiedSlot :: proc(space: ^DockSpace, excludeSlot: DockSlot) -> DockSlot {
	candidates := [4]DockSlot{.Center, .Right, .Left, .Bottom}
	for s in candidates {
		if s == excludeSlot do continue
		occupied := false
		for p in space.panels {
			if p.isVisible && p.slot == s {
				occupied = true
				break
			}
		}
		if !occupied do return s
	}
	return .None
}

// Moves a panel to a target slot. If another panel is already docked there,
// it moves the existing panel to avoid any visual overlap.
DockSpace_MovePanelToSlot :: proc(space: ^DockSpace, panel: ^DockPanel, targetSlot: DockSlot) {
	if panel == nil do return
	if targetSlot == .Floating || targetSlot == .Hidden || targetSlot == .None {
		panel.slot = targetSlot
		return
	}

	// 1. Check if another panel is already occupying the target slot
	occupant := DockSpace_FindOccupant(space, targetSlot, panel.id)
	if occupant != nil {
		destSlot := DockSlot.None

		// Priority A: If panel originated from a valid docked slot, swap occupant there
		if panel.prevSlot != .None && panel.prevSlot != .Floating && panel.prevSlot != .Hidden && panel.prevSlot != targetSlot {
			destSlot = panel.prevSlot
		} else {
			// Priority B: Find an open unoccupied dock slot
			destSlot = DockSpace_FindUnoccupiedSlot(space, targetSlot)
		}

		// Priority C: Fallback to opposite/adjacent slot
		if destSlot == .None || destSlot == targetSlot {
			#partial switch targetSlot {
			case .Left:   destSlot = .Right
			case .Right:  destSlot = .Left
			case .Bottom: destSlot = .Center
			case .Center: destSlot = .Bottom
			case:         destSlot = .Floating
			}
		}

		// If the destination slot is also occupied by another panel, displace that one to an open slot
		secondOccupant := DockSpace_FindOccupant(space, destSlot, occupant.id)
		if secondOccupant != nil && secondOccupant.id != panel.id {
			openSlot := DockSpace_FindUnoccupiedSlot(space, destSlot)
			secondOccupant.prevSlot = secondOccupant.slot
			secondOccupant.slot = openSlot if openSlot != .None else .Floating
		}

		occupant.prevSlot = occupant.slot
		occupant.slot = destSlot
	}

	// 2. Assign target slot to panel
	panel.prevSlot = panel.slot if panel.slot != .Floating else panel.prevSlot
	panel.slot = targetSlot
	panel.isVisible = true
}

DockSpace_SetSlot :: proc(space: ^DockSpace, id: string, newSlot: DockSlot) {
	p := DockSpace_FindPanel(space, id)
	if p == nil do return
	DockSpace_MovePanelToSlot(space, p, newSlot)
}

DockSpace_ToggleFloating :: proc(space: ^DockSpace, id: string) {
	p := DockSpace_FindPanel(space, id)
	if p == nil do return
	if p.slot == .Floating {
		target := p.prevSlot if (p.prevSlot != .Floating && p.prevSlot != .Hidden && p.prevSlot != .None) else .Left
		DockSpace_MovePanelToSlot(space, p, target)
	} else {
		p.prevSlot = p.slot
		p.slot = .Floating
	}
}

DockSpace_UpdateLayout :: proc(space: ^DockSpace, bounds: rl.Rectangle) {
	if bounds.width <= 10 || bounds.height <= 10 do return
	boundsChanged := (bounds.width != space.hostBounds.width || bounds.height != space.hostBounds.height)
	space.hostBounds = bounds

	mousePos := GetUIMousePosition()

	// 1. Check which slots contain visible panels
	hasLeft := false
	hasRight := false
	hasBottom := false
	hasCenter := false
	for p in space.panels {
		if !p.isVisible || p.isCollapsed do continue
		#partial switch p.slot {
		case .Left: hasLeft = true
		case .Right: hasRight = true
		case .Bottom: hasBottom = true
		case .Center: hasCenter = true
		case .Hidden, .Top, .Floating: // pass
		}
	}

	// 2. Handle interactive splitter dragging
	if IsUIMouseButtonPressed(.LEFT) {
		if hasLeft && PointInRect(mousePos, space.leftSplitterRect) {
			space.draggingSplitter = .LeftSplitter
		} else if hasRight && PointInRect(mousePos, space.rightSplitterRect) {
			space.draggingSplitter = .RightSplitter
		} else if hasBottom && PointInRect(mousePos, space.bottomSplitterRect) {
			space.draggingSplitter = .BottomSplitter
		}
	}

	if space.draggingSplitter != .None {
		switch space.draggingSplitter {
		case .LeftSplitter, .RightSplitter:
			SetUICursor(.RESIZE_EW, .Dragging)
		case .BottomSplitter:
			SetUICursor(.RESIZE_NS, .Dragging)
		case .None: // pass
		}
		if IsUIMouseButtonDown(.LEFT) {
			switch space.draggingSplitter {
			case .LeftSplitter:
				newW := clamp(mousePos.x - bounds.x, space.minLeftWidth, bounds.width * 0.45)
				space.leftRatio = newW / bounds.width
			case .RightSplitter:
				newW := clamp(bounds.x + bounds.width - mousePos.x, space.minRightWidth, bounds.width * 0.45)
				space.rightRatio = newW / bounds.width
			case .BottomSplitter:
				newH := clamp(bounds.y + bounds.height - mousePos.y, space.minBottomHeight, bounds.height * 0.45)
				space.bottomRatio = newH / bounds.height
			case .None: // pass
			}
		} else {
			space.draggingSplitter = .None
		}
	}

	if space.draggingSplitter == .None {
		if (hasLeft && PointInRect(mousePos, space.leftSplitterRect)) || (hasRight && PointInRect(mousePos, space.rightSplitterRect)) {
			SetUICursor(.RESIZE_EW, .Interact)
		} else if hasBottom && PointInRect(mousePos, space.bottomSplitterRect) {
			SetUICursor(.RESIZE_NS, .Interact)
		}
	}

	// 3. Compute slot dimensions based on window-resize invariant proportional ratios
	leftW: f32 = 0
	if hasLeft {
		leftW = clamp(bounds.width * space.leftRatio, space.minLeftWidth, space.maxLeftWidth)
		leftW = min(leftW, bounds.width * 0.45)
	}

	rightW: f32 = 0
	if hasRight {
		rightW = clamp(bounds.width * space.rightRatio, space.minRightWidth, space.maxRightWidth)
		rightW = min(rightW, bounds.width * 0.45)
	}

	bottomH: f32 = 0
	if hasBottom {
		bottomH = clamp(bounds.height * space.bottomRatio, space.minBottomHeight, space.maxBottomHeight)
		bottomH = min(bottomH, bounds.height * 0.45)
	}

	remW := max(bounds.width - leftW - rightW, 60.0)
	remH := max(bounds.height - bottomH, 60.0)

	space.leftRect = rl.Rectangle{bounds.x, bounds.y, leftW, bounds.height - bottomH}
	space.rightRect = rl.Rectangle{bounds.x + bounds.width - rightW, bounds.y, rightW, bounds.height - bottomH}
	space.bottomRect = rl.Rectangle{bounds.x, bounds.y + bounds.height - bottomH, bounds.width, bottomH}
	space.centerRect = rl.Rectangle{bounds.x + leftW, bounds.y, remW, remH}

	// Splitter rectangles
	sw := space.splitterWidth
	space.leftSplitterRect = rl.Rectangle{space.leftRect.x + space.leftRect.width - sw * 0.5, space.leftRect.y, sw, space.leftRect.height}
	space.rightSplitterRect = rl.Rectangle{space.rightRect.x - sw * 0.5, space.rightRect.y, sw, space.rightRect.height}
	space.bottomSplitterRect = rl.Rectangle{bounds.x, space.bottomRect.y - sw * 0.5, bounds.width, sw}

	// 4. Update each panel's rectangles (with partitioning to guarantee zero overlap even if multiple panels share a slot)
	leftPanels: [8]^DockPanel
	leftCount := 0
	rightPanels: [8]^DockPanel
	rightCount := 0
	bottomPanels: [8]^DockPanel
	bottomCount := 0
	centerPanels: [8]^DockPanel
	centerCount := 0

	for i in 0..<len(space.panels) {
		p := &space.panels[i]
		if !p.isVisible {
			p.panelRect = {}
			p.contentRect = {}
			continue
		}

		#partial switch p.slot {
		case .Left:
			if leftCount < 8 { leftPanels[leftCount] = p; leftCount += 1 }
		case .Right:
			if rightCount < 8 { rightPanels[rightCount] = p; rightCount += 1 }
		case .Bottom:
			if bottomCount < 8 { bottomPanels[bottomCount] = p; bottomCount += 1 }
		case .Center:
			if centerCount < 8 { centerPanels[centerCount] = p; centerCount += 1 }
		case .Floating:
			// If window resized, adapt floating panel smoothly
			if boundsChanged {
				p.floatPos.x = bounds.x + p.floatRelPos.x * bounds.width
				p.floatPos.y = bounds.y + p.floatRelPos.y * bounds.height
			}
			// Clamp floating panel inside hostBounds so it never flies off-screen
			p.floatPos.x = clamp(p.floatPos.x, bounds.x + 8, bounds.x + bounds.width - p.floatSize.x - 8)
			p.floatPos.y = clamp(p.floatPos.y, bounds.y + 8, bounds.y + bounds.height - p.floatSize.y - 8)
			p.floatRelPos = {
				(p.floatPos.x - bounds.x) / max(bounds.width, 1.0),
				(p.floatPos.y - bounds.y) / max(bounds.height, 1.0),
			}
			p.panelRect = rl.Rectangle{p.floatPos.x, p.floatPos.y, p.floatSize.x, p.floatSize.y}
		case .Hidden, .Top, .None:
			p.panelRect = {}
		}
	}

	// Layout Left panels (vertically tiled if multiple)
	if leftCount == 1 {
		leftPanels[0].panelRect = space.leftRect
	} else if leftCount > 1 {
		sliceH := space.leftRect.height / f32(leftCount)
		for j in 0..<leftCount {
			leftPanels[j].panelRect = rl.Rectangle{space.leftRect.x, space.leftRect.y + f32(j) * sliceH, space.leftRect.width, sliceH}
		}
	}

	// Layout Right panels (vertically tiled if multiple)
	if rightCount == 1 {
		rightPanels[0].panelRect = space.rightRect
	} else if rightCount > 1 {
		sliceH := space.rightRect.height / f32(rightCount)
		for j in 0..<rightCount {
			rightPanels[j].panelRect = rl.Rectangle{space.rightRect.x, space.rightRect.y + f32(j) * sliceH, space.rightRect.width, sliceH}
		}
	}

	// Layout Bottom panels (horizontally tiled if multiple)
	if bottomCount == 1 {
		bottomPanels[0].panelRect = space.bottomRect
	} else if bottomCount > 1 {
		sliceW := space.bottomRect.width / f32(bottomCount)
		for j in 0..<bottomCount {
			bottomPanels[j].panelRect = rl.Rectangle{space.bottomRect.x + f32(j) * sliceW, space.bottomRect.y, sliceW, space.bottomRect.height}
		}
	}

	// Layout Center panels (horizontally tiled if multiple)
	if centerCount == 1 {
		centerPanels[0].panelRect = space.centerRect
	} else if centerCount > 1 {
		sliceW := space.centerRect.width / f32(centerCount)
		for j in 0..<centerCount {
			centerPanels[j].panelRect = rl.Rectangle{space.centerRect.x + f32(j) * sliceW, space.centerRect.y, sliceW, space.centerRect.height}
		}
	}

	// Compute header and content rects for all panels
	for i in 0..<len(space.panels) {
		p := &space.panels[i]
		if !p.isVisible || p.panelRect.width <= 0 {
			p.headerRect = {}
			p.contentRect = {}
			continue
		}
		p.headerRect = rl.Rectangle{p.panelRect.x, p.panelRect.y, p.panelRect.width, space.headerHeight}
		p.contentRect = rl.Rectangle{
			p.panelRect.x + 8,
			p.panelRect.y + space.headerHeight + 6,
			max(p.panelRect.width - 16, 20.0),
			max(p.panelRect.height - space.headerHeight - 12, 20.0),
		}
	}

	// 5. Handle panel header dragging & dock targeting
	if space.draggingPanelId != "" {
		SetUICursor(.RESIZE_ALL, .Dragging)
		if IsUIMouseButtonDown(.LEFT) {
			dp := DockSpace_FindPanel(space, space.draggingPanelId)
			if dp != nil {
				dp.floatPos = {mousePos.x - space.dragOffset.x, mousePos.y - space.dragOffset.y}
				dp.panelRect = rl.Rectangle{dp.floatPos.x, dp.floatPos.y, dp.floatSize.x, dp.floatSize.y}
				dp.headerRect = rl.Rectangle{dp.panelRect.x, dp.panelRect.y, dp.panelRect.width, space.headerHeight}
				dp.contentRect = rl.Rectangle{
					dp.panelRect.x + 8,
					dp.panelRect.y + space.headerHeight + 6,
					max(dp.panelRect.width - 16, 20.0),
					max(dp.panelRect.height - space.headerHeight - 12, 20.0),
				}

				// Detect candidate dock target zone
				space.dragHoverSlot = .Floating
				space.dragPreviewRect = dp.panelRect

				edgeThresholdW := bounds.width * 0.16
				edgeThresholdH := bounds.height * 0.16

				if mousePos.x < bounds.x + edgeThresholdW && PointInRect(mousePos, bounds) {
					space.dragHoverSlot = .Left
					space.dragPreviewRect = rl.Rectangle{bounds.x, bounds.y, bounds.width * space.leftRatio, bounds.height}
				} else if mousePos.x > bounds.x + bounds.width - edgeThresholdW && PointInRect(mousePos, bounds) {
					space.dragHoverSlot = .Right
					space.dragPreviewRect = rl.Rectangle{bounds.x + bounds.width - (bounds.width * space.rightRatio), bounds.y, bounds.width * space.rightRatio, bounds.height}
				} else if mousePos.y > bounds.y + bounds.height - edgeThresholdH && PointInRect(mousePos, bounds) {
					space.dragHoverSlot = .Bottom
					space.dragPreviewRect = rl.Rectangle{bounds.x, bounds.y + bounds.height - (bounds.height * space.bottomRatio), bounds.width, bounds.height * space.bottomRatio}
				} else if PointInRect(mousePos, space.centerRect) {
					space.dragHoverSlot = .Center
					space.dragPreviewRect = space.centerRect
				}
			}
		} else {
			// Released mouse: drop panel into candidate target slot
			dp := DockSpace_FindPanel(space, space.draggingPanelId)
			if dp != nil {
				if space.dragHoverSlot != .Floating && space.dragHoverSlot != .Hidden && space.dragHoverSlot != .None {
					DockSpace_MovePanelToSlot(space, dp, space.dragHoverSlot)
				} else {
					dp.slot = .Floating
				}
			}
			space.draggingPanelId = ""
			space.dragHoverSlot = .None
		}
	}
}

DockSpace_BeginPanel :: proc(space: ^DockSpace, id: string) -> (visible: bool, contentBounds: rl.Rectangle) {
	p := DockSpace_FindPanel(space, id)
	if p == nil || !p.isVisible || p.panelRect.width <= 0 do return false, {}

	mousePos := GetUIMousePosition()

	// 1. Draw Panel Frame Background & Border
	rl.DrawRectangleRec(p.panelRect, space.panelBgColor)
	rl.DrawRectangleLinesEx(p.panelRect, 1, space.borderColor)

	// 2. Draw Header
	isHeaderHovered := PointInRect(mousePos, p.headerRect)
	if isHeaderHovered do SetUICursor(.POINTING_HAND, .Hover)
	hdrCol := space.headerActiveBg if isHeaderHovered else space.headerBgColor
	rl.DrawRectangleRec(p.headerRect, hdrCol)
	rl.DrawLineEx(
		{p.headerRect.x, p.headerRect.y + p.headerRect.height},
		{p.headerRect.x + p.headerRect.width, p.headerRect.y + p.headerRect.height},
		1,
		space.borderColor,
	)

	// Header accent strip
	accentCol := space.accentColor
	if p.slot == .Floating do accentCol = rl.Color{245, 158, 11, 255}
	rl.DrawRectangleRec({p.headerRect.x, p.headerRect.y, p.headerRect.width, 2}, accentCol)

	// Panel Title & Slot Badge
	slotBadge := "[Docked]"
	#partial switch p.slot {
	case .Left:     slotBadge = "[LEFT]"
	case .Right:    slotBadge = "[RIGHT]"
	case .Bottom:   slotBadge = "[BOTTOM]"
	case .Center:   slotBadge = "[CENTER]"
	case .Floating: slotBadge = "[FLOAT]"
	}

	titleText := fmt.tprintf("%s  %s", p.title, slotBadge)
	DrawTextStr(titleText, p.headerRect.x + 10, p.headerRect.y + (p.headerRect.height - 14) * 0.5, 14, rl.Color{230, 235, 245, 255})

	// 3. Header Action Buttons (Dock, Float, Close)
	btnW: f32 = 18.0
	btnH: f32 = 18.0
	btnY := p.headerRect.y + (p.headerRect.height - btnH) * 0.5
	curBtnX := p.headerRect.x + p.headerRect.width - 24

	// Close Button [X]
	if p.canClose {
		closeRect := rl.Rectangle{curBtnX, btnY, btnW, btnH}
		hoverClose := PointInRect(mousePos, closeRect)
		if hoverClose {
			rl.DrawRectangleRec(closeRect, rl.Color{239, 68, 68, 200})
			if IsUIMouseButtonPressed(.LEFT) {
				p.isVisible = false
			}
		}
		DrawTextStr("x", closeRect.x + 5, closeRect.y + 1, 11, rl.WHITE)
		curBtnX -= 22
	}

	// Float / Unfloat Button [⤢]
	if p.canUndock {
		floatRect := rl.Rectangle{curBtnX, btnY, btnW, btnH}
		hoverFloat := PointInRect(mousePos, floatRect)
		if hoverFloat {
			rl.DrawRectangleRec(floatRect, rl.Color{60, 70, 95, 255})
			if IsUIMouseButtonPressed(.LEFT) {
				DockSpace_ToggleFloating(space, p.id)
			}
		}
		floatIcon := "F" if p.slot != .Floating else "D"
		DrawTextStr(floatIcon, floatRect.x + 5, floatRect.y + 2, 11, rl.Color{200, 210, 230, 255})
		curBtnX -= 22
	}

	// Cycle Dock Slot Button [<] or [>] (Moves existing panel if target slot is occupied)
	cycleRect := rl.Rectangle{curBtnX, btnY, btnW, btnH}
	hoverCycle := PointInRect(mousePos, cycleRect)
	if hoverCycle {
		rl.DrawRectangleRec(cycleRect, rl.Color{60, 70, 95, 255})
		if IsUIMouseButtonPressed(.LEFT) {
			nextSlot: DockSlot = .Left
			#partial switch p.slot {
			case .Left:     nextSlot = .Right
			case .Right:    nextSlot = .Bottom
			case .Bottom:   nextSlot = .Center
			case .Center:   nextSlot = .Left
			case .Floating: nextSlot = .Left
			}
			DockSpace_MovePanelToSlot(space, p, nextSlot)
		}
	}
	DrawTextStr(">", cycleRect.x + 5, cycleRect.y + 2, 11, rl.Color{160, 180, 220, 255})

	// 4. Undock by dragging the title bar
	if isHeaderHovered && mousePos.x < curBtnX && IsUIMouseButtonPressed(.LEFT) {
		space.draggingPanelId = p.id
		space.dragOffset = {mousePos.x - p.panelRect.x, mousePos.y - p.panelRect.y}
		if p.slot != .Floating {
			p.prevSlot = p.slot
			p.slot = .Floating
			p.floatPos = {p.panelRect.x, p.panelRect.y}
			p.floatSize = {max(p.panelRect.width, 280.0), max(p.panelRect.height, 220.0)}
		}
	}

	return true, p.contentRect
}

DockSpace_EndPanel :: proc(space: ^DockSpace) {
	// Frame pop
}

DockSpace_RenderOverlays :: proc(space: ^DockSpace) {
	mousePos := GetUIMousePosition()

	// 1. Render Splitters with interactive hover indicators
	if space.leftSplitterRect.width > 0 {
		isHover := PointInRect(mousePos, space.leftSplitterRect) || space.draggingSplitter == .LeftSplitter
		spCol := space.accentColor if isHover else rl.Color{40, 48, 64, 255}
		rl.DrawRectangleRec(space.leftSplitterRect, spCol)
	}

	if space.rightSplitterRect.width > 0 {
		isHover := PointInRect(mousePos, space.rightSplitterRect) || space.draggingSplitter == .RightSplitter
		spCol := space.accentColor if isHover else rl.Color{40, 48, 64, 255}
		rl.DrawRectangleRec(space.rightSplitterRect, spCol)
	}

	if space.bottomSplitterRect.height > 0 {
		isHover := PointInRect(mousePos, space.bottomSplitterRect) || space.draggingSplitter == .BottomSplitter
		spCol := space.accentColor if isHover else rl.Color{40, 48, 64, 255}
		rl.DrawRectangleRec(space.bottomSplitterRect, spCol)
	}

	// 2. Render Drag & Drop Preview Zone Overlay
	if space.draggingPanelId != "" && space.dragHoverSlot != .None && space.dragHoverSlot != .Floating {
		// Translucent preview rectangle
		rl.DrawRectangleRec(space.dragPreviewRect, space.dropZoneColor)
		rl.DrawRectangleLinesEx(space.dragPreviewRect, 2, space.accentColor)

		targetName := "DOCK ZONE"
		#partial switch space.dragHoverSlot {
		case .Left:   targetName = "DOCK LEFT"
		case .Right:  targetName = "DOCK RIGHT"
		case .Bottom: targetName = "DOCK BOTTOM"
		case .Center: targetName = "DOCK CENTER (MAIN VIEWPORT)"
		}

		// If a panel is already docked in this slot, indicate that it will be moved!
		occupant := DockSpace_FindOccupant(space, space.dragHoverSlot, space.draggingPanelId)
		if occupant != nil {
			targetName = fmt.tprintf("%s (MOVES %s)", targetName, occupant.title)
		}

		cstr := fmt.ctprint(targetName)
		txtW := MeasureText(cstr, 14).x
		cx := space.dragPreviewRect.x + (space.dragPreviewRect.width - txtW) * 0.5
		cy := space.dragPreviewRect.y + (space.dragPreviewRect.height - 14) * 0.5

		rl.DrawRectangleRec({cx - 12, cy - 6, txtW + 24, 26}, rl.Color{20, 24, 34, 225})
		rl.DrawRectangleLinesEx({cx - 12, cy - 6, txtW + 24, 26}, 1, space.accentColor)
		DrawText(cstr, cx, cy, 14, rl.WHITE)
	}
}
