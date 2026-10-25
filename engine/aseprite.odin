package engine

import "core:bytes"
import "core:compress/zlib"
import "core:fmt"
import "core:mem"
import vmem "core:mem/virtual"
import "core:strings"

// ============================================================================
// Aseprite files (.aseprite / .ase), read directly (TODO E.3). The format:
// aseprite/docs/ase-file-specs.md (the aseprite/ submodule). Every chunk is
// read: layers (image / group / tilemap, flags incl. background and
// reference, blend mode, opacity, UUIDs), cels (raw, linked, compressed,
// compressed tilemap; opacity, z-index, extra / precise bounds), tags
// (direction, repeats, colour), palettes (new + old FLI chunks, names),
// user data (text, colour, typed properties incl. vectors and nested maps,
// extension property maps) on the sprite / layers / cels / tags / slices /
// tilesets / tiles, slices (per-frame keys, 9-patch centre, pivot),
// tilesets (embedded image, external link, flags), the colour profile,
// external files, the old mask chunk. aseprite_render.odin composites
// frames like Aseprite does; aseprite_node.odin plays them.
//
// A document owns all its memory (one arena): Ase_Destroy frees it.
// ============================================================================

Ase_Depth :: enum u16 {
	Indexed   = 8,
	Grayscale = 16,
	RGBA      = 32,
}

// Layer blend modes (the file's numbering).
Ase_Blend :: enum u16 {
	Normal, Multiply, Screen, Overlay, Darken, Lighten, Color_Dodge, Color_Burn, Hard_Light,
	Soft_Light, Difference, Exclusion, Hue, Saturation, Color, Luminosity, Addition, Subtract, Divide,
}

Ase_Layer_Flag :: enum u16 {Visible, Editable, Lock_Movement, Background, Prefer_Linked_Cels, Collapsed, Reference}
Ase_Layer_Flags :: bit_set[Ase_Layer_Flag; u16]

Ase_Layer_Kind :: enum u16 {Image, Group, Tilemap}

Ase_Header_Flag :: enum u32 {Layer_Opacity, Compose_Groups, Layer_UUIDs}
Ase_Header_Flags :: bit_set[Ase_Header_Flag; u32]

// A property value in user data.
Ase_Value :: union {
	bool,
	i64,
	u64,
	f64,
	string,
	Ase_Point,
	Ase_Size,
	Ase_Rect,
	[]Ase_Value,
	map[string]Ase_Value,
	Ase_UUID,
}
Ase_Point :: distinct [2]i32
Ase_Size :: distinct [2]i32
Ase_Rect :: struct {x, y, w, h: i32}
Ase_UUID :: distinct [16]u8

Ase_User_Data :: struct {
	text:       string,
	color:      [4]u8,
	has_color:  bool,
	properties: map[string]Ase_Value,         // the user's properties (key 0)
	extensions: map[string]map[string]Ase_Value, // per extension (its id from the external files)
}

Ase_Layer :: struct {
	name:        string,
	kind:        Ase_Layer_Kind,
	flags:       Ase_Layer_Flags,
	child_level: int,
	parent:      int, // layer index, -1 = the root
	blend:       Ase_Blend,
	opacity:     u8,
	tileset:     int, // tilemap layers
	uuid:        Ase_UUID,
	user:        Ase_User_Data,
}

Ase_Cel_Kind :: enum u16 {Raw, Linked, Compressed, Compressed_Tilemap}

// A tile in a tilemap cel: an index into the tileset (0 = empty) + flips.
Ase_Tile :: struct {
	index:         u32,
	xflip, yflip, dflip: bool,
}

Ase_Cel :: struct {
	layer:    int,
	x, y:     int,
	opacity:  u8,
	z_index:  int,
	kind:     Ase_Cel_Kind,
	w, h:     int,       // pixels (images) / tiles (tilemaps)
	pixels:   []u8,      // the sprite's depth: RGBA (4 bytes), gray+alpha (2), index (1)
	tiles:    []Ase_Tile,
	linked:   int,       // linked cels: the frame its image is from (-1: not linked)
	precise:  bool,      // cel extra: precise bounds (reference layers)
	precise_bounds: [4]f32,
	user:     Ase_User_Data,
}

Ase_Frame :: struct {
	duration: int, // ms
	cels:     [dynamic]Ase_Cel,
}

