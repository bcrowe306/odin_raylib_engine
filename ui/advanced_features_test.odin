package ui

import "core:testing"
import rl "vendor:raylib"

@test
test_flexbox_row_solve :: proc(t: ^testing.T) {
	// Container: 500px wide, Row, gap 10px, 3 items with grow factors
	container := FlexContainer{
		bounds = {0, 0, 500, 100},
		direction = .Row,
		justify = .FlexStart,
		align = .Center,
		gap = 10,
	}

	item1 := FlexItem{size = {50, 40}, grow = 1.0}
	item2 := FlexItem{size = {50, 40}, grow = 2.0}
	item3 := FlexItem{size = {50, 40}, grow = 0.0}

	items := [3]^FlexItem{&item1, &item2, &item3}
	Flex_Solve(container, items[:])

	// Total basis: 150px, gap: 20px, free space: 500 - 170 = 330px
	// item1 grows by 1/3 * 330 = 110px -> 160px
	// item2 grows by 2/3 * 330 = 220px -> 270px
	// item3 grows by 0 -> 50px
	testing.expect_value(t, item1.computed.width, 160.0)
	testing.expect_value(t, item2.computed.width, 270.0)
	testing.expect_value(t, item3.computed.width, 50.0)

	// Verify X positions
	testing.expect_value(t, item1.computed.x, 0.0)
	testing.expect_value(t, item2.computed.x, 170.0)
	testing.expect_value(t, item3.computed.x, 450.0)

	// Cross-axis align Center in 100px height with 40px item -> y = 30px
	testing.expect_value(t, item1.computed.y, 30.0)
}

@test
test_flexbox_column_stretch :: proc(t: ^testing.T) {
	container := FlexContainer{
		bounds = {0, 0, 200, 400},
		direction = .Column,
		justify = .FlexStart,
		align = .Stretch,
		gap = 10,
	}

	item1 := FlexItem{size = {50, 50}, grow = 0.0}
	item2 := FlexItem{size = {50, 50}, grow = 1.0}

	items := [2]^FlexItem{&item1, &item2}
	Flex_Solve(container, items[:])

	// Stretch cross-axis -> width expands to 200px
	testing.expect_value(t, item1.computed.width, 200.0)
	testing.expect_value(t, item2.computed.width, 200.0)

	// Main axis: total height 400, gap 10, basis 100, free space 290
	// item1 stays 50px, item2 grows to 50 + 290 = 340px
	testing.expect_value(t, item1.computed.height, 50.0)
	testing.expect_value(t, item2.computed.height, 340.0)
	testing.expect_value(t, item2.computed.y, 60.0)
}

@test
test_text_wrap_words :: proc(t: ^testing.T) {
	sampleText := "The quick brown fox jumps over the lazy dog"
	// Wrap at narrow width 100px
	lines := WrapText(sampleText, 100.0, 16.0)
	defer {
		for l in lines do delete(l)
		delete(lines)
	}

	testing.expect(t, len(lines) > 2, "Expected multiple wrapped lines")
	// Verify words are preserved
	testing.expect(t, len(lines[0]) > 0, "Line 1 should contain words")
}

@test
test_text_wrap_ellipsis :: proc(t: ^testing.T) {
	sampleText := "First Line\nSecond Line\nThird Line\nFourth Line\nFifth Line"
	truncated := WrapTextWithEllipsis(sampleText, 300.0, 2, 16.0)
	defer {
		for l in truncated do delete(l)
		delete(truncated)
	}

	testing.expect_value(t, len(truncated), 2)
}

@test
test_native_dialog_headless_safety :: proc(t: ^testing.T) {
	// Enable test mode
	testHook.enabled = true
	path, ok := NativeDialog_OpenFile("Test Open")
	testing.expect_value(t, ok, false)
	testing.expect_value(t, path, "")

	savePath, saveOk := NativeDialog_SaveFile("Test Save")
	testing.expect_value(t, saveOk, false)
	testing.expect_value(t, savePath, "")

	msgOk := NativeDialog_MessageBox("Test", "Message")
	testing.expect_value(t, msgOk, true)
	testHook.enabled = false
}
