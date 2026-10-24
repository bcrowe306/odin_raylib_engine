package engine

import "core:fmt"
import "core:math"
import os "osx"
import "core:path/filepath"
import "core:strings"
import rl "vendor:raylib"

// ============================================================================
// Ldtk_Doc exports (LDtk's ProjectSaver / LayerRender / exporter.Tiled):
//
//   images      <project>/png: one PNG per layer (+ "-int" IntGrid maps), per
//               level, or both; the background too; file name patterns
//   simplified  <project>/simplified/<level>/: data.json, layer PNGs,
//               _composite.png, _bg.png, IntGrid CSVs
//   Tiled       <project>/tiled/: a .tmx per level of the first world, a
//               .world file, IntGrid tilesets as PNGs
//
// Images are drawn on the CPU (raylib Image), so exports need no window.
// Ldtk_Doc_RunExports runs what the project's options ask for (after a save,
// like LDtk) and removes the folders of exports that are off.
// ============================================================================

LDTK_IMAGE_EXPORT_MODES := [?]string{"None", "OneImagePerLayer", "OneImagePerLevel", "LayersAndLevels"}

Ldtk_ExportResult :: struct {
	files:  int,
	errors: [dynamic]string, // temp allocator
}

@(private = "file")
export_err :: proc(r: ^Ldtk_ExportResult, format: string, args: ..any) {
	if r.errors == nil do r.errors = make([dynamic]string, context.temp_allocator)
	append(&r.errors, fmt.tprintf(format, ..args))
}

// the "<project name>" folder next to the project file
Ldtk_Doc_ExternalDir :: proc(doc: ^Ldtk_Doc, allocator := context.temp_allocator) -> string {
	stem := strings.trim_suffix(filepath.base(doc.path), filepath.ext(doc.path))
	if filepath.ext(doc.path) == "" do stem = fmt.tprintf("%s_data", stem)
	p, _ := filepath.join({doc.dir, stem}, allocator)
	return p
}

// ----------------------------------------------------------------------------
// CPU rendering
// ----------------------------------------------------------------------------

// Ldtk_ImageCache: tileset / background images by relative path.
Ldtk_ImageCache :: struct {
	images: map[string]rl.Image,
}

Ldtk_ImageCache_Destroy :: proc(c: ^Ldtk_ImageCache) {
	for k, img in c.images {
		if img.data != nil do rl.UnloadImage(img)
		delete(k)
	}
	delete(c.images)
	c^ = {}
}

@(private = "file")
cache_get :: proc(doc: ^Ldtk_Doc, c: ^Ldtk_ImageCache, rel: string) -> (rl.Image, bool) {
	if rel == "" do return {}, false
	if img, ok := c.images[rel]; ok do return img, img.data != nil
	p, _ := filepath.join({doc.dir, rel}, context.temp_allocator)
	img: rl.Image
	if os.is_file(p) {
		img = rl.LoadImage(strings.clone_to_cstring(p, context.temp_allocator))
		if img.data != nil do rl.ImageFormat(&img, .UNCOMPRESSED_R8G8B8A8)
	}
	c.images[strings.clone(rel)] = img
	return img, img.data != nil
}

@(private = "file")
draw_tile :: proc(dst: ^rl.Image, src: rl.Image, sx, sy, size: int, dx, dy: int, flips: u8, alpha: f64) {
	tint := rl.Color{255, 255, 255, u8(clamp(alpha * 255 + 0.5, 0, 255))}
	if tint.a == 0 do return
	if flips == 0 {
		rl.ImageDraw(dst, src, {f32(sx), f32(sy), f32(size), f32(size)}, {f32(dx), f32(dy), f32(size), f32(size)}, tint)
		return
	}
	piece := rl.ImageFromImage(src, {f32(sx), f32(sy), f32(size), f32(size)})
	defer rl.UnloadImage(piece)
	if flips & 1 != 0 do rl.ImageFlipHorizontal(&piece)
	if flips & 2 != 0 do rl.ImageFlipVertical(&piece)
	rl.ImageDraw(dst, piece, {0, 0, f32(size), f32(size)}, {f32(dx), f32(dy), f32(size), f32(size)}, tint)
}

// Ldtk_Doc_LayerHasTileImage: LayerRender.createPngs makes a tile image for
// Tiles layers and auto layers (IntGrid with rules, Auto layers).
Ldtk_Doc_LayerHasTileImage :: proc(d: ^Ldtk_DocLayerDef) -> bool {
	return d.type == .Tiles || d.type == .AutoLayer || (d.type == .IntGrid && d.tilesetUid >= 0)
}

// Ldtk_Doc_RenderLayer draws a layer's tiles (auto tiles, then grid tiles)
// at the level's size, with the layer's opacity. Unload the image.
Ldtk_Doc_RenderLayer :: proc(doc: ^Ldtk_Doc, li, layer: int, cache: ^Ldtk_ImageCache, opacity := -1.0) -> rl.Image {
	s := Ldtk_Doc_LevelSize(doc, li)
	img := rl.GenImageColor(i32(max(s.x, 1)), i32(max(s.y, 1)), {0, 0, 0, 0})
	ly := &doc.levels[li].layers[layer]
	d := Ldtk_Doc_LayerDef(doc, ly)
	if d == nil do return img
	ts := Ldtk_Doc_LayerTileset(doc, ly)
	if ts == nil do return img
	src, ok := cache_get(doc, cache, ts.relPath)
	if !ok do return img
	op := opacity >= 0 ? opacity : f64(d.opacity)
	off := Ldtk_Doc_LayerOffset(ly)
	for t in ly.autoTiles do draw_tile(&img, src, int(t.src.x), int(t.src.y), ts.gridSize, off.x + int(t.px.x), off.y + int(t.px.y), t.f, t.a * op)
	for t in ly.gridTiles do draw_tile(&img, src, int(t.src.x), int(t.src.y), ts.gridSize, off.x + int(t.px.x), off.y + int(t.px.y), t.f, t.a * op)
	return img
}