Ase_Direction :: enum u8 {Forward, Reverse, Ping_Pong, Ping_Pong_Reverse}

Ase_Tag :: struct {
	name:      string,
	from, to:  int,
	direction: Ase_Direction,
	repeats:   int, // 0 = not specified (loops; once on export)
	color:     [3]u8,
	user:      Ase_User_Data,
}

Ase_Slice_Key :: struct {
	frame:      int, // valid from this frame on
	x, y:       int,
	w, h:       int, // 0: hidden from this frame
	center:     [4]int, // 9-patch: x, y, w, h inside the slice
	pivot:      [2]int, // relative to the slice origin
}

Ase_Slice :: struct {
	name:      string,
	nine_patch: bool,
	has_pivot: bool,
	keys:      [dynamic]Ase_Slice_Key,
	user:      Ase_User_Data,
}

Ase_Tileset :: struct {
	id:          int,
	flags:       u32,
	count:       int,
	tile_w, tile_h: int,
	base_index:  int,
	name:        string,
	external:    bool,
	external_file: string, // its file name (the external files chunk)
	external_id: int,
	pixels:      []u8,     // tile_w x (tile_h * count), the sprite's depth
	user:        Ase_User_Data,
	tile_user:   [dynamic]Ase_User_Data,
}

Ase_Palette_Entry :: struct {
	color: [4]u8,
	name:  string,
}

Ase_External_File :: struct {
	id:   u32,
	kind: u8, // 0 palette, 1 tileset, 2 extension (properties), 3 extension (tile management)
	name: string,
}

Ase_Color_Profile :: struct {
	kind:  u16, // 0 none, 1 sRGB, 2 embedded ICC
	flags: u16,
	gamma: f32,
	icc:   []u8,
}

Ase_Mask :: struct {
	name:   string,
	x, y, w, h: int,
	bits:   []u8,
}

Ase_Document :: struct {
	width, height:   int,
	depth:           Ase_Depth,
	flags:           Ase_Header_Flags,
	transparent_index: u8,
	color_count:     int,
	pixel_ratio:     [2]int,
	grid:            [4]int, // x, y, w, h
	frames:          [dynamic]Ase_Frame,
	layers:          [dynamic]Ase_Layer,
	tags:            [dynamic]Ase_Tag,
	slices:          [dynamic]Ase_Slice,
	palette:         [dynamic]Ase_Palette_Entry,
	tilesets:        [dynamic]Ase_Tileset,
	external_files:  [dynamic]Ase_External_File,
	color_profile:   Ase_Color_Profile,
	masks:           [dynamic]Ase_Mask,
	user:            Ase_User_Data, // the sprite's
	arena:           vmem.Arena,
}

Ase_Error :: struct {
	message: string,
}

// Ase_Load reads a file's bytes. On failure: nil and why.
Ase_Load :: proc(data: []u8) -> (doc: ^Ase_Document, err: string) {
	doc = new(Ase_Document)
	if vmem.arena_init_growing(&doc.arena) != nil {
		free(doc)
		return nil, "out of memory"
	}
	a := vmem.arena_allocator(&doc.arena)
	r := Ase_Reader{data = data, a = a}
	if why, ok := ase_read(&r, doc); !ok {
		Ase_Destroy(doc)
		return nil, why
	}
	return doc, ""
}

// Ase_Destroy frees a document.
Ase_Destroy :: proc(doc: ^Ase_Document) {
	if doc == nil do return
	vmem.arena_destroy(&doc.arena)
	free(doc)
}

// --- reading ---------------------------------------------------------------------

@(private = "file")
Ase_Reader :: struct {
	data: []u8,
	pos:  int,
	bad:  bool, // read past the end
	a:    mem.Allocator,
}


@(private = "file")
need :: proc(r: ^Ase_Reader, n: int) -> bool {
	if r.pos + n > len(r.data) {
		r.bad = true
		return false
	}
	return true
}

