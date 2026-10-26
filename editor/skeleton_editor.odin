package editor

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"
import rl "vendor:raylib"

// ============================================================================
// Skeletons in the editor (engine/docs/skeletal_animation.md): the
// Inspector picks the export (Spine .json with its .atlas, DragonBones
// _ske.json), the animation and skin, previews the animation in the
// viewport (play / scrub), lists the bones - hover or click one to see it
// in the viewport - and attaches a Bone Attachment node to a bone.
// ============================================================================

@(private = "file")
skelPreview: struct {
	node:    ^e.SkeletonNode,
	playing: bool,
}

// skeleton_files: project .json files that are skeleton exports (a Spine
// .json next to its .atlas, or a DragonBones _ske.json), and Spine files
// without an atlas (bones only: rigs for vector skinning).
@(private = "file")
skeleton_files :: proc(state: ^EditorState) -> []string {
	out := make([dynamic]string, context.temp_allocator)
	for f in Editor_ListProjectFiles(state, "", {".json"}) {
		if strings.has_suffix(f, "_ske.json") {
			append(&out, f)
			continue
		}
		if strings.has_suffix(f, ".scene.json") || strings.has_suffix(f, ".import.json") || f == "project.json" do continue
		base := strings.trim_suffix(f, ".json")
		full, _ := filepath.join({state.projectPath, strings.concatenate({base, ".atlas"}, context.temp_allocator)}, context.temp_allocator)
		if os.is_file(full) || skeleton_rig_only(state, f) do append(&out, f)
	}
	return out[:]
}

// skeleton_rig_only: whether a .json is a Spine skeleton (its start has
// "skeleton" and "bones"), remembered per file and modification time.
@(private = "file")
skelRigCache: map[string]struct {mtime: i64, rig: bool}

@(private = "file")
skeleton_rig_only :: proc(state: ^EditorState, rel: string) -> bool {
	full, _ := filepath.join({state.projectPath, rel}, context.temp_allocator)
	mtime: i64
	if fi, err := os.stat(full, context.temp_allocator); err == nil do mtime = fi.modification_time._nsec
	if c, ok := skelRigCache[full]; ok && c.mtime == mtime do return c.rig
	rig := false
	if fh, err := os.open(full); err == nil {
		buf: [512]u8
		n, _ := os.read(fh, buf[:])
		os.close(fh)
		head := string(buf[:max(n, 0)])
		rig = strings.contains(head, "\"skeleton\"") && strings.contains(head, "\"bones\"")
	}
	if skelRigCache == nil do skelRigCache = make(map[string]struct {mtime: i64, rig: bool})
	if _, ok := skelRigCache[full]; !ok do full = strings.clone(full)
	skelRigCache[full] = {mtime, rig}
	return rig
}