// Ldtk_Doc_RenderIntGridMap: one pixel per cell in the value's colour (the
// "-int" image).
Ldtk_Doc_RenderIntGridMap :: proc(doc: ^Ldtk_Doc, li, layer: int) -> rl.Image {
	ly := &doc.levels[li].layers[layer]
	d := Ldtk_Doc_LayerDef(doc, ly)
	img := rl.GenImageColor(i32(max(ly.cWid, 1)), i32(max(ly.cHei, 1)), {0, 0, 0, 0})
	if d == nil do return img
	for cy in 0 ..< ly.cHei do for cx in 0 ..< ly.cWid {
		v := int(ly.intGrid[cx + cy * ly.cWid])
		if v == 0 do continue
		iv := Ldtk_Doc_IntValue(d, v)
		if iv == nil do continue
		c := iv.color
		c.a = 255
		rl.ImageDrawPixel(&img, i32(cx), i32(cy), c)
	}
	return img
}

// Ldtk_Doc_RenderLevelBg: the background colour and image (LayerRender's
// renderBgToTexture / createBgPng).
Ldtk_Doc_RenderLevelBg :: proc(doc: ^Ldtk_Doc, li: int, cache: ^Ldtk_ImageCache, withImage := true) -> rl.Image {
	s := Ldtk_Doc_LevelSize(doc, li)
	lv := &doc.levels[li]
	c := Ldtk_ParseHexColor(LdtkJson_Str(lv.obj, "__bgColor", LdtkJson_Str(doc.root, "defaultLevelBgColor", "#696A79")))
	img := rl.GenImageColor(i32(max(s.x, 1)), i32(max(s.y, 1)), c)
	if !withImage do return img
	rel := LdtkJson_Str(lv.obj, "bgRelPath")
	src, ok := cache_get(doc, cache, rel)
	if !ok do return img
	pos, _ := Ldtk_BgPosOf(LdtkJson_Str(lv.obj, "bgPos", "Cover"))
	pivot := [2]f64{LdtkJson_Float(lv.obj, "bgPivotX", 0.5), LdtkJson_Float(lv.obj, "bgPivotY", 0.5)}
	bg := Ldtk_LevelBgInfo(s, {int(src.width), int(src.height)}, pos, pivot)
	crop := rl.Rectangle{f32(bg.crop[0]), f32(bg.crop[1]), f32(bg.crop[2]), f32(bg.crop[3])}
	if pos != .Repeat {
		rl.ImageDraw(&img, src, crop, {f32(bg.topLeft.x), f32(bg.topLeft.y), crop.width * f32(bg.scale.x), crop.height * f32(bg.scale.y)}, rl.WHITE)
		return img
	}
	tw, th := crop.width, crop.height
	if tw < 1 || th < 1 do return img
	nx, ny := math.ceil(f32(s.x) / tw), math.ceil(f32(s.y) / th)
	start := [2]f32{f32(pivot.x) * (f32(s.x) - nx * tw), f32(pivot.y) * (f32(s.y) - ny * th)}
	for y := start.y; y < f32(s.y); y += th do for x := start.x; x < f32(s.x); x += tw {
		rl.ImageDraw(&img, src, crop, {x, y, tw, th}, rl.WHITE)
	}
	return img
}

// ----------------------------------------------------------------------------
// Images
// ----------------------------------------------------------------------------

Ldtk_Doc_ImageExportMode :: proc(doc: ^Ldtk_Doc) -> string {
	if LdtkJson_Bool(doc.root, "simplifiedExport") do return "LayersAndLevels"
	return LdtkJson_Str(doc.root, "imageExportMode", "None")
}

// Ldtk_Doc_DefaultPngPattern: Project.getDefaultImageExportFilePattern.
Ldtk_Doc_DefaultPngPattern :: proc(doc: ^Ldtk_Doc) -> string {
	return LdtkJson_Str(doc.root, "imageExportMode", "None") == "OneImagePerLevel" ? "%level_name" : "%level_name__%layer_name"
}

// Ldtk_Doc_PngFileName: Project.getPngFileName (%level_name, %world,
// %level_idx, %layer_name, %layer_idx; "-<suffix>" appended).
Ldtk_Doc_PngFileName :: proc(doc: ^Ldtk_Doc, pattern: string, li: int, layerUid: int, suffix := "") -> string {
	p := pattern
	if p == "" do p = LdtkJson_Str(doc.root, "pngFilePattern")
	if p == "" do p = Ldtk_Doc_DefaultPngPattern(doc)
	lv := &doc.levels[li]
	idx := 0
	for l, i in doc.levels do if l.world == lv.world && i < li do idx += 1
	layerIdx := 0
	layerName := ""
	for &d in doc.layerDefs {
		if d.uid == layerUid {
			layerName = d.identifier
			break
		}
		if d.type != .Entities do layerIdx += 1
	}
	p, _ = strings.replace_all(p, "%level_name", LdtkJson_Str(lv.obj, "identifier"), context.temp_allocator)
	p, _ = strings.replace_all(p, "%world", Ldtk_Doc_WorldName(doc, lv.world), context.temp_allocator)
	p, _ = strings.replace_all(p, "%level_idx", fmt.tprintf("%04d", idx), context.temp_allocator)
	p, _ = strings.replace_all(p, "%layer_name", layerName, context.temp_allocator)
	p, _ = strings.replace_all(p, "%layer_idx", fmt.tprintf("%02d", layerIdx), context.temp_allocator)
	return suffix == "" ? p : fmt.tprintf("%s-%s", p, suffix)
}

