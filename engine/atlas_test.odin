package engine

import "core:math/rand"
import os "osx"
import "core:testing"
import rl "vendor:raylib"

// Sprite atlases: the packer places every rectangle without overlaps inside
// its page (too-big ones left out); export packs the flagged textures (not
// mipmapped ones) into a page with their pixels and edge extrusion, plus
// atlas.json; a package with it gives atlased textures the page and their
// rectangle (sizes and source rects in page coordinates), "own" loads a
// separate texture, and releasing frees everything (leak tracker).
@(test)
test_sprite_atlas :: proc(t: ^testing.T) {
	// Packer.
	r := rand.create(7)
	context.random_generator = rand.default_random_generator(&r)
	sizes := make([][2]int, 120, context.temp_allocator)
	for &s in sizes do s = {8 + rand.int_max(120), 8 + rand.int_max(120)}
	sizes[5] = {600, 20}
	sizes[6] = {700, 700} // bigger than the page
	pos, pages := Atlas_Pack(sizes, 512, context.temp_allocator)
	testing.expect_value(t, pos[6][0], -1)
	for a in 0 ..< len(sizes) {
		if a == 6 do continue
		pa := pos[a]
		if a == 5 {
			testing.expect_value(t, pa[0], -1) // (600 wide: no page of 512)
			continue
		}
		testing.expectf(t, pa[0] >= 0 && pa[1] >= 0 && pa[2] >= 0 && pa[1] + sizes[a].x <= 512 && pa[2] + sizes[a].y <= 512, "inside its page: %v %v", pa, sizes[a])
		testing.expect(t, pages[pa[0]].x >= pa[1] + sizes[a].x && pages[pa[0]].y >= pa[2] + sizes[a].y, "within the page's used size")
		for b in a + 1 ..< len(sizes) {
			pb := pos[b]
			if pb[0] != pa[0] || b == 5 || b == 6 do continue
			overlap := pa[1] < pb[1] + sizes[b].x && pb[1] < pa[1] + sizes[a].x && pa[2] < pb[2] + sizes[b].y && pb[2] < pa[2] + sizes[a].y
			testing.expectf(t, !overlap, "%d and %d overlap", a, b)
		}
	}
	testing.expectf(t, len(pages) <= 4, "packed tightly (%d pages)", len(pages))

	// Export.
	dir :: "test_atlas_zz"
	_ = os.make_directory_all(dir + "/textures")
	defer os.remove_all(dir)
	defer Asset_ImportsReset()
	colors := [3]rl.Color{rl.RED, rl.GREEN, rl.BLUE}
	names := [3]cstring{dir + "/textures/a.png", dir + "/textures/b.png", dir + "/textures/c.png"}
	for c, i in colors {
		img := rl.GenImageColor(i32(10 + i * 6), 8, c)
		rl.ImageDrawPixel(&img, 0, 0, rl.WHITE) // a corner to check the extrusion
		rl.ExportImage(img, names[i])
		rl.UnloadImage(img)
	}
	_ = os.write_entire_file(dir + "/textures/a.png.import.json", transmute([]u8)string(`{"atlas": true}`))
	_ = os.write_entire_file(dir + "/textures/b.png.import.json", transmute([]u8)string(`{"atlas": true}`))
	_ = os.write_entire_file(dir + "/textures/c.png.import.json", transmute([]u8)string(`{"atlas": true, "mipmaps": true}`))
	_ = os.write_entire_file(dir + "/project.json", transmute([]u8)string(`{"name": "AtlasZz"}`))
	overrides := make(map[string][]u8, context.temp_allocator)
	sprites, pageCount := Atlas_Build(dir, &overrides, allocator = context.temp_allocator)
	testing.expectf(t, sprites == 2 && pageCount == 1, "two packed (the mipmapped one left out): %d on %d", sprites, pageCount)
	testing.expect(t, ATLAS_JSON in overrides && "atlas/page_0.png" in overrides, "page and atlas.json")
	ix: Atlas_Index
	testing.expect(t, Atlas_Parse(&ix, string(overrides[ATLAS_JSON])), "atlas.json parses")
	ea, hasA := ix.entries["textures/a.png"]
	_, hasC := ix.entries["textures/c.png"]
	testing.expect(t, hasA && !hasC && ea.rect.width == 10 && ea.rect.height == 8, "a's rectangle")
	png := overrides["atlas/page_0.png"]
	page := rl.LoadImageFromMemory(".png", raw_data(png), i32(len(png)))
	x, y := i32(ea.rect.x), i32(ea.rect.y)
	testing.expect(t, rl.GetImageColor(page, x + 3, y + 3) == rl.RED, "a's pixels")
	testing.expect(t, rl.GetImageColor(page, x - 1, y - 1) == rl.WHITE && rl.GetImageColor(page, x - 2, y + 3) == rl.RED, "edges repeated into the gap")
	rl.UnloadImage(page)
	vmem_destroy_index(&ix)

	// Runtime: a package with the atlas.
	rayzr :: dir + "/game.rayzr"
	testing.expect(t, RayzrPackage_CreateFromDirectory(dir, rayzr, true, overrides = overrides), "package")
	pkg, ok := RayzrPackage_Open(rayzr)
	testing.expect(t, ok, "opens")
	if !ok do return
	defer RayzrPackage_Close(pkg)
	rm: ResourceManager
	ResourceManager_Init(&rm)
	rm.package_ = pkg
	testing.expect(t, Atlas_Mount(&rm) && len(rm.atlas.entries) == 2, "mounted")
	ta, okA := LoadTexture_FilePath(&rm, "textures/a.png")
	testing.expect(t, okA && ta.page == 1 && ta.region == ea.rect, "atlased: the page and its rectangle")
	testing.expect_value(t, Texture_Size(ta), [2]f32{10, 8})
	testing.expect_value(t, Texture_Src(ta, {2, 1, -4, 3}), rl.Rectangle{ea.rect.x + 2, ea.rect.y + 1, -4, 3})
	tb, _ := LoadTexture_FilePath(&rm, "textures/b.png")
	testing.expect(t, tb.page == 1 && rm.atlas.pages[0].refs == 2, "b on the same page (one reference each)")
	own, okOwn := ResourceManager_LoadTextureOwn(&rm, "textures/a.png")
	testing.expect(t, okOwn && own != ta && own.page == 0 && own.region == {}, "own: a separate texture")
	again, _ := LoadTexture_FilePath(&rm, "textures/a.png")
	testing.expect(t, again == ta && ta.refCount == 2, "cached")
	ResourceManager_ReleaseTexture(&rm, again)
	ResourceManager_ReleaseTexture(&rm, ta)
	ResourceManager_ReleaseTexture(&rm, tb)
	testing.expect_value(t, rm.atlas.pages[0].refs, 0)
	ResourceManager_Terminate(&rm)
	testing.expect(t, !rm.atlas.ready, "unmounted with the resource manager")
}

@(private = "file")
vmem_destroy_index :: proc(ix: ^Atlas_Index) {
	rm := ResourceManager{atlas = ix^}
	Atlas_Unmount(&rm)
	ix^ = {}
}
