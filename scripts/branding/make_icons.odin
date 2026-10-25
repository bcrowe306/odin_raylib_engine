package make_icons

// Builds the editor's icons from branding/rayzr_icon_source.png (the logo
// on a dark squircle, square, no alpha):
//   editor/assets/icon.png        512, the squircle cut out (window icon,
//                                 Linux packages, Windows .ico)
//   editor/assets/icon_macos.png  1024, the same at 824 px with Apple's
//                                 margins (the .icns: sits right in the Dock)
//   editor/assets/icon.ico        16-256, PNG-encoded
//   editor/assets/icon.res        the same as a compiled Windows resource
//                                 (RT_ICON + RT_GROUP_ICON 1): the editor
//                                 .exe's icon (odin build -resource:...)
// Run: odin run scripts/branding/make_icons.odin -file
// The shape: a rounded square to the edges, each corner a superellipse
// |x/r|^n + |y/r|^n = 1 with r = 420/1568 of the size, n = 1.76 (fitted to
// the artwork's corners).

import "core:fmt"
import "core:math"
import "core:os"
import rl "vendor:raylib"

N :: 1.76
R :: 420.0 / 1568.0

cut :: proc(src: rl.Image, size: i32) -> rl.Image {
	img := rl.ImageCopy(src)
	rl.ImageResize(&img, size, size)
	rl.ImageFormat(&img, .UNCOMPRESSED_R8G8B8A8)
	px := ([^]rl.Color)(img.data)
	inset := 1.0 // (just inside the edge: no dark fringe)
	lo, hi := inset, f64(size) - inset
	r := R * f64(size)
	for y in 0 ..< size do for x in 0 ..< size {
		fx, fy := f64(x) + 0.5, f64(y) + 0.5
		// Distance into the corner region (0: not in a corner).
		dx := max(lo + r - fx, fx - (hi - r), 0)
		dy := max(lo + r - fy, fy - (hi - r), 0)
		alpha: f64
		if dx == 0 || dy == 0 {
			alpha = clamp(min(fx - lo, hi - fx, fy - lo, hi - fy) + 0.5, 0, 1)
		} else {
			f := math.pow(math.pow(dx / r, N) + math.pow(dy / r, N), 1.0 / N) // 1 on the edge
			alpha = clamp((1 - f) * r + 0.5, 0, 1)
		}
		c := &px[y * size + x]
		c.a = u8(f64(c.a) * alpha)
	}
	return img
}

main :: proc() {
	src := rl.LoadImage("branding/rayzr_icon_source.png")
	if src.data == nil {
		fmt.eprintln("branding/rayzr_icon_source.png not found (run from the repository root)")
		os.exit(1)
	}
	full := cut(src, 512)
	rl.ExportImage(full, "editor/assets/icon.png")

	// macOS: the shape at 824 of 1024 (Apple's icon grid).
	body := cut(src, 824)
	mac := rl.GenImageColor(1024, 1024, {0, 0, 0, 0})
	rl.ImageDraw(&mac, body, {0, 0, 824, 824}, {100, 100, 824, 824}, rl.WHITE)
	rl.ExportImage(mac, "editor/assets/icon_macos.png")

	// Windows: .ico with PNG entries.
	sizes := []i32{16, 24, 32, 48, 64, 128, 256}
	pngs := make([][]u8, len(sizes))
	for s, i in sizes {
		img := cut(src, s) if s >= 64 else cut_small(src, s)
		n: i32
		data := rl.ExportImageToMemory(img, ".png", &n)
		pngs[i] = ([^]u8)(data)[:n]
	}
	ico := make([dynamic]u8)
	put16 :: proc(b: ^[dynamic]u8, v: int) {append(b, u8(v), u8(v >> 8))}
	put32 :: proc(b: ^[dynamic]u8, v: int) {append(b, u8(v), u8(v >> 8), u8(v >> 16), u8(v >> 24))}
	put16(&ico, 0); put16(&ico, 1); put16(&ico, len(sizes))
	offset := 6 + 16 * len(sizes)
	for s, i in sizes {
		d := u8(0) if s >= 256 else u8(s)
		append(&ico, d, d, 0, 0)
		put16(&ico, 1); put16(&ico, 32)
		put32(&ico, len(pngs[i])); put32(&ico, offset)
		offset += len(pngs[i])
	}
	for p in pngs do append(&ico, ..p)
	_ = os.write_entire_file("editor/assets/icon.ico", ico[:])

	// .res: an empty first entry, one RT_ICON per image, the RT_GROUP_ICON.
	res := make([dynamic]u8)
	entry :: proc(b: ^[dynamic]u8, type, id: int, flags: int, data: []u8) {
		put16(b, 0); put16(b, 0) // (placeholder, patched below)
		pos := len(b) - 4
		v := len(data)
		b[pos], b[pos + 1], b[pos + 2], b[pos + 3] = u8(v), u8(v >> 8), u8(v >> 16), u8(v >> 24)
		put32(b, 32) // header size
		put16(b, 0xFFFF); put16(b, type)
		put16(b, 0xFFFF); put16(b, id)
		put32(b, 0) // data version
		put16(b, flags); put16(b, 0x0409 if type != 0 else 0)
		put32(b, 0); put32(b, 0) // version, characteristics
		append(b, ..data)
		for len(b) % 4 != 0 do append(b, 0)
	}
	entry(&res, 0, 0, 0, nil)
	for p, i in pngs do entry(&res, 3, i + 1, 0x1010, p) // RT_ICON
	group := make([dynamic]u8)
	put16(&group, 0); put16(&group, 1); put16(&group, len(sizes))
	for s, i in sizes {
		d := u8(0) if s >= 256 else u8(s)
		append(&group, d, d, 0, 0)
		put16(&group, 1); put16(&group, 32)
		put32(&group, len(pngs[i])); put16(&group, i + 1)
	}
	entry(&res, 14, 1, 0x1030, group[:]) // RT_GROUP_ICON
	_ = os.write_entire_file("editor/assets/icon.res", res[:])
	fmt.println("editor/assets/icon.png, icon_macos.png, icon.ico, icon.res")
}

// Small sizes: shrink from 4x (smoother than one big step).
cut_small :: proc(src: rl.Image, size: i32) -> rl.Image {
	big := cut(src, size * 4)
	rl.ImageResize(&big, size, size)
	return big
}
