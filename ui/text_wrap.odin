package ui

import "core:fmt"
import "core:math"
import "core:strings"
import rl "vendor:raylib"

// ============================================================================
// Rich Multi-Line Text Wrapping Engine & Wrapped Label Widget
// Supports whitespace-aware word wrapping, max-line ellipsis truncation,
// intrinsic height measurement, and dynamic layout pushing.
// ============================================================================

// Wrap text to fit within a given maximum width in pixels
WrapText :: proc(
	text: string,
	maxWidth: f32,
	fontSize: f32 = DEFAULT_FONT_SIZE,
	allocator := context.allocator,
) -> [dynamic]string {
	lines := make([dynamic]string, allocator)
	if len(text) == 0 do return lines

	// 1. Split text on physical newlines first
	rawParagraphs := strings.split(text, "\n", context.temp_allocator)

	for p in rawParagraphs {
		if len(p) == 0 {
			append(&lines, strings.clone("", allocator))
			continue
		}

		words := strings.split(p, " ", context.temp_allocator)
		curLine: strings.Builder
		strings.builder_init(&curLine, context.temp_allocator)

		for word in words {
			if len(word) == 0 do continue

			testLine := strings.to_string(curLine)
			candidate: string
			if len(testLine) == 0 {
				candidate = word
			} else {
				candidate = fmt.tprintf("%s %s", testLine, word)
			}

			measuredW := MeasureTextStr(candidate, fontSize).x

			if measuredW <= maxWidth || len(testLine) == 0 {
				if len(testLine) > 0 {
					strings.write_byte(&curLine, ' ')
				}
				strings.write_string(&curLine, word)
			} else {
				// Flush current line and start new one with this word
				append(&lines, strings.clone(strings.to_string(curLine), allocator))
				strings.builder_reset(&curLine)
				strings.write_string(&curLine, word)
			}
		}

		if strings.builder_len(curLine) > 0 {
			append(&lines, strings.clone(strings.to_string(curLine), allocator))
		}
	}

	return lines
}

// Wrap text and truncate with ellipsis if it exceeds maxLines
WrapTextWithEllipsis :: proc(
	text: string,
	maxWidth: f32,
	maxLines: int,
	fontSize: f32 = DEFAULT_FONT_SIZE,
	allocator := context.allocator,
) -> [dynamic]string {
	allLines := WrapText(text, maxWidth, fontSize, context.temp_allocator)
	res := make([dynamic]string, allocator)

	if maxLines <= 0 || len(allLines) <= maxLines {
		for l in allLines {
			append(&res, strings.clone(l, allocator))
		}
		return res
	}

	// Truncate at maxLines and append ellipsis to last line
	for i in 0..<(maxLines - 1) {
		append(&res, strings.clone(allLines[i], allocator))
	}

	lastLine := allLines[maxLines - 1]
	ellipsis := "..."
	for len(lastLine) > 0 && (MeasureTextStr(fmt.tprintf("%s%s", lastLine, ellipsis), fontSize).x > maxWidth) {
		lastLine = lastLine[:len(lastLine) - 1]
	}
	append(&res, strings.clone(fmt.tprintf("%s%s", lastLine, ellipsis), allocator))
	return res
}

// Measure intrinsic size of wrapped text block
MeasureTextWrapped :: proc(
	text: string,
	maxWidth: f32,
	fontSize: f32 = DEFAULT_FONT_SIZE,
	lineSpacing: f32 = 4.0,
) -> [2]f32 {
	if len(text) == 0 do return {0, fontSize}
	lines := WrapText(text, maxWidth, fontSize, context.temp_allocator)
	lineCount := max(len(lines), 1)

	maxW: f32 = 0
	for l in lines {
		w := MeasureTextStr(l, fontSize).x
		if w > maxW do maxW = w
	}

	totalH := f32(lineCount) * fontSize + f32(lineCount - 1) * lineSpacing
	return {maxW, totalH}
}

// Immediate-mode wrapped text label widget
// Renders wrapped lines and returns the total vertical height consumed.
GuiLabelWrapped :: proc(
	rect: rl.Rectangle,
	text: string,
	fontSize: f32 = DEFAULT_FONT_SIZE,
	color: rl.Color = {0, 0, 0, 0},
	lineSpacing: f32 = 4.0,
	maxLines: int = 0,
) -> (heightConsumed: f32) {
	if !rl.IsWindowReady() || len(text) == 0 do return 0

	t := GetTheme()
	txtColor := color if color.a > 0 else t.textPrimary

	lines := WrapTextWithEllipsis(text, rect.width, maxLines, fontSize, context.temp_allocator) if maxLines > 0 else WrapText(text, rect.width, fontSize, context.temp_allocator)
	if len(lines) == 0 do return 0

	curY := rect.y
	for line in lines {
		if curY + fontSize <= rect.y + rect.height || rect.height <= 0 {
			DrawTextStr(line, rect.x, curY, fontSize, txtColor)
		}
		curY += fontSize + lineSpacing
	}

	lineCount := len(lines)
	heightConsumed = f32(lineCount) * fontSize + f32(lineCount - 1) * lineSpacing
	return heightConsumed
}