inspector_skeleton :: proc(state: ^EditorState, sn: ^e.SkeletonNode) {
	if !UI_SectionHeader("Skeleton") do return
	if !UI_BeginProps("##skel") do return
	UI_PropLabel("File")
	imgui.SetNextItemWidth(field_width())
	if path, ok := asset_picker("insp.skel.file", sn.file, skeleton_files(state)); ok {
		Editor_RecordUndo(state, "Skeleton file")
		sn.file = strings.clone(path, sn.allocator)
	}
	Drive_Item("insp.skel.file")
	UI_Tooltip("A Spine .json export (its .atlas next to it) or a DragonBones _ske.json (its _tex.json next to it)")
	d := sn.data
	if d == nil {
		UI_EndProps()
		if sn.file != "" do UI_DimText("Could not load the skeleton (see the console).")
		else do UI_DimText("Pick a Spine or DragonBones export.")
		return
	}
	UI_PropLabel("Animation")
	imgui.SetNextItemWidth(field_width())
	if imgui.BeginCombo("##skel_anim", fmt.ctprintf("%s", sn.animation if sn.animation != "" else "(setup pose)")) {
		if imgui.Selectable("(setup pose)", sn.animation == "") {
			Editor_RecordUndo(state, "Skeleton animation")
			sn.animation = ""
			sn.animIndex = -1
		}
		for a in d.animations {
			if imgui.Selectable(fmt.ctprintf("%s  (%.2fs)", a.name, a.duration), a.name == sn.animation) {
				Editor_RecordUndo(state, "Skeleton animation")
				sn.animation = strings.clone(a.name, sn.allocator)
				sn.animIndex = e.Skeleton_AnimationIndex(d, a.name)
				sn.time = 0
			}
			Drive_Item(fmt.tprintf("pick:%s", a.name))
		}
		imgui.EndCombo()
	}
	Drive_Item("insp.skel.animation")
	if len(d.skins) > 1 {
		UI_PropLabel("Skin")
		imgui.SetNextItemWidth(field_width())
		if imgui.BeginCombo("##skel_skin", fmt.ctprintf("%s", sn.skin if sn.skin != "" else d.skins[0].name)) {
			for s in d.skins {
				if imgui.Selectable(fmt.ctprintf("%s", s.name), s.name == sn.skin) {
					Editor_RecordUndo(state, "Skeleton skin")
					sn.skin = strings.clone(s.name, sn.allocator)
				}
				Drive_Item(fmt.tprintf("pick:%s", s.name))
			}
			imgui.EndCombo()
		}
		Drive_Item("insp.skel.skin")
	}
	// Preview: play / scrub in the viewport (editing only; the game plays by itself).
	if sn.animIndex >= 0 && sn.animIndex < len(d.animations) && !state.isSimulating {
		dur := d.animations[sn.animIndex].duration
		UI_PropLabel("Preview")
		playing := skelPreview.node == sn && skelPreview.playing
		if UI_IconButton(ICON_FA_PAUSE if playing else ICON_FA_PLAY, "insp.skel.preview", "Pause" if playing else "Play the animation in the viewport", playing, 26) {
			skelPreview = {sn, !playing}
		}
		imgui.SameLine()
		imgui.SetNextItemWidth(imgui.GetContentRegionAvail().x)
		imgui.SliderFloat("##skel_time", &sn.time, 0, max(dur, 0.001), "%.2f s")
		Drive_Item("insp.skel.time")
		if playing {
			sn.time += rl.GetFrameTime() * max(sn.speed, 0.01)
			if dur > 0 && sn.time > dur do sn.time = 0
		}
	}
	UI_EndProps()

	// Bones: hover / click shows one in the viewport; attach a node to it.
	if UI_SectionHeader("Bones") {
		sn.selectedBone = -1
		depth := make([]int, len(d.bones), context.temp_allocator)
		for b, i in d.bones {
			if b.parent >= 0 do depth[i] = depth[b.parent] + 1
			imgui.PushIDInt(i32(i))
			imgui.Indent(f32(depth[i]) * 12 + 1)
			imgui.Selectable(fmt.ctprintf("%s  %s", ICON_FA_BONE, b.name), false, {}, {imgui.GetContentRegionAvail().x - 34, 0})
			Drive_Item(fmt.tprintf("insp.skel.bone:%s", b.name))
			if imgui.IsItemHovered() do sn.selectedBone = i
			imgui.SameLine()
			if UI_IconButton(ICON_FA_LINK, fmt.tprintf("insp.skel.attach:%s", b.name), "Add a Bone Attachment node following this bone", size = 24) {
				Editor_RecordUndo(state, "Attach to bone")
				ba := e.BoneAttachmentNode_Create(state.activeScene, fmt.tprintf("%s_attach", b.name), sn)
				ba.bone = strings.clone(b.name, ba.allocator)
				e.ProcessNodeQueues(state.activeScene.manager, &state.game.gameContext)
				state.selectedNode = ba
				Editor_Log(state, .Info, "Bone Attachment on %s: put a node under it to carry it along", b.name)
			}
			imgui.Unindent(f32(depth[i]) * 12 + 1)
			imgui.PopID()
		}
		UI_DimText(fmt.tprintf("%d bones, %d slots, %d animations", len(d.bones), len(d.slots), len(d.animations)))
	}
}
