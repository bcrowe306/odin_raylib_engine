package editor

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import buf "../odin_editor/buffer"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Rename-safe references. Renaming or moving a node can break what scripts
// say about it: `self.node:get_node("...")` paths (from each script's node),
// `self.node:get_child("Name")` and `Scene.find_node("Name")`, and node-
// reference properties (type = "node"). Before the change NodeRefs_Capture
// records what each of those points at; NodeRefs_AfterChange recomputes
// them: node properties are updated at once, script text edits are offered
// in a prompt (open scripts are edited in place, others on disk).
// ============================================================================

@(private = "file")
Ref_Literal :: struct {
	script: string, // project-relative
	call:   string, // the text before the literal: `self.node:get_node(`
	old:    string,
	owner:  ^e.Node,
	target: ^e.Node,
	byName: bool, // find_node / get_child: the name, not a path
}

@(private = "file")
Ref_Prop :: struct {
	inst:   ^e.ScriptInstance,
	name:   string,
	target: ^e.Node,
}

Ref_Snapshot :: struct {
	lits:  [dynamic]Ref_Literal,
	props: [dynamic]Ref_Prop,
}

Ref_Edit :: struct {
	script, call, old, new: string,
}

@(private = "file")
refs: struct {
	edits: [dynamic]Ref_Edit, // waiting for the prompt (heap)
	open:  bool,
}

@(private = "file")
REF_CALLS :: [?]string{"self.node:get_node(", "self.node:get_child(", "Scene.find_node("}

// script_text: an open document's text, else the file's.
@(private = "file")
script_text :: proc(state: ^EditorState, rel: string) -> string {
	abs := code_abs_path(state, rel)
	for d in GlobalCode.docs do if d.path == abs do return Code_DocText(d)
	data, err := os.read_entire_file(abs, context.temp_allocator)
	return string(data) if err == nil else ""
}

// literals: each string literal passed to `call` in a script.
@(private = "file")
literals :: proc(text, call: string) -> []string {
	out := make([dynamic]string, context.temp_allocator)
	rest := text
	for {
		i := strings.index(rest, call)
		if i < 0 do break
		rest = rest[i + len(call):]
		t := strings.trim_left_space(rest)
		if len(t) < 2 || (t[0] != '"' && t[0] != '\'') do continue
		if j := strings.index_byte(t[1:], t[0]); j > 0 do append(&out, t[1:1 + j])
	}
	return out[:]
}

// NodeRefs_Capture records what scripts and node properties point at now
// (temp-allocated; pass to NodeRefs_AfterChange the same frame).
NodeRefs_Capture :: proc(state: ^EditorState) -> (snap: Ref_Snapshot) {
	snap.lits = make([dynamic]Ref_Literal, context.temp_allocator)
	snap.props = make([dynamic]Ref_Prop, context.temp_allocator)
	if state.activeScene == nil do return
	mgr := state.activeScene.manager
	for owner in mgr.nodes {
		if owner == nil || owner.scriptInstance == nil do continue
		inst := cast(^e.ScriptInstance)owner.scriptInstance
		rel := asset_rel_editor(state, inst.modulePath)
		text := script_text(state, rel)
		for call in REF_CALLS {
			for lit in literals(text, call) {
				target: ^e.Node
				byName := call != "self.node:get_node("
				switch call {
				case "self.node:get_node(":  target = e.Node_ResolvePath(mgr, owner, lit)
				case "self.node:get_child(": for c in e.GetChildrenView(mgr, owner) do if c != nil && c.name == lit {target = c; break}
				case "Scene.find_node(":     target = e.Scene_FindNodeByName(state.activeScene, lit)
				}
				if target != nil do append(&snap.lits, Ref_Literal{rel, call, lit, owner, target, byName})
			}
		}
		// Node-reference properties.
		mod, ok := state.game.scriptManager.modules[e.ScriptVFS_NormalizePath(inst.modulePath)]
		if !ok || mod == nil do continue
		for p in mod.properties {
			if p.assetKind != "node" do continue
			v := inst.properties[p.name] or_else {}
			if v.valString == "" do continue
			if t := e.Node_ResolvePath(mgr, owner, v.valString); t != nil do append(&snap.props, Ref_Prop{inst, p.name, t})
		}
	}
	return
}