@(private = "file")
write_png :: proc(r: ^Ldtk_ExportResult, img: rl.Image, dir, name: string) {
	p, _ := filepath.join({dir, fmt.tprintf("%s.png", name)}, context.temp_allocator)
	if rl.ExportImage(img, strings.clone_to_cstring(p, context.temp_allocator)) do r.files += 1
	else do export_err(r, "Could not write %s", p)
}

@(private = "file")
init_dir :: proc(dir: string, removeExt: string) {
	if !os.is_dir(dir) {
		_ = os.make_directory_all(dir)
		return
	}
	if removeExt == "" do return
	if list, err := os.read_all_directory_by_path(dir, context.temp_allocator); err == nil {
		for fi in list do if fi.type != .Directory && strings.has_suffix(fi.name, removeExt) {
			p, _ := filepath.join({dir, fi.name}, context.temp_allocator)
			_ = os.remove(p)
		}
	}
}

// Ldtk_Doc_ExportImages: ProjectSaver's WritingImages state.
Ldtk_Doc_ExportImages :: proc(doc: ^Ldtk_Doc, r: ^Ldtk_ExportResult) {
	simplified := LdtkJson_Bool(doc.root, "simplifiedExport")
	mode := Ldtk_Doc_ImageExportMode(doc)
	base := Ldtk_Doc_ExternalDir(doc)
	baseDir, _ := filepath.join({base, simplified ? "simplified" : "png"}, context.temp_allocator)
	if mode == "None" {
		pngDir, _ := filepath.join({base, "png"}, context.temp_allocator)
		if os.is_dir(pngDir) do _ = os.remove_all(pngDir)
		return
	}
	if simplified {
		if os.is_dir(baseDir) do _ = os.remove_all(baseDir)
		_ = os.make_directory_all(baseDir)
	} else do init_dir(baseDir, ".png")
	exportBg := LdtkJson_Bool(doc.root, "exportLevelBg", true)
	cache: Ldtk_ImageCache
	defer Ldtk_ImageCache_Destroy(&cache)
	for &lv, li in doc.levels {
		id := LdtkJson_Str(lv.obj, "identifier")
		pngDir := baseDir
		if simplified {
			pngDir, _ = filepath.join({baseDir, id}, context.temp_allocator)
			init_dir(pngDir, ".png")
		}
		switch mode {
		case "OneImagePerLayer", "LayersAndLevels":
			if exportBg {
				bg := Ldtk_Doc_RenderLevelBg(doc, li, &cache)
				write_png(r, bg, pngDir, simplified ? "_bg" : fmt.tprintf("%s_bg", id))
				rl.UnloadImage(bg)
			}
			mains := make(map[int]rl.Image, allocator = context.temp_allocator)
			for &ly, j in lv.layers {
				d := Ldtk_Doc_LayerDef(doc, &ly)
				if d == nil do continue
				if Ldtk_Doc_LayerHasTileImage(d) {
					img := Ldtk_Doc_RenderLayer(doc, li, j, &cache)
					write_png(r, img, pngDir, Ldtk_Doc_PngFileName(doc, simplified ? "%layer_name" : "", li, d.uid))
					mains[j] = img
				}
				if d.type == .IntGrid {
					img := Ldtk_Doc_RenderIntGridMap(doc, li, j)
					write_png(r, img, pngDir, Ldtk_Doc_PngFileName(doc, simplified ? "%layer_name" : "", li, d.uid, "int"))
					rl.UnloadImage(img)
				}
			}
			if mode == "LayersAndLevels" {
				s := Ldtk_Doc_LevelSize(doc, li)
				comp := exportBg ? Ldtk_Doc_RenderLevelBg(doc, li, &cache, false) : rl.GenImageColor(i32(max(s.x, 1)), i32(max(s.y, 1)), {0, 0, 0, 0})
				#reverse for &ly, j in lv.layers {
					img, ok := mains[j]
					if !ok do continue
					d := Ldtk_Doc_LayerDef(doc, &ly)
					rl.ImageDraw(&comp, img, {0, 0, f32(img.width), f32(img.height)}, {0, 0, f32(img.width), f32(img.height)}, {255, 255, 255, u8(clamp(f64(d.opacity) * 255 + 0.5, 0, 255))})
				}
				write_png(r, comp, pngDir, simplified ? "_composite" : id)
				rl.UnloadImage(comp)
			}
			for _, img in mains do rl.UnloadImage(img)
		case "OneImagePerLevel":
			s := Ldtk_Doc_LevelSize(doc, li)
			comp := exportBg ? Ldtk_Doc_RenderLevelBg(doc, li, &cache) : rl.GenImageColor(i32(max(s.x, 1)), i32(max(s.y, 1)), {0, 0, 0, 0})
			#reverse for &ly, j in lv.layers {
				d := Ldtk_Doc_LayerDef(doc, &ly)
				if d == nil || !Ldtk_Doc_LayerHasTileImage(d) do continue
				img := Ldtk_Doc_RenderLayer(doc, li, j, &cache)
				rl.ImageDraw(&comp, img, {0, 0, f32(img.width), f32(img.height)}, {0, 0, f32(img.width), f32(img.height)}, rl.WHITE)
				rl.UnloadImage(img)
			}
			first := len(doc.layerDefs) > 0 ? doc.layerDefs[0].uid : -1
			write_png(r, comp, pngDir, Ldtk_Doc_PngFileName(doc, "", li, first))
			rl.UnloadImage(comp)
		}
	}
	if simplified {
		old, _ := filepath.join({base, "png"}, context.temp_allocator)
		if os.is_dir(old) do _ = os.remove_all(old)
	}
}

