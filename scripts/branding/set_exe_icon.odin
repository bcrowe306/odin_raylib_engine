package set_exe_icon

// Writes the editor's icon (editor/assets/icon.ico, made by make_icons.odin)
// into a Windows .exe - after linking: raylib's Windows library carries its
// own resource, and the linker takes only one (-resource fails with
// LNK1241). Windows only (the Win32 resource update API, editor/winres).
//   odin run scripts/branding/set_exe_icon.odin -file -- <exe> [icon.ico]

import "core:fmt"
import "core:os"
import winres "../../editor/winres"

main :: proc() {
	if len(os.args) < 2 {
		fmt.eprintln("usage: set_exe_icon <exe> [icon.ico]")
		os.exit(2)
	}
	exe := os.args[1]
	icoPath := os.args[2] if len(os.args) > 2 else "editor/assets/icon.ico"
	ico, err := os.read_entire_file(icoPath, context.allocator)
	if err != nil || len(ico) < 6 {
		fmt.eprintln("can't read", icoPath)
		os.exit(1)
	}
	u16le :: proc(b: []u8, at: int) -> int {return int(b[at]) | int(b[at + 1]) << 8}
	u32le :: proc(b: []u8, at: int) -> int {return u16le(b, at) | u16le(b, at + 2) << 16}
	count := u16le(ico, 4)
	// The .ico directory (16-byte entries, data offsets) becomes the
	// RT_GROUP_ICON directory (14-byte entries, resource ids 1..n).
	images := make([][]u8, count)
	group := make([dynamic]u8)
	append(&group, 0, 0, 1, 0, u8(count), u8(count >> 8))
	for i in 0 ..< count {
		e := 6 + 16 * i
		size, offset := u32le(ico, e + 8), u32le(ico, e + 12)
		images[i] = ico[offset:][:size]
		append(&group, ..ico[e:][:12]) // width, height, colours, reserved, planes, bit count, size
		append(&group, u8(i + 1), u8((i + 1) >> 8))
	}
	if !winres.Update(exe, images, group[:], nil) {
		fmt.eprintln("couldn't write the icon into", exe, "(Windows only)")
		os.exit(1)
	}
	fmt.printfln("%s: icon from %s (%d images)", exe, icoPath, count)
}
