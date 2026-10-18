package ui

import "core:fmt"
import "core:math"
import "core:strings"
import rl "vendor:raylib"

// ============================================================================
// HTML-Inspired UI Widgets: Lists (<ul>, <ol>) & Tables (<table>)
// ============================================================================

// ----------------------------------------------------------------------------
// 1. Unordered List (<ul>) & Ordered List (<ol>) Types
// ----------------------------------------------------------------------------

BulletStyle :: enum {
	Disc,   // Solid bullet dot
	Circle, // Hollow circle
	Square, // Filled square
	Dash,   // En-dash '-'
	Arrow,  // Right chevron '>'
}

NumberingStyle :: enum {
	Decimal,    // 1., 2., 3.
	AlphaLower, // a., b., c.
	AlphaUpper, // A., B., C.
	RomanLower, // i., ii., iii.
	RomanUpper, // I., II., III.
}

ListItem :: struct {
	text:       string,
	depth:      int,             // Indentation level: 0 = root, 1 = nested, etc.
	bullet:     BulletStyle,     // Custom bullet override for UL
	number:     int,             // Custom number override for OL (if 0, auto-numbered)
	isHeader:   bool,            // Styled as a sub-header item
	badge:      string,          // Optional inline badge/pill tag (e.g. "[OK]")
	badgeColor: rl.Color,        // Badge text color
	badgeBg:    rl.Color,        // Badge background chip color
}

// ----------------------------------------------------------------------------
// 2. Table (<table>) Types
// ----------------------------------------------------------------------------

TableColumn :: struct {
	title:    string,
	width:    f32,        // <= 1.0: relative ratio of available width; > 1.0: fixed pixel width
	align:    Alignment,  // .Start (left), .Center, .End (right)
	sortable: bool,
}

TableCell :: struct {
	text:       string,
	color:      rl.Color,   // Custom text color (default light gray if alpha == 0)
	badge:      string,     // Optional badge tag (e.g. "ONLINE", "ACTIVE")
	badgeColor: rl.Color,
	badgeBg:    rl.Color,
}

TableRow :: struct {
	cells:      []TableCell,
	id:         int,        // Unique row ID for data binding
	isSelected: bool,
}

// ----------------------------------------------------------------------------
// Helper: Numbering Formatters for <ol>
// ----------------------------------------------------------------------------