// ----------------------------------------------------------------------------
// Simplified format
// ----------------------------------------------------------------------------

@(private = "file")
jkv :: proc(o: ^LdtkJson, key: string, v: ^LdtkJson, a := context.temp_allocator) {
	append(&o.keys, key)
	append(&o.items, v)
}

// Ldtk_Doc_SimplifiedJson: Level.toSimplifiedJson (temp allocator).
Ldtk_Doc_SimplifiedJson :: proc(doc: ^Ldtk_Doc, li: int) -> ^LdtkJson {
	a := context.temp_allocator
	lv := &doc.levels[li]
	p := Ldtk_Doc_LevelPos(doc, li)
	s := Ldtk_Doc_LevelSize(doc, li)
	o := LdtkJson_New(.Object, a)
	jkv(o, "identifier", LdtkJson_NewString(LdtkJson_Str(lv.obj, "identifier"), a))
	jkv(o, "uniqueIdentifer", LdtkJson_NewString(LdtkJson_Str(lv.obj, "iid"), a))
	jkv(o, "x", LdtkJson_NewInt(p.x, a))
	jkv(o, "y", LdtkJson_NewInt(p.y, a))
	jkv(o, "width", LdtkJson_NewInt(s.x, a))
	jkv(o, "height", LdtkJson_NewInt(s.y, a))
	jkv(o, "bgColor", LdtkJson_NewString(LdtkJson_Str(lv.obj, "__bgColor", "#696A79"), a))
	n := LdtkJson_Get(lv.obj, "__neighbours")
	jkv(o, "neighbourLevels", n != nil ? LdtkJson_Clone(n, a) : LdtkJson_New(.Array, a))
	cf := LdtkJson_New(.Object, a)
	for fi in LdtkJson_Arr(lv.data, "fieldInstances") {
		v := LdtkJson_Get(fi, "__value")
		jkv(cf, LdtkJson_Str(fi, "__identifier"), v != nil ? LdtkJson_Clone(v, a) : LdtkJson_New(.Null, a))
	}
	jkv(o, "customFields", cf)
	layers := LdtkJson_New(.Array, a)
	#reverse for &ly in lv.layers {
		d := Ldtk_Doc_LayerDef(doc, &ly)
		if d == nil || !Ldtk_Doc_LayerHasTileImage(d) do continue
		append(&layers.items, LdtkJson_NewString(fmt.tprintf("%s.png", d.identifier), a))
	}
	jkv(o, "layers", layers)
	ents := LdtkJson_New(.Object, a)
	for &ly, j in lv.layers {
		d := Ldtk_Doc_LayerDef(doc, &ly)
		if d == nil || d.type != .Entities do continue
		for ent in Ldtk_Doc_Entities(doc, li, j) {
			id := LdtkJson_Str(ent, "__identifier")
			list := LdtkJson_Get(ents, id)
			if list == nil {
				list = LdtkJson_New(.Array, a)
				jkv(ents, strings.clone(id, a), list)
			}
			e := LdtkJson_New(.Object, a)
			px := LdtkJson_Arr(ent, "px")
			jkv(e, "id", LdtkJson_NewString(id, a))
			jkv(e, "iid", LdtkJson_NewString(LdtkJson_Str(ent, "iid"), a))
			jkv(e, "layer", LdtkJson_NewString(d.identifier, a))
			jkv(e, "x", LdtkJson_NewInt(len(px) > 0 ? int(px[0].num) : 0, a))
			jkv(e, "y", LdtkJson_NewInt(len(px) > 1 ? int(px[1].num) : 0, a))
			jkv(e, "width", LdtkJson_NewInt(LdtkJson_Int(ent, "width"), a))
			jkv(e, "height", LdtkJson_NewInt(LdtkJson_Int(ent, "height"), a))
			c := Ldtk_ParseHexColor(LdtkJson_Str(ent, "__smartColor", "#FFFFFF"))
			jkv(e, "color", LdtkJson_NewInt(int(c.r) << 16 | int(c.g) << 8 | int(c.b), a))
			ecf := LdtkJson_New(.Object, a)
			for fi in LdtkJson_Arr(ent, "fieldInstances") {
				v := LdtkJson_Get(fi, "__value")
				jkv(ecf, LdtkJson_Str(fi, "__identifier"), v != nil ? LdtkJson_Clone(v, a) : LdtkJson_New(.Null, a))
			}
			jkv(e, "customFields", ecf)
			append(&list.items, e)
		}
	}
	jkv(o, "entities", ents)
	return o
}

