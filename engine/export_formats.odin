package engine

import "core:c"
import "core:fmt"
import os "osx"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
import rl "vendor:raylib"

// ============================================================================
// File formats for exported games (no platform tools needed):
//   - icon images: a PNG resized to square sizes (padded, not stretched)
//   - Windows: .ico files, the RT_GROUP_ICON directory and the VERSIONINFO
//     resource the editor writes into the runner .exe
//   - Linux: an AppDir (AppRun, .desktop, icon, usr/bin/) - appimagetool
//     turns it into an .AppImage
// ============================================================================

Icon_Image :: struct {
	size: int,  // square side in pixels
	png:  []u8, // PNG-encoded
}

// Icon_Images resizes a PNG to each size (square: centred, transparent
// padding). Returns nil when the file can't be read.
Icon_Images :: proc(pngPath: string, sizes: []int, allocator := context.allocator) -> []Icon_Image {
	src := rl.LoadImage(strings.clone_to_cstring(pngPath, context.temp_allocator))
	if src.data == nil do return nil
	defer rl.UnloadImage(src)
	rl.ImageFormat(&src, .UNCOMPRESSED_R8G8B8A8)
	if src.width != src.height {
		side := max(src.width, src.height)
		rl.ImageResizeCanvas(&src, side, side, (side - src.width) / 2, (side - src.height) / 2, {0, 0, 0, 0})
	}
	out := make([dynamic]Icon_Image, allocator)
	for s in sizes {
		img := rl.ImageCopy(src)
		rl.ImageResize(&img, c.int(s), c.int(s))
		n: c.int
		data := rl.ExportImageToMemory(img, ".png", &n)
		rl.UnloadImage(img)
		if data == nil || n <= 0 do continue
		png := make([]u8, int(n), allocator)
		copy(png, ([^]u8)(data)[:n])
		rl.MemFree(data)
		append(&out, Icon_Image{s, png})
	}
	return out[:]
}

@(private = "file")
le16 :: proc(b: ^[dynamic]u8, v: int) {append(b, u8(v), u8(v >> 8))}
@(private = "file")
le32 :: proc(b: ^[dynamic]u8, v: u32) {append(b, u8(v), u8(v >> 8), u8(v >> 16), u8(v >> 24))}

// Ico_Write: an .ico file with PNG-encoded images (Windows Vista+).
Ico_Write :: proc(images: []Icon_Image, allocator := context.allocator) -> []u8 {
	b := make([dynamic]u8, allocator)
	le16(&b, 0) // reserved
	le16(&b, 1) // icon
	le16(&b, len(images))
	offset := 6 + 16 * len(images)
	for im in images {
		append(&b, u8(im.size if im.size < 256 else 0), u8(im.size if im.size < 256 else 0), 0, 0) // w, h (0 = 256), colours, reserved
		le16(&b, 1)  // planes
		le16(&b, 32) // bits per pixel
		le32(&b, u32(len(im.png)))
		le32(&b, u32(offset))
		offset += len(im.png)
	}
	for im in images do append(&b, ..im.png)
	return b[:]
}

// Ico_GroupDirectory: the RT_GROUP_ICON resource for images stored as
// RT_ICON resources with ids firstId, firstId+1, ...
Ico_GroupDirectory :: proc(images: []Icon_Image, firstId: int, allocator := context.allocator) -> []u8 {
	b := make([dynamic]u8, allocator)
	le16(&b, 0)
	le16(&b, 1)
	le16(&b, len(images))
	for im, i in images {
		append(&b, u8(im.size if im.size < 256 else 0), u8(im.size if im.size < 256 else 0), 0, 0)
		le16(&b, 1)
		le16(&b, 32)
		le32(&b, u32(len(im.png)))
		le16(&b, firstId + i)
	}
	return b[:]
}

