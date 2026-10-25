// Package winres writes resources (icon, version info) into a Windows .exe
// with the Win32 resource update API - so it only works on Windows hosts;
// elsewhere Update returns false and the exe keeps the runner's resources.
// The resource data itself comes from engine/export_formats.odin.
package winres

import "core:unicode/utf16"

AVAILABLE :: ODIN_OS == .Windows

// Update replaces the exe's icon (RT_ICON images with ids 1..n and the
// RT_GROUP_ICON directory, id 1 and GLFW_ICON) and its RT_VERSION (id 1).
Update :: proc(exePath: string, icons: [][]u8, group: []u8, version: []u8) -> bool {
	when ODIN_OS == .Windows {
		path := make([]u16, len(exePath) * 2 + 1, context.temp_allocator)
		n := utf16.encode_string(path[:len(path) - 1], exePath)
		path[n] = 0
		h := BeginUpdateResourceW(raw_data(path), false)
		if h == nil do return false
		ok := true
		LANG :: 0x0409 // en-US, like the VERSIONINFO translation
		res :: proc(id: int) -> rawptr {return rawptr(uintptr(id))} // MAKEINTRESOURCE
		if len(group) > 0 {
			for img, i in icons {
				ok &&= bool(UpdateResourceW(h, res(RT_ICON), res(i + 1), LANG, raw_data(img), u32(len(img))))
			}
			ok &&= bool(UpdateResourceW(h, res(RT_GROUP_ICON), res(1), LANG, raw_data(group), u32(len(group))))
			// raylib's own resource (raylib.lib) names its icon GLFW_ICON:
			// GLFW loads it for the window, and Explorer shows the first
			// group - named ones sort before numbered ones. Ours there too.
			glfw := []u16{'G', 'L', 'F', 'W', '_', 'I', 'C', 'O', 'N', 0}
			ok &&= bool(UpdateResourceW(h, res(RT_GROUP_ICON), raw_data(glfw), LANG, raw_data(group), u32(len(group))))
		}
		if len(version) > 0 {
			ok &&= bool(UpdateResourceW(h, res(RT_VERSION), res(1), LANG, raw_data(version), u32(len(version))))
		}
		return bool(EndUpdateResourceW(h, !ok)) && ok
	} else {
		return false
	}
}

when ODIN_OS == .Windows {
	RT_ICON       :: 3
	RT_GROUP_ICON :: 14
	RT_VERSION    :: 16

	foreign import kernel32 "system:Kernel32.lib"

	@(default_calling_convention = "system")
	foreign kernel32 {
		BeginUpdateResourceW :: proc(pFileName: [^]u16, bDeleteExistingResources: b32) -> rawptr ---
		UpdateResourceW :: proc(hUpdate: rawptr, lpType: rawptr, lpName: rawptr, wLanguage: u16, lpData: rawptr, cb: u32) -> b32 ---
		EndUpdateResourceW :: proc(hUpdate: rawptr, fDiscard: b32) -> b32 ---
	}
}
