package editor

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"
import rl "vendor:raylib"

// ============================================================================
// Aseprite in the editor (TODO E.3; engine/aseprite*.odin reads, renders
// and plays the files):
//   - Assets: an Aseprite section; thumbnails are the first frame;
//     dragging one into the viewport adds an AsepriteNode playing its first
//     tag; double-click / right-click > Edit in Aseprite opens it there -
//     saving there updates the editor at once (the file is watched).
//   - The Inspector's Aseprite section: the file, the tag (with its
//     direction / repeats / length), a frame slider with a preview (plays
//     in the viewport), every layer's visibility (overrides per node), the
//     pivot slice, the file's slices and user data.
//   - Settings > General > Aseprite: the program (else found where it
//     installs: the app, Steam, the PATH).
// ============================================================================

@(private = "file")
asePreview: struct {
	node:    ^e.AsepriteNode,
	playing: bool,
}

// lastAsepriteOpen: the file the last Edit in Aseprite asked for (drives).
lastAsepriteOpen: string

// Aseprite_FindProgram: the Aseprite executable ("" = not found).
Aseprite_FindProgram :: proc() -> string {
	if p := GlobalSettings.asepritePath; p != "" do return p
	home, _ := os.user_home_dir(context.temp_allocator)
	candidates: []string
	when ODIN_OS == .Darwin {
		candidates = {
			"/Applications/Aseprite.app/Contents/MacOS/aseprite",
			fmt.tprintf("%s/Applications/Aseprite.app/Contents/MacOS/aseprite", home),
			fmt.tprintf("%s/Library/Application Support/Steam/steamapps/common/Aseprite/Aseprite.app/Contents/MacOS/aseprite", home),
		}
	} else when ODIN_OS == .Windows {
		candidates = {
			"C:/Program Files/Aseprite/Aseprite.exe",
			"C:/Program Files (x86)/Aseprite/Aseprite.exe",
			"C:/Program Files (x86)/Steam/steamapps/common/Aseprite/Aseprite.exe",
			"C:/Program Files/Steam/steamapps/common/Aseprite/Aseprite.exe",
		}
	} else {
		candidates = {
			"/usr/bin/aseprite",
			"/usr/local/bin/aseprite",
			fmt.tprintf("%s/.steam/steam/steamapps/common/Aseprite/aseprite", home),
			fmt.tprintf("%s/.local/share/Steam/steamapps/common/Aseprite/aseprite", home),
		}
	}
	for c in candidates do if os.is_file(c) do return c
	return ""
}

// Aseprite_DefaultPath: what the settings field shows when empty.
Aseprite_DefaultPath :: proc() -> string {
	if p := Aseprite_FindProgram(); p != "" && GlobalSettings.asepritePath == "" do return fmt.tprintf("found: %s", p)
	return "the Aseprite program (not found: set it here)"
}

// Aseprite_Edit opens a file in Aseprite (else the system's app for it).
Aseprite_Edit :: proc(state: ^EditorState, full: string) {
	abs := full
	if a, err := os.get_absolute_path(full, context.temp_allocator); err == nil do abs = a
	delete(lastAsepriteOpen)
	lastAsepriteOpen = strings.clone(abs)
	if GlobalDrive.enabled {
		Editor_Log(state, .Info, "Would open in Aseprite: %s", abs) // (drives: no program)
		return
	}
	prog := Aseprite_FindProgram()
	if prog == "" {
		Editor_Log(state, .Warn, "Aseprite not found (Settings > General > Aseprite): opening %s with the system's app", filepath.base(abs))
		Editor_OpenExternally(state, abs)
		return
	}
	if _, err := os.process_start({command = {prog, abs}}); err != nil {
		Editor_Log(state, .Error, "Could not start Aseprite (%s): %v", prog, err)
		return
	}
	Editor_Log(state, .Info, "Editing %s in Aseprite (saving there updates the editor)", filepath.base(abs))
}

@(private = "file")
aseprite_files :: proc(state: ^EditorState) -> []string {
	return Editor_ListProjectFiles(state, "", {".aseprite", ".ase"})
}