// Ldtk_Doc_ExportSimplified: the WritingSimplifiedFormat state - data.json
// and an IntGrid CSV per level (the images come from ExportImages).
Ldtk_Doc_ExportSimplified :: proc(doc: ^Ldtk_Doc, r: ^Ldtk_ExportResult) {
	dir, _ := filepath.join({Ldtk_Doc_ExternalDir(doc), "simplified"}, context.temp_allocator)
	if !LdtkJson_Bool(doc.root, "simplifiedExport") {
		if os.is_dir(dir) do _ = os.remove_all(dir)
		return
	}
	init_dir(dir, ".json")
	for &lv, li in doc.levels {
		ld, _ := filepath.join({dir, LdtkJson_Str(lv.obj, "identifier")}, context.temp_allocator)
		_ = os.make_directory_all(ld)
		text := LdtkJson_ToString(Ldtk_Doc_SimplifiedJson(doc, li), .Full, context.temp_allocator)
		p, _ := filepath.join({ld, "data.json"}, context.temp_allocator)
		if os.write_entire_file(p, transmute([]byte)text) == nil do r.files += 1
		else do export_err(r, "Could not write %s", p)
		for &ly in lv.layers {
			d := Ldtk_Doc_LayerDef(doc, &ly)
			if d == nil || d.type != .IntGrid do continue
			// exporter.Csv.toString2D: rows joined by ",", ",\n" between rows
			b := strings.builder_make(context.temp_allocator)
			for cy in 0 ..< ly.cHei {
				for cx in 0 ..< ly.cWid {
					if cx > 0 do strings.write_byte(&b, ',')
					fmt.sbprintf(&b, "%d", ly.intGrid[cx + cy * ly.cWid])
				}
				if cy < ly.cHei - 1 do strings.write_byte(&b, ',')
				strings.write_byte(&b, '\n')
			}
			cp, _ := filepath.join({ld, fmt.tprintf("%s.csv", d.identifier)}, context.temp_allocator)
			if os.write_entire_file(cp, transmute([]byte)strings.to_string(b)) == nil do r.files += 1
			else do export_err(r, "Could not write %s", cp)
		}
	}
}

// ----------------------------------------------------------------------------
// Tiled
// ----------------------------------------------------------------------------

@(private = "file")
xml_escape :: proc(b: ^strings.Builder, s: string) {
	for c in s {
		switch c {
		case '&': strings.write_string(b, "&amp;")
		case '<': strings.write_string(b, "&lt;")
		case '>': strings.write_string(b, "&gt;")
		case '"': strings.write_string(b, "&quot;")
		case: strings.write_rune(b, c)
		}
	}
}

// a tiny XML writer matching Haxe's Xml.toString (attributes in order, no
// whitespace, empty elements closed with "/>")
@(private = "file")
Xml :: struct {
	b:    strings.Builder,
	open: [dynamic]string,
	tag:  bool, // inside an unclosed start tag
}

@(private = "file")
xml_start :: proc(x: ^Xml, name: string, attrs: ..string) {
	if x.tag do strings.write_byte(&x.b, '>')
	strings.write_byte(&x.b, '<')
	strings.write_string(&x.b, name)
	for i := 0; i + 1 < len(attrs); i += 2 {
		strings.write_byte(&x.b, ' ')
		strings.write_string(&x.b, attrs[i])
		strings.write_string(&x.b, "=\"")
		xml_escape(&x.b, attrs[i + 1])
		strings.write_byte(&x.b, '"')
	}
	append(&x.open, name)
	x.tag = true
}

@(private = "file")
xml_text :: proc(x: ^Xml, text: string) {
	if x.tag do strings.write_byte(&x.b, '>')
	x.tag = false
	xml_escape(&x.b, text)
}

@(private = "file")
xml_end :: proc(x: ^Xml) {
	name := pop(&x.open)
	if x.tag {
		strings.write_string(&x.b, "/>")
		x.tag = false
		return
	}
	strings.write_string(&x.b, "</")
	strings.write_string(&x.b, name)
	strings.write_byte(&x.b, '>')
}

// js_number: Std.string of a float
@(private = "file")
js_number :: proc(v: f64) -> string {
	b := strings.builder_make(context.temp_allocator)
	ldtk_js_number(&b, v)
	return strings.to_string(b)
}

@(private = "file")
Tiled_Csv :: struct {
	w, h: int,
	data: map[int]u32,
}

@(private = "file")
csv_string :: proc(c: ^Tiled_Csv) -> string {
	b := strings.builder_make(context.temp_allocator)
	for i in 0 ..< c.w * c.h {
		if i > 0 do strings.write_byte(&b, ',')
		fmt.sbprintf(&b, "%d", c.data[i] or_else 0)
	}
	return strings.to_string(b)
}

