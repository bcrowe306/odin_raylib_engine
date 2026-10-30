package editor

import "core:fmt"
import "core:mem"
import "core:slice"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Inspector field helpers shared by every section:
//   - X/Y fields with a link toggle (linked: editing one scales the other by
//     the same ratio, like Godot's scale lock)
//   - a reset button after every field, shown when the value differs from
//     the default (defaults come from a pristine node of the same type, a
//     script's declared default, or a fixed value)
// ============================================================================

FIELD_RESET_W :: f32(24)

@(private = "file")
linkedFields: map[string]bool

@(private = "file")
defaultsScene: ^e.Scene
@(private = "file")
defaultNodes: map[typeid]^e.Node

// Editor_DefaultNode: an untouched node of the same type (cached), the
// source of default values for reset buttons.
Editor_DefaultNode :: proc(node: ^e.Node) -> ^e.Node {
	if node == nil do return nil
	if n, ok := defaultNodes[node.typeId]; ok do return n
	if defaultsScene == nil {
		defaultsScene = new(e.Scene)
		e.InitializeScene(defaultsScene)
		defaultNodes = make(map[typeid]^e.Node)
	}
	n := e.Node_CreateByTypeName(defaultsScene, e.Node_TypeName(node))
	if n != nil do e.ProcessNodeQueues(defaultsScene.manager, nil)
	defaultNodes[node.typeId] = n
	return n
}

InspectorFields_Shutdown :: proc() {
	if defaultsScene != nil {
		e.TerminateScene(defaultsScene)
		free(defaultsScene)
		defaultsScene = nil
	}
	delete(defaultNodes)
	delete(linkedFields)
}

// field_width: the width left for a widget that is followed by a reset button.
field_width :: proc() -> f32 {
	return max(imgui.GetContentRegionAvail().x - FIELD_RESET_W, 40)
}

// field_reset draws the reset button after a widget (an empty slot when
// the value is already the default). Returns true when clicked.
field_reset :: proc(id: string, modified: bool) -> bool {
	// Right-aligned in the cell, whatever the widget's width.
	imgui.SameLine(0, 0)
	imgui.SetCursorPosX(imgui.GetCursorPosX() + max(imgui.GetContentRegionAvail().x - FIELD_RESET_W + 2, 2))
	if !modified {
		imgui.Dummy({FIELD_RESET_W - 2, imgui.GetFrameHeight()})
		return false
	}
	imgui.PushStyleVarImVec2(.FramePadding, {3, 3})
	clicked := UI_IconButton(ICON_FA_ROTATE_LEFT, fmt.tprintf("%s.reset", id), "Reset to default", size = FIELD_RESET_W - 2)
	imgui.PopStyleVar()
	return clicked
}

// --- vectors -----------------------------------------------------------------------

// vec2_edit: X/Y drag fields with coloured markers, a link toggle and a
// reset button (to `def`). Returns true when the value changed.
// undo: records an undo step before a change (nil = the active scene's
// snapshot, Editor_RecordUndo).
Vec2_Undo :: proc(state: ^EditorState, label: string, data: rawptr)