@(private = "file") u8_ :: proc(r: ^Ase_Reader) -> u8 {
	if !need(r, 1) do return 0
	r.pos += 1
	return r.data[r.pos - 1]
}
@(private = "file") u16_ :: proc(r: ^Ase_Reader) -> u16 {
	if !need(r, 2) do return 0
	v := u16(r.data[r.pos]) | u16(r.data[r.pos + 1]) << 8
	r.pos += 2
	return v
}
@(private = "file") i16_ :: proc(r: ^Ase_Reader) -> i16 {return i16(u16_(r))}
@(private = "file") u32_ :: proc(r: ^Ase_Reader) -> u32 {
	if !need(r, 4) do return 0
	d := r.data[r.pos:]
	r.pos += 4
	return u32(d[0]) | u32(d[1]) << 8 | u32(d[2]) << 16 | u32(d[3]) << 24
}
@(private = "file") i32_ :: proc(r: ^Ase_Reader) -> i32 {return i32(u32_(r))}
@(private = "file") u64_ :: proc(r: ^Ase_Reader) -> u64 {
	lo := u64(u32_(r))
	hi := u64(u32_(r))
	return lo | hi << 32
}
@(private = "file") fixed_ :: proc(r: ^Ase_Reader) -> f64 {return f64(i32_(r)) / 65536}
@(private = "file") skip :: proc(r: ^Ase_Reader, n: int) {
	if need(r, n) do r.pos += n
}
@(private = "file") bytes_ :: proc(r: ^Ase_Reader, n: int) -> []u8 {
	if n < 0 || !need(r, n) do return nil
	b := r.data[r.pos:r.pos + n]
	r.pos += n
	return b
}
@(private = "file") string_ :: proc(r: ^Ase_Reader) -> string {
	n := int(u16_(r))
	b := bytes_(r, n)
	return strings.clone(string(b), r.a)
}

// inflate: a zlib stream (cel / tileset pixels) of `expected` bytes.
@(private = "file")
inflate :: proc(r: ^Ase_Reader, compressed: []u8, expected: int) -> ([]u8, bool) {
	buf: bytes.Buffer
	defer bytes.buffer_destroy(&buf)
	if err := zlib.inflate(compressed, &buf, expected_output_size = expected); err != nil do return nil, false
	out := bytes.buffer_to_bytes(&buf)
	if len(out) < expected do return nil, false
	res := make([]u8, expected, r.a)
	copy(res, out[:expected])
	return res, true
}

@(private = "file")
bytes_per_pixel :: proc(d: Ase_Depth) -> int {
	switch d {
	case .RGBA: return 4
	case .Grayscale: return 2
	case .Indexed: return 1
	}
	return 4
}

// The object the next user data chunk belongs to.
@(private = "file")
User_Target :: struct {
	user:      ^Ase_User_Data,
	tag:       int, // tags: the next user data goes to tags[tag]
	tileset:   int, // tilesets: then the tiles' user data
	tile:      int,
}