// Ldtk_Doc_ExportTiled: exporter.Tiled - one .tmx per level of the first
// world, IntGrid layers as coloured tilesets, auto tiles in as many layers
// as stacked tiles need, entities as objects with their fields as
// properties, and a .world file. Layers whose grid isn't the most common one
// are left out (Tiled has a single grid per map).
Ldtk_Doc_ExportTiled :: proc(doc: ^Ldtk_Doc, r: ^Ldtk_ExportResult) {
	out, _ := filepath.join({Ldtk_Doc_ExternalDir(doc), "tiled"}, context.temp_allocator)
	if !LdtkJson_Bool(doc.root, "exportTiled") {
		if os.is_dir(out) do _ = os.remove_all(out)
		return
	}
	if os.is_dir(out) do _ = os.remove_all(out)
	_ = os.make_directory_all(out)
	// the most frequent layer grid
	grid := LdtkJson_Int(doc.root, "defaultGridSize", 16)
	{
		counts := make(map[int]int, allocator = context.temp_allocator)
		best := 0
		for &d in doc.layerDefs {
			counts[d.gridSize] += 1
			if counts[d.gridSize] > best {
				best = counts[d.gridSize]
				grid = d.gridSize
			}
		}
	}
	for &d in doc.layerDefs do if d.gridSize != grid do export_err(r, "Layer %s uses a %d px grid: Tiled supports one grid per map (%d px)", d.identifier, d.gridSize, grid)
	// IntGrid tilesets (coloured squares), shared by the maps
	for &d in doc.layerDefs {
		if d.type != .IntGrid || len(d.values) == 0 do continue
		img := rl.GenImageColor(i32(len(d.values) * d.gridSize), i32(d.gridSize), {0, 0, 0, 0})
		for v, i in d.values {
			c := v.color
			c.a = 255
			rl.ImageDrawRectangle(&img, i32(i * d.gridSize), 0, i32(d.gridSize), i32(d.gridSize), c)
		}
		write_png(r, img, out, fmt.tprintf("%s.intgrid", d.identifier))
		rl.UnloadImage(img)
	}
	world := LdtkJson_New(.Object, context.temp_allocator)
	maps := LdtkJson_New(.Array, context.temp_allocator)
	jkv(world, "maps", maps)
	jkv(world, "type", LdtkJson_NewString("world", context.temp_allocator))
	first := make([dynamic]int, context.temp_allocator)
	for &lv, li in doc.levels do if lv.world == 0 do append(&first, li)
	for li, n in first {
		id := LdtkJson_Str(doc.levels[li].obj, "identifier")
		name := len(first) > 1 ? fmt.tprintf("%04d_%s", n + 1, id) : id
		text := tiled_level(doc, li, grid, out, r)
		p, _ := filepath.join({out, fmt.tprintf("%s.tmx", name)}, context.temp_allocator)
		if os.write_entire_file(p, transmute([]byte)text) == nil do r.files += 1
		else do export_err(r, "Could not write %s", p)
		m := LdtkJson_New(.Object, context.temp_allocator)
		pos := Ldtk_Doc_LevelPos(doc, li)
		jkv(m, "fileName", LdtkJson_NewString(fmt.tprintf("%s.tmx", name), context.temp_allocator))
		jkv(m, "x", LdtkJson_NewInt(pos.x, context.temp_allocator))
		jkv(m, "y", LdtkJson_NewInt(pos.y, context.temp_allocator))
		append(&maps.items, m)
	}
	stem := strings.trim_suffix(filepath.base(doc.path), filepath.ext(doc.path))
	wp, _ := filepath.join({out, fmt.tprintf("%s.world", stem)}, context.temp_allocator)
	wt := LdtkJson_ToString(world, .Compact, context.temp_allocator)
	if os.write_entire_file(wp, transmute([]byte)wt) == nil do r.files += 1
}

