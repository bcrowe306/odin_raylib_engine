package engine

import os "osx"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import rl "vendor:raylib"

@(private = "file")
rd16 :: proc(b: []u8, at: int) -> int {return int(b[at]) | int(b[at + 1]) << 8}
@(private = "file")
rd32 :: proc(b: []u8, at: int) -> int {return rd16(b, at) | rd16(b, at + 2) << 16}

@(private = "file")
utf16_contains :: proc(b: []u8, s: string) -> bool {
	w := make([dynamic]u8, context.temp_allocator)
	for r in s do append(&w, u8(r), 0)
	return strings.contains(string(b), string(w[:]))
}

@(test)
test_export_formats :: proc(t: ^testing.T) {
	dir, _ := filepath.join({Engine_TempDir(), "ore_export_formats"}, context.temp_allocator)
	_ = os.remove_all(dir)
	_ = os.make_directory_all(dir)
	defer os.remove_all(dir)

	// A non-square source icon.
	png, _ := filepath.join({dir, "icon.png"}, context.temp_allocator)
	img := rl.GenImageColor(40, 20, {255, 0, 0, 255})
	rl.ExportImage(img, strings.clone_to_cstring(png, context.temp_allocator))
	rl.UnloadImage(img)

	images := Icon_Images(png, {16, 32, 256}, context.temp_allocator)
	testing.expect_value(t, len(images), 3)
	if len(images) != 3 do return
	// Square output: decode one back.
	back := rl.LoadImageFromMemory(".png", raw_data(images[1].png), i32(len(images[1].png)))
	testing.expect(t, back.width == 32 && back.height == 32, "resized to a square")
	rl.UnloadImage(back)

	// .ico: header, directory (256 written as 0), PNG data at the offsets.
	ico := Ico_Write(images, context.temp_allocator)
	testing.expect_value(t, rd16(ico, 2), 1)
	testing.expect_value(t, rd16(ico, 4), 3)
	testing.expect_value(t, ico[6 + 32], 0) // third entry: 256 -> 0
	off := rd32(ico, 6 + 32 + 12)
	testing.expect_value(t, rd32(ico, 6 + 32 + 8), len(images[2].png))
	testing.expect(t, string(ico[off + 1:off + 4]) == "PNG", "PNG data at the third entry's offset")
	grp := Ico_GroupDirectory(images, 1, context.temp_allocator)
	testing.expect_value(t, len(grp), 6 + 14 * 3)
	testing.expect_value(t, rd16(grp, 6 + 14 * 2 + 12), 3) // third image is RT_ICON id 3

	// VERSIONINFO: lengths add up, fixed info signature and strings present.
	testing.expect_value(t, Version_Parse("1.2.3"), [4]u16{1, 2, 3, 0})
	testing.expect_value(t, Version_Parse("2.0-beta"), [4]u16{2, 0, 0, 0})
	vi := VersionInfo_Resource("Space Game", "Space Game!", "1.2.3", "SpaceGame", context.temp_allocator)
	testing.expect_value(t, rd16(vi, 0), len(vi))
	testing.expect_value(t, rd16(vi, 2), 52) // sizeof(VS_FIXEDFILEINFO)
	// "VS_VERSION_INFO" + null = 32 bytes after the 6-byte header -> 38, padded to 40.
	testing.expect_value(t, rd32(vi, 40), 0xFEEF04BD)
	testing.expect_value(t, rd32(vi, 48), 1 << 16 | 2) // file version MS
	testing.expect_value(t, rd32(vi, 52), 3 << 16)     // file version LS
	testing.expect(t, utf16_contains(vi, "StringFileInfo") && utf16_contains(vi, "ProductName") && utf16_contains(vi, "SpaceGame.exe") && utf16_contains(vi, "1.2.3.0"), "strings")
	testing.expect(t, utf16_contains(vi, "Translation"), "VarFileInfo")
	// Every child block's length fits inside the root.
	at := 40 + 52
	for at < len(vi) {
		for at % 4 != 0 do at += 1
		if at >= len(vi) do break
		n := rd16(vi, at)
		testing.expectf(t, n > 0 && at + n <= len(vi), "child at %d has length %d (total %d)", at, n, len(vi))
		if n == 0 do break
		at += n
	}

	// Linux AppDir from a (fake) runner.
	runner, _ := filepath.join({dir, "runner"}, context.temp_allocator)
	_ = os.write_entire_file(runner, transmute([]u8)string("#!/bin/sh\necho runner\n"))
	ore, _ := filepath.join({dir, "game.ore"}, context.temp_allocator)
	_ = os.write_entire_file(ore, transmute([]u8)string("ORE"))
	cfg := ProjectConfig{name = "Space Game", windowTitle = "Space Game!"}
	appDir, ok := Export_LinuxAppDir(dir, "SpaceGame", &cfg, runner, nil, ore, "", png)
	testing.expect(t, ok, "AppDir written")
	check :: proc(t: ^testing.T, appDir: string, rel: string) -> string {
		p, _ := filepath.join({appDir, rel}, context.temp_allocator)
		data, err := os.read_entire_file(p, context.temp_allocator)
		testing.expectf(t, err == nil, "%s exists", rel)
		return string(data)
	}
	testing.expect(t, strings.contains(check(t, appDir, "AppRun"), `exec "$HERE/usr/bin/SpaceGame" "$@"`), "AppRun runs the game")
	desktop := check(t, appDir, "SpaceGame.desktop")
	testing.expect(t, strings.contains(desktop, "Name=Space Game!\n") && strings.contains(desktop, "Exec=SpaceGame\n") && strings.contains(desktop, "Icon=SpaceGame\n"), desktop)
	testing.expect(t, strings.has_prefix(check(t, appDir, "SpaceGame.png")[1:], "PNG"), "icon")
	testing.expect_value(t, check(t, appDir, "usr/bin/game.ore"), "ORE")
	_ = check(t, appDir, "usr/bin/SpaceGame")
	appRun, _ := filepath.join({appDir, "AppRun"}, context.temp_allocator)
	if info, err := os.stat(appRun, context.temp_allocator); err == nil {
		testing.expect(t, .Execute_User in info.mode, "AppRun is executable")
	}
}