@(private = "file")
ase_read :: proc(r: ^Ase_Reader, doc: ^Ase_Document) -> (string, bool) {
	a := r.a
	doc.frames = make([dynamic]Ase_Frame, a)
	doc.layers = make([dynamic]Ase_Layer, a)
	doc.tags = make([dynamic]Ase_Tag, a)
	doc.slices = make([dynamic]Ase_Slice, a)
	doc.palette = make([dynamic]Ase_Palette_Entry, a)
	doc.tilesets = make([dynamic]Ase_Tileset, a)
	doc.external_files = make([dynamic]Ase_External_File, a)
	doc.masks = make([dynamic]Ase_Mask, a)

	// Header (128 bytes).
	if len(r.data) < 128 do return "not an Aseprite file (too short)", false
	_ = u32_(r) // file size
	if u16_(r) != 0xA5E0 do return "not an Aseprite file (bad magic number)", false
	frames := int(u16_(r))
	doc.width = int(u16_(r))
	doc.height = int(u16_(r))
	depth := u16_(r)
	switch depth {
	case 8, 16, 32: doc.depth = Ase_Depth(depth)
	case: return fmt.tprintf("unsupported colour depth %d", depth), false
	}
	doc.flags = transmute(Ase_Header_Flags)u32_(r)
	speed := int(u16_(r))
	skip(r, 8)
	doc.transparent_index = u8_(r)
	skip(r, 3)
	doc.color_count = int(u16_(r))
	if doc.color_count == 0 do doc.color_count = 256
	pw, ph := int(u8_(r)), int(u8_(r))
	doc.pixel_ratio = {pw, ph} if pw > 0 && ph > 0 else {1, 1}
	doc.grid = {int(i16_(r)), int(i16_(r)), int(u16_(r)), int(u16_(r))}
	r.pos = 128

	bpp := bytes_per_pixel(doc.depth)
	target: User_Target = {user = &doc.user, tag = -1, tileset = -1}
	lastCel: ^Ase_Cel
	newPalette := false
	// Layer hierarchy (NOTE.1): a layer's parent is the last group read at
	// the level above it.
	groupAt := make([dynamic]int, a)

	for f in 0 ..< frames {
		frameStart := r.pos
		frameBytes := int(u32_(r))
		if u16_(r) != 0xF1FA do return fmt.tprintf("frame %d: bad frame magic number", f), false
		oldChunks := int(u16_(r))
		duration := int(u16_(r))
		skip(r, 2)
		newChunks := int(u32_(r))
		chunks := newChunks if newChunks != 0 else oldChunks
		append(&doc.frames, Ase_Frame{duration = duration if duration > 0 else speed, cels = make([dynamic]Ase_Cel, a)})
		frame := &doc.frames[len(doc.frames) - 1]

		for _ in 0 ..< chunks {
			chunkStart := r.pos
			size := int(u32_(r))
			kind := u16_(r)
			if size < 6 || chunkStart + size > len(r.data) do return fmt.tprintf("frame %d: broken chunk", f), false
			chunkEnd := chunkStart + size
			switch kind {
			case 0x0004, 0x0011: // old palettes (ignored when a new one is present)
				if newPalette do break
				packets := int(u16_(r))
				index := 0
				for _ in 0 ..< packets {
					index += int(u8_(r))
					n := int(u8_(r))
					if n == 0 do n = 256
					for _ in 0 ..< n {
						c := [4]u8{u8_(r), u8_(r), u8_(r), 255}
						if kind == 0x0011 do c = {u8(int(c[0]) * 255 / 63), u8(int(c[1]) * 255 / 63), u8(int(c[2]) * 255 / 63), 255}
						for len(doc.palette) <= index do append(&doc.palette, Ase_Palette_Entry{})
						doc.palette[index].color = c
						index += 1
					}
				}
			case 0x2019: // palette
				newPalette = true
				total := int(u32_(r))
				from := int(u32_(r))
				to := int(u32_(r))
				skip(r, 8)
				for len(doc.palette) < total do append(&doc.palette, Ase_Palette_Entry{})
				for i in from ..= to {
					flags := u16_(r)
					c := [4]u8{u8_(r), u8_(r), u8_(r), u8_(r)}
					name := string_(r) if flags & 1 != 0 else ""
					if i < len(doc.palette) do doc.palette[i] = {c, name}
				}
				target = {user = nil, tag = -1, tileset = -1} // (the sprite's user data comes after the palette in v1.3)
				if f == 0 do target.user = &doc.user
			case 0x2004: // layer
				l := Ase_Layer{parent = -1}
				l.flags = transmute(Ase_Layer_Flags)u16_(r)
				l.kind = Ase_Layer_Kind(u16_(r))
				l.child_level = int(u16_(r))
				skip(r, 4) // default width / height
				l.blend = Ase_Blend(u16_(r))
				l.opacity = u8_(r)
				skip(r, 3)
				l.name = string_(r)
				if l.kind == .Tilemap do l.tileset = int(u32_(r))
				if .Layer_UUIDs in doc.flags do copy(l.uuid[:], bytes_(r, 16))
				// Background layers have no blend mode / opacity; files
				// without the opacity flag: opaque (as Aseprite reads them).
				if .Background in l.flags || .Layer_Opacity not_in doc.flags do l.opacity = 255
				if .Background in l.flags do l.blend = .Normal
				if l.kind == .Group && .Compose_Groups not_in doc.flags {
					l.blend = .Normal
					l.opacity = 255
				}
				index := len(doc.layers)
				l.parent = groupAt[l.child_level - 1] if l.child_level > 0 && l.child_level - 1 < len(groupAt) else -1
				if l.kind == .Group {
					for len(groupAt) <= l.child_level do append(&groupAt, -1)
					groupAt[l.child_level] = index
				}
				append(&doc.layers, l)
				target = {user = &doc.layers[index].user, tag = -1, tileset = -1}
			case 0x2005: // cel
				c := Ase_Cel{linked = -1}
				c.layer = int(u16_(r))
				c.x = int(i16_(r))
				c.y = int(i16_(r))
				c.opacity = u8_(r)
				c.kind = Ase_Cel_Kind(u16_(r))
				c.z_index = int(i16_(r))
				skip(r, 5)
				ok := true
				switch c.kind {
				case .Raw:
					c.w = int(u16_(r))
					c.h = int(u16_(r))
					src := bytes_(r, c.w * c.h * bpp)
					c.pixels = make([]u8, len(src), a)
					copy(c.pixels, src)
				case .Linked:
					c.linked = int(u16_(r))
					// The linked frame's image (same layer).
					if c.linked >= 0 && c.linked < len(doc.frames) {
						for src in doc.frames[c.linked].cels do if src.layer == c.layer {
							c.w, c.h, c.pixels, c.tiles = src.w, src.h, src.pixels, src.tiles
						}
					}
				case .Compressed:
					c.w = int(u16_(r))
					c.h = int(u16_(r))
					c.pixels, ok = inflate(r, r.data[r.pos:chunkEnd], c.w * c.h * bpp)
				case .Compressed_Tilemap:
					c.w = int(u16_(r))
					c.h = int(u16_(r))
					bits := int(u16_(r))
					idMask, xMask, yMask, dMask := u32_(r), u32_(r), u32_(r), u32_(r)
					skip(r, 10)
					bytesPer := max(bits / 8, 1)
					raw: []u8
					raw, ok = inflate(r, r.data[r.pos:chunkEnd], c.w * c.h * bytesPer)
					if ok {
						c.tiles = make([]Ase_Tile, c.w * c.h, a)
						shift := u32(0)
						for shift < 32 && idMask >> shift & 1 == 0 do shift += 1
						for i in 0 ..< c.w * c.h {
							v: u32
							switch bytesPer {
							case 1: v = u32(raw[i])
							case 2: v = u32(raw[i * 2]) | u32(raw[i * 2 + 1]) << 8
							case: v = u32(raw[i * 4]) | u32(raw[i * 4 + 1]) << 8 | u32(raw[i * 4 + 2]) << 16 | u32(raw[i * 4 + 3]) << 24
							}
							c.tiles[i] = {
								index = (v & idMask) >> shift,
								xflip = xMask != 0 && v & xMask == xMask,
								yflip = yMask != 0 && v & yMask == yMask,
								dflip = dMask != 0 && v & dMask == dMask,
							}
						}
					}
				case:
					ok = false
				}
				if !ok do return fmt.tprintf("frame %d: a cel of layer %d can't be read", f, c.layer), false
				append(&frame.cels, c)
				lastCel = &frame.cels[len(frame.cels) - 1]
				target = {user = &lastCel.user, tag = -1, tileset = -1}
			case 0x2006: // cel extra
				flags := u32_(r)
				px, py, pw, ph := fixed_(r), fixed_(r), fixed_(r), fixed_(r)
				if lastCel != nil && flags & 1 != 0 {
					lastCel.precise = true
					lastCel.precise_bounds = {f32(px), f32(py), f32(pw), f32(ph)}
				}
			case 0x2007: // colour profile
				p := &doc.color_profile
				p.kind = u16_(r)
				p.flags = u16_(r)
				p.gamma = f32(fixed_(r))
				skip(r, 8)
				if p.kind == 2 {
					n := int(u32_(r))
					src := bytes_(r, n)
					p.icc = make([]u8, len(src), a)
					copy(p.icc, src)
				}
			case 0x2008: // external files
				n := int(u32_(r))
				skip(r, 8)
				for _ in 0 ..< n {
					e := Ase_External_File{id = u32_(r), kind = u8_(r)}
					skip(r, 7)
					e.name = string_(r)
					append(&doc.external_files, e)
				}
			case 0x2016: // mask (deprecated)
				m := Ase_Mask{x = int(i16_(r)), y = int(i16_(r)), w = int(u16_(r)), h = int(u16_(r))}
				skip(r, 8)
				m.name = string_(r)
				src := bytes_(r, m.h * ((m.w + 7) / 8))
				m.bits = make([]u8, len(src), a)
				copy(m.bits, src)
				append(&doc.masks, m)
			case 0x2017: // path (never used)
			case 0x2018: // tags
				n := int(u16_(r))
				skip(r, 8)
				first := len(doc.tags)
				for _ in 0 ..< n {
					t := Ase_Tag{from = int(u16_(r)), to = int(u16_(r))}
					t.direction = Ase_Direction(u8_(r))
					t.repeats = int(u16_(r))
					skip(r, 6)
					t.color = {u8_(r), u8_(r), u8_(r)}
					skip(r, 1)
					t.name = string_(r)
					// (The deprecated colour is the user data's until a user
					// data chunk says otherwise - Aseprite v1.2 files.)
					t.user.color = {t.color[0], t.color[1], t.color[2], 255}
					t.user.has_color = true
					append(&doc.tags, t)
				}
				target = {user = nil, tag = first if n > 0 else -1, tileset = -1}
			case 0x2020: // user data
				u := read_user_data(r, doc, chunkEnd)
				switch {
				case target.tag >= 0 && target.tag < len(doc.tags):
					// Tags: one user data chunk per tag, in order.
					doc.tags[target.tag].user = u
					target.tag += 1
				case target.tileset >= 0:
					// Tilesets: its own, then one per tile.
					ts := &doc.tilesets[target.tileset]
					if target.tile < 0 do ts.user = u
					else {
						for len(ts.tile_user) <= target.tile do append(&ts.tile_user, Ase_User_Data{})
						ts.tile_user[target.tile] = u
					}
					target.tile += 1
				case target.user != nil:
					target.user^ = u
					target.user = nil
				}
			case 0x2022: // slice
				s := Ase_Slice{keys = make([dynamic]Ase_Slice_Key, a)}
				nkeys := int(u32_(r))
				flags := u32_(r)
				skip(r, 4)
				s.name = string_(r)
				s.nine_patch = flags & 1 != 0
				s.has_pivot = flags & 2 != 0
				for _ in 0 ..< nkeys {
					k := Ase_Slice_Key{frame = int(u32_(r)), x = int(i32_(r)), y = int(i32_(r)), w = int(u32_(r)), h = int(u32_(r))}
					if s.nine_patch do k.center = {int(i32_(r)), int(i32_(r)), int(u32_(r)), int(u32_(r))}
					if s.has_pivot do k.pivot = {int(i32_(r)), int(i32_(r))}
					append(&s.keys, k)
				}
				append(&doc.slices, s)
				target = {user = &doc.slices[len(doc.slices) - 1].user, tag = -1, tileset = -1}
			case 0x2023: // tileset
				ts := Ase_Tileset{tile_user = make([dynamic]Ase_User_Data, a)}
				ts.id = int(u32_(r))
				ts.flags = u32_(r)
				ts.count = int(u32_(r))
				ts.tile_w = int(u16_(r))
				ts.tile_h = int(u16_(r))
				ts.base_index = int(i16_(r))
				skip(r, 14)
				ts.name = string_(r)
				if ts.flags & 1 != 0 {
					ts.external = true
					fileId := u32_(r)
					ts.external_id = int(u32_(r))
					for e in doc.external_files do if e.id == fileId do ts.external_file = e.name
				}
				if ts.flags & 2 != 0 {
					n := int(u32_(r))
					ok: bool
					ts.pixels, ok = inflate(r, bytes_(r, n), ts.tile_w * ts.tile_h * ts.count * bpp)
					if !ok do return fmt.tprintf("tileset %q can't be read", ts.name), false
				}
				append(&doc.tilesets, ts)
				target = {user = nil, tag = -1, tileset = len(doc.tilesets) - 1, tile = -1}
			case:
				// Unknown chunk: skipped (newer files keep working).
			}
			if r.bad do return fmt.tprintf("frame %d: a chunk is cut short", f), false
			r.pos = chunkEnd
		}
		r.pos = frameStart + frameBytes
		if r.pos > len(r.data) do return fmt.tprintf("frame %d is cut short", f), false
	}
	if len(doc.palette) == 0 do append(&doc.palette, Ase_Palette_Entry{})
	return "", true
}