// NodeRefs_AfterChange updates node properties and offers the script edits
// that keep pointing at the same nodes.
NodeRefs_AfterChange :: proc(state: ^EditorState, snap: Ref_Snapshot) {
	if state.activeScene == nil do return
	mgr := state.activeScene.manager
	for p in snap.props {
		if !e.Node_IsAlive(p.target) || p.inst.node == nil do continue
		path := e.Node_RelativePath(mgr, p.inst.node, p.target)
		if path != (p.inst.properties[p.name] or_else {}).valString {
			e.ScriptInstance_SetProperty(p.inst, p.name, {type = .String, valString = path}, &state.game.scriptManager)
		}
	}
	edits := make([dynamic]Ref_Edit, context.temp_allocator)
	for l in snap.lits {
		if !e.Node_IsAlive(l.target) || !e.Node_IsAlive(l.owner) do continue
		new := l.target.name if l.byName else e.Node_RelativePath(mgr, l.owner, l.target)
		if l.call == "self.node:get_child(" && e.GetParent(mgr, l.target) != l.owner do continue // not a child any more
		if new == l.old do continue
		dup := false
		for x in edits do if x.script == l.script && x.call == l.call && x.old == l.old do dup = true
		if !dup do append(&edits, Ref_Edit{l.script, l.call, l.old, new})
	}
	if len(edits) == 0 do return
	for x in refs.edits {delete(x.script); delete(x.call); delete(x.old); delete(x.new)}
	clear(&refs.edits)
	for x in edits do append(&refs.edits, Ref_Edit{strings.clone(x.script), strings.clone(x.call), strings.clone(x.old), strings.clone(x.new)})
	refs.open = true
}

// NodeRefs_Pending: script edits waiting for an answer (drives).
NodeRefs_Pending :: proc() -> int {return len(refs.edits)}

// NodeRefs_Render: the "update script references" prompt.
NodeRefs_Render :: proc(state: ^EditorState) {
	if refs.open {
		imgui.OpenPopup("Update Script References###NodeRefs")
		refs.open = false
	}
	center := imgui.GetMainViewport().WorkPos + imgui.GetMainViewport().WorkSize * 0.5
	imgui.SetNextWindowPos(center, .Appearing, {0.5, 0.5})
	if !imgui.BeginPopupModal("Update Script References###NodeRefs", nil, {.AlwaysAutoResize, .NoTitleBar}) do return
	defer imgui.EndPopup()
	imgui.PushFont(GlobalFonts.semibold)
	imgui.TextUnformatted(fmt.ctprintf("%s  Update script references?", ICON_FA_CODE))
	imgui.PopFont()
	UI_DimText("The node moved or was renamed; these still point at the old place:")
	imgui.Dummy({0, 4})
	for x in refs.edits {
		imgui.TextUnformatted(fmt.ctprintf("%s", x.script))
		imgui.SameLine(0, 8)
		UI_DimText(fmt.tprintf("%s\"%s\")  %s  %s\"%s\")", x.call, x.old, ICON_FA_ARROW_RIGHT, x.call, x.new))
	}
	imgui.Dummy({0, 6})
	if UI_PrimaryButton(fmt.tprintf("%s  Update", ICON_FA_CHECK), "refs.update", {120, 30}) { // no Enter: the rename's Enter would answer it
		n := apply_edits(state)
		Editor_Log(state, .Info, "Updated %d script reference(s)", n)
		clear_edits()
		imgui.CloseCurrentPopup()
	}
	imgui.SameLine()
	if UI_Button("Skip", "refs.skip", {90, 30}) || imgui.IsKeyPressed(.Escape) {
		clear_edits()
		imgui.CloseCurrentPopup()
	}
}

@(private = "file")
clear_edits :: proc() {
	for x in refs.edits {delete(x.script); delete(x.call); delete(x.old); delete(x.new)}
	clear(&refs.edits)
}

// apply_edits rewrites `call"old")` to `call"new")` (either quote): in open
// scripts as one undo step, other files on disk.
@(private = "file")
apply_edits :: proc(state: ^EditorState) -> int {
	count := 0
	scripts := make(map[string]bool, allocator = context.temp_allocator)
	for x in refs.edits do scripts[x.script] = true
	for rel in scripts {
		abs := code_abs_path(state, rel)
		var_doc: ^Code_Doc
		for d in GlobalCode.docs do if d.path == abs do var_doc = d
		if var_doc != nil {
			b := &var_doc.buffer
			group := buf.buffer_next_group(b)
			for x in refs.edits {
				if x.script != rel do continue
				for q in ([]string{"\"", "'"}) {
					from := strings.concatenate({x.call, q, x.old, q}, context.temp_allocator)
					to := strings.concatenate({x.call, q, x.new, q}, context.temp_allocator)
					for ln in 0 ..< buf.buffer_line_count(b) {
						for {
							line := buf.buffer_line_str(b, ln)
							i := strings.index(line, from)
							if i < 0 do break
							buf.buffer_delete_range(b, {ln, i}, {ln, i + len(from)}, group)
							buf.buffer_insert_text(b, {ln, i}, to, group)
							count += 1
						}
					}
				}
			}
			continue
		}
		data, err := os.read_entire_file(abs, context.temp_allocator)
		if err != nil do continue
		text := string(data)
		for x in refs.edits {
			if x.script != rel do continue
			for q in ([]string{"\"", "'"}) {
				from := strings.concatenate({x.call, q, x.old, q}, context.temp_allocator)
				to := strings.concatenate({x.call, q, x.new, q}, context.temp_allocator)
				n := strings.count(text, from)
				if n > 0 {
					text, _ = strings.replace_all(text, from, to, context.temp_allocator)
					count += n
				}
			}
		}
		_ = os.write_entire_file(abs, transmute([]u8)text)
	}
	_ = filepath.base
	Lua_MarkProjectTypesDirty()
	return count
}