vec2_edit :: proc(state: ^EditorState, id: string, v: ^[2]f32, speed: f32, undoLabel: string, def: [2]f32 = {0, 0}, mixed := [2]bool{}, undo: Vec2_Undo = nil, undoData: rawptr = nil) -> bool {
	record :: proc(state: ^EditorState, label: string, undo: Vec2_Undo, data: rawptr) {
		if undo != nil do undo(state, label, data)
		else do Editor_RecordUndo(state, label)
	}
	if id not_in linkedFields do linkedFields[strings.clone(id)] = strings.contains(id, "scale")
	linked := linkedFields[id]
	avail := imgui.GetContentRegionAvail().x
	w := (avail - UI_SPACE - FIELD_RESET_W - 26) * 0.5
	axis :: proc(color: imgui.Vec4) {
		pos := imgui.GetCursorScreenPos()
		dl := imgui.GetWindowDrawList()
		h := imgui.GetFrameHeight()
		imgui.DrawList_AddRectFilled(dl, {pos.x, pos.y + 4}, {pos.x + 2, pos.y + h - 4}, col_u32(color), 1, {})
	}
	old := v^
	changed := false
	axis(UI_DANGER)
	imgui.SetNextItemWidth(w)
	if imgui.DragFloat(fmt.ctprintf("##%s.x", id), &v.x, speed, 0, 0, MIXED_TEXT if mixed.x else "%.2f") {
		changed = true
		if linked do v.y = old.y * (v.x / old.x) if old.x != 0 else v.y + (v.x - old.x)
	}
	if imgui.IsItemActivated() do record(state, undoLabel, undo, undoData)
	Drive_Item(fmt.tprintf("%s.x", id))
	imgui.SameLine(0, UI_SPACE)
	axis(UI_SUCCESS)
	imgui.SetNextItemWidth(w)
	if imgui.DragFloat(fmt.ctprintf("##%s.y", id), &v.y, speed, 0, 0, MIXED_TEXT if mixed.y else "%.2f") {
		changed = true
		if linked do v.x = old.x * (v.y / old.y) if old.y != 0 else v.x + (v.y - old.y)
	}
	if imgui.IsItemActivated() do record(state, undoLabel, undo, undoData)
	Drive_Item(fmt.tprintf("%s.y", id))
	imgui.SameLine(0, 2)
	imgui.PushStyleVarImVec2(.FramePadding, {3, 3})
	if UI_IconButton(ICON_FA_LINK if linked else ICON_FA_LINK_SLASH, fmt.tprintf("%s.link", id), "Unlink X and Y" if linked else "Link X and Y (keep the ratio)", linked, 24) {
		linkedFields[id] = !linked
	}
	imgui.PopStyleVar()
	if field_reset(id, v^ != def) {
		record(state, fmt.tprintf("Reset %s", undoLabel), undo, undoData)
		v^ = def
		changed = true
	}
	return changed
}

// --- reflected properties ----------------------------------------------------------

@(private = "file")
defaultPhysicsShape: e.PhysicsShape

// prop_default: the same property on a pristine node of the node's type.
prop_default :: proc(node: ^e.Node, p: e.Node_Property) -> (e.Node_Property, bool) {
	if p.owner == "PhysicsShape" {
		e.PhysicsShape_InitDefault(&defaultPhysicsShape, .Box)
		for sp in e.Struct_CollectProperties(e.PhysicsShape, &defaultPhysicsShape) {
			if sp.name == p.name do return sp, true
		}
		return {}, false
	}
	d := Editor_DefaultNode(node)
	if d == nil do return {}, false
	return e.Node_FindProperty(d, p.name)
}

prop_is_default :: proc(p, d: e.Node_Property) -> bool {
	if p.kind == .String do return (^string)(p.ptr)^ == (^string)(d.ptr)^
	if p.kind == .String_List do return slice.equal(e.Property_GetList(p), e.Property_GetList(d))
	return mem.compare_ptrs(p.ptr, d.ptr, p.type.size) == 0
}

prop_reset :: proc(state: ^EditorState, node: ^e.Node, p, d: e.Node_Property) {
	Editor_RecordUndo(state, fmt.tprintf("Reset %s", p.name))
	if p.kind == .String {
		e.Property_SetString(node, p, (^string)(d.ptr)^)
		return
	}
	if p.kind == .String_List {
		e.Property_SetList(node, p, e.Property_GetList(d))
		return
	}
	mem.copy(p.ptr, d.ptr, p.type.size)
}

// reset_after: the reset button for a value with a fixed default.
reset_after :: proc(state: ^EditorState, id: string, v: ^$T, def: T, label: string) -> bool {
	if field_reset(id, v^ != def) {
		Editor_RecordUndo(state, fmt.tprintf("Reset %s", label))
		v^ = def
		return true
	}
	return false
}