// read_user_data: a user data chunk (text, colour, property maps).
@(private = "file")
read_user_data :: proc(r: ^Ase_Reader, doc: ^Ase_Document, chunkEnd: int) -> (u: Ase_User_Data) {
	a := r.a
	flags := u32_(r)
	if flags & 1 != 0 do u.text = string_(r)
	if flags & 2 != 0 {
		u.color = {u8_(r), u8_(r), u8_(r), u8_(r)}
		u.has_color = true
	}
	if flags & 4 != 0 {
		_ = u32_(r) // size
		maps := int(u32_(r))
		for _ in 0 ..< maps {
			key := u32_(r)
			props := read_properties(r, int(u32_(r)), 0)
			if key == 0 {
				u.properties = props
			} else {
				if u.extensions == nil do u.extensions = make(map[string]map[string]Ase_Value, a)
				name := fmt.aprintf("extension:%d", key, allocator = a)
				for e in doc.external_files do if e.id == key do name = e.name
				u.extensions[name] = props
			}
			if r.bad || r.pos > chunkEnd do break
		}
	}
	if u.properties == nil do u.properties = make(map[string]Ase_Value, a)
	return
}

@(private = "file")
read_properties :: proc(r: ^Ase_Reader, n: int, depth: int) -> map[string]Ase_Value {
	m := make(map[string]Ase_Value, r.a)
	for _ in 0 ..< n {
		if r.bad do break
		name := string_(r)
		kind := u16_(r)
		m[name] = read_value(r, kind, depth)
	}
	return m
}

