package ui

import "core:math"
import rl "vendor:raylib"

// ============================================================================
// Modern Dynamic Flexbox Layout Engine for Immediate and Retained UI
// Compliant with standard CSS Flexible Box Layout concepts.
// ============================================================================

FlexDirection :: enum {
	Row,
	Column,
	RowReverse,
	ColumnReverse,
}

FlexJustify :: enum {
	FlexStart,
	Center,
	FlexEnd,
	SpaceBetween,
	SpaceAround,
	SpaceEvenly,
}

FlexAlign :: enum {
	Auto,
	FlexStart,
	Center,
	FlexEnd,
	Stretch,
}

FlexWrap :: enum {
	NoWrap,
	Wrap,
}

FlexItem :: struct {
	size:       [2]f32,
	grow:       f32,
	shrink:     f32,
	basis:      f32,
	minSize:    [2]f32,
	maxSize:    [2]f32,
	alignSelf:  FlexAlign,
	computed:   rl.Rectangle,
}

FlexContainer :: struct {
	bounds:     rl.Rectangle,
	direction:  FlexDirection,
	justify:    FlexJustify,
	align:      FlexAlign,
	wrap:       FlexWrap,
	gap:        f32,
	padding:    [4]f32, // top, right, bottom, left
}

// Low-level Flexbox Layout Solver
Flex_Solve :: proc(container: FlexContainer, items: []^FlexItem) {
	if len(items) == 0 do return

	isRow := (container.direction == .Row || container.direction == .RowReverse)
	isReverse := (container.direction == .RowReverse || container.direction == .ColumnReverse)

	innerX := container.bounds.x + container.padding[3]
	innerY := container.bounds.y + container.padding[0]
	innerW := max(container.bounds.width - container.padding[1] - container.padding[3], 0)
	innerH := max(container.bounds.height - container.padding[0] - container.padding[2], 0)

	mainAvail := innerW if isRow else innerH
	crossAvail := innerH if isRow else innerW

	count := len(items)
	totalGap := f32(max(count - 1, 0)) * container.gap

	// Pass 1: Collect base sizes, grow/shrink sums
	totalBasis: f32 = 0
	totalGrow: f32 = 0
	totalShrink: f32 = 0

	for item in items {
		baseSize := item.basis
		if baseSize <= 0.0 {
			baseSize = item.size.x if isRow else item.size.y
		}
		item.computed.width = item.size.x
		item.computed.height = item.size.y
		if isRow {
			item.computed.width = baseSize
		} else {
			item.computed.height = baseSize
		}

		totalBasis += baseSize
		totalGrow += item.grow
		totalShrink += item.shrink
	}

	remainingSpace := mainAvail - totalBasis - totalGap

	// Pass 2: Distribute remaining space via flex-grow or flex-shrink
	if remainingSpace > 0.001 && totalGrow > 0.0001 {
		for item in items {
			if item.grow > 0 {
				extra := (item.grow / totalGrow) * remainingSpace
				if isRow {
					item.computed.width += extra
					if item.maxSize.x > 0 do item.computed.width = min(item.computed.width, item.maxSize.x)
					if item.minSize.x > 0 do item.computed.width = max(item.computed.width, item.minSize.x)
				} else {
					item.computed.height += extra
					if item.maxSize.y > 0 do item.computed.height = min(item.computed.height, item.maxSize.y)
					if item.minSize.y > 0 do item.computed.height = max(item.computed.height, item.minSize.y)
				}
			}
		}
	} else if remainingSpace < -0.001 && totalShrink > 0.0001 {
		overflow := -remainingSpace
		for item in items {
			if item.shrink > 0 {
				reduction := (item.shrink / totalShrink) * overflow
				if isRow {
					item.computed.width = max(item.computed.width - reduction, max(item.minSize.x, 0))
				} else {
					item.computed.height = max(item.computed.height - reduction, max(item.minSize.y, 0))
				}
			}
		}
	}

	// Pass 3: Recompute final used main size and apply JustifyContent
	usedMain: f32 = 0
	for item in items {
		usedMain += item.computed.width if isRow else item.computed.height
	}
	usedMain += totalGap
	freeSpace := max(mainAvail - usedMain, 0)

	startMain: f32 = 0
	stepGap := container.gap

	switch container.justify {
	case .FlexStart:
		startMain = 0
	case .Center:
		startMain = freeSpace * 0.5
	case .FlexEnd:
		startMain = freeSpace
	case .SpaceBetween:
		startMain = 0
		if count > 1 {
			stepGap = container.gap + (freeSpace / f32(count - 1))
		}
	case .SpaceAround:
		if count > 0 {
			spaceUnit := freeSpace / f32(count)
			startMain = spaceUnit * 0.5
			stepGap = container.gap + spaceUnit
		}
	case .SpaceEvenly:
		if count > 0 {
			spaceUnit := freeSpace / f32(count + 1)
			startMain = spaceUnit
			stepGap = container.gap + spaceUnit
		}
	}

	// Pass 4: Position items along main axis and cross axis
	curMain := startMain
	for i in 0..<count {
		idx := (count - 1 - i) if isReverse else i
		item := items[idx]

		itemAlign := item.alignSelf if item.alignSelf != .Auto else container.align

		if isRow {
			item.computed.x = innerX + curMain
			// Cross-axis (Vertical)
			switch itemAlign {
			case .FlexStart, .Auto:
				item.computed.y = innerY
			case .Center:
				item.computed.y = innerY + (crossAvail - item.computed.height) * 0.5
			case .FlexEnd:
				item.computed.y = innerY + crossAvail - item.computed.height
			case .Stretch:
				item.computed.y = innerY
				item.computed.height = crossAvail
			}
			curMain += item.computed.width + stepGap
		} else {
			item.computed.y = innerY + curMain
			// Cross-axis (Horizontal)
			switch itemAlign {
			case .FlexStart, .Auto:
				item.computed.x = innerX
			case .Center:
				item.computed.x = innerX + (crossAvail - item.computed.width) * 0.5
			case .FlexEnd:
				item.computed.x = innerX + crossAvail - item.computed.width
			case .Stretch:
				item.computed.x = innerX
				item.computed.width = crossAvail
			}
			curMain += item.computed.height + stepGap
		}
	}
}