@(private = "file")
tiled_level :: proc(doc: ^Ldtk_Doc, li: int, grid: int, out: string, r: ^Ldtk_ExportResult) -> string {
	lv := &doc.levels[li]
	s := Ldtk_Doc_LevelSize(doc, li)
	x: Xml
	x.b = strings.builder_make(context.temp_allocator)
	x.open = make([dynamic]string, context.temp_allocator)
	bg := LdtkJson_Str(lv.obj, "__bgColor", "#696A79")
	xml_start(&x, "map", "version", "1.4", "tiledversion", "1.4.2", "orientation", "orthogonal", "renderorder", "right-down", "compressionlevel", "0", "width", fmt.tprint(int(math.ceil(f64(s.x) / f64(grid)))), "height", fmt.tprint(int(math.ceil(f64(s.y) / f64(grid)))), "tilewidth", fmt.tprint(grid), "tileheight", fmt.tprint(grid), "infinite", "0", "backgroundcolor", strings.to_lower(bg, context.temp_allocator))
	gids := make(map[int]u32, allocator = context.temp_allocator)
	gid: u32 = 1
	for &ts in doc.tilesets {
		if ts.relPath == "" || LdtkJson_Get(ts.obj, "embedAtlas") != nil && !LdtkJson_IsNull(ts.obj, "embedAtlas") {
			export_err(r, "Skipped tileset %s (no image file)", ts.identifier)
			continue
		}
		if ts.padding != 0 do export_err(r, "Tileset %s has padding, which Tiled doesn't support", ts.identifier)
		cols := int(math.ceil(f64(ts.pxSize.x) / f64(max(ts.gridSize, 1))))
		count := cols * int(math.ceil(f64(ts.pxSize.y) / f64(max(ts.gridSize, 1))))
		abs, _ := filepath.join({doc.dir, ts.relPath}, context.temp_allocator)
		rel, err := filepath.rel(out, abs, context.temp_allocator)
		if err != nil do rel = ts.relPath
		rel, _ = strings.replace_all(rel, "\\", "/", context.temp_allocator)
		xml_start(&x, "tileset", "firstgid", fmt.tprint(gid), "name", ts.identifier, "tilewidth", fmt.tprint(ts.gridSize), "tileheight", fmt.tprint(ts.gridSize), "tilecount", fmt.tprint(count), "columns", fmt.tprint(cols), "objectalignment", "topleft", "margin", "0", "spacing", fmt.tprint(ts.spacing))
		xml_start(&x, "image", "source", rel, "width", fmt.tprint(ts.pxSize.x), "height", fmt.tprint(ts.pxSize.y))
		xml_end(&x)
		// tiles' custom data (JSON objects) as properties
		for cd in LdtkJson_Arr(ts.obj, "customData") {
			data, ok := LdtkJson_Parse(LdtkJson_Str(cd, "data"), context.temp_allocator)
			if !ok || data.kind != .Object do continue
			props := 0
			for v in data.items do if v.kind == .Bool || v.kind == .Number || v.kind == .String do props += 1
			if props == 0 do continue
			xml_start(&x, "tile", "id", fmt.tprint(LdtkJson_Int(cd, "tileId")))
			xml_start(&x, "properties")
			for k, i in data.keys {
				v := data.items[i]
				#partial switch v.kind {
				case .Bool: xml_start(&x, "property", "name", k, "type", "bool", "value", v.b ? "true" : "false")
				case .Number: xml_start(&x, "property", "name", k, "type", v.num == math.floor(v.num) ? "int" : "float", "value", js_number(v.num))
				case .String: xml_start(&x, "property", "name", k, "value", v.text)
				case: continue
				}
				xml_end(&x)
			}
			xml_end(&x)
			xml_end(&x)
		}
		xml_end(&x)
		gids[ts.uid] = gid
		gid += u32(count)
	}
	for &d in doc.layerDefs {
		if d.type != .IntGrid || len(d.values) == 0 do continue
		count := len(d.values)
		xml_start(&x, "tileset", "firstgid", fmt.tprint(gid), "name", d.identifier, "tilewidth", fmt.tprint(d.gridSize), "tileheight", fmt.tprint(d.gridSize), "tilecount", fmt.tprint(count), "columns", fmt.tprint(count), "objectalignment", "topleft")
		xml_start(&x, "image", "source", fmt.tprintf("%s.intgrid.png", d.identifier), "width", fmt.tprint(count * d.gridSize), "height", fmt.tprint(d.gridSize))
		xml_end(&x)
		xml_end(&x)
		gids[d.uid] = gid
		gid += u32(count)
	}
	tile_gid :: proc(gids: map[int]u32, owner: int, tid: int, flips: u8) -> u32 {
		g := (gids[owner] or_else 1) + u32(tid)
		if flips & 1 != 0 do g |= 1 << 31
		if flips & 2 != 0 do g |= 1 << 30
		return g
	}
	layerId, objectId := 1, 1
	csv_layer :: proc(x: ^Xml, layerId: ^int, name: string, w, h: int, opacity: f64, data: string) {
		xml_start(x, "layer", "id", fmt.tprint(layerId^), "name", name, "width", fmt.tprint(w), "height", fmt.tprint(h), "opacity", js_number(opacity))
		layerId^ += 1
		xml_start(x, "data", "encoding", "csv")
		xml_text(x, data)
		xml_end(x)
		xml_end(x)
	}
	#reverse for &ly, j in lv.layers {
		d := Ldtk_Doc_LayerDef(doc, &ly)
		if d == nil do continue
		if d.gridSize != grid {
			export_err(r, "Level %s: layer %s left out (grid size)", LdtkJson_Str(lv.obj, "identifier"), d.identifier)
			continue
		}
		opacity := f64(d.opacity)
		switch d.type {
		case .IntGrid:
			c := Tiled_Csv{w = ly.cWid, h = ly.cHei, data = make(map[int]u32, allocator = context.temp_allocator)}
			for v, i in ly.intGrid do if v != 0 do c.data[i] = tile_gid(gids, d.uid, int(v) - 1, 0)
			csv_layer(&x, &layerId, d.tilesetUid >= 0 ? fmt.tprintf("%s_values", d.identifier) : d.identifier, ly.cWid, ly.cHei, opacity, csv_string(&c))
		case .Entities:
			xml_start(&x, "objectgroup", "id", fmt.tprint(layerId), "name", d.identifier)
			layerId += 1
			for ent in Ldtk_Doc_Entities(doc, li, j) {
				ed := Ldtk_Doc_EntityDef(doc, LdtkJson_Int(ent, "defUid", -1))
				if ed == nil do continue
				px := LdtkJson_Arr(ent, "px")
				ex, ey := len(px) > 1 ? int(px[0].num) : 0, len(px) > 1 ? int(px[1].num) : 0
				ox, oy := ex, ey
				if ed.pivot != {} {
					ox -= int(math.round(ed.pivot.x * f64(ed.size.x)))
					oy -= int(math.round(ed.pivot.y * f64(ed.size.y)))
				}
				xml_start(&x, "object", "name", ed.identifier, "type", ed.identifier, "x", fmt.tprint(ox), "y", fmt.tprint(oy), "width", fmt.tprint(ed.size.x), "height", fmt.tprint(ed.size.y))
				objectId += 1
				xml_start(&x, "properties")
				prop :: proc(x: ^Xml, name, type, value: string) {
					if type == "" do xml_start(x, "property", "name", name, "value", value)
					else do xml_start(x, "property", "name", name, "type", type, "value", value)
					xml_end(x)
				}
				prop(&x, "__anchorX", "int", fmt.tprint(ex))
				prop(&x, "__anchorY", "int", fmt.tprint(ey))
				prop(&x, "__cx", "int", fmt.tprint(ex / max(d.gridSize, 1)))
				prop(&x, "__cy", "int", fmt.tprint(ey / max(d.gridSize, 1)))
				for fi in LdtkJson_Arr(ent, "fieldInstances") {
					fd := Ldtk_Doc_FieldDef(doc, LdtkJson_Int(fi, "defUid", -1))
					if fd == nil do continue
					fname := LdtkJson_Str(fi, "__identifier")
					kind := Ldtk_FieldKindOf(fd)
					type := ""
					#partial switch kind {
					case .Int: type = "int"
					case .Float: type = "float"
					case .Bool: type = "bool"
					case .Color: type = "color"
					case .Path: type = "file"
					case .Tile: type = "tile"
					}
					v := LdtkJson_Get(fi, "__value")
					vals := make([dynamic]^LdtkJson, context.temp_allocator)
					if v != nil && v.kind == .Array do append(&vals, ..v.items[:])
					else do append(&vals, v)
					for val, i in vals {
						text := tiled_value(kind, val)
						prop(&x, len(vals) <= 1 ? fname : fmt.tprintf("%s_%d", fname, i), type, text)
					}
				}
				xml_end(&x)
				xml_end(&x)
			}
			xml_end(&x)
		case .Tiles:
			ts := Ldtk_Doc_LayerTileset(doc, &ly)
			maxStack := 0
			counts := make(map[i32]int, allocator = context.temp_allocator)
			for t in ly.gridTiles {
				counts[t.coord] += 1
				maxStack = max(maxStack, counts[t.coord])
			}
			for k in 0 ..< maxStack {
				c := Tiled_Csv{w = ly.cWid, h = ly.cHei, data = make(map[int]u32, allocator = context.temp_allocator)}
				seen := make(map[i32]int, allocator = context.temp_allocator)
				for t in ly.gridTiles {
					idx := seen[t.coord]
					seen[t.coord] = idx + 1
					if idx == k && ts != nil do c.data[int(t.coord)] = tile_gid(gids, ts.uid, int(t.t), t.f)
				}
				csv_layer(&x, &layerId, maxStack > 1 ? fmt.tprintf("%s_%d", d.identifier, k + 1) : d.identifier, ly.cWid, ly.cHei, opacity, csv_string(&c))
			}
		case .AutoLayer:
		}
		if d.tilesetUid >= 0 && (d.type == .IntGrid || d.type == .AutoLayer) {
			ts := Ldtk_Doc_LayerTileset(doc, &ly)
			if ts == nil do continue
			layersCsv := make([dynamic]Tiled_Csv, context.temp_allocator)
			misaligned := false
			for t in ly.autoTiles {
				cx, cy := int(t.px.x) / grid, int(t.px.y) / grid
				if int(t.px.x) % grid != 0 || int(t.px.y) % grid != 0 do misaligned = true
				if cx < 0 || cy < 0 || cx >= ly.cWid || cy >= ly.cHei do continue
				k := 0
				coord := cx + cy * ly.cWid
				for k < len(layersCsv) {
					if coord not_in layersCsv[k].data do break
					k += 1
				}
				if k == len(layersCsv) do append(&layersCsv, Tiled_Csv{w = ly.cWid, h = ly.cHei, data = make(map[int]u32, allocator = context.temp_allocator)})
				layersCsv[k].data[cx + cy * ly.cWid] = tile_gid(gids, ts.uid, int(t.t), t.f)
			}
			if misaligned do export_err(r, "Layer %s in level %s has tiles off the grid: they appear shifted in Tiled", d.identifier, LdtkJson_Str(lv.obj, "identifier"))
			for &c, k in layersCsv do csv_layer(&x, &layerId, len(layersCsv) > 1 ? fmt.tprintf("%s_%d", d.identifier, k + 1) : d.identifier, ly.cWid, ly.cHei, opacity, csv_string(&c))
		}
	}
	// nextlayerid / nextobjectid are set last: they end the attribute list
	text := strings.to_string(x.b)
	if x.tag {
		strings.write_byte(&x.b, '>')
		x.tag = false
	}
	strings.write_string(&x.b, "</map>")
	text = strings.to_string(x.b)
	head := strings.index(text, "backgroundcolor=")
	if head >= 0 {
		end := strings.index_byte(text[head + 17:], '"') + head + 18
		text = fmt.tprintf("%s nextlayerid=\"%d\" nextobjectid=\"%d\"%s", text[:end], layerId, objectId, text[end:])
	}
	return text
}