@(private = "file")
read_value :: proc(r: ^Ase_Reader, kind: u16, depth: int) -> Ase_Value {
	if depth > 128 {
		r.bad = true
		return nil
	}
	switch kind {
	case 0x01: return u8_(r) != 0
	case 0x02: return i64(i8(u8_(r)))
	case 0x03: return i64(u8_(r))
	case 0x04: return i64(i16_(r))
	case 0x05: return i64(u16_(r))
	case 0x06: return i64(i32_(r))
	case 0x07: return i64(u32_(r))
	case 0x08: return i64(u64_(r))
	case 0x09: return u64_(r)
	case 0x0A: return fixed_(r)
	case 0x0B: return f64(transmute(f32)u32_(r))
	case 0x0C: return transmute(f64)u64_(r)
	case 0x0D: return string_(r)
	case 0x0E: return Ase_Point{i32_(r), i32_(r)}
	case 0x0F: return Ase_Size{i32_(r), i32_(r)}
	case 0x10: return Ase_Rect{i32_(r), i32_(r), i32_(r), i32_(r)}
	case 0x11:
		n := int(u32_(r))
		elem := u16_(r)
		if n < 0 || n > len(r.data) {
			r.bad = true
			return nil
		}
		v := make([]Ase_Value, n, r.a)
		for i in 0 ..< n {
			k := elem if elem != 0 else u16_(r)
			v[i] = read_value(r, k, depth + 1)
		}
		return v
	case 0x12:
		return read_properties(r, int(u32_(r)), depth + 1)
	case 0x13:
		id: Ase_UUID
		copy(id[:], bytes_(r, 16))
		return id
	}
	r.bad = true // unknown type: the rest can't be read
	return nil
}

