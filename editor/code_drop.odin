package editor

import "core:fmt"
import "core:path/filepath"
import "core:strings"
import buf "../odin_editor/buffer"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Dragging assets and nodes into a script.
//
// Drop an asset from the Assets panel onto the code: inserts its path as a
// string ("textures/ship.png"). Hold Cmd/Ctrl while dropping to declare it
// as an exported asset property instead:
//
//   ship = { type = "texture", default = "textures/ship.png" },
//
// which the Inspector edits with an asset picker. Dropping a node from the
// scene tree inserts `self.node:get_node("<relative path>")` (relative to a
// node that uses this script), or `Scene.find_node("Name")`.
// ============================================================================

// Script_AssetKind: the script property type for an asset path.
Script_AssetKind :: proc(rel: string) -> string {
	switch Asset_KindOf(rel) {
	case .Texture:   return "texture"
	case .Audio:     return "audio"
	case .Scene:     return "scene"
	case .Script:    return "script"
	case .Component: return "component"
	case .Level:     return "level"
	case .Shader:    return "file"
	case .Package, .Other:
	}
	if strings.has_suffix(strings.to_lower(rel, context.temp_allocator), ".ldtk") do return "level"
	return "file"
}

// Script_AssetFiles lists project files matching an asset property type.
Script_AssetFiles :: proc(state: ^EditorState, kind: string) -> []string {
	switch kind {
	case "texture":   return Editor_ListProjectFiles(state, "", TEXTURE_EXTS)
	case "audio":     return Editor_ListProjectFiles(state, "", AUDIO_EXTS)
	case "scene":     return Editor_ListProjectFiles(state, "", {".scene.json"})
	case "script":    return Editor_ListProjectFiles(state, "", {".lua"})
	case "component": return Editor_ListProjectFiles(state, "", {".component.json"})
	case "level":     return Editor_ListProjectFiles(state, "", {".ldtk"})
	}
	return Editor_ListProjectFiles(state, "", {".png", ".jpg", ".wav", ".ogg", ".mp3", ".json", ".lua", ".ldtk"})
}

// Script_PropAssetKind: the asset kind of a script property ("" if plain).
Script_PropAssetKind :: proc(state: ^EditorState, inst: ^e.ScriptInstance, name: string) -> string {
	sm := &state.game.scriptManager
	mod, ok := sm.modules[e.ScriptVFS_NormalizePath(inst.modulePath)]
	if !ok || mod == nil do return ""
	for p in mod.properties do if p.name == name do return p.assetKind
	return ""
}