@(private = "file")
tiled_value :: proc(kind: Ldtk_FieldKind, v: ^LdtkJson) -> string {
	if v == nil || v.kind == .Null do return "null"
	#partial switch v.kind {
	case .Number: return js_number(v.num)
	case .Bool: return v.b ? "true" : "false"
	case .String:
		if kind == .Color && strings.has_prefix(v.text, "#") do return fmt.tprintf("#ff%s", v.text[1:])
		return v.text
	case .Object:
		#partial switch kind {
		case .Point: return fmt.tprintf("%d,%d", LdtkJson_Int(v, "cx"), LdtkJson_Int(v, "cy"))
		case .EntityRef: return LdtkJson_Str(v, "entityIid")
		case .Tile: return fmt.tprintf("%d,%d,%d,%d", LdtkJson_Int(v, "x"), LdtkJson_Int(v, "y"), LdtkJson_Int(v, "w"), LdtkJson_Int(v, "h"))
		}
	}
	return LdtkJson_ToString(v, .Minified, context.temp_allocator)
}

// ----------------------------------------------------------------------------
// All exports
// ----------------------------------------------------------------------------

// Ldtk_Doc_RunExports: images, simplified data and Tiled maps as the
// project's options say (the folders of exports that are off are removed);
// an empty "<project name>" folder is removed too.
Ldtk_Doc_RunExports :: proc(doc: ^Ldtk_Doc) -> Ldtk_ExportResult {
	r: Ldtk_ExportResult
	Ldtk_Doc_ExportImages(doc, &r)
	Ldtk_Doc_ExportSimplified(doc, &r)
	Ldtk_Doc_ExportTiled(doc, &r)
	dir := Ldtk_Doc_ExternalDir(doc)
	if os.is_dir(dir) {
		if list, err := os.read_all_directory_by_path(dir, context.temp_allocator); err == nil && len(list) == 0 do _ = os.remove(dir)
	}
	return r
}
