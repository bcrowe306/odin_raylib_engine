package editor

import "core:testing"
import "core:time"

@(test)
test_file_browser_kinds :: proc(t: ^testing.T) {
	testing.expect_value(t, FileBrowser_KindOf("ship.PNG"), FB_Kind.Image)
	testing.expect_value(t, FileBrowser_KindOf("boom.ogg"), FB_Kind.Audio)
	testing.expect_value(t, FileBrowser_KindOf("intro.mp4"), FB_Kind.Video)
	testing.expect_value(t, FileBrowser_KindOf("pixel.ttf"), FB_Kind.Font)
	testing.expect_value(t, FileBrowser_KindOf("hero.aseprite"), FB_Kind.Aseprite)
	testing.expect_value(t, FileBrowser_KindOf("logo.svg"), FB_Kind.Vector)
	testing.expect_value(t, FileBrowser_KindOf("level.scene.json"), FB_Kind.Text)
	testing.expect_value(t, FileBrowser_KindOf("archive.zip"), FB_Kind.Other)
}

@(test)
test_file_browser_filter :: proc(t: ^testing.T) {
	png := FB_Entry{name = "Crate.png", kind = .Image}
	wav := FB_Entry{name = "blip.wav", kind = .Audio}
	lua := FB_Entry{name = "player.lua", kind = .Text}
	txt := FB_Entry{name = "notes.txt", kind = .Text}
	dir := FB_Entry{name = "Sprites", isDir = true, kind = .Folder}

	testing.expect(t, FileBrowser_Matches(png, .All, ""), "all")
	testing.expect(t, FileBrowser_Matches(png, .Images, ""), "image filter")
	testing.expect(t, !FileBrowser_Matches(wav, .Images, ""), "a sound isn't an image")
	testing.expect(t, FileBrowser_Matches(wav, .Audio, ""), "audio filter")
	// Game assets: what the importer knows, not any text file.
	testing.expect(t, FileBrowser_Matches(lua, .Game_Assets, ""), "a script is a game asset")
	testing.expect(t, !FileBrowser_Matches(txt, .Game_Assets, ""), "notes aren't")
	// Folders stay (to browse into) whatever the filter; the search
	// ignores case.
	testing.expect(t, FileBrowser_Matches(dir, .Audio, ""), "folders pass the type filter")
	testing.expect(t, FileBrowser_Matches(png, .All, "crate"), "case-insensitive search")
	testing.expect(t, !FileBrowser_Matches(png, .All, "ship"), "search miss")
	testing.expect(t, !FileBrowser_Matches(dir, .All, "ship"), "a folder that doesn't match")
}

@(test)
test_file_browser_sort :: proc(t: ^testing.T) {
	rows := []FB_Entry{
		{name = "b.png", size = 10, mod = time.unix(300, 0), kind = .Image},
		{name = "Zeta", isDir = true, kind = .Folder},
		{name = "a.wav", size = 30, mod = time.unix(100, 0), kind = .Audio},
		{name = "C.lua", size = 20, mod = time.unix(200, 0), kind = .Text},
		{name = "alpha", isDir = true, kind = .Folder},
	}
	names :: proc(rows: []FB_Entry) -> [5]string {
		out: [5]string
		for r, i in rows do out[i] = r.name
		return out
	}
	// Folders first; names ignore case.
	FileBrowser_Sort(rows, .Name, false)
	testing.expect_value(t, names(rows), [5]string{"alpha", "Zeta", "a.wav", "b.png", "C.lua"})
	FileBrowser_Sort(rows, .Name, true)
	testing.expect_value(t, names(rows), [5]string{"Zeta", "alpha", "C.lua", "b.png", "a.wav"})
	FileBrowser_Sort(rows, .Size, false)
	testing.expect_value(t, names(rows), [5]string{"alpha", "Zeta", "b.png", "C.lua", "a.wav"})
	FileBrowser_Sort(rows, .Modified, true)
	testing.expect_value(t, names(rows), [5]string{"alpha", "Zeta", "b.png", "C.lua", "a.wav"})
	FileBrowser_Sort(rows, .Type, false)
	testing.expect_value(t, names(rows), [5]string{"alpha", "Zeta", "C.lua", "b.png", "a.wav"})
}

@(test)
test_file_browser_size_text :: proc(t: ^testing.T) {
	testing.expect_value(t, FileBrowser_SizeText(512), "512 B")
	testing.expect_value(t, FileBrowser_SizeText(2048), "2.0 KB")
	testing.expect_value(t, FileBrowser_SizeText(5 * 1024 * 1024), "5.0 MB")
}