// Version_Parse: "1.2.3[.4]" -> four numbers (missing parts are 0).
Version_Parse :: proc(v: string) -> [4]u16 {
	out: [4]u16
	parts := strings.split(v, ".", context.temp_allocator)
	for p, i in parts {
		if i >= 4 do break
		digits := p
		for ch, k in p do if ch < '0' || ch > '9' {digits = p[:k]; break}
		n, _ := strconv.parse_int(digits)
		out[i] = u16(clamp(n, 0, 65535))
	}
	return out
}

// VersionInfo_Resource builds a VS_VERSIONINFO resource (RT_VERSION):
// fixed file/product version and the usual strings (US English, Unicode).
VersionInfo_Resource :: proc(productName, description, version, exeName: string, allocator := context.allocator) -> []u8 {
	utf16z :: proc(b: ^[dynamic]u8, s: string) {
		for r in s {
			if r < 0x10000 {
				le16(b, int(r))
			} else {
				q := int(r) - 0x10000
				le16(b, 0xD800 + (q >> 10))
				le16(b, 0xDC00 + (q & 0x3FF))
			}
		}
		le16(b, 0)
	}
	pad4 :: proc(b: ^[dynamic]u8) {for len(b) % 4 != 0 do append(b, 0)}
	// node writes one block: wLength, wValueLength, wType, szKey, padding,
	// value, padding, children. Returns its bytes (length patched in).
	node :: proc(key: string, value: []u8, valueLen: int, isText: bool, children: [][]u8) -> []u8 {
		b := make([dynamic]u8, context.temp_allocator)
		le16(&b, 0) // length, patched below
		le16(&b, valueLen)
		le16(&b, 1 if isText else 0)
		utf16z(&b, key)
		pad4(&b)
		append(&b, ..value)
		for ch in children {
			pad4(&b)
			append(&b, ..ch)
		}
		n := len(b)
		b[0], b[1] = u8(n), u8(n >> 8)
		return b[:]
	}
	text :: proc(key, value: string) -> []u8 {
		v := make([dynamic]u8, context.temp_allocator)
		utf16z(&v, value)
		return node(key, v[:], len(v) / 2, true, nil)
	}

	ver := Version_Parse(version)
	fixed := make([dynamic]u8, context.temp_allocator)
	le32(&fixed, 0xFEEF04BD)                         // signature
	le32(&fixed, 0x00010000)                         // structure version
	ms := int(ver[0]) << 16 | int(ver[1])
	ls := int(ver[2]) << 16 | int(ver[3])
	le32(&fixed, u32(ms)); le32(&fixed, u32(ls))               // file version
	le32(&fixed, u32(ms)); le32(&fixed, u32(ls))               // product version
	le32(&fixed, 0x3F)                               // flags mask
	le32(&fixed, 0)                                  // flags
	le32(&fixed, 0x00040004)                         // VOS_NT_WINDOWS32
	le32(&fixed, 1)                                  // VFT_APP
	le32(&fixed, 0)                                  // subtype
	le32(&fixed, 0); le32(&fixed, 0)                 // date

	versionText := fmt.tprintf("%d.%d.%d.%d", ver[0], ver[1], ver[2], ver[3])
	strs := [][]u8{
		text("CompanyName", productName),
		text("FileDescription", description),
		text("FileVersion", versionText),
		text("InternalName", exeName),
		text("OriginalFilename", strings.concatenate({exeName, ".exe"}, context.temp_allocator)),
		text("ProductName", productName),
		text("ProductVersion", versionText),
	}
	table := node("040904B0", nil, 0, true, strs)
	stringInfo := node("StringFileInfo", nil, 0, true, {table})
	translation := make([dynamic]u8, context.temp_allocator)
	le16(&translation, 0x0409) // US English
	le16(&translation, 1200)   // Unicode
	varInfo := node("VarFileInfo", nil, 0, true, {node("Translation", translation[:], 4, false, nil)})
	root := node("VS_VERSION_INFO", fixed[:], len(fixed), false, {stringInfo, varInfo})
	out := make([]u8, len(root), allocator)
	copy(out, root)
	return out
}