// inspector_aseprite: the Inspector's Aseprite section.
inspector_aseprite :: proc(state: ^EditorState, an: ^e.AsepriteNode) {
	if !UI_SectionHeader("Aseprite") do return
	if !UI_BeginProps("##ase") do return
	UI_PropLabel("File")
	imgui.SetNextItemWidth(field_width() - 30)
	if path, ok := asset_picker("insp.ase.file", an.file, aseprite_files(state)); ok {
		Editor_RecordUndo(state, "Aseprite file")
		an.file = strings.clone(path, an.allocator)
	}
	UI_Tooltip("An Aseprite file (.aseprite / .ase) in the project")
	imgui.SameLine(0, 4)
	if UI_IconButton(ICON_FA_PEN_TO_SQUARE, "insp.ase.edit", "Edit in Aseprite (saving there updates it here)", false, 26) && an.file != "" {
		Aseprite_Edit(state, e.Project_ResolveAssetPath(&state.game.gameContext, an.file))
	}
	size := e.AsepriteNode_Size(an) // (loads it)
	r := an.res
	if r == nil {
		UI_EndProps()
		if an.file != "" do UI_DimText("Could not load the file (see the console).")
		else do UI_DimText("Pick an Aseprite file, or drag one from Assets into the viewport.")
		return
	}
	doc := r.doc

	// The tag.
	UI_PropLabel("Animation")
	imgui.SetNextItemWidth(field_width())
	tagLabel :: proc(doc: ^e.Ase_Document, t: e.Ase_Tag) -> cstring {
		ms := 0
		for f in t.from ..= t.to do if f < len(doc.frames) do ms += doc.frames[f].duration
		reps := "loops" if t.repeats == 0 else fmt.tprintf("x%d", t.repeats)
		return fmt.ctprintf("%s  (frames %d-%d, %v, %s, %d ms)", t.name, t.from, t.to, t.direction, reps, ms)
	}
	current := "(every frame)"
	for t in doc.tags do if t.name == an.animation do current = t.name
	if imgui.BeginCombo("##ase_tag", strings.clone_to_cstring(current, context.temp_allocator), {.HeightLarge}) {
		if imgui.Selectable("(every frame)", an.animation == "") {
			Editor_RecordUndo(state, "Aseprite animation")
			an.animation = ""
			e.AsepriteNode_Play(an, "")
			an.playing = asePreview.node == an && asePreview.playing
		}
		for t in doc.tags {
			if imgui.Selectable(tagLabel(doc, t), t.name == an.animation) {
				Editor_RecordUndo(state, "Aseprite animation")
				an.animation = strings.clone(t.name, an.allocator)
				e.AsepriteNode_Play(an, t.name)
				an.playing = asePreview.node == an && asePreview.playing
			}
			Drive_Item(fmt.tprintf("insp.ase.tag:%s", t.name))
		}
		if len(doc.tags) == 0 do UI_DimText("No tags in this file (Aseprite: Frame > Tags)")
		imgui.EndCombo()
	}
	Drive_Item("insp.ase.tag")
	UI_Tooltip("The tag played: its direction and repeat count are Aseprite's")

	// Frame + preview.
	if !state.isSimulating {
		UI_PropLabel("Frame")
		playing := asePreview.node == an && asePreview.playing
		if UI_IconButton(ICON_FA_PAUSE if playing else ICON_FA_PLAY, "insp.ase.preview", "Pause" if playing else "Play the tag in the viewport", playing, 26) {
			if playing {
				asePreview = {}
				e.AsepriteNode_Stop(an)
			} else {
				asePreview = {an, true}
				e.AsepriteNode_Play(an, an.animation)
			}
		}
		imgui.SameLine()
		imgui.SetNextItemWidth(imgui.GetContentRegionAvail().x)
		f := i32(an.frame)
		if imgui.SliderInt("##ase_frame", &f, 0, i32(max(len(doc.frames) - 1, 0)), fmt.ctprintf("%%d  (%d ms)", doc.frames[clamp(int(f), 0, len(doc.frames) - 1)].duration)) {
			an.frame = int(f)
		}
		Drive_Item("insp.ase.frame")
		// (The editor doesn't update nodes outside Simulate: the preview advances here.)
		if playing {
			e.AsepriteNode_Update(an, &state.game.gameContext, rl.GetFrameTime())
			if !an.playing do e.AsepriteNode_Play(an, an.animation) // (a finished tag starts over)
		}
	}

	// The pivot slice.
	UI_PropLabel("Pivot Slice")
	imgui.SetNextItemWidth(field_width())
	if imgui.BeginCombo("##ase_pivot", strings.clone_to_cstring(an.pivotSlice if an.pivotSlice != "" else "(the node's pivot)", context.temp_allocator)) {
		if imgui.Selectable("(the node's pivot)", an.pivotSlice == "") {
			Editor_RecordUndo(state, "Aseprite pivot")
			an.pivotSlice = ""
		}
		for s in doc.slices do if s.has_pivot {
			if imgui.Selectable(strings.clone_to_cstring(s.name, context.temp_allocator), s.name == an.pivotSlice) {
				Editor_RecordUndo(state, "Aseprite pivot")
				an.pivotSlice = strings.clone(s.name, an.allocator)
			}
			Drive_Item(fmt.tprintf("insp.ase.pivot:%s", s.name))
		}
		imgui.EndCombo()
	}
	Drive_Item("insp.ase.pivot")
	UI_Tooltip("A slice with a pivot (Aseprite: Slice tool, then the slice's properties): the origin follows it frame by frame")
	UI_PropLabel("Size")
	UI_DimText(fmt.tprintf("%dx%d, %d frames, %d tags, %d layers%s", int(size.x), int(size.y), len(doc.frames), len(doc.tags), len(doc.layers),
		fmt.tprintf(", %d slices", len(doc.slices)) if len(doc.slices) > 0 else ""))
	UI_EndProps()

	// Layers: visible as in the file, overridden per node.
	if UI_SectionHeader("Aseprite Layers", false) {
		vis := e.Ase_LayerOverrides(doc, an.hideLayers, an.showLayers, context.temp_allocator)
		for l, i in doc.layers {
			depth := 0
			for p := l.parent; p >= 0; p = doc.layers[p].parent do depth += 1
			imgui.Indent(f32(depth) * 14 + 1)
			on := vis[i] if vis != nil else .Visible in l.flags
			label := fmt.ctprintf("%s%s##ase_layer_%d", l.name, " (group)" if l.kind == .Group else (" (tilemap)" if l.kind == .Tilemap else (" (reference)" if .Reference in l.flags else "")), i)
			if imgui.Checkbox(label, &on) {
				Editor_RecordUndo(state, "Aseprite layer")
				aseprite_set_layer(an, doc, l.name, on, .Visible in l.flags)
			}
			Drive_Item(fmt.tprintf("insp.ase.layer:%s", l.name))
			if l.user.text != "" do UI_Tooltip(l.user.text)
			imgui.Unindent(f32(depth) * 14 + 1)
		}
	}

	// What scripts can read: slices and user data.
	if (len(doc.slices) > 0 || doc.user.text != "") && UI_SectionHeader("Aseprite Data", false) {
		if doc.user.text != "" do UI_DimText(fmt.tprintf("Sprite: %s", doc.user.text))
		for &s in doc.slices {
			k, _ := e.Ase_SliceKey(&s, an.frame)
			extra := ""
			if s.nine_patch do extra = fmt.tprintf("%s, 9-patch", extra)
			if s.has_pivot do extra = fmt.tprintf("%s, pivot %d,%d", extra, k.pivot[0], k.pivot[1])
			imgui.TextUnformatted(fmt.ctprintf("%s  %d,%d %dx%d%s", s.name, k.x, k.y, k.w, k.h, extra))
			if s.user.text != "" do UI_Tooltip(s.user.text)
		}
		UI_DimText("Scripts: node:aseprite_slice(name), aseprite_layer_data, aseprite_cel_data, aseprite_info")
	}
}

