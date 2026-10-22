package editor

import "core:fmt"
import "core:strings"
import e "../engine"
import imgui "lib/imgui"
import rl "vendor:raylib"

// ============================================================================
// Inspector help: a property's tooltip (its doc, type, range, default and how
// scripts reach it) and the help pane at the bottom of the Inspector, which
// shows the last hovered property, else what the selected node type is for.
// Docs live in engine/property_docs.odin.
// ============================================================================

INSPECTOR_HELP_HEIGHT :: 96

Inspector_Help :: struct {
	key:   string, // "<node ptr>/<property>" of the shown property
	title: string,
	doc:   string,
	meta:  string,
}

inspectorHelp: Inspector_Help

// prop_help: tooltip and help pane for a property row whose label or field
// is hovered.
prop_help :: proc(state: ^EditorState, node: ^e.Node, p: e.Node_Property, hovered, tip: bool) {
	if !hovered do return
	doc := e.Property_Doc(p)
	meta := prop_meta(node, p)
	key := fmt.tprintf("%p/%s", node, p.name)
	if key != inspectorHelp.key {
		inspector_help_set(key, pretty_name(p.name), doc, meta)
	}
	if tip && imgui.BeginTooltip() {
		imgui.PushTextWrapPos(imgui.GetFontSize() * 22)
		imgui.PushFont(GlobalFonts.semibold)
		imgui.TextUnformatted(strings.clone_to_cstring(pretty_name(p.name), context.temp_allocator))
		imgui.PopFont()
		if doc != "" do imgui.TextWrapped("%s", strings.clone_to_cstring(doc, context.temp_allocator))
		imgui.PushStyleColorImVec4(.Text, UI_TEXT_DIM)
		imgui.TextWrapped("%s", strings.clone_to_cstring(meta, context.temp_allocator))
		imgui.PopStyleColor()
		imgui.PopTextWrapPos()
		imgui.EndTooltip()
	}
}

@(private = "file")
inspector_help_set :: proc(key, title, doc, meta: string) {
	delete(inspectorHelp.key)
	delete(inspectorHelp.title)
	delete(inspectorHelp.doc)
	delete(inspectorHelp.meta)
	inspectorHelp = {strings.clone(key), strings.clone(title), strings.clone(doc), strings.clone(meta)}
}

// prop_meta: "number · 0 to 8 · default 1 · Lua \"energy\"" (get/set_property).
prop_meta :: proc(node: ^e.Node, p: e.Node_Property) -> string {
	parts := make([dynamic]string, context.temp_allocator)
	switch p.kind {
	case .Float: append(&parts, "number")
	case .Int: append(&parts, "integer")
	case .Bool: append(&parts, "on / off")
	case .Vec2: append(&parts, "x, y")
	case .Color: append(&parts, "colour")
	case .String: append(&parts, "text")
	case .Enum: append(&parts, strings.join(e.Property_EnumNames(p), " / ", context.temp_allocator))
	case .Bit_Set: append(&parts, "any of: " if p.type.id != typeid_of(e.CollisionLayerSet) else "collision layers")
	}
	if p.kind == .Bit_Set && p.type.id != typeid_of(e.CollisionLayerSet) {
		parts[0] = strings.concatenate({parts[0], strings.join(e.Property_EnumNames(p), ", ", context.temp_allocator)}, context.temp_allocator)
	}
	if p.has_range && (p.kind == .Float || p.kind == .Int || p.kind == .Vec2) {
		append(&parts, fmt.tprintf("%v to %v", p.min, p.max))
	}
	if node != nil {
		if d, ok := prop_default(node, p); ok do append(&parts, fmt.tprintf("default %s", prop_value_text(d)))
	}
	if p.runtime do append(&parts, "runtime state (not saved)")
	else if node != nil && p.owner != "PhysicsShape" do append(&parts, fmt.tprintf("Lua \"%s\"", p.name))
	return strings.join(parts[:], "  ·  ", context.temp_allocator)
}

@(private = "file")
prop_value_text :: proc(p: e.Node_Property) -> string {
	switch p.kind {
	case .Float: return fmt.tprintf("%v", e.Property_GetFloat(p))
	case .Int: return fmt.tprintf("%v", e.Property_GetInt(p))
	case .Bool: return "on" if (^bool)(p.ptr)^ else "off"
	case .Vec2:
		v := (^[2]f32)(p.ptr)^
		return fmt.tprintf("%v, %v", v.x, v.y)
	case .Color:
		c := (^rl.Color)(p.ptr)^
		return fmt.tprintf("#%02x%02x%02x%02x", c.r, c.g, c.b, c.a)
	case .String:
		s := (^string)(p.ptr)^
		return "empty" if s == "" else fmt.tprintf("\"%s\"", s)
	case .Enum:
		names := e.Property_EnumNames(p)
		i := e.Property_GetEnumIndex(p)
		return names[i] if i >= 0 && i < len(names) else "?"
	case .Bit_Set:
		on := make([dynamic]string, context.temp_allocator)
		for n, i in e.Property_EnumNames(p) do if e.Property_BitSetHas(p, i) do append(&on, n)
		return "none" if len(on) == 0 else strings.join(on[:], ", ", context.temp_allocator)
	}
	return ""
}

// node_type_description: the Add Node catalogue's description of a type.
node_type_description :: proc(typeName: string) -> (name, desc: string) {
	for entry in NODE_CATALOG do if entry.typeName == typeName do return entry.name, entry.description
	return typeName, ""
}

// Inspector_HelpPane: the footer (when View > Inspector Help is on).
Inspector_HelpPane :: proc(state: ^EditorState) {
	imgui.Separator()
	if !imgui.BeginChild("##insphelp", {0, 0}, {}, {}) {
		imgui.EndChild()
		return
	}
	defer imgui.EndChild()
	node := state.selectedNode
	prefix := fmt.tprintf("%p/", node)
	title, doc, meta: string
	if node != nil && strings.has_prefix(inspectorHelp.key, prefix) {
		title, doc, meta = inspectorHelp.title, inspectorHelp.doc, inspectorHelp.meta
	} else if node != nil {
		title, doc = node_type_description(e.Node_TypeName(node))
		meta = "Hover a property for its help."
	} else {
		title = "Inspector"
		doc = "Select a node to edit its properties. Hover any property for what it does."
	}
	imgui.PushTextWrapPos(0)
	imgui.PushFont(GlobalFonts.semibold)
	imgui.TextUnformatted(strings.clone_to_cstring(title, context.temp_allocator))
	imgui.PopFont()
	Drive_Item("insp.help.title")
	if doc != "" do imgui.TextWrapped("%s", strings.clone_to_cstring(doc, context.temp_allocator))
	Drive_Item("insp.help.doc")
	if meta != "" {
		imgui.PushStyleColorImVec4(.Text, UI_TEXT_FAINT)
		imgui.TextWrapped("%s", strings.clone_to_cstring(meta, context.temp_allocator))
		imgui.PopStyleColor()
	}
	imgui.PopTextWrapPos()
}
