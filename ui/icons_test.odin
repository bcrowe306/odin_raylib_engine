package ui

import "core:testing"

@test
test_font_awesome_embedded_binary :: proc(t: ^testing.T) {
	// Verify that the Font Awesome Solid TTF file was embedded into binary via #load
	testing.expect(t, len(FA_SOLID_TTF) > 400_000, "Embedded Font Awesome TTF binary must be > 400 KB")
	testing.expect_value(t, len(ALL_ICON_CODEPOINTS), 1402)
}

@test
test_icon_enum_values :: proc(t: ^testing.T) {
	// Verify core Font Awesome icon Unicode codepoints
	testing.expect_value(t, rune(Icon.None), 0)
	testing.expect_value(t, rune(Icon.Play), 0xF04B)
	testing.expect_value(t, rune(Icon.Pause), 0xF04C)
	testing.expect_value(t, rune(Icon.Stop), 0xF04D)
	testing.expect_value(t, rune(Icon.Gear), 0xF013)
	testing.expect_value(t, rune(Icon.Settings), 0xF013)
	testing.expect_value(t, rune(Icon.FloppyDisk), 0xF0C7)
	testing.expect_value(t, rune(Icon.Save), 0xF0C7)
	testing.expect_value(t, rune(Icon.Rocket), 0xF135)
	testing.expect_value(t, rune(Icon.Wrench), 0xF0AD)
	testing.expect_value(t, rune(Icon.TriangleExclamation), 0xF071)
	testing.expect_value(t, rune(Icon.FolderOpen), 0xF07C)
	testing.expect_value(t, rune(Icon.Terminal), 0xF120)
}

@test
test_toolbar_item_structures :: proc(t: ^testing.T) {
	btn := ToolbarItem{
		id = 1,
		icon = .Rocket,
		label = "Launch",
		tooltip = "Launch Vessel",
		itemType = .Button,
	}
	testing.expect_value(t, btn.id, 1)
	testing.expect_value(t, btn.icon, Icon.Rocket)
	testing.expect_value(t, btn.label, "Launch")
	testing.expect_value(t, btn.itemType, ToolbarItemType.Button)

	toggle := ToolbarItem{
		id = 2,
		icon = .Play,
		itemType = .Toggle,
		isSelected = true,
	}
	testing.expect_value(t, toggle.isSelected, true)
	testing.expect_value(t, toggle.itemType, ToolbarItemType.Toggle)
}