// --- queries -------------------------------------------------------------------------

// Ase_FindTag: a tag by name (nil if none).
Ase_FindTag :: proc(doc: ^Ase_Document, name: string) -> ^Ase_Tag {
	for &t in doc.tags do if t.name == name do return &t
	return nil
}

// Ase_FindLayer: a layer's index by name (-1 if none).
Ase_FindLayer :: proc(doc: ^Ase_Document, name: string) -> int {
	for l, i in doc.layers do if l.name == name do return i
	return -1
}

// Ase_FindSlice: a slice by name (nil if none).
Ase_FindSlice :: proc(doc: ^Ase_Document, name: string) -> ^Ase_Slice {
	for &s in doc.slices do if s.name == name do return &s
	return nil
}

// Ase_SliceKey: the slice's key in effect at a frame (ok = false: none yet).
Ase_SliceKey :: proc(s: ^Ase_Slice, frame: int) -> (key: Ase_Slice_Key, ok: bool) {
	for k in s.keys {
		if k.frame <= frame {
			key = k
			ok = true
		}
	}
	return
}

// Ase_LayerVisible: the layer and all its groups are visible (and it's not
// a reference layer - those are tracing aids, never rendered).
Ase_LayerVisible :: proc(doc: ^Ase_Document, index: int) -> bool {
	for i := index; i >= 0; i = doc.layers[i].parent {
		l := &doc.layers[i]
		if .Visible not_in l.flags || .Reference in l.flags do return false
	}
	return true
}