// aseprite_set_layer: a layer shown / hidden for this node (an override
// only where it differs from the file).
@(private = "file")
aseprite_set_layer :: proc(an: ^e.AsepriteNode, doc: ^e.Ase_Document, name: string, on, inFile: bool) {
	drop :: proc(an: ^e.AsepriteNode, list: ^string, name: string) {
		parts := make([dynamic]string, context.temp_allocator)
		for p in strings.split(list^, ",", context.temp_allocator) {
			q := strings.trim_space(p)
			if q != "" && q != name do append(&parts, q)
		}
		list^ = strings.join(parts[:], ",", an.allocator)
	}
	add :: proc(an: ^e.AsepriteNode, list: ^string, name: string) {
		list^ = strings.concatenate({list^, "," if list^ != "" else "", name}, an.allocator)
	}
	drop(an, &an.hideLayers, name)
	drop(an, &an.showLayers, name)
	if on && !inFile do add(an, &an.showLayers, name)
	if !on && inFile do add(an, &an.hideLayers, name)
}

// Aseprite_DriveQuery: aseprite-open (the last Edit in Aseprite's file).
Aseprite_DriveQuery :: proc(q: string) -> (string, bool) {
	if q == "aseprite-open" do return lastAsepriteOpen, true
	return "", false
}