// ============================================================================
// Immediate-Mode Flexbox Layout Stack
// ============================================================================

MAX_FLEX_ITEMS :: 64
MAX_FLEX_DEPTH :: 8

ImmediateFlexContext :: struct {
	container:   FlexContainer,
	items:       [MAX_FLEX_ITEMS]FlexItem,
	itemPointers: [MAX_FLEX_ITEMS]^FlexItem,
	itemCount:   int,
	isSolved:    bool,
}

flexStack: [MAX_FLEX_DEPTH]ImmediateFlexContext
flexStackDepth: int = 0

// Begin a new Flexbox container scope
Flex_Begin :: proc(
	bounds: rl.Rectangle,
	direction: FlexDirection = .Row,
	gap: f32 = 8.0,
	justify: FlexJustify = .FlexStart,
	align: FlexAlign = .Center,
	padding: f32 = 0.0,
) -> bool {
	if flexStackDepth >= MAX_FLEX_DEPTH do return false

	ctx := &flexStack[flexStackDepth]
	flexStackDepth += 1

	ctx.container = FlexContainer{
		bounds = bounds,
		direction = direction,
		justify = justify,
		align = align,
		wrap = .NoWrap,
		gap = gap,
		padding = {padding, padding, padding, padding},
	}
	ctx.itemCount = 0
	ctx.isSolved = false

	return true
}

// Add an item specification to the active Flexbox container
Flex_AddItem :: proc(
	width, height: f32,
	grow: f32 = 0.0,
	shrink: f32 = 1.0,
	basis: f32 = 0.0,
	alignSelf: FlexAlign = .Auto,
) -> int {
	if flexStackDepth <= 0 do return -1
	ctx := &flexStack[flexStackDepth - 1]
	if ctx.itemCount >= MAX_FLEX_ITEMS do return -1

	idx := ctx.itemCount
	ctx.items[idx] = FlexItem{
		size = {width, height},
		grow = grow,
		shrink = shrink,
		basis = basis,
		alignSelf = alignSelf,
	}
	ctx.itemPointers[idx] = &ctx.items[idx]
	ctx.itemCount += 1
	return idx
}

// Solve the layout and pop the flex container from the stack
Flex_End :: proc() {
	if flexStackDepth <= 0 do return
	flexStackDepth -= 1
}

// Retrieve the calculated Rectangle for an added item index
Flex_GetRect :: proc(index: int) -> rl.Rectangle {
	if flexStackDepth <= 0 do return {}
	ctx := &flexStack[flexStackDepth - 1]
	if index < 0 || index >= ctx.itemCount do return {}

	if !ctx.isSolved {
		Flex_Solve(ctx.container, ctx.itemPointers[:ctx.itemCount])
		ctx.isSolved = true
	}

	return ctx.items[index].computed
}

// Convenience procedure: Calculate N equal proportional slots horizontally
Flex_RowSlots :: proc(bounds: rl.Rectangle, count: int, gap: f32 = 8.0) -> [dynamic]rl.Rectangle {
	res := make([dynamic]rl.Rectangle)
	if count <= 0 do return res

	totalGaps := f32(count - 1) * gap
	slotW := max((bounds.width - totalGaps) / f32(count), 1.0)

	for i in 0..<count {
		append(&res, rl.Rectangle{
			bounds.x + f32(i) * (slotW + gap),
			bounds.y,
			slotW,
			bounds.height,
		})
	}
	return res
}

// Convenience procedure: Calculate N equal proportional slots vertically
Flex_ColSlots :: proc(bounds: rl.Rectangle, count: int, gap: f32 = 8.0) -> [dynamic]rl.Rectangle {
	res := make([dynamic]rl.Rectangle)
	if count <= 0 do return res

	totalGaps := f32(count - 1) * gap
	slotH := max((bounds.height - totalGaps) / f32(count), 1.0)

	for i in 0..<count {
		append(&res, rl.Rectangle{
			bounds.x,
			bounds.y + f32(i) * (slotH + gap),
			bounds.width,
			slotH,
		})
	}
	return res
}
