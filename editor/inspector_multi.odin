package editor

import "core:c"
import "core:fmt"
import "core:mem"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Multi-edit: with several nodes selected, the Inspector shows the primary
// node; a property all of them have shows "—" where their values differ, and
// an edit is applied to every one of them (for x/y pairs and flag sets only
// the part that changed, so differing positions keep their other axis).
//
//     m := multi_begin(state, node, p)
//     ...widget showing m.mixed...
//     multi_end(&m)
// ============================================================================

MIXED_TEXT :: "—"

// ImGuiItemFlags_MixedValue (imgui_internal.h): a checkbox draws a dash.
ITEM_FLAG_MIXED_VALUE :: c.int(1 << 12)

Multi_Target :: struct {
	node: ^e.Node,
	prop: e.Node_Property,
}

Multi_Edit :: struct {
	node:    ^e.Node,
	prop:    e.Node_Property,
	others:  []Multi_Target,
	mixed:   [2]bool, // [0] the value (x for pairs), [1] y
	before:  [64]u8,
	beforeS: string,
}

// multi_selection: the selected nodes still alive (an undo rebuilds the
// scene before the selection is synced).
multi_selection :: proc(state: ^EditorState) -> []^e.Node {
	out := make([dynamic]^e.Node, context.temp_allocator)
	for n in state.selection do if e.Node_IsAlive(n) do append(&out, n)
	return out[:]
}

// multi_others: the same property on the other selected nodes (those that
// have it with the same type). Node base fields (position, layer...) are at
// the same offset in every node; struct values that aren't the node's own
// properties (a collision shape's fields) are never shared.
multi_others :: proc(state: ^EditorState, node: ^e.Node, p: e.Node_Property) -> []Multi_Target {
	sel := multi_selection(state)
	if len(sel) < 2 || node != state.selectedNode do return nil
	offset := uintptr(p.ptr) - uintptr(node)
	isBase := uintptr(p.ptr) >= uintptr(node) && offset < size_of(e.Node)
	if !isBase {
		own, ok := e.Node_FindProperty(node, p.name)
		if !ok || own.ptr != p.ptr do return nil
	}
	out := make([dynamic]Multi_Target, context.temp_allocator)
	for n in sel {
		if n == node do continue
		if isBase {
			q := p
			q.ptr = rawptr(uintptr(n) + offset)
			append(&out, Multi_Target{n, q})
		} else if q, ok := e.Node_FindProperty(n, p.name); ok && q.type.id == p.type.id {
			append(&out, Multi_Target{n, q})
		}
	}
	return out[:]
}

// multi_shared: every other selected node has the property.
multi_shared :: proc(state: ^EditorState, node: ^e.Node, p: e.Node_Property) -> bool {
	return len(multi_others(state, node, p)) == len(multi_selection(state)) - 1
}

multi_begin :: proc(state: ^EditorState, node: ^e.Node, p: e.Node_Property) -> (m: Multi_Edit) {
	m.node, m.prop = node, p
	m.others = multi_others(state, node, p)
	if len(m.others) == 0 do return
	if p.kind == .String {
		m.beforeS = strings.clone((^string)(p.ptr)^, context.temp_allocator)
	} else {
		mem.copy(&m.before, p.ptr, min(p.type.size, len(m.before)))
	}
	for o in m.others {
		switch p.kind {
		case .Vec2:
			a, b := (^[2]f32)(p.ptr)^, (^[2]f32)(o.prop.ptr)^
			if a.x != b.x do m.mixed[0] = true
			if a.y != b.y do m.mixed[1] = true
		case .String:
			if (^string)(p.ptr)^ != (^string)(o.prop.ptr)^ do m.mixed[0] = true
		case .Float, .Int, .Bool, .Color, .Enum, .Bit_Set:
			if mem.compare_ptrs(p.ptr, o.prop.ptr, p.type.size) != 0 do m.mixed[0] = true
		}
	}
	return
}

// multi_end: copies what the widget changed on the primary to the others.
multi_end :: proc(m: ^Multi_Edit) {
	if len(m.others) == 0 do return
	p := m.prop
	switch p.kind {
	case .String:
		now := (^string)(p.ptr)^
		if now == m.beforeS do return
		for o in m.others do e.Property_SetString(o.node, o.prop, now)
	case .Vec2:
		was := (^[2]f32)(&m.before)^
		now := (^[2]f32)(p.ptr)^
		for o in m.others {
			v := (^[2]f32)(o.prop.ptr)
			if now.x != was.x do v.x = now.x
			if now.y != was.y do v.y = now.y
		}
	case .Bit_Set:
		if mem.compare_ptrs(&m.before, p.ptr, p.type.size) == 0 do return
		was := p
		was.ptr = &m.before
		for _, i in e.Property_EnumNames(p) {
			on := e.Property_BitSetHas(p, i)
			if on == e.Property_BitSetHas(was, i) do continue
			for o in m.others do e.Property_BitSetSet(o.prop, i, on)
		}
	case .Float, .Int, .Bool, .Color, .Enum:
		if mem.compare_ptrs(&m.before, p.ptr, p.type.size) == 0 do return
		for o in m.others do mem.copy(o.prop.ptr, p.ptr, p.type.size)
	}
}

// node_field: a Node base field as a property (for the Transform section).
node_field :: proc(node: ^e.Node, ptr: rawptr, name: string, kind: e.Property_Kind, T: typeid) -> e.Node_Property {
	return {name = name, kind = kind, ptr = ptr, type = type_info_of(T)}
}

// mixed_push / mixed_pop: a checkbox shows a dash.
mixed_push :: proc(mixed: bool) {
	if mixed do imgui.PushItemFlag(transmute(imgui.ItemFlags)ITEM_FLAG_MIXED_VALUE, true)
}

mixed_pop :: proc(mixed: bool) {
	if mixed do imgui.PopItemFlag()
}

// Inspector_MultiBanner: "3 nodes selected" over the primary's Inspector.
Inspector_MultiBanner :: proc(state: ^EditorState) {
	sel := multi_selection(state)
	if len(sel) < 2 do return
	same := true
	for n in sel do if n.typeId != state.selectedNode.typeId do same = false
	UI_BeginBanner()
	{
		imgui.PushStyleColorImVec4(.Text, UI_ACCENT)
		kind := e.Node_TypeName(state.selectedNode) if same else "mixed types"
		imgui.TextUnformatted(fmt.ctprintf("%s  %d nodes selected (%s)", ICON_FA_CLONE, len(sel), kind))
		imgui.PopStyleColor()
		Drive_Item("insp.multi")
		imgui.PushStyleColorImVec4(.Text, UI_TEXT_DIM)
		imgui.TextWrapped("%s", fmt.ctprintf("Shared properties edit all of them (%s = values differ). Other sections edit %s.", MIXED_TEXT, state.selectedNode.name))
		imgui.PopStyleColor()
	}
	UI_EndBanner({0.361, 0.553, 1.000, 0.10})
}