FormatRomanNumeral :: proc(num: int, upper: bool) -> string {
	n := clamp(num, 1, 39)
	romans := [10]string{"", "i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix"}
	romansUpper := [10]string{"", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX"}
	tens := [4]string{"", "x", "xx", "xxx"}
	tensUpper := [4]string{"", "X", "XX", "XXX"}

	t := n / 10
	o := n % 10
	if upper {
		return fmt.tprintf("%s%s.", tensUpper[clamp(t, 0, 3)], romansUpper[clamp(o, 0, 9)])
	} else {
		return fmt.tprintf("%s%s.", tens[clamp(t, 0, 3)], romans[clamp(o, 0, 9)])
	}
}

FormatOrderedMarker :: proc(num: int, style: NumberingStyle, depth: int = 0) -> string {
	val := max(num, 1)
	switch style {
	case .Decimal:
		return fmt.tprintf("%d.", val)
	case .AlphaLower:
		ch := 'a' + u8((val - 1) % 26)
		return fmt.tprintf("%c.", ch)
	case .AlphaUpper:
		ch := 'A' + u8((val - 1) % 26)
		return fmt.tprintf("%c.", ch)
	case .RomanLower:
		return FormatRomanNumeral(val, false)
	case .RomanUpper:
		return FormatRomanNumeral(val, true)
	}
	return fmt.tprintf("%d.", val)
}

// ============================================================================
// 3. HTML Unordered List Widget (<ul>)
// ============================================================================

GuiUnorderedList :: proc(
	bounds: rl.Rectangle,
	items: []ListItem,
	selectedIndex: ^int = nil,
	scroll: ^rl.Vector2 = nil,
	defaultBullet: BulletStyle = .Disc,
	itemHeight: f32 = 24.0,
	idKey: uintptr = 0,
) -> (changed: bool, clickedIndex: int) {
	changed = false
	clickedIndex = -1
	if !rl.IsWindowReady() || len(items) == 0 do return

	key := idKey if idKey != 0 else uintptr(uint(u32(bounds.x * 1000)) ~ uint(u32(bounds.y * 1000)))
	ImmediateNav_RegisterFocusable(key, bounds)
	isFocused := ImmediateNav_IsFocused(key)

	mousePos := GetUIMousePosition()

	// Container frame background & border
	rl.DrawRectangleRec(bounds, rl.Color{20, 24, 32, 240})
	borderCol := rl.Color{96, 165, 250, 255} if isFocused else rl.Color{45, 52, 70, 255}
	rl.DrawRectangleLinesEx(bounds, 1, borderCol)

	// Scroll Panel setup
	contentH := f32(len(items)) * itemHeight + 12.0
	contentRect := rl.Rectangle{0, 0, bounds.width - 16, contentH}
	viewRect := rl.Rectangle{}

	localScroll := rl.Vector2{0, 0}
	scrPtr := scroll if scroll != nil else &localScroll

	GuiScrollPanel(bounds, nil, contentRect, scrPtr, &viewRect)
	BeginClipRect(viewRect)
	defer EndClipRect()

	inView := PointInRect(mousePos, viewRect)

	// Keyboard arrow navigation
	if isFocused && selectedIndex != nil && len(items) > 0 {
		if IsUIKeyPressed(.UP) {
			newIdx := max(selectedIndex^ - 1, 0)
			if newIdx != selectedIndex^ {
				selectedIndex^ = newIdx
				changed = true
			}
		} else if IsUIKeyPressed(.DOWN) {
			newIdx := min(selectedIndex^ + 1, len(items) - 1)
			if newIdx != selectedIndex^ {
				selectedIndex^ = newIdx
				changed = true
			}
		}
	}

	for i in 0..<len(items) {
		item := items[i]
		rowY := viewRect.y + scrPtr.y + 6.0 + f32(i) * itemHeight
		if rowY + itemHeight < viewRect.y || rowY > viewRect.y + viewRect.height do continue

		rowRect := rl.Rectangle{viewRect.x + 4, rowY, viewRect.width - 8, itemHeight}
		isHovered := inView && PointInRect(mousePos, rowRect)
		isSel := (selectedIndex != nil && selectedIndex^ == i)

		// Interaction
		if isHovered && IsUIMouseButtonPressed(.LEFT) {
			ImmediateNav_SetFocus(key)
			clickedIndex = i
			if selectedIndex != nil && selectedIndex^ != i {
				selectedIndex^ = i
				changed = true
			}
		}

		// Row background
		if isSel {
			rl.DrawRectangleRec(rowRect, rl.Color{45, 90, 180, 200})
		} else if isHovered {
			rl.DrawRectangleRec(rowRect, rl.Color{32, 38, 52, 255})
		}

		// Indentation & Marker
		indent := f32(item.depth) * 20.0 + 12.0
		markerX := rowRect.x + indent
		centerY := rowRect.y + rowRect.height * 0.5

		bullet := item.bullet if item.bullet != .Disc else defaultBullet

		// Draw HTML Bullet Graphic
		markerCol := rl.Color{96, 165, 250, 255} if isSel else rl.Color{160, 175, 205, 255}
		switch bullet {
		case .Disc:
			rl.DrawCircle(i32(markerX + 4), i32(centerY), 3, markerCol)
		case .Circle:
			rl.DrawCircleLines(i32(markerX + 4), i32(centerY), 3.5, markerCol)
		case .Square:
			rl.DrawRectangleRec({markerX + 1, centerY - 3, 6, 6}, markerCol)
		case .Dash:
			rl.DrawLineEx({markerX + 1, centerY}, {markerX + 8, centerY}, 1.5, markerCol)
		case .Arrow:
			rl.DrawLineEx({markerX + 2, centerY - 4}, {markerX + 6, centerY}, 1.5, markerCol)
			rl.DrawLineEx({markerX + 6, centerY}, {markerX + 2, centerY + 4}, 1.5, markerCol)
		}

		// Text label
		textX := markerX + 16.0
		textCol := rl.WHITE if isSel else (rl.Color{235, 240, 250, 255} if item.isHeader else rl.Color{205, 212, 228, 255})
		fontSize: f32 = 13.0 if !item.isHeader else 14
		DrawTextStr(item.text, textX, centerY - 6, fontSize, textCol)

		// Optional Badge / Chip Tag
		if item.badge != "" {
			badgeW := MeasureTextStr(item.badge, 10).x + 10.0
			badgeX := rowRect.x + rowRect.width - badgeW - 8.0
			badgeRect := rl.Rectangle{badgeX, centerY - 8, badgeW, 16}

			bBg := item.badgeBg if item.badgeBg.a > 0 else rl.Color{35, 45, 65, 255}
			bCol := item.badgeColor if item.badgeColor.a > 0 else rl.Color{52, 211, 153, 255}

			rl.DrawRectangleRec(badgeRect, bBg)
			rl.DrawRectangleLinesEx(badgeRect, 1, bCol)
			DrawTextStr(item.badge, badgeRect.x + 5, badgeRect.y + 2, 10, bCol)
		}
	}

	if isFocused {
		RenderFocusRing(bounds, true, 2.0)
	}

	return changed, clickedIndex
}

// ============================================================================
// 4. HTML Ordered List Widget (<ol>)
// ============================================================================

GuiOrderedList :: proc(
	bounds: rl.Rectangle,
	items: []ListItem,
	selectedIndex: ^int = nil,
	scroll: ^rl.Vector2 = nil,
	numbering: NumberingStyle = .Decimal,
	startNumber: int = 1,
	itemHeight: f32 = 24.0,
	idKey: uintptr = 0,
) -> (changed: bool, clickedIndex: int) {
	changed = false
	clickedIndex = -1
	if !rl.IsWindowReady() || len(items) == 0 do return

	key := idKey if idKey != 0 else uintptr(uint(u32(bounds.x * 1000)) ~ uint(u32(bounds.y * 1000)))
	ImmediateNav_RegisterFocusable(key, bounds)
	isFocused := ImmediateNav_IsFocused(key)

	mousePos := GetUIMousePosition()

	// Container frame background & border
	rl.DrawRectangleRec(bounds, rl.Color{20, 24, 32, 240})
	borderCol := rl.Color{96, 165, 250, 255} if isFocused else rl.Color{45, 52, 70, 255}
	rl.DrawRectangleLinesEx(bounds, 1, borderCol)

	// Scroll Panel setup
	contentH := f32(len(items)) * itemHeight + 12.0
	contentRect := rl.Rectangle{0, 0, bounds.width - 16, contentH}
	viewRect := rl.Rectangle{}

	localScroll := rl.Vector2{0, 0}
	scrPtr := scroll if scroll != nil else &localScroll

	GuiScrollPanel(bounds, nil, contentRect, scrPtr, &viewRect)
	BeginClipRect(viewRect)
	defer EndClipRect()

	inView := PointInRect(mousePos, viewRect)

	// Keyboard arrow navigation
	if isFocused && selectedIndex != nil && len(items) > 0 {
		if IsUIKeyPressed(.UP) {
			newIdx := max(selectedIndex^ - 1, 0)
			if newIdx != selectedIndex^ {
				selectedIndex^ = newIdx
				changed = true
			}
		} else if IsUIKeyPressed(.DOWN) {
			newIdx := min(selectedIndex^ + 1, len(items) - 1)
			if newIdx != selectedIndex^ {
				selectedIndex^ = newIdx
				changed = true
			}
		}
	}

	counter := startNumber
	for i in 0..<len(items) {
		item := items[i]
		rowY := viewRect.y + scrPtr.y + 6.0 + f32(i) * itemHeight
		if rowY + itemHeight < viewRect.y || rowY > viewRect.y + viewRect.height do continue

		rowRect := rl.Rectangle{viewRect.x + 4, rowY, viewRect.width - 8, itemHeight}
		isHovered := inView && PointInRect(mousePos, rowRect)
		isSel := (selectedIndex != nil && selectedIndex^ == i)

		// Interaction
		if isHovered && IsUIMouseButtonPressed(.LEFT) {
			ImmediateNav_SetFocus(key)
			clickedIndex = i
			if selectedIndex != nil && selectedIndex^ != i {
				selectedIndex^ = i
				changed = true
			}
		}

		// Row background
		if isSel {
			rl.DrawRectangleRec(rowRect, rl.Color{45, 90, 180, 200})
		} else if isHovered {
			rl.DrawRectangleRec(rowRect, rl.Color{32, 38, 52, 255})
		}

		// Indentation & Marker
		indent := f32(item.depth) * 20.0 + 12.0
		markerX := rowRect.x + indent
		centerY := rowRect.y + rowRect.height * 0.5

		// Determine list number
		numVal := item.number if item.number > 0 else counter
		if !item.isHeader do counter += 1

		markerStr := FormatOrderedMarker(numVal, numbering, item.depth)
		markerCol := rl.Color{96, 165, 250, 255} if isSel else rl.Color{160, 175, 205, 255}

		// Draw ordered marker
		markerW := MeasureTextStr(markerStr, 12).x
		DrawTextStr(markerStr, markerX, centerY - 6, 12, markerCol)

		// Text label
		textX := markerX + markerW + 8.0
		textCol := rl.WHITE if isSel else (rl.Color{235, 240, 250, 255} if item.isHeader else rl.Color{205, 212, 228, 255})
		fontSize: f32 = 13.0 if !item.isHeader else 14
		DrawTextStr(item.text, textX, centerY - 6, fontSize, textCol)

		// Optional Badge / Chip Tag
		if item.badge != "" {
			badgeW := MeasureTextStr(item.badge, 10).x + 10.0
			badgeX := rowRect.x + rowRect.width - badgeW - 8.0
			badgeRect := rl.Rectangle{badgeX, centerY - 8, badgeW, 16}

			bBg := item.badgeBg if item.badgeBg.a > 0 else rl.Color{35, 45, 65, 255}
			bCol := item.badgeColor if item.badgeColor.a > 0 else rl.Color{52, 211, 153, 255}

			rl.DrawRectangleRec(badgeRect, bBg)
			rl.DrawRectangleLinesEx(badgeRect, 1, bCol)
			DrawTextStr(item.badge, badgeRect.x + 5, badgeRect.y + 2, 10, bCol)
		}
	}

	if isFocused {
		RenderFocusRing(bounds, true, 2.0)
	}

	return changed, clickedIndex
}

// ============================================================================
// 5. HTML Table Widget (<table>) with <thead>, <tbody>, Sorting & Selection
// ============================================================================

GuiTable :: proc(
	bounds: rl.Rectangle,
	columns: []TableColumn,
	rows: []TableRow,
	selectedRow: ^int = nil,
	sortColumn: ^int = nil,
	sortAscending: ^bool = nil,
	scroll: ^rl.Vector2 = nil,
	headerHeight: f32 = 30.0,
	rowHeight: f32 = 26.0,
	idKey: uintptr = 0,
) -> (rowClicked: int, headerClicked: int) {
	rowClicked = -1
	headerClicked = -1
	if !rl.IsWindowReady() || len(columns) == 0 do return

	key := idKey if idKey != 0 else uintptr(uint(u32(bounds.x * 1000)) ~ uint(u32(bounds.y * 1000)))
	ImmediateNav_RegisterFocusable(key, bounds)
	isFocused := ImmediateNav_IsFocused(key)

	mousePos := GetUIMousePosition()

	// Outer Table Frame
	rl.DrawRectangleRec(bounds, rl.Color{20, 24, 32, 245})
	borderCol := rl.Color{96, 165, 250, 255} if isFocused else rl.Color{48, 56, 75, 255}
	rl.DrawRectangleLinesEx(bounds, 1, borderCol)

	// 1. Calculate concrete pixel widths for each column
	colWidths: [32]f32
	colCount := min(len(columns), 32)

	fixedW: f32 = 0
	relRatioSum: f32 = 0
	for i in 0..<colCount {
		w := columns[i].width
		if w > 1.0 {
			colWidths[i] = w
			fixedW += w
		} else {
			relRatioSum += max(w, 0.05)
		}
	}

	availW := max(bounds.width - fixedW - 14.0, 40.0) // 14px reserved for scrollbar
	for i in 0..<colCount {
		if columns[i].width <= 1.0 {
			ratio := max(columns[i].width, 0.05) / max(relRatioSum, 0.001)
			colWidths[i] = math.round(availW * ratio)
		}
	}

	// 2. Render <thead> Header Row
	headerRect := rl.Rectangle{bounds.x, bounds.y, bounds.width, headerHeight}
	rl.DrawRectangleRec(headerRect, rl.Color{28, 33, 44, 255})
	rl.DrawLineEx({bounds.x, bounds.y + headerHeight}, {bounds.x + bounds.width, bounds.y + headerHeight}, 1, rl.Color{55, 65, 88, 255})

	colX := bounds.x
	for i in 0..<colCount {
		col := columns[i]
		cw := colWidths[i]
		cRect := rl.Rectangle{colX, bounds.y, cw, headerHeight}

		isHdrHover := PointInRect(mousePos, cRect)
		if isHdrHover && col.sortable {
			rl.DrawRectangleRec(cRect, rl.Color{38, 46, 62, 255})
			if IsUIMouseButtonPressed(.LEFT) {
				headerClicked = i
				if sortColumn != nil {
					if sortColumn^ == i && sortAscending != nil {
						sortAscending^ = !sortAscending^
					} else {
						sortColumn^ = i
						if sortAscending != nil do sortAscending^ = true
					}
				}
			}
		}

		// Vertical divider line between column headers
		if i > 0 {
			rl.DrawLineEx({colX, bounds.y + 4}, {colX, bounds.y + headerHeight - 4}, 1, rl.Color{48, 56, 75, 255})
		}

		// Header title text
		titleW := MeasureTextStr(col.title, 12).x
		txtX := colX + 8.0
		switch col.align {
		case .Start:
			txtX = colX + 8.0
		case .Center:
			txtX = colX + (cw - titleW) * 0.5
		case .End, .Stretch:
			txtX = colX + cw - titleW - 12.0
		}

		DrawTextStr(col.title, txtX, bounds.y + (headerHeight - 12) * 0.5, 12, rl.Color{230, 235, 248, 255})

		// Sort Indicator (▲ / ▼)
		if sortColumn != nil && sortColumn^ == i {
			isAsc := sortAscending^ if sortAscending != nil else true
			sortIcon := "^" if isAsc else "v"
			DrawTextStr(sortIcon, colX + cw - 14, bounds.y + (headerHeight - 11) * 0.5, 11, rl.Color{59, 130, 246, 255})
		}

		colX += cw
	}

	// 3. Render <tbody> Table Body with ScrollPanel & Zebra Striping
	bodyY := bounds.y + headerHeight
	bodyH := max(bounds.height - headerHeight, 10.0)
	bodyRect := rl.Rectangle{bounds.x, bodyY, bounds.width, bodyH}

	totalRowsH := f32(len(rows)) * rowHeight
	contentRect := rl.Rectangle{0, 0, bounds.width - 14, totalRowsH}
	viewRect := rl.Rectangle{}

	localScroll := rl.Vector2{0, 0}
	scrPtr := scroll if scroll != nil else &localScroll

	GuiScrollPanel(bodyRect, nil, contentRect, scrPtr, &viewRect)
	BeginClipRect(viewRect)
	defer EndClipRect()

	inBody := PointInRect(mousePos, viewRect)

	// Keyboard arrow navigation
	if isFocused && selectedRow != nil && len(rows) > 0 {
		if IsUIKeyPressed(.UP) {
			selectedRow^ = max(selectedRow^ - 1, 0)
		} else if IsUIKeyPressed(.DOWN) {
			selectedRow^ = min(selectedRow^ + 1, len(rows) - 1)
		}
	}

	for r := 0; r < len(rows); r += 1 {
		row := rows[r]
		rowY := viewRect.y + scrPtr.y + f32(r) * rowHeight
		if rowY + rowHeight < viewRect.y || rowY > viewRect.y + viewRect.height do continue

		rowRect := rl.Rectangle{viewRect.x, rowY, viewRect.width, rowHeight}
		isRowHovered := inBody && PointInRect(mousePos, rowRect)
		isRowSel := (selectedRow != nil && selectedRow^ == r)

		if isRowHovered && IsUIMouseButtonPressed(.LEFT) {
			ImmediateNav_SetFocus(key)
			rowClicked = r
			if selectedRow != nil do selectedRow^ = r
		}

		// Zebra Striping row backgrounds
		if isRowSel {
			rl.DrawRectangleRec(rowRect, rl.Color{45, 90, 180, 200})
		} else if isRowHovered {
			rl.DrawRectangleRec(rowRect, rl.Color{36, 42, 58, 255})
		} else if r % 2 == 1 {
			rl.DrawRectangleRec(rowRect, rl.Color{24, 28, 38, 200})
		}

		// Horizontal row divider line
		rl.DrawLineEx({viewRect.x, rowY + rowHeight}, {viewRect.x + viewRect.width, rowY + rowHeight}, 1, rl.Color{38, 44, 60, 180})

		// Render each cell in row
		cellColX := viewRect.x
		for c := 0; c < min(len(row.cells), colCount); c += 1 {
			cell := row.cells[c]
			cw := colWidths[c]
			cRect := rl.Rectangle{cellColX, rowY, cw, rowHeight}

			centerY := rowY + (rowHeight - 12) * 0.5

			// Vertical grid line between cells
			if c > 0 {
				rl.DrawLineEx({cellColX, rowY}, {cellColX, rowY + rowHeight}, 1, rl.Color{38, 44, 60, 140})
			}

			// Render Badge if present
			if cell.badge != "" {
				badgeW := MeasureTextStr(cell.badge, 10).x + 10.0
				badgeX := cellColX + 8.0
				if columns[c].align == .Center {
					badgeX = cellColX + (cw - badgeW) * 0.5
				} else if columns[c].align == .End {
					badgeX = cellColX + cw - badgeW - 8.0
				}
				bRect := rl.Rectangle{badgeX, rowY + (rowHeight - 16) * 0.5, badgeW, 16}

				bBg := cell.badgeBg if cell.badgeBg.a > 0 else rl.Color{28, 36, 52, 255}
				bCol := cell.badgeColor if cell.badgeColor.a > 0 else rl.Color{52, 211, 153, 255}

				rl.DrawRectangleRec(bRect, bBg)
				rl.DrawRectangleLinesEx(bRect, 1, bCol)
				DrawTextStr(cell.badge, bRect.x + 5, bRect.y + 2, 10, bCol)
			} else if cell.text != "" {
				txtCol := rl.WHITE if isRowSel else (cell.color if cell.color.a > 0 else rl.Color{210, 216, 230, 255})
				txtW := MeasureTextStr(cell.text, 12).x

				txtX := cellColX + 8.0
				switch columns[c].align {
				case .Start:
					txtX = cellColX + 8.0
				case .Center:
					txtX = cellColX + (cw - txtW) * 0.5
				case .End, .Stretch:
					txtX = cellColX + cw - txtW - 10.0
				}
				DrawTextStr(cell.text, txtX, centerY, 12, txtCol)
			}

			cellColX += cw
		}
	}

	if isFocused {
		RenderFocusRing(bounds, true, 2.0)
	}

	return rowClicked, headerClicked
}