@(private = "file")
snake_ident :: proc(s: string) -> string {
	sb := strings.builder_make(context.temp_allocator)
	prevLower := false
	for ch in s {
		switch {
		case ch >= 'A' && ch <= 'Z':
			if prevLower do strings.write_byte(&sb, '_')
			strings.write_rune(&sb, ch + 32)
			prevLower = false
		case (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9'):
			if strings.builder_len(sb) == 0 && ch >= '0' && ch <= '9' do strings.write_byte(&sb, '_')
			strings.write_rune(&sb, ch)
			prevLower = true
		case:
			if strings.builder_len(sb) > 0 do strings.write_byte(&sb, '_')
			prevLower = false
		}
	}
	return strings.trim_right(strings.to_string(sb), "_")
}

// Code_DropAsset inserts an asset reference at `pos` (or, as a property,
// into the script's properties table).
Code_DropAsset :: proc(doc: ^Code_Doc, rel: string, pos: buf.Position, asProperty: bool) {
	b := &doc.buffer
	group := buf.buffer_next_group(b)
	if !asProperty {
		text := fmt.tprintf("%q", rel)
		// Already inside a string: just the path.
		line := buf.buffer_line_str(b, pos.line)
		if pos.col > 0 && pos.col < len(line) && (line[pos.col - 1] == '"' || line[pos.col - 1] == '\'') do text = rel
		end := buf.buffer_insert_text(b, pos, text, group)
		code_set_single_cursor(b, end, false)
		doc.scrollToCursor = true
		return
	}
	kind := Script_AssetKind(rel)
	text := buf.buffer_to_string(b, context.temp_allocator)
	cls := Script_ClassName(text)
	base := snake_ident(filepath.stem(filepath.stem(rel)))
	if base == "" do base = kind
	name := base
	for i := 2; strings.contains(text, fmt.tprintf("    %s = {{", name)) || strings.contains(text, fmt.tprintf("\t%s = {{", name)); i += 1 {
		name = fmt.tprintf("%s_%d", base, i)
	}
	indent := "\t" if doc.useTabs else "    "
	entry := fmt.tprintf("%s%s = {{ type = %q, default = %q }},\n", indent, name, kind, rel)
	// After `Cls.properties = {`.
	header := fmt.tprintf("%s.properties = {{", cls) if cls != "" else ".properties = {"
	for ln in 0 ..< buf.buffer_line_count(b) {
		l := strings.trim_space(buf.buffer_line_str(b, ln))
		if cls != "" && strings.has_prefix(l, header) || cls == "" && strings.contains(l, header) {
			end := buf.buffer_insert_text(b, {ln + 1, 0}, entry, group)
			code_set_single_cursor(b, {ln + 1, len(indent)}, false)
			b.cursors[0].sel = {anchor = {ln + 1, len(indent)}, active = true}
			b.cursors[0].pos = {ln + 1, len(indent) + len(name)}
			_ = end
			doc.scrollToCursor = true
			return
		}
	}
	// No properties table yet: create one after `local Cls = {}`.
	if cls == "" do return
	for ln in 0 ..< buf.buffer_line_count(b) {
		if strings.trim_space(buf.buffer_line_str(b, ln)) == fmt.tprintf("local %s = {{}}", cls) {
			block := fmt.tprintf("\n%s.properties = {{\n%s}}\n", cls, entry)
			buf.buffer_insert_text(b, {ln + 1, 0}, block, group)
			code_set_single_cursor(b, {ln + 3, len(indent)}, false)
			doc.scrollToCursor = true
			return
		}
	}
}

// Code_DropNode inserts a reference to a scene node.
Code_DropNode :: proc(state: ^EditorState, doc: ^Code_Doc, node: ^e.Node, pos: buf.Position) {
	if state.activeScene == nil || node == nil do return
	mgr := state.activeScene.manager
	// A node that runs this script: the selection if it does, else any.
	owner: ^e.Node
	usesScript :: proc(state: ^EditorState, n: ^e.Node, doc: ^Code_Doc) -> bool {
		if n == nil || n.scriptInstance == nil do return false
		rel := asset_rel_editor(state, (cast(^e.ScriptInstance)n.scriptInstance).modulePath)
		return strings.has_suffix(doc.path, rel)
	}
	if usesScript(state, state.selectedNode, doc) do owner = state.selectedNode
	if owner == nil {
		for n in mgr.nodes do if usesScript(state, n, doc) {owner = n; break}
	}
	text: string
	if owner != nil {
		text = fmt.tprintf("self.node:get_node(%q)", e.Node_RelativePath(mgr, owner, node))
	} else {
		text = fmt.tprintf("Scene.find_node(%q)", node.name)
	}
	b := &doc.buffer
	end := buf.buffer_insert_text(b, pos, text, buf.buffer_next_group(b))
	code_set_single_cursor(b, end, false)
	doc.scrollToCursor = true
}

// code_drop_target makes the text area accept assets and nodes; call right
// after the text area's input item.
code_drop_target :: proc(state: ^EditorState, doc: ^Code_Doc, mouse: [2]f32) {
	if !imgui.BeginDragDropTarget() do return
	defer imgui.EndDragDropTarget()
	cm := &GlobalCode
	b := &doc.buffer
	pos := code_pos_at(b, mouse)
	preview :: proc(b: ^buf.Buffer, pos: buf.Position) {
		cm := &GlobalCode
		p := code_screen_pos(b, pos)
		dl := imgui.GetForegroundDrawList()
		imgui.DrawList_AddRectFilled(dl, {p.x - 1, p.y}, {p.x + 2, p.y + cm.lineH}, col_u32(UI_WARNING))
	}
	if payload := imgui.AcceptDragDropPayload(ASSET_PAYLOAD, {.AcceptBeforeDelivery, .AcceptNoDrawDefaultRect}); payload != nil {
		preview(b, pos)
		io := imgui.GetIO()
		asProp := io.KeyCtrl || io.KeySuper
		if asProp do imgui.SetTooltip("Add as an exported property")
		if payload.Delivery {
			p := (^Asset_Payload)(payload.Data)
			rel := strings.clone(string(p.path[:p.len]), context.temp_allocator)
			Code_DropAsset(doc, rel, pos, asProp)
			cm.focusRequest = true
		}
	}
	if payload := imgui.AcceptDragDropPayload("ORE_NODE", {.AcceptBeforeDelivery, .AcceptNoDrawDefaultRect}); payload != nil {
		preview(b, pos)
		if payload.Delivery {
			n := (^^e.Node)(payload.Data)^
			if e.Node_IsAlive(n) do Code_DropNode(state, doc, n, pos)
			cm.focusRequest = true
		}
	}
}