// Linux_DesktopEntry: the AppDir's <name>.desktop.
Linux_DesktopEntry :: proc(displayName, exeName, comment: string) -> string {
	return fmt.tprintf("[Desktop Entry]\nType=Application\nName=%s\nExec=%s\nIcon=%s\nComment=%s\nCategories=Game;\nTerminal=false\n", displayName, exeName, exeName, comment)
}

// Linux_AppRun: the AppDir entry point (runs usr/bin/<exe>).
Linux_AppRun :: proc(exeName: string) -> string {
	return fmt.tprintf("#!/bin/sh\nHERE=\"$(dirname \"$(readlink -f \"$0\")\")\"\nexec \"$HERE/usr/bin/%s\" \"$@\"\n", exeName)
}

// Export_LinuxAppDir writes <dir>/<name>.AppDir: AppRun, <name>.desktop,
// <name>.png (+ .DirIcon), usr/bin/<name> (the runner), its libraries,
// game.ore and fonts/.
Export_LinuxAppDir :: proc(dir, name: string, cfg: ^ProjectConfig, runner: string, libs: []string, ore, font, iconPng: string) -> (string, bool) {
	appDir, _ := filepath.join({dir, strings.concatenate({name, ".AppDir"}, context.temp_allocator)}, context.temp_allocator)
	_ = os.remove_all(appDir)
	bin, _ := filepath.join({appDir, "usr", "bin"}, context.temp_allocator)
	if os.make_directory_all(bin) != nil do return "", false
	exe, _ := filepath.join({bin, name}, context.temp_allocator)
	if os.copy_file(exe, runner) != nil do return "", false
	_ = os.chmod(exe, os.Permissions_Default_File + os.Permissions_Execute_All)
	for lib in libs {
		dst, _ := filepath.join({bin, filepath.base(lib)}, context.temp_allocator)
		_ = os.copy_file(dst, lib)
	}
	dstOre, _ := filepath.join({bin, "game.ore"}, context.temp_allocator)
	if os.copy_file(dstOre, ore) != nil do return "", false
	if font != "" {
		fonts, _ := filepath.join({bin, "fonts"}, context.temp_allocator)
		_ = os.make_directory_all(fonts)
		dst, _ := filepath.join({fonts, filepath.base(font)}, context.temp_allocator)
		_ = os.copy_file(dst, font)
	}
	appRun, _ := filepath.join({appDir, "AppRun"}, context.temp_allocator)
	if os.write_entire_file(appRun, transmute([]u8)Linux_AppRun(name)) != nil do return "", false
	_ = os.chmod(appRun, os.Permissions_Default_File + os.Permissions_Execute_All)
	display := cfg.windowTitle if cfg.windowTitle != "" else cfg.name
	desktop, _ := filepath.join({appDir, strings.concatenate({name, ".desktop"}, context.temp_allocator)}, context.temp_allocator)
	_ = os.write_entire_file(desktop, transmute([]u8)Linux_DesktopEntry(display if display != "" else name, name, cfg.name))
	// appimagetool needs an icon named like the .desktop's Icon=.
	icon, _ := filepath.join({appDir, strings.concatenate({name, ".png"}, context.temp_allocator)}, context.temp_allocator)
	wrote := false
	if iconPng != "" {
		if imgs := Icon_Images(iconPng, {256}, context.temp_allocator); len(imgs) == 1 {
			wrote = os.write_entire_file(icon, imgs[0].png) == nil
		}
	}
	if !wrote {
		// A plain placeholder so the AppDir is complete.
		img := rl.GenImageColor(256, 256, {40, 44, 52, 255})
		defer rl.UnloadImage(img)
		n: c.int
		data := rl.ExportImageToMemory(img, ".png", &n)
		if data != nil {
			_ = os.write_entire_file(icon, ([^]u8)(data)[:n])
			rl.MemFree(data)
		}
	}
	dirIcon, _ := filepath.join({appDir, ".DirIcon"}, context.temp_allocator)
	_ = os.copy_file(dirIcon, icon)
	return strings.clone(appDir, context.temp_allocator), true
}
